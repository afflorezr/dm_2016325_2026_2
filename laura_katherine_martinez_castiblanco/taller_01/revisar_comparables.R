# =============================================================================
# revisar_comparables.R · Revisión manual de la correspondencia de productos
# Uso:  source("config.R"); source("scraper.R"); source("revisar_comparables.R")
#       revisar_comparables()                       # lista emparejamientos con brecha de precio alta
#       excluir_comparables("PROD_COM_05", "pack distinto (unidades) emparejado por error")
# Cada exclusión queda registrada en la tabla `correcciones` (no se borra ninguna observación).
# Después de excluir: en preparar_taller1.R pon REASIGNAR <- FALSE y vuelve a correrlo.
# =============================================================================
.corrida_ref <- function(con)
  dbGetQuery(con, "SELECT MAX(id_corrida) m FROM ejecuciones WHERE n_registros > 0")$m

revisar_comparables <- function(umbral = 0.25) {
  con <- db_conectar(); on.exit(dbDisconnect(con), add = TRUE)
  corrida <- .corrida_ref(con)
  d <- dbGetQuery(con, "SELECT o.id_producto_comun AS id, o.comercio, o.producto_raw AS producto,
        o.unidades AS und, o.contenido_total_ml AS ml, o.precio_cop AS precio,
        ROUND(o.precio_por_litro) AS cop_litro
      FROM observaciones o JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
      WHERE e.id_corrida = ? AND o.comparable = 1
      ORDER BY o.id_producto_comun, o.precio_cop", params = list(corrida))
  d <- d |> group_by(id) |>
    mutate(brecha = round((max(precio) - min(precio)) / min(precio), 2)) |> ungroup()
  sosp <- filter(d, brecha > umbral)
  cat("Corrida:", corrida, "| comparables:", n_distinct(d$id),
      "| con brecha >", umbral, ":", n_distinct(sosp$id), "\n\n")
  op <- options(width = 230); on.exit(options(op), add = TRUE)
  print(as.data.frame(sosp), right = FALSE)
  cat("\nRevisa: ¿mismo producto, misma variante y mismo número de unidades en los 3 comercios?\n",
      "Si no: excluir_comparables(c('PROD_COM_xx'), 'motivo')\n", sep = "")
  invisible(d)
}

excluir_comparables <- function(ids, motivo) {
  stopifnot(length(ids) >= 1, nzchar(motivo))
  con <- db_conectar(); on.exit(dbDisconnect(con), add = TRUE)
  corrida <- .corrida_ref(con)
  ph <- paste(rep("?", length(ids)), collapse = ",")
  obs <- dbGetQuery(con, sprintf("SELECT o.id_obs, o.id_producto_comun AS id
      FROM observaciones o JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
      WHERE e.id_corrida = ? AND o.comparable = 1 AND o.id_producto_comun IN (%s)", ph),
                    params = c(list(corrida), as.list(ids)))
  if (!nrow(obs)) { message("Nada que excluir (ids no encontrados)."); return(invisible(0L)) }
  dbBegin(con)
  tryCatch({
    dbExecute(con, "UPDATE observaciones SET comparable = 0, id_producto_comun = NULL WHERE id_obs = ?",
              params = list(obs$id_obs))
    dbAppendTable(con, "correcciones", data.frame(
      fecha = ahora_iso(), tabla = "observaciones", id_registro = as.character(obs$id_obs),
      campo = "comparable", valor_anterior = "1", valor_nuevo = "0",
      motivo = paste0(motivo, " [", obs$id, "]")))
    dbExecute(con, sprintf("DELETE FROM productos_comunes WHERE id_corrida = ? AND id_producto_comun IN (%s)", ph),
              params = c(list(corrida), as.list(ids)))
    dbCommit(con)
  }, error = function(e) { dbRollback(con); stop(e) })
  message(nrow(obs), " observaciones excluidas de los comparables (", paste(ids, collapse = ", "),
          "). Ahora: REASIGNAR <- FALSE en preparar_taller1.R y volver a correrlo.")
  invisible(nrow(obs))
}