# esquema_taller2.R -- Taller 2, Minería de Datos
# Migración idempotente de la base del Taller 1: se puede ejecutar varias veces
# sin perder ni duplicar datos. Solo AGREGA tablas, columnas, índices y vistas
# (las vistas se recrean porque no guardan datos).
#
# Uso:  source("esquema_taller2.R"); migrar_esquema_t2("comparador_precios.sqlite")

suppressPackageStartupMessages({ library(DBI); library(RSQLite) })

SQL_TABLAS_T2 <- "
CREATE TABLE IF NOT EXISTS correcciones (
  correccion_id  INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha          TEXT NOT NULL,
  tabla          TEXT NOT NULL,
  registro_id    TEXT NOT NULL,
  campo          TEXT NOT NULL,
  valor_anterior TEXT,
  valor_nuevo    TEXT,
  motivo         TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
  rechazo_id          INTEGER PRIMARY KEY AUTOINCREMENT,
  ejecucion_id        TEXT NOT NULL,
  comercio            TEXT,
  product_id_comercio TEXT,
  sku                 TEXT,
  url                 TEXT,
  fecha_hora_consulta TEXT,
  precio_cop          REAL,
  motivo_rechazo      TEXT NOT NULL,
  fecha_registro      TEXT NOT NULL
)"

SQL_INDICES_T2 <- c(
  # unicidad: una sola observación por anuncio y ejecución
  "CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_anuncio_ejecucion ON observaciones(anuncio_id, ejecucion_id)",
  # columnas usadas en los filtros de la aplicación
  "CREATE INDEX IF NOT EXISTS idx_obs_comparable_ejec ON observaciones(comparable, ejecucion_id)",
  "CREATE INDEX IF NOT EXISTS idx_obs_precio          ON observaciones(precio_cop)",
  "CREATE INDEX IF NOT EXISTS idx_obs_fecha           ON observaciones(fecha_hora_consulta)",
  "CREATE INDEX IF NOT EXISTS idx_obs_promocion       ON observaciones(en_promocion)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_comercio   ON anuncios(comercio_id, incluido)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_marca      ON anuncios(marca_estandar)",
  "CREATE INDEX IF NOT EXISTS idx_anuncios_subcat     ON anuncios(subcategoria)",
  "CREATE INDEX IF NOT EXISTS idx_ejec_estado         ON ejecuciones(comercio_id, estado, fecha_hora_inicio)"
)

