# server.R
# server.R
library(shiny)
library(dplyr)
library(DT)
library(glue)
library(promises)
library(future)
library(bslib)
library(highcharter)
library(tidyr)
library(DBI)
library(RSQLite)

source("db.R")
plan(multisession)

server <- function(input, output, session) {



  trigger_actualizacion <- reactiveVal(0)
  
  # --- 1. LÓGICA DEL BOTÓN DE ACTUALIZACIÓN ---
  
  # 1. Definimos la tarea (Asegúrate de que esta variable quede en la raíz del server)
  tarea_scraping <- ExtendedTask$new(function(modo_offline, max_paginas) {
    future_promise({
      source("scraper.R", local = TRUE)
      resumen <- ejecutar_pipeline(modo_ejecucion_offline = modo_offline, max_pag = max_paginas)
      return(resumen)
    })
  }) |> bind_task_button("btn_actualizar")
  
  observeEvent(input$btn_actualizar, {
    modo <- isTRUE(input$modo_offline)
    showNotification(
      if (modo) "Reprocesando copias locales en raw/..." else "Iniciando extracción en línea en segundo plano...",
      type = "warning", duration = 8
    )
    tarea_scraping$invoke(modo_offline = modo, max_paginas = 60)
  })
  
  observeEvent(tarea_scraping$status, {
    estado_actual <- tarea_scraping$status()
    
    if (estado_actual == "success") {
      showNotification("¡Actualización exitosa! Revisa el resumen por comercio.",
                       type = "message", duration = 10)
      trigger_actualizacion(isolate(trigger_actualizacion()) + 1)
    } else if (estado_actual == "error") {
      error_msg <- tarea_scraping$error()$message
      showNotification(
        paste("Error durante la extracción:", error_msg,
              "| Si estás en el servidor publicado, activa 'Modo sin conexión (raw/)'."),
        type = "error", duration = NULL
      )
    }
  }, ignoreInit = TRUE)
  
  output$resumen_scraping <- renderTable({
    req(tarea_scraping$status() == "success")
    tarea_scraping$result()
  })
  
  
  # 3. Escuchar los cambios de ESTADO de la tarea de forma segura
  observeEvent(tarea_scraping$status, {
    estado_actual <- tarea_scraping$status()
    
    if (estado_actual == "success") {
      # 3.1 Mensaje de éxito
      showNotification("¡Actualización exitosa! Los datos nuevos ya están en la base de datos.", 
                       type = "message", duration = 10)
      
      # 3.2 Forzamos la actualización usando isolate() para evitar el bucle infinito
      nuevo_valor <- isolate(trigger_actualizacion()) + 1
      trigger_actualizacion(nuevo_valor)
      
    } else if (estado_actual == "error") {
      # 3.3 Mensaje de error
      error_msg <- tarea_scraping$error()$message
      showNotification(paste("Error durante la extracción:", error_msg), 
                       type = "error", duration = NULL)
    }
    
  }, ignoreInit = TRUE)
  
  # --- 2. TABLA: ÚLTIMOS PRECIOS (Consulta parametrizada) ---
  observe({
    trigger_actualizacion()
    opts <- obtener_opciones_filtros()
    updateSelectizeInput(session, "filtro_marca", choices = opts$marcas, server = TRUE)
    updateCheckboxGroupInput(session, "filtro_mascota", choices = opts$mascotas, selected = opts$mascotas)
  
    df_ej <- obtener_ejecuciones()
    opciones_ej <- setNames(c("Todos", df_ej$id_ejecucion), c("Todos", df_ej$fecha_inicio))
    updateSelectInput(session, "filtro_ejecucion", choices = opciones_ej)
    })

  datos_precios <- reactive({
    trigger_actualizacion()
    req(length(input$filtro_comercio) > 0) 
    req(length(input$rango_fechas) == 2)
    req(input$filtro_ejecucion)
    
    obtener_precios_filtrados(
      comercios_seleccionados = input$filtro_comercio,
      marcas_sel = input$filtro_marca,
      mascotas_sel = input$filtro_mascota,
      texto_busqueda = input$filtro_texto,
      precio_min = input$filtro_precio[1], 
      precio_max = input$filtro_precio[2],
      fecha_inicio = as.character(input$rango_fechas[1]),
      fecha_fin = as.character(input$rango_fechas[2]),
      ejecucion_sel = input$filtro_ejecucion
    )
  })
  
  # --- 4. INDICADORES EN TARJETAS VALUE_BOX---
  output$tarjetas_indicadores <- renderUI({
    trigger_actualizacion()
    ind <- obtener_indicadores()
    
    tagList(
      # Fila 1: Métricas de Mercado
      layout_columns(
        col_widths = c(4, 4, 4),
        value_box(
          title = "Productos Homologados",
          value = ind$n_comparables,
          showcase = icon("tags"),
          theme = "primary",
          p(ind$desglose_comercios, class = "small mb-0 fw-medium")
        ),
        value_box(
          title = "Comercio Más Económico",
          value = ind$comercio_economico,
          showcase = icon("trophy"),
          theme = "success",
          p(ind$prom_economico, class = "small mb-0 fw-medium")
        ),
        value_box(
          title = "Ahorro Potencial Promedio",
          value = paste0(ind$ahorro_promedio, "%"),
          showcase = icon("piggy-bank"),
          theme = "info",
          p(paste0("Equivale a $", ind$ahorro_pesos, " COP por producto"), class = "small mb-0 fw-medium")
        )
      ),
      br(),
      # Fila 2: Métricas de Infraestructura y Trazabilidad
      layout_columns(
        col_widths = c(4, 4, 4),
        value_box(
          title = "Registros Históricos",
          value = format(ind$n_historial, big.mark = "."),
          showcase = icon("database"),
          theme = "secondary",
          p(paste0("Sobre ", ind$n_anuncios_tot, " anuncios rastreados"), class = "small mb-0 fw-medium")
        ),
        value_box(
          title = "Ejecuciones del Scraper",
          value = ind$n_ejecuciones,
          showcase = icon("robot"),
          theme = "warning",
          p(paste0("Monitoreo activo desde ", ind$primera_fecha), class = "small mb-0 fw-medium")
        ),
        value_box(
          title = "Última Actualización",
          value = ind$ultima_fecha,
          showcase = icon("clock"),
          theme = "dark",
          p(paste0("Cobertura de ", ind$n_marcas, " marcas comparables"), class = "small mb-0 fw-medium")
        )
      ),
      br(),
      # Fila 3: Panel de Movimientos de Precio (Última vs Penúltima corrida)
      div(
        class = "card bg-white",
        div(
          class = "card-header fw-bold text-primary d-flex justify-content-between align-items-center",
          span(icon("arrow-trend-up", class = "me-2"), "Dinámica de Precios (Última ejecución vs. anterior)"),
          span(class = "badge bg-light text-dark border", paste0("Período: ", ind$ultima_fecha))
        ),
        div(
          class = "card-body py-3",
          fluidRow(
            column(4, class = "text-center border-end",
                   h3(class = "fw-bold text-danger mb-0", ind$subidas),
                   span(class = "text-muted small", icon("arrow-up"), " Subieron de precio")),
            column(4, class = "text-center border-end",
                   h3(class = "fw-bold text-success mb-0", ind$bajadas),
                   span(class = "text-muted small", icon("arrow-down"), " Bajaron de precio")),
            column(4, class = "text-center",
                   h3(class = "fw-bold text-secondary mb-0", ind$iguales),
                   span(class = "text-muted small", icon("minus"), " Sin variación"))
          )
        )
      )
    )
  })
  
  output$tabla_precios <- renderDT({
    df <- datos_precios()
    names(df) <- tolower(names(df))
    if (nrow(df) > 0) {
      
      comercio_txt <- tolower(trimws(as.character(df$comercio)))
      anuncio_txt <- as.character(df$id_anuncio)
      
      
      base_url <- ifelse(comercio_txt == "exito", "https://www.exito.com",
                         ifelse(comercio_txt == "jumbo", "https://www.tiendasjumbo.co",
                                ifelse(comercio_txt == "olimpica", "https://www.olimpica.com", "")))
      
      
      df$enlace <- ifelse(
        base_url != "",
        paste0('<a href="', base_url, anuncio_txt, '" target="_blank" style="color:#0d6efd; font-weight:500; text-decoration:underline;">ver anuncio</a>'),
        "No disponible"
      )
    } else {
      # Aseguramos que la columna exista incluso si la tabla filtrada queda con 0 filas
      df$enlace <- character(0)
    }
    datatable(df,
              options = list(pageLength = 10, scrollX = TRUE),
              escape = FALSE,
              rownames = FALSE,
              colnames = c("ID Homologado", "Anuncio", "Comercio", "Marca", 
                           "Descripción Original", "Presentación", "Precio Etiqueta", 
                           "Precio x Unidad", "Fecha Consulta", "ID Ejecución")) %>%
      formatCurrency(c("precio", "precio_x_und"), currency = "$", interval = 0, mark = ".")
  })
  ######################################3
  # --- BOTÓN DESCARGA CSV  ---
  output$btn_descargar_csv <- downloadHandler(
    filename = function() {
      paste0("comparador_precios_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(datos_precios(), file, row.names = FALSE, fileEncoding = "UTF-8")
    }
  )
  
  # --- 3. TABLA: VARIACIONES DE MERCADO (MÓDULO 6.2) ---
  
  # Poblar selectores de ejecuciones (por defecto: última vs penúltima)
  observe({
    trigger_actualizacion()
    df_ej <- obtener_ejecuciones()
    req(nrow(df_ej) > 0)
    
    opciones <- setNames(df_ej$id_ejecucion, paste0("Ejecución #", df_ej$id_ejecucion, " (", df_ej$fecha_inicio, ")"))
    
    sel_actual <- df_ej$id_ejecucion[1]
    sel_anterior <- if (nrow(df_ej) >= 2) df_ej$id_ejecucion[2] else df_ej$id_ejecucion[1]
    
    updateSelectInput(session, "ejecucion_actual", choices = opciones, selected = sel_actual)
    updateSelectInput(session, "ejecucion_anterior", choices = opciones, selected = sel_anterior)
  })
  
  datos_cambios <- reactive({
    req(input$ejecucion_anterior, input$ejecucion_actual, length(input$filtro_comercio) > 0)
    
    df <- comparar_ejecuciones(
      id_anterior = input$ejecucion_anterior,
      id_actual = input$ejecucion_actual,
      comercios_seleccionados = input$filtro_comercio
    )
    
    # Filtrar por el umbral absoluto de cambio porcentual elegido por el usuario
    umbral <- as.numeric(input$umbral_cambio_pct)
    df <- df[abs(df$diff_pct) >= umbral, ]
    return(df)
  })
  
  output$tabla_cambios <- renderDT({
    df_cambios <- datos_cambios()
    
    datatable(df_cambios,
              options = list(pageLength = 10, scrollX = TRUE),
              rownames = FALSE,
              colnames = c("ID Homologado", "Comercio", "Producto", "Precio Anterior", 
                           "Precio Nuevo", "Variación ($)", "Variación (%)", "Estado")) %>%
      formatCurrency(c("precio_viejo", "precio_nuevo", "diff_pesos"), currency = "$", interval = 3, mark = ".", digits = 0) %>%
      formatStyle(
        'estado_cambio',
        target = 'row',
        backgroundColor = styleEqual(
          c('Subió', 'Bajó', 'Sin cambio'), 
          c('#ffe6e6', '#e6ffe6', '#ffffff')
        )
      )
  })
  
  # --- 4. INDICADORES ---
  output$resumen_indicadores <- renderPrint({
    trigger_actualizacion()
    obtener_indicadores()
  })
  
  # --- 5. GRÁFICO 1: EVOLUCIÓN DE PRECIOS ---
  
  # Cargar la lista de productos en el selector (dropdown) al iniciar
  observe({
    lista_prods <- obtener_lista_comparables()
    # Creamos una lista nombrada para que el usuario vea el nombre amigable pero el sistema use el ID
    opciones <- setNames(lista_prods$id_homologado, lista_prods$nombre_amigable)
    updateSelectInput(session, "producto_elegido", choices = opciones)
  })
  
  # Generar el gráfico interactivo con highcharter
  output$grafico_evolucion <- renderHighchart({
    req(input$producto_elegido) 
    
    df_hist <- obtener_historico_producto(
      input$producto_elegido,
      fecha_inicio = as.character(input$rango_fechas[1]),
      fecha_fin = as.character(input$rango_fechas[2])
    )
    req(nrow(df_hist) > 0)
    
    # 1. Asegurar formato numérico
    df_hist$precio <- as.numeric(df_hist$precio)
    
    # 2. Extraer solo los 10 primeros caracteres (ej: "2026-11-13") y convertir a timestamp
    texto_fecha <- substr(df_hist$fecha_consulta, 1, 19)
    df_hist$fecha_hora <- as.POSIXct(texto_fecha, format="%Y-%m-%dT%H:%M:%S")
    df_hist$fecha_ts <- datetime_to_timestamp(df_hist$fecha_hora)
    
    # 3. Limpiar NAs
    df_hist <- df_hist[!is.na(df_hist$fecha_ts) & !is.na(df_hist$precio), ]
    req(nrow(df_hist) > 0) 
    
    # 4. Dibujar (¡Notar el group = Comercio y {point.Comercio} con C mayúscula!)
    hchart(df_hist, type = "line", hcaes(x = fecha_ts, y = precio, group = Comercio)) %>%
      hc_title(text = "Evolución temporal por supermercado") %>%
      hc_xAxis(type = "datetime", title = list(text = "Fecha de Extracción")) %>%
      hc_yAxis(title = list(text = "Precio (COP)"),
               labels = list(format = "${value:,.0f}")) %>%
      hc_tooltip(pointFormat = "<b>{point.Comercio}</b>: ${point.precio:,.0f}<br/>") %>%
      hc_colors(c("#E50000", "#006400", "#00008B"))
  })
  
  # --- GRÁFICO 2: PRECIO UNITARIO ---
  
  # Llenar el selector de la pestaña de Precio Unitario
  observe({
    lista_prods <- obtener_lista_comparables()
    opciones <- setNames(lista_prods$id_homologado, lista_prods$nombre_amigable)
    updateSelectInput(session, "prod_unitario_elegido", choices = opciones)
  })
  
  # Renderizar el gráfico de barras
  output$grafico_unitario <- renderHighchart({
    req(input$prod_unitario_elegido)
    
    df_unit <- obtener_ultimo_precio_unitario(input$prod_unitario_elegido)
    req(nrow(df_unit) > 0)
    
    # Asegurar que sea numérico
    df_unit$precio_u <- as.numeric(df_unit$precio_u)
    
    # Crear gráfico de barras (column)
    hchart(df_unit, type = "column", hcaes(x = Comercio, y = precio_u, color = Comercio)) %>%
      hc_title(text = "Costo por unidad de medida (Último precio registrado)") %>%
      hc_xAxis(title = list(text = "Supermercado")) %>%
      hc_yAxis(title = list(text = "Precio Unitario (COP)"),
               labels = list(format = "${value:,.2f}")) %>%
      hc_tooltip(pointFormat = "<b>{point.Comercio}</b>: ${point.precio_u:,.2f} por unidad<br/>") %>%
      hc_colors(c("#E50000", "#006400", "#00008B")) # Rojo Exito, Verde Jumbo, Azul Olimpica
  })
  
  # --- GRÁFICO 3: DISTRIBUCIÓN DE PRECIOS (BOXPLOT CON MAPEO DIRECTO) ---
  
  output$grafico_distribucion <- renderHighchart({
    df_dist <- datos_precios()
    names(df_dist) <- tolower(names(df_dist))
    df_dist$Comercio <- df_dist$comercio
    req(nrow(df_dist) > 0)
    
    # 1. Limpieza básica
    df_dist$precio <- as.numeric(df_dist$precio)
    df_dist$Comercio <- as.character(df_dist$Comercio)
    df_dist <- df_dist[!is.na(df_dist$precio) & !is.na(df_dist$Comercio) & df_dist$precio > 0, ]
    req(nrow(df_dist) > 0)
    
    # 2. Calcular los valores exactos nombrando las columnas como Highcharter las exige
    cajas <- df_dist %>%
      dplyr::group_by(Comercio) %>%
      dplyr::summarise(
        low = min(precio, na.rm = TRUE),
        q1 = quantile(precio, 0.25, na.rm = TRUE),
        median = median(precio, na.rm = TRUE),
        q3 = quantile(precio, 0.75, na.rm = TRUE),
        high = max(precio, na.rm = TRUE),
        .groups = 'drop'
      )
    
    # 3. Dibujar usando hcaes para mapear las columnas directamente
    highchart() %>%
      hc_chart(type = "boxplot") %>%
      hc_title(text = "Distribución de toda la categoría (Última extracción)") %>%
      hc_xAxis(type = "category", title = list(text = "Supermercado")) %>%
      hc_yAxis(title = list(text = "Precio Etiqueta (COP)"),
               labels = list(format = "${value:,.0f}")) %>%
      hc_add_series(
        data = cajas,
        type = "boxplot",
        name = "Distribución de Precios",
        # Aquí ocurre la magia: le decimos a la gráfica qué columna es qué valor
        hcaes(x = Comercio, low = low, q1 = q1, median = median, q3 = q3, high = high),
        colorByPoint = TRUE
      ) %>%
      hc_colors(c("#E50000", "#006400", "#00008B"))
  })
  # --- GRÁFICO 4: PARTICIPACIÓN DE MARCAS (DONA) ---
  
  output$grafico_marcas <- renderHighchart({
    df_base <- datos_precios()
    req(nrow(df_base) > 0)
    names(df_base) <- tolower(names(df_base))
    df_marcas <- df_base %>%
      dplyr::group_by(marca) %>%
      dplyr::summarise(cantidad = dplyr::n_distinct(id_homologado), .groups = "drop") %>%
      dplyr::arrange(dplyr::desc(cantidad))
    
    # Aseguramos tipos de datos limpios
    df_marcas$cantidad <- as.numeric(df_marcas$cantidad)
    
    # Dibujamos un gráfico circular (pie) con un hueco en el medio (innerSize) para que sea Dona
    highchart() %>%
      hc_chart(type = "pie") %>%
      hc_title(text = "Participación de Marcas en el Mercado Analizado") %>%
      hc_add_series(
        data = df_marcas, 
        type = "pie",
        name = "Cantidad de Productos",
        hcaes(name = marca, y = cantidad),
        innerSize = "60%", # Esto lo convierte en dona
        dataLabels = list(enabled = TRUE, format = "<b>{point.name}</b>: {point.percentage:.1f} %")
      ) %>%
      # Tema de colores variados para que se vea genial
      hc_colors(c("#2C3E50", "#E74C3C", "#3498DB", "#F39C12", "#1ABC9C", "#9B59B6"))
  })
  # --- LÓGICA DE CANASTA ---
  
  # 1. Poblar el selector de productos para la canasta
  observe({
    lista_prods <- obtener_lista_comparables()
    opciones <- setNames(lista_prods$id_homologado, lista_prods$nombre_amigable)
    updateSelectizeInput(session, "canasta_productos", choices = opciones, server = TRUE)
  })
  
  # 2. Generar dinámicamente los campos de cantidad por cada producto elegido
  output$ui_cantidades_canasta <- renderUI({
    req(input$canasta_productos)
    lista_prods <- obtener_lista_comparables()
    
    inputs_lista <- lapply(input$canasta_productos, function(id_p) {
      nombre_p <- lista_prods$nombre_amigable[lista_prods$id_homologado == id_p][1]
      numericInput(
        inputId = paste0("cant_", id_p),
        label = paste("Cantidad para:", nombre_p),
        value = 1, min = 1, max = 50, step = 1
      )
    })
    
    tagList(
      strong("2. Define las cantidades:"),
      br(), br(),
      inputs_lista
    )
  })
  
  # 3. Calcular costos por comercio y canasta óptima
  calculo_canasta <- reactive({
    req(length(input$canasta_productos) > 0)
    trigger_actualizacion()
    
    ids <- as.character(input$canasta_productos)
    df_precios <- obtener_precios_canasta(ids)
    req(nrow(df_precios) > 0)
    
    # Estandarizar todos los nombres de columnas a minúsculas para evitar errores de mayúsculas
    names(df_precios) <- tolower(names(df_precios))
    
    # Construir tabla de cantidades ingresadas por el usuario
    cantidades <- sapply(ids, function(id_p) {
      val <- input[[paste0("cant_", id_p)]]
      if (is.null(val) || is.na(val) || val < 1) 1 else as.numeric(val)
    })
    df_cant <- data.frame(id_homologado = ids, cantidad = as.numeric(cantidades), stringsAsFactors = FALSE)
    
    # Unir precios con cantidades y calcular subtotal por ítem
    df_calc <- df_precios %>%
      dplyr::mutate(
        comercio = as.character(comercio),
        precio = as.numeric(precio)
      ) %>%
      dplyr::inner_join(df_cant, by = "id_homologado") %>%
      dplyr::mutate(subtotal = precio * cantidad)
    
    # A) Costo mínimo comprando cada producto donde sea más barato
    optimo_por_prod <- df_calc %>%
      dplyr::group_by(id_homologado, producto, cantidad) %>%
      dplyr::summarise(min_subtotal = min(subtotal, na.rm = TRUE), .groups = "drop")
    
    costo_minimo <- sum(optimo_por_prod$min_subtotal, na.rm = TRUE)
    
    # B) Costo por comercio (validando completitud de la canasta)
    todos_comercios <- sort(unique(df_calc$comercio))
    n_req <- length(ids)
    
    lista_filas <- lapply(todos_comercios, function(com) {
      sub_com <- df_calc[df_calc$comercio == com, , drop = FALSE]
      n_encontrados <- length(unique(sub_com$id_homologado))
      
      if (n_encontrados < n_req) {
        data.frame(
          Comercio = com,
          Estado = paste0("Incompleta (Faltan ", n_req - n_encontrados, " producto(s))"),
          Total_COP = NA_real_,
          Ahorro_vs_Unico = NA_real_,
          stringsAsFactors = FALSE
        )
      } else {
        sub_unico <- sub_com %>%
          dplyr::group_by(id_homologado) %>%
          dplyr::summarise(sub_min = min(subtotal, na.rm = TRUE), .groups = "drop")
        
        total_com <- sum(sub_unico$sub_min, na.rm = TRUE)
        data.frame(
          Comercio = com,
          Estado = "Canasta completa",
          Total_COP = total_com,
          Ahorro_vs_Unico = total_com - costo_minimo,
          stringsAsFactors = FALSE
        )
      }
    })
    
    resumen_comercios <- if (length(lista_filas) > 0) {
      do.call(rbind, lista_filas)
    } else {
      data.frame(
        Comercio = character(),
        Estado = character(),
        Total_COP = numeric(),
        Ahorro_vs_Unico = numeric(),
        stringsAsFactors = FALSE
      )
    }
    
    list(
      costo_minimo = costo_minimo,
      comercios = resumen_comercios
    )
  })
  
  # 4. Mostrar tarjeta de resumen óptimo
  output$resumen_canasta_optima <- renderUI({
    res <- calculo_canasta()
    mejor_unico <- min(res$comercios$Total_COP, na.rm = TRUE)
    ahorro_max <- if (is.finite(mejor_unico)) mejor_unico - res$costo_minimo else 0
    
    div(class = "card bg-light mb-3",
        div(class = "card-body",
            h5(class = "card-title text-success", "Canasta Óptima (Comprando cada producto donde es más barato)"),
            p(class = "card-text fs-4", 
              strong("Costo Mínimo Total: "), 
              paste0("$", format(res$costo_minimo, big.mark = ".", decimal.mark = ",")), " COP"),
            if (is.finite(mejor_unico)) {
              p(class = "text-muted mb-0",
                paste0("Ahorro de $", format(ahorro_max, big.mark = ".", decimal.mark = ","), 
                       " COP frente a la mejor opción de un solo supermercado."))
            }
        )
    )
  })
  
  # 5. Renderizar tabla comparativa por comercio
  output$tabla_canasta_comercios <- renderDT({
    res <- calculo_canasta()
    datatable(res$comercios,
              options = list(dom = 't', ordering = FALSE),
              rownames = FALSE,
              colnames = c("Supermercado", "Disponibilidad de Canasta", "Costo Total (COP)", "Sobrecosto vs Óptimo (COP)")) %>%
      formatCurrency(c("Total_COP", "Ahorro_vs_Unico"), currency = "$", interval = 3, mark = ".", digits = 0)
    })
}
