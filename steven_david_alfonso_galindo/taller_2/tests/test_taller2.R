# Pruebas del Taller 2. Usan datos pequeños y una base temporal; nunca la base
# de la entrega ni los sitios. Se corren desde la carpeta taller_2 con:
#   Rscript -e 'testthat::test_dir("tests")'

library(testthat)

# chdir = TRUE: scraper.R carga validacion.R desde su propia carpeta
source("../scraper.R", encoding = "UTF-8", chdir = TRUE)
source("../db.R", encoding = "UTF-8")

# Base temporal con el esquema del Taller 1 y la migración del Taller 2
base_temporal <- function() {
  CONFIG$ruta_esquema <<- "../sql/esquema.sql"
  con <- dbConnect(RSQLite::SQLite(), tempfile(fileext = ".sqlite"))
  dbExecute(con, "PRAGMA foreign_keys = ON")
  crear_esquema(con)
  aplicar_migracion(con, ruta = "../sql/migracion_t2.sql")
  con
}

# Dos productos de La Riviera tal como los devolvería el scraper
datos_prueba <- function(id_ejecucion, precios, hora = "10:00:00") {
  conformar(tibble(
    comercio = "La Riviera",
    id_producto_comercio = c("perfume-a", "perfume-b"),
    nombre = c("PERFUME A EDP 100ML", "PERFUME B EDT 50ML"),
    precio = precios,
    promocion = FALSE,
    url_extraccion = "https://www.lariviera.co/fragancias?page=1",
    fecha_hora_consulta = paste0(substr(id_ejecucion, 1, 4), "-", substr(id_ejecucion, 5, 6), "-",
                                 substr(id_ejecucion, 7, 8), "T", hora, "-05:00"),
    id_ejecucion = id_ejecucion
  ))
}

cargar <- function(con, id_ejecucion, precios) {
  registrar_inicio(con, id_ejecucion, "la_riviera", ahora_iso(), "en_linea")
  insertar_observaciones(con, datos_prueba(id_ejecucion, precios), "la_riviera")
}

test_that("convierte el precio en texto a número", {
  expect_equal(texto_a_numero("$ 12.900"), 12900)
  expect_equal(texto_a_numero("$1.290.000,00"), 1290000)  # los ,00 del final no cuentan
  expect_true(is.na(texto_a_numero("Agotado")))
  expect_true(is.na(texto_a_numero("$ 0")))
})

test_that("normaliza el contenido y la unidad de la presentación", {
  p <- extraer_presentacion(c("VERSACE EROS EDT 100ML", "Perfume 3.4 FL OZ", "Perfume sin tamaño"))
  expect_equal(p$contenido, c(100, 3.4, NA))
  expect_equal(p$unidad, c("ml", "oz", NA))
})

test_that("el ahorro se calcula bien cuando dos comercios empatan", {
  expect_equal(calcular_ahorro(c(300000, 300000, NA), 250000), 50000)
  precios <- data.frame(
    producto_id = c("A", "A", "B", "B"),
    comercio = c("Falabella", "Farmatodo", "Falabella", "Farmatodo"),
    precio = c(100, 100, 50, 80))
  r <- calcular_canasta(precios, c(A = 1, B = 2))
  expect_equal(r$minimo, 200)          # A en cualquiera (empate) + 2 B en Falabella
  expect_equal(r$ahorro, 0)            # Falabella ya es el más barato en todo
})

test_that("la canasta no falla si ninguna presentación tiene precio", {
  sin_precios <- data.frame(producto_id = character(), comercio = character(), precio = numeric())
  r <- calcular_canasta(sin_precios, c(A = 1))
  expect_equal(nrow(r$por_comercio), 0)
  expect_true(is.na(r$minimo))
})

test_that("un rechazo no se anota dos veces al reprocesar", {
  con <- base_temporal()
  on.exit(dbDisconnect(con))
  cargar(con, "20261110T100000", c(100000, NA))
  cargar(con, "20261110T100000", c(100000, NA))
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) AS n FROM rechazos")$n, 1)
})

test_that("la búsqueda exige cada palabra en el nombre o en la marca", {
  con <- base_temporal()
  on.exit(dbDisconnect(con))
  expect_equal(as.character(condicion_busqueda(con, "", "nombre_original")), "1 = 1")
  expect_equal(as.character(condicion_busqueda(con, "x' OR 1=1", "nombre_original")), "1 = 1")
  dos <- as.character(condicion_busqueda(con, "Versace Eros", "nombre_original"))
  expect_match(dos, "LIKE '%Versace%' OR marca LIKE '%Versace%'", fixed = TRUE)
  expect_match(dos, " AND ", fixed = TRUE)
})

test_that("una ejecución fallida no aparece en la lista de ejecuciones", {
  con <- base_temporal()
  on.exit(dbDisconnect(con))
  cargar(con, "20261110T100000", c(100000, 200000))
  dbExecute(con, "UPDATE ejecuciones SET estado = 'completa' WHERE id_ejecucion = '20261110T100000'")
  registrar_inicio(con, "20261111T100000", "la_riviera", "2026-11-11T10:00:00-05:00", "en_linea")
  expect_equal(lista_ejecuciones(con)$id_ejecucion, "20261110T100000")
  expect_equal(ultima_ejecucion(con), "20261110T100000")
})

test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  con <- base_temporal()
  on.exit(dbDisconnect(con))
  primera <- cargar(con, "20261110T100000", c(100000, 200000))
  segunda <- cargar(con, "20261110T100000", c(100000, 200000))
  expect_equal(primera$nuevas, 2)
  expect_equal(segunda$nuevas, 0)
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones")$n, 2)
})

test_that("detecta los cambios de precio entre dos ejecuciones", {
  con <- base_temporal()
  on.exit(dbDisconnect(con))
  cargar(con, "20261010T100000", c(100000, 200000))
  cargar(con, "20261110T100000", c(120000, 200000))
  cambios <- comparar_ejecuciones(con, "20261010T100000", "20261110T100000", umbral = 10)
  expect_equal(nrow(cambios), 1)                 # el que no cambió no aparece
  expect_equal(cambios$situacion, "Subió")
  expect_equal(cambios$cambio_cop, 20000)
  expect_equal(cambios$cambio_pct, 20)
  expect_equal(cambios$grande, 1)
})

test_that("la canasta no se calcula en un comercio al que le falta un producto", {
  precios <- data.frame(
    producto_id = c("A", "B", "A"),
    comercio = c("Falabella", "Falabella", "Farmatodo"),
    precio = c(100, 50, 90))
  r <- calcular_canasta(precios, c(A = 1, B = 1))
  farmatodo <- r$por_comercio[r$por_comercio$comercio == "Farmatodo", ]
  expect_true(is.na(farmatodo$total))
  expect_equal(farmatodo$faltan, "B")
  expect_equal(r$por_comercio$total[r$por_comercio$comercio == "Falabella"], 150)
})

test_that("una observación sin precio se rechaza y no se inserta", {
  con <- base_temporal()
  on.exit(dbDisconnect(con))
  carga <- cargar(con, "20261110T100000", c(100000, NA))
  expect_equal(carga$nuevas, 1)
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) AS n FROM rechazos")$n, 1)
})

test_that("la búsqueda rechaza texto que podría ser inyección SQL", {
  expect_equal(limpiar_busqueda("  Versace Eros "), "Versace Eros")
  expect_equal(limpiar_busqueda("x' OR 1=1; DROP TABLE observaciones; --"), "")
  expect_equal(limpiar_busqueda(strrep("a", 61)), "")
})
