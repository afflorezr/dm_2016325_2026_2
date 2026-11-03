paquetes <- c("shiny", "bslib", "DT", "ggplot2")
for (p in paquetes) if (!requireNamespace(p, quietly = TRUE)) install.packages(p)

library(shiny)
library(bslib)
library(ggplot2)
library(DT)

# Cargar los datos
datos_base <- read.csv("saber11.csv")

# Interfaz de Usuario (UI)
ui <- page_sidebar(
  title = "Saber 11: ¿colegio o estrato?",
  theme = bs_theme(bootswatch = "flatly"),
  
  sidebar = sidebar(
    title = "Filtros Globales",
    selectInput("filtro_dep", "Departamento:", 
                choices = c("Todos", unique(datos_base$departamento))),
    checkboxGroupInput("filtro_nat", "Naturaleza:", 
                       choices = unique(datos_base$naturaleza), 
                       selected = unique(datos_base$naturaleza)),
    sliderInput("filtro_estrato", "Estrato:", 
                min = 1, max = 6, value = c(1, 6), step = 1),
    radioButtons("filtro_zona", "Zona:", 
                 choices = c("Todas", "Urbana", "Rural"), selected = "Todas")
  ),
  
  navset_tab(
    # --- PESTAÑA 1: EXPLORAR ---
    nav_panel(
      "Explorar",
      layout_columns(
        value_box(title = "N° Estudiantes (n)", value = textOutput("vb_n")),
        value_box(title = "Media Puntaje", value = textOutput("vb_media")),
        value_box(title = "Mediana Puntaje", value = textOutput("vb_mediana"))
      ),
      card(
        card_header("Distribución del Puntaje según Naturaleza"),
        plotOutput("boxplot_puntaje")
      ),
      card(
        card_header("Tabla de Datos"),
        DTOutput("tabla_datos")
      )
    ),
    
    # --- PESTAÑA 2: MODELO ---
    nav_panel(
      "Modelo",
      sidebarLayout(
        sidebarPanel(
          width = 4,
          checkboxGroupInput("predictores", "Selecciona Predictores:",
                             choices = c("estrato" = "estrato",
                                         "naturaleza" = "naturaleza",
                                         "horas_estudio" = "horas_estudio",
                                         "zona" = "zona"),
                             selected = c("estrato", "naturaleza")),
          actionButton("btn_ajustar", "Ajustar Modelo", class = "btn-primary w-100 mb-2"),
          actionButton("btn_guardar", "Guardar Escenario", class = "btn-secondary w-100"),
          hr(),
          textInput("nombre_escenario", "Nombre del Escenario:", value = "Escenario 1")
        ),
        mainPanel(
          width = 8,
          uiOutput("alerta_na"),
          card(
            card_header("Resultados del Modelo (lm)"),
            verbatimTextOutput("resumen_modelo")
          ),
          card(
            card_header("Historial de Escenarios Guardados"),
            tableOutput("tabla_historial"),
            downloadButton("descargar_historial", "Descargar CSV", class = "btn-success")
          )
        )
      )
    )
  )
)

