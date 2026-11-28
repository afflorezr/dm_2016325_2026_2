# Pestaña 2 · Comparador de productos equivalentes: precio, precio por unidad (sin mezclar unidades) y ahorro
comparador_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("aviso")),
    layout_columns(col_widths = c(12),
      tarjeta("¿Dónde es más barato cada producto? (productos comparables de la ejecución elegida)",
              div(style = "max-height: 620px; overflow-y: auto;", highchartOutput(ns("g_precios"), height = "1050px")),
              ayuda = "Solo productos que existen en los tres comercios del trío comparable (misma marca, variante y contenido).")),
    layout_columns(col_widths = c(6, 6),
      tarjeta("Precio por unidad de contenido entre comercios",
              selectInput(ns("unidad"), "Unidad de comparación (no se mezclan unidades)", choices = "mL", width = "260px"),
              highchartOutput(ns("g_unitario"), height = "340px"),
              ayuda = "Mediana del precio por litro (COP/L) por subcategoría y comercio, calculada en SQL sobre la selección actual."),
      tarjeta("Pregunta del consumidor: ¿cuánto me ahorro por elegir el comercio correcto?",
              highchartOutput(ns("g_ahorro"), height = "380px"),
              ayuda = "Ahorro % = (precio máximo − precio mínimo) / precio máximo, por producto comparable.")),
    tarjeta("Mejor precio por producto (con empates)", DTOutput(ns("t_mejor")))
  )
}

comparador_server <- function(id, filtros, catalogos, version, corrida) {
  moduleServer(id, function(input, output, session) {
    comp <- reactive(db_comparables_corrida(corrida(), filtros()$comercios)) |> bindCache(corrida(), filtros()$comercios, version())
    uni  <- reactive(db_mediana_unitario(filtros(), por_comercio = TRUE)) |> bindCache(filtros(), version())
    aho  <- reactive(db_ahorro_por_producto(corrida(), filtros()$comercios)) |> bindCache(corrida(), filtros()$comercios, version())

    output$aviso <- renderUI(aviso(paste0("Precios de la ejecución ", corrida(), " (",
                                          fmt_fecha(catalogos()$corridas$fecha_hora[catalogos()$corridas$id_corrida == corrida()]),
                                          "). Moneda: COP. Para cambiar de ejecución use el filtro del panel lateral."), "secondary"))
    observeEvent(uni(), {
      u <- unique(uni()$unidad_base); if (!length(u)) u <- "mL"
      updateSelectInput(session, "unidad", choices = u, selected = if (isTruthy(input$unidad) && input$unidad %in% u) input$unidad else u[1])
    })

    output$g_precios <- renderHighchart({
      d <- comp(); vacio(d, "No hay productos comparables para esta ejecución y estos comercios.")
      prods <- unique(d$etiqueta); cms <- sort(unique(d$comercio))
      hc <- highchart() |> hc_chart(type = "bar") |> hc_xAxis(categories = prods)
      for (cm in cms) {
        y <- vapply(prods, function(p) { v <- d$precio_cop[d$etiqueta == p & d$comercio == cm]; if (length(v)) v[1] else NA_real_ }, numeric(1))
        hc <- hc |> hc_add_series(name = cm, data = unname(y), color = color_de(cm))
      }
      hc |> hc_tooltip(shared = TRUE, valueDecimals = 0, valuePrefix = "$ ") |> hc_base("Precio (COP)")
    })
    output$g_unitario <- renderHighchart({
      d <- uni(); vacio(d); d <- d[d$unidad_base == input$unidad, , drop = FALSE]; vacio(d)
      subs <- sort(unique(d$subcategoria)); cms <- sort(unique(d$comercio))
      hc <- highchart() |> hc_chart(type = "column") |> hc_xAxis(categories = subs)
      for (cm in cms) {
        y <- vapply(subs, function(s) { v <- d$mediana_cop_l[d$subcategoria == s & d$comercio == cm]; if (length(v)) v[1] else NA_real_ }, numeric(1))
        hc <- hc |> hc_add_series(name = cm, data = unname(y), color = color_de(cm))
      }
      hc |> hc_tooltip(shared = TRUE, valueDecimals = 0, valuePrefix = "$ ", valueSuffix = " /L") |> hc_base(paste0("COP por litro (", input$unidad, ")"))
    })
    output$g_ahorro <- renderHighchart({
      d <- aho(); vacio(d); d <- head(d[d$n_comercios >= 2, , drop = FALSE], 15); vacio(d, "Se necesitan al menos 2 comercios por producto.")
      highchart() |> hc_chart(type = "bar") |> hc_xAxis(categories = d$etiqueta) |>
        hc_add_series(name = "Ahorro %", color = "#0E8F6B", showInLegend = FALSE,
                      data = lapply(seq_len(nrow(d)), function(i) list(y = d$ahorro_pct[i], min = d$minimo[i], max = d$maximo[i]))) |>
        hc_tooltip(pointFormat = "Ahorro: <b>{point.y} %</b><br/>Mínimo: ${point.min} · Máximo: ${point.max}") |>
        hc_base("Ahorro máximo (%)")
    })
    output$t_mejor <- renderDT({
      d <- comp(); vacio(d, "No hay productos comparables para mostrar.")
      a <- calcular_ahorro(d[, c("clave_producto", "comercio", "precio_cop")])
      a$producto <- d$etiqueta[match(a$clave_producto, d$clave_producto)]
      t <- data.frame(Producto = a$producto, `Mínimo (COP)` = a$precio_minimo, `Máximo (COP)` = a$precio_maximo,
                      `Ahorro (COP)` = a$ahorro_cop, `Ahorro (%)` = a$ahorro_pct,
                      `Comercio(s) más barato(s)` = a$comercios_minimo, Empate = ifelse(a$hay_empate, "Sí", "No"), check.names = FALSE)
      datatable(t, rownames = FALSE, class = "compact stripe", options = list(pageLength = 10, language = DT_ES)) |>
        formatCurrency(c("Mínimo (COP)", "Máximo (COP)", "Ahorro (COP)"), currency = "$ ", digits = 0, mark = ".", dec.mark = ",") |>
        formatRound("Ahorro (%)", 1, dec.mark = ",")
    })
  })
}
