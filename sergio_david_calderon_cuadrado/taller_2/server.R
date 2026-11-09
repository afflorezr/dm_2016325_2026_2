server <- function(input, output, session) {
  con <- conectar()
  session$onSessionEnded(function() dbDisconnect(con))
  
  # El orden en server.R es: opc, el observe, texto_d, f, ind, y al final los output.
  opc <- reactive(opciones_filtros(con))
  
  observe({
    updateSelectizeInput(session, "comercio",
                         choices = opc()$comercios, selected = opc()$comercios)
    updateSliderInput(session, "precio",
                      min   = opc()$precio[["minimo"]],
                      max   = opc()$precio[["maximo"]],
                      value = c(opc()$precio[["minimo"]], opc()$precio[["maximo"]]))
    updateSelectInput(session, "producto",
                      choices = setNames(opc()$productos$id_producto, opc()$productos$producto))
    updateSelectizeInput(session, "subcategoria", choices = opc()$subcategorias)
    updateSelectizeInput(session, "marca",        choices = opc()$marcas)
    ej <- opc()$ejecuciones
    updateSelectInput(session, "corrida",
                      choices = setNames(ej$codigo_corrida,
                                         paste0(sub("T", " ", substr(ej$fecha_hora_inicio, 1, 16)), " · ", ej$estado)))
    updateDateRangeInput(session, "fechas",
                         start = opc()$fechas[["desde"]], end = opc()$fechas[["hasta"]],
                         min   = opc()$fechas[["desde"]], max = opc()$fechas[["hasta"]])
  })
  
  texto_d <- debounce(reactive(input$texto), 600)
  
  f <- reactive(list(
    comercios = input$comercio, subcategorias = input$subcategoria, marcas = input$marca,
    precio = input$precio, solo_promociones = input$promo,
    solo_comparables = input$comparables, texto = texto_d(),
    corrida = if (identical(input$periodo, "ejecucion")) input$corrida,
    fechas  = if (identical(input$periodo, "fechas")) input$fechas))
  
  # observe(print(f()$solo_comparables))
  
  ind <- reactive({
    tryCatch(indicadores(con, f()),
             error_validacion = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  
  output$n_productos <- renderText(ind()$resumen$productos)
  output$n_obs       <- renderText(ind()$resumen$observaciones)
  output$pct_promo   <- renderText(paste0(ind()$resumen$pct_promocion, " %"))
  output$mediana     <- renderText(formato_cop(ind()$resumen$mediana_precio))
  
  output$ahorro <- renderText({
    a <- ind()$ahorro_maximo
    req(nrow(a) > 0)
    formato_cop(a$ahorro_cop)
  })
  output$ahorro_detalle <- renderText({
    a <- ind()$ahorro_maximo
    req(nrow(a) > 0)
    paste0(a$producto, ": ", a$comercio_barato, " vs ", a$comercio_caro,
           " (ejecución del ", substr(a$fecha_corrida, 1, 10), ")")
  })
  output$cambios <- renderText({
    cu <- ind()$cambios_ultima
    paste0(cu$suben, " suben · ", cu$bajan, " bajan")
  })
  output$t_ultima   <- renderTable(ind()$ultima_ejecucion[, c("comercio", "estado", "fecha_hora_inicio", "n_registros")])
  output$t_subcat   <- renderTable(transform(ind()$mediana_subcategoria, mediana = formato_cop(mediana)))
  output$t_comercio <- renderTable(ind()$por_comercio)
  
  output$g_evolucion <- renderHighchart({
    req(input$producto)
    d <- serie_precio(con, input$producto)
    d$fecha    <- as.Date(substr(d$fecha_hora_consulta, 1, 10))
    d$comercio <- factor(d$comercio, levels = names(PALETA_COMERCIOS))
    hchart(d, "line", hcaes(x = fecha, y = precio, group = comercio)) |>
      hc_colors(unname(PALETA_COMERCIOS)) |>
      hc_xAxis(type = "datetime", title = list(text = "Fecha de la ejecución")) |>
      hc_yAxis(title = list(text = "Precio (COP)")) |>
      hc_title(text = "Evolución del precio") |>
      hc_tooltip(shared = TRUE, valueSuffix = " COP") |>
      hc_plotOptions(series = list(marker = list(enabled = TRUE)))
  })
  
  # Reutilizable: aplica una consulta con los filtros y muestra el error de validación si lo hay
  con_filtros <- function(fun) {
    tryCatch(fun(con, f()),
             error_validacion = function(e) validate(need(FALSE, conditionMessage(e))))
  }
  
  output$g_unitario <- renderHighchart({
    d <- con_filtros(precio_unitario)
    d <- d[d$medida == input$medida, ]
    req(nrow(d) > 0)
    d$comercio <- factor(d$comercio, levels = names(PALETA_COMERCIOS))
    d$color <- unname(PALETA_COMERCIOS[as.character(d$comercio)])
    hchart(d, "column", hcaes(x = comercio, y = mediana, color = color)) |>
      hc_colors(unname(PALETA_COMERCIOS)) |>
      hc_yAxis(title = list(text = paste("COP por", input$medida))) |>
      hc_xAxis(title = list(text = "Comercio")) |>
      hc_legend(enabled = FALSE)
  })
  
  output$g_distribucion <- renderHighchart({
    d <- con_filtros(distribucion_precios)
    req(nrow(d) > 0)
    highchart() |>
      hc_chart(type = "boxplot") |>
      hc_xAxis(categories = as.character(d$comercio)) |>
      hc_yAxis(title = list(text = "Precio (COP)")) |>
      hc_add_series(name = "Precio (COP)", colorByPoint = TRUE,
                    data = lapply(seq_len(nrow(d)), function(i)
                      unname(unlist(d[i, c("minimo", "q1", "mediana", "q3", "maximo")])))) |>
      hc_colors(unname(PALETA_COMERCIOS[as.character(d$comercio)])) |>
      hc_legend(enabled = FALSE)
  })
  
  output$tabla <- renderDT({
    p <- con_filtros(filtrar_precios)
    p$producto  <- sprintf('<a href="%s" target="_blank" rel="noopener">%s</a>',
                           htmltools::htmlEscape(p$url_producto), htmltools::htmlEscape(p$nombre))
    p$promocion <- ifelse(p$es_promocion == 1, "Sí", "No")
    p$fecha     <- sub("T", " ", substr(p$fecha_hora_consulta, 1, 16))
    datatable(p[, c("comercio", "producto", "marca", "presentacion", "precio",
                    "precio_por_medida", "medida", "promocion", "disponibilidad", "fecha")],
              escape = FALSE, rownames = FALSE, extensions = "Buttons",
              colnames = c("Comercio", "Producto", "Marca", "Presentación", "Precio (COP)",
                           "Precio por unidad (COP)", "Unidad", "Promoción", "Disponibilidad", "Fecha de consulta"),
              options = list(dom = "Bfrtip", pageLength = 15,
                             buttons = list(list(extend = "csv", text = "Descargar CSV")))) |>
      formatCurrency("precio", currency = "$ ", interval = 3, mark = ".", dec.mark = ",", digits = 0) |>
      formatCurrency("precio_por_medida", currency = "$ ", interval = 3, mark = ".", dec.mark = ",", digits = 2)
  })
  
  output$periodo <- renderText({
    r <- ind()$resumen
    base <- switch(r$periodo,
                   ultimo_precio = "Último precio de cada producto",
                   ejecucion     = "Ejecución elegida",
                   fechas        = "Rango de fechas elegido")
    paste0(base, " · datos hasta el ", substr(r$fecha_hasta, 1, 10))
  })
  
  output$g_promos <- renderHighchart({
    d <- con_filtros(promociones_por_comercio)
    req(nrow(d) > 0)
    d$comercio <- factor(d$comercio, levels = names(PALETA_COMERCIOS))
    d$tooltip <- paste0(d$en_promocion, " de ", d$productos, " productos<br>Descuento mediano: ",
                        ifelse(is.na(d$descuento_mediano_pct), "sin promociones", paste0(d$descuento_mediano_pct, " %")))
    d$color <- unname(PALETA_COMERCIOS[as.character(d$comercio)])
    hchart(d, "column", hcaes(x = comercio, y = pct_promocion, color = color)) |>
      # hc_colors(unname(PALETA_COMERCIOS)) |>
      hc_xAxis(title = list(text = "Comercio")) |>
      hc_yAxis(title = list(text = "% de productos en promoción"), max = 100) |>
      hc_tooltip(pointFormat = "{point.tooltip}") |>
      hc_legend(enabled = FALSE)
  })
}
