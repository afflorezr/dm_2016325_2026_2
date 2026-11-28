if (!file.exists("scraper.R") || !file.exists("validacion.R")) {
  stop("Deben existir scraper.R y validacion.R en la carpeta actual")
}
source("scraper.R")
source("validacion.R")

disponibilidad_vtex_t2 <- function(datos) {
  if (!nrow(datos)) return(datos)
  datos$disponibilidad <- NA_character_
  for (ruta in unique(datos$origen_raw)) {
    if (is.na(ruta) || !file.exists(ruta)) next
    productos <- tryCatch(productos_vtex(leer_gzip(ruta)), error = function(e) NULL)
    if (is.null(productos)) next
    estados <- list()
    for (producto in productos) {
      for (articulo in producto$items) {
        sku <- texto1(articulo$itemId)
        if (is.na(sku)) next
        vendedores <- articulo$sellers %o% list()
        if (!length(vendedores) || !is.list(vendedores[[1]])) next
        oferta <- vendedores[[1]]$commertialOffer
        if (!is.list(oferta)) next
        cantidad <- numero1(oferta$AvailableQuantity)
        if (is.finite(cantidad)) {
          estados[[sku]] <- if (cantidad > 0) "disponible" else "agotado"
        }
      }
    }
    indices <- which(datos$origen_raw == ruta)
    for (i in indices) {
      estado <- estados[[as.character(datos$sku[[i]])]]
      if (!is.null(estado)) datos$disponibilidad[[i]] <- estado
    }
  }
  datos
}

