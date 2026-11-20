-- =============================================================================
-- Consultas SQL del Taller Parcial 1
-- Comparador de precios de confitería: Éxito, Carulla y Jumbo
--
-- Cada consulta usa un marcador ? para el id_ejecucion. Desde R se ejecuta con
--   dbGetQuery(con, sql, params = list(id_ejecucion))
-- o se reemplaza ? por el id de la ejecución que se quiera analizar.
--
-- Las consultas están ocultas en la presentación compilada; este archivo las
-- conserva para la revisión técnica.
-- =============================================================================

-- Pregunta 1. ¿Cuántos comercios, productos y observaciones hay?
WITH e AS (SELECT ? AS id)
SELECT
  (SELECT COUNT(*) FROM comercios) AS comercios,
  (SELECT COUNT(*) FROM observaciones, e WHERE id_ejecucion = e.id) AS observaciones,
  (SELECT COUNT(DISTINCT id_comercio) FROM observaciones, e WHERE id_ejecucion = e.id) AS comercios_con_datos,
  (SELECT COUNT(*) FROM observaciones, e WHERE id_ejecucion = e.id AND es_comparable = 1) AS observaciones_comparables,
  (SELECT COUNT(DISTINCT id_producto_comun) FROM observaciones, e
    WHERE id_ejecucion = e.id AND es_comparable = 1) AS productos_comparables;

-- Pregunta 1b. Aporte de cada comercio a la base.
SELECT c.nombre AS comercio,
       COUNT(o.id_observacion) AS observaciones,
       SUM(CASE WHEN o.es_comparable = 1 THEN 1 ELSE 0 END) AS comparables,
       COUNT(DISTINCT o.subcategoria) AS subcategorias
  FROM comercios c
  LEFT JOIN observaciones o
    ON o.id_comercio = c.id_comercio AND o.id_ejecucion = ?
 GROUP BY c.nombre
 ORDER BY observaciones DESC;

-- Pregunta 2. ¿Se alcanzan 24 observaciones comparables y hay duplicados?
WITH e AS (SELECT ? AS id),
comparables AS (
  SELECT o.id_producto_comun,
         COUNT(DISTINCT o.id_comercio) AS n_comercios,
         COUNT(*) AS n_obs
    FROM observaciones o, e
   WHERE o.id_ejecucion = e.id AND o.es_comparable = 1 AND o.disponible = 1
   GROUP BY o.id_producto_comun
)
SELECT COUNT(*) AS productos_comparables,
       SUM(CASE WHEN n_comercios = 3 THEN 1 ELSE 0 END) AS productos_con_tres_comercios,
       SUM(n_obs) AS observaciones_comparables,
       MIN(n_comercios) AS minimo_comercios,
       MAX(n_comercios) AS maximo_comercios
  FROM comparables;

-- Pregunta 2b. Duplicados del mismo SKU en la ejecución.
WITH e AS (SELECT ? AS id)
SELECT COUNT(*) AS duplicados
  FROM (
    SELECT id_comercio, sku_comercio
      FROM observaciones, e
     WHERE id_ejecucion = e.id
     GROUP BY id_comercio, sku_comercio
    HAVING COUNT(*) > 1
  );

-- Pregunta 3. Precio mínimo, máximo, promedio y comercio más barato (con empates).
WITH e AS (SELECT ? AS id),
precios AS (
  SELECT o.id_producto_comun, o.nombre_canonico, o.comercio, o.precio_cop,
         MIN(o.precio_cop) OVER (PARTITION BY o.id_producto_comun) AS precio_min,
         MAX(o.precio_cop) OVER (PARTITION BY o.id_producto_comun) AS precio_max,
         AVG(o.precio_cop) OVER (PARTITION BY o.id_producto_comun) AS precio_prom,
         RANK() OVER (PARTITION BY o.id_producto_comun ORDER BY o.precio_cop) AS rk
    FROM v_observaciones o, e
   WHERE o.id_ejecucion = e.id AND o.es_comparable = 1 AND o.disponible = 1
)
SELECT id_producto_comun, nombre_canonico,
       MIN(precio_min) AS precio_min,
       MAX(precio_max) AS precio_max,
       ROUND(AVG(precio_prom), 0) AS precio_prom,
       GROUP_CONCAT(DISTINCT CASE WHEN rk = 1 THEN comercio END) AS comercios_mas_baratos
  FROM precios
 GROUP BY id_producto_comun, nombre_canonico
 ORDER BY id_producto_comun;

-- Pregunta 4. Ahorro en COP y en porcentaje.
WITH e AS (SELECT ? AS id)
SELECT id_producto_comun, nombre_canonico,
       MIN(precio_cop) AS precio_min,
       MAX(precio_cop) AS precio_max,
       MAX(precio_cop) - MIN(precio_cop) AS ahorro_cop,
       ROUND(100.0 * (MAX(precio_cop) - MIN(precio_cop)) / MAX(precio_cop), 1) AS ahorro_pct
  FROM v_observaciones, e
 WHERE id_ejecucion = e.id AND es_comparable = 1 AND disponible = 1
 GROUP BY id_producto_comun, nombre_canonico
 ORDER BY ahorro_pct DESC;

