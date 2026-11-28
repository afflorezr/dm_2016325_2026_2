-- =====================================================================
-- sql/vistas.sql
-- Vistas SQL del Comparador de Precios (Taller 2 - Minería de Datos UNAL)
-- =====================================================================

-- 1. Vista plana de todas las observaciones válidas con campos normalizados
DROP VIEW IF EXISTS v_observaciones;
CREATE VIEW v_observaciones AS
SELECT
    o.observacion_id,
    o.ejecucion_id,
    c.comercio_id,
    c.nombre AS comercio,
    a.anuncio_id,
    a.sku,
    a.ean,
    a.url,
    a.nombre_original,
    COALESCE(p.nombre_estandar, a.nombre_estandar, a.nombre_original) AS nombre,
    COALESCE(p.marca_estandar, a.marca_estandar, a.marca_original) AS marca,
    COALESCE(p.subcategoria_estandar, a.subcategoria_estandar, a.categoria_original) AS subcategoria,
    COALESCE(p.contenido_total, a.contenido_total) AS contenido_total,
    COALESCE(p.unidad_normalizada, a.unidad_normalizada) AS unidad_normalizada,
    COALESCE(p.unidades_por_paquete, a.unidades_por_paquete, 1) AS unidades_por_paquete,
    a.producto_id,
    COALESCE(p.es_comparable, 0) AS es_comparable,
    COALESCE(p.es_canasta_8, 0) AS es_canasta_8,
    o.precio_actual,
    o.precio_antes,
    o.es_promocion,
    COALESCE(o.disponibilidad, 'disponible') AS disponibilidad,
    o.fecha_hora_consulta,
    o.descartada,
    o.motivo_descarte,
    CASE 
        WHEN COALESCE(p.contenido_total, a.contenido_total) > 0 AND o.precio_actual > 0 
        THEN ROUND(o.precio_actual / COALESCE(p.contenido_total, a.contenido_total), 4)
        ELSE NULL 
    END AS precio_unitario
FROM observaciones o
JOIN anuncios a ON o.anuncio_id = a.anuncio_id
JOIN comercios c ON a.comercio_id = c.comercio_id
LEFT JOIN productos p ON a.producto_id = p.producto_id;

-- 2. Último precio observado para cada anuncio
DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
WITH ultima_obs AS (
    SELECT 
        o.observacion_id,
        o.anuncio_id,
        o.ejecucion_id,
        o.precio_actual,
        o.precio_antes,
        o.es_promocion,
        COALESCE(o.disponibilidad, 'disponible') AS disponibilidad,
        o.fecha_hora_consulta,
        o.descartada,
        o.motivo_descarte,
        ROW_NUMBER() OVER(PARTITION BY o.anuncio_id ORDER BY o.fecha_hora_consulta DESC, o.observacion_id DESC) as rn
    FROM observaciones o
    WHERE o.descartada = 0
)
SELECT
    u.observacion_id,
    u.ejecucion_id,
    c.comercio_id,
    c.nombre AS comercio,
    a.anuncio_id,
    a.sku,
    a.ean,
    a.url,
    COALESCE(p.nombre_estandar, a.nombre_estandar, a.nombre_original) AS nombre,
    COALESCE(p.marca_estandar, a.marca_estandar, a.marca_original) AS marca,
    COALESCE(p.subcategoria_estandar, a.subcategoria_estandar, a.categoria_original) AS subcategoria,
    COALESCE(p.contenido_total, a.contenido_total) AS contenido_total,
    COALESCE(p.unidad_normalizada, a.unidad_normalizada) AS unidad_normalizada,
    COALESCE(p.unidades_por_paquete, a.unidades_por_paquete, 1) AS unidades_por_paquete,
    a.producto_id,
    COALESCE(p.es_comparable, 0) AS es_comparable,
    COALESCE(p.es_canasta_8, 0) AS es_canasta_8,
    u.precio_actual,
    u.precio_antes,
    u.es_promocion,
    u.disponibilidad,
    u.fecha_hora_consulta,
    CASE 
        WHEN COALESCE(p.contenido_total, a.contenido_total) > 0 AND u.precio_actual > 0 
        THEN ROUND(u.precio_actual / COALESCE(p.contenido_total, a.contenido_total), 4)
        ELSE NULL 
    END AS precio_unitario
FROM ultima_obs u
JOIN anuncios a ON u.anuncio_id = a.anuncio_id
JOIN comercios c ON a.comercio_id = c.comercio_id
LEFT JOIN productos p ON a.producto_id = p.producto_id
WHERE u.rn = 1;

-- 3. Vista de los 8 productos comparables presentes en los 3 comercios con precio unitario
DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT
    o.observacion_id,
    o.ejecucion_id,
    c.comercio_id,
    c.nombre AS comercio,
    p.producto_id,
    p.ean,
    p.nombre_estandar AS nombre,
    p.marca_estandar AS marca,
    p.subcategoria_estandar AS subcategoria,
    p.contenido_total,
    p.unidad_normalizada,
    a.anuncio_id,
    a.sku,
    a.url,
    o.precio_actual,
    o.precio_antes,
    o.es_promocion,
    COALESCE(o.disponibilidad, 'disponible') AS disponibilidad,
    o.fecha_hora_consulta,
    ROUND(o.precio_actual / p.contenido_total, 4) AS precio_unitario
FROM comparables_8 c8
JOIN productos p ON c8.producto_id = p.producto_id
JOIN anuncios a ON p.producto_id = a.producto_id
JOIN comercios c ON a.comercio_id = c.comercio_id
JOIN observaciones o ON a.anuncio_id = o.anuncio_id
WHERE o.descartada = 0;

