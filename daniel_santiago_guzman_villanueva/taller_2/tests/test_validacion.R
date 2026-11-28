test_that("la validación rechaza precios inválidos, URL y fecha ausentes y duplicados", {
  d <- dplyr::bind_rows(
    anuncio_prueba("locatel", "ok",   "1", OPTI, 40000, F1),
    anuncio_prueba("locatel", "cero", "2", OPTI, 0,     F1),
    anuncio_prueba("locatel", "sinp", "3", OPTI, NA,    F1, disponible = 1L),
    anuncio_prueba("locatel", "agot", "4", OPTI, NA,    F1, disponible = 0L),
    anuncio_prueba("locatel", "url",  "5", OPTI, 40000, F1, url = NA),
    anuncio_prueba("locatel", "fec",  "6", OPTI, 40000, "11/10/2026"),
    anuncio_prueba("locatel", "ok",   "1", OPTI, 40000, F1)            # duplicado
  )
  v <- validar_observaciones(d, "E1")
  # el agotado sin precio es válido: el dato ausente queda NULL
  expect_equal(sort(v$validas$sku), c("agot", "ok"))
  expect_setequal(v$rechazadas$regla,
                  c("precio_positivo", "precio_presente_disponible", "url_presente",
                    "fecha_presente", "sin_duplicados"))
})

test_that("las rechazadas no entran a observaciones y quedan registradas", {
  con <- base_temporal(); on.exit(DBI::dbDisconnect(con))
  d <- dplyr::bind_rows(datos_comercio("locatel", F1, 40000),
                        anuncio_prueba("locatel", "malo", "9", OPTI, 0, F1))
  cargar_comercio(con, d, "E1", "locatel")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n, 2)
  r <- DBI::dbGetQuery(con, "SELECT sku, regla FROM observaciones_rechazadas")
  expect_equal(r$sku, "malo")
  expect_equal(r$regla, "precio_positivo")
})

test_that("si falta un producto comparable la ejecución del comercio queda parcial", {
  con <- base_temporal(); on.exit(DBI::dbDisconnect(con))
  cargar_ejecucion(con, "E1", list(
    locatel = datos_comercio("locatel", F1, 40000),
    farmatodo = datos_comercio("farmatodo", F1, 41000),
    colsubsidio = datos_comercio("colsubsidio", F1, 42000)))
  fila <- cargar_comercio(con, datos_comercio("colsubsidio", F2, 42000, con_renu = FALSE),
                          "E2", "colsubsidio", total = 1L)
  expect_equal(fila$estado, "parcial")
  expect_match(fila$detalle, "Comparables no observados")
})
