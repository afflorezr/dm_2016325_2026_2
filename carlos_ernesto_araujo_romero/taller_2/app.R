# =============================================================================
# app.R
# Comparador de precios de confitería — aplicación Shiny.
# Interfaz y servidor. Todo el acceso a datos vive en db.R y la extracción en
# scraper.R; aquí no hay SQL ni código de scraping.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(highcharter)
  library(DT)
  library(dplyr)
  library(promises)
  library(future)
  library(DBI)
})

source("db.R")
plan(multisession)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Formato numérico colombiano en los ejes y tooltips de Highcharts.
hc_lang <- function(h, thousandsSep = ".", decimalPoint = ",") {
  lang <- list(
    thousandsSep = thousandsSep, decimalPoint = decimalPoint,
    months = c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
               "agosto", "septiembre", "octubre", "noviembre", "diciembre"),
    shortMonths = c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago",
                    "sep", "oct", "nov", "dic"),
    weekdays = c("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"),
    shortWeekdays = c("dom", "lun", "mar", "mié", "jue", "vie", "sáb")
  )
  h$x$conf_opts$lang <- utils::modifyList(h$x$conf_opts$lang %||% list(), lang)
  h$x$hc_opts$lang <- lang
  h
}

PALETA <- c("Carulla" = "#B3122E", "Jumbo" = "#E8A200",
            "Olímpica" = "#1F5FA8", "Éxito" = "#0F8A4B")

cop <- function(x) {
  if (is.null(x) || length(x) == 0) return("—")
  out <- paste0("$ ", format(round(as.numeric(x)), big.mark = ".", decimal.mark = ",",
                             trim = TRUE))
  out[is.na(x)] <- "—"
  out
}

numero <- function(x) {
  if (is.null(x) || length(x) == 0) return("—")
  out <- format(x, big.mark = ".", decimal.mark = ",", trim = TRUE)
  out[is.na(x)] <- "—"
  out
}

etiqueta_ejecucion <- function(e) {
  paste0(substr(e$fecha_inicio, 1, 16), " · ", e$modo, " · ", e$estado,
         " · ", numero(e$n_registros), " registros")
}

colores_comercio <- function(nombres) {
  out <- unname(PALETA[nombres])
  out[is.na(out)] <- "#6B7280"
  out
}

# -----------------------------------------------------------------------------
# Interfaz
# -----------------------------------------------------------------------------

