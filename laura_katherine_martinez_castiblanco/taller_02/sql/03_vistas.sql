-- =============================================================================
-- 03_vistas.sql · Vistas que la aplicación consume directamente
-- Se recrean (DROP + CREATE) para que la migración sea idempotente.
-- Regla de oro: el id_producto_comun cambia entre corridas; la identidad estable
-- de un producto comparable es clave_producto (marca|subcategoria|variante|ml|unidades).
-- =============================================================================
DROP VIEW IF EXISTS v_canasta_supermercado;
DROP VIEW IF EXISTS v_historial_precios;
DROP VIEW IF EXISTS v_productos_comparables;
DROP VIEW IF EXISTS v_comparables;
DROP VIEW IF EXISTS v_cambios_precio;
DROP VIEW IF EXISTS v_precios_actuales;
DROP VIEW IF EXISTS v_ultimo_precio;
DROP VIEW IF EXISTS v_obs_validas;
DROP VIEW IF EXISTS v_ejecuciones_resumen;
DROP VIEW IF EXISTS v_corridas;

-- Una fila por corrida (ejecución en línea de todos los comercios). Excluye reprocesos offline.
CREATE VIEW v_corridas AS
SELECT e.id_corrida,
       MIN(e.fecha_inicio)                    AS fecha_hora,
       SUBSTR(MIN(e.fecha_inicio), 1, 10)     AS fecha,
       COUNT(*)                               AS n_comercios,
       SUM(e.n_registros)                     AS n_obs,
       SUM(e.n_descartados)                   AS n_descartes,
       CASE WHEN SUM(e.estado = 'fallida') > 0 THEN 'fallida'
            WHEN SUM(e.estado = 'parcial') > 0 OR SUM(e.estado = 'en_curso') > 0 THEN 'parcial'
            ELSE 'completa' END               AS estado
FROM ejecuciones e
WHERE e.modo = 'online'
GROUP BY e.id_corrida;

-- Auditoría: lo registrado en ejecuciones vs. lo realmente guardado
CREATE VIEW v_ejecuciones_resumen AS
SELECT e.id_ejecucion, e.id_corrida, e.comercio, e.modo, e.estado, e.fecha_inicio, e.fecha_fin,
       e.n_registros AS registros_registrados,
       (SELECT COUNT(*) FROM observaciones o WHERE o.id_ejecucion = e.id_ejecucion) AS observaciones_reales,
       e.n_descartados, e.detalle
FROM ejecuciones e;

-- Observaciones vigentes (excluye las marcadas como descartadas a posteriori) + campos derivados
CREATE VIEW v_obs_validas AS
SELECT o.*,
       e.id_corrida,
       e.modo AS modo_ejecucion,
       o.contenido_total_ml AS volumen_ml,
       'mL' AS unidad_base,
       CASE WHEN o.contenido_total_ml > 0 THEN o.precio_cop / o.contenido_total_ml END AS precio_por_ml,
       CASE WHEN o.contenido_total_ml > 0 THEN o.precio_cop * 1000.0 / o.contenido_total_ml END AS precio_por_l
FROM observaciones o
JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
LEFT JOIN obs_descartadas d ON d.id_obs = o.id_obs
WHERE d.id_obs IS NULL;

-- Último precio observado de cada anuncio (comercio + SKU)
CREATE VIEW v_ultimo_precio AS
SELECT * FROM (
  SELECT v.*,
         ROW_NUMBER() OVER (PARTITION BY v.comercio, v.sku_comercio
                            ORDER BY v.fecha_hora_consulta DESC) AS rn,
         (v.id_corrida = (SELECT MAX(id_corrida) FROM v_corridas)) AS en_ultima_corrida
  FROM v_obs_validas v
) WHERE rn = 1;

-- Precios de la corrida más reciente (foto actual del mercado)
CREATE VIEW v_precios_actuales AS
SELECT * FROM v_obs_validas
WHERE id_corrida = (SELECT MAX(id_corrida) FROM v_corridas);

