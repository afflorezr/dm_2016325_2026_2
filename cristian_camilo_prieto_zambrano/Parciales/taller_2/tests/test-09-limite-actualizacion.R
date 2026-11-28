# 9. Límite de actualizaciones desde la aplicación: entre dos actualizaciones
# en línea deben pasar al menos ESPERA_EN_LINEA_MIN minutos, y solo corre una
# actualización a la vez. En la base de prueba, la última ejecución en línea
# empezó el 2026-10-08 a las 10:05 (hora de Colombia).

test_that("dentro de la hora siguiente a una actualización en línea hay que esperar", {
  archivo <- tempfile(fileext = ".sqlite")
  con <- base_prueba()
  DBI::dbExecute(con, "VACUUM INTO ?", params = list(archivo))
  withr::defer(unlink(archivo))
  ultima <- leer_fecha_iso("2026-10-08T10:05:00-05:00")

  e <- espera_en_linea(archivo, minutos = 60, ahora = ultima + 10 * 60)
  expect_equal(e$minutos, 50)
  expect_equal(format(e$proxima, "%H:%M", tz = ZONA), "11:05")
  expect_equal(espera_en_linea(archivo, minutos = 60, ahora = ultima + 61 * 60)$minutos, 0)
})

test_that("si hay que esperar, no se consultan los sitios y se explica por qué", {
  archivo <- tempfile(fileext = ".sqlite")
  con <- base_prueba()
  DBI::dbExecute(con, "UPDATE ejecuciones SET inicio = ?",
                 params = list(format(Sys.time() - 5 * 60, "%Y-%m-%dT%H:%M:%S-05:00", tz = ZONA)))
  DBI::dbExecute(con, "VACUUM INTO ?", params = list(archivo))
  withr::defer(unlink(archivo))
  n_antes <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM ejecuciones")$n

  r <- actualizar_precios(db = archivo, offline = FALSE)
  expect_match(r$bloqueo, "modo sin conexión")
  con2 <- DBI::dbConnect(RSQLite::SQLite(), archivo)
  withr::defer(DBI::dbDisconnect(con2))
  expect_equal(DBI::dbGetQuery(con2, "SELECT COUNT(*) AS n FROM ejecuciones")$n, n_antes)
})

test_that("solo una actualización a la vez; un candado abandonado se reemplaza", {
  candado <- file.path(tempdir(), "prueba_candado.lock")
  withr::defer(unlink(candado, recursive = TRUE))
  unlink(candado, recursive = TRUE)
  expect_true(tomar_candado(candado))
  expect_false(tomar_candado(candado))                # ya hay una en curso
  Sys.setFileTime(candado, Sys.time() - 31 * 60)
  expect_true(tomar_candado(candado, max_min = 30))   # abandonado hace más de 30 min
})
