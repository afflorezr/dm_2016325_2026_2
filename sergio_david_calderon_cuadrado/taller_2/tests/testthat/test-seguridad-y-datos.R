test_that("validar_texto acepta texto normal y rechaza lo peligroso (S3)", {
  expect_equal(validar_texto("  humectaci\u00f3n   diaria "), "humectaci\u00f3n diaria")
  expect_null(validar_texto("   "))
  for (malo in c("'; DROP TABLE observaciones; --", "100%", "a_b", "<script>", strrep("a", 61), "uno dos tres cuatro cinco seis"))
    expect_error(validar_texto(malo), class = "error_validacion")
})

test_that("consultas parametrizadas: texto con comillas no altera la base (S2)", {
  con <- crear_base_prueba(); on.exit(DBI::dbDisconnect(con))
  antes <- c(cantidad_filas(con, "observaciones"), cantidad_filas(con, "anuncios"))
  expect_error(filtrar_precios(con, list(texto = "x'; DROP TABLE anuncios;--")), class = "error_validacion")
  expect_equal(nrow(filtrar_precios(con, list(comercios = "x'); DROP TABLE anuncios;--"))), 0)
  expect_equal(c(cantidad_filas(con, "observaciones"), cantidad_filas(con, "anuncios")), antes)
})

test_that("insertar dos veces lo mismo no duplica rechazos ni agotados", {
  con <- crear_base_prueba(); on.exit(DBI::dbDisconnect(con))
  rech <- data.frame(codigo_corrida = B, comercio = "exito", sku = "X1", nombre = "Crema", precio_texto = "$ ???",
                     regla = "precio_valido", motivo = "precio no numerico")
  registrar_rechazos(con, rech); registrar_rechazos(con, rech)
  expect_equal(cantidad_filas(con, "rechazos"), 1)
  ago <- data.frame(fecha_consulta = "2026-02-01T10:00:00-05:00", nombres = "Otra crema agotada", url = "https://prueba/z",
                    texto_original_anuncio = "Agotado", id_ejecucion = B, comercio = "farmatodo")
  n0 <- cantidad_filas(con, "agotados")
  registrar_agotados(con, ago); registrar_agotados(con, ago)
  expect_equal(cantidad_filas(con, "agotados"), n0 + 1)
})

test_that("validacion.R separa tarjetas agotadas y reconoce sus textos", {
  skip_if_not_installed("pointblank"); skip_if_not_installed("dplyr")
  source(file.path(raiz(), "validacion.R"), encoding = "UTF-8", local = TRUE)
  expect_true(all(es_agotado_texto(c("Av\u00edsame cuando est\u00e9 disponible", "Producto AGOTADO", "Sin stock"))))
  expect_false(es_agotado_texto("Crema corporal 200 ml $ 20.000"))
  obs <- data.frame(texto_original_anuncio = c("Agotado", "Crema $ 20.000"), precio_real_cop = c(NA, 20000))
  s <- separar_agotados(obs)
  expect_equal(c(nrow(s$agotados), nrow(s$resto)), c(1, 1))
})
