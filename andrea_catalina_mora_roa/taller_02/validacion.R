# Ninguna observación entra a la base sin pasar por validar_observaciones().
# Las reglas se declaran como una tabla (nombre, descripción, función que devuelve TRUE si la fila
# cumple). Las filas que fallan alguna regla NO se insertan: se devuelven con el motivo para
# registrarlas en la tabla `rechazos`.

no_vacio <- function(x) !is.na(x) & nzchar(trimws(as.character(x)))

REGLAS_FILA <- list(
  list(regla = "precio_positivo",
       descripcion = "precio numérico y mayor que cero",
       cumple = function(d) is.numeric(d$precio) & !is.na(d$precio) & d$precio > 0,
       motivo = function(d) ifelse(is.na(d$precio), "precio ausente (el sitio no publica precio)",
                                   sprintf("precio no válido: %s", d$precio))),
  list(regla = "campos_presentes",
       descripcion = "comercio, SKU, URL y fecha y hora de consulta presentes",
       cumple = function(d) no_vacio(d$comercio) & no_vacio(d$sku_comercio) &
                            no_vacio(d$url) & no_vacio(d$fecha_hora),
       motivo = function(d) {
         falta <- cbind(comercio = !no_vacio(d$comercio), sku = !no_vacio(d$sku_comercio),
                        url = !no_vacio(d$url), fecha_hora = !no_vacio(d$fecha_hora))
         paste("falta:", apply(falta, 1, function(r) paste(colnames(falta)[r], collapse = ", ")))
       }),
  list(regla = "fecha_iso",
       descripcion = "fecha y hora en ISO 8601 con zona (AAAA-MM-DDTHH:MM:SS-05:00)",
       cumple = function(d) !is.na(d$fecha_hora) &
         grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$", d$fecha_hora, perl = TRUE),
       motivo = function(d) sprintf("fecha y hora con formato no válido: %s", d$fecha_hora)),
  list(regla = "moneda_cop",
       descripcion = "moneda COP",
       cumple = function(d) !is.na(d$moneda) & d$moneda == "COP",
       motivo = function(d) sprintf("moneda distinta de COP: %s", d$moneda)),
  list(regla = "sin_duplicados",
       descripcion = "sin observaciones duplicadas (comercio + SKU) en la misma ejecución",
       cumple = function(d) !duplicated(paste(d$comercio, d$sku_comercio, sep = "\r")),
       motivo = function(d) "observación duplicada en la misma ejecución (se conserva la primera)")
)

# d: data.frame con las columnas que entrega scraper.R (COLS). Devuelve:
#   validas    filas que cumplen todas las reglas
#   rechazadas una fila por (observación, regla incumplida), con el motivo
#   resumen    una fila por regla: evaluadas, fallas, resultado
validar_observaciones <- function(d) {
  vacia_rech <- data.frame(comercio = character(), sku_comercio = character(), nombre_original = character(),
                           url = character(), fecha_hora = character(), precio = numeric(),
                           regla = character(), motivo = character(), stringsAsFactors = FALSE)
  if (is.null(d) || !nrow(d)) {
    res <- do.call(rbind, lapply(REGLAS_FILA, function(r)
      data.frame(regla = r$regla, evaluadas = 0L, fallas = 0L, resultado = "no cumple",
                 detalle = "sin observaciones para validar", stringsAsFactors = FALSE)))
    return(list(validas = d, rechazadas = vacia_rech, resumen = res))
  }
  ok_total <- rep(TRUE, nrow(d))
  rech <- list(); res <- list()
  for (r in REGLAS_FILA) {
    ok <- r$cumple(d)
    ok[is.na(ok)] <- FALSE
    ok_total <- ok_total & ok
    if (any(!ok)) {
      f <- d[!ok, , drop = FALSE]
      rech[[r$regla]] <- data.frame(comercio = f$comercio, sku_comercio = f$sku_comercio,
                                    nombre_original = f$nombre_original, url = f$url,
                                    fecha_hora = f$fecha_hora, precio = suppressWarnings(as.numeric(f$precio)),
                                    regla = r$regla, motivo = r$motivo(f), stringsAsFactors = FALSE)
    }
    res[[r$regla]] <- data.frame(regla = r$regla, evaluadas = nrow(d), fallas = sum(!ok),
                                 resultado = if (all(ok)) "cumple" else "no cumple",
                                 detalle = r$descripcion, stringsAsFactors = FALSE)
  }
  list(validas = d[ok_total, , drop = FALSE],
       rechazadas = if (length(rech)) do.call(rbind, c(rech, make.row.names = FALSE)) else vacia_rech,
       resumen = do.call(rbind, c(res, make.row.names = FALSE)))
}

# Regla canasta_referencia: presencia de la canasta de referencia en el comercio.
#   ids_validos: producto_id de las observaciones VÁLIDAS del comercio (calculados con limpieza.R)
#   referencia : producto_id de los 8 productos de la canasta de referencia
validar_canasta_referencia <- function(ids_validos, referencia) {
  faltan <- setdiff(referencia, ids_validos)
  data.frame(regla = "canasta_referencia", evaluadas = length(referencia), fallas = length(faltan),
             resultado = if (length(faltan) == 0 && length(referencia) > 0) "cumple" else "no cumple",
             detalle = if (!length(referencia)) "no hay canasta de referencia definida"
                       else if (length(faltan)) paste("faltan:", paste(faltan, collapse = ", "))
                       else sprintf("los %d productos de referencia están presentes", length(referencia)),
             stringsAsFactors = FALSE)
}
