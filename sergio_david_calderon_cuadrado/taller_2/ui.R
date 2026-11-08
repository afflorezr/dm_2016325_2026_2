ui <- page_navbar(
  title = "Comparador de precios de cremas corporales",
  sidebar = sidebar(
    selectizeInput("comercio", "Comercio", choices = NULL, multiple = TRUE),
    sliderInput("precio", "Precio (COP)", min = 0, max = 500000,
                value = c(0, 500000), step = 1000),
    checkboxInput("promo", "Solo promociones", value = FALSE),
    textInput("texto", "Buscar en el nombre", value = "")
  ),
  nav_panel("Resumen",
    p(class = "text-muted", textOutput("periodo")),
    layout_columns(fill = FALSE, col_widths = c(3, 3, 3, 3),
      value_box(title = "Productos", value = textOutput("n_productos")),
      value_box(title = "Numero de observaciones", value = textOutput("n_obs")),
      value_box(title = "% en promoción", value = textOutput("pct_promo")),
      value_box(title = "Mediana del precio", value = textOutput("mediana"))
    ),
    layout_columns(fill = FALSE, col_widths = c(6, 6),
      value_box(title = "Ahorro máximo entre comercios (COP)", value = textOutput("ahorro"),
                textOutput("ahorro_detalle")),
      value_box(title = "Cambios de precio en la última ejecución", value = textOutput("cambios"),
                "frente a la ejecución anterior"),
      card(card_header("Última ejecución"), tableOutput("t_ultima")),
      card(card_header("Mediana de precio por subcategoría (COP)"), tableOutput("t_subcat")),
      card(card_header("Productos y observaciones por comercio"), tableOutput("t_comercio"))
    )
  ),
  nav_panel("Gráficos",
            selectInput("producto", "Producto comparable", choices = NULL),
            card(card_header("Evolución del precio por comercio (COP)"),
                 highchartOutput("g_evolucion")),
            radioButtons("medida", "Unidad del precio unitario", choices = c("mL" = "ml", "g" = "g"), inline = TRUE),
            layout_columns(fill = FALSE, col_widths = c(5, 4, 3),
              card(card_header("Mediana del precio por unidad (COP por mL o g)"), highchartOutput("g_unitario")),
              card(card_header("Distribución del precio por comercio (COP)"),     highchartOutput("g_distribucion"))
            )
  ),
  nav_panel("Tabla", DTOutput("tabla"))
)
