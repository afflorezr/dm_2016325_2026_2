# =============================================================================
# correcciones_taller1.R · Corrige errores señalados en la retroalimentación del Taller 1
# SIN borrar observaciones: cada cambio queda en la tabla `correcciones` (fecha, registro,
# campo, valor anterior, valor nuevo, motivo). Es idempotente: repetirlo no duplica.
# Uso (desde taller_2/):  source("correcciones_taller1.R")
# Edite la sección "CORRECCIONES" con los casos reales de su retroalimentación.
# =============================================================================
source("db.R", encoding = "UTF-8"); library(dplyr)
db_migrar()
con <- db_abrir(); on.exit(dbDisconnect(con))

# Ayudante: busca observaciones por patrón de nombre (consulta parametrizada) y devuelve sus id_obs
buscar <- function(patron, comercio = NULL) {
  sql <- "SELECT id_obs, comercio, producto_raw, marca_estandarizada, precio_cop FROM observaciones WHERE producto_raw LIKE ?"
  p <- list(paste0("%", patron, "%"))
  if (!is.null(comercio)) { sql <- paste(sql, "AND comercio = ?"); p <- c(p, list(comercio)) }
  dbGetQuery(con, sql, params = p)
}

# ---- CORRECCIONES (ejemplos: reemplácelos por los suyos) ----------------------------------
# 1) Marca mal estandarizada
#    x <- buscar("manzana postobon"); for (i in x$id_obs) db_corregir_campo(con, i, "marca_estandarizada", "POSTOBON", "Marca estandarizada incorrecta (Taller 1)")
# 2) Precio mal extraído (verifique contra la copia cruda en raw/ antes de corregir)
#    db_corregir_campo(con, 123L, "precio_cop", 4990, "Precio tomado del bloque equivocado; verificado en raw/")
# 3) Observación fuera de categoría: se MARCA como descartada, no se borra
#    db_descartar_obs(con, 456L, "Producto no es bebida (fuera de categoría)")
# 4) Campo faltante que sí consta en la copia cruda
#    db_corregir_campo(con, 789L, "marca_estandarizada", "HIT", "Marca presente en la ficha técnica del raw")

# ---- Resumen ----------------------------------------------------------------------------------
print(dbGetQuery(con, "SELECT COUNT(*) AS correcciones_registradas FROM correcciones"))
