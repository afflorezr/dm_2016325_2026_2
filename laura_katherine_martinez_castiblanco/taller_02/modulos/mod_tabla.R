# Pestaña 6 · Tabla de productos filtrados (ordenar, buscar y descargar en CSV / Excel)
tabla_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(class = "d-flex flex-wrap justify-content-between align-items-center mb-2 gap-2",
        uiOutput(ns("conteo")),
        div(downloadButton(ns("csv"), "Descargar CSV", class = "btn-sm btn-primary"),
            if (requireNamespace("writexl", quietly = TRUE)) downloadButton(ns("xlsx"), "Descargar Excel", class = "btn-sm btn-outline-primary"))),
    tarjeta("Productos con los filtros actuales", DTOutput(ns("t")))
  )
}

tabla_server <- function(id, filtros, catalogos, version) {
  moduleServer(id, function(input, output, session) {
    LIMITE <- 20000L
    datos <- reactive(db_tabla(filtros(), LIMITE)) |> bindCache(filtros(), version())
    output$conteo <- renderUI({
      d <- datos(); aviso(sprintf("%s filas · precios en COP · %s%s", fmt_num(nrow(d)), periodo_texto(filtros(), catalogos()$corridas),
                                  if (nrow(d) >= LIMITE) " · (se muestran las primeras 20.000)" else ""), "secondary")
    })
    output$t <- renderDT({
      d <- datos(); vacio(d)
      enlace <- ifelse(grepl("^https?://", d$Enlace), sprintf("<a href='%s' target='_blank' rel='noopener noreferrer'>Ver anuncio</a>", htmltools::htmlEscape(d$Enlace)), "—")
      d$Enlace <- enlace
      d$Fecha_consulta <- fmt_fecha(d$Fecha_consulta)
      names(d) <- c("Comercio", "Producto", "Marca", "Subcategoría", "Presentación", "Precio (COP)", "Precio por litro (COP/L)",
                    "Promoción", "Disponibilidad", "Fecha de consulta", "Enlace", "Ejecución")
      datatable(d, rownames = FALSE, filter = "top", class = "compact stripe hover",
                escape = setdiff(names(d), "Enlace"), options = list(pageLength = 15, scrollX = TRUE, language = DT_ES)) |>
        formatCurrency(c("Precio (COP)", "Precio por litro (COP/L)"), currency = "$ ", digits = 0, mark = ".", dec.mark = ",")
    })
    descarga <- function() db_tabla(filtros(), 1e6L)
    output$csv <- downloadHandler(
      filename = function() paste0("comparador_precios_", format(Sys.Date(), "%Y%m%d"), ".csv"),
      content = function(file) readr::write_excel_csv(descarga(), file))
    output$xlsx <- downloadHandler(
      filename = function() paste0("comparador_precios_", format(Sys.Date(), "%Y%m%d"), ".xlsx"),
      content = function(file) writexl::write_xlsx(descarga(), file))
  })
}
