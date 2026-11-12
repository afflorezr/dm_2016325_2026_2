library(testthat)

test_that("convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio(c("12.900,50", "12,5", "$1.299.900")), c(12900.5, 12.5, 1299900))
  expect_true(is.na(limpiar_precio("agotado")))
  expect_equal(limpiar_precio(3500), 3500)
})

test_that("normaliza las unidades de contenido a mL, g y unidad", {
  r <- extraer_contenido(c("Esmalte 13 ml", "Removedor 1 L", "Crema 2,5 oz", "Lima 30 gr", "Set x 3 unidades", "Sin dato"))
  expect_equal(r$contenido_unidad, c("ml", "ml", "ml", "g", "und", NA))
  expect_equal(r$contenido_valor, c(13, 1000, round(2.5 * 29.5735, 2), 30, 3, NA))
})

test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  ruta <- tempfile(fileext = ".sqlite")
  d <- limpiar_datos(datos_falsos("jumbo")); r <- resumen_falso("jumbo")
  suppressMessages({ cargar_sqlite(d, r, ruta); cargar_sqlite(d, r, ruta) })
  n <- db_consultar("SELECT COUNT(*) n FROM observaciones", ruta = ruta)$n
  expect_equal(n, nrow(d))
  expect_equal(db_consultar("SELECT COUNT(*) n FROM ejecuciones", ruta = ruta)$n, 1)
})

test_that("si un comercio falla, los demás continúan y la falla queda registrada con su motivo", {
  ruta <- tempfile(fileext = ".sqlite")
  sondeo_ok <- function(cm) list(ok = TRUE, motivo = NA_character_)
  res <- suppressMessages(suppressWarnings(actualizar_precios(
    ruta, comercios = c("exito", "jumbo"), recolector = recolector_falso, sondeo = sondeo_ok)))
  est <- setNames(res$resumen$estado, res$resumen$comercio)
  expect_equal(unname(est["exito"]), "fallida")
  expect_equal(unname(est["jumbo"]), "completa")
  expect_match(res$resumen$motivo[res$resumen$comercio == "exito"], "HTTP 500")
  expect_equal(res$resumen$recolectados[res$resumen$comercio == "jumbo"], 8)
  expect_false(res$todos_fallaron)
  # un sitio que bloquea (sondeo falla) también queda registrado sin hacer más peticiones
  Sys.sleep(1.1)                                            # el id de la ejecución tiene resolución de segundos
  res2 <- suppressMessages(actualizar_precios(ruta, comercios = "jumbo", recolector = recolector_falso,
            sondeo = function(cm) list(ok = FALSE, motivo = motivo_http(403))))
  expect_true(res2$todos_fallaron)
  expect_match(res2$resumen$motivo, "bloqueó")
})

test_that("si falla la carga de un comercio no queda nada a medias en la base", {
  ruta <- tempfile(fileext = ".sqlite")
  sondeo_ok <- function(cm) list(ok = TRUE, motivo = NA_character_)
  res <- suppressMessages(suppressWarnings(actualizar_precios(
    ruta, comercios = c("jumbo", "olimpica"), recolector = recolector_falso, sondeo = sondeo_ok)))
  expect_equal(res$resumen$estado[res$resumen$comercio == "olimpica"], "fallida")
  expect_match(res$resumen$motivo[res$resumen$comercio == "olimpica"], "se deshicieron")
  n_olim <- db_consultar("SELECT COUNT(*) n FROM observaciones o JOIN anuncios a USING (anuncio_id)
                          JOIN comercios c USING (comercio_id) WHERE c.nombre = 'olimpica'", ruta = ruta)$n
  expect_equal(n_olim, 0)                                   # lo insertado antes del error se deshizo
  expect_gt(db_consultar("SELECT COUNT(*) n FROM observaciones", ruta = ruta)$n, 0)   # jumbo sí quedó
})

test_that("el ahorro entre comercios maneja empates y precios iguales", {
  ruta <- crear_base_canasta(data.frame(
    comercio   = c("exito", "jumbo", "olimpica", "exito", "olimpica"),
    producto_id = c("P01", "P01", "P01", "P02", "P02"),
    precio_cop = c(1000, 1000, 1500, 2000, 2000)))
  a <- db_ahorro_producto("R1", ruta)
  p1 <- a[a$producto_id == "P01", ]; p2 <- a[a$producto_id == "P02", ]
  expect_equal(p1$ahorro_cop, 500)
  expect_equal(p1$comercios_mas_baratos, "exito, jumbo")    # el empate lista a todos los comercios
  expect_equal(p2$ahorro_cop, 0)                            # todos cobran lo mismo: sin ahorro
  expect_equal(p2$ahorro_pct, 0)
})

test_that("la canasta no se calcula cuando a un comercio le falta un producto", {
  ruta <- crear_base_canasta(data.frame(
    comercio   = c("exito", "jumbo", "olimpica", "exito", "olimpica"),   # jumbo NO tiene P02
    producto_id = c("P01", "P01", "P01", "P02", "P02"),
    precio_cop = c(1000, 900, 1500, 2000, 1800)))
  items <- data.frame(producto_id = c("P01", "P02"), cantidad = c(2, 1))
  cn <- db_canasta(items, "R1", ruta)
  j <- cn$por_comercio[cn$por_comercio$comercio == "jumbo", ]
  expect_true(is.na(j$total_cop))                           # nunca un total incompleto
  expect_equal(j$faltantes, "P02")
  expect_equal(cn$por_comercio$total_cop[cn$por_comercio$comercio == "exito"], 2 * 1000 + 2000)
  expect_equal(cn$total_minimo, 2 * 900 + 1800)             # P01 en jumbo, P02 en olímpica
  expect_equal(cn$mejor_un_comercio, 4000)                  # éxito 4000 vs olímpica 4800
  expect_equal(cn$ahorro_cop, 4000 - 3600)
  # si NINGÚN comercio tiene el producto, no hay total mínimo
  cn2 <- db_canasta(data.frame(producto_id = "P99", cantidad = 1), "R1", ruta)
  expect_true(is.na(cn2$total_minimo)); expect_true(is.na(cn2$ahorro_cop))
})

test_that("un producto repetido en dos categorías del mismo comercio no se cuenta como rechazo", {
  ruta <- tempfile(fileext = ".sqlite")
  rec <- function(comercio, ejecucion) {
    d <- datos_falsos(comercio, ejecucion, ts = inicio_iso(ejecucion))
    list(datos = rbind(d, d[1:3, ]), resumen = resumen_falso(comercio, ejecucion))   # 3 anuncios repetidos
  }
  res <- suppressMessages(actualizar_precios(ruta, comercios = "jumbo", recolector = rec,
                                             sondeo = function(cm) list(ok = TRUE, motivo = NA_character_)))
  expect_equal(res$resumen$rechazados, 0)
  expect_equal(res$resumen$recolectados, 8)
})
