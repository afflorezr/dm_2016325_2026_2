fila <- function(...) {
  base <- data.frame(comercio_id = "exito", ejecucion_id = "E1", fecha_hora_consulta = "2026-11-01T10:00:00-05:00",
                     url_fuente = "https://www.exito.com/api", sku_comercio = "1", nombre_original = "Crema",
                     precio = 5000, disponible = 1L, stringsAsFactors = FALSE)
  utils::modifyList(base, list(...))
}

test_that("la validación rechaza precios inválidos, campos faltantes y duplicados", {
  d <- rbind(fila(sku_comercio = "ok"),
             fila(sku_comercio = "negativo", precio = -10),
             fila(sku_comercio = "sin_url", url_fuente = NA_character_),
             fila(sku_comercio = "sin_fecha", fecha_hora_consulta = NA_character_),
             fila(sku_comercio = "sin_precio", precio = NA_real_),                       # disponible pero sin precio
             fila(sku_comercio = "agotado", precio = NA_real_, disponible = 0L),         # válida: agotado sin precio
             fila(sku_comercio = "ok"))                                                  # duplicada
  v <- validar_observaciones(d)
  expect_equal(v$validas$sku_comercio, c("ok", "agotado"))
  expect_equal(nrow(v$rechazadas), 5)
  motivo <- stats::setNames(v$rechazadas$motivo, v$rechazadas$sku_comercio)
  expect_match(motivo[["negativo"]], "V2"); expect_match(motivo[["sin_url"]], "V4")
  expect_match(motivo[["sin_fecha"]], "V4"); expect_match(motivo[["sin_precio"]], "V3"); expect_match(motivo[["ok"]], "V6")
})

test_that("un precio no numérico se rechaza y no se reemplaza", {
  d <- rbind(fila(sku_comercio = "a"), fila(sku_comercio = "b"))
  d$precio <- c("5000", "consultar")
  v <- validar_observaciones(d)
  expect_equal(v$validas$precio, 5000)
  expect_match(v$rechazadas$motivo, "V1")
})

test_that("avisa cuando falta un producto comparable de referencia", {
  ref <- data.frame(producto_id = c("G1", "G2"), producto = c("Crema A", "Enjuague B"), sku_comercio = c("1", "99"))
  v <- validar_observaciones(fila(), ref)
  expect_equal(v$faltan_referencia, "Enjuague B")
  expect_equal(nrow(v$validas), 1)                  # regla del lote: no rechaza filas
})