ui <- page_sidebar(
  title = tags$span(class = "fw-semibold", "Comparador de precios · Confitería"),
  theme = bs_theme(version = 5, primary = "#1F4E79", base_font = "system-ui",
                   heading_font = "system-ui", bg = "#F7F8FA", fg = "#1F2937"),
  sidebar = sidebar(
    width = 330,
    h6("Filtros de la categoría", class = "text-uppercase text-muted small fw-semibold"),
    selectInput("ejecucion", "Ejecución", choices = NULL),
    selectInput("comercios", "Comercios", choices = NULL, multiple = TRUE),
    selectInput("subcategoria", "Subcategoría", choices = NULL),
    selectInput("marca", "Marca", choices = NULL),
    sliderInput("precio", "Rango de precio (COP)", min = 0, max = 200000,
                value = c(0, 200000), step = 1000),
    checkboxInput("solo_promo", "Solo promociones", value = FALSE),
    checkboxInput("solo_comparables", "Solo productos comparables", value = FALSE),
    textInput("buscar", "Buscar en el nombre", placeholder = "Ej.: corona"),
    actionButton("limpiar", "Limpiar filtros", icon = icon("eraser"),
                 class = "btn-outline-secondary btn-sm w-100"),
    hr(),
    p(class = "small text-muted mb-0",
      "Precios en pesos colombianos (COP) del momento de la consulta. ",
      "No incluyen domicilio, mínimos de compra ni condiciones de las promociones.")
  ),
  navset_card_tab(
    id = "paginas",

    nav_panel(
      "Resumen", icon = icon("gauge-high"),
      div(class = "p-2",
        uiOutput("kpis"),
        layout_columns(
          col_widths = c(7, 5),
          card(
            card_header(
              class = "d-flex justify-content-between align-items-center gap-2",
              "Evolución del precio de una presentación",
              div(style = "min-width: 280px;", selectInput("producto_evolucion", NULL, choices = NULL, width = "280px"))
            ),
            highchartOutput("grafico_evolucion", height = 370),
            p(class = "small text-muted mb-0",
              "Solo presentaciones comparables. Cada punto es una consulta; ",
              "los cortes de la línea corresponden a ejecuciones distintas.")
          ),
          card(
            card_header("Ahorro potencial entre comercios"),
            highchartOutput("grafico_ahorro", height = 370),
            p(class = "small text-muted mb-0",
              "Ahorro = (precio máximo − mínimo) / máximo. El color indica el comercio ",
              "con el precio mínimo; en gris, los empates. Solo con los tres comercios.")
          )
        ),
        layout_columns(
          col_widths = c(6, 6),
          card(
            card_header("Distribución de precios de la categoría por comercio"),
            highchartOutput("grafico_distribucion", height = 380),
            p(class = "small text-muted mb-0",
              "Todos los anuncios disponibles de la categoría en el filtro actual, ",
              "agrupados en intervalos de $5.000. No son presentaciones comparables.")
          ),
          card(
            card_header(
              class = "d-flex justify-content-between align-items-center gap-2",
              "Precio por unidad de contenido",
              div(style = "min-width: 250px;", selectInput("producto_unidad", NULL, choices = NULL, width = "250px"))
            ),
            highchartOutput("grafico_unidad", height = 380),
            p(class = "small text-muted mb-0",
              "Solo presentaciones comparables. El indicador se expresa por 100 g, ",
              "por 100 mL o por unidad, sin mezclar unidades en el mismo gráfico.")
          )
        ),
        card(
          card_header("Qué dicen los datos"),
          uiOutput("lectura")
        )
      )
    ),

    nav_panel(
      "Productos", icon = icon("table-list"),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "Productos filtrados",
          downloadButton("descargar", "Descargar CSV", class = "btn-sm btn-outline-primary")
        ),
        DTOutput("tabla")
      ),
      card(
        card_header("Precio por unidad de las presentaciones comparables"),
        DTOutput("tabla_unidad")
      )
    ),

    nav_panel(
      "Cambios", icon = icon("arrow-trend-up"),
      div(class = "p-2",
        card(
          card_header("Comparar dos ejecuciones"),
          layout_columns(
            col_widths = c(4, 4, 2, 2),
            selectInput("cambio_a", "Ejecución anterior", choices = NULL),
            selectInput("cambio_b", "Ejecución actual", choices = NULL),
            numericInput("umbral", "Umbral (%)", value = 5, min = 0, max = 50, step = 1),
            checkboxInput("cambios_comparables", "Solo comparables", value = TRUE)
          ),
          uiOutput("aviso_cambios")
        ),
        uiOutput("resumen_cambios"),
        layout_columns(
          col_widths = c(7, 5),
          card(card_header("Mayores variaciones"), highchartOutput("grafico_cambios", height = 400)),
          card(card_header("Detalle"), DTOutput("tabla_cambios"))
        )
      )
    ),

    nav_panel(
      "Canasta", icon = icon("basket-shopping"),
      div(class = "p-2",
        card(
          card_header("Armar una canasta comparable"),
          p(class = "text-muted small",
            "Elija productos comparables y la cantidad de cada uno. El costo se calcula ",
            "solo con precios de la misma ejecución y solo si el comercio tiene todos los productos."),
          checkboxGroupInput("canasta_productos", "Productos", choices = NULL),
          uiOutput("canasta_cantidades")
        ),
        uiOutput("canasta_totales"),
        layout_columns(
          col_widths = c(7, 5),
          card(card_header("Costo de la canasta por comercio"), highchartOutput("grafico_canasta", height = 340)),
          card(card_header("Cómo leer el resultado"), uiOutput("canasta_nota"))
        )
      )
    ),

    nav_panel(
      "Actualizar", icon = icon("rotate"),
      div(class = "p-2",
        card(
          card_header("Actualizar precios"),
          p(class = "text-muted",
            "El botón ejecuta el módulo scraper.R sobre los comercios activos. ",
            "La recolección corre en segundo plano, valida cada observación y agrega una nueva ",
            "ejecución sin sobrescribir las anteriores."),
          div(class = "d-flex flex-wrap gap-2",
            uiOutput("boton_actualizar", inline = TRUE),
            uiOutput("boton_reprocesar", inline = TRUE)
          ),
          uiOutput("estado_tarea")
        ),
        card(card_header("Avance por comercio"), tableOutput("progreso")),
        card(card_header("Resumen de la última actualización"), uiOutput("resumen_actualizacion")),
        card(
          card_header("Últimas ejecuciones"),
          tableOutput("tabla_ejecuciones")
        )
      )
    ),

    nav_panel(
      "Acerca de", icon = icon("circle-info"),
      div(class = "p-2",
        card(
          card_header("Qué compara esta aplicación"),
          p("Categoría: confitería (chocolates, chocolate de mesa, caramelos, gomitas, ",
            "chicles y mentas). Comercios activos: Carulla, Jumbo y Olímpica. ",
            "Los datos provienen del módulo de scraping entregado en el Taller 1 y se ",
            "guardan en SQLite con su copia cruda en raw/."),
          p("Éxito aparece en el historial porque sus ejecuciones del Taller 1 se conservan. ",
            "El 11 de noviembre de 2026 Cloudflare bloqueó su dominio con HTTP 403; la ",
            "decisión de reemplazarlo por Olímpica está registrada en la tabla correcciones.")
        ),
        card(
          card_header("Vistas SQL de la base"),
          tags$ul(
            tags$li(tags$b("v_observaciones"), ": observaciones con nombres legibles."),
            tags$li(tags$b("v_ultimo_precio"), ": última observación de cada anuncio."),
            tags$li(tags$b("v_cambios_precio"), ": variaciones entre dos ejecuciones del mismo anuncio."),
            tags$li(tags$b("v_comparables"), ": catálogo canónico y cobertura de correspondencia."),
            tags$li(tags$b("v_disponibilidad"), ": disponible, agotado o no observado."),
            tags$li(tags$b("v_ahorro_presentacion"), ": mínimo, máximo, empates y ahorro."),
            tags$li(tags$b("v_precio_unitario"), ": precio por g, mL o unidad."),
            tags$li(tags$b("v_resumen_ejecucion"), ": totales de cada ejecución.")
          )
        ),
        card(
          card_header("Declaración de uso de inteligencia artificial"),
          p("El desarrollo de esta aplicación contó con asistencia de modelos de lenguaje ",
            "para el andamiaje de la interfaz, la redacción de consultas SQL, las pruebas ",
            "y la documentación. El estudiante ejecutó, revisó y validó cada módulo, y ",
            "conserva el historial de Git con los cambios. El detalle está en el README.md.")
        ),
        card(
          card_header("Limitaciones"),
          tags$ul(
            tags$li("Los precios son una fotografía del momento de la consulta."),
            tags$li("La disponibilidad cambia: un producto publicado puede estar agotado."),
            tags$li("La correspondencia de presentaciones es manual y está auditada."),
            tags$li("La canasta no incluye envío, mínimos de compra ni cupones."),
            tags$li("En un servidor público el scraping puede estar bloqueado; use el modo sin conexión.")
          )
        )
      )
    )
  )
)

