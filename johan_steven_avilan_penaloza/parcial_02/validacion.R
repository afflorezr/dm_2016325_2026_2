# validacion.R — Taller 2
# Reglas explícitas que debe cumplir una observación antes de entrar a la base.
# Las observaciones que no las cumplen NO se insertan: se registran en la tabla
# `rechazadas` con el motivo. (Módulo 1, sección 3.4 del enunciado.)

library(dplyr)
library(stringr)
library(tibble)

es_vacio <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))

# Valida fila por fila y separa válidas de rechazadas.
# Reglas (se aplica la primera que falle, en este orden):
#   1. comercio, sku, nombre, URL y fecha-hora de consulta presentes
#   2. precio, si existe, numérico y > 0
#   3. precio ausente solo se acepta si el sitio marca el producto como agotado
#      (disponible = 0); un dato ausente queda como NULL, nunca se inventa
#   4. sin duplicados del mismo (comercio, sku) dentro de la misma ejecución
validar_observaciones <- function(df) {
  vacias <- tibble(comercio = character(), sku = character(),
                   nombre_original = character(), url = character(),
                   precio = numeric(), fecha_hora_consulta = character(),
                   motivo = character())
  if (nrow(df) == 0) return(list(validas = df, rechazadas = vacias))

  for (col in c("comercio", "sku", "nombre_original", "url", "precio",
                "disponible", "fecha_hora_consulta")) {
    if (!col %in% names(df)) df[[col]] <- NA
  }
  precio <- suppressWarnings(as.numeric(df$precio))
  motivo <- rep(NA_character_, nrow(df))
  marcar <- function(condicion, texto) {
    idx <- which(is.na(motivo) & condicion %in% TRUE)
    motivo[idx] <<- texto
  }

  marcar(es_vacio(df$comercio),            "Comercio ausente")
  marcar(es_vacio(df$sku),                 "SKU ausente")
  marcar(es_vacio(df$nombre_original),     "Nombre del anuncio ausente")
  marcar(es_vacio(df$url),                 "URL ausente")
  marcar(es_vacio(df$fecha_hora_consulta), "Fecha y hora de consulta ausentes")
  marcar(!is.na(df$precio) & is.na(precio), "Precio no numérico")
  marcar(!is.na(precio) & precio <= 0,     "Precio menor o igual a cero")
  marcar(is.na(precio) & (is.na(df$disponible) | df$disponible != 0),
         "Sin precio y no marcado como agotado por el sitio")
  clave <- paste(df$comercio, df$sku, sep = "\r")
  marcar(duplicated(clave),                "Duplicado en la misma ejecución")

  ok <- is.na(motivo)
  rech <- tibble(comercio = as.character(df$comercio),
                 sku = as.character(df$sku),
                 nombre_original = as.character(df$nombre_original),
                 url = as.character(df$url),
                 precio = precio,
                 fecha_hora_consulta = as.character(df$fecha_hora_consulta),
                 motivo = motivo)[!ok, ]
  list(validas = df[ok, ], rechazadas = rech)
}

# Presencia de los ocho productos comparables en un comercio.
# Devuelve los id_comparable AUSENTES (o presentes pero sin precio, si
# exigir_precio = TRUE, porque sin precio no se pueden comparar).
#   La Rebaja y Locatel: por EAN. Farmatodo: por expresión regular del nombre.
comparables_faltantes <- function(df, comercio,
                                  especificacion = especificacion_comparables,
                                  exigir_precio = TRUE) {
  if (nrow(df) == 0) return(especificacion$id_comparable)
  if (exigir_precio) df <- df[!is.na(df$precio), ]
  presente <- vapply(seq_len(nrow(especificacion)), function(i) {
    e <- especificacion[i, ]
    if (comercio == "Farmatodo") {
      any(str_detect(df$nombre_original, regex(e$patron_farmatodo, ignore_case = TRUE)),
          na.rm = TRUE)
    } else {
      any(!is.na(df$ean) & df$ean == e$ean)
    }
  }, logical(1))
  especificacion$id_comparable[!presente]
}

# Informe con pointblank (opcional): las mismas reglas en forma de agente, útil
# para mostrar o documentar la validación. La decisión de insertar o rechazar
# fila por fila la toma validar_observaciones(), porque pointblank reporta
# resultados agregados por regla.
informe_validacion <- function(df) {
  if (!requireNamespace("pointblank", quietly = TRUE)) return(NULL)
  pointblank::create_agent(tbl = as.data.frame(df), label = "Validación de observaciones") |>
    pointblank::col_vals_gt(columns = "precio", value = 0, na_pass = TRUE) |>
    pointblank::col_vals_not_null(columns = c("comercio", "sku", "url", "fecha_hora_consulta")) |>
    pointblank::rows_distinct(columns = c("comercio", "sku")) |>
    pointblank::interrogate()
}
