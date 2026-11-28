# Mineria de Datos 2016325 - Taller 2
# Paso 13: vistas SQL para el comparador de precios.
# Ejecutar desde el proyecto taller_2:
# source("vistas_taller2.R", encoding = "UTF-8")
# No altera observaciones, precios ni archivos RAW.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

crear_vistas_taller2 <- function(db_path = "comparador_precios.sqlite") {
  if (!file.exists(db_path)) stop("No se encontro comparador_precios.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")

  if (!identical(DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][1], "ok")) {
    stop("La base no supera la comprobacion de integridad.")
  }
  campos <- DBI::dbListFields(con, "observaciones")
  if (!all(c("estado_validacion", "estado_disponibilidad") %in% campos)) {
    stop("Faltan campos del Paso 11. Ejecuta estructura_taller2.R primero.")
  }

  DBI::dbWithTransaction(con, {
    # Se eliminan solo las vistas de Taller 2; nunca las tablas de datos.
    DBI::dbExecute(con, "DROP VIEW IF EXISTS v_comparables")
    DBI::dbExecute(con, "DROP VIEW IF EXISTS v_cambios_precio")
    DBI::dbExecute(con, "DROP VIEW IF EXISTS v_ultimo_precio")

    DBI::dbExecute(con, "
      CREATE VIEW v_ultimo_precio AS
      WITH ordenadas AS (
        SELECT o.observacion_id,
               o.ejecucion_id, o.comercio_id, o.producto_comercio_id,
               o.fecha_hora_consulta, o.precio_cop, o.precio_antes_cop,
               o.precio_lista_cop, o.promocion, o.pum_cop,
               o.estado_validacion, o.estado_disponibilidad,
               ROW_NUMBER() OVER (
                 PARTITION BY o.comercio_id, o.producto_comercio_id
                 ORDER BY o.fecha_hora_consulta DESC, o.observacion_id DESC
               ) AS orden
        FROM observaciones o
      )
      SELECT o.observacion_id, o.ejecucion_id, o.comercio_id,
             c.nombre AS comercio, o.producto_comercio_id,
             a.producto_comun_id, a.producto_original, a.marca_estandar,
             a.subcategoria_estandar, a.comparable, a.incluido_categoria,
             a.contenido_valor_estandar, a.unidad_estandar,
             a.url, o.fecha_hora_consulta,
             o.precio_cop, o.precio_antes_cop, o.precio_lista_cop,
             o.promocion, o.pum_cop,
             o.estado_validacion, o.estado_disponibilidad,
             e.modo AS modo_ejecucion, e.estado AS estado_ejecucion
      FROM ordenadas o
      JOIN anuncios a
        ON a.ejecucion_id = o.ejecucion_id
       AND a.comercio_id = o.comercio_id
       AND a.producto_comercio_id = o.producto_comercio_id
      JOIN comercios c ON c.comercio_id = o.comercio_id
      JOIN ejecuciones e
        ON e.ejecucion_id = o.ejecucion_id AND e.comercio_id = o.comercio_id
      WHERE o.orden = 1
        AND o.precio_cop > 0
        AND o.estado_validacion <> 'rechazada'
    ")

    DBI::dbExecute(con, "
      CREATE VIEW v_cambios_precio AS
      WITH por_ejecucion AS (
        SELECT o.observacion_id, o.ejecucion_id,
               o.comercio_id, o.producto_comercio_id,
               o.fecha_hora_consulta, o.precio_cop,
               a.producto_comun_id, a.producto_original,
               a.comparable, a.incluido_categoria,
               c.nombre AS comercio,
               ROW_NUMBER() OVER (
                 PARTITION BY o.ejecucion_id, o.comercio_id, o.producto_comercio_id
                 ORDER BY o.fecha_hora_consulta DESC, o.observacion_id DESC
               ) AS orden
        FROM observaciones o
        JOIN anuncios a
          ON a.ejecucion_id = o.ejecucion_id
         AND a.comercio_id = o.comercio_id
         AND a.producto_comercio_id = o.producto_comercio_id
        JOIN comercios c ON c.comercio_id = o.comercio_id
        WHERE o.precio_cop > 0
          AND o.estado_validacion <> 'rechazada'
      ), serie AS (
        SELECT p.*,
               LAG(p.precio_cop) OVER (
                 PARTITION BY p.comercio_id, p.producto_comercio_id
                 ORDER BY p.fecha_hora_consulta, p.observacion_id
               ) AS precio_anterior_cop,
               LAG(p.fecha_hora_consulta) OVER (
                 PARTITION BY p.comercio_id, p.producto_comercio_id
                 ORDER BY p.fecha_hora_consulta, p.observacion_id
               ) AS fecha_hora_anterior,
               LAG(p.ejecucion_id) OVER (
                 PARTITION BY p.comercio_id, p.producto_comercio_id
                 ORDER BY p.fecha_hora_consulta, p.observacion_id
               ) AS ejecucion_anterior
        FROM por_ejecucion p
        WHERE p.orden = 1
      )
      SELECT observacion_id, comercio_id, comercio, producto_comercio_id,
             producto_comun_id, producto_original, comparable, incluido_categoria,
             ejecucion_anterior, ejecucion_id AS ejecucion_actual,
             fecha_hora_anterior, fecha_hora_consulta AS fecha_hora_actual,
             precio_anterior_cop, precio_cop AS precio_actual_cop,
             ROUND(precio_cop - precio_anterior_cop, 2) AS cambio_cop,
             ROUND(100.0 * (precio_cop - precio_anterior_cop)
                   / NULLIF(precio_anterior_cop, 0), 2) AS cambio_pct
      FROM serie
      WHERE precio_anterior_cop IS NOT NULL
        AND ejecucion_anterior <> ejecucion_id
    ")

    DBI::dbExecute(con, "
      CREATE VIEW v_comparables AS
      SELECT u.observacion_id, u.ejecucion_id, u.comercio_id,
             u.comercio, u.producto_comercio_id, u.producto_comun_id,
             pc.producto_comun, u.producto_original, u.marca_estandar,
             u.subcategoria_estandar, u.url, u.fecha_hora_consulta,
             u.precio_cop, u.precio_antes_cop, u.promocion,
             u.contenido_valor_estandar AS contenido_total,
             u.unidad_estandar AS unidad_contenido,
             CASE WHEN u.contenido_valor_estandar > 0
                  THEN ROUND(u.precio_cop / u.contenido_valor_estandar, 2)
                  ELSE NULL END AS precio_por_unidad_cop,
             u.estado_validacion, u.estado_disponibilidad
      FROM v_ultimo_precio u
      JOIN productos_comunes pc
        ON pc.producto_comun_id = u.producto_comun_id
      WHERE u.comparable = 1
        AND u.incluido_categoria = 1
    ")
  })

  cat("\n=== RESULTADOS DEL PASO 13 ===\n")
  print(DBI::dbGetQuery(con, "
    SELECT name FROM sqlite_master
    WHERE type = 'view' AND name IN (
      'v_ultimo_precio', 'v_cambios_precio', 'v_comparables'
    ) ORDER BY name
  "))
  print(DBI::dbGetQuery(con, "
    SELECT 'v_ultimo_precio' AS vista, COUNT(*) AS filas FROM v_ultimo_precio
    UNION ALL
    SELECT 'v_cambios_precio', COUNT(*) FROM v_cambios_precio
    UNION ALL
    SELECT 'v_comparables', COUNT(*) FROM v_comparables
  "))
  print(DBI::dbGetQuery(con, "
    SELECT comercio, COUNT(*) AS comparables,
           SUM(CASE WHEN precio_por_unidad_cop > 0 THEN 1 ELSE 0 END)
             AS precios_unitarios_validos
    FROM v_comparables GROUP BY comercio ORDER BY comercio
  "))
  print(DBI::dbGetQuery(con, "PRAGMA integrity_check"))
  invisible(TRUE)
}

crear_vistas_taller2()
