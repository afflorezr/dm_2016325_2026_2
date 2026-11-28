# =============================================================================
# app.R — Interfaz y Servidor de la Aplicación (Taller 2)
# =============================================================================

library(shiny)
library(bslib)
library(highcharter)
library(DT)
library(dplyr)
library(DBI)
library(RSQLite)

# Cargamos nuestra capa de datos
source("db.R")

# ---- Interfaz de Usuario (UI) -----------------------------------------------
ui <- page_sidebar(
  title = "Comparador de Precios - D1, Carulla y Olímpica",
  theme = bs_theme(bootswatch = "flatly"), # Un tema limpio y moderno
  
  # Panel lateral (Filtros)
  sidebar = sidebar(
    title = "Filtros",
    selectInput("filtro_comercio", "Comercio:", 
                choices = c("D1", "Carulla", "Olímpica"), 
                selected = c("D1", "Carulla", "Olímpica"), 
                multiple = TRUE),
    checkboxInput("filtro_comparable", "Solo productos comparables", value = FALSE),
    input_task_button("btn_actualizar", "Actualizar Precios (En vivo)", class = "btn-primary")
  ),
  
  # Contenido principal
  navset_card_tab(
    # Pestaña 1: Resumen y Tabla
    nav_panel(
      "Resumen",
      layout_columns(
        value_box(
          title = "Total Productos",
          value = textOutput("kpi_productos"),
          showcase = bsicons::bs_icon("box-seam")
        ),
        value_box(
          title = "Última Actualización",
          value = textOutput("kpi_fecha"),
          showcase = bsicons::bs_icon("calendar-check")
        )
      ),
      card(
        card_header("Tabla de Productos (Últimos Precios)"),
        DTOutput("tabla_precios")
      )
    ),
    
    # Pestaña 2: Gráficos
    nav_panel(
      "Evolución de Precios",
      card(
        card_header("Selecciona un producto para ver su historial"),
        selectInput("select_producto", "Producto:", choices = NULL),
        highchartOutput("grafico_evolucion")
      )
    ),
    
    # Pestaña 3: Canasta
    nav_panel(
      "Canasta",
      card(
        card_header("Arma tu canasta de 8 productos comparables"),
        p("Selecciona la cantidad para cada producto. Si un comercio no tiene todos los productos, no se mostrará un total incompleto."),
        uiOutput("ui_canasta_inputs"),
        hr(),
        h4("Resultados"),
        DTOutput("tabla_canasta_comercios"),
        br(),
        uiOutput("texto_ahorro")
      )
    ),
    
    # Pestaña 4: Análisis y Gráficos
    nav_panel(
      "Análisis",
      layout_columns(
        col_widths = c(6, 6),
        
        # Gráfico 2: Distribución de precios (Boxplot)
        card(
          card_header("Distribución de precios por comercio"),
          highchartOutput("grafico_distribucion")
        ),
        
        # Gráfico 3: Promociones
        card(
          card_header("Porcentaje de productos en promoción"),
          highchartOutput("grafico_promociones")
        )
      ),
      br(),
      # Sección de Cambios de Precio (Módulo 6)
      card(
        card_header("Cambios de Precio entre las dos últimas ejecuciones"),
        p("Comparación de los mismos productos (mismo SKU) en el mismo comercio."),
        DTOutput("tabla_cambios")
      )
    )
  )
)

