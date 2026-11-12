# validacion.R — Reglas de validación y correcciones · Taller 2 · cuidado bucal.
#
# Ninguna observación entra a la base sin pasar por validar_observaciones(). Las reglas se
# declaran con pointblank; las filas que fallan no se insertan y quedan, con el motivo, en la
# tabla observaciones_rechazadas.
#
#   V1 precio numérico.
#   V2 precio mayor que cero cuando hay precio.
#   V3 un producto disponible debe traer precio. (Un producto AGOTADO puede no tener precio
#      publicado: el dato ausente queda como NULL, no se inventa ni se reemplaza.)
#   V4 comercio, URL de la fuente, SKU y fecha y hora de consulta presentes.
#   V5 fecha y hora en ISO 8601 con hora de Colombia (-05:00).
#   V6 sin observaciones duplicadas (comercio, SKU) dentro de la misma ejecución.
#   V7 los ocho productos comparables de referencia presentes en el comercio (regla del lote:
#      no rechaza filas; si falta alguno la ejecución del comercio queda como «parcial»).

PATRON_FECHA <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}-05:00$"

# datos: tabla estándar del scraper. referencia: data.frame(producto_id, producto, sku_comercio) con
# los anuncios de los comparables de referencia en ese comercio.
# Devuelve list(validas, rechazadas (con columna motivo), faltan_referencia, agente).
validar_observaciones <- function(datos, referencia = NULL) {
  salida <- list(validas = datos, rechazadas = cbind(datos[0, , drop = FALSE], motivo = character(0)),
                 faltan_referencia = character(0), agente = NULL)
  if (nrow(datos) == 0) return(salida)
  d <- datos
  d$.fila <- seq_len(nrow(d))
  d$.precio_texto <- as.character(d$precio)
  no_numerico <- rep(FALSE, nrow(d))
  if (!is.numeric(d$precio)) {                                   # V1: texto que no se puede leer como número
    num <- suppressWarnings(as.numeric(d$precio))
    no_numerico <- !is.na(d$precio) & is.na(num)
    d$precio <- num
  }
  d$.precio_numerico <- !no_numerico
  d$.con_precio_si_disponible <- !(is.na(d$precio) & !is.na(d$disponible) & d$disponible == 1) | no_numerico
  d$.primera <- !duplicated(d[c("comercio_id", "sku_comercio", "ejecucion_id")])

  faltan <- character(0)
  if (!is.null(referencia) && nrow(referencia) > 0) {
    presentes <- unique(referencia$producto_id[referencia$sku_comercio %in% d$sku_comercio])
    faltan <- unique(referencia$producto[!(referencia$producto_id %in% presentes)])
  }

  agente <- pointblank::create_agent(tbl = d, label = "Validación de observaciones antes de insertar")
  agente <- pointblank::col_vals_equal(agente, columns = ".precio_numerico", value = TRUE,
                                       label = "V1: precio no numérico")
  agente <- pointblank::col_vals_gt(agente, columns = "precio", value = 0, na_pass = TRUE,
                                    label = "V2: precio menor o igual a cero")
  agente <- pointblank::col_vals_equal(agente, columns = ".con_precio_si_disponible", value = TRUE,
                                       label = "V3: producto disponible sin precio")
  agente <- pointblank::col_vals_not_null(agente, columns = "comercio_id", label = "V4: falta el comercio")
  agente <- pointblank::col_vals_not_null(agente, columns = "url_fuente", label = "V4: falta la URL de la fuente")
  agente <- pointblank::col_vals_not_null(agente, columns = "sku_comercio", label = "V4: falta el SKU")
  agente <- pointblank::col_vals_not_null(agente, columns = "fecha_hora_consulta",
                                          label = "V4: falta la fecha y hora de consulta")
  agente <- pointblank::col_vals_regex(agente, columns = "fecha_hora_consulta", regex = PATRON_FECHA, na_pass = TRUE,
                                       label = "V5: fecha y hora con formato inválido")
  agente <- pointblank::col_vals_equal(agente, columns = ".primera", value = TRUE,
                                       label = "V6: observación duplicada en la misma ejecución")
  agente <- pointblank::specially(agente, fn = function(x) length(faltan) == 0,
                                  label = "V7: faltan productos comparables de referencia")
  agente <- pointblank::interrogate(agente, extract_failed = TRUE, get_first_n = nrow(d))

  # Motivo de rechazo por fila: etiquetas de las reglas que la fila no cumplió
  extractos <- pointblank::get_data_extracts(agente)
  etiquetas <- agente$validation_set$label
  motivo <- rep(NA_character_, nrow(d))
  for (paso in names(extractos)) {
    filas <- extractos[[paso]]$.fila
    motivo[filas] <- ifelse(is.na(motivo[filas]), etiquetas[as.integer(paso)],
                            paste(motivo[filas], etiquetas[as.integer(paso)], sep = "; "))
  }
  mal <- !is.na(motivo)
  rechazadas <- datos[mal, , drop = FALSE]
  rechazadas$precio <- d$.precio_texto[mal]
  rechazadas$motivo <- motivo[mal]
  validas <- datos[!mal, , drop = FALSE]
  validas$precio <- d$precio[!mal]
  rownames(validas) <- NULL; rownames(rechazadas) <- NULL
  list(validas = validas, rechazadas = rechazadas, faltan_referencia = faltan, agente = agente)
}

