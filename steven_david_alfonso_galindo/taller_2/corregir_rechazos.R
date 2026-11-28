# corregir_rechazos.R · Cuarta corrección (11/11/2026)
# Cada vez que se reprocesaba una ejecución, la tabla rechazos volvía a anotar
# los mismos productos. validacion.R ya no lo hace; este script quita las
# anotaciones repetidas que quedaron (se conserva la primera de cada una).
#
#   source("corregir_rechazos.R")

source("scraper.R", encoding = "UTF-8")

con <- conectar_bd()
antes <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM rechazos")$n
dbWithTransaction(con, {
  dbExecute(con, "
    DELETE FROM rechazos
     WHERE rechazo_id NOT IN (SELECT MIN(rechazo_id) FROM rechazos
                               GROUP BY id_ejecucion, comercio_id, id_producto_comercio, regla)")
  despues <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM rechazos")$n
  if (despues < antes) {
    dbAppendTable(con, "correcciones", data.frame(
      fecha = ahora_iso(), tabla = "rechazos", registro_id = "todas", campo = "filas",
      valor_anterior = as.character(antes), valor_nuevo = as.character(despues),
      motivo = "Rechazos anotados más de una vez al reprocesar la misma ejecución"))
  }
})
print(dbGetQuery(con, "SELECT id_ejecucion, regla, COUNT(*) AS n FROM rechazos GROUP BY 1, 2"))
dbDisconnect(con)
