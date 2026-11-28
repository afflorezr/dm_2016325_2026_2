# app.R · Comparador de precios de perfumes
# Interfaz y servidor. Las consultas están en db.R. El botón de actualizar
# corre ejecutar_recoleccion() de scraper.R en segundo plano.
#
# Para correrla: abrir este archivo en RStudio y presionar "Run App", o
#   shiny::runApp()

library(shiny)
library(bslib)
library(highcharter)
library(DT)
library(promises)
library(future)

source("db.R", encoding = "UTF-8")

plan(multisession)   # la actualización corre en otra sesión de R

con <- abrir_conexion()
onStop(function() dbDisconnect(con))

# Mismo color para cada comercio en toda la aplicación
COLORES <- c("La Riviera" = "#1b9e77", "Falabella" = "#d95f02", "Farmatodo" = "#7570b3")

# Separador de miles en los gráficos
options(highcharter.lang = list(thousandsSep = ".", decimalPoint = ","))

cop <- function(x) ifelse(is.na(x), "-", paste0("$", format(round(x), big.mark = ".", decimal.mark = ",", trim = TRUE)))
fecha_texto <- function(f) format(as.Date(f), "%d/%m/%Y")

# Textos de las tablas DT en español
DT_ES <- list(search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas", info = "_START_ a _END_ de _TOTAL_",
              infoEmpty = "Sin filas", infoFiltered = "(de _MAX_ en total)", zeroRecords = "Ninguna fila cumple",
              thousands = ".", paginate = list(previous = "Anterior", `next` = "Siguiente"))

ejecuciones <- lista_ejecuciones(con)
opciones_ejecucion <- setNames(ejecuciones$id_ejecucion, fecha_texto(ejecuciones$fecha))
rango <- rango_precios(con)
comparables <- lista_comparables(con)
opciones_comparables <- setNames(comparables$producto_id, comparables$presentacion)
# Comparar abre en una presentación que tenga precios en la última ejecución
con_datos <- ahorro_por_presentacion(con, ejecuciones$id_ejecucion[1])$presentacion
comparable_inicial <- opciones_comparables[names(opciones_comparables) %in% con_datos][1]

# ---- Interfaz ----
filtros <- sidebar(
  width = 280,
  selectInput("ejecucion", "Ejecución (fecha de los datos)", choices = opciones_ejecucion),
  checkboxGroupInput("comercios", "Comercio", choices = names(COLORES), selected = names(COLORES)),
  selectInput("subcategoria", "Subcategoría", choices = c("Todas", lista_subcategorias(con), "Sin clasificar")),
  selectizeInput("marca", "Marca", choices = c("Todas", lista_marcas(con))),
  sliderInput("precio", "Precio (COP)", min = 0, max = ceiling(rango$maximo / 1e5) * 1e5,
              value = c(0, ceiling(rango$maximo / 1e5) * 1e5), step = 10000, pre = "$", sep = "."),
  checkboxInput("solo_promo", "Solo promociones", FALSE),
  checkboxInput("solo_comparables", "Solo comparables", FALSE),
  textInput("busqueda", "Buscar por nombre o marca", placeholder = "Ej.: Versace Eros"),
  helpText("Letras, números y espacios; máximo 60 caracteres.")
)

