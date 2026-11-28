# prueba_boton.R -- aplicación mínima SOLO para probar el botón de actualización (Día 2).
# Ejecutar desde taller_2/:   shiny::runApp("prueba_boton.R")
library(shiny); library(bslib); library(future)
plan(multisession)
source("db.R", encoding = "UTF-8"); source("mod_actualizar.R", encoding = "UTF-8")

ui <- page_sidebar(title = "Prueba del botón de actualización",
  sidebar = sidebar(width = 420, mod_actualizar_ui("act")),
  card(card_header("Base activa"), verbatimTextOutput("info")))

server <- function(input, output, session) {
  act <- mod_actualizar_server("act", ruta_db = DB_RUTA)
  output$info <- renderText({
    act$version()                                   # se recalcula al terminar una actualización
    paste0("Base: ", basename(act$db()), "\nVersión de datos: ", db_version(act$db()),
           "\nÚltima ejecución por comercio:\n",
           paste(capture.output(print(db_consultar("SELECT comercio, ejecucion_id, estado FROM v_ultima_ejecucion",
                                                   ruta = act$db()))), collapse = "\n"))
  })
}
shinyApp(ui, server)
