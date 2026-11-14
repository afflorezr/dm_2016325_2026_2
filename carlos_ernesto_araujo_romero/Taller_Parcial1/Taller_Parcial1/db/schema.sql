-- Esquema de la base de datos del comparador de precios de confitería.
-- SQLite 3. Se puede crear desde cero con crear_esquema() en scraper.R.

PRAGMA foreign_keys = ON;

-- 1. Comercios participantes
CREATE TABLE IF NOT EXISTS comercios (
  id_comercio        TEXT PRIMARY KEY,
  nombre             TEXT NOT NULL,
  url_base           TEXT NOT NULL,
  grupo              TEXT,
  categoria_equivalente TEXT,
  robots_url         TEXT,
  notas              TEXT
);

-- 2. Ejecuciones de recolección (una fila por corrida del scraper)
CREATE TABLE IF NOT EXISTS ejecuciones (
  id_ejecucion       TEXT PRIMARY KEY,
  fecha_inicio       TEXT NOT NULL,
  fecha_fin          TEXT,
  modo               TEXT NOT NULL CHECK (modo IN ('online', 'offline')),
  estado             TEXT NOT NULL CHECK (estado IN ('en_curso', 'completa', 'parcial', 'fallida')),
  n_registros        INTEGER NOT NULL DEFAULT 0,
  n_obs_comparables  INTEGER NOT NULL DEFAULT 0,
  n_productos_comparables INTEGER NOT NULL DEFAULT 0,
  n_comercios        INTEGER NOT NULL DEFAULT 0,
  notas              TEXT
);

-- 3. Detalle por comercio dentro de cada ejecución (auditoría y conteos)
CREATE TABLE IF NOT EXISTS ejecuciones_comercio (
  id_ejecucion       TEXT NOT NULL,
  id_comercio        TEXT NOT NULL,
  fecha_inicio       TEXT NOT NULL,
  fecha_fin          TEXT,
  n_paginas          INTEGER,
  n_reportado_sitio  INTEGER,
  n_extraido         INTEGER,
  n_incluido         INTEGER,
  n_excluido         INTEGER,
  n_con_precio       INTEGER,
  estado             TEXT NOT NULL CHECK (estado IN ('en_curso', 'completa', 'parcial', 'fallida')),
  url_categoria      TEXT,
  mensaje            TEXT,
  PRIMARY KEY (id_ejecucion, id_comercio),
  FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion),
  FOREIGN KEY (id_comercio) REFERENCES comercios(id_comercio)
);

-- 4. Detalle por rama de categoría consultada (para conciliar con el sitio)
CREATE TABLE IF NOT EXISTS ejecuciones_categoria (
  id_ejecucion       TEXT NOT NULL,
  id_comercio        TEXT NOT NULL,
  rama               TEXT NOT NULL,
  url_categoria      TEXT NOT NULL,
  n_reportado        INTEGER,
  n_extraido         INTEGER,
  n_incluido         INTEGER,
  n_excluido         INTEGER,
  n_paginas          INTEGER,
  estado             TEXT NOT NULL,
  PRIMARY KEY (id_ejecucion, id_comercio, rama),
  FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion),
  FOREIGN KEY (id_comercio) REFERENCES comercios(id_comercio)
);

-- 5. Catálogo canónico de las presentaciones comparables
CREATE TABLE IF NOT EXISTS productos_comparables (
  id_producto_comun  TEXT PRIMARY KEY,
  nombre_canonico    TEXT NOT NULL,
  marca              TEXT NOT NULL,
  variante           TEXT NOT NULL,
  contenido_valor    REAL,
  contenido_unidad   TEXT,
  subcategoria       TEXT NOT NULL,
  unidad_base        TEXT,
  justificacion      TEXT,
  fecha_creacion     TEXT
);

