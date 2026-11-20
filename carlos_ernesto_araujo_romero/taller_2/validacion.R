# =============================================================================
# validacion.R
# Reglas explícitas que debe cumplir toda observación antes de entrar a la base.
#
# Una observación que no cumple una regla no se inserta: se guarda en
# observaciones_rechazadas con el motivo. Las reglas cubren precio, datos
# obligatorios, duplicados y coherencia de contenido.
# =============================================================================

# Devuelve el catálogo de reglas para el diccionario y la aplicación.
reglas_validacion <- function() {
  data.frame(
    regla = c(
      "precio_positivo", "campos_obligatorios", "url_valida", "fecha_iso",
      "disponibilidad_valida", "duplicado_ejecucion", "precio_lista_coherente",
      "contenido_positivo", "unidad_normalizada"
    ),
    descripcion = c(
      "Si el producto está disponible, precio_cop debe ser numérico y mayor que cero.",
      "comercio, sku, texto original, URL y fecha de consulta no pueden ser nulos.",
      "La URL de extracción debe empezar por http:// o https://.",
      "fecha_consulta debe estar en formato ISO 8601 con hora de Colombia (-05:00).",
      "estado_disponibilidad solo admite disponible, agotado o no_observado.",
      "No puede haber dos observaciones del mismo anuncio en la misma ejecución.",
      "Si existe precio de lista, no puede ser menor que el precio pagado.",
      "contenido_total, cuando existe, debe ser mayor que cero.",
      "unidad_normalizada solo admite g, mL o unidad."
    ),
    stringsAsFactors = FALSE
  )
}

# Convierte un precio en texto ("$ 12.900", "12.900,50") a número.
limpiar_precio <- function(x) {
  convertir <- function(valor) {
    if (is.na(valor)) return(NA_real_)
    valor <- gsub("[^0-9,.-]", "", as.character(valor))
    if (!nzchar(valor)) return(NA_real_)
    if (grepl(",", valor, fixed = TRUE)) {
      valor <- gsub(".", "", valor, fixed = TRUE)
      valor <- sub(",", ".", valor, fixed = TRUE)
    } else if (grepl("^\\d{1,3}(\\.\\d{3})+$", valor)) {
      valor <- gsub(".", "", valor, fixed = TRUE)
    }
    suppressWarnings(as.numeric(valor))
  }
  vapply(x, convertir, numeric(1), USE.NAMES = FALSE)
}

# Valida un lote de observaciones de un comercio.
# Devuelve list(validas = data.frame, rechazadas = data.frame, resumen = data.frame).
validar_observaciones <- function(datos, con = NULL, id_ejecucion = NULL) {
  if (is.null(datos) || nrow(datos) == 0) {
    return(list(
      validas = datos,
      rechazadas = data.frame(id_comercio = character(), sku_comercio = character(),
                              texto_original = character(), precio_cop = numeric(),
                              motivo = character(), detalle = character()),
      resumen = data.frame(motivo = character(), n = integer())
    ))
  }

  n <- nrow(datos)
  motivo <- rep(NA_character_, n)
  detalle <- rep(NA_character_, n)

  marcar <- function(condicion, texto_motivo, texto_detalle = NA_character_) {
    idx <- which(condicion & is.na(motivo))
    if (length(idx) > 0) {
      motivo[idx] <<- texto_motivo
      detalle[idx] <<- texto_detalle
    }
  }

  vacio <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))

  marcar(vacio(datos$id_comercio) | vacio(datos$sku_comercio) |
           vacio(datos$texto_original) | vacio(datos$url_producto) |
           vacio(datos$fecha_consulta),
         "campos_obligatorios",
         "Falta comercio, SKU, texto original, URL o fecha de consulta.")

  marcar(!is.na(datos$url_producto) & !grepl("^https?://", datos$url_producto),
         "url_valida", "La URL no empieza por http:// o https://.")

  marcar(!vacio(datos$fecha_consulta) &
           !grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}-05:00$", datos$fecha_consulta),
         "fecha_iso", "La fecha no está en ISO 8601 con hora de Colombia.")

  marcar(!datos$estado_disponibilidad %in% c("disponible", "agotado", "no_observado"),
         "disponibilidad_valida", "Estado de disponibilidad desconocido.")

  disponibles <- datos$estado_disponibilidad == "disponible"
  marcar(disponibles & (is.na(datos$precio_cop) | !is.finite(datos$precio_cop) |
                          datos$precio_cop <= 0),
         "precio_positivo", "Producto disponible sin precio numérico mayor que cero.")

  marcar(!is.na(datos$precio_lista_cop) & !is.na(datos$precio_cop) &
           datos$precio_lista_cop < datos$precio_cop,
         "precio_lista_coherente", "El precio de lista es menor que el precio pagado.")

  marcar(!is.na(datos$contenido_total) & datos$contenido_total <= 0,
         "contenido_positivo", "El contenido total es menor o igual que cero.")

  marcar(!is.na(datos$unidad_normalizada) &
           !datos$unidad_normalizada %in% c("g", "mL", "unidad"),
         "unidad_normalizada", "Unidad distinta de g, mL o unidad.")

  clave <- paste(datos$id_comercio, datos$sku_comercio, sep = "|")
  marcar(duplicated(clave), "duplicado_ejecucion",
         "El mismo anuncio aparece dos veces en el lote.")

  if (!is.null(con) && !is.null(id_ejecucion)) {
    previos <- DBI::dbGetQuery(
      con,
      "SELECT id_comercio, sku_comercio FROM observaciones WHERE id_ejecucion = ?",
      params = list(id_ejecucion)
    )
    clave_previa <- paste(previos$id_comercio, previos$sku_comercio, sep = "|")
    marcar(clave %in% clave_previa, "duplicado_ejecucion",
           "El anuncio ya existe en la base para esta ejecución.")
  }

  validas <- datos[is.na(motivo), , drop = FALSE]
  rechazadas <- datos[!is.na(motivo), , drop = FALSE]
  rechazadas <- data.frame(
    id_comercio = rechazadas$id_comercio,
    sku_comercio = rechazadas$sku_comercio,
    texto_original = rechazadas$texto_original,
    precio_cop = rechazadas$precio_cop,
    motivo = motivo[!is.na(motivo)],
    detalle = detalle[!is.na(motivo)],
    stringsAsFactors = FALSE
  )

  resumen <- if (nrow(rechazadas) == 0) {
    data.frame(motivo = character(), n = integer())
  } else {
    tabla <- as.data.frame(table(motivo = rechazadas$motivo), stringsAsFactors = FALSE)
    names(tabla) <- c("motivo", "n")
    tabla[tabla$n > 0, , drop = FALSE]
  }

  list(validas = validas, rechazadas = rechazadas, resumen = resumen)
}
