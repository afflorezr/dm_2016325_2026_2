-- F1.3 Esquema Taller 2. Comentarios sin punto y coma (el ejecutor separa por punto y coma)

ALTER TABLE productos ADD COLUMN en_conjunto INTEGER NOT NULL DEFAULT 0 CHECK (en_conjunto IN (0,1));

UPDATE productos SET en_conjunto = 1 WHERE id_producto BETWEEN 1 AND 8;

ALTER TABLE observaciones ADD COLUMN disponibilidad TEXT NOT NULL DEFAULT 'disponible'
  CHECK (disponibilidad IN ('disponible','agotado'));

CREATE TABLE rechazos (
  id_rechazo          INTEGER PRIMARY KEY,
  fecha_hora_registro TEXT NOT NULL,
  codigo_corrida      TEXT,
  comercio            TEXT,
  sku                 TEXT,
  nombre              TEXT,
  precio_texto        TEXT,
  regla               TEXT NOT NULL,
  motivo              TEXT NOT NULL
);

CREATE TABLE correcciones (
  id_correccion  INTEGER PRIMARY KEY,
  fecha          TEXT NOT NULL,
  tabla          TEXT NOT NULL,
  registro       TEXT NOT NULL,
  campo          TEXT NOT NULL,
  valor_anterior TEXT,
  valor_nuevo    TEXT,
  motivo         TEXT NOT NULL
);

INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo)
VALUES (strftime('%Y-%m-%dT%H:%M:%S-05:00','now','-5 hours'), 'productos', 'id_producto=9',
  'en_conjunto', NULL, '0',
  'Nivea hidratacion express 1000 ml existe en Exito (SKU 283481) pero el scraper no lo alcanza. Queda fuera del conjunto comparable de 8 productos');

INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo)
SELECT strftime('%Y-%m-%dT%H:%M:%S-05:00','now','-5 hours'), 'ejecuciones',
  'id_ejecucion=' || id_ejecucion, 'estado', estado, 'completa',
  'El estado parcial se debia solo al producto 9 ausente de Exito. Se evalua contra el conjunto de 8 productos'
FROM ejecuciones
WHERE estado = 'parcial' AND mensaje = '1 producto(s) del catalogo sin precio'
  AND id_comercio = (SELECT id_comercio FROM comercios WHERE codigo = 'exito');

UPDATE ejecuciones SET estado = 'completa', mensaje = NULL
WHERE estado = 'parcial' AND mensaje = '1 producto(s) del catalogo sin precio'
  AND id_comercio = (SELECT id_comercio FROM comercios WHERE codigo = 'exito');

CREATE INDEX IF NOT EXISTS ix_obs_fecha        ON observaciones (fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS ix_obs_precio       ON observaciones (precio_cop);
CREATE INDEX IF NOT EXISTS ix_obs_comercio_eje ON observaciones (id_comercio, id_ejecucion);
CREATE INDEX IF NOT EXISTS ix_anuncios_marca   ON anuncios (marca_std);
CREATE INDEX IF NOT EXISTS ix_anuncios_subcat  ON anuncios (subcategoria_std);
CREATE INDEX IF NOT EXISTS ix_ejec_fecha       ON ejecuciones (fecha_hora_inicio);
CREATE INDEX IF NOT EXISTS ix_rechazos_corrida ON rechazos (codigo_corrida);

DROP VIEW IF EXISTS v_precios;
CREATE VIEW v_precios AS
SELECT o.id_observacion, o.id_anuncio, o.id_ejecucion, e.codigo_corrida,
       e.estado AS estado_ejecucion, o.fecha_hora_consulta,
       c.id_comercio, c.nombre AS comercio, a.sku, a.nombre_original AS nombre,
       a.marca_std AS marca, a.subcategoria_std AS subcategoria,
       a.id_producto, p.nombre AS producto,
       CASE WHEN a.id_producto IS NULL THEN 0 ELSE 1 END AS es_comparable,
       COALESCE(p.en_conjunto, 0) AS en_conjunto,
       a.medida, a.cantidad_unidad, a.unidades, a.cantidad_total,
       CASE WHEN a.cantidad_total IS NULL THEN NULL
            WHEN a.unidades > 1 THEN printf('%g x %g %s', a.unidades, a.cantidad_unidad, a.medida)
            ELSE printf('%g %s', a.cantidad_total, a.medida) END AS presentacion,
       o.precio_cop AS precio, o.precio_lista_cop AS precio_lista, o.es_promocion,
       o.disponibilidad,
       ROUND(o.precio_cop * 1.0 / a.cantidad_total, 2) AS precio_por_medida,
       o.url_extraccion, a.url_producto, o.texto_original_anuncio
FROM observaciones o
JOIN anuncios    a ON a.id_anuncio   = o.id_anuncio
JOIN comercios   c ON c.id_comercio  = o.id_comercio
JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
LEFT JOIN productos p ON p.id_producto = a.id_producto;

DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
SELECT * FROM v_precios v
WHERE v.fecha_hora_consulta =
  (SELECT MAX(o.fecha_hora_consulta) FROM observaciones o WHERE o.id_anuncio = v.id_anuncio);

DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT * FROM v_precios WHERE en_conjunto = 1;

DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
WITH s AS (
  SELECT id_observacion, id_anuncio, id_ejecucion,
         fecha_hora_consulta AS fecha_actual, precio_cop AS precio_actual,
         LAG(precio_cop)           OVER w AS precio_anterior,
         LAG(fecha_hora_consulta)  OVER w AS fecha_anterior,
         LAG(id_ejecucion)         OVER w AS id_ejecucion_anterior
  FROM observaciones
  WINDOW w AS (PARTITION BY id_anuncio ORDER BY fecha_hora_consulta)
)
SELECT s.id_observacion, c.nombre AS comercio, a.id_anuncio, a.sku,
       a.nombre_original AS nombre, a.id_producto,
       s.id_ejecucion_anterior, s.id_ejecucion, s.fecha_anterior, s.fecha_actual,
       s.precio_anterior, s.precio_actual,
       s.precio_actual - s.precio_anterior AS variacion_cop,
       ROUND(100.0 * (s.precio_actual - s.precio_anterior) / s.precio_anterior, 1) AS variacion_pct
FROM s
JOIN anuncios  a ON a.id_anuncio  = s.id_anuncio
JOIN comercios c ON c.id_comercio = a.id_comercio
WHERE s.precio_anterior IS NOT NULL;

DROP VIEW IF EXISTS v_no_observados;
CREATE VIEW v_no_observados AS
SELECT e.id_ejecucion, e.codigo_corrida, c.nombre AS comercio,
       a.id_anuncio, a.sku, a.nombre_original AS nombre, a.id_producto
FROM ejecuciones e
JOIN comercios c ON c.id_comercio = e.id_comercio
JOIN anuncios  a ON a.id_comercio = e.id_comercio
WHERE e.estado <> 'fallida'
  AND EXISTS (SELECT 1 FROM observaciones o
              WHERE o.id_anuncio = a.id_anuncio AND o.fecha_hora_consulta < e.fecha_hora_inicio)
  AND NOT EXISTS (SELECT 1 FROM observaciones o
              WHERE o.id_anuncio = a.id_anuncio AND o.id_ejecucion = e.id_ejecucion);
