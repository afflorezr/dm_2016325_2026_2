-- migracion_t2.sql
-- Cambios a la base del Taller 1 para el Taller 2. Se corre una sola vez con
-- aplicar_migracion() de scraper.R (revisa antes si la tabla correcciones existe).
-- No borra nada: solo agrega tablas, columnas, índices y vistas.

-- ---- 1. Tablas nuevas ----

-- Cada corrección a un dato ya guardado queda registrada aquí.
CREATE TABLE IF NOT EXISTS correcciones (
  correccion_id   INTEGER PRIMARY KEY,
  fecha           TEXT    NOT NULL,
  tabla           TEXT    NOT NULL,
  registro_id     TEXT    NOT NULL,              -- llave del registro (p. ej. anuncio_id)
  campo           TEXT    NOT NULL,
  valor_anterior  TEXT,
  valor_nuevo     TEXT,
  motivo          TEXT    NOT NULL
);

-- Observaciones que no pasaron la validación y por eso no se insertaron.
CREATE TABLE IF NOT EXISTS rechazos (
  rechazo_id            INTEGER PRIMARY KEY,
  id_ejecucion          TEXT    NOT NULL,
  comercio_id           INTEGER NOT NULL REFERENCES comercios (comercio_id),
  id_producto_comercio  TEXT,
  nombre_original       TEXT,
  precio                REAL,
  regla                 TEXT    NOT NULL,        -- regla de validacion.R que falló
  fecha_hora_registro   TEXT    NOT NULL
);

-- Indicadores para saber si cada ejecución trajo la categoría completa.
-- Responde a la retroalimentación del Taller 1 (Falabella y Farmatodo no
-- muestran un total confiable).
CREATE TABLE IF NOT EXISTS controles_completitud (
  id_ejecucion  TEXT    NOT NULL,
  comercio_id   INTEGER NOT NULL,
  indicador     TEXT    NOT NULL,
  valor         REAL,
  descripcion   TEXT,
  PRIMARY KEY (id_ejecucion, comercio_id, indicador),
  FOREIGN KEY (id_ejecucion, comercio_id) REFERENCES ejecuciones (id_ejecucion, comercio_id)
);

-- ---- 2. Columnas nuevas ----

-- La disponibilidad se guarda en la columna disponible del Taller 1
-- (1 = disponible, 0 = agotado según el sitio, NULL = el sitio no lo dice).
-- "no observado" no se guarda: sale de la vista v_disponibilidad.

-- para descartar una observación sin borrarla
ALTER TABLE observaciones ADD COLUMN descartada INTEGER NOT NULL DEFAULT 0
  CHECK (descartada IN (0, 1));

-- Contenido total de la presentación y su unidad normalizada.
-- En perfumes siempre es mL; contenido_total = contenido_ml * unidades.
ALTER TABLE anuncios ADD COLUMN contenido_total REAL;
ALTER TABLE anuncios ADD COLUMN unidad_norm TEXT
  CHECK (unidad_norm IS NULL OR unidad_norm IN ('mL', 'g', 'unidad'));

UPDATE anuncios
   SET contenido_total = contenido_ml * COALESCE(unidades, 1),
       unidad_norm     = 'mL'
 WHERE contenido_ml IS NOT NULL;

-- ---- 3. Unicidad e índices ----

-- Un anuncio se observa una sola vez por ejecución.
CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_anuncio_ejecucion
  ON observaciones (anuncio_id, id_ejecucion);