-- Cambio de precio de cada anuncio respecto a su observación anterior
CREATE VIEW v_cambios_precio AS
SELECT comercio, sku_comercio, producto_raw, id_ejecucion, id_corrida, fecha_hora_consulta, precio_cop,
       precio_anterior, fecha_anterior, id_corrida_anterior,
       precio_cop - precio_anterior AS delta_cop,
       CASE WHEN precio_anterior > 0 THEN 100.0 * (precio_cop - precio_anterior) / precio_anterior END AS delta_pct,
       CASE WHEN precio_anterior IS NULL THEN 'nuevo'
            WHEN precio_cop > precio_anterior THEN 'sube'
            WHEN precio_cop < precio_anterior THEN 'baja'
            ELSE 'igual' END AS sentido
FROM (
  SELECT comercio, sku_comercio, producto_raw, id_ejecucion, id_corrida, fecha_hora_consulta, precio_cop,
         LAG(precio_cop)           OVER w AS precio_anterior,
         LAG(fecha_hora_consulta)  OVER w AS fecha_anterior,
         LAG(id_corrida)           OVER w AS id_corrida_anterior
  FROM v_obs_validas
  WINDOW w AS (PARTITION BY comercio, sku_comercio ORDER BY fecha_hora_consulta)
);

-- Catálogo de productos comparables por corrida, con etiqueta legible
CREATE VIEW v_productos_comparables AS
SELECT pc.id_corrida, pc.id_producto_comun, pc.clave_producto, pc.marca, pc.subcategoria, pc.variante,
       pc.contenido_total_ml, pc.unidades, pc.n_comercios, pc.lista_comercios,
       pc.marca || ' ' || LOWER(REPLACE(pc.variante, '_', ' ')) || ' · ' ||
       CAST(CAST(pc.contenido_total_ml AS INTEGER) AS TEXT) || ' mL' ||
       CASE WHEN pc.unidades > 1 THEN ' (' || pc.unidades || ' und)' ELSE '' END AS etiqueta
FROM productos_comunes pc;

-- Observaciones comparables (compatibles con las consultas del Taller 1)
CREATE VIEW v_comparables AS
SELECT v.*, pc.clave_producto, pc.variante, pc.marca AS marca_comun, pc.unidades AS unidades_comun,
       pc.marca || ' ' || LOWER(REPLACE(pc.variante, '_', ' ')) || ' · ' ||
       CAST(CAST(pc.contenido_total_ml AS INTEGER) AS TEXT) || ' mL' ||
       CASE WHEN pc.unidades > 1 THEN ' (' || pc.unidades || ' und)' ELSE '' END AS etiqueta
FROM v_obs_validas v
JOIN productos_comunes pc ON pc.id_corrida = v.id_corrida AND pc.id_producto_comun = v.id_producto_comun
WHERE v.comparable = 1 AND v.id_producto_comun IS NOT NULL;

-- Serie histórica por producto comparable y comercio (una fila por corrida)
CREATE VIEW v_historial_precios AS
SELECT c.clave_producto, c.etiqueta, c.comercio, c.id_corrida, c.id_ejecucion, c.fecha_hora_consulta,
       SUBSTR(c.fecha_hora_consulta, 1, 10) AS fecha, c.precio_cop, c.precio_por_l, c.es_promocion, c.disponibilidad
FROM v_comparables c;

-- Base de la canasta: precio por producto comparable y comercio en cada corrida + mínimo y empates
CREATE VIEW v_canasta_supermercado AS
SELECT id_corrida, clave_producto, etiqueta, comercio, precio_cop, es_promocion, disponibilidad, url_producto,
       MIN(precio_cop) OVER (PARTITION BY id_corrida, clave_producto) AS precio_minimo,
       (precio_cop = MIN(precio_cop) OVER (PARTITION BY id_corrida, clave_producto)) AS es_minimo,
       COUNT(*) OVER (PARTITION BY id_corrida, clave_producto) AS n_comercios_con_precio
FROM v_comparables;
