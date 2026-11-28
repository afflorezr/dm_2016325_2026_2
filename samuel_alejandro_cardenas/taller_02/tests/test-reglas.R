testthat::test_that("1. convierte precios de texto a COP", {
  testthat::expect_equal(precio_cop("$ 12.900"), 12900)
  testthat::expect_equal(precio_cop("COP 19.850"), 19850)
  testthat::expect_true(is.na(precio_cop("sin precio")))
})

testthat::test_that("2. normaliza cantidades sin mezclar unidades", {
  a <- normalizar_unidad_t2(50, "gr")
  b <- normalizar_unidad_t2(100, "ml")
  c <- normalizar_unidad_t2(3, "unds")
  d <- normalizar_unidad_t2(500, "mg")
  testthat::expect_identical(a$unidad_normalizada, "g")
  testthat::expect_equal(a$contenido_total, 50)
  testthat::expect_identical(b$unidad_normalizada, "mL")
  testthat::expect_identical(c$unidad_normalizada, "unidad")
  testthat::expect_equal(d$contenido_total, 0.5)
})

testthat::test_that("3. valida antes de insertar y rechaza precios no positivos", {
  raw <- tempfile(fileext = ".json.gz")
  writeLines("origen de prueba", raw)
  fila <- data.frame(
    comercio = "Cafam", sku = "SKU_TEST", producto_original = "Producto de prueba caja 3",
    precio = 0, url = "https://ejemplo.invalid/producto",
    fecha_consulta = "2026-11-11T15:00:00-05:00",
    id_ejecucion = "20261111_150000", cantidad = 3, unidad = "unidad",
    origen_raw = raw, id_comun = NA_character_, comparable = 0L,
    stringsAsFactors = FALSE
  )
  mapa <- data.frame(comercio = "Cafam", sku = "SKU_TEST",
                     id_comun = "durex_real_feel_3", stringsAsFactors = FALSE)
  verificacion <- validar_lote_t2(fila, "Cafam", "20261111_150000", mapa)
  testthat::expect_equal(nrow(verificacion$validas), 0L)
  testthat::expect_equal(nrow(verificacion$rechazadas), 1L)
  testthat::expect_match(verificacion$rechazadas$motivo_rechazo[[1L]], "precio")
  fila$precio <- 12900
  fila_duplicada <- rbind(fila, fila)
  verificacion2 <- validar_lote_t2(fila_duplicada, "Cafam", "20261111_150000", mapa)
  testthat::expect_equal(nrow(verificacion2$validas), 1L)
  testthat::expect_equal(nrow(verificacion2$rechazadas), 1L)
  testthat::expect_match(verificacion2$rechazadas$motivo_rechazo[[1L]], "duplicado")
  unlink(raw)
})

testthat::test_that("4. la restriccion UNIQUE vuelve idempotente una insercion", {
  con_base_temporal(function(con) {
    n1 <- insertar_prueba(con, "Cafam", "SKU_A", "producto_a", "EJ_1", 100)
    n2 <- insertar_prueba(con, "Cafam", "SKU_A", "producto_a", "EJ_1", 999)
    x <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n, MIN(precio) AS precio FROM observaciones")
    testthat::expect_equal(n1, 1L)
    testthat::expect_equal(n2, 0L)
    testthat::expect_equal(x$n[[1L]], 1L)
    testthat::expect_equal(x$precio[[1L]], 100)
  })
})

testthat::test_that("5. detecta cambios COP y porcentaje entre ejecuciones", {
  con_base_temporal(function(con) {
    insertar_prueba(con, "Cafam", "SKU_A", "producto_a", "EJ_1", 18615,
                    fecha = "2026-10-10T08:41:11-05:00")
    insertar_prueba(con, "Cafam", "SKU_A", "producto_a", "EJ_2", 17212)
    x <- comparar_ejecuciones_sql("EJ_1", "EJ_2")
    testthat::expect_equal(nrow(x), 1L)
    testthat::expect_identical(x$situacion[[1L]], "bajo")
    testthat::expect_equal(x$variacion_cop[[1L]], -1403)
    testthat::expect_equal(x$variacion_pct[[1L]], -7.54)
  })
})

testthat::test_that("6. ahorro con empate de precios y dos productos", {
  con_base_temporal(function(con) {
    insertar_prueba(con, "Cafam", "A_C", "a", "EJ_2", 100)
    insertar_prueba(con, "Locatel", "A_L", "a", "EJ_2", 100)
    insertar_prueba(con, "Cruz Verde", "A_V", "a", "EJ_2", 200)
    insertar_prueba(con, "Cafam", "B_C", "b", "EJ_2", 200)
    insertar_prueba(con, "Locatel", "B_L", "b", "EJ_2", 250)
    insertar_prueba(con, "Cruz Verde", "B_V", "b", "EJ_2", 150)
    minimo <- minimo_canasta_sql(c("a", "b"), c(1L, 1L), "EJ_2")
    tiendas <- canasta_sql(c("a", "b"), c(1L, 1L), "EJ_2")
    testthat::expect_equal(sum(minimo$subtotal), 250)
    testthat::expect_equal(min(tiendas$total_estimado), 300)
    testthat::expect_equal(min(tiendas$total_estimado) - sum(minimo$subtotal), 50)
  })
})

testthat::test_that("7. canasta incompleta no habilita un total de tienda", {
  con_base_temporal(function(con) {
    insertar_prueba(con, "Cafam", "A_C", "a", "EJ_2", 100)
    insertar_prueba(con, "Cafam", "B_C", "b", "EJ_2", 200)
    insertar_prueba(con, "Locatel", "A_L", "a", "EJ_2", 90)
    tiendas <- canasta_sql(c("a", "b"), c(1L, 1L), "EJ_2")
    locatel <- tiendas[tiendas$comercio == "Locatel", , drop = FALSE]
    cafam <- tiendas[tiendas$comercio == "Cafam", , drop = FALSE]
    testthat::expect_equal(locatel$presentes[[1L]], 1L)
    testthat::expect_true(locatel$presentes[[1L]] < 2L)
    testthat::expect_equal(cafam$presentes[[1L]], 2L)
    total_visible <- ifelse(tiendas$presentes == 2L & tiendas$agotados == 0L,
                            tiendas$total_estimado, NA_real_)
    testthat::expect_true(is.na(total_visible[tiendas$comercio == "Locatel"]))
    testthat::expect_equal(total_visible[tiendas$comercio == "Cafam"], 300)
  })
})
