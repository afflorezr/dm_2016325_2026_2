# Mineria de Datos (2016325) - Taller 2
# Paso 14. Reglas previas a la insercion y auditoria historica.
# Este modulo NO modifica SQLite y NO consulta sitios web.

# Convierte textos de precios colombianos a numeros (COP).
# Ejemplos: "$ 12.500" -> 12500; "12.500,50" -> 12500.5.
parsear_precio_cop <- function(x) {
  if (is.numeric(x)) return(as.numeric(x))
  vapply(as.character(x), function(elemento) {
    if (is.na(elemento) || !nzchar(trimws(elemento))) return(NA_real_)
    s <- gsub("[^0-9,.\\-]", "", trimws(elemento))
    if (!nzchar(s) || s %in% c("-", ".", ",")) return(NA_real_)

    puntos <- gregexpr(".", s, fixed = TRUE)[[1]]
    comas <- gregexpr(",", s, fixed = TRUE)[[1]]
    ultimo_punto <- if (puntos[1] < 0L) -1L else max(puntos)
    ultima_coma <- if (comas[1] < 0L) -1L else max(comas)

    if (ultimo_punto > 0L && ultima_coma > 0L) {
      # El ultimo separador se interpreta como decimal.
      if (ultimo_punto > ultima_coma) {
        s <- gsub(",", "", s, fixed = TRUE)
      } else {
        s <- gsub(".", "", s, fixed = TRUE)
        s <- sub(",", ".", s, fixed = TRUE)
      }
    } else if (ultimo_punto > 0L) {
      if (grepl("^-?[0-9]{1,3}(\\.[0-9]{3})+$", s)) {
        s <- gsub(".", "", s, fixed = TRUE)
      }
    } else if (ultima_coma > 0L) {
      if (grepl("^-?[0-9]{1,3}(,[0-9]{3})+$", s)) {
        s <- gsub(",", "", s, fixed = TRUE)
      } else {
        s <- sub(",", ".", s, fixed = TRUE)
      }
    }
    suppressWarnings(as.numeric(s))
  }, numeric(1), USE.NAMES = FALSE)
}

