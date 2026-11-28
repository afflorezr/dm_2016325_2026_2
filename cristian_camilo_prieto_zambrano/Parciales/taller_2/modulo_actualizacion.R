# =============================================================================
# modulo_actualizacion.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Módulo de Shiny con el botón de actualización de precios (Módulo 2).
#
#   actualizacion_ui(id)                           tarjeta con el botón
#   actualizacion_server(id, db, al_terminar)      lógica
#
# - Reutiliza el scraper: llama a actualizar_precios() de scraper.R; no copia
#   ni reescribe la extracción aquí.
# - No bloquea la aplicación: la actualización corre en otro proceso de R
#   (ExtendedTask + future_promise). Mientras tanto la aplicación responde.
# - Al terminar llama a al_terminar(), que en la aplicación incrementa la
#   versión de los datos e invalida la caché: indicadores, gráficos y tablas
#   se actualizan sin reiniciar.
# - Modo sin conexión: reprocesa una corrida de raw/ (la carga si no está en
#   la base; si ya está, la verifica contra lo guardado).
#
# Requiere: shiny >= 1.8.1, bslib, promises, future, y un plan de future
# definido en la aplicación (plan(multisession)).
# =============================================================================

NOMBRES_COMERCIO <- c(locatel = "Locatel", cruzverde = "Cruz Verde", farmatodo = "Farmatodo")

actualizacion_ui <- function(id) {
  ns <- NS(id)
  card(
    card_header(div("Actualizar precios",
                    span(class = "sub", "Consulta de nuevo los comercios y agrega una corrida a la base."))),
    radioButtons(
      ns("modo"), label = "Modo",
      choiceNames = list(
        tagList(strong("En línea"), span(class = "nota-filtros d-block", "Consulta los sitios de los comercios.")),
        tagList(strong("Sin conexión"),
                span(class = "nota-filtros d-block", "Reprocesa las copias crudas guardadas en raw/."))),
      choiceValues = c("en_linea", "sin_conexion")
    ),
    conditionalPanel(
      "input.modo == 'sin_conexion'", ns = ns,
      selectInput(ns("corrida"), "Corrida guardada en raw/", choices = NULL)
    ),
    input_task_button(ns("actualizar"), "Actualizar precios",
                      icon = icon("rotate"), label_busy = "Actualizando…", class = "btn-primary"),
    p(class = "nota-filtros mb-0",
      "En línea, la consulta tarda unos minutos por las pausas entre solicitudes.",
      "Mientras tanto puede seguir usando la aplicación."),
    uiOutput(ns("mensaje")),
    div(style = "overflow-x: auto;", tableOutput(ns("resumen")))
  )
}

actualizacion_server <- function(id, db = "comparador_precios.sqlite", al_terminar = function() NULL) {
  moduleServer(id, function(input, output, session) {

    # Corridas disponibles en raw/ para el modo sin conexión
    corridas <- reactiveVal(corridas_en_raw())
    observe({
      cr <- corridas()
      updateSelectInput(session, "corrida",
                        choices = setNames(cr$corrida, sprintf("%s (%s)", cr$fecha, cr$comercios)))
    })

    # La actualización corre en otro proceso. Ahí se carga scraper.R (que carga
    # db.R y validacion.R) y se llama a actualizar_precios().
    tarea <- ExtendedTask$new(function(db, offline, corrida) {
      future_promise({
        source("scraper.R", local = TRUE)
        actualizar_precios(db = db, offline = offline, corrida = corrida)
      }, seed = TRUE)
    }) |> bind_task_button("actualizar")

    observeEvent(input$actualizar, {
      offline <- identical(input$modo, "sin_conexion")
      if (offline && (is.null(input$corrida) || !nzchar(input$corrida))) {
        showNotification("No hay corridas guardadas en raw/ para reprocesar.", type = "warning")
        return()
      }
      tarea$invoke(db, offline, if (offline) input$corrida else NULL)
    })

    # Al terminar (con éxito o con error) la base pudo cambiar: se avisa a la
    # aplicación para que invalide la caché y refresque todo
    observeEvent(tarea$status(), {
      if (tarea$status() %in% c("success", "error")) {
        corridas(corridas_en_raw())
        al_terminar()
      }
    }, ignoreInit = TRUE)

    resultado <- reactive({
      estado <- tarea$status()
      if (estado == "success") list(ok = TRUE, r = tarea$result())
      else if (estado == "error") list(ok = FALSE, error = tryCatch(tarea$result(), error = conditionMessage))
      else NULL
    })

    output$mensaje <- renderUI({
      res <- resultado()
      if (is.null(res)) return(NULL)
      if (!res$ok) {
        return(div(class = "alert alert-danger mt-3",
                   strong("La actualización no pudo completarse. "), res$error))
      }
      r <- res$r
      if (!is.null(r$bloqueo)) {
        return(div(class = "alert alert-warning mt-3",
                   strong("No se actualizó. "), r$bloqueo))
      }
      fecha <- fecha_corrida(r$corrida)
      if (isTRUE(r$sitios_inaccesibles)) {
        return(div(class = "alert alert-warning mt-3",
                   strong("No fue posible consultar los sitios de los comercios desde este servidor. "),
                   "Los comercios suelen bloquear las plataformas de publicación. ",
                   "Use el modo sin conexión para reprocesar las copias crudas guardadas en raw/. ",
                   "Los intentos quedaron registrados como ejecuciones fallidas, con su motivo."))
      }
      div(class = "alert alert-success mt-3",
          strong(if (r$modo == "en_linea") "Actualización terminada. " else "Reprocesamiento terminado. "),
          sprintf("Corrida del %s (%s). Resumen por comercio:", fecha,
                  if (r$modo == "en_linea") "en línea" else "sin conexión"))
    })

    output$resumen <- renderTable({
      res <- resultado()
      req(res, res$ok, is.null(res$r$bloqueo))
      x <- res$r$resumen
      guion <- function(v) ifelse(is.na(v), "—", format(v, big.mark = ".", decimal.mark = ","))
      data.frame(
        Comercio          = unname(NOMBRES_COMERCIO[x$comercio]),
        Estado            = x$estado,
        Recolectados      = guion(x$registros),
        `En la categoría` = guion(x$en_categoria),
        Nuevos            = guion(x$nuevos),
        Subieron          = guion(x$subieron),
        Bajaron           = guion(x$bajaron),
        `No observados`   = guion(x$no_observados),
        Rechazados        = guion(x$rechazados),
        Motivo            = ifelse(is.na(x$motivo), "", x$motivo),
        check.names = FALSE
      )
    }, striped = FALSE, hover = TRUE, spacing = "s", width = "100%", align = "l")
  })
}
