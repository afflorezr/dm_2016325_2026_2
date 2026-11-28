-- ============================================================================
-- esquema.sql — Base comparador_precios.sqlite (Taller 2, Minería de Datos UNAL)
--
-- Conserva TODAS las tablas y columnas del Taller 1 y agrega (enunciado §3.6):
--   * tablas correcciones, rechazos y validaciones;
--   * observaciones.disponibilidad ('disponible' / 'agotado'); el "no observado"
--     sale de la vista v_disponibilidad;
--   * contenido_total y unidad_normalizada (mL, g o unidad) en anuncios y productos;
--   * UNIQUE (id_ejecucion, id_comercio, sku_comercio) en observaciones, además del
--     UNIQUE del Taller 1;
--   * índices sobre las columnas que usan los filtros de la aplicación;
--   * vistas que la aplicación usa directamente.
--
-- scraper.conectar() ejecuta este archivo cada vez que abre la base para escribir.
-- Por eso todo es idempotente: CREATE ... IF NOT EXISTS y, para las vistas,
-- DROP VIEW IF EXISTS + CREATE VIEW (así un cambio en una vista se aplica solo).
-- El significado de cada columna está en diccionario_datos.md.
-- ============================================================================
PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- Tablas del Taller 1 (con las columnas nuevas del Taller 2 al final)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS comercios (
    id_comercio  TEXT PRIMARY KEY,
    nombre       TEXT NOT NULL,
    url_base     TEXT NOT NULL,
    plataforma   TEXT,
    secciones    TEXT,                 -- secciones del sitio recorridas (JSON)
    robots       TEXT,                 -- resultado de la revisión de robots.txt
    -- Taller 2
    nombre_corto TEXT,                 -- nombre que muestra la aplicación
    activo       INTEGER NOT NULL DEFAULT 0 CHECK (activo IN (0, 1))  -- 1 = se recolecta
);

CREATE TABLE IF NOT EXISTS ejecuciones (
    id_ejecucion          TEXT NOT NULL,
    id_comercio           TEXT NOT NULL REFERENCES comercios(id_comercio),
    inicio                TEXT NOT NULL,     -- ISO 8601, hora de Colombia (-05:00)
    fin                   TEXT,
    modo                  TEXT NOT NULL CHECK (modo IN ('en_linea', 'sin_conexion')),
    paginas               INTEGER,
    total_reportado_sitio INTEGER,
    productos_recorridos  INTEGER,
    registros_categoria   INTEGER,
    excluidos             INTEGER,
    estado                TEXT NOT NULL CHECK (estado IN ('completa', 'parcial', 'fallida')),
    detalle               TEXT,              -- JSON: errores o motivo de la falla
    PRIMARY KEY (id_ejecucion, id_comercio)
);

CREATE TABLE IF NOT EXISTS productos (
    id_producto        TEXT PRIMARY KEY,     -- P01 ... P10
    descripcion        TEXT NOT NULL,
    principio_activo   TEXT,
    concentracion      TEXT,                 -- en el mismo orden que principio_activo
    forma              TEXT,
    laboratorio        TEXT,
    unidades           INTEGER,
    contenido_ml       REAL,                 -- columna del Taller 1 (solo líquidos)
    -- Taller 2
    contenido_total    REAL CHECK (contenido_total IS NULL OR contenido_total > 0),
    unidad_normalizada TEXT CHECK (unidad_normalizada IN ('mL', 'g', 'unidad'))
);

-- Un anuncio = un SKU de un comercio (campos originales y estandarizados)
CREATE TABLE IF NOT EXISTS anuncios (
    id_comercio               TEXT NOT NULL REFERENCES comercios(id_comercio),
    sku_comercio              TEXT NOT NULL,
    id_producto_comercio      TEXT,
    ean                       TEXT,
    ean_valido                INTEGER,
    nombre_original           TEXT NOT NULL,
    marca_original            TEXT,
    laboratorio_original      TEXT,
    principio_activo_original TEXT,
    presentacion_original     TEXT,
    via_original              TEXT,
    requiere_formula          TEXT,
    categoria_comercio        TEXT,
    url_producto              TEXT,
    principio_activo_std      TEXT,
    subcategoria              TEXT,
    marca_std                 TEXT,
    laboratorio_std           TEXT,
    forma_std                 TEXT,
    concentracion_std         TEXT,
    unidades                  INTEGER,
    contenido                 REAL,
    unidad_contenido          TEXT,
    fuente_cantidad           TEXT,
    id_producto               TEXT REFERENCES productos(id_producto),
    comparable                INTEGER NOT NULL DEFAULT 0,
    -- Taller 2
    contenido_total           REAL CHECK (contenido_total IS NULL OR contenido_total > 0),
    unidad_normalizada        TEXT CHECK (unidad_normalizada IN ('mL', 'g', 'unidad')),
    PRIMARY KEY (id_comercio, sku_comercio)
);

