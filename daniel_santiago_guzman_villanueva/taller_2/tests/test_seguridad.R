test_that("la búsqueda rechaza texto peligroso o demasiado largo", {
  expect_error(validar_texto("'; DROP TABLE observaciones; --"), "solo admite")
  expect_error(validar_texto(strrep("a", 61)), "como máximo")
  expect_equal(validar_texto("  Renu +2.50 "), "Renu +2.50")
  expect_null(validar_texto(""))
})

test_that("los valores del usuario van como parámetros, nunca dentro del SQL", {
  op <- list(comercios = data.frame(comercio = c("locatel", "farmatodo")),
             subcategorias = "Estuches", marcas = "RENU",
             ejecuciones = data.frame(id_ejecucion = "E1"), precio = c(0, 1000))
  f <- limpiar_filtros(list(comercios = c("locatel", "x' OR 1=1 --"), ejecucion = "E1",
                            texto = "renu", periodo = "ejecucion"), op)
  expect_equal(f$comercios, "locatel")                       # lo desconocido se descarta
  w <- where_filtros(f)
  expect_false(grepl("renu|locatel|E1", w$sql))
  expect_equal(unlist(w$params), c("locatel", "E1", "renu", "renu"))
})
