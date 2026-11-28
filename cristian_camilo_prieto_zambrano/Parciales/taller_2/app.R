# =============================================================================
# app.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Comparador de precios de nutrición clínica (Locatel, Cruz Verde, Farmatodo).
# Ejecutar desde la carpeta taller_2:  shiny::runApp()
#
# Organización (ningún archivo concentra toda la aplicación):
#   app.R                   interfaz y lógica reactiva (sin SQL)
#   db.R                    consultas y estructura de la base (todo el SQL)
#   scraper.R               extracción; el botón de actualización la reutiliza
#   validacion.R            reglas de validación antes de insertar
#   tema.R                  estética, colores de los comercios y formatos
#   graficos.R              los cuatro gráficos (highcharter)
#   componentes.R           tarjetas de comparación, indicadores y canasta
#   modulo_actualizacion.R  botón de actualización (tarea en segundo plano)
# =============================================================================

library(shiny)
library(bslib)
library(highcharter)
library(DT)
library(promises)
library(future)

source("scraper.R")                # carga db.R y validacion.R
source("tema.R")
source("graficos.R")
source("componentes.R")
source("modulo_actualizacion.R")

plan(multisession)                 # la actualización corre en otro proceso
configurar_highcharter()

DB <- "comparador_precios.sqlite"
pool <- conectar_app(DB)
onStop(function() pool::poolClose(pool))
OPCIONES <- opciones_filtros(pool)

# Opciones del selector de ejecución
opciones_corrida <- function(corridas) {
  c("Más reciente de cada comercio" = "vigente",
    setNames(corridas$corrida,
             sprintf("%s%s", fecha_corrida(corridas$corrida),
                     ifelse(corridas$completas < corridas$comercios, " (incompleta)", ""))))
}
# Nombres visibles de los comparables (con su presentación), por id_producto
nombres_comparables <- function(comp) {
  setNames(nombre_comparable(comp$producto, comp$contenido_total, comp$unidad_norm), comp$id_producto)
}
opciones_comparables <- function(comp) {
  n <- nombres_comparables(comp)
  setNames(names(n), unname(n))
}
precio_tope <- function(op) max(10000, ceiling(op$precio$maximo / 10000) * 10000, na.rm = TRUE)

# Una entrada inválida (búsqueda, ejecución, cantidades) se muestra como
# mensaje en la salida, no como error técnico
seguro <- function(expr) {
  tryCatch(expr, entrada_invalida = function(e) shiny::validate(need(FALSE, conditionMessage(e))))
}

# -----------------------------------------------------------------------------
# Interfaz
# -----------------------------------------------------------------------------
panel_filtros <- sidebar(
  id = "panel", width = 300, title = "Filtros", open = "desktop",
  textInput("busqueda", NULL, placeholder = "Buscar: glucerna vainilla…"),
  uiOutput("aviso_busqueda"),
  selectInput("corrida", "Ejecución", choices = opciones_corrida(OPCIONES$corridas)),
  checkboxGroupInput("comercios", "Comercios",
                     choiceNames = lapply(names(COMERCIOS), insignia),
                     choiceValues = names(COMERCIOS), selected = names(COMERCIOS)),
  selectizeInput("subcategorias", "Subcategoría", choices = OPCIONES$subcategorias, multiple = TRUE,
                 options = list(placeholder = "Todas")),
  selectizeInput("marcas", "Marca", choices = OPCIONES$marcas, multiple = TRUE,
                 options = list(placeholder = "Todas")),
  sliderInput("precio", "Rango de precio (COP)", min = 0, max = precio_tope(OPCIONES),
              value = c(0, precio_tope(OPCIONES)), step = 1000, pre = "$", sep = ".", ticks = FALSE),
  input_switch("solo_promociones", "Solo promociones"),
  input_switch("solo_comparables", "Solo productos comparables"),
  actionButton("limpiar", "Limpiar filtros", icon = icon("rotate-left"),
               class = "btn-outline-secondary btn-sm"),
  div(class = "nota-filtros",
      "Los filtros aplican a Resumen, Productos y Cambios de precio. Evolución usa los comercios;",
      "la Canasta, la ejecución.")
)

