P1 <- list(exito = c(15000, 20000, 18000), olimpica = c(15000, 22000, 16000), locatel = c(17000, 21000, 16000))

test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  r1 <- cargar_ejecucion(b, raw, "E20261101T100000", P1)
  r2 <- cargar_ejecucion(b, raw, "E20261101T100000", P1)
  expect_equal(sum(r1$observaciones_nuevas), 9)
  expect_equal(sum(r2$observaciones_nuevas), 0)
  expect_true(all(r2$ya_cargada))
  expect_equal(r2$coinciden_raw, c(3, 3, 3))        # lo leído de raw/ coincide con lo guardado
  expect_equal(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM observaciones")$n, 9)
  expect_error(DBI::dbExecute(b$con, paste(                                  # la restricción de unicidad lo impide
    "INSERT INTO observaciones (ejecucion_id, comercio_id, anuncio_id, sku_comercio, fecha_hora_consulta, es_promocion, url_fuente)",
    "SELECT ejecucion_id, comercio_id, anuncio_id, sku_comercio, fecha_hora_consulta, 0, url_fuente FROM observaciones LIMIT 1")),
    "UNIQUE")
})

test_that("detecta cambios de precio, productos nuevos y no observados entre ejecuciones", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  cargar_ejecucion(b, raw, "E20261101T100000", P1)
  P2 <- P1; P2$exito <- c(16500, 20000, 18000); P2$olimpica <- c(15000, 19800, 16000)
  escribir_raw(raw, "exito", "E20261108T100000", productos_prueba("exito", P2$exito), "2026-11-08")
  escribir_raw(raw, "olimpica", "E20261108T100000", productos_prueba("olimpica", P2$olimpica), "2026-11-08")
  loc <- rbind(productos_prueba("locatel", P2$locatel)[1:2, ],       # Locatel: falta el enjuague y aparece uno nuevo
               data.frame(sku = "lo9", nombre = "Seda dental Colgate 25 m", ean = "", precio = 9000, disponible = TRUE))
  escribir_raw(raw, "locatel", "E20261108T100000", loc, "2026-11-08")
  r <- ejecutar_recoleccion(names(P1), "sin_conexion", b$ruta, raw, "E20261108T100000", verbose = FALSE,
                            esquema = "../esquema.sql", ruta_manual = "no_existe.csv")
  expect_equal(r$cambios_precio, c(1, 1, 0)); expect_equal(r$productos_nuevos, c(0, 0, 1)); expect_equal(r$no_observados, c(0, 0, 1))
  k <- comparar_ejecuciones(b$con, "E20261101T100000", "E20261108T100000", umbral = 5)
  expect_equal(nrow(k$cambios), 2)
  sube <- k$cambios[k$cambios$tipo == "subió", ]; baja <- k$cambios[k$cambios$tipo == "bajó", ]
  expect_equal(c(sube$cambio_cop, sube$cambio_pct, sube$variacion_grande), c(1500, 10, 1))
  expect_equal(c(baja$cambio_cop, baja$cambio_pct, baja$variacion_grande), c(-2200, -10, 1))
  expect_equal(nrow(k$nuevos), 1)
  expect_equal(nrow(k$no_observados), 1)
  expect_equal(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM v_cambios_precio WHERE ejecucion_id = 'E20261108T100000'")$n, 2)
  # el producto que no apareció queda como «no observado», no como agotado
  d <- resumen_disponibilidad(b$con, "E20261108T100000")
  expect_equal(d$anuncios[d$comercio == "Locatel" & d$estado == "no_observado"], 1)
})

test_that("si un comercio falla, los demás se insertan y la falla queda registrada", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  r <- cargar_ejecucion(b, raw, "E20261101T100000", P1[c("exito", "olimpica")], comercios = c("exito", "olimpica", "locatel"))
  expect_equal(r$estado, c("completa", "completa", "fallida"))
  expect_match(r$mensaje[3], "no hay copias crudas")
  expect_equal(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM observaciones")$n, 6)
  expect_equal(DBI::dbGetQuery(b$con, "SELECT estado FROM ejecuciones WHERE comercio_id = 'locatel'")$estado, "fallida")
})

test_that("las observaciones rechazadas no entran a la base y quedan con su motivo", {
  b <- base_temporal(); raw <- withr::local_tempdir()
  r <- cargar_ejecucion(b, raw, "E20261101T100000", list(exito = c(15000, NA, 18000)))   # disponible y sin precio
  expect_equal(c(r$validos, r$rechazados), c(2, 1))
  expect_equal(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM observaciones")$n, 2)
  expect_match(DBI::dbGetQuery(b$con, "SELECT motivo FROM observaciones_rechazadas")$motivo, "V3")
})
