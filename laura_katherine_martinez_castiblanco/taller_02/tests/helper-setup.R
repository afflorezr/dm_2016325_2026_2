# Se carga automáticamente antes de las pruebas (testthat::test_dir("tests") se ejecuta con tests/ como directorio).
# Las pruebas usan SOLO datos mínimos y una base temporal: nunca la base de la entrega ni los sitios.
library(testthat)
source(file.path("..", "validacion.R"), encoding = "UTF-8")
source(file.path("..", "db.R"), encoding = "UTF-8")
DIR_SQL_PRUEBA <- file.path("..", "sql")

# Esquema mínimo equivalente al que crea el scraper en el Taller 1
crear_db_prueba <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- dbConnect(SQLite(), ruta)
  for (s in c(
    "CREATE TABLE ejecuciones(id_ejecucion TEXT PRIMARY KEY, id_corrida TEXT NOT NULL, comercio TEXT NOT NULL,
       fecha_inicio TEXT NOT NULL, fecha_fin TEXT, modo TEXT NOT NULL, n_registros INTEGER DEFAULT 0,
       n_descartados INTEGER DEFAULT 0, estado TEXT NOT NULL, detalle TEXT)",
    "CREATE TABLE observaciones(id_obs INTEGER PRIMARY KEY AUTOINCREMENT, id_ejecucion TEXT NOT NULL REFERENCES ejecuciones(id_ejecucion),
       comercio TEXT NOT NULL, fecha_hora_consulta TEXT NOT NULL, sku_comercio TEXT NOT NULL, sku_origen TEXT, producto_raw TEXT NOT NULL,
       texto_original_anuncio TEXT, marca_raw TEXT, marca_estandarizada TEXT, subcategoria TEXT, presentacion_raw TEXT, unidades INTEGER,
       volumen_unit_ml REAL, contenido_total_ml REAL, unidad_medida TEXT, precio_cop REAL NOT NULL CHECK(precio_cop > 0),
       precio_lista_cop REAL, es_promocion INTEGER, disponibilidad TEXT, precio_por_litro REAL, url_extraccion TEXT, url_producto TEXT,
       url_imagen TEXT, archivo_raw TEXT, termino_busqueda TEXT, comparable INTEGER DEFAULT 0, id_producto_comun TEXT,
       UNIQUE(comercio, sku_comercio, fecha_hora_consulta), UNIQUE(id_ejecucion, sku_comercio))",
    "CREATE TABLE productos_comunes(id_corrida TEXT NOT NULL, id_producto_comun TEXT NOT NULL, clave_producto TEXT NOT NULL, marca TEXT,
       subcategoria TEXT, variante TEXT, contenido_total_ml REAL, unidades INTEGER, n_comercios INTEGER, lista_comercios TEXT,
       PRIMARY KEY(id_corrida, id_producto_comun))",
    "CREATE TABLE correcciones(id_correccion INTEGER PRIMARY KEY AUTOINCREMENT, fecha TEXT NOT NULL, tabla TEXT NOT NULL,
       id_registro TEXT NOT NULL, campo TEXT NOT NULL, valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT NOT NULL)",
    "CREATE TABLE descartes(id_descarte INTEGER PRIMARY KEY AUTOINCREMENT, id_ejecucion TEXT, comercio TEXT, fecha_hora_consulta TEXT,
       producto_raw TEXT, motivo TEXT NOT NULL, detalle TEXT, archivo_raw TEXT)")) dbExecute(con, s)
  dbDisconnect(con)
  db_migrar(ruta, DIR_SQL_PRUEBA)
  ruta
}

# Observación mínima válida
obs_prueba <- function(id_ej, comercio, sku, precio, fecha, comparable = 0L, id_pc = NA_character_, nombre = "Gaseosa X 1500 ml") {
  data.frame(id_ejecucion = id_ej, comercio = comercio, fecha_hora_consulta = fecha, sku_comercio = sku, producto_raw = nombre,
             marca_estandarizada = "MARCA", subcategoria = "Gaseosas", contenido_total_ml = 1500, unidades = 1L, unidad_medida = "ml",
             precio_cop = precio, es_promocion = 0L, disponibilidad = "disponible", precio_por_litro = precio / 1.5,
             url_producto = paste0("https://ejemplo.test/", sku), comparable = comparable, id_producto_comun = id_pc,
             stringsAsFactors = FALSE)
}
