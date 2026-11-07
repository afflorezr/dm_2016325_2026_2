# validacion.R: reglas que debe cumplir una observacion antes de entrar a la base.
# No toca la base: recibe tablas y devuelve tablas.
suppressPackageStartupMessages({ library(pointblank); library(dplyr) })

RX_FECHA_ISO <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$"

# regla (etiqueta del paso) -> motivo legible que se guarda en `rechazos`
MOTIVOS <- c(
  precio_real_positivo  = "precio real ausente, no numerico o no mayor que cero",
  precio_lista_positivo = "precio de lista ausente, no numerico o no mayor que cero",
  precio_real_le_lista  = "el precio real es mayor que el precio de lista",
  comercio_presente     = "comercio ausente",
  sku_presente          = "sku ausente",
  url_presente          = "url ausente",
  fecha_presente        = "fecha y hora de consulta ausente",
  fecha_formato_iso     = "fecha y hora de consulta sin formato ISO 8601 con zona",
  no_duplicada          = "observacion duplicada en la misma ejecucion"
)

# obs      : una fila por observacion (columnas del scraper: comercio, sku, nombres, url,
#            fecha_consulta, id_ejecucion, precio_lista_cop, precio_real_cop)
# esperados: tabla (comercio, sku) con los productos comparables que cada comercio debe traer
# Devuelve: validas, rechazadas (una fila por regla incumplida), faltantes, agentes (informes pointblank)
validar_observaciones <- function(obs, esperados) {
  obs <- obs |>
    mutate(.fila = row_number(),
           sku   = trimws(sku),
           .dup  = as.integer(!is.na(sku) & duplicated(paste(comercio, sku, id_ejecucion))))
  
  # --- reglas por fila ---
  agente <- create_agent(tbl = obs, tbl_name = "observaciones", label = "Validacion de observaciones") |>
    col_vals_gt(columns = "precio_real_cop",  value = 0, label = "precio_real_positivo") |>
    col_vals_gt(columns = "precio_lista_cop", value = 0, label = "precio_lista_positivo") |>
    col_vals_lte(columns = "precio_real_cop", value = vars(precio_lista_cop), label = "precio_real_le_lista") |>
    col_vals_not_null(columns = "comercio",       label = "comercio_presente") |>
    col_vals_not_null(columns = "sku",            label = "sku_presente") |>
    col_vals_not_null(columns = "url",            label = "url_presente") |>
    col_vals_not_null(columns = "fecha_consulta", label = "fecha_presente") |>
    col_vals_regex(columns = "fecha_consulta", regex = RX_FECHA_ISO, label = "fecha_formato_iso") |>
    col_vals_equal(columns = ".dup", value = 0L, label = "no_duplicada") |>
    interrogate()
  
  etiquetas <- agente$validation_set$label
  n_fallidas <- agente$validation_set$n_failed
  fallos <- lapply(seq_along(etiquetas), function(i) {
    if (is.na(n_fallidas[i]) || n_fallidas[i] == 0) return(NULL)   # sin fallos no hay extracto
    tibble(.fila = get_data_extracts(agente, i = i)$.fila, regla = etiquetas[i])
  }) |> bind_rows()
  if (nrow(fallos) == 0) fallos <- tibble(.fila = integer(), regla = character())
  
  rechazadas <- fallos |>
    left_join(obs, by = ".fila") |>
    transmute(codigo_corrida = as.character(id_ejecucion), comercio, sku, nombre = nombres,
              precio_texto = as.character(precio_real_cop), regla,
              motivo = unname(MOTIVOS[regla]))
  validas <- obs |> filter(!.fila %in% fallos$.fila) |> select(-.fila, -.dup)
  
  # --- cobertura: los productos esperados deben estar en cada (ejecucion, comercio) ---
  cobertura <- validas |>
    distinct(id_ejecucion, comercio) |>
    inner_join(esperados, by = "comercio", relationship = "many-to-many") |>
    left_join(validas |> distinct(id_ejecucion, comercio, sku) |> mutate(visto = 1L),
              by = c("id_ejecucion", "comercio", "sku")) |>
    mutate(presente = coalesce(visto, 0L)) |>
    select(id_ejecucion, comercio, sku, presente)
  
  agente_cob <- create_agent(tbl = cobertura, tbl_name = "cobertura",
                             label = "Productos comparables presentes") |>
    col_vals_equal(columns = "presente", value = 1L, label = "producto_comparable_presente") |>
    interrogate()
  
  list(validas = validas, rechazadas = rechazadas,
       faltantes = cobertura |> filter(presente == 0L) |> select(-presente),
       agentes = list(filas = agente, cobertura = agente_cob))
}

# ---- Disponibilidad ----
# Textos con que el sitio indica que un producto no esta disponible (".{1,2}" cubre una tilde en UTF-8)
RX_AGOTADO <- "(?i)(av.{1,2}same cuando est.{1,2} disponible|agotad[oa]|sin existencias|sin stock)"

es_agotado_texto <- function(texto) grepl(RX_AGOTADO, texto, perl = TRUE)

# Tarjetas agotadas segun el sitio: sin precio, no son observaciones.
# Devuelve agotados (para la tabla `agotados`) y resto (lo que sigue a validar_observaciones)
separar_agotados <- function(obs) {
  ago <- es_agotado_texto(obs$texto_original_anuncio) & is.na(obs$precio_real_cop)
  list(agotados = obs[ago, ], resto = obs[!ago, ])
}

# Agrega `disponibilidad` a observaciones validas: agotado solo si el texto lo dice
marcar_disponibilidad <- function(obs) {
  mutate(obs, disponibilidad = ifelse(es_agotado_texto(texto_original_anuncio), "agotado", "disponible"))
}