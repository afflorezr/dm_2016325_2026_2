# ==============================================================================
# TALLER PRÁCTICO: CLASE 05 - MINERÍA DE DATOS
# TEMA: Aplicaciones Web Interactivas y Dashboards con R Shiny
# AUTOR: Inti A. Olaya
# INSTITUCIÓN: Universidad Nacional de Colombia
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. INSTALACIÓN Y CARGA DE LIBRERÍAS
# ------------------------------------------------------------------------------
paquetes <- c("shiny", "tidyverse", "bslib", "DT", "plotly")
paquetes_faltantes <- paquetes[!(paquetes %in% installed.packages()[, "Package"])]
if (length(paquetes_faltantes) > 0) {
  install.packages(paquetes_faltantes)
}

library(shiny)
library(tidyverse)
library(bslib)
library(DT)
library(plotly)

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DE DATOS SIMULADOS (GLOBAL / PASO 0)
# ------------------------------------------------------------------------------
# Simulación del dataset Saber 11 / Rendimiento Académico
set.seed(1111)
n <- 1500
departamentos <- c("Bogotá", "Antioquia", "Valle del Cauca", "Boyacá", "Chocó")
departamento <- sample(departamentos, n, replace = TRUE, prob = c(0.30, 0.25, 0.20, 0.15, 0.10))
p_rural <- c(0.05, 0.25, 0.25, 0.40, 0.50)[match(departamento, departamentos)]
zona <- ifelse(runif(n) < p_rural, "Rural", "Urbana")
estrato <- ifelse(zona == "Rural", sample(1:3, n, replace = TRUE), sample(1:6, n, replace = TRUE, prob = c(0.15, 0.30, 0.28, 0.15, 0.07, 0.05)))
naturaleza <- ifelse(runif(n) < plogis(-3.2 + 0.75 * estrato), "Privado", "Oficial")
horas_estudio <- round(pmax(0, rnorm(n, 5 + 0.5 * estrato, 2)), 1)
puntaje <- round(200 + 14 * estrato + 12 * (naturaleza == "Privado") + 4 * horas_estudio - 15 * (zona == "Rural") + rnorm(n, 0, 30))
horas_estudio[sample(n, 60)] <- NA # 60 valores faltantes simulados

datos_saber11 <- tibble(
  departamento = factor(departamento),
  zona = factor(zona),
  estrato = as.integer(estrato),
  naturaleza = factor(naturaleza),
  horas_estudio = horas_estudio,
  puntaje = puntaje
)

# ------------------------------------------------------------------------------
# 3. DEFINICIÓN DE LA INTERFAZ DE USUARIO (UI)
# ------------------------------------------------------------------------------
ui <- fluidPage(
  theme = bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = "#1d4ed8",
    secondary = "#64748b"
  ),
  
  titlePanel(
    div(
      h2("Dashboard Interactivo Saber 11 - Minería de Datos", style = "font-weight: bold;"),
      h5("Autor: Inti A. Olaya | Universidad Nacional de Colombia", style = "color: #64748b;")
    )
  ),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("Filtros del Dataset"),
      selectInput(
        inputId = "depto",
        label = "Departamento:",
        choices = c("Todos", levels(datos_saber11$departamento)),
        selected = "Todos"
      ),
      checkboxGroupInput(
        inputId = "naturaleza",
        label = "Naturaleza del Colegio:",
        choices = c("Oficial", "Privado"),
        selected = c("Oficial", "Privado")
      ),
      radioButtons(
        inputId = "zona",
        label = "Zona de Ubicación:",
        choices = c("Todas", "Urbana", "Rural"),
        selected = "Todas"
      ),
      sliderInput(
        inputId = "estrato",
        label = "Rango de Estrato Socioeconómico:",
        min = 1, max = 6, value = c(1, 6), step = 1
      ),
      hr(),
      actionButton("btn_ajustar", "Ajustar Modelo Lineal", class = "btn-primary w-100"),
      br(), br(),
      downloadButton("btn_descargar", "Exportar Filtrados (CSV)", class = "btn-outline-secondary w-100")
    ),
    
    mainPanel(
      width = 9,
      tabsetPanel(
        type = "tabs",
        tabPanel(
          "Exploración Visual",
          br(),
          fluidRow(
            column(6, plotlyOutput("grafico_box", height = "350px")),
            column(6, plotlyOutput("grafico_scatter", height = "350px"))
          ),
          br(),
          fluidRow(
            column(12, DTOutput("tabla_datos"))
          )
        ),
        tabPanel(
          "Modelado Predictivo",
          br(),
          h4("Resultados del Modelo Econométrico (lm)"),
          verbatimTextOutput("resumen_modelo"),
          uiOutput("alerta_faltantes")
        )
      )
    )
  )
)

