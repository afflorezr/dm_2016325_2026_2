test_that("convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("12.900,50"), 12900.5)
  expect_equal(limpiar_precio("1,234.5"), 1234.5)
  expect_equal(limpiar_precio(8490), 8490)
  expect_true(is.na(limpiar_precio("agotado")))
  expect_true(is.na(limpiar_precio(0)))            # un precio 0 es un dato ausente, nunca un precio
  expect_true(is.na(limpiar_precio(NULL)))
})

test_that("normaliza las unidades a mL, g y m", {
  expect_equal(normalizar_unidad(1, "l"), list(valor = 1000, unidad = "ml"))
  expect_equal(normalizar_unidad(1.5, "kg"), list(valor = 1500, unidad = "g"))
  expect_equal(normalizar_unidad(50, "yd")$valor, 45.72)
  expect_equal(normalizar_unidad(75, "cc")$unidad, "ml")
})

test_that("extrae contenido, número de unidades y contenido total del nombre", {
  x <- extraer_contenido("Crema dental Colgate Triple Acción 3 x 75 ml")
  expect_equal(c(x$contenido_unitario, x$n_unidades, x$contenido_total), c(75, 3, 225))
  expect_equal(x$unidad, "ml")
  y <- extraer_contenido("Enjuague Listerine 1 L")
  expect_equal(c(y$contenido_total, y$n_unidades), c(1000, 1))
  z <- extraer_contenido("Cepillo dental Colgate Medio x 5 und", subcategoria = "Cepillo dental")
  expect_equal(z$contenido_total, 5); expect_equal(z$unidad, "und")
  expect_true(is.na(extraer_contenido("Hilo dental sin medida")$contenido_total))   # ausente queda ausente
})

test_that("valida el dígito de control del código de barras", {
  expect_equal(gtin_valido("7509546000350"), "07509546000350")
  expect_true(is.na(gtin_valido("7509546000351")))
  expect_true(is.na(gtin_valido("")))
})

test_that("la búsqueda de texto valida longitud y caracteres", {
  expect_true(validar_busqueda("colgate total 12")$ok)
  expect_equal(validar_busqueda("  crema   dental ")$palabras, c("crema", "dental"))
  expect_false(validar_busqueda("x'; DROP TABLE observaciones;--")$ok)
  expect_false(validar_busqueda(strrep("a", 61))$ok)
})
