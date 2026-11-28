# Minería de Datos 2016325 - Taller 2
# Paso 11: ampliación controlada de la base SQLite.
# No ejecuta scraping, no altera los precios existentes y no modifica taller_01.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

preparar_estructura_taller2 <- function(
    db_path = "comparador_precios.sqlite",
    backup_path = "comparador_precios_respaldo_taller2.sqlite") {

  if (!file.exists(db_path) || !file.exists(backup_path)) {
    stop("Falta la base o su respaldo. No se aplicaron cambios.")
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON;")

  integridad <- DBI::dbGetQuery(con, "PRAGMA integrity_check;")[[1]][1]
  if (!identical(integridad, "ok")) stop("La base no supera integrity_check.")

  requeridas <- c("comercios", "ejecuciones", "anuncios", "observaciones", "productos_comunes")
  if (!all(requeridas %in% DBI::dbListTables(con))) {
    stop("Faltan tablas principales de Taller 1. No se aplicaron cambios.")
  }

  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS correcciones (
        correccion_id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha_correccion TEXT NOT NULL,
        tabla_afectada TEXT NOT NULL,
        registro_id TEXT NOT NULL,
        campo TEXT NOT NULL,
        valor_anterior TEXT,
        valor_nuevo TEXT,
        motivo TEXT NOT NULL,
        evidencia_raw TEXT
      );
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
        rechazo_id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha_rechazo TEXT NOT NULL,
        observacion_id INTEGER,
        ejecucion_id TEXT NOT NULL,
        comercio_id INTEGER NOT NULL,
        producto_comercio_id TEXT,
        motivo TEXT NOT NULL,
        evidencia_raw TEXT,
        origen TEXT NOT NULL CHECK (origen IN ('historico', 'nueva_extraccion')),
        FOREIGN KEY (observacion_id) REFERENCES observaciones(observacion_id),
        FOREIGN KEY (comercio_id) REFERENCES comercios(comercio_id)
      );
    ")

    campos <- DBI::dbListFields(con, "observaciones")
    if (!"estado_validacion" %in% campos) {
      DBI::dbExecute(con, "
        ALTER TABLE observaciones
        ADD COLUMN estado_validacion TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado_validacion IN ('pendiente', 'valida', 'rechazada'));
      ")
    }
    if (!"estado_disponibilidad" %in% campos) {
      DBI::dbExecute(con, "
        ALTER TABLE observaciones
        ADD COLUMN estado_disponibilidad TEXT NOT NULL DEFAULT 'sin_evidencia'
        CHECK (estado_disponibilidad IN ('sin_evidencia', 'disponible', 'agotado'));
      ")
    }
    if (!"evidencia_raw" %in% campos) {
      DBI::dbExecute(con, "ALTER TABLE observaciones ADD COLUMN evidencia_raw TEXT;")
    }

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_obs_ejecucion_comercio ON observaciones(ejecucion_id, comercio_id);")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_obs_fecha ON observaciones(fecha_hora_consulta);")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_anuncios_comparables ON anuncios(producto_comun_id, comercio_id);")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_anuncios_filtros ON anuncios(comercio_id, incluido_categoria, comparable, subcategoria_estandar, marca_estandar);")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ejecuciones_fecha ON ejecuciones(fecha_hora_inicio);")
  })

  print(DBI::dbGetQuery(con, "PRAGMA integrity_check;"))
  print(DBI::dbGetQuery(con, "PRAGMA foreign_key_check;"))
  print(DBI::dbGetQuery(con, "SELECT COUNT(*) AS observaciones FROM observaciones;"))
  print(DBI::dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('correcciones', 'observaciones_rechazadas');"))
  print(DBI::dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY name;"))
  invisible(TRUE)
}

preparar_estructura_taller2()
