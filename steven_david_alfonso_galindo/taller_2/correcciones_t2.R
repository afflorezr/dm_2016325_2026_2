# correcciones_t2.R · Correcciones a la base del Taller 1
# Se corre UNA vez, desde la carpeta taller_2, con la base que ya tiene las dos
# ejecuciones:
#
#   source("correcciones_t2.R")
#
# No borra observaciones. Cada valor que cambia queda en la tabla correcciones
# con la fecha, el registro, el valor anterior, el nuevo y el motivo.
#   1. Reglas de exclusión corregidas en procesamiento.R (accesorios, body
#      mist, cremas, varias unidades, "+" en el nombre, Cherry Baby).
#   2. Disponibilidad de La Riviera leída de las copias de raw/, que el
#      Taller 1 no extraía.
#   3. Controles de completitud de Falabella y Farmatodo (retroalimentación
#      del docente), calculados desde raw/ para cada ejecución.

source("scraper.R", encoding = "UTF-8")
source("procesamiento.R", encoding = "UTF-8")

con <- conectar_bd()          # aplica sql/migracion_t2.sql si hace falta
hoy <- ahora_iso()

if (dbGetQuery(con, "SELECT COUNT(*) AS n FROM correcciones")$n > 0) {
  stop("La tabla correcciones ya tiene filas: este script ya se corrió.")
}

guardar_correcciones <- function(cambios) {
  if (nrow(cambios) == 0) return(0)
  dbAppendTable(con, "correcciones", cambios)
  nrow(cambios)
}

# 1. Reglas de exclusión ------------------------------------------------------
campos <- c("excluido", "motivo_exclusion", "producto_id")
antes <- dbGetQuery(con, "SELECT anuncio_id, excluido, motivo_exclusion, producto_id FROM anuncios")
procesar_base(con)
despues <- dbGetQuery(con, "SELECT anuncio_id, excluido, motivo_exclusion, producto_id FROM anuncios")

comparacion <- merge(antes, despues, by = "anuncio_id", suffixes = c("_antes", "_despues"))
cambios <- do.call(rbind, lapply(campos, function(campo) {
  a <- as.character(comparacion[[paste0(campo, "_antes")]])
  d <- as.character(comparacion[[paste0(campo, "_despues")]])
  distinto <- xor(is.na(a), is.na(d)) | (!is.na(a) & !is.na(d) & a != d)
  if (!any(distinto)) return(NULL)
  data.frame(fecha = hoy, tabla = "anuncios",
             registro_id = as.character(comparacion$anuncio_id[distinto]),
             campo = campo, valor_anterior = a[distinto], valor_nuevo = d[distinto],
             motivo = "Regla de exclusión corregida según la revisión del Taller 1")
}))
if (is.null(cambios)) cambios <- data.frame()
message("Correcciones de exclusión: ", guardar_correcciones(cambios))

# 2. Disponibilidad de La Riviera ---------------------------------------------
ejecuciones <- dbGetQuery(con, "SELECT id_ejecucion FROM ejecuciones WHERE comercio_id = ?",
                          params = list(id_comercio("la_riviera")))$id_ejecucion
for (ej in ejecuciones) {
  paginas <- reprocesar_raw("la_riviera", ej, parsear_la_riviera)
  datos <- bind_rows(lapply(paginas, function(p) if (isTRUE(p$ok)) p$datos else NULL))
  datos <- datos[!is.na(datos$disponible), c("id_producto_comercio", "disponible")]
  datos <- distinct(datos, id_producto_comercio, .keep_all = TRUE)

  actual <- dbGetQuery(con, "
    SELECT o.observacion_id, a.id_producto_comercio, o.disponible
      FROM observaciones o JOIN anuncios a ON a.anuncio_id = o.anuncio_id
     WHERE o.id_ejecucion = ? AND o.comercio_id = ? AND o.disponible IS NULL",
    params = list(ej, id_comercio("la_riviera")))
  actual$nuevo <- as.integer(datos$disponible[match(actual$id_producto_comercio, datos$id_producto_comercio)])
  actual <- actual[!is.na(actual$nuevo), ]

  dbWithTransaction(con, {
    dbExecute(con, "UPDATE observaciones SET disponible = ? WHERE observacion_id = ?",
              params = list(actual$nuevo, actual$observacion_id))
    guardar_correcciones(data.frame(
      fecha = hoy, tabla = "observaciones",
      registro_id = as.character(actual$observacion_id), campo = "disponible",
      valor_anterior = NA_character_, valor_nuevo = as.character(actual$nuevo),
      motivo = "Disponibilidad leída de la copia cruda (JSON de Wix, isInStock)"))
  })
  message("La Riviera ", ej, ": disponibilidad en ", nrow(actual), " observaciones (",
          sum(actual$nuevo == 0), " agotadas)")
}

