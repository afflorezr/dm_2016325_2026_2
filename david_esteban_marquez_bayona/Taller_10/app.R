# =============================================================================
# Taller 10 — Explorador de arriendos (Shiny)
# Autor: David Márquez
# Requiere arriendos.csv en la misma carpeta (lo genera taller_10.R).
# Ejecutar: shiny::runApp("app.R")   o botón "Run App" en RStudio
# install.packages(c("shiny", "corrplot"))
# =============================================================================
library(shiny)
library(corrplot)

datos <- read.csv("arriendos.csv", encoding = "UTF-8")

# --- Funciones -----------------------------------------------------------------
asimetria <- function(x) { m <- mean(x); mean((x - m)^3) / mean((x - m)^2)^1.5 }
pesos <- function(x) formatC(round(x), format = "d", big.mark = ".")
es_atipico <- function(x) {
  q <- unname(quantile(x, c(.25, .75))); r <- q[2] - q[1]
  x < q[1] - 1.5 * r | x > q[2] + 1.5 * r
}

# --- Interfaz ------------------------------------------------------------------
ui <- fluidPage(
  titlePanel("Explorador de arriendos"),
  sidebarLayout(
    sidebarPanel(
      checkboxGroupInput("ciudad", "Ciudad", choices = sort(unique(datos$ciudad)),
                         selected = unique(datos$ciudad)),
      sliderInput("estrato", "Estrato", min = 1, max = 6, value = c(1, 6), step = 1),
      sliderInput("umbral", "Umbral de asimetría", min = 0, max = 2,
                  value = 0.5, step = 0.1)
    ),
    mainPanel(
      fluidRow(
        column(4, h4("Arriendo típico"), textOutput("tipico")),
        column(4, h4("CV"),              textOutput("cv")),
        column(4, h4("Atípicos"),        textOutput("n_atip"))
      ),
      hr(),
      uiOutput("mensajes"),
      tabsetPanel(
        tabPanel("Histograma", plotOutput("hist")),
        tabPanel("Atípicos", downloadButton("descargar", "Descargar CSV"),
                 tableOutput("tabla_atip")),
        tabPanel("Correlaciones (Spearman)", plotOutput("corr"))
      )
    )
  )
)

# --- Servidor ------------------------------------------------------------------
server <- function(input, output) {

  grupo <- reactive({
    d <- subset(datos, ciudad %in% input$ciudad &
                  estrato >= input$estrato[1] & estrato <= input$estrato[2])
    validate(need(nrow(d) >= 5, "Seleccione un grupo con al menos 5 registros."))
    d
  })

  # Regla 1: |asimetría| > umbral -> mediana e IQR; si no, media y DE
  usa_mediana <- reactive(abs(asimetria(grupo()$arriendo)) > input$umbral)

  output$tipico <- renderText({
    x <- grupo()$arriendo
    if (usa_mediana()) paste0("Mediana: $", pesos(median(x)), " (IQR $", pesos(IQR(x)), ")")
    else               paste0("Media: $",   pesos(mean(x)),   " (DE $",  pesos(sd(x)), ")")
  })

  output$cv <- renderText({
    x <- grupo()$arriendo
    paste0(round(100 * sd(x) / mean(x), 1), "%")
  })

  # Regla 2: atípico por la regla del IQR (no necesariamente error)
  atipicos <- reactive(grupo()[es_atipico(grupo()$arriendo), ])
  output$n_atip <- renderText(nrow(atipicos()))

  output$mensajes <- renderUI({
    x <- grupo()$arriendo; a <- asimetria(x); cv <- sd(x) / mean(x)
    tagList(
      p(strong("Centro: "), if (usa_mediana())
        sprintf("se reporta la mediana porque |asimetría| = %.2f > %.1f.", abs(a), input$umbral)
        else sprintf("se reporta la media porque |asimetría| = %.2f ≤ %.1f.", abs(a), input$umbral)),
      # Regla 3: CV > 30% -> grupo heterogéneo
      if (cv > 0.30) p(style = "color:#b35900;",
                       sprintf("Atención: CV = %.1f%% > 30%%, el grupo es heterogéneo.", 100 * cv)),
      p(em("Atípico no significa error: revise cada registro marcado."))
    )
  })

  output$hist <- renderPlot({
    x <- grupo()$arriendo
    hist(x, breaks = 40, col = "grey85", border = "white",
         main = "Distribución del arriendo", xlab = "Arriendo (COP)")
    abline(v = mean(x),   col = "firebrick", lwd = 2)
    abline(v = median(x), col = "steelblue", lwd = 2)
    legend("topright", lwd = 2, col = c("firebrick", "steelblue"),
           legend = c("Media", "Mediana"))
  })

  output$tabla_atip <- renderTable(atipicos()[order(-atipicos()$arriendo), ],
                                   digits = 0)

  output$descargar <- downloadHandler(
    filename = "atipicos.csv",
    content  = function(f) write.csv(atipicos(), f, row.names = FALSE)
  )

  # Regla 4: estrato es ordinal -> Spearman
  output$corr <- renderPlot({
    m <- cor(grupo()[, c("arriendo", "area_m2", "estrato", "antiguedad")],
             method = "spearman")
    corrplot(m, method = "color", type = "upper", addCoef.col = "black",
             tl.col = "black")
  })
}

shinyApp(ui, server)
