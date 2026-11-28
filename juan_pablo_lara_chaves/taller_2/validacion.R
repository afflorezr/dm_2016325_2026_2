# validacion.R | reglas antes de insertar (Taller 2, §3.4 y Anexo C)
library(pointblank); library(dplyr); library(tidyr)

validar_observaciones <- function(datos) {
  d <- datos |>
    group_by(comercio, producto_comercio, ejecucion_id) |>
    mutate(.dup = row_number() > 1) |> ungroup() |>
    mutate(.regla = case_when(
      is.na(precio) | precio <= 0                      ~ "precio_positivo",
      is.na(comercio) | is.na(url) | is.na(fecha_hora) ~ "campos_obligatorios",
      .dup                                             ~ "duplicado_en_ejecucion"),
      .motivo = case_when(
        .regla == "precio_positivo"        ~ "El precio falta o no es mayor que cero",
        .regla == "campos_obligatorios"    ~ "Falta comercio, URL o fecha y hora de consulta",
        .regla == "duplicado_en_ejecucion" ~ "Anuncio repetido en la misma ejecución"))
  
  agente <- create_agent(tbl = select(datos, comercio, producto_comercio, ejecucion_id, precio, url, fecha_hora),
                         label = "Validación de observaciones") |>
    col_vals_not_null(columns = c(precio)) |>
    col_vals_gt(columns = c(precio), value = 0, na_pass = FALSE) |>
    col_vals_not_null(columns = c(comercio, url, fecha_hora)) |>
    rows_distinct(columns = c(comercio, producto_comercio, ejecucion_id)) |>
    interrogate()
  
  list(validas    = d |> filter(is.na(.regla)) |> select(-.dup, -.regla, -.motivo),
       rechazadas = d |> filter(!is.na(.regla)) |> select(-.dup),
       agente     = agente)
}

# Los 8 comparables deben estar en cada comercio
verificar_comparables <- function(datos, productos, comercios = c("farmatodo", "locatel", "ortopedicos_futuro")) {
  esperados <- expand_grid(producto_id = productos, comercio = comercios)
  hay <- datos |> filter(comparable == 1) |> distinct(producto_id, comercio)
  faltan <- anti_join(esperados, hay, by = c("producto_id", "comercio"))
  list(ok = nrow(faltan) == 0, faltan = faltan)
}