guardar_lote_seguro_t2 <- function(con, ejecucion, comercio, resultado, validacion, inicio) {
  validas <- validacion$validas
  rechazadas <- validacion$rechazadas
  cov <- resultado$cobertura
  campos_observaciones <- c(columnas, "contenido_total", "unidad_normalizada", "disponibilidad")
  sql_observacion <- paste0(
    "INSERT OR IGNORE INTO observaciones (",
    paste(campos_observaciones, collapse = ","),
    ") VALUES (", paste(rep("?", length(campos_observaciones)), collapse = ","), ")"
  )

  insertadas <- 0L
  nuevas <- 0L
  cambios <- 0L
  sin_precio_previo <- 0L

  DBI::dbWithTransaction(con, {
    for (i in seq_len(nrow(rechazadas))) {
      f <- rechazadas[i, , drop = FALSE]
      registro <- jsonlite::toJSON(as.list(f[1, setdiff(names(f), "motivo_rechazo"), drop = FALSE]),
                                    auto_unbox = TRUE, na = "null")
      DBI::dbExecute(con, paste0(
        "INSERT INTO observaciones_rechazadas ",
        "(fecha_rechazo,id_ejecucion,comercio,sku,precio_texto,url,origen_raw,motivo,registro_original) ",
        "VALUES (?,?,?,?,?,?,?,?,?)"
      ), params = list(fecha_colombia(), ejecucion, comercio, as.character(f$sku[[1]]),
                       as.character(f$precio[[1]]), as.character(f$url[[1]]),
                       as.character(f$origen_raw[[1]]), as.character(f$motivo_rechazo[[1]]),
                       as.character(registro)))
    }

    for (i in seq_len(nrow(validas))) {
      f <- validas[i, , drop = FALSE]
      anterior <- DBI::dbGetQuery(con,
        paste0("SELECT precio FROM observaciones ",
               "WHERE comercio=? AND sku=? AND id_ejecucion<>? ",
               "ORDER BY fecha_consulta DESC,id DESC LIMIT 1"),
        params = list(comercio, as.character(f$sku[[1]]), ejecucion))

      fila <- unname(as.list(f[1, campos_observaciones, drop = FALSE]))
      n <- DBI::dbExecute(con, sql_observacion, params = fila)
      if (n != 1L) next
      insertadas <- insertadas + 1L
      if (!nrow(anterior)) {
        nuevas <- nuevas + 1L
      } else if (!is.na(anterior$precio[[1]]) &&
                 !isTRUE(all.equal(as.numeric(f$precio[[1]]), as.numeric(anterior$precio[[1]])))) {
        cambios <- cambios + 1L
      } else if (is.na(anterior$precio[[1]])) {
        sin_precio_previo <- sin_precio_previo + 1L
      }

      DBI::dbExecute(con, paste0(
        "INSERT INTO productos ",
        "(comercio,sku,nombre,marca,subcategoria,url,id_comun,comparable,",
        "contenido_total,unidad_normalizada,ultima_fecha_consulta) ",
        "VALUES (?,?,?,?,?,?,?,?,?,?,?) ",
        "ON CONFLICT(comercio,sku) DO UPDATE SET ",
        "nombre=excluded.nombre,marca=excluded.marca,",
        "subcategoria=excluded.subcategoria,url=excluded.url,",
        "id_comun=excluded.id_comun,comparable=excluded.comparable,",
        "contenido_total=excluded.contenido_total,",
        "unidad_normalizada=excluded.unidad_normalizada,",
        "ultima_fecha_consulta=excluded.ultima_fecha_consulta"
      ), params = list(comercio, as.character(f$sku[[1]]), as.character(f$producto_original[[1]]),
                       as.character(f$marca[[1]]), as.character(f$subcategoria[[1]]),
                       as.character(f$url[[1]]), as.character(f$id_comun[[1]]),
                       as.integer(f$comparable[[1]]), as.numeric(f$contenido_total[[1]]),
                       as.character(f$unidad_normalizada[[1]]),
                       as.character(f$fecha_consulta[[1]])))
    }

    if (nrow(cov)) {
      for (i in seq_len(nrow(cov))) {
        DBI::dbExecute(con, paste0(
          "INSERT INTO cobertura ",
          "(id_ejecucion,comercio,seccion,esperados,capturados,paginas,estado,detalle) ",
          "VALUES (?,?,?,?,?,?,?,?) ",
          "ON CONFLICT(id_ejecucion,comercio,seccion) DO UPDATE SET ",
          "esperados=excluded.esperados,capturados=excluded.capturados,",
          "paginas=excluded.paginas,estado=excluded.estado,detalle=excluded.detalle"
        ), params = list(ejecucion, comercio, as.character(cov$seccion[[i]]),
                         as.integer(cov$esperados[[i]]), as.integer(cov$capturados[[i]]),
                         as.integer(cov$paginas[[i]]), as.character(cov$estado[[i]]),
                         as.character(cov$detalle[[i]])))
      }
    }

    todas_rutas <- nrow(cov) > 0L && all(cov$estado == "ruta_recorrida")
    estado <- if (insertadas == 0L) "fallida" else if (
      !isTRUE(validacion$completos) || !todas_rutas || nrow(rechazadas) > 0L
    ) "parcial" else "pendiente_verificar_cobertura"
    detalle <- paste0(
      "Comparables presentes: ", 8L - length(validacion$faltantes_comparables), "/8; ",
      "rechazadas=", nrow(rechazadas), "; ",
      "rutas=", paste(paste(cov$seccion, cov$estado, sep = ":"), collapse = ","), ". ",
      "Recorrer la ruta NO certifica por si solo cobertura total."
    )
    DBI::dbExecute(con, paste0(
      "INSERT INTO ejecuciones (id_ejecucion,comercio,inicio,registros,estado,detalle) ",
      "VALUES (?,?,?,?,?,?)"
    ), params = list(ejecucion, comercio, inicio, as.integer(insertadas), estado, detalle))
  })

  data.frame(comercio = comercio, recolectadas = nrow(resultado$datos),
             insertadas = insertadas, nuevos_sku = nuevas,
             cambios_precio = cambios, rechazadas = nrow(rechazadas),
             comparables_validos = 8L - length(validacion$faltantes_comparables),
             no_observados = NA_integer_,
             estado = if (insertadas == 0L) "fallida" else if (
               !isTRUE(validacion$completos) ||
                 !nrow(cov) || !all(cov$estado == "ruta_recorrida") ||
                 nrow(rechazadas) > 0L
             ) "parcial" else "pendiente_verificar_cobertura",
             stringsAsFactors = FALSE)
}

