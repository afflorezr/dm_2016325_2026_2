# Solo lectura: no altera SQLite, raw/ ni Git.
cat('=== ARCHIVOS DE ENTREGA ===\n')
requeridos <- c('app.R','db.R','scraper.R','validacion.R',
  'comparador_precios.sqlite','diccionario_datos.md','raw',
  'renv.lock','README.md','tests','canasta.R','comparacion_ejecuciones.R',
  'actualizacion_t2.R','previsualizacion_t2.R','paso23_disponibilidad_t2.R')
print(data.frame(archivo = requeridos, existe = file.exists(requeridos)), row.names = FALSE)

cat('\n=== SINTAXIS R ===\n')
archivos_r <- c('app.R','db.R','canasta.R','comparacion_ejecuciones.R',
                'validacion.R','tests/testthat/test_taller2.R')
for (a in archivos_r) {
  cat(a, ': ', if (file.exists(a) && !inherits(
    try(parse(file=a),silent=TRUE), 'try-error')) 'OK' else 'REVISAR', '\n',sep='')
}

local({
if (file.exists('comparador_precios.sqlite')) {
  cat('\n=== BASE DE DATOS REAL (SOLO LECTURA) ===\n')
  con <- DBI::dbConnect(RSQLite::SQLite(),
    'comparador_precios.sqlite', flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add=TRUE)
  print(DBI::dbGetQuery(con, 'PRAGMA integrity_check'))
  print(DBI::dbGetQuery(con, 'PRAGMA foreign_key_check'))
  print(DBI::dbGetQuery(con, "SELECT COUNT(*) AS observaciones FROM observaciones"))
  print(DBI::dbGetQuery(con, "SELECT ejecucion_id, COUNT(DISTINCT comercio_id) AS comercios FROM ejecuciones GROUP BY ejecucion_id"))
  print(DBI::dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type='view'"))
}
})
cat('\nIMPORTANTE: comprobar además URL publicada, PR en GitHub y pruebas locales.\n')
