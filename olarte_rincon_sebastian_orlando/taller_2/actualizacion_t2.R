# Universidad Nacional de Colombia - Mineria de Datos 2016325
# Taller 2 - Actualizacion controlada con validacion ANTES de insertar.
# Reutiliza scraper.R y validacion.R. No modifica el Taller 1.
# Al hacer source() no se ejecuta ningun scraping ni se escribe en SQLite.

verificar_preparacion_t2 <- function(db_path = "comparador_precios.sqlite",
                                    raw_root = "raw") {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Faltan DBI o RSQLite")
  }
  if (!file.exists(db_path)) stop("No existe la base: ", db_path)
  if (!dir.exists(raw_root)) stop("No existe la carpeta RAW: ", raw_root)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path,
                       flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  estructura <- c("comercios", "ejecuciones", "anuncios", "observaciones",
                   "productos_comunes", "correcciones", "observaciones_rechazadas")
  faltantes <- setdiff(estructura, DBI::dbListTables(con))
  if (length(faltantes)) stop("Faltan tablas: ", paste(faltantes, collapse = ", "))

  columnas <- c("estado_validacion", "estado_disponibilidad", "evidencia_raw")
  if (!all(columnas %in% DBI::dbListFields(con, "observaciones"))) {
    stop("Faltan columnas agregadas en el paso 11")
  }

  vistas <- DBI::dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'view'")$name
  requeridas <- c("v_ultimo_precio", "v_cambios_precio", "v_comparables")
  if (!all(requeridas %in% vistas)) stop("Faltan las vistas del paso 13")

  integridad <- DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]]
  errores_fk <- nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check"))
  if (!identical(integridad, "ok") || errores_fk != 0L) {
    stop("Integridad de SQLite no superada")
  }

  tabla <- DBI::dbGetQuery(con, "
    SELECT (SELECT COUNT(*) FROM observaciones) AS observaciones,
           (SELECT COUNT(*) FROM v_comparables) AS comparables,
           (SELECT COUNT(*) FROM v_cambios_precio) AS cambios_precio
  ")
  cat("\n=== PREPARACION PARA ACTUALIZACION ===\n")
  print(tabla)
  cat("Integridad:", integridad, "| Errores FK:", errores_fk, "\n")
  cat("Estado: preparado, SIN consultar internet ni escribir en SQLite.\n")
  invisible(tabla)
}

# Tabla propia de eventos: conserva mensajes de fallos de red, parseo o insercion.
crear_bitacora_t2 <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS errores_actualizacion (
      error_id INTEGER PRIMARY KEY AUTOINCREMENT,
      fecha_error TEXT NOT NULL,
      ejecucion_id TEXT NOT NULL,
      comercio_id INTEGER NOT NULL,
      etapa TEXT NOT NULL,
      mensaje TEXT NOT NULL,
      raw_dir TEXT,
      FOREIGN KEY (comercio_id) REFERENCES comercios(comercio_id)
    )
  ")
}

