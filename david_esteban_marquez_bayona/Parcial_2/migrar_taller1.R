# migrar_taller1.R — Prepara la base del Taller 2 a partir de la entrega del Taller 1.
#
# Uso (desde taller_2/):  Rscript migrar_taller1.R [carpeta_del_taller_1]
# Por defecto busca ../Parcial_1/taller1_cuidado_bucal. Es idempotente:
#   1. copia comparador_precios.sqlite, raw/ y correspondencias_manuales.csv si aún no están aquí;
#   2. agrega tablas, columnas, índices y vistas del Taller 2 (no borra ni modifica observaciones);
#   3. re-estandariza los anuncios y registra en `correcciones` las reglas C1 y C2;
#   4. elige los ocho productos comparables de referencia.
# No consulta ningún sitio ni crea observaciones: los precios siguen siendo los del scraping.
source("limpieza.R", encoding = "UTF-8"); source("validacion.R", encoding = "UTF-8"); source("scraper.R", encoding = "UTF-8")

origen <- commandArgs(trailingOnly = TRUE)
origen <- if (length(origen)) origen[1] else file.path("..", "Parcial_1", "taller1_cuidado_bucal")
if (!file.exists(DB_PATH)) {
  if (!file.exists(file.path(origen, DB_PATH))) stop("No se encontró la base del Taller 1 en ", origen, call. = FALSE)
  file.copy(file.path(origen, DB_PATH), DB_PATH)
  message("Base copiada desde ", origen)
}
if (!dir.exists(RAW_DIR) && dir.exists(file.path(origen, RAW_DIR))) {
  file.copy(file.path(origen, RAW_DIR), ".", recursive = TRUE)
  message("Copias crudas (raw/) copiadas desde ", origen)
}
if (!file.exists("correspondencias_manuales.csv") && file.exists(file.path(origen, "correspondencias_manuales.csv"))) {
  file.copy(file.path(origen, "correspondencias_manuales.csv"), ".")
}

con <- conectar(DB_PATH)
corr <- actualizar_correspondencias(con)
invisible(elegir_comparables_referencia(con))
invisible(DBI::dbExecute(con, "PRAGMA optimize"))
q <- function(sql) DBI::dbGetQuery(con, sql)
message(sprintf("Ejecución de referencia: %s · presentaciones comparables: %d", corr$ejecucion_referencia, corr$n_comparables))
message("Correcciones registradas por regla y campo:")
print(q("SELECT regla, campo, COUNT(*) AS correcciones FROM correcciones GROUP BY regla, campo"))
message("Ocho productos comparables de referencia:")
print(q(paste("SELECT r.orden, p.nombre_estandar AS producto, p.subcategoria FROM comparables_referencia r",
              "JOIN productos p ON p.producto_id = r.producto_id ORDER BY r.orden")))
message("Ejecuciones por fecha (se necesitan al menos dos fechas distintas con ejecuciones completas):")
print(q(paste("SELECT substr(inicio, 1, 10) AS fecha, COUNT(DISTINCT ejecucion_id) AS ejecuciones,",
              "SUM(estado = 'completa') AS comercios_completos FROM ejecuciones GROUP BY 1")))
DBI::dbDisconnect(con)
