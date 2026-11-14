# app.R — Comparador de precios (Taller 2)
# Interfaz. No contiene SQL: todas las consultas están en db.R.
# La actualización de precios (botón) se agrega en el siguiente peldaño.

library(shiny)
library(bslib)
library(DT)
library(highcharter)
library(DBI)
library(promises)
library(future)

source("db.R")

# Las actualizaciones corren en un proceso aparte para no bloquear la app.
plan(multisession, workers = 2)

# Tarea en segundo plano: reutiliza el scraper del Taller 1 (scraper.R); no se
# copia dentro de la aplicación. modo: "online" consulta los sitios;
# "offline" reprocesa las copias crudas de raw/.
crear_tarea <- function(modo) {
  ExtendedTask$new(function() {
    future_promise({
      source("scraper.R")
      ejecutar_recoleccion(".", modo = modo)
    })
  })
}

con <- abrir_db()
onStop(function() cerrar_db(con))

opc  <- opciones_filtros(con)
comp <- lista_comparables(con)
nombres_comp <- setNames(comp$producto, as.character(comp$id_comparable))
unidades     <- unidades_comparables(con)
fechas_cmp   <- fechas_comparables(con)
fechas       <- opc$fechas

# ---- Utilidades de presentación ----------------------------------------

fmt_n   <- function(x) format(x, big.mark = ".", decimal.mark = ",", scientific = FALSE, trim = TRUE)
fmt_cop <- function(x) ifelse(is.na(x), "—", paste0("$", fmt_n(round(x))))
esc     <- function(x) ifelse(is.na(x), "", htmltools::htmlEscape(as.character(x)))
enlace_html <- function(url) {
  ifelse(is.na(url) | !nzchar(url), "",
         sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">ver anuncio</a>',
                 htmltools::htmlEscape(url, attribute = TRUE)))
}
idioma_dt <- list(search = "Buscar:", lengthMenu = "Mostrar _MENU_ filas",
                  info = "Mostrando _START_ a _END_ de _TOTAL_ filas",
                  infoEmpty = "Sin filas", zeroRecords = "Sin resultados",
                  emptyTable = "Sin datos",
                  paginate = list(previous = "Anterior", `next` = "Siguiente"))

caja <- function(titulo, id) {
  value_box(title = titulo,
            value = textOutput(id),
            p(textOutput(paste0(id, "_nota"), inline = TRUE), class = "small mb-0"))
}

# ---- Interfaz ------------------------------------------------------------