# -----------------------------------------------------------------------------
# Servidor
# -----------------------------------------------------------------------------

server <- function(input, output, session) {
  con <- conectar()
  onStop(function() desconectar(con))

  version <- reactiveVal(0L)
  id_actual <- reactiveVal(NULL)
  seleccion_pendiente <- reactiveVal(NULL)

  ejecuciones <- reactive({
    version()
    listar_ejecuciones(con)
  })

  observe({
    ejs <- ejecuciones()
    req(nrow(ejs) > 0)
    choices <- setNames(ejs$id_ejecucion, etiqueta_ejecucion(ejs))
    actual <- isolate(input$ejecucion)
    pendiente <- seleccion_pendiente()
    if (!is.null(pendiente) && pendiente %in% ejs$id_ejecucion) {
      actual <- pendiente
      seleccion_pendiente(NULL)
    } else if (is.null(actual) || !actual %in% ejs$id_ejecucion) {
      actual <- ultima_ejecucion(con)
    }
    updateSelectInput(session, "ejecucion", choices = choices, selected = actual)
  })

  observeEvent(input$ejecucion, {
    req(input$ejecucion)
    ejs <- ejecuciones()
    fila <- ejs[ejs$id_ejecucion == input$ejecucion, , drop = FALSE]
    if (nrow(fila) == 0) return()

    detalle <- dbGetQuery(con, "
      SELECT DISTINCT c.id_comercio, c.nombre, c.activo
        FROM observaciones o
        JOIN comercios c ON c.id_comercio = o.id_comercio
       WHERE o.id_ejecucion = ?
       ORDER BY c.activo DESC, c.nombre", params = list(input$ejecucion))
    updateSelectInput(session, "comercios", choices = setNames(detalle$id_comercio, detalle$nombre),
                      selected = detalle$id_comercio)

    opciones <- opciones_filtros(con, input$ejecucion)
    updateSelectInput(session, "subcategoria", choices = c("Todas" = "", sort(unique(opciones$subcategoria))),
                      selected = "")
    updateSelectInput(session, "marca", choices = c("Todas" = "", sort(unique(opciones$marca))),
                      selected = "")

    rango <- rango_precios(con, input$ejecucion)
    updateSliderInput(session, "precio", min = rango[1], max = rango[2],
                      value = c(rango[1], rango[2]))

    comparables <- productos_comparables(con)
    etiquetas <- setNames(comparables$id_producto_comun,
                          paste0(comparables$nombre_canonico, " (", numero(comparables$contenido_total),
                                 " ", comparables$unidad_normalizada, ")"))
    seleccion <- if ("CONF_01_CORONA_TRAD_200G" %in% comparables$id_producto_comun) {
      "CONF_01_CORONA_TRAD_200G"
    } else {
      comparables$id_producto_comun[1]
    }
    updateSelectInput(session, "producto_evolucion", choices = etiquetas, selected = seleccion)
    updateSelectInput(session, "producto_unidad", choices = etiquetas, selected = seleccion)

    updateCheckboxGroupInput(session, "canasta_productos", choices = etiquetas,
                             selected = head(comparables$id_producto_comun, 4))

    updateSelectInput(session, "cambio_b", choices = setNames(ejs$id_ejecucion, etiqueta_ejecucion(ejs)),
                      selected = input$ejecucion)
    anterior <- ejecucion_anterior_misma_cobertura(con, input$ejecucion)
    if (is.na(anterior)) anterior <- ejecucion_anterior(con, input$ejecucion)
    updateSelectInput(session, "cambio_a", choices = setNames(ejs$id_ejecucion, etiqueta_ejecucion(ejs)),
                      selected = if (is.na(anterior)) input$ejecucion else anterior)
  })

  observeEvent(input$limpiar, {
    req(input$ejecucion)
    updateSelectInput(session, "subcategoria", selected = "")
    updateSelectInput(session, "marca", selected = "")
    updateCheckboxInput(session, "solo_promo", value = FALSE)
    updateCheckboxInput(session, "solo_comparables", value = FALSE)
    updateTextInput(session, "buscar", value = "")
    rango <- rango_precios(con, input$ejecucion)
    updateSliderInput(session, "precio", value = c(rango[1], rango[2]))
  })

  filtros <- reactive({
    list(comercios = input$comercios %||% character(),
         subcategoria = input$subcategoria %||% "",
         marca = input$marca %||% "",
         precio_min = input$precio[1],
         precio_max = input$precio[2],
         solo_promo = isTRUE(input$solo_promo),
         solo_comparables = isTRUE(input$solo_comparables),
         buscar = input$buscar %||% "")
  }) |> debounce(300)

  datos <- reactive({
    req(input$ejecucion)
    productos(con, input$ejecucion, filtros())
  }) |> bindCache(input$ejecucion, input$comercios, input$subcategoria, input$marca,
                  input$precio, input$solo_promo, input$solo_comparables, input$buscar,
                  version())

  # ---------------------------------------------------------------------------
  # Indicadores
  # ---------------------------------------------------------------------------

  output$kpis <- renderUI({
    req(input$ejecucion)
    ejec <- dbGetQuery(con, "SELECT fecha_inicio, estado, modo FROM ejecuciones WHERE id_ejecucion = ?",
                       params = list(input$ejecucion))
    k <- kpis(con, input$ejecucion, filtros())
    cajas <- lapply(seq_len(nrow(k)), function(i) {
      value_box(
        title = k$indicador[i],
        value = k$valor[i],
        p(class = "small text-muted mb-0", k$detalle[i]),
        theme = if (i == 1) "primary" else "light"
      )
    })
    tagList(
      p(class = "text-muted small mb-2",
        "Ejecución del ", substr(ejec$fecha_inicio[1], 1, 16),
        " · ", ejec$modo[1], " · ", ejec$estado[1],
        " · precios en COP del momento de la consulta"),
      do.call(layout_column_wrap, c(list(width = "240px", gap = "1rem"), cajas))
    )
  })

  output$lectura <- renderUI({
    req(input$ejecucion)
    ahorros <- dbGetQuery(con, "
      SELECT a.id_producto_comun, a.nombre_canonico, a.ahorro_pct, a.ahorro_cop,
             a.precio_min, a.precio_max, a.comercios_min
        FROM v_ahorro_presentacion a
        JOIN productos_comparables p ON p.id_producto_comun = a.id_producto_comun
       WHERE a.id_ejecucion = ? AND p.vigente = 1 AND a.n_comercios = 3
       ORDER BY a.ahorro_pct DESC", params = list(input$ejecucion))
    ejec <- dbGetQuery(con, "SELECT fecha_inicio, estado FROM ejecuciones WHERE id_ejecucion = ?",
                       params = list(input$ejecucion))
    if (nrow(ahorros) == 0) {
      return(p(class = "text-muted mb-0", "No hay presentaciones comparables con precios en los tres comercios."))
    }
    ganadores <- unlist(strsplit(ahorros$comercios_min, ", "))
    conteo <- sort(table(ganadores), decreasing = TRUE)
    mayor <- ahorros[1, ]
    tags$div(
      tags$p(class = "mb-2",
        "En la ejecución del ", substr(ejec$fecha_inicio[1], 1, 16),
        " se comparan ", nrow(ahorros), " presentaciones presentes en los tres comercios. ",
        "El comercio con el precio mínimo más veces es ", names(conteo)[1], " (", conteo[1],
        " de ", nrow(ahorros), ")."),
      tags$p(class = "mb-2",
        "La mayor diferencia es ", mayor$nombre_canonico, ": ",
        cop(mayor$precio_min), " frente a ", cop(mayor$precio_max), ", es decir ",
        format(mayor$ahorro_pct, decimal.mark = ","), " % (", cop(mayor$ahorro_cop), ")."),
      tags$p(class = "mb-0",
        "Comprar cada producto donde está más barato no equivale a comprar todo en un solo ",
        "comercio: la sección Canasta muestra las dos cuentas por separado.")
    )
  })

  # ---------------------------------------------------------------------------
  # Gráficos
  # ---------------------------------------------------------------------------

  output$grafico_evolucion <- renderHighchart({
    req(input$ejecucion, input$producto_evolucion)
    d <- serie_precio(con, input$producto_evolucion, input$comercios)
    validate(need(nrow(d) > 0, "No hay observaciones de esta presentación con los filtros actuales."))
    h <- highchart() |>
      hc_chart(type = "spline") |>
      hc_xAxis(type = "datetime") |>
      hc_yAxis(title = list(text = "Precio (COP)")) |>
      hc_tooltip(shared = TRUE, valuePrefix = "$ ") |>
      hc_legend(enabled = TRUE) |>
      hc_lang(thousandsSep = ".", decimalPoint = ",") |>
      hc_credits(enabled = FALSE) |>
      hc_exporting(enabled = FALSE)
    for (com in unique(d$comercio)) {
      sub <- d[d$comercio == com, , drop = FALSE]
      datos_serie <- lapply(seq_len(nrow(sub)), function(i) {
        list(x = as.numeric(as.POSIXct(sub$fecha_consulta[i], format = "%Y-%m-%dT%H:%M:%S",
                                       tz = "America/Bogota")) * 1000,
             y = sub$precio_cop[i])
      })
      h <- hc_add_series(h, name = com, data = datos_serie,
                         color = PALETA[[com]] %||% "#6B7280",
                         marker = list(enabled = TRUE, radius = 3))
    }
    h
  }) |> bindCache(input$ejecucion, input$producto_evolucion, input$comercios, version())

  output$grafico_unidad <- renderHighchart({
    req(input$ejecucion, input$producto_unidad)
    u <- precio_unidad(con, input$ejecucion, input$producto_unidad)
    validate(need(nrow(u) > 0, "No hay precios por unidad para esta presentación."))
    unidad <- u$unidad_normalizada[1]
    factor <- if (unidad %in% c("g", "mL")) 100 else 1
    etiqueta <- if (unidad %in% c("g", "mL")) paste0("COP / 100 ", unidad) else "COP / unidad"
    u$valor <- u$precio_por_unidad * factor
    u <- u[order(u$valor), , drop = FALSE]
    puntos <- lapply(seq_len(nrow(u)), function(i) {
      list(y = round(u$valor[i], 1), color = PALETA[[u$comercio[i]]] %||% "#6B7280")
    })
    highchart() |>
      hc_chart(type = "column") |>
      hc_xAxis(categories = u$comercio) |>
      hc_yAxis(title = list(text = etiqueta)) |>
      hc_plotOptions(column = list(dataLabels = list(enabled = TRUE,
                                                     format = "$ {point.y:,.1f}"))) |>
      hc_add_series(name = etiqueta, data = puntos) |>
      hc_legend(enabled = FALSE) |>
      hc_lang(thousandsSep = ".", decimalPoint = ",") |>
      hc_credits(enabled = FALSE) |>
      hc_tooltip(pointFormat = paste0("<b>", etiqueta, ":</b> $ {point.y:,.1f}<br/>"))
  }) |> bindCache(input$ejecucion, input$producto_unidad, version())

  output$grafico_distribucion <- renderHighchart({
    req(input$ejecucion)
    d <- distribucion_precios(con, input$ejecucion, filtros(), ancho = 5000)
    validate(need(nrow(d) > 0, "No hay precios para los filtros seleccionados."))
    categorias <- sort(unique(d$desde))
    etiquetas <- paste0(cop(categorias), "–", cop(categorias + 5000))
    h <- highchart() |>
      hc_chart(type = "column") |>
      hc_xAxis(categories = etiquetas, labels = list(rotation = -45, style = list(fontSize = "10px"))) |>
      hc_yAxis(title = list(text = "Número de anuncios")) |>
      hc_plotOptions(column = list(groupPadding = 0.1, pointPadding = 0.05)) |>
      hc_tooltip(shared = TRUE) |>
      hc_legend(enabled = TRUE) |>
      hc_lang(thousandsSep = ".", decimalPoint = ",") |>
      hc_credits(enabled = FALSE)
    for (com in unique(d$comercio)) {
      valores <- setNames(rep(0, length(categorias)), categorias)
      sub <- d[d$comercio == com, , drop = FALSE]
      valores[as.character(sub$desde)] <- sub$n
      h <- hc_add_series(h, name = com, data = unname(valores),
                         color = PALETA[[com]] %||% "#6B7280")
    }
    h
  }) |> bindCache(input$ejecucion, input$comercios, input$subcategoria, input$marca,
                   input$precio, input$solo_promo, input$solo_comparables, input$buscar,
                   version())

  output$grafico_ahorro <- renderHighchart({
    req(input$ejecucion)
    d <- dbGetQuery(con, "
      SELECT a.nombre_canonico, a.ahorro_pct, a.ahorro_cop, a.precio_min, a.precio_max,
             a.comercios_min
        FROM v_ahorro_presentacion a
        JOIN productos_comparables p ON p.id_producto_comun = a.id_producto_comun
       WHERE a.id_ejecucion = ? AND p.vigente = 1 AND a.n_comercios = 3
       ORDER BY a.ahorro_pct", params = list(input$ejecucion))
    validate(need(nrow(d) > 0, "No hay presentaciones con precios en los tres comercios."))
    d$grupo <- ifelse(grepl(",", d$comercios_min), "Empate", d$comercios_min)
    d$etiqueta <- ifelse(nchar(d$nombre_canonico) > 38,
                         paste0(substr(d$nombre_canonico, 1, 36), "…"),
                         d$nombre_canonico)
    categorias <- d$etiqueta
    h <- highchart() |>
      hc_chart(type = "bar") |>
      hc_xAxis(categories = categorias) |>
      hc_yAxis(title = list(text = "Ahorro (%)"), max = ceiling(max(d$ahorro_pct) / 5) * 5) |>
      hc_legend(enabled = TRUE) |>
      hc_lang(thousandsSep = ".", decimalPoint = ",") |>
      hc_credits(enabled = FALSE) |>
      hc_tooltip(pointFormat = "<b>{series.name}</b><br/>Ahorro: {point.y:.1f} %<br/>Mínimo: $ {point.min:,.0f}<br/>Máximo: $ {point.max:,.0f}")
    for (grupo in c("Carulla", "Jumbo", "Olímpica", "Empate")) {
      if (!grupo %in% d$grupo) next
      valores <- lapply(seq_len(nrow(d)), function(i) {
        if (d$grupo[i] != grupo) return(NULL)
        list(y = d$ahorro_pct[i], min = d$precio_min[i], max = d$precio_max[i])
      })
      h <- hc_add_series(h, name = grupo, data = valores,
                         color = if (grupo == "Empate") "#6B7280" else PALETA[[grupo]],
                         dataLabels = list(enabled = TRUE, format = "{point.y:.1f} %"))
    }
    h
  }) |> bindCache(input$ejecucion, version())

  # ---------------------------------------------------------------------------
  # Tablas
  # ---------------------------------------------------------------------------

  formatear_tabla <- function(d) {
    d$comercio <- htmltools::htmlEscape(d$comercio)
    d$producto <- htmltools::htmlEscape(d$producto)
    d$marca <- htmltools::htmlEscape(d$marca %||% "")
    d$presentacion <- ifelse(is.na(d$contenido_total), "—",
                             paste0(numero(d$contenido_total), " ", d$unidad_normalizada))
    d$promocion <- ifelse(d$es_promocion == 1, "Sí", "No")
    d$disponibilidad <- ifelse(d$estado_disponibilidad == "disponible", "Disponible", "Agotado")
    d$fecha <- substr(d$fecha_consulta, 1, 16)
    factor <- ifelse(d$unidad_normalizada %in% c("g", "mL"), 100, 1)
    d$unitario <- ifelse(
      is.na(d$contenido_total) | is.na(d$precio_cop) | d$contenido_total <= 0, "—",
      paste0("$ ", format(round(d$precio_cop / d$contenido_total * factor, 1),
                          big.mark = ".", decimal.mark = ","),
             ifelse(d$unidad_normalizada %in% c("g", "mL"),
                    paste0(" / 100 ", d$unidad_normalizada), " / unidad")))
    d$enlace <- ifelse(is.na(d$url_producto) | !nzchar(d$url_producto), "",
                       sprintf('<a href="%s" target="_blank" rel="noopener">Ver</a>',
                               htmltools::htmlEscape(d$url_producto)))
    d
  }

  output$tabla <- renderDT({
    d <- datos()
    validate(need(nrow(d) > 0, "No hay productos con los filtros seleccionados. Ajuste el panel lateral."))
    d <- formatear_tabla(d)
    dt <- datatable(
      d[, c("comercio", "producto", "marca", "presentacion", "precio_cop", "unitario",
            "promocion", "disponibilidad", "fecha", "enlace")],
      colnames = c("Comercio", "Producto", "Marca", "Presentación", "Precio (COP)",
                   "Precio unitario", "Promoción", "Disponibilidad", "Consulta", "Anuncio"),
      rownames = FALSE, escape = FALSE, filter = "top",
      options = list(pageLength = 12, scrollX = TRUE, autoWidth = TRUE,
                     order = list(list(4, "asc")),
                     language = list(
                       search = "Buscar:", lengthMenu = "Mostrar _MENU_ registros",
                       info = "Mostrando _START_ a _END_ de _TOTAL_",
                       infoEmpty = "Sin registros", zeroRecords = "No hay productos con esos filtros",
                       paginate = list(first = "Primero", last = "Último",
                                       `next` = "Siguiente", previous = "Anterior")))
    )
    DT::formatCurrency(dt, columns = "precio_cop", currency = "$ ", interval = 3,
                       mark = ".", dec.mark = ",")
  })

  output$tabla_unidad <- renderDT({
    req(input$ejecucion)
    u <- precio_unidad(con, input$ejecucion)
    validate(need(nrow(u) > 0, "No hay presentaciones comparables con contenido normalizado."))
    u$precio_100 <- round(ifelse(u$unidad_normalizada %in% c("g", "mL"),
                                 u$precio_por_unidad * 100, u$precio_por_unidad), 1)
    u$unidad <- ifelse(u$unidad_normalizada %in% c("g", "mL"),
                       paste0("COP / 100 ", u$unidad_normalizada), "COP / unidad")
    u <- u[order(u$id_producto_comun, u$precio_100), c("nombre_canonico", "comercio", "contenido_total",
                                                       "unidad_normalizada", "precio_cop", "precio_100", "unidad")]
    dt <- datatable(u, colnames = c("Producto", "Comercio", "Contenido", "Unidad", "Precio (COP)",
                                    "Por unidad", "Unidad del indicador"),
                    rownames = FALSE, filter = "top",
                    options = list(pageLength = 8, scrollX = TRUE, dom = "ftip"))
    DT::formatCurrency(dt, columns = c("precio_cop", "precio_100"), currency = "$ ",
                       interval = 3, mark = ".", dec.mark = ",")
  })

  output$descargar <- downloadHandler(
    filename = function() paste0("productos_", input$ejecucion, ".csv"),
    content = function(file) {
      utils::write.csv(datos(), file, row.names = FALSE, fileEncoding = "UTF-8")
    }
  )

  # ---------------------------------------------------------------------------
  # Cambios de precio
  # ---------------------------------------------------------------------------

  cambios <- reactive({
    req(input$cambio_a, input$cambio_b)
    validate(need(input$cambio_a != input$cambio_b, "Seleccione dos ejecuciones distintas."))
    cambios_entre(con, input$cambio_a, input$cambio_b,
                  umbral = input$umbral, solo_comparables = isTRUE(input$cambios_comparables))
  }) |> bindCache(input$cambio_a, input$cambio_b, input$umbral, input$cambios_comparables, version())

  output$aviso_cambios <- renderUI({
    req(input$cambio_a, input$cambio_b)
    a <- dbGetQuery(con, "SELECT GROUP_CONCAT(DISTINCT id_comercio) AS x FROM observaciones WHERE id_ejecucion = ?",
                    params = list(input$cambio_a))$x[1]
    b <- dbGetQuery(con, "SELECT GROUP_CONCAT(DISTINCT id_comercio) AS x FROM observaciones WHERE id_ejecucion = ?",
                    params = list(input$cambio_b))$x[1]
    if (!identical(a, b)) {
      div(class = "alert alert-warning mb-0",
          "Las ejecuciones comparadas no tienen los mismos comercios. ",
          "Los productos de un comercio nuevo aparecerán como nuevos y los de un comercio ",
          "retirado, como no observados.")
    }
  })

  output$resumen_cambios <- renderUI({
    d <- cambios()
    subieron <- sum(d$tipo == "Subió", na.rm = TRUE)
    bajaron <- sum(d$tipo == "Bajó", na.rm = TRUE)
    nuevos <- sum(d$tipo == "Nuevo", na.rm = TRUE)
    retirados <- sum(d$tipo == "Dejó de observarse", na.rm = TRUE)
    layout_column_wrap(width = "220px",
      value_box("Subieron", numero(subieron), "con el umbral elegido", theme = "danger"),
      value_box("Bajaron", numero(bajaron), "con el umbral elegido", theme = "success"),
      value_box("Nuevos", numero(nuevos), "anuncios que no estaban antes", theme = "light"),
      value_box("No observados", numero(retirados), "anuncios que dejaron de aparecer", theme = "light")
    )
  })

  output$grafico_cambios <- renderHighchart({
    d <- cambios()
    validate(need(any(d$tipo %in% c("Subió", "Bajó")),
                  "No hay variaciones que superen el umbral en este par de ejecuciones."))
    d <- d[d$tipo %in% c("Subió", "Bajó"), , drop = FALSE]
    d <- d[order(-abs(d$cambio_pct)), , drop = FALSE]
    d <- head(d, 18)
    d$etiqueta <- paste0(d$nombre_canonico, " · ", d$comercio)
    puntos <- lapply(seq_len(nrow(d)), function(i) {
      list(y = d$cambio_pct[i], anterior = d$precio_anterior[i], actual = d$precio_actual[i],
           color = if (d$cambio_cop[i] > 0) "#B3122E" else "#0F8A4B")
    })
    highchart() |>
      hc_chart(type = "bar") |>
      hc_xAxis(categories = d$etiqueta) |>
      hc_yAxis(title = list(text = "Variación (%)"), plotLines = list(list(value = 0, width = 1, color = "#9CA3AF"))) |>
      hc_add_series(name = "Variación", data = puntos,
                    dataLabels = list(enabled = TRUE, format = "{point.y:.1f} %")) |>
      hc_legend(enabled = FALSE) |>
      hc_lang(thousandsSep = ".", decimalPoint = ",") |>
      hc_credits(enabled = FALSE) |>
      hc_tooltip(pointFormat = "<b>{point.y:.1f} %</b><br/>Anterior: $ {point.anterior:,.0f}<br/>Actual: $ {point.actual:,.0f}")
  })

  output$tabla_cambios <- renderDT({
    d <- cambios()
    validate(need(nrow(d) > 0, "No hay cambios con el umbral seleccionado."))
    d$producto <- htmltools::htmlEscape(d$nombre_canonico)
    d$comercio <- htmltools::htmlEscape(d$comercio)
    dt <- datatable(
      d[, c("tipo", "comercio", "producto", "precio_anterior", "precio_actual", "cambio_cop", "cambio_pct")],
      colnames = c("Tipo", "Comercio", "Producto", "Antes", "Ahora", "Cambio COP", "Cambio %"),
      rownames = FALSE, filter = "top",
      options = list(pageLength = 8, scrollX = TRUE, dom = "ftip",
                     language = list(zeroRecords = "Sin cambios", search = "Buscar:",
                                     info = "Mostrando _START_ a _END_ de _TOTAL_",
                                     paginate = list(`next` = "Siguiente", previous = "Anterior")))
    )
    DT::formatCurrency(dt, columns = c("precio_anterior", "precio_actual", "cambio_cop"),
                       currency = "$ ", interval = 3, mark = ".", dec.mark = ",")
  })

  # ---------------------------------------------------------------------------
  # Canasta
  # ---------------------------------------------------------------------------

  output$canasta_cantidades <- renderUI({
    req(input$canasta_productos)
    comparables <- productos_comparables(con)
    comparables <- comparables[comparables$id_producto_comun %in% input$canasta_productos, , drop = FALSE]
    cajas <- lapply(seq_len(nrow(comparables)), function(i) {
      id <- comparables$id_producto_comun[i]
      numericInput(paste0("cant_", id), comparables$nombre_canonico[i], value = 1,
                   min = 1, max = 50, step = 1)
    })
    do.call(layout_column_wrap, c(list(width = "260px"), cajas))
  })

  canasta_res <- reactive({
    req(input$ejecucion, input$canasta_productos)
    precios <- precios_canasta(con, input$ejecucion, input$canasta_productos)
    cantidades <- vapply(input$canasta_productos, function(id) {
      valor <- input[[paste0("cant_", id)]]
      if (is.null(valor) || is.na(valor) || valor < 1) 1 else min(as.numeric(valor), 50)
    }, numeric(1))
    names(cantidades) <- input$canasta_productos
    calcular_canasta(precios, cantidades)
  })

  output$canasta_totales <- renderUI({
    res <- canasta_res()
    validate(need(nrow(res$por_comercio) > 0, "Seleccione al menos un producto."))
    cajas <- lapply(seq_len(nrow(res$por_comercio)), function(i) {
      fila <- res$por_comercio[i, ]
      if (fila$completo) {
        value_box(fila$comercio, cop(fila$costo), "canasta completa", theme = "light")
      } else {
        value_box(fila$comercio, "No disponible",
                  paste0("Faltan: ", fila$faltantes), theme = "warning")
      }
    })
    cajas[[length(cajas) + 1]] <- value_box(
      "Compra óptima", if (is.na(res$optimo)) "—" else cop(res$optimo),
      "cada producto donde está más barato", theme = "primary")
    do.call(layout_column_wrap, c(list(width = "230px", gap = "1rem"), cajas))
  })

  output$grafico_canasta <- renderHighchart({
    res <- canasta_res()
    validate(need(nrow(res$por_comercio) > 0, "Seleccione al menos un producto."))
    d <- res$por_comercio
    puntos <- lapply(seq_len(nrow(d)), function(i) {
      list(y = if (is.na(d$costo[i])) 0 else d$costo[i],
           color = if (is.na(d$costo[i])) "#D1D5DB" else PALETA[[d$comercio[i]]] %||% "#6B7280")
    })
    highchart() |>
      hc_chart(type = "column") |>
      hc_xAxis(categories = d$comercio) |>
      hc_yAxis(title = list(text = "Costo (COP)")) |>
      hc_add_series(name = "Costo", data = puntos,
                    dataLabels = list(enabled = TRUE, format = "$ {point.y:,.0f}")) |>
      hc_legend(enabled = FALSE) |>
      hc_lang(thousandsSep = ".", decimalPoint = ",") |>
      hc_credits(enabled = FALSE) |>
      hc_tooltip(pointFormat = "<b>{point.category}</b><br/>$ {point.y:,.0f}")
  })

  output$canasta_nota <- renderUI({
    res <- canasta_res()
    completo <- sum(res$por_comercio$completo, na.rm = TRUE)
    tags$div(
      p(class = "mb-2", "Se comparan ", length(input$canasta_productos), " productos. ",
        completo, " de ", nrow(res$por_comercio), " comercios tienen todos los precios."),
      if (!is.na(res$ahorro) && res$ahorro > 0) {
        p(class = "mb-2", "Comprar cada producto donde está más barato ahorra ",
          cop(res$ahorro), " frente a la mejor canasta de un solo comercio.")
      } else {
        p(class = "mb-2", "No hay ahorro calculable con los productos seleccionados.")
      },
      p(class = "small text-muted mb-0",
        "El resultado no incluye envío, mínimos de compra, cupones ni condiciones de las promociones.")
    )
  })

  # ---------------------------------------------------------------------------
  # Actualización
  # ---------------------------------------------------------------------------

  tarea_online <- ExtendedTask$new(function(id) {
    future_promise({
      tryCatch({
        source("scraper.R")
        list(ok = TRUE, res = ejecutar_recoleccion(offline = FALSE, id_ejecucion = id, verboso = FALSE))
      }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    }, seed = TRUE)
  })

  tarea_offline <- ExtendedTask$new(function(id, origen) {
    future_promise({
      tryCatch({
        source("scraper.R")
        list(ok = TRUE, res = ejecutar_recoleccion(offline = TRUE, id_ejecucion = id,
                                                   id_origen = origen, verboso = FALSE))
      }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    }, seed = TRUE)
  })

  output$boton_actualizar <- renderUI({
    ocupado <- identical(tarea_online$status(), "running")
    actionButton("actualizar", if (ocupado) "Actualizando..." else "Actualizar precios (en línea)",
                 icon = icon("cloud-arrow-down"), class = "btn-primary",
                 disabled = if (ocupado) "disabled" else NULL)
  })

  output$boton_reprocesar <- renderUI({
    ocupado <- identical(tarea_offline$status(), "running")
    actionButton("reprocesar", if (ocupado) "Reprocesando..." else "Reprocesar copias locales",
                 icon = icon("hard-drive"), class = "btn-outline-secondary",
                 disabled = if (ocupado) "disabled" else NULL)
  })

  observeEvent(input$actualizar, {
    if (identical(tarea_online$status(), "running")) return()
    id <- paste0("EJEC_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    id_actual(id)
    tarea_online$invoke(id)
  })

  observeEvent(input$reprocesar, {
    if (identical(tarea_offline$status(), "running")) return()
    origen <- input$ejecucion
    req(origen)
    id <- paste0("EJEC_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_OFF")
    id_actual(id)
    tarea_offline$invoke(id, origen)
  })

  progreso <- reactivePoll(
    1200, session,
    checkFunc = function() {
      id <- id_actual()
      if (is.null(id)) return("")
      p <- tryCatch(progreso_ejecucion(con, id), error = function(e) NULL)
      handle <- tryCatch(tarea_online$status(), error = function(e) "")
      paste(id, nrow(p), if (is.null(p)) "" else paste(p$estado, collapse = ","), handle)
    },
    valueFunc = function() {
      id <- id_actual()
      if (is.null(id)) return(NULL)
      tryCatch(progreso_ejecucion(con, id), error = function(e) NULL)
    }
  )

  output$progreso <- renderTable({
    p <- progreso()
    if (is.null(p) || nrow(p) == 0) {
      return(data.frame(Estado = "Sin actualización en curso"))
    }
    data.frame(Comercio = p$comercio, Estado = p$estado,
               Extraídos = p$n_extraido, Incluidos = p$n_incluido,
               `Con precio` = p$n_con_precio, Mensaje = p$mensaje,
               check.names = FALSE)
  })

  output$estado_tarea <- renderUI({
    estado <- tryCatch(tarea_online$status(), error = function(e) "idle")
    estado_off <- tryCatch(tarea_offline$status(), error = function(e) "idle")
    if (estado == "running" || estado_off == "running") {
      div(class = "alert alert-info mt-3 mb-0", "Actualización en curso. La aplicación sigue disponible.")
    } else if (estado == "error" || estado_off == "error") {
      div(class = "alert alert-danger mt-3 mb-0",
          "La actualización falló. Revise la conexión y el detalle en el avance por comercio.")
    } else if (estado == "success" || estado_off == "success") {
      div(class = "alert alert-success mt-3 mb-0", "Última actualización terminada.")
    } else {
      NULL
    }
  })

  observar_resultado <- function(tarea) {
    observeEvent(tarea$status(), {
      if (tarea$status() != "success") return()
      res <- tarea$result()
      if (!isTRUE(res$ok)) {
        showNotification(paste("Error en la actualización:", res$error), type = "error", duration = 15)
        return()
      }
      seleccion_pendiente(res$res$id_ejecucion)
      version(version() + 1L)
      showNotification(paste("Ejecución", res$res$id_ejecucion, "terminada:", res$res$estado),
                       type = if (res$res$estado == "completa") "message" else "warning",
                       duration = 10)
    }, ignoreInit = TRUE)
  }
  observar_resultado(tarea_online)
  observar_resultado(tarea_offline)

  output$resumen_actualizacion <- renderUI({
    version()
    id <- id_actual()
    if (is.null(id)) {
      return(p(class = "text-muted mb-0", "Aún no se ha ejecutado una actualización en esta sesión."))
    }
    r <- tryCatch(resumen_actualizacion(con, id), error = function(e) NULL)
    if (is.null(r) || nrow(r) == 0) {
      return(p(class = "text-muted mb-0", "Sin datos para esta ejecución."))
    }
    tabla <- r
    names(tabla) <- c("Comercio", "Recolectados", "Nuevos", "Cambios de precio",
                      "No observados", "Estado")
    tagList(
      p(class = "mb-2", "Ejecución ", tags$code(id), ": ",
        sum(tabla$Recolectados), " observaciones en ", nrow(tabla), " comercios."),
      tableOutput("tabla_resumen_actualizacion")
    )
  })

  output$tabla_resumen_actualizacion <- renderTable({
    version()
    id <- id_actual()
    req(id)
    r <- resumen_actualizacion(con, id)
    names(r) <- c("Comercio", "Recolectados", "Nuevos", "Cambios de precio",
                  "No observados", "Estado")
    r
  })

  output$tabla_ejecuciones <- renderTable({
    ejs <- ejecuciones()
    data.frame(Fecha = substr(ejs$fecha_inicio, 1, 16), Modo = ejs$modo,
               Estado = ejs$estado, Registros = ejs$n_registros,
               Comparables = ejs$n_obs_comparables, Comercios = ejs$comercios,
               check.names = FALSE)
  })
}

shinyApp(ui, server)
