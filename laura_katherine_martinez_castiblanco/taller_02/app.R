# =============================================================================
# app.R · Comparador de precios de bebidas (Taller 2 · Minería de Datos · UNAL)
# Ejecutar:  shiny::runApp()   desde la carpeta taller_2/  (rutas relativas; sin setwd())
# Estructura: app.R (UI + servidor) · db.R (SQL) · scraper.R (Taller 1) · validacion.R (lógica)
#             actualizacion.R (botón) · modulos/ (una pestaña por archivo) · sql/ (migración y vistas)
# =============================================================================
library(shiny); library(bslib); library(promises); library(future)
plan(multisession, workers = 2)

# --- Carga de módulos (orden importa: validacion.R redefine validar_obs() de scraper.R) ---
source("config.R", encoding = "UTF-8")
SCRAPER_OK <- tryCatch({ source("scraper.R", encoding = "UTF-8"); TRUE }, error = function(e) { message("scraper.R no se pudo cargar: ", conditionMessage(e)); FALSE })
for (f in c("validacion.R", "db.R", "actualizacion.R", "utils_ui.R", list.files("modulos", pattern = "\\.R$", full.names = TRUE)))
  source(f, encoding = "UTF-8")

if (!file.exists(DB_PATH)) stop("No se encontró ", DB_PATH, ". Copie aquí la base del Taller 1 (ver README.md).")
db_migrar()   # idempotente: tablas, vistas e índices del Taller 2

tema <- bs_theme(version = 5, primary = "#0E8F6B", secondary = "#5B6B7F", "border-radius" = ".6rem",
                 base_font = font_collection("Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"))

# ------------------------------------------------------------------------------
# INTERFAZ
# ------------------------------------------------------------------------------
ui <- page_navbar(
  title = tagList(icon("scale-balanced"), "Comparador de precios"),
  id = "nav", theme = tema, fillable = FALSE, lang = "es", window_title = "Comparador de precios · bebidas",
  header = tags$head(tags$link(rel = "stylesheet", href = "estilos.css")),
  sidebar = sidebar(id = "sb", width = 310, open = "desktop",
    div(class = "leyenda-comercios", lapply(names(COLOR_COMERCIO), function(cm) span(class = "chip", tags$i(style = paste0("background:", COLOR_COMERCIO[[cm]])), cm))),
    div(class = "sidebar-titulo", "Dónde y qué"),
    selectizeInput("comercios", "Comercio", choices = NULL, multiple = TRUE, options = list(plugins = list("remove_button"), placeholder = "Todos")),
    selectizeInput("subcategorias", "Subcategoría", choices = NULL, multiple = TRUE, options = list(plugins = list("remove_button"), placeholder = "Todas")),
    selectizeInput("marcas", "Marca", choices = NULL, multiple = TRUE, options = list(plugins = list("remove_button"), placeholder = "Todas")),
    div(class = "sidebar-titulo", "Precio y fecha"),
    sliderInput("precio", "Rango de precio (COP)", min = 0, max = 100000, value = c(0, 100000), step = 50, pre = "$ ", sep = "."),
    selectInput("ejec", "Ejecución / fecha de los datos", choices = c("Última ejecución" = "__ultima__")),
    div(class = "sidebar-titulo", "Opciones"),
    checkboxInput("solo_promo", "Solo promociones", FALSE),
    checkboxInput("solo_comparables", "Solo productos comparables", FALSE),
    textInput("texto", "Buscar en nombre o anuncio", placeholder = "p. ej. coca cola 1,5"),
    actionButton("reset", "Restablecer filtros", icon = icon("rotate-left"), class = "btn-sm btn-outline-secondary w-100")),
  nav_panel("Resumen", value = "resumen", icon = icon("gauge-high"), resumen_ui("res")),
  nav_panel("Comparador", value = "comparador", icon = icon("scale-balanced"), comparador_ui("cmp")),
  nav_panel("Evolución", value = "evolucion", icon = icon("chart-line"), historial_ui("his")),
  nav_panel("Cambios de precio", value = "cambios", icon = icon("arrows-up-down"), cambios_ui("cam")),
  nav_panel("Canasta", value = "canasta", icon = icon("basket-shopping"), canasta_ui("can")),
  nav_panel("Tabla", value = "tabla", icon = icon("table"), tabla_ui("tab")),
  nav_panel("Actualizar", value = "actualizar", icon = icon("rotate"), actualizar_ui("act")),
  nav_panel("Datos y auditoría", value = "datos", icon = icon("shield-halved"), datos_ui("dat")),
  nav_spacer(),
  nav_item(input_dark_mode(id = "modo"))
)

