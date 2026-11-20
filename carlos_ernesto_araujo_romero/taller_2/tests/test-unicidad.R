test_that("una observación no se inserta dos veces en la misma ejecución", {
  b <- nueva_base()
  on.exit(DBI::dbDisconnect(b$con), add = TRUE)
  nueva_ejecucion(b$con, "E1", "2026-11-10T09:00:00-05:00")

  nueva_observacion(b$con, "E1", "carulla", "sku-1", 1000,
                    "2026-11-10T09:01:00-05:00")
  expect_error(
    nueva_observacion(b$con, "E1", "carulla", "sku-1", 1200,
                      "2026-11-10T09:05:00-05:00"),
    "UNIQUE"
  )
  expect_equal(
    DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM observaciones")$n,
    1
  )
})

test_that("la validación detecta el duplicado dentro del lote", {
  d <- data.frame(
    id_comercio = c("carulla", "carulla"), sku_comercio = c("1", "1"),
    texto_original = "Producto",
    url_producto = "https://carulla.test/1",
    fecha_consulta = "2026-11-11T10:00:00-05:00",
    estado_disponibilidad = "disponible", precio_cop = c(1000, 1200),
    precio_lista_cop = NA_real_, contenido_total = 100,
    unidad_normalizada = "g", stringsAsFactors = FALSE
  )
  resultado <- validar_observaciones(d)
  expect_equal(nrow(resultado$validas), 1)
  expect_equal(resultado$rechazadas$motivo, "duplicado_ejecucion")
})