-- Pregunta 5. Precio por 100 g en las presentaciones comparables.
WITH e AS (SELECT ? AS id),
base AS (
  SELECT o.*,
         CASE
           WHEN o.id_producto_comun IN ('CONF_01_CORONA_TRAD_200G', 'CONF_02_CORONA_TRAD_450G') THEN 'Corona tradicional'
           WHEN o.id_producto_comun IN ('CONF_09_MILLOWS_75G', 'CONF_10_MILLOWS_300G') THEN 'Millows original'
           ELSE o.nombre_canonico
         END AS producto_base,
         o.precio_cop / o.contenido_valor * 100 AS precio_100g
    FROM v_observaciones o, e
   WHERE o.id_ejecucion = e.id
     AND o.es_comparable = 1 AND o.disponible = 1
     AND o.contenido_unidad = 'g' AND o.contenido_valor > 0
)
SELECT producto_base, nombre_canonico, comercio, contenido_valor,
       precio_cop, ROUND(precio_100g, 1) AS precio_100g,
       RANK() OVER (PARTITION BY producto_base ORDER BY precio_100g) AS rk
  FROM base
 ORDER BY producto_base, precio_100g;

-- Pregunta 6. Mayores diferencias de precio entre comercios.
WITH e AS (SELECT ? AS id)
SELECT id_producto_comun, nombre_canonico,
       MIN(precio_cop) AS precio_min,
       MAX(precio_cop) AS precio_max,
       MAX(precio_cop) - MIN(precio_cop) AS diferencia_cop,
       ROUND(100.0 * (MAX(precio_cop) - MIN(precio_cop)) / MAX(precio_cop), 1) AS diferencia_pct
  FROM v_observaciones, e
 WHERE id_ejecucion = e.id AND es_comparable = 1 AND disponible = 1
 GROUP BY id_producto_comun, nombre_canonico
 ORDER BY diferencia_cop DESC;

-- Pregunta 7a. Faltantes en el catálogo completo.
WITH e AS (SELECT ? AS id)
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN precio_cop IS NULL THEN 1 ELSE 0 END) AS sin_precio,
  SUM(CASE WHEN contenido_valor IS NULL THEN 1 ELSE 0 END) AS sin_contenido,
  SUM(CASE WHEN marca IS NULL OR TRIM(marca) = '' THEN 1 ELSE 0 END) AS sin_marca,
  SUM(CASE WHEN descripcion_original IS NULL OR TRIM(descripcion_original) = '' THEN 1 ELSE 0 END) AS sin_descripcion,
  SUM(CASE WHEN url_producto IS NULL OR TRIM(url_producto) = '' THEN 1 ELSE 0 END) AS sin_url
  FROM observaciones, e
 WHERE id_ejecucion = e.id;

-- Pregunta 7b. Faltantes en la canasta comparable.
WITH e AS (SELECT ? AS id)
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN precio_cop IS NULL THEN 1 ELSE 0 END) AS sin_precio,
  SUM(CASE WHEN contenido_valor IS NULL THEN 1 ELSE 0 END) AS sin_contenido,
  SUM(CASE WHEN marca IS NULL OR TRIM(marca) = '' THEN 1 ELSE 0 END) AS sin_marca,
  SUM(CASE WHEN url_producto IS NULL OR TRIM(url_producto) = '' THEN 1 ELSE 0 END) AS sin_url
  FROM observaciones, e
 WHERE id_ejecucion = e.id AND es_comparable = 1;

-- Pregunta 8. Cobertura y calidad por comercio.
WITH e AS (SELECT ? AS id)
SELECT c.nombre AS comercio,
       ec.n_reportado_sitio AS reportados,
       ec.n_extraido AS extraidos,
       ec.n_incluido AS incluidos,
       ec.n_con_precio AS con_precio,
       ROUND(100.0 * ec.n_con_precio / NULLIF(ec.n_incluido, 0), 1) AS pct_con_precio,
       ROUND(100.0 * SUM(CASE WHEN o.marca IS NOT NULL AND TRIM(o.marca) <> '' THEN 1 ELSE 0 END) / COUNT(o.id_observacion), 1) AS pct_marca,
       ROUND(100.0 * SUM(CASE WHEN o.contenido_valor IS NOT NULL THEN 1 ELSE 0 END) / COUNT(o.id_observacion), 1) AS pct_contenido,
       ROUND(100.0 * SUM(CASE WHEN o.descripcion_original IS NOT NULL AND TRIM(o.descripcion_original) <> '' THEN 1 ELSE 0 END) / COUNT(o.id_observacion), 1) AS pct_descripcion
  FROM ejecuciones_comercio ec
  JOIN comercios c ON c.id_comercio = ec.id_comercio
  JOIN e ON ec.id_ejecucion = e.id
  JOIN observaciones o ON o.id_comercio = ec.id_comercio AND o.id_ejecucion = ec.id_ejecucion
 WHERE ec.id_ejecucion = e.id
 GROUP BY c.nombre, ec.n_reportado_sitio, ec.n_extraido, ec.n_incluido, ec.n_con_precio
 ORDER BY incluidos DESC;

