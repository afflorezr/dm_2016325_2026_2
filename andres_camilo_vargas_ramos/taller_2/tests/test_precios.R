
library(testthat)
library(DBI)
library(RSQLite)
library(tibble)
library(dplyr)

ruta_raiz <- if (file.exists("scraper.R")) "." else ".."
source(file.path(ruta_raiz, "scraper.R"), chdir = TRUE)
source(file.path(ruta_raiz, "validacion.R"), chdir = TRUE)
source(file.path(ruta_raiz, "db.R"), chdir = TRUE)

crear_bd_temporal <- function() {
  tf <- tempfile(fileext = ".sqlite")
  con <- dbConnect(SQLite(), tf)
  on.exit(dbDisconnect(con), add = TRUE)
  migrar_esquema_t2(con)

  dbAppendTable(con, "productos", tibble(
    id_producto      = c("P01", "P02"),
    nombre_std       = c("Suero Fresa 500 mL", "Sobres Sales 20 g"),
    marca_std        = c("MarcaA", "MarcaB"),
    subcategoria_std = c("Sueros", "Sales"),
    contenido        = c(500, 20),
    unidad           = c("ml", "g"),
    n_unidades       = c(1L, 1L),
    contenido_total  = c(500, 20),
    unidad_norm      = c("mL", "g")
  ))

  dbAppendTable(con, "correspondencia", tibble(
    id_producto = c("P01", "P01", "P02", "P02"),
    comercio    = c("ComercioA", "ComercioB", "ComercioA", "ComercioB"),
    sku         = c("A1", "B1", "A2", "B2"),
    verificado  = c(1L, 1L, 1L, 1L),
    nota        = NA_character_
  ))

  dbAppendTable(con, "ejecuciones", tibble(
    id_ejecucion = c("EJ1", "EJ1", "EJ2", "EJ2"),
    comercio     = c("ComercioA", "ComercioB", "ComercioA", "ComercioB"),
    inicio       = c("2026-10-01T10:00:00-05:00", "2026-10-01T10:01:00-05:00",
                     "2026-11-01T10:00:00-05:00", "2026-11-01T10:01:00-05:00"),
    fin          = c("2026-10-01T10:00:30-05:00", "2026-10-01T10:01:30-05:00",
                     "2026-11-01T10:00:30-05:00", "2026-11-01T10:01:30-05:00"),
    modo         = rep("sin_conexion", 4),
    n_registros  = c(2L, 2L, 2L, 1L),
    n_esperado   = rep(2L, 4),
    estado       = c("completa", "completa", "completa", "parcial"),
    detalle      = NA_character_
  ))

  dbAppendTable(con, "observaciones", tibble(
    id_ejecucion          = c("EJ1", "EJ1", "EJ1", "EJ1", "EJ2", "EJ2", "EJ2"),
    comercio              = c("ComercioA", "ComercioA", "ComercioB", "ComercioB",
                              "ComercioA", "ComercioA", "ComercioB"),
    sku                   = c("A1", "A2", "B1", "B2", "A1", "A2", "B1"),
    nombre_original       = c("Suero 500", "Sal 20", "Suero 500", "Sal 20",
                              "Suero 500", "Sal 20", "Suero 500"),
    marca                 = c("MarcaA", "MarcaB", "MarcaA", "MarcaB", "MarcaA", "MarcaB", "MarcaA"),
    subcategoria          = rep("Digestivo", 7),
    descripcion_original  = rep("Desc", 7),
    precio                = c(10000, 5000, 10000, 6000, 12000, 4500, 10000),
    precio_antes          = rep(NA_real_, 7),
    promocion             = rep(0L, 7),
    disponible            = rep(1L, 7),
    estado_disponibilidad = rep("disponible", 7),
    descartada            = rep(0L, 7),
    url                   = paste0("https://ejemplo.com/", 1:7),
    fecha_hora_consulta   = c("2026-10-01T10:00:10-05:00", "2026-10-01T10:00:11-05:00",
                              "2026-10-01T10:01:10-05:00", "2026-10-01T10:01:11-05:00",
                              "2026-11-01T10:00:10-05:00", "2026-11-01T10:00:11-05:00",
                              "2026-11-01T10:01:10-05:00")
  ))

  tf
}

test_that("1. Convierte precios en texto colombiano a número y limpia inválidos", {
  expect_equal(precio_texto_a_num("$ 12.900"), 12900)
  expect_equal(precio_texto_a_num("$3.050 (Normal)"), 3050)
  expect_equal(precio_texto_a_num("$ 10.250,00"), 10250)
  expect_true(is.na(precio_texto_a_num("$ 0")))
  expect_true(is.na(precio_texto_a_num("Agotado")))
})