ui <- page_navbar(
  title = "Comparador de precios de perfumes",
  theme = bs_theme(version = 5, bootswatch = "zephyr"),
  sidebar = filtros,
  fillable = FALSE,   # la página se desplaza; los gráficos conservan su altura

  nav_panel("Resumen",
    textOutput("fecha_datos"),
    layout_columns(
      col_widths = c(4, 4, 4), fill = FALSE,
      value_box("Productos en la categoría", textOutput("v_productos"), textOutput("v_productos_detalle")),
      value_box("Última ejecución", textOutput("v_ultima"), textOutput("v_ultima_estado")),
      value_box("Productos en promoción", textOutput("v_promo"), "porcentaje de la ejecución elegida"),
      value_box("Precio mediano", textOutput("v_mediana"), textOutput("v_mediana_detalle")),
      value_box("Ahorro máximo entre comercios", textOutput("v_ahorro"), textOutput("v_ahorro_detalle")),
      value_box("Cambios de precio", textOutput("v_cambios"), "frente a la ejecución anterior")
    ),
    layout_columns(
      card(min_height = 460, card_header("Distribución de precios por comercio (COP)"), highchartOutput("g_distribucion", height = "400px")),
      card(min_height = 460, card_header("¿Qué comercio tiene el menor precio más veces?"), highchartOutput("g_mas_barato", height = "400px"))
    )
  ),

  nav_panel("Comparar",
    selectInput("producto", "Presentación comparable", choices = opciones_comparables,
                  selected = comparable_inicial, width = "400px"),
    layout_columns(
      card(min_height = 460, card_header("Evolución del precio (COP)"), highchartOutput("g_evolucion", height = "400px")),
      card(min_height = 460, card_header("Diferencia de precio entre comercios"), DTOutput("t_ahorro"))
    ),
    card(min_height = 760, card_header("Precio por mL de las presentaciones comparables (COP por mL)"),
         p("Cada fila es una presentación y cada punto el precio por mL en un comercio. Más a la izquierda es más barato."),
         highchartOutput("g_precio_ml", height = "650px"))
  ),

  nav_panel("Cambios de precio",
    layout_columns(
      col_widths = c(4, 4, 4),
      selectInput("ejec_a", "Ejecución anterior", choices = opciones_ejecucion,
                  selected = opciones_ejecucion[min(2, length(opciones_ejecucion))]),
      selectInput("ejec_b", "Ejecución reciente", choices = opciones_ejecucion,
                  selected = opciones_ejecucion[1]),
      sliderInput("umbral", "Resaltar variaciones mayores a (%)", min = 5, max = 100, value = 20, step = 5)
    ),
    p("Se aplican los filtros del panel lateral. Las filas en amarillo superan el umbral."),
    textOutput("resumen_cambios"),
    card(DTOutput("t_cambios", fill = FALSE))
  ),

  nav_panel("Canasta",
    p("Elija presentaciones comparables y la cantidad de cada una. Se usan los precios de la ejecución elegida en el panel lateral."),
    selectizeInput("canasta", "Presentaciones", choices = opciones_comparables, multiple = TRUE, width = "600px"),
    uiOutput("cantidades"),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Costo de la canasta por comercio"), tableOutput("t_canasta")),
      card(card_header("Comprando cada producto donde es más barato"), uiOutput("canasta_minimo"))
    ),
    p(em("El resultado no incluye costos de envío, compras mínimas ni las condiciones de las promociones."))
  ),

  nav_panel("Productos",
    downloadButton("descargar", "Descargar CSV"),
    card(DTOutput("t_productos", fill = FALSE))
  ),

  nav_panel("Actualizar",
    radioButtons("modo", "Modo", choices = c("En línea" = "en_linea", "Sin conexión" = "sin_conexion"),
                 inline = TRUE),
    input_task_button("actualizar", "Actualizar precios", label_busy = "Actualizando..."),
    br(),
    uiOutput("mensaje_actualizacion"),
    tableOutput("t_resumen_actualizacion")
  )
)

