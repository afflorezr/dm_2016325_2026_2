# =============================================================================
# reconstruir_productos_comunes.R · Deja productos_comunes coherente con observaciones.comparable
# Uso (desde taller_2/):  source("reconstruir_productos_comunes.R"); reconstruir_productos_comunes("20261110-141724")
# No reasigna comparables: solo reconstruye el catálogo desde lo que ya está marcado.
# =============================================================================
source("config.R", encoding = "UTF-8"); source("scraper.R", encoding = "UTF-8")
source("comparables.R", encoding = "UTF-8"); source("db.R", encoding = "UTF-8")
library(dplyr)

reconstruir_productos_comunes <- function(id_corrida, min_comercios = 3) {
  con <- db_abrir(); on.exit(dbDisconnect(con), add = TRUE)
  obs <- dbGetQuery(con, "SELECT o.id_obs, o.comercio, o.id_producto_comun, o.producto_raw, o.marca_estandarizada AS marca,
                           o.subcategoria, o.contenido_total_ml, o.unidades
                    FROM observaciones o JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
                    LEFT JOIN obs_descartadas d ON d.id_obs = o.id_obs
                    WHERE e.id_corrida = ? AND e.modo = 'online' AND d.id_obs IS NULL
                      AND o.comparable = 1 AND o.id_producto_comun IS NOT NULL", params = list(id_corrida))
  info <- obs |> group_by(id_producto_comun) |>
    summarise(marca = first(marca), subcategoria = first(subcategoria), variante = clave_variante(first(producto_raw)),
              contenido_total_ml = first(contenido_total_ml), unidades = first(unidades),
              n_comercios = n_distinct(comercio), lista_comercios = paste(sort(unique(comercio)), collapse = " | "),
              ids = list(id_obs), .groups = "drop") |>
    mutate(clave_producto = paste(marca, subcategoria, variante, round(contenido_total_ml), unidades, sep = "|"))
  
  incompletos <- info[info$n_comercios < min_comercios, ]
  if (nrow(incompletos)) {
    message("Productos con menos de ", min_comercios, " comercios (se desmarcan con auditoría): ",
            paste(incompletos$id_producto_comun, collapse = ", "))
    for (i in unlist(incompletos$ids))
      db_corregir_campo(con, i, "comparable", 0L, paste0("Producto comparable quedó con menos de ", min_comercios,
                                                         " comercios tras corregir emparejamientos (corrida ", id_corrida, ")."))
    info <- info[info$n_comercios >= min_comercios, ]
  }
  dbBegin(con)
  tryCatch({
    dbExecute(con, "DELETE FROM productos_comunes WHERE id_corrida = ?", params = list(id_corrida))
    if (nrow(info)) dbAppendTable(con, "productos_comunes", data.frame(
      id_corrida = id_corrida, id_producto_comun = info$id_producto_comun, clave_producto = info$clave_producto,
      marca = info$marca, subcategoria = info$subcategoria, variante = info$variante,
      contenido_total_ml = info$contenido_total_ml, unidades = info$unidades,
      n_comercios = info$n_comercios, lista_comercios = info$lista_comercios))
    dbCommit(con)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop(e) })
  message("Corrida ", id_corrida, ": ", nrow(info), " productos comparables.")
  invisible(info)
}