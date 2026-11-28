# =============================================================================
# preparar_taller1.R · Ejecutar DESPUES de terminar el scraper (con taller_01.Rproj abierto)
# REASIGNAR = TRUE  : recalcula los comparables (asignar_comparables) y regenera el .rds
# REASIGNAR = FALSE : conserva los comparables actuales (p. ej. tras excluir_comparables()) y solo regenera el .rds
# =============================================================================
REASIGNAR <- FALSE

source("config.R"); source("scraper.R"); source("comparables.R")
suppressPackageStartupMessages(library(tidyr))

if (REASIGNAR) asignar_comparables()
con <- db_conectar(); on.exit(dbDisconnect(con), add = TRUE)
corrida <- dbGetQuery(con, "SELECT MAX(id_corrida) m FROM ejecuciones WHERE n_registros > 0")$m

df_resultado_final <- dbGetQuery(con, "SELECT o.*, e.id_corrida FROM observaciones o
  JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion WHERE e.id_corrida = ?", params = list(corrida))
productos_comparables_info <- dbGetQuery(con, "SELECT id_producto_comun AS id_comun_asignado, clave_producto,
  n_comercios, lista_comercios FROM productos_comunes WHERE id_corrida = ? ORDER BY id_producto_comun", params = list(corrida))
matriz_comparables <- df_resultado_final |> filter(comparable == 1) |>
  count(id_producto_comun, comercio) |> pivot_wider(names_from = comercio, values_from = n, values_fill = 0)
resumen_na <- tibble(columna = names(df_resultado_final),
                     n_na = vapply(df_resultado_final, function(x) sum(is.na(x)), integer(1))) |>
  mutate(pct_na = round(100 * n_na / nrow(df_resultado_final), 2))

por_comercio <- df_resultado_final |> count(comercio, name = "n")

# Cobertura: subconsultas (un LEFT JOIN con cobertura_sitio multiplica las filas y infla las sumas)
cob <- dbGetQuery(con, "
  SELECT e.comercio,
    (SELECT MAX(c.total_sitio) FROM cobertura_sitio c WHERE c.id_ejecucion = e.id_ejecucion AND c.tipo = 'listado') AS total_sitio_reportado,
    (SELECT COUNT(*) FROM cobertura_sitio c WHERE c.id_ejecucion = e.id_ejecucion AND c.tipo = 'producto') AS fichas_visitadas,
    e.n_registros AS productos_extraidos,
    e.n_descartados AS productos_descartados
  FROM ejecuciones e WHERE e.id_corrida = ? ORDER BY e.comercio", params = list(corrida))

cifras <- list(
  id_corrida = corrida,
  fecha = substr(min(df_resultado_final$fecha_hora_consulta), 1, 10),
  n_obs = nrow(df_resultado_final),
  n_comercios = n_distinct(df_resultado_final$comercio),
  n_prod_unicos = n_distinct(paste(df_resultado_final$comercio, df_resultado_final$sku_comercio)),
  n_comp_prod = nrow(productos_comparables_info),
  n_comp_obs = sum(df_resultado_final$comparable == 1),
  por_comercio = setNames(por_comercio$n, por_comercio$comercio),
  descartes = dbGetQuery(con, "SELECT d.motivo, COUNT(*) n FROM descartes d JOIN ejecuciones e
     ON e.id_ejecucion = d.id_ejecucion WHERE e.id_corrida = ? GROUP BY d.motivo ORDER BY n DESC", params = list(corrida)),
  cobertura = cob)
saveRDS(list(df_resultado_final = df_resultado_final, productos_comparables_info = productos_comparables_info,
             matriz_comparables = matriz_comparables, resumen_na = resumen_na, cifras = cifras),
        "df_resultado_final.rds")

# ---- Verificacion de requisitos minimos (guia del Taller 1) -------------------
cat("\n=== VERIFICACION ===\n")
chk <- function(ok, txt) cat(if (ok) "[OK]  " else "[FALLA]", txt, "\n")
chk(cifras$n_comercios >= 3, paste("comercios con datos:", cifras$n_comercios))
cm_comp <- df_resultado_final |> filter(comparable == 1) |> count(id_producto_comun)
chk(nrow(cm_comp) >= 8 && all(cm_comp$n == 3), paste("productos comparables:", nrow(cm_comp), "x 3 comercios =", cifras$n_comp_obs, "obs (>=24)"))
chk(!anyNA(df_resultado_final$fecha_hora_consulta), "fecha_hora_consulta en todas las observaciones")
chk(all(df_resultado_final$precio_cop > 0), "precios > 0 (sin ceros ni inventados)")
falt <- sum(!file.exists(df_resultado_final$archivo_raw))
chk(falt == 0, paste("copias crudas en raw/ existentes; faltan:", falt))
chk(file.exists("raw/manifest.csv"), "raw/manifest.csv presente")
chk(anyDuplicated(df_resultado_final[, c("comercio", "sku_comercio")]) == 0, "sin duplicados comercio+SKU en la corrida")
cat("\nObservaciones por comercio:\n"); print(cifras$por_comercio)
cat("\nCobertura (total_sitio = mayor conteo que muestra el buscador del sitio; solo orientativo):\n"); print(cob)
cat("\nDescartes por motivo:\n"); print(cifras$descartes)
cat("\nTamano de raw/ (MB):", round(sum(file.size(list.files("raw", recursive = TRUE, full.names = TRUE))) / 1e6, 1), "\n")