# ui.R
# Interfaz con bslib. Aquí no hay SQL ni cálculos: solo la disposición.

caja <- function(id, titulo, icono, tema = "primary") {
  value_box(
    title = titulo,
    value = textOutput(id),
    showcase = icon(icono),
    theme = tema,
    p(textOutput(paste0(id, "_nota"), inline = TRUE), class = "small mb-0")
  )
}

filtros <- list(
  selectizeInput("f_comercio", "Comercio", choices = NULL, multiple = TRUE,
                 options = list(placeholder = "Todos los comercios")),
  selectizeInput("f_subcategoria", "Subcategoría", choices = NULL, multiple = TRUE,
                 options = list(placeholder = "Todas")),
  selectizeInput("f_marca", "Marca", choices = NULL, multiple = TRUE,
                 options = list(placeholder = "Todas")),
  sliderInput("f_precio", "Rango de precio (COP)", min = 0, max = 100000,
              value = c(0, 100000), step = 500, pre = "$", sep = "."),
  radioButtons("f_periodo", "Periodo", inline = TRUE,
               choices = c("Una ejecución" = "ejecucion", "Rango de fechas" = "fechas")),
  conditionalPanel(
    "input.f_periodo == 'ejecucion'",
    selectInput("f_ejecucion", "Ejecución", choices = NULL)
  ),
  conditionalPanel(
    "input.f_periodo == 'fechas'",
    dateRangeInput("f_fechas", "Fecha de consulta", language = "es",
                   separator = " a ", format = "dd/mm/yyyy")
  ),
  checkboxInput("f_promo", "Solo productos en promoción"),
  checkboxInput("f_comparables", "Solo productos comparables"),
  textInput("f_texto", "Buscar en el nombre o en el anuncio", placeholder = "Ej.: loratadina"),
  uiOutput("aviso_busqueda"),
  actionButton("f_limpiar", "Quitar filtros", class = "btn-outline-primary btn-sm")
)

page_navbar(
  id = "pagina",
  title = "Comparador de precios · medicamentos respiratorios",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  lang = "es",
  fillable = FALSE,

  sidebar = sidebar(
    width = 300,
    conditionalPanel(
      "['resumen', 'graficos', 'productos'].includes(input.pagina)",
      h6("Filtros"),
      filtros
    ),
    conditionalPanel(
      "!['resumen', 'graficos', 'productos'].includes(input.pagina)",
      p(class = "text-muted small",
        "Los filtros de esta barra aplican a Resumen, Gráficos y Productos.",
        "Esta página tiene sus propios controles.")
    )
  ),

  # ---------- Resumen ----------
  nav_panel(
    "Resumen", value = "resumen",
    uiOutput("aviso_sin_datos"),
    layout_column_wrap(
      width = "250px", fill = FALSE,
      caja("ind_productos", "Productos distintos", "box"),
      caja("ind_observaciones", "Observaciones de precio", "list"),
      caja("ind_ultima", "Última ejecución", "clock", "secondary"),
      caja("ind_promo", "En promoción", "tags", "success"),
      caja("ind_mediana", "Precio mediano", "scale-balanced"),
      caja("ind_ahorro", "Ahorro máximo entre comercios", "piggy-bank", "success"),
      caja("ind_cambios", "Cambios de precio", "arrow-trend-up", "warning"),
      caja("ind_disponibilidad", "Agotados", "ban", "danger")
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Productos y observaciones por comercio"),
           DTOutput("tabla_por_comercio")),
      card(card_header("Precio mediano por subcategoría"),
           DTOutput("tabla_mediana_sub"))
    )
  ),

#Gráficos
  nav_panel(
    "Gráficos", value = "graficos",
    layout_columns(
      col_widths = c(6, 6, 6, 6),
      card(
        full_screen = TRUE,
        card_header("Evolución del precio"),
        selectInput("g_comparable", "Producto comparable", choices = NULL, width = "100%"),
        highchartOutput("g_evolucion", height = "380px")
      ),
      card(
        full_screen = TRUE,
        card_header("Precio por unidad de contenido"),
        radioButtons("g_unidad", "Unidad",
                     choices = c("por unidad" = "unidad", "por sobre" = "sobres",
                                 "por mL" = "mL", "por dosis" = "dosis"), inline = TRUE),
        highchartOutput("g_unitario", height = "380px")
      ),
      card(
        full_screen = TRUE,
        card_header("Distribución de precios"),
        highchartOutput("g_distribucion", height = "420px")
      ),
      card(
        full_screen = TRUE,
        card_header("¿Dónde conviene comprar?"),
        highchartOutput("g_mas_barato", height = "420px")
      )
    )
  ),

