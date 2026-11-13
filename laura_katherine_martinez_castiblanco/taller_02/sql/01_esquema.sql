-- =============================================================================
-- 01_esquema.sql · Migración idempotente del Taller 2 (SQLite)
-- Solo AGREGA objetos; no borra ni modifica observaciones del Taller 1.
-- Las tablas ejecuciones, observaciones, descartes, cobertura_sitio,
-- correcciones y productos_comunes ya las crea el scraper (db_crear_esquema).
-- =============================================================================

-- Registro de la validación por lote (una fila por regla y ejecución)
CREATE TABLE IF NOT EXISTS validaciones(
  id_validacion INTEGER PRIMARY KEY AUTOINCREMENT,
  id_ejecucion  TEXT NOT NULL,
  fecha_hora    TEXT NOT NULL,
  regla         TEXT NOT NULL,
  n_evaluadas   INTEGER,
  n_fallidas    INTEGER,
  resultado     TEXT CHECK(resultado IN ('ok','falla','omitida')),
  detalle       TEXT
);

-- Marca de observaciones descartadas a posteriori (sin borrarlas)
CREATE TABLE IF NOT EXISTS obs_descartadas(
  id_obs   INTEGER PRIMARY KEY,
  fecha    TEXT NOT NULL,
  motivo   TEXT NOT NULL
);

-- Metadatos de la app (versión del esquema)
CREATE TABLE IF NOT EXISTS meta_app(
  clave TEXT PRIMARY KEY,
  valor TEXT
);
INSERT OR REPLACE INTO meta_app(clave, valor) VALUES ('esquema_taller2', '2.0');
