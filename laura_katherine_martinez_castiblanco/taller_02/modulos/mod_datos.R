# Pestaña 8 · Datos y auditoría: trazabilidad de ejecuciones, correcciones, descartes, validaciones y diccionario
datos_ui <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Ejecuciones", p(class = "small text-body-secondary", "Cada observación se rastrea hasta su ejecución (id_ejecucion) y su copia cruda en raw/ (columna archivo_raw)."),
              DTOutput(ns("t_ejec"))),
    nav_panel("Correcciones del Taller 1", p(class = "small text-body-secondary", "No se borra ninguna observación: cada cambio queda registrado con fecha, valor anterior, valor nuevo y motivo."),
              DTOutput(ns("t_corr"))),
    nav_panel("Observaciones rechazadas", p(class = "small text-body-secondary", "Motivos por los que un producto no entró a la base."), DTOutput(ns("t_desc"))),
    nav_panel("Validaciones de lote", DTOutput(ns("t_val"))),
    nav_panel("Diccionario de datos", uiOutput(ns("dic"))))
}

datos_server <- function(id, version) {
  moduleServer(id, function(input, output, session) {
    tabla <- function(d, vacio_msg) { vacio(d, vacio_msg); datatable(d, rownames = FALSE, class = "compact stripe", options = list(pageLength = 10, scrollX = TRUE, language = DT_ES)) }
    output$t_ejec <- renderDT({ version(); tabla(db_auditoria(), "Sin ejecuciones registradas.") })
    output$t_corr <- renderDT({ version(); tabla(db_correcciones_lista(), "Aún no hay correcciones registradas.") })
    output$t_desc <- renderDT({ version(); tabla(db_descartes_resumen(), "Sin observaciones rechazadas.") })
    output$t_val  <- renderDT({ version(); tabla(db_validaciones(), "Aún no hay validaciones de lote (se registran al actualizar).") })
    output$dic <- renderUI({
      if (!file.exists("diccionario_datos.md")) return(aviso("No se encontró diccionario_datos.md.", "warning"))
      if (requireNamespace("markdown", quietly = TRUE)) includeMarkdown("diccionario_datos.md")
      else tags$pre(paste(readLines("diccionario_datos.md", encoding = "UTF-8", warn = FALSE), collapse = "\n"))
    })
  })
}
