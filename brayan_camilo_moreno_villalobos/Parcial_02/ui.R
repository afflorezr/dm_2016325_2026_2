# ui.R
library(shiny)
library(DT)
library(bslib) 
library(highcharter)

# Definición del tema visual moderno con bslib
tema_app <- bs_theme(
  version = 5,
  bootswatch = "zephyr",
  primary = "#1E3A5F",      # Azul marino elegante
  secondary = "#4A6FA5",    # Azul acero
  success = "#198754",      # Verde ahorro
  info = "#0DCAF0",
  warning = "#F59E0B",
  base_font = font_google("Inter"),
  heading_font = font_google("Plus Jakarta Sans"),
  "border-radius" = "0.6rem"
)

ui <- page_sidebar(
  title = div(
    style = "display: flex; align-items: center; gap: 10px; font-weight: 700;",
    icon("paw", class = "fa-lg"),
    span("Comparador de Precios · Alimentos para Mascotas")
  ),
  theme = tema_app,
  fillable = FALSE,
  
  # CSS personalizado para pulir detalles visuales
  tags$head(
    tags$style(HTML("
      .bslib-sidebar-layout > .sidebar {
        background-color: #F8FAFC;
        border-right: 1px solid #E2E8F0;
      }
      .nav-pills .nav-link {
        font-weight: 500;
        color: #334155;
        border-radius: 0.5rem;
        margin-right: 4px;
      }
      .nav-pills .nav-link.active {
        background-color: #1E3A5F !important;
        color: #FFFFFF !important;
        box-shadow: 0 2px 6px rgba(30, 58, 95, 0.25);
      }
      .card {
        border: 1px solid #E2E8F0;
        box-shadow: 0 2px 8px rgba(15, 23, 42, 0.04);
      }
    "))
  ),
  
  # --- BARRA LATERAL DE FILTROS ---
  sidebar = sidebar(
    width = 310,
    title = div(icon("sliders-h"), " Filtros de Búsqueda"),
    
    textInput("filtro_texto", "Buscar producto o palabra clave:", 
              placeholder = "Ej: Dog Chow, Salmón, 1500..."),
    
    checkboxGroupInput("filtro_comercio", "Seleccionar Comercio:",
                       choices = c("Exito", "Jumbo", "Olimpica"),
                       selected = c("Exito", "Jumbo", "Olimpica")),
    
    selectizeInput("filtro_marca", "Filtrar por Marca:",
                   choices = NULL, multiple = TRUE,
                   options = list(placeholder = "Todas las marcas")),
    
    checkboxGroupInput("filtro_mascota", "Tipo de Mascota:",
                       choices = NULL),
    
    sliderInput("filtro_precio", "Rango de Precio por Unidad ($):",
                min = 0, max = 500000, value = c(0, 500000), step = 1000, pre = "$"),
    dateRangeInput(
      inputId = "rango_fechas",
      label = "Fecha de consulta",
      start = "2026-11-10",       
      end = "2027-11-10",         
      separator = " a ",          
      language = "es",            
      format = "yyyy-mm-dd"       
    ),
    selectInput(
      inputId = "filtro_ejecucion", 
      label = "Ejecución", 
      choices = c("Todos" = "Todos"), # Se llenará automáticamente desde el servidor
      selected = "Todos"
    ),
    hr(),
    div(
      class = "p-2 rounded bg-white border",
      h6(icon("database"), " Actualización de Datos", class = "fw-bold mb-1"),
      p("Ejecuta el motor de extracción para obtener los precios de hoy. (Puede tardar varios minutos).", 
        class = "text-muted small mb-2"),
      input_task_button("btn_actualizar", "Ejecutar Scraper Ahora", icon = icon("sync"), class = "btn-primary w-100"),
      input_switch("modo_offline", "Modo sin conexión, usando archivos locales (usar raw/)", value = FALSE)
    )
  ),
  
  # --- CONTENIDO PRINCIPAL CON PESTAÑAS MODERNAS ---
  navset_card_pill(
    id = "navegacion_principal",
    
    # 1. Pestaña de Indicadores (La ponemos de primera para impacto visual)
    nav_panel(
      title = "Indicadores",
      icon = icon("gauge-high"),
      div(
        class = "p-2",
        h4("Indicadores Clave del Mercado y Base de Datos", class = "fw-bold text-primary"),
        p("Métricas consolidadas calculadas directamente mediante consultas SQL sobre la base de datos.", class = "text-muted"),
        br(),
        uiOutput("tarjetas_indicadores")
      )
    ),
    
    # 2. Evolución de Precios
    nav_panel(
      title = "Evolución de Precios",
      icon = icon("chart-line"),
      div(
        class = "p-2",
        h4("Compara la evolución histórica de un producto", class = "fw-bold text-primary"),
        fluidRow(
          column(6, selectInput("producto_elegido", "Selecciona un producto comparable:", 
                                choices = NULL, width = "100%"))
        ),
        highchartOutput("grafico_evolucion", height = "500px")
      )
    ),
    
    # 3. Precio Unitario
    nav_panel(
      title = "Precio Unitario",
      icon = icon("scale-balanced"),
      div(
        class = "p-2",
        h4("Comparación de Precio por Unidad (Última extracción)", class = "fw-bold text-primary"),
        fluidRow(
          column(6, selectInput("prod_unitario_elegido", "Selecciona un producto comparable:", 
                                choices = NULL, width = "100%"))
        ),
        highchartOutput("grafico_unitario", height = "400px")
      )
    ),
    
    # 4. Distribución
    nav_panel(
      title = "Distribución",
      icon = icon("chart-bar"),
      div(
        class = "p-2",
        h4("Distribución de Precios por Supermercado", class = "fw-bold text-primary"),
        p("Este gráfico de cajas (boxplot) muestra la dispersión de los precios de toda la categoría en la extracción más reciente. Te permite ver rápidamente qué supermercado tiene los precios más altos, más bajos y dónde se concentra la mayoría de los productos.", class = "text-muted"),
        highchartOutput("grafico_distribucion", height = "500px")
      )
    ),
    
    # 5. Participación de Marcas
    nav_panel(
      title = "Participación de Marcas",
      icon = icon("chart-pie"),
      div(
        class = "p-2",
        h4("Distribución del Catálogo por Marca", class = "fw-bold text-primary"),
        p("Proporción de productos homologados que pertenecen a cada marca dentro de la categoría analizada.", class = "text-muted"),
        highchartOutput("grafico_marcas", height = "500px")
      )
    ),
    
    # 6. Canasta
    nav_panel(
      title = "Canasta",
      icon = icon("cart-shopping"),
      div(
        class = "p-2",
        h4("Simulador de Canasta de Mercado", class = "fw-bold text-primary"),
        p("Selecciona los productos que deseas llevar y ajusta sus cantidades para encontrar dónde te sale más económico.", class = "text-muted"),
        
        fluidRow(
          column(6,
                 div(class = "p-3 bg-light rounded border",
                     selectizeInput("canasta_productos", "1. Elige tus productos:",
                                    choices = NULL, multiple = TRUE, width = "100%",
                                    options = list(placeholder = "Selecciona uno o varios productos..."))
                 )
          ),
          column(6,
                 div(class = "p-3 bg-light rounded border",
                     uiOutput("ui_cantidades_canasta")
                 )
          )
        ),
        hr(),
        uiOutput("resumen_canasta_optima"),
        br(),
        h5("Comparación comprando toda la canasta en un solo comercio:", class = "fw-bold"),
        DTOutput("tabla_canasta_comercios"),
        br(),
        div(class = "alert alert-warning d-flex align-items-center", role = "alert",
            icon("exclamation-triangle", class = "me-2 fa-lg"),
            div(
              strong("Advertencia: "), 
              "Los valores calculados corresponden a los precios de etiqueta de la última extracción y no incluyen costos de envío, montos mínimos de compra ni condiciones especiales de promociones."
            )
        )
      )
    ),
    
    # 7. Últimos Precios
    nav_panel(
      title = "Últimos Precios",
      icon = icon("table"),
      div(
        class = "p-2",
        fluidRow(
          column(8, 
                 h4("Catálogo de Precios Recientes", class = "fw-bold text-primary")
          ),
          column(4, class = "text-end align-self-center",
                 downloadButton("btn_descargar_csv", "Descargar CSV Filtrado", class = "btn-success"))
        ),
        br(),
        DTOutput("tabla_precios")
      )
    ),
    
    # 8. Variaciones de Mercado
    nav_panel(
      title = "Variaciones de Mercado",
      icon = icon("arrow-trend-up"),
      div(
        class = "p-2",
        h4("Análisis de Variaciones entre Ejecuciones", class = "fw-bold text-primary"),
        p("Compara dos corridas del scraper y ajusta el umbral mínimo para detectar cambios relevantes de precio.", class = "text-muted"),
        div(
          class = "p-3 bg-light rounded border mb-3",
          fluidRow(
            column(4, selectInput("ejecucion_anterior", "Ejecución Base (Anterior):", choices = NULL, width = "100%")),
            column(4, selectInput("ejecucion_actual", "Ejecución a Comparar (Reciente):", choices = NULL, width = "100%")),
            column(4, sliderInput("umbral_cambio_pct", "Umbral mínimo de variación (%):",
                                  min = 0, max = 50, value = 0, step = 1, post = "%", width = "100%"))
          )
        ),
        DTOutput("tabla_cambios")
      )
    )
  )
)