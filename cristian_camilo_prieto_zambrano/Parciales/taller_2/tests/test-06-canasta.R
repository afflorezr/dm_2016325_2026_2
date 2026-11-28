# 6. La canasta no se calcula en un comercio al que le falta un producto.
# Corrida 1: una unidad de P01 y dos de P03. Cruz Verde no tiene P03.

test_that("el comercio incompleto no tiene total y se indica qué le falta", {
  con <- base_prueba()
  k <- costo_canasta(con, c("P01", "P03"), c(1, 2), corrida = C1)
  pc <- k$por_comercio
  cv <- pc[pc$id_comercio == "cruzverde", ]
  expect_true(is.na(cv$total))
  expect_equal(cv$faltantes, "P03")
  expect_equal(pc$total[pc$id_comercio == "locatel"], 80000 + 2 * 100000)
  expect_equal(pc$total[pc$id_comercio == "farmatodo"], 90000 + 2 * 98000)
})

test_that("la compra combinada usa el más barato de cada producto", {
  con <- base_prueba()
  r <- costo_canasta(con, c("P01", "P03"), c(1, 2), corrida = C1)$resumen
  expect_equal(r$total_combinado, 80000 + 2 * 98000)
  expect_equal(r$mejor_comercio, "Locatel")
  expect_equal(r$ahorro_combinado, 280000 - 276000)
})

test_that("un producto sin precio en ningún comercio deja todos los totales vacíos", {
  con <- base_prueba()
  k <- costo_canasta(con, c("P01", "P99"), c(1, 1), corrida = C1)
  expect_true(all(is.na(k$por_comercio$total)))
  expect_true(is.na(k$resumen$total_combinado))
})

test_that("cantidades o códigos inválidos se rechazan", {
  con <- base_prueba()
  expect_error(costo_canasta(con, "P01", -1, corrida = C1), class = "entrada_invalida")
  expect_error(costo_canasta(con, "P01", 2.5, corrida = C1), class = "entrada_invalida")
  expect_error(costo_canasta(con, "x' OR 1=1", 1, corrida = C1), class = "entrada_invalida")
})
