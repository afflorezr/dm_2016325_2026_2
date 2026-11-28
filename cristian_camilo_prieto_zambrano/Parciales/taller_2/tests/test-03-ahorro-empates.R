# 3. Ahorro con empates: si dos comercios comparten el precio mínimo, ambos son
# "el más barato", ninguno tiene sobrecosto y el ahorro se mide contra el más caro.
# En la base de prueba, P01 en la corrida 1: Locatel 80.000, Cruz Verde 80.000,
# Farmatodo 90.000.

test_that("los dos comercios empatados quedan como más baratos", {
  con <- base_prueba()
  d <- DBI::dbGetQuery(con, "
    SELECT id_comercio, es_mas_barato, n_mas_baratos, sobrecosto, ahorro_maximo
    FROM v_comparables WHERE id_producto = 'P01' AND corrida = ? ORDER BY id_comercio",
    params = list(C1))
  expect_equal(d$id_comercio, c("cruzverde", "farmatodo", "locatel"))
  expect_equal(d$es_mas_barato, c(1L, 0L, 1L))
  expect_equal(unique(d$n_mas_baratos), 2L)
  expect_equal(d$sobrecosto, c(0, 10000, 0))
  expect_equal(unique(d$ahorro_maximo), 10000)
})

test_that("el indicador de mayor ahorro nombra a los dos comercios empatados", {
  con <- base_prueba()
  a <- indicadores(con, list(corrida = C1))$ahorro_maximo$tabla
  expect_equal(a$id_producto, "P01")
  expect_equal(a$ahorro, 10000)
  expect_equal(a$porcentaje, 11.1)
  expect_setequal(strsplit(a$mas_barato, ", ")[[1]], c("Locatel", "Cruz Verde"))
  expect_equal(a$mas_caro, "Farmatodo")
})
