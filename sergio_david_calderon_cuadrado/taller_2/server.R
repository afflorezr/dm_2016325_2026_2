server <- function(input, output, session) {
  con <- conectar()
  session$onSessionEnded(function() dbDisconnect(con))
  
  # El orden en server.R es: opc, el observe, texto_d, f, ind, y al final los output.
  version <- reactiveVal(0)     # sube en 1 cuando hay datos nuevos y obliga a recalcular
  opc <- reactive({ version(); opciones_filtros(con) })
  
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
  
  observe({
    ej <- opc()$ejecuciones
    comp <- ej$codigo_corrida[ej$estado == "completa"]          # las completas, de la más reciente a la más antigua
    etiquetas <- setNames(ej$codigo_corrida,
                          paste0(sub("T", " ", substr(ej$fecha_hora_inicio, 1, 16)), " · ", ej$estado))
    updateSelectInput(session, "ej_a", choices = etiquetas, selected = comp[2])
    updateSelectInput(session, "ej_b", choices = etiquetas, selected = comp[1])
    updateSelectInput(session, "canasta_ej", choices = etiquetas, selected = comp[1])
    updateSelectizeInput(session, "canasta_prod",
                         choices = setNames(opc()$productos$id_producto, opc()$productos$producto))
  })
  
  cambios <- reactive({
    req(input$ej_a, input$ej_b)
    tryCatch(cambios_entre(con, input$ej_a, input$ej_b, input$umbral),
             error_validacion = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  
  output$resumen_cambios <- renderText({
    s <- table(factor(cambios()$situacion,
                      levels = c("sube", "baja", "igual", "nuevo", "no_observado", "agotado_segun_sitio")))
    paste0(s[["sube"]], " suben · ", s[["baja"]], " bajan · ", s[["igual"]], " iguales · ",
           s[["nuevo"]], " nuevos · ", s[["no_observado"]] + s[["agotado_segun_sitio"]], " no observados")
  })
  
  output$t_cambios <- renderDT({
    tab  <- cambios()
    cols <- c("comercio", "nombre", "precio_a", "precio_b", "variacion_cop", "variacion_pct", "situacion", "supera_umbral")
    datatable(tab[, cols], rownames = FALSE,
              colnames = c("Comercio", "Producto", "Precio A (COP)", "Precio B (COP)", "Variación (COP)",
                           "Variación (%)", "Situación", "Supera umbral"),
              options = list(pageLength = 15, columnDefs = list(list(visible = FALSE, targets = 7)))) |>
      formatCurrency(c("precio_a", "precio_b", "variacion_cop"), currency = "$ ", interval = 3,
                     mark = ".", dec.mark = ",", digits = 0) |>
      formatStyle("variacion_pct", valueColumns = "supera_umbral",
                  backgroundColor = styleEqual(1, "#FFF3CD"), fontWeight = styleEqual(1, "bold"))
  })
  
  output$canasta_cantidades <- renderUI({
    req(input$canasta_prod)
    nombres <- setNames(opc()$productos$producto, opc()$productos$id_producto)
    tagList(lapply(input$canasta_prod, function(id) {
      previo <- isolate(input[[paste0("cant_", id)]])
      numericInput(paste0("cant_", id), paste("Cantidad:", nombres[[id]]),
                   value = if (is.null(previo)) 1 else previo, min = 1, max = 99, step = 1)
    }))
  })
  
  items <- reactive({
    req(input$canasta_prod)
    cant <- lapply(input$canasta_prod, function(id) input[[paste0("cant_", id)]])
    req(!any(sapply(cant, is.null)))
    data.frame(id_producto = as.integer(input$canasta_prod), cantidad = unlist(cant))
  })
  
  canasta_res <- reactive({
    req(input$canasta_ej)
    tryCatch(canasta(con, items(), input$canasta_ej),
             error_validacion = function(e) validate(need(FALSE, conditionMessage(e))))
  })
  
  output$t_canasta <- renderTable({
    t <- canasta_res()$totales
    data.frame(Comercio = t$comercio,
               `Costo total (COP)` = ifelse(t$completa == 1, formato_cop(t$costo),
                                            paste("No disponible. Falta:", t$faltantes)),
               check.names = FALSE)
  }, spacing = "xs", striped = TRUE)
  
  output$t_optima <- renderTable({
    o <- canasta_res()$compra_optima
    data.frame(Producto = o$producto, Cantidad = o$cantidad, `Comprar en` = o$comercio,
               `Precio unitario (COP)` = formato_cop(o$precio_unitario),
               `Subtotal (COP)` = formato_cop(o$subtotal), check.names = FALSE)
  }, spacing = "xs", striped = TRUE)
  
  output$res_canasta <- renderText({
    r <- canasta_res()$resumen
    if (is.na(r$costo_minimo_combinado)) return("Algún producto no está disponible en ningún comercio en esta ejecución.")
    txt <- paste0("Costo mínimo combinado: ", formato_cop(r$costo_minimo_combinado), " COP.")
    if (is.na(r$ahorro_cop)) paste(txt, "Ningún comercio tiene toda la canasta.")
    else paste0(txt, " Ahorro frente a comprar todo en ", r$mejor_comercio_unico, ": ",
                formato_cop(r$ahorro_cop), " COP (", r$ahorro_pct, " %).")
  })
  
  output$aviso_canasta <- renderText(
    paste0(canasta_res()$advertencia, " Precios de la ejecución del ", substr(canasta_res()$ejecucion$fecha, 1, 10), "."))
  
  resultado_act <- reactiveVal(NULL)
  
  observeEvent(input$actualizar, {
    showNotification("Actualizando...", id = "act", duration = NULL)
    res <- tryCatch({
      source("scraper.R", encoding = "UTF-8", local = TRUE)   # se carga solo al pulsar
      ejecutar_recoleccion(con, "respaldo")
    }, error = function(e) list(error = conditionMessage(e)))
    removeNotification("act")
    resultado_act(res)
    if (is.null(res$error)) version(version() + 1)
  })
  
  output$msg_act <- renderText({
    r <- req(resultado_act())
    if (!is.null(r$error)) paste("No se pudo actualizar:", r$error)
    else if (sum(r$resumen$nuevas_observaciones) == 0) "Sin datos nuevos: la base ya estaba al día."
    else paste("Actualización lista:", sum(r$resumen$nuevas_observaciones), "observaciones nuevas.")
  })
  output$t_act    <- renderTable({ r <- req(resultado_act()); req(is.null(r$error)); r$res })
  output$t_act_ej <- renderTable({ r <- req(resultado_act()); req(is.null(r$error)); r$ejecuciones_nuevas })
  
  
  ruta_progreso <- tempfile(fileext = ".csv")
  
  tarea <- ExtendedTask$new(function(modo, ruta_progreso, ruta_bd) {
    future_promise({
      source("scraper.R", encoding = "UTF-8")
      ejecutar_recoleccion(modo = modo, ruta_bd = ruta_bd, progreso = crear_progreso(ruta_progreso))
    }, seed = NULL)
  }) |> bind_task_button("actualizar")
  
  observeEvent(input$actualizar,   { unlink(ruta_progreso); tarea$invoke("scrape",   ruta_progreso, RUTA_BD) })
  observeEvent(input$sin_conexion, { unlink(ruta_progreso); tarea$invoke("respaldo", ruta_progreso, RUTA_BD) })
  
  avance <- reactive({ invalidateLater(1000); leer_progreso(ruta_progreso) })
  output$t_avance <- renderTable(avance())
  
  resultado <- reactive(
    tryCatch(tarea$result(),
             error = function(e) if (inherits(e, "shiny.silent.error")) stop(e) else list(error = conditionMessage(e))))
  
  observeEvent(tarea$status(), if (tarea$status() == "success") version(version() + 1))
  
  output$msg_act <- renderText({
    r <- resultado()
    if (!is.null(r$error)) paste("No se pudo actualizar:", r$error)
    else if (nrow(r$fallos) > 0) paste("Actualización con fallos en:", paste(r$fallos$comercio, collapse = ", "))
    else paste("Actualización lista:", sum(r$resumen$nuevas_observaciones), "observaciones nuevas.")
  })
  output$t_act    <- renderTable(req(resultado()$resumen))
  output$t_act_ej <- renderTable(req(resultado()$ejecuciones_nuevas))
}

