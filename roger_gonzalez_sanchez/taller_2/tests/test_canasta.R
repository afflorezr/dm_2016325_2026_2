precios_canasta <- function() {
  data.frame(
    id_comparable = c(1, 2, 1, 2, 1, 2),
    comparable = c("Arroz", "Aceite", "Arroz", "Aceite", "Arroz", "Aceite"),
    comercio = c("A", "A", "B", "B", "C", "C"),
    precio = c(1000, 2100, 1100, 2000, 1000, 2200),
    estado = "disponible"
  )
}

test_that("la canasta no se calcula en un comercio al que le falta un producto", {
  p <- precios_canasta()
  p$precio[p$comercio == "B" & p$comparable == "Aceite"] <- NA
  p$estado[p$comercio == "B" & p$comparable == "Aceite"] <- "no_observado"
  p$estado[p$comercio == "C" & p$comparable == "Arroz"] <- "agotado"

  k <- calcular_canasta(p, data.frame(id_comparable = c(1, 2), cantidad = c(1, 1)))
  fila_b <- k$por_comercio[k$por_comercio$comercio == "B", ]
  fila_c <- k$por_comercio[k$por_comercio$comercio == "C", ]

  expect_false(fila_b$completa)
  expect_true(is.na(fila_b$total))
  expect_equal(fila_b$faltan, "Aceite")
  expect_true(is.na(fila_c$total))   # agotado cuenta como faltante
  expect_equal(k$por_comercio$total[k$por_comercio$comercio == "A"], 3100)
})

test_that("el ahorro se calcula bien cuando hay empates", {
  k <- calcular_canasta(precios_canasta(),
                        data.frame(id_comparable = c(1, 2), cantidad = c(2, 1)))

  # arroz: empate entre A y C a 1000; aceite: B a 2000
  expect_equal(k$detalle$donde[k$detalle$comparable == "Arroz"], "A / C")
  expect_equal(k$costo_minimo, 2 * 1000 + 2000)
  # A = 4100, B = 4200, C = 4200
  expect_equal(k$mejor_comercio, "A")
  expect_equal(k$ahorro, 100)

  # empate en el mejor comercio
  k2 <- calcular_canasta(precios_canasta(),
                         data.frame(id_comparable = c(1, 2), cantidad = c(1, 1)))
  expect_equal(k2$mejor_comercio, "A / B")   # A = 3100, B = 3100
  expect_equal(k2$ahorro, 100)
  expect_equal(k2$por_comercio$ahorro_vs_minimo[k2$por_comercio$comercio == "C"], 200)
})
