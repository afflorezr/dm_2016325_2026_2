# =============================================================================
# server.R  -  Logica de la aplicacion (Modulos 2, 3, 5 y 6)
# -----------------------------------------------------------------------------
# - Modulo 2: boton de actualizacion con ExtendedTask (segundo plano),
#   tolerancia a fallas por comercio, modo sin conexion y resumen por comercio.
# - Modulo 3: TODO el SQL vive en db.R; aqui solo se llaman funciones.
# - Modulo 5: indicadores, graficos interactivos (highcharter) y tabla (DT).
# - Modulo 6: precio unitario, cambios de precio y canasta.
# =============================================================================

function(input, output, session) {

  # ---------------------------------------------------------- conexion
  con <- abrir_conexion(DB_PATH)
  onSessionEnded(function() cerrar_conexion(con))

  # Gatillo de invalidacion: al terminar una actualizacion se incrementa y
  # todas las reactivas dependientes (y su cache) se recalculan.
  # Inicia en 1 para que req()/filtros funcionen desde el arranque.
  gatillo <- reactiveVal(1L)
  actualizado_sesion <- reactiveVal(FALSE)

  # ------------------------------------------------- Modulo 2: actualizacion
  # Tarea en segundo plano: recibe el modo y los terminos extra que el usuario
  # escriba en el panel lateral (se suman a TERMINOS_BUSQUEDA).
  tarea_actualizacion <- ExtendedTask$new(function(modo, terminos_extra) {
    future_promise({
      tryCatch({
        if (!exists("ejecutar_scraper", mode = "function")) {
          source("validacion.R", local = FALSE)
          source("scraper.R",     local = FALSE)
        }
        terminos <- unique(c(TERMINOS_BUSQUEDA, terminos_extra))
        ejecutar_scraper(modo = modo, terminos = terminos)
      }, error = function(e) {
        list(error = paste("Fallo la recolección:", conditionMessage(e)))
      })
    })
  }) |> bind_task_button("btn_actualizar")

  observeEvent(input$btn_actualizar, {
    tarea_actualizacion$invoke(
      modo = input$modo_ejecucion %||% "offline",
      terminos_extra = parsear_terminos(input$productos_extra))
  })

  observeEvent(tarea_actualizacion$result(), {
    res <- tarea_actualizacion$result()
    if (is.list(res) && !is.null(res$error)) {
      showNotification(res$error, type = "error", duration = 10)
    } else if (inherits(res, "error")) {
      showNotification(conditionMessage(res), type = "error", duration = 10)
    } else {
      if (!is.null(res$resumen) && nrow(res$resumen)) {
        fallidas <- res$resumen |> filter(estado == "fallida")
        if (nrow(fallidas)) {
          showNotification(
            paste("Comercios con falla:", paste(fallidas$comercio, collapse = ", "),
                  "—", substr(fallidas$motivo[1], 1, 120)),
            type = "warning", duration = 12)
        } else {
          showNotification("Precios actualizados correctamente.", type = "message")
        }
        output$tabla_resumen_actualizacion <- renderTable(res$resumen)
      }
      actualizado_sesion(TRUE)
      gatillo(gatillo() + 1L)
    }
  })

  output$estado_actualizacion <- renderUI({
    corriendo <- tryCatch(tarea_actualizacion$running(), error = function(e) FALSE)
    if (isTRUE(corriendo)) {
      div(class = "alert alert-info py-2 small",
          icon("spinner", class = "fa-spin"), " Actualizando precios…",
          " Puede tomar varios minutos.")
    } else if (isTRUE(actualizado_sesion())) {
      div(class = "alert alert-success py-2 small",
          "Última actualización aplicada. Los indicadores están al día.")
    } else {
      div(class = "text-muted small", "Sin actualizaciones en esta sesión.")
    }
  })

  # ------------------------------------------------- listas para los filtros
  observe({
    gatillo()
    updateSelectInput(session, "comercio",
                      choices = lista_comercios(con), selected = character(0))
    updateSelectInput(session, "subcategoria",
                      choices = lista_subcategorias(con), selected = character(0))
    ej <- lista_ejecuciones(con)
    updateSelectInput(session, "ejecucion",
                      choices = setNames(ej$id_ejecucion, ej$fecha_consulta),
                      selected = character(0))
    comp <- lista_comparables(con)
    updateSelectInput(session, "comparable_evolucion", choices = comp,
                      selected = if (length(comp)) comp[1] else NULL)
    updateSelectizeInput(session, "canasta_productos", choices = comp,
                         server = TRUE)
    # el calendario de fechas cubre todo el rango observado en la base
    fq <- rango_fechas_observadas(con)
    if (!is.na(fq$mn[1])) {
      updateDateRangeInput(session, "fechas",
                           start = as.Date(substr(fq$mn[1], 1, 10)),
                           end   = as.Date(substr(fq$mx[1], 1, 10)),
                           min   = as.Date(substr(fq$mn[1], 1, 10)),
                           max   = as.Date(substr(fq$mx[1], 1, 10)))
    }
    # por defecto: las dos ejecuciones mas recientes en cambios de precio
    if (length(ej$id_ejecucion) >= 2) {
      updateSelectInput(session, "ejec_a", choices = setNames(ej$id_ejecucion, ej$fecha_consulta),
                        selected = ej$id_ejecucion[2])
      updateSelectInput(session, "ejec_b", choices = setNames(ej$id_ejecucion, ej$fecha_consulta),
                        selected = ej$id_ejecucion[1])
    } else if (length(ej$id_ejecucion) == 1) {
      updateSelectInput(session, "ejec_a", choices = ej$id_ejecucion)
      updateSelectInput(session, "ejec_b", choices = ej$id_ejecucion)
    }
  })

  # Marca depende de la subcategoria elegida
  observe({
    gatillo()
    updateSelectInput(session, "marca",
                      choices = lista_marcas(con, input$comercio, input$subcategoria),
                      selected = character(0))
  })

  # ---------------------------------------------------------- filtros activos
  filtros <- reactive({
    gatillo()  # dependencia: invalida tras cada actualizacion
    list(
      comercios      = input$comercio %||% character(0),
      subcategorias  = input$subcategoria %||% character(0),
      marcas         = input$marca %||% character(0),
      pmin           = if (!is.null(input$precio)) input$precio[1] else NULL,
      pmax           = if (!is.null(input$precio)) input$precio[2] else NULL,
      fecha_desde    = if (!is.null(input$fechas) && !is.na(input$fechas[1]))
                         as.character(input$fechas[1]) else NULL,
      fecha_hasta    = if (!is.null(input$fechas) && !is.na(input$fechas[2]))
                         as.character(input$fechas[2]) else NULL,
      ejecuciones    = input$ejecucion %||% character(0),
      solo_promocion = isTRUE(input$solo_promocion),
      solo_comparables = isTRUE(input$solo_comparables),
      busqueda       = validar_texto_busqueda(input$busqueda %||% "")
    )
  })

  datos_filtrados <- reactive({
    gatillo()
    f <- filtros()
    tryCatch(do.call(filtrar_ultimo_precio, c(list(con), f)),
             error = function(e) {
               showNotification(MSG_ERROR, type = "error")
               data.frame()
             })
  }) |> bindCache(filtros(), gatillo())

  output$n_resultados <- renderText({
    n <- nrow(datos_filtrados())
    paste(n, "anuncio(s) en la última observación de cada URL")
  })

  # ------------------------------------------------- limpiar filtros (UX)
  observeEvent(input$limpiar_filtros, {
    updateTextInput(session, "busqueda", value = "")
    updateSelectInput(session, "comercio", selected = character(0))
    updateSelectInput(session, "subcategoria", selected = character(0))
    updateSelectInput(session, "marca", selected = character(0))
    updateSelectInput(session, "ejecucion", selected = character(0))
    updateSliderInput(session, "precio", value = c(0, PRECIO_MAX))
    fq <- rango_fechas_observadas(con)
    if (!is.na(fq$mn[1])) {
      updateDateRangeInput(session, "fechas",
                           start = as.Date(substr(fq$mn[1], 1, 10)),
                           end   = as.Date(substr(fq$mx[1], 1, 10)))
    }
    updateCheckboxInput(session, "solo_promocion", value = FALSE)
    updateCheckboxInput(session, "solo_comparables", value = FALSE)
  })

  # ============================================================ INDICADORES
  ind_por_comercio <- reactive({
    gatillo(); indicador_por_comercio(con)
  }) |> bindCache(gatillo())

  ind_ultima <- reactive({
    gatillo(); indicador_ultima_ejecucion(con)
  }) |> bindCache(gatillo())

  ind_promo <- reactive({
    gatillo(); indicador_promocion(con)
  }) |> bindCache(gatillo())

  ind_mediana <- reactive({
    gatillo(); indicador_mediana_subcategoria(con)
  }) |> bindCache(gatillo())

  ind_ahorro <- reactive({
    gatillo(); indicador_ahorro_maximo(con)
  }) |> bindCache(gatillo())

  ind_cambios <- reactive({
    gatillo(); indicador_cambios(con)
  }) |> bindCache(gatillo())

  output$ind_observaciones <- renderText({
    df <- datos_filtrados()
    fmt_entero(nrow(df))
  })
  output$ind_observaciones_sub <- renderText({
    df <- datos_filtrados()
    paste0(length(unique(df$url)), " anuncios · ",
           paste(sprintf("%s %s", df$comercio |> table() |> sort(decreasing = TRUE) |> head(3) |> names(),
                         df$comercio |> table() |> sort(decreasing = TRUE) |> head(3) |> as.integer()),
                 collapse = " · "))
  })

  output$ind_comparables <- renderText({
    n <- contar_comparables(con)
    fmt_entero(n)
  })
  output$ind_comparables_sub <- renderText({
    obs <- contar_observaciones_comparables(con)
    paste0(obs, " observaciones comparables")
  })

  output$ind_promo <- renderText({
    paste0(format(ind_promo()$pct_promocion[1], nsmall = 1), " %")
  })
  output$ind_promo_periodo <- renderText({
    p <- ind_promo()
    if (!nrow(p) || is.na(p$periodo[1])) "—" else substr(p$periodo[1], 1, 16)
  })

  output$ind_ahorro <- renderText({
    a <- ind_ahorro()
    if (!nrow(a) || is.na(a$ahorro_max_cop[1])) return("—")
    paste0("$ ", fmt_entero(a$ahorro_max_cop[1]))
  })
  output$ind_ahorro_sub <- renderText({
    a <- ind_ahorro()
    if (!nrow(a) || is.na(a$ahorro_max_cop[1])) return("sin comparables aún")
    paste0(a$ahorro_max_pct[1], "% · ", a$marca[1], " ", a$subcategoria[1], " ",
           a$contenido_valor[1], " ", a$contenido_unidad[1])
  })

  output$cambios_subidas <- renderText(ind_cambios()$subidas[1] %||% 0)
  output$cambios_bajas   <- renderText(ind_cambios()$bajas[1] %||% 0)
  output$cambios_total   <- renderText(ind_cambios()$n_cambios[1] %||% 0)
  output$cambios_periodo <- renderText({
    c <- ind_cambios()
    if (!nrow(c) || is.na(c$periodo[1])) "Aún no hay cambios registrados (se necesitan dos ejecuciones)."
    else paste("Período:", c$periodo[1])
  })

  output$tabla_ejecucion <- renderTable({
    u <- ind_ultima()
    if (!nrow(u)) return(data.frame(Mensaje = "Sin ejecuciones registradas"))
    data.frame(
      Campo = c("Fecha y hora (Colombia)", "Comercios exitosos",
                "Comercios parciales", "Comercios fallidos"),
      Valor = c(u$fecha_consulta[1], u$exitosas[1], u$parciales[1], u$fallidas[1])
    )
  }, striped = TRUE, spacing = "xs")

  output$tabla_indicadores_subcategoria <- renderTable({
    ind_mediana()
  }, striped = TRUE, spacing = "xs", digits = 0)

  # ================================================================ GRAFICOS
  # 1) Distribucion de precios por comercio (boxplot)
  output$hc_distribucion <- renderHighchart({
    gatillo()
    df <- distribucion_precios(con)
    req(nrow(df) > 0)
    series <- lapply(split(df$precio_cop, df$comercio), function(x) {
      qs <- unname(quantile(x, c(0, .25, .5, .75, 1)))
      list(name = "", data = list(list(low = qs[1], q1 = qs[2], median = qs[3],
                                       q3 = qs[4], high = qs[5])))
    })
    nombres <- names(split(df$precio_cop, df$comercio))
    hc <- highchart()
    for (i in seq_along(series)) {
      hc <- hc |>
        hc_add_series(data = series[[i]]$data, type = "boxplot",
                      name = nombres[i],
                      color = color_comercio(nombres[i]))
    }
    hc |>
      hc_title(text = NULL) |>
      hc_xAxis(title = list(text = "Comercio")) |>
      hc_yAxis(title = list(text = "Precio (COP)"),
               labels = list(format = "{value:,.0f}")) |>
      hc_tooltip(pointFormat = "Min {point.low:.0f} · Q1 {point.q1:.0f} · Mediana {point.median:.0f} · Q3 {point.q3:.0f} · Max {point.high:.0f} COP") |>
      hc_plotOptions(boxplot = list(stemWidth = 1, fillColor = "transparent")) |>
      hc_legend(enabled = TRUE) |>
      hc_credits(enabled = FALSE)
  })

  # 2) Libre: brecha de precio entre comercios
  output$hc_brecha <- renderHighchart({
    gatillo()
    df <- serie_brecha(con) |> head(15)
    req(nrow(df) > 0)
    cats <- if ("producto" %in% names(df)) df$producto else
      paste0(df$marca, " ", df$subcategoria, " ", df$contenido_valor, " ",
             df$contenido_unidad)
    puntos <- Map(function(b, cc, cb) {
      list(y = b, comercio_caro = cc, comercio_barato = cb)
    }, df$brecha_cop, df$comercio_caro, df$comercio_barato)
    highchart() |>
      hc_chart(type = "bar") |>
      hc_add_series(
        data = puntos,
        name = "Brecha máximo - mínimo (COP)",
        color = "#E4002B",
        showInLegend = FALSE,
        dataLabels = list(enabled = TRUE,
                          formatter = JS("function(){return '$ ' + Highcharts.numberFormat(this.y,0,'',',')}"))) |>
      hc_xAxis(categories = cats, title = list(text = NULL)) |>
      hc_yAxis(title = list(text = "Diferencia (COP)"),
               labels = list(format = "{value:,.0f}")) |>
      hc_tooltip(pointFormatter = JS(
        "function(){return '<b>'+ this.category +'</b><br/>Brecha: $ ' +
         Highcharts.numberFormat(this.y,0,'',',') + ' COP<br/>Más caro: ' +
         this.point.comercio_caro + '<br/>Más barato: ' + this.point.comercio_barato}")) |>
      hc_credits(enabled = FALSE)
  })

  # 3) Evolucion del precio de un comparable
  output$titulo_evolucion <- renderText({
    paste("Evolución del precio —", input$comparable_evolucion %||% "seleccione un producto")
  })
  output$hc_evolucion <- renderHighchart({
    gatillo()
    idc <- input$comparable_evolucion
    req(idc)
    df <- serie_evolucion(con, idc)
    if (!nrow(df)) {
      return(highchart() |>
               hc_title(text = MSG_SIN_DATOS) |>
               hc_credits(enabled = FALSE))
    }
    df$ts <- as.numeric(as.POSIXct(substr(df$fecha_consulta, 1, 19),
                                   format = "%Y-%m-%dT%H:%M:%S",
                                   tz = "America/Bogota")) * 1000
    series <- lapply(split(df, df$comercio), function(d) {
      list(name = d$comercio[1],
           color = color_comercio(d$comercio[1]),
           data = Map(function(x, y, p, u) list(x = x, y = y,
                                                promo = p, url = u),
                      d$ts, d$precio_cop, d$en_promocion, d$url))
    })
    hc <- highchart()
    for (s in series) hc <- hc |> hc_add_series_list(list(s))
    hc |>
      hc_title(text = NULL) |>
      hc_xAxis(type = "datetime",
               title = list(text = "Fecha de consulta (hora de Colombia)")) |>
      hc_yAxis(title = list(text = "Precio (COP)"),
               labels = list(format = "{value:,.0f}")) |>
      hc_tooltip(shared = TRUE,
                 formatter = JS("function(){
                   var s = '<b>' + Highcharts.dateFormat('%e %b %Y %H:%M', this.x) + '</b>';
                   this.points.forEach(function(p){
                     s += '<br/>' + p.series.name + ': $ ' +
                          Highcharts.numberFormat(p.y,0,'',',') +
                          (p.point.promo ? ' (promoción)' : '');
                   });
                   return s;}")) |>
      hc_legend(enabled = TRUE) |>
      hc_credits(enabled = FALSE)
  })

  # 4) Precio por unidad de contenido (sin mezclar unidades)
  output$aviso_unidad <- renderText({
    paste("Comparando solo presentaciones en",
          switch(input$unidad_unitario, ml = "mililitros", g = "gramos",
                 "unidades"),
          ". No se mezclan unidades distintas en el mismo ranking.")
  })
  output$titulo_unitario <- renderText({
    paste0("Precio por unidad de contenido (", UNIDAD_LABEL[input$unidad_unitario] %||% "", ")")
  })
  output$hc_unitario <- renderHighchart({
    gatillo()
    uni <- input$unidad_unitario %||% "ml"
    df <- serie_precio_unitario(con, uni)
    if (!nrow(df)) {
      return(highchart() |>
               hc_title(text = MSG_SIN_DATOS) |> hc_credits(enabled = FALSE))
    }
    # una fila por presentacion, columnas por comercio
    wide <- df |>
      mutate(etiqu = str_trunc(paste(marca, subcategoria, contenido_valor,
                                     contenido_unidad), 42, side = "right")) |>
      select(etiqu, id_comun, comercio, precio_por_100) |>
      distinct(etiqu, id_comun, comercio, .keep_all = TRUE) |>
      pivot_wider(names_from = comercio, values_from = precio_por_100,
                  values_fn = min)
    cols <- setdiff(names(wide), c("etiqu", "id_comun"))
    hc <- highchart()
    for (cm in cols) {
      hc <- hc |> hc_add_series(
        data = as.list(wide[[cm]]), name = cm,
        color = color_comercio(cm))
    }
    hc |>
      hc_chart(type = "column") |>
      hc_title(text = NULL) |>
      hc_xAxis(categories = wide$etiqu, title = list(text = NULL),
               labels = list(rotation = -35, style = list(fontSize = "10px"))) |>
      hc_yAxis(title = list(text = UNIDAD_LABEL[uni] %||% ""),
               labels = list(format = "{value:,.0f}")) |>
      hc_tooltip(shared = TRUE,
                 pointFormat = "<span style='color:{series.color}'>●</span> {series.name}: <b>{point.y:,.1f}</b><br/>") |>
      hc_legend(enabled = TRUE) |>
      hc_credits(enabled = FALSE)
  })

  # =========================================================== TABLA + CSV
  output$tabla_productos <- renderDT({
    df <- datos_filtrados()
    req(nrow(df) > 0)
    df |>
      transmute(
        Comercio = comercio,
        Producto = producto,
        Marca = marca,
        Subcategoria = subcategoria,
        Presentacion = ifelse(is.na(contenido_valor), "—",
                              paste0(contenido_valor, " ", contenido_unidad)),
        `Precio (COP)` = round(precio_cop),
        `Precio unitario` = ifelse(is.na(contenido_valor), NA,
                                   round(precio_cop / contenido_valor, 2)),
        Promocion = ifelse(en_promocion == 1, "Sí", "No"),
        Disponibilidad = ifelse(is.na(disponibilidad), "no observado", disponibilidad),
        Fecha = substr(fecha_consulta, 1, 16),
        Enlace = paste0("<a href='", url, "' target='_blank' rel='noopener'>ver anuncio</a>")
      ) |>
      datatable(options = list(pageLength = 10, order = list(list(5, "asc")),
                               scrollX = TRUE),
                escape = FALSE, rownames = FALSE) |>
      formatCurrency("Precio (COP)", currency = "$ ", interval = 3, mark = ".")
  })

  output$descargar_csv <- downloadHandler(
    filename = function() {
      paste0("productos_filtrados_", format(Sys.time(), "%Y%m%d_%H%M"), ".csv")
    },
    content = function(file) {
      df <- datos_filtrados()
      utils::write.csv(df, file, row.names = FALSE, fileEncoding = "UTF-8")
    }
  )

  # =============================================== PESTANA COMPARABLES
  output$tabla_comparables <- renderDT({
    gatillo()
    df <- serie_precio_unitario(con, input$unidad_unitario %||% "ml")
    req(nrow(df) > 0)
    wide <- df |>
      select(id_comun, marca, subcategoria, contenido_valor, contenido_unidad,
             comercio, producto, precio_cop, precio_por_100) |>
      pivot_wider(names_from = comercio,
                  values_from = c(precio_cop, precio_por_100),
                  names_sep = " ")
    datatable(wide, options = list(pageLength = 10, scrollX = TRUE),
              rownames = FALSE) |>
      formatCurrency(grep("^precio_cop ", names(wide), value = TRUE),
                     currency = "$ ", interval = 3, mark = ".")
  })

  # =============================================== PESTANA CAMBIOS
  cambios <- reactive({
    gatillo()
    req(input$ejec_a, input$ejec_b)
    comparar_ejecuciones(con, input$ejec_a, input$ejec_b)
  }) |> bindCache(input$ejec_a, input$ejec_b, gatillo())

  output$cmp_subieron <- renderText(nrow(cambios()$subieron))
  output$cmp_bajaron  <- renderText(nrow(cambios()$bajaron))
  output$cmp_nuevos   <- renderText(nrow(cambios()$nuevos))
  output$cmp_fuera    <- renderText(nrow(cambios()$desaparecieron))

  tabla_cambios_datos <- reactive({
    c <- cambios()
    rbind(
      c$subieron |> mutate(sentido = "Subió"),
      c$bajaron  |> mutate(sentido = "Bajó"),
      c$iguales  |> mutate(sentido = "Sin cambio")
    ) |>
      mutate(`Resaltado` = ifelse(abs(variacion_cop) >= (input$umbral %||% 0),
                                  "Variación grande", ""))
  })

  # Grafica resumen: mayores variaciones de precio entre las dos ejecuciones.
  # Rojo = subio, verde = bajo; las lineas punteadas marcan el umbral.
  output$hc_resumen_cambios <- renderHighchart({
    df <- tabla_cambios_datos()
    req(nrow(df) > 0)
    df <- df |> filter(sentido != "Sin cambio")
    if (!nrow(df)) {
      return(highchart() |>
               hc_title(text = "Sin variaciones de precio entre las dos ejecuciones.") |>
               hc_credits(enabled = FALSE))
    }
    df <- df |>
      mutate(etiqueta = str_trunc(paste0(comercio, " · ", producto), 48, side = "right")) |>
      slice_max(abs(variacion_cop), n = 12, with_ties = FALSE) |>
      arrange(variacion_cop)
    puntos <- Map(
      function(v, pa, pb, pct, cm, pr, et) {
        list(y = v, color = if (!is.na(v) && v > 0) "#E4002B" else "#2E7D32",
             precio_a = pa, precio_b = pb, pct = pct,
             comercio = cm, producto = pr, etiqueta = et)
      },
      df$variacion_cop, df$precio_a, df$precio_b, df$variacion_pct,
      df$comercio, df$producto, df$etiqueta)
    umbral <- input$umbral %||% 1000
    highchart() |>
      hc_chart(type = "bar") |>
      hc_add_series(
        data = puntos, name = "Variación (COP)", showInLegend = FALSE,
        dataLabels = list(enabled = TRUE,
                          formatter = JS("function(){return '$ ' + Highcharts.numberFormat(this.y,0,'',',')}"))) |>
      hc_xAxis(categories = df$etiqueta, title = list(text = NULL),
               labels = list(style = list(fontSize = "10px"))) |>
      hc_yAxis(title = list(text = "Variación del precio (COP)"),
               labels = list(format = "{value:,.0f}"),
               plotLines = list(
                 list(value = umbral, color = "#999999", width = 1,
                      dashStyle = "Dash",
                      label = list(text = "umbral", style = list(fontSize = "9px"))),
                 list(value = -umbral, color = "#999999", width = 1,
                      dashStyle = "Dash"))) |>
      hc_tooltip(formatter = JS(
        "function(){return '<b>' + this.point.producto + '</b><br/>' + this.point.comercio +
         '<br/>Precio anterior: $ ' + Highcharts.numberFormat(this.point.precio_a,0,'',',') +
         '<br/>Precio nuevo: $ ' + Highcharts.numberFormat(this.point.precio_b,0,'',',') +
         '<br/>Variación: $ ' + Highcharts.numberFormat(this.y,0,'',',') +
         ' (' + this.point.pct + ' %)'}")) |>
      hc_credits(enabled = FALSE)
  })

  output$tabla_cambios <- renderDT({
    df <- tabla_cambios_datos()
    req(nrow(df) > 0)
    df |>
      transmute(
        Comercio = comercio, Producto = producto,
        `Precio anterior (COP)` = round(precio_a),
        `Precio nuevo (COP)` = round(precio_b),
        `Variación (COP)` = round(variacion_cop),
        `Variación (%)` = variacion_pct,
        Sentido = sentido, Señal = Resaltado
      ) |>
      datatable(options = list(pageLength = 10, order = list(list(4, "desc"))),
                rownames = FALSE) |>
      formatCurrency(c("Precio anterior (COP)", "Precio nuevo (COP)",
                       "Variación (COP)"),
                     currency = "$ ", interval = 3, mark = ".") |>
      formatStyle("Señal", backgroundColor = styleEqual("Variación grande", "#FFF3CD"))
  })

  output$tabla_nuevos <- renderDT({
    df <- cambios()$nuevos
    if (!nrow(df)) return(datatable(data.frame(Mensaje = "Sin productos nuevos")))
    df |> transmute(Comercio = comercio, Producto = producto,
                    `Precio (COP)` = round(precio_b),
                    Fecha = substr(fecha_b, 1, 16)) |>
      datatable(options = list(pageLength = 8), rownames = FALSE) |>
      formatCurrency("Precio (COP)", currency = "$ ", interval = 3, mark = ".")
  })

  output$tabla_fuera <- renderDT({
    df <- cambios()$desaparecieron
    if (!nrow(df)) return(datatable(data.frame(Mensaje = "Ningún producto dejó de observarse")))
    df |> transmute(Comercio = comercio, Producto = producto,
                    `Precio (COP)` = round(precio_a),
                    Fecha = substr(fecha_a, 1, 16)) |>
      datatable(options = list(pageLength = 8), rownames = FALSE) |>
      formatCurrency("Precio (COP)", currency = "$ ", interval = 3, mark = ".")
  })

  # =============================================== PESTANA CANASTA
  output$canasta_cantidades <- renderUI({
    ids <- input$canasta_productos
    if (!length(ids)) return(NULL)
    lapply(ids, function(id) {
      numericInput(paste0("cant_", gsub("[^A-Za-z0-9]", "_", id)),
                   label = str_trunc(id, 50), value = 1, min = 1, max = 99, step = 1)
    })
  })

  canasta_resultado <- eventReactive(input$btn_canasta, {
    ids <- input$canasta_productos
    if (!length(ids)) return(list(error = "Seleccione al menos un producto."))
    cant <- setNames(
      vapply(ids, function(id) {
        v <- input[[paste0("cant_", gsub("[^A-Za-z0-9]", "_", id))]]
        if (is.null(v) || is.na(v) || v < 1) 1 else as.numeric(v)
      }, numeric(1)),
      ids)
    ejec <- ejecucion_canasta(con, ids)
    if (is.na(ejec))
      return(list(error = "Ninguna ejecución contiene todos los productos elegidos."))
    por_comercio <- canasta_por_comercio(con, cant, ejec)
    minima <- canasta_minima(con, cant, ejec)
    detalle <- canasta_detalle(con, cant, ejec)
    list(cant = cant, ejecucion = ejec, por_comercio = por_comercio,
         minima = minima, detalle = detalle)
  })

  output$tabla_canasta <- renderTable({
    r <- canasta_resultado()
    if (!is.null(r$error)) return(data.frame(Mensaje = r$error))
    pc <- r$por_comercio
    n_total <- length(r$cant)
    pc$Estado <- ifelse(pc$productos_ok == n_total, "Completa", "Incompleta")
    pc$`Costo total (COP)` <- ifelse(pc$Estado == "Completa",
                                     paste0("$ ", vapply(pc$costo_total, fmt_entero, character(1))),
                                     "No se calcula (faltan productos)")
    pc |> transmute(
      Comercio = comercio,
      Estado = Estado,
      `Costo total (COP)` = `Costo total (COP)`,
      `Fecha de precios` = substr(fecha_consulta, 1, 16)
    )
  }, striped = TRUE)

  output$canasta_aviso <- renderText({
    r <- canasta_resultado()
    if (!is.null(r$error)) return(r$error)
    pc <- r$por_comercio
    n_total <- length(r$cant)
    if (!any(pc$productos_ok == n_total))
      return("Ningún comercio tiene todos los productos en la ejecución elegida; no se muestra un total incompleto.")
    paste0("Precios de la ejecución ", r$ejecucion,
           ". No incluye envío, mínimos de compra ni condiciones de promociones.")
  })

  output$tabla_canasta_min <- renderTable({
    r <- canasta_resultado()
    if (!is.null(r$error) || isTRUE(r$minima$incompleto))
      return(data.frame(Mensaje = if (!is.null(r$error)) r$error else r$minima$motivo))
    pc <- r$por_comercio |> filter(productos_ok == length(r$cant))
    if (!nrow(pc)) return(data.frame(Mensaje = "Sin comercio completo para comparar."))
    mejor <- min(pc$costo_total)
    ahorro <- mejor - r$minima$costo_minimo
    filas <- data.frame(
      Concepto = c("Compra mínima (cada producto donde es más barato)",
                   "Mejor comercio único (todo en un solo comercio)",
                   "Ahorro de comprar por separado"),
      `Valor (COP)` = c(paste0("$ ", fmt_entero(r$minima$costo_minimo)),
                        paste0("$ ", fmt_entero(mejor)),
                        paste0("$ ", fmt_entero(ahorro)))
    )
    filas
  }, striped = TRUE)
}
