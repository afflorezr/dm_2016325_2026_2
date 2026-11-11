# Reciben tablas ya calculadas por db.R; aquí no hay SQL ni lectura de la base.

suppressPackageStartupMessages(library(highcharter))

# Un color fijo por comercio en toda la aplicación (paleta apta para daltonismo, la del Taller 1)
COLOR_COMERCIO <- c(larebaja = "#D55E00", cafam = "#0072B2", locatel = "#009E73")
NOMBRE_COMERCIO <- c(larebaja = "La Rebaja", cafam = "Droguerías Cafam", locatel = "Locatel Colombia")

local({
  lang <- getOption("highcharter.lang")
  lang$thousandsSep <- "."; lang$decimalPoint <- ","
  lang$months <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
                   "septiembre", "octubre", "noviembre", "diciembre")
  lang$shortMonths <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
  lang$weekdays <- c("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")
  lang$resetZoom <- "Restablecer zoom"
  lang$noData <- "Sin datos para mostrar"
  options(highcharter.lang = lang)
})

cop <- function(x, d = 0) ifelse(is.na(x), "—",
  paste0("$", formatC(round(x, d), format = "f", digits = d, big.mark = ".", decimal.mark = ",")))
num <- function(x, d = 0) ifelse(is.na(x), "—", formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))
pct <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), " %"))
abreviar <- function(x, n = 48) ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "…"), x)
fecha_legible <- function(ejecucion_id) {
  t <- as.POSIXct(ejecucion_id, format = "%Y%m%dT%H%M%S", tz = "America/Bogota")
  ifelse(is.na(t), ejecucion_id, format(t, "%d/%m/%Y %H:%M"))
}
# ms desde 1970 para el eje de fechas de Highcharts (a partir de ISO 8601 con zona -05:00)
a_milisegundos <- function(iso) {
  t <- as.POSIXct(sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", iso), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  as.numeric(t) * 1000
}

# Estilo común: misma tipografía y tonos que la interfaz (app.R)
base_hc <- function(titulo, subtitulo = NULL) {
  highchart() |>
    hc_chart(backgroundColor = "transparent", spacingTop = 14,
             style = list(fontFamily = "Inter, system-ui, sans-serif")) |>
    hc_title(text = titulo, align = "left",
             style = list(fontSize = "15px", fontWeight = "600", color = "#12343B",
                          fontFamily = "Outfit, system-ui, sans-serif")) |>
    hc_subtitle(text = subtitulo, align = "left", style = list(color = "#5E6E73", fontSize = "12px")) |>
    hc_legend(itemStyle = list(color = "#1F2D33", fontWeight = "500")) |>
    hc_tooltip(backgroundColor = "#FFFFFF", borderColor = "#D5DEDB", borderRadius = 8,
               style = list(color = "#1F2D33")) |>
    hc_credits(enabled = TRUE, text = "Fuente: scraping propio (raw/) · precios en COP",
               style = list(color = "#8A9A9E")) |>
    hc_exporting(enabled = TRUE)
}

puntos <- function(x, y, extra = NULL) {
  ok <- !is.na(y)
  lapply(which(ok), function(i) c(list(x = x[i], y = y[i]), if (!is.null(extra)) lapply(extra, `[`, i)))
}

grafico_evolucion <- function(s, titulo) {
  s$ms <- a_milisegundos(s$fecha_hora)
  hc <- base_hc(titulo, "Precio de venta en cada ejecución del scraper (COP)") |>
    hc_xAxis(type = "datetime", title = list(text = "Fecha y hora de consulta")) |>
    hc_yAxis(title = list(text = "Precio (COP)"), labels = list(format = "${value:,.0f}")) |>
    hc_tooltip(shared = FALSE, xDateFormat = "%d/%m/%Y %H:%M", valuePrefix = "$", valueDecimals = 0)
  for (cm in intersect(names(COLOR_COMERCIO), unique(s$comercio))) {
    d <- s[s$comercio == cm, ]
    hc <- hc |> hc_add_series(name = NOMBRE_COMERCIO[[cm]], type = "line", color = COLOR_COMERCIO[[cm]],
                              marker = list(enabled = TRUE, radius = 5), data = puntos(d$ms, d$precio))
  }
  hc
}

# Precio por unidad de contenido (una sola unidad: mL, g o unidad)
grafico_precio_unitario <- function(d, unidad) {
  prod <- unique(d[order(d$descripcion), c("producto_id", "descripcion")])
  cats <- abreviar(prod$descripcion, 55)
  hc <- base_hc(sprintf("Precio por %s en presentaciones comparables", unidad),
                sprintf("Mismo producto (EAN y contenido) en cada comercio · COP por %s", unidad)) |>
    hc_chart(type = "bar") |>
    hc_xAxis(categories = cats, title = list(text = NULL)) |>
    hc_yAxis(title = list(text = sprintf("COP por %s", unidad))) |>
    hc_tooltip(valuePrefix = "$", valueDecimals = 1, valueSuffix = paste0(" por ", unidad))
  for (cm in intersect(names(COLOR_COMERCIO), unique(d$comercio))) {
    x <- d[d$comercio == cm, ]
    idx <- match(x$producto_id, prod$producto_id) - 1L
    hc <- hc |> hc_add_series(name = NOMBRE_COMERCIO[[cm]], color = COLOR_COMERCIO[[cm]],
                              data = puntos(idx, round(x$precio_por_unidad, 1)))
  }
  hc
}

# Distribución de precios por comercio (cinco números calculados en SQL)
grafico_distribucion <- function(b, log = FALSE) {
  hc <- base_hc("Distribución de precios de la categoría por comercio",
                "Mínimo, cuartiles, mediana y máximo de las observaciones filtradas (COP)") |>
    hc_chart(type = "boxplot") |>
    hc_xAxis(categories = unname(NOMBRE_COMERCIO[b$comercio]), title = list(text = NULL)) |>
    hc_yAxis(title = list(text = "Precio (COP)"), type = if (log) "logarithmic" else "linear",
             labels = list(format = "${value:,.0f}")) |>
    hc_legend(enabled = FALSE) |>
    hc_tooltip(headerFormat = "<b>{point.key}</b><br/>",
               pointFormat = paste0("Observaciones: {point.n}<br/>Máximo: ${point.high:,.0f}<br/>",
                                    "Q3: ${point.q3:,.0f}<br/>Mediana: ${point.median:,.0f}<br/>",
                                    "Q1: ${point.q1:,.0f}<br/>Mínimo: ${point.low:,.0f}"))
  datos <- lapply(seq_len(nrow(b)), function(i)
    list(x = i - 1L, low = b$minimo[i], q1 = b$q1[i], median = b$mediana[i], q3 = b$q3[i],
         high = b$maximo[i], n = b$n[i], color = COLOR_COMERCIO[[b$comercio[i]]],
         fillColor = paste0(COLOR_COMERCIO[[b$comercio[i]]], "33")))
  hc |> hc_add_series(name = "Precio", data = datos, lineWidth = 2, medianWidth = 3)
}

# Gráfico libre: ¿cuánto cuesta cada tableta según la marca? (mismo principio activo y concentración)
grafico_dosis <- function(d, principio, concentracion) {
  orden <- aggregate(minimo_por_unidad ~ marca, d, min)
  orden <- orden[order(orden$minimo_por_unidad), ]
  hc <- base_hc(sprintf("¿Cuánto cuesta una tableta o cápsula de %s %s según la marca?",
                        tolower(gsub("_", " ", principio)), concentracion),
                "Precio mínimo por unidad (tableta, cápsula o sobre) de cada marca en cada comercio · COP") |>
    hc_chart(type = "column") |>
    hc_xAxis(categories = orden$marca, title = list(text = "Marca (ordenadas de la más barata a la más cara)")) |>
    hc_yAxis(title = list(text = "COP por unidad")) |>
    hc_tooltip(valuePrefix = "$", valueDecimals = 0, valueSuffix = " por unidad")
  for (cm in intersect(names(COLOR_COMERCIO), unique(d$comercio))) {
    x <- d[d$comercio == cm, ]
    hc <- hc |> hc_add_series(name = NOMBRE_COMERCIO[[cm]], color = COLOR_COMERCIO[[cm]],
                              data = puntos(match(x$marca, orden$marca) - 1L, round(x$minimo_por_unidad)))
  }
  hc
}

# Cambios de precio entre dos ejecuciones: variación porcentual por anuncio
grafico_cambios <- function(d, umbral) {
  d <- d[d$tipo %in% c("subió", "bajó"), ]
  d <- d[order(d$cambio_pct), ]
  hc <- base_hc("Variación de precio del mismo anuncio entre las dos ejecuciones",
                sprintf("Cada punto es un anuncio; las líneas marcan el umbral de ±%s %%", num(umbral, 0))) |>
    hc_chart(type = "scatter", zoomType = "xy") |>
    hc_xAxis(title = list(text = "Precio antes (COP)"), type = "logarithmic") |>
    hc_yAxis(title = list(text = "Cambio (%)"),
             plotLines = list(list(value = umbral, color = "#888", dashStyle = "Dash", width = 1),
                              list(value = -umbral, color = "#888", dashStyle = "Dash", width = 1))) |>
    hc_tooltip(headerFormat = "", pointFormat = paste0("<b>{point.nombre}</b><br/>Antes: ${point.x:,.0f}",
                                                       "<br/>Después: ${point.despues:,.0f}<br/>Cambio: {point.y:.1f} %"))
  for (cm in names(NOMBRE_COMERCIO)) {
    x <- d[d$comercio == NOMBRE_COMERCIO[[cm]], ]
    if (!nrow(x)) next
    hc <- hc |> hc_add_series(name = NOMBRE_COMERCIO[[cm]], color = COLOR_COMERCIO[[cm]],
                              data = puntos(x$precio_antes, x$cambio_pct,
                                            list(nombre = x$producto, despues = x$precio_despues)))
  }
  hc
}
