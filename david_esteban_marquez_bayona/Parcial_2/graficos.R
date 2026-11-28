# graficos.R — Tema visual, formato y gráficos interactivos (highcharter) · Taller 2 · cuidado bucal.
# Recibe tablas ya calculadas por db.R; aquí no hay SQL ni lógica de negocio.

# ---------------------------------------------------------------------------
# Tema visual (lo usan app.R y los gráficos, para que todo hable el mismo idioma)
# Estilo sobrio con un guiño discreto a Wes Anderson: papel crema, tipografía geométrica
# (tipo Futura) en títulos espaciados, composición centrada y marcos finos dobles.
# ---------------------------------------------------------------------------
PAPEL <- "#f4ede1"       # fondo de la página (crema)
SUPERFICIE <- "#fffcf6"  # tarjetas y gráficos (marfil)
TINTA <- "#2c2622"       # texto principal (sepia oscuro)
TINTA_2 <- "#6e6158"     # texto secundario y ejes
LINEA <- "#e2d6c2"       # bordes y líneas de eje
REJILLA <- "#efe6d6"     # cuadrícula de los gráficos
ACENTO <- "#6b4a5e"      # color principal de la interfaz (ciruela apagado, distinto de los comercios)
ACENTO_SUAVE <- "#e9dfe3"

# Cada comercio conserva su color, su símbolo y su logo en toda la aplicación. Los colores
# siguen la marca (Éxito amarillo oscuro, Olímpica rojo, Locatel verde). Rojo y verde se confunden
# con daltonismo, por eso cada comercio tiene además un símbolo distinto y su logo en las leyendas.
COLORES_COMERCIO <- c(exito = "#b8860b", olimpica = "#c8102e", locatel = "#1e8c5a")
SIMBOLOS_COMERCIO <- c(exito = "circle", olimpica = "square", locatel = "diamond")
LOGOS_COMERCIO <- c(exito = "./logos/exito.png", olimpica = "./logos/olimpica.png", locatel = "./logos/locatel_simbolo.png")
LOGOS_GRANDES <- c(exito = "./logos/exito.png", olimpica = "./logos/olimpica.png", locatel = "./logos/locatel.png")
COLOR_EMPATE <- "#a59a8c"
# Subcategorías (gráfico de composición): paleta validada para daltonismo; «Otras» en gris cálido.
COLORES_SUBCATEGORIA <- c("#16998a", "#cf5f4c", "#4570c6", "#c98f12", "#a352aa", "#6e9c22")
COLOR_OTRAS <- "#bdb2a2"

color_comercio <- function(comercio_id) {
  col <- unname(COLORES_COMERCIO[comercio_id]); col[is.na(col)] <- COLOR_EMPATE; col
}
simbolo_comercio <- function(comercio_id) {
  s <- unname(SIMBOLOS_COMERCIO[comercio_id]); s[is.na(s)] <- "circle"; s
}
# Logo como etiqueta <img> (texto HTML para tablas y gráficos). Los logos están en www/logos/;
# son de sus dueños y se usan solo para identificar cada comercio.
logo_html <- function(comercio_id, alto = 18, grande = FALSE) {
  src <- unname((if (grande) LOGOS_GRANDES else LOGOS_COMERCIO)[comercio_id])
  ifelse(is.na(src), "", sprintf('<img src="%s" alt="" style="height:%dpx;vertical-align:middle;margin-right:6px;">', src, alto))
}

.sans <- c("system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif")
tema_app <- function() {
  bslib::bs_theme(
    version = 5, bg = PAPEL, fg = TINTA, primary = ACENTO, secondary = TINTA_2,
    success = "#3f7a4f", info = "#4570c6", warning = "#a86b00", danger = "#a23a2e",
    # Si no hay conexión para descargar las fuentes, se usan las del sistema (nunca una con serifa)
    base_font = do.call(bslib::font_collection, c(list(bslib::font_google("Work Sans", wght = c(400, 500, 600), local = FALSE)), .sans)),
    heading_font = do.call(bslib::font_collection, c(list(bslib::font_google("Josefin Sans", wght = c(500, 600, 700), local = FALSE),
                                                          "Futura", "Century Gothic"), .sans)),
    code_font = bslib::font_collection(bslib::font_google("IBM Plex Mono", local = FALSE), "Consolas", "monospace"),
    "font-size-base" = "0.93rem", "border-radius" = "0.35rem", "border-color" = LINEA,
    "card-bg" = SUPERFICIE, "card-border-color" = LINEA, "card-cap-bg" = SUPERFICIE,
    "headings-font-weight" = 600, "link-color" = ACENTO, "input-bg" = SUPERFICIE)
}

