-- Vistas del Taller 2 (las ejecuta scraper.R::conectar después de esquema.sql). La aplicación consulta
-- estas vistas desde db.R; se borran y se vuelven a crear para que siempre coincidan con este archivo.

-- v_catalogo: una fila por observación vigente (anuncio incluido en la categoría y observación no
-- descartada), con los campos estandarizados y el precio por unidad de contenido.
DROP VIEW IF EXISTS v_comparables;
DROP VIEW IF EXISTS v_cambios_precio;
DROP VIEW IF EXISTS v_ultimo_precio;
DROP VIEW IF EXISTS v_disponibilidad;
DROP VIEW IF EXISTS v_catalogo;
CREATE VIEW v_catalogo AS
SELECT o.observacion_id, o.ejecucion_id, o.comercio_id, c.nombre AS comercio, a.anuncio_id, a.sku_comercio,
       a.producto_id, COALESCE(a.nombre_std, a.nombre_original) AS nombre, a.nombre_original, a.texto_original,
       a.marca_std AS marca, a.subcategoria_std AS subcategoria, a.contenido_total, a.n_unidades,
       CASE a.unidad WHEN 'ml' THEN 'mL' WHEN 'und' THEN 'unidad' ELSE a.unidad END AS unidad,
       CASE WHEN a.contenido_total IS NULL THEN NULL
            WHEN a.unidad = 'und' THEN printf('%g', a.contenido_total) || CASE WHEN a.contenido_total = 1 THEN ' unidad' ELSE ' unidades' END
            WHEN a.n_unidades > 1 THEN a.n_unidades || ' x ' || printf('%g', a.contenido_unitario) || ' ' || replace(a.unidad, 'ml', 'mL')
            ELSE printf('%g', a.contenido_total) || ' ' || replace(a.unidad, 'ml', 'mL') END AS presentacion,
       o.precio, o.precio_lista,
       CASE WHEN o.precio IS NOT NULL AND a.contenido_total > 0 AND a.unidad IN ('ml', 'g', 'm', 'und')
            THEN o.precio / a.contenido_total END AS precio_unitario,
       o.es_promocion, o.texto_promocion, o.disponibilidad, o.fecha_hora_consulta,
       substr(o.fecha_hora_consulta, 1, 10) AS fecha, a.url_producto, o.url_fuente, a.comparable, e.carpeta_raw
FROM observaciones o
JOIN anuncios a ON a.anuncio_id = o.anuncio_id
JOIN comercios c ON c.comercio_id = o.comercio_id
JOIN ejecuciones e ON e.ejecucion_id = o.ejecucion_id AND e.comercio_id = o.comercio_id
WHERE a.incluido = 1 AND o.descartada = 0;

-- v_ultimo_precio: la observación más reciente de cada anuncio. `estado_actual` distingue disponible,
-- agotado (lo dice el sitio) y no observado (el anuncio no apareció en la última ejecución del comercio).
CREATE VIEW v_ultimo_precio AS
SELECT v.*, u.ultima_ejecucion,
       CASE WHEN v.ejecucion_id <> u.ultima_ejecucion THEN 'no observado'
            ELSE COALESCE(v.disponibilidad, 'sin dato') END AS estado_actual
FROM v_catalogo v
JOIN (SELECT anuncio_id, MAX(ejecucion_id) AS ejecucion_id FROM observaciones WHERE descartada = 0
      GROUP BY anuncio_id) m ON m.anuncio_id = v.anuncio_id AND m.ejecucion_id = v.ejecucion_id
JOIN (SELECT comercio_id, MAX(ejecucion_id) AS ultima_ejecucion FROM ejecuciones WHERE estado <> 'fallida'
      GROUP BY comercio_id) u ON u.comercio_id = v.comercio_id;

