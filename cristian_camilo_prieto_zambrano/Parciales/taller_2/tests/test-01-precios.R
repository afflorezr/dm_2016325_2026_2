# 1. Precio de la respuesta de un sitio a número
# Las APIs de los tres comercios entregan los precios como números. La regla
# que se aplica es que un precio 0, vacío, ausente o no numérico queda NA
# (sin precio publicado), nunca 0.

test_that("un precio numérico se conserva", {
  expect_equal(limpiar_precio(12900), 12900)
  expect_equal(limpiar_precio(8155.5), 8155.5)
  expect_equal(limpiar_precio("12900"), 12900)     # número que llega como texto
})

test_that("precio 0, negativo, ausente o no numérico queda NA, nunca 0", {
  expect_identical(limpiar_precio(0), NA_real_)
  expect_identical(limpiar_precio(-100), NA_real_)
  expect_identical(limpiar_precio(NULL), NA_real_)
  expect_identical(limpiar_precio(list()), NA_real_)
  expect_identical(limpiar_precio(NA), NA_real_)
  expect_identical(limpiar_precio("sin precio"), NA_real_)
})

test_that("los parsers aplican la regla: oferta en 0 usa el precio de lista", {
  hit <- list(fullPrice = 50000, offerPrice = 0, mediaDescription = "Ensure Advance Vainilla x 400 gr",
              id = "1", stores_with_stock = list("a"))
  pag <- list(texto = jsonlite::toJSON(list(hits = list(hit)), auto_unbox = TRUE),
              seccion = "nutricion", fecha_hora = "2026-11-15T10:00:00-05:00")
  d <- parsear_farmatodo(list(pag))
  expect_equal(d$precio, 50000)
  expect_equal(d$promocion, 0L)
})
