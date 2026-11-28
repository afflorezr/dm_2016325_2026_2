# Pruebas automáticas (testthat). Ejecutar desde taller_02/:  Rscript -e 'testthat::test_dir("tests")'
# Usan datos pequeños y bases temporales: nunca la base de la entrega ni los sitios.

test_that("1. convierte el precio en texto a número", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("$12.900,50"), 12900.5)
  expect_equal(limpiar_precio("1.250.000"), 1250000)
  expect_equal(limpiar_precio("12,900"), 12900)
  expect_equal(limpiar_precio(18900), 18900)
  expect_true(is.na(limpiar_precio("sin precio")))
  expect_true(is.na(limpiar_precio(NULL)))
})

test_that("2. normaliza el contenido y la unidad (mL, g o unidad)", {
  x <- contenido_desde_nombre(norm_txt(c("Naproxeno Caja X 30 Tabletas", "Jarabe Frasco X 120 Ml",
                                         "Gel Tubo X 50 G", "Suspension 100 mg en 5 ml x 60 ml")))
  expect_equal(x$contenido_valor, c(30, 120, 50, 60))
  expect_equal(x$contenido_unidad, c("un", "ml", "g", "ml"))
  # el producto_id no depende del lote (antes "24un" o "24.0un" según los demás valores)
  expect_equal(num_txt(24), "24.0")
  expect_equal(num_txt(c(24, 2.5)), c("24.0", "2.5"))
  con <- crear_base_prueba(); on.exit(dbDisconnect(con))
  u <- dbGetQuery(con, "SELECT producto_id, contenido_total, unidad_norm FROM productos ORDER BY producto_id")
  expect_equal(u$unidad_norm, c("unidad", "mL"))
  expect_equal(u$contenido_total, c(10, 100))
})

test_that("3. calcula el ahorro entre comercios y reporta los empates", {
  con <- crear_base_prueba(); on.exit(dbDisconnect(con))
  e <- "20260201T100000"
  agregar_obs(con, "larebaja", "a1", "P1", e, 10000)
  agregar_obs(con, "cafam",    "b1", "P1", e, 10000)   # empate en el mínimo
  agregar_obs(con, "locatel",  "c1", "P1", e, 12500)
  a <- ahorro_por_producto(con, e)
  expect_equal(nrow(a), 1)
  expect_equal(a$ahorro_cop, 2500)
  expect_equal(a$ahorro_pct, 20)
  expect_equal(a$n_empatados, 2)
  expect_setequal(strsplit(a$comercios_mas_baratos, ", ")[[1]], c("La Rebaja", "Droguerías Cafam"))
})

