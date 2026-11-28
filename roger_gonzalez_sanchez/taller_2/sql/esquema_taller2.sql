-- Lo que el Taller 2 agrega a la base del Taller 1 (comparador_precios.sqlite).
-- Las tablas del Taller 1 (comercios, ejecuciones, productos_comunes,
-- observaciones) se crean con crear_esquema() de R/06_base_datos.R y no se tocan.
-- Las columnas nuevas de esas tablas las agrega db_inicializar() (db.R).
-- Este archivo lo ejecuta db_inicializar() cada vez que arranca la app:
-- las tablas e índices se crean solo si no existen y las vistas se recrean
-- (no guardan datos).

-- Correcciones a la base del Taller 1 (sección 3.2)
CREATE TABLE IF NOT EXISTS correcciones (
  id_correccion  INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha          TEXT NOT NULL,
  tabla          TEXT NOT NULL,
  id_registro    TEXT NOT NULL,
  campo          TEXT NOT NULL,
  valor_anterior TEXT,
  valor_nuevo    TEXT,
  motivo         TEXT NOT NULL
);

-- Observaciones que no pasaron la validación (sección 3.4)
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
  id_rechazo               INTEGER PRIMARY KEY AUTOINCREMENT,
  id_ejecucion             TEXT NOT NULL,
  comercio                 TEXT,
  sku_comercio             TEXT,
  producto_nombre_original TEXT,
  precio_cop               REAL,
  url_producto             TEXT,
  fecha_hora_consulta      TEXT,
  archivo_raw              TEXT,
  motivo                   TEXT NOT NULL,
  fecha_registro           TEXT NOT NULL
);

