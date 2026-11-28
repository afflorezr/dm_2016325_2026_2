# Se ejecuta antes de las pruebas. Las pruebas usan datos pequeños y una base
# temporal: nunca la base de la entrega ni los sitios de los comercios.
# testthat corre desde tests/, por eso las rutas suben un nivel.

library(testthat)
source("../db.R")
source("../scraper.R")   # carga también validacion.R y esquema.R

con_temporal <- function(env = parent.frame()) {
  ruta <- tempfile(fileext = ".sqlite")
  con <- crear_base(ruta)
  withr::defer({ DBI::dbDisconnect(con); unlink(ruta) }, envir = env)
  con
}

# Tabla pequeña con el formato que produce el scraper
datos_prueba <- function(skus = c("A1", "A2"), precios = c(1000, 2000),
                         comercio = "Locatel", ts = "2026-11-01T10:00:00-05:00",
                         id_ejecucion = "locatel_prueba") {
  estandarizar_columnas(tibble::tibble(
    comercio = comercio, sku = skus, ean = NA_character_,
    nombre_original = paste("Producto", skus), marca_original = "MARCA",
    precio = precios, url = paste0("https://ejemplo.test/", skus),
    fecha_hora_consulta = ts, id_ejecucion = id_ejecucion))
}