test_that("4. insertar dos veces la misma ejecución no duplica observaciones", {
  con <- crear_base_prueba(); on.exit(dbDisconnect(con))
  ctx <- nuevo_contexto("offline", "20261105T235015")
  datos <- lote_scraper(3)
  res <- list(datos = datos, total_sitio = 3L, completo = TRUE, notas = character())
  val <- validar_observaciones(datos)
  r6 <- validar_canasta_referencia(character(), character())
  i1 <- insertar_comercio(con, ctx, "cafam", val, res, r6, ahora_iso(), existia_ejecucion = FALSE)
  i2 <- insertar_comercio(con, ctx, "cafam", val, res, r6, ahora_iso(), existia_ejecucion = TRUE)
  expect_equal(i1$insertadas, 3L)
  expect_equal(i2$insertadas, 0L)
  expect_equal(i2$nuevos, 0L)
  n <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones WHERE ejecucion_id = '20261105T235015'")$n
  expect_equal(n, 3)
  # la restricción de unicidad también lo impide a nivel de la base
  expect_error(dbExecute(con, "INSERT INTO observaciones (ejecucion_id, comercio, anuncio_id, fecha_hora, precio)
                               SELECT ejecucion_id, comercio, anuncio_id, fecha_hora || 'x', precio
                               FROM observaciones LIMIT 1"), "UNIQUE")
})

test_that("5. detecta los cambios de precio del mismo anuncio entre ejecuciones", {
  con <- crear_base_prueba(); on.exit(dbDisconnect(con))
  agregar_obs(con, "cafam", "b1", "P1", "20260101T100000", 10000)
  agregar_obs(con, "cafam", "b1", "P1", "20260201T100000", 11000)   # subió 10 %
  agregar_obs(con, "cafam", "b2", "P2", "20260101T100000", 5000)
  agregar_obs(con, "cafam", "b2", "P2", "20260201T100000", 5000)    # igual
  agregar_obs(con, "cafam", "b3", "P2", "20260201T100000", 7000)    # nuevo
  x <- comparar_ejecuciones(con, "20260101T100000", "20260201T100000")
  expect_equal(x$tipo[x$producto == "Anuncio b1"], "subió")
  expect_equal(x$cambio_cop[x$producto == "Anuncio b1"], 1000)
  expect_equal(x$cambio_pct[x$producto == "Anuncio b1"], 10)
  expect_equal(x$tipo[x$producto == "Anuncio b2"], "sin cambio")
  expect_equal(x$tipo[x$producto == "Anuncio b3"], "nuevo")
  cp <- comparar_con_previa(con, "cafam", "20260201T100000")
  expect_equal(cp$cambios, 1L)
  v <- dbGetQuery(con, "SELECT direccion FROM v_cambios_precio WHERE direccion <> 'igual'")
  expect_equal(v$direccion, "subió")
})

test_that("6. la canasta no se calcula en un comercio al que le falta un producto", {
  con <- crear_base_prueba(); on.exit(dbDisconnect(con))
  e <- "20260201T100000"
  agregar_obs(con, "larebaja", "a1", "P1", e, 10000); agregar_obs(con, "larebaja", "a2", "P2", e, 8000)
  agregar_obs(con, "cafam",    "b1", "P1", e,  9000); agregar_obs(con, "cafam",    "b2", "P2", e, 8500)
  agregar_obs(con, "locatel",  "c1", "P1", e,  9500)                                  # sin P2
  r <- canasta(con, e, data.frame(producto_id = c("P1", "P2"), cantidad = c(2, 1)))
  pc <- r$por_comercio
  expect_true(is.na(pc$total[pc$comercio == "locatel"]))
  expect_equal(pc$completo[pc$comercio == "locatel"], 0)
  expect_equal(pc$total[pc$comercio == "larebaja"], 2 * 10000 + 8000)
  expect_equal(pc$total[pc$comercio == "cafam"], 2 * 9000 + 8500)
  expect_equal(r$optima, 2 * 9000 + 8000)          # cada producto donde es más barato
})

test_that("7. la validación rechaza precios no válidos, campos faltantes y duplicados", {
  d <- lote_scraper(5)
  d$precio[1] <- NA; d$precio[2] <- 0; d$url[3] <- NA
  d <- rbind(d, d[5, ])                             # duplicado en la misma ejecución
  v <- validar_observaciones(d)
  expect_equal(nrow(v$validas), 2)                  # filas 4 y 5 (la copia de la 5 se rechaza)
  expect_setequal(unique(v$rechazadas$regla), c("precio_positivo", "campos_presentes", "sin_duplicados"))
  expect_equal(v$resumen$resultado[v$resumen$regla == "moneda_cop"], "cumple")
  r6 <- validar_canasta_referencia(c("P1"), c("P1", "P2"))
  expect_equal(r6$resultado, "no cumple"); expect_equal(r6$fallas, 1)
})

test_that("8. el texto del usuario se valida y nunca entra al SQL (consultas parametrizadas)", {
  expect_false(validar_texto("x'; DROP TABLE anuncios;--")$ok)
  expect_false(validar_texto(strrep("a", 61))$ok)
  expect_true(validar_texto("acetaminofén 500 mg")$ok)
  w <- construir_where(list(texto = "naproxeno", comercios = c("cafam", "locatel"), ejecucion = "E1"))
  expect_false(grepl("naproxeno|cafam|E1", w$sql))
  expect_true(all(c("%naproxeno%", "cafam", "locatel", "E1") %in% unlist(w$params)))
})