-- Índices para los filtros de la app (el Taller 1 ya tenía
-- ix_obs_ejecucion e ix_obs_comparable)
CREATE INDEX IF NOT EXISTS ix_obs_comercio     ON observaciones (comercio, id_ejecucion);
CREATE INDEX IF NOT EXISTS ix_obs_subcategoria ON observaciones (subcategoria_estandar);
CREATE INDEX IF NOT EXISTS ix_obs_marca        ON observaciones (marca_estandarizada);
CREATE INDEX IF NOT EXISTS ix_obs_precio       ON observaciones (precio_cop);
CREATE INDEX IF NOT EXISTS ix_obs_fecha        ON observaciones (fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS ix_rech_ejecucion   ON observaciones_rechazadas (id_ejecucion);

-- ===================== VISTAS =====================

-- Observaciones no descartadas con contenido normalizado y precio unitario.
-- unidad_normalizada: mL; g (también mg / 1000); unidad (tabletas, sobres, dosis).
DROP VIEW IF EXISTS v_observaciones;
CREATE VIEW v_observaciones AS
SELECT o.id_observacion, o.id_ejecucion, e.fecha_inicio AS fecha_ejecucion, e.modo,
       o.comercio, o.sku_comercio, o.producto_nombre_original, o.marca_estandarizada,
       o.subcategoria_estandar, o.presentacion_original, o.contenido_num, o.unidad_medida,
       CASE WHEN o.unidad_medida = 'mg' THEN o.contenido_num / 1000.0
            ELSE o.contenido_num END AS contenido_total,
       CASE WHEN o.unidad_medida = 'mL' THEN 'mL'
            WHEN o.unidad_medida IN ('g', 'mg') THEN 'g'
            WHEN o.unidad_medida IN ('unidad', 'sobres', 'dosis') THEN 'unidad' END AS unidad_normalizada,
       CASE WHEN o.contenido_num > 0 THEN
              o.precio_cop / (CASE WHEN o.unidad_medida = 'mg' THEN o.contenido_num / 1000.0
                                   ELSE o.contenido_num END)
       END AS precio_unitario,
       o.precio_cop, o.precio_regular_cop, o.es_promocion, o.disponible,
       CASE o.disponible WHEN 1 THEN 'disponible' WHEN 0 THEN 'agotado'
            ELSE 'sin_dato' END AS estado_disponibilidad,
       o.comparable, o.id_producto_comun, o.url_producto, o.descripcion_original,
       o.fecha_hora_consulta, o.archivo_raw
FROM observaciones o
JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
WHERE o.descartada = 0;

-- Último precio conocido de cada producto en cada comercio
DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
SELECT * FROM (
  SELECT v.*,
         ROW_NUMBER() OVER (PARTITION BY v.comercio, v.sku_comercio
                            ORDER BY v.fecha_hora_consulta DESC) AS orden
  FROM v_observaciones v
) WHERE orden = 1;

-- Cambios de precio de un producto frente a su observación anterior
DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
SELECT *,
       precio_actual - precio_anterior AS diferencia,
       ROUND(100.0 * (precio_actual - precio_anterior) / precio_anterior, 2) AS variacion_pct
FROM (
  SELECT v.id_ejecucion, v.fecha_ejecucion, v.comercio, v.sku_comercio,
         v.producto_nombre_original, v.marca_estandarizada, v.id_producto_comun,
         v.url_producto, v.fecha_hora_consulta,
         LAG(v.id_ejecucion) OVER w AS id_ejecucion_anterior,
         LAG(v.precio_cop) OVER w AS precio_anterior,
         v.precio_cop AS precio_actual
  FROM v_observaciones v
  WINDOW w AS (PARTITION BY v.comercio, v.sku_comercio ORDER BY v.fecha_hora_consulta)
)
WHERE precio_anterior IS NOT NULL AND precio_anterior <> precio_actual;

-- Los 8 comparables en cada comercio y ejecución, aunque no se hayan observado.
-- estado: disponible, agotado, sin_dato (el sitio no lo indica) o no_observado.
-- Una corrida sin conexión que no agregó nada no cuenta como ejecución.
DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT e.id_ejecucion, e.fecha_inicio AS fecha_ejecucion,
       p.id_producto_comun, p.descripcion AS comparable, e.comercio,
       o.id_observacion, o.sku_comercio, o.producto_nombre_original, o.marca_estandarizada,
       o.precio_cop, o.contenido_num, o.unidad_medida, o.contenido_total,
       o.unidad_normalizada, o.precio_unitario, o.es_promocion, o.url_producto,
       o.fecha_hora_consulta,
       CASE WHEN o.id_observacion IS NULL THEN 'no_observado'
            ELSE o.estado_disponibilidad END AS estado
FROM ejecuciones e
CROSS JOIN productos_comunes p
LEFT JOIN v_observaciones o
  ON o.id_ejecucion = e.id_ejecucion AND o.comercio = e.comercio
 AND o.comparable = 1 AND o.id_producto_comun = p.id_producto_comun
WHERE e.modo IS NOT 'offline'
   OR EXISTS (SELECT 1 FROM observaciones x
              WHERE x.id_ejecucion = e.id_ejecucion AND x.comercio = e.comercio);

-- Estado de cada producto ya conocido de un comercio en cada ejecución
-- (no_observado si no apareció; no significa agotado).
DROP VIEW IF EXISTS v_disponibilidad;
CREATE VIEW v_disponibilidad AS
WITH primera AS (
  SELECT o.comercio, o.sku_comercio, MIN(e.fecha_inicio) AS primera_vez
  FROM observaciones o
  JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
  WHERE o.descartada = 0
  GROUP BY o.comercio, o.sku_comercio
)
SELECT e.id_ejecucion, a.comercio, a.sku_comercio,
       CASE WHEN o.id_observacion IS NULL THEN 'no_observado'
            WHEN o.disponible = 1 THEN 'disponible'
            WHEN o.disponible = 0 THEN 'agotado'
            ELSE 'sin_dato' END AS estado
FROM ejecuciones e
JOIN primera a ON a.comercio = e.comercio AND a.primera_vez <= e.fecha_inicio
LEFT JOIN observaciones o
  ON o.id_ejecucion = e.id_ejecucion AND o.comercio = a.comercio
 AND o.sku_comercio = a.sku_comercio AND o.descartada = 0
WHERE e.modo IS NOT 'offline'
   OR EXISTS (SELECT 1 FROM observaciones x
              WHERE x.id_ejecucion = e.id_ejecucion AND x.comercio = e.comercio);

-- Una fila por ejecución (la tabla ejecuciones tiene una fila por comercio)
DROP VIEW IF EXISTS v_ejecuciones;
CREATE VIEW v_ejecuciones AS
SELECT e.id_ejecucion,
       MIN(e.fecha_inicio) AS fecha_inicio,
       MAX(e.modo) AS modo,
       CASE WHEN SUM(e.estado = 'COMPLETA') = COUNT(*) THEN 'COMPLETA'
            WHEN SUM(e.estado = 'FALLIDA') = COUNT(*) THEN 'FALLIDA'
            WHEN SUM(e.estado = 'EN_CURSO') > 0 THEN 'EN_CURSO'
            ELSE 'PARCIAL' END AS estado,
       COUNT(*) AS comercios_intentados,
       (SELECT COUNT(*) FROM observaciones o
        WHERE o.id_ejecucion = e.id_ejecucion AND o.descartada = 0) AS n_observaciones,
       (SELECT COUNT(DISTINCT o.comercio) FROM observaciones o
        WHERE o.id_ejecucion = e.id_ejecucion AND o.descartada = 0) AS n_comercios
FROM ejecuciones e
GROUP BY e.id_ejecucion;