-- 6. Observaciones: cada producto/presentación de cada comercio en cada ejecución
CREATE TABLE IF NOT EXISTS observaciones (
  id_observacion         INTEGER PRIMARY KEY AUTOINCREMENT,
  id_ejecucion           TEXT NOT NULL,
  id_comercio            TEXT NOT NULL,
  id_producto_comercio   TEXT,
  sku_comercio           TEXT NOT NULL,
  texto_original         TEXT NOT NULL,
  descripcion_original   TEXT,
  especificaciones_json  TEXT,
  marca                  TEXT,
  categoria_sitio        TEXT,
  subcategoria           TEXT,
  contenido_valor        REAL,
  contenido_unidad       TEXT,
  contenido_origen       TEXT,
  unidades_por_paquete   INTEGER,
  empaque_mencionado     INTEGER,
  precio_cop             REAL,
  precio_lista_cop       REAL,
  es_promocion           INTEGER NOT NULL DEFAULT 0 CHECK (es_promocion IN (0, 1)),
  descuento_pct          REAL,
  disponible             INTEGER NOT NULL DEFAULT 0 CHECK (disponible IN (0, 1)),
  precio_por_unidad      REAL,
  unidad_precio          TEXT,
  url_producto           TEXT,
  fecha_consulta         TEXT NOT NULL,
  id_producto_comun      TEXT,
  es_comparable          INTEGER NOT NULL DEFAULT 0 CHECK (es_comparable IN (0, 1)),
  FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion),
  FOREIGN KEY (id_comercio) REFERENCES comercios(id_comercio),
  FOREIGN KEY (id_producto_comun) REFERENCES productos_comparables(id_producto_comun),
  UNIQUE (id_comercio, sku_comercio, fecha_consulta),
  CHECK (precio_cop IS NULL OR precio_cop > 0),
  CHECK (contenido_valor IS NULL OR contenido_valor > 0),
  CHECK (unidades_por_paquete IS NULL OR unidades_por_paquete > 0)
);

-- Una sola observación comparable por comercio y producto en cada ejecución.
CREATE UNIQUE INDEX IF NOT EXISTS ux_observaciones_comparable
  ON observaciones (id_ejecucion, id_comercio, id_producto_comun)
  WHERE es_comparable = 1;

CREATE INDEX IF NOT EXISTS ix_observaciones_ejecucion
  ON observaciones (id_ejecucion, es_comparable, disponible);

CREATE INDEX IF NOT EXISTS ix_observaciones_producto
  ON observaciones (id_producto_comun, id_comercio, fecha_consulta);

CREATE INDEX IF NOT EXISTS ix_observaciones_comercio
  ON observaciones (id_comercio, fecha_consulta);

-- 7. Correspondencia explícita entre el SKU de cada comercio y el producto canónico
CREATE TABLE IF NOT EXISTS mapeo_productos (
  id_producto_comun  TEXT NOT NULL,
  id_comercio        TEXT NOT NULL,
  sku_comercio       TEXT NOT NULL,
  nombre_comercio    TEXT,
  regla              TEXT,
  confianza          TEXT NOT NULL CHECK (confianza IN ('alta', 'media', 'baja')),
  validado_por       TEXT,
  fecha_validacion   TEXT,
  PRIMARY KEY (id_producto_comun, id_comercio, sku_comercio),
  FOREIGN KEY (id_producto_comun) REFERENCES productos_comparables(id_producto_comun),
  FOREIGN KEY (id_comercio) REFERENCES comercios(id_comercio)
);

-- 8. Registros descartados: exclusiones de categoría, duplicados y faltantes
CREATE TABLE IF NOT EXISTS descartes (
  id_descarte        INTEGER PRIMARY KEY AUTOINCREMENT,
  id_ejecucion       TEXT NOT NULL,
  id_comercio        TEXT,
  sku_comercio       TEXT,
  texto_original     TEXT,
  motivo             TEXT NOT NULL,
  detalle            TEXT,
  fecha_registro     TEXT NOT NULL,
  FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion),
  FOREIGN KEY (id_comercio) REFERENCES comercios(id_comercio)
);

CREATE INDEX IF NOT EXISTS ix_descartes_ejecucion
  ON descartes (id_ejecucion, id_comercio, motivo);

-- 9. Vista de apoyo: observaciones con nombres legibles
CREATE VIEW IF NOT EXISTS v_observaciones AS
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
  o.precio_cop,
  o.precio_lista_cop,
  o.es_promocion,
  o.descuento_pct,
  o.disponible,
  o.precio_por_unidad,
  o.unidad_precio,
  o.url_producto,
  o.fecha_consulta,
  o.es_comparable
FROM observaciones o
JOIN comercios c ON c.id_comercio = o.id_comercio
LEFT JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun;
