# presentacion.R
# Formatos, colores y gráficos (highcharter). No tiene SQL: recibe tablas
# que ya vienen calculadas desde db.R.

library(highcharter)

#Formatos

cop <- function(x) {
  ifelse(is.na(x), "sin dato",
         paste0("$", formatC(round(x), format = "d", big.mark = ".", decimal.mark = ","), " COP"))
}
numero <- function(x, dec = 0) {
  ifelse(is.na(x), "sin dato", formatC(x, format = "f", digits = dec, big.mark = ".", decimal.mark = ","))
}
porcentaje <- function(x) ifelse(is.na(x), "sin dato", paste0(numero(x, 1), " %"))

ETIQUETA_ESTADO <- c(disponible = "Disponible", agotado = "Agotado según el sitio",
                     sin_dato = "El sitio no lo indica", no_observado = "No observado")
ETIQUETA_TIPO <- c(sube = "Subió", baja = "Bajó", nuevo = "Nuevo",
                   no_observado = "Dejó de observarse", sin_cambio = "Sin cambio")
ETIQUETA_MODO <- c(online = "En línea", offline = "Sin conexión", test = "Prueba")
# Unidad con la que se expresa el precio unitario (mg se pasa a g en v_observaciones)
ETIQUETA_POR <- c(mL = "mL", g = "g", mg = "g", unidad = "unidad", sobres = "sobre", dosis = "dosis")

# "2026-10-11T02:42:16-05:00" -> "11/10/2026 02:42"
fecha_corta <- function(x) {
  ifelse(is.na(x), "", paste0(substr(x, 9, 10), "/", substr(x, 6, 7), "/", substr(x, 1, 4),
                              " ", substr(x, 12, 16)))
}

etiqueta_ejecucion <- function(id, fecha, estado = NULL) {
  paste0(fecha_corta(fecha), " · ", id, if (!is.null(estado)) paste0(" (", estado, ")"))
}

#Colores fijos por comercio

COLORES_FIJOS <- c("Farmatodo" = "#1B6CA8", "Cruz Verde" = "#2E8B57", "La Rebaja" = "#D1495B")
PALETA <- c("#8E5BB5", "#E07A1F", "#4D4D4D")

asignar_colores <- function(comercios) {
  comercios <- sort(unique(comercios))
  otros <- setdiff(comercios, names(COLORES_FIJOS))
  c(COLORES_FIJOS, stats::setNames(rep(PALETA, length.out = length(otros)), otros))
}

color_de <- function(comercio, colores) {
  col <- unname(colores[comercio])
  col[is.na(col)] <- "#7F7F7F"
  col
}

# Versión clara y sólida del color (para el fondo de las celdas de las tablas)
tono_claro <- function(colores, intensidad = 0.25) {
  m <- grDevices::col2rgb(colores)
  m <- 255 - (255 - m) * intensidad
  stats::setNames(grDevices::rgb(m[1, ], m[2, ], m[3, ], maxColorValue = 255), names(colores))
}

#Textos de highcharter y DT en español

opciones_hc <- getOption("highcharter.lang")
opciones_hc$thousandsSep <- "."
opciones_hc$decimalPoint <- ","
opciones_hc$months <- c("Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
                        "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre")
opciones_hc$shortMonths <- c("Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul",
                             "Ago", "Sep", "Oct", "Nov", "Dic")
opciones_hc$weekdays <- c("Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado")
opciones_hc$noData <- "No hay datos para mostrar"
options(highcharter.lang = opciones_hc)

DT_ESPANOL <- list(
  search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas",
  info = "Filas _START_ a _END_ de _TOTAL_", infoEmpty = "Sin filas",
  infoFiltered = "(de _MAX_ en total)", zeroRecords = "Ninguna fila coincide con la búsqueda",
  emptyTable = "No hay datos para los filtros elegidos",
  paginate = list(first = "Primera", last = "Última", `next` = "Siguiente", previous = "Anterior")
)

# Enlace seguro: solo http(s) y con el texto escapado
enlace <- function(url, texto = "Ver anuncio") {
  ok <- !is.na(url) & grepl("^https?://", url)
  ifelse(ok, sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>',
                     htmltools::htmlEscape(url, attribute = TRUE), texto), "")
}

base_grafico <- function(titulo, subtitulo) {
  highchart() |>
    hc_title(text = titulo, style = list(fontSize = "15px")) |>
    hc_subtitle(text = subtitulo) |>
    hc_credits(enabled = FALSE) |>
    hc_exporting(enabled = TRUE)
}

#Gráfico 1: evolución del precio de un comparable

