# esquema.R — Taller 2
# Migración idempotente del esquema: contenido normalizado, índices y vistas SQL
# que usa la aplicación. Se puede ejecutar cuantas veces se quiera.
# Requiere scraper.R cargado (usa agregar_columna_si_falta y registrar_correccion).

ids_historicos <- c("farmatodo_2026-10-10", "larebaja_2026-10-10", "locatel_2026-10-10",
                    "farmatodo_2026-11-09", "larebaja_2026-11-09", "locatel_2026-11-09")

# ---- Vistas, en orden de dependencia ------------------------------------

VISTAS_SQL <- c(

  # Ejecuciones útiles (completas o parciales) numeradas por comercio:
  # orden 1 = la más reciente, 2 = la anterior.
  v_ejecuciones_orden = "
    CREATE VIEW v_ejecuciones_orden AS
    SELECT id_ejecucion, id_comercio, fecha_hora_inicio, estado,
           ROW_NUMBER() OVER (PARTITION BY id_comercio
                              ORDER BY fecha_hora_inicio DESC) AS orden
    FROM   ejecuciones
    WHERE  estado IN ('completa', 'parcial')",

  # Estado actual: cada anuncio incluido, con su observación de la ejecución
  # más reciente de su comercio.
  v_ultimo_precio = "
    CREATE VIEW v_ultimo_precio AS
    SELECT o.id_observacion, o.id_ejecucion, o.fecha_hora_consulta,
           SUBSTR(o.fecha_hora_consulta, 1, 10)            AS fecha,
           c.nombre                                        AS comercio,
           a.id_anuncio, a.sku,
           a.nombre_original                               AS nombre,
           a.marca, a.subcategoria, a.url, a.id_comparable,
           a.contenido_total, a.unidad_normalizada,
           o.precio, o.precio_antes, o.es_promocion,
           CASE WHEN o.disponible = 1 THEN 'disponible' ELSE 'agotado' END AS disponibilidad,
           CASE WHEN o.precio IS NOT NULL AND a.contenido_total > 0
                THEN ROUND(o.precio * 1.0 / a.contenido_total, 2) END       AS precio_unitario
    FROM   observaciones o
    JOIN   v_ejecuciones_orden eo ON eo.id_ejecucion = o.id_ejecucion AND eo.orden = 1
    JOIN   anuncios  a ON a.id_anuncio  = o.id_anuncio
    JOIN   comercios c ON c.id_comercio = a.id_comercio
    WHERE  a.incluido = 1",

  # Tres estados de disponibilidad en la ejecución más reciente de cada comercio.
  v_disponibilidad = "
    CREATE VIEW v_disponibilidad AS
    SELECT c.nombre AS comercio, a.id_anuncio, a.sku,
           a.nombre_original AS nombre, eo.id_ejecucion,
           CASE WHEN o.id_observacion IS NULL THEN 'no observado'
                WHEN o.disponible = 1         THEN 'disponible'
                ELSE 'agotado' END AS disponibilidad
    FROM   anuncios a
    JOIN   comercios c ON c.id_comercio = a.id_comercio
    JOIN   v_ejecuciones_orden eo ON eo.id_comercio = a.id_comercio AND eo.orden = 1
    LEFT JOIN observaciones o ON o.id_anuncio = a.id_anuncio
                             AND o.id_ejecucion = eo.id_ejecucion
    WHERE  a.incluido = 1",

  # Compara, por comercio, las dos ejecuciones más recientes (mismo anuncio,
  # mismo comercio).
  v_cambios_precio = "
    CREATE VIEW v_cambios_precio AS
    WITH par AS (
      SELECT id_comercio,
             MAX(CASE WHEN orden = 1 THEN id_ejecucion END) AS ej_act,
             MAX(CASE WHEN orden = 2 THEN id_ejecucion END) AS ej_ant
      FROM   v_ejecuciones_orden
      GROUP  BY id_comercio
    ),
    union_anuncios AS (
      SELECT DISTINCT p.id_comercio, p.ej_act, p.ej_ant, o.id_anuncio
      FROM   par p
      JOIN   observaciones o ON o.id_ejecucion IN (p.ej_act, p.ej_ant)
    )
    SELECT c.nombre AS comercio, a.id_anuncio, a.sku,
           a.nombre_original AS nombre, a.marca, a.url, a.id_comparable,
           ant.precio AS precio_anterior,
           act.precio AS precio_actual,
           act.precio - ant.precio AS cambio_cop,
           ROUND(100.0 * (act.precio - ant.precio) / ant.precio, 1) AS cambio_pct,
           CASE WHEN ant.id_observacion IS NULL THEN 'nuevo'
                WHEN act.id_observacion IS NULL THEN 'no observado'
                WHEN ant.precio IS NULL OR act.precio IS NULL THEN 'sin comparación'
                WHEN act.precio > ant.precio THEN 'subió'
                WHEN act.precio < ant.precio THEN 'bajó'
                ELSE 'igual' END AS tipo
    FROM   union_anuncios u
    JOIN   anuncios  a ON a.id_anuncio  = u.id_anuncio
    JOIN   comercios c ON c.id_comercio = u.id_comercio
    LEFT JOIN observaciones act ON act.id_anuncio = u.id_anuncio AND act.id_ejecucion = u.ej_act
    LEFT JOIN observaciones ant ON ant.id_anuncio = u.id_anuncio AND ant.id_ejecucion = u.ej_ant
    WHERE  a.incluido = 1",

  # Observaciones de los ocho productos comparables (con precio), una por
  # anuncio y día (la última de ese día).
  v_comparables = "
    CREATE VIEW v_comparables AS
    SELECT SUBSTR(o.fecha_hora_consulta, 1, 10) AS fecha,
           o.fecha_hora_consulta, o.id_ejecucion,
           p.id_comparable, p.nombre_comun AS producto,
           c.nombre AS comercio, a.sku, a.nombre_original, a.url,
           o.precio, o.precio_antes, o.es_promocion, o.disponible,
           a.contenido_total, a.unidad_normalizada,
           ROUND(o.precio * 1.0 / a.contenido_total, 2) AS precio_unitario
    FROM   observaciones o
    JOIN   anuncios              a ON a.id_anuncio    = o.id_anuncio
    JOIN   comercios             c ON c.id_comercio   = a.id_comercio
    JOIN   productos_comparables p ON p.id_comparable = a.id_comparable
    WHERE  o.precio IS NOT NULL AND a.contenido_total > 0
      AND  o.id_observacion IN (
             SELECT MAX(id_observacion) FROM observaciones
             GROUP BY id_anuncio, SUBSTR(fecha_hora_consulta, 1, 10))",

  # Histórico: todas las observaciones de anuncios incluidos, con las mismas
  # columnas que v_ultimo_precio (permite filtrar por fecha de captura).
  v_precios = "
    CREATE VIEW v_precios AS
    SELECT o.id_observacion, o.id_ejecucion, o.fecha_hora_consulta,
           SUBSTR(o.fecha_hora_consulta, 1, 10) AS fecha,
           c.nombre AS comercio,
           a.id_anuncio, a.sku,
           a.nombre_original AS nombre,
           a.marca, a.subcategoria, a.url, a.id_comparable,
           a.contenido_total, a.unidad_normalizada,
           o.precio, o.precio_antes, o.es_promocion,
           CASE WHEN o.disponible = 1 THEN 'disponible' ELSE 'agotado' END AS disponibilidad,
           CASE WHEN o.precio IS NOT NULL AND a.contenido_total > 0
                THEN ROUND(o.precio * 1.0 / a.contenido_total, 2) END       AS precio_unitario
    FROM   observaciones o
    JOIN   anuncios  a ON a.id_anuncio  = o.id_anuncio
    JOIN   comercios c ON c.id_comercio = a.id_comercio
    WHERE  a.incluido = 1",

  # Fecha de referencia: la más reciente con los 8 productos en los 3 comercios.
  v_referencia = "
    CREATE VIEW v_referencia AS
    SELECT MAX(fecha) AS fecha
    FROM (SELECT fecha FROM v_comparables
          GROUP BY fecha
          HAVING COUNT(*) >= 24 AND COUNT(DISTINCT comercio) = 3)"
)