-- 4. Vista de cambios de precio entre ejecuciones para el mismo anuncio y comercio
DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
WITH obs_ordenadas AS (
    SELECT
        o.observacion_id,
        o.anuncio_id,
        o.ejecucion_id,
        o.precio_actual,
        o.precio_antes,
        o.fecha_hora_consulta,
        COALESCE(o.disponibilidad, 'disponible') AS disponibilidad,
        o.descartada,
        LAG(o.ejecucion_id) OVER (PARTITION BY o.anuncio_id ORDER BY o.fecha_hora_consulta ASC) AS ejecucion_anterior_id,
        LAG(o.precio_actual) OVER (PARTITION BY o.anuncio_id ORDER BY o.fecha_hora_consulta ASC) AS precio_anterior,
        LAG(o.fecha_hora_consulta) OVER (PARTITION BY o.anuncio_id ORDER BY o.fecha_hora_consulta ASC) AS fecha_anterior
    FROM observaciones o
    WHERE o.descartada = 0
)
SELECT
    cur.observacion_id,
    cur.anuncio_id,
    a.comercio_id,
    c.nombre AS comercio,
    a.sku,
    a.ean,
    a.url,
    COALESCE(p.nombre_estandar, a.nombre_estandar, a.nombre_original) AS nombre,
    COALESCE(p.marca_estandar, a.marca_estandar, a.marca_original) AS marca,
    COALESCE(p.subcategoria_estandar, a.subcategoria_estandar, a.categoria_original) AS subcategoria,
    COALESCE(p.contenido_total, a.contenido_total) AS contenido_total,
    COALESCE(p.unidad_normalizada, a.unidad_normalizada) AS unidad_normalizada,
    COALESCE(p.es_comparable, 0) AS es_comparable,
    COALESCE(p.es_canasta_8, 0) AS es_canasta_8,
    cur.ejecucion_anterior_id,
    cur.ejecucion_id AS ejecucion_actual_id,
    cur.precio_anterior,
    cur.precio_actual,
    ROUND(cur.precio_actual - cur.precio_anterior, 2) AS cambio_cop,
    CASE 
        WHEN cur.precio_anterior > 0 
        THEN ROUND(((cur.precio_actual - cur.precio_anterior) * 100.0) / cur.precio_anterior, 2)
        ELSE NULL 
    END AS cambio_porcentaje,
    CASE
        WHEN cur.precio_anterior IS NULL THEN 'nuevo'
        WHEN cur.precio_actual > cur.precio_anterior THEN 'subida'
        WHEN cur.precio_actual < cur.precio_anterior THEN 'bajada'
        ELSE 'sin_cambio'
    END AS tipo_cambio,
    cur.fecha_anterior,
    cur.fecha_hora_consulta AS fecha_actual,
    cur.descartada
FROM obs_ordenadas cur
JOIN anuncios a ON cur.anuncio_id = a.anuncio_id
JOIN comercios c ON a.comercio_id = c.comercio_id
LEFT JOIN productos p ON a.producto_id = p.producto_id;

-- 5. Disponibilidad derivada por ejecución (disponible, agotado o no observado)
DROP VIEW IF EXISTS v_disponibilidad;
CREATE VIEW v_disponibilidad AS
WITH matriz AS (
    SELECT 
        e.ejecucion_id,
        e.comercio_id,
        c.nombre AS comercio,
        e.fecha_hora_inicio,
        c8.producto_id,
        p.ean,
        p.nombre_estandar AS nombre,
        p.marca_estandar AS marca
    FROM ejecuciones e
    JOIN comercios c ON e.comercio_id = c.comercio_id
    CROSS JOIN comparables_8 c8
    JOIN productos p ON c8.producto_id = p.producto_id
)
SELECT
    m.ejecucion_id,
    m.comercio_id,
    m.comercio,
    m.fecha_hora_inicio,
    m.producto_id,
    m.ean,
    m.nombre,
    m.marca,
    o.observacion_id,
    o.precio_actual,
    CASE
        WHEN o.observacion_id IS NULL THEN 'no_observado'
        WHEN o.disponibilidad = 'disponible' THEN 'disponible'
        WHEN o.disponibilidad = 'agotado' THEN 'agotado'
        ELSE 'disponible'
    END AS estado_disponibilidad
FROM matriz m
LEFT JOIN anuncios a ON a.comercio_id = m.comercio_id AND a.producto_id = m.producto_id
LEFT JOIN observaciones o ON o.anuncio_id = a.anuncio_id AND o.ejecucion_id = m.ejecucion_id;

-- 6. Resumen de ejecuciones y cobertura de catálogo y comparables
DROP VIEW IF EXISTS v_ejecuciones_resumen;
CREATE VIEW v_ejecuciones_resumen AS
SELECT
    e.ejecucion_id,
    e.comercio_id,
    c.nombre AS comercio,
    e.fecha_hora_inicio,
    e.fecha_hora_fin,
    e.registros_obtenidos,
    e.registros_con_precio,
    e.total_sitio,
    e.estado,
    e.nota,
    COUNT(DISTINCT CASE WHEN o.descartada = 0 THEN o.anuncio_id END) AS anuncios_observados,
    COUNT(DISTINCT CASE WHEN p.es_canasta_8 = 1 AND o.descartada = 0 THEN p.producto_id END) AS comparables_8_observados
FROM ejecuciones e
JOIN comercios c ON e.comercio_id = c.comercio_id
LEFT JOIN observaciones o ON e.ejecucion_id = o.ejecucion_id
LEFT JOIN anuncios a ON o.anuncio_id = a.anuncio_id
LEFT JOIN productos p ON a.producto_id = p.producto_id
GROUP BY e.ejecucion_id;