actualizar_precios_t2 <- function(db = "comparador_precios_taller2.sqlite") {
  if (!file.exists(db)) stop("No existe la base del Taller 2: ", db)
  if (!file.exists("config/equivalencias_revisar.csv")) {
    stop("Falta config/equivalencias_revisar.csv")
  }
  mapa <- mapa_comparables_t2()
  dir.create("respaldos", recursive = TRUE, showWarnings = FALSE)
  ejecucion <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "America/Bogota")
  respaldo <- file.path("respaldos", paste0("taller2_antes_captura_", ejecucion, ".sqlite"))
  if (!file.copy(db, respaldo, overwrite = FALSE)) stop("No se pudo respaldar la base: captura cancelada")

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]] != "ok") {
    stop("La base de trabajo no supera integridad SQLite")
  }
  if (nrow(DBI::dbGetQuery(con, "SELECT id_ejecucion FROM ejecuciones WHERE id_ejecucion=? LIMIT 1",
                           params = list(ejecucion)))) {
    stop("Ya existe una captura con este identificador. Ejecuta mas tarde.")
  }
  DBI::dbExecute(con, paste0(
    "CREATE TABLE IF NOT EXISTS estados_no_observados (",
    "id_ejecucion TEXT NOT NULL,comercio TEXT NOT NULL,sku TEXT NOT NULL,",
    "fecha_deteccion TEXT NOT NULL,estado TEXT NOT NULL DEFAULT 'no_observado' ",
    "CHECK(estado='no_observado'),motivo TEXT NOT NULL,",
    "PRIMARY KEY (id_ejecucion,comercio,sku))"
  ))
  cat("\nEjecucion real:", ejecucion, "\n")
  cat("Respaldo previo:", respaldo, "\n")
  salidas <- list()
  comercios <- c("Cafam", "Locatel", "Cruz Verde")
  for (comercio in comercios) {
    cat("\nConsultando", comercio, "...\n")
    inicio <- fecha_colombia()
    resultado <- tryCatch({
      if (comercio == "Cruz Verde") extraer_tienda_cruzverde(ejecucion)
      else extraer_tienda_vtex(comercio, ejecucion)
    }, error = function(e) {
      list(datos = fila_vacia(), cobertura = resultado_cobertura(
        comercio, "error", NA_integer_, 0L, 0L, "fallida", conditionMessage(e)))
    })
    if (comercio != "Cruz Verde") {
      resultado$datos <- disponibilidad_vtex_t2(resultado$datos)
    }
    validacion <- tryCatch(
      validar_lote_t2(resultado$datos, comercio, ejecucion, mapa),
      error = function(e) e
    )
    if (inherits(validacion, "error")) {
      mensaje <- paste("Falló la validación del lote:", conditionMessage(validacion))
      cat(mensaje, "\n")
      resultado <- list(datos = fila_vacia(), cobertura = resultado_cobertura(
        comercio, "validacion", NA_integer_, 0L, 0L, "fallida", mensaje))
      validacion <- validar_lote_t2(resultado$datos, comercio, ejecucion, mapa)
    }
    informe <- tryCatch(
      guardar_lote_seguro_t2(con, ejecucion, comercio, resultado, validacion, inicio),
      error = function(e) {
        mensaje <- conditionMessage(e)
        cat("ERROR en la transacción de", comercio, ":", mensaje, "\n")
        tryCatch(DBI::dbExecute(con,
          "INSERT INTO ejecuciones (id_ejecucion,comercio,inicio,registros,estado,detalle) VALUES (?,?,?,?,?,?)",
          params = list(ejecucion, comercio, inicio, 0L, "fallida", mensaje)),
          error = function(e2) message("No se pudo registrar el fallo: ", conditionMessage(e2)))
        data.frame(comercio = comercio, recolectadas = nrow(resultado$datos),
                   insertadas = 0L, nuevos_sku = 0L, cambios_precio = 0L,
                   rechazadas = NA_integer_, comparables_validos = 0L,
                   no_observados = NA_integer_, estado = "fallida",
                   stringsAsFactors = FALSE)
      }
    )
    salidas[[comercio]] <- informe
    print(informe, row.names = FALSE)
  }
  print(DBI::dbGetQuery(con, "PRAGMA integrity_check"))
  cat("\nNOTA: NA en no_observados significa cobertura aun no certificada; ",
      "no implica que el producto este agotado.\n", sep = "")
  cat("La base original comparador_precios.sqlite NO se modifico.\n")
  invisible(list(id_ejecucion = ejecucion,
                 resumen = do.call(rbind, salidas), respaldo = respaldo))
}

reprocesar_raw_t2 <- function(ejecucion, comercio) {
  if (!grepl("^[0-9]{8}_[0-9]{6}$", ejecucion)) stop("Identificador de ejecucion no valido")
  if (!comercio %in% c("Cafam", "Locatel", "Cruz Verde")) stop("Comercio desconocido")
  mapa <- mapa_comparables_t2()
  resultado <- if (comercio == "Cruz Verde") {
    extraer_tienda_cruzverde(ejecucion, offline = TRUE)
  } else {
    extraer_tienda_vtex(comercio, ejecucion, offline = TRUE)
  }
  if (comercio != "Cruz Verde") resultado$datos <- disponibilidad_vtex_t2(resultado$datos)
  validacion <- validar_lote_t2(resultado$datos, comercio, ejecucion, mapa)
  list(cobertura = resultado$cobertura, validas = nrow(validacion$validas),
       rechazadas = nrow(validacion$rechazadas),
       faltantes_comparables = validacion$faltantes_comparables)
}
