# =============================================================================
# app.R — Comparador de precios: salud digestiva (Shiny + bslib + highcharter)
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(highcharter)
  library(DT)
  library(promises)
  library(future)
})

# Ejecución asíncrona en segundo plano (Módulo 2.2 / Anexo B)
plan(multisession)

source("db.R")
source("validacion.R")

# Asegura esquema, índices y vistas al arrancar
local({
  con <- abrir_conexion(DB_PATH_DEFAULT)
  on.exit(dbDisconnect(con), add = TRUE)
  migrar_esquema_t2(con)
})

# Paleta fija por comercio en toda la aplicación (Módulo 5.1)
COLORES_COMERCIO <- c(
  "Colsubsidio" = "#F39C12",
  "Farmatodo"   = "#1E88E5",
  "Cruz Verde"  = "#2E7D32"
)

formato_cop <- function(x) {
  ifelse(is.na(x), "N/D", paste0("$ ", format(round(x, 0), big.mark = ".", decimal.mark = ",")))
}

opciones_ini <- obtener_opciones_filtros(DB_PATH_DEFAULT)

# ---- INTERFAZ DE USUARIO (bslib) --------------------------------------------
ui <- page_navbar(
  title = "Comparador de precios · Salud digestiva",
  theme = bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = "#1B4F72",
    base_font = font_google("Inter")
  ),
  fillable = FALSE,
  
  # Panel lateral global de filtros y actualización
  sidebar = sidebar(
    width = 310,
    title = "Filtros y actualización",
    
    selectInput(
      "f_comercio", "Comercio:",
      choices  = opciones_ini$comercios,
      selected = opciones_ini$comercios,
      multiple = TRUE
    ),
    selectInput(
      "f_subcat", "Subcategoría:",
      choices  = opciones_ini$subcategorias,
      selected = NULL,
      multiple = TRUE
    ),
    selectInput(
      "f_marca", "Marca:",
      choices  = opciones_ini$marcas,
      selected = NULL,
      multiple = TRUE
    ),
    sliderInput(
      "f_precio", "Rango de precio (COP):",
      min   = opciones_ini$pmin,
      max   = opciones_ini$pmax,
      value = c(opciones_ini$pmin, opciones_ini$pmax),
      step  = 500,
      pre   = "$ "
    ),
    selectInput(
      "f_ejecucion", "Ejecución (vacío = última por comercio):",
      choices  = setNames(
        opciones_ini$ejecuciones$id_ejecucion,
        paste0(opciones_ini$ejecuciones$id_ejecucion, " (", substr(opciones_ini$ejecuciones$fecha_inicio, 1, 10), ")")
      ),
      selected = NULL,
      multiple = TRUE
    ),
    checkboxInput("f_promo", "Solo productos en promoción", value = FALSE),
    checkboxInput("f_comp",  "Solo productos comparables (P01–P12)", value = FALSE),
    textInput("f_busqueda", "Buscar en nombre o descripción:", placeholder = "Ej: Electrolit, 500 ml, sobre..."),
    actionButton("btn_limpiar", "Limpiar filtros", class = "btn-outline-secondary btn-sm w-100 mb-3"),
    
    hr(),
    strong("Actualizar base de precios"),
    checkboxInput("upd_offline", "Modo sin conexión (reprocesar raw/)", value = FALSE),
    conditionalPanel(
      condition = "input.upd_offline == true",
      selectInput(
        "upd_id_raw", "Ejecución en raw/:",
        choices = opciones_ini$ejecuciones$id_ejecucion
      )
    ),
    input_task_button("btn_actualizar", "Actualizar precios", class = "btn-primary w-100"),
    div(class = "mt-2 small text-muted", textOutput("estado_actualizacion"))
  ),
  
  # ==================== PESTAÑA 1: RESUMEN Y CATÁLOGO ========================
  nav_panel(
    title = "Resumen y catálogo",
    icon = icon("chart-line"),
    
    # Resultado de la última actualización ejecutada desde la app (si aplica)
    uiOutput("panel_resumen_actualizacion"),
    
    # 6 Tarjetas de indicadores calculados en SQL (Módulo 5.3)
    layout_columns(
      col_widths = c(4, 4, 4, 4, 4, 4),
      value_box(
        title    = "Productos únicos (ítems)",
        value    = textOutput("kpi_productos"),
        p(class = "small mb-0", textOutput("kpi_productos_sub")),
        showcase = icon("boxes-stacked"),
        theme    = "primary"
      ),
      value_box(
        title    = "Mediana de precio (COP)",
        value    = textOutput("kpi_mediana"),
        p(class = "small mb-0", textOutput("kpi_mediana_sub")),
        showcase = icon("tag"),
        theme    = "info"
      ),
      value_box(
        title    = "En promoción (%)",
        value    = textOutput("kpi_promo"),
        p(class = "small mb-0", "Sobre observaciones filtradas"),
        showcase = icon("percent"),
        theme    = "success"
      ),
      value_box(
        title    = "Ahorro máximo comparable (COP)",
        value    = textOutput("kpi_ahorro"),
        p(class = "small mb-0", textOutput("kpi_ahorro_sub")),
        showcase = icon("piggy-bank"),
        theme    = "warning"
      ),
      value_box(
        title    = "Cambios en última ejecución",
        value    = textOutput("kpi_cambios"),
        p(class = "small mb-0", "Anuncios con variación de precio"),
        showcase = icon("arrows-rotate"),
        theme    = "secondary"
      ),
      value_box(
        title    = "Última ejecución registrada",
        value    = textOutput("kpi_ultima_ej"),
        p(class = "small mb-0", textOutput("kpi_ultima_ej_sub")),
        showcase = icon("clock"),
        theme    = "dark"
      )
    ),
    
    # Fila 1 de gráficos interactivos (Highcharter)
    layout_columns(
      col_widths = c(6, 6),
      card(
        full_screen = TRUE,
        card_header(
          div(
            class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
            span("1. Evolución de precio por producto comparable (COP)"),
            selectInput(
              "g1_producto", label = NULL, width = "260px",
              choices = setNames(opciones_ini$comparables$id_producto, opciones_ini$comparables$nombre_std),
              selected = "P01"
            )
          )
        ),
        card_body(highchartOutput("graf_evolucion", height = "340px"))
      ),
      card(
        full_screen = TRUE,
        card_header(
          div(
            class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
            span("2. Precio por unidad normalizada (sin mezclar unidades)"),
            radioButtons(
              "g2_unidad", label = NULL, inline = TRUE,
              choices = c("COP / mL" = "mL", "COP / g" = "g", "COP / unidad" = "unidad"),
              selected = "mL"
            )
          )
        ),
        card_body(highchartOutput("graf_unitario", height = "340px"))
      )
    ),
    
    # Fila 2 de gráficos interactivos (Highcharter)
    layout_columns(
      col_widths = c(6, 6),
      card(
        full_screen = TRUE,
        card_header("3. Distribución de precios de la categoría por comercio (COP)"),
        card_body(highchartOutput("graf_distribucion", height = "340px"))
      ),
      card(
        full_screen = TRUE,
        card_header("4. Ahorro potencial (%) entre comercio más caro y más barato"),
        card_body(highchartOutput("graf_brecha_ahorro", height = "340px"))
      )
    ),
    
    # Tabla filtrable y descarga CSV (Módulo 5.5)
    card(
      card_header(
        div(
          class = "d-flex justify-content-between align-items-center",
          span("Catálogo de productos filtrados (precios en COP)"),
          downloadButton("descargar_csv", "Descargar CSV filtrado", class = "btn-sm btn-outline-primary")
        )
      ),
      card_body(DTOutput("tabla_productos"))
    )
  ),
  
  # ==================== PESTAÑA 2: CAMBIOS ENTRE EJECUCIONES ==================
  nav_panel(
    title = "Cambios entre ejecuciones",
    icon = icon("code-compare"),
    
    card(
      card_header("Comparación temporal del mismo anuncio en el mismo comercio"),
      card_body(
        layout_columns(
          col_widths = c(4, 4, 4),
          selectInput("cmp_ej_ant", "Ejecución anterior:", choices = NULL),
          selectInput("cmp_ej_act", "Ejecución actual:", choices = NULL),
          sliderInput("cmp_umbral", "Umbral de variación destacada (%):",
                      min = 0, max = 50, value = 5, step = 1, post = " %")
        ),
        layout_columns(
          col_widths = c(3, 3, 3, 3),
          value_box("Subieron de precio", textOutput("cmp_n_subieron"), theme = "danger"),
          value_box("Bajaron de precio", textOutput("cmp_n_bajaron"), theme = "success"),
          value_box("Anuncios nuevos", textOutput("cmp_n_nuevos"), theme = "info"),
          value_box("Dejaron de observarse", textOutput("cmp_n_ausentes"), theme = "warning")
        ),
        DTOutput("tabla_cambios")
      )
    )
  ),
  
  # ==================== PESTAÑA 3: CALCULADORA DE CANASTA ====================
  nav_panel(
    title = "Calculadora de canasta",
    icon = icon("cart-shopping"),
    
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("Configurar canasta comparable"),
        card_body(
          selectInput(
            "can_ejecucion", "Ejecución de referencia:",
            choices = setNames(opciones_ini$ejecuciones$id_ejecucion, opciones_ini$ejecuciones$id_ejecucion)
          ),
          selectInput(
            "can_productos", "Seleccione productos comparables:",
            choices  = setNames(opciones_ini$comparables$id_producto, opciones_ini$comparables$nombre_std),
            selected = c("P01", "P04", "P09", "P12"),
            multiple = TRUE
          ),
          uiOutput("can_cantidades_ui"),
          div(
            class = "alert alert-warning small mt-3 mb-0",
            icon("triangle-exclamation"),
            strong(" Aviso al consumidor: "),
            "Los totales calculados corresponden exclusivamente a los precios unitarios capturados en la ejecución seleccionada. No incluyen costos de envío, pedidos mínimos ni restricciones de medios de pago o programas de fidelización."
          )
        )
      ),
      div(
        layout_columns(
          col_widths = c(6, 6),
          value_box(
            title = "Costo mínimo óptimo (multi-comercio)",
            value = textOutput("can_costo_optimo"),
            p(class = "small mb-0", "Comprando cada ítem donde es más barato"),
            showcase = icon("award"),
            theme = "success"
          ),
          value_box(
            title = "Ahorro máximo de la canasta (COP)",
            value = textOutput("can_ahorro"),
            p(class = "small mb-0", textOutput("can_ahorro_sub")),
            showcase = icon("sack-dollar"),
            theme = "primary"
          )
        ),
        card(
          card_header("Costo total por comercio (solo se calcula si el comercio tiene todos los productos)"),
          card_body(DTOutput("tabla_canasta_comercios"))
        ),
        card(
          card_header("Desglose óptimo por producto"),
          card_body(DTOutput("tabla_canasta_optima"))
        )
      )
    )
  )
)