ui <- page_navbar(
  title = "Comparador de precios · Primeros auxilios y curación",
  theme = bs_theme(version = 5, preset = "flatly"),
  lang  = "es",
  fillable = FALSE,

  nav_panel(
    "Resumen",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        title = "Filtros", width = 320,
        checkboxGroupInput("comercio", "Comercio", choices = opc$comercios,
                           selected = opc$comercios),
        selectizeInput("subcategoria", "Subcategoría", choices = opc$subcategorias,
                       multiple = TRUE, options = list(placeholder = "Todas")),
        selectizeInput("marca", "Marca", choices = opc$marcas, multiple = TRUE,
                       options = list(placeholder = "Todas")),
        sliderInput("precio", "Rango de precio (COP)", min = 0, max = opc$precio_max,
                    value = c(0, opc$precio_max), step = 1000, pre = "$", sep = "."),
        selectInput("captura", "Captura (ejecución)",
                    choices = c("Última de cada comercio" = "ultima",
                                setNames(fechas, fechas))),
        checkboxInput("solo_promo", "Solo promociones", FALSE),
        checkboxInput("solo_comparables", "Solo productos comparables", FALSE),
        textInput("busqueda", "Buscar por palabras en el nombre del anuncio",
                  placeholder = "ej. micropore 24 mm")
      ),

      layout_column_wrap(
        width = "240px",
        caja("Productos listados (unidad: productos)", "i1"),
        caja("Última ejecución", "i2"),
        caja("Productos en promoción (%)", "i3"),
        caja("Mediana del precio (COP)", "i4"),
        caja("Ahorro máximo entre comercios (COP)", "i5"),
        caja("Cambios de precio, última ejecución (productos)", "i6")
      ),

      layout_column_wrap(
        width = 1/2,
        card(full_screen = TRUE,
             card_header("Evolución del precio de un producto comparable"),
             selectInput("comparable", NULL, choices = setNames(comp$id_comparable, comp$producto), width = "100%"),
             highchartOutput("g_evolucion", height = "300px"),
             card_footer(textOutput("pie_g1"))),
        card(full_screen = TRUE,
             card_header("Precio por unidad de contenido (sin mezclar unidades)"),
             radioButtons("unidad", "Unidad de contenido", choices = unidades, inline = TRUE),
             highchartOutput("g_unitario", height = "300px"),
             card_footer(textOutput("pie_g2"))),
        card(full_screen = TRUE,
             card_header("Distribución de precios de la categoría por comercio"),
             highchartOutput("g_distribucion", height = "340px"),
             card_footer(textOutput("pie_g3"))),
        card(full_screen = TRUE,
             card_header("¿En qué comercio es más probable encontrar el producto disponible?"),
             highchartOutput("g_disponibilidad", height = "340px"),
             card_footer(textOutput("pie_g4")))
      ),

      card(
        full_screen = TRUE,
        card_header("Productos filtrados"),
        downloadButton("descargar", "Descargar CSV (filtros actuales)"),
        DTOutput("tabla"),
        card_footer(textOutput("pie_tabla"))
      )
    )
  ),

  nav_panel(
    "Cambios de precio",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        title = "Comparar capturas", width = 300,
        selectInput("fecha_ant", "Captura anterior", choices = fechas,
                    selected = if (length(fechas) >= 2) fechas[2] else fechas[1]),
        selectInput("fecha_act", "Captura actual", choices = fechas, selected = fechas[1]),
        numericInput("umbral", "Umbral de variación grande (%)", value = 10, min = 0, max = 100, step = 1),
        checkboxGroupInput("cambios_comercio", "Comercio", choices = opc$comercios,
                           selected = opc$comercios),
        selectInput("tipo", "Mostrar",
                    choices = c("Todos", "subió", "bajó", "nuevo", "no observado", "sin comparación", "igual"))
      ),
      uiOutput("cambios_cajas"),
      card(card_header("Cambios por producto (mismo anuncio, mismo comercio)"),
           DTOutput("tabla_cambios"),
           card_footer("Precios en COP. Solo se comparan los comercios con ejecución completa en ambas capturas. Una variación mayor al umbral se resalta: verde si bajó, rojo si subió. Parte de los cambios puede deberse a campañas temporales de descuento."))
    )
  ),

  nav_panel(
    "Canasta",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        title = "Arme su canasta", width = 340,
        selectizeInput("canasta_prod", "Productos comparables",
                       choices = setNames(comp$id_comparable, comp$producto),
                       multiple = TRUE, options = list(placeholder = "Elija uno o más")),
        uiOutput("cantidades"),
        selectInput("canasta_fecha", "Captura (precios de una misma ejecución)",
                    choices = fechas_cmp, selected = fechas_cmp[1]),
        checkboxInput("solo_disp", "Contar solo productos disponibles", TRUE)
      ),
      uiOutput("canasta_cajas"),
      card(card_header("Costo de la canasta por comercio"),
           DTOutput("tabla_canasta")),
      card(card_header("Comprando cada producto donde es más barato"),
           DTOutput("tabla_minimo")),
      p(class = "text-muted small",
        "El resultado no incluye envío, mínimos de compra ni las condiciones de las promociones. ",
        "Un comercio solo muestra total si tiene todos los productos elegidos.")
    )
  ),

  nav_panel(
    "Actualización",
    layout_column_wrap(
      width = 1/2,
      card(
        card_header("Actualizar precios"),
        p("Consulta de nuevo los sitios de los comercios con el scraper del Taller 1. ",
          "Puede tardar varios minutos y la aplicación sigue disponible mientras tanto. ",
          "Cada comercio se valida e inserta por separado: si uno falla, los demás continúan."),
        input_task_button("actualizar", "Actualizar precios (en línea)",
                          label_busy = "Actualizando..."),
        uiOutput("estado_tarea")
      ),
      card(
        card_header("Modo sin conexión"),
        p("Reprocesa las copias crudas guardadas en raw/ sin consultar ningún sitio. ",
          "No duplica observaciones: insertar dos veces la misma ejecución no cambia la base."),
        input_task_button("reprocesar", "Reprocesar copias de raw/ (sin conexión)",
                          label_busy = "Reprocesando...")
      )
    ),
    card(
      card_header("Resumen de la última actualización de esta sesión"),
      DTOutput("tabla_resumen")
    ),
    card(
      card_header("Historial de ejecuciones"),
      DTOutput("tabla_historial"),
      card_footer("Cada ejecución se rastrea hasta sus copias crudas (columna ruta_raw). ",
                  "En shinyapps.io los cambios a la base no se conservan al reiniciar la aplicación, ",
                  "y los comercios suelen bloquear los servidores de despliegue: la actualización en línea ",
                  "funciona al ejecutar la aplicación localmente; en el servidor use el modo sin conexión.")
    )
  ),

  nav_spacer(),
  nav_item(span(class = "navbar-text small", textOutput("fecha_datos", inline = TRUE)))
)

