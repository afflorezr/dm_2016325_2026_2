# Pestaña 7 · Actualizar precios: botón en segundo plano (ExtendedTask) que reutiliza scraper.R
COMERCIOS_OPCIONES <- c("Éxito" = "exito", "Carulla" = "carulla", "PriceSmart" = "pricesmart", "Supermercado Comunal" = "supercomunal")

ids_raw <- function() {
  m <- file.path("raw", "manifest.csv")
  if (!file.exists(m)) return(character())
  rev(sort(unique(utils::read.csv(m, colClasses = "character", fileEncoding = "UTF-8")$id_corrida)))
}
leer_log_reciente <- function(n = 25) {
  logs <- list.files("diagnostico", pattern = "^scraper(_offline)?\\.log$", recursive = TRUE, full.names = TRUE)
  if (!length(logs)) return("(aún no hay registro de ejecución)")
  f <- logs[which.max(file.mtime(logs))]
  paste(utils::tail(readLines(f, warn = FALSE, encoding = "UTF-8"), n), collapse = "\n")
}

actualizar_ui <- function(id) {
  ns <- NS(id)
  layout_columns(col_widths = c(4, 8),
    tarjeta("Actualizar precios",
      radioButtons(ns("modo"), "Modo", c("En línea (scraping de los comercios)" = "online", "Sin conexión (reprocesar copias de raw/)" = "offline")),
      checkboxGroupInput(ns("comercios"), "Comercios", choices = COMERCIOS_OPCIONES, selected = unname(COMERCIOS_OPCIONES)),
      conditionalPanel(sprintf("input['%s'] == 'online'", ns("modo")),
        checkboxInput(ns("prueba"), "Corrida de prueba (copia temporal: no modifica la base ni raw/)", FALSE)),
      conditionalPanel(sprintf("input['%s'] == 'offline'", ns("modo")),
        selectInput(ns("id_off"), "Corrida de raw/ a reprocesar", choices = ids_raw())),
      input_task_button(ns("go"), "Actualizar precios", icon = icon("rotate"), label_busy = "Actualizando…", class = "btn-primary w-100"),
      p(class = "small mt-3 mb-0 text-body-secondary",
        "La actualización corre en segundo plano: puede seguir usando la aplicación. Respeta pausas entre peticiones, un agente de usuario identificable y un tope de fichas por comercio.")),
    div(uiOutput(ns("estado_scraping")), uiOutput(ns("resultado")),
        tarjeta("Registro de la ejecución (últimas líneas)", div(class = "log-actualizacion", textOutput(ns("log"))))))
}

actualizar_server <- function(id, version) {
  moduleServer(id, function(input, output, session) {
    tarea <- ExtendedTask$new(function(modo, comercios, prueba, id_off) {
      future_promise({
        source("actualizacion.R", encoding = "UTF-8"); cargar_motor()
        ejecutar_actualizacion(modo = modo, comercios = comercios, prueba = prueba, id_corrida_offline = id_off)
      }, seed = NULL)
    }) |> bind_task_button("go")

    observeEvent(input$go, {
      cm <- intersect(input$comercios, unname(COMERCIOS_OPCIONES))
      if (!length(cm)) return(showNotification("Elija al menos un comercio.", type = "warning"))
      id_off <- NULL
      if (input$modo == "offline") {
        if (!isTruthy(input$id_off) || !input$id_off %in% ids_raw()) return(showNotification("Corrida de raw/ no válida.", type = "error"))
        id_off <- input$id_off
      }
      tarea$invoke(input$modo, cm, isTRUE(input$prueba), id_off)
    })
    observeEvent(tarea$status(), {
      if (tarea$status() == "success") {
        r <- tryCatch(tarea$result(), error = function(e) NULL)
        if (!is.null(r) && isTRUE(r$ok)) {
          if (!isTRUE(r$prueba)) version(version() + 1)
          showNotification(r$mensaje, type = "message", duration = 8)
        }
      }
    })

    output$estado_scraping <- renderUI({
      e <- if (exists("estado_scraping")) estado_scraping() else list(ok = FALSE, motivo = "Módulo de actualización no cargado.")
      if (e$ok) aviso("Este equipo puede hacer scraping en línea (Chrome detectado).", "success")
      else aviso(paste("Scraping en línea no disponible aquí:", e$motivo), "warning")
    })
    output$resultado <- renderUI({
      st <- tarea$status()
      if (st == "initial") return(aviso("Aún no se ha lanzado ninguna actualización en esta sesión.", "secondary"))
      if (st == "running") return(aviso("Actualizando en segundo plano… el registro de abajo se refresca solo.", "info"))
      r <- tryCatch(tarea$result(), error = function(e) list(ok = FALSE, mensaje = paste("Error inesperado:", conditionMessage(e))))
      tagList(
        aviso(r$mensaje, if (isTRUE(r$ok)) "success" else "danger"),
        if (length(r$advertencias)) aviso(paste(r$advertencias, collapse = " · "), "warning"),
        if (!is.null(r$resumen)) tarjeta("Resumen por comercio", tableOutput(session$ns("t_resumen"))),
        if (!is.null(r$verificacion)) tarjeta("Verificación del reproceso: copias de raw/ vs. base", tableOutput(session$ns("t_verif"))))
    })
    resultado <- reactive(tryCatch(tarea$result(), error = function(e) NULL))
    output$t_resumen <- renderTable({
      r <- resultado()$resumen; req(r)
      data.frame(Comercio = r$comercio, Estado = r$estado, Recolectados = r$recolectados, Nuevos = r$nuevos,
                 `Cambios de precio` = r$cambios_precio, `No observados` = r$no_observados, Descartados = r$descartados,
                 Detalle = ifelse(is.na(r$detalle), "", substr(r$detalle, 1, 120)), check.names = FALSE)
    }, striped = TRUE, width = "100%")
    output$t_verif <- renderTable({
      v <- resultado()$verificacion; req(v)
      data.frame(Comercio = v$comercio, `Reprocesadas desde raw/` = v$reprocesadas, `Presentes en la base` = v$en_base,
                 `Precio coincide` = v$precio_coincide, check.names = FALSE)
    }, striped = TRUE, width = "100%")
    output$log <- renderText({
      if (tarea$status() == "running") invalidateLater(3000, session)
      leer_log_reciente()
    })
  })
}
