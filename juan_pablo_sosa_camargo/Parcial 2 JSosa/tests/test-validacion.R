# =============================================================================
# tests/test-validacion.R  -  Reglas de validacion antes de insertar (Modulo 1)
# Datos pequenos en memoria; no toca la base de la entrega.
# =============================================================================

if (!exists("obs", mode = "function")) {
  base <- if (file.exists("scraper.R")) "." else ".."
  source(file.path(base, "tests", "helper-fixtures.R"))
}

test_that("una fila correcta pasa todas las reglas", {
  r <- validar_observaciones(obs())
  expect_equal(nrow(r$validas), 1)
  expect_equal(r$n_rechazadas, 0)
})

test_that("rechaza precios no numericos, cero o negativos", {
  expect_error(validar_observaciones(obs(precio = "12000")))

  mala <- obs(precio = 0)
  r <- validar_observaciones(mala)
  expect_equal(nrow(r$validas), 0)
  expect_match(r$motivos, "precio_positivo")

  mala2 <- obs(precio = -5000)
  expect_equal(nrow(validar_observaciones(mala2)$validas), 0)
})

test_that("rechaza observaciones sin comercio, URL o fecha", {
  mala <- obs(url = NA_character_)
  r <- validar_observaciones(mala)
  expect_equal(nrow(r$validas), 0)
  expect_match(r$motivos, "campos_obligatorios")

  mala2 <- obs(comercio = NA_character_)
  expect_match(validar_observaciones(mala2)$motivos, "campos_obligatorios")

  mala3 <- obs(fecha = NA_character_)
  r3 <- validar_observaciones(mala3)
  expect_true(any(grepl("campos_obligatorios", r3$motivos)))
})

test_that("rechaza precio_antes inconsistente (menor que el precio actual)", {
  mala <- obs()
  mala$precio_antes <- 10000  # < precio_cop 12000
  r <- validar_observaciones(mala)
  expect_equal(nrow(r$validas), 0)
  expect_match(r$motivos, "precio_antes_valido")
})

test_that("detecta duplicados en la misma ejecucion (comercio+URL+fecha)", {
  base <- obs()
  dos <- rbind(base, base)
  r <- validar_observaciones(dos)
  expect_equal(nrow(r$validas), 1)
  expect_equal(r$n_duplicados, 1)
})

test_that("las filas rechazadas quedan con su motivo registrado", {
  mala <- obs(precio = 0); mala$producto <- NA_character_
  r <- validar_observaciones(mala)
  expect_equal(nrow(r$rechazadas), 1)
  expect_true(nzchar(r$rechazadas$motivo[1]))
})