-- v_cambios_precio: observaciones cuyo precio difiere del de la observación anterior del MISMO anuncio
-- en el MISMO comercio (cambio en COP y en porcentaje).
CREATE VIEW v_cambios_precio AS
SELECT ejecucion_id, ejecucion_anterior, comercio_id, comercio, anuncio_id, producto_id, nombre, marca, subcategoria,
       presentacion, comparable, precio_anterior, precio, precio - precio_anterior AS cambio_cop,
       100.0 * (precio - precio_anterior) / precio_anterior AS cambio_pct,
       CASE WHEN precio > precio_anterior THEN 'subió' ELSE 'bajó' END AS tipo_cambio,
       fecha_hora_consulta, url_producto
FROM (SELECT v.*, LAG(v.precio) OVER w AS precio_anterior, LAG(v.ejecucion_id) OVER w AS ejecucion_anterior
      FROM v_catalogo v WINDOW w AS (PARTITION BY v.anuncio_id ORDER BY v.ejecucion_id))
WHERE precio IS NOT NULL AND precio_anterior IS NOT NULL AND precio <> precio_anterior;

-- v_comparables: un precio por presentación comparable, comercio y ejecución (si el comercio tiene
-- varios anuncios de la misma presentación se toma el disponible más barato). `comprable` = tiene
-- precio y está disponible. El precio unitario solo se calcula si el contenido está verificado, es
-- decir, si todos los anuncios de la presentación declaran el mismo contenido y la misma unidad.
CREATE VIEW v_comparables AS
SELECT producto_id, producto, marca, subcategoria, contenido_total, unidad, presentacion, contenido_verificado,
       orden_referencia, ejecucion_id, comercio_id, comercio, anuncio_id, precio, precio_lista,
       CASE WHEN contenido_verificado = 1 AND contenido_total > 0 THEN precio / contenido_total END AS precio_unitario,
       es_promocion, disponibilidad,
       CASE WHEN precio IS NOT NULL AND disponibilidad = 'disponible' THEN 1 ELSE 0 END AS comprable,
       fecha_hora_consulta, fecha, url_producto
FROM (SELECT p.producto_id, p.nombre_estandar AS producto, p.marca, p.subcategoria, p.contenido_total,
             CASE p.unidad WHEN 'ml' THEN 'mL' WHEN 'und' THEN 'unidad' ELSE p.unidad END AS unidad,
             v.presentacion, p.contenido_verificado, r.orden AS orden_referencia, v.ejecucion_id, v.comercio_id,
             v.comercio, v.anuncio_id, v.precio, v.precio_lista, v.es_promocion, v.disponibilidad,
             v.fecha_hora_consulta, v.fecha, v.url_producto,
             ROW_NUMBER() OVER (PARTITION BY p.producto_id, v.comercio_id, v.ejecucion_id
                                ORDER BY (v.precio IS NULL), (COALESCE(v.disponibilidad, '') <> 'disponible'),
                                         v.precio, v.anuncio_id) AS orden
      FROM productos p
      JOIN v_catalogo v ON v.producto_id = p.producto_id
      LEFT JOIN comparables_referencia r ON r.producto_id = p.producto_id
      WHERE p.comparable = 1)
WHERE orden = 1;

-- v_disponibilidad: estado de cada anuncio en cada ejecución no fallida de su comercio posterior a su
-- primera aparición: disponible, agotado, sin_dato o no_observado. Un anuncio no observado NO se
-- interpreta como agotado ni como retirado.
CREATE VIEW v_disponibilidad AS
SELECT e.ejecucion_id, a.comercio_id, a.anuncio_id, a.producto_id,
       CASE WHEN o.observacion_id IS NULL THEN 'no_observado' ELSE COALESCE(o.disponibilidad, 'sin_dato') END AS estado
FROM anuncios a
JOIN ejecuciones e ON e.comercio_id = a.comercio_id AND e.estado <> 'fallida' AND e.fin >= a.primera_consulta
LEFT JOIN observaciones o ON o.anuncio_id = a.anuncio_id AND o.ejecucion_id = e.ejecucion_id AND o.descartada = 0
WHERE a.incluido = 1;
