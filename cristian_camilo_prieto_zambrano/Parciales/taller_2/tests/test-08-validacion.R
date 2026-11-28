# 8. Validación antes de insertar: las observaciones inválidas se rechazan y
# quedan registradas con la regla que no cumplieron.

test_that("un precio negativo y una fila duplicada se rechazan", {
  fecha <- "2026-10-01T10:05:00-05:00"
  d <- rbind(anuncio("locatel", "a", "Glucerna Vainilla Liquido x 237 ml", -5000, fecha = fecha),
             anuncio("locatel", "b", "Ensure Advance Vainilla Polvo x 400 gr", 80000, fecha = fecha),
             anuncio("locatel", "b", "Ensure Advance Vainilla Polvo x 400 gr", 80000, fecha = fecha))
  v <- suppressMessages(validar_observaciones(limpiar(d), etiqueta = "prueba"))
  expect_equal(nrow(v$aceptadas), 1)
  expect_equal(v$aceptadas$sku, "b")
  expect_true("precio_valido" %in% v$rechazadas$regla[v$rechazadas$sku == "a"])
  expect_true("sin_duplicados" %in% v$rechazadas$regla[v$rechazadas$sku == "b"])
})