CREATE TABLE IF NOT EXISTS correspondencia (
    id_producto  TEXT NOT NULL REFERENCES productos(id_producto),
    id_comercio  TEXT NOT NULL,
    sku_comercio TEXT NOT NULL,
    regla        TEXT,
    PRIMARY KEY (id_comercio, sku_comercio),
    FOREIGN KEY (id_comercio, sku_comercio) REFERENCES anuncios(id_comercio, sku_comercio)
);

-- Una observación = el precio de un SKU en una ejecución
CREATE TABLE IF NOT EXISTS observaciones (
    id_observacion  INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion    TEXT NOT NULL,
    id_comercio     TEXT NOT NULL,
    sku_comercio    TEXT NOT NULL,
    fecha_consulta  TEXT NOT NULL,           -- ISO 8601, hora de Colombia
    precio          REAL CHECK (precio IS NULL OR precio > 0),   -- COP; NULL = sin precio
    precio_lista    REAL CHECK (precio_lista IS NULL OR precio_lista > 0),
    promocion       INTEGER,                 -- 1 si precio < precio_lista
    disponible      INTEGER CHECK (disponible IN (0, 1)),
    url_extraccion  TEXT NOT NULL,
    texto_original  TEXT NOT NULL,
    -- Taller 2
    disponibilidad  TEXT NOT NULL CHECK (disponibilidad IN ('disponible', 'agotado')),
    descartada      INTEGER NOT NULL DEFAULT 0 CHECK (descartada IN (0, 1)),
    motivo_descarte TEXT,
    UNIQUE (id_comercio, sku_comercio, fecha_consulta),           -- Taller 1
    UNIQUE (id_ejecucion, id_comercio, sku_comercio),             -- Taller 2: una vez por ejecución
    CHECK ((disponible = 1 AND disponibilidad = 'disponible')
        OR (disponible = 0 AND disponibilidad = 'agotado')),
    CHECK (disponibilidad = 'agotado' OR precio IS NOT NULL),     -- disponible => con precio
    CHECK (descartada = 0 OR motivo_descarte IS NOT NULL),
    FOREIGN KEY (id_comercio, sku_comercio) REFERENCES anuncios(id_comercio, sku_comercio),
    FOREIGN KEY (id_ejecucion, id_comercio) REFERENCES ejecuciones(id_ejecucion, id_comercio)
);

CREATE TABLE IF NOT EXISTS excluidos (
    id_ejecucion         TEXT NOT NULL,
    id_comercio          TEXT NOT NULL,
    sku_comercio         TEXT NOT NULL,
    nombre_original      TEXT,
    principio_activo     TEXT,
    categoria_comercio   TEXT,
    motivo               TEXT NOT NULL,
    PRIMARY KEY (id_ejecucion, id_comercio, sku_comercio)
);

-- ---------------------------------------------------------------------------
-- Tablas nuevas del Taller 2
-- ---------------------------------------------------------------------------
-- Cada cambio a un dato que ya estaba en la base (§3.2). Nunca se borra nada.
CREATE TABLE IF NOT EXISTS correcciones (
    id_correccion  INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha          TEXT NOT NULL,        -- ISO 8601, hora de Colombia
    tabla          TEXT NOT NULL,        -- anuncios, productos, observaciones...
    registro       TEXT NOT NULL,        -- clave del registro: 'locatel/14177', 'P02', ...
    campo          TEXT NOT NULL,
    valor_anterior TEXT,                 -- NULL = estaba vacío
    valor_nuevo    TEXT,                 -- NULL = queda vacío
    motivo         TEXT NOT NULL,
    origen         TEXT NOT NULL         -- archivo y función que hizo el cambio
);

-- Observaciones que no pasaron la validación (§3.4): no se insertan, se guardan aquí.
CREATE TABLE IF NOT EXISTS rechazos (
    id_rechazo     INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion   TEXT NOT NULL,
    id_comercio    TEXT,
    sku_comercio   TEXT,
    fecha_consulta TEXT,
    url_extraccion TEXT,
    precio         REAL,
    motivo         TEXT NOT NULL,
    registro       TEXT NOT NULL,        -- la fila rechazada completa (JSON)
    fecha_registro TEXT NOT NULL,
    UNIQUE (id_ejecucion, id_comercio, sku_comercio, motivo)
);

-- Resultado de cada regla de validación por ejecución y comercio.
CREATE TABLE IF NOT EXISTS validaciones (
    id_ejecucion TEXT NOT NULL,
    id_comercio  TEXT NOT NULL,
    regla        TEXT NOT NULL,
    n_revisadas  INTEGER NOT NULL,
    n_fallas     INTEGER NOT NULL,
    aprobada     INTEGER NOT NULL CHECK (aprobada IN (0, 1)),
    detalle      TEXT,
    fecha        TEXT NOT NULL,
    PRIMARY KEY (id_ejecucion, id_comercio, regla)
);

