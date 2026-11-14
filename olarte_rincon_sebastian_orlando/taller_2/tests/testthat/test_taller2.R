# Pruebas del Taller 2: SOLO SQLite en memoria; sin scraping y sin modificar la base entregada.
raiz_pruebas <- if (file.exists('validacion.R')) '.' else if (file.exists('../../validacion.R')) '../..' else stop('No se encuentra la raiz de taller_2')
source(file.path(raiz_pruebas, 'validacion.R'), encoding = 'UTF-8')
source(file.path(raiz_pruebas, 'canasta.R'), encoding = 'UTF-8')
source(file.path(raiz_pruebas, 'comparacion_ejecuciones.R'), encoding = 'UTF-8')

crear_bd_prueba <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), ':memory:')
  comandos <- c(
    'CREATE TABLE comercios (comercio_id INTEGER PRIMARY KEY, nombre TEXT NOT NULL)',
    'CREATE TABLE ejecuciones (ejecucion_id TEXT, comercio_id INTEGER, fecha_hora_inicio TEXT, PRIMARY KEY(ejecucion_id, comercio_id))',
    'CREATE TABLE productos_comunes (producto_comun_id TEXT PRIMARY KEY, producto_comun TEXT)',
    'CREATE TABLE anuncios (ejecucion_id TEXT, comercio_id INTEGER, producto_comercio_id TEXT, producto_comun_id TEXT, comparable INTEGER, incluido_categoria INTEGER, producto_original TEXT, PRIMARY KEY(ejecucion_id,comercio_id,producto_comercio_id))',
    'CREATE TABLE observaciones (observacion_id INTEGER PRIMARY KEY, ejecucion_id TEXT, comercio_id INTEGER, producto_comercio_id TEXT, precio_cop REAL, fecha_hora_consulta TEXT, estado_validacion TEXT, estado_disponibilidad TEXT)',
    'CREATE UNIQUE INDEX ux_registro_prueba ON observaciones(ejecucion_id,comercio_id,producto_comercio_id,fecha_hora_consulta)',
    'CREATE TABLE observaciones_rechazadas (ejecucion_id TEXT, comercio_id INTEGER, producto_comercio_id TEXT)'
  )
  for (sql in comandos) DBI::dbExecute(con, sql)
  DBI::dbExecute(con, "INSERT INTO comercios VALUES (1, 'Tienda A'), (2, 'Tienda B')")
  DBI::dbExecute(con, "INSERT INTO productos_comunes VALUES ('P01','Crema A'),('P02','Crema B'),('P03','Producto ausente'),('P04','Producto nuevo')")
  for (e in c('2026-10-10T09:00:00', '2026-11-13T09:00:00')) {
    id <- if (startsWith(e, '2026-10')) 'octubre' else 'noviembre'
    for (c in 1:2) DBI::dbExecute(con,
      'INSERT INTO ejecuciones VALUES (?, ?, ?)', params = list(id, c, e))
  }
  añadir <- function(ej, tienda, id, precio, idcomun = id) {
    DBI::dbExecute(con, 'INSERT INTO anuncios VALUES (?, ?, ?, ?, 1, 1, ?)',
                   params = list(ej, tienda, paste0(id,'_',tienda), idcomun, id))
    fecha <- if (ej == 'octubre') '2026-10-10T10:00:00' else '2026-11-13T10:00:00'
    DBI::dbExecute(con,
       "INSERT INTO observaciones(ejecucion_id,comercio_id,producto_comercio_id,precio_cop,fecha_hora_consulta,estado_validacion,estado_disponibilidad) VALUES(?,?,?,?,?,'valida','sin_evidencia')",
       params = list(ej, tienda, paste0(id,'_',tienda), precio, fecha))
  }
  añadir('octubre',1,'P01',100)
  añadir('octubre',2,'P01',200)
  añadir('octubre',1,'P02',400)
  añadir('octubre',2,'P02',200)
  añadir('octubre',1,'P03',80)
  añadir('noviembre',1,'P01',120)
  añadir('noviembre',2,'P01',200)
  añadir('noviembre',1,'P02',420)
  añadir('noviembre',2,'P02',200)
  añadir('noviembre',1,'P04',55)
  con
}

