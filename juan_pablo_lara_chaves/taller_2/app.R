# app.R  (ejecutar desde taller_2/ con shiny::runApp())
library(shiny); library(bslib); library(DBI); library(RSQLite); library(glue)
library(dplyr); library(highcharter); library(DT); library(promises); library(future)
plan(multisession)
source("db.R")   # crear_esquema, precios_filtrados, cambios_entre, actualizar_comercio, actualizar_offline

DB  <- "comparador_precios.sqlite"
COL <- c(farmatodo = "#1b9e77", locatel = "#d95f02", ortopedicos_futuro = "#7570b3")

ui <- page_navbar(
  title = "Comparador de precios: Ortopedia y rehabilitación",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  fillable = FALSE,
  sidebar = sidebar(
    width = 300,
    selectInput("ejec", "Ejecución", choices = NULL),
    checkboxGroupInput("cm", "Comercios", choices = names(COL), selected = names(COL)),
    selectInput("prod", "Comparable", choices = NULL, multiple = TRUE),
    sliderInput("precio", "Rango de precio (COP)", 0, 200000, c(0, 200000), step = 1000, pre = "$"),
    checkboxInput("promo", "Solo en promoción", FALSE),
    textInput("texto", "Buscar por nombre"),
    checkboxInput("solo_comp", "Solo comparables", FALSE),
    hr(),
    radioButtons("modo", "Actualización",
                 c("En línea (scraping)" = "online", "Sin conexión (HTML guardado)" = "offline")),
    selectInput("cm_upd", "Comercio a actualizar", names(COL)),
    input_task_button("actualizar", "Actualizar datos"),
    textOutput("estado_upd")
  ),
  nav_panel("Resumen",
            uiOutput("indicadores"),
            layout_columns(col_widths = c(6, 6),
                           card(min_height = "420px", full_screen = TRUE,
                                card_header("Evolución del precio promedio"),
                                highchartOutput("g_evol",   height = "350px")),
                           card(min_height = "420px", full_screen = TRUE,
                                card_header("Precio unitario por comparable"),
                                highchartOutput("g_unit",   height = "350px")),
                           card(min_height = "420px", full_screen = TRUE,
                                card_header("Distribución de precios"),
                                highchartOutput("g_dist",   height = "350px")),
                           card(min_height = "420px", full_screen = TRUE,
                                card_header("Brecha entre comercios (%)"),
                                highchartOutput("g_brecha", height = "350px")))),
  nav_panel("Datos",
            downloadButton("bajar", "Descargar CSV"), DTOutput("tabla")),
  nav_panel("Comparar ejecuciones",
            layout_columns(col_widths = c(4, 4, 4),
                           selectInput("ej_a", "Ejecución A", NULL),
                           selectInput("ej_b", "Ejecución B", NULL),
                           numericInput("umbral", "Umbral de cambio (%)", 10, min = 0, step = 1)),
            DTOutput("tabla_cambios")),
  nav_panel("Canasta",
            selectInput("canasta", "Productos de la canasta", NULL, multiple = TRUE, width = "100%"),
            uiOutput("msg_canasta"), DTOutput("tabla_canasta"))
)

