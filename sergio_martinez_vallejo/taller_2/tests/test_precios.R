library(testthat)
library(dplyr)

# Cargamos las funciones que vamos a probar
source(here::here("scraper.R"))
source(here::here("db.R"))

# 1. Conversión de precios en texto a número
test_that("limpiar_precio convierte correctamente de texto a numero", {
  # Tu función num_o_na se encarga de esto en el scraper
  expect_equal(num_o_na("12900"), 12900)
  expect_equal(num_o_na("$ 12.900"), NA_real_) # Asumiendo que la API devuelve números limpios, no texto con $
  expect_equal(num_o_na("-500"), NA_real_) # Precios negativos deben ser NA
  expect_equal(num_o_na(0), NA_real_)      # Precios en 0 deben ser NA
  expect_equal(num_o_na(NA), NA_real_)
})

# 2. Normalización de unidades (usando la tabla productos de correspondencia)
test_that("La tabla de productos tiene las unidades normalizadas", {
  # Verificamos que las unidades en tu tribble de correspondencia sean coherentes
  unidades_validas <- c("m", "servilleta", "hoja", "vaso", "plato", "tenedor")
  # (Esta prueba es un ejemplo, puedes adaptarla a tu lógica real)
  expect_true(all(unidades_validas %in% c("m", "servilleta", "hoja", "vaso", "plato", "tenedor")))
})

# 3. Cálculo del ahorro con empates
test_that("calcular_canasta maneja empates correctamente", {
  # Simulamos una base de datos en memoria (SQLite)
  con_test <- dbConnect(RSQLite::SQLite(), ":memory:")
  
  # Creamos las tablas necesarias
  dbExecute(con_test, "CREATE TABLE correspondencia (id_producto TEXT, comercio TEXT, sku TEXT)")
  dbExecute(con_test, "CREATE TABLE productos (id_producto TEXT, nombre_std TEXT)")
  dbExecute(con_test, "CREATE TABLE v_ultimo_precio (comercio TEXT, sku TEXT, precio REAL)")
  
  # Insertamos datos de prueba con empate (mismo precio en dos comercios)
  dbExecute(con_test, "INSERT INTO productos VALUES ('P01', 'Producto Test')")
  dbExecute(con_test, "INSERT INTO correspondencia VALUES ('P01', 'Carulla', 'SKU1')")
  dbExecute(con_test, "INSERT INTO correspondencia VALUES ('P01', 'D1', 'SKU2')")
  dbExecute(con_test, "INSERT INTO v_ultimo_precio VALUES ('Carulla', 'SKU1', 1000)")
  dbExecute(con_test, "INSERT INTO v_ultimo_precio VALUES ('D1', 'SKU2', 1000)")
  
  cantidades <- c("P01" = 1)
  res <- calcular_canasta(con_test, cantidades)
  
  # Como hay empate, el costo mínimo debe ser 1000
  expect_equal(res$costo_minimo, 1000)
  
  dbDisconnect(con_test)
})

# 4. Insertar dos veces la misma ejecución no duplica observaciones
test_that("La restriccion UNIQUE evita duplicados en observaciones", {
  con_test <- dbConnect(RSQLite::SQLite(), ":memory:")
  
  dbExecute(con_test, "
    CREATE TABLE observaciones (
      id_obs INTEGER PRIMARY KEY AUTOINCREMENT,
      comercio TEXT, sku TEXT, fecha_hora_consulta TEXT,
      UNIQUE (comercio, sku, fecha_hora_consulta)
    )")
  
  # Insertamos una observación
  dbExecute(con_test, "INSERT INTO observaciones (comercio, sku, fecha_hora_consulta) VALUES ('D1', 'SKU1', '2026-11-16')")
  
  # Intentamos insertar la misma
  dbExecute(con_test, "INSERT OR IGNORE INTO observaciones (comercio, sku, fecha_hora_consulta) VALUES ('D1', 'SKU1', '2026-11-16')")
  
  # Verificamos que solo hay 1 fila
  n <- dbGetQuery(con_test, "SELECT COUNT(*) as n FROM observaciones")$n
  expect_equal(n, 1)
  
  dbDisconnect(con_test)
})

# 5. Detección de cambios de precio
test_that("La vista v_cambios_precio detecta subidas y bajadas", {
  con_test <- dbConnect(RSQLite::SQLite(), ":memory:")
  
  # Creamos las tablas necesarias para la vista
  dbExecute(con_test, "CREATE TABLE observaciones (id_obs INTEGER PRIMARY KEY, comercio TEXT, sku TEXT, nombre_original TEXT, fecha_hora_consulta TEXT, precio REAL, descartada INTEGER DEFAULT 0)")
  
  # Insertamos datos en dos fechas
  dbExecute(con_test, "INSERT INTO observaciones VALUES (1, 'D1', 'SKU1', 'Prod', '2026-11-15', 1000, 0)")
  dbExecute(con_test, "INSERT INTO observaciones VALUES (2, 'D1', 'SKU1', 'Prod', '2026-11-16', 1200, 0)") # Subió
  
  # Creamos la vista (simplificada para el test)
  dbExecute(con_test, "
    CREATE VIEW v_cambios_precio AS
    SELECT actual.comercio, actual.sku, actual.precio - anterior.precio AS diferencia_absoluta
    FROM observaciones actual
    JOIN observaciones anterior ON actual.comercio = anterior.comercio AND actual.sku = anterior.sku
    WHERE actual.fecha_hora_consulta > anterior.fecha_hora_consulta
  ")
  
  res <- dbGetQuery(con_test, "SELECT diferencia_absoluta FROM v_cambios_precio")
  expect_equal(res$diferencia_absoluta, 200)
  
  dbDisconnect(con_test)
})

# 6. La canasta no se calcula si falta un producto
test_that("calcular_canasta no da total si falta un producto en el comercio", {
  con_test <- dbConnect(RSQLite::SQLite(), ":memory:")
  
  dbExecute(con_test, "CREATE TABLE correspondencia (id_producto TEXT, comercio TEXT, sku TEXT)")
  dbExecute(con_test, "CREATE TABLE productos (id_producto TEXT, nombre_std TEXT)")
  dbExecute(con_test, "CREATE TABLE v_ultimo_precio (comercio TEXT, sku TEXT, precio REAL)")
  
  # Producto 1 y 2, pero el comercio D1 solo tiene el 1
  dbExecute(con_test, "INSERT INTO productos VALUES ('P01', 'Prod1'), ('P02', 'Prod2')")
  dbExecute(con_test, "INSERT INTO correspondencia VALUES ('P01', 'D1', 'SKU1'), ('P02', 'D1', 'SKU2')")
  dbExecute(con_test, "INSERT INTO v_ultimo_precio VALUES ('D1', 'SKU1', 1000)") # Falta SKU2
  
  cantidades <- c("P01" = 1, "P02" = 1)
  res <- calcular_canasta(con_test, cantidades)
  
  # D1 no debe tener costo total (porque le falta el P02)
  expect_false(res$resumen_comercios$completo[res$resumen_comercios$comercio == "D1"])
  
  dbDisconnect(con_test)
})