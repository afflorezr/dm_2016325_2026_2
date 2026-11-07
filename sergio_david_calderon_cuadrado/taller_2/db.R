# db.R: acceso a la base SQLite. Sin codigo de interfaz.
RUTA_BD <- "comparador_precios.sqlite"

# Fecha y hora actual en ISO 8601 con zona de Bogota: 2026-11-07T10:30:00-05:00
ahora_iso <- function() {
  f <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", f)
}

# Abre la conexion con las llaves foraneas activas. Quien la abre la cierra con DBI::dbDisconnect().
conectar <- function(ruta = RUTA_BD) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

# SKU de los productos comparables (conjunto de 8) en cada comercio
skus_conjunto <- function(con) {
  DBI::dbGetQuery(con,
                  "SELECT c.codigo AS comercio, a.sku
       FROM anuncios a
       JOIN comercios c ON c.id_comercio  = a.id_comercio
       JOIN productos p ON p.id_producto  = a.id_producto
      WHERE p.en_conjunto = 1")
}

# Guarda en `rechazos` las observaciones que no pasaron la validacion
registrar_rechazos <- function(con, rechazadas) {
  if (is.null(rechazadas) || nrow(rechazadas) == 0) return(invisible(0L))
  n <- DBI::dbExecute(con,
                      "INSERT OR IGNORE INTO rechazos (fecha_hora_registro, codigo_corrida, comercio, sku, nombre,
                           precio_texto, regla, motivo)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                      params = list(rep(ahora_iso(), nrow(rechazadas)),
                                    rechazadas$codigo_corrida, rechazadas$comercio, rechazadas$sku,
                                    rechazadas$nombre, rechazadas$precio_texto,
                                    rechazadas$regla, rechazadas$motivo))
  invisible(n)
}

# Ejecuta un archivo .sql (sentencias terminadas en ; al final de linea) en una sola transaccion
aplicar_sql <- function(con, archivo) {
  sql <- paste(readLines(archivo, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  sentencias <- strsplit(sql, ";[[:space:]]*\n")[[1]]
  DBI::dbWithTransaction(con, {
    for (s in sentencias) {
      if (nzchar(trimws(gsub("--[^\n]*", "", s)))) DBI::dbExecute(con, s)
    }
  })
  invisible(length(sentencias))
}

# Guarda las tarjetas "agotado segun el sitio". Solo entran las de ejecuciones ya registradas.
# `agotados` conserva las columnas del scraper (id_ejecucion = codigo de la corrida)
registrar_agotados <- function(con, agotados) {
  if (is.null(agotados) || nrow(agotados) == 0) return(invisible(0L))
  n <- DBI::dbExecute(con,
                      "INSERT OR IGNORE INTO agotados (id_ejecucion, id_comercio, fecha_hora_consulta, nombre, url, texto_original)
     SELECT e.id_ejecucion, c.id_comercio, ?, ?, ?, ?
       FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
      WHERE e.codigo_corrida = ? AND c.codigo = ?",
                      params = list(agotados$fecha_consulta, agotados$nombres, agotados$url,
                                    agotados$texto_original_anuncio, agotados$id_ejecucion, agotados$comercio))
  invisible(n)
}