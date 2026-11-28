test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  con <- base_temporal(); on.exit(DBI::dbDisconnect(con))
  datos <- list(locatel = datos_comercio("locatel", F1, 40000),
                farmatodo = datos_comercio("farmatodo", F1, 41000),
                colsubsidio = datos_comercio("colsubsidio", F1, 42000))
  cargar_ejecucion(con, "E1", datos)
  n1 <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n
  cargar_ejecucion(con, "E1", datos)                      # reproceso
  n2 <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n
  expect_equal(n1, 6)
  expect_equal(n2, n1)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM ejecuciones")$n, 3)
})

test_that("calcula el ahorro y lista todos los comercios empatados en el mínimo", {
  con <- base_temporal(); on.exit(DBI::dbDisconnect(con))
  cargar_ejecucion(con, "E1", list(
    locatel = datos_comercio("locatel", F1, 40000),
    farmatodo = datos_comercio("farmatodo", F1, 40000),
    colsubsidio = datos_comercio("colsubsidio", F1, 45000)))
  a <- ahorro_por_producto(con, "E1")
  opti <- a[a$id_producto == "SV-300653610800", ]
  expect_equal(opti$precio_min, 40000)
  expect_equal(opti$ahorro_cop, 5000)
  expect_equal(opti$ahorro_pct, 11.1)
  expect_equal(opti$n_empatados, 2)
  expect_equal(opti$comercio_mas_barato, "farmatodo, locatel")
})

test_that("detecta los cambios de precio del mismo anuncio entre ejecuciones", {
  con <- base_temporal(); on.exit(DBI::dbDisconnect(con))
  cargar_ejecucion(con, "E1", list(
    locatel = datos_comercio("locatel", F1, 40000),
    farmatodo = datos_comercio("farmatodo", F1, 41000),
    colsubsidio = datos_comercio("colsubsidio", F1, 42000)))
  cargar_ejecucion(con, "E2", list(
    locatel = datos_comercio("locatel", F2, 44000),               # sube 10 %
    farmatodo = datos_comercio("farmatodo", F2, 41000),           # igual
    colsubsidio = datos_comercio("colsubsidio", F2, 39900)))      # baja
  ce <- cambios_entre(con, "E1", "E2")
  expect_equal(nrow(ce$cambios), 2)
  sube <- ce$cambios[ce$cambios$comercio == "Locatel", ]
  expect_equal(sube$direccion, "subió")
  expect_equal(sube$cambio_cop, 4000)
  expect_equal(sube$cambio_pct, 10)
  v <- DBI::dbGetQuery(con, "SELECT direccion, COUNT(*) n FROM v_cambios_precio
                              WHERE id_ejecucion = 'E2' GROUP BY direccion")
  expect_equal(v$n[v$direccion == "bajó"], 1)
})

test_that("la canasta no se calcula en un comercio al que le falta un producto", {
  con <- base_temporal(); on.exit(DBI::dbDisconnect(con))
  cargar_ejecucion(con, "E1", list(
    locatel = datos_comercio("locatel", F1, 40000, p_renu = 25000),
    farmatodo = datos_comercio("farmatodo", F1, 41000, p_renu = 24000),
    colsubsidio = datos_comercio("colsubsidio", F1, 42000, renu_disponible = 0L)))  # agotado
  items <- data.frame(id_producto = c("SV-300653610800", "SV-310119033227"), cantidad = c(2, 1))
  r <- canasta(con, "E1", items)
  col <- r$por_comercio[r$por_comercio$comercio == "colsubsidio", ]
  expect_true(is.na(col$total))
  expect_match(col$faltantes, "ReNu")
  expect_equal(r$por_comercio$total[r$por_comercio$comercio == "locatel"], 2 * 40000 + 25000)
  expect_equal(r$costo_minimo, 2 * 40000 + 24000)          # cada producto donde es más barato
  expect_equal(r$ahorro, (2 * 40000 + 25000) - (2 * 40000 + 24000))
})
