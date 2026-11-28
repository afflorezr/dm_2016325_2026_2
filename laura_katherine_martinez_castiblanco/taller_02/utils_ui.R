# =============================================================================
# utils_ui.R · Utilidades de presentación (colores por comercio, formatos, componentes)
# =============================================================================
suppressPackageStartupMessages({ library(shiny); library(bslib); library(highcharter); library(DT) })

# Cada comercio conserva SIEMPRE el mismo color en toda la aplicación
COLOR_COMERCIO <- c("Éxito" = "#E8A200", "Carulla" = "#0E8F6B",
                    "PriceSmart" = "#8A5CF6", "Supermercado Comunal" = "#2F6FDE")
color_de <- function(comercios) {
  col <- unname(COLOR_COMERCIO[comercios]); col[is.na(col)] <- "#7A8599"; col
}

# ---- Formatos (COP, es-CO) ----------------------------------------------------
fmt_cop <- function(x, dec = 0) ifelse(is.na(x), "—", paste0("$ ", formatC(x, format = "f", digits = dec, big.mark = ".", decimal.mark = ",")))
fmt_num <- function(x, dec = 0) ifelse(is.na(x), "—", formatC(x, format = "f", digits = dec, big.mark = ".", decimal.mark = ","))
fmt_pct <- function(x, dec = 1) ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = dec, decimal.mark = ","), " %"))
fmt_fecha <- function(x) {
  d <- as.Date(substr(x, 1, 10)); ifelse(is.na(d), "—", format(d, "%d-%m-%Y"))
}
# "2026-11-08T17:45:07-05:00" -> milisegundos epoch (para ejes datetime de Highcharts)
iso_a_ms <- function(x) {
  t <- as.POSIXct(sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", x), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  as.numeric(t) * 1000
}

DT_ES <- list(search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas", info = "Filas _START_ a _END_ de _TOTAL_",
              infoEmpty = "Sin filas", infoFiltered = "(filtrado de _MAX_)", zeroRecords = "Sin coincidencias",
              emptyTable = "No hay datos para mostrar", paginate = list(previous = "Anterior", `next` = "Siguiente"))

# ---- Componentes ----------------------------------------------------------------
kpi <- function(titulo, valor_id, icono, pie_id, tema = NULL) {
  value_box(title = titulo, value = textOutput(valor_id, inline = TRUE), showcase = icon(icono),
            p(class = "kpi-pie", textOutput(pie_id, inline = TRUE)), theme = tema, class = "kpi-card")
}
aviso <- function(texto, tipo = "info") div(class = paste0("alert alert-", tipo, " py-2 mb-2"), role = "alert", texto)
tarjeta <- function(titulo, ..., ayuda = NULL, alto = NULL) {
  card(full_screen = TRUE, height = alto,
       card_header(class = "d-flex justify-content-between align-items-center", span(titulo),
                   if (!is.null(ayuda)) tooltip(icon("circle-info"), ayuda)),
       card_body(...))
}
# Gráfico base: fondo transparente, tipografía heredada (sirve en modo claro y oscuro)
hc_base <- function(hc, titulo_y = NULL, formato_y = "{value}") {
  hc |>
    hc_chart(backgroundColor = "transparent", style = list(fontFamily = "inherit")) |>
    hc_yAxis(title = list(text = titulo_y), labels = list(format = formato_y), gridLineColor = "rgba(128,128,128,.25)") |>
    hc_legend(itemStyle = list(fontWeight = "500")) |>
    hc_credits(enabled = FALSE) |>
    hc_exporting(enabled = TRUE)
}
vacio <- function(df, msg = "No hay datos con los filtros elegidos. Amplíe la selección o restablezca los filtros.") {
  validate(need(!is.null(df) && nrow(df) > 0, msg))
}
periodo_texto <- function(f, corridas) {
  if (is.null(f$corridas)) return(sprintf("todas las ejecuciones (%d)", nrow(corridas)))
  if (length(f$corridas) == 1) {
    i <- match(f$corridas, corridas$id_corrida)
    return(paste0("ejecución del ", fmt_fecha(corridas$fecha_hora[i]), " (", f$corridas, ")"))
  }
  sprintf("%d ejecuciones", length(f$corridas))
}

# Operador "si es nulo" (R >= 4.4 lo trae; se define por compatibilidad)
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
