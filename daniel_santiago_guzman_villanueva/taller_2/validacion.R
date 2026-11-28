# =============================================================================
# validacion.R — Taller 2, Módulo 1 (sección 3.4)
#
# Ninguna observación entra a la base sin validarse. Las reglas están escritas
# de forma explícita en REGLAS_VALIDACION: cada una es una condición que debe
# cumplir la fila. Las filas que incumplen al menos una regla NO se insertan:
# se devuelven en `rechazadas` (una fila por regla incumplida) y scraper.R las
# guarda en la tabla observaciones_rechazadas.
#
# Decisión sobre precios ausentes: la sección 3.1 exige que un dato que no se
# pudo extraer quede como ausente (NULL), y la 3.4 que el precio sea numérico
# y mayor que cero. Se combinan así: si hay precio, debe ser numérico y > 0;
# un precio ausente solo se acepta cuando el propio sitio marca el producto
# como agotado (Colsubsidio publica los agotados sin precio). Un producto
# disponible sin precio se rechaza.
# =============================================================================

REGLAS_VALIDACION <- tibble::tribble(
  ~regla,                       ~motivo,
  "precio_numerico",            "El precio no es numérico",
  "precio_positivo",            "El precio publicado es menor o igual a cero",
  "precio_presente_disponible", "Producto disponible sin precio publicado",
  "comercio_presente",          "Falta el comercio",
  "sku_presente",               "Falta el identificador del anuncio (sku)",
  "url_presente",               "Falta la URL del anuncio o no es http(s)",
  "fecha_presente",             "Falta la fecha y hora de consulta o no está en ISO 8601",
  "sin_duplicados",             "Observación duplicada en la misma ejecución (mismo comercio y sku)"
)

PATRON_FECHA_ISO <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$"

# Devuelve una matriz lógica: TRUE = la fila CUMPLE la regla
evaluar_reglas <- function(d) {
  vacio <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))
  precio_num <- suppressWarnings(as.numeric(d$precio))
  cbind(
    precio_numerico            = is.na(d$precio) | (is.numeric(d$precio) & !is.na(precio_num)),
    precio_positivo            = is.na(precio_num) | precio_num > 0,
    precio_presente_disponible = !(is.na(d$precio) & d$disponible %in% 1L),
    comercio_presente          = !vacio(d$comercio),
    sku_presente               = !vacio(d$sku),
    url_presente               = !vacio(d$url) & grepl("^https?://", d$url),
    fecha_presente             = !vacio(d$fecha_hora_consulta) &
                                   grepl(PATRON_FECHA_ISO, d$fecha_hora_consulta),
    # la primera aparición se conserva; las repeticiones se rechazan
    sin_duplicados             = !duplicated(d[, c("comercio", "sku")])
  )
}

# datos: tabla común de scraper.R (una ejecución, un comercio o varios)
# Devuelve list(validas, rechazadas, resumen)
validar_observaciones <- function(datos, id_ejecucion) {
  if (nrow(datos) == 0) {
    return(list(validas = datos,
                rechazadas = tibble::tibble(id_ejecucion = character(), comercio = character(),
                                            sku = character(), regla = character(),
                                            motivo = character(), precio = numeric(),
                                            url = character(), fecha_hora_consulta = character(),
                                            texto_original = character()),
                resumen = tibble::tibble(regla = REGLAS_VALIDACION$regla, incumplen = 0L)))
  }
  cumple <- evaluar_reglas(datos)
  stopifnot(identical(colnames(cumple), REGLAS_VALIDACION$regla))
  ok <- rowSums(!cumple) == 0

  fallas <- which(!cumple, arr.ind = TRUE)
  rechazadas <- tibble::tibble(
    fila  = fallas[, "row"],
    regla = colnames(cumple)[fallas[, "col"]]
  ) |>
    dplyr::left_join(REGLAS_VALIDACION, by = "regla") |>
    dplyr::mutate(
      id_ejecucion        = id_ejecucion,
      comercio            = as.character(datos$comercio[fila]),
      sku                 = as.character(datos$sku[fila]),
      precio              = suppressWarnings(as.numeric(datos$precio[fila])),
      url                 = as.character(datos$url[fila]),
      fecha_hora_consulta = as.character(datos$fecha_hora_consulta[fila]),
      texto_original      = as.character(datos$texto_original[fila])
    ) |>
    dplyr::select(id_ejecucion, comercio, sku, regla, motivo, precio, url,
                  fecha_hora_consulta, texto_original)

  list(
    validas    = datos[ok, , drop = FALSE],
    rechazadas = rechazadas,
    resumen    = tibble::tibble(regla = colnames(cumple),
                                incumplen = as.integer(colSums(!cumple)))
  )
}

# Presencia de los productos comparables (sección 3.4, último punto).
# esperados: comercio, sku, id_producto de los comparables ya conocidos.
# Devuelve los id_producto que el comercio debía traer y no aparecen entre
# las observaciones válidas (vector vacío si están todos o si aún no hay
# comparables definidos, p. ej. en la primera ejecución sobre una base nueva).
verificar_comparables <- function(validas, esperados, comercio) {
  esp <- esperados[esperados$comercio == comercio, , drop = FALSE]
  if (nrow(esp) == 0) return(character())
  presentes <- unique(esp$id_producto[esp$sku %in% validas$sku])
  sort(setdiff(unique(esp$id_producto), presentes))
}
