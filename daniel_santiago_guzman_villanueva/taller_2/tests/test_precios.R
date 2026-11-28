test_that("convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("$12.900,50"), 12900.5)
  expect_equal(limpiar_precio("1.234.567"), 1234567)
  expect_equal(limpiar_precio(45950), 45950)
})

test_that("un precio ausente, cero o no numérico queda NA (nunca 0)", {
  expect_true(is.na(limpiar_precio(0)))
  expect_true(is.na(limpiar_precio("$ 0")))
  expect_true(is.na(limpiar_precio("Agotado")))
  expect_true(is.na(limpiar_precio(NULL)))
})
