# Mineria de Datos - Taller 2
# Observatorio de precios | interfaz redisenada
# Solo utiliza consultas de db.R. No ejecuta scraping por si misma.

paquetes <- c("shiny", "bslib", "plotly", "DT", "DBI", "RSQLite",
              "future", "promises")
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltantes)) {
  stop("Instala estos paquetes: ", paste(faltantes, collapse = ", "))
}

if (utils::packageVersion("shiny") < "1.8.1") {
  stop("Se requiere Shiny 1.8.1 o posterior para ExtendedTask")
}
# Un trabajador independiente: evita bloquear la interfaz durante el scraper.
future::plan(future::multisession, workers = 2L)

source("db.R", encoding = "UTF-8", local = TRUE)
source("canasta.R", encoding = "UTF-8", local = TRUE)
source("comparacion_ejecuciones.R", encoding = "UTF-8", local = TRUE)
if (!file.exists("comparador_precios.sqlite")) {
  stop("Ejecuta la aplicacion desde la carpeta taller_2")
}

con_inicio <- abrir_db()
opciones <- opciones_db(con_inicio)
ejecuciones_inicio <- ejecuciones_db(con_inicio)
ejecuciones_canasta_inicio <- listar_ejecuciones_canasta_db(con_inicio)
ejecuciones_comparacion_inicio <- listar_ejecuciones_comparacion_db(con_inicio)
productos_canasta_inicio <- listar_productos_canasta_db(con_inicio)
cerrar_db(con_inicio)

etiquetas_comparacion <- stats::setNames(
  ejecuciones_comparacion_inicio$ejecucion_id,
  paste0(substr(ejecuciones_comparacion_inicio$fecha_hora, 1L, 16L),
         " · ", ejecuciones_comparacion_inicio$comercios, " comercios")
)
comparacion_actual_default <- if (nrow(ejecuciones_comparacion_inicio))
  ejecuciones_comparacion_inicio$ejecucion_id[1L] else NULL
comparacion_anterior_default <- if (nrow(ejecuciones_comparacion_inicio) >= 2L)
  ejecuciones_comparacion_inicio$ejecucion_id[2L] else NULL

fechas_registradas <- as.Date(substr(ejecuciones_inicio$fecha_hora_inicio, 1L, 10L))
fechas_registradas <- fechas_registradas[!is.na(fechas_registradas)]
if (!length(fechas_registradas)) fechas_registradas <- Sys.Date()

paleta_comercios <- c(
  "Cruz Verde" = "#138D82",
  "Droguerías Cafam" = "#D28A37",
  "La Rebaja" = "#6779CA"
)

formatear_numero <- function(x, digitos = 0L) {
  if (!length(x) || is.na(x[1]) || !is.finite(suppressWarnings(as.numeric(x[1])))) return("—")
  format(round(as.numeric(x[1]), digits = digitos),
         big.mark = ".", decimal.mark = ",", nsmall = digitos,
         trim = TRUE, scientific = FALSE)
}
formatear_cop <- function(x) paste0("$", formatear_numero(x))
formatear_numero_vector <- function(x) {
  format(round(x, 2), big.mark = ".", decimal.mark = ",",
         trim = TRUE, scientific = FALSE)
}
mensaje_vacio <- function(texto) {
  plotly::layout(plotly::plot_ly(),
    annotations = list(list(text = texto, x = 0.5, y = 0.5,
      xref = "paper", yref = "paper", showarrow = FALSE)),
    xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)"
  )
}

tarjeta_kpi <- function(titulo, output_id, detalle, clase = "") {
  shiny::div(class = paste("metric", clase),
    shiny::div(class = "metric-title", titulo),
    shiny::div(class = "metric-value", shiny::textOutput(output_id, inline = TRUE)),
    shiny::div(class = "metric-note", detalle)
  )
}

tarjeta_plot <- function(titulo, texto, output_id, alto = "350px", control = NULL) {
  shiny::tags$section(class = "panel chart-panel",
    shiny::div(class = "panel-heading",
      shiny::div(shiny::h3(titulo), shiny::p(texto))
    ),
    if (!is.null(control)) shiny::div(class = "chart-control", control),
    plotly::plotlyOutput(output_id, height = alto)
  )
}

