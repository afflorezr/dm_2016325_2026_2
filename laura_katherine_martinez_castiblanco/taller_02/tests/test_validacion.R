# Pruebas de la lógica pura (validacion.R)

test_that("convierte el precio en texto a número (formato colombiano)", {
  expect_equal(limpiar_precio("$ 12.900"), 12900)
  expect_equal(limpiar_precio("$12.900,50"), 12900.5)
  expect_equal(limpiar_precio("1.234.567"), 1234567)
  expect_equal(limpiar_precio("4,63"), 4.63)
  expect_true(is.na(limpiar_precio("gratis")))
  expect_true(is.na(limpiar_precio(NA)))
})

test_that("normaliza unidades a mL, g o unidad sin mezclarlas", {
  r <- normalizar_unidad(c(1.5, 600, 2, 6), c("L", "ml", "kg", "und"))
  expect_equal(r$valor_base, c(1500, 600, 2000, 6))
  expect_equal(r$unidad_base, c("mL", "mL", "g", "unidad"))
  expect_true(is.na(normalizar_unidad(1, "galon")$unidad_base))
  pu <- precio_unitario(c(3000, 3000), c(1.5, 500), c("l", "g"))
  expect_equal(pu$unidad_base, c("mL", "g"))          # no se mezclan en la misma comparación
  expect_equal(pu$precio_unitario, c(2, 6))
  expect_true(is.na(precio_unitario(3000, 0, "ml")$precio_unitario))
})

test_that("calcula el ahorro por producto y reporta los empates", {
  d <- data.frame(clave_producto = "P1", comercio = c("A", "B", "C"), precio_cop = c(4000, 4000, 5000))
  a <- calcular_ahorro(d)
  expect_equal(a$precio_minimo, 4000); expect_equal(a$ahorro_cop, 1000); expect_equal(a$ahorro_pct, 20)
  expect_equal(a$comercios_minimo, "A | B"); expect_true(a$hay_empate)
})

test_that("detecta subidas, bajadas, productos nuevos y no observados", {
  ant <- data.frame(comercio = "A", sku_comercio = c("1", "2", "3", "4"), producto_raw = paste0("p", 1:4), precio_cop = c(1000, 2000, 3000, 4000))
  nue <- data.frame(comercio = "A", sku_comercio = c("1", "2", "3", "9"), producto_raw = c("p1", "p2", "p3", "p9"), precio_cop = c(1200, 1800, 3000, 500))
  r <- detectar_cambios(ant, nue, umbral_pct = 15)
  est <- setNames(r$estado, r$sku_comercio)
  expect_equal(unname(est[c("1", "2", "3", "4", "9")]), c("sube", "baja", "igual", "no_observado", "nuevo"))
  expect_equal(r$delta_pct[r$sku_comercio == "1"], 20)
  expect_true(r$variacion_grande[r$sku_comercio == "1"]); expect_false(r$variacion_grande[r$sku_comercio == "2"])
})

test_that("la canasta no se calcula en un comercio al que le falta un producto", {
  precios <- data.frame(clave_producto = c("P1", "P2", "P1"), comercio = c("A", "A", "B"), precio_cop = c(1000, 2000, 900))
  sel <- data.frame(clave_producto = c("P1", "P2"), cantidad = c(2, 1))
  r <- calcular_canasta(precios, sel)
  expect_equal(r$por_comercio$total_cop[r$por_comercio$comercio == "A"], 4000)
  expect_true(is.na(r$por_comercio$total_cop[r$por_comercio$comercio == "B"]))
  expect_false(r$por_comercio$completa[r$por_comercio$comercio == "B"])
  expect_equal(r$por_comercio$n_faltantes[r$por_comercio$comercio == "B"], 1)
})

test_that("compra dividida: ahorro frente al mejor comercio único, con empates", {
  precios <- data.frame(clave_producto = c("P1", "P1", "P2", "P2"), comercio = c("A", "B", "A", "B"), precio_cop = c(1000, 800, 2000, 2000))
  r <- calcular_canasta(precios, data.frame(clave_producto = c("P1", "P2"), cantidad = c(1, 1)))
  expect_equal(r$mejor_unico_total, 2800)             # B: 800 + 2000
  expect_equal(r$total_dividida, 2800)                # P1 en B, P2 empata (A | B)
  expect_equal(r$ahorro_cop, 0)
  expect_equal(r$detalle$comercios_minimo, c("B", "A | B"))
  expect_true(r$detalle$hay_empate[2])
})

test_that("valida y sanea el texto de búsqueda", {
  expect_equal(validar_texto("coca cola; DROP TABLE x --"), "coca cola DROP TABLE x --")
  expect_equal(nchar(validar_texto(strrep("a", 500), 60)), 60)
  expect_equal(validar_texto(NULL), "")
  expect_equal(escapar_like("50%_off"), "50\\%\\_off")
})

test_that("las reglas de validación rechazan precios, fechas y duplicados inválidos", {
  o <- data.frame(precio_cop = c(1000, -5, 1000, 1000), comercio = "A", sku_comercio = c("1", "2", "1", "4"),
                  url_producto = "http://x", url_extraccion = NA, disponibilidad = "disponible",
                  fecha_hora_consulta = c("2026-11-09T10:00:00-05:00", "2026-11-09T10:00:00-05:00", "2026-11-09T10:00:00-05:00", "ayer"),
                  stringsAsFactors = FALSE)
  m <- reglas_obs(o)
  expect_equal(m, c(NA, "validacion_precio", "validacion_duplicado", "validacion_fecha"))
})

test_that("verifica que cada comercio tenga los comparables mínimos", {
  comp <- data.frame(comercio = rep(c("A", "B"), c(8, 3)), clave_producto = c(paste0("P", 1:8), paste0("P", 1:3)))
  r <- validar_comparables_presentes(comp, c("A", "B"), 8)
  expect_equal(r$cumple, c(TRUE, FALSE))
})
