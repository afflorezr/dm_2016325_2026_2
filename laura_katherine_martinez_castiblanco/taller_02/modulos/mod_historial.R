# Pestaña 3 · Evolución del precio de un producto comparable (una serie por comercio)
historial_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("aviso")),
    layout_columns(col_widths = c(4, 8),
      tarjeta("Producto", selectInput(ns("producto"), "Producto comparable", choices = NULL, width = "100%"),
              uiOutput(ns("leyenda")), uiOutput(ns("resumen_serie"))),
      tarjeta("Evolución del precio (COP)", highchartOutput(ns("g_serie"), height = "380px"),
              ayuda = "Cada punto es una ejecución del scraper. Se conectan las ejecuciones del mismo anuncio comparable.")),
    tarjeta("Detalle de la serie", DTOutput(ns("t_serie")))
  )
}

historial_server <- function(id, filtros, catalogos, version) {
  moduleServer(id, function(input, output, session) {
    prods <- reactive(db_productos_comparables()) |> bindCache(version())
    observeEvent(prods(), {
      p <- prods(); ch <- setNames(p$clave_producto, p$etiqueta)
      updateSelectInput(session, "producto", choices = ch, selected = if (isTruthy(input$producto) && input$producto %in% ch) input$producto else ch[1])
    })
    serie <- reactive({
      clave <- validar_texto(input$producto, 120); req(nzchar(clave))
      db_serie_producto(input$producto, filtros()$comercios)
    }) |> bindCache(input$producto, filtros()$comercios, version())

    output$aviso <- renderUI({
      n <- nrow(catalogos()$corridas)
      if (n < 2) aviso("Solo hay una ejecución en la base: la evolución necesita al menos dos fechas distintas. Use la pestaña «Actualizar».", "warning")
      else aviso(sprintf("%d ejecuciones disponibles: %s.", n, paste(fmt_fecha(rev(catalogos()$corridas$fecha_hora)), collapse = " · ")), "secondary")
    })
    output$leyenda <- renderUI(div(class = "leyenda-comercios", lapply(names(COLOR_COMERCIO), function(cm)
      span(class = "chip", tags$i(style = paste0("background:", COLOR_COMERCIO[[cm]])), cm))))
    output$resumen_serie <- renderUI({
      d <- serie(); if (!nrow(d)) return(NULL)
      tags$ul(class = "small mb-0", lapply(sort(unique(d$comercio)), function(cm) {
        x <- d[d$comercio == cm, ]; x <- x[order(x$fecha_hora_consulta), ]
        v <- if (nrow(x) > 1) fmt_pct(100 * (x$precio_cop[nrow(x)] - x$precio_cop[1]) / x$precio_cop[1]) else "—"
        tags$li(tags$b(cm), ": ", fmt_cop(x$precio_cop[nrow(x)]), " (variación total ", v, ")")
      }))
    })
    output$g_serie <- renderHighchart({
      d <- serie(); vacio(d, "No hay observaciones de este producto con los comercios elegidos.")
      hc <- highchart() |> hc_chart(type = "line") |> hc_xAxis(type = "datetime")
      for (cm in sort(unique(d$comercio))) {
        x <- d[d$comercio == cm, ]; x <- x[order(x$fecha_hora_consulta), ]
        hc <- hc |> hc_add_series(name = cm, color = color_de(cm), marker = list(enabled = TRUE, radius = 5),
                                  data = lapply(seq_len(nrow(x)), function(i) list(x = iso_a_ms(x$fecha_hora_consulta[i]), y = x$precio_cop[i])))
      }
      hc |> hc_tooltip(shared = TRUE, xDateFormat = "%d-%m-%Y %H:%M", valueDecimals = 0, valuePrefix = "$ ") |> hc_base("Precio (COP)")
    })
    output$t_serie <- renderDT({
      d <- serie(); vacio(d)
      t <- data.frame(Comercio = d$comercio, Fecha = fmt_fecha(d$fecha_hora_consulta), `Precio (COP)` = d$precio_cop,
                      Promoción = ifelse(d$es_promocion == 1, "Sí", "No"), Ejecución = d$id_corrida, check.names = FALSE)
      datatable(t, rownames = FALSE, class = "compact stripe", options = list(pageLength = 8, language = DT_ES)) |>
        formatCurrency("Precio (COP)", currency = "$ ", digits = 0, mark = ".", dec.mark = ",")
    })
  })
}