css <- "
:root {--navy:#182F49; --ink:#23374B; --muted:#6E8091; --line:#E4EAF0;
       --canvas:#F6F8FB; --teal:#0D8278; --white:#FFFFFF;}
html, body {min-height:100%; background:var(--canvas); color:var(--ink);}
body {font-family:'Inter', 'Segoe UI', Arial, sans-serif; font-size:14px;}
.container-fluid {max-width:1700px; padding:0 28px 30px;}
.topbar {background:#fff; border-bottom:1px solid var(--line); padding:17px 0 16px;
         margin:0 -28px 25px; padding-left:29px; padding-right:29px;
         display:flex; align-items:center; justify-content:space-between; gap:14px;}
.brand {display:flex; align-items:center; gap:13px;}
.brand-icon {height:42px; width:42px; display:flex; align-items:center;
             justify-content:center; background:#E8F5F2; border-radius:12px;
             color:var(--teal); font-size:22px; font-weight:800;}
.brand-name {font-size:18px; font-weight:800; letter-spacing:-.5px; color:var(--navy); line-height:1.2;}
.brand-subtitle {font-size:12px; color:var(--muted); margin-top:3px;}
.topbar-tag {font-size:11px; letter-spacing:.07em; color:#698197; font-weight:700;}
.dashboard {display:grid; grid-template-columns:266px minmax(0,1fr); gap:24px; align-items:start;}
.filters {background:#fff; border:1px solid var(--line); border-radius:16px;
          padding:22px 18px; position:sticky; top:18px; box-shadow:0 3px 15px #29405808;}
.filter-title {display:flex; align-items:center; justify-content:space-between; margin-bottom:5px;}
.filter-title h2 {font-size:15px; font-weight:800; margin:0; color:var(--navy);}
.filter-pill {font-size:10px; font-weight:800; color:var(--teal); background:#EAF6F3;
              border-radius:6px; padding:5px 7px;}
.filters-description {font-size:12px; line-height:1.55; color:var(--muted); margin:0 0 17px;}
.filters .form-group {margin-bottom:15px;}
.filters label {font-size:12px; font-weight:700; margin-bottom:6px; color:#405367;}
.filters input[type=text], .filters .form-control {border:1px solid #D9E2EA;
        border-radius:9px; min-height:38px; background:#fff; box-shadow:none; font-size:13px;}
.filters .selectize-input {border:1px solid #D9E2EA; border-radius:9px;
        box-shadow:none; padding:8px; min-height:39px; font-size:12px;}
.filters .selectize-input .item {background:#EDF4F9 !important; color:#244763 !important;
        border:0 !important; border-radius:5px; padding:3px 6px !important;}
.filters .irs--shiny .irs-bar, .filters .irs--shiny .irs-handle {background:var(--teal);}
.filters .irs--shiny .irs-from, .filters .irs--shiny .irs-to,
.filters .irs--shiny .irs-single {background:var(--navy);}
.extra-filters {border-top:1px solid var(--line); margin-top:11px; padding-top:14px;}
.extra-filters summary {font-size:12px; font-weight:750; cursor:pointer; color:var(--teal);
                        margin-bottom:10px; list-style:none; user-select:none;}
.extra-filters summary:after {content:'⌄'; float:right; color:var(--muted);}
.extra-filters[open] summary:after {content:'⌃';}
.filter-footer {border-radius:10px; background:#F4F7FA; padding:11px 12px; margin-top:16px;
                 font-size:11px; line-height:1.6; color:var(--muted);}
.content {min-width:0;}
.hero {border:1px solid #E3EAF0; background:#fff; padding:24px 27px; border-radius:16px;
       margin-bottom:20px; display:flex; align-items:center; justify-content:space-between;
       gap:18px; box-shadow:0 4px 15px #29405806;}
.eyebrow {font-weight:800; font-size:10px; text-transform:uppercase; color:var(--teal);
          letter-spacing:.12em; margin-bottom:7px;}
.hero h1 {font-weight:800; letter-spacing:-.8px; font-size:27px; line-height:1.22;
          color:var(--navy); margin:0 0 7px;}
.hero p {font-size:13px; margin:0; color:var(--muted); line-height:1.5;}
.hero-date {background:#EDF6F4; border:1px solid #D8ECE8; border-radius:10px;
            padding:11px 15px; flex-shrink:0; min-width:185px;}
.hero-date-label {font-size:10px; color:#52837F; font-weight:800; letter-spacing:.07em;
                  margin-bottom:4px; text-transform:uppercase;}
.hero-date .shiny-text-output {font-size:12px; font-weight:750; color:#166C64;}
.main-tabs .nav-tabs {border:0; gap:7px; padding:0; margin-bottom:18px; flex-wrap:wrap;}
.main-tabs .nav-tabs .nav-link {border:1px solid transparent; background:transparent;
        color:#63798C; font-size:13px; font-weight:720; border-radius:9px;
        padding:10px 15px; transition:background .15s;}
.main-tabs .nav-tabs .nav-link:hover {background:#E9EFF5; color:var(--navy);}
.main-tabs .nav-tabs .nav-link.active {color:#fff; background:var(--navy); border-color:var(--navy);}
.main-tabs .tab-content {overflow:visible; min-height:0;}
.section-title {margin:0 0 14px; color:var(--navy); font-size:15px; font-weight:800;}
.metrics-grid {display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:13px; margin-bottom:14px;}
.metric {border:1px solid var(--line); background:#fff; border-radius:13px; padding:20px;
         min-width:0; min-height:122px; box-shadow:0 3px 13px #263D5506; position:static;}
.metric:before {content:''; display:block; width:24px; height:3px; border-radius:10px;
                background:#D5E1EB; margin-bottom:14px;}
.metric.accent:before {background:var(--teal);}
.metric.indigo:before {background:#667ACC;}
.metric.gold:before {background:#D28A37;}
.metric-title {font-size:12px; font-weight:650; color:var(--muted); margin-bottom:8px;}
.metric-value {font-size:27px; font-weight:830; letter-spacing:-.8px; line-height:1.1;
               color:var(--navy); overflow-wrap:anywhere;}
.metric-note {font-size:11px; color:#8A9AAA; margin-top:8px; line-height:1.4;}
.summary-band {background:#fff; border:1px solid var(--line); border-radius:13px;
               display:grid; grid-template-columns:repeat(3,minmax(0,1fr));
               margin-bottom:19px; box-shadow:0 3px 13px #263D5505;}
.summary-cell {padding:17px 20px; min-width:0;}
.summary-cell + .summary-cell {border-left:1px solid var(--line);}
.summary-label {font-size:11px; color:var(--muted); font-weight:650; margin-bottom:6px;}
.summary-value {font-size:20px; font-weight:800; color:var(--navy); white-space:nowrap;}
.panel {background:#fff; border:1px solid var(--line); border-radius:14px;
        margin-bottom:18px; padding:21px 23px 15px; box-shadow:0 3px 13px #263D5506;
        height:auto !important; overflow:visible !important;}
.panel-heading {display:flex; align-items:start; justify-content:space-between;
                gap:12px; margin-bottom:13px;}
.panel h3 {font-weight:790; font-size:15px; margin:0 0 5px; color:var(--navy);}
.panel-heading p, .panel-description {font-size:12px; color:var(--muted); margin:0; line-height:1.5;}
.chart-control {max-width:420px; margin-bottom:9px;}
.chart-control label {color:#5D7388; font-size:12px; font-weight:700;}
.chart-control .form-control {border-radius:8px; border-color:#DAE3EB; font-size:12px;}
.chart-panel .plotly, .chart-panel .html-widget {max-width:100%;}
.charts-two {display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:16px;}
.charts-two .panel {min-width:0;}
.table-panel .dataTables_wrapper {padding:8px 0 0; font-size:12px;}
.table-panel table.dataTable {width:100% !important;}
.table-panel th {color:#4C637A; background:#F5F8FA;}
.catalog-toolbar {display:flex; align-items:end; gap:16px; flex-wrap:wrap; margin:10px 0 15px;}
.catalog-toolbar .form-group {margin-bottom:0; width:145px;}
.catalog-toolbar .btn {border-radius:9px; background:var(--teal); border-color:var(--teal);
                       font-weight:700; font-size:12px; padding:9px 12px;}
.page-indicator {font-size:12px; color:var(--muted); padding-bottom:9px;}
.footer {font-size:11px; color:#92A1AE; margin:13px 0 0; line-height:1.65; text-align:center;}
/* Modulo 6: canasta de compras */
.canasta-config {display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;margin:12px 0 14px;}
.canasta-config .form-group {min-width:0;}
.canasta-cantidades {display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin:14px 0 18px;}
.canasta-cantidades .form-group {min-width:0;padding:12px;border:1px solid var(--line);border-radius:10px;background:#F8FAFC;margin-bottom:0;}
.canasta-cantidades label {font-size:12px;font-weight:680;color:#405367;line-height:1.4;}
.canasta-cantidades input {width:100%;border-radius:8px;border-color:#D9E2EA;}
.canasta-nota {padding:12px 14px;border:1px solid #DAE9E6;border-radius:10px;background:#F4FAF8;font-size:12px;color:#355C57;line-height:1.65;margin:10px 0 18px;}
.canasta-config label {font-weight:700;font-size:12px;color:#405367;}
.canasta-accion {background:var(--teal);color:white;font-weight:750;border-radius:9px;padding:9px 18px;border:0;margin-bottom:8px;}
@media(max-width:700px) {.canasta-config,.canasta-cantidades{grid-template-columns:1fr;}}
@media(max-width:1250px) {.metrics-grid {grid-template-columns:repeat(2,minmax(0,1fr));}
  .dashboard {grid-template-columns:250px minmax(0,1fr); gap:17px;}}
@media(max-width:940px) {.dashboard {grid-template-columns:1fr;}
  .filters {position:static;} .charts-two {grid-template-columns:1fr;}
  .hero-date {display:none;} .container-fluid {padding:0 15px 25px;}
  .topbar {margin:0 -15px 20px; padding:15px;}}
@media(max-width:540px) {.metrics-grid {grid-template-columns:repeat(2,minmax(0,1fr)); gap:9px;}
  .metric {padding:14px; min-height:112px;} .metric-value {font-size:22px;}
  .hero {padding:20px;} .hero h1 {font-size:21px;}
  .summary-cell {padding:12px 9px;} .summary-value {font-size:16px;}
  .panel {padding:15px 12px 9px;} .topbar-tag {display:none;}}
"

ui <- shiny::fluidPage(
  theme = bslib::bs_theme(version = 5, bg = "#F6F8FB", fg = "#23374B", primary = "#0D8278"),
  shiny::tags$head(
    shiny::tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    shiny::tags$style(shiny::HTML(css))
  ),
  shiny::tags$header(class = "topbar",
    shiny::div(class = "brand",
      shiny::div(class = "brand-icon", "▥"),
      shiny::div(
        shiny::div(class = "brand-name", "Observatorio de precios"),
        shiny::div(class = "brand-subtitle", "Medicamentos dermatológicos · Taller 2")
      )
    ),
    shiny::div(class = "topbar-tag", "MINERÍA DE DATOS  ·  UNAL")
  ),
  shiny::div(class = "dashboard",
    shiny::tags$aside(class = "filters",
      shiny::div(class = "filter-title", shiny::h2("Filtros"),
                 shiny::span(class = "filter-pill", "SQL")),
      shiny::p(class = "filters-description", "Explora los registros con los filtros que necesites."),
      shiny::textInput("busqueda", "Buscar medicamento (tabla y CSV)", placeholder = "Nombre o referencia"),
      shiny::selectizeInput("comercio", "Droguerías",
        choices = opciones$comercios, selected = opciones$comercios, multiple = TRUE),
      shiny::sliderInput("precio", "Rango de precios · COP", min = 0, max = 2000000,
                         value = c(0, 2000000), step = 10000, pre = "$", sep = "."),
      shiny::tags$details(class = "extra-filters",
        shiny::tags$summary("Filtros avanzados"),
        shiny::selectizeInput("marca", "Marca", choices = NULL,
          selected = NULL, multiple = TRUE, options = list(placeholder = "Todas")),
        shiny::selectizeInput("subcategoria", "Subcategoría",
          choices = opciones$subcategorias, selected = NULL, multiple = TRUE,
          options = list(placeholder = "Todas")),
        shiny::dateRangeInput("fechas", "Fechas de consulta",
          start = min(fechas_registradas), end = max(fechas_registradas),
          min = min(fechas_registradas), max = max(fechas_registradas),
          format = "yyyy-mm-dd", separator = " a "),
        shiny::selectInput("tipo", "Comparabilidad",
          choices = c("Todos" = "todos", "Solo comparables" = "si", "No comparables" = "no")),
        shiny::selectInput("promocion", "Promoción",
          choices = c("Todas" = "todas", "Con promoción" = "si", "Sin promoción" = "no")),
        shiny::checkboxInput("categoria", "Solo categoría dermatológica", FALSE)
      ),
      shiny::div(class = "filter-footer", "Datos provenientes de las capturas de Cafam, Cruz Verde y La Rebaja. Los precios no son cotizaciones en tiempo real.")
    ),
    shiny::tags$main(class = "content",
      shiny::div(class = "hero",
        shiny::div(
          shiny::div(class = "eyebrow", "Inteligencia de precios"),
          shiny::h1("Decisiones de compra con datos"),
          shiny::p("Explora precios, compara droguerías y analiza su evolución.")
        ),
        shiny::div(class = "hero-date",
          shiny::div(class = "hero-date-label", "Última captura"),
          shiny::textOutput("fecha_actualizacion")
        )
      ),
      shiny::div(class = "main-tabs",
        shiny::tabsetPanel(id = "vista", type = "tabs",
          shiny::tabPanel("Panorama", value = "resumen",
            shiny::h2(class = "section-title", "Visión general"),
            shiny::div(class = "metrics-grid",
              tarjeta_kpi("Ofertas disponibles", "kpi_ofertas", "Último precio válido", "accent"),
              tarjeta_kpi("Droguerías", "kpi_comercios", "Comercios consultados"),
              tarjeta_kpi("Productos homologados", "kpi_productos", "Comparables distintos", "indigo"),
              tarjeta_kpi("Promociones", "kpi_promos", "Ofertas identificadas", "gold")
            ),
            shiny::div(class = "summary-band",
              shiny::div(class = "summary-cell",
                shiny::div(class = "summary-label", "Precio promedio"),
                shiny::div(class = "summary-value", shiny::textOutput("kpi_promedio", inline = TRUE))
              ),
              shiny::div(class = "summary-cell",
                shiny::div(class = "summary-label", "Precio mínimo"),
                shiny::div(class = "summary-value", shiny::textOutput("kpi_minimo", inline = TRUE))
              ),
              shiny::div(class = "summary-cell",
                shiny::div(class = "summary-label", "Precio máximo"),
                shiny::div(class = "summary-value", shiny::textOutput("kpi_maximo", inline = TRUE))
              )
            ),
            tarjeta_plot("Evolución de los precios", "Precio promedio por comercio y fecha de captura.",
              "grafico_evolucion", alto = "350px",
              control = shiny::selectInput("producto_serie", "Producto comparable",
                choices = c("Promedio de los ocho productos" = "todos",
                  stats::setNames(as.character(opciones$productos$producto_comun_id),
                                  opciones$productos$producto_comun)), width = "100%")
            )
          ),
          shiny::tabPanel("Análisis", value = "analisis",
            shiny::h2(class = "section-title", "Comparación por presentación"),
            tarjeta_plot("Precio por gramo o mililitro", "Cada producto se compara entre las tres droguerías.",
              "grafico_unitario", alto = "500px",
              control = shiny::selectInput("producto_unitario", "Producto comparable",
                choices = stats::setNames(as.character(opciones$productos$producto_comun_id),
                                  opciones$productos$producto_comun),
                selected = if (nrow(opciones$productos))
                  opciones$productos$producto_comun_id[1L] else NULL,
                width = "100%")
            ),
            shiny::div(class = "charts-two",
              tarjeta_plot("Distribución de precios", "Intervalos de 20.000 COP por comercio.",
                "grafico_distribucion", alto = "320px"),
              tarjeta_plot("Subcategorías", "Número de ofertas según clasificación.",
                "grafico_subcategorias", alto = "320px")
            )
          ),
          shiny::tabPanel("Cambios de precio", value = "cambios",
            shiny::h2(class = "section-title", "Comparar ejecuciones reales"),
            shiny::tags$section(class = "panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Capturas y umbral"),
                  shiny::p("Mismo anuncio y misma droguería. Las ausencias no equivalen a agotamiento."))
              ),
              shiny::div(class = "canasta-config",
                shiny::selectInput("comparacion_anterior", "Ejecución anterior",
                  choices = etiquetas_comparacion,
                  selected = comparacion_anterior_default, width = "100%"),
                shiny::selectInput("comparacion_actual", "Ejecución actual",
                  choices = etiquetas_comparacion,
                  selected = comparacion_actual_default, width = "100%")
              ),
              shiny::sliderInput("umbral_cambio", "Variación destacada (%)",
                min = 0, max = 100, value = 10, step = 1),
              shiny::textOutput("mensaje_comparacion")
            ),
            shiny::div(class = "metrics-grid",
              tarjeta_kpi("Comparaciones", "kpi_comparaciones", "Anuncios comparables entre fechas"),
              tarjeta_kpi("Cambios efectivos", "kpi_cambios", "Variaciones de precio", "accent"),
              tarjeta_kpi("Aumentos", "kpi_aumentos", "Precios mayores", "gold"),
              tarjeta_kpi("Disminuciones", "kpi_disminuciones", "Precios menores", "indigo")
            ),
            shiny::tags$section(class = "panel table-panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Estados entre las dos capturas"),
                  shiny::p("Incluye anuncios nuevos, no observados y observados sin precio válido."))
              ),
              shiny::tableOutput("resumen_comparacion")
            ),
            shiny::tags$section(class = "panel table-panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Detalle por anuncio y comercio"),
                  shiny::p("COP, variación porcentual y resaltado conforme al umbral elegido."))
              ),
              DT::DTOutput("tabla_cambios")
            )
          ),
          shiny::tabPanel("Catálogo", value = "catalogo",
            shiny::h2(class = "section-title", "Consulta de ofertas"),
            shiny::tags$section(class = "panel table-panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Precios más recientes"),
                           shiny::p("Tabla filtrada y paginada desde SQLite."))
              ),
              shiny::div(class = "catalog-toolbar",
                shiny::numericInput("pagina", "Página", value = 1L,
                                    min = 1L, max = 10000L, step = 1L),
                shiny::div(class = "page-indicator", shiny::textOutput("info_pagina")),
                shiny::downloadButton("descargar_csv", "Descargar CSV")
              ),
              DT::DTOutput("tabla_catalogo")
            )
          ),
          shiny::tabPanel("Canasta de compras", value = "canasta",
            shiny::h2(class = "section-title", "Canasta de productos homologados"),
            shiny::tags$section(class = "panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Diseña tu canasta"),
                  shiny::p("Escoge una captura y las cantidades de cada presentación. Solo se comparan precios de esa ejecución."))
              ),
              shiny::div(class = "canasta-config",
                shiny::selectInput("ejecucion_canasta", "Ejecución de precios",
                  choices = stats::setNames(ejecuciones_canasta_inicio$ejecucion_id,
                    paste0(substr(ejecuciones_canasta_inicio$fecha_hora, 1L, 16L),
                      " · ", ejecuciones_canasta_inicio$comercios, " comercios")),
                  selected = if (nrow(ejecuciones_canasta_inicio))
                    ejecuciones_canasta_inicio$ejecucion_id[1L] else NULL,
                  width = "100%"),
                shiny::selectizeInput("productos_canasta", "Presentaciones comparables",
                  choices = stats::setNames(productos_canasta_inicio$producto_comun_id,
                                            productos_canasta_inicio$producto_comun),
                  selected = intersect(c("P01", "P02"), productos_canasta_inicio$producto_comun_id),
                  multiple = TRUE, width = "100%",
                  options = list(placeholder = "Selecciona uno o varios productos"))
              ),
              shiny::uiOutput("cantidades_canasta"),
              shiny::actionButton("calcular_canasta", "Calcular canasta", class = "canasta-accion"),
              shiny::p(class = "panel-description",
                "Las cantidades son envases. Si cambias una selección o cantidad, vuelve a calcular para actualizar los resultados.")
            ),
            shiny::uiOutput("estado_canasta"),
            shiny::div(class = "metrics-grid",
              tarjeta_kpi("Mejor tienda completa", "canasta_mejor_total", "Costo en COP", "accent"),
              tarjeta_kpi("Compra combinada", "canasta_mixto_total", "Costo en COP", "indigo"),
              tarjeta_kpi("Ahorro adicional", "canasta_ahorro_total", "Frente a la mejor tienda completa", "gold"),
              tarjeta_kpi("Ahorro porcentual", "canasta_ahorro_pct", "Frente a la mejor tienda completa")
            ),
            shiny::tags$section(class = "panel table-panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Costo por droguería"),
                  shiny::p("No se muestra un total si un comercio no tiene todos los productos."))
              ),
              shiny::div(style = "overflow-x:auto;", shiny::tableOutput("tabla_canasta_comercios"))
            ),
            shiny::tags$section(class = "panel table-panel",
              shiny::div(class = "panel-heading",
                shiny::div(shiny::h3("Compra combinada más económica"),
                  shiny::p("Se elige el menor precio documentado por producto; los empates se indican."))
              ),
              shiny::div(style = "overflow-x:auto;", shiny::tableOutput("tabla_canasta_mixta"))
            ),
            shiny::div(class = "canasta-nota",
              "Precios históricos de una sola captura. No incluyen envío, mínimos de compra ni condiciones de las promociones. ",
              "Los sitios pueden no confirmar existencias; verifica precios y disponibilidad antes de comprar.")
          ),
          shiny::tabPanel("Actualización", value = "actualizacion",
            shiny::h2(class = "section-title", "Actualizar desde el scraper"),
            shiny::tags$section(class = "panel",
              shiny::div(class = "panel-heading",
                shiny::div(
                  shiny::h3("Recolección controlada"),
                  shiny::p("La actualización reutiliza scraper.R, valida antes de insertar y registra los resultados por droguería.")
                )
              ),
              shiny::selectInput("modo_actualizacion", "Modo de ejecución",
                choices = c(
                  "Demostración sin conexión (no modifica SQLite)" = "offline",
                  "Captura real desde los sitios web" = "online"
                ), selected = "offline", width = "100%"),
              shiny::div(style = "max-width:310px; margin-bottom:14px;",
                bslib::input_task_button("iniciar_actualizacion", "Ejecutar proceso",
                  label_busy = "Procesando...", class = "btn-primary")
              ),
              shiny::p(class = "panel-description",
                "Modo offline: reprocesa el RAW del Taller 1 y no crea una captura nueva. ",
                "Modo online: visita los tres comercios, conserva nuevas copias RAW y escribe en SQLite."),
              shiny::tags$hr(),
              shiny::strong("Estado del proceso"),
              shiny::div(style = "margin:9px 0 16px;", shiny::textOutput("estado_actualizacion")),
              shiny::div(class = "table-panel", shiny::tableOutput("resumen_actualizacion")),
              shiny::div(style = "margin-top:12px;", shiny::textOutput("detalle_actualizacion"))
            )
          )
        )
      ),
      shiny::tags$footer(class = "footer",
        "Universidad Nacional de Colombia · Minería de Datos · Precios en COP · ",
        "Los precios no incluyen costos de envío y no garantizan disponibilidad actual.")
    )
  )
)

server <- function(input, output, session) {
  con <- abrir_db()
  session$onSessionEnded(function() cerrar_db(con))

  # Cargar las marcas desde el servidor, sin enviar miles de opciones al navegador.
  shiny::updateSelectizeInput(session, "marca",
    choices = opciones$marcas, server = TRUE)

  # La revisión se incrementa solo si termina una captura en línea.
  # De esta forma los gráficos y KPI se vuelven a consultar sin reiniciar Shiny.
  revision_bd <- shiny::reactiveVal(0L)
  # Modulo 6: canasta calculada directamente desde SQLite, sin escritura.
  canasta_resultado <- shiny::reactiveVal(NULL)

  # Una nueva captura real puede añadir una ejecución seleccionable.
  shiny::observeEvent(revision_bd(), {
    nuevas <- listar_ejecuciones_canasta_db(con)
    if (nrow(nuevas)) {
      shiny::updateSelectInput(session, "ejecucion_canasta",
        choices = stats::setNames(nuevas$ejecucion_id,
          paste0(substr(nuevas$fecha_hora, 1L, 16L),
                 " · ", nuevas$comercios, " comercios")),
        selected = nuevas$ejecucion_id[1L])
    }
    canasta_resultado(NULL)
  }, ignoreInit = TRUE)

  output$cantidades_canasta <- shiny::renderUI({
    ids <- input$productos_canasta
    if (is.null(ids) || !length(ids)) {
      return(shiny::p(class = "panel-description",
        "Selecciona al menos una presentación para indicar sus cantidades."))
    }
    shiny::div(class = "canasta-cantidades",
      lapply(ids, function(id) {
        nombre <- productos_canasta_inicio$producto_comun[
          match(id, productos_canasta_inicio$producto_comun_id)]
        id_control <- paste0("cantidad_canasta_", id)
        anterior <- shiny::isolate(input[[id_control]])
        if (length(anterior) != 1L || is.na(anterior)) anterior <- 1L
        shiny::numericInput(id_control, paste0(nombre, " · envases"),
          value = anterior, min = 1L, max = 100L, step = 1L, width = "100%")
      })
    )
  })

  # Evita mostrar resultados antiguos si el usuario cambia cantidades o selección.
  shiny::observeEvent({
    list(input$ejecucion_canasta, input$productos_canasta,
      lapply(input$productos_canasta, function(id) {
        input[[paste0("cantidad_canasta_", id)]]
      }))
  }, {
    canasta_resultado(NULL)
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$calcular_canasta, {
    ids <- input$productos_canasta
    if (is.null(ids) || !length(ids)) {
      canasta_resultado(list(error = "Selecciona al menos un producto homologado."))
      return(invisible(NULL))
    }
    cantidades <- vapply(ids, function(id) {
      valor <- input[[paste0("cantidad_canasta_", id)]]
      if (length(valor) != 1L || is.null(valor)) return(NA_real_)
      suppressWarnings(as.numeric(valor))
    }, numeric(1))
    names(cantidades) <- ids
    resultado <- tryCatch(
      calcular_canasta_db(con, input$ejecucion_canasta, cantidades),
      error = function(e) list(error = conditionMessage(e))
    )
    canasta_resultado(resultado)
  })

  output$estado_canasta <- shiny::renderUI({
    r <- canasta_resultado()
    if (is.null(r)) {
      return(shiny::div(class = "canasta-nota",
        "Selecciona los productos y pulsa «Calcular canasta» para comparar precios."))
    }
    if (!is.null(r$error)) {
      return(shiny::div(class = "canasta-nota",
        paste0("No se pudo calcular: ", r$error)))
    }
    comercio <- if (is.na(r$mejor_comercio_completo)) {
      "No hay una tienda con la canasta completa."
    } else {
      paste0("Mejor tienda completa: ", r$mejor_comercio_completo,
             " (", formatear_cop(r$mejor_total_cop), ").")
    }
    shiny::div(class = "canasta-nota",
      shiny::tags$strong(comercio), shiny::tags$p(r$mensaje),
      shiny::tags$p(r$advertencia))
  })

  output$canasta_mejor_total <- shiny::renderText({
    r <- canasta_resultado()
    if (is.null(r) || !is.null(r$error)) return("—")
    formatear_cop(r$mejor_total_cop)
  })
  output$canasta_mixto_total <- shiny::renderText({
    r <- canasta_resultado()
    if (is.null(r) || !is.null(r$error)) return("—")
    formatear_cop(r$costo_mixto_cop)
  })
  output$canasta_ahorro_total <- shiny::renderText({
    r <- canasta_resultado()
    if (is.null(r) || !is.null(r$error)) return("—")
    formatear_cop(r$ahorro_cop)
  })
  output$canasta_ahorro_pct <- shiny::renderText({
    r <- canasta_resultado()
    if (is.null(r) || !is.null(r$error)) return("—")
    paste0(formatear_numero(r$ahorro_pct, 2L), " %")
  })

  output$tabla_canasta_comercios <- shiny::renderTable({
    r <- canasta_resultado()
    if (is.null(r) || !is.null(r$error)) return(NULL)
    d <- r$por_comercio
    d$costo_total_cop <- vapply(d$costo_total_cop, function(x) {
      if (is.na(x)) "No calculable" else formatear_cop(x)
    }, character(1))
    d$productos_faltantes[d$productos_faltantes == ""] <- "—"
    names(d) <- c("Droguería", "Estado", "Encontrados", "Requeridos",
                  "Total (COP)", "Productos faltantes")
    d
  }, striped = TRUE, bordered = TRUE, spacing = "s")

  output$tabla_canasta_mixta <- shiny::renderTable({
    r <- canasta_resultado()
    if (is.null(r) || !is.null(r$error) || !nrow(r$detalle_mixto)) return(NULL)
    d <- r$detalle_mixto
    d$precio_envase_cop <- vapply(d$precio_envase_cop, formatear_cop, character(1))
    d$subtotal_cop <- vapply(d$subtotal_cop, formatear_cop, character(1))
    d$empate <- ifelse(d$empate, "Sí", "No")
    names(d) <- c("ID", "Producto", "Cantidad", "Droguería recomendada",
                  "Precio/envase (COP)", "Subtotal (COP)",
                  "Empate", "Comercios empatados")
    d
  }, striped = TRUE, bordered = TRUE, spacing = "s")


  tarea_actualizar <- shiny::ExtendedTask$new(function(modo) {
    promises::future_promise({
      source("scraper.R", encoding = "UTF-8")
      source("validacion.R", encoding = "UTF-8")
      source("previsualizacion_t2.R", encoding = "UTF-8")
      source("actualizacion_t2.R", encoding = "UTF-8")

      resultado <- actualizar_precios_t2(modo = modo)
      estado_ausencias <- "No aplica: en modo offline no se modifican datos."
      if (identical(modo, "online")) {
        # El archivo histórico contiene una función que se ejecuta al hacer source().
        # Solo se llama después de que se termina la captura online.
        estado_ausencias <- tryCatch({
          if (!file.exists("paso23_disponibilidad_t2.R")) {
            stop("Falta paso23_disponibilidad_t2.R")
          }
          source("paso23_disponibilidad_t2.R", encoding = "UTF-8")
          "Se actualizaron las ausencias de las capturas completas."
        }, error = function(e) paste("Pendiente de revisión:", conditionMessage(e)))
      }
      # El resumen online indica cuántos anuncios dejaron de observarse,
      # sin confundirlos con observaciones que fueron rechazadas.
      if (identical(modo, "online") &&
          file.exists("comparador_precios.sqlite") &&
          "comercio" %in% names(resultado$resumen)) {
        con_res <- DBI::dbConnect(RSQLite::SQLite(),
                                 "comparador_precios.sqlite",
                                 flags = RSQLite::SQLITE_RO)
        resultado$resumen$no_observados <- tryCatch({
          faltantes <- DBI::dbGetQuery(con_res, "
            SELECT c.nombre AS comercio, COUNT(*) AS n
            FROM productos_no_observados n
            JOIN comercios c ON c.comercio_id = n.comercio_id
            WHERE n.ejecucion_id = ?
            GROUP BY c.nombre
          ", params = list(resultado$ejecucion_id))
          indices <- match(resultado$resumen$comercio, faltantes$comercio)
          valores <- faltantes$n[indices]
          valores[is.na(valores)] <- 0L
          as.integer(valores)
        }, error = function(e) rep(NA_integer_, nrow(resultado$resumen)))
        DBI::dbDisconnect(con_res)
      }
      list(
        modo = modo,
        ejecucion_id = if (identical(modo, "online")) resultado$ejecucion_id else NA_character_,
        resumen = resultado$resumen,
        ausencias = estado_ausencias,
        finalizado = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
    })
  }) |> bslib::bind_task_button("iniciar_actualizacion")

  shiny::observeEvent(input$iniciar_actualizacion, {
    shiny::req(input$modo_actualizacion %in% c("online", "offline"))
    tarea_actualizar$invoke(input$modo_actualizacion)
  })

  # Únicamente el éxito de una actualización en línea invalida las consultas.
  shiny::observe({
    if (!identical(tarea_actualizar$status(), "success")) return()
    terminado <- tarea_actualizar$result()
    if (identical(terminado$modo, "online")) {
      revision_bd(shiny::isolate(revision_bd()) + 1L)
      e <- ejecuciones_db(con)
      fechas_nuevas <- as.Date(substr(e$fecha_hora_inicio, 1L, 10L))
      fechas_nuevas <- fechas_nuevas[!is.na(fechas_nuevas)]
      if (length(fechas_nuevas)) {
        shiny::updateDateRangeInput(session, "fechas",
          start = min(fechas_nuevas), end = max(fechas_nuevas),
          min = min(fechas_nuevas), max = max(fechas_nuevas))
      }
    }
  })

  output$estado_actualizacion <- shiny::renderText({
    estado <- tarea_actualizar$status()
    if (identical(estado, "initial")) return("Sin ejecutar. Comienza por probar el modo sin conexión.")
    if (identical(estado, "running")) return("Procesando. Puedes continuar utilizando los filtros y las demás pestañas.")
    if (identical(estado, "error")) {
      detalle <- tryCatch(tarea_actualizar$result(), error = function(e) conditionMessage(e))
      return(paste("Error:", detalle))
    }
    resultado <- tarea_actualizar$result()
    if (identical(resultado$modo, "offline")) {
      paste0("Demostración sin conexión terminada: ", resultado$finalizado,
             ". No se creó una nueva captura ni se modificó SQLite.")
    } else {
      paste0("Captura en línea terminada: ", resultado$finalizado,
             ". Identificador: ", resultado$ejecucion_id)
    }
  })

  output$resumen_actualizacion <- shiny::renderTable({
    if (!identical(tarea_actualizar$status(), "success")) return(NULL)
    tarea_actualizar$result()$resumen
  }, striped = TRUE, bordered = TRUE, digits = 0)

  output$detalle_actualizacion <- shiny::renderText({
    if (!identical(tarea_actualizar$status(), "success")) return("")
    tarea_actualizar$result()$ausencias
  })

  filtros <- shiny::reactive({
    shiny::req(input$precio)
    fechas <- input$fechas
    lista <- list(
      comercio = if (is.null(input$comercio) || !length(input$comercio)) {
        # Ningun comercio seleccionado: cero resultados, no todos.
        "__SIN_COMERCIOS__"
      } else input$comercio,
      marca = input$marca,
      subcategoria = input$subcategoria,
      precio_min = input$precio[1],
      precio_max = input$precio[2],
      texto = input$busqueda,
      comparable = switch(input$tipo, si = TRUE, no = FALSE, NULL),
      promocion = switch(input$promocion, si = TRUE, no = FALSE, NULL),
      categoria = if (isTRUE(input$categoria)) TRUE else NULL
    )
    if (length(fechas) == 2L && all(!is.na(fechas))) {
      lista$desde <- as.character(fechas[1])
      lista$hasta <- as.character(fechas[2])
    }
    lista
  })

  # Cache por sesion: los resultados se comparten entre salidas que usan
  # los mismos filtros. revision_bd() invalida al terminar una captura online.
  kpis <- shiny::reactive({
    revision_bd()
    indicadores_db(con, filtros())
  }) |> shiny::bindCache(filtros(), revision_bd(), cache = "session")
  # Las dos ejecuciones, el umbral y la revisión invalidan esta caché.
  comparacion_seleccionada <- shiny::reactive({
    revision_bd()
    shiny::req(input$comparacion_anterior, input$comparacion_actual,
               input$umbral_cambio)
    tryCatch(
      comparar_ejecuciones_db(con, input$comparacion_anterior,
        input$comparacion_actual, input$umbral_cambio),
      error = function(e) list(error = conditionMessage(e))
    )
  }) |> shiny::bindCache(input$comparacion_anterior, input$comparacion_actual,
                          input$umbral_cambio, revision_bd(), cache = "session")

  shiny::observeEvent(revision_bd(), {
    ejecuciones_nuevas <- listar_ejecuciones_comparacion_db(con)
    if (nrow(ejecuciones_nuevas) >= 2L) {
      elecciones <- stats::setNames(ejecuciones_nuevas$ejecucion_id,
        paste0(substr(ejecuciones_nuevas$fecha_hora, 1L, 16L),
           " · ", ejecuciones_nuevas$comercios, " comercios"))
      shiny::updateSelectInput(session, "comparacion_actual",
        choices = elecciones, selected = ejecuciones_nuevas$ejecucion_id[1L])
      shiny::updateSelectInput(session, "comparacion_anterior",
        choices = elecciones, selected = ejecuciones_nuevas$ejecucion_id[2L])
    }
  }, ignoreInit = TRUE)

  output$mensaje_comparacion <- shiny::renderText({
    r <- comparacion_seleccionada()
    if (!is.null(r$error)) return(paste("No se pudo comparar:", r$error))
    paste0("Anuncios analizados: ", nrow(r$detalle),
      ". Cambios con magnitud ≥ ", formatear_numero(r$umbral_pct),
      "%: ", r$cambios_grandes, ". No observado no significa agotado.")
  })

  output$fecha_actualizacion <- shiny::renderText({
    revision_bd()
    e <- ejecuciones_db(con)
    if (nrow(e)) {
      f <- max(as.character(e$fecha_hora_inicio), na.rm = TRUE)
      substr(f, 1, 10)
    } else "Sin registros"
  })

  output$kpi_ofertas <- shiny::renderText(formatear_numero(kpis()$ofertas))
  output$kpi_comercios <- shiny::renderText(formatear_numero(kpis()$comercios))
  output$kpi_productos <- shiny::renderText(formatear_numero(kpis()$productos_comparables))
  output$kpi_promos <- shiny::renderText(formatear_numero(kpis()$promociones))
  output$kpi_promedio <- shiny::renderText(formatear_cop(kpis()$precio_promedio_cop))
  output$kpi_minimo <- shiny::renderText(formatear_cop(kpis()$precio_minimo_cop))
  output$kpi_maximo <- shiny::renderText(formatear_cop(kpis()$precio_maximo_cop))

  numero_comparacion <- function(estado = NULL) {
    r <- comparacion_seleccionada()
    if (!is.null(r$error)) return("—")
    if (is.null(estado)) {
      return(formatear_numero(sum(r$resumen$cantidad[
        r$resumen$estado %in% c("Aumento", "Disminucion", "Sin cambio")
      ])))
    }
    formatear_numero(sum(r$resumen$cantidad[r$resumen$estado %in% estado]))
  }
  output$kpi_comparaciones <- shiny::renderText(numero_comparacion())
  output$kpi_cambios <- shiny::renderText(numero_comparacion(c("Aumento", "Disminucion")))
  output$kpi_aumentos <- shiny::renderText(numero_comparacion("Aumento"))
  output$kpi_disminuciones <- shiny::renderText(numero_comparacion("Disminucion"))

  output$grafico_evolucion <- plotly::renderPlotly({
    revision_bd()
    id <- if (identical(input$producto_serie, "todos")) NULL else input$producto_serie
    d <- serie_comparables_db(con, producto_comun_id = id)
    if (!nrow(d)) return(mensaje_vacio("Sin información histórica disponible"))
    d$comercio <- factor(d$comercio, levels = names(paleta_comercios))
    d$etiqueta <- paste0(as.character(d$comercio), "<br>", d$fecha,
                        "<br>Precio promedio: $", formatear_numero_vector(round(d$precio_promedio_cop)))
    plotly::plot_ly(d,
      x = ~fecha, y = ~precio_promedio_cop,
      color = ~comercio, colors = unname(paleta_comercios),
      type = "scatter", mode = "lines+markers",
      text = ~etiqueta, hoverinfo = "text", line = list(width = 3),
      marker = list(size = 9)
    ) |>
      plotly::layout(
        xaxis = list(title = "Fecha de captura"),
        yaxis = list(title = "Precio promedio (COP)", tickformat = ",.0f"),
        legend = list(orientation = "h", x = 0, y = 1.16),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
        margin = list(t = 55, b = 55)
      )
  })

  output$grafico_unitario <- plotly::renderPlotly({
    revision_bd()
    id <- if (identical(input$producto_unitario, "todos")) NULL else input$producto_unitario
    d <- comparables_db(con,
      comercio = if (length(input$comercio)) input$comercio else "__SIN_COMERCIOS__",
      producto_comun_id = id
    )
    d <- d[!is.na(d$precio_por_unidad_cop) & d$precio_por_unidad_cop > 0, , drop = FALSE]
    if (!nrow(d)) return(mensaje_vacio("No hay precios unitarios para estos filtros"))
    d$comercio <- factor(d$comercio, levels = names(paleta_comercios))
    d$etiqueta <- paste0(d$producto_comun, "<br>", as.character(d$comercio),
                        "<br>$", formatear_numero_vector(d$precio_por_unidad_cop),
                        " por ", d$unidad_contenido)
    d$producto_comun <- factor(d$producto_comun,
      levels = rev(unique(as.character(d$producto_comun))))
    plotly::plot_ly(d,
      x = ~precio_por_unidad_cop, y = ~producto_comun,
      color = ~comercio, colors = unname(paleta_comercios),
      type = "bar", orientation = "h", text = ~etiqueta, hoverinfo = "text"
    ) |>
      plotly::layout(
        barmode = "group",
        xaxis = list(title = paste0("COP por ", if (nrow(d)) d$unidad_contenido[1L] else "unidad"), tickformat = ",.0f"),
        yaxis = list(title = "", automargin = TRUE),
        legend = list(orientation = "h", x = 0, y = 1.16),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
        margin = list(t = 65, b = 50, l = 210, r = 20)
      )
  })

  output$grafico_distribucion <- plotly::renderPlotly({
    revision_bd()
    d <- distribucion_db(con, filtros(), ancho = 20000)
    if (!nrow(d)) return(mensaje_vacio("Sin ofertas para los filtros seleccionados"))
    d$comercio <- factor(d$comercio, levels = names(paleta_comercios))
    plotly::plot_ly(d,
      x = ~precio_desde_cop, y = ~cantidad, color = ~comercio,
      colors = unname(paleta_comercios), type = "bar"
    ) |>
      plotly::layout(
        barmode = "group",
        xaxis = list(title = "Precio inicial del intervalo (COP)", tickformat = ",.0f"),
        yaxis = list(title = "Número de ofertas"),
        legend = list(orientation = "h", x = 0, y = 1.16),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
        margin = list(t = 55, b = 50)
      )
  })

  output$grafico_subcategorias <- plotly::renderPlotly({
    revision_bd()
    d <- subcategorias_db(con, filtros(), limite = 12L)
    if (!nrow(d)) return(mensaje_vacio("Sin subcategorías para los filtros seleccionados"))
    d$subcategoria_completa <- as.character(d$subcategoria)
    d$subcategoria <- vapply(d$subcategoria, function(x) {
      x <- gsub("^/+|/+$", "", x)
      x <- gsub("/", " · ", x, fixed = TRUE)
      if (nchar(x) > 52L) paste0(substr(x, 1L, 49L), "…") else x
    }, character(1))
    d$subcategoria <- factor(d$subcategoria, levels = rev(unique(d$subcategoria)))
    plotly::plot_ly(d, x = ~ofertas, y = ~subcategoria,
                    type = "bar", orientation = "h",
                    marker = list(color = "#138D82"),
                    hoverinfo = "text",
                    text = ~paste0(subcategoria_completa, ": ", ofertas, " ofertas")) |>
      plotly::layout(
        xaxis = list(title = "Ofertas"), yaxis = list(title = "", automargin = TRUE),
        paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
        margin = list(t = 25, l = 125, b = 50)
      )
  })

  output$resumen_comparacion <- shiny::renderTable({
    r <- comparacion_seleccionada()
    if (!is.null(r$error)) return(NULL)
    d <- r$resumen
    names(d) <- c("Estado", "Cantidad")
    d
  }, striped = TRUE, bordered = TRUE, spacing = "s")

  output$tabla_cambios <- DT::renderDT({
    r <- comparacion_seleccionada()
    if (!is.null(r$error)) {
      return(DT::datatable(data.frame(Información = r$error),
                           rownames = FALSE))
    }
    d <- r$detalle
    if (!nrow(d)) return(DT::datatable(data.frame(
      Información = "No se encontraron anuncios entre estas dos ejecuciones"),
      rownames = FALSE))
    d$supera_umbral <- ifelse(d$supera_umbral == 1L, "Sí", "No")
    names(d) <- c("Droguería", "Producto", "ID anuncio", "Antes (COP)",
                  "Ahora (COP)", "Cambio (COP)", "Cambio (%)", "Estado",
                  "Supera umbral", "Fecha anterior", "Fecha actual")
    DT::datatable(d, rownames = FALSE,
      options = list(pageLength = 10, scrollX = TRUE, searchHighlight = TRUE,
                     order = list(list(5, "desc"))))
  }, server = FALSE)

  # La clave incluye la pagina; evita mostrar una pagina equivocada
  # cuando el usuario navega el catalogo.
  datos_catalogo <- shiny::reactive({
    revision_bd()
    tabla_precios_db(con, filtros(), limite = 100L,
                     pagina = as.integer(input$pagina))
  }) |> shiny::bindCache(filtros(), input$pagina, revision_bd(),
                         cache = "session")

  output$info_pagina <- shiny::renderText({
    n <- as.integer(kpis()$ofertas[1])
    paste0("Página ", input$pagina, " de ", max(1L, ceiling(n / 100L)),
           " · ", formatear_numero(n), " ofertas")
  })

  output$tabla_catalogo <- DT::renderDT({
    d <- datos_catalogo()
    names(d) <- c("Comercio", "Producto", "Marca", "Subcategoría", "Presentación",
                  "Precio COP", "Precio unitario COP", "Unidad", "Precio anterior COP",
                  "Promoción", "Comparable", "Fecha de captura", "Disponibilidad",
                  "URL", "Ejecución")
    DT::datatable(d, rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE,
                                 autoWidth = TRUE, searching = FALSE))
  }, server = FALSE)

  output$descargar_csv <- shiny::downloadHandler(
    filename = function() paste0("precios_filtrados_", Sys.Date(), ".csv"),
    content = function(file) {
      n <- as.integer(kpis()$ofertas[1])
      if (is.na(n) || n < 1L) {
        utils::write.csv(data.frame(), file, row.names = FALSE, fileEncoding = "UTF-8")
        return(invisible(NULL))
      }
      total_paginas <- ceiling(n / 1000)
      bloques <- lapply(seq_len(total_paginas), function(p) {
        tabla_precios_db(con, filtros(), limite = 1000L, pagina = p)
      })
      utils::write.csv(do.call(rbind, bloques), file,
                       row.names = FALSE, fileEncoding = "UTF-8", na = "")
    }
  )
}

shiny::shinyApp(ui = ui, server = server)
