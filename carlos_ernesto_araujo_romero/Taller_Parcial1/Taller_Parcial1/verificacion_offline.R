# =============================================================================
# verificacion_offline.R
# Comprueba que la recolección se puede reproducir sin volver a consultar los
# sitios: lee únicamente raw/ y crea una base de verificación separada.
#
# Uso:
#   Rscript verificacion_offline.R
#   Rscript verificacion_offline.R EJEC_20261105_222937
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
})

source("scraper.R")

args <- commandArgs(trailingOnly = TRUE)
ruta_db_principal <- "comparador_precios.sqlite"
ruta_db_verificacion <- "verificacion_offline.sqlite"

con <- dbConnect(SQLite(), ruta_db_principal)
on.exit(dbDisconnect(con), add = TRUE)

if (length(args) >= 1 && nzchar(args[1])) {
  id_ejecucion <- args[1]
} else {
  candidatas <- dbGetQuery(con, "
    SELECT id_ejecucion
      FROM ejecuciones
     WHERE estado = 'completa'
     ORDER BY fecha_inicio DESC")
  if (nrow(candidatas) == 0) stop("No hay ejecuciones completas en la base principal.")
  id_ejecucion <- candidatas$id_ejecucion[1]
}

message("Verificando offline la ejecución: ", id_ejecucion)

ver <- verificar_offline(
  id_ejecucion = id_ejecucion,
  ruta_db_verificacion = ruta_db_verificacion,
  ruta_db_original = ruta_db_principal
)

lineas <- c(
  "VERIFICACIÓN DEL MODO SIN CONEXIÓN",
  "===================================",
  paste0("Ejecución: ", id_ejecucion),
  paste0("Fecha de la prueba: ", ahora_colombia()),
  paste0("Base original: ", ruta_db_principal),
  paste0("Base reprocesada desde raw/: ", ruta_db_verificacion),
  "",
  "Comparación por comercio (conteos, suma de precios y disponibilidad):",
  capture.output(print(ver$comparacion, row.names = FALSE)),
  "",
  paste0("¿Todos los comercios coinciden? ", ifelse(ver$todo_igual, "SÍ", "NO")),
  "",
  "La prueba no hizo peticiones HTTP: leyó los archivos .json.gz y los",
  "metadata.json de raw/ y aplicó el mismo parser y la misma correspondencia.",
  ""
)

writeLines(lineas, "verificacion_offline.txt", useBytes = TRUE)
cat(paste(lineas, collapse = "\n"))
cat("\nArchivo generado: verificacion_offline.txt\n")

if (!ver$todo_igual) {
  quit(status = 1)
}
