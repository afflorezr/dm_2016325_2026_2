# testthat carga este archivo antes de las pruebas. Las pruebas corren con
# tests/ como directorio de trabajo, por eso los archivos se leen con "../".
# Nunca se usa comparador_precios.sqlite ni se consultan los sitios: las
# funciones de scraping se reemplazan por datos pequeños.

suppressMessages(source("../scraper.R"))   # módulos del Taller 1 (R/)
source("../db.R")
source("../validacion.R")
source("../analisis.R")
source("../actualizacion.R")

# Base temporal con el esquema del Taller 1 + lo del Taller 2
base_temporal <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- abrir_conexion(ruta, crear = TRUE)
  crear_esquema(con)
  db_inicializar(con, "../sql/esquema_taller2.sql")
  list(con = con, ruta = ruta, raw = tempfile("raw_"))
}

# Observaciones pequeñas con las columnas que entrega el scraper del Taller 1.
# Crea también la copia "cruda" en raw/{clave}/ para que pasen la validación.
obs_prueba <- function(skus, precios, fecha, id_ejecucion, dir_raw, clave = "farmatodo") {
  archivo <- paste0(id_ejecucion, "_001_categoria_prueba_p001.json.gz")
  dir.create(file.path(dir_raw, clave, "2026-11-10"), recursive = TRUE, showWarnings = FALSE)
  writeLines("{}", file.path(dir_raw, clave, "2026-11-10", archivo))
  data.frame(
    comercio = COMERCIOS[[clave]]$nombre, sku_comercio = skus,
    producto_nombre_original = paste("Loratadina 10 mg x 10 tabletas", skus),
    marca_estandarizada = "Genfar", subcategoria_estandar = "Antihistamínicos",
    contenido_num = 10, unidad_medida = "unidad", precio_cop = precios,
    precio_regular_cop = precios, es_promocion = 0L,
    url_producto = paste0("https://tienda.example/p/", skus), fecha_hora_consulta = fecha,
    id_ejecucion = id_ejecucion, presentacion_original = NA, descripcion_original = NA,
    ficha_tecnica_original = NA, categoria_origen = "prueba", url_consulta = NA,
    archivo_raw = archivo, disponible = 1L, stringsAsFactors = FALSE
  )
}

# Reemplazo del scraper: devuelve siempre los mismos datos con el id que recibe
scraper_falso <- function(skus, precios, fecha, dir_raw) {
  function(clave, sin_conexion, id_ejecucion) {
    obs_prueba(skus, precios, fecha, id_ejecucion, dir_raw, clave)
  }
}

actualizar_prueba <- function(b, recolectar, id, comercios = "farmatodo") {
  suppressWarnings(ejecutar_actualizacion(b$ruta, comercios = comercios, recolectar = recolectar,
                                          pausa = 0, esperar_minutos = 0, dir_raw = b$raw,
                                          id_ejecucion = id))
}
