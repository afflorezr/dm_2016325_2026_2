# app.R — Comparador de precios de cuidado bucal · Taller 2 · Minería de Datos (2016325) · UNAL.
#
# Interfaz (bslib) y servidor. Aquí no hay SQL ni scraping: las consultas están en db.R, la
# extracción en scraper.R, las reglas en validacion.R y limpieza.R, y los gráficos en graficos.R.
# Ejecutar desde la carpeta taller_2/:  shiny::runApp()

library(shiny)
library(bslib)
library(promises)
library(future)

source("limpieza.R", encoding = "UTF-8"); source("validacion.R", encoding = "UTF-8"); source("scraper.R", encoding = "UTF-8"); source("db.R", encoding = "UTF-8"); source("graficos.R", encoding = "UTF-8")

plan(multisession, workers = 2)             # la actualización corre en otro proceso de R
.opciones_idioma()

# La base del Taller 1 se adapta una sola vez (tablas, columnas y vistas nuevas; no borra datos).
local({
  con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH); on.exit(DBI::dbDisconnect(con))
  if (!.hay_tabla(con, "v_catalogo") || !.hay_tabla(con, "comparables_referencia")) {
    DBI::dbDisconnect(conectar(DB_PATH))
  }
})
CON <- abrir_conexion(DB_PATH)              # una sola conexión de lectura para toda la aplicación
onStop(function() cerrar_conexion(CON))

AVISO_CANASTA <- paste("El resultado no incluye costos de envío, mínimos de compra ni las condiciones de las",
                       "promociones (cupos, medios de pago, unidades mínimas). Los precios son los del momento de la captura.")

# ---------------------------------------------------------------------------
# Interfaz
# ---------------------------------------------------------------------------
tarjeta_indicador <- function(titulo, id, detalle_id, tema = NULL) {
  value_box(title = titulo, value = textOutput(id, inline = TRUE), p(textOutput(detalle_id, inline = TRUE), class = "small mb-0"),
            theme = tema, min_height = "0", fill = FALSE)
}

