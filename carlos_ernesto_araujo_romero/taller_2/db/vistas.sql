-- =============================================================================
-- Vistas de la base del comparador (Taller 2).
-- La aplicación consulta directamente v_ultimo_precio, v_cambios_precio,
-- v_comparables, v_disponibilidad, v_ahorro_presentacion y v_resumen_ejecucion.
-- Se recrean en cada apertura para que una actualización del código no deje
-- definiciones antiguas en la base.
-- =============================================================================

DROP VIEW IF EXISTS v_observaciones;
CREATE VIEW v_observaciones AS
SELECT
  o.id_observacion,
  o.id_ejecucion,
  o.id_comercio,
  c.nombre AS comercio,
  o.id_producto_comun,
  p.nombre_canonico,
  p.marca AS marca_canonica,
  o.marca,
  o.subcategoria,
  o.texto_original,
  o.contenido_valor,
  o.contenido_unidad,
  o.contenido_total,
  o.unidad_normalizada,
  o.precio_cop,
  o.precio_lista_cop,
  o.es_promocion,
  o.descuento_pct,
  o.disponible,
  o.estado_disponibilidad,
  o.precio_por_unidad,
  o.unidad_precio,
  o.url_producto,
  o.fecha_consulta,
  o.es_comparable
FROM observaciones o
JOIN comercios c ON c.id_comercio = o.id_comercio
LEFT JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun;

-- Catálogo canónico con la cobertura de correspondencia por comercio.
DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT
  p.id_producto_comun,
  p.nombre_canonico,
  p.marca,
  p.variante,
  p.contenido_total,
  p.unidad_normalizada,
  p.subcategoria,
  p.justificacion,
  p.vigente,
  COUNT(DISTINCT m.id_comercio) AS n_comercios_mapeados,
  GROUP_CONCAT(DISTINCT m.id_comercio) AS comercios_mapeados
FROM productos_comparables p
LEFT JOIN mapeo_productos m ON m.id_producto_comun = p.id_producto_comun
GROUP BY p.id_producto_comun;

-- Última observación de cada anuncio (comercio + SKU), sin importar la ejecución.
DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
SELECT
  u.id_observacion, u.id_ejecucion, u.id_comercio, c.nombre AS comercio,
  u.sku_comercio, u.id_producto_comun, p.nombre_canonico,
  u.texto_original, u.marca, u.subcategoria,
  u.contenido_total, u.unidad_normalizada,
  u.precio_cop, u.precio_lista_cop, u.es_promocion, u.descuento_pct,
  u.disponible, u.estado_disponibilidad,
  u.precio_por_unidad, u.unidad_precio, u.url_producto,
  u.fecha_consulta, u.es_comparable
FROM (
  SELECT o.*,
         ROW_NUMBER() OVER (
           PARTITION BY o.id_comercio, o.sku_comercio
           ORDER BY o.fecha_consulta DESC, o.id_observacion DESC
         ) AS rn
  FROM observaciones o
) u
JOIN comercios c ON c.id_comercio = u.id_comercio
LEFT JOIN productos_comparables p ON p.id_producto_comun = u.id_producto_comun
WHERE u.rn = 1;

-- Cambios de precio entre dos ejecuciones cualesquiera, para el mismo anuncio
-- (mismo comercio y mismo SKU). La aplicación filtra el par de ejecuciones.
DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
SELECT
  ea.id_ejecucion AS ejecucion_anterior,
  eb.id_ejecucion AS ejecucion_actual,
  a.id_comercio,
  c.nombre AS comercio,
  a.sku_comercio,
  a.id_producto_comun,
  p.nombre_canonico,
  a.texto_original,
  a.precio_cop AS precio_anterior,
  b.precio_cop AS precio_actual,
  b.precio_cop - a.precio_cop AS cambio_cop,
  ROUND(100.0 * (b.precio_cop - a.precio_cop) / a.precio_cop, 2) AS cambio_pct,
  a.fecha_consulta AS fecha_anterior,
  b.fecha_consulta AS fecha_actual
FROM ejecuciones ea
JOIN ejecuciones eb ON eb.fecha_inicio > ea.fecha_inicio
JOIN observaciones a ON a.id_ejecucion = ea.id_ejecucion
JOIN observaciones b
  ON b.id_ejecucion = eb.id_ejecucion
 AND b.id_comercio = a.id_comercio
 AND b.sku_comercio = a.sku_comercio
JOIN comercios c ON c.id_comercio = a.id_comercio
LEFT JOIN productos_comparables p ON p.id_producto_comun = a.id_producto_comun
WHERE a.precio_cop IS NOT NULL
  AND b.precio_cop IS NOT NULL
  AND ea.estado IN ('completa', 'parcial')
  AND eb.estado IN ('completa', 'parcial');

-- Disponibilidad en los tres estados exigidos: disponible, agotado según el
-- sitio y no observado en la ejecución. Cruza ejecuciones, comercios y
-- presentaciones comparables.
DROP VIEW IF EXISTS v_disponibilidad;
CREATE VIEW v_disponibilidad AS
SELECT
  e.id_ejecucion,
  e.fecha_inicio,
  c.id_comercio,
  c.nombre AS comercio,
  c.activo AS comercio_activo,
  p.id_producto_comun,
  p.nombre_canonico,
  COALESCE(o.estado_disponibilidad, 'no_observado') AS estado,
  o.precio_cop,
  o.fecha_consulta
