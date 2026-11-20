test_that("el texto de búsqueda se valida antes de usarse", {
  expect_equal(validar_texto("corona"), "corona")
  expect_equal(validar_texto("100% cacao"), "100 cacao")
  expect_equal(validar_texto("' OR 1=1 --"), "")
  expect_equal(validar_texto(strrep("a", 61)), "")
  expect_equal(validar_texto("texto; DROP TABLE observaciones"), "")
})

test_that("los filtros viajan como parámetros y no como texto SQL", {
  f <- construir_filtros(list(
    comercios = c("carulla", "jumbo"), subcategoria = "", marca = "",
    precio_min = 0, precio_max = 20000, solo_promo = FALSE,
    solo_comparables = TRUE, buscar = "corona"
  ))
  expect_match(f$where, "id_comercio IN \\(\\?, \\?\\)")
  expect_match(f$where, "es_comparable = 1")
  expect_false(grepl("corona", f$where))
  expect_equal(length(f$params), 6)
  expect_equal(f$params[[1]], "carulla")
})