# Solo puede usar valores provenientes del sitio. Nunca inventa capturas.
actualizar_precios_t2 <- function(modo = c("online", "offline"),
                                  db_path = "comparador_precios.sqlite",
                                  raw_root = "raw",
                                  pausa_cafam = 0.6,
                                  pausa_cruz_verde = 0.8) {
  modo <- match.arg(modo)
  necesarias <- c("scrapear_cafam", "scrapear_cruz_verde", "scrapear_la_rebaja",
                  "normalizar_resultado_cafam", "normalizar_resultado_cv",
                  "normalizar_resultado_lr", "validar_lote",
                  "crear_id_ejecucion_general", "construir_resumen_general",
                  "insertar_resultado_sqlite", "obtener_id_comercio")
  faltan <- necesarias[!vapply(necesarias, function(x)
    exists(x, mode = "function", inherits = TRUE), logical(1))]
  if (length(faltan)) stop("Primero carga scraper.R y validacion.R. Faltan: ",
                          paste(faltan, collapse = ", "))

  verificar_preparacion_t2(db_path, raw_root)

  if (modo == "offline") {
    if (!exists("previsualizar_actualizacion_t2", mode = "function")) {
      stop("Para modo offline, carga tambien previsualizacion_t2.R")
    }
    cat("\nMODO OFFLINE: solo reprocesa el RAW historico; NO inserta datos.\n")
    return(previsualizar_actualizacion_t2(raw_root = raw_root))
  }

  # Identificador NUEVO: solo se crea para una captura realmente online.
  id_global <- crear_id_ejecucion_general("taller2")
  configuracion <- list(
    cafam = list(nombre = "Droguerías Cafam", subcarpeta = "cafam",
                 extraer = scrapear_cafam, normalizar = normalizar_resultado_cafam,
                 args = list(pausa = pausa_cafam)),
    cruz_verde = list(nombre = "Cruz Verde", subcarpeta = "cruz_verde",
                      extraer = scrapear_cruz_verde, normalizar = normalizar_resultado_cv,
                      args = list(pausa = pausa_cruz_verde)),
    la_rebaja = list(nombre = "La Rebaja", subcarpeta = "la_rebaja",
                     extraer = scrapear_la_rebaja, normalizar = normalizar_resultado_lr,
                     args = list())
  )

  # No reutilizar directorios/identificadores de una corrida anterior.
  existentes <- vapply(configuracion, function(cnf)
    dir.exists(file.path(raw_root, cnf$subcarpeta, id_global)), logical(1))
  if (any(existentes)) stop("Ya hay RAW con este identificador; reintenta en otro segundo")

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 15000")
  crear_bitacora_t2(con)

  if (DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM ejecuciones WHERE ejecucion_id = ?",
                      params = list(id_global))$n[[1]] != 0L) {
    stop("Identificador de ejecucion ya registrado: ", id_global)
  }

  filas_resumen <- list()
  cat("\n=== ACTUALIZACION ONLINE REAL ===\n")
  cat("Identificador de captura:", id_global, "\n")

  for (clave in names(configuracion)) {
    cfg <- configuracion[[clave]]
    nombre <- cfg$nombre
    raw_dir_esperado <- file.path(raw_root, cfg$subcarpeta, id_global)
    inicio <- iso_colombia_final()
    cat("\n---", nombre, "---\n")

    # Cada comercio falla de forma independiente: los demas continuan.
    ejecucion_comercio <- tryCatch({
      argumentos <- c(list(modo = "online", raw_root = raw_root,
                           ejecucion_id = id_global), cfg$args)
      resultado <- do.call(cfg$extraer, argumentos)
      datos <- cfg$normalizar(resultado, ejecucion_global = id_global,
                             ejecucion_fuente = id_global)
      if (!is.data.frame(datos) || nrow(datos) < 1L) {
        stop("La extraccion no produjo registros normalizados")
      }
      if (!identical(unique(as.character(datos$comercio)), nombre)) {
        stop("El comercio de los datos no coincide con la fuente")
      }

      v <- validar_lote(datos, comercios_esperados = nombre)
      raw_dir <- if (!is.null(resultado$raw_dir)) resultado$raw_dir else
        if (!is.null(resultado$carpeta_raw)) resultado$carpeta_raw else raw_dir_esperado
      resumen <- construir_resumen_general(
        datos, resultado, nombre, id_global, id_global, "online", raw_dir
      )
      if (!isTRUE(v$cobertura_completa)) resumen$estado <- "parcial"

      # Insercion y registro de rechazados en una UNICA transaccion por comercio.
      comercio_id <- obtener_id_comercio(con, nombre)
      DBI::dbWithTransaction(con, {
        if (nrow(v$validas)) {
          insertar_resultado_sqlite(con, v$validas, resumen)
          DBI::dbExecute(con, "
            UPDATE observaciones SET estado_validacion = 'valida',
                   evidencia_raw = ?
            WHERE ejecucion_id = ? AND comercio_id = ?
              AND estado_validacion = 'pendiente'
          ", params = list(as.character(raw_dir), id_global, comercio_id))
        } else {
          # Una extraccion sin precios validos igual debe quedar documentada.
          DBI::dbExecute(con, "
            INSERT INTO ejecuciones
            (ejecucion_id, comercio_id, ejecucion_fuente,
             fecha_hora_inicio, fecha_hora_fin, modo,
             productos_reportados_sitio, registros_obtenidos,
             productos_categoria, comparables_con_precio,
             precios_encontrados, precios_faltantes, estado, raw_dir)
            VALUES (?, ?, ?, ?, ?, 'online', ?, ?, ?, 0, 0, ?, 'parcial', ?)
          ", params = list(id_global, comercio_id, id_global,
                            resumen$fecha_hora_inicio[[1]], resumen$fecha_hora_fin[[1]],
                            resumen$productos_reportados_sitio[[1]],
                            as.integer(nrow(datos)),
                            as.integer(sum(datos$incluido_categoria == 1L, na.rm = TRUE)),
                            as.integer(nrow(datos)), as.character(raw_dir)))
        }

        if (nrow(v$rechazadas)) {
          for (j in seq_len(nrow(v$rechazadas))) {
            f <- v$rechazadas[j, , drop = FALSE]
            DBI::dbExecute(con, "
              INSERT INTO observaciones_rechazadas
                (fecha_rechazo, observacion_id, ejecucion_id, comercio_id,
                 producto_comercio_id, motivo, evidencia_raw, origen)
              VALUES (?, NULL, ?, ?, ?, ?, ?, 'nueva_extraccion')
            ", params = list(iso_colombia_final(), id_global, comercio_id,
                              as.character(f$producto_comercio_id[[1]]),
                              as.character(f$motivo_rechazo[[1]]), as.character(raw_dir)))
          }
        }
      })

      nuevos <- DBI::dbGetQuery(con, "
        SELECT COUNT(*) AS n FROM observaciones
        WHERE ejecucion_id = ? AND comercio_id = ?
      ", params = list(id_global, comercio_id))$n[[1]]

      cambios <- DBI::dbGetQuery(con, "
        SELECT COUNT(*) AS n FROM v_cambios_precio
        WHERE ejecucion_actual = ? AND comercio_id = ? AND cambio_cop <> 0
      ", params = list(id_global, comercio_id))$n[[1]]

      data.frame(comercio = nombre, obtenidos = nrow(datos),
                 insertados = as.integer(nuevos),
                 rechazados = nrow(v$rechazadas),
                 comparables_validos = v$cobertura$productos_comparables_validos[[1]],
                 cambios_detectados = as.integer(cambios),
                 estado = as.character(resumen$estado[[1]]),
                 stringsAsFactors = FALSE)
    }, error = function(e) {
      msg <- conditionMessage(e)
      cat("FALLO:", msg, "\n")
      # Fallo sin datos validos: se conserva la ejecucion fallida y el motivo.
      # Si la transaccion anterior fallo, ya fue revertida.
      tryCatch(DBI::dbWithTransaction(con, {
        cid <- obtener_id_comercio(con, nombre)
        DBI::dbExecute(con, "
          INSERT OR IGNORE INTO ejecuciones
            (ejecucion_id, comercio_id, ejecucion_fuente,
             fecha_hora_inicio, fecha_hora_fin, modo,
             registros_obtenidos, estado, raw_dir)
          VALUES (?, ?, ?, ?, ?, 'online', 0, 'fallida', ?)
        ", params = list(id_global, cid, id_global, inicio,
                          iso_colombia_final(), raw_dir_esperado))
        DBI::dbExecute(con, "
          INSERT INTO errores_actualizacion
            (fecha_error, ejecucion_id, comercio_id, etapa, mensaje, raw_dir)
          VALUES (?, ?, ?, 'extraccion_normalizacion_o_insercion', ?, ?)
        ", params = list(iso_colombia_final(), id_global, cid, msg,
                          raw_dir_esperado))
      }), error = function(log_error) {
        warning("No fue posible registrar el fallo de ", nombre, ": ",
                conditionMessage(log_error))
      })
      data.frame(comercio = nombre, obtenidos = NA_integer_,
                 insertados = 0L, rechazados = NA_integer_,
                 comparables_validos = NA_integer_, cambios_detectados = 0L,
                 estado = "fallida", stringsAsFactors = FALSE)
    })

    filas_resumen[[clave]] <- ejecucion_comercio
    print(ejecucion_comercio, row.names = FALSE)
  }

  tabla <- do.call(rbind, filas_resumen)
  rownames(tabla) <- NULL
  cat("\n=== RESUMEN ACTUALIZACION T2 ===\n")
  print(tabla, row.names = FALSE)
  cat("Identificador real:", id_global, "\n")
  cat("Integridad:", DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]], "\n")
  cat("Errores FK:", nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check")), "\n")
  invisible(list(ejecucion_id = id_global, resumen = tabla))
}
