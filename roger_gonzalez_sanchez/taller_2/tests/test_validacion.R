test_that("rechaza precio cero, URL vacía, duplicados y sin copia cruda, con su motivo", {
  dir_raw <- tempfile("raw_")
  d <- obs_prueba(c("1", "2", "3", "3", "4"), c(1000, 0, 2000, 2000, 500),
                  "2026-11-10T10:00:00-05:00", "EJ_A", dir_raw)
  d$url_producto[3] <- ""
  d$archivo_raw[5] <- "no_existe.json.gz"
  v <- validar_observaciones(preparar_observaciones(d), archivos_raw_de(dir_raw, "farmatodo"))

  expect_equal(v$validas$sku_comercio, "1")
  expect_equal(nrow(v$rechazadas), 4)
  expect_match(v$rechazadas$motivo[1], "precio")
  expect_match(v$rechazadas$motivo[2], "URL")
  expect_match(v$rechazadas$motivo[3], "duplicada")
  expect_match(v$rechazadas$motivo[4], "copia cruda")
})

test_that("si el scraper no trae una columna obligatoria se detiene", {
  d <- obs_prueba("1", 1000, "2026-11-10T10:00:00-05:00", "EJ_A", tempfile("raw_"))
  d$url_producto <- NULL
  expect_error(preparar_observaciones(d), "url_producto")
})

test_that("detecta los comparables que faltan en un comercio", {
  d <- obs_prueba("1", 3000, "2026-11-10T10:00:00-05:00", "EJ_A", tempfile("raw_"))
  faltan <- faltan_comparables(preparar_observaciones(d))
  expect_length(faltan, 7)   # solo está la loratadina 10 mg x 10
  expect_false(any(grepl("Loratadina", faltan)))
})

test_that("la búsqueda del usuario se valida antes de consultar", {
  expect_equal(validar_busqueda("  loratadina "), "loratadina")
  expect_null(validar_busqueda("'; DROP TABLE observaciones; --"))
  expect_null(validar_busqueda(strrep("a", 61)))
})
