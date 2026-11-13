-- =============================================================================
-- consultas.sql · Consultas SQL del Taller 1 (SQLite)
-- Vistas temporales creadas por helpers.R::crear_vistas() (corrida más reciente):
--   v_categoria   : toda la categoría (precio > 0), con id_corrida y volumen_ml
--   v_comparables : solo comparable = 1 con id_producto_comun
-- Tablas base: observaciones, ejecuciones, descartes, cobertura_sitio, correcciones, productos_comunes.
-- =============================================================================

-- 1. ¿Cuántos comercios, productos y observaciones contiene la base?

SELECT
  comercio,
  COUNT(DISTINCT sku_comercio) AS productos_unicos,
  COUNT(*) AS total_observaciones,
  SUM(CASE WHEN comparable = 1 THEN 1 ELSE 0 END) AS obs_comparables
FROM observaciones
GROUP BY comercio

UNION ALL

SELECT
  'TOTAL BASE' AS comercio,
  COUNT(DISTINCT comercio || '|' || sku_comercio) AS productos_unicos,
  COUNT(*) AS total_observaciones,
  SUM(CASE WHEN comparable = 1 THEN 1 ELSE 0 END) AS obs_comparables
FROM observaciones;

-- 2. ¿Hay al menos 24 observaciones comparables en una misma ejecución y registros repetidos?

SELECT e.id_corrida,
  COUNT(DISTINCT o.comercio) AS comercios_activos,
  COUNT(DISTINCT o.id_producto_comun) AS presentaciones_comparables,
  COUNT(*) AS total_obs_comparables,
  COUNT(*) - COUNT(DISTINCT o.comercio || '|' || o.sku_comercio) AS registros_repetidos,
  CASE WHEN COUNT(*) >= 24 THEN 'CUMPLE (>= 24)' ELSE 'INSUFICIENTE' END AS evaluacion_cobertura
FROM observaciones o JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
WHERE o.comparable = 1
GROUP BY e.id_corrida;

-- 3. Precio mínimo, máximo y promedio por presentación (con empates)

WITH estadisticas AS (
  SELECT id_producto_comun,
    MIN(precio_cop) AS precio_min,
    MAX(precio_cop) AS precio_max,
    ROUND(AVG(precio_cop), 0) AS precio_promedio
  FROM v_comparables
  GROUP BY id_producto_comun
)
SELECT e.id_producto_comun, e.precio_min, e.precio_max, e.precio_promedio,
  GROUP_CONCAT(c.comercio, ' | ') AS comercio_menor_precio
FROM estadisticas e
JOIN v_comparables c
  ON e.id_producto_comun = c.id_producto_comun AND e.precio_min = c.precio_cop
GROUP BY e.id_producto_comun, e.precio_min, e.precio_max, e.precio_promedio
ORDER BY e.id_producto_comun;

-- 4. Ahorro en COP y en porcentaje al elegir la oferta más económica (Pmax - Pmin; % sobre Pmax)

SELECT id_producto_comun,
  MIN(precio_cop) AS precio_minimo,
  MAX(precio_cop) AS precio_maximo,
  (MAX(precio_cop) - MIN(precio_cop)) AS ahorro_cop,
  ROUND(((MAX(precio_cop) - MIN(precio_cop)) * 100.0 / MAX(precio_cop)), 2) AS ahorro_porcentaje
FROM v_comparables
GROUP BY id_producto_comun
ORDER BY ahorro_porcentaje DESC;

-- 5. Menor precio por litro entre tamaños comparables de una misma marca y variante
--    (solo familias con >= 2 tamaños; en empates de COP/L se muestra un comercio)