# ---- Servidor (Lógica) --------------------------------------------------------
server <- function(input, output, session) {
  
  # Conexión a la base de datos (se abre una vez y se cierra al salir)
  con <- conectar_db()
  onStop(function() dbDisconnect(con))
  
  
  # =========================================================================
  # MÓDULO 2: Tarea asíncrona para el botón de Actualizar
  # =========================================================================
  
  tarea_scraper <- ExtendedTask$new(function() {
    future_promise({
      source("scraper.R", local = TRUE) 
      
      # Para pruebas, usamos el modo offline (es más rápido)
      resumen <- ejecutar_recoleccion(offline = TRUE, id_ejecucion = "20261116T180941")
      
      return(resumen)
    })
  }) |> bind_task_button("btn_actualizar") 
  
  observeEvent(input$btn_actualizar, {
    tarea_scraper$invoke()
  })

  
  observeEvent(tarea_scraper$status(), {
    if (tarea_scraper$status() == "success") {
      resumen <- tarea_scraper$result()
      
      # AQUÍ ESTÁ EL MODAL (La ventana emergente)
      showModal(modalDialog(
        title = "¡Actualización Completada!",
        p("Aquí está el resumen de la recolección:"),
        renderTable(resumen),
        easyClose = TRUE,
        footer = modalButton("Cerrar")
      ))
      
    } else if (tarea_scraper$status() == "error") {
      showNotification("Hubo un error al intentar actualizar. Revisa la consola.", type = "error")
    }
  })
  
  # Cargar los productos comparables en el selector de la pestaña de gráficos
  observe({
    df_prod <- obtener_productos_comparables(con)
    opciones <- setNames(df_prod$id_producto, df_prod$nombre_std)
    updateSelectInput(session, "select_producto", choices = opciones)
  })
  
  # Reactive para obtener los datos filtrados de la tabla
  datos_tabla <- reactive({
    obtener_ultimos_precios(
      con, 
      comercios_filtro = input$filtro_comercio,
      solo_comparables = input$filtro_comparable
    )
  })
  
  # KPIs
  output$kpi_productos <- renderText({
    nrow(datos_tabla())
  })
  
  output$kpi_fecha <- renderText({
    # Sacamos solo la fecha de la última consulta
    fecha <- max(datos_tabla()$fecha_hora_consulta)
    substr(fecha, 1, 10)
  })
  
  # Renderizar la tabla
  output$tabla_precios <- renderDT({
    datatable(
      datos_tabla() |> select(comercio, nombre_original, precio, disponible, fecha_hora_consulta),
      options = list(pageLength = 10, scrollX = TRUE),
      rownames = FALSE
    )
  })
  
  # Gráfico de evolución
  output$grafico_evolucion <- renderHighchart({
    req(input$select_producto)
    df_graf <- obtener_evolucion_precio(con, input$select_producto)
    
    if (nrow(df_graf) == 0) return(highchart() |> hc_title(text = "Sin datos"))
    
    # Convertimos la fecha a formato Date para el gráfico
    df_graf$fecha_hora_consulta <- as.POSIXct(df_graf$fecha_hora_consulta, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota")
    
    hchart(df_graf, "line", hcaes(x = fecha_hora_consulta, y = precio, group = comercio)) |>
      hc_title(text = "Historial de Precios") |>
      hc_yAxis(title = list(text = "Precio (COP)"))
  })
  
  # ---- Lógica de la Canasta ----
  
  # Generar los inputs de cantidad dinámicamente
  output$ui_canasta_inputs <- renderUI({
    df_prod <- obtener_productos_comparables(con)
    inputs <- lapply(seq_len(nrow(df_prod)), function(i) {
      numericInput(
        inputId = paste0("cant_", df_prod$id_producto[i]),
        label = df_prod$nombre_std[i],
        value = 1, min = 0, step = 1
      )
    })
    # Los ponemos en un layout de columnas para que no quede una lista larguísima
    layout_columns(col_widths = c(4, 4, 4), !!!inputs)
  })
  
  # Calcular la canasta de forma reactiva
  datos_canasta <- reactive({
    df_prod <- obtener_productos_comparables(con)
    cantidades <- c()
    
    for (id in df_prod$id_producto) {
      val <- input[[paste0("cant_", id)]]
      if (!is.null(val) && val > 0) {
        cantidades[id] <- val
      }
    }
    
    if (length(cantidades) == 0) return(NULL)
    
    calcular_canasta(con, cantidades)
  })
  
  # Renderizar la tabla de resultados por comercio
  output$tabla_canasta_comercios <- renderDT({
    res <- datos_canasta()
    req(res)
    
    df_mostrar <- res$resumen_comercios
    # Formatear los precios
    df_mostrar$costo_total <- ifelse(
      is.na(df_mostrar$costo_total), 
      "Faltan productos", 
      paste0("$ ", format(df_mostrar$costo_total, big.mark = ".", decimal.mark = ",", nsmall = 0))
    )
    
    datatable(df_mostrar, 
              options = list(dom = 't', ordering = FALSE), 
              rownames = FALSE,
              colnames = c("Comercio", "Costo Total", "¿Tiene todo?"))
  })
  
  # Texto de ahorro mínimo
  output$texto_ahorro <- renderUI({
    res <- datos_canasta()
    req(res)
    
    # Encontrar el comercio más barato (solo entre los completos)
    completos <- res$resumen_comercios[res$resumen_comercios$completo == TRUE, ]
    
    if (nrow(completos) > 0) {
      mejor_comercio <- completos[which.min(completos$costo_total), ]
      ahorro <- mejor_comercio$costo_total - res$costo_minimo
      
      tagList(
        h5(strong(paste("El lugar más barato para comprar todo:", mejor_comercio$comercio))),
        p(paste0("Costo total en un solo comercio: $ ", format(mejor_comercio$costo_total, big.mark = "."))),
        h5(strong(paste("Costo mínimo comprando en diferentes comercios: $ ", format(res$costo_minimo, big.mark = ".")))),
        p(strong(paste0("¡Ahorro comprando inteligentemente: $ ", format(ahorro, big.mark = "."))), style = "color: #2e7d32;")
      )
    } else {
      p("Ningún comercio tiene todos los productos seleccionados en este momento.", style = "color: red;")
    }
  })
  # =========================================================================
  # MÓDULO 5 Y 6: Gráficos y Cambios de Precio
  # =========================================================================
  
  # Gráfico de Distribución (Boxplot)
  output$grafico_distribucion <- renderHighchart({
    df <- obtener_distribucion_precios(con)
    
    # Filtramos nulos y ceros
    df <- df |> filter(!is.na(precio), precio > 0)
    req(nrow(df) > 0)
    
    # Gráfico de dispersión (scatter)
    hchart(df, "scatter", hcaes(x = comercio, y = precio, group = comercio)) |>
      hc_title(text = "Distribución de Precios (COP)") |>
      hc_yAxis(title = list(text = "Precio (COP)")) |>
      hc_xAxis(title = list(text = "Comercio")) |>
      hc_colors(c("#007bff", "#28a745", "#ffc107")) |>
      hc_tooltip(pointFormat = "<b>{point.comercio}</b><br/>Precio: ${point.y:,.0f} COP")
  })
  
  # Gráfico de Promociones (Barras apiladas)
  output$grafico_promociones <- renderHighchart({
    df <- obtener_promociones_por_comercio(con)
    req(nrow(df) > 0)
    
    # Calculamos los que NO están en promoción
    df$sin_promocion <- df$total_productos - df$en_promocion
    
    # Preparamos los datos para Highcharter
    df_long <- data.frame(
      comercio = rep(df$comercio, 2),
      tipo = c(rep("En promoción", nrow(df)), rep("Sin promoción", nrow(df))),
      cantidad = c(df$en_promocion, df$sin_promocion)
    )
    
    hchart(df_long, "column", hcaes(x = comercio, y = cantidad, group = tipo)) |>
      hc_title(text = "Productos en promoción vs. regulares") |>
      hc_yAxis(title = list(text = "Cantidad de productos")) |>
      hc_colors(c("#2e7d32", "#9e9e9e")) # Verde para promo, gris para normal
  })
  
  # Tabla de Cambios de Precio
  output$tabla_cambios <- renderDT({
    df <- obtener_cambios_recientes(con)
    
    if (nrow(df) == 0) {
      return(datatable(data.frame(Mensaje = "No hay dos ejecuciones en fechas distintas para comparar.")))
    }
    
    # Formateamos los números para que se vean bonitos
    df$precio_anterior <- paste0("$ ", format(df$precio_anterior, big.mark = ".", decimal.mark = ","))
    df$precio_actual <- paste0("$ ", format(df$precio_actual, big.mark = ".", decimal.mark = ","))
    
    # Agregamos flechas de subida/bajada
    df$tendencia <- ifelse(df$diferencia_absoluta > 0, "🔺 Subió", 
                           ifelse(df$diferencia_absoluta < 0, "🔻 Bajó", "➖ Igual"))
    
    df_mostrar <- df |> 
      select(comercio, nombre_original, precio_anterior, precio_actual, tendencia, diferencia_pct) |>
      rename(
        Comercio = comercio,
        Producto = nombre_original,
        Anterior = precio_anterior,
        Actual = precio_actual,
        Cambio = tendencia,
        `% Variación` = diferencia_pct
      )
    
    datatable(df_mostrar, 
              options = list(pageLength = 10, scrollX = TRUE),
              rownames = FALSE,
              caption = "Cambios ordenados por diferencia absoluta (de mayor a menor)")
  })
}

# Ejecutar la app
shinyApp(ui, server)
