# =============================================================================
# ui.R  -  Interfaz de la aplicacion (Modulo 5: presentacion y diseno)
# -----------------------------------------------------------------------------
# bslib::page_sidebar con indicadores en tarjetas (value_box), filtros en el
# panel lateral (en acordeones compactos), navegacion por pestanas con iconos y
# tablas/graficos interactivos con pantalla completa. Moneda COP, unidades y
# fecha de los datos siempre visibles. Ver www/custom.css para los ajustes de
# tipografia y densidad (usables con zoom normal).
# =============================================================================

filtro_comun <- function(id, label, choices = character(), multiple = TRUE) {
  selectizeInput(
    id, label, choices = choices, multiple = multiple, width = "100%",
    options = list(placeholder = "Todos", plugins = list("remove_button"))
  )
}

mini_stat <- function(valor, texto) {
  div(class = "text-center",
      div(class = "stat-num", textOutput(valor, inline = TRUE)),
      p(class = "small text-muted mb-0", texto))
}

ui <- page_sidebar(
  title = div(
    class = "app-title",
    "Comparador de precios",
    span(class = "badge text-bg-light ms-2", "Cuidado del bebé · Colombia")
  ),
  theme = bs_theme(version = 5, bootswatch = "flatly",
                   primary = "#0071CE", "enable-bslib" = TRUE),
  fillable = FALSE,

  tags$head(tags$link(rel = "stylesheet", type = "text/css", href = "custom.css")),

  # ---------------------------------------------------------------- sidebar
  sidebar = sidebar(
    width = 300,

    accordion(
      id = "paneles_laterales", multiple = TRUE,
      open = c("Filtros", "Actualizar precios"),

      # ---- panel de filtros (abierto por defecto: es el uso principal)
      accordion_panel(
        "Filtros", icon = icon("sliders"),

        textInput("busqueda", "Buscar en el nombre o anuncio", value = "",
                  placeholder = "ej: Johnson manzanilla"),
        filtro_comun("comercio", "Comercio"),
        filtro_comun("subcategoria", "Subcategoría"),
        filtro_comun("marca", "Marca"),
        sliderInput("precio", "Precio (COP)", min = 0, max = PRECIO_MAX,
                    value = c(0, PRECIO_MAX), step = 500,
                    pre = "$ ", sep = ".", ticks = FALSE, width = "100%"),
        dateRangeInput(
          "fechas", "Fecha de consulta",
          start = RANGO_FECHAS[1], end = RANGO_FECHAS[2],
          min = RANGO_FECHAS[1], max = RANGO_FECHAS[2],
          format = "yyyy-mm-dd", weekstart = 1, language = "es",
          separator = " a ", width = "100%"
        ),
        filtro_comun("ejecucion", "Ejecución"),
        checkboxInput("solo_promocion", "Solo promociones", FALSE),
        checkboxInput("solo_comparables", "Solo productos comparables", FALSE),

        div(class = "d-flex justify-content-between align-items-center mt-2",
            span(class = "small text-muted",
                 textOutput("n_resultados", inline = TRUE)),
            actionButton("limpiar_filtros", "Limpiar filtros",
                         class = "btn-outline-secondary btn-sm"))
      ),

      # ---- panel de actualizacion de precios
      accordion_panel(
        "Actualizar precios", icon = icon("arrows-rotate"),

        div(
          class = "scrapers-box mb-2",
          div(class = "small fw-bold",
              icon("globe", class = "me-1"),
              paste0("Scrapers configurados: ", length(COMERCIOS))),
          tags$ul(
            class = "list-unstyled small mb-0 mt-1",
            lapply(names(COMERCIOS), function(k) {
              tags$li(
                class = "d-flex align-items-center gap-2",
                span(class = "dot-comercio",
                     style = paste0("background:", color_comercio(COMERCIOS[[k]]$nombre))),
                span(COMERCIOS[[k]]$nombre),
                span(class = "text-muted ms-auto",
                     sub("^https?://(www\\.)?", "", COMERCIOS[[k]]$base))
              )
            })
          )
        ),

        radioButtons(
          "modo_ejecucion", "Modo de recolección",
          choiceNames = c("En línea (scraping a los sitios)",
                          "Sin conexión (reprocesa copias de raw/)"),
          choiceValues = c("online", "offline"),
          selected = "online"
        ),
        textAreaInput(
          "productos_extra", "Buscar más productos (separados por coma)",
          value = "", rows = 2, width = "100%",
          placeholder = "ej: pañales talla 3, toallitas húmedas, talco bebé"
        ),
        actionButton("btn_actualizar", "Actualizar precios",
                     class = "btn-primary w-100 mb-2"),
        uiOutput("estado_actualizacion"),
        tableOutput("tabla_resumen_actualizacion"),
        helpText("La actualización corre en segundo plano y no bloquea la app.",
                 "Si un sitio falla, se registra y continúan los demás.")
      )
    )
  ),

  # ---------------------------------------------------------------- contenido
  navset_card_tab(

    # ===== Pestana 1: Resumen =====
    nav_panel(
      "Resumen", icon = icon("chart-pie"),

      layout_columns(
        col_widths = c(3, 3, 3, 3),
        value_box(
          title = "Observaciones", value = textOutput("ind_observaciones"),
          showcase = icon("layer-group"), theme = "primary",
          min_height = "112px",
          p(class = "small mb-0", textOutput("ind_observaciones_sub"))
        ),
        value_box(
          title = "Comparables (3 comercios)", value = textOutput("ind_comparables"),
          showcase = icon("scale-balanced"), theme = "success",
          min_height = "112px",
          p(class = "small mb-0", textOutput("ind_comparables_sub"))
        ),
        value_box(
          title = "En promoción", value = textOutput("ind_promo"),
          showcase = icon("tag"), theme = "warning",
          min_height = "112px",
          p(class = "small mb-0", "última observación por anuncio")
        ),
        value_box(
          title = "Ahorro máximo", value = textOutput("ind_ahorro"),
          showcase = icon("coins"), theme = "danger",
          min_height = "112px",
          p(class = "small mb-0", textOutput("ind_ahorro_sub"))
        )
      ),

      layout_columns(
        col_widths = c(6, 6),
        card(
          card_header("Cambios de precio (última ejecución vs anterior)"),
          layout_columns(
            col_widths = c(4, 4, 4),
            mini_stat("cambios_subidas", "subidas"),
            mini_stat("cambios_bajas", "bajas"),
            mini_stat("cambios_total", "cambios totales")
          ),
          card_footer(p(class = "mb-0", textOutput("cambios_periodo")))
        ),
        card(
          card_header("Estado de la última ejecución"),
          tableOutput("tabla_ejecucion")
        )
      ),

      card(
        full_screen = TRUE,
        card_header("Distribución de precios de la categoría por comercio (COP)"),
        highchartOutput("hc_distribucion", height = "360px"),
        card_footer(
          "Cada punto es un anuncio; la caja resume la mediana y los cuartiles. ",
          "No se comparan promedios de surtidos distintos entre sí: use la ",
          "pestaña Comparables para comparaciones equivalentes."
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Mayores brechas de precio entre comercios (mismo producto)"),
        highchartOutput("hc_brecha", height = "420px"),
        card_footer(
          "Top 15 productos con la diferencia más grande entre el comercio ",
          "más caro y el más barato. Período: última observación de cada anuncio."
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Mediana del precio por subcategoría (COP)"),
        tableOutput("tabla_indicadores_subcategoria"),
        card_footer(
          "Mediana en COP de la última observación de cada anuncio; período: ",
          textOutput("ind_promo_periodo", inline = TRUE), "."
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Productos filtrados"),
        DTOutput("tabla_productos"),
        card_footer(
          div(class = "d-flex justify-content-end",
              downloadButton("descargar_csv", "Descargar CSV filtrado",
                             class = "btn-outline-primary btn-sm"))
        )
      )
    ),

    # ===== Pestana 2: Comparables =====
    nav_panel(
      "Comparables", icon = icon("scale-balanced"),

      layout_columns(
        col_widths = c(3, 9),
        card(
          card_header("Selección"),
          selectInput("unidad_unitario", "Unidad de contenido",
                      choices = c("Mililitros (ml)" = "ml",
                                  "Gramos (g)" = "g",
                                  "Unidades" = "unidad"),
                      selected = "ml"),
          selectInput("comparable_evolucion",
                      "Producto comparable (evolución del precio)",
                      choices = NULL),
          p(class = "small text-muted mb-0", textOutput("aviso_unidad"))
        ),
        card(
          full_screen = TRUE,
          card_header(textOutput("titulo_evolucion")),
          highchartOutput("hc_evolucion", height = "340px"),
          card_footer(
            "Una serie por comercio. Fecha y hora de consulta (hora de ",
            "Colombia). Precio en COP."
          )
        )
      ),
      card(
        full_screen = TRUE,
        card_header(textOutput("titulo_unitario")),
        highchartOutput("hc_unitario", height = "400px"),
        card_footer(
          "Precio por unidad de contenido de la MISMA presentación. ",
          "No se mezclan mL con g ni con unidades."
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Tabla de comparables por comercio (última ejecución)"),
        DTOutput("tabla_comparables")
      )
    ),

    # ===== Pestana 3: Cambios de precio =====
    nav_panel(
      "Cambios de precio", icon = icon("chart-line"),

      layout_columns(
        col_widths = c(3, 9),
        card(
          card_header("Ejecuciones a comparar"),
          selectInput("ejec_a", "Ejecución anterior", choices = NULL),
          selectInput("ejec_b", "Ejecución posterior", choices = NULL),
          sliderInput("umbral", "Umbral para resaltar variaciones grandes (COP)",
                      min = 0, max = 10000, value = 1000, step = 100,
                      pre = "$ ", sep = ".", ticks = FALSE, width = "100%"),
          p(class = "small text-muted mb-0",
            "Por defecto se comparan las dos ejecuciones más recientes. ",
            "La comparación es del mismo anuncio en el mismo comercio.")
        ),
        card(
          card_header("Resumen de la comparación"),
          layout_columns(
            col_widths = c(3, 3, 3, 3),
            mini_stat("cmp_subieron", "subieron"),
            mini_stat("cmp_bajaron", "bajaron"),
            mini_stat("cmp_nuevos", "nuevos"),
            mini_stat("cmp_fuera", "dejaron de observarse")
          ),
          highchartOutput("hc_resumen_cambios", height = "340px"),
          card_footer(
            "Top 12 de las mayores variaciones entre las dos ejecuciones. ",
            "Rojo: el precio subió. Verde: el precio bajó. ",
            "Las líneas punteadas marcan el umbral del panel de la izquierda."
          )
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Precios que subieron o bajaron"),
        DTOutput("tabla_cambios")
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(
          full_screen = TRUE,
          card_header("Productos nuevos en la ejecución posterior"),
          DTOutput("tabla_nuevos")
        ),
        card(
          full_screen = TRUE,
          card_header("Productos que dejaron de observarse"),
          DTOutput("tabla_fuera")
        )
      )
    ),

    # ===== Pestana 4: Canasta =====
    nav_panel(
      "Canasta", icon = icon("basket-shopping"),

      layout_columns(
        col_widths = c(4, 8),
        card(
          card_header("Arme su canasta"),
          selectizeInput(
            "canasta_productos", "Productos comparables",
            choices = NULL, multiple = TRUE,
            options = list(placeholder = "Escriba y seleccione productos",
                           plugins = list("remove_button"))
          ),
          uiOutput("canasta_cantidades"),
          actionButton("btn_canasta", "Calcular canasta",
                       class = "btn-primary w-100"),
          p(class = "small text-muted mt-2 mb-0",
            "Se usan precios de la misma ejecución (la más reciente que tenga ",
            "todos los productos). El resultado no incluye envío, mínimos de ",
            "compra ni condiciones de las promociones.")
        ),
        card(
          card_header("Costo por comercio"),
          tableOutput("tabla_canasta"),
          p(class = "small mb-0", textOutput("canasta_aviso"))
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Compra mínima (cada producto donde es más barato)"),
        tableOutput("tabla_canasta_min"),
        card_footer(
          "El ahorro es frente a comprar toda la canasta en un solo comercio ",
          "con los precios observados en la misma ejecución."
        )
      )
    )
  )
)
