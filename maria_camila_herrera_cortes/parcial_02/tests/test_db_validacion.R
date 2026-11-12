library(testthat)

test_that("la migración es idempotente y crea tablas, índices y vistas", {
  ruta <- crear_base_prueba()
  migrar_esquema_t2(ruta); migrar_esquema_t2(ruta)          # dos veces: sin error ni duplicados
  con <- dbConnect(SQLite(), ruta); on.exit(dbDisconnect(con))
  objs <- dbGetQuery(con, "SELECT name FROM sqlite_master")$name
  expect_true(all(c("correcciones", "observaciones_rechazadas", "v_ultimo_precio",
                    "v_cambios_precio", "v_comparables", "v_disponibilidad",
                    "ux_obs_anuncio_ejecucion") %in% objs))
})

test_that("insertar dos veces la misma observación no la duplica", {
  ruta <- crear_base_prueba()
  con <- dbConnect(SQLite(), ruta); on.exit(dbDisconnect(con))
  antes <- dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n
  sql <- "INSERT OR IGNORE INTO observaciones (anuncio_id, ejecucion_id, fecha_hora_consulta, precio_cop, comparable)
          VALUES (1, 'run_A', '2026-11-01T10:00:01-05:00', 10000, 1)"
  dbExecute(con, sql); dbExecute(con, sql)
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n, antes)
  # misma ejecución y mismo anuncio con otra hora tampoco entra (restricción por ejecución)
  expect_error(dbExecute(con, "INSERT INTO observaciones (anuncio_id, ejecucion_id, fecha_hora_consulta, precio_cop, comparable)
                               VALUES (1, 'run_A', '2026-11-01T11:11:11-05:00', 10000, 1)"))
})

test_that("la validación rechaza precios inválidos, campos vacíos y duplicados, y acepta agotados sin precio", {
  d <- data.frame(comercio = c("exito", "exito", "jumbo", "jumbo", "olimpica"), ejecucion_id = "r1",
                  product_id = c("1", "1", "2", "3", "4"), sku = c("a", "a", "b", "c", "d"),
                  url = c("u", "u", "u", NA, "u"), fecha_hora_consulta = "2026-11-05T10:00:00-05:00",
                  precio_cop = c(1000, 1000, -5, 500, NA), disponible = c(TRUE, TRUE, TRUE, TRUE, FALSE))
  v <- validar_observaciones(d)
  expect_equal(v$valida, c(TRUE, FALSE, FALSE, FALSE, TRUE))   # duplicado, precio<=0, sin URL; agotado sin precio pasa
})

test_that("se detecta cuando falta un producto comparable en un comercio", {
  d <- data.frame(comercio = c("exito", "exito", "jumbo"), producto_id = c("P01", "P02", "P01"), incluido = TRUE)
  prod <- data.frame(producto_id = c("P01", "P02"), principal = 1L)
  r <- completitud_comparables(d, prod)
  expect_equal(r$completo[r$comercio == "exito"], TRUE)
  expect_equal(r$completo[r$comercio == "jumbo"], FALSE)
  expect_equal(r$faltantes[r$comercio == "jumbo"], "P02")
})

test_that("el texto del usuario se valida y una inyección SQL no tiene efecto", {
  expect_error(validar_texto("x'; DROP TABLE anuncios;--"))
  expect_error(validar_texto(strrep("a", 200)))
  expect_equal(validar_texto("  esmalte gel "), "esmalte gel")
  ruta <- crear_base_prueba(); migrar_esquema_t2(ruta)
  # un valor malicioso como filtro (marca) viaja como parámetro: no devuelve nada y no rompe la base
  r <- db_precios_filtrados(marcas = "x'; DROP TABLE anuncios;--", ruta = ruta)
  expect_equal(nrow(r), 0)
  expect_gt(nrow(db_precios_filtrados(ruta = ruta)), 0)
  # los comodines % y _ se tratan como texto literal
  expect_equal(nrow(db_precios_filtrados(busqueda = "%", ruta = ruta)), 0)
})

test_that("las vistas distinguen disponible, agotado y no observado, y la última ejecución", {
  ruta <- crear_base_prueba(); migrar_esquema_t2(ruta)
  disp <- db_consultar("SELECT nombre, ejecucion_id, estado FROM v_disponibilidad", ruta = ruta)
  expect_equal(disp$estado[disp$nombre == "Lima Y" & disp$ejecucion_id == "run_A"], "agotado")
  expect_equal(disp$estado[disp$nombre == "Lima Y" & disp$ejecucion_id == "run_B"], "no_observado")
  ult <- db_consultar("SELECT DISTINCT ejecucion_id FROM v_ultimo_precio", ruta = ruta)
  expect_equal(ult$ejecucion_id, "run_B")
})

test_that("la comparación de ejecuciones clasifica subió, igual, y no observado", {
  ruta <- crear_base_prueba(); migrar_esquema_t2(ruta)
  r <- clasificar_cambios(db_comparar_ejecuciones("run_A", "run_B", ruta), umbral_pct = 5)
  expect_equal(r$tipo[r$nombre == "Removedor X" & r$comercio == "exito"], "subió")
  expect_equal(r$variacion_pct[r$comercio == "exito" & r$nombre == "Removedor X"], 10)
  expect_true(r$variacion_grande[r$comercio == "exito" & r$nombre == "Removedor X"])
  expect_equal(r$tipo[r$comercio == "jumbo"], "igual")
  expect_equal(r$tipo[r$nombre == "Lima Y"], "no observado")
})
