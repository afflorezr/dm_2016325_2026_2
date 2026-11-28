library(testthat)

test_that("los formatos usan pesos colombianos y los comercios conservan su color", {
  expect_equal(fmt_cop(c(12900, 1299900, NA)), c("$12.900", "$1.299.900", "—"))
  expect_equal(fmt_pct(12.34), "12,3 %")
  expect_equal(fmt_fecha("2026-11-09T12:58:18-05:00"), "09/11/2026 12:58")
  expect_equal(color_comercio(c("jumbo", "jumbo")), rep(unname(COLORES_COMERCIO["jumbo"]), 2))
  expect_equal(length(unique(color_comercio(c("exito", "jumbo", "olimpica")))), 3)
  expect_equal(nombre_comercio("olimpica"), "Olímpica")
})

test_that("la mediana y los cuantiles calculados con SQL coinciden con los de R", {
  precios <- c(1000, 900, 1500, 2000, 1800, 700)
  ruta <- crear_base_canasta(data.frame(comercio = rep(c("exito", "jumbo"), 3),
                                        producto_id = rep(c("P01", "P02"), each = 3), precio_cop = precios))
  m <- db_ind_mediana(list(), ruta, "global")
  expect_equal(m$mediana_cop, median(precios))                 # n par: promedio de los dos centrales
  q <- db_cuantiles_precio(list(), ruta)
  x <- sort(precios[c(1, 3, 5)])                               # precios de "exito" en la base de prueba
  n <- length(x)
  expect_equal(q$mediana[q$comercio == "exito"], x[as.integer(0.5 * (n - 1)) + 1])
  expect_equal(q$p25[q$comercio == "exito"], x[as.integer(0.25 * (n - 1)) + 1])
})

