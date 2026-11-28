P1 <- list(exito = c(15000, 20000, 18000), olimpica = c(15000, 22000, 16000), locatel = c(17000, 21000, 16000))

test_that("el ahorro entre comercios maneja los empates", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  cargar_ejecucion(b, raw, "E20261101T100000", P1)
  a <- ahorro_por_producto(b$con, "E20261101T100000")
  crema <- a[grepl("Triple Accion", a$producto), ]
  expect_equal(c(crema$precio_min, crema$precio_max, crema$ahorro_cop), c(15000, 17000, 2000))
  expect_equal(crema$n_empatados, 2)                                   # Éxito y Olímpica empatan en el mínimo
  expect_setequal(strsplit(crema$comercio_mas_barato, " / ")[[1]], c("Éxito", "Olímpica"))
  cepillo <- a[grepl("Medio", a$producto), ]
  expect_equal(c(cepillo$ahorro_cop, cepillo$n_empatados), c(2000, 1))
  expect_equal(round(cepillo$ahorro_pct, 2), round(100 * 2000 / 22000, 2))
  # si todos los comercios empatan no hay ahorro
  igual <- list(exito = c(9000, 9000, 9000), olimpica = c(9000, 9000, 9000), locatel = c(9000, 9000, 9000))
  cargar_ejecucion(b, raw, "E20261102T100000", igual, "2026-11-02")
  a2 <- ahorro_por_producto(b$con, "E20261102T100000")
  expect_true(all(a2$ahorro_cop == 0)); expect_true(all(a2$n_empatados == 3))
})

test_that("la canasta calcula el costo por comercio, el mínimo y el ahorro", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  cargar_ejecucion(b, raw, "E20261101T100000", P1)
  items <- data.frame(producto_id = c(id_producto(b$con, "Triple Accion"), id_producto(b$con, "Medio"), id_producto(b$con, "Plax")),
                      cantidad = c(2, 1, 1))
  k <- calcular_canasta(b$con, items, "E20261101T100000")
  total <- stats::setNames(k$por_comercio$total, k$por_comercio$comercio_id)
  expect_equal(total[["exito"]], 2 * 15000 + 20000 + 18000)
  expect_equal(total[["olimpica"]], 2 * 15000 + 22000 + 16000)
  expect_equal(total[["locatel"]], 2 * 17000 + 21000 + 16000)
  expect_equal(k$resumen$total_minimo, 2 * 15000 + 20000 + 16000)       # cada producto donde es más barato
  expect_equal(k$resumen$total_mejor_comercio, 68000)                   # Éxito y Olímpica empatan
  expect_equal(k$resumen$ahorro, 68000 - 66000)
})

test_that("la canasta no se calcula en un comercio al que le falta un producto", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  cargar_ejecucion(b, raw, "E20261101T100000", P1)                      # con esta ejecución los tres son comparables
  disp <- list(exito = c(TRUE, TRUE, TRUE), olimpica = c(TRUE, TRUE, TRUE), locatel = c(TRUE, TRUE, FALSE))
  cargar_ejecucion(b, raw, "E20261102T100000", P1, "2026-11-02", disponibles = disp)   # enjuague agotado en Locatel
  ids <- c(id_producto(b$con, "Triple Accion"), id_producto(b$con, "Plax"))
  expect_false(anyNA(ids))
  k <- calcular_canasta(b$con, data.frame(producto_id = ids, cantidad = c(1, 1)), "E20261102T100000")
  loc <- k$por_comercio[k$por_comercio$comercio_id == "locatel", ]
  expect_true(is.na(loc$total))                                         # no muestra un total incompleto
  expect_equal(loc$n_faltantes, 1); expect_match(loc$faltantes, "Plax")
  expect_false(anyNA(k$por_comercio$total[k$por_comercio$comercio_id != "locatel"]))
  expect_equal(k$resumen$total_minimo, 15000 + 16000)
})

test_that("los filtros se aplican en SQL y el texto del usuario no altera la consulta", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  cargar_ejecucion(b, raw, "E20261101T100000", P1)
  expect_equal(nrow(productos_filtrados(b$con, filtros())), 9)
  expect_equal(nrow(productos_filtrados(b$con, filtros(comercios = c("exito", "locatel"), precio_max = 17000))), 3)
  expect_equal(nrow(productos_filtrados(b$con, filtros(texto = "plax"))), 3)
  expect_equal(nrow(productos_filtrados(b$con, filtros(comercios = "exito' OR '1'='1"))), 0)
  expect_equal(nrow(productos_filtrados(b$con, filtros(texto = "100%"))), 0)          # % se busca como texto
  expect_equal(indicadores(b$con, filtros(comercios = "exito"))$mediana_precio, 18000)
  expect_equal(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM observaciones")$n, 9)
})