validar_lote <- function(datos,
                        comercios_esperados = c(
                          "Cruz Verde", "Droguerías Cafam", "La Rebaja"
                        )) {
  if (!is.data.frame(datos)) stop("datos debe ser un data.frame")
  requeridas <- c(
    "ejecucion_id", "comercio", "producto_comercio_id",
    "fecha_hora_consulta", "precio_cop", "url", "comparable",
    "incluido_categoria", "producto_comun_id",
    "contenido_valor_estandar", "unidad_estandar"
  )
  faltantes <- setdiff(requeridas, names(datos))
  if (length(faltantes)) {
    stop("Columnas faltantes: ", paste(faltantes, collapse = ", "))
  }

  texto <- function(x) {
    y <- trimws(as.character(x))
    y[is.na(y)] <- ""
    y
  }
  n <- nrow(datos)
  errores <- rep("", n)
  agregar <- function(condicion, mensaje) {
    condicion[is.na(condicion)] <- TRUE
    if (any(condicion)) {
      previos <- errores[condicion]
      errores[condicion] <<- ifelse(
        nzchar(previos), paste0(previos, "; ", mensaje), mensaje
      )
    }
  }

  comercio <- texto(datos$comercio)
  producto <- texto(datos$producto_comercio_id)
  ejecucion <- texto(datos$ejecucion_id)
  fecha <- texto(datos$fecha_hora_consulta)
  url <- texto(datos$url)
  codigo_comun <- texto(datos$producto_comun_id)
  precio <- parsear_precio_cop(datos$precio_cop)
  comparable <- suppressWarnings(as.integer(datos$comparable))
  categoria <- suppressWarnings(as.integer(datos$incluido_categoria))
  contenido <- suppressWarnings(as.numeric(as.character(datos$contenido_valor_estandar)))
  unidad <- tolower(texto(datos$unidad_estandar))

  agregar(!nzchar(comercio), "comercio ausente")
  agregar(!nzchar(producto), "identificador de producto ausente")
  agregar(!nzchar(ejecucion), "identificador de ejecucion ausente")
  agregar(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}", fecha),
          "fecha de consulta ausente o sin formato ISO")
  agregar(!grepl("^https?://[^[:space:]]+", url, ignore.case = TRUE),
          "URL ausente o invalida")
  agregar(!is.finite(precio) | precio <= 0,
          "precio no numerico, nulo o menor o igual a cero")

  clave <- paste(comercio, producto, fecha, sep = "||")
  agregar(duplicated(clave), "observacion duplicada en el lote")

  es_comparable <- !is.na(comparable) & comparable == 1L
  agregar(es_comparable & !nzchar(codigo_comun),
          "comparable sin producto comun")
  agregar(es_comparable & !(categoria %in% 1L),
          "comparable fuera de categoria")
  agregar(es_comparable & (!is.finite(contenido) | contenido <= 0),
          "comparable sin contenido total valido")
  agregar(es_comparable & !(unidad %in% c("g", "ml", "unidad")),
          "comparable sin unidad normalizada")

  salida <- datos
  salida$precio_cop_validado <- precio
  salida$motivo_rechazo <- ifelse(nzchar(errores), errores, NA_character_)
  salida$estado_validacion_propuesto <- ifelse(
    nzchar(errores), "rechazada", "valida"
  )

  todas_tiendas <- unique(c(comercios_esperados, comercio[nzchar(comercio)]))
  cobertura <- do.call(rbind, lapply(todas_tiendas, function(tienda) {
    filas <- comercio == tienda & es_comparable & categoria == 1L &
      !nzchar(errores) & nzchar(codigo_comun)
    cantidad <- length(unique(codigo_comun[filas]))
    data.frame(
      comercio = tienda,
      productos_comparables_validos = cantidad,
      cumple_ocho = cantidad == 8L,
      stringsAsFactors = FALSE
    )
  }))

  resumen <- data.frame(
    total = nrow(salida),
    validas = sum(salida$estado_validacion_propuesto == "valida"),
    rechazadas = sum(salida$estado_validacion_propuesto == "rechazada")
  )

  list(
    datos = salida,
    validas = salida[salida$estado_validacion_propuesto == "valida", , drop = FALSE],
    rechazadas = salida[salida$estado_validacion_propuesto == "rechazada", , drop = FALSE],
    resumen = resumen,
    cobertura = cobertura,
    cobertura_completa = all(cobertura$cumple_ocho)
  )
}

# Audita las observaciones historicas sin actualizarlas.
# No confundir la propuesta de validacion con el estado ya guardado en SQLite.
auditar_historico <- function(db_path = "comparador_precios.sqlite") {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Instala los paquetes DBI y RSQLite")
  }
  if (!file.exists(db_path)) stop("No se encontro la base: ", db_path)
  con <- DBI::dbConnect(
    RSQLite::SQLite(), dbname = db_path, flags = RSQLite::SQLITE_RO
  )
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  datos <- DBI::dbGetQuery(con, "
    SELECT o.observacion_id, o.ejecucion_id, c.nombre AS comercio,
           o.producto_comercio_id, o.fecha_hora_consulta, o.precio_cop,
           a.url, a.comparable, a.incluido_categoria,
           a.producto_comun_id, a.contenido_valor_estandar,
           a.unidad_estandar, o.estado_validacion AS estado_guardado
    FROM observaciones o
    INNER JOIN anuncios a
      ON o.ejecucion_id = a.ejecucion_id
     AND o.comercio_id = a.comercio_id
     AND o.producto_comercio_id = a.producto_comercio_id
    INNER JOIN comercios c ON c.comercio_id = o.comercio_id
  ")

  resultado <- validar_lote(datos)
  cat("\n=== AUDITORIA HISTORICA (SOLO LECTURA) ===\n")
  print(resultado$resumen)
  cat("\nCobertura de productos comparables:\n")
  print(resultado$cobertura, row.names = FALSE)
  cat("\nEstados ya almacenados en SQLite:\n")
  print(as.data.frame(table(datos$estado_guardado)))
  cat("\nMotivos encontrados en la nueva validacion:\n")
  print(as.data.frame(table(
    resultado$rechazadas$motivo_rechazo, useNA = "ifany"
  )))
  invisible(resultado)
}
