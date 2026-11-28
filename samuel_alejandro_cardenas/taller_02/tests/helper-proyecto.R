raices <- c(".", "..", "../..")
raiz_t2 <- raices[vapply(raices, function(p) {
  file.exists(file.path(p, "scraper.R")) &&
    file.exists(file.path(p, "validacion.R")) &&
    file.exists(file.path(p, "db.R"))
}, logical(1))][1L]
if (is.na(raiz_t2)) stop("Ejecuta las pruebas desde la carpeta taller_2 del proyecto.")

source(file.path(raiz_t2, "scraper.R"), local = TRUE)
source(file.path(raiz_t2, "validacion.R"), local = TRUE)
source(file.path(raiz_t2, "db.R"), local = TRUE)

con_base_temporal <- function(prueba) {
  ruta <- tempfile(pattern = "test_t2_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta)
  entorno_db <- environment(conectar_consulta)
  original <- get("RUTA_BD", envir = entorno_db, inherits = TRUE)
  on.exit({
    assign("RUTA_BD", original, envir = entorno_db)
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
    unlink(ruta)
  }, add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE observaciones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_ejecucion TEXT NOT NULL,
      comercio TEXT NOT NULL,
      sku TEXT NOT NULL,
      producto_original TEXT NOT NULL,
      precio REAL NOT NULL,
      fecha_consulta TEXT NOT NULL,
      id_comun TEXT,
      comparable INTEGER NOT NULL DEFAULT 0,
      disponibilidad TEXT,
      UNIQUE (id_ejecucion, comercio, sku)
    )
  ")
  DBI::dbExecute(con, "
    CREATE VIEW v_comparables AS
      SELECT id_ejecucion, comercio, sku, id_comun, precio, disponibilidad
      FROM observaciones WHERE comparable = 1
  ")
  assign("RUTA_BD", ruta, envir = entorno_db)
  prueba(con)
}

insertar_prueba <- function(con, comercio, sku, id_comun, ejecucion, precio,
                           disponibilidad = "disponible", fecha = "2026-11-11T15:00:00-05:00") {
  DBI::dbExecute(con, "
    INSERT OR IGNORE INTO observaciones
    (id_ejecucion, comercio, sku, producto_original, precio,
     fecha_consulta, id_comun, comparable, disponibilidad)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
  ", params = list(ejecucion, comercio, sku, sku, as.numeric(precio),
                   fecha, id_comun, disponibilidad))
}