# ---- Vistas ------------------------------------------------------------------
# v_precios: toda observación vigente (no descartada) de un anuncio incluido, con
#   los campos que usa la aplicación. Base de las demás vistas.
# v_ultima_ejecucion: por comercio, la ejecución más reciente completa (parcial solo si nunca hubo una completa).
# v_ultimo_precio: v_precios restringida a la última ejecución de cada comercio.
# v_cambios_precio: compara cada observación con la anterior del MISMO anuncio.
# v_comparables: observaciones de los productos comparables, con precio unitario.
# v_disponibilidad: disponible / agotado / no_observado por anuncio y ejecución.
SQL_VISTAS_T2 <- c(
"DROP VIEW IF EXISTS v_precios",
"CREATE VIEW v_precios AS
SELECT o.observacion_id, o.anuncio_id, o.ejecucion_id, o.fecha_hora_consulta,
       c.nombre AS comercio, a.product_id_comercio, a.sku,
       a.nombre_original AS nombre, a.marca_estandar AS marca, a.marca_original,
       a.subcategoria, a.contenido_valor, a.contenido_unidad,
       a.producto_id, a.url, a.vendedor,
       a.nombre_original || ' ' || COALESCE(a.descripcion_original, '') AS texto_anuncio,
       o.precio_cop, o.precio_lista_cop, o.en_promocion, o.disponible,
       o.estado_disponibilidad, o.comparable,
       CASE WHEN o.precio_cop IS NOT NULL AND a.contenido_valor > 0
                 AND a.contenido_unidad IN ('ml','g','und')
            THEN o.precio_cop / a.contenido_valor END AS precio_unitario,
       CASE a.contenido_unidad WHEN 'ml' THEN 'mL' WHEN 'g' THEN 'g'
                               WHEN 'und' THEN 'unidad' END AS unidad_norm
FROM observaciones o
JOIN anuncios  a ON a.anuncio_id  = o.anuncio_id
JOIN comercios c ON c.comercio_id = a.comercio_id
WHERE o.descartada = 0 AND a.incluido = 1",

"DROP VIEW IF EXISTS v_ultima_ejecucion",
"CREATE VIEW v_ultima_ejecucion AS
-- Por comercio: la ejecución más reciente COMPLETA; solo si el comercio nunca tuvo una completa,
-- la más reciente parcial. Así una ejecución interrumpida o con pocos productos no reemplaza
-- a los precios de una ejecución completa.
SELECT e.comercio_id, c.nombre AS comercio, e.ejecucion_id, e.fecha_hora_inicio, e.estado
FROM ejecuciones e
JOIN comercios c ON c.comercio_id = e.comercio_id
WHERE e.estado IN ('completa','parcial')
  AND e.fecha_hora_inicio = (
    SELECT MAX(e2.fecha_hora_inicio) FROM ejecuciones e2
    WHERE e2.comercio_id = e.comercio_id
      AND e2.estado = CASE WHEN EXISTS (SELECT 1 FROM ejecuciones e3
                                        WHERE e3.comercio_id = e.comercio_id AND e3.estado = 'completa')
                           THEN 'completa' ELSE 'parcial' END)",

"DROP VIEW IF EXISTS v_ultimo_precio",
"CREATE VIEW v_ultimo_precio AS
SELECT p.* FROM v_precios p
JOIN v_ultima_ejecucion u ON u.comercio = p.comercio AND u.ejecucion_id = p.ejecucion_id",

"DROP VIEW IF EXISTS v_cambios_precio",
"CREATE VIEW v_cambios_precio AS
WITH x AS (
  SELECT anuncio_id, comercio, producto_id, nombre, marca, ejecucion_id,
         fecha_hora_consulta, precio_cop,
         LAG(precio_cop)          OVER w AS precio_anterior,
         LAG(ejecucion_id)        OVER w AS ejecucion_anterior,
         LAG(fecha_hora_consulta) OVER w AS fecha_anterior
  FROM v_precios
  WINDOW w AS (PARTITION BY anuncio_id ORDER BY fecha_hora_consulta)
)
SELECT anuncio_id, comercio, producto_id, nombre, marca,
       ejecucion_anterior, fecha_anterior, ejecucion_id AS ejecucion_actual,
       fecha_hora_consulta AS fecha_actual, precio_anterior, precio_cop AS precio_actual,
       precio_cop - precio_anterior AS variacion_cop,
       100.0 * (precio_cop - precio_anterior) / precio_anterior AS variacion_pct
FROM x
WHERE precio_cop IS NOT NULL AND precio_anterior IS NOT NULL
  AND precio_cop <> precio_anterior",

"DROP VIEW IF EXISTS v_comparables",
"CREATE VIEW v_comparables AS
SELECT ejecucion_id, fecha_hora_consulta, comercio, p.producto_id,
       pr.producto_estandar, pr.marca_estandar, pr.subcategoria,
       pr.contenido, pr.unidad, precio_cop, precio_lista_cop, en_promocion,
       vendedor, url, nombre AS nombre_original,
       estado_disponibilidad,
       precio_cop / pr.contenido AS precio_unitario,
       CASE pr.unidad WHEN 'ml' THEN 'mL' WHEN 'g' THEN 'g' WHEN 'und' THEN 'unidad' END AS unidad_norm,
       pr.principal
FROM v_precios p
JOIN productos pr ON pr.producto_id = p.producto_id
WHERE p.comparable = 1",

"DROP VIEW IF EXISTS v_disponibilidad",
"CREATE VIEW v_disponibilidad AS
WITH primera AS (
  SELECT anuncio_id, MIN(fecha_hora_consulta) AS f0 FROM observaciones GROUP BY anuncio_id
), ej AS (
  SELECT e.ejecucion_id, e.comercio_id, e.fecha_hora_inicio
  FROM ejecuciones e WHERE e.estado IN ('completa','parcial')
)
SELECT a.anuncio_id, c.nombre AS comercio, a.nombre_original AS nombre, a.producto_id,
       ej.ejecucion_id, ej.fecha_hora_inicio,
       CASE WHEN o.observacion_id IS NULL THEN 'no_observado'
            ELSE COALESCE(o.estado_disponibilidad,
                          CASE WHEN o.disponible = 1 THEN 'disponible' ELSE 'agotado' END)
       END AS estado
FROM anuncios a
JOIN comercios c ON c.comercio_id = a.comercio_id
JOIN primera pr  ON pr.anuncio_id = a.anuncio_id
JOIN ej          ON ej.comercio_id = a.comercio_id
                AND ej.fecha_hora_inicio >= SUBSTR(pr.f0, 1, 10)
LEFT JOIN observaciones o ON o.anuncio_id = a.anuncio_id AND o.ejecucion_id = ej.ejecucion_id
WHERE a.incluido = 1"
)

