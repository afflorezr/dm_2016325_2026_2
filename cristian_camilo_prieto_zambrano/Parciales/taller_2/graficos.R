# =============================================================================
# graficos.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Los cuatro gráficos interactivos de la aplicación (sección 7.4), con
# highcharter. Reciben tablas ya calculadas en SQL por db.R: aquí solo se
# dibuja, no se filtra ni se agrega.
#
#   1. grafico_evolucion()     evolución del precio de un comparable, una serie
#                              por comercio
#   2. grafico_cuadricula()    precio por unidad de contenido de cada comparable
#                              en cada comercio, coloreado por sobrecosto frente
#                              al más barato (sin mezclar unidades: cada fila es
#                              un producto con su propia unidad)
#   3. grafico_distribucion()  distribución de precios de la categoría por comercio
#   4. grafico_tamanos()       libre elección: ¿conviene la presentación grande?
# =============================================================================

marca_tiempo <- function(fecha) datetime_to_timestamp(as.Date(substr(fecha, 1, 10)))

# 1. Evolución del precio de un producto comparable ------------------------------
grafico_evolucion <- function(d, producto) {
  d <- d[d$coincide == 1 & !is.na(d$precio), ]
  # El eje es diario: si un comercio tiene dos corridas el mismo día, se deja la última
  d <- d[order(d$id_comercio, substr(d$fecha, 1, 10), d$corrida), ]
  d <- d[!duplicated(paste(d$id_comercio, substr(d$fecha, 1, 10)), fromLast = TRUE), ]
  hc <- highchart() |>
    hc_chart(type = "line", zoomType = "x") |>
    hc_title(text = producto) |>
    hc_subtitle(text = "Precio de venta en COP en cada consulta. Una línea por comercio.") |>
    hc_xAxis(type = "datetime", title = list(text = "Fecha de la consulta"),
             dateTimeLabelFormats = list(day = "%e %b", week = "%e %b", month = "%b %Y")) |>
    hc_yAxis(title = list(text = "Precio (COP)"), labels = list(format = "${value:,.0f}")) |>
    hc_tooltip(shared = FALSE, useHTML = TRUE, xDateFormat = "%e de %B de %Y",
               pointFormat = paste0("<span style='color:{series.color}'>●</span> ",
                                    "<b>{series.name}</b>: ${point.y:,.0f}<br>",
                                    "<span style='color:#6B7280'>{point.pu}</span>")) |>
    hc_plotOptions(line = list(lineWidth = 3, marker = list(enabled = TRUE, radius = 6)))
  for (cm in intersect(names(COMERCIOS), unique(d$id_comercio))) {
    x <- d[d$id_comercio == cm, ]
    x <- x[order(x$fecha), ]
    hc <- hc_add_series(hc, name = COMERCIOS[[cm]], color = COLOR_COMERCIO[[cm]],
                        marker = list(symbol = MARCADOR_COMERCIO[[cm]]),
                        data = lapply(seq_len(nrow(x)), function(i) list(
                          x = marca_tiempo(x$fecha[i]), y = x$precio[i],
                          pu = paste("Precio por unidad:", cop_unidad(x$precio_unitario[i], x$unidad_norm[i])))))
  }
  hc
}

