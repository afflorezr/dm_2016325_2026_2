library(testthat)

# Las pruebas cargan el módulo desde la carpeta del taller y usan bases temporales
raiz <- normalizePath(file.path(test_path(), ".."), winslash = "/")
source(file.path(raiz, "scraper.R"), chdir = TRUE)

test_that("convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("$ 1.234.567"), 1234567)
  expect_true(is.na(limpiar_precio("$ 0")))
  expect_true(is.na(limpiar_precio(NA_character_)))
})

test_that("normaliza el contenido a mL, g o unidad y no toma los miligramos", {
  capsulas <- extraer_contenido("FRASCO X 30 CAP")
  expect_equal(capsulas$cantidad, 30)
  expect_equal(capsulas$unidad, "und")

  litro <- extraer_contenido("JARABE 1 L")
  expect_equal(litro$cantidad, 1000)
  expect_equal(litro$unidad, "mL")

  gramos <- extraer_contenido("SABOR FRESA 380 G")
  expect_equal(gramos$cantidad, 380)
  expect_equal(gramos$unidad, "g")

  miligramos <- extraer_contenido("VITAMINA C 500 MG")
  expect_true(is.na(miligramos$cantidad))
  expect_true(is.na(miligramos$unidad))

  kilo <- extraer_contenido("2 KG")
  expect_equal(kilo$cantidad, 2000)
  expect_equal(kilo$unidad, "g")
})

test_that("el ahorro cuenta el empate en el menor precio", {
  resultado <- resumen_ahorro(c(CAFAM = 10000, `LA REBAJA` = 10000, `LA ALEMANA` = 18000))
  expect_equal(resultado$ahorro, 8000)
  expect_equal(resultado$minimo, 10000)
  expect_setequal(resultado$mas_economicos, c("CAFAM", "LA REBAJA"))
})

test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  ruta <- tempfile(fileext = ".sqlite")
  inicializar_bd_sqlite(ruta)
  fecha <- as.POSIXct("2026-11-14 10:00:00", tz = "America/Bogota")
  df <- tibble(
    comercio = "CAFAM",
    n_producto = "OMEGA 3 X 30 CAP",
    enlace = "https://www.drogueriascafam.com.co/omega-3-30/p",
    precio = "$ 12.900",
    marca = "PROCAPS",
    contenido = NA_character_,
    precio_sin_promo = NA_character_,
    pagina = 1L,
    consulta = "vitaminas",
    fecha_extraccion = fecha
  )
  cargar_comercio(ruta, df, "CAFAM", "TEST_1", fecha, fecha, paginas = 1L, modo = "prueba")
  cargar_comercio(ruta, df, "CAFAM", "TEST_1", fecha, fecha, paginas = 1L, modo = "prueba")
  n <- consultar("SELECT COUNT(*) AS n FROM historico_productos", path = ruta)$n
  expect_equal(n, 1)
})

test_that("detecta subidas, bajadas, productos nuevos y los que dejan de observarse", {
  cambios <- detectar_cambios_precio(
    tibble(
      comercio = c("CAFAM", "CAFAM", "CAFAM", "CAFAM"),
      enlace = c("a", "b", "c", "d"),
      precio_antes = c(10000, 10000, NA, 5000),
      precio_despues = c(12000, NA, 8000, 5050)
    ),
    umbral_pct = 5
  )
  expect_equal(cambios$tipo, c("subio", "no_observado", "nuevo", "subio"))
  expect_equal(cambios$variacion_grande, c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(cambios$delta_cop[1], 2000)
})

test_that("un enlace descartado no produce cambios de precio falsos", {
  ruta <- tempfile(fileext = ".sqlite")
  inicializar_bd_sqlite(ruta)
  lote <- function(fecha, nombre_portada, precio_portada, precio_omega) {
    tibble(
      comercio = "CAFAM",
      n_producto = c("OMEGA 3 X 30 CAP", nombre_portada),
      enlace = c("https://www.drogueriascafam.com.co/omega-3-30/p", "https://www.drogueriascafam.com.co/"),
      precio = c(precio_omega, precio_portada),
      marca = "PROCAPS",
      contenido = NA_character_,
      precio_sin_promo = NA_character_,
      pagina = 1L,
      consulta = "vitaminas",
      fecha_extraccion = fecha
    )
  }
  f1 <- as.POSIXct("2026-11-01 10:00:00", tz = "America/Bogota")
  f2 <- as.POSIXct("2026-11-08 10:00:00", tz = "America/Bogota")
  cargar_comercio(ruta, lote(f1, "REMOVEDOR", "$ 6.400", "$ 10.000"), "CAFAM", "E1", f1, f1, 1L, "prueba")
  cargar_comercio(ruta, lote(f2, "EDAPIL", "$ 115.400", "$ 11.000"), "CAFAM", "E2", f2, f2, 1L, "prueba")
  reconstruir_capa_analitica(ruta)

  cambios <- consultar("SELECT enlace, tipo FROM v_cambios_precio", path = ruta)
  expect_equal(nrow(cambios), 1)
  expect_equal(cambios$tipo, "subio")
  expect_match(cambios$enlace, "omega-3-30/p$")
})

test_that("la canasta no se calcula cuando a un comercio le falta un producto", {
  precios <- tibble(
    comercio = c("CAFAM", "CAFAM", "LA REBAJA"),
    id_producto = c("P01", "P02", "P01"),
    precio = c(10000, 5000, 8000)
  )
  pedido <- tibble(id_producto = c("P01", "P02"), cantidad = c(2, 1))
  resultado <- costo_canasta(precios, pedido)

  cafam <- filter(resultado$por_comercio, comercio == "CAFAM")
  rebaja <- filter(resultado$por_comercio, comercio == "LA REBAJA")
  expect_true(cafam$completo)
  expect_equal(cafam$costo, 25000)
  expect_false(rebaja$completo)
  expect_true(is.na(rebaja$costo))
  expect_equal(resultado$costo_minimo, 21000)
  expect_equal(cafam$ahorro_vs_minimo, 4000)
})