tiene_columna <- function(con, tabla, columna)
  columna %in% dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tabla))$name

aplicar_migracion_t2 <- function(con) {
  dbExecute(con, "PRAGMA foreign_keys = ON")
  dbWithTransaction(con, {
    # columnas nuevas en observaciones (disponibilidad y descarte sin borrar)
    if (!tiene_columna(con, "observaciones", "estado_disponibilidad"))
      dbExecute(con, "ALTER TABLE observaciones ADD COLUMN estado_disponibilidad TEXT
                      CHECK (estado_disponibilidad IN ('disponible','agotado'))")
    if (!tiene_columna(con, "ejecuciones", "motivo"))      # por qué una ejecución quedó parcial o fallida
      dbExecute(con, "ALTER TABLE ejecuciones ADD COLUMN motivo TEXT")
    if (!tiene_columna(con, "observaciones", "descartada"))
      dbExecute(con, "ALTER TABLE observaciones ADD COLUMN descartada INTEGER NOT NULL DEFAULT 0")
    # lo que el sitio indicó: disponible si AvailableQuantity > 0, agotado si no
    dbExecute(con, "UPDATE observaciones SET estado_disponibilidad =
                    CASE WHEN disponible = 1 THEN 'disponible' ELSE 'agotado' END
                    WHERE estado_disponibilidad IS NULL AND disponible IS NOT NULL")
    for (s in trimws(strsplit(SQL_TABLAS_T2, ";")[[1]])) if (nzchar(s)) dbExecute(con, s)
    for (s in SQL_INDICES_T2) dbExecute(con, s)
    for (s in SQL_VISTAS_T2)  dbExecute(con, s)
  })
  invisible(TRUE)
}

migrar_esquema_t2 <- function(ruta_db = "comparador_precios.sqlite") {
  con <- dbConnect(SQLite(), ruta_db)
  on.exit(dbDisconnect(con))
  aplicar_migracion_t2(con)
  invisible(ruta_db)
}

# Registro de una corrección (nunca se borra la observación original)
registrar_correccion <- function(ruta_db, tabla, registro_id, campo,
                                 valor_anterior, valor_nuevo, motivo) {
  con <- dbConnect(SQLite(), ruta_db); on.exit(dbDisconnect(con))
  dbExecute(con, "INSERT INTO correcciones (fecha, tabla, registro_id, campo,
                    valor_anterior, valor_nuevo, motivo) VALUES (?,?,?,?,?,?,?)",
            params = list(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota"),
                          tabla, as.character(registro_id), campo,
                          as.character(valor_anterior), as.character(valor_nuevo), motivo))
}
