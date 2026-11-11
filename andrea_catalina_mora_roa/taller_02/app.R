suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(promises)
  library(future)
})
source("db.R", encoding = "UTF-8")
source("graficos.R", encoding = "UTF-8")

plan(multisession, workers = 2)          # la actualización corre en otro proceso (no bloquea).
                                         # Con workers = 1, future la ejecutaría en el mismo proceso.
options(shiny.sanitize.errors = TRUE)    # sin mensajes técnicos para el usuario

RUTA_TRABAJO <- ruta_base_trabajo()
con <- abrir_base(RUTA_TRABAJO)          # una conexión de lectura por proceso, cerrada al salir
onStop(function() cerrar_base(con))

COMERCIOS_APP <- listar_comercios(con)
ELECCION_COMERCIOS <- setNames(COMERCIOS_APP$comercio, COMERCIOS_APP$nombre)

etiqueta_ejecucion <- function(e) sprintf("%s · %s (%s)", fecha_legible(e$ejecucion_id), e$ejecucion_id, e$estado)

# Mensaje claro en lugar de un gráfico vacío
sin_datos <- function(x, msg = "No hay datos para los filtros elegidos. Amplíe la selección.") {
  shiny::validate(shiny::need(!is.null(x) && (is.null(nrow(x)) || nrow(x) > 0), msg))
}

tarjeta_grafico <- function(titulo, ..., alto = "520px", icono = "chart-column")
  card(full_screen = TRUE, height = alto, class = "tarjeta",
       card_header(span(icon(icono), titulo)), ...)

# Tinta verde petróleo para la navegación, acentos menta y fondos suaves. Los colores de los
# comercios (graficos.R: naranja, azul y verde) se reservan para los datos y no se usan en la interfaz.
PALETA <- list(tinta = "#12343B", primario = "#0F766E", primario_claro = "#E3F2EF",
               acento = "#F2B544", fondo = "#F5F7F6", texto = "#1F2D33", suave = "#5E6E73")