# ------------------------------------------------------------------------------
# SERVIDOR
# ------------------------------------------------------------------------------
server <- function(input, output, session) {
  version <- reactiveVal(0)                         # se incrementa al terminar una actualización (invalida caché y catálogos)
  catalogos <- reactive({ version(); db_catalogos() })

  # Los controles se llenan con catálogos obtenidos por SQL (no se carga la tabla completa)
  observeEvent(catalogos(), {
    cat <- catalogos(); co <- cat$corridas
    updateSelectizeInput(session, "comercios", choices = cat$comercios,
                         selected = if (is.null(input$comercios)) cat$comercios else intersect(input$comercios, cat$comercios))
    updateSelectizeInput(session, "subcategorias", choices = cat$subcategorias, selected = intersect(input$subcategorias, cat$subcategorias))
    updateSelectizeInput(session, "marcas", choices = cat$marcas, selected = intersect(input$marcas, cat$marcas), server = TRUE)
    lo <- floor(cat$rango_precio[["lo"]]); hi <- ceiling(cat$rango_precio[["hi"]])
    if (is.finite(lo) && is.finite(hi)) updateSliderInput(session, "precio", min = lo, max = hi, value = c(lo, hi))
    ch <- c("Última ejecución" = "__ultima__", "Todas las ejecuciones" = "__todas__",
            setNames(co$id_corrida, paste0(fmt_fecha(co$fecha_hora), " · ", co$id_corrida, " (", fmt_num(co$n_obs), " obs · ", co$estado, ")")))
    updateSelectInput(session, "ejec", choices = ch, selected = if (isTruthy(input$ejec) && input$ejec %in% ch) input$ejec else "__ultima__")
  })

  texto_deb <- debounce(reactive(input$texto), 500)
  filtros <- reactive({
    cat <- catalogos(); co <- cat$corridas$id_corrida
    ej <- input$ejec %||% "__ultima__"
    corridas <- if (!length(co)) NULL else if (ej == "__todas__") NULL else if (ej %in% co) ej else co[1]
    lo <- floor(cat$rango_precio[["lo"]]); hi <- ceiling(cat$rango_precio[["hi"]]); pr <- input$precio
    precio <- if (length(pr) == 2 && is.numeric(pr) && (pr[1] > lo || pr[2] < hi)) pr else NULL
    list(comercios = input$comercios, subcategorias = input$subcategorias, marcas = input$marcas, precio = precio,
         corridas = corridas, solo_promo = isTRUE(input$solo_promo), solo_comparables = isTRUE(input$solo_comparables),
         texto = validar_texto(texto_deb(), 60))
  })
  corrida <- reactive({
    f <- filtros()
    if (length(f$corridas) == 1) return(f$corridas)
    cc <- catalogos()$corridas_comp
    if (nrow(cc)) cc$id_corrida[1] else catalogos()$corridas$id_corrida[1]
  })

  observeEvent(input$reset, {
    cat <- catalogos()
    updateSelectizeInput(session, "comercios", selected = cat$comercios)
    updateSelectizeInput(session, "subcategorias", selected = character(0)); updateSelectizeInput(session, "marcas", selected = character(0))
    updateSliderInput(session, "precio", value = c(floor(cat$rango_precio[["lo"]]), ceiling(cat$rango_precio[["hi"]])))
    updateSelectInput(session, "ejec", selected = "__ultima__")
    updateCheckboxInput(session, "solo_promo", value = FALSE); updateCheckboxInput(session, "solo_comparables", value = FALSE)
    updateTextInput(session, "texto", value = "")
  })

  resumen_server("res", filtros, catalogos, version, corrida)
  comparador_server("cmp", filtros, catalogos, version, corrida)
  historial_server("his", filtros, catalogos, version)
  cambios_server("cam", filtros, catalogos, version)
  canasta_server("can", filtros, catalogos, version, corrida)
  tabla_server("tab", filtros, catalogos, version)
  actualizar_server("act", version)
  datos_server("dat", version)
}

shinyApp(ui, server)