WITH t AS (
  SELECT p.marca, p.subcategoria, p.variante, v.id_producto_comun,
         v.contenido_total_ml AS volumen_ml, v.unidades, v.comercio, v.precio_cop,
         ROUND(v.precio_por_litro, 0) AS cop_por_litro,
         ROW_NUMBER() OVER (PARTITION BY v.id_producto_comun ORDER BY v.precio_por_litro) AS pos
  FROM v_comparables v
  JOIN productos_comunes p ON p.id_producto_comun = v.id_producto_comun AND p.id_corrida = v.id_corrida
), m AS (
  SELECT * FROM t WHERE pos = 1
), g AS (
  SELECT *,
    COUNT(*) OVER (PARTITION BY marca, subcategoria, variante) AS n_tamanos,
    RANK() OVER (PARTITION BY marca, subcategoria, variante ORDER BY cop_por_litro) AS ranking_cop_litro
  FROM m
)
SELECT marca, subcategoria, variante, id_producto_comun, volumen_ml, unidades,
       comercio AS comercio_mas_barato, precio_cop, cop_por_litro, ranking_cop_litro
FROM g
WHERE n_tamanos >= 2
ORDER BY marca, variante, cop_por_litro;

-- 6. Mayores diferencias de precio entre comercios (ordenadas por ahorro porcentual)

SELECT c.id_producto_comun,
  COUNT(DISTINCT c.comercio) AS num_comercios,
  MIN(c.precio_cop) AS precio_minimo,
  MAX(c.precio_cop) AS precio_maximo,
  (MAX(c.precio_cop) - MIN(c.precio_cop)) AS brecha_cop,
  ROUND((MAX(c.precio_cop) - MIN(c.precio_cop)) * 100.0 / MAX(c.precio_cop), 2) AS ahorro_pct,
  ROUND((MAX(c.precio_cop) - MIN(c.precio_cop)) * 100.0 / MIN(c.precio_cop), 2) AS sobreprecio_relativo_pct,
  (SELECT c2.comercio FROM v_comparables c2 WHERE c2.id_producto_comun = c.id_producto_comun
   ORDER BY c2.precio_cop DESC LIMIT 1) AS comercio_mas_caro
FROM v_comparables c
GROUP BY c.id_producto_comun
HAVING num_comercios >= 3
ORDER BY ahorro_pct DESC;

-- 7. Datos faltantes o inconsistentes que afectan la comparación

SELECT COUNT(*) AS total_observaciones_evaluadas,
  SUM(CASE WHEN precio_cop IS NULL OR precio_cop <= 0 THEN 1 ELSE 0 END) AS precios_invalidos_nulos,
  SUM(CASE WHEN contenido_total_ml IS NULL OR contenido_total_ml <= 0 THEN 1 ELSE 0 END) AS contenido_faltante,
  SUM(CASE WHEN unidad_medida IS NULL OR unidad_medida = '' THEN 1 ELSE 0 END) AS unidad_faltante,
  SUM(CASE WHEN marca_estandarizada IS NULL THEN 1 ELSE 0 END) AS marca_no_identificada,
  SUM(CASE WHEN sku_comercio IS NULL OR sku_comercio = '' THEN 1 ELSE 0 END) AS sku_faltante,
  SUM(CASE WHEN disponibilidad = 'no_observado' THEN 1 ELSE 0 END) AS disponibilidad_no_observada
FROM v_categoria;

-- 8. Tamaño de la oferta por comercio y ejecución, y calidad de la descripción

SELECT e.id_corrida, MIN(e.fecha_inicio) AS fecha_inicio, o.comercio,
  COUNT(*) AS total_productos_extraidos,
  ROUND(SUM(CASE WHEN o.texto_original_anuncio IS NOT NULL AND LENGTH(o.texto_original_anuncio) > 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_con_descripcion,
  ROUND(SUM(CASE WHEN o.marca_estandarizada IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_con_marca,
  ROUND(SUM(CASE WHEN o.contenido_total_ml > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_con_contenido
FROM ejecuciones e JOIN observaciones o ON e.id_ejecucion = o.id_ejecucion
GROUP BY e.id_corrida, o.comercio
ORDER BY e.id_corrida DESC, total_productos_extraidos DESC;