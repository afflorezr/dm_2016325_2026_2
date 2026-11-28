-- Esquema de la base (copia de sqlite_master) para las pruebas. Sin datos.
CREATE TABLE comercios (
  id_comercio  INTEGER PRIMARY KEY,
  codigo       TEXT NOT NULL UNIQUE,      -- clave del scraper: exito | farmatodo | larebaja
  nombre       TEXT NOT NULL,             -- nombre para mostrar
  sitio_web    TEXT
);

CREATE TABLE productos (
  id_producto      INTEGER PRIMARY KEY,   -- = id_producto de CATALOGO_COMPARABLES
  nombre           TEXT NOT NULL UNIQUE,
  linea            TEXT,                  -- nombre sin el contenido: 'Lubriderm humectacion diaria'
  marca_std        TEXT NOT NULL,
  subcategoria_std TEXT NOT NULL,
  presentacion     TEXT NOT NULL,         -- legible: '400 ml', '3 x 200 ml'
  medida           TEXT NOT NULL CHECK (medida IN ('ml','g')),
  cantidad_unidad  REAL NOT NULL CHECK (cantidad_unidad > 0),
  unidades         REAL NOT NULL DEFAULT 1 CHECK (unidades > 0),
  cantidad_total   REAL NOT NULL CHECK (cantidad_total > 0)
, en_conjunto INTEGER NOT NULL DEFAULT 0 CHECK (en_conjunto IN (0,1)));

CREATE TABLE anuncios (
  id_anuncio            INTEGER PRIMARY KEY,
  id_comercio           INTEGER NOT NULL REFERENCES comercios (id_comercio),
  sku                   TEXT NOT NULL,    -- 'producto del comercio'
  id_producto           INTEGER REFERENCES productos (id_producto),   -- NULL = no comparable
  nombre_original       TEXT NOT NULL,    -- nombre tal como se publico
  presentacion_original TEXT,             -- presentacion tal como se publico (puede ser NULL)
  marca_original        TEXT,
  marca_std             TEXT,
  subcategoria_std      TEXT,
  envase                TEXT,
  medida                TEXT CHECK (medida IN ('ml','g')),
  cantidad_unidad       REAL CHECK (cantidad_unidad > 0),
  unidades              REAL CHECK (unidades > 0),
  cantidad_total        REAL CHECK (cantidad_total > 0),
  url_producto          TEXT,
  texto_original        TEXT,             -- texto de la tarjeta la PRIMERA vez que se vio, sin limpieza
  primera_consulta      TEXT NOT NULL,
  ultima_consulta       TEXT NOT NULL,
  UNIQUE (id_comercio, sku),
  UNIQUE (id_anuncio, id_comercio)        -- permite la FK compuesta de observaciones
);

CREATE UNIQUE INDEX ux_anuncio_producto_comercio
  ON anuncios (id_comercio, id_producto) WHERE id_producto IS NOT NULL;

CREATE INDEX ix_anuncios_producto ON anuncios (id_producto);

CREATE TABLE ejecuciones (
  id_ejecucion      INTEGER PRIMARY KEY,
  codigo_corrida    TEXT NOT NULL,        -- id_ejecucion del scraper (AAAAMMDDhhmmss)
  id_comercio       INTEGER NOT NULL REFERENCES comercios (id_comercio),
  fecha_hora_inicio TEXT NOT NULL
    CHECK (fecha_hora_inicio GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9]:[0-9][0-9]'),
  n_registros       INTEGER NOT NULL DEFAULT 0 CHECK (n_registros >= 0),
  estado            TEXT NOT NULL CHECK (estado IN ('completa','parcial','fallida')),
  mensaje           TEXT,
  UNIQUE (codigo_corrida, id_comercio),
  UNIQUE (id_ejecucion, id_comercio)      -- permite la FK compuesta de observaciones
);

