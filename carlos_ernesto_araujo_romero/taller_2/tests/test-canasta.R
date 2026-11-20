test_that("la canasta no se calcula cuando falta un producto", {
  precios <- data.frame(
    id_comercio = c("carulla", "carulla", "jumbo"),
    comercio = c("Carulla", "Carulla", "Jumbo"),
    id_producto_comun = c("P1", "P2", "P1"),
    nombre_canonico = c("Producto uno", "Producto dos", "Producto uno"),
    precio_cop = c(1000, 1000, 900),
    estado_disponibilidad = "disponible",
    stringsAsFactors = FALSE
  )
  res <- calcular_canasta(precios, c(P1 = 1, P2 = 2))
  expect_false(res$por_comercio$completo[res$por_comercio$comercio == "Jumbo"])
  expect_true(is.na(res$por_comercio$costo[res$por_comercio$comercio == "Jumbo"]))
  expect_equal(res$por_comercio$costo[res$por_comercio$comercio == "Carulla"], 3000)
  expect_equal(res$optimo, 2900)
})

test_that("la canasta completa calcula totales y ahorro frente al mejor comercio único", {
  precios <- data.frame(
    id_comercio = c("carulla", "carulla", "jumbo", "jumbo"),
    comercio = c("Carulla", "Carulla", "Jumbo", "Jumbo"),
    id_producto_comun = c("P1", "P2", "P1", "P2"),
    nombre_canonico = c("Producto uno", "Producto dos", "Producto uno", "Producto dos"),
    precio_cop = c(1000, 800, 900, 1200),
    estado_disponibilidad = "disponible",
    stringsAsFactors = FALSE
  )
  res <- calcular_canasta(precios, c(P1 = 1, P2 = 2))
  expect_true(all(res$por_comercio$completo))
  expect_equal(res$por_comercio$costo[res$por_comercio$comercio == "Carulla"], 2600)
  expect_equal(res$por_comercio$costo[res$por_comercio$comercio == "Jumbo"], 3300)
  expect_equal(res$optimo, 2500)
  expect_equal(res$ahorro, 100)
})

test_that("un producto agotado no completa la canasta", {
  precios <- data.frame(
    id_comercio = c("carulla", "carulla"),
    comercio = c("Carulla", "Carulla"),
    id_producto_comun = c("P1", "P2"),
    nombre_canonico = c("Producto uno", "Producto dos"),
    precio_cop = c(1000, NA),
    estado_disponibilidad = c("disponible", "agotado"),
    stringsAsFactors = FALSE
  )
  res <- calcular_canasta(precios, c(P1 = 1, P2 = 1))
  expect_false(res$por_comercio$completo[1])
  expect_true(is.na(res$por_comercio$costo[1]))
})
