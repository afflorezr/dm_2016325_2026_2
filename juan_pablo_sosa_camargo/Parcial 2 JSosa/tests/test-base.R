# =============================================================================
# tests/test-base.R  -  SQLite: duplicados, cambios de precio, ahorro y canasta
# Usa SOLO una base temporal (tempfile): nunca la base de la entrega.
# =============================================================================

if (!exists("obs", mode = "function")) {
  base <- if (file.exists("scraper.R")) "." else ".."
  source(file.path(base, "tests", "helper-fixtures.R"))
}

# ---- tests -----------------------------------------------------------------

test_that("insertar dos veces la misma ejecucion no duplica observaciones", {
  b <- crear_base_temporal(); on.exit({DBI::dbDisconnect(b$con); unlink(b$ruta)})
  df <- obs()
  r1 <- persistir_comercio(b$con, df, info_de(df))
  expect_equal(r1$insertados, 1)

  r2 <- persistir_comercio(b$con, df, info_de(df))
  expect_equal(r2$insertados, 0)

  n <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) n FROM observaciones")$n
  expect_equal(n, 1)
})

test_that("detecta cambios de precio entre dos ejecuciones", {
  b <- crear_base_temporal(); on.exit({DBI::dbDisconnect(b$con); unlink(b$ruta)})
  df1 <- obs(precio = 10000, fecha = "2026-11-10T10:00:00-05:00",
             ejec = "ejec_A")
  df2 <- obs(precio = 12500, fecha = "2026-11-11T10:00:00-05:00",
             ejec = "ejec_B")
  persistir_comercio(b$con, df1, info_de(df1))
  persistir_comercio(b$con, df2, info_de(df2))

  cambios <- DBI::dbGetQuery(b$con, "
    SELECT precio_actual, precio_anterior, variacion_cop, variacion_pct
    FROM v_cambios_precio")
  expect_equal(nrow(cambios), 1)
  expect_equal(cambios$precio_anterior, 10000)
  expect_equal(cambios$precio_actual, 12500)
  expect_equal(cambios$variacion_cop, 2500)

  # y la vista de ultima observacion queda en el precio nuevo
  ult <- DBI::dbGetQuery(b$con, "SELECT precio_cop FROM v_ultimo_precio")
  expect_equal(ult$precio_cop, 12500)
})

test_that("el ahorro maximo entre comercios se calcula en SQL por comparable", {
  b <- crear_base_temporal(); on.exit({DBI::dbDisconnect(b$con); unlink(b$ruta)})
  # p1: 10000 vs 15000 => ahorro 5000 (33.3 %); p2: empate => ahorro 0
  filas <- rbind(
    obs(comercio = "Farmatodo", url = "https://t.com/p1a", precio = 10000,
        comparable = 1L, id_comun = "p1"),
    obs(comercio = "Jumbo", url = "https://t.com/p1b", precio = 15000,
        comparable = 1L, id_comun = "p1"),
    obs(comercio = "Farmatodo", url = "https://t.com/p2a", precio = 5000,
        comparable = 1L, id_comun = "p2"),
    obs(comercio = "Jumbo", url = "https://t.com/p2b", precio = 5000,
        comparable = 1L, id_comun = "p2")
  )
  for (i in seq_len(nrow(filas)))
    persistir_comercio(b$con, filas[i, , drop = FALSE],
                       info_de(filas[i, , drop = FALSE]))

  a <- indicador_ahorro_maximo(b$con)
  expect_equal(nrow(a), 1)
  expect_equal(a$id_comun, "p1")
  expect_equal(a$ahorro_max_cop, 5000)
  expect_equal(a$ahorro_max_pct, round(100 * 5000 / 15000, 1))
})

test_that("el ahorro maximo es cero cuando los precios empatan", {
  b <- crear_base_temporal(); on.exit({DBI::dbDisconnect(b$con); unlink(b$ruta)})
  filas <- rbind(
    obs(comercio = "Farmatodo", url = "https://t.com/p1a", precio = 5000,
        comparable = 1L, id_comun = "p1"),
    obs(comercio = "Jumbo", url = "https://t.com/p1b", precio = 5000,
        comparable = 1L, id_comun = "p1")
  )
  for (i in seq_len(nrow(filas)))
    persistir_comercio(b$con, filas[i, , drop = FALSE],
                       info_de(filas[i, , drop = FALSE]))

  a <- indicador_ahorro_maximo(b$con)
  expect_equal(a$ahorro_max_cop, 0)
  expect_equal(a$ahorro_max_pct, 0)
})

test_that("la canasta en SQL exige todos los productos y usa el minimo por producto", {
  b <- crear_base_temporal(); on.exit({DBI::dbDisconnect(b$con); unlink(b$ruta)})
  # Farmatodo tiene los 2 productos; Jumbo solo p1 y mas caro
  filas <- rbind(
    obs(comercio = "Farmatodo", url = "https://t.com/a1", precio = 1000,
        comparable = 1L, id_comun = "p1"),
    obs(comercio = "Farmatodo", url = "https://t.com/a2", precio = 2000,
        comparable = 1L, id_comun = "p2"),
    obs(comercio = "Jumbo", url = "https://t.com/b1", precio = 1500,
        comparable = 1L, id_comun = "p1")
  )
  for (i in seq_len(nrow(filas)))
    persistir_comercio(b$con, filas[i, , drop = FALSE],
                       info_de(filas[i, , drop = FALSE]))

  cant <- c(p1 = 1, p2 = 2)

  pc <- canasta_por_comercio(b$con, cant)
  expect_equal(nrow(pc), 2)
  expect_equal(pc$productos_ok[pc$comercio == "Farmatodo"], 2)
  expect_equal(pc$costo_total[pc$comercio == "Farmatodo"], 1000 + 2 * 2000)
  expect_equal(pc$productos_ok[pc$comercio == "Jumbo"], 1)

  mn <- canasta_minima(b$con, cant)
  expect_false(mn$incompleto)
  expect_equal(mn$costo_minimo, 1000 + 2 * 2000)
  expect_equal(mn$productos, 2)

  det <- canasta_detalle(b$con, cant)
  expect_equal(nrow(det), 2)
  expect_equal(det$mejor_comercio[det$id_comun == "p1"], "Farmatodo")
  expect_equal(det$precio_min[det$id_comun == "p2"], 2000)

  # si falta un producto en toda la base, no se calcula
  mn2 <- canasta_minima(b$con, c(p1 = 1, p2 = 2, p3 = 1))
  expect_true(mn2$incompleto)
})

test_that("validar_texto_busqueda limita longitud y caracteres", {
  expect_equal(validar_texto_busqueda("johnson manzanilla"), "johnson manzanilla")
  expect_equal(validar_texto_busqueda("  <script>  "), "script")
  largo <- strrep("a", 200)
  expect_lte(nchar(validar_texto_busqueda(largo)), 80)
  expect_equal(validar_texto_busqueda(NULL), "")
})
