
test_that("ahorro: calcula (max-min)/max y reporta empates en el mínimo", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  obs(con, "e1", "A", "P1", 100); obs(con, "e1", "B", "P1", 80); obs(con, "e1", "C", "P1", 80)
  r <- ahorro_por_producto(con, "e1")
  expect_equal(r$ahorro_pct, 20)
  expect_setequal(strsplit(r$mas_barato, " \\| ")[[1]], c("B", "C"))
})

test_that("referencia: usa la variante más cara cuando hay varios anuncios", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  obs(con, "e1", "A", "P1", 50)
  dbExecute(con, "INSERT INTO observaciones
    (ejecucion_id, comercio, nombre, producto_comercio, precio, fecha_hora, producto_id, comparable)
    VALUES ('e1','A','P1 variante','P1 A v2', 70, '2026-11-01T10:00:00', 'P1', 1)")
  r <- dbGetQuery(con, "SELECT precio, n_anuncios FROM v_referencia WHERE producto_id='P1'")
  expect_equal(r$precio, 70); expect_equal(r$n_anuncios, 2)
})

test_that("no duplica una ejecución: UNIQUE + INSERT OR IGNORE", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  obs(con, "e1", "A", "P1", 100)
  n <- dbExecute(con, "INSERT OR IGNORE INTO observaciones
    (ejecucion_id, comercio, nombre, producto_comercio, precio, fecha_hora, producto_id, comparable)
    VALUES ('e1','A','P1 A','P1 A',100,'2026-11-01T10:00:00','P1',1)")
  expect_equal(n, 0)
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n, 1)
})

test_that("precio no positivo es rechazado por el esquema", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  expect_error(obs(con, "e1", "A", "P1", 0))
})

test_that("cambios de precio: devuelve los que cambian y marca los que superan el umbral", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  obs(con, "e1", "A", "P1", 100); obs(con, "e2", "A", "P1", 120)   # +20 %
  obs(con, "e1", "A", "P2", 100); obs(con, "e2", "A", "P2", 103)   # +3 %
  obs(con, "e1", "A", "P3", 100); obs(con, "e2", "A", "P3", 100)   # sin cambio
  r10 <- cambios_entre(con, "e1", "e2", umbral_pct = 10)
  expect_equal(nrow(r10), 2)                    # P3 no aparece
  expect_equal(sum(r10$variacion_grande), 1)    # solo el +20 %
  r1 <- cambios_entre(con, "e1", "e2", umbral_pct = 1)
  expect_equal(sum(r1$variacion_grande), 2)
})

test_that("canasta: marca incompletos a los comercios sin todos los productos", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  for (p in c("P1", "P2")) { obs(con, "e1", "A", p, 100); obs(con, "e1", "B", p, 90) }
  obs(con, "e1", "C", "P1", 50)                                     # C no tiene P2
  r <- canasta_totales(con, "e1", c("P1", "P2"))
  expect_false(r$completa[r$comercio == "C"])
  expect_true(all(r$completa[r$comercio %in% c("A", "B")]))
  expect_equal(r$total[r$comercio == "B"], 180)
})

test_that("canasta vacía no rompe", {
  con <- con_prueba(); on.exit(dbDisconnect(con))
  expect_equal(nrow(canasta_totales(con, "e1", character())), 0)
})