# 2. Cuadrícula: precio por unidad y sobrecosto -----------------------------------
grafico_cuadricula <- function(d) {
  comercios <- intersect(names(COMERCIOS), unique(d$id_comercio))
  productos <- unique(d[order(d$id_producto), c("id_producto", "producto", "unidad_norm")])
  # Etiquetas en SVG (no HTML) alineadas a la derecha: quedan ancladas por su
  # borde derecho, así que si la fuente carga después y el texto se ensancha,
  # crece hacia la izquierda y no se mete en las celdas. El margen izquierdo es
  # fijo, calculado con el nombre más largo.
  etiquetas_y <- sprintf("<b>%s</b><br><span style=\"color:#6B7280;font-size:11px\">COP por %s</span>",
                         productos$producto, productos$unidad_norm)
  margen <- min(340, max(150, 30 + 8 * max(nchar(productos$producto))))
  etiquetas_x <- vapply(comercios, function(cm) as.character(insignia(cm)), character(1))
  puntos <- lapply(seq_len(nrow(d)), function(i) {
    r <- d[i, ]
    sin_dato <- is.na(r$sobrecosto_pct)
    list(x = match(r$id_comercio, comercios) - 1, y = match(r$id_producto, productos$id_producto) - 1,
         value = if (sin_dato) NULL else r$sobrecosto_pct,
         pu = if (sin_dato) "sin dato" else cop_unidad(r$precio_unitario, r$unidad_norm),
         precio = if (is.na(r$precio)) "—" else cop(r$precio),
         etiqueta = if (sin_dato) "sin dato"
                    else if (isTRUE(r$es_mas_barato == 1)) "Mejor precio"
                    else paste0("+", numero(r$sobrecosto_pct, 1), " %"),
         dif = if (sin_dato || isTRUE(r$es_mas_barato == 1)) "" else paste0(cop(r$sobrecosto), " más"),
         comercio = COMERCIOS[[r$id_comercio]], producto = r$producto,
         motivo = if (!sin_dato) "" else if (is.na(r$precio)) "El comercio no tiene precio en esta corrida."
                  else "El comercio publicó otra presentación.")
  })
  maximo <- max(c(20, d$sobrecosto_pct), na.rm = TRUE)
  highchart() |>
    hc_chart(type = "heatmap", height = 90 + 52 * nrow(productos), marginTop = 50, marginLeft = margen) |>
    hc_title(text = NULL) |>
    hc_xAxis(categories = unname(etiquetas_x), opposite = TRUE, lineWidth = 0,
             labels = list(useHTML = TRUE)) |>
    hc_yAxis(categories = etiquetas_y, title = list(text = ""), reversed = TRUE, gridLineWidth = 0,
             labels = list(useHTML = FALSE, align = "right", x = -14,
                           style = list(fontSize = "12.5px", textOverflow = "none", whiteSpace = "nowrap",
                                        color = COLOR_TEXTO))) |>
    hc_colorAxis(min = 0, max = maximo, stops = ESCALA_SOBRECOSTO,
                 labels = list(format = "{value} %")) |>
    hc_legend(title = list(text = "Cuánto más caro que el más barato"), align = "right",
              layout = "horizontal", verticalAlign = "bottom") |>
    hc_tooltip(useHTML = TRUE, headerFormat = "",
               pointFormat = paste0("<b>{point.producto}</b><br>{point.comercio}<br>",
                                    "Precio: {point.precio}<br>Por unidad: {point.pu}<br>",
                                    "<b>{point.etiqueta}</b> {point.dif}<br>",
                                    "<span style='color:#6B7280'>{point.motivo}</span>")) |>
    hc_add_series(name = "Sobrecosto", data = puntos, borderWidth = 3, borderColor = "#FFFFFF",
                  nullColor = "#EDEDE9",
                  dataLabels = list(enabled = TRUE, useHTML = TRUE,
                                    format = paste0("<div style='text-align:center;line-height:1.15'>",
                                                    "<b>{point.etiqueta}</b><br>",
                                                    "<span style='font-size:11px'>{point.pu}</span></div>"),
                                    style = list(textOutline = "none", fontWeight = "normal",
                                                 color = "contrast", fontSize = "12px")))
}

# 3. Distribución de precios por comercio -----------------------------------------
grafico_distribucion <- function(d) {
  d <- d[d$comercio %in% COMERCIOS, ]
  ids <- names(COMERCIOS)[match(d$comercio, COMERCIOS)]
  orden <- order(match(ids, names(COMERCIOS)))
  d <- d[orden, ]; ids <- ids[orden]
  cajas <- lapply(seq_len(nrow(d)), function(i) list(
    low = d$minimo[i], q1 = d$q1[i], median = d$mediana[i], q3 = d$q3[i], high = d$maximo[i],
    color = COLOR_COMERCIO[[ids[i]]], fillColor = paste0(COLOR_COMERCIO[[ids[i]]], "26"),
    n = d$n[i], promedio = cop(d$promedio[i]),
    tx = sprintf("Mínimo %s<br>Primer cuartil %s<br><b>Mediana %s</b><br>Tercer cuartil %s<br>Máximo %s",
                 cop(d$minimo[i]), cop(d$q1[i]), cop(d$mediana[i]), cop(d$q3[i]), cop(d$maximo[i]))))
  highchart() |>
    hc_chart(type = "boxplot") |>
    hc_title(text = NULL) |>
    hc_xAxis(categories = unname(COMERCIOS[ids]), title = list(text = "")) |>
    hc_yAxis(type = "logarithmic", title = list(text = "Precio (COP, escala logarítmica)"),
             labels = list(format = "${value:,.0f}")) |>
    hc_legend(enabled = FALSE) |>
    hc_tooltip(useHTML = TRUE, headerFormat = "<b>{point.key}</b><br>",
               pointFormat = "{point.n} productos<br>{point.tx}<br>Promedio {point.promedio}") |>
    hc_add_series(name = "Precios", data = cajas, lineWidth = 2, medianWidth = 4,
                  whiskerLength = "40%", stemDashStyle = "Solid")
}

