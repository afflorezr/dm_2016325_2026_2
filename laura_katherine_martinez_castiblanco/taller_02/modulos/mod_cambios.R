# Pestaña 4 · Cambios de precio entre dos ejecuciones (mismo anuncio, mismo comercio)
cambios_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(col_widths = c(3, 3, 3, 3),
      selectInput(ns("a"), "Ejecución anterior", choices = NULL),
      selectInput(ns("b"), "Ejecución nueva", choices = NULL),
      sliderInput(ns("umbral"), "Umbral de variación grande (±%)", min = 1, max = 50, value = 10, step = 1),
      checkboxInput(ns("solo_grandes"), "Mostrar solo variaciones grandes", FALSE)),
    uiOutput(ns("aviso")),
    layout_column_wrap(width = "190px", fill = FALSE,
      kpi("Suben", ns("k_sube"), "arrow-trend-up", ns("p_sube"), tema = "danger"),
      kpi("Bajan", ns("k_baja"), "arrow-trend-down", ns("p_baja"), tema = "success"),
      kpi("Productos nuevos", ns("k_nuevo"), "plus", ns("p_nuevo")),
      kpi("Dejaron de observarse", ns("k_no"), "eye-slash", ns("p_no"))),
    layout_columns(col_widths = c(5, 7),
      tarjeta("Mayores variaciones (%)", highchartOutput(ns("g_top"), height = "420px")),
      tarjeta("Detalle por anuncio", DTOutput(ns("t_cambios"))))
  )
}

cambios_server <- function(id, filtros, catalogos, version) {
  moduleServer(id, function(input, output, session) {
    observeEvent(catalogos(), {
      co <- catalogos()$corridas
      ch <- setNames(co$id_corrida, paste0(fmt_fecha(co$fecha_hora), " · ", co$id_corrida, " (", fmt_num(co$n_obs), " obs · ", co$estado, ")"))
      updateSelectInput(session, "b", choices = ch, selected = ch[1])
      updateSelectInput(session, "a", choices = ch, selected = if (length(ch) >= 2) ch[2] else ch[1])
    })
    ok <- reactive(isTruthy(input$a) && isTruthy(input$b) && input$a != input$b)
    datos <- reactive({
      req(ok()); d <- db_cambios_entre(input$a, input$b, input$umbral)
      cm <- filtros()$comercios; if (length(cm)) d <- d[d$comercio %in% cm, , drop = FALSE]
      d
    }) |> bindCache(input$a, input$b, input$umbral, filtros()$comercios, version())

    output$aviso <- renderUI(if (!ok()) aviso("Elija dos ejecuciones distintas para comparar (se necesitan al menos dos en la base).", "warning")
      else aviso(paste0("Comparación de ", input$a, " → ", input$b, ". «Dejó de observarse» no significa agotado ni retirado: solo que no apareció en la nueva ejecución."), "secondary"))
    cuenta <- function(e) { d <- datos(); sum(d$estado == e) }
    pct <- function(e) { d <- datos(); if (!nrow(d)) "" else paste0(fmt_pct(100 * sum(d$estado == e) / nrow(d)), " de los anuncios") }
    output$k_sube <- renderText(fmt_num(cuenta("sube")));       output$p_sube <- renderText(pct("sube"))
    output$k_baja <- renderText(fmt_num(cuenta("baja")));       output$p_baja <- renderText(pct("baja"))
    output$k_nuevo <- renderText(fmt_num(cuenta("nuevo")));     output$p_nuevo <- renderText(pct("nuevo"))
    output$k_no <- renderText(fmt_num(cuenta("no_observado"))); output$p_no <- renderText(pct("no_observado"))

    output$g_top <- renderHighchart({
      d <- datos(); d <- d[d$estado %in% c("sube", "baja") & !is.na(d$delta_pct), , drop = FALSE]; vacio(d, "No hay cambios de precio entre estas ejecuciones.")
      d <- head(d[order(-abs(d$delta_pct)), ], 15)
      highchart() |> hc_chart(type = "bar") |> hc_xAxis(categories = substr(d$producto_raw, 1, 38)) |>
        hc_add_series(name = "Variación %", showInLegend = FALSE,
                      data = lapply(seq_len(nrow(d)), function(i) list(y = d$delta_pct[i], color = if (d$delta_pct[i] > 0) "#D64545" else "#1F9D55",
                                                                     cop = d$delta_cop[i], com = d$comercio[i]))) |>
        hc_tooltip(pointFormat = "<b>{point.y} %</b> ({point.cop} COP) · {point.com}") |> hc_base("Variación (%)")
    })
    output$t_cambios <- renderDT({
      d <- datos(); vacio(d)
      if (isTRUE(input$solo_grandes)) d <- d[d$variacion_grande, , drop = FALSE]
      vacio(d, "Ningún anuncio supera el umbral elegido.")
      lab <- c(sube = "Sube", baja = "Baja", igual = "Igual", nuevo = "Nuevo", no_observado = "No observado")
      t <- data.frame(Comercio = d$comercio, Producto = d$producto_raw, `Precio anterior` = d$precio_anterior, `Precio nuevo` = d$precio_nuevo,
                      `Cambio (COP)` = d$delta_cop, `Variación (%)` = d$delta_pct, Estado = unname(lab[d$estado]),
                      `Variación grande` = ifelse(d$variacion_grande, "Sí", "No"), check.names = FALSE)
      datatable(t, rownames = FALSE, class = "compact stripe", options = list(pageLength = 10, language = DT_ES)) |>
        formatCurrency(c("Precio anterior", "Precio nuevo", "Cambio (COP)"), currency = "$ ", digits = 0, mark = ".", dec.mark = ",") |>
        formatStyle(names(t), valueColumns = "Variación grande", backgroundColor = styleEqual("Sí", "rgba(228,87,46,.16)"),
                    fontWeight = styleEqual("Sí", "600"))
    })
  })
}
