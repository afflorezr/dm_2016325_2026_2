# =============================================================================
# validacion.R  -  Reglas de validacion antes de insertar en SQLite (Modulo 1)
# -----------------------------------------------------------------------------
# Ninguna observacion entra a la base sin pasar por estas reglas. Las filas que
# no superan la validacion NO se insertan: se registran en
# observaciones_rechazadas con su motivo (ver registrar_rechazadas en scraper.R).
# Se carga automaticamente desde scraper.R; tambien puede cargarse solo.
# Reglas: precio numerico > 0; comercio/URL/fecha presentes; sin duplicados en
# la misma ejecucion; precio_antes coherente; disponibilidad en el catalogo;
# fecha ISO 8601 de Colombia. Se auditan ademas con pointblank.
# =============================================================================

# Catalogo de estados de disponibilidad admitidos:
DISPONIBILIDADES <- c("disponible", "agotado")

# ----------------------------------------------------------------------------
# 7. VALIDACIÓN POR FILA + AUDITORÍA pointblank
# ----------------------------------------------------------------------------
RX_FECHA_ISO <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}-05:00$"

validar_observaciones <- function(df) {
  n_in <- nrow(df)
  vacio <- list(validas = df[0, , drop = FALSE] |> as_tibble(),
                rechazadas = df[0, , drop = FALSE] |> as_tibble(),
                n_rechazadas = 0L, n_duplicados = 0L, motivos = character())
  if (n_in == 0) return(vacio)
  if (!is.numeric(df$precio_cop)) stop("precio_cop no es numérico", call. = FALSE)

  df_u  <- distinct(df, comercio, url, fecha_consulta, .keep_all = TRUE)
  n_dup <- n_in - nrow(df_u)

  reglas <- list(
    campos_obligatorios = !is.na(df_u$comercio) & !is.na(df_u$producto) &
      !is.na(df_u$texto_original) & !is.na(df_u$url) & !is.na(df_u$fecha_consulta),
    precio_positivo     = !is.na(df_u$precio_cop) & df_u$precio_cop > 0,
    precio_antes_valido = is.na(df_u$precio_antes) |
      (!is.na(df_u$precio_antes) & df_u$precio_antes >= df_u$precio_cop),
    promocion_0_1       = df_u$en_promocion %in% c(0L, 1L),
    unidad_valida       = is.na(df_u$contenido_unidad) | df_u$contenido_unidad %in% c("ml", "g", "unidad"),
    contenido_positivo  = is.na(df_u$contenido_valor) | df_u$contenido_valor > 0,
    disponibilidad_ok   = is.na(df_u$disponibilidad) | df_u$disponibilidad %in% DISPONIBILIDADES,
    fecha_iso_colombia  = str_detect(df_u$fecha_consulta, RX_FECHA_ISO) %in% TRUE
  )
  reglas <- lapply(reglas, function(r) r %in% TRUE)
  ok <- Reduce(`&`, reglas)

  motivos <- character()
  for (nm in names(reglas)) {
    k <- sum(!reglas[[nm]])
    if (k > 0) motivos <- c(motivos, sprintf("%s: %d filas descartadas", nm, k))
  }
  if (n_dup > 0) motivos <- c(motivos, sprintf("duplicados exactos descartados: %d", n_dup))

  validas <- df_u[ok, , drop = FALSE] |> as_tibble()

  # Filas rechazadas con el motivo por fila (se registran en observaciones_rechazadas)
  fallas <- map_chr(seq_len(nrow(df_u)), function(i) {
    malos <- names(reglas)[map_lgl(reglas, ~ !.x[i])]
    if (length(malos)) paste(malos, collapse = "; ") else NA_character_
  })
  rechazadas <- df_u[!ok, , drop = FALSE] |> as_tibble() |>
    mutate(motivo = fallas[!ok])

  if (nrow(validas) > 0) {
    aud <- tryCatch({
      v2 <- validas |> mutate(unidad_ok = is.na(contenido_unidad) |
                                contenido_unidad %in% c("ml", "g", "unidad"))
      ag <- pointblank::create_agent(tbl = v2, tbl_name = "observaciones",
                                     label = "Auditoría posterior a validación") |>
        pointblank::col_vals_not_null(columns = c(comercio, producto, texto_original, url, fecha_consulta)) |>
        pointblank::col_vals_gt(columns = precio_cop, value = 0) |>
        pointblank::col_vals_in_set(columns = en_promocion, set = c(0L, 1L)) |>
        pointblank::col_vals_in_set(columns = unidad_ok, set = TRUE) |>
        pointblank::col_vals_regex(columns = fecha_consulta, regex = RX_FECHA_ISO) |>
        pointblank::rows_distinct(columns = c(comercio, url, fecha_consulta)) |>
        pointblank::interrogate()
      sum(ag$validation_set$n_failed, na.rm = TRUE)
    }, error = function(e) NA_integer_)
    if (!is.na(aud) && aud > 0)
      motivos <- c(motivos, sprintf("auditoría pointblank: %d fallos inesperados", aud))
  }

  list(validas = validas, rechazadas = rechazadas,
       n_rechazadas = nrow(df_u) - nrow(validas),
       n_duplicados = n_dup, motivos = motivos)
}