tema <- bs_theme(
  version = 5,
  bg = "#FFFFFF", fg = PALETA$texto,
  primary = PALETA$primario, secondary = PALETA$suave, success = "#2E8B57",
  info = "#2C7DA0", warning = PALETA$acento, danger = "#C0392B",
  base_font = font_collection(font_google("Inter", local = FALSE), "system-ui", "sans-serif"),
  heading_font = font_collection(font_google("Outfit", local = FALSE), "system-ui", "sans-serif"),
  font_scale = 0.95,
  "border-radius" = "0.75rem", "card-border-width" = "0px",
  "input-border-color" = "#D5DEDB"
) |> bs_add_rules(sprintf("
  body { background-color: %1$s; }
  .bslib-page-navbar > .navbar, .navbar.navbar-static-top, nav.navbar {
    background-color: %2$s !important; border-bottom: 3px solid %3$s; }
  .navbar .navbar-brand, .navbar .nav-link { color: #E8F1EF !important; }
  .navbar .nav-link { font-weight: 500; border-radius: .5rem; padding: .45rem .7rem !important; margin: 0 .05rem;
                      font-size: .9rem; }
  .navbar .nav-link:hover { background: rgba(255,255,255,.08); }
  .navbar .nav-link.active { background: %3$s !important; color: %2$s !important; }
  .marca { display: flex; align-items: center; gap: .65rem; line-height: 1.1; }
  .marca .logo { width: 38px; height: 38px; border-radius: 10px; background: %3$s; color: %2$s;
                 display: inline-flex; align-items: center; justify-content: center; font-size: 1.1rem; }
  .marca .titulo { font-family: Outfit, system-ui, sans-serif; font-weight: 700; font-size: 1.15rem; color: #fff; }
  .marca .sub { font-size: .72rem; color: #A9C7C1; letter-spacing: .02em; }
  .fecha-datos { display: inline-block; margin-top: .3rem; background: rgba(255,255,255,.1); color: #fff;
                 border: 1px solid rgba(255,255,255,.25); border-radius: 999px; padding: .12rem .6rem;
                 font-size: .72rem; white-space: nowrap; }
  .fecha-datos .fa, .fecha-datos svg { margin-right: .35rem; color: %4$s; }
  .bslib-sidebar-layout > .sidebar { background-color: #FFFFFF; border-right: 1px solid #E3E9E7; }
  .sidebar .sidebar-title { font-family: Outfit, sans-serif; font-weight: 700; color: %2$s; }
  .sidebar .control-label, .sidebar label.form-label { font-size: .74rem; font-weight: 600; text-transform: uppercase;
                                    letter-spacing: .04em; color: %5$s; }
  .sidebar .checkbox label, .sidebar .radio label { text-transform: none; letter-spacing: 0; font-size: .88rem;
                                                    font-weight: 400; color: %6$s; }
  .card, .tarjeta { border: none; box-shadow: 0 1px 2px rgba(18,52,59,.06), 0 6px 18px rgba(18,52,59,.06); }
  .card-header { background: #FFFFFF; border-bottom: 1px solid #EEF2F1; font-family: Outfit, sans-serif;
                 font-weight: 600; color: %2$s; }
  .card-header .fa, .card-header svg { color: %7$s; margin-right: .45rem; }
  .bslib-value-box { border: none !important; box-shadow: 0 1px 2px rgba(18,52,59,.06), 0 6px 18px rgba(18,52,59,.07); }
  .bslib-value-box .value-box-title { font-size: .74rem; text-transform: uppercase; letter-spacing: .04em; opacity: .85;
                                      margin-bottom: .15rem; }
  .bslib-value-box .value-box-value { font-family: Outfit, sans-serif; font-weight: 700; font-size: 1.55rem;
                                      line-height: 1.15; margin-bottom: .25rem; }
  .bslib-value-box .value-box-area { padding: .9rem 1rem .9rem .4rem !important; }
  .bslib-value-box .value-box-showcase { padding-left: 1.1rem !important; opacity: .85; }
  .bslib-value-box .value-box-showcase i { font-size: 2rem !important; }
  .bslib-value-box p { font-size: .78rem; opacity: .85; margin-bottom: 0; }
  .banda-datos { background: linear-gradient(90deg, %2$s, %7$s); color: #fff; border-radius: .9rem;
                 padding: 1rem 1.25rem; margin-bottom: 1rem; display: flex; gap: 1rem; align-items: center; }
  .banda-datos .icono { font-size: 1.6rem; opacity: .9; }
  .banda-datos .t1 { font-family: Outfit, sans-serif; font-weight: 600; font-size: 1.05rem; }
  .banda-datos .t2 { font-size: .82rem; opacity: .9; }
  .chip { display: inline-block; padding: .1rem .55rem; border-radius: 999px; font-size: .75rem; font-weight: 600; color: #fff; }
  .table { font-size: .86rem; } .table thead th { color: %5$s; font-weight: 600; border-bottom-width: 1px; }
  table.dataTable thead th { background: %8$s; color: %2$s; }
  .btn-primary { font-weight: 600; } .nota { font-size: .8rem; color: %5$s; }
  details.ayuda summary { cursor: pointer; font-size: .82rem; color: %7$s; font-weight: 600; }
  details.ayuda p { font-size: .8rem; color: %5$s; margin: .4rem 0 0; }
  .irs--shiny .irs-bar, .irs--shiny .irs-from, .irs--shiny .irs-to, .irs--shiny .irs-single { background: %7$s; border-color: %7$s; }
", PALETA$fondo, PALETA$tinta, PALETA$acento, PALETA$acento, PALETA$suave, PALETA$texto, PALETA$primario,
   PALETA$primario_claro))

tema_vb <- function(tipo = c("base", "acento", "verde", "ambar"))
  switch(match.arg(tipo),
         base   = value_box_theme(bg = "#FFFFFF", fg = PALETA$tinta),
         acento = value_box_theme(bg = PALETA$primario_claro, fg = PALETA$tinta),
         verde  = value_box_theme(bg = "#E7F5EC", fg = "#1E5C3A"),
         ambar  = value_box_theme(bg = "#FDF3DF", fg = "#6B4A0E"))

caja <- function(titulo, valor, detalle, icono, tipo = "base")
  value_box(titulo, valor, p(detalle), showcase = icon(icono),
            showcase_layout = showcase_left_center(width = "72px", max_height = "2.4rem"),
            theme = tema_vb(tipo))

barra_filtros <- sidebar(
  width = 300, title = span(icon("sliders"), " Filtros"), bg = "#FFFFFF",
  checkboxGroupInput("comercios", "Comercio", choices = ELECCION_COMERCIOS, selected = COMERCIOS_APP$comercio),
  radioButtons("modo_tiempo", "Periodo", inline = TRUE,
               choices = c("Ejecución" = "ejecucion", "Rango de fechas" = "fechas")),
  conditionalPanel("input.modo_tiempo == 'ejecucion'",
                   selectInput("ejecucion", "Ejecución del scraper", choices = NULL)),
  conditionalPanel("input.modo_tiempo == 'fechas'",
                   dateRangeInput("fechas", "Fechas de consulta", language = "es", separator = "a",
                                  format = "dd/mm/yyyy")),
  selectizeInput("subcategorias", "Subcategoría", choices = NULL, multiple = TRUE,
                 options = list(placeholder = "Todas")),
  selectizeInput("marcas", "Marca", choices = NULL, multiple = TRUE, options = list(placeholder = "Todas")),
  sliderInput("precio", "Precio (COP)", min = 0, max = 250000, value = c(0, 250000), step = 1000, pre = "$",
              sep = ".", ticks = FALSE),
  textInput("texto", "Buscar en nombre o texto del anuncio", placeholder = "p. ej. naproxeno 250"),
  uiOutput("aviso_texto"),
  checkboxInput("solo_promo", "Solo en promoción", FALSE),
  checkboxInput("solo_comparables", "Solo comparables (mismo EAN y contenido en los 3 comercios)", FALSE),
  checkboxInput("solo_categoria", "Solo productos de la categoría (dolor e inflamación)", TRUE)
)

pestana_resumen <- nav_panel(
  "Resumen", icon = icon("gauge-high"),
  uiOutput("encabezado_datos"),
  layout_column_wrap(
    width = 1/3, fill = FALSE,
    caja("Productos observados", textOutput("ind_productos"), textOutput("ind_productos_det", inline = TRUE), "pills", "acento"),
    caja("Última ejecución", textOutput("ind_ultima"), textOutput("ind_ultima_det", inline = TRUE), "calendar-check"),
    caja("En promoción", textOutput("ind_promo"), textOutput("ind_promo_det", inline = TRUE), "tags", "ambar"),
    caja("Precio mediano", textOutput("ind_mediana"), textOutput("ind_mediana_det", inline = TRUE), "scale-balanced"),
    caja("Ahorro máximo entre comercios", textOutput("ind_ahorro"), textOutput("ind_ahorro_det", inline = TRUE), "piggy-bank", "verde"),
    caja("Cambios de precio", textOutput("ind_cambios"), textOutput("ind_cambios_det", inline = TRUE), "arrow-trend-up", "acento")
  ),
  layout_columns(
    col_widths = c(7, 5),
    tarjeta_grafico("3. Distribución de precios por comercio", icono = "chart-simple",
                    checkboxInput("escala_log", "Escala logarítmica", TRUE),
                    highchartOutput("graf_distribucion", height = "420px")),
    card(class = "tarjeta", card_header(span(icon("store"), "Por comercio y por subcategoría")),
         tableOutput("tabla_por_comercio"), tableOutput("tabla_mediana_subcat"))
  )
)

pestana_evolucion <- nav_panel(
  "Evolución", icon = icon("chart-line"),
  layout_columns(
    col_widths = c(12, 12),
    tarjeta_grafico("1. Evolución del precio de un producto comparable", icono = "chart-line",
                    selectizeInput("producto_serie", "Producto comparable", choices = NULL, width = "100%"),
                    highchartOutput("graf_evolucion", height = "400px")),
    tarjeta_grafico("2. Precio por unidad de contenido entre comercios", icono = "ruler",
                    radioButtons("unidad", "Unidad de comparación (no se mezclan unidades)", inline = TRUE,
                                 choices = c("Por unidad (tableta, cápsula…)" = "unidad", "Por mL" = "mL", "Por g" = "g")),
                    uiOutput("contenedor_unitario"), alto = "auto")
  )
)

pestana_dosis <- nav_panel(
  "¿Marca o genérico?", icon = icon("capsules"),
  tarjeta_grafico("4. ¿Cuánto cuesta una tableta del mismo medicamento según la marca?", icono = "capsules",
                  p(class = "nota",
                    "Pregunta del consumidor: si compro el mismo principio activo en la misma concentración, ",
                    "¿cuánto pago de más por una marca frente a la opción más barata y en qué comercio? ",
                    "Se comparan todas las presentaciones sólidas de la categoría (no solo las comparables) ",
                    "con el precio por tableta, cápsula o sobre."),
                  selectInput("principio_dosis", "Principio activo y concentración", choices = NULL, width = "100%"),
                  highchartOutput("graf_dosis", height = "430px"),
                  uiOutput("texto_dosis"), alto = "auto")
)

pestana_tabla <- nav_panel(
  "Productos", icon = icon("table-list"),
  card(class = "tarjeta",
       card_header(class = "d-flex justify-content-between align-items-center",
                   span(icon("table-list"), "Productos filtrados"),
                   downloadButton("descargar_csv", "Descargar CSV", class = "btn-sm btn-primary")),
       DTOutput("tabla_productos"))
)

pestana_cambios <- nav_panel(
  "Cambios", icon = icon("arrows-up-down"),
  card(class = "tarjeta", card_body(layout_columns(
    col_widths = c(4, 4, 4), fill = FALSE,
    selectInput("ejec_a", "Ejecución inicial", choices = NULL, width = "100%"),
    selectInput("ejec_b", "Ejecución final", choices = NULL, width = "100%"),
    sliderInput("umbral", "Resaltar variaciones mayores a (%)", min = 1, max = 50, value = 10, post = " %",
                width = "100%")
  ))),
  uiOutput("resumen_cambios"),
  tarjeta_grafico("Variación por anuncio", icono = "arrows-up-down", highchartOutput("graf_cambios", height = "420px")),
  card(class = "tarjeta", card_header(span(icon("list"), "Detalle (mismo anuncio en el mismo comercio)")),
       DTOutput("tabla_cambios"))
)

pestana_canasta <- nav_panel(
  "Canasta", icon = icon("basket-shopping"),
  layout_columns(
    col_widths = c(5, 7),
    card(class = "tarjeta", card_header(span(icon("basket-shopping"), "Arme su canasta")),
         selectInput("ejec_canasta", "Precios de la ejecución", choices = NULL, width = "100%"),
         selectizeInput("canasta_productos", "Productos comparables", choices = NULL, multiple = TRUE, width = "100%",
                        options = list(placeholder = "Elija uno o varios productos")),
         uiOutput("canasta_cantidades"),
         div(class = "alert alert-warning small",
             "El resultado no incluye costos de envío, mínimos de compra ni las condiciones de las promociones.")),
    card(class = "tarjeta", card_header(span(icon("receipt"), "Resultado")), uiOutput("canasta_resultado"),
         tableOutput("canasta_por_comercio"), tableOutput("canasta_detalle"))
  )
)

pestana_actualizar <- nav_panel(
  "Actualizar", icon = icon("rotate"),
  layout_columns(
    col_widths = c(4, 8),
    card(class = "tarjeta", card_header(span(icon("rotate"), "Actualizar precios")),
         radioButtons("modo_act", "Modo", choices = c("En línea (consulta los sitios)" = "online",
                                                      "Sin conexión (reprocesa raw/)" = "offline")),
         checkboxGroupInput("comercios_act", "Comercios", choices = ELECCION_COMERCIOS,
                            selected = COMERCIOS_APP$comercio),
         conditionalPanel("input.modo_act == 'offline'",
                          selectInput("ejec_raw", "Copia cruda a reprocesar", choices = NULL)),
         input_task_button("actualizar", "Actualizar precios", label_busy = "Actualizando…",
                           icon = icon("rotate"), class = "btn-primary w-100"),
         tags$details(class = "ayuda mt-3", tags$summary("¿Cómo funciona?"),
           p("En línea: consulta los sitios con pausas entre peticiones y respetando el robots.txt (unos minutos). ",
             "La aplicación sigue disponible mientras tanto."),
           p("Sin conexión: reprocesa las copias crudas guardadas en raw/."),
           p("Si el servidor no puede consultar los sitios (suelen bloquear servidores en la nube), ",
             "se informa y puede usar el modo sin conexión."))),
    card(class = "tarjeta", card_header(span(icon("list-check"), "Avance y resumen por comercio")),
         uiOutput("estado_actualizacion"), tableOutput("tabla_progreso"))
  ),
  card(class = "tarjeta", card_header(span(icon("clock-rotate-left"), "Ejecuciones registradas")),
       tableOutput("tabla_ejecuciones")),
  card(class = "tarjeta", card_header(span(icon("shield-halved"), "Validaciones de la ejecución seleccionada en los filtros")),
       tableOutput("tabla_validaciones"))
)

ui <- page_navbar(
  title = div(class = "marca", span(class = "logo", icon("prescription-bottle-medical")),
              div(div(class = "titulo", "Comparador de precios"),
                  div(class = "sub", "Dolor e inflamación · La Rebaja · Cafam · Locatel"),
                  div(class = "fecha-datos", icon("clock"), textOutput("pie_fecha", inline = TRUE)))),
  window_title = "Comparador de precios · Dolor e inflamación",
  theme = tema,
  sidebar = barra_filtros,
  fillable = FALSE,
  lang = "es",
  pestana_resumen, pestana_evolucion, pestana_dosis, pestana_tabla, pestana_cambios, pestana_canasta,
  pestana_actualizar,
  nav_spacer()
)

server <- function(input, output, session) {
  version <- reactiveVal(0L)            # sube al terminar una actualización -> invalida la caché

  ejecuciones <- reactive({ version(); listar_ejecuciones(con) })
  ultima <- reactive({ e <- ejecuciones(); if (nrow(e)) e[1, ] else NULL })

  # Catálogos de los filtros (se refrescan tras actualizar)
  observe({
    e <- ejecuciones()
    elec <- setNames(e$ejecucion_id, etiqueta_ejecucion(e))
    sel <- isolate(input$ejecucion)
    # tras una actualización se muestra la ejecución más reciente; si no, se conserva la elegida
    tras_actualizar <- isolate(version()) > 0
    updateSelectInput(session, "ejecucion", choices = c(elec, "Todas las ejecuciones" = "todas"),
                      selected = if (!tras_actualizar && !is.null(sel) && sel %in% c(e$ejecucion_id, "todas")) sel
                                 else e$ejecucion_id[1])
    updateSelectInput(session, "ejec_a", choices = elec, selected = if (nrow(e) > 1) e$ejecucion_id[2] else e$ejecucion_id[1])
    updateSelectInput(session, "ejec_b", choices = elec, selected = e$ejecucion_id[1])
    updateSelectInput(session, "ejec_canasta", choices = elec, selected = e$ejecucion_id[1])
    fechas <- as.Date(e$fecha)
    updateDateRangeInput(session, "fechas", start = min(fechas), end = max(fechas))
    updateSelectizeInput(session, "subcategorias", choices = listar_subcategorias(con), server = FALSE)
    updateSelectizeInput(session, "marcas", choices = listar_marcas(con), server = TRUE)
    r <- rango_precios(con)
    tope <- ceiling(r$max / 10000) * 10000
    updateSliderInput(session, "precio", min = 0, max = tope, value = c(0, tope))
    updateSelectInput(session, "ejec_raw", choices = ejecuciones_raw_app())
  })

  ejecuciones_raw_app <- function() {
    ids <- unique(unlist(lapply(COMERCIOS_APP$comercio, function(cm)
      list.dirs(file.path("raw", cm), full.names = FALSE, recursive = FALSE))))
    sort(ids[nzchar(ids)], decreasing = TRUE)
  }

  texto_valido <- reactive(validar_texto(input$texto))
  output$aviso_texto <- renderUI({
    t <- texto_valido()
    if (!t$ok) div(class = "text-danger small mb-2", t$mensaje)
  })

  filtros_crudos <- reactive({
    req(input$ejecucion)
    pr <- input$precio
    list(comercios = input$comercios %||% character(),
         subcategorias = input$subcategorias %||% character(),
         marcas = input$marcas %||% character(),
         precio_min = if (pr[1] > 0) pr[1] else NA,
         precio_max = if (pr[2] < session$userData$tope_precio %||% Inf) pr[2] else NA,
         ejecucion = input$ejecucion,
         usar_fechas = identical(input$modo_tiempo, "fechas"),
         fecha_desde = as.character(input$fechas[1]), fecha_hasta = as.character(input$fechas[2]),
         solo_promo = input$solo_promo, solo_comparables = input$solo_comparables,
         solo_categoria = input$solo_categoria,
         texto = texto_valido()$valor)
  })
  observe({ session$userData$tope_precio <- ceiling(rango_precios(con)$max / 10000) * 10000 })
  filtros <- debounce(filtros_crudos, 500)

  f_ok <- reactive({
    f <- filtros()
    validate(need(length(f$comercios) > 0, "Elija al menos un comercio."))
    f
  })
  # Ejecución de referencia para indicadores que exigen una sola ejecución
  ejec_ref <- reactive({
    f <- filtros()
    if (!isTRUE(f$usar_fechas) && !is.na(f$ejecucion) && f$ejecucion != "todas") f$ejecucion else ultima()$ejecucion_id
  })

  output$pie_fecha <- renderText({
    u <- ultima(); if (is.null(u)) return("Sin ejecuciones")
    sprintf("Últimos datos: %s (%s)", fecha_legible(u$ejecucion_id), u$estado)
  })
  output$encabezado_datos <- renderUI({
    u <- ultima(); f <- filtros()
    periodo <- if (isTRUE(f$usar_fechas)) sprintf("del %s al %s", f$fecha_desde, f$fecha_hasta)
               else if (f$ejecucion == "todas") "todas las ejecuciones" else paste("ejecución", fecha_legible(f$ejecucion))
    div(class = "banda-datos", span(class = "icono", icon("circle-info")),
        div(div(class = "t1", sprintf("Periodo mostrado: %s", periodo)),
            div(class = "t2", sprintf("Precios en pesos colombianos (COP) tal como se publicaron al momento de la captura · Última ejecución: %s",
                                      fecha_legible(u$ejecucion_id)))))
  })

  general <- reactive(ind_general(con, f_ok())) |> bindCache(filtros(), version())
  mediana <- reactive(ind_mediana_total(con, f_ok())) |> bindCache(filtros(), version())
  ahorro <- reactive(ind_ahorro_maximo(con, ejec_ref(), filtros()$comercios)) |>
    bindCache(ejec_ref(), filtros()$comercios, version())
  cambios <- reactive(ind_cambios_precio(con, ejec_ref(), filtros()$comercios)) |>
    bindCache(ejec_ref(), filtros()$comercios, version())
  por_comercio <- reactive(ind_por_comercio(con, f_ok())) |> bindCache(filtros(), version())
  mediana_sub <- reactive(ind_mediana_subcategoria(con, f_ok())) |> bindCache(filtros(), version())

  periodo_txt <- reactive({
    g <- general()
    if (is.na(g$desde)) "sin datos" else if (g$desde == g$hasta) paste("consulta del", g$desde) else paste("consultas del", g$desde, "al", g$hasta)
  })

  output$ind_productos <- renderText(paste(num(general()$productos), "anuncios"))
  output$ind_productos_det <- renderText(sprintf("%s observaciones · %s comparables · %s",
                                                 num(general()$observaciones), num(general()$comparables), periodo_txt()))
  output$ind_ultima <- renderText(fecha_legible(ultima()$ejecucion_id))
  output$ind_ultima_det <- renderText(sprintf("Estado: %s (%d de %d comercios completos)",
                                              ultima()$estado, ultima()$completas, ultima()$comercios))
  output$ind_promo <- renderText(pct(general()$pct_promocion))
  output$ind_promo_det <- renderText(paste("% de observaciones con precio de venta menor al de lista ·", periodo_txt()))
  output$ind_mediana <- renderText(cop(mediana()))
  output$ind_mediana_det <- renderText(paste("COP por presentación · ver mediana por subcategoría abajo ·", periodo_txt()))
  output$ind_ahorro <- renderText({
    a <- ahorro(); if (is.null(a)) "—" else cop(a$ahorro_cop)
  })
  output$ind_ahorro_det <- renderText({
    a <- ahorro(); if (is.null(a)) return("Sin productos comparables en la ejecución")
    sprintf("COP (%s) en %s · más barato en: %s · ejecución %s", pct(a$ahorro_pct), abreviar(a$producto, 40), a$comercios_mas_baratos,
            fecha_legible(ejec_ref()))
  })
  output$ind_cambios <- renderText(paste(num(cambios()$cambios), "anuncios"))
  output$ind_cambios_det <- renderText({
    x <- cambios()
    if (is.na(x$ejecucion_anterior)) return(paste("No hay ejecución anterior a", fecha_legible(ejec_ref())))
    sprintf("Subieron %s, bajaron %s · %s frente a %s", num(x$subieron), num(x$bajaron),
            fecha_legible(ejec_ref()), fecha_legible(x$ejecucion_anterior))
  })

  output$tabla_por_comercio <- renderTable({
    x <- por_comercio(); sin_datos(x)
    data.frame(Comercio = x$comercio, Anuncios = num(x$productos), Observaciones = num(x$observaciones),
               `En promoción` = pct(x$pct_promocion), Agotados = num(x$agotados), check.names = FALSE)
  }, striped = TRUE, width = "100%")
  output$tabla_mediana_subcat <- renderTable({
    x <- mediana_sub(); sin_datos(x)
    data.frame(Subcategoría = x$subcategoria, `Mediana (COP)` = cop(x$mediana), Observaciones = num(x$observaciones),
               check.names = FALSE)
  }, striped = TRUE, width = "100%")

  output$graf_distribucion <- renderHighchart({
    b <- distribucion_precios(con, f_ok()); sin_datos(b)
    grafico_distribucion(b, log = isTRUE(input$escala_log))
  }) |> bindCache(filtros(), input$escala_log, version())

  observe({
    version()
    p <- listar_comparables(con)
    updateSelectizeInput(session, "producto_serie", choices = setNames(p$producto_id, p$descripcion),
                         selected = p$producto_id[1], server = TRUE)
  })
  output$graf_evolucion <- renderHighchart({
    req(input$producto_serie)
    s <- serie_producto(con, input$producto_serie)
    s <- s[s$comercio %in% filtros()$comercios, ]
    sin_datos(s)
    nombre <- listar_comparables(con)
    grafico_evolucion(s, abreviar(nombre$descripcion[nombre$producto_id == input$producto_serie][1], 80))
  }) |> bindCache(input$producto_serie, filtros()$comercios, version())

  datos_unitario <- reactive(
    precio_unitario_comparables(con, ejec_ref(), input$unidad, filtros()$comercios, filtros()$subcategorias)
  ) |> bindCache(ejec_ref(), input$unidad, filtros()$comercios, filtros()$subcategorias, version())
  output$contenedor_unitario <- renderUI({   # alto según el número de productos
    n <- length(unique(datos_unitario()$producto_id))
    highchartOutput("graf_unitario", height = paste0(max(380, 34 * n + 140), "px"))
  })
  output$graf_unitario <- renderHighchart({
    d <- datos_unitario()
    sin_datos(d, sprintf("No hay presentaciones comparables medidas en %s con estos filtros.", input$unidad))
    grafico_precio_unitario(d, input$unidad)
  }) |> bindCache(ejec_ref(), input$unidad, filtros()$comercios, filtros()$subcategorias, version())

  observe({
    p <- principios_dosis(con, ejec_ref())
    elec <- setNames(paste(p$principio, p$concentracion, sep = "|"),
                     sprintf("%s %s (%d marcas)", tolower(gsub("_", " ", p$principio)), p$concentracion, p$marcas))
    updateSelectInput(session, "principio_dosis", choices = elec, selected = elec[1])
  })
  dosis <- reactive({
    req(input$principio_dosis)
    pc <- strsplit(input$principio_dosis, "|", fixed = TRUE)[[1]]
    list(principio = pc[1], conc = pc[2], d = precio_por_dosis(con, ejec_ref(), pc[1], pc[2], filtros()$comercios))
  })
  output$graf_dosis <- renderHighchart({
    x <- dosis(); sin_datos(x$d)
    grafico_dosis(x$d, x$principio, x$conc)
  })
  output$texto_dosis <- renderUI({
    x <- dosis(); d <- x$d; if (!nrow(d)) return(NULL)
    min_i <- which.min(d$minimo_por_unidad); max_i <- which.max(d$minimo_por_unidad)
    p(class = "small", sprintf(
      "Lo más barato: %s en %s a %s por unidad. Lo más caro: %s en %s a %s por unidad (%s veces más). Ejecución %s.",
      d$marca[min_i], d$comercio_nombre[min_i], cop(d$minimo_por_unidad[min_i]),
      d$marca[max_i], d$comercio_nombre[max_i], cop(d$minimo_por_unidad[max_i]),
      num(d$minimo_por_unidad[max_i] / d$minimo_por_unidad[min_i], 1), fecha_legible(ejec_ref())))
  })

  tabla <- reactive(productos_filtrados(con, f_ok())) |> bindCache(filtros(), version())
  output$tabla_productos <- renderDT({
    x <- tabla(); sin_datos(x)
    x$enlace <- ifelse(is.na(x$enlace), "",
                       sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">Ver anuncio</a>',
                               htmltools::htmlEscape(x$enlace, attribute = TRUE)))
    x$fecha_consulta <- substr(x$fecha_consulta, 1, 16)
    names(x) <- c("Comercio", "Nombre", "Marca", "Subcategoría", "Presentación", "Precio (COP)",
                  "Precio de lista (COP)", "Precio unitario (COP)", "Unidad", "Promoción", "Disponibilidad",
                  "Comparable", "Ejecución", "Fecha de consulta", "Enlace")
    datatable(x, rownames = FALSE, escape = setdiff(names(x), "Enlace"), filter = "top",
              options = list(pageLength = 15, scrollX = TRUE, language = DT_ES,
                             columnDefs = list(list(visible = FALSE, targets = c(3, 6, 12))))) |>
      formatCurrency(c("Precio (COP)", "Precio de lista (COP)"), currency = "$", digits = 0, mark = ".", dec.mark = ",") |>
      formatCurrency("Precio unitario (COP)", currency = "$", digits = 1, mark = ".", dec.mark = ",")
  })
  output$descargar_csv <- downloadHandler(
    filename = function() sprintf("productos_filtrados_%s.csv", format(Sys.time(), "%Y%m%d_%H%M")),
    content = function(file) write.csv(tabla(), file, row.names = FALSE, fileEncoding = "UTF-8", na = "")
  )

  cmp <- reactive({
    req(input$ejec_a, input$ejec_b)
    validate(need(input$ejec_a != input$ejec_b, "Elija dos ejecuciones distintas para comparar."))
    comparar_ejecuciones(con, input$ejec_a, input$ejec_b, filtros()$comercios, isTRUE(input$solo_categoria))
  }) |> bindCache(input$ejec_a, input$ejec_b, filtros()$comercios, input$solo_categoria, version())

  output$resumen_cambios <- renderUI({
    x <- cmp(); u <- input$umbral
    n <- function(t) sum(x$tipo == t)
    grandes <- sum(abs(x$cambio_pct) >= u, na.rm = TRUE)
    layout_column_wrap(width = 1/5, fill = FALSE,
      caja("Subieron", n("subió"), "anuncios", "arrow-up", "ambar"),
      caja("Bajaron", n("bajó"), "anuncios", "arrow-down", "verde"),
      caja(sprintf("Variación ≥ %s %%", u), grandes, "anuncios", "triangle-exclamation", "acento"),
      caja("Nuevos", n("nuevo"), "solo en la ejecución final", "plus"),
      caja("Dejaron de observarse", n("dejó de observarse"), "solo en la inicial", "eye-slash"))
  })
  output$graf_cambios <- renderHighchart({
    x <- cmp()
    sin_datos(x[x$tipo %in% c("subió", "bajó"), ], "No hubo cambios de precio entre estas ejecuciones.")
    grafico_cambios(x, input$umbral)
  })
  output$tabla_cambios <- renderDT({
    x <- cmp(); sin_datos(x)
    x <- x[x$tipo != "sin cambio", ]
    sin_datos(x, "Ningún anuncio cambió de precio, apareció o dejó de observarse.")
    x$grande <- !is.na(x$cambio_pct) & abs(x$cambio_pct) >= input$umbral
    x$enlace <- sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">Ver</a>',
                        htmltools::htmlEscape(x$enlace, attribute = TRUE))
    names(x) <- c("Comercio", "Producto", "Antes (COP)", "Después (COP)", "Cambio (COP)", "Cambio (%)", "Tipo",
                  "Enlace", "grande")
    datatable(x, rownames = FALSE, escape = setdiff(names(x), "Enlace"),
              options = list(pageLength = 15, scrollX = TRUE, language = DT_ES,
                             columnDefs = list(list(visible = FALSE, targets = 8)))) |>
      formatCurrency(c("Antes (COP)", "Después (COP)", "Cambio (COP)"), currency = "$", digits = 0, mark = ".", dec.mark = ",") |>
      formatStyle("grande", target = "row", backgroundColor = styleEqual(TRUE, "#fff3cd"))
  })

  observe({
    req(input$ejec_canasta)
    p <- listar_comparables(con, input$ejec_canasta)
    sel <- isolate(input$canasta_productos)
    updateSelectizeInput(session, "canasta_productos", choices = setNames(p$producto_id, p$descripcion),
                         selected = intersect(sel, p$producto_id), server = TRUE)
  })
  output$canasta_cantidades <- renderUI({
    ids <- input$canasta_productos; if (!length(ids)) return(NULL)
    p <- listar_comparables(con, input$ejec_canasta)
    lapply(seq_along(ids), function(i)
      numericInput(paste0("cant_", i), abreviar(p$descripcion[match(ids[i], p$producto_id)], 60),
                   value = isolate(input[[paste0("cant_", i)]]) %||% 1, min = 1, max = 50, step = 1, width = "100%"))
  })
  canasta_res <- reactive({
    ids <- input$canasta_productos
    validate(need(length(ids) > 0, "Elija al menos un producto para calcular la canasta."))
    cant <- vapply(seq_along(ids), function(i) {
      v <- suppressWarnings(as.integer(input[[paste0("cant_", i)]] %||% 1L))
      if (is.na(v) || v < 1) 1L else min(v, 50L)
    }, integer(1))
    canasta(con, input$ejec_canasta, data.frame(producto_id = ids, cantidad = cant))
  })
  output$canasta_resultado <- renderUI({
    r <- canasta_res(); pc <- r$por_comercio
    completos <- pc[pc$completo == 1, ]
    incompletos <- pc[pc$completo == 0, ]
    tagList(
      if (nrow(completos)) {
        mejor <- completos[which.min(completos$total), ]
        ahorro_mezcla <- if (!is.na(r$optima)) mejor$total - r$optima else NA
        div(class = "alert alert-success",
            sprintf("Comprando todo en un solo comercio, lo más barato es %s: %s. ", mejor$comercio_nombre, cop(mejor$total)),
            if (!is.na(r$optima))
              sprintf("Comprando cada producto donde es más barato: %s (ahorro de %s frente a %s).",
                      cop(r$optima), cop(ahorro_mezcla), mejor$comercio_nombre))
      } else div(class = "alert alert-warning", "Ningún comercio tiene todos los productos elegidos en esta ejecución."),
      if (nrow(incompletos))
        div(class = "alert alert-secondary small",
            sprintf("Sin total (falta algún producto): %s.",
                    paste(sprintf("%s (faltan %d)", incompletos$comercio_nombre,
                                  incompletos$productos_pedidos - incompletos$productos_con_precio), collapse = "; "))),
      p(class = "small text-muted", sprintf("Precios de la ejecución %s, en COP.", fecha_legible(input$ejec_canasta))))
  })
  output$canasta_por_comercio <- renderTable({
    req(length(input$canasta_productos) > 0)          # el aviso se muestra una sola vez (arriba)
    pc <- canasta_res()$por_comercio
    data.frame(Comercio = pc$comercio_nombre, `Productos con precio` = sprintf("%d de %d", pc$productos_con_precio, pc$productos_pedidos),
               `Total (COP)` = ifelse(pc$completo == 1, cop(pc$total), "No disponible: falta algún producto"),
               check.names = FALSE)
  }, striped = TRUE, width = "100%")
  output$canasta_detalle <- renderTable({
    req(length(input$canasta_productos) > 0)
    d <- canasta_res()$detalle
    p <- listar_comparables(con, input$ejec_canasta)
    data.frame(Producto = abreviar(p$descripcion[match(d$producto_id, p$producto_id)], 55), Cantidad = d$cantidad,
               `Precio mínimo (COP)` = cop(d$precio_min), `Subtotal (COP)` = cop(d$subtotal),
               `Dónde comprar (empates incluidos)` = d$donde_comprar, check.names = FALSE)
  }, striped = TRUE, width = "100%")

  id_actual <- reactiveVal(NULL)
  tarea <- ExtendedTask$new(function(modo, comercios, ejecucion_raw, actualizacion_id, ruta) {
    future_promise({
      # entorno propio: los módulos del scraper no se mezclan con los de la interfaz
      e <- new.env()
      sys.source("actualizacion.R", envir = e, keep.source = FALSE)
      e$actualizar_precios(ruta_db = ruta, comercios = comercios, modo = modo,
                         ejecucion_raw = ejecucion_raw, actualizacion_id = actualizacion_id)
    }, seed = TRUE)
  }) |> bind_task_button("actualizar")

  observeEvent(input$actualizar, {
    if (!length(input$comercios_act)) {
      showNotification("Elija al menos un comercio para actualizar.", type = "warning"); return()
    }
    if (input$modo_act == "offline" && !nzchar(input$ejec_raw %||% "")) {
      showNotification("No hay copias en raw/ para reprocesar.", type = "warning"); return()
    }
    aid <- format(Sys.time(), "%Y%m%dT%H%M%OS3")
    id_actual(aid)
    tarea$invoke(input$modo_act, input$comercios_act,
                 if (input$modo_act == "offline") input$ejec_raw else NULL, aid, RUTA_TRABAJO)
  })

  progreso <- reactive({
    aid <- id_actual(); req(aid)
    if (tarea$status() == "running") invalidateLater(2000)
    progreso_actualizacion(con, aid)
  })

  observe({
    st <- tarea$status()
    if (st == "success") {
      isolate(version(version() + 1L))
      showNotification("Actualización terminada: indicadores, gráficos y tablas al día.", type = "message")
    } else if (st == "error") {
      showNotification("La actualización no pudo completarse. Revise el resumen.", type = "error", duration = NULL)
    }
  })

  output$estado_actualizacion <- renderUI({
    if (is.null(id_actual())) return(p(class = "text-muted", "Aún no se ha ejecutado una actualización en esta sesión."))
    st <- tarea$status()
    x <- progreso()
    msg <- switch(st,
      running = div(class = "alert alert-info", "Actualizando… el avance por comercio se muestra abajo."),
      success = {
        fall <- x[x$estado == "fallida", ]
        if (nrow(fall) == nrow(x) && all(x$modo == "online"))
          div(class = "alert alert-danger",
              "El servidor no pudo consultar los sitios de los comercios (posible bloqueo o sin conexión). ",
              "Los datos existentes no se modificaron. Use el modo sin conexión para reprocesar las copias de raw/.")
        else if (nrow(fall)) div(class = "alert alert-warning",
                                 "Algunos comercios fallaron; los demás se actualizaron. Vea el motivo en la tabla.")
        else div(class = "alert alert-success", "Actualización terminada.")
      },
      error = div(class = "alert alert-danger", "La actualización se interrumpió; la base no quedó a medias porque cada comercio se inserta en una transacción."),
      NULL)
    tagList(msg)
  })
  output$tabla_progreso <- renderTable({
    x <- progreso(); req(nrow(x))
    data.frame(Comercio = x$comercio_nombre, Ejecución = x$ejecucion_id, Modo = x$modo, Estado = x$estado,
               Recolectados = num(x$recolectados), `Productos nuevos` = num(x$nuevos),
               `Observaciones insertadas` = num(x$insertadas), Rechazadas = num(x$rechazadas),
               `Cambios de precio` = num(x$cambios_precio), `No observados` = num(x$no_observados),
               Motivo = x$motivo, check.names = FALSE)
  }, striped = TRUE, width = "100%")

  output$tabla_ejecuciones <- renderTable({
    version(); x <- resumen_ejecuciones(con)
    data.frame(Ejecución = x$ejecucion_id, Comercio = x$comercio, Inicio = substr(x$inicio, 1, 16),
               Modo = x$modo, Estado = x$estado, `Total en el sitio` = num(x$total_sitio),
               `Observaciones válidas` = num(x$observaciones_validas), Rechazadas = num(x$rechazadas),
               check.names = FALSE)
  }, striped = TRUE, width = "100%")
  output$tabla_validaciones <- renderTable({
    version(); x <- validaciones_ejecucion(con, ejec_ref())
    sin_datos(x, "Esta ejecución no tiene validaciones registradas.")
    data.frame(Comercio = x$comercio, Regla = x$regla, Evaluadas = x$evaluadas, Fallas = x$fallas,
               Resultado = x$resultado, Detalle = x$detalle, check.names = FALSE)
  }, striped = TRUE, width = "100%")
}

DT_ES <- list(search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas", info = "Filas _START_ a _END_ de _TOTAL_",
              infoEmpty = "Sin filas", infoFiltered = "(filtradas de _MAX_)", zeroRecords = "No hay coincidencias",
              paginate = list(first = "Primera", last = "Última", `next` = "Siguiente", previous = "Anterior"))

shinyApp(ui, server)
