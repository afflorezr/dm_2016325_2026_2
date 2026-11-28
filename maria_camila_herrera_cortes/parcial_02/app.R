# app.R -- Taller 2, Minería de Datos: Comparador de precios (Cuidado y decoración de uñas)
# Aplicación Shiny (bslib). La interfaz NO contiene SQL: todas las consultas están en db.R.
# Ejecutar desde la carpeta taller_2/:  shiny::runApp()

library(shiny); library(bslib); library(DT); library(highcharter); library(future)
plan(multisession)
source("colores.R",       encoding = "UTF-8")   # colores de toda la aplicación (editable)
source("db.R",            encoding = "UTF-8")
source("graficos.R",      encoding = "UTF-8")
source("mod_actualizar.R", encoding = "UTF-8")
configurar_highcharter()

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
PAGINAS_CON_FILTROS <- c("Resumen", "Productos")
MENSAJE_SIN_DATOS <- "No hay productos que cumplan estos filtros. Pruebe ampliar el rango de precio o quitar algún filtro."
IDIOMA_DT <- list(search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas", zeroRecords = "Sin resultados con estos filtros",
                  emptyTable = "Sin datos", info = "Mostrando _START_ a _END_ de _TOTAL_ filas",
                  infoEmpty = "Sin filas", infoFiltered = "(de _MAX_ en total)",
                  paginate = list(`first` = "Primera", `last` = "Última", `next` = "Siguiente", previous = "Anterior"))