# Servidor (Server)
server <- function(input, output, session) {
  
  # 1. Reactivo para filtrar datos (Reutilizable)
  datos_filtrados <- reactive({
    df <- datos_base
    
    if (input$filtro_dep != "Todos") {
      df <- df[df$departamento == input$filtro_dep, ]
    }
    
    df <- df[df$naturaleza %in% input$filtro_nat, ]
    df <- df[df$estrato >= input$filtro_estrato[1] & df$estrato <= input$filtro_estrato[2], ]
    
    if (input$filtro_zona != "Todas") {
      df <- df[df$zona == input$filtro_zona, ]
    }
    
    # Control de fallas con validate/need (Validación si no hay datos)
    validate(
      need(nrow(df) > 0, "No hay datos para mostrar con los filtros seleccionados. Por favor ajusta los filtros.")
    )
    
    df
  })
  
  # --- SALIDAS ETAPA 1: EXPLORADOR ---
  output$vb_n <- renderText({ nrow(datos_filtrados()) })
  output$vb_media <- renderText({ round(mean(datos_filtrados()$puntaje, na.rm = TRUE), 1) })
  output$vb_mediana <- renderText({ median(datos_filtrados()$puntaje, na.rm = TRUE) })
  
  output$boxplot_puntaje <- renderPlot({
    validate(
      need(length(unique(datos_filtrados()$naturaleza)) > 0, "Debes seleccionar al menos una naturaleza.")
    )
    ggplot(datos_filtrados(), aes(x = naturaleza, y = puntaje, fill = naturaleza)) +
      geom_boxplot(alpha = 0.7) +
      theme_minimal() +
      labs(x = "Naturaleza del Colegio", y = "Puntaje Saber 11") +
      guides(fill = "none")
  })
  
  output$tabla_datos <- renderDT({
    datatable(datos_filtrados(), options = list(pageLength = 5))
  })
  
  # --- SALIDAS ETAPA 2: MODELO E HISTORIAL ---
  
  # Ajustar modelo únicamente cuando se presiona el botón "Ajustar"
  modelo_fit <- eventReactive(input$btn_ajustar, {
    df <- datos_filtrados()
    
    validate(
      need(length(input$predictores) > 0, "Selecciona al menos un predictor para ajustar el modelo.")
    )
    
    # Evitar error cuando un factor tiene un solo nivel
    if ("naturaleza" %in% input$predictores) {
      validate(
        need(length(unique(df$naturaleza)) > 1, "Para incluir 'naturaleza', debes tener colegios 'Oficial' y 'Privado' en los datos.")
      )
    }
    if ("zona" %in% input$predictores) {
      validate(
        need(length(unique(df$zona)) > 1, "Para incluir 'zona', debes tener colegios de zonas 'Urbana' y 'Rural' en los datos.")
      )
    }
    
    formula_str <- paste("puntaje ~", paste(input$predictores, collapse = " + "))
    mod <- lm(as.formula(formula_str), data = df)
    
    list(modelo = mod, datos = df)
  })
  
  # Aviso de cuántas filas descartó lm() debido a NA
  output$alerta_na <- renderUI({
    fit_data <- modelo_fit()
    mod <- fit_data$modelo
    n_descartados <- length(mod$na.action)
    
    if (n_descartados > 0) {
      div(class = "alert alert-warning", 
          sprintf("Atención: %d filas fueron descartadas por falta de datos (valores NA en predictores).", n_descartados))
    }
  })
  
  output$resumen_modelo <- renderPrint({
    summary(modelo_fit()$modelo)
  })
  
  # Historial usando reactiveValues (nunca usando <<- )
  historial <- reactiveValues(df = data.frame(
    Escenario = character(),
    Coef_Privado = numeric(),
    R2 = numeric(),
    n = integer(),
    stringsAsFactors = FALSE
  ))
  
  observeEvent(input$btn_guardar, {
    fit_data <- modelo_fit()
    mod <- fit_data$modelo
    s <- summary(mod)
    
    coef_priv <- if ("naturalezaPrivado" %in% names(coef(mod))) {
      round(coef(mod)["naturalezaPrivado"], 2)
    } else {
      NA
    }
    
    nuevo_registro <- data.frame(
      Escenario = input$nombre_escenario,
      Coef_Privado = coef_priv,
      R2 = round(s$r.squared, 3),
      n = length(s$residuals)
    )
    
    historial$df <- rbind(historial$df, nuevo_registro)
  })
  
  output$tabla_historial <- renderTable({
    historial$df
  })
  
  # Descarga de Historial
  output$descargar_historial <- downloadHandler(
    filename = function() {
      paste("historial_escenarios_", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      write.csv(historial$df, file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