FROM ejecuciones e
CROSS JOIN comercios c
CROSS JOIN productos_comparables p
LEFT JOIN observaciones o
  ON o.id_ejecucion = e.id_ejecucion
 AND o.id_comercio = c.id_comercio
 AND o.id_producto_comun = p.id_producto_comun
 AND o.es_comparable = 1
WHERE e.estado IN ('completa', 'parcial');

-- Precio mínimo, máximo, promedio y ahorro por presentación y ejecución.
-- Incluye empates: la lista de comercios con el precio mínimo va separada por |.
DROP VIEW IF EXISTS v_ahorro_presentacion;
CREATE VIEW v_ahorro_presentacion AS
WITH precios AS (
  SELECT
    o.id_ejecucion,
    o.id_producto_comun,
    o.id_comercio,
    c.nombre AS comercio,
    o.precio_cop,
    MIN(o.precio_cop) OVER (PARTITION BY o.id_ejecucion, o.id_producto_comun) AS precio_min,
    MAX(o.precio_cop) OVER (PARTITION BY o.id_ejecucion, o.id_producto_comun) AS precio_max,
    AVG(o.precio_cop) OVER (PARTITION BY o.id_ejecucion, o.id_producto_comun) AS precio_promedio
  FROM observaciones o
  JOIN comercios c ON c.id_comercio = o.id_comercio
  WHERE o.es_comparable = 1
    AND o.precio_cop IS NOT NULL
    AND o.estado_disponibilidad = 'disponible'
)
SELECT
  pr.id_ejecucion,
  pr.id_producto_comun,
  p.nombre_canonico,
  p.marca,
  p.subcategoria,
  p.contenido_total,
  p.unidad_normalizada,
  COUNT(DISTINCT pr.id_comercio) AS n_comercios,
  pr.precio_min,
  pr.precio_max,
  ROUND(pr.precio_promedio, 2) AS precio_promedio,
  pr.precio_max - pr.precio_min AS ahorro_cop,
  CASE WHEN pr.precio_max > 0
       THEN ROUND(100.0 * (pr.precio_max - pr.precio_min) / pr.precio_max, 2)
       ELSE NULL END AS ahorro_pct,
  GROUP_CONCAT(DISTINCT CASE WHEN pr.precio_cop = pr.precio_min THEN pr.comercio END) AS comercios_min,
  GROUP_CONCAT(DISTINCT CASE WHEN pr.precio_cop = pr.precio_max THEN pr.comercio END) AS comercios_max
FROM precios pr
JOIN productos_comparables p ON p.id_producto_comun = pr.id_producto_comun
GROUP BY pr.id_ejecucion, pr.id_producto_comun;

-- Precio por unidad de contenido de las presentaciones comparables.
DROP VIEW IF EXISTS v_precio_unitario;
CREATE VIEW v_precio_unitario AS
SELECT
  o.id_ejecucion,
  o.id_comercio,
  c.nombre AS comercio,
  o.id_producto_comun,
  p.nombre_canonico,
  p.subcategoria,
  p.contenido_total,
  p.unidad_normalizada,
  o.precio_cop,
  ROUND(o.precio_cop / p.contenido_total, 2) AS precio_por_unidad
FROM observaciones o
JOIN comercios c ON c.id_comercio = o.id_comercio
JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun
WHERE o.es_comparable = 1
  AND o.precio_cop IS NOT NULL
  AND o.estado_disponibilidad = 'disponible'
  AND p.contenido_total > 0
  AND p.unidad_normalizada IS NOT NULL;

-- Resumen de cada ejecución para los indicadores de la aplicación.
DROP VIEW IF EXISTS v_resumen_ejecucion;
CREATE VIEW v_resumen_ejecucion AS
SELECT
  e.id_ejecucion,
  e.fecha_inicio,
  e.fecha_fin,
  e.modo,
  e.estado,
  COUNT(DISTINCT o.id_comercio) AS n_comercios,
  COUNT(o.id_observacion) AS n_observaciones,
  SUM(CASE WHEN o.es_comparable = 1 THEN 1 ELSE 0 END) AS n_observaciones_comparables,
  COUNT(DISTINCT CASE WHEN o.es_comparable = 1 THEN o.id_producto_comun END) AS n_productos_comparables,
  SUM(CASE WHEN o.es_promocion = 1 THEN 1 ELSE 0 END) AS n_promociones,
  SUM(CASE WHEN o.estado_disponibilidad = 'disponible' THEN 1 ELSE 0 END) AS n_disponibles,
  SUM(CASE WHEN o.estado_disponibilidad = 'agotado' THEN 1 ELSE 0 END) AS n_agotados,
  MIN(o.fecha_consulta) AS primera_consulta,
  MAX(o.fecha_consulta) AS ultima_consulta
FROM ejecuciones e
LEFT JOIN observaciones o ON o.id_ejecucion = e.id_ejecucion
GROUP BY e.id_ejecucion;