grafico_evolucion <- function(d, nombre_producto, colores, subtitulo) {
  # highcharts muestra las fechas en UTC; se pasa la hora de Bogotá tal cual
  d$x <- datetime_to_timestamp(as.POSIXct(substr(d$fecha_hora_consulta, 1, 19),
                                          format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))
  formato_fecha <- "%d %b %Y"
  hc <- base_grafico(paste("Evolución del precio:", nombre_producto), subtitulo) |>
    hc_xAxis(type = "datetime", title = list(text = "Fecha de consulta (hora de Colombia)"),
             dateTimeLabelFormats = list(millisecond = formato_fecha, second = formato_fecha,
                                         minute = formato_fecha, hour = formato_fecha,
                                         day = formato_fecha)) |>
    hc_yAxis(title = list(text = "Precio (COP)")) |>
    hc_tooltip(shared = FALSE, xDateFormat = "%d %b %Y %H:%M",
               valuePrefix = "$", valueSuffix = " COP")
  for (com in sort(unique(d$comercio))) {
    dd <- d[d$comercio == com, ]
    hc <- hc |> hc_add_series(dd, "line", hcaes(x = x, y = precio), name = com,
                              color = color_de(com, colores), marker = list(enabled = TRUE))
  }
  hc
}

#Gráfico 2: precio por unidad de contenido

grafico_precio_unitario <- function(d, unidad, colores, subtitulo) {
  productos <- sort(unique(d$comparable))
  por <- ETIQUETA_POR[[unidad]]
  hc <- base_grafico(paste("Precio por", por, "de los productos comparables"), subtitulo) |>
    hc_chart(type = "bar") |>
    hc_xAxis(categories = productos, title = list(text = NULL)) |>
    hc_yAxis(title = list(text = paste("COP por", por))) |>
    hc_tooltip(valueDecimals = 1, valueSuffix = paste(" COP por", por))
  for (com in sort(unique(d$comercio))) {
    dd <- d[d$comercio == com, ]
    valores <- dd$precio_unitario[match(productos, dd$comparable)]
    hc <- hc |> hc_add_series(name = com, data = valores, color = color_de(com, colores))
  }
  hc
}

#Gráfico 3: distribución de precios por comercio

grafico_distribucion <- function(d, colores, subtitulo) {
  comercios <- sort(unique(d$comercio))
  cajas <- list()
  atipicos <- list()
  for (i in seq_along(comercios)) {
    p <- d$precio[d$comercio == comercios[i]]
    b <- grDevices::boxplot.stats(p)
    col <- color_de(comercios[i], colores)
    cajas[[i]] <- list(x = i - 1, low = b$stats[1], q1 = b$stats[2], median = b$stats[3],
                       q3 = b$stats[4], high = b$stats[5], color = col,
                       fillColor = paste0(col, "40"), name = comercios[i])
    for (v in b$out) atipicos[[length(atipicos) + 1]] <- list(x = i - 1, y = v, color = col)
  }
  base_grafico("Distribución de precios de la categoría por comercio", subtitulo) |>
    hc_xAxis(categories = comercios, title = list(text = "Comercio")) |>
    # escala logarítmica: hay medicamentos de pocos miles y otros de millones
    hc_yAxis(type = "logarithmic", title = list(text = "Precio (COP, escala logarítmica)")) |>
    hc_add_series(type = "boxplot", name = "Precio", data = cajas,
                  tooltip = list(pointFormat = paste(
                    "Máximo: ${point.high:,.0f}<br/>Q3: ${point.q3:,.0f}<br/>",
                    "Mediana: ${point.median:,.0f}<br/>Q1: ${point.q1:,.0f}<br/>",
                    "Mínimo: ${point.low:,.0f}<br/>(COP)"))) |>
    hc_add_series(type = "scatter", name = "Valores atípicos", data = atipicos,
                  marker = list(radius = 3), tooltip = list(pointFormat = "${point.y:,.0f} COP")) |>
    hc_legend(enabled = FALSE)
}

#Gráfico 4 (libre): ¿dónde es más barato cada comparable?

grafico_mas_barato <- function(d, total_comparables, colores, subtitulo) {
  base_grafico("¿En qué comercio está más barato cada producto comparable?", subtitulo) |>
    hc_chart(type = "column") |>
    hc_xAxis(categories = d$comercio, title = list(text = "Comercio")) |>
    hc_yAxis(title = list(text = "Número de productos comparables"),
             allowDecimals = FALSE, max = total_comparables) |>
    hc_add_series(name = "Productos donde es el más barato",
                  data = lapply(seq_len(nrow(d)), function(i)
                    list(y = d$veces[i], color = color_de(d$comercio[i], colores)))) |>
    hc_tooltip(pointFormat = paste0("{point.y} de ", total_comparables, " productos comparables")) |>
    hc_legend(enabled = FALSE)
}
