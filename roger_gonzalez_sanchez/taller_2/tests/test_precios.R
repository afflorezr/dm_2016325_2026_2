test_that("convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("$1.299.900"), 1299900)
  expect_equal(limpiar_precio("12.900,50"), 12900.5)
  # num1() es la conversión que usa el scraper del Taller 1 con los valores JSON
  expect_equal(num1("12900"), 12900)
  expect_true(is.na(num1(NULL)))
})

test_that("normaliza el contenido y la unidad", {
  # extraer_contenido() es la normalización del Taller 1 (R/02)
  r <- extraer_contenido(c("Abrilar jarabe 100 ml", "Dolex Gripa x 12 tabletas",
                           "Fluimucil 600 mg x 10 sobres", "Jarabe 1 L"))
  expect_equal(r$contenido_num, c(100, 12, 10, 1000))
  expect_equal(r$unidad_medida, c("mL", "unidad", "sobres", "mL"))

  # v_observaciones lleva cada unidad a mL, g o unidad
  b <- base_temporal()
  on.exit(cerrar_conexion(b$con))
  d <- obs_prueba(c("1", "2", "3"), c(1000, 2000, 3000), "2026-11-10T10:00:00-05:00", "EJ_A", b$raw)
  d$contenido_num <- c(500, 10, 120)
  d$unidad_medida <- c("mg", "sobres", "mL")
  registrar_ejecucion(b$con, "EJ_A", "Farmatodo", "2026-11-10T10:00:00-05:00", 3L, "COMPLETA", "online")
  db_insertar_observaciones(b$con, preparar_observaciones(d))
  v <- dbGetQuery(b$con, "SELECT contenido_total, unidad_normalizada, precio_unitario
                          FROM v_observaciones ORDER BY sku_comercio")
  expect_equal(v$unidad_normalizada, c("g", "unidad", "mL"))
  expect_equal(v$contenido_total, c(0.5, 10, 120))
  expect_equal(v$precio_unitario, c(2000, 200, 25))
})
