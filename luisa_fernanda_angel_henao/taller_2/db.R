library(DBI)
library(RSQLite)

RUTA_DB <- "comparador_precios.sqlite"

db_con <- function() {
  dbConnect(SQLite(), RUTA_DB)
}

productos_comparables <- function(con) {
  dbGetQuery(con, "
    SELECT producto_comun_id
    FROM vw_comp
    WHERE producto_comun_id IS NOT NULL
    GROUP BY producto_comun_id
    HAVING COUNT(DISTINCT comercio) = 3
    ORDER BY producto_comun_id")
}

precios_filtrados <- function(con, comercios, pmin = 0, pmax = 1e9) {
  marcas <- paste(rep("?", length(comercios)), collapse = ",")
  sql <- paste0("
    SELECT comercio, producto_comun_id, nombre_original, precio, precio_unidad,
           en_promocion, disponible, fecha_hora, url
    FROM vw_comp
    WHERE comercio IN (", marcas, ")
      AND precio BETWEEN ? AND ?
    ORDER BY producto_comun_id, precio")
  dbGetQuery(con, sql, params = c(as.list(comercios), list(pmin, pmax)))
}

indicadores <- function(con) {
  dbGetQuery(con, "
    WITH comp AS (
      SELECT producto_comun_id
      FROM vw_comp
      WHERE producto_comun_id IS NOT NULL
      GROUP BY producto_comun_id
      HAVING COUNT(DISTINCT comercio) = 3)
    SELECT (SELECT COUNT(*) FROM comp) AS productos_comparables,
           COUNT(*) AS observaciones_comparables,
           MIN(fecha_hora) AS captura_inicio,
           MAX(fecha_hora) AS captura_fin
    FROM vw_comp
    WHERE producto_comun_id IN (SELECT producto_comun_id FROM comp)")
}