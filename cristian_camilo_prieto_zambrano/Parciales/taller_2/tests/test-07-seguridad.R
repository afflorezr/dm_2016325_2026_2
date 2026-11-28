# 7. Entradas del usuario: la búsqueda se valida y los filtros van como
# parámetros, nunca pegados al SQL.

test_that("la búsqueda acepta texto normal y rechaza caracteres no permitidos", {
  expect_true(validar_busqueda("glucerna vainilla")$ok)
  expect_true(validar_busqueda("")$ok)
  expect_false(validar_busqueda("x'; DROP TABLE observaciones; --")$ok)
})

test_that("una búsqueda maliciosa se rechaza sin tocar la base", {
  con <- base_prueba()
  expect_error(productos_filtrados(con, list(busqueda = "x'; DROP TABLE observaciones; --")),
               class = "entrada_invalida")
  expect_true(DBI::dbExistsTable(con, "observaciones"))
})

test_that("un filtro con comillas se trata como texto, no como SQL", {
  con <- base_prueba()
  todos <- nrow(productos_filtrados(con, list()))
  expect_gt(todos, 0)
  expect_equal(nrow(productos_filtrados(con, list(marcas = "x' OR '1'='1"))), 0)
})
