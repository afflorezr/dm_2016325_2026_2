# Pruebas de extracción, validación e inserción (Módulos 1 y 7)

test_that("convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("$1.250.000"), 1250000)
  expect_equal(limpiar_precio(c("$ 5.600", "$ 7.000")), c(5600, 7000))
  expect_equal(limpiar_precio("$ 1.500,50"), 1500.5)
})

test_that("un precio sin dígitos queda ausente (NA), no se inventa", {
  expect_true(is.na(limpiar_precio("")))
  expect_true(is.na(limpiar_precio(NA)))
  expect_true(is.na(limpiar_precio("Agotado")))
})

test_that("normaliza las unidades de contenido (sobre -> unidad)", {
  con <- con_temporal()
  id_com <- obtener_id_comercio(con, "Locatel")
  DBI::dbExecute(con, "INSERT INTO anuncios
    (id_comercio, sku, nombre_original, contenido_valor, contenido_unidad)
    VALUES (?, ?, ?, ?, ?)",
    params = list(rep(id_com, 3), c("1", "2", "3"), c("Gasa", "Alcohol", "Cinta"),
                  c(12, 700, 5), c("sobre", "mL", "m")))
  migrar_esquema(con)
  r <- DBI::dbGetQuery(con, "SELECT sku, contenido_total, unidad_normalizada
                             FROM anuncios ORDER BY sku")
  expect_equal(r$unidad_normalizada, c("unidad", "mL", "m"))
  expect_equal(r$contenido_total, c(12, 700, 5))
})

test_that("la validación rechaza precios no positivos, sin URL y duplicados", {
  df <- datos_prueba(skus = c("A", "B", "C", "A"), precios = c(1000, 0, 500, 1000))
  df$url[3] <- NA
  v <- validar_observaciones(df)
  expect_equal(v$validas$sku, "A")
  expect_equal(nrow(v$rechazadas), 3)
  expect_true(all(c("Precio menor o igual a cero", "URL ausente",
                    "Duplicado en la misma ejecución") %in% v$rechazadas$motivo))
})

test_that("un precio ausente solo se acepta si el sitio marca el producto agotado", {
  df <- datos_prueba(skus = c("A", "B"), precios = c(NA, NA))
  df$disponible <- c(0L, 1L)
  v <- validar_observaciones(df)
  expect_equal(v$validas$sku, "A")
  expect_equal(v$rechazadas$sku, "B")
})

test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  con <- con_temporal()
  df <- datos_prueba()
  r1 <- persistir_ejecucion(con, "Locatel", "locatel_prueba", df)
  n1 <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones")$n
  r2 <- persistir_ejecucion(con, "Locatel", "locatel_prueba", df)
  n2 <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones")$n
  expect_equal(n1, 2)
  expect_equal(n2, 2)
  expect_equal(r1$observaciones_nuevas, 2)
  expect_equal(r2$observaciones_nuevas, 0)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM ejecuciones")$n, 1)
})

test_that("las observaciones rechazadas quedan registradas con su motivo", {
  con <- con_temporal()
  df <- datos_prueba(skus = c("A", "B"), precios = c(1000, -5))
  r <- persistir_ejecucion(con, "Locatel", "locatel_prueba", df)
  rech <- DBI::dbGetQuery(con, "SELECT sku, motivo FROM rechazadas")
  expect_equal(r$rechazados, 1)
  expect_equal(rech$sku, "B")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones")$n, 1)
})

test_that("detecta los comparables ausentes (por EAN y por nombre)", {
  esp <- tibble::tibble(id_comparable = 1:2, ean = c("111", "222"),
                        patron_farmatodo = c("alcohol", "gasa"))
  df <- datos_prueba(); df$ean <- c("111", "999")
  expect_equal(comparables_faltantes(df, "Locatel", esp), 2L)
  df2 <- datos_prueba(comercio = "Farmatodo"); df2$nombre_original <- c("Alcohol MK", "Venda")
  expect_equal(comparables_faltantes(df2, "Farmatodo", esp), 2L)
})