-- columnas que usan los filtros de la aplicación
CREATE INDEX IF NOT EXISTS idx_obs_precio      ON observaciones (precio);
CREATE INDEX IF NOT EXISTS idx_obs_fecha       ON observaciones (fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS idx_obs_comparable  ON observaciones (comparable, id_ejecucion);
CREATE INDEX IF NOT EXISTS idx_anuncios_subcat ON anuncios (subcategoria_std);
CREATE INDEX IF NOT EXISTS idx_anuncios_marca  ON anuncios (marca_std);

-- ---- 4. Vistas ----

-- Ejecuciones con su fecha (una fila por ejecución, sin importar el comercio).
CREATE VIEW IF NOT EXISTS v_ejecuciones AS
SELECT id_ejecucion,
       MIN(substr(fecha_hora_inicio, 1, 10)) AS fecha,
       MIN(fecha_hora_inicio)                AS inicio,
       MAX(fecha_hora_fin)                   AS fin,
       SUM(estado = 'completa')              AS comercios_completos,
       COUNT(*)                              AS comercios
  FROM ejecuciones
 GROUP BY id_ejecucion;

-- Todas las observaciones válidas con los datos que muestra la aplicación.
CREATE VIEW IF NOT EXISTS v_precios AS
SELECT o.observacion_id,
       o.id_ejecucion,
       substr(o.fecha_hora_consulta, 1, 10) AS fecha,
       o.fecha_hora_consulta,
       c.comercio_id,
       c.nombre               AS comercio,
       a.anuncio_id,
       o.nombre_original,
       o.texto_original,
       a.marca_std            AS marca,
       a.subcategoria_std     AS subcategoria,
       a.concentracion_std    AS concentracion,
       a.contenido_total,
       a.unidad_norm,
       a.producto_id,
       o.precio,
       o.precio_antes,
       o.promocion,
       CASE o.disponible WHEN 1 THEN 'disponible'
                         WHEN 0 THEN 'agotado'
                         ELSE 'sin dato' END AS disponibilidad,
       o.comparable,
       a.url_producto
  FROM observaciones o
  JOIN comercios c ON c.comercio_id = o.comercio_id
  JOIN anuncios  a ON a.anuncio_id  = o.anuncio_id
 WHERE a.excluido = 0
   AND o.descartada = 0
   AND o.precio IS NOT NULL;

-- Precio de cada anuncio en la ejecución más reciente.
CREATE VIEW IF NOT EXISTS v_ultimo_precio AS
SELECT *
  FROM v_precios
 WHERE id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones);

-- Presentaciones comparables con su precio por mL.
CREATE VIEW IF NOT EXISTS v_comparables AS
SELECT v.*,
       p.marca || ' ' || p.linea || ' ' || p.concentracion || ' ' ||
         CAST(p.contenido AS INTEGER) || ' mL'            AS presentacion,
       ROUND(v.precio / v.contenido_total, 1)             AS precio_por_ml
  FROM v_precios v
  JOIN productos p ON p.producto_id = v.producto_id
 WHERE v.comparable = 1
   AND v.contenido_total > 0;

-- Cambio de precio de cada anuncio entre una ejecución y la anterior en que
-- se observó. Solo compara el mismo anuncio en el mismo comercio.
CREATE VIEW IF NOT EXISTS v_cambios_precio AS
SELECT *,
       precio - precio_anterior                                AS cambio_cop,
       ROUND(100.0 * (precio - precio_anterior) / precio_anterior, 1) AS cambio_pct
  FROM (
    SELECT v.*,
           LAG(v.id_ejecucion) OVER w AS ejecucion_anterior,
           LAG(v.precio)       OVER w AS precio_anterior
      FROM v_precios v
    WINDOW w AS (PARTITION BY v.anuncio_id ORDER BY v.id_ejecucion)
  )
 WHERE precio_anterior IS NOT NULL;

-- Las tres situaciones de disponibilidad por anuncio y ejecución:
-- disponible, agotado según el sitio y no observado en esa ejecución.
CREATE VIEW IF NOT EXISTS v_disponibilidad AS
SELECT a.anuncio_id,
       a.comercio_id,
       e.id_ejecucion,
       CASE
         WHEN o.observacion_id IS NULL THEN 'no observado'
         WHEN o.disponible = 1 THEN 'disponible'
         WHEN o.disponible = 0 THEN 'agotado'
         ELSE 'sin dato'
       END AS disponibilidad
  FROM anuncios a
  JOIN ejecuciones e ON e.comercio_id = a.comercio_id
  LEFT JOIN observaciones o
         ON o.anuncio_id = a.anuncio_id AND o.id_ejecucion = e.id_ejecucion
 WHERE a.excluido = 0;