ESTILOS_APP <- "
  :root { --papel: #f4ede1; --marfil: #fffcf6; --linea: #e2d6c2; --tinta-2: #6e6158; --acento: #6b4a5e; }
  body { font-variant-numeric: tabular-nums; }
  h1, h2, h3, h4, .navbar-brand, .card-header, .value-box-title, .sidebar-title, .titulo-seccion {
    font-family: 'Josefin Sans', Futura, 'Century Gothic', system-ui, sans-serif; }

  /* Barra superior: marfil con una doble línea fina, como el borde de un programa de mano */
  .navbar { background: var(--marfil) !important; border-bottom: 3px double var(--linea); }
  .navbar-brand { font-weight: 700; letter-spacing: .08em; text-transform: uppercase; font-size: 1.02rem; }
  .navbar-brand .marca { display:inline-block; width:.6rem; height:.6rem; border-radius:50%; margin-right:.6rem;
                         background: conic-gradient(#b8860b 0 120deg, #c8102e 120deg 240deg, #1e8c5a 240deg); vertical-align: 1px; }
  .navbar .nav-link { font-family: 'Josefin Sans', Futura, system-ui, sans-serif; font-weight: 600; letter-spacing: .05em;
                      text-transform: uppercase; font-size: .76rem; color: var(--tinta-2); padding-top: .65rem; white-space: nowrap; }
  .navbar .nav-link.active { color: var(--acento) !important; box-shadow: inset 0 -2px 0 var(--acento); }

  /* Panel de filtros */
  .bslib-sidebar-layout > .sidebar { background: #efe6d6; border-right: 1px solid var(--linea); }
  .sidebar-title { font-size: .78rem; text-transform: uppercase; letter-spacing: .16em; color: var(--tinta-2); font-weight: 700;
                   text-align: center; }
  .sidebar .form-label, .sidebar .control-label { font-size: .84rem; font-weight: 500; }

  /* Tarjetas con marco doble y título centrado y espaciado */
  .card { border: 1px solid var(--linea); box-shadow: inset 0 0 0 4px var(--marfil), inset 0 0 0 5px #f1e8d8; }
  .card-header { text-align: center; text-transform: uppercase; letter-spacing: .14em; font-size: .8rem; font-weight: 700;
                 color: var(--acento); border-bottom: 1px solid #efe6d6; padding: 1rem 1rem .75rem; background: transparent; }
  .card-header::before, .card-header::after { content: '\\00B7'; color: #c9b9a2; margin: 0 .6rem; }
  .card-header.d-flex::before, .card-header.d-flex::after { content: none; }
  .card-footer { background: transparent; border-top: 1px solid #efe6d6; color: var(--tinta-2); text-align: center; }

  /* Indicadores: centrados, cifra protagonista */
  .bslib-value-box { text-align: center; border: 1px solid var(--linea) !important; }
  .bslib-value-box .value-box-area { padding: 1.1rem 1rem !important; align-items: center; }
  .bslib-value-box p { margin-bottom: 0; color: var(--tinta-2); }
  .bslib-value-box.bg-primary p { color: rgba(255,255,255,.85); }
  .bslib-value-box .value-box-title { font-size: .72rem; text-transform: uppercase; letter-spacing: .14em; color: var(--tinta-2); font-weight: 700; }
  .bslib-value-box .value-box-value { font-size: 1.6rem; font-weight: 600; letter-spacing: -0.01em; margin: .15rem 0 .25rem; }
  .bslib-value-box.bg-primary .value-box-title { color: rgba(255,255,255,.8); }

  /* Tablas */
  .shiny-table { font-size: .9rem; }
  .shiny-table td, .shiny-table th { padding: .38rem .6rem; }
  .shiny-table thead th { color: var(--tinta-2); font-weight: 600; border-bottom: 1px solid var(--linea); }
  table.dataTable thead th { color: var(--tinta-2); font-weight: 600; }
  .tabla-logos td:first-child { white-space: nowrap; }
  .cantidad .form-group { margin-bottom: 0; }

  /* Logos de los comercios */
  .comercio-logo { display:flex; align-items:center; gap:.5rem; margin-bottom:.35rem; }
  .comercio-logo img { height: 20px; width: 44px; object-fit: contain; object-position: left center; margin-right: 0 !important; }
  .punto { display:inline-block; width:.7rem; height:.7rem; border-radius:50%; margin-right:.4rem; vertical-align: -1px; }

  /* Pestaña «Comercios»: una ficha por comercio, simétricas, con el logo arriba */
  .titulo-seccion { text-align:center; text-transform: uppercase; letter-spacing:.2em; font-size:.78rem; font-weight:700;
                    color: var(--tinta-2); margin: .4rem 0 1rem; }
  .titulo-seccion span { display:inline-block; padding: 0 1rem; position: relative; }
  .titulo-seccion span::before, .titulo-seccion span::after { content:''; position:absolute; top:50%; width:3.5rem; border-top:1px solid #cdbda6; }
  .titulo-seccion span::before { right:100%; } .titulo-seccion span::after { left:100%; }
  .ficha { background: var(--marfil); border: 1px solid var(--linea); border-radius: .35rem; padding: 1.4rem 1.2rem 1.1rem;
           box-shadow: inset 0 0 0 4px var(--marfil), inset 0 0 0 5px #f1e8d8; text-align: center; height: 100%;
           border-top: 4px solid var(--color-comercio); }
  .ficha .ficha-logo { height: 64px; display:flex; align-items:center; justify-content:center; margin-bottom: .7rem; }
  .ficha .ficha-logo img { max-height: 64px; max-width: 180px; }
  .ficha .ficha-nombre { font-family: 'Josefin Sans', Futura, system-ui, sans-serif; text-transform: uppercase; letter-spacing:.16em;
                         font-weight:700; font-size:.82rem; color: var(--tinta-2); margin-bottom: .9rem; }
  .ficha .ficha-cifra { font-size: 2rem; font-weight: 600; line-height: 1.1; color: var(--color-comercio); }
  .ficha .ficha-cifra-texto { font-size: .78rem; color: var(--tinta-2); margin-bottom: 1rem; }
  .ficha dl { display:grid; grid-template-columns: 1fr auto; gap: .35rem .8rem; margin: 0; text-align:left; font-size:.86rem;
              border-top: 1px solid #efe6d6; padding-top: .8rem; }
  .ficha dt { font-weight: 400; color: var(--tinta-2); } .ficha dd { margin:0; font-weight:600; text-align:right; }

  /* Gráfico de waffle */
  .waffle { display:grid; grid-template-columns: repeat(10, 1fr); gap: 4px; width: 100%; max-width: 300px; margin: .6rem auto 1.1rem; align-self: center; }
  .waffle i { display:block; aspect-ratio: 1; border-radius: 3px; background: var(--c); }
  .waffle-leyenda { display:grid; gap:.45rem; width: 100%; max-width: 330px; margin: 0 auto; font-size:.86rem; align-self: center; }
  .waffle-leyenda div { display:flex; align-items:center; gap:.55rem; }
  .waffle-leyenda .muestra { width: 14px; height: 14px; border-radius: 3px; flex: none; }
  .waffle-leyenda img { height: 18px; width: 40px; object-fit: contain; object-position: left center; }
  .waffle-leyenda .valor { margin-left:auto; font-weight:600; }

  .alert { border-radius: .35rem; }
  .highcharts-root, .highcharts-root text, .highcharts-tooltip span { font-family: 'Work Sans', system-ui, -apple-system, 'Segoe UI', sans-serif !important; }
"

# ---- Formato (pesos colombianos, porcentajes y fechas) ----
cop <- function(x, decimales = 0) {
  ifelse(is.na(x), "—", paste0("$ ", formatC(as.numeric(x), format = "f", digits = decimales,
                                                         big.mark = ".", decimal.mark = ",")))
}
pct <- function(x, decimales = 1) {
  ifelse(is.na(x), "—", paste0(formatC(as.numeric(x), format = "f", digits = decimales, decimal.mark = ","), " %"))
}
entero <- function(x) ifelse(is.na(x), "—", formatC(as.numeric(x), format = "d", big.mark = ".", decimal.mark = ","))
fecha_hora <- function(iso) ifelse(is.na(iso), "—", paste(substr(iso, 1, 10), substr(iso, 12, 16)))
etiqueta_ejecucion <- function(ejecucion_id) {                # E20261009T144022 -> 2026-10-09 14:40
  sub("^E(\\d{4})(\\d{2})(\\d{2})T(\\d{2})(\\d{2})\\d{2}$", "\\1-\\2-\\3 \\4:\\5", ejecucion_id)
}

# ---------------------------------------------------------------------------
# Tema de los gráficos
# ---------------------------------------------------------------------------
.texto_eje <- list(color = TINTA_2, fontSize = "12px")
TEMA_GRAFICOS <- highcharter::hc_theme(
  colors = unname(COLORES_COMERCIO),
  chart = list(backgroundColor = "transparent", spacing = list(12, 26, 10, 4),
               style = list(color = TINTA)),   # la fuente la pone ESTILOS_APP (.highcharts-root)
  title = list(text = NULL), subtitle = list(text = NULL),
  xAxis = list(lineColor = LINEA, tickColor = LINEA, tickLength = 4, gridLineColor = REJILLA,
               labels = list(style = .texto_eje), title = list(style = list(color = TINTA_2, fontWeight = "500"))),
  yAxis = list(gridLineColor = REJILLA, gridLineWidth = 1, lineWidth = 0, tickWidth = 0,
               labels = list(style = .texto_eje), title = list(style = list(color = TINTA_2, fontWeight = "500"))),
  legend = list(align = "left", verticalAlign = "top", layout = "horizontal", margin = 14, useHTML = TRUE,
                labelFormatter = highcharter::JS(
                  "function () { var l = this.options.logo; return (l ? '<img src=\"' + l + '\" style=\"height:16px;vertical-align:-3px;margin-right:4px\">' : '') + this.name; }"),
                itemStyle = list(color = TINTA, fontWeight = "500", fontSize = "12.5px"),
                itemHoverStyle = list(color = ACENTO)),
  tooltip = list(backgroundColor = SUPERFICIE, borderColor = LINEA, borderRadius = 8, borderWidth = 1, padding = 10,
                 shadow = list(color = "rgba(29,43,49,0.10)", offsetX = 0, offsetY = 2, width = 6),
                 style = list(color = TINTA, fontSize = "12.5px")),
  plotOptions = list(
    series = list(animation = list(duration = 350), states = list(inactive = list(opacity = 0.35))),
    line = list(lineWidth = 2, marker = list(enabled = TRUE, radius = 5, lineWidth = 2, lineColor = SUPERFICIE)),
    bar = list(borderRadius = 4, borderWidth = 0, maxPointWidth = 18),
    scatter = list(marker = list(radius = 6, lineWidth = 2, lineColor = SUPERFICIE))),
  credits = list(enabled = FALSE), exporting = list(enabled = FALSE))

.tema <- function(hc) highcharter::hc_add_theme(hc, TEMA_GRAFICOS)

# Marcas legibles para un eje logarítmico entre a y b: 1, 2 y 5 por potencia de 10
# (solo 1 y 5, o solo potencias de 10, si el rango es muy amplio).
.marcas_log <- function(a, b) {
  for (pasos in list(c(1, 2, 5), c(1, 3), 1)) {
    m <- sort(as.vector(outer(pasos, 10^(floor(log10(a)):ceiling(log10(b))))))
    m <- m[seq(max(which(m <= a)), min(which(m >= b)))]
    if (length(m) <= 6) return(m)
  }
  m
}
.opciones_idioma <- function() {
  lang <- getOption("highcharter.lang")
  lang$decimalPoint <- ","; lang$thousandsSep <- "."
  lang$noData <- "No hay datos para mostrar"
  options(highcharter.lang = lang)
}

# 1. Evolución del precio de una presentación comparable: una línea por comercio.
grafico_evolucion <- function(d) {
  ejec <- sort(unique(d$ejecucion_id))
  hc <- highcharter::highchart() |>
    highcharter::hc_chart(type = "line") |>
    highcharter::hc_xAxis(categories = as.list(etiqueta_ejecucion(ejec)), title = list(text = NULL)) |>
    highcharter::hc_yAxis(title = list(text = "Precio (COP)"), labels = list(format = "$ {value:,.0f}")) |>
    highcharter::hc_tooltip(shared = TRUE, crosshairs = list(width = 1, color = LINEA, dashStyle = "Solid"),
                            headerFormat = "<span style='color:#56656c'>{point.key}</span><br>",
                            pointFormat = "<span style='color:{series.color}'>●</span> {series.name}: <b>$ {point.y:,.0f}</b><br>") |>
    highcharter::hc_plotOptions(line = list(connectNulls = FALSE))
  for (cid in unique(d$comercio_id)) {
    s <- d[d$comercio_id == cid, ]
    valores <- s$precio[match(ejec, s$ejecucion_id)]
    hc <- highcharter::hc_add_series(hc, name = s$comercio[1], color = color_comercio(cid), logo = unname(LOGOS_COMERCIO[cid]),
                                     marker = list(symbol = simbolo_comercio(cid)),
                                     data = lapply(valores, function(v) if (is.na(v)) NULL else v))
  }
  .tema(hc)
}

# 2. Precio por unidad de contenido: una fila por producto, una línea gris del más barato al más
#    caro y un punto por comercio (todas las filas en la MISMA unidad).
grafico_precio_unitario <- function(d, unidad, maximo = 12L) {
  productos <- utils::head(unique(d$producto), maximo)
  d <- d[d$producto %in% productos, ]
  rango <- lapply(seq_along(productos), function(i) {
    v <- d$precio_unitario[d$producto == productos[i]]
    list(x = i - 1, low = min(v), high = max(v))
  })
  hc <- highcharter::highchart() |>
    highcharter::hc_chart(type = "columnrange", inverted = TRUE, spacingRight = 36) |>
    highcharter::hc_xAxis(categories = as.list(productos), lineWidth = 0, tickLength = 0, gridLineWidth = 0,
                          labels = list(style = list(color = TINTA, fontSize = "12px", width = "230px", textOverflow = "ellipsis"))) |>
    highcharter::hc_yAxis(type = "logarithmic", title = list(text = sprintf("COP por %s (escala logarítmica)", unidad)),
                          tickPositions = log10(.marcas_log(min(d$precio_unitario), max(d$precio_unitario))),
                          labels = list(format = "$ {value:,.0f}", rotation = 0, autoRotation = FALSE, overflow = "allow")) |>
    highcharter::hc_tooltip(shared = FALSE, headerFormat = "<b>{point.key}</b><br>",
                            pointFormat = sprintf("<span style='color:{point.color}'>●</span> {series.name}: <b>$ {point.y:,.1f}</b> por %s<br>Precio del empaque: $ {point.precio:,.0f}", unidad)) |>
    highcharter::hc_add_series(name = "Rango entre comercios", data = rango, color = LINEA, borderRadius = 3,
                               pointWidth = 4, enableMouseTracking = FALSE, showInLegend = FALSE)
  for (cid in unique(d$comercio_id)) {
    s <- d[d$comercio_id == cid, ]
    puntos <- lapply(which(productos %in% s$producto), function(i) {
      fila <- s[s$producto == productos[i], ][1, ]
      list(x = i - 1, y = round(fila$precio_unitario, 2), precio = fila$precio)
    })
    hc <- highcharter::hc_add_series(hc, type = "scatter", name = s$comercio[1], color = color_comercio(cid),
                                     logo = unname(LOGOS_COMERCIO[cid]), marker = list(symbol = simbolo_comercio(cid)), data = puntos)
  }
  .tema(hc)
}

# 3. Distribución de precios de la categoría por comercio (caja: cuartiles; bigotes: percentiles 5 y 95).
grafico_distribucion <- function(d) {
  puntos <- lapply(seq_len(nrow(d)), function(i) {
    col <- color_comercio(d$comercio_id[i])
    list(x = i - 1, low = d$p05[i], q1 = d$q1[i], median = d$mediana[i], q3 = d$q3[i], high = d$p95[i],
         color = col, fillColor = paste0(col, "26"), medianColor = col, n = d$observaciones[i])
  })
  highcharter::highchart() |>
    highcharter::hc_chart(type = "boxplot", inverted = TRUE, spacingRight = 44) |>
    highcharter::hc_xAxis(categories = as.list(paste0(logo_html(d$comercio_id, 20), d$comercio)), lineWidth = 0, tickLength = 0,
                          labels = list(useHTML = TRUE, style = list(color = TINTA, fontSize = "13px", fontWeight = "500"))) |>
    highcharter::hc_yAxis(type = "logarithmic", title = list(text = "Precio (COP, escala logarítmica)"),
                          tickPositions = log10(.marcas_log(min(d$p05), max(d$p95))),   # Highcharts 9: posiciones en log10
                          labels = list(format = "$ {value:,.0f}", rotation = 0, autoRotation = FALSE, overflow = "allow")) |>
    highcharter::hc_legend(enabled = FALSE) |>
    highcharter::hc_tooltip(useHTML = TRUE, headerFormat = "<b>{point.key}</b><br>", pointFormat = paste0(
      "Percentil 95: $ {point.high:,.0f}<br>Cuartil 3: $ {point.q3:,.0f}<br><b>Mediana: $ {point.median:,.0f}</b><br>",
      "Cuartil 1: $ {point.q1:,.0f}<br>Percentil 5: $ {point.low:,.0f}<br><span style='color:#56656c'>{point.n:,.0f} observaciones con precio</span>")) |>
    highcharter::hc_add_series(name = "Precio", data = puntos, lineWidth = 1.5, medianWidth = 3, whiskerWidth = 2,
                               whiskerLength = "35%", stemWidth = 1.5, pointWidth = 26) |>
    .tema()
}

# 4. ¿En qué productos vale más la pena comparar? Ahorro entre el comercio más caro y el más barato;
#    el color indica el comercio más barato (gris si hay empate).
grafico_ahorro <- function(d, maximo = 12L) {
  d <- utils::head(d[d$ahorro_cop > 0, ], maximo)
  d$grupo <- ifelse(d$n_empatados > 1, "empate", d$comercio_id_min)
  hc <- highcharter::highchart() |>
    highcharter::hc_chart(type = "bar") |>
    highcharter::hc_xAxis(categories = as.list(d$producto), lineWidth = 0, tickLength = 0,
                          labels = list(style = list(color = TINTA, fontSize = "12px", width = "230px", textOverflow = "ellipsis"))) |>
    highcharter::hc_yAxis(title = list(text = "Ahorro frente al comercio más caro (COP)"),
                          labels = list(rotation = 0, autoRotation = FALSE, formatter = highcharter::JS(
                            "function () { return this.value >= 1000 ? '$ ' + Highcharts.numberFormat(this.value / 1000, 0) + ' mil' : '$ ' + this.value; }"))) |>
    highcharter::hc_plotOptions(bar = list(grouping = FALSE, dataLabels = list(
      enabled = TRUE, format = "{point.pct:.0f} %", style = list(fontWeight = "500", color = TINTA_2, textOutline = "none")))) |>
    highcharter::hc_tooltip(headerFormat = "<b>{point.key}</b><br>", pointFormat = paste0(
      "Más barato en <b>{point.barato}</b>: $ {point.pmin:,.0f}<br>Más caro: $ {point.pmax:,.0f}<br>",
      "Ahorro: <b>$ {point.y:,.0f}</b> ({point.pct:.1f} %)"))
  for (g in unique(d$grupo)) {
    datos <- lapply(which(d$grupo == g), function(i) {
      list(x = i - 1, y = d$ahorro_cop[i], pct = d$ahorro_pct[i], barato = d$comercio_mas_barato[i],
           pmin = d$precio_min[i], pmax = d$precio_max[i])
    })
    hc <- highcharter::hc_add_series(hc, data = datos, color = color_comercio(g), logo = unname(LOGOS_COMERCIO[g]),
      name = if (g == "empate") "Empate entre comercios" else paste("Más barato en", d$comercio_mas_barato[d$grupo == g][1]))
  }
  .tema(hc)
}

# 5. Composición del catálogo de cada comercio por subcategoría, en porcentaje (columnas al 100 %).
#    d: comercio_id, comercio, grupo, anuncios, pct (calculado en SQL).
grafico_composicion <- function(d) {
  comercios <- unique(d[c("comercio_id", "comercio")])
  grupos <- unique(d$grupo[d$grupo != "Otras"]); grupos <- c(grupos, if (any(d$grupo == "Otras")) "Otras")
  hc <- highcharter::highchart() |>
    highcharter::hc_chart(type = "column") |>
    highcharter::hc_xAxis(categories = as.list(paste0(logo_html(comercios$comercio_id, 22), "<br>", comercios$comercio)),
                          lineWidth = 0, tickLength = 0,
                          labels = list(useHTML = TRUE, style = list(color = TINTA, fontSize = "12.5px", textAlign = "center"))) |>
    highcharter::hc_yAxis(max = 100, tickInterval = 25, title = list(text = "% de los anuncios del comercio"),
                          labels = list(format = "{value} %")) |>
    highcharter::hc_plotOptions(column = list(stacking = "percent", borderWidth = 1, borderColor = SUPERFICIE, borderRadius = 0,
                                              pointPadding = 0.12, groupPadding = 0.12, maxPointWidth = 120,
      dataLabels = list(enabled = TRUE, format = "{point.pct:.0f} %", filter = list(property = "pct", operator = ">", value = 7),
                        style = list(color = "#ffffff", fontWeight = "600", fontSize = "11.5px", textOutline = "none")))) |>
    highcharter::hc_legend(reversed = FALSE, align = "center", verticalAlign = "bottom") |>
    highcharter::hc_tooltip(useHTML = TRUE, headerFormat = "", pointFormat = paste0(
      "<b>{series.name}</b><br>{point.n:,.0f} anuncios · <b>{point.pct:.1f} %</b> del catálogo"))
  for (k in seq_along(grupos)) {
    g <- grupos[k]
    datos <- lapply(seq_len(nrow(comercios)), function(i) {
      fila <- d[d$comercio_id == comercios$comercio_id[i] & d$grupo == g, ]
      if (nrow(fila) == 0) list(y = 0, n = 0, pct = 0) else list(y = fila$anuncios, n = fila$anuncios, pct = fila$pct)
    })
    hc <- highcharter::hc_add_series(hc, name = g, data = datos,
                                     color = if (g == "Otras") COLOR_OTRAS else COLORES_SUBCATEGORIA[(k - 1) %% 6 + 1])
  }
  .tema(hc)
}

# 6. Marcas de cada comercio (packed bubble): una burbuja por marca, de tamaño proporcional al
#    número de anuncios; las burbujas de cada comercio se agrupan y llevan su color.
grafico_burbujas <- function(d) {
  hc <- highcharter::highchart() |>
    highcharter::hc_chart(type = "packedbubble") |>
    highcharter::hc_legend(align = "center", verticalAlign = "bottom") |>
    highcharter::hc_tooltip(useHTML = TRUE, headerFormat = "", pointFormat = "<b>{point.name}</b> en {series.name}<br>{point.value:,.0f} anuncios") |>
    highcharter::hc_plotOptions(packedbubble = list(
      minSize = "20%", maxSize = "85%", zMin = 0,
      layoutAlgorithm = list(splitSeries = TRUE, gravitationalConstant = 0.02, seriesInteraction = FALSE, maxIterations = 400,
                             dragBetweenSeries = FALSE, parentNodeLimit = TRUE,
                             parentNodeOptions = list(bubblePadding = 8, marker = list(
                               fillColor = "#f3ebdd", fillOpacity = 1, lineColor = LINEA, lineWidth = 1))),
      parentNode = list(allowPointSelect = FALSE),
      marker = list(fillOpacity = 0.85, lineWidth = 1.5, lineColor = SUPERFICIE),
      dataLabels = list(enabled = TRUE, format = "{point.name}", filter = list(property = "y", operator = ">", value = 0),
                        style = list(color = "#ffffff", textOutline = "none", fontWeight = "500", fontSize = "10px", textOverflow = "ellipsis"),
                        parentNodeFormat = "{point.series.name}", parentNodeTextPath = list(enabled = FALSE))))
  for (cid in unique(d$comercio_id)) {
    s <- d[d$comercio_id == cid, ]
    tope <- max(s$anuncios)
    hc <- highcharter::hc_add_series(hc, name = s$comercio[1], color = color_comercio(cid), logo = unname(LOGOS_COMERCIO[cid]),
      data = lapply(seq_len(nrow(s)), function(i) list(name = s$marca[i], value = s$anuncios[i],
                                                       # solo se rotulan las burbujas grandes
                                                       y = if (s$anuncios[i] >= 0.45 * tope) 1 else 0)))
  }
  .tema(hc)
}

# 8. Sunburst: catálogo de cada comercio por subcategoría y marca. El anillo interior es el comercio
#    (con su color); los anillos externos heredan el color en tonos más claros. Clic para acercar.
grafico_sunburst <- function(d) {
  pts <- list(list(id = "raiz", parent = "", name = "Cat\u00e1logo", color = SUPERFICIE))
  for (cid in unique(d$comercio_id)) {
    dc <- d[d$comercio_id == cid, ]
    pts[[length(pts) + 1]] <- list(id = cid, parent = "raiz", name = dc$comercio[1], color = color_comercio(cid),
                                   logo = unname(LOGOS_COMERCIO[cid]))
    for (sub in unique(dc$subcategoria)) {
      sid <- paste(cid, sub, sep = "|")
      pts[[length(pts) + 1]] <- list(id = sid, parent = cid, name = sub)
      ds <- dc[dc$subcategoria == sub, ]
      for (i in seq_len(nrow(ds))) {
        pts[[length(pts) + 1]] <- list(id = paste(sid, ds$marca[i], sep = "|"), parent = sid, name = ds$marca[i], value = ds$anuncios[i])
      }
    }
  }
  highcharter::highchart() |>
    highcharter::hc_add_dependency("modules/sunburst.js") |>
    highcharter::hc_chart(type = "sunburst") |>
    highcharter::hc_tooltip(useHTML = TRUE, headerFormat = "",
                            pointFormat = "<b>{point.name}</b><br>{point.value:,.0f} anuncios") |>
    highcharter::hc_add_series(type = "sunburst", data = pts, allowTraversingTree = TRUE, cursor = "pointer",
      borderColor = SUPERFICIE, borderWidth = 1.5, name = "Cat\u00e1logo",
      levels = list(
        list(level = 1, levelIsConstant = FALSE, dataLabels = list(enabled = FALSE)),
        list(level = 2, colorByPoint = FALSE, levelSize = list(unit = "weight", value = 1.1),
             dataLabels = list(rotationMode = "parallel", style = list(fontSize = "12px", fontWeight = "600", color = "#ffffff", textOutline = "none"))),
        list(level = 3, colorVariation = list(key = "brightness", to = 0.18), levelSize = list(unit = "weight", value = 1),
             dataLabels = list(rotationMode = "parallel", filter = list(property = "outerArcLength", operator = ">", value = 34),
                               style = list(fontSize = "10.5px", fontWeight = "500", color = "#ffffff", textOutline = "none"))),
        list(level = 4, colorVariation = list(key = "brightness", to = 0.3), levelSize = list(unit = "weight", value = 1),
             dataLabels = list(rotationMode = "perpendicular", filter = list(property = "outerArcLength", operator = ">", value = 22),
                               style = list(fontSize = "9.5px", fontWeight = "400", color = TINTA, textOutline = "none"))))) |>
    .tema()
}

# 7. Waffle (HTML): de cada 100 productos comparables, ¿en cuántos es más barato cada comercio?
#    conteo: data.frame(grupo = comercio_id o "empate", comercio, n). Cada cuadro = 1 %.
waffle_html <- function(conteo) {
  total <- sum(conteo$n)
  cuota <- 100 * conteo$n / total
  cuadros <- floor(cuota); resto <- 100 - sum(cuadros)
  if (resto > 0) {                                 # método del mayor residuo: siempre suman 100
    extra <- order(cuota - cuadros, decreasing = TRUE)[seq_len(resto)]
    cuadros[extra] <- cuadros[extra] + 1
  }
  colores <- ifelse(conteo$grupo == "empate", COLOR_EMPATE, color_comercio(conteo$grupo))
  celdas <- unlist(mapply(function(col, k) rep(sprintf('<i style="--c:%s"></i>', col), k), colores, cuadros, SIMPLIFY = FALSE))
  leyenda <- vapply(seq_len(nrow(conteo)), function(i) {
    marca <- if (conteo$grupo[i] == "empate") "" else sprintf('<img src="%s" alt="">', LOGOS_COMERCIO[[conteo$grupo[i]]])
    sprintf('<div><span class="muestra" style="background:%s"></span>%s<span>%s</span><span class="valor">%s · %s</span></div>',
            colores[i], marca, htmltools::htmlEscape(conteo$comercio[i]), entero(conteo$n[i]), pct(cuota[i], 0))
  }, "")
  htmltools::HTML(paste0('<div class="waffle" role="img" aria-label="Distribución de los productos comparables según el comercio más barato">',
                         paste(celdas, collapse = ""), '</div><div class="waffle-leyenda">', paste(leyenda, collapse = ""), "</div>"))
}

# Ficha de un comercio para la pestaña «Comercios».
ficha_comercio <- function(cid, nombre, cifra, cifra_texto, filas) {
  htmltools::div(class = "ficha", style = sprintf("--color-comercio:%s", color_comercio(cid)),
    htmltools::div(class = "ficha-logo", htmltools::img(src = unname(LOGOS_GRANDES[cid]), alt = nombre)),
    htmltools::div(class = "ficha-nombre", nombre),
    htmltools::div(class = "ficha-cifra", cifra),
    htmltools::div(class = "ficha-cifra-texto", cifra_texto),
    htmltools::tags$dl(lapply(names(filas), function(k) htmltools::tagList(htmltools::tags$dt(k), htmltools::tags$dd(filas[[k]])))))
}
