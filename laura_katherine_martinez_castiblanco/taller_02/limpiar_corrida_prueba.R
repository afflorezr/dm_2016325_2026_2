# =============================================================================
# limpiar_corrida_prueba.R · Elimina UNA corrida de prueba que quedó guardada por error.
# Uso (desde taller_2/):
#   source("limpiar_corrida_prueba.R")
#   listar_corridas()                          # identifique la de prueba (pocas obs., pocos comparables)
#   eliminar_corrida_prueba("AAAAMMDD-HHMMSS")
# Hace respaldo .bak de la base y del manifest antes de borrar. Las corridas oficiales están protegidas.
# =============================================================================
source("db.R", encoding = "UTF-8"); library(readr); library(dplyr)

listar_corridas <- function() db_q(
  "SELECT c.id_corrida, c.fecha_hora, c.n_obs, c.estado,
          (SELECT COUNT(*) FROM productos_comunes p WHERE p.id_corrida = c.id_corrida) AS comparables
   FROM v_corridas c ORDER BY c.id_corrida")

eliminar_corrida_prueba <- function(id, protegidas = c("20261108-174507", "20261110-141724")) {
  stopifnot(is.character(id), length(id) == 1)
  if (id %in% protegidas) stop("Esa es una corrida oficial protegida; no se elimina.")
  if (!id %in% listar_corridas()$id_corrida) stop("No existe la corrida ", id)
  sello <- format(Sys.time(), "%Y%m%d%H%M%S"); man <- file.path("raw", "manifest.csv")
  file.copy(DB_PATH, paste0(DB_PATH, ".bak_", sello))
  if (file.exists(man)) file.copy(man, paste0(man, ".bak_", sello))
  
  con <- db_abrir(); on.exit(dbDisconnect(con), add = TRUE)
  dbBegin(con)
  tryCatch({
    ej <- dbGetQuery(con, "SELECT id_ejecucion FROM ejecuciones WHERE id_corrida = ?", params = list(id))$id_ejecucion
    for (e in ej) {
      dbExecute(con, "DELETE FROM obs_descartadas WHERE id_obs IN (SELECT id_obs FROM observaciones WHERE id_ejecucion = ?)", params = list(e))
      for (t in c("observaciones", "descartes", "cobertura_sitio"))
        dbExecute(con, sprintf("DELETE FROM %s WHERE id_ejecucion = ?", t), params = list(e))
    }
    dbExecute(con, "DELETE FROM validaciones WHERE id_ejecucion = ?", params = list(id))   # el lote guarda aquí el id_corrida
    dbExecute(con, "DELETE FROM productos_comunes WHERE id_corrida = ?", params = list(id))
    dbExecute(con, "DELETE FROM ejecuciones WHERE id_corrida = ?", params = list(id))
    dbCommit(con)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop("Se revirtió: ", conditionMessage(e)) })
  
  if (file.exists(man)) {
    m <- read_csv(man, col_types = cols(.default = col_character()), show_col_types = FALSE)
    write_csv(filter(m, id_corrida != id), man)
  }
  unlink(list.files("raw", pattern = paste0("^", id, "$"), recursive = TRUE, include.dirs = TRUE, full.names = TRUE), recursive = TRUE)
  unlink(file.path("diagnostico", id), recursive = TRUE)
  message("Corrida ", id, " eliminada. Respaldo: ", DB_PATH, ".bak_", sello)
  print(listar_corridas()); invisible(TRUE)
}