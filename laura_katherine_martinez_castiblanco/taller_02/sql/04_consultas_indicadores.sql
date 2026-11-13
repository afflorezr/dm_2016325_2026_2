-- =============================================================================
-- 04_consultas_indicadores.sql · Consultas independientes que reproducen cada
-- indicador de la app (requisito 14 del enunciado). Ejecutar sobre comparador_precios.sqlite.
-- Sustituya :corrida por un id_corrida (p. ej. el de SELECT MAX(id_corrida) FROM v_corridas).
-- =============================================================================

-- K1. Fecha y estado de la última corrida
SELECT id_corrida, fecha_hora, estado, n_obs FROM v_corridas ORDER BY id_corrida DESC LIMIT 1;

-- K2. Productos y observaciones por comercio (corrida)
SELECT comercio, COUNT(DISTINCT sku_comercio) AS productos, COUNT(*) AS observaciones
FROM v_obs_validas WHERE id_corrida = :corrida GROUP BY comercio;

-- K3. Proporción de productos en promoción por comercio (%)
SELECT comercio, ROUND(100.0 * SUM(es_promocion = 1) / COUNT(*), 1) AS pct_promocion
FROM v_obs_validas WHERE id_corrida = :corrida GROUP BY comercio;

-- K4. Precio por litro: mediana por subcategoría (COP/L)
WITH r AS (
  SELECT subcategoria, precio_por_l,
         ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio_por_l) AS rn,
         COUNT(*)     OVER (PARTITION BY subcategoria) AS n
  FROM v_obs_validas WHERE id_corrida = :corrida AND precio_por_l IS NOT NULL)
SELECT subcategoria, ROUND(AVG(precio_por_l), 0) AS mediana_cop_por_l
FROM r WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY subcategoria;

-- K5. Ahorro máximo entre comercios (productos comparables, corrida)
SELECT etiqueta, MIN(precio_cop) AS minimo, MAX(precio_cop) AS maximo,
       MAX(precio_cop) - MIN(precio_cop) AS ahorro_cop,
       ROUND(100.0 * (MAX(precio_cop) - MIN(precio_cop)) / MAX(precio_cop), 2) AS ahorro_pct
FROM v_comparables WHERE id_corrida = :corrida
GROUP BY clave_producto, etiqueta ORDER BY ahorro_cop DESC LIMIT 1;

-- K6. Cambios de precio en la última corrida (sube / baja)
SELECT sentido, COUNT(*) AS n FROM v_cambios_precio
WHERE id_corrida = :corrida AND sentido IN ('sube', 'baja') GROUP BY sentido;

-- K7. Atípicos: precio por litro fuera de 1.5 * IQR dentro del comercio (se calcula en R con quantile();
--     aquí un criterio simple reproducible: más de 3 veces la mediana de su subcategoría)
-- (ver db.R :: db_atipicos)

-- G1. Serie de un producto comparable por comercio
SELECT fecha, comercio, precio_cop FROM v_historial_precios
WHERE clave_producto = :clave ORDER BY fecha, comercio;

-- G2. Precio por litro entre comercios (unidad única: COP/L)
SELECT comercio, ROUND(AVG(precio_por_l), 0) AS cop_por_l
FROM v_obs_validas WHERE id_corrida = :corrida AND unidad_base = 'mL' GROUP BY comercio;

-- C1. Costo de canasta por comercio (solo si tiene todos los productos de :claves)
--     Se evalúa en R (validacion.R :: calcular_canasta) sobre v_canasta_supermercado.
SELECT comercio, clave_producto, precio_cop, es_minimo FROM v_canasta_supermercado
WHERE id_corrida = :corrida;
