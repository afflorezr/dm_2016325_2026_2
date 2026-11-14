test_that("normaliza el contenido a gramos y mililitros", {
  kg <- parsear_contenido("Chocolate 1,5 kg")
  expect_equal(kg$valor, 1500)
  expect_equal(kg$unidad, "g")

  ml <- parsear_contenido("Jabón 200 ml")
  expect_equal(ml$valor, 200)
  expect_equal(ml$unidad, "ml")
})

test_that("interpreta paquetes múltiples y unidades contables", {
  multipack <- parsear_contenido("Chocolatina 12x80g")
  expect_equal(multipack$valor, 960)
  expect_equal(multipack$unidad, "g")
  expect_equal(multipack$empaque, 12)

  unidades <- parsear_contenido("Caja x12 unidades")
  expect_equal(unidades$valor, 12)
  expect_equal(unidades$unidad, "unidad")
})

test_that("deja el contenido ausente cuando no hay dato", {
  vacio <- parsear_contenido("Producto sin presentación")
  expect_true(is.na(vacio$valor))
  expect_true(is.na(vacio$unidad))
})