ui <- page_navbar(
  title = tags$span(tags$span(class = "marca"), "Comparador de precios"),
  window_title = "Comparador de precios \u00b7 Cuidado bucal",
  id = "pagina", lang = "es", fillable = FALSE,
  theme = tema_app(),
  header = tags$head(tags$style(HTML(ESTILOS_APP))),
  sidebar = sidebar(
    width = 310, title = "Filtros",
    selectizeInput("f_comercio", "Comercio", choices = NULL, multiple = TRUE, options = list(placeholder = "Todos")),
    selectizeInput("f_subcategoria", "Subcategoría", choices = NULL, multiple = TRUE, options = list(placeholder = "Todas")),
    selectizeInput("f_marca", "Marca", choices = NULL, multiple = TRUE, options = list(placeholder = "Todas")),
    layout_columns(col_widths = c(6, 6), gap = "0.5rem",
      numericInput("f_precio_min", "Precio mín. (COP)", value = NA, min = 0, step = 1000),
      numericInput("f_precio_max", "Precio máx. (COP)", value = NA, min = 0, step = 1000)),
    selectInput("f_ejecucion", "Ejecución (fecha de los precios)", choices = NULL),
    conditionalPanel("input.f_ejecucion == 'rango'",
      dateRangeInput("f_fechas", "Rango de fechas", language = "es", separator = " a ", format = "yyyy-mm-dd")),
    input_switch("f_promocion", "Solo promociones", FALSE),
    input_switch("f_comparable", "Solo productos comparables", FALSE),
    textInput("f_texto", "Buscar en el nombre o en el anuncio", placeholder = "p. ej. colgate total"),
    uiOutput("aviso_busqueda"),
    actionButton("limpiar", "Limpiar filtros", class = "btn-outline-secondary btn-sm"),
    hr(class = "my-2"),
    div(class = "small text-muted", uiOutput("pie_datos"))
  ),

  nav_panel("Resumen",
    uiOutput("aviso_sin_datos"),
    layout_column_wrap(width = "230px", fill = FALSE,
      tarjeta_indicador("Productos (anuncios)", "ind_productos", "ind_productos_det"),
      tarjeta_indicador("Última ejecución", "ind_ultima", "ind_ultima_det"),
      tarjeta_indicador("En promoción", "ind_promo", "ind_promo_det"),
      tarjeta_indicador("Precio mediano", "ind_mediana", "ind_mediana_det"),
      tarjeta_indicador("Ahorro máximo entre comercios", "ind_ahorro", "ind_ahorro_det"),
      tarjeta_indicador("Cambios de precio", "ind_cambios", "ind_cambios_det"),
      tarjeta_indicador("Agotados según el sitio", "ind_agotado", "ind_agotado_det")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Distribución de precios por comercio"),
           highcharter::highchartOutput("g_distribucion", height = "290px"),
           card_footer(class = "small text-muted", textOutput("nota_distribucion", inline = TRUE))),
      card(card_header("Productos y observaciones por comercio"), div(class = "tabla-logos", style = "overflow-x: auto;", tableOutput("t_comercios")),
           card_footer(class = "small text-muted", textOutput("nota_comercios", inline = TRUE)))),
    card(card_header("Precio mediano por subcategoría (COP)"), tableOutput("t_medianas"))
  ),

  nav_panel("Comercios",
    div(class = "titulo-seccion", span(textOutput("titulo_comercios", inline = TRUE))),
    uiOutput("fichas_comercios"),
    layout_columns(col_widths = c(5, 7), class = "mt-3",
      card(card_header("¿Quién es más barato?"),
           uiOutput("waffle"),
           card_footer(class = "small", textOutput("nota_waffle", inline = TRUE))),
      card(card_header("Composici\u00f3n del cat\u00e1logo"),
           highcharter::highchartOutput("g_composicion", height = "420px"),
           card_footer(class = "small", textOutput("nota_composicion", inline = TRUE)))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Del comercio a la marca"),
           highcharter::highchartOutput("g_sunburst", height = "540px"),
           card_footer(class = "small", textOutput("nota_sunburst", inline = TRUE))),
      card(card_header("Las marcas de cada comercio"),
           highcharter::highchartOutput("g_burbujas", height = "540px"),
           card_footer(class = "small", textOutput("nota_burbujas", inline = TRUE))))
  ),

  nav_panel("Productos",
    card(card_header(class = "d-flex justify-content-between align-items-center", span("Productos filtrados"),
                     downloadButton("descargar", "Descargar CSV", class = "btn-sm btn-primary")),
         DT::DTOutput("t_productos", fill = FALSE),
         card_footer(class = "small text-muted", textOutput("nota_productos", inline = TRUE)))
  ),

  nav_panel("Comparar precios",
    card(card_header("Evolución del precio de un producto comparable"),
         selectizeInput("c_producto", "Producto comparable", choices = NULL, width = "100%"),
         highcharter::highchartOutput("g_evolucion", height = "320px"),
         card_footer(class = "small text-muted", "Una serie por comercio; cada punto es una ejecución. Precio en COP del anuncio disponible más barato de esa presentación. Los filtros de comercio se aplican.")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Precio por unidad de contenido"),
           layout_columns(col_widths = c(5, 7), gap = "0.5rem",
             selectInput("c_unidad", "Unidad de medida", choices = NULL),
             selectizeInput("c_subcategoria", "Subcategoría", choices = NULL, multiple = TRUE, options = list(placeholder = "Todas"))),
           highcharter::highchartOutput("g_unitario", height = "560px"),
           card_footer(class = "small text-muted", textOutput("nota_unitario", inline = TRUE))),
      card(card_header("¿En qué productos vale más la pena comparar antes de comprar?"),
           highcharter::highchartOutput("g_ahorro", height = "560px"),
           card_footer(class = "small text-muted", textOutput("nota_ahorro", inline = TRUE))))
  ),

  nav_panel("Cambios de precio",
    card(
      layout_columns(col_widths = c(4, 4, 4),
        selectInput("k_anterior", "Ejecución anterior", choices = NULL),
        selectInput("k_actual", "Ejecución actual", choices = NULL),
        sliderInput("k_umbral", "Resaltar variaciones desde (%)", min = 1, max = 50, value = 10, step = 1, post = " %")),
      uiOutput("k_resumen")),
    navset_card_tab(
      nav_panel("Subieron o bajaron", DT::DTOutput("k_cambios", fill = FALSE)),
      nav_panel("Productos nuevos", DT::DTOutput("k_nuevos", fill = FALSE)),
      nav_panel("Dejaron de observarse", p(class = "small text-muted",
        "Un producto no observado no se interpreta como agotado ni como retirado: solo se sabe que no apareció en esa ejecución."),
        DT::DTOutput("k_no_observados", fill = FALSE)))
  ),

  nav_panel("Canasta",
    layout_columns(col_widths = c(5, 7),
      card(card_header("Arme su canasta"),
           selectizeInput("b_productos", "Productos comparables", choices = NULL, multiple = TRUE, width = "100%",
                          options = list(placeholder = "Elija uno o varios productos", plugins = list("remove_button"))),
           uiOutput("b_cantidades"),
           selectInput("b_ejecucion", "Precios de la ejecución", choices = NULL),
           div(class = "alert alert-warning small mb-0", AVISO_CANASTA)),
      div(uiOutput("b_resumen"),
          card(card_header("Costo de la canasta en cada comercio"), div(class = "tabla-logos", tableOutput("b_comercios"))),
          card(card_header("Compra más barata: cada producto donde cuesta menos"), tableOutput("b_optimo"))))
  ),

  nav_panel("Actualizar datos",
    layout_columns(col_widths = c(4, 8),
      card(card_header("Actualizar precios"),
           p(class = "small", "Consulta de nuevo los tres comercios con el scraper del proyecto, guarda las copias crudas en ",
             code("raw/"), ", valida las observaciones y agrega a la base solo las que no existen."),
           input_switch("u_sin_conexion", "Modo sin conexión (reprocesar raw/)", FALSE),
           conditionalPanel("input.u_sin_conexion", selectInput("u_ejecucion", "Copias crudas a reprocesar", choices = NULL)),
           input_task_button("actualizar", "Actualizar precios", label_busy = "Actualizando…", class = "btn-primary"),
           uiOutput("u_progreso")),
      div(uiOutput("u_mensaje"),
          card(card_header("Resumen por comercio de la última actualización"), div(style = "overflow-x: auto;", tableOutput("u_resumen"))))),
    navset_card_tab(title = "Calidad y origen de los datos",
      nav_panel("Ejecuciones", DT::DTOutput("q_ejecuciones", fill = FALSE)),
      nav_panel("Disponibilidad", tableOutput("q_disponibilidad")),
      nav_panel("Correcciones", DT::DTOutput("q_correcciones", fill = FALSE)),
      nav_panel("Observaciones rechazadas", DT::DTOutput("q_rechazadas", fill = FALSE)))
  ),
  nav_spacer(),
  nav_item(span(class = "navbar-text small", textOutput("nav_fecha", inline = TRUE)))
)

