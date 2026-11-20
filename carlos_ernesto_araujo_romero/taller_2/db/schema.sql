-- =============================================================================
-- Esquema de la base del comparador de precios (Taller 2).
-- Curso: Minería de Datos — Universidad Nacional de Colombia.
--
-- Es la base del Taller 1 más los objetos del Taller 2:
--   * disponibilidad en tres estados y contenido normalizado (g, mL, unidad),
--   * tabla correcciones y registro de observaciones rechazadas,
--   * restricción de unicidad por ejecución y comercio,
--   * índices para los filtros de la aplicación.
-- Las vistas de la aplicación viven en db/vistas.sql.
-- =============================================================================

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS comercios (
  id_comercio            TEXT PRIMARY KEY,
  nombre                 TEXT NOT NULL,
  url_base               TEXT NOT NULL,
  grupo                  TEXT,
  categoria_equivalente  TEXT,
  robots_url             TEXT,
  activo                 INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1)),
  motivo_estado          TEXT,
  notas                  TEXT
);

CREATE TABLE IF NOT EXISTS ejecuciones (
  id_ejecucion             TEXT PRIMARY KEY,
  fecha_inicio             TEXT NOT NULL,
  fecha_fin                TEXT,
  modo                     TEXT NOT NULL CHECK (modo IN ('online', 'offline')),
  estado                   TEXT NOT NULL CHECK (estado IN ('en_curso', 'completa', 'parcial', 'fallida')),
  n_registros              INTEGER NOT NULL DEFAULT 0,
  n_obs_comparables        INTEGER NOT NULL DEFAULT 0,
  n_productos_comparables  INTEGER NOT NULL DEFAULT 0,
  n_comercios              INTEGER NOT NULL DEFAULT 0,
  notas                    TEXT
);

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

CREATE TABLE IF NOT EXISTS productos_comparables (
  id_producto_comun   TEXT PRIMARY KEY,
  nombre_canonico     TEXT NOT NULL,
  marca               TEXT NOT NULL,
  variante            TEXT NOT NULL,
  contenido_valor     REAL,
  contenido_unidad    TEXT,
  contenido_total     REAL,
  unidad_normalizada  TEXT CHECK (unidad_normalizada IN ('g', 'mL', 'unidad')),
  subcategoria        TEXT NOT NULL,
  unidad_base         TEXT,
  justificacion       TEXT,
  fecha_creacion      TEXT,
  vigente             INTEGER NOT NULL DEFAULT 1 CHECK (vigente IN (0, 1))
);

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
  contenido_total        REAL,
  unidad_normalizada     TEXT CHECK (unidad_normalizada IN ('g', 'mL', 'unidad')),
  contenido_origen       TEXT,
  unidades_por_paquete   INTEGER,
  empaque_mencionado     INTEGER,
  precio_cop             REAL,
  precio_lista_cop       REAL,
  es_promocion           INTEGER NOT NULL DEFAULT 0 CHECK (es_promocion IN (0, 1)),
  descuento_pct          REAL,
  disponible             INTEGER NOT NULL DEFAULT 0 CHECK (disponible IN (0, 1)),
  estado_disponibilidad  TEXT NOT NULL DEFAULT 'no_observado'
                         CHECK (estado_disponibilidad IN ('disponible', 'agotado', 'no_observado')),
  precio_por_unidad      REAL,
  unidad_precio          TEXT,
  url_producto           TEXT,
  fecha_consulta         TEXT NOT NULL,
  id_producto_comun      TEXT,
  es_comparable          INTEGER NOT NULL DEFAULT 0 CHECK (es_comparable IN (0, 1)),
  FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion),
  FOREIGN KEY (id_comercio) REFERENCES comercios(id_comercio),
  FOREIGN KEY (id_producto_comun) REFERENCES productos_comparables(id_producto_comun),
  CHECK (precio_cop IS NULL OR precio_cop > 0),
  CHECK (contenido_valor IS NULL OR contenido_valor > 0),
  CHECK (unidades_por_paquete IS NULL OR unidades_por_paquete > 0)
);

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

-- Correcciones documentadas sobre la entrega del Taller 1 o sobre ejecuciones
-- posteriores. Nunca se modifica una observación sin dejar rastro aquí.
CREATE TABLE IF NOT EXISTS correcciones (
  id_correccion   INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha           TEXT NOT NULL,
  tabla           TEXT NOT NULL,
  campo           TEXT NOT NULL,
  id_registro     TEXT NOT NULL,
  valor_anterior  TEXT,
  valor_nuevo     TEXT,
  motivo          TEXT NOT NULL,
  id_ejecucion    TEXT,
  autor           TEXT
);

-- Observaciones que no pasaron las reglas de validación antes de insertarse.
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
  id_rechazo      INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha           TEXT NOT NULL,
  id_ejecucion    TEXT,
  id_comercio     TEXT,
  sku_comercio    TEXT,
  texto_original  TEXT,
  precio_cop      REAL,
  motivo          TEXT NOT NULL,
  detalle         TEXT
);

-- ---------------------------------------------------------------------------
-- Restricciones de unicidad e índices
-- ---------------------------------------------------------------------------

-- Una misma observación (comercio + anuncio) no puede entrar dos veces en la
-- misma ejecución, aunque cambie el segundo de consulta.
CREATE UNIQUE INDEX IF NOT EXISTS ux_observaciones_ejecucion_anuncio
  ON observaciones (id_ejecucion, id_comercio, sku_comercio);

-- Una sola fila comparable por producto y comercio en cada ejecución.
CREATE UNIQUE INDEX IF NOT EXISTS ux_observaciones_comparable
  ON observaciones (id_ejecucion, id_comercio, id_producto_comun)
  WHERE es_comparable = 1;

CREATE INDEX IF NOT EXISTS ix_observaciones_ejecucion
  ON observaciones (id_ejecucion, es_comparable, disponible);
CREATE INDEX IF NOT EXISTS ix_observaciones_producto
  ON observaciones (id_producto_comun, id_comercio, fecha_consulta);
CREATE INDEX IF NOT EXISTS ix_observaciones_comercio
  ON observaciones (id_comercio, fecha_consulta);
CREATE INDEX IF NOT EXISTS ix_observaciones_subcategoria
  ON observaciones (subcategoria, precio_cop);
CREATE INDEX IF NOT EXISTS ix_observaciones_marca
  ON observaciones (marca, precio_cop);
CREATE INDEX IF NOT EXISTS ix_observaciones_precio
  ON observaciones (precio_cop);
CREATE INDEX IF NOT EXISTS ix_observaciones_promocion
  ON observaciones (es_promocion, id_ejecucion);
CREATE INDEX IF NOT EXISTS ix_observaciones_fecha
  ON observaciones (fecha_consulta);
CREATE INDEX IF NOT EXISTS ix_ejecuciones_fecha
  ON ejecuciones (fecha_inicio, estado);
CREATE INDEX IF NOT EXISTS ix_descartes_ejecucion
  ON descartes (id_ejecucion, id_comercio, motivo);
CREATE INDEX IF NOT EXISTS ix_rechazadas_ejecucion
  ON observaciones_rechazadas (id_ejecucion, id_comercio, motivo);
CREATE INDEX IF NOT EXISTS ix_correcciones_fecha
  ON correcciones (fecha, tabla);
