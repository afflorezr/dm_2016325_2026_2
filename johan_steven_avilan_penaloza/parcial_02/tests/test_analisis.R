# Pruebas del análisis para el consumidor y de la capa de acceso (Módulos 3, 4 y 6)

precios_canasta_prueba <- function() {
  data.frame(
    id_comparable = c(1, 1, 1, 2, 2),
    producto      = c("Alcohol", "Alcohol", "Alcohol", "Gasa", "Gasa"),
    comercio      = c("Farmatodo", "La Rebaja", "Locatel", "Farmatodo", "Locatel"),
    precio        = c(10000, 8000, 8000, 5000, 6000),
    stringsAsFactors = FALSE)
}

test_that("el ahorro con empates lista todos los comercios empatados", {
  a <- ahorro_por_producto(precios_canasta_prueba())
  alcohol <- a[a$producto == "Alcohol", ]
  expect_equal(alcohol$minimo, 8000)
  expect_equal(alcohol$maximo, 10000)
  expect_equal(alcohol$ahorro, 2000)
  expect_equal(alcohol$mas_baratos, "La Rebaja / Locatel")
})

test_that("si todos los comercios cobran lo mismo el ahorro es cero", {
  p <- data.frame(id_comparable = 1, producto = "X",
                  comercio = c("A", "B"), precio = c(500, 500), stringsAsFactors = FALSE)
  a <- ahorro_por_producto(p)
  expect_equal(a$ahorro, 0)
  expect_equal(a$ahorro_pct, 0)
})

test_that("detecta subidas, bajadas, productos nuevos y no observados", {
  d <- data.frame(
    precio_anterior = c(1000, 1000, 1000, NA,   1000, NA),
    precio_actual   = c(1100,  900, 1000, 500,  NA,   NA),
    en_anterior     = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    en_actual       = c(TRUE, TRUE, TRUE, TRUE,  FALSE, TRUE))
  r <- clasificar_cambios(d)
  expect_equal(r$tipo, c("subió", "bajó", "igual", "nuevo", "no observado", "sin comparación"))
  expect_equal(r$cambio_cop[1:3], c(100, -100, 0))
  expect_equal(r$cambio_pct[1:2], c(10, -10))
})

test_that("la canasta no se calcula en un comercio al que le falta un producto", {
  r <- calcular_canasta(precios_canasta_prueba(), c("1" = 1, "2" = 1),
                        nombres = c("1" = "Alcohol", "2" = "Gasa"))
  pc <- r$por_comercio
  rebaja <- pc[pc$comercio == "La Rebaja", ]
  expect_false(rebaja$completo)
  expect_true(is.na(rebaja$total))
  expect_match(rebaja$faltan, "Gasa")
  expect_equal(pc$total[pc$comercio == "Farmatodo"], 15000)
  expect_equal(pc$total[pc$comercio == "Locatel"], 14000)
})

test_that("el costo mínimo compra cada producto donde es más barato y calcula el ahorro", {
  r <- calcular_canasta(precios_canasta_prueba(), c("1" = 2, "2" = 1))
  # Alcohol x2 a 8000 (La Rebaja o Locatel) + Gasa x1 a 5000 (Farmatodo)
  expect_equal(r$minimo, 21000)
  # Mejor comercio único completo: Locatel = 2*8000 + 6000 = 22000
  expect_equal(r$mejor_unico, 22000)
  expect_equal(r$ahorro, 1000)
})

test_that("si ningún comercio tiene un producto, el mínimo no se calcula", {
  p <- precios_canasta_prueba()[1:3, ]   # solo alcohol
  r <- calcular_canasta(p, c("1" = 1, "2" = 1))
  expect_true(is.na(r$minimo))
  expect_true(is.na(r$ahorro))
})

test_that("el texto de búsqueda se limpia y nunca entra al SQL", {
  malo <- "alcohol'; DROP TABLE anuncios;--"
  expect_equal(limpiar_busqueda(malo), "alcohol DROP TABLE anuncios--")
  expect_equal(nchar(limpiar_busqueda(strrep("a", 200))), 60)
  fl <- construir_filtros(list(busqueda = malo, comercios = c("Locatel", "x' OR '1'='1")))
  expect_false(grepl("DROP", fl$where, ignore.case = TRUE))
  expect_false(grepl("OR '1'", fl$where, fixed = TRUE))
  expect_true(grepl("?", fl$where, fixed = TRUE))
  expect_true("x' OR '1'='1" %in% unlist(fl$params))   # viaja como parámetro
})

test_that("las vistas calculan el último precio y los cambios sobre una base temporal", {
  con <- con_temporal()
  persistir_ejecucion(con, "Locatel", "locatel_a",
    datos_prueba(precios = c(1000, 2000), ts = "2026-11-01T10:00:00-05:00", id_ejecucion = "locatel_a"))
  persistir_ejecucion(con, "Locatel", "locatel_b",
    datos_prueba(precios = c(1100, 2000), ts = "2026-11-05T10:00:00-05:00", id_ejecucion = "locatel_b"))
  DBI::dbExecute(con, "UPDATE ejecuciones SET estado = 'completa'")
  migrar_esquema(con)
  ult <- DBI::dbGetQuery(con, "SELECT sku, precio FROM v_ultimo_precio ORDER BY sku")
  expect_equal(ult$precio, c(1100, 2000))
  cam <- DBI::dbGetQuery(con, "SELECT sku, tipo FROM v_cambios_precio ORDER BY sku")
  expect_equal(cam$tipo, c("subió", "igual"))
})