# ---- SERVIDOR ---------------------------------------------------------------
server <- function(input, output, session) {
  # Token reactivo para invalidar caché tras cada actualización de la base (Módulo 3)
  version_bd <- reactiveVal(1L)
  
  # Inicializar selectores de comparación de ejecuciones (por defecto las 2 más recientes)
  observe({
    version_bd()
    opts <- obtener_opciones_filtros(DB_PATH_DEFAULT)
    ejs  <- opts$ejecuciones$id_ejecucion
    
    updateSelectInput(session, "f_comercio", choices = opts$comercios,
                      selected = intersect(input$f_comercio %||% opts$comercios, opts$comercios))
    updateSelectInput(session, "f_subcat", choices = opts$subcategorias, selected = input$f_subcat)
    updateSelectInput(session, "f_marca",  choices = opts$marcas, selected = input$f_marca)
    updateSelectInput(session, "f_ejecucion",
                      choices = setNames(ejs, paste0(ejs, " (", substr(opts$ejecuciones$fecha_inicio, 1, 10), ")")),
                      selected = input$f_ejecucion)
    updateSelectInput(session, "upd_id_raw", choices = ejs, selected = ejs[1])
    updateSelectInput(session, "can_ejecucion", choices = ejs, selected = ejs[1])
    
    ej_act_def <- if (length(ejs) >= 1) ejs[1] else NULL
    ej_ant_def <- if (length(ejs) >= 2) ejs[2] else ej_act_def
    updateSelectInput(session, "cmp_ej_ant", choices = ejs, selected = ej_ant_def)
    updateSelectInput(session, "cmp_ej_act", choices = ejs, selected = ej_act_def)
  })
  
  # Botón limpiar filtros
  observeEvent(input$btn_limpiar, {
    opts <- obtener_opciones_filtros(DB_PATH_DEFAULT)
    updateSelectInput(session, "f_comercio", selected = opts$comercios)
    updateSelectInput(session, "f_subcat", selected = character(0))
    updateSelectInput(session, "f_marca", selected = character(0))
    updateSliderInput(session, "f_precio", value = c(opts$pmin, opts$pmax))
    updateSelectInput(session, "f_ejecucion", selected = character(0))
    updateCheckboxInput(session, "f_promo", value = FALSE)
    updateCheckboxInput(session, "f_comp", value = FALSE)
    updateTextInput(session, "f_busqueda", value = "")
  })
  
  # ---- Tarea asíncrona en segundo plano (Módulo 2: ExtendedTask) ------------
  tarea_scraping <- ExtendedTask$new(function(modo_offline, id_raw) {
    future_promise({
      source("scraper.R", local = TRUE)
      if (isTRUE(modo_offline)) {
        ejecutar_recoleccion(db = DB_PATH_DEFAULT, offline = TRUE, id_ejecucion = id_raw)
      } else {
        ejecutar_recoleccion(db = DB_PATH_DEFAULT, offline = FALSE)
      }
    })
  }) |> bind_task_button("btn_actualizar")
  
  observeEvent(input$btn_actualizar, {
    tarea_scraping$invoke(input$upd_offline, input$upd_id_raw)
  })
  
  # Cuando termina la tarea, incrementa versión de BD para invalidar cachés
  observeEvent(tarea_scraping$result(), {
    version_bd(isolate(version_bd()) + 1L)
  })
  
  output$estado_actualizacion <- renderText({
    st <- tarea_scraping$status()
    if (st == "running") {
      "Ejecutando recolección en segundo plano... La interfaz sigue operativa."
    } else if (st == "error") {
      "Error en la recolección. En despliegue remoto los comercios pueden bloquear Chrome; use el modo sin conexión."
    } else {
      "Listo para actualizar en línea o reprocesar raw/."
    }
  })
  
  output$panel_resumen_actualizacion <- renderUI({
    req(tarea_scraping$status() == "success")
    res <- tarea_scraping$result()
    req(nrow(res) > 0)
    
    card(
      class = "border-primary mb-3",
      card_header(class = "bg-primary text-white",
                  paste("Resultado de actualización — Ejecución:", res$id_ejecucion[1])),
      card_body(
        renderTable(res |> select(
          Comercio = comercio, Estado = estado, Recolectados = recolectados,
          Nuevos = nuevos, Rechazados = rechazados,
          `Cambios precio` = cambios_precio, `No observados` = no_observados,
          Detalle = detalle
        ))
      )
    )
  })
  
  
  datos_filtrados <- reactive({
    consultar_productos_filtrados(
      db_path          = DB_PATH_DEFAULT,
      comercios        = input$f_comercio,
      subcategorias    = input$f_subcat,
      marcas           = input$f_marca,
      rango_precio     = input$f_precio,
      ejecuciones      = input$f_ejecucion,
      solo_promociones = input$f_promo,
      solo_comparables = input$f_comp,
      busqueda         = input$f_busqueda
    )
  }) |> bindCache(
    version_bd(), input$f_comercio, input$f_subcat, input$f_marca,
    input$f_precio, input$f_ejecucion, input$f_promo, input$f_comp, input$f_busqueda
  )
  
  kpis_reactivos <- reactive({
    consultar_indicadores(
      db_path          = DB_PATH_DEFAULT,
      comercios        = input$f_comercio,
      subcategorias    = input$f_subcat,
      marcas           = input$f_marca,
      rango_precio     = input$f_precio,
      ejecuciones      = input$f_ejecucion,
      solo_promociones = input$f_promo,
      solo_comparables = input$f_comp,
      busqueda         = input$f_busqueda
    )
  }) |> bindCache(
    version_bd(), input$f_comercio, input$f_subcat, input$f_marca,
    input$f_precio, input$f_ejecucion, input$f_promo, input$f_comp, input$f_busqueda
  )
  
  # ---- Salidas de los 6 indicadores -----------------------------------------
  output$kpi_productos <- renderText({
    format(kpis_reactivos()$n_productos_unicos, big.mark = ".")
  })
  output$kpi_productos_sub <- renderText({
    pc <- kpis_reactivos()$por_comercio
    if (nrow(pc) == 0) return("Sin registros para el filtro actual")
    paste(paste0(pc$comercio, ": ", pc$n_productos), collapse = " | ")
  })
  
  output$kpi_mediana <- renderText({
    formato_cop(kpis_reactivos()$mediana_precio)
  })
  output$kpi_mediana_sub <- renderText({
    f <- kpis_reactivos()$ultima_fecha
    if (is.na(f)) "Sin datos" else paste("Corte:", substr(f, 1, 16))
  })
  
  output$kpi_promo <- renderText({
    paste0(kpis_reactivos()$pct_promocion, " %")
  })
  
  output$kpi_ahorro <- renderText({
    ah <- kpis_reactivos()$ahorro_max
    if (nrow(ah) == 0) "N/D" else paste0(formato_cop(ah$ahorro_cop), " (", ah$ahorro_pct, "%)")
  })
  output$kpi_ahorro_sub <- renderText({
    ah <- kpis_reactivos()$ahorro_max
    if (nrow(ah) == 0) "Sin comparables" else ah$nombre_std[1]
  })
  
  output$kpi_cambios <- renderText({
    as.character(kpis_reactivos()$n_cambios_ult)
  })
  
  output$kpi_ultima_ej <- renderText({
    ue <- kpis_reactivos()$ultima_ejecucion
    if (nrow(ue) == 0) "N/D" else substr(ue$inicio[1], 1, 10)
  })
  output$kpi_ultima_ej_sub <- renderText({
    ue <- kpis_reactivos()$ultima_ejecucion
    if (nrow(ue) == 0) "" else ue$id_ejecucion[1]
  })
  
  # ---- Gráficos interactivos Highcharter (Módulo 5.4) -----------------------
  
  # Gráfico 1: Evolución del precio de un producto comparable por comercio
  output$graf_evolucion <- renderHighchart({
    version_bd()
    req(input$g1_producto)
    df <- consultar_evolucion_producto(DB_PATH_DEFAULT, input$g1_producto)
    shiny::validate(shiny::need(nrow(df) > 0, "No hay observaciones históricas para este producto."))
    
    df <- df |>
      mutate(etiqueta_ej = paste0(substr(fecha_hora_consulta, 1, 10), " (", id_ejecucion, ")"))
    ejecuciones_x <- unique(df$etiqueta_ej)
    
    hc <- highchart() |>
      hc_chart(type = "line") |>
      hc_title(text = df$nombre_std[1], style = list(fontSize = "14px")) |>
      hc_xAxis(categories = ejecuciones_x, title = list(text = "Ejecución (fecha)")) |>
      hc_yAxis(title = list(text = "Precio (COP)"),
               labels = list(format = "$ {value:,.0f}")) |>
      hc_tooltip(shared = TRUE, valuePrefix = "$ ", valueDecimals = 0)
    
    for (com in names(COLORES_COMERCIO)) {
      sub <- df |> filter(comercio == com)
      if (nrow(sub) > 0) {
        vals <- vapply(ejecuciones_x, function(ej) {
          v <- sub$precio[sub$etiqueta_ej == ej]
          if (length(v) == 0) NA_real_ else v[1]
        }, numeric(1))
        hc <- hc |> hc_add_series(
          name  = com,
          data  = unname(vals),
          color = COLORES_COMERCIO[[com]]
        )
      }
    }
    hc
  })
  
  # Gráfico 2: Precio por unidad normalizada (sin mezclar mL, g y unidad)
  output$graf_unitario <- renderHighchart({
    version_bd()
    req(input$g2_unidad)
    df <- consultar_precio_unitario_por_unidad(DB_PATH_DEFAULT, input$g2_unidad, input$f_comercio)
    shiny::validate(shiny::need(nrow(df) > 0, "No hay productos comparables para esta unidad y filtros."))
    
    prods <- unique(df$nombre_std)
    hc <- highchart() |>
      hc_chart(type = "column") |>
      hc_title(text = paste("Comparación en COP /", input$g2_unidad), style = list(fontSize = "14px")) |>
      hc_xAxis(categories = prods, labels = list(rotation = -25)) |>
      hc_yAxis(title = list(text = paste("Precio por", input$g2_unidad, "(COP)")),
               labels = list(format = "$ {value:,.1f}")) |>
      hc_tooltip(valuePrefix = "$ ", valueSuffix = paste0(" / ", input$g2_unidad), valueDecimals = 2)
    
    for (com in names(COLORES_COMERCIO)) {
      sub <- df |> filter(comercio == com)
      if (nrow(sub) > 0) {
        vals <- vapply(prods, function(p) {
          v <- sub$precio_unitario[sub$nombre_std == p]
          if (length(v) == 0) NA_real_ else v[1]
        }, numeric(1))
        hc <- hc |> hc_add_series(
          name  = com,
          data  = unname(vals),
          color = COLORES_COMERCIO[[com]]
        )
      }
    }
    hc
  })
  
  # Gráfico 3: Distribución de precios por comercio (Boxplot en Highcharter)
  output$graf_distribucion <- renderHighchart({
    version_bd()
    df <- consultar_distribucion_precios(DB_PATH_DEFAULT, input$f_comercio, input$f_precio)
    shiny::validate(shiny::need(nrow(df) > 0, "No hay precios disponibles con los filtros actuales."))
    
    comercios_disp <- intersect(names(COLORES_COMERCIO), unique(df$comercio))
    cajas <- lapply(comercios_disp, function(com) {
      vals <- sort(df$precio[df$comercio == com])
      q <- as.numeric(quantile(vals, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE))
      list(low = q[1], q1 = q[2], median = q[3], q3 = q[4], high = q[5],
           color = COLORES_COMERCIO[[com]], fillColor = paste0(COLORES_COMERCIO[[com]], "33"))
    })
    
    highchart() |>
      hc_chart(type = "boxplot") |>
      hc_title(text = "Distribución de precios (Mín, Q1, Mediana, Q3, Máx)", style = list(fontSize = "14px")) |>
      hc_xAxis(categories = comercios_disp) |>
      hc_yAxis(title = list(text = "Precio (COP)"), labels = list(format = "$ {value:,.0f}")) |>
      hc_legend(enabled = FALSE) |>
      hc_add_series(name = "Precios (COP)", data = cajas) |>
      hc_tooltip(valuePrefix = "$ ", valueDecimals = 0)
  })
  
  # Gráfico 4: Brecha de ahorro (%) entre el comercio más caro y el más barato
  output$graf_brecha_ahorro <- renderHighchart({
    version_bd()
    df <- consultar_brecha_ahorro_comparables(DB_PATH_DEFAULT)
    shiny::validate(shiny::need(nrow(df) > 0, "No hay suficientes comparables para calcular brechas."))
    
    datos_barra <- lapply(seq_len(nrow(df)), function(i) {
      ganador <- strsplit(df$mas_barato[i], ",")[[1]][1] |> trimws()
      col <- if (ganador %in% names(COLORES_COMERCIO)) COLORES_COMERCIO[[ganador]] else "#34495E"
      list(
        y = df$ahorro_pct[i],
        color = col,
        ahorro_cop = formato_cop(df$ahorro_cop[i]),
        mas_barato = df$mas_barato[i],
        mas_caro   = df$mas_caro[i]
      )
    })
    
    highchart() |>
      hc_chart(type = "bar") |>
      hc_title(text = "Ahorro % eligiendo la tienda más barata (color = tienda más económica)",
               style = list(fontSize = "13px")) |>
      hc_xAxis(categories = df$nombre_std) |>
      hc_yAxis(title = list(text = "Ahorro potencial (%)"), labels = list(format = "{value}%")) |>
      hc_legend(enabled = FALSE) |>
      hc_add_series(name = "Ahorro %", data = datos_barra) |>
      hc_tooltip(
        useHTML = TRUE,
        pointFormat = "<b>Ahorro: {point.y}% ({point.ahorro_cop})</b><br>Más barato: {point.mas_barato}<br>Más caro: {point.mas_caro}"
      )
  })
  
  # ---- Tabla filtrable y descarga CSV (Módulo 5.5) ------------------------
  output$tabla_productos <- renderDT({
    df <- datos_filtrados()
    shiny::validate(shiny::need(nrow(df) > 0, "Ningún producto coincide con los filtros seleccionados."))
    
    df_vista <- df |>
      mutate(
        Enlace = sprintf('<a href="%s" target="_blank" rel="noopener">Ver anuncio</a>', url),
        Promocion = ifelse(promocion == 1, "Sí", "No")
      ) |>
      select(
        Comercio = comercio,
        Producto = producto,
        Marca = marca,
        Presentación = presentacion,
        `Precio (COP)` = precio,
        `Precio unitario` = precio_unitario,
        Unidad = unidad_norm,
        Promoción = Promocion,
        Disponibilidad = disponibilidad,
        `Fecha consulta` = fecha_hora_consulta,
        Enlace
      )
    
    datatable(
      df_vista,
      escape = FALSE,
      rownames = FALSE,
      options = list(pageLength = 15, scrollX = TRUE, language = list(url = "//cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json"))
    ) |>
      formatCurrency(c("Precio (COP)", "Precio unitario"), currency = "$ ", digits = 0, mark = ".", dec.mark = ",")
  })
  
  output$descargar_csv <- downloadHandler(
    filename = function() {
      paste0("comparador_precios_", format(Sys.time(), "%Y%m%d_%H%M"), ".csv")
    },
    content = function(file) {
      write.csv(datos_filtrados(), file, row.names = FALSE, fileEncoding = "UTF-8")
    }
  )
  
  # ---- Pestaña 2: Comparación entre dos ejecuciones (Módulo 6.2) ------------
  datos_comparacion <- reactive({
    version_bd()
    req(input$cmp_ej_ant, input$cmp_ej_act)
    comparar_dos_ejecuciones(DB_PATH_DEFAULT, input$cmp_ej_ant, input$cmp_ej_act)
  })
  
  output$cmp_n_subieron <- renderText({
    as.character(sum(datos_comparacion()$estado_cambio == "Subió", na.rm = TRUE))
  })
  output$cmp_n_bajaron <- renderText({
    as.character(sum(datos_comparacion()$estado_cambio == "Bajó", na.rm = TRUE))
  })
  output$cmp_n_nuevos <- renderText({
    as.character(sum(datos_comparacion()$estado_cambio == "Nuevo en ejecución", na.rm = TRUE))
  })
  output$cmp_n_ausentes <- renderText({
    as.character(sum(datos_comparacion()$estado_cambio == "Dejó de observarse", na.rm = TRUE))
  })
  
  output$tabla_cambios <- renderDT({
    df <- datos_comparacion()
    shiny::validate(shiny::need(nrow(df) > 0, "No hay registros para comparar entre estas dos ejecuciones."))
    
    umbral <- input$cmp_umbral %||% 5
    df_mostrar <- df |>
      mutate(
        destacado = ifelse(!is.na(cambio_pct) & abs(cambio_pct) >= umbral, 1, 0),
        Enlace = sprintf('<a href="%s" target="_blank" rel="noopener">Abrir</a>', url)
      ) |>
      select(
        Comercio = comercio,
        SKU = sku,
        Producto = producto,
        Estado = estado_cambio,
        `Precio anterior (COP)` = precio_anterior,
        `Precio actual (COP)` = precio_actual,
        `Cambio (COP)` = cambio_cop,
        `Cambio (%)` = cambio_pct,
        destacado,
        Enlace
      )
    
    datatable(
      df_mostrar,
      escape = FALSE,
      rownames = FALSE,
      options = list(
        pageLength = 15,
        scrollX = TRUE,
        columnDefs = list(list(visible = FALSE, targets = 8))
      )
    ) |>
      formatCurrency(c("Precio anterior (COP)", "Precio actual (COP)", "Cambio (COP)"),
                     currency = "$ ", digits = 0, mark = ".", dec.mark = ",") |>
      formatStyle(
        "destacado",
        target = "row",
        backgroundColor = styleEqual(1, "#FCF3CF"),
        fontWeight = styleEqual(1, "bold")
      )
  })
  
  # ---- Pestaña 3: Calculadora de Canasta (Módulo 6.3) -----------------------
  output$can_cantidades_ui <- renderUI({
    req(input$can_productos)
    prods <- opciones_ini$comparables |> filter(id_producto %in% input$can_productos)
    lapply(seq_len(nrow(prods)), function(i) {
      pid <- prods$id_producto[i]
      numericInput(
        inputId = paste0("cant_", pid),
        label   = paste0(prods$nombre_std[i], " (cantidad):"),
        value   = 1, min = 1, max = 50, step = 1
      )
    })
  })
  
  resultado_canasta <- reactive({
    version_bd()
    req(input$can_productos, input$can_ejecucion)
    items <- lapply(input$can_productos, function(pid) {
      cant <- input[[paste0("cant_", pid)]] %||% 1
      tibble(id_producto = pid, cantidad = as.integer(cant))
    }) |> bind_rows()
    
    calcular_canasta(DB_PATH_DEFAULT, items, id_ejecucion = input$can_ejecucion)
  })
  
  output$can_costo_optimo <- renderText({
    formato_cop(resultado_canasta()$costo_optimo)
  })
  
  output$can_ahorro <- renderText({
    res <- resultado_canasta()
    if (is.na(res$ahorro_vs_mejor_tienda)) "N/D" else formato_cop(res$ahorro_vs_mejor_tienda)
  })
  
  output$can_ahorro_sub <- renderText({
    res <- resultado_canasta()
    if (is.na(res$ahorro_vs_mejor_tienda)) {
      "Ningún comercio tiene la canasta completa"
    } else {
      paste("Frente al mejor comercio único (hasta", formato_cop(res$ahorro_vs_peor_tienda), "vs el más caro)")
    }
  })
  
  output$tabla_canasta_comercios <- renderDT({
    df <- resultado_canasta()$por_comercio
    shiny::validate(shiny::need(nrow(df) > 0, "Seleccione al menos un producto para calcular la canasta."))
    
    datatable(
      df |> select(
        Comercio = comercio,
        `Cobertura` = items_cubiertos,
        `Costo total (COP)` = costo_total,
        `Estado de la canasta` = estado_canasta
      ),
      rownames = FALSE,
      options = list(dom = "t")
    ) |>
      formatCurrency("Costo total (COP)", currency = "$ ", digits = 0, mark = ".", dec.mark = ",")
  })
  
  output$tabla_canasta_optima <- renderDT({
    df <- resultado_canasta()$optima_detalle
    shiny::validate(shiny::need(nrow(df) > 0, "Seleccione al menos un producto."))
    
    datatable(
      df |> select(
        Producto = producto,
        Cantidad = cantidad,
        `Menor precio unit. (COP)` = precio_min_unit,
        `Dónde comprar` = mejor_comercio,
        `Subtotal (COP)` = subtotal
      ),
      rownames = FALSE,
      options = list(dom = "t", pageLength = 15)
    ) |>
      formatCurrency(c("Menor precio unit. (COP)", "Subtotal (COP)"),
                     currency = "$ ", digits = 0, mark = ".", dec.mark = ",")
  })
}

shinyApp(ui, server)
