test_that("convierte precios en texto a números", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("12.900,50"), 12900.5)
  expect_equal(limpiar_precio(c("$ 8.290", "$ 1.234")), c(8290, 1234))
  expect_true(is.na(limpiar_precio(NA)))
  expect_true(is.na(limpiar_precio("sin precio")))
})

test_that("rechaza observaciones con precio no positivo", {
  d <- data.frame(
    id_comercio = "carulla", sku_comercio = "1", texto_original = "Producto",
    url_producto = "https://carulla.test/1", fecha_consulta = "2026-11-11T10:00:00-05:00",
    estado_disponibilidad = "disponible", precio_cop = 0, precio_lista_cop = NA,
    contenido_total = 100, unidad_normalizada = "g", stringsAsFactors = FALSE
  )
  resultado <- validar_observaciones(d)
  expect_equal(nrow(resultado$validas), 0)
  expect_equal(resultado$rechazadas$motivo, "precio_positivo")
})

test_that("los datos obligatorios se validan antes de insertar", {
  d <- data.frame(
    id_comercio = "carulla", sku_comercio = "1", texto_original = "Producto",
    url_producto = "carulla.test/1", fecha_consulta = "ayer",
    estado_disponibilidad = "disponible", precio_cop = 1000, precio_lista_cop = NA,
    contenido_total = 100, unidad_normalizada = "g", stringsAsFactors = FALSE
  )
  resultado <- validar_observaciones(d)
  expect_equal(nrow(resultado$rechazadas), 1)
  expect_true(resultado$rechazadas$motivo %in% c("url_valida", "fecha_iso"))
})
