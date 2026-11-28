# corregir_falabella.R · Tercera corrección (11/11/2026)
# Falabella identifica cada anuncio por su variante (skuId), y el listado
# muestra una variante u otra del mismo producto según el orden del recorrido.
# Por eso algunos productos quedaron dos veces en la misma ejecución, y el
# control de completitud contaba variantes cuando el total del sitio cuenta
# productos.
#
# Para cada ejecución que tenga copias en raw/ este script:
#   1. Marca como descartada la observación repetida (se conserva la variante
#      de código menor). No borra nada y cada marca queda en correcciones.
#   2. Vuelve a calcular el control de completitud de Falabella contando
#      productos: el código que va en la URL después de /product/.
#
# Se puede correr otra vez después de una ejecución nueva:
#   source("corregir_falabella.R")

source("scraper.R", encoding = "UTF-8")

con <- conectar_bd()
fal <- id_comercio("falabella")
producto_falabella <- function(url) sub("^.*/product/([^/]+).*$", "\\1", url)

# 1. Variantes repetidas -------------------------------------------------------
obs <- dbGetQuery(con, "
  SELECT o.observacion_id, o.id_ejecucion, a.id_producto_comercio, a.url_producto
    FROM observaciones o JOIN anuncios a ON a.anuncio_id = o.anuncio_id
   WHERE o.comercio_id = ? AND o.descartada = 0", params = list(fal))
obs$producto <- producto_falabella(obs$url_producto)
obs <- obs[order(obs$id_ejecucion, obs$producto, obs$id_producto_comercio), ]
repetidas <- obs[duplicated(obs[c("id_ejecucion", "producto")]), ]

if (nrow(repetidas) > 0) {
  dbWithTransaction(con, {
    dbExecute(con, "UPDATE observaciones SET descartada = 1 WHERE observacion_id = ?",
              params = list(repetidas$observacion_id))
    dbAppendTable(con, "correcciones", data.frame(
      fecha = ahora_iso(), tabla = "observaciones", registro_id = as.character(repetidas$observacion_id),
      campo = "descartada", valor_anterior = "0", valor_nuevo = "1",
      motivo = paste0("Falabella: variante repetida del producto ", repetidas$producto, " en la misma ejecución")))
  })
}
print(table(repetidas$id_ejecucion))

# 2. Control de completitud ----------------------------------------------------
control <- function(ej, indicador, valor, descripcion) {
  data.frame(id_ejecucion = ej, comercio_id = fal, indicador = indicador, valor = valor, descripcion = descripcion)
}

ejecuciones <- dbGetQuery(con, "
  SELECT id_ejecucion, n_total_sitio FROM ejecuciones
   WHERE comercio_id = ? AND estado <> 'fallida'", params = list(fal))

for (i in seq_len(nrow(ejecuciones))) {
  ej <- ejecuciones$id_ejecucion[i]
  if (!file.exists(ruta_manifiesto("falabella", ej))) next
  paginas <- reprocesar_raw("falabella", ej, parsear_falabella)
  ok <- Filter(function(p) isTRUE(p$ok), paginas)
  orden <- vapply(ok, function(p) if (grepl("asc", p$meta$archivo)) "asc" else "desc", "")
  productos <- function(cual) unique(producto_falabella(unlist(lapply(ok[orden == cual], function(p) p$datos$url_producto))))
  asc <- productos("asc"); desc <- productos("desc")
  obtenidos <- length(union(asc, desc))
  total <- ejecuciones$n_total_sitio[i]
  nuevos <- rbind(
    control(ej, "productos_recorrido_asc", length(asc), "Productos distintos en el recorrido por precio ascendente"),
    control(ej, "productos_recorrido_desc", length(desc), "Productos distintos en el recorrido por precio descendente"),
    control(ej, "productos_en_ambos", length(intersect(asc, desc)), "Productos que aparecen en los dos recorridos"),
    control(ej, "productos_obtenidos", obtenidos, "Productos distintos obtenidos (unión de los dos recorridos)"),
    control(ej, "total_sitio", total, "Productos que informa el sitio en la categoría"),
    control(ej, "cobertura_pct", round(100 * obtenidos / total, 2), "Productos obtenidos / total que informa el sitio"))

  antes <- dbGetQuery(con, "SELECT indicador, valor FROM controles_completitud
                             WHERE id_ejecucion = ? AND comercio_id = ?", params = list(ej, fal))
  cambios <- merge(antes, nuevos[c("indicador", "valor")], by = "indicador", all = TRUE, suffixes = c("_antes", "_nuevo"))
  cambios <- cambios[is.na(cambios$valor_antes) | is.na(cambios$valor_nuevo) | cambios$valor_antes != cambios$valor_nuevo, ]
  dbWithTransaction(con, {
    dbExecute(con, "DELETE FROM controles_completitud WHERE id_ejecucion = ? AND comercio_id = ?", params = list(ej, fal))
    dbAppendTable(con, "controles_completitud", nuevos)
    if (nrow(cambios) > 0) {
      dbAppendTable(con, "correcciones", data.frame(
        fecha = ahora_iso(), tabla = "controles_completitud",
        registro_id = paste(ej, fal, cambios$indicador, sep = "|"), campo = "valor",
        valor_anterior = as.character(cambios$valor_antes), valor_nuevo = as.character(cambios$valor_nuevo),
        motivo = "Falabella: el control de completitud cuenta productos, no variantes"))
    }
  })
}
print(dbGetQuery(con, "SELECT id_ejecucion, indicador, valor FROM controles_completitud
                        WHERE comercio_id = ? ORDER BY id_ejecucion", params = list(fal)))

dbDisconnect(con)
