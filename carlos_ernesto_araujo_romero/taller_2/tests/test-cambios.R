test_that("detecta subidas, bajadas, productos nuevos y no observados", {
  b <- nueva_base()
  on.exit(DBI::dbDisconnect(b$con), add = TRUE)

  nueva_ejecucion(b$con, "E1", "2026-11-10T09:00:00-05:00")
  nueva_ejecucion(b$con, "E2", "2026-11-11T09:00:00-05:00")

  nueva_observacion(b$con, "E1", "carulla", "p1", 1000, "2026-11-10T09:01:00-05:00", "P1", 1)
  nueva_observacion(b$con, "E1", "jumbo", "p1", 1000, "2026-11-10T09:02:00-05:00", "P1", 1)
  nueva_observacion(b$con, "E1", "carulla", "p3", 700, "2026-11-10T09:03:00-05:00", "P2", 0)

  nueva_observacion(b$con, "E2", "carulla", "p1", 1200, "2026-11-11T09:01:00-05:00", "P1", 1)
  nueva_observacion(b$con, "E2", "jumbo", "p1", 900, "2026-11-11T09:02:00-05:00", "P1", 1)
  nueva_observacion(b$con, "E2", "carulla", "p2", 500, "2026-11-11T09:03:00-05:00", "P2", 1)

  d <- cambios_entre(b$con, "E1", "E2", umbral = 0, solo_comparables = FALSE)
  expect_equal(nrow(d), 4)
  expect_equal(sum(d$tipo == "Subió"), 1)
  expect_equal(sum(d$tipo == "Bajó"), 1)
  expect_equal(sum(d$tipo == "Nuevo"), 1)
  expect_equal(sum(d$tipo == "Dejó de observarse"), 1)

  subida <- d[d$tipo == "Subió", ]
  expect_equal(subida$cambio_cop, 200)
  expect_equal(subida$cambio_pct, 20)

  solo_grandes <- cambios_entre(b$con, "E1", "E2", umbral = 15, solo_comparables = FALSE)
  expect_equal(nrow(solo_grandes[solo_grandes$tipo == "Subió", ]), 1)
  expect_equal(nrow(solo_grandes[solo_grandes$tipo == "Bajó", ]), 0)
})

test_that("sin cambios devuelve una tabla vacía sin errores", {
  b <- nueva_base()
  on.exit(DBI::dbDisconnect(b$con), add = TRUE)
  nueva_ejecucion(b$con, "E1", "2026-11-10T09:00:00-05:00")
  nueva_ejecucion(b$con, "E2", "2026-11-11T09:00:00-05:00")
  nueva_observacion(b$con, "E1", "carulla", "p1", 1000, "2026-11-10T09:01:00-05:00", "P1", 1)
  nueva_observacion(b$con, "E2", "carulla", "p1", 1000, "2026-11-11T09:01:00-05:00", "P1", 1)

  d <- cambios_entre(b$con, "E1", "E2", umbral = 0, solo_comparables = FALSE)
  expect_equal(nrow(d), 0)
  expect_true(all(c("tipo", "precio_anterior", "cambio_pct") %in% names(d)))
})
