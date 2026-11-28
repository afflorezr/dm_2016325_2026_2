# Taller 2 - comparacion de dos capturas elegidas (solo lectura)
# No ejecuta scraping, no escribe en SQLite y no altera el historico.
# Compara el mismo producto_comercio_id dentro del mismo comercio.

listar_ejecuciones_comparacion_db <- function(con) {
  stopifnot(DBI::dbIsValid(con))
  DBI::dbGetQuery(con, "
    SELECT ejecucion_id,
           MIN(substr(fecha_hora_inicio, 1, 19)) AS fecha_hora,
           COUNT(DISTINCT comercio_id) AS comercios
    FROM ejecuciones
    GROUP BY ejecucion_id
    ORDER BY fecha_hora DESC, ejecucion_id DESC
  ")
}

comparar_ejecuciones_db <- function(con, anterior_id, actual_id, umbral_pct = 10) {
  if (!DBI::dbIsValid(con)) stop("La conexion SQLite no esta abierta")
  ids <- c(anterior_id, actual_id)
  if (length(anterior_id) != 1L || length(actual_id) != 1L ||
      anyNA(ids) || any(!nzchar(ids)) || any(nchar(ids) > 160L) ||
      identical(as.character(anterior_id), as.character(actual_id))) {
    stop("Seleccione dos ejecuciones distintas y validas")
  }
  if (length(umbral_pct) != 1L || is.na(umbral_pct) ||
      !is.finite(suppressWarnings(as.numeric(umbral_pct))) ||
      umbral_pct < 0 || umbral_pct > 1000) {
    stop("El umbral porcentual debe estar entre 0 y 1000")
  }

  ejecuciones <- listar_ejecuciones_comparacion_db(con)
  ind_a <- match(as.character(anterior_id), ejecuciones$ejecucion_id)
  ind_b <- match(as.character(actual_id), ejecuciones$ejecucion_id)
  if (is.na(ind_a) || is.na(ind_b)) stop("Ejecucion no registrada en SQLite")
  if (!(ejecuciones$fecha_hora[ind_a] < ejecuciones$fecha_hora[ind_b])) {
    stop("La ejecucion anterior debe preceder cronologicamente a la actual")
  }

  # Tres parametros enlazados; los valores del usuario NUNCA se concatenan al SQL.
  # Se comparan solo comercios presentes en las dos ejecuciones.
  # 'No observado' implica que no existe anuncio en la captura nueva.
  # Si existe un anuncio sin precio valido, se identifica por separado.
  sql <- "
    WITH parametros AS (
      SELECT ? AS id_anterior, ? AS id_actual, ? AS umbral
    ), comercios_comunes AS (
      SELECT e1.comercio_id
      FROM ejecuciones e1
      JOIN ejecuciones e2 ON e2.comercio_id = e1.comercio_id
      CROSS JOIN parametros par
      WHERE e1.ejecucion_id = par.id_anterior
        AND e2.ejecucion_id = par.id_actual
    ), filas AS (
      SELECT o.ejecucion_id, o.comercio_id, c.nombre AS comercio,
             o.producto_comercio_id, a.producto_original,
             o.precio_cop, o.fecha_hora_consulta,
             ROW_NUMBER() OVER (
               PARTITION BY o.ejecucion_id, o.comercio_id, o.producto_comercio_id
               ORDER BY o.fecha_hora_consulta DESC, o.observacion_id DESC
             ) AS posicion
      FROM observaciones o
      JOIN anuncios a ON a.ejecucion_id = o.ejecucion_id
          AND a.comercio_id = o.comercio_id
          AND a.producto_comercio_id = o.producto_comercio_id
      JOIN comercios c ON c.comercio_id = o.comercio_id
      JOIN comercios_comunes cc ON cc.comercio_id = o.comercio_id
      CROSS JOIN parametros par
      WHERE o.ejecucion_id IN (par.id_anterior, par.id_actual)
        AND o.precio_cop > 0
        AND COALESCE(o.estado_validacion, '') <> 'rechazada'
    ), antigua AS (
      SELECT f.* FROM filas f CROSS JOIN parametros par
      WHERE f.ejecucion_id = par.id_anterior AND f.posicion = 1
    ), nueva AS (
      SELECT f.* FROM filas f CROSS JOIN parametros par
      WHERE f.ejecucion_id = par.id_actual AND f.posicion = 1
    ), unidas AS (
      SELECT a.comercio_id, a.comercio,
             a.producto_comercio_id,
             COALESCE(n.producto_original, a.producto_original) AS producto,
             a.precio_cop AS precio_anterior_cop,
             n.precio_cop AS precio_actual_cop,
             a.fecha_hora_consulta AS fecha_anterior,
             n.fecha_hora_consulta AS fecha_actual
      FROM antigua a
      LEFT JOIN nueva n ON n.comercio_id = a.comercio_id
        AND n.producto_comercio_id = a.producto_comercio_id
      UNION ALL
      SELECT n.comercio_id, n.comercio,
             n.producto_comercio_id, n.producto_original AS producto,
             NULL AS precio_anterior_cop,
             n.precio_cop AS precio_actual_cop,
             NULL AS fecha_anterior,
             n.fecha_hora_consulta AS fecha_actual
      FROM nueva n
      LEFT JOIN antigua a ON a.comercio_id = n.comercio_id
        AND a.producto_comercio_id = n.producto_comercio_id
      WHERE a.producto_comercio_id IS NULL
    ), clasificacion AS (
      SELECT u.*,
        CASE
          WHEN u.precio_anterior_cop IS NULL THEN 'Nuevo'
          WHEN u.precio_actual_cop IS NULL AND (
            EXISTS (
              SELECT 1 FROM anuncios ax CROSS JOIN parametros par
              WHERE ax.ejecucion_id = par.id_actual
                AND ax.comercio_id = u.comercio_id
                AND ax.producto_comercio_id = u.producto_comercio_id
            ) OR EXISTS (
              SELECT 1 FROM observaciones_rechazadas rx CROSS JOIN parametros par
              WHERE rx.ejecucion_id = par.id_actual
                AND rx.comercio_id = u.comercio_id
                AND rx.producto_comercio_id = u.producto_comercio_id
            )
          ) THEN 'Sin precio valido'
          WHEN u.precio_actual_cop IS NULL THEN 'No observado'
          WHEN u.precio_actual_cop > u.precio_anterior_cop THEN 'Aumento'
          WHEN u.precio_actual_cop < u.precio_anterior_cop THEN 'Disminucion'
          ELSE 'Sin cambio'
        END AS estado,
        CASE WHEN u.precio_anterior_cop IS NOT NULL
                  AND u.precio_actual_cop IS NOT NULL
             THEN ROUND(u.precio_actual_cop - u.precio_anterior_cop, 2)
             ELSE NULL END AS cambio_cop,
        CASE WHEN u.precio_anterior_cop IS NOT NULL
                  AND u.precio_actual_cop IS NOT NULL
             THEN ROUND(100.0 * (u.precio_actual_cop - u.precio_anterior_cop)
                        / NULLIF(u.precio_anterior_cop, 0), 2)
             ELSE NULL END AS cambio_pct
      FROM unidas u
    )
    SELECT comercio, producto, producto_comercio_id,
           precio_anterior_cop, precio_actual_cop,
           cambio_cop, cambio_pct, estado,
           CASE WHEN cambio_pct IS NOT NULL AND cambio_cop <> 0
                  AND ABS(cambio_pct) >= (SELECT umbral FROM parametros)
                THEN 1 ELSE 0 END AS supera_umbral,
           fecha_anterior, fecha_actual
    FROM clasificacion
    ORDER BY CASE estado
        WHEN 'Aumento' THEN 1 WHEN 'Disminucion' THEN 2
        WHEN 'Nuevo' THEN 3 WHEN 'No observado' THEN 4
        WHEN 'Sin precio valido' THEN 5 ELSE 6 END,
        ABS(COALESCE(cambio_cop, 0)) DESC, comercio, producto
  "

  detalle <- DBI::dbGetQuery(con, sql, params = list(
    as.character(anterior_id), as.character(actual_id), as.numeric(umbral_pct)
  ))

  categorias <- c("Aumento", "Disminucion", "Sin cambio", "Nuevo",
                  "No observado", "Sin precio valido")
  resumen <- data.frame(
    estado = categorias,
    cantidad = as.integer(table(factor(detalle$estado, levels = categorias))),
    stringsAsFactors = FALSE
  )
  list(
    anterior_id = as.character(anterior_id),
    actual_id = as.character(actual_id),
    umbral_pct = as.numeric(umbral_pct),
    detalle = detalle,
    resumen = resumen,
    cambios_grandes = sum(detalle$supera_umbral, na.rm = TRUE),
    comercios_comparados = unique(detalle$comercio),
    aclaracion = paste(
      "Se compara el mismo anuncio en el mismo comercio entre las dos ejecuciones.",
      "No observado no significa agotado.",
      "Los registros observados sin precio valido se informan por separado."
    )
  )
}