# ---------------------------------------------------------------------------
# Servidor
# ---------------------------------------------------------------------------
server <- function(input, output, session) {
  version <- reactiveVal(0L)                # aumenta al terminar una actualización: invalida la caché

  ejecuciones <- reactive(listar_ejecuciones(CON)) |> bindCache(version())
  opciones <- reactive(opciones_filtros(CON)) |> bindCache(version())
  comparables <- reactive(lista_comparables(CON)) |> bindCache(version())
  ejecucion_reciente <- reactive({
    e <- ejecuciones(); e <- if (any(e$estado == "completa")) e[e$estado == "completa", ] else e[e$estado != "fallida", ]
    if (nrow(e)) e$ejecucion_id[1] else NULL
  })
  opciones_ejecucion <- function(e) stats::setNames(e$ejecucion_id, sprintf("%s · %s", etiqueta_ejecucion(e$ejecucion_id), e$estado))

  # Llena los selectores al iniciar y después de cada actualización, conservando lo elegido
  observe({
    op <- opciones(); e <- ejecuciones(); comp <- comparables()
    validas <- e[e$estado != "fallida", ]
    isolate({
      updateSelectizeInput(session, "f_comercio", choices = stats::setNames(op$comercios$comercio_id, op$comercios$nombre), selected = input$f_comercio)
      updateSelectizeInput(session, "f_subcategoria", choices = op$subcategorias$subcategoria, selected = input$f_subcategoria)
      updateSelectizeInput(session, "f_marca", choices = op$marcas$marca, selected = input$f_marca, server = TRUE)
      ej <- opciones_ejecucion(validas)
      # Por defecto, la ejecución completa más reciente (una parcial no sirve para comparar comercios)
      completas <- unname(ej[validas$estado == "completa"])
      ej_def <- if (length(completas)) completas[1] else unname(ej[1])
      ej_ant <- if (length(completas) > 1) completas[2] else unname(ej[min(2, length(ej))])
      updateSelectInput(session, "f_ejecucion", choices = c(ej, "Rango de fechas (todas las ejecuciones)" = "rango"), selected = ej_def)
      updateDateRangeInput(session, "f_fechas", start = op$fechas$desde, end = op$fechas$hasta, min = op$fechas$desde, max = op$fechas$hasta)
      updateSelectInput(session, "k_actual", choices = ej, selected = ej_def)
      updateSelectInput(session, "k_anterior", choices = ej, selected = ej_ant)
      updateSelectInput(session, "b_ejecucion", choices = ej, selected = ej_def)
      prods <- split(stats::setNames(comp$producto_id, comp$producto),
                     factor(ifelse(is.na(comp$orden_referencia), comp$subcategoria, "Ocho productos de referencia"),
                            levels = unique(ifelse(is.na(comp$orden_referencia), comp$subcategoria, "Ocho productos de referencia"))))
      sel_c <- if (isTruthy(input$c_producto) && input$c_producto %in% comp$producto_id) input$c_producto else comp$producto_id[1]
      updateSelectizeInput(session, "c_producto", choices = prods, selected = sel_c)
      sel_b <- if (length(input$b_productos)) intersect(input$b_productos, comp$producto_id) else comp$producto_id[!is.na(comp$orden_referencia)]
      updateSelectizeInput(session, "b_productos", choices = prods, selected = sel_b)
      crudas <- ejecuciones_en_raw(RAW_DIR)
      ids <- sort(unique(crudas$ejecucion_id), decreasing = TRUE)
      updateSelectInput(session, "u_ejecucion", choices = c(stats::setNames(ids, etiqueta_ejecucion(ids)), "Todas las copias de raw/" = "todas"))
    })
  })

  observeEvent(input$limpiar, {
    for (id in c("f_comercio", "f_subcategoria", "f_marca")) updateSelectizeInput(session, id, selected = character(0))
    updateNumericInput(session, "f_precio_min", value = NA); updateNumericInput(session, "f_precio_max", value = NA)
    updateTextInput(session, "f_texto", value = "")
    update_switch("f_promocion", value = FALSE); update_switch("f_comparable", value = FALSE)
  })

  # ---- Filtros ----
  texto <- debounce(reactive(input$f_texto), 500)
  busqueda <- reactive(validar_busqueda(texto()))
  output$aviso_busqueda <- renderUI({
    b <- busqueda()
    if (!b$ok) div(class = "alert alert-warning small py-1 px-2", b$mensaje)
  })
  f <- reactive({
    req(input$f_ejecucion)
    por_rango <- identical(input$f_ejecucion, "rango")
    numero <- function(x) if (is.null(x) || is.na(x)) NULL else x
    filtros(comercios = input$f_comercio, subcategorias = input$f_subcategoria, marcas = input$f_marca,
            precio_min = numero(input$f_precio_min), precio_max = numero(input$f_precio_max),
            ejecucion = if (por_rango) NULL else input$f_ejecucion,
            fecha_desde = if (por_rango) format(input$f_fechas[1]) else NULL,
            fecha_hasta = if (por_rango) format(input$f_fechas[2]) else NULL,
            solo_promociones = input$f_promocion, solo_comparables = input$f_comparable,
            texto = if (busqueda()$ok) texto() else NULL)
  })
  # ejecución con la que se calculan las comparaciones entre comercios
  ejecucion_activa <- reactive(if (identical(input$f_ejecucion, "rango")) ejecucion_reciente() else input$f_ejecucion)
  periodo <- reactive({
    if (identical(input$f_ejecucion, "rango")) sprintf("del %s al %s", format(input$f_fechas[1]), format(input$f_fechas[2]))
    else paste("ejecución del", etiqueta_ejecucion(input$f_ejecucion))
  })

  ind <- reactive(indicadores(CON, f())) |> bindCache(f(), version())
  por_comercio <- reactive(conteo_por_comercio(CON, f())) |> bindCache(f(), version())
  tabla <- reactive(productos_filtrados(CON, f())) |> bindCache(f(), version())
  ahorros <- reactive(ahorro_por_producto(CON, ejecucion_activa(), input$f_comercio, input$f_subcategoria)) |>
    bindCache(ejecucion_activa(), input$f_comercio, input$f_subcategoria, version())
  hay_datos <- reactive(isTRUE(ind()$observaciones > 0))
  SIN_DATOS <- "Ningún producto cumple los filtros elegidos. Quite algún filtro o use «Limpiar filtros»."

  output$aviso_sin_datos <- renderUI(if (!hay_datos()) div(class = "alert alert-info", SIN_DATOS))
  output$pie_datos <- renderUI({
    u <- ultima_ejecucion(CON); version()
    tagList(lapply(names(COMERCIOS), function(cid) div(class = "comercio-logo",
              HTML(logo_html(cid, 20)), span(class = "punto", style = paste0("background:", color_comercio(cid))), COMERCIOS[[cid]][1])),
            div(class = "mt-2", sprintf("Precios en pesos colombianos (COP). Última ejecución: %s.", fecha_hora(max(u$inicio)))))
  })
  output$nav_fecha <- renderText({
    req(ejecucion_reciente())
    sprintf("Precios al %s", etiqueta_ejecucion(ejecucion_reciente()))
  })

  # ---- Indicadores ----
  output$ind_productos <- renderText(entero(ind()$productos))
  output$ind_productos_det <- renderText(sprintf("%s observaciones · %s", entero(ind()$observaciones), periodo()))
  output$ind_ultima <- renderText({ version(); fecha_hora(max(ultima_ejecucion(CON)$inicio)) })
  output$ind_ultima_det <- renderText({
    version(); u <- ultima_ejecucion(CON)
    paste(sprintf("%s: %s", u$comercio, u$estado), collapse = " · ")
  })
  output$ind_promo <- renderText(pct(ind()$pct_promocion))
  output$ind_promo_det <- renderText(sprintf("de las %s observaciones con precio · %s", entero(ind()$con_precio), periodo()))
  output$ind_mediana <- renderText(paste(cop(ind()$mediana_precio), "COP"))
  output$ind_mediana_det <- renderText(sprintf("mediana por anuncio · %s", periodo()))
  output$ind_ahorro <- renderText({
    a <- ahorros(); if (nrow(a) == 0) "—" else paste(cop(a$ahorro_cop[1]), "COP")
  })
  output$ind_ahorro_det <- renderText({
    a <- ahorros()
    if (nrow(a) == 0) return("sin productos comparables en la selección")
    sprintf("%s (%s menos en %s) · ejecución del %s", a$producto[1], pct(a$ahorro_pct[1], 0), a$comercio_mas_barato[1],
            etiqueta_ejecucion(ejecucion_activa()))
  })
  cambios_ult <- reactive(cambios_en_ejecucion(CON, ejecucion_activa())) |> bindCache(ejecucion_activa(), version())
  output$ind_cambios <- renderText(entero(cambios_ult()$cambios))
  output$ind_cambios_det <- renderText(sprintf("%s subieron y %s bajaron frente a la observación anterior · ejecución del %s",
    entero(cambios_ult()$subieron), entero(cambios_ult()$bajaron), etiqueta_ejecucion(ejecucion_activa())))
  output$ind_agotado <- renderText(pct(ind()$pct_agotado))
  output$ind_agotado_det <- renderText(sprintf("de las observaciones · %s", periodo()))

  # ---- Resumen ----
  output$g_distribucion <- highcharter::renderHighchart({
    d <- distribucion_precios(CON, f())
    validate(need(nrow(d) > 0, SIN_DATOS))
    grafico_distribucion(d)
  }) |> bindCache(f(), version())
  output$nota_distribucion <- renderText(sprintf(
    "Caja: cuartiles 1 a 3 con la mediana; bigotes: percentiles 5 y 95. Precios en COP por anuncio, %s.", periodo()))
  output$t_comercios <- renderTable({
    d <- por_comercio()
    validate(need(nrow(d) > 0, SIN_DATOS))
    data.frame(Comercio = paste0(logo_html(d$comercio_id, 18), d$comercio), Anuncios = entero(d$productos),
               `Con precio` = entero(d$con_precio), Promo = entero(d$en_promocion), Agotados = entero(d$agotados),
               check.names = FALSE)
  }, class = "tabla-compacta", align = "lrrrr", width = "100%", sanitize.text.function = function(x) x)
  output$nota_comercios <- renderText(sprintf("Conteos de anuncios y observaciones, %s.", periodo()))
  output$t_medianas <- renderTable({
    d <- mediana_por_subcategoria(CON, f())
    validate(need(nrow(d) > 0, SIN_DATOS))
    data.frame(`Subcategoría` = d$subcategoria, `Precio mediano (COP)` = cop(d$mediana),
               `Observaciones con precio` = entero(d$observaciones), Periodo = periodo(), check.names = FALSE)
  }, class = "tabla-compacta", align = "lrrl", width = "100%") |> bindCache(f(), version())

  # ---- Comercios ----
  perfil <- reactive(perfil_comercios(CON, f())) |> bindCache(f(), version())
  ganadores <- reactive(quien_es_mas_barato(CON, ejecucion_activa(), input$f_comercio, input$f_subcategoria)) |>
    bindCache(ejecucion_activa(), input$f_comercio, input$f_subcategoria, version())
  output$titulo_comercios <- renderText(sprintf("Tres comercios, frente a frente \u00b7 %s", periodo()))
  output$fichas_comercios <- renderUI({
    p <- perfil(); g <- ganadores()
    validate(need(nrow(p) > 0, SIN_DATOS))
    total <- sum(g$n)
    fichas <- lapply(seq_len(nrow(p)), function(i) {
      cid <- p$comercio_id[i]; gana <- sum(g$n[g$grupo == cid])
      ficha_comercio(cid, p$comercio[i],
        cifra = if (total > 0) pct(100 * gana / total, 0) else "\u2014",
        cifra_texto = if (total > 0) sprintf("m\u00e1s barato en %d de %d productos comparables", gana, total) else "sin productos comparables",
        filas = list(`Anuncios` = entero(p$anuncios[i]), `Marcas` = entero(p$marcas[i]),
                     `Precio mediano` = paste(cop(p$mediana[i]), "COP"), `En promoción` = pct(p$pct_promocion[i]),
                     `Agotados según el sitio` = pct(p$pct_agotado[i])))
    })
    do.call(layout_columns, c(list(col_widths = rep(12 %/% nrow(p), nrow(p)), fill = FALSE), fichas))
  })
  output$waffle <- renderUI({
    g <- ganadores()
    validate(need(nrow(g) > 0, "No hay productos comparables con precio en al menos dos de los comercios elegidos."))
    waffle_html(g)
  })
  output$nota_waffle <- renderText(sprintf(
    "Cada cuadro es 1 %% de los %s productos comparables con precio en al menos dos comercios. Ejecuci\u00f3n del %s.",
    entero(sum(ganadores()$n)), etiqueta_ejecucion(ejecucion_activa())))
  output$g_composicion <- highcharter::renderHighchart({
    d <- composicion_catalogo(CON, f())
    validate(need(nrow(d) > 0, SIN_DATOS))
    grafico_composicion(d)
  }) |> bindCache(f(), version())
  output$nota_composicion <- renderText(sprintf("Porcentaje de los anuncios de cada comercio en cada subcategor\u00eda, %s.", periodo()))
  output$g_sunburst <- highcharter::renderHighchart({
    d <- jerarquia_catalogo(CON, f())
    validate(need(nrow(d) > 0, SIN_DATOS))
    grafico_sunburst(d)
  }) |> bindCache(f(), version())
  output$nota_sunburst <- renderText(sprintf(paste(
    "Anillos de adentro hacia afuera: comercio, sus cinco subcategor\u00edas principales y sus tres marcas con m\u00e1s anuncios.",
    "El \u00e1rea es el n\u00famero de anuncios. Haga clic en un sector para acercarse y en el centro para volver. %s."),
    sub("^(.)", "\\U\\1", periodo(), perl = TRUE)))
  output$g_burbujas <- highcharter::renderHighchart({
    d <- marcas_por_comercio(CON, f())
    validate(need(nrow(d) > 0, SIN_DATOS))
    grafico_burbujas(d)
  }) |> bindCache(f(), version())
  output$nota_burbujas <- renderText(sprintf(
    "Las nueve marcas con m\u00e1s anuncios en cada comercio; el tama\u00f1o de la burbuja es el n\u00famero de anuncios. %s.",
    sub("^(.)", "\\U\\1", periodo(), perl = TRUE)))

  # ---- Tabla de productos ----
  enlace <- function(url) {
    ok <- !is.na(url) & grepl("^https?://", url)
    ifelse(ok, sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">Ver anuncio</a>', htmltools::htmlEscape(url, attribute = TRUE)), "")
  }
  opciones_dt <- list(pageLength = 15, scrollX = TRUE, language = list(
    search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas", info = "Filas _START_ a _END_ de _TOTAL_",
    infoEmpty = "Sin filas", infoFiltered = "(filtradas de _MAX_)", zeroRecords = "Ninguna fila coincide con la b\u00fasqueda",
    emptyTable = "Sin datos", processing = "Procesando\u2026", thousands = ".", decimal = ",",
    paginate = list(first = "Primera", last = "\u00daltima", `next` = "Siguiente", previous = "Anterior")))
  output$t_productos <- DT::renderDT({
    d <- tabla()
    validate(need(nrow(d) > 0, SIN_DATOS))
    vista <- data.frame(
      Comercio = d$comercio, Nombre = d$nombre, Marca = d$marca, `Presentación` = d$presentacion,
      `Precio (COP)` = d$precio, `Precio unitario (COP)` = round(d$precio_unitario, 2), `por` = d$unidad,
      `Promoción` = ifelse(d$es_promocion == 1, "Sí", "No"), Disponibilidad = d$disponibilidad,
      `Fecha de consulta` = fecha_hora(d$fecha_hora_consulta), Enlace = enlace(d$url_producto), check.names = FALSE)
    DT::datatable(vista, rownames = FALSE, escape = -11, filter = "none", options = opciones_dt, selection = "none") |>
      DT::formatCurrency("Precio (COP)", currency = "$ ", mark = ".", dec.mark = ",", digits = 0) |>
      DT::formatCurrency("Precio unitario (COP)", currency = "$ ", mark = ".", dec.mark = ",", digits = 2)
  }, server = TRUE)
  output$nota_productos <- renderText(sprintf(
    "%s filas, %s. Precio unitario = precio / contenido total, en COP por la unidad indicada. Sin precio: el sitio no lo publicó.",
    entero(nrow(tabla())), periodo()))
  output$descargar <- downloadHandler(
    filename = function() sprintf("cuidado_bucal_%s.csv", format(Sys.time(), "%Y%m%d_%H%M%S", tz = TZ)),
    content = function(archivo) {
      d <- tabla()
      d$es_promocion <- ifelse(d$es_promocion == 1, "si", "no"); d$moneda <- "COP"
      utils::write.csv(d, archivo, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    })

  # ---- Comparar precios ----
  output$g_evolucion <- highcharter::renderHighchart({
    req(input$c_producto)
    d <- evolucion_precio(CON, input$c_producto, input$f_comercio)
    d <- d[!is.na(d$precio), ]
    validate(need(nrow(d) > 0, "No hay precios de este producto en los comercios elegidos."))
    grafico_evolucion(d)
  }) |> bindCache(input$c_producto, input$f_comercio, version())

  observe({
    req(ejecucion_activa())
    u <- unidades_comparables(CON, ejecucion_activa()); version()
    updateSelectInput(session, "c_unidad", choices = stats::setNames(u$unidad, sprintf("%s (%d productos)", u$unidad, u$n)),
                      selected = isolate(if (isTruthy(input$c_unidad) && input$c_unidad %in% u$unidad) input$c_unidad else u$unidad[1]))
  })
  unitarios <- reactive({
    req(input$c_unidad, ejecucion_activa())
    precio_unitario_comparables(CON, ejecucion_activa(), input$c_unidad, NULL, input$f_comercio)
  }) |> bindCache(input$c_unidad, ejecucion_activa(), input$f_comercio, version())
  observe({
    subs <- sort(unique(unitarios()$subcategoria))
    updateSelectizeInput(session, "c_subcategoria", choices = subs, selected = isolate(intersect(input$c_subcategoria, subs)))
  })
  output$g_unitario <- highcharter::renderHighchart({
    d <- unitarios()
    if (length(input$c_subcategoria)) d <- d[d$subcategoria %in% input$c_subcategoria, ]
    validate(need(nrow(d) > 0, "No hay productos comparables con precio unitario para esta unidad y estos comercios."))
    grafico_precio_unitario(d, input$c_unidad)
  })
  output$nota_unitario <- renderText({
    d <- unitarios()
    sprintf("COP por %s, ejecución del %s. Solo presentaciones con contenido verificado; se muestran hasta 12 de %d (use la subcategoría para acotar). No se mezclan unidades.",
            input$c_unidad, etiqueta_ejecucion(ejecucion_activa()), length(unique(d$producto)))
  })
  output$g_ahorro <- highcharter::renderHighchart({
    a <- ahorros()
    validate(need(nrow(a) > 0 && any(a$ahorro_cop > 0), "No hay productos comparables con precios distintos entre los comercios elegidos."))
    grafico_ahorro(a)
  })
  output$nota_ahorro <- renderText(sprintf(
    "Diferencia en COP entre el comercio más caro y el más barato para la misma presentación; la etiqueta es el ahorro en %%. Los 12 mayores, ejecución del %s.",
    etiqueta_ejecucion(ejecucion_activa())))

  # ---- Cambios de precio ----
  comparacion <- reactive({
    req(input$k_anterior, input$k_actual)
    validate(need(input$k_anterior != input$k_actual, "Elija dos ejecuciones distintas para comparar."))
    comparar_ejecuciones(CON, input$k_anterior, input$k_actual, input$f_comercio, input$k_umbral)
  }) |> bindCache(input$k_anterior, input$k_actual, input$f_comercio, input$k_umbral, version())
  output$k_resumen <- renderUI({
    r <- comparacion()$resumen
    caja <- function(titulo, valor) div(class = "col", div(class = "border rounded p-2 h-100", div(class = "small text-muted", titulo), div(class = "fs-5", valor)))
    tagList(
      div(class = "row row-cols-2 row-cols-md-6 g-2",
          caja("Anuncios comparados", entero(r$comparados)), caja("↑ Subieron", entero(r$subieron)), caja("↓ Bajaron", entero(r$bajaron)),
          caja(sprintf("Variación ≥ %d %%", input$k_umbral), entero(r$grandes)), caja("Nuevos", entero(r$nuevos)),
          caja("Dejaron de observarse", entero(r$no_observados))),
      p(class = "small text-muted mt-2 mb-0", sprintf("De %s a %s. Se compara el mismo anuncio en el mismo comercio; precios en COP.",
                                                       etiqueta_ejecucion(input$k_anterior), etiqueta_ejecucion(input$k_actual))))
  })
  output$k_cambios <- DT::renderDT({
    d <- comparacion()$cambios
    validate(need(nrow(d) > 0, "Ningún precio cambió entre estas dos ejecuciones en los comercios elegidos."))
    vista <- data.frame(Comercio = d$comercio, Nombre = d$nombre, `Presentación` = d$presentacion,
      `Precio anterior (COP)` = d$precio_anterior, `Precio actual (COP)` = d$precio_actual, `Cambio (COP)` = d$cambio_cop,
      `Cambio (%)` = round(d$cambio_pct, 1), Movimiento = ifelse(d$tipo == "subió", "↑ subió", "↓ bajó"),
      `Variación grande` = ifelse(d$variacion_grande == 1, "Sí", "No"), Enlace = enlace(d$url_producto), check.names = FALSE)
    DT::datatable(vista, rownames = FALSE, escape = -10, options = opciones_dt, selection = "none") |>
      DT::formatCurrency(c("Precio anterior (COP)", "Precio actual (COP)", "Cambio (COP)"), currency = "$ ", mark = ".", dec.mark = ",", digits = 0) |>
      DT::formatStyle("Variación grande", target = "row", fontWeight = DT::styleEqual("Sí", "bold"))
  })
  tabla_simple <- function(d, vacio, columnas) {
    validate(need(nrow(d) > 0, vacio))
    vista <- stats::setNames(d[names(columnas)], unname(columnas))
    vista$Enlace <- enlace(d$url_producto)
    precio <- grep("COP", names(vista), value = TRUE)
    DT::datatable(vista, rownames = FALSE, escape = -ncol(vista), options = opciones_dt, selection = "none") |>
      DT::formatCurrency(precio, currency = "$ ", mark = ".", dec.mark = ",", digits = 0)
  }
  output$k_nuevos <- DT::renderDT(tabla_simple(comparacion()$nuevos,
    "No aparecieron productos nuevos entre estas dos ejecuciones.",
    c(comercio = "Comercio", nombre = "Nombre", presentacion = "Presentación", precio = "Precio (COP)", disponibilidad = "Disponibilidad")))
  output$k_no_observados <- DT::renderDT(tabla_simple(comparacion()$no_observados,
    "Todos los productos de la ejecución anterior se volvieron a observar.",
    c(comercio = "Comercio", nombre = "Nombre", presentacion = "Presentación", ultimo_precio = "Último precio (COP)",
      disponibilidad_anterior = "Disponibilidad anterior")))

  # ---- Canasta ----
  output$b_cantidades <- renderUI({
    comp <- comparables(); ids <- input$b_productos
    if (!length(ids)) return(div(class = "alert alert-info small", "Elija al menos un producto comparable."))
    tagList(lapply(ids, function(id) {
      actual <- isolate(input[[paste0("cant_", id)]])
      div(class = "d-flex align-items-center gap-2 mb-1 cantidad",
          div(style = "width: 5.5rem;", numericInput(paste0("cant_", id), NULL, value = if (is.null(actual) || is.na(actual)) 1 else actual, min = 1, max = 99, step = 1)),
          div(class = "small", comp$producto[match(id, comp$producto_id)]))
    }))
  })
  canasta <- reactive({
    req(input$b_ejecucion); ids <- input$b_productos
    validate(need(length(ids) > 0, "Elija al menos un producto comparable para calcular la canasta."))
    cant <- vapply(ids, function(id) { v <- input[[paste0("cant_", id)]]; if (is.null(v) || is.na(v)) 1 else max(1, min(99, round(v))) }, numeric(1))
    version()
    calcular_canasta(CON, data.frame(producto_id = ids, cantidad = cant), input$b_ejecucion, input$f_comercio)
  })
  output$b_resumen <- renderUI({
    r <- canasta()$resumen
    ejec <- etiqueta_ejecucion(input$b_ejecucion)
    if (length(r$sin_precio)) {
      return(div(class = "alert alert-warning", sprintf("Ningún comercio tiene disponible: %s. No se calcula el costo mínimo (ejecución del %s).",
                                                         paste(r$sin_precio, collapse = "; "), ejec)))
    }
    layout_column_wrap(width = 1 / 3, fill = FALSE,
      value_box("Costo mínimo combinando comercios", paste(cop(r$total_minimo), "COP"), p(class = "small mb-0", paste("ejecución del", ejec)), theme = "primary", min_height = "110px"),
      value_box("Mejor comercio único", if (is.na(r$total_mejor_comercio)) "—" else paste(cop(r$total_mejor_comercio), "COP"),
                p(class = "small mb-0", if (is.na(r$mejor_comercio)) "ningún comercio tiene todos los productos" else r$mejor_comercio), min_height = "110px"),
      value_box("Ahorro por combinar comercios", if (is.na(r$ahorro)) "—" else paste(cop(r$ahorro), "COP"),
                p(class = "small mb-0", if (is.na(r$ahorro)) "no se puede calcular" else sprintf("%s frente al mejor comercio único", pct(r$ahorro_pct))), min_height = "110px"))
  })
  output$b_comercios <- renderTable({
    d <- canasta()$por_comercio
    data.frame(Comercio = paste0(logo_html(d$comercio_id, 18), d$comercio),
               `Costo de la canasta (COP)` = ifelse(is.na(d$total), "No se calcula: faltan productos", cop(d$total)),
               `Productos que faltan` = ifelse(is.na(d$faltantes), "—", htmltools::htmlEscape(d$faltantes)), check.names = FALSE)
  }, class = "tabla-compacta", width = "100%", sanitize.text.function = function(x) x)
  output$b_optimo <- renderTable({
    d <- canasta()$optimo
    data.frame(Producto = d$producto, Cantidad = entero(d$cantidad), `Comprar en` = ifelse(is.na(d$comercio), "No disponible", d$comercio),
               `Precio (COP)` = cop(d$precio), `Subtotal (COP)` = cop(d$subtotal), check.names = FALSE)
  }, class = "tabla-compacta", align = "lrlrr", width = "100%")

  # ---- Actualización en segundo plano ----
  archivo_progreso <- tempfile("progreso_", fileext = ".txt")
  tarea <- ExtendedTask$new(function(modo, ejecucion, archivo) {
    future_promise({
      source("limpieza.R", encoding = "UTF-8"); source("validacion.R", encoding = "UTF-8"); source("scraper.R", encoding = "UTF-8")
      avance <- function(cid, texto) cat(sprintf("%s|%s\n", cid, texto), file = archivo, append = TRUE)
      if (modo == "en_linea") ejecutar_recoleccion(verbose = FALSE, progreso = avance)
      else reprocesar_sin_conexion(ejecuciones = ejecucion, verbose = FALSE, progreso = avance)
    }, seed = TRUE)
  }) |> bind_task_button("actualizar")

  observeEvent(input$actualizar, {
    unlink(archivo_progreso)
    sin_conexion <- isTRUE(input$u_sin_conexion)
    tarea$invoke(if (sin_conexion) "sin_conexion" else "en_linea",
                 if (sin_conexion && !identical(input$u_ejecucion, "todas")) input$u_ejecucion else NULL, archivo_progreso)
  })
  resultado <- reactive(tryCatch(tarea$result(), error = function(e) structure(list(mensaje = conditionMessage(e)), class = "falla")))
  observeEvent(resultado(), {
    if (!inherits(resultado(), "falla")) version(version() + 1L)     # refresca indicadores, gráficos y tablas
  })
  output$u_progreso <- renderUI({
    if (tarea$status() != "running") return(NULL)
    invalidateLater(1000)
    lineas <- if (file.exists(archivo_progreso)) readLines(archivo_progreso, warn = FALSE, encoding = "UTF-8") else character(0)
    partes <- strsplit(lineas, "|", fixed = TRUE)
    ultimo <- list(); for (p in partes) if (length(p) == 2) ultimo[[p[1]]] <- p[2]
    nombre <- function(k) if (!is.null(COMERCIOS[[k]])) COMERCIOS[[k]][1] else "Correspondencia de productos"
    div(class = "small mt-2", if (!length(ultimo)) "Iniciando…", lapply(names(ultimo), function(k) div(strong(nombre(k)), ": ", ultimo[[k]])))
  })
  output$u_mensaje <- renderUI({
    if (tarea$status() == "initial") return(div(class = "alert alert-secondary", "Aún no se ha ejecutado una actualización en esta sesión."))
    if (tarea$status() == "running") return(div(class = "alert alert-info", "Actualización en curso. Puede seguir usando la aplicación mientras termina."))
    r <- resultado()
    if (inherits(r, "falla")) return(div(class = "alert alert-danger", "La actualización no se pudo completar: ", r$mensaje))
    fallidos <- r[r$estado == "fallida", ]
    if (nrow(fallidos) == nrow(r) && r$modo[1] == "en_linea") {
      return(div(class = "alert alert-danger", strong("No se pudo consultar ningún comercio desde este servidor. "),
                 "Los comercios suelen bloquear las plataformas de despliegue. La base no cambió. Active «Modo sin conexión» para reprocesar las copias de raw/. ",
                 "Motivo: ", fallidos$mensaje[1]))
    }
    tagList(
      if (nrow(fallidos) > 0) div(class = "alert alert-warning", sprintf("Falló %s; los demás comercios se actualizaron. Motivo: %s",
                                                                          paste(fallidos$comercio, collapse = ", "), fallidos$mensaje[1])),
      div(class = "alert alert-success", sprintf("Actualización terminada (%s): %s observaciones nuevas. Indicadores, gráficos y tablas ya usan los datos actualizados.%s",
        if (r$modo[1] == "en_linea") "en línea" else "sin conexión", entero(sum(r$observaciones_nuevas)),
        if (all(r$ya_cargada)) " Estas copias ya estaban cargadas: no se duplicó ninguna observación." else "")))
  })
  output$u_resumen <- renderTable({
    validate(need(tarea$status() %in% c("success", "error"), "El resumen aparece al terminar la actualización."))
    r <- resultado()
    validate(need(!inherits(r, "falla"), "Sin resumen: la actualización falló."))
    data.frame(`Ejecución` = etiqueta_ejecucion(r$ejecucion_id), Comercio = r$comercio, Estado = r$estado,
               `Productos recolectados` = entero(r$recolectados), `Rechazados` = entero(r$rechazados),
               `Observaciones nuevas` = entero(r$observaciones_nuevas), `Productos nuevos` = entero(r$productos_nuevos),
               `Cambios de precio` = entero(r$cambios_precio), `No observados` = entero(r$no_observados),
               `Coinciden con la base` = entero(r$coinciden_raw), Motivo = ifelse(is.na(r$mensaje), "", r$mensaje), check.names = FALSE)
  }, class = "tabla-compacta", width = "100%")

  # ---- Calidad y origen de los datos ----
  dt_plana <- function(d, vacio) {
    validate(need(nrow(d) > 0, vacio))
    DT::datatable(d, rownames = FALSE, options = c(opciones_dt, list(pageLength = 8)), selection = "none")
  }
  output$q_ejecuciones <- DT::renderDT({ version(); dt_plana(detalle_ejecuciones(CON), "No hay ejecuciones registradas.") })
  output$q_correcciones <- DT::renderDT({ version(); dt_plana(listar_correcciones(CON), "No hay correcciones registradas.") })
  output$q_rechazadas <- DT::renderDT({ version(); dt_plana(listar_rechazadas(CON), "Ninguna observación ha sido rechazada por la validación.") })
  output$q_disponibilidad <- renderTable({
    version(); req(ejecucion_activa())
    d <- resumen_disponibilidad(CON, ejecucion_activa())
    validate(need(nrow(d) > 0, "Sin datos de disponibilidad."))
    d$estado <- c(disponible = "Disponible", agotado = "Agotado según el sitio", no_observado = "No observado en la ejecución", sin_dato = "Sin dato")[d$estado]
    data.frame(Comercio = d$comercio, Estado = d$estado, Anuncios = entero(d$anuncios), `Ejecución` = etiqueta_ejecucion(ejecucion_activa()), check.names = FALSE)
  }, class = "tabla-compacta")
}

shinyApp(ui, server)
