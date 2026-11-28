test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  b <- base_temporal()
  on.exit(cerrar_conexion(b$con))
  falso <- scraper_falso(c("1", "2"), c(1000, 2000), "2026-11-10T10:00:00-05:00", b$raw)

  r1 <- actualizar_prueba(b, falso, "EJ_20261110T100000")
  r2 <- actualizar_prueba(b, falso, "EJ_20261110T100500")

  expect_equal(r1$comercios$insertadas, 2)
  expect_equal(r2$comercios$insertadas, 0)
  expect_equal(dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM observaciones")$n, 2)

  # la restricción UNIQUE del Taller 1 también lo impide si se inserta directo
  otra_vez <- obs_prueba(c("1", "2"), c(1000, 2000), "2026-11-10T10:00:00-05:00",
                         "EJ_20261110T100000", b$raw)
  expect_equal(db_insertar_observaciones(b$con, preparar_observaciones(otra_vez)), 0)
})

test_that("detecta subidas, bajadas, productos nuevos y no observados", {
  b <- base_temporal()
  on.exit(cerrar_conexion(b$con))
  antes <- scraper_falso(c("1", "2", "3"), c(1000, 2000, 3000), "2026-11-03T10:00:00-05:00", b$raw)
  despues <- scraper_falso(c("1", "2", "4"), c(1200, 1800, 500), "2026-11-10T10:00:00-05:00", b$raw)

  r1 <- actualizar_prueba(b, antes, "EJ_20261103T100000")
  r2 <- actualizar_prueba(b, despues, "EJ_20261110T100000")

  cmp <- db_comparar_ejecuciones(b$con, r1$id_ejecucion, r2$id_ejecucion)
  tipo <- setNames(cmp$tipo, cmp$sku_comercio)
  expect_equal(tipo[["1"]], "sube")
  expect_equal(tipo[["2"]], "baja")
  expect_equal(tipo[["4"]], "nuevo")
  expect_equal(tipo[["3"]], "no_observado")
  expect_equal(cmp$variacion_pct[cmp$sku_comercio == "1"], 20)

  expect_equal(r2$comercios$cambios_precio, 2)
  expect_equal(r2$comercios$nuevos, 1)
  expect_equal(r2$comercios$no_observados, 1)
  expect_equal(db_cambios_en_ejecucion(b$con, r2$id_ejecucion)$cambios, 2)
})

test_that("si un comercio falla, los demás se guardan y queda el motivo", {
  b <- base_temporal()
  on.exit(cerrar_conexion(b$con))
  falso <- function(clave, sin_conexion, id_ejecucion) {
    if (clave == "cruzverde") stop("HTTP 403: acceso bloqueado")
    obs_prueba(c("1", "2"), c(1000, 2000), "2026-11-10T10:00:00-05:00", id_ejecucion, b$raw, clave)
  }
  r <- actualizar_prueba(b, falso, "EJ_20261110T100000", comercios = c("farmatodo", "cruzverde"))

  fila_cv <- r$comercios[r$comercios$comercio == "Cruz Verde", ]
  expect_equal(fila_cv$estado, "FALLIDA")
  expect_match(fila_cv$motivo, "403")
  expect_equal(r$comercios$insertadas[r$comercios$comercio == "Farmatodo"], 2)
  expect_equal(r$estado, "PARCIAL")
  # la falla queda registrada en la tabla ejecuciones del Taller 1
  ej <- dbGetQuery(b$con, "SELECT estado, detalle FROM ejecuciones WHERE comercio = 'Cruz Verde'")
  expect_equal(ej$estado, "FALLIDA")
  expect_match(ej$detalle, "403")
})

test_that("el texto del usuario va como parámetro y no altera la consulta", {
  b <- base_temporal()
  on.exit(cerrar_conexion(b$con))
  actualizar_prueba(b, scraper_falso("1", 1000, "2026-11-10T10:00:00-05:00", b$raw),
                    "EJ_20261110T100000")

  expect_equal(nrow(db_productos(b$con, list(texto = "x' OR '1'='1"))), 0)
  expect_equal(nrow(db_productos(b$con, list(texto = "loratadina"))), 1)
  expect_equal(nrow(db_productos(b$con, list(comercios = "Farmatodo' --"))), 0)
})
