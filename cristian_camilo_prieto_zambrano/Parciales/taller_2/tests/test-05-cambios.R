# 5. Detección de cambios de precio entre dos ejecuciones (mismo anuncio, mismo
# comercio). En Locatel, de la corrida 1 a la 2: P01 igual, P02 baja 10 %,
# P03 sube 10 %, Nutren deja de observarse, Pediasure es nuevo y Casilan pasa
# de 250 g a 500 g con el mismo SKU.

test_that("se clasifica cada tipo de cambio", {
  con <- base_prueba()
  cc <- comparar_ejecuciones(con, C1, C2, umbral_pct = 5)
  l <- cc$cambios[cc$cambios$comercio == "Locatel", ]
  tipo <- setNames(l$tipo_cambio, l$nombre)
  expect_equal(tipo[["Prowhey Net Vainilla Polvo x 434 gr"]], "subió")
  expect_equal(tipo[["Glucerna Vainilla Liquido x 237 ml"]], "bajó")
  expect_equal(tipo[["Ensure Advance Vainilla Polvo x 400 gr"]], "igual")
  expect_equal(tipo[["Pediasure Fresa Polvo x 400 gr"]], "nuevo")
  expect_equal(tipo[["Nutren Senior Vainilla x 400 gr"]], "no observado")
  expect_equal(tipo[["Casilan Polvo x 500 gr"]], "cambió la presentación")
  var <- setNames(l$variacion_pct, l$nombre)
  expect_equal(var[["Prowhey Net Vainilla Polvo x 434 gr"]], 10)
  expect_equal(var[["Glucerna Vainilla Liquido x 237 ml"]], -10)
})

test_that("un cambio de presentación no se cuenta como subida ni bajada", {
  con <- base_prueba()
  r <- comparar_ejecuciones(con, C1, C2, umbral_pct = 5)$resumen
  r <- r[r$comercio == "Locatel", ]
  expect_equal(c(r$subieron, r$bajaron, r$cambio_presentacion), c(1, 1, 1))
})

test_that("el umbral resalta solo las variaciones que lo alcanzan", {
  con <- base_prueba()
  resaltados <- function(u) {
    d <- comparar_ejecuciones(con, C1, C2, umbral_pct = u)$cambios
    sort(d$nombre[d$destacado == 1])
  }
  expect_equal(resaltados(5), sort(c("Prowhey Net Vainilla Polvo x 434 gr",
                                     "Glucerna Vainilla Liquido x 237 ml")))
  expect_length(resaltados(15), 0)
})