INDICES_SQL <- c(
  "CREATE INDEX IF NOT EXISTS idx_anuncios_comercio     ON anuncios (id_comercio)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_subcategoria ON anuncios (subcategoria)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_marca        ON anuncios (marca)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_comparable   ON anuncios (id_comparable)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_incluido     ON anuncios (incluido)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_ean          ON anuncios (ean)",
  "CREATE INDEX IF NOT EXISTS idx_obs_ejecucion         ON observaciones (id_ejecucion)",
  "CREATE INDEX IF NOT EXISTS idx_obs_precio            ON observaciones (precio)",
  "CREATE INDEX IF NOT EXISTS idx_obs_promocion         ON observaciones (es_promocion)",
  "CREATE INDEX IF NOT EXISTS idx_ejec_comercio_fecha   ON ejecuciones (id_comercio, fecha_hora_inicio)",
  "CREATE INDEX IF NOT EXISTS idx_rechazadas_ejecucion  ON rechazadas (id_ejecucion)"
)

migrar_esquema <- function(con) {
  agregar_columna_si_falta(con, "anuncios", "contenido_total", "REAL")
  agregar_columna_si_falta(con, "anuncios", "unidad_normalizada", "TEXT")

  DBI::dbWithTransaction(con, {
    # Contenido total y unidad normalizada de las presentaciones comparables
    DBI::dbExecute(con, "
      UPDATE anuncios
      SET contenido_total    = contenido_valor,
          unidad_normalizada = CASE contenido_unidad
                                 WHEN 'mL'     THEN 'mL'
                                 WHEN 'g'      THEN 'g'
                                 WHEN 'm'      THEN 'm'
                                 WHEN 'unidad' THEN 'unidad'
                                 WHEN 'sobre'  THEN 'unidad'
                               END")
    for (s in INDICES_SQL) DBI::dbExecute(con, s)
    for (v in rev(names(VISTAS_SQL))) DBI::dbExecute(con, paste0("DROP VIEW IF EXISTS ", v))
    for (v in names(VISTAS_SQL)) DBI::dbExecute(con, VISTAS_SQL[[v]])
  })
  invisible(TRUE)
}

# Registra, una sola vez, las correcciones sobre lo ya entregado en el Taller 1.
corregir_historico <- function(con) {
  # 1. El campo `modo` de las seis ejecuciones históricas quedó en 'offline'
  #    porque se migró al reprocesar raw/; las seis fueron capturas en línea.
  h <- DBI::dbGetQuery(con, "
    SELECT id_ejecucion, modo FROM ejecuciones
    WHERE modo = 'offline' AND id_ejecucion IN (?, ?, ?, ?, ?, ?)",
    params = as.list(ids_historicos))
  for (i in seq_len(nrow(h))) {
    DBI::dbExecute(con, "UPDATE ejecuciones SET modo = 'online' WHERE id_ejecucion = ?",
                   params = list(h$id_ejecucion[i]))
    registrar_correccion(con, "ejecuciones", h$id_ejecucion[i], "modo", "offline", "online",
      "La captura original fue en línea; 'offline' era solo el modo del reprocesamiento al migrar el esquema")
  }
  # 2. El informe del Taller 1 mencionaba ejecuciones que no existen.
  ya <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM correcciones WHERE tabla = 'informe_taller_1'")$n
  if (ya == 0) {
    registrar_correccion(con, "informe_taller_1", "taller_1.qmd (Limitaciones)",
      "fechas de ejecución", "7 y 9 de octubre de 2026", "10 de octubre de 2026",
      "El texto citaba dos ejecuciones; la base y raw/ solo contienen la del 10 de octubre")
  }
  invisible(nrow(h))
}