CREATE TABLE observaciones (
  id_observacion         INTEGER PRIMARY KEY,
  id_anuncio             INTEGER NOT NULL,
  id_comercio            INTEGER NOT NULL,
  id_ejecucion           INTEGER NOT NULL,
  fecha_hora_consulta    TEXT NOT NULL    -- ISO 8601 con zona: 2026-10-15T09:30:00-05:00
    CHECK (fecha_hora_consulta GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9]:[0-9][0-9]'),
  precio_cop             INTEGER NOT NULL CHECK (precio_cop > 0),        -- lo que paga cualquier cliente
  precio_lista_cop       INTEGER NOT NULL CHECK (precio_lista_cop > 0),  -- precio sin descuento
  es_promocion           INTEGER NOT NULL CHECK (es_promocion IN (0,1)), -- 1 = precio_cop incluye descuento general
  url_extraccion         TEXT NOT NULL,   -- pagina de donde salio el precio
  texto_original_anuncio TEXT,            -- texto de la tarjeta en ESTE momento (trae precio y promo), sin limpieza
  busqueda               TEXT, disponibilidad TEXT NOT NULL DEFAULT 'disponible'
  CHECK (disponibilidad IN ('disponible','agotado')),            -- informativo: primera busqueda en que salio
  UNIQUE (id_anuncio, fecha_hora_consulta),
  CHECK (precio_cop <= precio_lista_cop),
  CHECK ((precio_cop < precio_lista_cop) = es_promocion),
  FOREIGN KEY (id_anuncio, id_comercio)   REFERENCES anuncios (id_anuncio, id_comercio),
  FOREIGN KEY (id_ejecucion, id_comercio) REFERENCES ejecuciones (id_ejecucion, id_comercio)
);

CREATE INDEX ix_obs_ejecucion ON observaciones (id_ejecucion);

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

CREATE INDEX ix_obs_fecha        ON observaciones (fecha_hora_consulta);

CREATE INDEX ix_obs_precio       ON observaciones (precio_cop);

CREATE INDEX ix_obs_comercio_eje ON observaciones (id_comercio, id_ejecucion);

CREATE INDEX ix_anuncios_marca   ON anuncios (marca_std);

CREATE INDEX ix_anuncios_subcat  ON anuncios (subcategoria_std);

CREATE INDEX ix_ejec_fecha       ON ejecuciones (fecha_hora_inicio);

CREATE INDEX ix_rechazos_corrida ON rechazos (codigo_corrida);

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

CREATE VIEW v_ultimo_precio AS
SELECT * FROM v_precios v
WHERE v.fecha_hora_consulta =
  (SELECT MAX(o.fecha_hora_consulta) FROM observaciones o WHERE o.id_anuncio = v.id_anuncio);

CREATE VIEW v_comparables AS
SELECT * FROM v_precios WHERE en_conjunto = 1;

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

CREATE TABLE agotados (
  id_agotado          INTEGER PRIMARY KEY,
  id_ejecucion        INTEGER NOT NULL REFERENCES ejecuciones (id_ejecucion),
  id_comercio         INTEGER NOT NULL REFERENCES comercios (id_comercio),
  fecha_hora_consulta TEXT NOT NULL,
  nombre              TEXT NOT NULL,
  url                 TEXT,
  texto_original      TEXT,
  UNIQUE (id_ejecucion, nombre)
);

CREATE INDEX ix_agotados_ejecucion ON agotados (id_ejecucion);

CREATE UNIQUE INDEX ux_rechazos
  ON rechazos (codigo_corrida, comercio, COALESCE(sku, ''), COALESCE(nombre, ''), regla);

CREATE VIEW v_no_observados AS
SELECT e.id_ejecucion, e.codigo_corrida, c.nombre AS comercio,
       a.id_anuncio, a.sku, a.nombre_original AS nombre, a.id_producto,
       CASE WHEN EXISTS (SELECT 1 FROM agotados g
                         WHERE g.id_ejecucion = e.id_ejecucion AND g.url = a.url_producto)
            THEN 'agotado_segun_sitio' ELSE 'no_observado' END AS situacion
FROM ejecuciones e
JOIN comercios c ON c.id_comercio = e.id_comercio
JOIN anuncios  a ON a.id_comercio = e.id_comercio
WHERE e.estado = 'completa'
  AND EXISTS (SELECT 1 FROM observaciones o
              WHERE o.id_anuncio = a.id_anuncio AND o.fecha_hora_consulta < e.fecha_hora_inicio)
  AND NOT EXISTS (SELECT 1 FROM observaciones o
              WHERE o.id_anuncio = a.id_anuncio AND o.id_ejecucion = e.id_ejecucion);

