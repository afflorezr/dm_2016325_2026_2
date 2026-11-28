# 4. Insertar dos veces la misma ejecución no duplica observaciones

test_that("volver a insertar el mismo lote no agrega observaciones", {
  archivo <- tempfile(fileext = ".sqlite")
  con <- crear_base(archivo)
  withr::defer({ DBI::dbDisconnect(con); unlink(archivo) })
  fecha <- "2026-10-01T10:05:00-05:00"
  filas <- rbind(anuncio("locatel", "a", "Ensure Advance Vainilla Polvo x 400 gr", 80000, fecha = fecha),
                 anuncio("locatel", "b", "Glucerna Vainilla Liquido x 237 ml", 15000, fecha = fecha),
                 anuncio("locatel", "c", "Nutren Senior Vainilla x 400 gr", -1, fecha = fecha))  # rechazada
  v <- suppressMessages(validar_observaciones(limpiar(filas), etiqueta = "prueba"))
  primera <- cargar(con, C1, "locatel", filas)
  contar <- function(tabla) DBI::dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", tabla))$n
  n_obs <- contar("observaciones")
  n_rech <- contar("rechazos")
  expect_equal(n_obs, 2)

  segunda <- insertar_lote(con, v$aceptadas, v$rechazadas, primera$id_ejecucion)
  expect_equal(segunda$nuevas, 0L)
  expect_equal(contar("observaciones"), n_obs)
  expect_equal(contar("rechazos"), n_rech)
  expect_equal(contar("anuncios"), 2)
})

test_that("una corrida ya cargada se reconoce y no se vuelve a cargar", {
  con <- base_prueba()
  expect_false(is.null(ejecucion_cargada(con, C1, "locatel")))
  expect_null(ejecucion_cargada(con, "20991231T000000", "locatel"))
})