encabezado_tarjeta <- function(titulo, subtitulo) {
  card_header(div(titulo, span(class = "sub", subtitulo)))
}

ui <- page_navbar(
  title = tags$span(icon("capsules"),
                    HTML(" Comparador<span class='marca-punto'>.</span>"),
                    tags$span(class = "d-none d-md-inline", style = "font-weight:600;color:#6B7280;margin-left:.35rem",
                              "Nutrición clínica")),
  id = "pestanas", theme = tema_app(), sidebar = panel_filtros, fillable = FALSE, lang = "es",
  window_title = "Comparador de precios · Nutrición clínica",

  nav_panel(
    "Resumen", value = "resumen", icon = icon("house"),
    div(class = "etiqueta-seccion", "Comparador de precios · Nutrición clínica"),
    h1(class = "titular", HTML("¿Dónde comprar <span class='acento'>más barato</span>?")),
    p(class = "bajada",
      "Fórmulas nutricionales, módulos de proteína y espesantes en Locatel, Cruz Verde y Farmatodo.",
      "Los precios se recolectan de los sitios de cada comercio y corresponden al momento de la consulta."),
    uiOutput("indicadores"),
    div(class = "etiqueta-seccion mt-4", "Precios comparados"),
    h2(class = "titular", style = "font-size:1.7rem", "El mismo producto, tres comercios"),
    p(class = "bajada",
      "Presentaciones idénticas en los tres comercios. El porcentaje es lo que se ahorra comprando en el más",
      "barato frente al más caro. Toque un precio para abrir el anuncio en el sitio."),
    uiOutput("tarjetas"),
    card(class = "mt-4",
         encabezado_tarjeta("¿En qué comercio conviene cada producto?",
                            "Precio por unidad de contenido (COP por g o por mL, según el producto) y cuánto más caro está cada comercio frente al más barato."),
         uiOutput("g_cuadricula_ui")),
    layout_columns(
      col_widths = breakpoints(sm = 12, xxl = c(6, 6)),
      card(encabezado_tarjeta("¿Cómo se distribuyen los precios en cada comercio?",
                              "Mínimo, cuartiles, mediana y máximo de los productos de la categoría con los filtros aplicados."),
           uiOutput("g_distribucion_ui")),
      card(encabezado_tarjeta("¿Conviene comprar la presentación grande?",
                              "Precio por unidad del tamaño pequeño (círculo vacío) y del grande (círculo lleno) del mismo producto, en cada comercio."),
           uiOutput("g_tamanos_ui"))
    )
  ),

  nav_panel(
    "Productos", value = "productos", icon = icon("table-list"),
    card(
      card_header(class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
                  div("Productos", span(class = "sub", textOutput("resumen_tabla", inline = TRUE))),
                  downloadButton("descargar", "Descargar CSV", class = "btn-sm btn-primary")),
      DTOutput("tabla", fill = FALSE)
    )
  ),

  nav_panel(
    "Evolución", value = "evolucion", icon = icon("chart-line"),
    card(
      card_header(class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
                  div("Evolución del precio", span(class = "sub", "Un producto comparable, una línea por comercio.")),
                  div(style = "min-width:300px",
                      selectInput("producto_evolucion", NULL, choices = opciones_comparables(OPCIONES$comparables),
                                  width = "100%"))),
      highchartOutput("g_evolucion", height = "430px")
    )
  ),

  nav_panel(
    "Cambios de precio", value = "cambios", icon = icon("arrow-right-arrow-left"),
    card(
      encabezado_tarjeta("Comparar dos ejecuciones",
                         "El mismo anuncio en el mismo comercio. Un cambio de presentación no se cuenta como cambio de precio."),
      layout_columns(
        col_widths = breakpoints(sm = 12, md = c(4, 4, 4)),
        selectInput("cambio_anterior", "Ejecución anterior", choices = NULL),
        selectInput("cambio_actual", "Ejecución actual", choices = NULL),
        sliderInput("umbral", "Resaltar variaciones de al menos", min = 0, max = 50, value = 10,
                    step = 1, post = " %", ticks = FALSE)
      ),
      uiOutput("cambios_resumen"),
      DTOutput("tabla_cambios", fill = FALSE)
    )
  ),

  nav_panel(
    "Canasta", value = "canasta", icon = icon("basket-shopping"),
    card(
      encabezado_tarjeta("Arme su canasta",
                         "Elija productos comparables y cantidades. Se usan los precios de una misma ejecución."),
      layout_columns(
        col_widths = breakpoints(sm = 12, lg = c(4, 8)),
        div(selectizeInput("canasta_productos", "Productos", choices = opciones_comparables(OPCIONES$comparables),
                           selected = head(OPCIONES$comparables$id_producto, 3), multiple = TRUE,
                           options = list(placeholder = "Elija uno o varios")),
            uiOutput("canasta_cantidades")),
        div(uiOutput("canasta_resultado"), DTOutput("canasta_detalle", fill = FALSE))
      )
    )
  ),

  nav_panel(
    "Datos", value = "datos", icon = icon("database"),
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(4, 8)),
      actualizacion_ui("actualizacion"),
      card(encabezado_tarjeta("Ejecuciones registradas",
                              "Cada consulta a un comercio. La vigente es la más reciente que no falló."),
           DTOutput("tabla_ejecuciones", fill = FALSE))
    )
  ),

  nav_spacer(),
  nav_item(uiOutput("fecha_datos"))
)