# ------------------------------------------------------------------------------
# 4. DEFINICIÓN DEL SERVIDOR (SERVER)
# ------------------------------------------------------------------------------
server <- function(input, output, session) {
  
  # Reactive values para estado mutable
  historial_modelos <- reactiveValues(conteo = 0)
  
  # Filtro reactivo optimizado para evitar duplicación de código
  datos_filtrados <- reactive({
    req(input$naturaleza) # Validación de presencia
    
    df <- datos_saber11 %>%
      filter(
        naturaleza %in% input$naturaleza,
        estrato >= input$estrato[1] & estrato <= input$estrato[2]
      )
    
    if (input$depto != "Todos") {
      df <- df %>% filter(departamento == input$depto)
    }
    
    if (input$zona != "Todas") {
      df <- df %>% filter(zona == input$zona)
    }
    
    # Manejo de registros vacíos mediante validate()
    validate(
      need(nrow(df) > 0, "No hay registros disponibles para la combinación de filtros seleccionada.")
    )
    
    df
  })
  
  # Gráfico 1: Boxplot por Naturaleza del Colegio
  output$grafico_box <- renderPlotly({
    p <- datos_filtrados() %>%
      ggplot(aes(x = naturaleza, y = puntaje, fill = naturaleza)) +
      geom_boxplot(alpha = 0.7, outlier.colour = "red") +
      scale_fill_manual(values = c("Oficial" = "#2563eb", "Privado" = "#16a34a")) +
      labs(title = "Distribución de Puntaje por Naturaleza", x = "Naturaleza", y = "Puntaje") +
      theme_minimal()
    ggplotly(p)
  })
  
  # Gráfico 2: Dispersión Horas de Estudio vs Puntaje
  output$grafico_scatter <- renderPlotly({
    p <- datos_filtrados() %>%
      filter(!is.na(horas_estudio)) %>%
      ggplot(aes(x = horas_estudio, y = puntaje, color = zona)) +
      geom_point(alpha = 0.6) +
      geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
      labs(title = "Horas de Estudio vs. Puntaje Saber 11", x = "Horas de Estudio", y = "Puntaje") +
      theme_minimal()
    ggplotly(p)
  })
  
  # Tabla Interactiva DT
  output$tabla_datos <- renderDT({
    datatable(
      datos_filtrados(),
      options = list(pageLength = 5, autoWidth = TRUE),
      rownames = FALSE
    )
  })
  
  # Ajuste del Modelo Predictivo (Desencadenado por eventReactive)
  modelo_lineal <- eventReactive(input$btn_ajustar, {
    df <- datos_filtrados()
    validate(
      need(length(unique(df$naturaleza)) > 0, "Se requiere al menos un grupo de naturaleza para el modelo.")
    )
    historial_modelos$conteo <- historial_modelos$conteo + 1
    lm(puntaje ~ estrato + naturaleza + horas_estudio + zona, data = df)
  })
  
  output$resumen_modelo <- renderPrint({
    req(modelo_lineal())
    summary(modelo_lineal())
  })
  
  # Alerta sobre registros excluidos
  output$alerta_faltantes <- renderUI({
    n_na <- sum(is.na(datos_filtrados()$horas_estudio))
    if (n_na > 0) {
      div(
        class = "alert alert-warning mt-3",
        role = "alert",
        icon("exclamation-triangle"),
        sprintf(" Atención: Se excluyeron %d observaciones con datos faltantes en 'horas_estudio' durante el ajuste del modelo.", n_na)
      )
    }
  })
  
  # Descarga de datos en CSV
  output$btn_descargar <- downloadHandler(
    filename = function() {
      paste0("saber11_filtrados_IntiOlaya_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(datos_filtrados(), file, row.names = FALSE)
    }
  )
}

# ------------------------------------------------------------------------------
# 5. EJECUCIÓN DE LA APLICACIÓN SHINY
# ------------------------------------------------------------------------------
shinyApp(ui = ui, server = server)

# ==============================================================================
# INSTRUCCIONES DE CONTROL DE VERSIONES (GIT)
# Autor: Inti A. Olaya
# ------------------------------------------------------------------------------
# 1. Abrir la terminal en RStudio
# 2. Verificar el estado del repositorio:
#    git status
# 3. Añadir el script del taller:
#    git add entregas/taller_05_mineria_datos.R
# 4. Confirmar los cambios con commit:
#    git commit -m "Entrega Taller Clase 5 (R Shiny) - Inti A. Olaya"
# 5. Enviar cambios al repositorio remoto:
#    git push origin main
# ==============================================================================
