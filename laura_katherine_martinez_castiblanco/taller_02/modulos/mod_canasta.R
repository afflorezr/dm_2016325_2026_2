# Pestaña 5 · Canasta: compra en un solo comercio vs. compra dividida (precios de UNA misma ejecución)
canasta_ui <- function(id) {
  ns <- NS(id)
  layout_columns(col_widths = c(4, 8),
                 tarjeta("Arme su canasta",
                         selectInput(ns("corrida"), "Ejecución de los precios", choices = NULL, width = "100%"),
                         selectizeInput(ns("productos"), "Productos comparables", choices = NULL, multiple = TRUE, width = "100%",
                                        options = list(placeholder = "Escriba para buscar y elegir productos…", plugins = list("remove_button"))),
                         uiOutput(ns("cantidades")),
                         actionButton(ns("limpiar"), "Vaciar canasta", icon = icon("trash"), class = "btn-sm btn-outline-secondary")),
                 div(
                   uiOutput(ns("aviso")),
                   layout_column_wrap(width = "200px", fill = FALSE,
                                      kpi("Mejor comercio único", ns("k1"), "store", ns("p1")),
                                      kpi("Compra dividida", ns("k2"), "shuffle", ns("p2")),
                                      kpi("Ahorro de dividir", ns("k3"), "piggy-bank", ns("p3"), tema = "success")),
                   layout_columns(col_widths = c(6, 6),
                                  tarjeta("Costo de la canasta por comercio", highchartOutput(ns("g_total"), height = "300px")),
                                  tarjeta("Totales", DTOutput(ns("t_total")))),
                   tarjeta("Dónde comprar cada producto (compra dividida)", DTOutput(ns("t_detalle")))))
}

