library(shiny)
library(bslib)
source("db.R")

ui <- page_sidebar(
  title = "Comparador de precios: maquillaje",
  sidebar = sidebar(
    checkboxGroupInput("comercios", "Comercios",
                       choices = c("Farmatodo" = "farmatodo",
                                   "Éxito" = "exito",
                                   "Cromantic" = "cromantic"),
                       selected = c("farmatodo", "exito", "cromantic")),
    sliderInput("precio", "Precio (COP)", 0, 100000, c(0, 100000), step = 1000)
  ),
  layout_columns(
    value_box("Productos comparables (7 de 8 del Taller 1)", textOutput("n_productos")),
    value_box("Observaciones comparables", textOutput("n_obs"))
  ),
  card(card_header("Precios de los productos comparables"), tableOutput("tabla")),
  card(card_header("Nota"),
       p("Se muestran 7 productos porque los tres SKU de Maybelline en Éxito no tienen tono verificable en la captura. Precios de la ejecución 20261110T225816."))
)

server <- function(input, output, session) {
  con <- db_con()
  session$onSessionEnded(function() dbDisconnect(con))
  
  ind <- reactive(indicadores(con))
  output$n_productos <- renderText(ind()$productos_comparables)
  output$n_obs <- renderText(ind()$observaciones_comparables)
  
  output$tabla <- renderTable({
    precios_filtrados(con, input$comercios, input$precio[1], input$precio[2])
  })
}

shinyApp(ui, server)