-- ---------------------------------------------------------------------------
-- Índices (columnas que usan los filtros y las vistas de la aplicación).
-- Los UNIQUE de observaciones ya crean índices sobre (id_comercio, sku_comercio,
-- fecha_consulta) y (id_ejecucion, id_comercio, sku_comercio).
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_observaciones_fecha     ON observaciones (fecha_consulta);
CREATE INDEX IF NOT EXISTS idx_observaciones_precio    ON observaciones (precio);
CREATE INDEX IF NOT EXISTS idx_observaciones_promocion ON observaciones (promocion);
CREATE INDEX IF NOT EXISTS idx_anuncios_subcategoria   ON anuncios (subcategoria);
CREATE INDEX IF NOT EXISTS idx_anuncios_marca          ON anuncios (marca_std);
CREATE INDEX IF NOT EXISTS idx_anuncios_comparable     ON anuncios (comparable, id_producto);
CREATE INDEX IF NOT EXISTS idx_ejecuciones_estado      ON ejecuciones (estado);

-- ---------------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------------
-- Una fila por observación con todos los campos que muestra la aplicación.
DROP VIEW IF EXISTS v_observaciones;
CREATE VIEW v_observaciones AS
SELECT o.id_observacion,
       o.id_ejecucion,
       c.nombre                AS comercio,
       c.nombre_corto,
       o.id_comercio,
       a.id_producto,
       p.descripcion           AS producto,
       a.sku_comercio,
       a.ean,
       a.nombre_original,
       a.marca_std             AS marca,
       a.laboratorio_std       AS laboratorio,
       a.subcategoria,
       a.principio_activo_std  AS principio_activo,
       a.concentracion_std     AS concentracion,
       a.forma_std             AS forma,
       a.unidades,
       a.contenido,
       a.unidad_contenido,
       a.contenido_total,
       a.unidad_normalizada,
       o.precio,
       o.precio_lista,
       o.promocion,
       o.disponible,
       o.disponibilidad,
       o.precio / a.contenido_total AS precio_unitario,   -- COP por mL, g o unidad
       a.url_producto,
       o.url_extraccion,
       o.texto_original,
       o.fecha_consulta,
       a.comparable,
       o.descartada,
       o.motivo_descarte
FROM observaciones o
JOIN anuncios  a ON a.id_comercio = o.id_comercio AND a.sku_comercio = o.sku_comercio
JOIN comercios c ON c.id_comercio = o.id_comercio
LEFT JOIN productos p ON p.id_producto = a.id_producto;

-- Ejecuciones en que TODOS los comercios activos quedaron 'completa' (§3.3).
DROP VIEW IF EXISTS v_ejecuciones_completas;
CREATE VIEW v_ejecuciones_completas AS
SELECT e.id_ejecucion,
       MIN(e.inicio)          AS inicio,
       MAX(e.fin)             AS fin,
       SUBSTR(MIN(e.inicio), 1, 10) AS fecha
FROM ejecuciones e
JOIN comercios c ON c.id_comercio = e.id_comercio AND c.activo = 1
GROUP BY e.id_ejecucion
HAVING SUM(e.estado = 'completa') = (SELECT COUNT(*) FROM comercios WHERE activo = 1);

-- Último estado conocido de cada anuncio (su observación más reciente no descartada).
DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
SELECT *
FROM (SELECT v.*,
             ROW_NUMBER() OVER (PARTITION BY v.id_comercio, v.sku_comercio
                                ORDER BY v.fecha_consulta DESC) AS orden
      FROM v_observaciones v
      WHERE v.descartada = 0)
WHERE orden = 1;

-- Cambios de precio de un mismo anuncio entre observaciones consecutivas
-- (LAG por anuncio, en orden de fecha). Solo filas en que el precio cambió.
DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
WITH serie AS (
    SELECT o.id_ejecucion, o.id_comercio, o.sku_comercio, o.fecha_consulta, o.precio,
           LAG(o.id_ejecucion)   OVER w AS id_ejecucion_anterior,
           LAG(o.fecha_consulta) OVER w AS fecha_anterior,
           LAG(o.precio)         OVER w AS precio_anterior
    FROM observaciones o
    JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.id_comercio = o.id_comercio
    WHERE o.descartada = 0 AND e.estado <> 'fallida'
    WINDOW w AS (PARTITION BY o.id_comercio, o.sku_comercio ORDER BY o.fecha_consulta)
)
SELECT s.id_ejecucion,
       s.id_comercio,
       c.nombre_corto AS comercio,
       s.sku_comercio,
       a.nombre_original,
       a.id_producto,
       a.subcategoria,
       s.id_ejecucion_anterior,
       s.fecha_anterior,
       s.precio_anterior,
       s.fecha_consulta,
       s.precio,
       s.precio - s.precio_anterior                                  AS cambio_cop,
       ROUND(100.0 * (s.precio - s.precio_anterior) / s.precio_anterior, 2) AS cambio_pct,
       CASE WHEN s.precio > s.precio_anterior THEN 'subió' ELSE 'bajó' END AS direccion
