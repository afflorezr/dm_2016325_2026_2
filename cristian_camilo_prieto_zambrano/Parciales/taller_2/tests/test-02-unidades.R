# 2. Normalización de unidades: el contenido se lleva a g o mL desde el nombre

test_that("gramos y mililitros con sus variantes de escritura", {
  r <- extraer_contenido(c("Tarro X 400Gr", "Botella x 237 ml", "Lata 850 g", "x 420 gramos"))
  expect_equal(r$contenido, c(400, 237, 850, 420))
  expect_equal(r$unidad, c("g", "mL", "g", "g"))
})

test_that("kg, L, lb y oz se convierten a g o mL", {
  r <- extraer_contenido(c("x 1.5 kg", "x 1 L", "x 2lb", "x 8 oz", "x 0.400 kg"))
  expect_equal(r$contenido, c(1500, 1000, 907.2, 226.8, 400))
  expect_equal(r$unidad, c("g", "mL", "g", "g", "g"))
})

test_that("el punto de miles en g y mL no se lee como decimal", {
  r <- extraer_contenido(c("x 1.000 g", "x 1.500 ml"))
  expect_equal(r$contenido, c(1000, 1500))
})

test_that("un nombre sin contenido queda NA y se cuentan las unidades del empaque", {
  r <- extraer_contenido("Multivitamínico x 30 Tabletas")
  expect_true(is.na(r$contenido))
  expect_true(is.na(r$unidad))
  expect_equal(extraer_unidades(c("Proklein x 200ml X 6Und", "Glucerna x 237 ml")), c(6L, 1L))
})