# 4. ¿Conviene la presentación grande? (gráfico de libre elección) -----------------
# Por cada par de tamaños y comercio: precio por unidad del tamaño pequeño y del
# grande, unidos por una línea en el color del comercio, con el ahorro de
# comprar el grande.
grafico_tamanos <- function(d) {
  d <- d[order(d$producto, match(d$id_comercio, names(COMERCIOS))), ]
  categorias <- sprintf("<b>%s</b><br><span style=\"color:#6B7280\">%s<br>%s → %s</span>",
                        COMERCIOS[d$id_comercio], d$producto,
                        presentacion(d$contenido_pequeno, d$unidad_norm),
                        presentacion(d$contenido_grande, d$unidad_norm))
  texto_ahorro <- ifelse(d$ahorro_pct >= 0,
                         paste0("ahorra ", numero(d$ahorro_pct, 1), " %"),
                         paste0("el grande cuesta ", numero(-d$ahorro_pct, 1), " % más"))
  conectores <- lapply(seq_len(nrow(d)), function(i) list(
    low = d$pu_grande[i], high = d$pu_pequeno[i], connectorColor = COLOR_COMERCIO[[d$id_comercio[i]]],
    lowColor = COLOR_COMERCIO[[d$id_comercio[i]]], color = COLOR_COMERCIO[[d$id_comercio[i]]]))
  pequenos <- lapply(seq_len(nrow(d)), function(i) list(
    x = i - 1, y = d$pu_pequeno[i], color = COLOR_COMERCIO[[d$id_comercio[i]]],
    tx = sprintf("%s: %s (%s)", presentacion(d$contenido_pequeno[i], d$unidad_norm[i]),
                 cop_unidad(d$pu_pequeno[i], d$unidad_norm[i]), cop(d$precio_pequeno[i]))))
  grandes <- lapply(seq_len(nrow(d)), function(i) list(
    x = i - 1, y = d$pu_grande[i], color = COLOR_COMERCIO[[d$id_comercio[i]]],
    tx = sprintf("%s: %s (%s)", presentacion(d$contenido_grande[i], d$unidad_norm[i]),
                 cop_unidad(d$pu_grande[i], d$unidad_norm[i]), cop(d$precio_grande[i]))))
  unidad <- unique(d$unidad_norm)
  highchart() |>
    hc_add_dependency("modules/dumbbell.js") |>
    hc_chart(inverted = TRUE, height = 90 + 64 * nrow(d), marginLeft = 240, marginRight = 150) |>
    hc_title(text = NULL) |>
    # Dos ejes de categorías: a la izquierda el comercio y el producto; a la
    # derecha, en su propia columna, el ahorro (así no se monta sobre los puntos)
    hc_xAxis_multiples(
      list(categories = categorias, title = list(text = ""),
           labels = list(useHTML = FALSE, align = "right", x = -14,
                         style = list(fontSize = "12px", width = "215px", textOverflow = "none",
                                      color = COLOR_TEXTO))),
      list(categories = texto_ahorro, linkedTo = 0, opposite = TRUE, title = list(text = ""),
           lineWidth = 0, tickLength = 0,
           labels = list(useHTML = FALSE, align = "left", x = 14,
                         style = list(fontSize = "12px", fontWeight = "700", width = "135px",
                                      textOverflow = "none", color = COLOR_TEXTO)))
    ) |>
    hc_yAxis(title = list(text = sprintf("Precio por %s (COP)", paste(unidad, collapse = " o "))),
             labels = list(format = "${value:,.0f}", overflow = "allow"), maxPadding = 0.05) |>
    hc_tooltip(useHTML = TRUE, shared = FALSE, headerFormat = "{point.key}<br>",
               pointFormat = "{point.tx}") |>
    hc_legend(align = "left", verticalAlign = "top", itemDistance = 28) |>
    hc_add_series(type = "dumbbell", name = "Diferencia", data = conectores, showInLegend = FALSE,
                  connectorWidth = 4, marker = list(enabled = FALSE), enableMouseTracking = FALSE) |>
    # El color de la serie (gris) es el de la leyenda; cada punto lleva el de su comercio
    hc_add_series(type = "scatter", name = "Presentación pequeña", data = pequenos, color = COLOR_SUAVE,
                  marker = list(symbol = "circle", radius = 8, lineWidth = 3, lineColor = NULL,
                                fillColor = "#FFFFFF")) |>
    hc_add_series(type = "scatter", name = "Presentación grande", data = grandes, color = COLOR_SUAVE,
                  marker = list(symbol = "circle", radius = 8))
}