# ---------------------------------------------------------------------------
# Los ocho productos comparables de referencia
# ---------------------------------------------------------------------------

# Anuncios de los comparables de referencia: data.frame(producto_id, producto, comercio_id, sku_comercio).
comparables_de_referencia <- function(con) {
  DBI::dbGetQuery(con, paste(
    "SELECT r.producto_id, COALESCE(p.nombre_estandar, r.producto_id) AS producto, a.comercio_id, a.sku_comercio",
    "FROM comparables_referencia r JOIN anuncios a ON a.producto_id = r.producto_id AND a.incluido = 1",
    "LEFT JOIN productos p ON p.producto_id = r.producto_id ORDER BY r.orden"))
}

# Elige una sola vez los ocho comparables de referencia (si la tabla ya tiene datos no la toca).
# Criterio: presentaciones emparejadas por EAN, sin alertas, con contenido verificado y con precio
# disponible en todos los comercios en TODAS las ejecuciones completas; se toma una por subcategoría
# y se sigue por rondas hasta completar ocho, en orden de identificador (determinístico).
elegir_comparables_referencia <- function(con, n = 8L) {
  if (DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM comparables_referencia")$n > 0) return(invisible(0L))
  DBI::dbExecute(con, paste(
    "INSERT INTO comparables_referencia (producto_id, orden, criterio, fecha_seleccion)",
    "SELECT producto_id, ROW_NUMBER() OVER (ORDER BY ronda, subcategoria), ?, ? FROM (",
    "  SELECT p.producto_id, p.subcategoria, ROW_NUMBER() OVER (PARTITION BY p.subcategoria ORDER BY p.producto_id) AS ronda",
    "  FROM productos p WHERE p.comparable = 1 AND p.alerta IS NULL AND p.contenido_verificado = 1",
    "    AND p.metodo_correspondencia = 'EAN' AND p.subcategoria <> 'Kits y combos'",
    "    AND NOT EXISTS (SELECT 1 FROM correcciones k JOIN anuncios x ON k.tabla = 'anuncios'",
    "                      AND x.anuncio_id = CAST(k.registro_id AS INTEGER) WHERE x.producto_id = p.producto_id)",
    "    AND (SELECT COUNT(*) FROM (SELECT o.ejecucion_id, o.comercio_id FROM observaciones o",
    "           JOIN anuncios a ON a.anuncio_id = o.anuncio_id",
    "           WHERE a.producto_id = p.producto_id AND a.incluido = 1 AND o.precio IS NOT NULL AND o.disponible = 1",
    "             AND o.descartada = 0 GROUP BY o.ejecucion_id, o.comercio_id))",
    "        = (SELECT COUNT(*) FROM ejecuciones WHERE estado = 'completa')",
    ") ORDER BY ronda, subcategoria LIMIT ?"),
    params = list(paste("EAN válido, sin alertas, contenido verificado y precio disponible en los tres",
                        "comercios en todas las ejecuciones completas; una por subcategoría"),
                  format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00", tz = "America/Bogota"), as.integer(n)))
}

# ---------------------------------------------------------------------------
# Correcciones manuales (tabla `correcciones`)
# ---------------------------------------------------------------------------

# Corrige un campo estandarizado de un anuncio. Queda registrada (fecha, valor anterior, valor nuevo
# y motivo) y se reaplica cada vez que se actualiza la correspondencia; no borra nada.
registrar_correccion <- function(con, anuncio_id, campo, valor_nuevo, motivo) {
  stopifnot(length(anuncio_id) == 1, campo %in% CAMPOS_CORREGIBLES, nzchar(motivo))
  anterior <- DBI::dbGetQuery(con, sprintf("SELECT %s AS v FROM anuncios WHERE anuncio_id = ?", campo),
                              params = list(anuncio_id))$v
  if (length(anterior) == 0) stop("no existe el anuncio ", anuncio_id, call. = FALSE)
  DBI::dbExecute(con, paste(
    "INSERT OR IGNORE INTO correcciones (fecha, tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo, regla)",
    "VALUES (?, 'anuncios', ?, ?, ?, ?, ?, 'manual')"),
    params = list(format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00", tz = "America/Bogota"), as.character(anuncio_id),
                  campo, as.character(anterior), as.character(valor_nuevo), motivo))
}

# Marca una observación como descartada (no se borra): deja de aparecer en las vistas.
descartar_observacion <- function(con, observacion_id, motivo) {
  stopifnot(length(observacion_id) == 1, nzchar(motivo))
  DBI::dbWithTransaction(con, {
    k <- DBI::dbExecute(con, "UPDATE observaciones SET descartada = 1, motivo_descarte = ? WHERE observacion_id = ? AND descartada = 0",
                        params = list(motivo, observacion_id))
    if (k > 0) DBI::dbExecute(con, paste(
      "INSERT OR IGNORE INTO correcciones (fecha, tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo, regla)",
      "VALUES (?, 'observaciones', ?, 'descartada', '0', '1', ?, 'manual')"),
      params = list(format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00", tz = "America/Bogota"), as.character(observacion_id), motivo))
    k
  })
}