# ---- Servidor ------------------------------------------------------------

server <- function(input, output, session) {

  version <- reactiveVal(0L)   # se incrementa al terminar una actualización (invalida la caché)

  filtros <- reactive({
    validate(need(length(input$comercio) > 0, "Seleccione al menos un comercio."))
    rango <- input$precio
    activo <- !is.null(rango) && !identical(as.numeric(rango), c(0, opc$precio_max))
    list(comercios = input$comercio, subcategorias = input$subcategoria,
         marcas = input$marca,
         precio_min = if (activo) rango[1], precio_max = if (activo) rango[2],
         solo_promo = input$solo_promo, solo_comparables = input$solo_comparables,
         busqueda = busqueda(), fecha = input$captura)
  })
  busqueda <- debounce(reactive(input$busqueda), 500)

  datos <- reactive(precios_filtrados(con, filtros())) |>
    bindCache(filtros(), version())
  ind <- reactive(indicadores(con, filtros())) |>
    bindCache(filtros(), version())

  nota_periodo <- function(i) {
    if (is.na(i$fecha_max)) return("sin datos")
    if (identical(i$fecha_min, i$fecha_max)) paste("captura del", i$fecha_max)
    else paste("capturas del", i$fecha_min, "al", i$fecha_max)
  }

  output$fecha_datos <- renderText({
    paste0("Precios al momento de la captura. Última ejecución: ", ind()$ultima_fecha)
  })

  # --- Indicadores ---
  output$i1      <- renderText(fmt_n(ind()$productos))
  output$i1_nota <- renderText(paste0("productos · ", nota_periodo(ind())))
  output$i2      <- renderText(ind()$ultima_fecha)
  output$i2_nota <- renderText(if (ind()$ultima_completa) "completa en todos los comercios"
                               else "parcial en al menos un comercio")
  output$i3      <- renderText({
    i <- ind(); if (i$productos == 0) "—" else paste0(round(100 * i$promos / i$productos, 1), " %")
  })
  output$i3_nota <- renderText(paste0("de ", fmt_n(ind()$productos), " productos · ", nota_periodo(ind())))
  output$i4      <- renderText(fmt_cop(ind()$mediana))
  output$i4_nota <- renderText(paste0("de ", fmt_n(ind()$con_precio), " productos con precio · ", nota_periodo(ind())))
  output$i5      <- renderText(fmt_cop(ind()$ahorro_max))
  output$i5_nota <- renderText(paste0(ind()$ahorro_producto, " · captura del ", ind()$ahorro_fecha))
  output$i6      <- renderText(fmt_n(ind()$cambios))
  output$i6_nota <- renderText("subió o bajó frente a la ejecución anterior")

  # --- Pies de gráfico con unidad y fecha ---
  for (id in c("pie_g1", "pie_g2", "pie_g3", "pie_g4", "pie_tabla")) {
    local({
      i <- id
      output[[i]] <- renderText(paste0("Precios en COP. Fuente: scraping de los sitios de los comercios. ",
                                       "Se usa la última ejecución completa de cada comercio. Última ejecución: ",
                                       ind()$ultima_fecha, "."))
    })
  }

  # --- Gráfico 1: evolución ---
  output$g_evolucion <- renderHighchart({
    req(input$comparable)
    d <- serie_precio(con, input$comparable)
    validate(need(nrow(d) > 0, "Este producto no tiene precios registrados."))
    d$fecha <- as.Date(d$fecha)
    hc <- highchart() |>
      hc_xAxis(type = "datetime") |>
      hc_yAxis(title = list(text = "Precio (COP)")) |>
      hc_tooltip(shared = TRUE, valueDecimals = 0, valuePrefix = "$")
    for (cm in intersect(names(COLORES_COMERCIO), unique(d$comercio))) {
      hc <- hc_add_series(hc, data = d[d$comercio == cm, ], type = "line",
                          hcaes(x = fecha, y = precio), name = cm,
                          color = COLORES_COMERCIO[[cm]], marker = list(enabled = TRUE))
    }
    hc
  }) |> bindCache(input$comparable, version())

  # --- Gráfico 2: precio por unidad ---
  output$g_unitario <- renderHighchart({
    req(input$unidad)
    d <- precio_unitario_comparables(con, input$unidad)
    validate(need(nrow(d) > 0, "No hay productos comparables con esa unidad."))
    prods <- unique(d$producto)
    hc <- highchart() |>
      hc_chart(type = "bar") |>
      hc_xAxis(categories = substr(prods, 1, 48)) |>
      hc_yAxis(title = list(text = paste0("COP por ", input$unidad))) |>
      hc_tooltip(valueDecimals = 2, valuePrefix = "$")
    for (cm in intersect(names(COLORES_COMERCIO), unique(d$comercio))) {
      dd <- d[d$comercio == cm, ]
      hc <- hc_add_series(hc, name = cm, color = COLORES_COMERCIO[[cm]],
                          data = dd$precio_unitario[match(prods, dd$producto)])
    }
    hc
  }) |> bindCache(input$unidad, version())

  # --- Gráfico 3: distribución ---
  output$g_distribucion <- renderHighchart({
    d <- distribucion_precios(con, filtros())
    validate(need(nrow(d) > 0, "Ningún producto cumple los filtros elegidos."))
    niveles <- levels(factor(d$comercio))
    hcboxplot(x = d$precio, var = d$comercio, name = "Precio (COP)", colorByPoint = TRUE) |>
      hc_colors(unname(COLORES_COMERCIO[niveles])) |>
      hc_yAxis(type = "logarithmic", title = list(text = "Precio (COP, escala logarítmica)")) |>
      hc_tooltip(valueDecimals = 0, valuePrefix = "$")
  }) |> bindCache(filtros(), version())

  # --- Gráfico 4: disponibilidad ---
  output$g_disponibilidad <- renderHighchart({
    d <- disponibilidad_por_comercio(con)
    validate(need(nrow(d) > 0, "Sin datos de disponibilidad."))
    cms <- intersect(names(COLORES_COMERCIO), unique(d$comercio))
    hc <- highchart() |>
      hc_chart(type = "column") |>
      hc_xAxis(categories = cms) |>
      hc_yAxis(title = list(text = "Número de productos")) |>
      hc_plotOptions(column = list(stacking = "normal")) |>
      hc_tooltip(shared = TRUE)
    cols <- c("disponible" = "#2a9d8f", "agotado" = "#e76f51", "no observado" = "#adb5bd")
    for (est in names(cols)) {
      vals <- vapply(cms, function(cm) {
        v <- d$n[d$comercio == cm & d$disponibilidad == est]
        if (length(v) == 0) 0 else v
      }, numeric(1))
      hc <- hc_add_series(hc, name = est, color = cols[[est]], data = unname(vals))
    }
    hc
  }) |> bindCache(version())

  # --- Tabla y descarga ---
  output$tabla <- renderDT({
    d <- datos()
    validate(need(nrow(d) > 0,
      "Ningún producto cumple los filtros elegidos. Pruebe ampliar el rango de precio o quitar filtros."))
    t <- data.frame(
      Comercio = esc(d$comercio), Producto = esc(d$nombre), Marca = esc(d$marca),
      Presentación = esc(d$presentacion), `Precio (COP)` = d$precio,
      `Precio unitario (COP)` = d$precio_unitario, `Unidad` = esc(d$unidad_unitaria),
      `Promoción` = ifelse(d$es_promocion == 1, "Sí", "No"),
      Disponibilidad = esc(d$disponibilidad),
      `Fecha de consulta` = substr(d$fecha_hora_consulta, 1, 10),
      Enlace = enlace_html(d$url), check.names = FALSE, stringsAsFactors = FALSE)
    datatable(t, rownames = FALSE, escape = FALSE,
              options = list(pageLength = 15, scrollX = TRUE, language = idioma_dt)) |>
      formatCurrency(c("Precio (COP)", "Precio unitario (COP)"), currency = "$",
                     digits = 0, mark = ".", dec.mark = ",")
  })

  output$descargar <- downloadHandler(
    filename = function() paste0("precios_filtrados_", Sys.Date(), ".csv"),
    content  = function(file) utils::write.csv(datos(), file, row.names = FALSE, fileEncoding = "UTF-8")
  )

  # --- Actualización de precios (tareas en segundo plano) ---
  tarea_online  <- crear_tarea("online")  |> bind_task_button("actualizar")
  tarea_offline <- crear_tarea("offline") |> bind_task_button("reprocesar")
  ultimo_resumen <- reactiveVal(NULL)

  ocupado <- function() {
    any(c(tarea_online$status(), tarea_offline$status()) == "running")
  }

  # Las listas de fechas se leen al iniciar; tras actualizar hay que refrescarlas.
  refrescar_fechas <- function() {
    f  <- fechas_captura(con)
    fc <- fechas_comparables(con)
    updateSelectInput(session, "captura",
                      choices = c("Última de cada comercio" = "ultima", setNames(f, f)),
                      selected = isolate(input$captura))
    updateSelectInput(session, "fecha_act", choices = f, selected = f[1])
    updateSelectInput(session, "fecha_ant", choices = f,
                      selected = if (length(f) >= 2) f[2] else f[1])
    updateSelectInput(session, "canasta_fecha", choices = fc, selected = fc[1])
  }

  terminar <- function(res, modo) {
    ultimo_resumen(res)
    if (is.null(res) || nrow(res) == 0) {
      showNotification("No había nada que procesar.", type = "warning")
    } else if (modo == "online" && all(res$estado == "fallida")) {
      showNotification(
        paste("No se pudo actualizar desde este entorno: los comercios suelen bloquear",
              "los servidores de despliegue o no hay navegador automatizado.",
              "Use el modo sin conexión o ejecute la aplicación localmente."),
        type = "error", duration = NULL)
    } else {
      showNotification(sprintf("Actualización terminada: %s observaciones nuevas.",
                               sum(res$observaciones_nuevas)), type = "message")
    }
    version(version() + 1L)    # invalida la caché: indicadores, gráficos y tablas se recalculan
    refrescar_fechas()
  }

  fallo <- function(tarea) {
    msg <- tryCatch({ tarea$result(); "" }, error = function(e) conditionMessage(e))
    showNotification(paste("La actualización falló:", msg), type = "error", duration = NULL)
  }

  observeEvent(input$actualizar, {
    if (ocupado()) {
      showNotification("Ya hay una actualización en curso.", type = "warning")
      update_task_button("actualizar", state = "ready")
    } else tarea_online$invoke()
  })
  observeEvent(input$reprocesar, {
    if (ocupado()) {
      showNotification("Ya hay una actualización en curso.", type = "warning")
      update_task_button("reprocesar", state = "ready")
    } else tarea_offline$invoke()
  })

  observeEvent(tarea_online$status(), {
    est <- tarea_online$status()
    if (est == "success") terminar(tarea_online$result(), "online")
    if (est == "error")   fallo(tarea_online)
  })
  observeEvent(tarea_offline$status(), {
    est <- tarea_offline$status()
    if (est == "success") terminar(tarea_offline$result(), "offline")
    if (est == "error")   fallo(tarea_offline)
  })

  output$estado_tarea <- renderUI({
    if (ocupado()) p(class = "text-warning mt-2",
                     "Actualización en curso. Puede tardar varios minutos...")
  })

  output$tabla_resumen <- renderDT({
    r <- ultimo_resumen()
    validate(need(!is.null(r) && nrow(r) > 0,
                  "Aún no se ha ejecutado ninguna actualización en esta sesión."))
    t <- data.frame(Comercio = r$comercio, Estado = r$estado,
                    `Productos recolectados` = r$recolectados, Rechazados = r$rechazados,
                    `Productos nuevos` = r$productos_nuevos,
                    `Observaciones nuevas` = r$observaciones_nuevas,
                    `Cambios de precio` = r$cambios_precio,
                    `No observados` = r$no_observados, Motivo = r$mensaje,
                    check.names = FALSE, stringsAsFactors = FALSE)
    datatable(t, rownames = FALSE, options = list(dom = "t", scrollX = TRUE, language = idioma_dt))
  })

  output$tabla_historial <- renderDT({
    version()
    h <- historial_ejecuciones(con)
    names(h) <- c("Ejecución", "Comercio", "Inicio", "Estado", "Registros", "Productos",
                  "Total del sitio", "Rechazadas", "Modo", "Motivo", "Copia cruda")
    datatable(h, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE, language = idioma_dt))
  })

  # --- Cambios de precio ---
  cambios <- reactive({
    validate(
      need(length(fechas_captura(con)) >= 2, "Se necesitan al menos dos capturas para comparar."),
      need(length(input$cambios_comercio) > 0, "Seleccione al menos un comercio."),
      need(input$fecha_ant != input$fecha_act, "Elija dos capturas distintas."))
    cambios_entre(con, input$fecha_ant, input$fecha_act, input$cambios_comercio)
  }) |> bindCache(input$fecha_ant, input$fecha_act, input$cambios_comercio, version())

  output$cambios_cajas <- renderUI({
    d <- cambios()
    n <- function(t) sum(d$tipo == t, na.rm = TRUE)
    grande <- sum(abs(d$cambio_pct) >= (input$umbral %||% 10), na.rm = TRUE)
    layout_column_wrap(
      width = "170px",
      value_box("Subieron", n("subió")), value_box("Bajaron", n("bajó")),
      value_box("Nuevos", n("nuevo")), value_box("Dejaron de observarse", n("no observado")),
      value_box(paste0("Variación ≥ ", input$umbral %||% 10, " %"), grande))
  })

  output$tabla_cambios <- renderDT({
    d <- cambios()
    if (input$tipo != "Todos") d <- d[d$tipo == input$tipo, ]
    validate(need(nrow(d) > 0, "No hay productos con ese tipo de cambio entre las capturas elegidas."))
    u <- input$umbral %||% 10
    t <- data.frame(
      Comercio = esc(d$comercio), Producto = esc(d$nombre), Marca = esc(d$marca),
      `Precio anterior (COP)` = d$precio_anterior, `Precio actual (COP)` = d$precio_actual,
      `Cambio (COP)` = d$cambio_cop, `Cambio (%)` = d$cambio_pct, Tipo = esc(d$tipo),
      Enlace = enlace_html(d$url), check.names = FALSE, stringsAsFactors = FALSE)
    datatable(t, rownames = FALSE, escape = FALSE,
              options = list(pageLength = 15, scrollX = TRUE, language = idioma_dt)) |>
      formatCurrency(c("Precio anterior (COP)", "Precio actual (COP)", "Cambio (COP)"),
                     currency = "$", digits = 0, mark = ".", dec.mark = ",") |>
      formatRound("Cambio (%)", digits = 1, mark = ".", dec.mark = ",") |>
      formatStyle("Cambio (%)",
                  backgroundColor = styleInterval(c(-u, u), c("#d1e7dd", "transparent", "#f8d7da")))
  })

  # --- Canasta ---
  output$cantidades <- renderUI({
    ids <- input$canasta_prod
    if (length(ids) == 0) return(NULL)
    tagList(lapply(ids, function(id) {
      numericInput(paste0("cant_", id), paste("Cantidad:", nombres_comp[[id]]),
                   value = isolate(input[[paste0("cant_", id)]]) %||% 1, min = 1, max = 99, step = 1)
    }))
  })

  canasta <- reactive({
    version()    # se recalcula tras una actualización
    ids <- input$canasta_prod
    validate(need(length(ids) > 0, "Elija al menos un producto para armar la canasta."))
    cant <- vapply(ids, function(id) {
      v <- suppressWarnings(as.numeric(input[[paste0("cant_", id)]]))
      if (length(v) == 0 || is.na(v) || v < 1) 1 else min(floor(v), 99)
    }, numeric(1))
    names(cant) <- ids
    pr <- precios_canasta(con, ids, input$canasta_fecha, isTRUE(input$solo_disp))
    calcular_canasta(pr, cant, nombres = nombres_comp)
  })

  output$canasta_cajas <- renderUI({
    r <- canasta()
    layout_column_wrap(
      width = "240px",
      value_box("Costo mínimo (cada producto donde es más barato)",
                if (is.na(r$minimo)) "No disponible" else fmt_cop(r$minimo),
                p(if (is.na(r$minimo)) "Algún producto no tiene precio disponible en ningún comercio" else "COP", class = "small mb-0")),
      value_box("Mejor comercio único (canasta completa)",
                if (is.na(r$mejor_unico)) "Ninguno" else fmt_cop(r$mejor_unico),
                p(if (is.na(r$mejor_unico)) "Ningún comercio tiene todos los productos" else "COP", class = "small mb-0")),
      value_box("Ahorro frente a comprar todo en un solo comercio",
                if (is.na(r$ahorro)) "—" else fmt_cop(r$ahorro),
                p(if (is.na(r$ahorro_pct)) "" else paste0(r$ahorro_pct, " %"), class = "small mb-0")))
  })

  output$tabla_canasta <- renderDT({
    r <- canasta()$por_comercio
    t <- data.frame(Comercio = r$comercio,
                    `Costo de la canasta (COP)` = r$total,
                    Estado = ifelse(r$completo, "Canasta completa", paste("Falta:", r$faltan)),
                    check.names = FALSE, stringsAsFactors = FALSE)
    datatable(t, rownames = FALSE, options = list(dom = "t", language = idioma_dt)) |>
      formatCurrency("Costo de la canasta (COP)", currency = "$", digits = 0, mark = ".", dec.mark = ",")
  })

  output$tabla_minimo <- renderDT({
    d <- canasta()$detalle
    t <- data.frame(Producto = d$producto, Cantidad = d$cantidad,
                    `Comercio más barato` = ifelse(is.na(d$comercio), "Sin precio disponible", d$comercio),
                    `Precio unitario (COP)` = d$precio, `Subtotal (COP)` = d$subtotal,
                    check.names = FALSE, stringsAsFactors = FALSE)
    datatable(t, rownames = FALSE, options = list(dom = "t", language = idioma_dt)) |>
      formatCurrency(c("Precio unitario (COP)", "Subtotal (COP)"), currency = "$",
                     digits = 0, mark = ".", dec.mark = ",")
  })
}

shinyApp(ui, server)
