test_that("normaliza el contenido a mL y g", {
  x <- extraer_contenido(c("Frasco x 120 ml", "FRASCO X 105 ML", "Solución X 1Lt",
                           "Tarro 2 kg", "Cápsulas 500 mg", "Gafas de lectura"))
  expect_equal(x$contenido, c(120, 105, 1000, 2000, 0.5, NA))
  expect_equal(x$unidad, c("mL", "mL", "mL", "g", "g", NA))
})

test_that("cuenta las unidades del empaque y las gafas quedan en und", {
  expect_equal(extraer_unidades(c("Caja x 30 und", "CAJA X 6 UN", "Frasco x 120 ml")),
               c(30L, 6L, 1L))
  d <- clasificar_productos(anuncio_prueba("locatel", "1", "7506245491472",
                                           "Gafas de lectura Foster Grant +1.50", 39900, F1))
  expect_equal(d$subcategoria_std, "Lentes de lectura")
  expect_equal(c(d$contenido, d$unidad), c("1", "und"))
})