canasta_server <- function(id, filtros, catalogos, version, corrida) {
  moduleServer(id, function(input, output, session) {
    # Selector propio: solo ejecuciones que tienen productos comparables
    observe({
      cc <- catalogos()$corridas_comp; req(nrow(cc) > 0)
      ch <- setNames(cc$id_corrida, sprintf("%s · %s (%d comparables · %s)", fmt_fecha(cc$fecha_hora), cc$id_corrida, cc$n_comparables, cc$estado))
      sel <- isolate(input$corrida)
      updateSelectInput(session, "corrida", choices = ch,
                        selected = if (isTruthy(sel) && sel %in% ch) sel else if (corrida() %in% ch) corrida() else ch[1])
    })
    corr <- reactive({ req(input$corrida); input$corrida })
    
    comp <- reactive(db_comparables_corrida(corr(), filtros()$comercios)) |> bindCache(corr(), filtros()$comercios, version())
    cat_prod <- reactive({ d <- comp(); d <- d[!duplicated(d$clave_producto), c("clave_producto", "etiqueta")]; d[order(d$etiqueta), ] })
    observeEvent(cat_prod(), {
      p <- cat_prod(); updateSelectizeInput(session, "productos", choices = setNames(p$clave_producto, p$etiqueta),
                                            selected = intersect(input$productos, p$clave_producto), server = FALSE)
    })
    observeEvent(input$limpiar, updateSelectizeInput(session, "productos", selected = character(0)))
    
    id_cant <- function(k) paste0("cant_", match(k, cat_prod()$clave_producto))
    output$cantidades <- renderUI({
      sel <- input$productos; if (!length(sel)) return(NULL)
      p <- cat_prod()
      lapply(sel, function(k) numericInput(session$ns(id_cant(k)), p$etiqueta[match(k, p$clave_producto)],
                                           value = isolate(input[[id_cant(k)]]) %||% 1, min = 1, max = 99, step = 1, width = "100%"))
    })
    seleccion <- reactive({
      sel <- input$productos; req(length(sel) > 0)
      data.frame(clave_producto = sel, cantidad = vapply(sel, function(k) as.numeric(input[[id_cant(k)]] %||% 1), numeric(1)),
                 stringsAsFactors = FALSE)
    })
    res <- reactive(calcular_canasta(comp()[, c("clave_producto", "comercio", "precio_cop")], seleccion()))
    etq <- function(k) { p <- cat_prod(); p$etiqueta[match(k, p$clave_producto)] }
    
    output$aviso <- renderUI({
      if (!nrow(catalogos()$corridas_comp)) return(aviso("Ninguna ejecución tiene productos comparables todavía.", "danger"))
      if (!length(input$productos)) return(aviso(paste0("Elija uno o más productos comparables. Precios de la ejecución ", corr(), "."), "info"))
      r <- res(); tagList(
        aviso(paste0(r$aviso, " Ejecución ", corr(), "."), "warning"),
        if (any(!r$por_comercio$completa)) aviso(paste("Comercios sin total (les falta algún producto):",
                                                       paste(r$por_comercio$comercio[!r$por_comercio$completa], collapse = ", ")), "secondary"))
    })
    output$k1 <- renderText({ req(length(input$productos) > 0); r <- res(); if (is.na(r$mejor_unico_total)) "Sin total completo" else fmt_cop(r$mejor_unico_total) })
    output$p1 <- renderText({ req(length(input$productos) > 0); r <- res(); if (is.na(r$mejor_unico_total)) "ningún comercio tiene todos los productos" else paste(r$mejor_unico_comercio, "· COP · ejecución", corr()) })
    output$k2 <- renderText({ req(length(input$productos) > 0); fmt_cop(res()$total_dividida) })
    output$p2 <- renderText({ req(length(input$productos) > 0); if (is.na(res()$total_dividida)) "algún producto no tiene precio" else "cada producto donde es más barato · COP" })
    output$k3 <- renderText({ req(length(input$productos) > 0); fmt_cop(res()$ahorro_cop) })
    output$p3 <- renderText({ req(length(input$productos) > 0); r <- res(); if (is.na(r$ahorro_cop)) "sin comparación posible" else paste0(fmt_pct(r$ahorro_pct), " frente a comprar todo en ", r$mejor_unico_comercio) })
    
    output$g_total <- renderHighchart({
      validate(need(length(input$productos) > 0, "Elija productos para ver el gráfico.")); r <- res()
      pc <- r$por_comercio; pts <- lapply(seq_len(nrow(pc)), function(i) list(y = pc$total_cop[i], color = color_de(pc$comercio[i])))
      cats <- pc$comercio
      if (!is.na(r$total_dividida)) { pts <- c(pts, list(list(y = r$total_dividida, color = "#0B1F3A"))); cats <- c(cats, "Compra dividida") }
      highchart() |> hc_chart(type = "column") |> hc_xAxis(categories = cats) |>
        hc_add_series(name = "Total", data = pts, showInLegend = FALSE) |>
        hc_tooltip(valueDecimals = 0, valuePrefix = "$ ", pointFormat = "<b>${point.y}</b>") |> hc_base("COP")
    })
    output$t_total <- renderDT({
      validate(need(length(input$productos) > 0, "")); pc <- res()$por_comercio
      t <- data.frame(Comercio = pc$comercio, `Total (COP)` = ifelse(pc$completa, fmt_cop(pc$total_cop),
                                                                     paste0("Incompleta: falta ", pc$n_faltantes, " producto(s)")), check.names = FALSE)
      datatable(t, rownames = FALSE, class = "compact", options = list(dom = "t", language = DT_ES))
    })
    output$t_detalle <- renderDT({
      validate(need(length(input$productos) > 0, "")); d <- res()$detalle
      t <- data.frame(Producto = etq(d$clave_producto), Cantidad = d$cantidad, `Precio mínimo (COP)` = fmt_cop(d$precio_minimo),
                      `Comprar en` = ifelse(is.na(d$comercios_minimo), "Sin precio", d$comercios_minimo),
                      `Subtotal (COP)` = fmt_cop(d$subtotal_cop), Empate = ifelse(d$hay_empate, "Sí", "No"), check.names = FALSE)
      datatable(t, rownames = FALSE, class = "compact stripe", options = list(dom = "t", pageLength = 50, language = DT_ES))
    })
  })
}