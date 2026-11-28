# Se carga automáticamente antes de las pruebas (testthat::test_dir("tests")).
# Las pruebas usan datos pequeños escritos aquí y una base temporal: nunca la
# base de la entrega ni los sitios de los comercios.
suppressPackageStartupMessages({
  source("../validacion.R", encoding = "UTF-8")
  options(comparador.dir = "..")
  source("../scraper.R", encoding = "UTF-8")
  source("../db.R", encoding = "UTF-8")
})

# Un anuncio en el formato común que devuelven los scrapers
anuncio_prueba <- function(comercio, sku, ean, nombre, precio, fecha,
                           disponible = 1L, precio_lista = precio,
                           url = paste0("https://ejemplo.test/", comercio, "/", sku)) {
  cont <- extraer_contenido(nombre)
  tibble::tibble(
    comercio = comercio, seccion = "prueba", sku = sku, ean = ean, ean_alt = NA_character_,
    nombre = nombre, marca = NA_character_, subcategoria = "Salud visual > Soluciones",
    contenido = cont$contenido, unidad = cont$unidad, n_unidades = extraer_unidades(nombre),
    precio = precio, precio_lista = precio_lista,
    promocion = as.integer(isTRUE(precio_lista > precio)), disponible = as.integer(disponible),
    url = url, texto_original = paste(nombre, "| | descripción de prueba"),
    fecha_hora_consulta = fecha
  )
}

OPTI <- "Solución Opti-Free PureMoist Frasco x 120 ml"
RENU <- "Renu Fresh Solución Multipropósito Frasco x 120 ml"

# Datos de un comercio: dos presentaciones comparables (mismo EAN en los tres)
datos_comercio <- function(comercio, fecha, p_opti, p_renu = 25000, con_renu = TRUE,
                           renu_disponible = 1L) {
  d <- anuncio_prueba(comercio, paste0(comercio, "-1"), "0300653610800", OPTI, p_opti, fecha)
  if (con_renu) {
    d <- dplyr::bind_rows(d, anuncio_prueba(comercio, paste0(comercio, "-2"), "310119033227",
                                            RENU, p_renu, fecha, disponible = renu_disponible))
  }
  d
}

# Base temporal con una o dos ejecuciones cargadas por el mismo camino que usa
# ejecutar_recoleccion() (validación + transacción por comercio)
base_temporal <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- conectar_db(ruta)
  attr(con, "ruta") <- ruta
  con
}

cargar_ejecucion <- function(con, corrida, lista_datos) {
  filas <- lapply(names(lista_datos), function(com) {
    cargar_comercio(con, lista_datos[[com]], corrida, com, "en_linea",
                    total = nrow(lista_datos[[com]]))
  })
  suppressMessages(actualizar_correspondencia(con))
  dplyr::bind_rows(filas)
}

F1 <- "2026-10-11T20:00:00-05:00"
F2 <- "2026-11-15T18:00:00-05:00"
