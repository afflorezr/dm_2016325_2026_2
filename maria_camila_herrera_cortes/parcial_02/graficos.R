# graficos.R -- Taller 2, Módulo 5: colores, formatos y gráficos (highcharter)
# Funciones que reciben tablas (salida de db.R) y devuelven gráficos o tablas listas para mostrar.
# Cada comercio conserva el mismo color en toda la aplicación.

suppressPackageStartupMessages({ library(highcharter) })

# Etiquetas de eje en pesos con separador de miles: 12900 -> $12.900
JS_COP <- JS("function() { return '$' + Highcharts.numberFormat(this.value, 0, ',', '.'); }")

if (!exists("COLORES_COMERCIO")) source("colores.R", encoding = "UTF-8")   # colores en un solo archivo
NOMBRES_COMERCIO <- c(exito = "Éxito", jumbo = "Jumbo", olimpica = "Olímpica")

color_comercio  <- function(x) { v <- unname(COLORES_COMERCIO[as.character(x)]); v[is.na(v)] <- "#6B7280"; v }
nombre_comercio <- function(x) { v <- unname(NOMBRES_COMERCIO[as.character(x)]); ifelse(is.na(v), as.character(x), v) }

# Moneda COP con separador de miles punto: 12900 -> "$12.900"
fmt_cop <- function(x, decimales = 0)
  ifelse(is.na(x), "—", paste0("$", formatC(x, format = "f", digits = decimales, big.mark = ".", decimal.mark = ",")))
fmt_num <- function(x) ifelse(is.na(x), "—", formatC(x, format = "d", big.mark = ".", decimal.mark = ","))
fmt_pct <- function(x, d = 1) ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = d, decimal.mark = ","), " %"))

