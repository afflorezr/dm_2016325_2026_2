test_that("calcula el ahorro y reconoce los empates", {
  a <- calcular_ahorro(c(100, 100, 120), c("Carulla", "Jumbo", "Olímpica"))
  expect_equal(a$minimo, 100)
  expect_equal(a$maximo, 120)
  expect_equal(a$ahorro_cop, 20)
  expect_equal(a$ahorro_pct, 16.67)
  expect_setequal(a$empates, c("Carulla", "Jumbo"))

  b <- calcular_ahorro(c(90, 90), c("Carulla", "Jumbo"))
  expect_equal(b$ahorro_cop, 0)
  expect_equal(b$ahorro_pct, 0)
  expect_length(b$empates, 2)
})

test_that("con precios ausentes no inventa un ahorro", {
  a <- calcular_ahorro(c(NA, NA), c("Carulla", "Jumbo"))
  expect_true(is.na(a$minimo))
  expect_true(is.na(a$ahorro_cop))
})