FROM serie s
JOIN anuncios  a ON a.id_comercio = s.id_comercio AND a.sku_comercio = s.sku_comercio
JOIN comercios c ON c.id_comercio = s.id_comercio
WHERE s.precio IS NOT NULL
  AND s.precio_anterior IS NOT NULL
  AND s.precio <> s.precio_anterior;

-- Observaciones de las presentaciones comparables (P01...) con su precio por
-- unidad de contenido. El contenido sale de productos (verificado a mano).
DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT v.id_observacion,
       v.id_ejecucion,
       v.fecha_consulta,
       v.id_comercio,
       v.nombre_corto        AS comercio,
       v.id_producto,
       p.descripcion         AS producto,
       p.principio_activo,
       v.sku_comercio,
       v.nombre_original,
       p.contenido_total,
       p.unidad_normalizada,
       v.precio,
       v.precio_lista,
       v.promocion,
       v.disponibilidad,
       v.precio / p.contenido_total AS precio_unitario,
       v.url_producto
FROM v_observaciones v
JOIN productos p ON p.id_producto = v.id_producto
WHERE v.comparable = 1
  AND v.descartada = 0;

-- Situación de cada anuncio en cada ejecución (§3.5): 'disponible', 'agotado' (lo
-- dice el sitio) o 'no observado' (el anuncio ya se había visto en ese comercio,
-- pero no apareció en esta ejecución). 'no observado' NO significa agotado.
DROP VIEW IF EXISTS v_disponibilidad;
CREATE VIEW v_disponibilidad AS
SELECT o.id_ejecucion, o.id_comercio, o.sku_comercio, o.disponibilidad AS situacion
FROM observaciones o
WHERE o.descartada = 0
UNION ALL
SELECT e.id_ejecucion, e.id_comercio, a.sku_comercio, 'no observado' AS situacion
FROM ejecuciones e
JOIN anuncios a ON a.id_comercio = e.id_comercio
WHERE e.estado <> 'fallida'
  AND EXISTS (SELECT 1 FROM observaciones o1
              WHERE o1.id_comercio = a.id_comercio AND o1.sku_comercio = a.sku_comercio
                AND o1.fecha_consulta < e.inicio)
  AND NOT EXISTS (SELECT 1 FROM observaciones o2
                  WHERE o2.id_ejecucion = e.id_ejecucion
                    AND o2.id_comercio = a.id_comercio AND o2.sku_comercio = a.sku_comercio);

-- Resumen de cada ejecución y comercio (lo que muestra la aplicación al actualizar).
DROP VIEW IF EXISTS v_resumen_ejecucion;
CREATE VIEW v_resumen_ejecucion AS
SELECT e.id_ejecucion,
       e.id_comercio,
       c.nombre_corto AS comercio,
       e.modo,
       e.estado,
       e.inicio,
       e.fin,
       (SELECT COUNT(*) FROM observaciones o
        WHERE o.id_ejecucion = e.id_ejecucion AND o.id_comercio = e.id_comercio
          AND o.descartada = 0)                                       AS recolectados,
       (SELECT COUNT(*) FROM observaciones o
        WHERE o.id_ejecucion = e.id_ejecucion AND o.id_comercio = e.id_comercio
          AND o.descartada = 0
          AND NOT EXISTS (SELECT 1 FROM observaciones o0
                          WHERE o0.id_comercio = o.id_comercio
                            AND o0.sku_comercio = o.sku_comercio
                            AND o0.fecha_consulta < o.fecha_consulta)) AS nuevos,
       (SELECT COUNT(*) FROM v_cambios_precio v
        WHERE v.id_ejecucion = e.id_ejecucion AND v.id_comercio = e.id_comercio) AS cambios_precio,
       (SELECT COUNT(*) FROM v_disponibilidad d
        WHERE d.id_ejecucion = e.id_ejecucion AND d.id_comercio = e.id_comercio
          AND d.situacion = 'no observado')                            AS no_observados,
       (SELECT COUNT(*) FROM rechazos r
        WHERE r.id_ejecucion = e.id_ejecucion AND r.id_comercio = e.id_comercio) AS rechazados,
       e.detalle
FROM ejecuciones e
JOIN comercios c ON c.id_comercio = e.id_comercio;
