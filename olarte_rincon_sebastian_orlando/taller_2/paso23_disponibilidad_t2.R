# Mineria de Datos 2016325 - Taller 2
# Paso 23: distinguir NO OBSERVADO de OBSERVADO PERO RECHAZADO.
# Ejecutar con Shiny detenido, desde taller_2:
# source("paso23_disponibilidad_t2.R", encoding = "UTF-8")
# No ejecuta scraping ni agrega observaciones o precios inventados.

if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("RSQLite", quietly = TRUE)) {
  stop("Faltan los paquetes DBI o RSQLite")
}

registrar_disponibilidad_t2 <- function(
    db_path = "comparador_precios.sqlite",
    carpeta_respaldos = "backups") {

  if (!file.exists(db_path)) stop("No existe la SQLite de Taller 2")
  dir.create(carpeta_respaldos, showWarnings = FALSE, recursive = TRUE)
  destino <- file.path(carpeta_respaldos, paste0(
    "antes_disponibilidad_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".sqlite"))
  if (file.exists(destino) || !isTRUE(file.copy(db_path, destino, overwrite = FALSE))) {
    stop("No se pudo crear un respaldo nuevo. No se modifico la base.")
  }
  cat("Respaldo creado:", destino, "\n")

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 15000")
  stopifnot(identical(DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]], "ok"))

  necesarias <- c("ejecuciones", "comercios", "anuncios", "observaciones",
                 "observaciones_rechazadas")
  if (!all(necesarias %in% DBI::dbListTables(con))) {
    stop("Faltan tablas necesarias. No se aplicaron cambios.")
  }

  # Solo se compara la ultima corrida de cada comercio si fue COMPLETA.
  # La anterior tambien debe ser completa (o la captura historica reprocesada).
  sql_candidatos <- "
    WITH orden AS (
      SELECT comercio_id, ejecucion_id, estado, fecha_hora_inicio,
             ROW_NUMBER() OVER (
               PARTITION BY comercio_id
               ORDER BY fecha_hora_inicio DESC, ejecucion_id DESC
             ) AS posicion
      FROM ejecuciones
    ), pares AS (
      SELECT act.comercio_id, act.ejecucion_id AS ejecucion_actual,
             ant.ejecucion_id AS ejecucion_anterior
      FROM orden act
      JOIN orden ant ON ant.comercio_id = act.comercio_id
                    AND ant.posicion = 2
      WHERE act.posicion = 1 AND act.estado = 'completa'
        AND ant.estado IN ('completa', 'reprocesada_offline')
    )
    SELECT p.ejecucion_actual, p.comercio_id,
           a.producto_comercio_id, p.ejecucion_anterior,
           a.producto_original
    FROM pares p
    JOIN anuncios a ON a.ejecucion_id = p.ejecucion_anterior
                   AND a.comercio_id = p.comercio_id
    WHERE NOT EXISTS (
      SELECT 1 FROM anuncios nuevo
      WHERE nuevo.ejecucion_id = p.ejecucion_actual
        AND nuevo.comercio_id = p.comercio_id
        AND nuevo.producto_comercio_id = a.producto_comercio_id
    )
      AND NOT EXISTS (
      SELECT 1 FROM observaciones_rechazadas r
      WHERE r.ejecucion_id = p.ejecucion_actual
        AND r.comercio_id = p.comercio_id
        AND r.producto_comercio_id = a.producto_comercio_id
    )
  "

  candidatos <- DBI::dbGetQuery(con, sql_candidatos)
  cat("No observados verificados entre las dos ultimas capturas completas:",
      nrow(candidatos), "\n")

  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS productos_no_observados (
        ausencia_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ejecucion_id TEXT NOT NULL,
        comercio_id INTEGER NOT NULL,
        producto_comercio_id TEXT NOT NULL,
        ejecucion_anterior TEXT NOT NULL,
        producto_original_anterior TEXT,
        fecha_registro TEXT NOT NULL,
        motivo TEXT NOT NULL,
        UNIQUE (ejecucion_id, comercio_id, producto_comercio_id),
        FOREIGN KEY (ejecucion_id, comercio_id)
          REFERENCES ejecuciones(ejecucion_id, comercio_id),
        FOREIGN KEY (ejecucion_anterior, comercio_id, producto_comercio_id)
          REFERENCES anuncios(ejecucion_id, comercio_id, producto_comercio_id)
      )
    ")
    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_no_obs_comercio_ejecucion
      ON productos_no_observados(comercio_id, ejecucion_id)
    ")

    fecha <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    for (i in seq_len(nrow(candidatos))) {
      f <- candidatos[i, ]
      DBI::dbExecute(con, "
        INSERT OR IGNORE INTO productos_no_observados
          (ejecucion_id, comercio_id, producto_comercio_id,
           ejecucion_anterior, producto_original_anterior,
           fecha_registro, motivo)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ", params = list(
        as.character(f$ejecucion_actual), as.integer(f$comercio_id),
        as.character(f$producto_comercio_id),
        as.character(f$ejecucion_anterior),
        if (is.na(f$producto_original)) NA_character_ else as.character(f$producto_original),
        fecha,
        "No aparecio en el inventario extraido de esta ejecucion completa; no implica agotamiento"
      ))
    }

    # Vista de estados: registros observados, rechazados y no observados.
    # Nunca asigna un precio ni infiere stock a los productos ausentes.
    DBI::dbExecute(con, "DROP VIEW IF EXISTS v_estado_captura_t2")
    DBI::dbExecute(con, "
      CREATE VIEW v_estado_captura_t2 AS
      SELECT o.ejecucion_id, o.comercio_id, c.nombre AS comercio,
             o.producto_comercio_id, a.producto_original,
             o.observacion_id, o.fecha_hora_consulta, o.precio_cop,
             o.estado_validacion, o.estado_disponibilidad,
             CASE WHEN o.estado_validacion = 'rechazada'
                  THEN 'observado_rechazado'
                  ELSE 'observado' END AS situacion_captura,
             o.evidencia_raw
      FROM observaciones o
      JOIN comercios c ON c.comercio_id = o.comercio_id
      JOIN anuncios a ON a.ejecucion_id = o.ejecucion_id
                     AND a.comercio_id = o.comercio_id
                     AND a.producto_comercio_id = o.producto_comercio_id
      UNION ALL
      SELECT r.ejecucion_id, r.comercio_id, c.nombre,
             r.producto_comercio_id, NULL,
             NULL, NULL, NULL, 'rechazada', 'sin_evidencia',
             'observado_rechazado', r.evidencia_raw
      FROM observaciones_rechazadas r
      JOIN comercios c ON c.comercio_id = r.comercio_id
      WHERE r.observacion_id IS NULL
      UNION ALL
      SELECT n.ejecucion_id, n.comercio_id, c.nombre,
             n.producto_comercio_id, n.producto_original_anterior,
             NULL, NULL, NULL, 'no_aplica', 'no_observado',
             'no_observado', NULL
      FROM productos_no_observados n
      JOIN comercios c ON c.comercio_id = n.comercio_id
    ")
  })

  fallos <- DBI::dbGetQuery(con, "
    SELECT n.ausencia_id
    FROM productos_no_observados n
    WHERE EXISTS (
      SELECT 1 FROM anuncios a
      WHERE a.ejecucion_id = n.ejecucion_id
        AND a.comercio_id = n.comercio_id
        AND a.producto_comercio_id = n.producto_comercio_id
    ) OR EXISTS (
      SELECT 1 FROM observaciones_rechazadas r
      WHERE r.ejecucion_id = n.ejecucion_id
        AND r.comercio_id = n.comercio_id
        AND r.producto_comercio_id = n.producto_comercio_id
    )
  ")
  if (nrow(fallos) > 0L) stop("Hay ausencias contradictorias; revisar el historial")

  cat("\n=== PASO 23: ESTADOS DE CAPTURA ===\n")
  print(DBI::dbGetQuery(con, "
    SELECT situacion_captura, COUNT(*) AS registros
    FROM v_estado_captura_t2
    GROUP BY situacion_captura
    ORDER BY situacion_captura
  "), row.names = FALSE)
  cat("\nNo observados por comercio:\n")
  print(DBI::dbGetQuery(con, "
    SELECT c.nombre AS comercio, COUNT(*) AS no_observados
    FROM productos_no_observados n
    JOIN comercios c ON c.comercio_id = n.comercio_id
    GROUP BY c.nombre ORDER BY c.nombre
  "), row.names = FALSE)
  cat("\nObservaciones reales (sin cambios):\n")
  print(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones"))
  cat("Integridad:", DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]], "\n")
  cat("Errores FK:", nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check")), "\n")
  invisible(TRUE)
}

registrar_disponibilidad_t2()
