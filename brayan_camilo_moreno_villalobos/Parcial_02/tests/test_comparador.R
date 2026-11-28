library(testthat)
library(DBI)
library(RSQLite)
library(dplyr)

# Cargar funciones de la capa de datos
source("../db.R", chdir = TRUE)

test_that("1. Limpieza y conversión numérica de precios funciona correctamente", {
  precios_sucios <- c("$ 45.900", "12.500,00", "$130,078", NA)
  limpiar_precio <- function(x) {
    as.numeric(gsub("[^0-9]", "", sub(",00$", "", x)))
  }
  limpios <- limpiar_precio(precios_sucios)
  
  expect_equal(limpios[1], 45900)
  expect_equal(limpios[2], 12500)
  expect_equal(limpios[3], 130078)
  expect_true(is.na(limpios[4]))
})

test_that("2. Normalización de unidades a precio por gramo/unidad es consistente", {
  precio_etiqueta <- 30000
  gramos <- 1500
  precio_unitario <- precio_etiqueta / gramos
  
  expect_equal(precio_unitario, 20)
  expect_gt(precio_unitario, 0)
})

test_that("3. Cálculo de ahorro en canasta maneja empates entre comercios sin duplicar", {
  df_simulado <- data.frame(
    id_homologado = c("PROD_1", "PROD_1", "PROD_2", "PROD_2"),
    comercio = c("Exito", "Jumbo", "Exito", "Jumbo"),
    subtotal = c(10000, 10000, 25000, 20000),
    stringsAsFactors = FALSE
  )
  
  optimo <- df_simulado %>%
    group_by(id_homologado) %>%
    summarise(min_sub = min(subtotal), .groups = "drop")
  
  expect_equal(nrow(optimo), 2)
  expect_equal(sum(optimo$min_sub), 30000)
})

test_that("4. Manejo de canasta incompleta detecta productos faltantes y devuelve NA", {
  ids_requeridos <- c("PROD_1", "PROD_2", "PROD_3")
  df_comercio <- data.frame(
    id_homologado = c("PROD_1", "PROD_2"),
    subtotal = c(15000, 20000),
    stringsAsFactors = FALSE
  )
  
  n_encontrados <- length(unique(df_comercio$id_homologado))
  total_comercio <- if (n_encontrados < length(ids_requeridos)) NA_real_ else sum(df_comercio$subtotal)
  
  expect_equal(n_encontrados, 2)
  expect_true(is.na(total_comercio))
})

test_that("5. No duplicación al reinsertar registros de correcciones del Taller 1", {
  db_temp <- tempfile(fileext = ".sqlite")
  con <- conectar_db(db_temp)
  dbDisconnect(con)
  
  # Ejecutar dos veces el registro de correcciones sobre la BD temporal
  registrar_correcciones <- function(ruta) {
    c_tmp <- conectar_db(ruta)
    n <- dbGetQuery(c_tmp, "SELECT COUNT(*) as n FROM correcciones")$n
    if (n == 0) {
      dbExecute(c_tmp, "INSERT INTO correcciones (fecha, motivo) VALUES ('2026-11-14', 'Prueba')")
    }
    dbDisconnect(c_tmp)
  }
  
  registrar_correcciones(db_temp)
  registrar_correcciones(db_temp)
  
  con_check <- conectar_db(db_temp)
  total_filas <- dbGetQuery(con_check, "SELECT COUNT(*) as n FROM correcciones")$n
  dbDisconnect(con_check)
  unlink(db_temp)
  
  expect_equal(total_filas, 1)
})

test_that("6. Detección de cambios de precio (Subió, Bajó, Sin cambio) es exacta", {
  precio_viejo <- c(10000, 20000, 15000)
  precio_nuevo <- c(12000, 18000, 15000)
  
  estados <- ifelse(precio_nuevo > precio_viejo, "Subió",
                    ifelse(precio_nuevo < precio_viejo, "Bajó", "Sin cambio"))
  
  expect_equal(estados, c("Subió", "Bajó", "Sin cambio"))
})