#Tabla de productos
  nav_panel(
    "Productos", value = "productos",
    card(
      full_screen = TRUE,
      card_header(
        class = "d-flex justify-content-between align-items-center",
        textOutput("titulo_tabla", inline = TRUE),
        downloadButton("descargar_csv", "Descargar CSV", class = "btn-sm btn-primary")
      ),
      DTOutput("tabla_productos")
    )
  ),

#Cambios de precio
  nav_panel(
    "Cambios de precio", value = "cambios",
    layout_sidebar(
      sidebar = sidebar(
        width = 280,
        selectInput("c_anterior", "Ejecución anterior", choices = NULL),
        selectInput("c_reciente", "Ejecución reciente", choices = NULL),
        sliderInput("c_umbral", "Resaltar variaciones de más de (%)",
                    min = 1, max = 50, value = 10, step = 1, post = " %"),
        checkboxGroupInput("c_tipos", "Mostrar",
                           choices = c("Subió" = "sube", "Bajó" = "baja", "Nuevo" = "nuevo",
                                       "Dejó de observarse" = "no_observado",
                                       "Sin cambio" = "sin_cambio"),
                           selected = c("sube", "baja", "nuevo", "no_observado"))
      ),
      layout_column_wrap(
        width = "200px", fill = FALSE,
        caja("c_suben", "Subieron", "arrow-up", "danger"),
        caja("c_bajan", "Bajaron", "arrow-down", "success"),
        caja("c_nuevos", "Nuevos", "plus", "primary"),
        caja("c_no_obs", "Dejaron de observarse", "eye-slash", "secondary")
      ),
      card(
        card_header("Detalle (mismo anuncio en el mismo comercio)"),
        p(class = "small text-muted",
          "Solo se comparan comercios con datos en las dos ejecuciones.",
          "Las filas resaltadas superan el umbral elegido."),
        DTOutput("tabla_cambios")
      )
    )
  ),

#Canasta
  nav_panel(
    "Canasta", value = "canasta",
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        selectInput("k_ejecucion", "Precios de la ejecución", choices = NULL),
        selectizeInput("k_productos", "Productos comparables", choices = NULL, multiple = TRUE,
                       options = list(placeholder = "Elija uno o más productos")),
        uiOutput("k_cantidades")
      ),
      div(class = "alert alert-warning",
          "El resultado no incluye costos de envío, mínimos de compra ni las condiciones",
          "de las promociones. Los precios son los del momento de la captura."),
      layout_column_wrap(
        width = "250px", fill = FALSE,
        caja("k_minimo", "Costo mínimo combinando comercios", "cart-shopping", "success"),
        caja("k_mejor", "Mejor comercio para comprar todo", "store"),
        caja("k_ahorro", "Ahorro al combinar comercios", "piggy-bank", "warning")
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("Costo de la canasta en cada comercio"), DTOutput("k_tabla_comercios")),
        card(card_header("Dónde comprar cada producto"), DTOutput("k_tabla_detalle"))
      )
    )
  ),

#Actualización
  nav_panel(
    "Actualizar datos", value = "actualizar",
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("Actualizar precios"),
        p("El botón ejecuta el scraper del Taller 1 (scraper.R) en segundo plano sobre",
          "Farmatodo, Cruz Verde y La Rebaja. Tarda unos minutos; puede seguir usando la",
          "aplicación mientras termina."),
        checkboxInput("modo_sin_conexion",
                      "Modo sin conexión: reprocesar las copias guardadas en raw/",
                      value = EN_SERVIDOR),
        input_task_button("actualizar", "Actualizar precios",
                          label_busy = "Actualizando...", icon = icon("rotate")),
        uiOutput("aviso_servidor"),
        uiOutput("estado_actualizacion")
      ),
      card(
        card_header("Resumen por comercio de la última actualización"),
        DTOutput("tabla_resumen_actualizacion")
      )
    ),
    navset_card_tab(
      nav_panel("Historial de ejecuciones", DTOutput("tabla_ejecuciones")),
      nav_panel("Detalle por comercio", DTOutput("tabla_ejecuciones_comercio")),
      nav_panel("Observaciones rechazadas", DTOutput("tabla_rechazos")),
      nav_panel("Correcciones", DTOutput("tabla_correcciones"))
    )
  ),

  nav_spacer(),
  nav_item(span(class = "small text-light", textOutput("fecha_datos", inline = TRUE)))
)
