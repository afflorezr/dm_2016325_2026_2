# Consultas de db.R sobre la base de prueba (respuestas calculadas a mano en helper-fixture.R)
con <- crear_base_prueba()

test_that("filtrar_precios: ultimo precio, ejecucion y comparables", {
  expect_equal(nrow(filtrar_precios(con)), 11)                          # 11 anuncios, un ultimo precio cada uno
  expect_equal(nrow(filtrar_precios(con, list(corrida = A))), 10)
  expect_equal(nrow(filtrar_precios(con, list(corrida = B))), 9)
  expect_equal(nrow(filtrar_precios(con, list(solo_comparables = TRUE))), 9)   # anuncios 1 a 9
})

test_that("filtrar_precios: filtros combinados", {
  r <- filtrar_precios(con, list(comercios = COM_EXITO, solo_promociones = TRUE))
  expect_equal(nrow(r), 1); expect_equal(r$precio, 27000)
  expect_equal(nrow(filtrar_precios(con, list(precio = c(11000, 26000)))), 4)  # 25000, 20000, 12000, 20000
  expect_equal(nrow(filtrar_precios(con, list(texto = "alfa"))), 3)
  expect_equal(nrow(filtrar_precios(con, list(texto = "alfa 100"))), 3)        # dos palabras: AND
  expect_equal(nrow(filtrar_precios(con, list(texto = "zzz"))), 0)
  expect_equal(nrow(filtrar_precios(con, list(fechas = c("2026-01-01", "2026-01-31")))), 10)
})

test_that("indicadores: resumen, mediana y promociones calculados en SQL", {
  ind <- indicadores(con)
  expect_equal(ind$resumen$productos, 11)
  expect_equal(ind$resumen$productos_en_promocion, 1)
  expect_equal(ind$resumen$pct_promocion, 9.1)
  expect_equal(ind$resumen$mediana_precio, median(c(5000, 5000, 10000, 10000, 12000, 20000, 20000, 25000, 27000, 30000, 30000)))
  p <- promociones_por_comercio(con)
  ex <- p[p$comercio == COM_EXITO, ]
  expect_equal(c(ex$productos, ex$en_promocion, ex$pct_promocion, ex$descuento_mediano_pct), c(4, 1, 25, 10))
  expect_true(is.na(p$descuento_mediano_pct[p$comercio == "Farmatodo"]))
})

test_that("precio_unitario agrupa por comercio y unidad", {
  pu <- precio_unitario(con)
  ex <- pu[pu$comercio == COM_EXITO & pu$medida == "ml", ]
  expect_equal(ex$n, 3); expect_equal(ex$mediana, median(c(100, 125, 67.5)))
})

test_that("cambios_entre detecta sube, baja, igual, nuevo y no observado", {
  r <- cambios_entre(con)                                   # por defecto: dos ultimas completas (A y B; C es parcial)
  expect_equal(as.list(table(r$situacion))[c("sube", "baja", "igual", "nuevo", "no_observado", "agotado_segun_sitio")],
               list(sube = 1L, baja = 1L, igual = 6L, nuevo = 1L, no_observado = 1L, agotado_segun_sitio = 1L))
  s <- r[r$situacion == "sube", ]
  expect_equal(c(s$variacion_cop, s$variacion_pct), c(5000, 25))
  expect_equal(sum(r$supera_umbral), 2)                     # 25 % y -10 % con umbral 10
  expect_equal(sum(cambios_entre(con, A, B, umbral = 20)$supera_umbral), 1)
  expect_error(cambios_entre(con, A, "99999999999999"), class = "error_validacion")
})

test_that("ahorro maximo entre comercios, con empates", {
  a <- indicadores(con)$ahorro_maximo                       # corrida B: p2 cuesta 25000, 20000 y 20000
  expect_equal(c(a$ahorro_cop, a$ahorro_pct), c(5000, 20))
  expect_equal(c(a$comercio_caro, a$comercio_barato), c(COM_EXITO, "Farmatodo"))   # el empate se resuelve por orden alfabetico
  expect_equal(indicadores(con, list(corrida = A))$ahorro_maximo$ahorro_cop, 2000)  # en A solo p1 difiere
})

test_that("canasta: ahorro 0 cuando el mejor comercio ya es el minimo (empates)", {
  r <- canasta(con, data.frame(id_producto = 1:2, cantidad = c(2, 1)))   # corrida B
  expect_equal(r$totales$costo, c(45000, 40000, 44000))
  expect_equal(r$resumen$costo_minimo_combinado, 40000)
  expect_equal(r$resumen$ahorro_cop, 0)
})

test_that("canasta incompleta: un comercio sin todos los productos no tiene total", {
  r <- canasta(con, data.frame(id_producto = 1:3, cantidad = c(1, 1, 1)))
  expect_equal(r$totales$completa, c(1, 0, 1))
  expect_true(is.na(r$totales$costo[r$totales$comercio == "Farmatodo"]))
  expect_match(r$totales$faltantes[r$totales$comercio == "Farmatodo"], "Gamma")
  expect_equal(r$resumen$costo_minimo_combinado, 57000)
  expect_equal(c(r$resumen$ahorro_cop, r$resumen$ahorro_pct), c(5000, 8.1))
  expect_match(r$advertencia, "env")
})

test_that("canasta rechaza entradas invalidas", {
  expect_error(canasta(con, data.frame(id_producto = 1, cantidad = 0)), class = "error_validacion")
  expect_error(canasta(con, data.frame(id_producto = 1, cantidad = 2.5)), class = "error_validacion")
  expect_error(canasta(con, data.frame(id_producto = 99, cantidad = 1)), class = "error_validacion")
  expect_error(canasta(con, data.frame(id_producto = c(1, 1), cantidad = c(1, 1))), class = "error_validacion")
})

test_that("serie_precio devuelve todas las observaciones del producto", {
  expect_equal(nrow(serie_precio(con, 3)), 5)               # Exito 2, Farmatodo 1, La Rebaja 2
})

DBI::dbDisconnect(con)
