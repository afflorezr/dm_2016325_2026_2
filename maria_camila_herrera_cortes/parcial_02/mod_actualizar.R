# mod_actualizar.R -- Taller 2, Módulo 2: botón de actualización (módulo de Shiny)
# - El scraping corre en segundo plano (ExtendedTask + future_promise): la aplicación sigue
#   respondiendo; el avance por comercio se lee de un archivo de progreso.
# - Al terminar muestra el resumen por comercio y avisa a la aplicación (`version`) para que
#   invalide la caché y actualice indicadores, gráficos y tablas sin reiniciar.
# - Si los comercios no responden desde este equipo (típico en la nube), lo explica y ofrece el
#   modo sin conexión, que reprocesa las copias de raw/ hacia una base temporal de demostración.
# Requiere shiny >= 1.8.1, bslib, promises y future.
#
# En app.R:  plan(multisession)   # antes de la interfaz
#   ui:     mod_actualizar_ui("act")
#   server: act <- mod_actualizar_server("act", ruta_db = DB_RUTA)
#           act$db()        # ruta de la base activa (real, o la temporal del modo sin conexión)
#           act$version()   # cambia al terminar una actualización: úsela como clave de caché

library(shiny); library(bslib); library(promises); library(future)

mod_actualizar_ui <- function(id) {
  ns <- NS(id)
  tagList(
    input_task_button(ns("actualizar"), "Actualizar precios", label_busy = "Actualizando precios..."),
    input_task_button(ns("sin_conexion"), "Modo sin conexión (usar raw/)", label_busy = "Reprocesando raw/...",
                      type = "outline-secondary", class = "mt-2"),
    uiOutput(ns("volver")),
    uiOutput(ns("avance")),
    uiOutput(ns("resultado"))
  )
}

mod_actualizar_server <- function(id, ruta_db = "comparador_precios.sqlite", ejecuciones_sin_conexion = NULL) {
  moduleServer(id, function(input, output, session) {
    progreso <- tempfile(fileext = ".log")            # lo escribe la tarea; la interfaz lo lee
    db_activa <- reactiveVal(ruta_db)
    version   <- reactiveVal(0L)
    ultimo    <- reactiveVal(NULL)

    tarea_linea <- ExtendedTask$new(function(db, archivo) {
      future_promise({
        source("actualizacion.R", encoding = "UTF-8")
        actualizar_precios(db, archivo_progreso = archivo)
      }, globals = list(db = db, archivo = archivo), seed = NULL)
    }) |> bind_task_button("actualizar")

    tarea_off <- ExtendedTask$new(function(ruta, archivo, ejec) {
      future_promise({
        source("actualizacion.R", encoding = "UTF-8")
        reprocesar_sin_conexion(db_destino = ruta, ejecuciones = ejec, archivo_progreso = archivo)
      }, globals = list(ruta = ruta, archivo = archivo, ejec = ejec), seed = NULL)
    }) |> bind_task_button("sin_conexion")

    observeEvent(input$actualizar, {
      cat("", file = progreso)
      tarea_linea$invoke(ruta_db, progreso)               # siempre sobre la base real
    })
    observeEvent(input$sin_conexion, {
      cat("", file = progreso)
      tarea_off$invoke(tempfile(fileext = ".sqlite"), progreso, ejecuciones_sin_conexion)
    })

    # Resultados: se actualizan la base activa y la versión (invalida cachés)
    observe({
      r <- tryCatch(tarea_linea$result(), error = function(e) NULL)
      if (!is.null(r)) { ultimo(r); version(isolate(version()) + 1L) }
    })
    observe({
      r <- tryCatch(tarea_off$result(), error = function(e) NULL)
      if (!is.null(r)) { ultimo(r); db_activa(r$db); version(isolate(version()) + 1L) }
    })
    observeEvent(input$volver, { db_activa(ruta_db); version(version() + 1L) })

    avance <- reactivePoll(800, session,
      checkFunc = function() file.mtime(progreso),
      valueFunc = function() if (file.exists(progreso)) readLines(progreso, warn = FALSE) else character())
    ocupado <- reactive(identical(tarea_linea$status(), "running") || identical(tarea_off$status(), "running"))

    output$avance <- renderUI({
      if (!ocupado()) return(NULL)
      tags$pre(class = "small mt-2", paste(tail(avance(), 12), collapse = "\n"))
    })
    output$volver <- renderUI({
      if (identical(db_activa(), ruta_db)) NULL
      else div(class = "alert alert-warning mt-2 small",
               "Está viendo datos de demostración reprocesados desde raw/ (base temporal).",
               actionLink(session$ns("volver"), "Volver a la base real"))
    })
    output$resultado <- renderUI({
      err <- NULL
      for (t in list(tarea_linea, tarea_off))
        if (identical(t$status(), "error")) err <- tryCatch({ t$result(); NULL }, error = function(e) conditionMessage(e))
      if (!is.null(err))
        return(div(class = "alert alert-danger mt-2 small",
                   "No se pudo completar la operación. Detalle: ", err))
      r <- ultimo(); if (is.null(r)) return(NULL)
      clase <- if (isTRUE(r$todos_fallaron)) "alert-danger" else if (r$modo == "sin_conexion" ||
                 all(r$resumen$estado == "completa")) "alert-success" else "alert-warning"
      tagList(
        div(class = paste("alert mt-2 small", clase), r$mensaje),
        tags$small(sprintf("Ejecución %s", r$ejecucion_id)),
        tags$table(class = "table table-sm small",
          tags$thead(tags$tr(lapply(c("Comercio", "Estado", "Recolectados", "Nuevos", "Cambios de precio",
                                      "No observados", "Rechazados", "Motivo"), tags$th))),
          tags$tbody(lapply(seq_len(nrow(r$resumen)), function(i) with(r$resumen[i, ], tags$tr(
            tags$td(comercio), tags$td(estado), tags$td(recolectados), tags$td(nuevos),
            tags$td(cambios_precio), tags$td(no_observados), tags$td(rechazados),
            tags$td(if (is.na(motivo)) "" else motivo)))))))
    })

    list(db = db_activa, version = version, ultimo = ultimo)
  })
}