# ---- Servidor ----
server <- function(input, output, session) {

  # sube en 1 al terminar una actualización, para invalidar la caché
  version <- reactiveVal(0)

  # filtros en una lista, como los espera db.R
  f <- reactive({
    req(input$ejecucion)
    list(ejecucion = input$ejecucion, comercios = input$comercios,
         subcategoria = input$subcategoria, marca = input$marca,
         precio_min = input$precio[1], precio_max = input$precio[2],
         solo_promo = input$solo_promo, solo_comparables = input$solo_comparables,
         busqueda = input$busqueda)
  })

  productos <- reactive({
    precios_filtrados(con, f())
  }) |> bindCache(f(), version())

  observeEvent(input$busqueda, {
    if (nzchar(input$busqueda) && limpiar_busqueda(input$busqueda) == "") {
      showNotification("La búsqueda solo admite letras, números y espacios (máximo 60 caracteres).",
                       type = "warning")
    }
  })

  # ---- Resumen ---------------------------------------------------------------
  fecha_ejecucion <- reactive({
    e <- lista_ejecuciones(con)
    e[e$id_ejecucion == input$ejecucion, ]
  }) |> bindCache(input$ejecucion, version())

  output$fecha_datos <- renderText({
    paste("Datos de la ejecución del", fecha_texto(fecha_ejecucion()$fecha),
          "· Precios en pesos colombianos (COP) · La categoría es perfumes")
  })

  conteo <- reactive(productos_por_comercio(con, input$ejecucion)) |> bindCache(input$ejecucion, version())
  output$v_productos <- renderText(format(sum(conteo()$productos), big.mark = ".", decimal.mark = ","))
  output$v_productos_detalle <- renderText(
    paste0(conteo()$comercio, ": ", format(conteo()$productos, big.mark = ".", decimal.mark = ",", trim = TRUE), collapse = " · "))

  output$v_ultima <- renderText({
    version()
    fecha_texto(lista_ejecuciones(con)$fecha[1])
  })
  output$v_ultima_estado <- renderText({
    version()
    e <- estado_ejecucion(con, ultima_ejecucion(con))
    paste0(e$comercio, ": ", e$estado, collapse = " · ")
  })

  output$v_promo <- renderText(paste0(format(proporcion_promocion(con, input$ejecucion), decimal.mark = ","), " %")) |>
    bindCache(input$ejecucion, version())

  medianas <- reactive(mediana_por_subcategoria(con, input$ejecucion)) |> bindCache(input$ejecucion, version())
  output$v_mediana <- renderText({
    m <- medianas()
    if (input$subcategoria %in% m$subcategoria) cop(m$mediana[m$subcategoria == input$subcategoria])
    else cop(median(productos()$precio))
  })
  output$v_mediana_detalle <- renderText({
    paste0(sub("Perfume ", "", medianas()$subcategoria), ": ", cop(medianas()$mediana), collapse = " · ")
  })

  ahorro <- reactive(ahorro_por_presentacion(con, input$ejecucion)) |> bindCache(input$ejecucion, version())
  output$v_ahorro <- renderText(cop(ahorro()$ahorro[1]))
  output$v_ahorro_detalle <- renderText(paste("en", ahorro()$presentacion[1]))

  output$v_cambios <- renderText(numero_cambios(con, input$ejecucion)) |> bindCache(input$ejecucion, version())

  output$g_distribucion <- renderHighchart({
    d <- productos()
    shiny::validate(need(nrow(d) > 0, "Ningún producto cumple los filtros elegidos."))
    cajas <- data_to_boxplot(d, precio, comercio, add_outliers = FALSE, name = "Precio")
    highchart() |>
      hc_xAxis(type = "category") |>
      hc_add_series_list(cajas) |>
      hc_plotOptions(boxplot = list(colorByPoint = TRUE)) |>
      hc_colors(unname(COLORES[sort(unique(d$comercio))])) |>
      hc_yAxis(title = list(text = "Precio (COP)")) |>
      hc_tooltip(valuePrefix = "$") |>
      hc_legend(enabled = FALSE)
  })

  output$g_mas_barato <- renderHighchart({
    d <- veces_mas_barato(con, input$ejecucion)
    shiny::validate(need(nrow(d) > 0, "No hay presentaciones comparables en esta ejecución."))
    d$color <- COLORES[d$comercio]
    hchart(d, "column", hcaes(x = comercio, y = veces, color = color), name = "Presentaciones") |>
      hc_yAxis(title = list(text = "Presentaciones donde es el más barato")) |>
      hc_xAxis(title = list(text = NULL))
  }) |> bindCache(input$ejecucion, version())

  # ---- Comparar --------------------------------------------------------------
  # Las fechas van como categorías porque hay pocas ejecuciones. Si un comercio
  # no tuvo la presentación en una fecha, el punto queda vacío.
  output$g_evolucion <- renderHighchart({
    req(input$producto)
    d <- evolucion_precio(con, input$producto)
    shiny::validate(need(nrow(d) > 0, "No hay precios para esta presentación."))
    fechas <- sort(unique(d$fecha))
    g <- highchart() |>
      hc_xAxis(categories = as.list(fecha_texto(fechas)), title = list(text = "Fecha de la ejecución")) |>
      hc_yAxis(title = list(text = "Precio (COP)"), labels = list(format = "${value:,.0f}")) |>
      hc_tooltip(shared = TRUE, valuePrefix = "$", valueDecimals = 0)
    for (comercio in intersect(names(COLORES), d$comercio)) {
      x <- d[d$comercio == comercio, ]
      g <- g |> hc_add_series(name = comercio, type = "line", color = unname(COLORES[comercio]),
                              data = x$precio[match(fechas, x$fecha)], marker = list(radius = 6))
    }
    g
  }) |> bindCache(input$producto, version())

  output$t_ahorro <- renderDT({
    d <- ahorro()
    shiny::validate(need(nrow(d) > 0, "No hay presentaciones comparables en esta ejecución."))
    d <- d[, c("presentacion", "precio_min", "precio_max", "ahorro")]
    datatable(d, rownames = FALSE, options = list(pageLength = 8, dom = "tp", language = DT_ES),
              colnames = c("Presentación", "Precio más bajo", "Precio más alto", "Diferencia (COP)")) |>
      formatCurrency(2:4, currency = "$", mark = ".", dec.mark = ",", digits = 0)
  })

  # una fila por presentación, un punto por comercio, de menor a mayor precio por mL
  output$g_precio_ml <- renderHighchart({
    d <- precio_por_ml(con, input$ejecucion)
    d <- d[d$comercio %in% input$comercios, ]
    shiny::validate(need(nrow(d) > 0, "No hay presentaciones comparables para los comercios elegidos."))
    minimo <- tapply(d$precio_por_ml, d$presentacion, min)
    orden <- names(sort(minimo))
    g <- highchart() |>
      hc_chart(type = "scatter", inverted = TRUE) |>
      hc_xAxis(categories = orden, title = list(text = NULL), gridLineWidth = 1) |>
      hc_yAxis(title = list(text = "COP por mL"), labels = list(format = "${value:,.0f}")) |>
      hc_tooltip(pointFormat = "{series.name}: <b>${point.y:,.0f} por mL</b>")
    for (comercio in intersect(names(COLORES), d$comercio)) {
      x <- d[d$comercio == comercio, ]
      puntos <- data.frame(x = match(x$presentacion, orden) - 1, y = x$precio_por_ml)
      g <- g |> hc_add_series(name = comercio, color = unname(COLORES[comercio]),
                              data = list_parse2(puntos), marker = list(radius = 6, symbol = "circle"))
    }
    g
  })

  # ---- Cambios de precio -----------------------------------------------------
  cambios <- reactive({
    shiny::validate(need(input$ejec_a != input$ejec_b, "Elija dos ejecuciones distintas."))
    a <- min(input$ejec_a, input$ejec_b)
    b <- max(input$ejec_a, input$ejec_b)
    comparar_ejecuciones(con, a, b, input$umbral, f())
  }) |> bindCache(input$ejec_a, input$ejec_b, input$umbral, f(), version())

  output$resumen_cambios <- renderText({
    t <- table(factor(cambios()$situacion, levels = c("Subió", "Bajó", "Nuevo", "Dejó de observarse")))
    paste0(names(t), ": ", t, collapse = " · ")
  })

  output$t_cambios <- renderDT({
    d <- cambios()
    shiny::validate(need(nrow(d) > 0, "No hay cambios entre estas ejecuciones con los filtros elegidos."))
    d$grande <- as.integer(d$grande)
    datatable(d[, c("comercio", "nombre", "situacion", "precio_a", "precio_b", "cambio_cop", "cambio_pct", "grande")],
              rownames = FALSE, filter = "top",
              colnames = c("Comercio", "Producto", "Situación", "Precio antes", "Precio después",
                           "Cambio (COP)", "Cambio (%)", "grande"),
              options = list(pageLength = 15, language = DT_ES, columnDefs = list(list(visible = FALSE, targets = 7)))) |>
      formatCurrency(4:6, currency = "$", mark = ".", dec.mark = ",", digits = 0) |>
      formatString("cambio_pct", suffix = " %") |>
      formatStyle("grande", target = "row", backgroundColor = styleEqual(1, "#ffe08a"))
  })

  # ---- Canasta ---------------------------------------------------------------
  output$cantidades <- renderUI({
    req(input$canasta)
    nombres <- names(opciones_comparables)[match(input$canasta, opciones_comparables)]
    campos <- lapply(seq_along(input$canasta), function(i) {
      id <- paste0("cant_", input$canasta[i])
      previa <- isolate(input[[id]])   # conserva la cantidad si ya se había escrito
      numericInput(id, nombres[i], value = if (is.null(previa)) 1 else previa, min = 1, max = 20)
    })
    do.call(layout_columns, c(list(col_widths = 3), campos))
  })

  canasta <- reactive({
    req(input$canasta)
    cantidades <- sapply(input$canasta, function(p) {
      x <- input[[paste0("cant_", p)]]
      if (is.null(x) || is.na(x) || x < 1) 1 else round(x)
    })
    names(cantidades) <- input$canasta
    precios <- precios_canasta(con, input$ejecucion, input$canasta)
    nombres <- names(opciones_comparables)[match(input$canasta, opciones_comparables)]
    calcular_canasta(precios, cantidades, nombres)
  })

  output$t_canasta <- renderTable({
    d <- canasta()$por_comercio
    data.frame(Comercio = d$comercio,
               Total = ifelse(is.na(d$total), "No se puede calcular", cop(d$total)),
               `Productos que faltan` = d$faltan, check.names = FALSE)
  })

  output$canasta_minimo <- renderUI({
    r <- canasta()
    if (is.na(r$minimo)) return(p("Alguna presentación no tiene precio en esta ejecución."))
    tagList(
      h4(cop(r$minimo)),
      if (is.na(r$ahorro)) p("Ningún comercio tiene todos los productos, así que no hay con qué comparar.")
      else p("Ahorro frente a comprar todo en el comercio completo más barato:", strong(cop(r$ahorro)))
    )
  })

  # ---- Productos -------------------------------------------------------------
  output$t_productos <- renderDT({
    d <- productos()
    shiny::validate(need(nrow(d) > 0, "Ningún producto cumple los filtros elegidos."))
    d$enlace <- paste0('<a href="', d$url_producto, '" target="_blank">ver</a>')
    d$promocion <- ifelse(d$promocion == 1, "Sí", "No")
    d$presentacion <- ifelse(is.na(d$contenido_total), "", paste(d$contenido_total, d$unidad_norm))
    d <- d[, c("comercio", "nombre", "marca", "presentacion", "precio", "precio_por_ml",
               "promocion", "disponibilidad", "fecha_hora_consulta", "enlace")]
    datatable(d, rownames = FALSE, escape = -10,   # solo la columna del enlace lleva HTML
              colnames = c("Comercio", "Producto", "Marca", "Presentación", "Precio (COP)",
                           "Precio por mL (COP)", "Promoción", "Disponibilidad", "Consulta", "Anuncio"),
              options = list(pageLength = 15, language = DT_ES)) |>
      formatCurrency(5:6, currency = "$", mark = ".", dec.mark = ",", digits = 0)
  })

  output$descargar <- downloadHandler(
    filename = function() paste0("perfumes_", input$ejecucion, ".csv"),
    content = function(file) {
      writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), file)   # marca UTF-8 para que Excel lea bien las tildes
      suppressWarnings(write.table(productos(), file, sep = ",", row.names = FALSE, qmethod = "double",
                                   append = TRUE, fileEncoding = "UTF-8"))
    }
  )

  # ---- Actualizar ------------------------------------------------------------
  # Corre en otra sesión de R para no bloquear la aplicación.
  tarea <- ExtendedTask$new(function(modo, id) {
    future_promise({
      source("scraper.R", encoding = "UTF-8")
      source("procesamiento.R", encoding = "UTF-8")
      resumen <- ejecutar_recoleccion(modo = modo, id_ejecucion = id)
      if (any(resumen$estado != "fallida")) {
        con2 <- conectar_bd()
        procesar_base(con2)
        DBI::dbDisconnect(con2)
      }
      resumen
    }, seed = TRUE)
  }) |> bind_task_button("actualizar")

  # Sin conexión se reprocesa la última ejecución con datos; en línea el
  # scraper crea una ejecución nueva (id = NULL).
  observeEvent(input$actualizar, {
    id <- if (input$modo == "sin_conexion") ultima_ejecucion(con) else NULL
    tarea$invoke(input$modo, id)
  })

  # Al terminar bien se refresca la lista de ejecuciones. Si la tarea dio error
  # o no trajo datos de ningún comercio, la aplicación se queda donde estaba.
  observeEvent(tarea$status(), {
    req(tarea$status() == "success")
    req(any(tarea$result()$estado != "fallida"))
    version(version() + 1)
    e <- lista_ejecuciones(con)
    opciones <- setNames(e$id_ejecucion, fecha_texto(e$fecha))
    updateSelectInput(session, "ejecucion", choices = opciones, selected = opciones[1])
    updateSelectInput(session, "ejec_a", choices = opciones, selected = opciones[min(2, length(opciones))])
    updateSelectInput(session, "ejec_b", choices = opciones, selected = opciones[1])
  })

  output$mensaje_actualizacion <- renderUI({
    estado <- tarea$status()
    if (estado == "initial") return(NULL)
    if (estado == "running") return(div(class = "alert alert-info", "Actualizando..."))
    if (estado == "error") {
      error <- tryCatch(tarea$result(), error = function(e) conditionMessage(e))
      return(div(class = "alert alert-danger", "La actualización no terminó: ", error))
    }
    r <- tarea$result()
    if (all(r$estado == "fallida")) {
      div(class = "alert alert-warning",
          if (input$modo == "en_linea") p("No se pudo consultar ningún comercio. Es común en servidores en la nube,",
            "porque los sitios bloquean esas conexiones. Pruebe el modo sin conexión o ejecute la aplicación en su computador.")
          else p("No se pudo reprocesar ninguna copia de raw/."),
          if (nrow(r) > 0) tags$ul(lapply(paste0(r$comercio, ": ", r$detalle), tags$li)))
    } else {
      nuevas <- sum(r$observaciones_nuevas)
      div(class = "alert alert-success",
          if (nuevas > 0) paste0("Actualización terminada: se agregaron ", format(nuevas, big.mark = "."),
                                 " observaciones. Los indicadores, gráficos y tablas ya las usan.")
          else "Reproceso terminado. Las observaciones de esa ejecución ya estaban en la base, así que no se agregó ninguna.")
    }
  })

  output$t_resumen_actualizacion <- renderTable({
    req(tarea$status() == "success")
    r <- tarea$result()
    req(nrow(r) > 0)
    d <- resumen_actualizacion(con, r$id_ejecucion[1])
    names(d) <- c("Comercio", "Estado", "Recolectados", "Nuevos", "Cambios de precio", "No observados", "Detalle")
    d
  })
}

shinyApp(ui, server)