# Tema: color principal y color de la pestaña activa vienen de colores.R
tema <- bs_theme(version = 5, bootswatch = "flatly", primary = COLOR_PRINCIPAL) |>
  bs_add_rules(sprintf("
    .navbar .nav-link.active, .navbar .nav-link.active:hover, .navbar .nav-link.active:focus
      { color: %1$s !important; border-bottom: 3px solid %1$s !important; }
    .navbar .nav-link:hover { color: %2$s !important; }
    a:not(.nav-link):not(.btn):not(.dropdown-item) { color: %3$s; }
    .bslib-value-box .value-box-value { font-size: 1.7rem; line-height: 1.15; }
    .bslib-value-box .value-box-title { font-size: .9rem; }
    .bslib-value-box { min-height: 130px; }
    .irs--shiny .irs-grid-text { display: none; }
    .seccion-titulo { margin: 1.2rem 0 .2rem 0; font-weight: 700; }
    .seccion-nota { color: #64748b; font-size: .85rem; margin-bottom: .6rem; }
    .nota-grafico { color: #64748b; font-size: .82rem; margin: .2rem .4rem 0 .4rem; }
  ", COLOR_PESTANA_ACTIVA, COLOR_PESTANA_HOVER, COLOR_ENLACE))

punto_color <- function(cm) tags$span(style = sprintf("display:inline-block;width:11px;height:11px;border-radius:50%%;background:%s;margin-right:6px;", color_comercio(cm)))
etiqueta_comercio <- function(cm) tags$span(punto_color(cm), nombre_comercio(cm))

etiqueta_ejecucion <- function(e) paste0(fmt_fecha(e$fecha_hora), " · ", e$estado_global, " (", e$ejecucion_id, ")")

# ------------------------------- Interfaz -------------------------------------------------------
filtros_ui <- tagList(
  h6("Filtros", class = "fw-bold"),
  checkboxGroupInput("f_comercio", "Comercio", choiceNames = lapply(names(NOMBRES_COMERCIO), etiqueta_comercio),
                     choiceValues = names(NOMBRES_COMERCIO), selected = names(NOMBRES_COMERCIO)),
  selectInput("f_subcategoria", "Subcategoría", choices = NULL, multiple = TRUE),
  selectizeInput("f_marca", "Marca", choices = NULL, multiple = TRUE, options = list(placeholder = "Todas")),
  sliderInput("f_precio", "Precio (COP)", min = 0, max = 500000, value = c(0, 500000), step = 1000, pre = "$", sep = ".", ticks = FALSE),
  radioButtons("f_tiempo", "Datos de", choices = c("Última ejecución" = "ultima", "Una ejecución" = "ejec",
                                                    "Rango de fechas" = "rango")),
  conditionalPanel("input.f_tiempo == 'ejec'", selectInput("f_ejecucion", "Ejecución", choices = NULL)),
  conditionalPanel("input.f_tiempo == 'rango'",
                   dateRangeInput("f_fechas", "Fechas de consulta", language = "es", format = "dd/mm/yyyy", separator = " a ")),
  input_switch("f_promocion", "Solo promociones", value = FALSE),
  input_switch("f_comparables", "Solo productos comparables", value = FALSE),
  textInput("f_busqueda", "Buscar en el nombre o en el texto del anuncio", placeholder = "ej. esmalte gel"),
  actionButton("f_reset", "Restablecer filtros", class = "btn-outline-secondary btn-sm w-100"),
  hr(), uiOutput("fecha_datos")
)

ui <- page_navbar(
  id = "pagina", title = "Comparador de precios · Cuidado y decoración de uñas", lang = "es", fillable = FALSE,
  window_title = "Comparador de precios", theme = tema,
  sidebar = sidebar(id = "barra", width = 330, open = TRUE, filtros_ui),

  # ------------------------------------------------------------------ Resumen
  nav_panel("Resumen", value = "Resumen",
    div(class = "seccion-titulo h5", "Según los filtros seleccionados"),
    div(class = "seccion-nota", "Estas tarjetas y gráficos cambian con el panel de filtros de la izquierda."),
    uiOutput("ind_filtrados"),
    layout_columns(col_widths = breakpoints(sm = 12, xl = c(6, 6)), fill = FALSE,
      card(height = "560px", full_screen = TRUE, highchartOutput("g_distribucion", height = "480px"),
           div(class = "nota-grafico", "Escala logarítmica: la misma distancia vertical representa el mismo cambio porcentual de precio (no los mismos pesos), así se ven juntos los productos baratos y los caros.")),
      card(height = "560px", full_screen = TRUE, highchartOutput("g_mediana", height = "480px"))),
    layout_columns(col_widths = breakpoints(sm = 12, xl = c(6, 6)), fill = FALSE,
      card(height = "480px", full_screen = TRUE, highchartOutput("g_promocion", height = "420px")),
      card(height = "480px", full_screen = TRUE, highchartOutput("g_disponibilidad", height = "420px"))),
    div(class = "seccion-titulo h5", "Comparación entre los tres comercios"),
    div(class = "seccion-nota", "Estas tarjetas comparan siempre a todos los comercios en la última ejecución completa; no dependen del filtro de comercio."),
    uiOutput("ind_fijos"),
    p(class = "text-muted small", "Los precios corresponden al momento de la captura. Moneda: pesos colombianos (COP).")),

  # ---------------------------------------------------------- Comparar comercios
  nav_panel("Comparar comercios", value = "Comparar",
    card(height = "700px", full_screen = TRUE,
         card_header("Evolución del precio de un producto comparable"),
         layout_columns(col_widths = c(8, 4), fill = FALSE,
           selectInput("ev_producto", "Producto comparable", choices = NULL, width = "100%"),
           radioButtons("ev_eje", "Eje horizontal", choices = c("Fecha real" = "fecha", "Una marca por ejecución" = "ejecucion"), inline = FALSE)),
         highchartOutput("g_evolucion", height = "500px"), uiOutput("nota_evolucion")),
    card(height = "760px", full_screen = TRUE,
         card_header("Precio por unidad de contenido"),
         layout_columns(col_widths = c(4, 8), fill = FALSE,
           radioButtons("pu_unidad", "Unidad (no se mezclan)", choices = c("mL", "g", "unidad"), inline = TRUE),
           selectInput("pu_ejec", "Ejecución", choices = NULL, width = "100%")),
         highchartOutput("g_unitario", height = "520px"), uiOutput("nota_unitario")),
    card(height = "780px", full_screen = TRUE,
         card_header("¿En qué comercio conviene comprar cada producto?"),
         selectInput("sc_ejec", "Ejecución", choices = NULL, width = "50%"),
         highchartOutput("g_sobrecosto", height = "560px"), uiOutput("nota_sobrecosto")),
    layout_columns(col_widths = breakpoints(sm = 12, xl = c(6, 6)), fill = FALSE,
      card(height = "520px", full_screen = TRUE, highchartOutput("g_mas_barato", height = "460px")),
      card(height = "520px", full_screen = TRUE, highchartOutput("g_ahorro", height = "460px")))),

  # ---------------------------------------------------------------- Productos
  nav_panel("Productos", value = "Productos",
    card(full_screen = TRUE, min_height = "600px",
         card_header(class = "d-flex justify-content-between align-items-center", "Productos filtrados",
                     downloadButton("descargar", "Descargar CSV", class = "btn-sm btn-outline-primary")),
         DTOutput("tabla"))),

  # ---------------------------------------------------------- Cambios de precio
  nav_panel("Cambios de precio", value = "Cambios",
    card(card_header("¿Qué ejecuciones comparar?"),
         layout_columns(col_widths = c(6, 6), fill = FALSE,
           selectInput("cb_anterior", "Ejecución anterior", choices = NULL, width = "100%"),
           selectInput("cb_actual", "Ejecución actual", choices = NULL, width = "100%")),
         div(class = "px-2 pb-2",
             sliderInput("cb_umbral", "Resaltar en amarillo las variaciones de al menos (%)", min = 0.5, max = 50, value = 5, step = 0.5,
                         width = "100%", post = " %", ticks = FALSE))),
    uiOutput("cb_resumen"),
    uiOutput("cb_aviso"),
    card(height = "560px", full_screen = TRUE, highchartOutput("g_variaciones", height = "500px")),
    card(full_screen = TRUE, min_height = "560px", checkboxInput("cb_solo_cambios", "Mostrar solo productos con cambios", TRUE), DTOutput("cb_tabla")),
    p(class = "text-muted small", "Se compara el mismo anuncio en el mismo comercio. Solo se consideran los comercios con datos válidos en ambas ejecuciones.")),

  # ------------------------------------------------------------------- Canasta
  nav_panel("Canasta", value = "Canasta",
    layout_columns(col_widths = breakpoints(sm = 12, lg = c(4, 8)), fill = FALSE,
      card(card_header("Arme su canasta"),
           selectizeInput("c_productos", "Productos comparables", choices = NULL, multiple = TRUE,
                          options = list(placeholder = "Elija uno o más productos")),
           uiOutput("c_cantidades"),
           selectInput("c_ejec", "Precios de la ejecución", choices = NULL)),
      div(uiOutput("c_resultado")))),

  # --------------------------------------------------------------- Actualizar
  nav_panel("Actualizar datos", value = "Actualizar",
    layout_columns(col_widths = breakpoints(sm = 12, lg = c(5, 7)), fill = FALSE,
      card(card_header("Actualizar precios"), mod_actualizar_ui("act")),
      card(card_header("Sobre los datos"),
           p("Todos los precios provienen del código de web scraping (scraper.R) ejecutado sobre los sitios de Éxito, Jumbo y Olímpica;",
             "cada observación se puede rastrear hasta su copia cruda en la carpeta raw/ y a su ejecución."),
           p("En plataformas de despliegue gratuitas los comercios suelen bloquear las consultas y los cambios en la base",
             "no se conservan al reiniciar la aplicación. En ese caso use el ", strong("modo sin conexión"),
             ", que reprocesa las copias de raw/. La actualización en línea funciona al ejecutar la aplicación en su computador."),
           p("Los resultados de la canasta no incluyen envío, mínimos de compra ni condiciones de las promociones.")))))


# ------------------------------- Servidor -------------------------------------------------------
server <- function(input, output, session) {
  act <- mod_actualizar_server("act", ruta_db = DB_RUTA)
  db <- act$db; ver <- act$version

  # Catálogos (se recalculan al terminar una actualización o al cambiar de base)
  catalogo <- reactive(tryCatch(db_filtros(db()), error = function(e) NULL)) |> bindCache(ver(), db())
  ejec_tbl <- reactive(tryCatch(db_ejecuciones(db()), error = function(e) NULL)) |> bindCache(ver(), db())
  ref      <- reactive(tryCatch(db_ultima_ejecucion(db()), error = function(e) NULL)) |> bindCache(ver(), db())
  ultima   <- reactive(tryCatch(db_ind_ultima_ejecucion(db()), error = function(e) NULL)) |> bindCache(ver(), db())
  ej_choices <- reactive({ e <- ejec_tbl(); req(e)
    setNames(e$ejecucion_id, vapply(seq_len(nrow(e)), function(i) etiqueta_ejecucion(e[i, ]), "")) })
  nombres_prod <- reactive({ cp <- catalogo()$productos_comparables; setNames(cp$producto_estandar, cp$producto_id) })

  elegir <- function(actual, opciones) if (length(actual) && nzchar(actual[1]) && actual[1] %in% opciones) actual[1] else opciones[1]

  observe({
    cf <- catalogo(); req(cf)
    sel <- intersect(isolate(input$f_comercio), cf$comercios); if (!length(sel)) sel <- cf$comercios
    updateCheckboxGroupInput(session, "f_comercio", choiceNames = lapply(cf$comercios, etiqueta_comercio),
                             choiceValues = cf$comercios, selected = sel)
    updateSelectInput(session, "f_subcategoria", choices = cf$subcategorias, selected = intersect(isolate(input$f_subcategoria), cf$subcategorias))
    updateSelectizeInput(session, "f_marca", choices = cf$marcas, selected = intersect(isolate(input$f_marca), cf$marcas), server = TRUE)
    tope <- max(1000, ceiling(cf$precio$max / 1000) * 1000)
    updateSliderInput(session, "f_precio", min = 0, max = tope, value = c(0, tope))
    prod <- setNames(cf$productos_comparables$producto_id,
                     paste0(cf$productos_comparables$producto_id, " · ", cf$productos_comparables$producto_estandar))
    un <- intersect(c("mL", "g", "unidad"), cf$unidades)       # solo las unidades que existen en los comparables
    if (length(un)) updateRadioButtons(session, "pu_unidad", choices = un, selected = elegir(isolate(input$pu_unidad), un), inline = TRUE)
    updateSelectInput(session, "ev_producto", choices = prod, selected = elegir(isolate(input$ev_producto), unname(prod)))
    updateSelectizeInput(session, "c_productos", choices = prod, selected = intersect(isolate(input$c_productos), prod))
  })
  observe({
    ch <- ej_choices(); e <- ejec_tbl(); req(ch, e)
    completas <- e$ejecucion_id[e$estado_global == "completa"]
    ultima_ok <- ref() %||% ch[1]
    for (id in c("f_ejecucion", "pu_ejec", "sc_ejec", "c_ejec")) updateSelectInput(session, id, choices = ch, selected = ultima_ok)
    act_id <- completas[1] %||% ch[1]; ant_id <- completas[2] %||% ch[min(2, length(ch))]
    updateSelectInput(session, "cb_actual", choices = ch, selected = act_id)
    updateSelectInput(session, "cb_anterior", choices = ch, selected = ant_id)
  })
  observeEvent(input$pagina, {
    if (exists("toggle_sidebar", asNamespace("bslib"))) bslib::toggle_sidebar("barra", open = input$pagina %in% PAGINAS_CON_FILTROS)
  })
  observeEvent(input$f_reset, {
    cf <- catalogo(); req(cf); tope <- max(1000, ceiling(cf$precio$max / 1000) * 1000)
    updateCheckboxGroupInput(session, "f_comercio", selected = cf$comercios); updateSelectInput(session, "f_subcategoria", selected = character())
    updateSelectizeInput(session, "f_marca", selected = character()); updateSliderInput(session, "f_precio", value = c(0, tope))
    updateRadioButtons(session, "f_tiempo", selected = "ultima"); updateTextInput(session, "f_busqueda", value = "")
    update_switch("f_promocion", FALSE); update_switch("f_comparables", FALSE)
  })

  # Filtros del panel lateral (con pausa para no consultar en cada tecla)
  filtros <- reactive({
    t <- input$f_tiempo %||% "ultima"; cf <- catalogo()
    tope <- if (is.null(cf)) Inf else max(1000, ceiling(cf$precio$max / 1000) * 1000)
    p <- input$f_precio %||% c(0, tope)
    list(comercios = input$f_comercio, subcategorias = input$f_subcategoria, marcas = input$f_marca,
         # los extremos del control no filtran: así no se ocultan los productos sin precio (agotados)
         precio_min = if (p[1] > 0) p[1] else NULL, precio_max = if (p[2] < tope) p[2] else NULL,
         ejecucion = if (t == "ejec") input$f_ejecucion else NULL,
         fecha_desde = if (t == "rango" && length(input$f_fechas)) as.character(input$f_fechas[1]) else NULL,
         fecha_hasta = if (t == "rango" && length(input$f_fechas)) as.character(input$f_fechas[2]) else NULL,
         solo_promocion = isTRUE(input$f_promocion), solo_comparables = isTRUE(input$f_comparables),
         busqueda = input$f_busqueda %||% "")
  })
  filtros_d <- debounce(filtros, 500)

  con_error <- function(expr) tryCatch(expr, error = function(e)
    structure(data.frame(), error = if (inherits(e, "entrada_invalida")) conditionMessage(e)
              else "No se pudo consultar la base de datos. Pruebe 'Restablecer filtros' o actualice la página."))
  validar <- function(x, vacio = MENSAJE_SIN_DATOS) {
    msg <- attr(x, "error")
    shiny::validate(
      shiny::need(is.null(msg), msg),
      shiny::need(NROW(x) > 0, vacio)
    )
    invisible(x)
  }
  periodo <- reactive({
    f <- filtros_d(); u <- ultima()
    if (!is.null(f$ejecucion)) paste("ejecución", paste(f$ejecucion, collapse = ", "))
    else if (!is.null(f$fecha_desde)) paste0("del ", fmt_fecha(paste0(f$fecha_desde, "T00:00:00")) |> substr(1, 10), " al ",
                                              fmt_fecha(paste0(f$fecha_hasta, "T00:00:00")) |> substr(1, 10))
    else if (!is.null(u)) paste0("última ejecución de cada comercio (", fmt_fecha(max(u$fecha_hora_inicio)) |> substr(1, 10), ")")
    else "última ejecución"
  })

  # Datos filtrados (consulta SQL parametrizada, en caché hasta que cambie la base)
  datos <- reactive(con_error(do.call(db_precios_filtrados, c(filtros_d(), list(ruta = db()))))) |>
    bindCache(filtros_d(), ver(), db())

  output$fecha_datos <- renderUI({
    u <- ultima(); req(u)
    tags$small(class = "text-muted", "Datos al ", strong(fmt_fecha(max(u$fecha_hora_inicio))), br(),
               "Estado: ", paste(paste0(nombre_comercio(u$comercio), " ", u$estado), collapse = " · "))
  })

  # ---- Resumen: indicadores (cada uno calculado con SQL) ----
  tarjeta <- function(titulo, valor, detalle) value_box(title = titulo, value = valor, p(class = "small mb-0", detalle), theme = "light")

  ind_f <- reactive({
    f <- filtros_d()
    list(prod = con_error(db_ind_productos(f, db())), promo = con_error(db_ind_promocion(f, db())),
         med = con_error(db_ind_mediana(f, db(), "global")))
  }) |> bindCache(filtros_d(), ver(), db())
  ind_c <- reactive(list(ahorro = con_error(db_ind_ahorro_max(ref(), db())), cambios = con_error(db_ind_cambios(ref(), db())),
                         barato = con_error(db_ind_mas_barato(ref(), db())))) |> bindCache(ref(), ver(), db())

  output$ind_filtrados <- renderUI({
    i <- ind_f(); validar(i$prod); per <- periodo(); pr <- i$prod; pm <- i$promo; md <- i$med
    layout_column_wrap(width = "280px", fill = FALSE,
      tarjeta("Productos observados", fmt_num(sum(pr$productos)),
              paste0(paste0(nombre_comercio(pr$comercio), ": ", fmt_num(pr$productos)), collapse = " · ")),
      tarjeta("Productos en promoción", fmt_pct(pm$pct), paste0(fmt_num(pm$en_promocion), " de ", fmt_num(pm$productos), " productos · ", per)),
      tarjeta("Precio mediano", fmt_cop(md$mediana_cop[1]), paste0("COP · ", fmt_num(md$n[1]), " productos con precio · ", per)))
  })
  output$ind_fijos <- renderUI({
    c <- ind_c(); u <- ultima(); ah <- c$ahorro; cb <- c$cambios; br <- c$barato
    layout_column_wrap(width = "260px", fill = FALSE,
      tarjeta("Última ejecución", if (!is.null(u)) substr(fmt_fecha(max(u$fecha_hora_inicio)), 1, 10) else "—",
              if (!is.null(u)) paste0(substr(fmt_fecha(max(u$fecha_hora_inicio)), 12, 16), " · ", paste(nombre_comercio(u$comercio), u$estado, collapse = " · ")) else ""),
      tarjeta("Mayor ahorro entre comercios", if (NROW(ah)) fmt_cop(ah$ahorro_cop) else "—",
              if (NROW(ah)) paste0(fmt_pct(ah$ahorro_pct), " en ", abreviar(ah$producto_estandar, 34), " (compre en ", paste(nombre_comercio(strsplit(ah$comercios_mas_baratos, ", ")[[1]]), collapse = " o "), ")") else "Sin comparables"),
      tarjeta("Cambios de precio", fmt_num(cb$cambios), paste0(fmt_num(cb$subieron), " subieron · ", fmt_num(cb$bajaron), " bajaron · ejecución ", ref())),
      tarjeta("Comercio más barato", if (NROW(br)) nombre_comercio(br$comercio[1]) else "—",
              if (NROW(br)) paste0("más barato en ", br$productos_mas_barato[1], " de ", br$comparables[1], " productos comparables (ejecución ", ref(), ")") else ""))
  })

  output$g_distribucion <- renderHighchart({
    q <- con_error(db_cuantiles_precio(filtros_d(), db())); validar(q)
    grafico_distribucion(q, paste0("Caja: P25–P75 · bigotes: P5–P95 · línea: mediana · ", periodo()))
  }) |> bindCache(filtros_d(), ver(), db())
  output$g_mediana <- renderHighchart({
    m <- con_error(db_ind_mediana(filtros_d(), db())); validar(m)
    grafico_mediana_subcat(m, periodo())
  }) |> bindCache(filtros_d(), ver(), db())
  promo_df <- reactive(con_error(db_promocion_por_comercio(filtros_d(), db()))) |> bindCache(filtros_d(), ver(), db())
  output$g_promocion <- renderHighchart({ d <- promo_df(); validar(d); grafico_promocion(d, periodo()) })
  output$g_disponibilidad <- renderHighchart({ d <- promo_df(); validar(d); grafico_disponibilidad(d, periodo()) })

  # ---- Comparar comercios ----
  serie <- reactive({ req(input$ev_producto); con_error(db_serie_precio(input$ev_producto, ruta = db())) }) |>
    bindCache(input$ev_producto, ver(), db())
  output$g_evolucion <- renderHighchart({
    s <- serie(); validar(s, "Este producto no tiene observaciones.")
    grafico_evolucion(s, nombres_prod()[[input$ev_producto]] %||% input$ev_producto,
                      paste0(nrow(s), " observaciones · ", length(unique(s$ejecucion_id)), " ejecuciones"), eje = input$ev_eje %||% "fecha")
  })
  output$nota_evolucion <- renderUI({
    s <- serie(); req(NROW(s) > 0); todos <- catalogo()$comercios; sin <- setdiff(todos, unique(s$comercio[!is.na(s$precio_cop)]))
    div(class = "nota-grafico", "Una línea por comercio. Los tramos sin línea son ejecuciones en las que el producto no tuvo precio (agotado o no listado).",
        if (length(sin)) paste0(" Sin precio en ningún momento: ", paste(nombre_comercio(sin), collapse = ", "), "."))
  })
  cob_unit <- reactive({ req(input$pu_ejec); con_error(db_cobertura_comparables(input$pu_ejec, db())) }) |> bindCache(input$pu_ejec, ver(), db())
  output$g_unitario <- renderHighchart({
    req(input$pu_ejec, input$pu_unidad)
    d <- con_error(db_precio_unitario(input$pu_ejec, input$pu_unidad, db()))
    validar(d, paste0("No hay productos comparables medidos en ", input$pu_unidad, " en esta ejecución."))
    grafico_precio_unitario(d, input$pu_unidad, paste0("Ejecución ", input$pu_ejec, " · ", fmt_fecha(d$fecha_hora_consulta[1] %||% NA)))
  }) |> bindCache(input$pu_ejec, input$pu_unidad, ver(), db())
  output$nota_unitario <- renderUI({
    cb <- cob_unit(); req(NROW(cb) > 0)
    mostrados <- cb$producto_id[cb$unidad_norm == input$pu_unidad & cb$n_comercios > 0]
    otra <- cb[cb$unidad_norm != input$pu_unidad, ]
    div(class = "nota-grafico", sprintf("Se muestran %d de %d productos comparables (los medidos en %s).", length(mostrados), nrow(cb), input$pu_unidad),
        if (nrow(otra)) paste0(" Los demás se miden en otra unidad y no se mezclan: ", paste(paste0(otra$producto_id, " (", otra$unidad_norm, ")"), collapse = ", "), ". Cámbiela arriba para verlos."))
  })
  cob_sc <- reactive({ req(input$sc_ejec); con_error(db_cobertura_comparables(input$sc_ejec, db())) }) |> bindCache(input$sc_ejec, ver(), db())
  output$g_sobrecosto <- renderHighchart({
    req(input$sc_ejec)
    d <- con_error(db_sobrecosto(input$sc_ejec, db())); validar(d, "No hay productos comparables con precio en al menos dos comercios en esta ejecución.")
    grafico_sobrecosto(d, paste0("Ejecución ", input$sc_ejec, " · 0 % = el comercio más barato de ese producto"))
  }) |> bindCache(input$sc_ejec, ver(), db())
  output$nota_sobrecosto <- renderUI({
    cb <- cob_sc(); req(NROW(cb) > 0); ok <- cb[cb$n_comercios >= 2, ]; falta <- cb[cb$n_comercios < 2, ]
    div(class = "nota-grafico", sprintf("Se muestran %d de %d productos comparables: solo los que tienen precio en 2 o más comercios.", nrow(ok), nrow(cb)),
        if (nrow(falta)) paste0(" No se comparan: ", paste(paste0(falta$producto_id, " (precio en ", falta$n_comercios, " comercio", ifelse(falta$n_comercios == 1, "", "s"), ")"), collapse = ", "), "."))
  })
  output$g_mas_barato <- renderHighchart({
    d <- con_error(db_ind_mas_barato(input$sc_ejec %||% ref(), db())); validar(d, "No hay comparables con precio en al menos dos comercios.")
    grafico_mas_barato(d, paste0("Ejecución ", input$sc_ejec %||% ref(), " · los empates cuentan para todos los comercios empatados"))
  })
  output$g_ahorro <- renderHighchart({
    d <- con_error(db_ahorro_producto(input$sc_ejec %||% ref(), db())); validar(d, "No hay comparables con precio en esta ejecución.")
    d <- d[d$n_comercios >= 2, ]; validar(d, "No hay comparables con precio en al menos dos comercios.")
    grafico_ahorro(d, paste0("Ejecución ", input$sc_ejec %||% ref(), " · diferencia entre el comercio más caro y el más barato"))
  })

  # ---- Productos: tabla con orden, búsqueda y descarga ----
  output$tabla <- renderDT({
    x <- datos(); validar(x)
    t <- tabla_productos(x)
    datatable(t, rownames = FALSE, escape = setdiff(seq_along(t), ncol(t)), selection = "none",
              options = list(pageLength = 15, lengthMenu = c(10, 15, 25, 50, 100), language = IDIOMA_DT, scrollX = TRUE,
                             order = list(list(4, "asc")))) |>
      formatCurrency("Precio (COP)", currency = "$", digits = 0, mark = ".", dec.mark = ",") |>
      formatCurrency("Precio unitario (COP)", currency = "$", digits = 1, mark = ".", dec.mark = ",")
  })
  output$descargar <- downloadHandler(
    filename = function() paste0("productos_filtrados_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      x <- datos(); req(NROW(x) > 0)
      con <- file(file, "wb"); writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con); close(con)    # BOM: Excel lee bien las tildes
      suppressWarnings(write.table(tabla_productos(x, para_csv = TRUE), file, sep = ",", row.names = FALSE,
                                   fileEncoding = "UTF-8", append = TRUE, qmethod = "double"))
    })

  # ---- Cambios de precio entre dos ejecuciones elegidas ----
  cambios <- reactive({
    req(input$cb_anterior, input$cb_actual)
    shiny::validate(
      shiny::need(
        input$cb_anterior != input$cb_actual,
        "Elija dos ejecuciones distintas para comparar."
      )
    ) ### cambiar 358
    ids <- sort(c(input$cb_anterior, input$cb_actual))                                   # anterior = la más antigua
    d <- con_error(db_comparar_ejecuciones(ids[1], ids[2], db())); validar(d, "No hay productos para comparar en estas ejecuciones.")
    clasificar_cambios(d, input$cb_umbral %||% 5)
  }) |> bindCache(input$cb_anterior, input$cb_actual, input$cb_umbral, ver(), db())
  output$cb_resumen <- renderUI({
    d <- cambios(); n <- function(t) sum(d$tipo == t)
    caja <- function(t, v) value_box(title = t, value = fmt_num(v), theme = "light")
    layout_column_wrap(width = "170px", fill = FALSE, caja("Subieron", n("subió")), caja("Bajaron", n("bajó")),
                       caja("Nuevos", n("nuevo")), caja("No observados", n("no observado")),
                       caja("Sin precio en alguna", n("sin precio en alguna ejecución")),
                       caja(paste0("Variación ≥ ", input$cb_umbral, " %"), sum(d$variacion_grande)))
  })
  output$cb_aviso <- renderUI({
    d <- cambios(); if (sum(d$variacion_grande) > 0) return(NULL)
    div(class = "alert alert-info small", sprintf("Ninguna variación llega a %s %% entre estas dos ejecuciones, por eso no hay filas amarillas. Pruebe con un umbral menor.", input$cb_umbral))
  })
  output$g_variaciones <- renderHighchart({
    d <- cambios(); validar(d[d$tipo %in% c("subió", "bajó"), ], "No hubo cambios de precio entre estas dos ejecuciones.")
    grafico_variaciones(d, paste0("Entre ", input$cb_anterior, " y ", input$cb_actual, " · rojo: subió · verde: bajó"))
  })
  output$cb_tabla <- renderDT({
    d <- cambios(); if (isTRUE(input$cb_solo_cambios)) d <- d[d$tipo != "igual", ]
    shiny::validate(need(nrow(d) > 0, "No hay cambios entre estas dos ejecuciones."))
    d <- d[order(-abs(d$variacion_pct), d$tipo), ]
    t <- data.frame(Comercio = nombre_comercio(d$comercio), Producto = d$nombre, Cambio = d$tipo,
                    `Precio anterior (COP)` = d$precio_anterior, `Precio actual (COP)` = d$precio_actual,
                    `Variación (COP)` = d$variacion_cop, `Variación (%)` = round(d$variacion_pct, 1),
                    `Variación grande` = ifelse(d$variacion_grande, "Sí", "No"),
                    Enlace = ifelse(!is.na(d$url) & grepl("^https?://", d$url),
                                    paste0("<a href='", htmltools::htmlEscape(d$url, attribute = TRUE), "' target='_blank' rel='noopener'>Ver anuncio</a>"), ""),
                    check.names = FALSE, stringsAsFactors = FALSE)
    datatable(t, rownames = FALSE, escape = seq_len(ncol(t) - 1), selection = "none",
              options = list(pageLength = 15, language = IDIOMA_DT, scrollX = TRUE)) |>
      formatCurrency(c("Precio anterior (COP)", "Precio actual (COP)", "Variación (COP)"), currency = "$", digits = 0, mark = ".", dec.mark = ",") |>
      # el color se aplica a CADA celda (con el estilo de fila, el tema de la página lo tapa)
      formatStyle(columns = names(t), valueColumns = "Variación grande", target = "cell",
                  backgroundColor = styleEqual("Sí", "#FDE68A"), fontWeight = styleEqual("Sí", "600"))
  })

  # ---- Canasta ----
  output$c_cantidades <- renderUI({
    p <- input$c_productos; req(length(p) > 0)
    tagList(lapply(p, function(id) numericInput(paste0("cant_", id), paste("Cantidad de", id),
                                                value = isolate(input[[paste0("cant_", id)]]) %||% 1, min = 1, max = 99, step = 1)))
  })
  canasta <- reactive({
    p <- input$c_productos
    shiny::validate(need(length(p) > 0, "Elija al menos un producto para calcular la canasta."))
    cant <- vapply(p, function(id) as.numeric(input[[paste0("cant_", id)]] %||% 1), 0)
    shiny::validate(need(all(!is.na(cant) & cant >= 1), "Las cantidades deben ser números mayores o iguales a 1."))
    req(input$c_ejec)
    con_error(db_canasta(data.frame(producto_id = p, cantidad = cant), input$c_ejec, db()))
  })
  output$g_canasta_total <- renderHighchart({
    r <- canasta(); validar(r)
    grafico_canasta_total(r$detalle, r$por_comercio, paste0("Ejecución ", r$ejecucion, " · solo comercios con la canasta completa"))
  })
  output$g_canasta_precios <- renderHighchart({
    r <- canasta(); validar(r)
    grafico_canasta_precios(r$detalle, nombres_prod(), paste0("Ejecución ", r$ejecucion, " · un producto sin barra = sin precio en ese comercio"))
  })
  output$c_resultado <- renderUI({
    r <- canasta(); validar(r); nm <- catalogo()$productos_comparables
    nombre <- function(id) nm$producto_estandar[match(id, nm$producto_id)]
    pc <- r$por_comercio
    caja <- function(t, v, d) value_box(title = t, value = v, p(class = "small mb-0", d), theme = "light")
    mejor <- pc[which.min(pc$total_cop), ]
    tagList(
      layout_column_wrap(width = "210px", fill = FALSE,
        caja("Todo en un solo comercio", if (is.finite(r$mejor_un_comercio)) fmt_cop(r$mejor_un_comercio) else "—",
             if (is.finite(r$mejor_un_comercio)) paste0("el más barato con la canasta completa: ", nombre_comercio(mejor$comercio)) else "ningún comercio tiene todos los productos"),
        caja("Cada producto donde es más barato", fmt_cop(r$total_minimo),
             if (is.na(r$total_minimo)) "falta al menos un producto en todos los comercios" else "suma de los precios mínimos"),
        caja("Ahorro", fmt_cop(r$ahorro_cop), "frente a comprar todo en el comercio más barato")),
      card(height = "520px", full_screen = TRUE, highchartOutput("g_canasta_total", height = "460px")),
      card(height = "520px", full_screen = TRUE, highchartOutput("g_canasta_precios", height = "460px")),
      card(card_header("Costo de la canasta por comercio (COP)"),
        tags$table(class = "table table-sm", tags$thead(tags$tr(tags$th("Comercio"), tags$th("Total"), tags$th("Detalle"))),
          tags$tbody(lapply(seq_len(nrow(pc)), function(i) tags$tr(
            tags$td(nombre_comercio(pc$comercio[i])),
            tags$td(if (is.na(pc$total_cop[i])) "—" else fmt_cop(pc$total_cop[i])),
            tags$td(if (is.na(pc$total_cop[i])) span(class = "text-danger", paste0("Canasta incompleta: no tiene ", paste(pc$faltantes[i], collapse = ", "))) else "Completa")))))),
      card(card_header("Dónde comprar cada producto"),
        tags$table(class = "table table-sm", tags$thead(tags$tr(lapply(c("Producto", "Cantidad", "Precio mínimo", "Subtotal", "Más barato en"), tags$th))),
          tags$tbody(lapply(seq_len(nrow(r$mejor_por_producto)), function(i) { b <- r$mejor_por_producto[i, ]; tags$tr(
            tags$td(paste(b$producto_id, "·", abreviar(nombre(b$producto_id), 40))), tags$td(b$cantidad),
            tags$td(fmt_cop(b$precio_min)), tags$td(fmt_cop(b$subtotal_min)),
            tags$td(if (is.na(b$precio_min)) "sin precio en ningún comercio" else paste(nombre_comercio(strsplit(b$comercios_mas_baratos, ", ")[[1]]), collapse = ", "))) })))),
      div(class = "alert alert-warning small", r$aviso, " Precios de la ejecución ", r$ejecucion, "."))
  })
}

shinyApp(ui, server)