server <- function(input, output, session) {
  con <- dbConnect(SQLite(), DB)
  session$onSessionEnded(function() dbDisconnect(con))
  q <- function(sql, ...) {
    env <- parent.frame()
    dbGetQuery(con, glue_sql(sql, ..., .con = con, .envir = env))}  
  version <- reactiveVal(0)   # sube tras cada actualización (invalida cachés)
  
  # ---- Selectores ----
  observe({
    version()
    ej <- q("SELECT DISTINCT ejecucion_id FROM v_referencia ORDER BY 1 DESC")$ejecucion_id
    pr <- q("SELECT DISTINCT producto_id FROM v_referencia ORDER BY 1")$producto_id
    updateSelectInput(session, "ejec", choices = ej, selected = ej[1])
    updateSelectInput(session, "ej_a", choices = ej, selected = ej[min(2, length(ej))])
    updateSelectInput(session, "ej_b", choices = ej, selected = ej[1])
    updateSelectInput(session, "prod", choices = pr)
    updateSelectInput(session, "canasta", choices = pr, selected = pr[seq_len(min(3, length(pr)))])
  })
  
  # ---- Filtros combinables (anuncios de la ejecución elegida) ----
  base <- reactive({
    req(input$ejec, input$cm)
    pr <- if (length(input$prod)) input$prod else
      q("SELECT DISTINCT producto_id FROM v_referencia")$producto_id
    q("SELECT * FROM v_comparables
       WHERE ejecucion_id = {input$ejec} AND comercio IN ({input$cm*})
         AND producto_id IN ({pr*})
         AND precio BETWEEN {input$precio[1]} AND {input$precio[2]}
         {if (input$promo) DBI::SQL('AND en_promocion = 1') else DBI::SQL('')}")
  }) |> bindCache(input$ejec, input$cm, input$prod, input$precio, input$promo, version())
  
  # ---- Indicadores en SQL (7) ----
  output$indicadores <- renderUI({
    e <- input$ejec; req(e)
    n_comp <- q("SELECT COUNT(DISTINCT producto_id) n FROM v_referencia WHERE ejecucion_id = {e}")$n
    n_cm   <- q("SELECT COUNT(DISTINCT comercio) n FROM v_referencia WHERE ejecucion_id = {e}")$n
    n_ej   <- q("SELECT COUNT(DISTINCT ejecucion_id) n FROM ejecuciones")$n
    prom   <- q("SELECT ROUND(AVG(precio)) v FROM v_referencia WHERE ejecucion_id = {e}")$v
    ahorro <- q("SELECT ROUND(AVG(100.0*(mx-mn)/mx),1) v FROM
                 (SELECT MAX(precio) mx, MIN(precio) mn FROM v_referencia
                  WHERE ejecucion_id = {e} GROUP BY producto_id HAVING COUNT(*) > 1)")$v
    promo  <- q("SELECT ROUND(100.0*AVG(en_promocion),1) v FROM v_comparables
                 WHERE ejecucion_id = {e}")$v
    gana   <- q("WITH m AS (SELECT producto_id, MIN(precio) mn FROM v_referencia
                            WHERE ejecucion_id = {e} GROUP BY producto_id)
                 SELECT r.comercio, COUNT(*) n
                 FROM v_referencia r JOIN m USING (producto_id)
                 WHERE r.ejecucion_id = {e} AND r.precio = m.mn   -- empates cuentan para todos
                 GROUP BY r.comercio ORDER BY n DESC LIMIT 1")
    layout_column_wrap(width = 1/4, fill = FALSE,
                       value_box("Comparables", n_comp),
                       value_box("Comercios", n_cm),
                       value_box("Ejecuciones", n_ej),
                       value_box("Precio promedio", paste0("$", format(prom, big.mark = ".", decimal.mark = ","))),
                       value_box("Ahorro prom. máx-mín", paste0(ahorro, "%")),
                       value_box("Anuncios en promoción", paste0(promo, "%")),
                       value_box("Más barato en más productos", paste0(gana$comercio, " (", gana$n, ")")))
  }) |> bindCache(input$ejec, version())
  
  # ---- Gráficos (highcharter, colores fijos por comercio) ----
  output$g_evol <- renderHighchart({
    d <- q("SELECT ejecucion_id, comercio, ROUND(AVG(precio)) precio FROM v_referencia
            WHERE comercio IN ({input$cm*}) GROUP BY ejecucion_id, comercio
            ORDER BY ejecucion_id")
    req(nrow(d) > 0)
    hchart(d, "line", hcaes(ejecucion_id, precio, group = comercio),
           color = unname(COL[sort(unique(d$comercio))])) |>
      hc_xAxis(type = "category", title = list(text = "Ejecución")) |>
      hc_yAxis(title = list(text = "COP"))
  }) |> bindCache(input$cm, version())
  
  output$g_unit <- renderHighchart({
    d <- base() |> filter(!is.na(precio_unitario)) |>
      group_by(producto_id, comercio) |>
      summarise(pu = round(max(precio_unitario)), .groups = "drop")
    req(nrow(d) > 0)
    hchart(d, "column", hcaes(producto_id, pu, group = comercio),
           color = unname(COL[sort(unique(d$comercio))])) |>
      hc_yAxis(title = list(text = "COP por unidad de contenido"))
  }) |> bindCache(input$ejec, input$cm, input$prod, input$precio, input$promo, version())
  
  output$g_dist <- renderHighchart({
    d <- base(); req(nrow(d) > 0)
    d$comercio <- factor(d$comercio, levels = sort(unique(d$comercio)))
    cols <- unname(COL[levels(d$comercio)])
    highchart() |>
      hc_chart(type = "boxplot") |>
      hc_xAxis(type = "category") |>
      hc_yAxis(title = list(text = "COP")) |>
      hc_colors(cols) |>
      hc_add_series_list(
        data_to_boxplot(d, variable = precio, group_var = comercio,
                        add_outliers = TRUE, name = "Precio", colorByPoint = TRUE)) |>
      hc_legend(enabled = FALSE)
  }) |> bindCache(input$ejec, input$cm, input$prod, input$precio, input$promo, version())  
  
  output$g_brecha <- renderHighchart({
    d <- q("SELECT producto_id, ROUND(100.0*(MAX(precio)-MIN(precio))/MIN(precio),1) brecha
            FROM v_referencia
            WHERE ejecucion_id = {input$ejec} AND comercio IN ({input$cm*})
            GROUP BY producto_id HAVING COUNT(*) > 1 ORDER BY brecha DESC")
    req(nrow(d) > 0)
    hchart(d, "bar", hcaes(producto_id, brecha), color = "#2c3e50") |>
      hc_yAxis(title = list(text = "(máx − mín) / mín, %"))
  }) |> bindCache(input$ejec, input$cm, version())
  
  # ---- Tabla + descarga ----
  tabla <- reactive({
    version()
    precios_filtrados(con, comercios = input$cm, pmin = input$precio[1], pmax = input$precio[2],
                      solo_promo = input$promo, solo_comparables = input$solo_comp,
                      texto = input$texto)
  })
  output$tabla <- renderDT(
    datatable(tabla(), filter = "top", options = list(pageLength = 15, scrollX = TRUE)))
  output$bajar <- downloadHandler(
    filename = function() paste0("precios_", Sys.Date(), ".csv"),
    content  = function(file) write.csv(tabla(), file, row.names = FALSE, fileEncoding = "UTF-8"))
  
  # ---- Comparación de dos ejecuciones ----
  output$tabla_cambios <- renderDT({
    req(input$ej_a, input$ej_b, input$ej_a != input$ej_b)
    datatable(cambios_entre(con, input$ej_a, input$ej_b, input$umbral),
              options = list(scrollX = TRUE))
  })
  
  # ---- Canasta: solo comercios con TODOS los productos ----
  canasta <- reactive({
    req(input$canasta, input$ejec)
    canasta_totales(con, input$ejec, input$canasta)
  })
  output$tabla_canasta <- renderDT({
    d <- canasta() |> filter(completa) |> arrange(total) |> select(comercio, total)
    datatable(d, rownames = FALSE) |> formatCurrency("total", "$", digits = 0, mark = ".")
  })
  output$msg_canasta <- renderUI({
    f <- canasta() |> filter(!completa)
    if (nrow(f)) div(class = "alert alert-warning",
                     "Excluidos por no tener todos los productos: ", paste(f$comercio, collapse = ", "))
  })
  
  # ---- Botón de actualización: ExtendedTask + modo sin conexión ----
  tarea <- ExtendedTask$new(function(comercio, offline, ejecucion_ui) {
    future_promise({
      for (f in c("scraper.R", "procesamiento.R", "db.R", "validacion.R")) source(f)
      con <- dbConnect(SQLite(), DB); on.exit(dbDisconnect(con))
      if (offline) {
        actualizar_offline(con, comercio, ejecucion_ui)
      } else {
        r <- actualizar_comercio(con, comercio)
        list(recolectadas = r$recolectadas, nuevas = r$nuevas, rechazadas = r$rechazadas)
      }
    }, globals = list(comercio = comercio, offline = offline,
                      ejecucion_ui = ejecucion_ui, DB = DB), seed = NULL)
  })
  observeEvent(input$actualizar, {
    tarea$invoke(input$cm_upd, input$modo == "offline", input$ejec)
  })
  observeEvent(tarea$status(), {
    if (tarea$status() == "success") version(version() + 1)
  })
  output$estado_upd <- renderText({
    switch(tarea$status(),
           running = "Actualizando…",
           success = { r <- tarea$result()
           glue("Listo: {r$recolectadas} recolectadas, {r$nuevas} nuevas, {r$rechazadas} rechazadas.") },
           error   = "Error al actualizar (ver consola).",
           "")
  })
}

shinyApp(ui, server)