testthat::test_that('Convierte precios colombianos de texto en números', {
  testthat::expect_equal(parsear_precio_cop('$ 12.500'), 12500)
  testthat::expect_equal(parsear_precio_cop('12.500,50'), 12500.5)
  testthat::expect_true(is.na(parsear_precio_cop('sin precio')))
})

testthat::test_that('Normalización de unidades reutiliza función del scraper original', {
  # El source registra funciones, NO ejecuta recolección ni conexiones web.
  if (!exists('normalizar_unidad_final', mode = 'function')) {
    source(file.path(raiz_pruebas, 'scraper.R'), encoding = 'UTF-8', local = FALSE)
  }
  testthat::expect_equal(normalizar_unidad_final('gramos'), 'g')
  testthat::expect_equal(normalizar_unidad_final('mL'), 'ml')
  testthat::expect_equal(convertir_contenido_final(1, 'kg')$valor, 1000)
  testthat::expect_equal(convertir_contenido_final(1, 'l')$unidad, 'ml')
})

testthat::test_that('La canasta mixta calcula ahorro positivo', {
  con <- crear_bd_prueba()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  r <- calcular_canasta_db(con, 'octubre', c(P01=1L,P02=1L))
  testthat::expect_equal(r$costo_mixto_cop, 300)
  testthat::expect_equal(r$mejor_total_cop, 400)
  testthat::expect_equal(r$ahorro_cop, 100)
  testthat::expect_equal(r$ahorro_pct, 25)
})

testthat::test_that('Empates de precio quedan registrados y el ahorro no es negativo', {
  con <- crear_bd_prueba()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "UPDATE observaciones SET precio_cop = 100 WHERE ejecucion_id='octubre' AND comercio_id=2 AND producto_comercio_id='P01_2'")
  r <- calcular_canasta_db(con, 'octubre', c(P01=1L,P02=1L))
  testthat::expect_true(r$detalle_mixto$empate[1])
  testthat::expect_true(grepl('Tienda A', r$detalle_mixto$comercios_empatados[1], fixed=TRUE))
  testthat::expect_gte(r$ahorro_cop, 0)
})

testthat::test_that('Insertar dos veces la misma observación no la duplica', {
  con <- crear_bd_prueba()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  n <- DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM observaciones')$n[[1]]
  # Se aplica la restricción UNIQUE del esquema de prueba; no toca SQLite entregada.
  DBI::dbExecute(con, "INSERT OR IGNORE INTO observaciones(ejecucion_id,comercio_id,producto_comercio_id,precio_cop,fecha_hora_consulta,estado_validacion,estado_disponibilidad) VALUES('octubre',1,'P01_1',100,'2026-10-10T10:00:00','valida','sin_evidencia')")
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT COUNT(*) AS n FROM observaciones')$n[[1]], n)
})

testthat::test_that('Detecta cambios, nuevos y no observados por anuncio/tienda', {
  con <- crear_bd_prueba()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  r <- comparar_ejecuciones_db(con, 'octubre','noviembre',10)
  testthat::expect_true(any(r$detalle$estado == 'Aumento'))
  testthat::expect_true(any(r$detalle$estado == 'Sin cambio'))
  testthat::expect_true(any(r$detalle$estado == 'Nuevo'))
  testthat::expect_true(any(r$detalle$estado == 'No observado'))
  testthat::expect_equal(sum(r$resumen$cantidad), nrow(r$detalle))
})

testthat::test_that('Nunca calcula total incompleto ni ahorro ficticio', {
  con <- crear_bd_prueba()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  r <- calcular_canasta_db(con, 'octubre', c(P01=1L, P04=1L))
  testthat::expect_true(all(is.na(r$por_comercio$costo_total_cop)))
  testthat::expect_true(is.na(r$costo_mixto_cop))
  testthat::expect_true(is.na(r$ahorro_cop))
  testthat::expect_gt(length(r$faltantes_globales), 0)
})