test_that("2. Normaliza unidades a mL, g y unidad y calcula precio unitario", {
  bd <- crear_bd_temporal()
  on.exit(unlink(bd), add = TRUE)

  res_ml <- consultar_precio_unitario_por_unidad(bd, unidad_sel = "mL")
  expect_true(all(res_ml$unidad_norm == "mL"))
  expect_equal(res_ml$precio_unitario[res_ml$comercio == "ComercioA"], 24)
  expect_equal(res_ml$precio_unitario[res_ml$comercio == "ComercioB"], 20)
})

test_that("3. Calcula correctamente el ahorro y reporta empates entre comercios", {
  bd <- crear_bd_temporal()
  on.exit(unlink(bd), add = TRUE)

  items <- tibble(id_producto = c("P01", "P02"), cantidad = c(1L, 2L))
  res <- calcular_canasta(bd, items, id_ejecucion = "EJ1")

  expect_equal(res$costo_optimo, 20000)
  expect_equal(res$ahorro_vs_mejor_tienda, 0)
  expect_equal(res$ahorro_vs_peor_tienda, 2000)
  expect_match(res$optima_detalle$mejor_comercio[res$optima_detalle$id_producto == "P01"], "ComercioA / ComercioB")
})

test_that("4. La restricción de unicidad impide duplicar observaciones repetidas", {
  bd <- crear_bd_temporal()
  on.exit(unlink(bd), add = TRUE)

  con <- dbConnect(SQLite(), bd)
  on.exit(dbDisconnect(con), add = TRUE)

  antes <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones")$n
  ins <- dbExecute(con, "
    INSERT OR IGNORE INTO observaciones
    (id_ejecucion, comercio, sku, nombre_original, precio, url, fecha_hora_consulta)
    VALUES ('EJ1', 'ComercioA', 'A1', 'Suero 500', 10000, 'https://ejemplo.com/1', '2026-10-01T10:00:10-05:00')
  ")
  despues <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones")$n

  expect_equal(ins, 0)
  expect_equal(antes, despues)
})

test_that("5. Detecta subidas, bajadas y productos que dejaron de observarse", {
  bd <- crear_bd_temporal()
  on.exit(unlink(bd), add = TRUE)

  cmp <- comparar_dos_ejecuciones(bd, ej_anterior = "EJ1", ej_actual = "EJ2")

  a1 <- cmp |> filter(comercio == "ComercioA", sku == "A1")
  expect_equal(a1$cambio_cop, 2000)
  expect_equal(a1$cambio_pct, 20)
  expect_equal(a1$estado_cambio, "Subió")

  a2 <- cmp |> filter(comercio == "ComercioA", sku == "A2")
  expect_equal(a2$cambio_cop, -500)
  expect_equal(a2$cambio_pct, -10)
  expect_equal(a2$estado_cambio, "Bajó")

  b2 <- cmp |> filter(comercio == "ComercioB", sku == "B2")
  expect_equal(b2$estado_cambio, "Dejó de observarse")
})

test_that("6. No calcula total de canasta cuando falta un producto en el comercio", {
  bd <- crear_bd_temporal()
  on.exit(unlink(bd), add = TRUE)

  items <- tibble(id_producto = c("P01", "P02"), cantidad = c(1L, 1L))
  res <- calcular_canasta(bd, items, id_ejecucion = "EJ2")

  fila_b <- res$por_comercio |> filter(comercio == "ComercioB")
  expect_false(fila_b$completa)
  expect_true(is.na(fila_b$costo_total))
  expect_match(fila_b$estado_canasta, "Incompleta")
})

test_that("7. La validación separa filas inválidas con motivo y conserva las válidas", {
  df_prueba <- tibble(
    comercio            = c("Colsubsidio", "Colsubsidio", "Farmatodo"),
    sku                 = c("101", "102", "103"),
    nombre_original     = c("Prod OK", "Prod Precio Cero", "Prod Sin URL"),
    marca               = c("M1", "M1", "M2"),
    subcategoria        = c("Sub", "Sub", "Sub"),
    descripcion_original= c("D1", "D2", "D3"),
    precio              = c(15000, 0, 12000),
    precio_antes        = c(NA_real_, NA_real_, NA_real_),
    promocion           = c(0L, 0L, 0L),
    disponible          = c(1L, 1L, 1L),
    url                 = c("https://ok.com", "https://cero.com", NA_character_),
    fecha_hora_consulta = rep("2026-11-13T10:00:00-05:00", 3)
  )

  val <- validar_observaciones(df_prueba, id_ejecucion = "TEST_EJ")
  expect_equal(nrow(val$validas), 1)
  expect_equal(nrow(val$rechazadas), 2)
})