# "2026-11-09T12:58:18-05:00" -> "09/11/2026 12:58"
fmt_fecha <- function(iso) {
  t <- as.POSIXct(substr(iso, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  ifelse(is.na(t), "—", format(t, "%d/%m/%Y %H:%M"))
}
ms_local <- function(iso) as.numeric(as.POSIXct(substr(iso, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")) * 1000

abreviar <- function(x, n = 30) ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "…"), x)

# Idioma de los gráficos: español, coma decimal y punto de miles
configurar_highcharter <- function() {
  l <- getOption("highcharter.lang")
  l$decimalPoint <- ","; l$thousandsSep <- "."
  l$months <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
                "septiembre", "octubre", "noviembre", "diciembre")
  l$shortMonths <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
  l$weekdays <- c("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")
  l$noData <- "Sin datos para mostrar"; l$loading <- "Cargando..."
  l$downloadPNG <- "Descargar PNG"; l$downloadJPEG <- "Descargar JPEG"
  l$downloadPDF <- "Descargar PDF"; l$downloadSVG <- "Descargar SVG"; l$printChart <- "Imprimir"
  options(highcharter.lang = l)
}

base_hc <- function(tipo, titulo, subtitulo = NULL) {
  highchart() |>
    hc_chart(type = tipo, style = list(fontFamily = "inherit")) |>
    hc_title(text = titulo, align = "left", style = list(fontSize = "16px")) |>
    hc_subtitle(text = subtitulo, align = "left") |>
    hc_exporting(enabled = TRUE) |>
    hc_credits(enabled = FALSE)
}

# 1. Evolución del precio de un producto comparable, una serie por comercio
#    eje = "fecha": escala de tiempo real; eje = "ejecucion": una marca por ejecución (separación pareja)
grafico_evolucion <- function(d, producto, subtitulo = NULL, eje = c("fecha", "ejecucion")) {
  eje <- match.arg(eje)
  hc <- base_hc("line", paste("Evolución del precio:", abreviar(producto, 70)), subtitulo) |>
    hc_yAxis(title = list(text = "Precio (COP)"), labels = list(formatter = JS_COP)) |>
    hc_legend(align = "center", verticalAlign = "top") |>
    hc_plotOptions(series = list(marker = list(enabled = TRUE, radius = 5), lineWidth = 3, connectNulls = FALSE))
  if (eje == "fecha") {
    hc <- hc |> hc_xAxis(type = "datetime", title = list(text = "Fecha de consulta")) |>
      hc_tooltip(shared = TRUE, xDateFormat = "%d/%m/%Y %H:%M", valuePrefix = "$", valueDecimals = 0)
    for (cm in unique(d$comercio)) {
      x <- d[d$comercio == cm, ]
      hc <- hc_add_series(hc, name = nombre_comercio(cm), color = color_comercio(cm), type = "line",
                          data = lapply(seq_len(nrow(x)), function(i) list(x = ms_local(x$fecha_hora_consulta[i]), y = x$precio_cop[i])))
    }
  } else {
    ej <- unique(d[order(d$fecha_hora_consulta), c("ejecucion_id", "fecha_hora_consulta")])
    hc <- hc |> hc_xAxis(categories = fmt_fecha(ej$fecha_hora_consulta), title = list(text = "Ejecución (fecha de consulta)"),
                         labels = list(rotation = -30, step = 1)) |>
      hc_tooltip(shared = TRUE, valuePrefix = "$", valueDecimals = 0)
    for (cm in unique(d$comercio)) {
      v <- d$precio_cop[match(paste(ej$ejecucion_id, cm), paste(d$ejecucion_id, d$comercio))]
      hc <- hc_add_series(hc, name = nombre_comercio(cm), color = color_comercio(cm), type = "line", data = as.list(v))
    }
  }
  hc
}

# 2. Precio por unidad de contenido (una sola unidad por gráfico, nunca mezcladas)
grafico_precio_unitario <- function(d, unidad, subtitulo = NULL) {
  prods <- unique(d[, c("producto_id", "producto_estandar")])
  cats <- paste0(prods$producto_id, " · ", abreviar(prods$producto_estandar, 26))
  hc <- base_hc("column", paste0("Precio por ", unidad, " entre comercios"), subtitulo) |>
    hc_xAxis(categories = cats, labels = list(rotation = -30, step = 1, style = list(fontSize = "11px"))) |>
    hc_yAxis(title = list(text = paste0("COP por ", unidad))) |>
    hc_tooltip(shared = TRUE, valuePrefix = "$", valueDecimals = 1, valueSuffix = paste0(" / ", unidad)) |>
    hc_plotOptions(column = list(borderWidth = 0))
  for (cm in unique(d$comercio)) {
    v <- d$precio_unitario[match(paste(prods$producto_id, cm), paste(d$producto_id, d$comercio))]
    hc <- hc_add_series(hc, name = nombre_comercio(cm), color = color_comercio(cm), data = as.list(v))
  }
  hc
}

# 3. Distribución de precios por comercio (caja P25-P75, bigotes P5-P95, línea = mediana)
grafico_distribucion <- function(q, subtitulo = NULL, log = TRUE) {
  hc <- base_hc("boxplot", "Distribución de precios por comercio", subtitulo) |>
    hc_xAxis(categories = paste0(nombre_comercio(q$comercio), " (n = ", fmt_num(q$n), ")")) |>
    hc_yAxis(title = list(text = "Precio (COP)"), type = if (log) "logarithmic" else "linear",
             labels = list(formatter = JS_COP)) |>
    hc_tooltip(pointFormat = paste0("P95: ${point.high}<br/>P75: ${point.q3}<br/>Mediana: ${point.median}<br/>",
                                    "P25: ${point.q1}<br/>P5: ${point.low}")) |>
    hc_legend(enabled = FALSE)
  hc_add_series(hc, name = "Precios", type = "boxplot", colorByPoint = TRUE, colors = as.list(color_comercio(q$comercio)),
                data = lapply(seq_len(nrow(q)), function(i)
                  list(low = q$p5[i], q1 = q$p25[i], median = q$mediana[i], q3 = q$p75[i], high = q$p95[i])))
}

# 4. Gráfico libre: ¿cuánto más caro es cada comercio frente al más barato, producto por producto?
grafico_sobrecosto <- function(d, subtitulo = NULL) {
  prods <- unique(d[, c("producto_id", "producto_estandar")])
  cats <- paste0(prods$producto_id, " · ", abreviar(prods$producto_estandar, 26))
  hc <- base_hc("bar", "Sobrecosto frente al comercio más barato", subtitulo) |>
    hc_xAxis(categories = cats, labels = list(step = 1, style = list(fontSize = "11px"))) |>
    hc_yAxis(title = list(text = "% más caro que el precio mínimo (0 = el más barato)"), min = 0) |>
    hc_tooltip(shared = TRUE, valueSuffix = " %", valueDecimals = 1)
  for (cm in unique(d$comercio)) {
    v <- d$sobrecosto_pct[match(paste(prods$producto_id, cm), paste(d$producto_id, d$comercio))]
    hc <- hc_add_series(hc, name = nombre_comercio(cm), color = color_comercio(cm), data = as.list(v))
  }
  hc
}

# Mediana del precio por subcategoría
grafico_mediana_subcat <- function(d, subtitulo = NULL) {
  d <- head(d[order(-d$mediana_cop), ], 12)
  base_hc("bar", "Mediana del precio por subcategoría", subtitulo) |>
    hc_xAxis(categories = paste0(d$subcategoria, " (n = ", fmt_num(d$n), ")"), labels = list(step = 1)) |>
    hc_yAxis(title = list(text = "Mediana (COP)"), labels = list(formatter = JS_COP)) |>
    hc_tooltip(pointFormat = "Mediana: <b>${point.y}</b>") |>
    hc_legend(enabled = FALSE) |>
    hc_add_series(name = "Mediana", data = as.list(round(d$mediana_cop)), color = COLOR_NEUTRO)
}

# ---- gráficos nuevos --------------------------------------------------------------------------
# Promoción por comercio (% de productos en promoción)
grafico_promocion <- function(d, subtitulo = NULL) {
  base_hc("column", "Productos en promoción por comercio", subtitulo) |>
    hc_xAxis(categories = nombre_comercio(d$comercio)) |>
    hc_yAxis(title = list(text = "% de productos en promoción"), min = 0, labels = list(format = "{value} %")) |>
    hc_tooltip(pointFormat = "{point.y} % ({point.n} de {point.total} productos)") |>
    hc_legend(enabled = FALSE) |>
    hc_add_series(name = "Promoción", colorByPoint = TRUE, colors = as.list(color_comercio(d$comercio)),
                  data = lapply(seq_len(nrow(d)), function(i) list(y = d$pct[i], n = d$en_promocion[i], total = d$productos[i])),
                  dataLabels = list(enabled = TRUE, format = "{point.y} %"))
}

# Disponibilidad por comercio (disponible / agotado según el sitio)
grafico_disponibilidad <- function(d, subtitulo = NULL) {
  base_hc("column", "Disponibilidad de los productos por comercio", subtitulo) |>
    hc_xAxis(categories = nombre_comercio(d$comercio)) |>
    hc_yAxis(title = list(text = "Número de productos"), stackLabels = list(enabled = TRUE)) |>
    hc_plotOptions(column = list(stacking = "normal")) |>
    hc_tooltip(shared = TRUE) |>
    hc_add_series(name = "Agotado según el sitio", color = "#CBD5E1", data = as.list(d$agotados)) |>
    hc_add_series(name = "Disponible", color = COLOR_BAJA, data = as.list(d$disponibles))
}

# ¿En cuántos productos comparables es el más barato cada comercio?
grafico_mas_barato <- function(d, subtitulo = NULL) {
  base_hc("column", "Productos comparables en los que cada comercio es el más barato", subtitulo) |>
    hc_xAxis(categories = nombre_comercio(d$comercio)) |>
    hc_yAxis(title = list(text = "Número de productos"), allowDecimals = FALSE, min = 0) |>
    hc_tooltip(pointFormat = "Más barato en <b>{point.y}</b> de {point.total} productos") |>
    hc_legend(enabled = FALSE) |>
    hc_add_series(name = "Productos", colorByPoint = TRUE, colors = as.list(color_comercio(d$comercio)),
                  data = lapply(seq_len(nrow(d)), function(i) list(y = d$productos_mas_barato[i], total = d$comparables[i])),
                  dataLabels = list(enabled = TRUE))
}

# Ahorro en pesos por producto si se compra en el comercio más barato
grafico_ahorro <- function(a, subtitulo = NULL) {
  a <- a[order(-a$ahorro_cop), ]
  cats <- paste0(a$producto_id, " · ", abreviar(a$producto_estandar, 26))
  base_hc("bar", "Ahorro por producto comprando en el comercio más barato", subtitulo) |>
    hc_xAxis(categories = cats, labels = list(step = 1, style = list(fontSize = "11px"))) |>
    hc_yAxis(title = list(text = "Ahorro frente al comercio más caro (COP)"), min = 0, labels = list(formatter = JS_COP)) |>
    hc_tooltip(pointFormat = "Ahorro: <b>${point.y}</b> ({point.pct} %)<br/>Más barato en: {point.donde}") |>
    hc_legend(enabled = FALSE) |>
    hc_add_series(name = "Ahorro", color = COLOR_BAJA,
                  data = lapply(seq_len(nrow(a)), function(i) list(y = a$ahorro_cop[i], pct = a$ahorro_pct[i],
                                                                   donde = a$comercios_mas_baratos[i])),
                  dataLabels = list(enabled = TRUE, format = "${point.y}"))
}

# Mayores variaciones de precio entre dos ejecuciones
grafico_variaciones <- function(d, subtitulo = NULL, n = 12) {
  d <- d[d$tipo %in% c("subió", "bajó") & !is.na(d$variacion_pct), ]
  d <- head(d[order(-abs(d$variacion_pct)), ], n)
  base_hc("bar", paste0("Las ", nrow(d), " mayores variaciones de precio"), subtitulo) |>
    hc_xAxis(categories = paste0(nombre_comercio(d$comercio), " · ", abreviar(d$nombre, 34)), labels = list(step = 1, style = list(fontSize = "11px"))) |>
    hc_yAxis(title = list(text = "Variación del precio (%)"), labels = list(format = "{value} %")) |>
    hc_tooltip(pointFormat = "{point.y} % ({point.cop})") |>
    hc_legend(enabled = FALSE) |>
    hc_add_series(name = "Variación", data = lapply(seq_len(nrow(d)), function(i)
      list(y = round(d$variacion_pct[i], 1), color = if (d$variacion_pct[i] > 0) COLOR_SUBE else COLOR_BAJA,
           cop = paste0(fmt_cop(d$precio_anterior[i]), " → ", fmt_cop(d$precio_actual[i])))))
}

# Canasta: costo total por comercio (solo comercios con la canasta completa), apilado por producto
grafico_canasta_total <- function(det, pc, subtitulo = NULL) {
  cms <- pc$comercio
  etiquetas <- ifelse(is.na(pc$total_cop), paste0(nombre_comercio(cms), " (incompleta)"), nombre_comercio(cms))
  hc <- base_hc("column", "Costo de la canasta por comercio", subtitulo) |>
    hc_xAxis(categories = etiquetas) |>
    hc_yAxis(title = list(text = "Costo total (COP)"), stackLabels = list(enabled = TRUE, format = "${total:,.0f}"),
             labels = list(formatter = JS_COP)) |>
    hc_plotOptions(column = list(stacking = "normal")) |>
    hc_tooltip(shared = TRUE, valuePrefix = "$", valueDecimals = 0)
  prods <- unique(det$producto_id)
  for (k in seq_along(prods)) {
    v <- vapply(cms, function(cm) {
      if (is.na(pc$total_cop[pc$comercio == cm])) return(NA_real_)       # nunca se muestra un total incompleto
      det$subtotal[det$comercio == cm & det$producto_id == prods[k]][1] }, 0, USE.NAMES = FALSE)
    hc <- hc_add_series(hc, name = prods[k], color = PALETA_PRODUCTOS[(k - 1) %% length(PALETA_PRODUCTOS) + 1], data = as.list(v))
  }
  hc
}

# Canasta: precio unitario de cada producto elegido en cada comercio
grafico_canasta_precios <- function(det, nombres, subtitulo = NULL) {
  prods <- unique(det$producto_id)
  base_hc("column", "Precio de cada producto de la canasta por comercio", subtitulo) |>
    hc_xAxis(categories = paste0(prods, " · ", abreviar(nombres[match(prods, names(nombres))], 24)),
             labels = list(step = 1, rotation = -20)) |>
    hc_yAxis(title = list(text = "Precio por unidad de venta (COP)"), labels = list(formatter = JS_COP)) |>
    hc_tooltip(shared = TRUE, valuePrefix = "$", valueDecimals = 0) -> hc
  for (cm in unique(det$comercio)) {
    v <- det$precio_cop[match(paste(prods, cm), paste(det$producto_id, det$comercio))]
    hc <- hc_add_series(hc, name = nombre_comercio(cm), color = color_comercio(cm), data = as.list(v))
  }
  hc
}

# ---- tabla de productos lista para mostrar / descargar ---------------------------------------
tabla_productos <- function(x, para_csv = FALSE) {
  disp <- ifelse(is.na(x$estado_disponibilidad), "No observado",
                 ifelse(x$estado_disponibilidad == "disponible", "Disponible", "Agotado"))
  url_ok <- !is.na(x$url) & grepl("^https?://", x$url)
  enlace <- if (para_csv) x$url else ifelse(url_ok,
    paste0("<a href='", htmltools::htmlEscape(x$url, attribute = TRUE), "' target='_blank' rel='noopener'>Ver anuncio</a>"), "")
  out <- data.frame(Comercio = nombre_comercio(x$comercio), Producto = x$nombre, Marca = x$marca,
                    Presentación = x$presentacion, `Precio (COP)` = x$precio_cop,
                    `Precio unitario (COP)` = round(x$precio_unitario, 1), Unidad = x$unidad_norm,
                    Promoción = ifelse(x$en_promocion == 1, "Sí", "No"), Disponibilidad = disp,
                    `Fecha de consulta` = if (para_csv) x$fecha_hora_consulta else fmt_fecha(x$fecha_hora_consulta),
                    Enlace = enlace, check.names = FALSE, stringsAsFactors = FALSE)
  out
}