# -----------------------------------------------------------------------------
# Servidor
# -----------------------------------------------------------------------------
server <- function(input, output, session) {

  # Versión de los datos: la actualización la incrementa, lo que invalida la
  # caché de todas las consultas y refresca la aplicación sin reiniciarla
  version_datos <- reactiveVal(0L)
  actualizacion_server("actualizacion", db = DB,
                       al_terminar = function() version_datos(version_datos() + 1L))

  opciones <- reactive(opciones_filtros(pool)) |> bindCache(version_datos())
  nombres  <- reactive(nombres_comparables(opciones()$comparables))
  con_nombres <- function(d) {
    if (is.data.frame(d) && nrow(d) > 0 && "id_producto" %in% names(d)) {
      d$producto <- unname(nombres()[d$id_producto])
    }
    d
  }
  observeEvent(version_datos(), {
    op <- opciones()
    updateSelectInput(session, "corrida", choices = opciones_corrida(op$corridas),
                      selected = isolate(input$corrida))
    updateSelectizeInput(session, "subcategorias", choices = op$subcategorias,
                         selected = isolate(input$subcategorias))
    updateSelectizeInput(session, "marcas", choices = op$marcas, selected = isolate(input$marcas))
    tope <- precio_tope(op)
    updateSliderInput(session, "precio", max = tope,
                      value = c(isolate(input$precio)[1], max(isolate(input$precio)[2], tope)))
    recientes <- corridas_recientes(pool)
    opc <- setNames(op$corridas$corrida, fecha_corrida(op$corridas$corrida))
    updateSelectInput(session, "cambio_anterior", choices = opc, selected = recientes[["anterior"]])
    updateSelectInput(session, "cambio_actual", choices = opc, selected = recientes[["actual"]])
  })

  observeEvent(input$limpiar, {
    updateTextInput(session, "busqueda", value = "")
    updateSelectInput(session, "corrida", selected = "vigente")
    updateCheckboxGroupInput(session, "comercios", selected = names(COMERCIOS))
    updateSelectizeInput(session, "subcategorias", selected = character())
    updateSelectizeInput(session, "marcas", selected = character())
    updateSliderInput(session, "precio", value = c(0, precio_tope(opciones())))
    update_switch("solo_promociones", value = FALSE)
    update_switch("solo_comparables", value = FALSE)
  })

  # --- Filtros ----------------------------------------------------------------
  busqueda <- debounce(reactive(input$busqueda), 400)
  output$aviso_busqueda <- renderUI({
    b <- validar_busqueda(busqueda())
    if (!b$ok) div(class = "text-danger small mb-2", icon("circle-exclamation"), " ", b$mensaje)
  })

  filtros <- reactive({
    shiny::validate(need(length(input$comercios) > 0, "Seleccione al menos un comercio en el panel de filtros."))
    b <- validar_busqueda(busqueda())
    shiny::validate(need(b$ok, b$mensaje))
    rango <- input$precio
    tope <- precio_tope(opciones())
    list(
      comercios = if (setequal(input$comercios, names(COMERCIOS))) character() else input$comercios,
      subcategorias = input$subcategorias %||% character(),
      marcas = input$marcas %||% character(),
      precio_min = if (rango[1] > 0) rango[1] else NA_real_,
      precio_max = if (rango[2] < tope) rango[2] else NA_real_,
      corrida = input$corrida %||% "vigente",
      solo_promociones = isTRUE(input$solo_promociones),
      solo_comparables = isTRUE(input$solo_comparables),
      busqueda = busqueda() %||% ""
    )
  })

  # --- Consultas (en SQL, con caché que se invalida al actualizar) --------------
  ind     <- reactive({
    i <- seguro(indicadores(pool, filtros()))
    i$ahorro_maximo$tabla <- con_nombres(i$ahorro_maximo$tabla)
    i
  }) |> bindCache(filtros(), version_datos())
  tarj    <- reactive(con_nombres(seguro(tarjetas_comparables(pool, filtros())))) |>
    bindCache(filtros(), version_datos())
  matriz  <- reactive(con_nombres(seguro(matriz_comparables(pool, filtros())))) |>
    bindCache(filtros(), version_datos())
  dist    <- reactive(seguro(distribucion_precios(pool, filtros()))) |> bindCache(filtros(), version_datos())
  tamanos <- reactive(seguro(comparacion_tamanos(pool, filtros())))  |> bindCache(filtros(), version_datos())
  prods   <- reactive(seguro(productos_filtrados(pool, filtros())))  |> bindCache(filtros(), version_datos())
  ejec    <- reactive(listar_ejecuciones(pool))                       |> bindCache(version_datos())
  fechas  <- reactive(fecha_datos(pool))                              |> bindCache(version_datos())

  # --- Fecha de los datos (siempre visible) -------------------------------------
  output$fecha_datos <- renderUI({
    f <- fechas()
    if (nrow(f) == 0) return(span(class = "fecha-datos", "Sin datos"))
    span(class = "fecha-datos", icon("clock"), " Datos al ", strong(fecha_corta(max(f$fecha))))
  })

  # --- Resumen ------------------------------------------------------------------
  output$indicadores <- renderUI({
    layout_column_wrap(width = "250px", gap = "1rem", fill = FALSE, heights_equal = "row",
                       !!!cajas_indicadores(ind()))
  })
  output$tarjetas <- renderUI(tarjetas_comparacion(tarj()))

  # Gráficos con altura según los datos; sin datos, un mensaje en su lugar
  output$g_cuadricula_ui <- renderUI({
    n <- length(unique(matriz()$id_producto))
    if (n == 0) return(mensaje_vacio("Ningún producto comparable cumple los filtros."))
    highchartOutput("g_cuadricula", height = paste0(90 + 52 * n, "px"))
  })
  output$g_cuadricula <- renderHighchart(grafico_cuadricula(matriz()))

  output$g_distribucion_ui <- renderUI({
    if (nrow(dist()) == 0) return(mensaje_vacio("Ningún producto con precio cumple los filtros."))
    highchartOutput("g_distribucion", height = "340px")
  })
  output$g_distribucion <- renderHighchart(grafico_distribucion(dist()))

  output$g_tamanos_ui <- renderUI({
    n <- nrow(tamanos())
    if (n == 0) return(mensaje_vacio("Ningún producto con dos tamaños y precio en los comercios elegidos cumple los filtros."))
    highchartOutput("g_tamanos", height = paste0(90 + 64 * n, "px"))
  })
  output$g_tamanos <- renderHighchart(grafico_tamanos(tamanos()))

  # --- Productos ----------------------------------------------------------------
  output$resumen_tabla <- renderText({
    d <- prods()
    sprintf("%s productos · %s", numero(nrow(d)),
            if (identical(filtros()$corrida, "vigente")) "ejecución más reciente de cada comercio"
            else paste("corrida del", fecha_corrida(filtros()$corrida)))
  })
  output$tabla <- renderDT({
    d <- prods()
    shiny::validate(need(nrow(d) > 0, "Ningún producto cumple los filtros. Pruebe quitar alguno."))
    t <- data.frame(
      Comercio = insignia_html(d$id_comercio),
      Producto = sprintf("<b>%s</b><br><span class='nota-filtros'>%s · %s</span>",
                         htmltools::htmlEscape(d$nombre), htmltools::htmlEscape(d$marca),
                         htmltools::htmlEscape(d$subcategoria)),
      Presentación = presentacion(d$contenido_total, d$unidad_norm),
      Precio = d$precio, `Precio por unidad` = cop_unidad(d$precio_unitario, d$unidad_norm),
      pu = d$precio_unitario,
      Promoción = ifelse(d$promocion == 1, "Sí", "No"),
      Disponibilidad = ifelse(d$disponibilidad == "agotado", "Agotado", "Disponible"),
      Consulta = fecha_corta(d$fecha_hora_consulta),
      Anuncio = sprintf('<a href="%s" target="_blank" rel="noopener">Ver</a>', d$url),
      check.names = FALSE)
    datatable(
      t, rownames = FALSE, fillContainer = FALSE, escape = setdiff(seq_len(ncol(t)), c(1, 2, 10)),
      selection = "none", class = "hover row-border",
      colnames = c("Precio (COP)" = "Precio"),
      options = list(
        pageLength = 15, lengthMenu = c(15, 30, 60), order = list(list(3, "asc")), scrollX = TRUE,
        columnDefs = list(list(targets = 4, orderData = 5), list(targets = 5, visible = FALSE),
                          list(targets = c(0, 2, 3, 4, 8), className = "sin-corte")),
        language = list(search = "Buscar en la tabla:", lengthMenu = "Mostrar _MENU_",
                        info = "_START_ a _END_ de _TOTAL_ productos", infoEmpty = "Sin productos",
                        infoFiltered = "(de _MAX_)", zeroRecords = "Sin resultados",
                        paginate = list(previous = "Anterior", `next` = "Siguiente")))
    ) |>
      formatCurrency("Precio (COP)", currency = "$", mark = ".", dec.mark = ",", digits = 0)
  })
  output$descargar <- downloadHandler(
    filename = function() sprintf("productos_filtrados_%s.csv", format(Sys.Date(), "%Y%m%d")),
    content = function(archivo) {
      d <- prods()
      readr::write_excel_csv2(data.frame(
        comercio = d$comercio, producto = d$nombre, marca = d$marca, subcategoria = d$subcategoria,
        contenido_total = d$contenido_total, unidad = d$unidad_norm, precio_cop = d$precio,
        precio_por_unidad_cop = round(d$precio_unitario, 2), precio_lista_cop = d$precio_lista,
        promocion = d$promocion, disponibilidad = d$disponibilidad,
        fecha_hora_consulta = d$fecha_hora_consulta, corrida = d$corrida, url = d$url), archivo)
    })

  # --- Evolución ----------------------------------------------------------------
  evol <- reactive({
    req(input$producto_evolucion)
    seguro(serie_precio(pool, input$producto_evolucion, list(comercios = filtros()$comercios)))
  }) |> bindCache(input$producto_evolucion, filtros()$comercios, version_datos())
  output$g_evolucion <- renderHighchart({
    d <- evol()
    shiny::validate(need(nrow(d[d$coincide == 1 & !is.na(d$precio), ]) > 0,
                  "No hay precios de este producto en los comercios elegidos."))
    nombre <- nombres()[[input$producto_evolucion]]
    grafico_evolucion(d, nombre)
  })

  # --- Cambios de precio --------------------------------------------------------
  cambios <- reactive({
    req(input$cambio_anterior, input$cambio_actual)
    shiny::validate(need(input$cambio_anterior != input$cambio_actual, "Elija dos ejecuciones distintas."))
    seguro(comparar_ejecuciones(pool, input$cambio_anterior, input$cambio_actual,
                                umbral_pct = input$umbral, f = filtros()))
  }) |> bindCache(input$cambio_anterior, input$cambio_actual, input$umbral, filtros(), version_datos())

  output$cambios_resumen <- renderUI({
    cc <- cambios()
    r <- cc$resumen
    caja <- function(i) {
      id <- names(COMERCIOS)[match(r$comercio[i], COMERCIOS)]
      div(class = "tarjeta-comp",
          div(class = "encabezado", insignia(id),
              span(class = "tiendas", paste(r$destacados[i], plural(r$destacados[i], "destacado", "destacados")))),
          div(style = "display:flex;gap:1rem;flex-wrap:wrap;font-size:.9rem",
              span(icon("arrow-up", style = "color:#9A3412"), strong(r$subieron[i]),
                   plural(r$subieron[i], " subió", " subieron")),
              span(icon("arrow-down", style = "color:#1E40AF"), strong(r$bajaron[i]),
                   plural(r$bajaron[i], " bajó", " bajaron")),
              span(strong(r$nuevos[i]), plural(r$nuevos[i], " nuevo", " nuevos")),
              span(strong(r$no_observados[i]), plural(r$no_observados[i], " no observado", " no observados"))))
    }
    tagList(
      if (nrow(r) > 0) layout_column_wrap(width = "240px", gap = "1rem", fill = FALSE,
                                          !!!lapply(seq_len(nrow(r)), caja)),
      if (length(cc$omitidos) > 0)
        div(class = "aviso-canasta mt-2", icon("circle-info"),
            sprintf(" Sin datos en alguna de las dos ejecuciones: %s. No se compara.",
                    paste(cc$omitidos, collapse = ", "))),
      div(class = "nota-filtros mt-2 mb-2",
          sprintf("Del %s al %s. Filas resaltadas: variación de %s %% o más.",
                  fecha_corrida(cc$corrida_anterior), fecha_corrida(cc$corrida_actual), cc$umbral_pct))
    )
  })
  output$tabla_cambios <- renderDT({
    d <- cambios()$cambios
    shiny::validate(need(nrow(d) > 0, "No hay productos para comparar con los filtros elegidos."))
    t <- data.frame(
      Comercio = insignia_html(d$id_comercio), Producto = d$nombre, Cambio = d$tipo_cambio,
      Antes = d$precio_anterior, Ahora = d$precio_actual, Diferencia = d$diferencia,
      `Variación (%)` = d$variacion_pct, destacado = d$destacado, check.names = FALSE)
    datatable(t, rownames = FALSE, fillContainer = FALSE, escape = -1, selection = "none",
              class = "hover row-border",
              colnames = c("Antes (COP)" = "Antes", "Ahora (COP)" = "Ahora", "Diferencia (COP)" = "Diferencia"),
              options = list(pageLength = 15, scrollX = TRUE, order = list(),
                             columnDefs = list(list(targets = 7, visible = FALSE)),
                             language = list(search = "Buscar:", lengthMenu = "Mostrar _MENU_",
                                             info = "_START_ a _END_ de _TOTAL_", zeroRecords = "Sin resultados",
                                             paginate = list(previous = "Anterior", `next` = "Siguiente")))) |>
      formatCurrency(c("Antes (COP)", "Ahora (COP)", "Diferencia (COP)"), currency = "$",
                     mark = ".", dec.mark = ",", digits = 0) |>
      formatRound("Variación (%)", digits = 1, mark = ".", dec.mark = ",") |>
      formatStyle("destacado", target = "row", backgroundColor = styleEqual(1, "#FFF3EC"),
                  fontWeight = styleEqual(1, "600"))
  })

  # --- Canasta ------------------------------------------------------------------
  output$canasta_cantidades <- renderUI({
    ids <- input$canasta_productos
    if (length(ids) == 0) return(NULL)
    tagList(div(class = "nota-filtros mb-1", "Cantidades"),
            lapply(ids, function(id) {
              previo <- isolate(input[[paste0("cant_", id)]])
              numericInput(paste0("cant_", id), nombres()[[id]],
                           value = if (is.null(previo)) 1 else previo, min = 1, max = 99, step = 1)
            }))
  })
  cantidades <- reactive({
    ids <- input$canasta_productos
    vapply(ids, function(id) as.numeric(input[[paste0("cant_", id)]] %||% 1), numeric(1))
  })
  canasta <- reactive({
    ids <- input$canasta_productos
    shiny::validate(need(length(ids) > 0, "Elija al menos un producto para armar la canasta."))
    corrida <- if (identical(input$corrida, "vigente")) NULL else input$corrida
    k <- seguro(costo_canasta(pool, ids, cantidades(), corrida = corrida))
    k$detalle <- con_nombres(k$detalle)
    # Los faltantes llegan como códigos (P03, P07): se muestran con su nombre
    k$por_comercio$faltantes <- vapply(k$por_comercio$faltantes, function(x) {
      if (is.na(x)) return(NA_character_)
      paste(nombres()[trimws(strsplit(x, ",")[[1]])], collapse = ", ")
    }, character(1), USE.NAMES = FALSE)
    k
  }) |> bindCache(input$canasta_productos, cantidades(), input$corrida, version_datos())

  output$canasta_resultado <- renderUI(resultado_canasta(canasta()))
  output$canasta_detalle <- renderDT({
    d <- canasta()$detalle
    t <- data.frame(Producto = d$producto, Cantidad = d$cantidad, `Precio más bajo` = d$precio_min,
                    Subtotal = d$subtotal, `Dónde` = ifelse(is.na(d$donde), "Sin precio", d$donde),
                    check.names = FALSE)
    datatable(t, rownames = FALSE, fillContainer = FALSE, selection = "none",
              options = list(dom = "t", paging = FALSE, ordering = FALSE)) |>
      formatCurrency(c("Precio más bajo", "Subtotal"), currency = "$", mark = ".", dec.mark = ",", digits = 0)
  })

  # --- Datos --------------------------------------------------------------------
  output$tabla_ejecuciones <- renderDT({
    d <- ejec()
    t <- data.frame(
      Fecha = fecha_corta(d$fecha), Comercio = insignia_html(d$id_comercio),
      Estado = ifelse(d$vigente == 1, paste(d$estado, "· vigente"), d$estado),
      Modo = ifelse(d$modo == "en_linea", "en línea", "sin conexión"),
      Recolectados = ifelse(is.na(d$total_sitio), numero(d$n_registros),
                            sprintf("%s de %s", numero(d$n_registros), numero(d$total_sitio))),
      `Válidas` = d$n_observaciones, Rechazos = d$n_rechazos,
      Motivo = ifelse(is.na(d$motivo), "", d$motivo), check.names = FALSE)
    datatable(t, rownames = FALSE, fillContainer = FALSE, escape = -2, selection = "none",
              class = "hover row-border nowrap",
              options = list(pageLength = 10, scrollX = TRUE, ordering = FALSE,
                             language = list(lengthMenu = "Mostrar _MENU_", search = "Buscar:",
                                             info = "_START_ a _END_ de _TOTAL_",
                                             paginate = list(previous = "Anterior", `next` = "Siguiente"))))
  })
}

shinyApp(ui, server)
