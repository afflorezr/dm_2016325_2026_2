# =============================================================================
# tests/test-precios.R  -  Conversion de precios y normalizacion de unidades
# Ejecutar desde la raiz del proyecto:  Rscript -e "testthat::test_dir('tests')"
# Usa solo datos pequenos en memoria: nunca la base de la entrega ni los sitios.
# =============================================================================

if (!exists("parse_cop", mode = "function")) {
  ruta <- if (file.exists("scraper.R")) "scraper.R" else file.path("..", "scraper.R")
  source(ruta)
}

test_that("convierte el precio en texto a numero (COP con punto de miles)", {
  expect_equal(parse_cop("$ 12.900"), 12900)
  expect_equal(parse_cop("$4.450"), 4450)
  expect_equal(parse_cop("15.000"), 15000)
})

test_that("convierte precios con coma decimal", {
  expect_equal(parse_cop("$ 313,50"), 313.5)
  expect_equal(parse_cop("$ 1.234,56"), 1234.56)
})

test_that("devuelve NA ante textos sin precio (no inventa valores)", {
  expect_true(is.na(parse_cop(NA_character_)))
  expect_true(is.na(parse_cop("sin precio")))
  expect_true(is.na(parse_cop("")))
})

test_that("extrae presentacion en ml, g y unidades con conversiones", {
  p1 <- extraer_presentacion("Jabon Bebe Johnsons 200 ml")
  expect_equal(p1$valor, 200)
  expect_equal(p1$unidad, "ml")

  p2 <- extraer_presentacion("Crema 1 litro")
  expect_equal(p2$valor, 1000)          # 1 L = 1000 mL
  expect_equal(p2$unidad, "ml")

  p3 <- extraer_presentacion("Jabon en barra x 3 und")
  expect_equal(p3$valor, 3)
  expect_equal(p3$unidad, "unidad")

  p4 <- extraer_presentacion("Polvo 2 kilos")
  expect_equal(p4$valor, 2000)          # 2 kg = 2000 g
  expect_equal(p4$unidad, "g")
})

test_that("la fecha ISO de Colombia cumple el formato obligatorio", {
  expect_true(str_detect("2026-08-14T10:35:00-05:00", RX_FECHA_ISO))
  expect_false(str_detect("2026-08-14 10:35:00", RX_FECHA_ISO))
  expect_false(str_detect("2026-08-14T10:35:00+02:00", RX_FECHA_ISO))
})
