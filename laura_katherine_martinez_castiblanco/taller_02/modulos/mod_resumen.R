# Pestaña 1 · Resumen general: 8 indicadores (SQL) + distribución, oferta y mediana de precio por litro
resumen_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_column_wrap(width = "210px", fill = FALSE,
      kpi("Productos distintos", ns("k1"), "boxes-stacked", ns("p1")),
      kpi("Observaciones", ns("k2"), "database", ns("p2")),
      kpi("Precio promedio", ns("k3"), "tag", ns("p3")),
      kpi("En promoción", ns("k4"), "percent", ns("p4")),
      kpi("Última ejecución", ns("k5"), "clock", ns("p5")),
      kpi("Mayor ahorro posible", ns("k6"), "piggy-bank", ns("p6")),
      kpi("Cambios de precio", ns("k7"), "arrows-up-down", ns("p7")),
      kpi("Precios atípicos", ns("k8"), "triangle-exclamation", ns("p8"))),
    layout_columns(col_widths = c(7, 5),
      tarjeta("Distribución de precios por comercio (cuartiles, escala logarítmica)", highchartOutput(ns("g_dist"), height = "360px"),
              ayuda = "Caja = Q1–Q3, línea = mediana, bigotes = mínimo y máximo. Calculado con SQL sobre la selección actual."),
      tarjeta("Productos y % en promoción por comercio", highchartOutput(ns("g_oferta"), height = "360px"))),
    layout_columns(col_widths = c(6, 6),
      tarjeta("Mediana de precio por litro, por subcategoría (COP/L)", highchartOutput(ns("g_mediana"), height = "340px")),
      tarjeta("Precios atípicos: más de 3 veces la mediana de su subcategoría (COP/L)", DTOutput(ns("t_atip"))))
  )
}

resumen_server <- function(id, filtros, catalogos, version, corrida) {
  moduleServer(id, function(input, output, session) {
    kp   <- reactive(db_kpi_general(filtros())) |> bindCache(filtros(), version())
    obs  <- reactive(db_obs_por_comercio(filtros())) |> bindCache(filtros(), version())
    dist <- reactive(db_distribucion(filtros(), "precio_cop")) |> bindCache(filtros(), version())
    med  <- reactive(db_mediana_unitario(filtros(), por_comercio = FALSE)) |> bindCache(filtros(), version())
    atip <- reactive(db_atipicos(filtros())) |> bindCache(filtros(), version())
    aho  <- reactive(db_ahorro_max(corrida())) |> bindCache(corrida(), version())
    cam  <- reactive(db_cambios_ultima()) |> bindCache(version())
    ult  <- reactive(db_ultima_corrida()) |> bindCache(version())
    per  <- reactive(periodo_texto(filtros(), catalogos()$corridas))

    output$k1 <- renderText(fmt_num(kp()$n_productos)); output$p1 <- renderText(paste("anuncios únicos ·", per()))
    output$k2 <- renderText(fmt_num(kp()$n_obs));       output$p2 <- renderText(paste("observaciones ·", per()))
    output$k3 <- renderText(fmt_cop(kp()$precio_prom)); output$p3 <- renderText(paste("COP por producto ·", per()))
    output$k4 <- renderText(fmt_pct(kp()$pct_promo));   output$p4 <- renderText(paste("% de observaciones ·", per()))
    output$k5 <- renderText(fmt_fecha(ult()$fecha_hora))
    output$p5 <- renderText(if (nrow(ult())) paste("estado:", ult()$estado, "· corrida", ult()$id_corrida) else "sin ejecuciones")
    output$k6 <- renderText(if (nrow(aho())) fmt_cop(aho()$ahorro_cop) else "—")
    output$p6 <- renderText(if (nrow(aho())) paste0(aho()$etiqueta, " (", fmt_pct(aho()$ahorro_pct), ") · COP · corrida ", corrida()) else "sin comparables")
    output$k7 <- renderText({ d <- cam(); if (!nrow(d)) "0" else fmt_num(sum(d$n)) })
    output$p7 <- renderText({
      d <- cam(); if (!nrow(d)) return("vs. ejecución anterior · COP")
      paste0(sum(d$n[d$sentido == "sube"]), " suben · ", sum(d$n[d$sentido == "baja"]), " bajan · última ejecución")
    })
    output$k8 <- renderText(fmt_num(nrow(atip()))); output$p8 <- renderText(paste("COP/L > 3× mediana ·", per()))

    output$g_dist <- renderHighchart({
      d <- dist(); vacio(d)
      pts <- lapply(seq_len(nrow(d)), function(i) list(low = d$minimo[i], q1 = d$q1[i], median = d$mediana[i],
                                                       q3 = d$q3[i], high = d$maximo[i], color = color_de(d$comercio[i])))
      highchart() |> hc_chart(type = "boxplot") |>
        hc_xAxis(categories = d$comercio) |>
        hc_add_series(name = "Precio (COP)", data = pts, showInLegend = FALSE) |>
        hc_yAxis(type = "logarithmic") |>
        hc_tooltip(valueDecimals = 0, valuePrefix = "$ ") |>
        hc_base("COP (escala log)")
    })
    output$g_oferta <- renderHighchart({
      d <- obs(); vacio(d)
      highchart() |> hc_chart(type = "column") |>
        hc_xAxis(categories = d$comercio) |>
        hc_add_series(name = "Productos", data = lapply(seq_len(nrow(d)), function(i) list(y = d$productos[i], color = color_de(d$comercio[i])))) |>
        hc_add_series(name = "% en promoción", type = "line", yAxis = 1, color = "#E4572E", data = d$pct_promo) |>
        hc_yAxis_multiples(list(title = list(text = "Productos (anuncios únicos)")),
                           list(title = list(text = "% en promoción"), opposite = TRUE, max = 100, gridLineWidth = 0)) |>
        hc_tooltip(shared = TRUE) |>
        hc_chart(backgroundColor = "transparent") |> hc_credits(enabled = FALSE)
    })
    output$g_mediana <- renderHighchart({
      d <- med(); vacio(d)
      highchart() |> hc_chart(type = "bar") |>
        hc_xAxis(categories = d$subcategoria) |>
        hc_add_series(name = "Mediana COP/L", data = d$mediana_cop_l, color = "#0E8F6B", showInLegend = FALSE) |>
        hc_tooltip(valueDecimals = 0, valuePrefix = "$ ", valueSuffix = " /L") |>
        hc_base("COP por litro")
    })
    output$t_atip <- renderDT({
      d <- atip(); vacio(d, "Sin precios atípicos en la selección actual.")
      d$precio_cop <- fmt_cop(d$precio_cop); d$precio_por_l <- fmt_cop(d$precio_por_l); d$mediana_subcategoria <- fmt_cop(d$mediana_subcategoria)
      names(d) <- c("Comercio", "Producto", "Subcategoría", "Precio (COP)", "COP/L", "Mediana subcat. (COP/L)")
      datatable(d, rownames = FALSE, options = list(pageLength = 6, dom = "tp", language = DT_ES), class = "compact stripe")
    })
  })
}