test_that("una ejecución parcial más reciente no reemplaza a la última completa", {
  ruta <- crear_base_canasta(data.frame(comercio = c("exito", "jumbo"), producto_id = "P01", precio_cop = c(1000, 1100)))
  con <- dbConnect(SQLite(), ruta)
  dbExecute(con, "INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, n_registros, estado, motivo)
                  VALUES ('R2', 1, '2026-11-08T10:00:00-05:00', 50, 'parcial', 'interrumpida')")
  dbDisconnect(con)
  u <- db_consultar("SELECT comercio, ejecucion_id FROM v_ultima_ejecucion ORDER BY comercio", ruta = ruta)
  expect_equal(u$ejecucion_id, c("R1", "R1"))
  expect_equal(db_ultima_ejecucion(ruta), "R1")
  # pero el indicador de "última ejecución" sí informa el intento parcial, con su motivo
  i <- db_ind_ultima_ejecucion(ruta)
  expect_equal(i$estado[i$comercio == "exito"], "parcial"); expect_equal(i$motivo[i$comercio == "exito"], "interrumpida")
})

test_that("una ejecución interrumpida de raw/ no se usa en el modo sin conexión", {
  completo <- data.frame(comercio = c("exito", "jumbo", "olimpica"), total_sitio = c(1103, 1380, 1189), n_productos = c(1102, 1380, 1189))
  expect_true(resumen_es_completo(completo))
  expect_false(resumen_es_completo(data.frame(comercio = "exito", total_sitio = 3955, n_productos = 50)))
  expect_false(resumen_es_completo(completo[1:2, ]))           # falta un comercio
})

test_that("los filtros viajan como parámetros y las promociones y búsquedas se combinan", {
  f <- filtros_sql(comercios = c("exito", "jumbo"), solo_promocion = TRUE, busqueda = "esmalte 100%", precio_max = 5000)
  expect_equal(f$fuente, "v_ultimo_precio")
  expect_equal(length(f$par), 5)                                # 2 comercios + precio + 2 palabras
  expect_true(any(vapply(f$par, function(p) identical(p, "%100\\%%"), TRUE)))   # el % del usuario es texto literal
  expect_false(grepl("esmalte|100", f$donde))                   # el texto del usuario nunca entra al SQL
  expect_equal(filtros_sql(ejecucion = "R1")$fuente, "v_precios")
  err <- tryCatch(filtros_sql(busqueda = "a;b"), error = function(e) e)
  expect_s3_class(err, "entrada_invalida")
})

test_that("la tabla descargable y el enlace al anuncio no permiten HTML ni esquemas peligrosos", {
  x <- data.frame(comercio = "jumbo", nombre = "Esmalte", marca = "M", presentacion = "13 ml", precio_cop = 5000,
                  precio_unitario = 384.6, unidad_norm = "mL", en_promocion = 0L, estado_disponibilidad = "agotado",
                  fecha_hora_consulta = "2026-11-09T12:58:18-05:00",
                  url = c("https://j.test/a'onmouseover='x", "javascript:alert(1)"), stringsAsFactors = FALSE)
  x <- rbind(x, x[1, ]); x$url[2] <- "javascript:alert(1)"; x <- x[1:2, ]
  t <- tabla_productos(x)
  expect_false(grepl("'onmouseover='", t$Enlace[1], fixed = TRUE))   # la comilla simple queda escapada
  expect_equal(t$Enlace[2], "")                                     # javascript: no se convierte en enlace
  expect_equal(t$Disponibilidad[1], "Agotado")
  expect_equal(tabla_productos(x, para_csv = TRUE)$Enlace[2], "javascript:alert(1)")   # el CSV conserva el dato original
})

test_that("el ahorro máximo y el comercio más barato salen de la misma ejecución", {
  ruta <- crear_base_canasta(data.frame(comercio = c("exito", "jumbo", "olimpica", "exito", "olimpica"),
                                        producto_id = c("P01", "P01", "P01", "P02", "P02"),
                                        precio_cop = c(1000, 1000, 1500, 2000, 1800)))
  a <- db_ind_ahorro_max("R1", ruta)
  expect_equal(a$producto_id, "P01"); expect_equal(a$ahorro_cop, 500)
  b <- db_ind_mas_barato("R1", ruta)                            # P01: empate éxito-jumbo; P02: olímpica
  expect_equal(b$productos_mas_barato[b$comercio == "exito"], 1)
  expect_equal(b$productos_mas_barato[b$comercio == "jumbo"], 1)
  expect_equal(b$productos_mas_barato[b$comercio == "olimpica"], 1)
})

test_that("promoción, disponibilidad y cobertura de comparables se calculan por comercio", {
  ruta <- crear_base_canasta(data.frame(comercio = c("exito", "jumbo", "olimpica", "exito", "olimpica"),
                                        producto_id = c("P01", "P01", "P01", "P02", "P02"),
                                        precio_cop = c(1000, 900, 1500, 2000, 1800)))
  p <- db_promocion_por_comercio(list(), ruta)
  expect_equal(p$productos[p$comercio == "exito"], 2); expect_equal(sum(p$disponibles), 5)
  cob <- db_cobertura_comparables("R1", ruta)
  expect_equal(cob$n_comercios[cob$producto_id == "P01"], 3)
  expect_equal(cob$n_comercios[cob$producto_id == "P02"], 2)          # jumbo no tiene precio de P02
  expect_equal(cob$unidad_norm[cob$producto_id == "P02"], "g")
})

test_that("el detalle de la canasta trae una fila por comercio y producto, con NA donde falta el precio", {
  ruta <- crear_base_canasta(data.frame(comercio = c("exito", "jumbo", "olimpica", "exito", "olimpica"),
                                        producto_id = c("P01", "P01", "P01", "P02", "P02"),
                                        precio_cop = c(1000, 900, 1500, 2000, 1800)))
  cn <- db_canasta(data.frame(producto_id = c("P01", "P02"), cantidad = c(2, 3)), "R1", ruta)
  expect_equal(nrow(cn$detalle), 6)
  expect_true(is.na(cn$detalle$subtotal[cn$detalle$comercio == "jumbo" & cn$detalle$producto_id == "P02"]))
  expect_equal(cn$detalle$subtotal[cn$detalle$comercio == "exito" & cn$detalle$producto_id == "P02"], 6000)
})

test_that("las series de los gráficos son listas sin nombres (si no, el navegador no las dibuja)", {
  ruta <- crear_base_canasta(data.frame(comercio = c("exito", "jumbo", "olimpica", "exito", "olimpica"),
                                        producto_id = c("P01", "P01", "P01", "P02", "P02"),
                                        precio_cop = c(1000, 900, 1500, 2000, 1800)))
  cn <- db_canasta(data.frame(producto_id = c("P01", "P02"), cantidad = c(2, 1)), "R1", ruta)
  graficos <- list(grafico_canasta_total(cn$detalle, cn$por_comercio),
                   grafico_canasta_precios(cn$detalle, c(P01 = "uno", P02 = "dos")),
                   grafico_sobrecosto(db_sobrecosto("R1", ruta)), grafico_ahorro(db_ahorro_producto("R1", ruta)),
                   grafico_mas_barato(db_ind_mas_barato("R1", ruta)),
                   grafico_promocion(db_promocion_por_comercio(list(), ruta)))
  for (g in graficos) for (s in g$x$hc_opts$series) expect_null(names(s$data))
  # la canasta incompleta no dibuja barra para el comercio al que le falta un producto
  tot <- grafico_canasta_total(cn$detalle, cn$por_comercio)$x$hc_opts$series[[1]]$data
  expect_true(is.na(tot[[2]]))                                           # jumbo (orden alfabético: exito, jumbo, olimpica)
  expect_match(grafico_canasta_total(cn$detalle, cn$por_comercio)$x$hc_opts$xAxis$categories[2], "incompleta")
})

test_that("los colores salen de colores.R y cada comercio tiene el suyo", {
  expect_true(all(c("exito", "jumbo", "olimpica") %in% names(COLORES_COMERCIO)))
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", c(COLORES_COMERCIO, COLOR_PRINCIPAL, COLOR_PESTANA_ACTIVA, COLOR_ENLACE))))
})