# 3. Controles de completitud -------------------------------------------------
# Nota (11/11/2026): el control de Falabella que calcula este bloque contaba
# variantes y no productos. Se reemplazó con corregir_falabella.R.
# Falabella: el sitio informa posiciones del listado, no productos distintos.
# Con los dos recorridos (precio ascendente y descendente) se estima el
# tamaño del catálogo por captura-recaptura (estimador de Chapman):
#   N = (n1 + 1)(n2 + 1) / (m + 1) - 1
# donde n1 y n2 son los productos de cada recorrido y m los que están en ambos.
# Farmatodo: el servicio no da un total; se verifica que ningún tramo final
# llegue al tope de 80 resultados.
control <- function(ej, clave, indicador, valor, descripcion) {
  data.frame(id_ejecucion = ej, comercio_id = id_comercio(clave), indicador = indicador,
             valor = valor, descripcion = descripcion)
}

controles <- list()
for (ej in dbGetQuery(con, "SELECT DISTINCT id_ejecucion FROM ejecuciones")$id_ejecucion) {
  paginas <- reprocesar_raw("falabella", ej, parsear_falabella)
  ok <- Filter(function(p) isTRUE(p$ok), paginas)
  orden <- vapply(ok, function(p) if (grepl("asc", p$meta$archivo)) "asc" else "desc", "")
  ids_asc  <- unique(unlist(lapply(ok[orden == "asc"],  function(p) p$datos$id_producto_comercio)))
  ids_desc <- unique(unlist(lapply(ok[orden == "desc"], function(p) p$datos$id_producto_comercio)))
  n1 <- length(ids_asc); n2 <- length(ids_desc); m <- length(intersect(ids_asc, ids_desc))
  estimado <- (n1 + 1) * (n2 + 1) / (m + 1) - 1
  obtenidos <- length(union(ids_asc, ids_desc))
  controles[[length(controles) + 1]] <- rbind(
    control(ej, "falabella", "productos_recorrido_asc", n1, "Productos distintos en el recorrido por precio ascendente"),
    control(ej, "falabella", "productos_recorrido_desc", n2, "Productos distintos en el recorrido por precio descendente"),
    control(ej, "falabella", "productos_en_ambos", m, "Productos que aparecen en los dos recorridos"),
    control(ej, "falabella", "catalogo_estimado", round(estimado), "Tamaño estimado del catálogo (Chapman)"),
    control(ej, "falabella", "productos_obtenidos", obtenidos, "Productos distintos obtenidos (unión de los dos recorridos)"),
    control(ej, "falabella", "cobertura_pct", round(100 * obtenidos / estimado, 1), "Productos obtenidos / catálogo estimado"))

  # Farmatodo: cuántos resultados trajo cada consulta guardada.
  manifiesto <- leer_manifiesto("farmatodo", ej)
  paginas <- reprocesar_raw("farmatodo", ej, parsear_farmatodo)
  filas <- vapply(paginas, function(p) if (isTRUE(p$ok)) nrow(p$datos) else NA_integer_, 1L)
  finales <- filas[!is.na(filas) & filas < 80]
  controles[[length(controles) + 1]] <- rbind(
    control(ej, "farmatodo", "consultas", length(filas), "Consultas al servicio de búsqueda"),
    control(ej, "farmatodo", "consultas_en_tope", sum(filas >= 80, na.rm = TRUE), "Consultas con 80 resultados (se parten en tramos más pequeños)"),
    control(ej, "farmatodo", "tramos_finales", length(finales), "Tramos con menos de 80 resultados"),
    control(ej, "farmatodo", "filas_tramos_finales", sum(finales), "Suma de resultados de los tramos finales"))
}
controles <- do.call(rbind, controles)
dbWithTransaction(con, {
  dbExecute(con, "DELETE FROM controles_completitud")
  dbAppendTable(con, "controles_completitud", controles)
})
print(controles[controles$indicador %in% c("catalogo_estimado", "cobertura_pct", "consultas_en_tope"), ])

dbDisconnect(con)
message("Correcciones terminadas")
