# Pruebas de la capa de datos (db.R) sobre una base temporal

test_that("insertar dos veces la misma ejecución no duplica observaciones", {
  ruta <- crear_db_prueba(); con <- db_abrir(ruta); on.exit(dbDisconnect(con))
  db_registrar_ejecucion(con, "C1_a", "C1", "A")
  o <- rbind(obs_prueba("C1_a", "A", "s1", 3000, "2026-11-08T10:00:00-05:00"),
             obs_prueba("C1_a", "A", "s2", 4000, "2026-11-08T10:00:01-05:00"))
  expect_equal(db_insertar_obs(con, o), 2L)
  expect_equal(db_insertar_obs(con, o), 0L)           # segunda vez: todo ignorado por la restricción de unicidad
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n, 2)
})

test_that("las consultas parametrizadas resisten la inyección SQL", {
  ruta <- crear_db_prueba(); con <- db_abrir(ruta)
  db_registrar_ejecucion(con, "C1_a", "C1", "A"); db_insertar_obs(con, obs_prueba("C1_a", "A", "s1", 3000, "2026-11-08T10:00:00-05:00"))
  dbDisconnect(con)
  malo <- "x'; DROP TABLE observaciones; --"
  d <- db_tabla(list(texto = malo, comercios = c("A", "' OR 1=1 --")), path = ruta)
  expect_equal(nrow(d), 0)
  expect_true("observaciones" %in% dbListTables(db_abrir(ruta)))
  expect_equal(nrow(db_tabla(list(), path = ruta)), 1)
})

test_that("filtros_where genera un marcador por cada parámetro", {
  fw <- filtros_where(list(comercios = c("A", "B"), subcategorias = "Gaseosas", precio = c(100, 900), solo_promo = TRUE, texto = "coca"))
  expect_equal(lengths(regmatches(fw$sql, gregexpr("\\?", fw$sql))), length(fw$params))
  expect_false(grepl("coca", fw$sql))                 # el valor del usuario nunca viaja en el texto SQL
})

test_that("una corrección queda auditada y no borra la observación", {
  ruta <- crear_db_prueba(); con <- db_abrir(ruta); on.exit(dbDisconnect(con))
  db_registrar_ejecucion(con, "C1_a", "C1", "A"); db_insertar_obs(con, obs_prueba("C1_a", "A", "s1", 3000, "2026-11-08T10:00:00-05:00"))
  id <- dbGetQuery(con, "SELECT id_obs FROM observaciones")$id_obs
  expect_true(db_corregir_campo(con, id, "marca_estandarizada", "COCA-COLA", "Marca mal detectada"))
  expect_false(db_corregir_campo(con, id, "marca_estandarizada", "COCA-COLA", "sin cambios"))   # idempotente
  cr <- dbGetQuery(con, "SELECT * FROM correcciones")
  expect_equal(nrow(cr), 1); expect_equal(cr$valor_anterior, "MARCA"); expect_equal(cr$valor_nuevo, "COCA-COLA")
  expect_error(db_corregir_campo(con, id, "precio_cop; DROP TABLE x", "1", "mal campo"))
  db_descartar_obs(con, id, "Producto fuera de categoría")
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones")$n, 1)       # sigue en la base
  expect_equal(dbGetQuery(con, "SELECT COUNT(*) n FROM v_obs_validas")$n, 0)       # pero ya no se usa
})

test_that("la vista de cambios detecta la variación entre dos ejecuciones", {
  ruta <- crear_db_prueba(); con <- db_abrir(ruta); on.exit(dbDisconnect(con))
  db_registrar_ejecucion(con, "C1_a", "C1", "A"); db_registrar_ejecucion(con, "C2_a", "C2", "A")
  db_insertar_obs(con, obs_prueba("C1_a", "A", "s1", 4000, "2026-11-08T10:00:00-05:00"))
  db_insertar_obs(con, obs_prueba("C2_a", "A", "s1", 4400, "2026-11-09T10:00:00-05:00"))
  v <- dbGetQuery(con, "SELECT * FROM v_cambios_precio ORDER BY fecha_hora_consulta")
  expect_equal(v$sentido, c("nuevo", "sube")); expect_equal(v$delta_cop[2], 400); expect_equal(v$delta_pct[2], 10)
  ch <- db_cambios_entre("C1", "C2", 5, path = ruta)
  expect_equal(ch$estado, "sube"); expect_true(ch$variacion_grande)
})

test_that("el historial une corridas por clave_producto aunque cambie el id PROD_COM", {
  ruta <- crear_db_prueba(); con <- db_abrir(ruta); on.exit(dbDisconnect(con))
  for (k in 1:2) {
    ej <- paste0("C", k, "_a"); db_registrar_ejecucion(con, ej, paste0("C", k), "A")
    dbExecute(con, "INSERT INTO productos_comunes VALUES(?,?,?,?,?,?,?,?,?,?)",
              params = list(paste0("C", k), paste0("PROD_COM_0", k), "MARCA|Gaseosas|BASE|1500|1", "MARCA", "Gaseosas", "BASE", 1500, 1, 1, "A"))
    db_insertar_obs(con, obs_prueba(ej, "A", "s1", 4000 + 100 * k, paste0("2026-11-0", 7 + k, "T10:00:00-05:00"), 1L, paste0("PROD_COM_0", k)))
  }
  s <- db_serie_producto("MARCA|Gaseosas|BASE|1500|1", path = ruta)
  expect_equal(nrow(s), 2); expect_equal(s$precio_cop, c(4100, 4200))
})
