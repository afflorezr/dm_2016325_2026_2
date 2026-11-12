# Utilidades de las pruebas: módulos del proyecto, base temporal y copias crudas de juguete.
# Nada de esto toca la base de la entrega ni consulta los sitios.
source("../limpieza.R", encoding = "UTF-8"); source("../validacion.R", encoding = "UTF-8"); source("../scraper.R", encoding = "UTF-8"); source("../db.R", encoding = "UTF-8")

EAN <- c(crema = "7509546000350", cepillo = "7702010631795", enjuague = "7891024130957")

base_temporal <- function(env = parent.frame()) {
  ruta <- withr::local_tempfile(fileext = ".sqlite", .local_envir = env)
  con <- conectar(ruta, esquema = "../esquema.sql")
  withr::defer(DBI::dbDisconnect(con), envir = env)
  list(ruta = ruta, con = con)
}

# Escribe en `raw_dir` una ejecución de un comercio con el formato real (manifest + JSON de VTEX).
# productos: data.frame(sku, nombre, ean, precio, disponible)
escribir_raw <- function(raw_dir, cid, ejecucion_id, productos, fecha = "2026-11-01", hora = "10:00:00") {
  carpeta <- file.path(raw_dir, cid, fecha, ejecucion_id)
  dir.create(carpeta, recursive = TRUE, showWarnings = FALSE)
  json <- lapply(seq_len(nrow(productos)), function(i) list(
    productId = paste0("P", productos$sku[i]), productName = productos$nombre[i], brand = "Colgate",
    categories = list("/Cuidado personal/Cuidado oral/"), link = paste0("https://ejemplo.test/", productos$sku[i], "/p"),
    items = list(list(itemId = productos$sku[i], name = productos$nombre[i], ean = productos$ean[i],
      sellers = list(list(sellerDefault = TRUE, sellerName = "Tienda", commertialOffer = list(
        Price = productos$precio[i], ListPrice = productos$precio[i], IsAvailable = productos$disponible[i])))))))
  .escribir_gz(charToRaw(enc2utf8(as.character(jsonlite::toJSON(json, auto_unbox = TRUE, null = "null")))),
               file.path(carpeta, "0001_productos_s1.json.gz"))
  marca <- sprintf("%sT%s-05:00", fecha, hora)
  man <- list(ejecucion_id = ejecucion_id, comercio_id = cid, comercio = COMERCIOS[[cid]][1], url_base = COMERCIOS[[cid]][3],
              inicio = marca, fin = marca, user_agent = "pruebas",
              secciones = list(list(seccion_id = "1", nombre = "Cuidado oral", ruta_nombres = "Cuidado oral", filtro = "/1/",
                                    url = NULL, api = "catalogo", total_reportado = nrow(productos))),
              peticiones = list(list(archivo = "0001_productos_s1.json.gz", tipo = "productos", seccion_id = "1",
                                     url = paste0(COMERCIOS[[cid]][3], "/api/prueba"), params = NULL,
                                     fecha_hora_consulta = marca, status = 200, resources = NULL, bytes = 1)),
              errores = list())
  writeLines(jsonlite::toJSON(man, auto_unbox = TRUE, null = "null"), file.path(carpeta, "manifest.json"))
  invisible(carpeta)
}

# Tres productos en los tres comercios. `precios`: lista por comercio con los precios de crema, cepillo y enjuague.
productos_prueba <- function(cid, precios, disponibles = c(TRUE, TRUE, TRUE)) {
  data.frame(sku = paste0(substr(cid, 1, 2), 1:3),
             nombre = c("Crema dental Colgate Triple Accion 3 x 75 ml", "Cepillo dental Colgate Medio x 5 und",
                        "Enjuague bucal Colgate Plax Soft Mint 500 ml"),
             ean = unname(EAN), precio = precios, disponible = disponibles, stringsAsFactors = FALSE)
}

cargar_ejecucion <- function(b, raw_dir, ejecucion_id, precios, fecha = "2026-11-01", disponibles = NULL, comercios = names(precios)) {
  for (cid in names(precios)) {
    escribir_raw(raw_dir, cid, ejecucion_id, productos_prueba(cid, precios[[cid]], disponibles[[cid]] %||% c(TRUE, TRUE, TRUE)), fecha)
  }
  ejecutar_recoleccion(comercios, "sin_conexion", b$ruta, raw_dir, ejecucion_id, verbose = FALSE,
                       esquema = "../esquema.sql", ruta_manual = "no_existe.csv")
}
id_producto <- function(con, nombre) {
  DBI::dbGetQuery(con, "SELECT producto_id FROM productos WHERE nombre_estandar LIKE ?", params = list(paste0("%", nombre, "%")))$producto_id[1]
}
