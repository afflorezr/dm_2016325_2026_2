# =============================================================================
# tests/helper-fixtures.R  -  Carga del codigo del proyecto y fixtures comunes
# testthat::test_dir("tests") lo sourcea antes de correr los archivos test-*.
# Usa SOLO bases temporales: nunca la base de la entrega.
# =============================================================================

if (!exists("ejecutar_scraper", mode = "function")) {
  base <- if (file.exists("scraper.R")) "." else ".."
  source(file.path(base, "validacion.R"))
  source(file.path(base, "scraper.R"))
  source(file.path(base, "db.R"))
}

crear_base_temporal <- function() {
  ruta <- tempfile(pattern = "test_comparador_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta)
  inicializar_db(con)
  list(ruta = ruta, con = con)
}

# Una observacion valida por defecto; se sobreescribe lo que el test necesite.
obs <- function(comercio = "Farmatodo", url = "https://ejemplo.com/p/1",
                precio = 12000, fecha = "2026-11-10T10:00:00-05:00",
                ejec = "ejec_test", producto = "Jabon Bebe 200 ml",
                marca = "Marca", comparable = 0L,
                id_comun = NA_character_) {
  data.frame(
    comercio = comercio, producto = producto,
    texto_original = paste(producto, "|", marca),
    marca = marca, subcategoria = "Jabón",
    contenido_valor = 200, contenido_unidad = "ml",
    precio_cop = precio, precio_antes = NA_real_, en_promocion = 0L,
    sku = "123", disponibilidad = "disponible",
    url = url, fecha_consulta = fecha, id_ejecucion = ejec,
    comparable = comparable, id_comun = id_comun,
    stringsAsFactors = FALSE
  )
}

info_de <- function(df, ejec = df$id_ejecucion[1], fecha = df$fecha_consulta[1]) {
  list(id_ejecucion = ejec, comercio = df$comercio[1], modo = "offline",
       fecha_consulta = fecha, origen_raw = NA_character_,
       tarjetas = nrow(df), rechazados = 0L, estado = "exitosa",
       motivo = NA_character_)
}
