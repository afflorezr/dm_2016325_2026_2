# Mineria de Datos - Taller 2
# Paso 12: documentar las 14 incidencias historicas de La Rebaja.
# Se conservan observaciones y valores originales. No ejecuta scraping.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Falta jsonlite. Ejecuta install.packages('jsonlite') y reintenta.")
}

registrar_incidencias_t1 <- function(
  db_path = "comparador_precios.sqlite",
  backup_path = "comparador_precios_respaldo_taller2.sqlite",
  raw_dir = "raw/la_rebaja/larebaja_20261010_214127"
) {
  if (!file.exists(db_path) || !file.exists(backup_path)) {
    stop("Falta la base de trabajo o su respaldo. No se aplicaron cambios.")
  }
  if (!dir.exists(raw_dir)) stop("No se encontro el directorio RAW de La Rebaja.")

  # Localizaciones reales verificadas en las respuestas JSON de VTEX.
  archivos_json <- c(
    `1349` = "medicamentos_formula_medica__OrderByNameASC__1550_1599.json",
    `246`  = "medicamentos_formula_medica__OrderByNameASC__1600_1649.json",
    `1226` = "medicamentos_formula_medica__OrderByNameASC__1650_1699.json",
    `335`  = "medicamentos_formula_medica__OrderByNameASC__1700_1749.json",
    `1218` = "medicamentos_formula_medica__OrderByNameASC__1750_1799.json",
    `466`  = "medicamentos_formula_medica__OrderByNameASC__1900_1949.json",
    `1148` = "medicamentos_formula_medica__OrderByNameASC__1950_1999.json",
    `1236` = "medicamentos_formula_medica__OrderByNameASC__2050_2099.json",
    `591`  = "medicamentos_formula_medica__OrderByNameASC__2100_2149.json",
    `4819` = "medicamentos_formula_medica__OrderByNameASC__2250_2299.json",
    `807`  = "medicamentos_formula_medica__OrderByNameASC__2300_2349.json",
    `2766` = "medicamentos_formula_medica__OrderByNameASC__2350_2399.json",
    `856`  = "medicamentos_formula_medica__OrderByNameASC__2400_2449.json",
    `1879` = "medicamentos_formula_medica__OrderByNameDESC__1500_1549.json"
  )

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")

  requeridas <- c("correcciones", "observaciones_rechazadas", "observaciones", "anuncios")
  if (!all(requeridas %in% DBI::dbListTables(con))) {
    stop("Faltan las tablas del Paso 11. Ejecuta primero estructura_taller2.R.")
  }

  datos <- DBI::dbGetQuery(con, "
    SELECT o.observacion_id, o.ejecucion_id, o.comercio_id,
           o.producto_comercio_id, o.precio_cop,
           o.estado_validacion, o.estado_disponibilidad,
           a.comparable, a.incluido_categoria, c.nombre AS comercio
    FROM observaciones o
    INNER JOIN anuncios a
      ON a.ejecucion_id = o.ejecucion_id
     AND a.comercio_id = o.comercio_id
     AND a.producto_comercio_id = o.producto_comercio_id
    INNER JOIN comercios c ON c.comercio_id = o.comercio_id
    WHERE o.precio_cop = 0 AND c.nombre = 'La Rebaja'
  ")
  ids <- as.character(datos$producto_comercio_id)
  if (nrow(datos) != 14L || anyDuplicated(ids) ||
      !identical(sort(ids), sort(names(archivos_json)))) {
    stop("Los 14 identificadores no coinciden exactamente con la captura auditada.")
  }
  if (any(datos$comparable != 0L) || any(datos$incluido_categoria != 0L)) {
    stop("Hay registros cero dentro de los comparables/categoria; revisar manualmente.")
  }

  csv_path <- file.path(raw_dir, "larebaja_registros.csv")
  if (!file.exists(csv_path)) stop("No se encontro el CSV original.")
  raw_csv <- read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
  filas_csv <- raw_csv[as.character(raw_csv$producto_comercio_id) %in% ids, ]
  if (nrow(filas_csv) != 14L ||
      !identical(sort(as.character(filas_csv$producto_comercio_id)), sort(ids)) ||
      any(is.na(filas_csv$precio_cop) | filas_csv$precio_cop != 0) ||
      any(is.na(filas_csv$precio_antes_cop) | filas_csv$precio_antes_cop != 0)) {
    stop("La evidencia del CSV no coincide con los 14 registros de precio cero.")
  }

  # Confirmar directamente el estado comercial en cada JSON original.
  evidencia <- stats::setNames(character(length(ids)), ids)
  for (id in ids) {
    ruta <- file.path(raw_dir, unname(archivos_json[id]))
    if (!file.exists(ruta)) stop(paste("Falta JSON:", ruta))
    productos <- jsonlite::fromJSON(ruta, simplifyVector = FALSE)
    encontrado <- Filter(function(p) identical(as.character(p$productId), id), productos)
    if (length(encontrado) != 1L) {
      stop(paste("El producto", id, "no es unico o no esta en:", ruta))
    }
    ofertas <- unlist(lapply(encontrado[[1]]$items, function(item) item$sellers),
                     recursive = FALSE)
    comerciales <- lapply(ofertas, function(vendedor) vendedor$commertialOffer)
    if (length(comerciales) == 0L) stop(paste("Sin ofertas verificables:", id))
    precio <- vapply(comerciales, function(x) if (is.null(x$Price)) NA_real_ else as.numeric(x$Price), numeric(1))
    lista <- vapply(comerciales, function(x) if (is.null(x$ListPrice)) NA_real_ else as.numeric(x$ListPrice), numeric(1))
    cantidad <- vapply(comerciales, function(x) if (is.null(x$AvailableQuantity)) NA_real_ else as.numeric(x$AvailableQuantity), numeric(1))
    disponible <- vapply(comerciales, function(x) if (is.null(x$IsAvailable)) NA else isTRUE(x$IsAvailable), logical(1))
    if (!all(!is.na(precio) & precio == 0) ||
        !all(!is.na(lista) & lista == 0) ||
        !all(!is.na(cantidad) & cantidad == 0) ||
        !all(!is.na(disponible) & !disponible)) {
      stop(paste("La respuesta JSON no respalda precio cero y agotado:", id))
    }
    evidencia[id] <- gsub("\\\\", "/", ruta)
  }

  fecha <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  motivo <- paste(
    "Incidencia historica Taller 1: el RAW JSON VTEX informa Price=0,",
    "ListPrice=0, AvailableQuantity=0 e IsAvailable=false.",
    "No es precio valido para comparacion. Se conserva el registro y su precio original."
  )

  DBI::dbWithTransaction(con, {
    for (i in seq_len(nrow(datos))) {
      fila <- datos[i, ]
      id <- as.character(fila$producto_comercio_id)
      obs_id <- as.integer(fila$observacion_id)
      ruta <- unname(evidencia[id])

      registrar_cambio <- function(campo, anterior, nuevo) {
        if (identical(as.character(anterior), nuevo)) return(invisible(NULL))
        existente <- DBI::dbGetQuery(con, "
          SELECT COUNT(*) AS n FROM correcciones
          WHERE tabla_afectada = 'observaciones'
            AND registro_id = ? AND campo = ? AND valor_nuevo = ?",
          params = list(as.character(obs_id), campo, nuevo))$n[[1]]
        if (existente == 0L) {
          DBI::dbExecute(con, "
            INSERT INTO correcciones
            (fecha_correccion, tabla_afectada, registro_id, campo,
             valor_anterior, valor_nuevo, motivo, evidencia_raw)
            VALUES (?, 'observaciones', ?, ?, ?, ?, ?, ?)",
            params = list(fecha, as.character(obs_id), campo,
                          as.character(anterior), nuevo, motivo, ruta))
        }
      }

      registrar_cambio("estado_validacion", fila$estado_validacion, "rechazada")
      registrar_cambio("estado_disponibilidad", fila$estado_disponibilidad, "agotado")

      DBI::dbExecute(con, "
        UPDATE observaciones
           SET estado_validacion = 'rechazada',
               estado_disponibilidad = 'agotado',
               evidencia_raw = ?
         WHERE observacion_id = ?",
         params = list(ruta, obs_id))

      registrado <- DBI::dbGetQuery(con, "
        SELECT COUNT(*) AS n FROM observaciones_rechazadas
         WHERE observacion_id = ? AND origen = 'historico'",
        params = list(obs_id))$n[[1]]
      if (registrado == 0L) {
        DBI::dbExecute(con, "
          INSERT INTO observaciones_rechazadas
          (fecha_rechazo, observacion_id, ejecucion_id, comercio_id,
           producto_comercio_id, motivo, evidencia_raw, origen)
          VALUES (?, ?, ?, ?, ?, ?, ?, 'historico')",
          params = list(fecha, obs_id, fila$ejecucion_id,
                        as.integer(fila$comercio_id), id, motivo, ruta))
      }
    }
  })

  cat("\n=== VERIFICACION DEL PASO 12 ===\n")
  print(DBI::dbGetQuery(con, "PRAGMA integrity_check"))
  print(DBI::dbGetQuery(con, "PRAGMA foreign_key_check"))
  print(DBI::dbGetQuery(con, "
    SELECT COUNT(*) AS total_observaciones,
           SUM(CASE WHEN precio_cop = 0 THEN 1 ELSE 0 END) AS precios_cero_conservados,
           SUM(CASE WHEN precio_cop = 0 AND estado_validacion = 'rechazada' THEN 1 ELSE 0 END) AS ceros_rechazados,
           SUM(CASE WHEN precio_cop = 0 AND estado_disponibilidad = 'agotado' THEN 1 ELSE 0 END) AS ceros_agotados
    FROM observaciones"))
  print(DBI::dbGetQuery(con, "
    SELECT (SELECT COUNT(*) FROM observaciones_rechazadas WHERE origen='historico') AS rechazados_historicos,
           (SELECT COUNT(*) FROM correcciones WHERE tabla_afectada='observaciones') AS cambios_documentados"))
  invisible(TRUE)
}

registrar_incidencias_t1()
