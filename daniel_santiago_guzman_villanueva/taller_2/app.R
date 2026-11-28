
# Presentacion y paquetes -------------------------------------------------
# app.R — Taller 2: Comparador de precios de Salud visual y lentes de contacto
#
# Interfaz en Shiny + bslib. No contiene SQL: todas las consultas están en
# db.R. La actualización llama a ejecutar_recoleccion() de scraper.R en una
# tarea en segundo plano (ExtendedTask), sin bloquear la aplicación.
#
# Ejecutar desde la carpeta taller_2/:  shiny::runApp()
# .........................................................................
library(shiny)       # >= 1.8.1 (ExtendedTask)
library(bslib)       # >= 0.7   (input_task_button)
library(highcharter)
library(DT)
library(promises)
library(future)      # jneap

source("db.R", encoding = "UTF-8")

# Dos procesos de R auxiliares: la actualización corre en uno de ellos
plan(multisession, workers = 2)

DIR_APP <- normalizePath(".")
con <- abrir_conexion(file.path(DIR_APP, "comparador_precios.sqlite"))
onStop(function() DBI::dbDisconnect(con))

# Mismo color para cada comercio en toda la aplicación
# Aquí me tomo la libertad de poner los coloresque correspondan a cada comercio
# locatel es un color verde porque oliva no cargo
# farmatodo es azul como su logo, pero deje deepsky por ser de mis colores 
# favoritos de R
# y colsubsidio se queda con su color institucional porque lo tenia a mano
COLORES <- c(locatel = "#2ca02c", farmatodo = "#00BFFF", colsubsidio = "#612166")

op0 <- opciones_filtros(con)
NOMBRES <- setNames(op0$comercios$nombre, op0$comercios$comercio)
COLORES_NOMBRE <- setNames(COLORES[names(NOMBRES)], NOMBRES)

AVISO_CANASTA <- paste(
  "El resultado no incluye costos de envío, pedidos mínimos ni las condiciones",
  "de las promociones (vigencia, topes por cliente, medios de pago)."
)

# Highcharts en español, con punto de miles y coma decimal
lang <- getOption("highcharter.lang")
lang$decimalPoint <- ","
lang$thousandsSep <- "."
lang$months <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                 "agosto", "septiembre", "octubre", "noviembre", "diciembre")
lang$shortMonths <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago",
                      "sep", "oct", "nov", "dic")
lang$weekdays <- c("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")
lang$noData <- "No hay datos para mostrar"
options(highcharter.lang = lang)


# .........................................................................
# Utilidades de formato (sin acceso a datos) ------------------------------
# .........................................................................
# Nota revision codigo: esta seccion hace varias declaraciones de funciones
# Generalmente dan formato al llamado del scraper
cop <- function(x, digitos = 0) {
  ifelse(is.na(x), "—",
         paste0("$ ", formatC(round(x, digitos), format = "f", digits = digitos,
                              big.mark = ".", decimal.mark = ",")))
}
fmt_fecha <- function(x) ifelse(is.na(x), "—", paste(substr(x, 1, 10), substr(x, 12, 16)))
# "2026-11-15T18:54:00-05:00" -> milisegundos para Highcharts. Se lee la hora
# local de Colombia como si fuera UTC para que el eje muestre la hora local.
a_ms <- function(x) {
  as.numeric(as.POSIXct(substr(x, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")) * 1000
}

# Corridas con copias crudas de los tres comercios (para el modo sin conexión)
corridas_crudas <- function(dir_raw = file.path(DIR_APP, "raw")) {
  l <- lapply(names(COLORES), function(com) {
    basename(list.dirs(file.path(dir_raw, com), recursive = FALSE))
  })
  sort(Reduce(intersect, l), decreasing = TRUE)
}

# Mensaje claro en lugar de un error técnico
seguro <- function(expr) {
  tryCatch(expr, error = function(e) {
    if (inherits(e, "shiny.silent.error")) stop(e)
    validate(need(FALSE, paste("No fue posible consultar los datos:", conditionMessage(e))))
  })
}

opciones_ejecucion <- function(ej) setNames(ej$id_ejecucion, ej$etiqueta)

# .........................................................................
# Interfaz ----------------------------------------------------------------
# .........................................................................
filtros_ui <- sidebar(
  width = 300,
  title = "Filtros",
  selectizeInput("comercios", "Comercio", multiple = TRUE,
                 choices = setNames(op0$comercios$comercio, op0$comercios$nombre),
                 selected = op0$comercios$comercio),
  selectizeInput("subcategorias", "Subcategoría", choices = op0$subcategorias,
                 multiple = TRUE, options = list(placeholder = "Todas")),
  selectizeInput("marcas", "Marca", choices = op0$marcas, multiple = TRUE,
                 options = list(placeholder = "Todas")),
  sliderInput("precio", "Precio del empaque (COP)", min = op0$precio[1], max = op0$precio[2],
              value = op0$precio, step = 1000, pre = "$", sep = "."),
  radioButtons("periodo", "Periodo", inline = TRUE,
               choices = c("Una ejecución" = "ejecucion", "Rango de fechas" = "fechas")),
  conditionalPanel(
    "input.periodo == 'ejecucion'",
    selectInput("ejecucion", "Ejecución", choices = opciones_ejecucion(op0$ejecuciones),
                selected = op0$referencia)
  ),
  conditionalPanel(
    "input.periodo == 'fechas'",
    dateRangeInput("fechas", "Fechas de consulta", start = op0$fechas[1], end = op0$fechas[2],
                   language = "es", separator = "a", format = "yyyy-mm-dd")
  ),
  checkboxInput("solo_promo", "Solo productos en promoción"),
  checkboxInput("solo_comparables", "Solo productos comparables (en los 3 comercios)"),
  textInput("texto", "Buscar en el nombre o el texto del anuncio",
            placeholder = "p. ej. renu, +2.50"),
  helpText("Los filtros aplican a Resumen y Productos. En Cambios de precio y",
           "Canasta solo aplica el filtro de comercio.")
)

ui <- page_navbar(
  title = "Comparador de precios · Salud visual",
  theme = bs_theme(version = 5, primary = "#2c3e50"),
  sidebar = filtros_ui,
  fillable = FALSE,

  nav_panel(
    "Resumen",
    uiOutput("periodo_texto"),
    layout_column_wrap(
      width = "220px", fill = FALSE,
      value_box("Productos en la categoría", textOutput("vb_productos"),
                uiOutput("vb_productos_det")),
      value_box("Observaciones de precio", textOutput("vb_obs"), uiOutput("vb_obs_det")),
      value_box("Última ejecución", textOutput("vb_ultima"), uiOutput("vb_ultima_det")),
      value_box("En promoción", textOutput("vb_promo"), uiOutput("vb_promo_det")),
      value_box("Mediana del precio", textOutput("vb_mediana"), uiOutput("vb_mediana_det")),
      value_box("Ahorro máximo entre comercios", textOutput("vb_ahorro"), uiOutput("vb_ahorro_det")),
      value_box("Cambios de precio (última ejecución)", textOutput("vb_cambios"),
                uiOutput("vb_cambios_det"))
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        card_header("Evolución del precio de un producto comparable"),
        selectInput("producto_serie", NULL, width = "100%",
                    choices = setNames(op0$comparables$id_producto, op0$comparables$nombre_std)),
        highchartOutput("g_serie", height = "360px")
      ),
      card(
        card_header("Mediana del precio por subcategoría"),
        tableOutput("t_mediana_sub")
      )
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Precio por unidad de contenido entre comercios"),
        radioButtons("unidad", NULL, inline = TRUE, choices = op0$unidades,
                     selected = "mL"),
        highchartOutput("g_unitario", height = "420px")
      ),
      card(
        card_header("Distribución de precios de la categoría por comercio"),
        highchartOutput("g_distribucion", height = "460px")
      )
    ),
    card(
      card_header("¿Cuánto me ahorro comprando cada presentación en el comercio más barato?"),
      highchartOutput("g_ahorro", height = "420px")
    )
  ),

  nav_panel(
    "Productos",
    card(
      card_header(
        class = "d-flex justify-content-between align-items-center",
        uiOutput("titulo_tabla", inline = TRUE),
        downloadButton("descargar", "Descargar CSV", class = "btn-sm")
      ),
      DTOutput("tabla")
    )
  ),

  nav_panel(
    "Cambios de precio",
    card(
      layout_columns(
        col_widths = c(3, 3, 3, 3),
        selectInput("ejec_a", "Ejecución anterior", choices = NULL),
        selectInput("ejec_b", "Ejecución posterior", choices = NULL),
        sliderInput("umbral", "Resaltar variaciones de al menos (%)", min = 0, max = 50,
                    value = 10, step = 1, post = " %"),
        checkboxInput("cambios_comparables", "Solo productos comparables")
      ),
      helpText("Se compara el mismo anuncio (mismo producto en el mismo comercio) en las dos",
               "ejecuciones. Un producto que no aparece en la ejecución posterior se reporta",
               "como «dejó de observarse», no como agotado ni retirado.")
    ),
    layout_column_wrap(
      width = "200px", fill = FALSE,
      value_box("Subieron", textOutput("vc_sube")),
      value_box("Bajaron", textOutput("vc_baja")),
      value_box("Productos nuevos", textOutput("vc_nuevos")),
      value_box("Dejaron de observarse", textOutput("vc_no_obs"))
    ),
    navset_card_tab(
      nav_panel("Cambios de precio", DTOutput("t_cambios")),
      nav_panel("Productos nuevos", DTOutput("t_nuevos")),
      nav_panel("Dejaron de observarse", DTOutput("t_no_obs"))
    )
  ),

  nav_panel(
    "Canasta",
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("Arme su canasta"),
        selectInput("ejec_canasta", "Precios de la ejecución", choices = NULL),
        selectizeInput("canasta_prod", "Productos comparables", multiple = TRUE,
                       choices = setNames(op0$comparables$id_producto, op0$comparables$nombre_std),
                       options = list(placeholder = "Elija uno o varios productos")),
        uiOutput("canasta_cantidades"),
        checkboxInput("canasta_disp", "Excluir productos agotados", value = TRUE)
      ),
      card(
        card_header("Resultado"),
        uiOutput("canasta_resumen"),
        h6("Costo en cada comercio"),
        tableOutput("canasta_comercios"),
        h6("Comprando cada producto donde es más barato"),
        tableOutput("canasta_optimo"),
        div(class = "alert alert-warning small mb-0", AVISO_CANASTA)
      )
    )
  ),

  nav_panel(
    "Actualizar precios",
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header("Nueva ejecución del scraper"),
        radioButtons("modo_act", "Modo", choices = c(
          "En línea: consulta los tres sitios" = "en_linea",
          "Sin conexión: reprocesa las copias crudas de raw/" = "sin_conexion")),
        conditionalPanel(
          "input.modo_act == 'sin_conexion'",
          selectInput("corrida_raw", "Corrida guardada en raw/", choices = corridas_crudas())
        ),
        input_task_button("actualizar", "Actualizar precios", label_busy = "Actualizando…",
                          icon = NULL),
        helpText("La actualización corre en segundo plano: puede seguir usando la aplicación.",
                 "En línea tarda unos minutos (pausa de 1,5 s entre peticiones).",
                 "Cada comercio se inserta en su propia transacción; si uno falla, los demás",
                 "continúan y la ejecución de ese comercio queda como parcial o fallida.")
      ),
      card(
        card_header("Resultado de la actualización"),
        uiOutput("act_mensaje"),
        tableOutput("act_resumen")
      )
    )
  ),

  nav_panel(
    "Calidad de los datos",
    card(card_header("Ejecuciones registradas"), DTOutput("t_ejecuciones")),
    layout_columns(
      col_widths = c(7, 5),
      card(card_header("Correcciones a la base del Taller 1"), DTOutput("t_correcciones")),
      card(card_header("Observaciones rechazadas en la validación"), tableOutput("t_rechazos"))
    ),
    card(
      card_header("Origen de los datos"),
      p("Todos los precios provienen del scraper (scraper.R) ejecutado sobre los servicios",
        "que usan las propias páginas de Locatel, Farmatodo y Droguerías Colsubsidio.",
        "Cada respuesta se guarda sin modificar en raw/<comercio>/<ejecución>/ y cada",
        "observación conserva su fecha y hora de consulta y su ejecución. Un precio que",
        "no se pudo extraer queda vacío; nunca se completa ni se estima."),
      p("Los precios corresponden al momento de la consulta y no incluyen envío.")
    )
  ),

  nav_spacer(),
  nav_item(uiOutput("fecha_datos", class = "small text-muted"))
)

# .........................................................................
# Servidor ----------------------------------------------------------------
# .........................................................................
# Cada sección explorable en el menu lateral de R Studio a partir de aqui
# Son las paginas de la cinta de secciones de la app o funciones de cada
# seccion
server <- function(input, output, session) {

  # --- Versión de los datos: invalida la caché cuando cambia la base --------
  firma <- reactivePoll(5000, session,
                        checkFunc = function() firma_datos(con),
                        valueFunc = function() firma_datos(con))

  opciones <- reactive(opciones_filtros(con)) |> bindCache(firma())

  # Mantiene los selectores de ejecución al día después de una actualización
  observeEvent(opciones(), {
    op <- opciones()
    ch <- opciones_ejecucion(op$ejecuciones)
    sel <- if (isTruthy(input$ejecucion) && input$ejecucion %in% ch) input$ejecucion else op$referencia
    updateSelectInput(session, "ejecucion", choices = ch, selected = sel)
    ids <- op$ejecuciones$id_ejecucion
    updateSelectInput(session, "ejec_b", choices = ch, selected = ids[1])
    updateSelectInput(session, "ejec_a", choices = ch, selected = ids[min(2, length(ids))])
    updateSelectInput(session, "ejec_canasta", choices = ch, selected = op$referencia)
    updateSelectInput(session, "corrida_raw", choices = corridas_crudas())
  })

  # --- Filtros (validados y limpiados en db.R) ------------------------------
  filtros_brutos <- reactive({
    list(comercios = input$comercios, subcategorias = input$subcategorias,
         marcas = input$marcas, precio = input$precio, periodo = input$periodo,
         ejecucion = input$ejecucion, fechas = input$fechas,
         solo_promo = input$solo_promo, solo_comparables = input$solo_comparables,
         texto = input$texto)
  }) |> debounce(400)

  filtros <- reactive({
    f <- tryCatch(limpiar_filtros(filtros_brutos(), opciones()), error = function(e) e)
    validate(need(!inherits(f, "error"), if (inherits(f, "error")) conditionMessage(f)))
    validate(need(length(f$comercios) > 0, "Elija al menos un comercio."))
    f
  })

  periodo_txt <- reactive(describir_periodo(filtros(), opciones()$ejecuciones))
  # Ejecución usada en los indicadores que comparan comercios
  ejec_ref <- reactive({
    f <- filtros()
    if (f$periodo == "ejecucion" && !is.na(f$ejecucion)) f$ejecucion else opciones()$referencia
  })
  etiqueta_ej <- function(id) {
    e <- opciones()$ejecuciones
    if (id %in% e$id_ejecucion) e$etiqueta[e$id_ejecucion == id] else id
  }

  output$fecha_datos <- renderUI({
    firma()
    u <- ind_ultima_ejecucion(con)
    HTML(sprintf("Datos al %s · ejecución %s", fmt_fecha(u$inicio), u$id_ejecucion))
  })
  output$periodo_texto <- renderUI({
    p(class = "text-muted small",
      sprintf("Periodo: %s. Precios en pesos colombianos (COP) por empaque.", periodo_txt()))
  })

  # --- Indicadores -----------------------------------------------------------
  por_comercio <- reactive(seguro(ind_por_comercio(con, filtros()))) |>
    bindCache(filtros(), firma())
  promo   <- reactive(seguro(ind_promocion(con, filtros()))) |> bindCache(filtros(), firma())
  mediana <- reactive(seguro(mediana_precio(con, filtros()))) |> bindCache(filtros(), firma())
  mediana_sub <- reactive(seguro(mediana_precio(con, filtros(), por_subcategoria = TRUE))) |>
    bindCache(filtros(), firma())
  ahorros <- reactive(seguro(ahorro_por_producto(con, ejec_ref(), filtros()$comercios))) |>
    bindCache(ejec_ref(), filtros()$comercios, firma())
  cambios_ult <- reactive(seguro(ind_cambios_ultima(con, filtros()$comercios))) |>
    bindCache(filtros()$comercios, firma())
  ultima <- reactive(seguro(ind_ultima_ejecucion(con))) |> bindCache(firma())

  detalle_comercio <- function(d, col) {
    tags$small(paste(sprintf("%s: %s", d$comercio,
                             format(d[[col]], big.mark = ".", decimal.mark = ",")), collapse = " · "),
               tags$br(), periodo_txt())
  }
  output$vb_productos <- renderText({
    d <- por_comercio(); validate(need(nrow(d) > 0, "Sin datos para estos filtros"))
    paste(format(sum(d$productos), big.mark = ".", decimal.mark = ","), "anuncios")
  })
  output$vb_productos_det <- renderUI(detalle_comercio(por_comercio(), "productos"))
  output$vb_obs <- renderText({
    d <- por_comercio(); validate(need(nrow(d) > 0, "Sin datos para estos filtros"))
    paste(format(sum(d$observaciones), big.mark = ".", decimal.mark = ","), "precios")
  })
  output$vb_obs_det <- renderUI(detalle_comercio(por_comercio(), "observaciones"))
  output$vb_ultima <- renderText(fmt_fecha(ultima()$inicio))
  output$vb_ultima_det <- renderUI({
    u <- ultima()
    tags$small(sprintf("Ejecución %s: %d de %d comercios completos", u$id_ejecucion,
                       u$completas, u$comercios), tags$br(), u$detalle)
  })
  output$vb_promo <- renderText({
    d <- promo(); validate(need(isTRUE(d$con_precio > 0), "Sin datos para estos filtros"))
    paste0(format(d$pct_promocion, decimal.mark = ","), " %")
  })
  output$vb_promo_det <- renderUI({
    d <- promo()
    tags$small(sprintf("%s de %s observaciones con precio", d$en_promocion, d$con_precio),
               tags$br(), periodo_txt())
  })
  output$vb_mediana <- renderText({
    d <- mediana(); validate(need(nrow(d) > 0, "Sin datos para estos filtros"))
    paste(cop(d$mediana), "COP")
  })
  output$vb_mediana_det <- renderUI(tags$small(
    sprintf("Precio por empaque, %s observaciones", format(mediana()$observaciones, big.mark = ".", decimal.mark = ",")),
    tags$br(), periodo_txt()))
  output$vb_ahorro <- renderText({
    d <- ahorros(); validate(need(nrow(d) > 0, "Sin comparables"))
    paste(cop(d$ahorro_cop[1]), "COP")
  })
  output$vb_ahorro_det <- renderUI({
    d <- ahorros()
    tags$small(sprintf("%s (%s %%), comprando en %s", d$producto[1],
                       format(d$ahorro_pct[1], decimal.mark = ","),
                       paste(NOMBRES[strsplit(d$comercio_mas_barato[1], ", ")[[1]]],
                             collapse = " o ")),
               tags$br(), paste("Ejecución", etiqueta_ej(ejec_ref())))
  })
  output$vb_cambios <- renderText({
    d <- cambios_ult(); validate(need(nrow(d) > 0, "Sin ejecución anterior"))
    sprintf("▲ %d  ▼ %d", d$subieron, d$bajaron)
  })
  output$vb_cambios_det <- renderUI({
    d <- cambios_ult()
    tags$small(sprintf("Subieron / bajaron de %s anuncios con precio anterior",
                       format(d$comparados, big.mark = ".", decimal.mark = ",")), tags$br(),
               paste("Ejecución", etiqueta_ej(d$id_ejecucion), "frente a la observación anterior"))
  })

  output$t_mediana_sub <- renderTable({
    d <- mediana_sub(); validate(need(nrow(d) > 0, "No hay datos para los filtros seleccionados."))
    data.frame(`Subcategoría` = d$subcategoria, `Mediana (COP)` = cop(d$mediana),
               Observaciones = d$observaciones, check.names = FALSE)
  }, align = "lrr")

  # --- Gráficos ---------------------------------------------------------------
  serie <- reactive({
    req(input$producto_serie)
    id <- solo_permitidos(input$producto_serie, opciones()$comparables$id_producto)
    validate(need(length(id) == 1, "Elija un producto comparable."))
    seguro(serie_producto(con, id, filtros()$comercios))
  }) |> bindCache(input$producto_serie, filtros()$comercios, firma())

  output$g_serie <- renderHighchart({
    d <- serie()
    validate(need(nrow(d) > 0, "No hay precios de este producto para los comercios elegidos."))
    hc <- highchart() |>
      hc_xAxis(type = "datetime", title = list(text = "Fecha de consulta")) |>
      hc_yAxis(title = list(text = "Precio del empaque (COP)"),
               labels = list(format = "$ {value:,.0f}")) |>
      hc_tooltip(shared = FALSE, xDateFormat = "%Y-%m-%d %H:%M",
                 pointFormat = "{series.name}: <b>$ {point.y:,.0f} COP</b><br>{point.estado}") |>
      hc_subtitle(text = paste(d$nombre_std[1], "· todas las ejecuciones · hora de Colombia"))
    for (com in unique(d$comercio)) {
      s <- d[d$comercio == com, ]
      puntos <- lapply(seq_len(nrow(s)), function(i) list(
        x = a_ms(s$fecha_hora_consulta[i]), y = s$precio[i],
        estado = paste0(if (s$promocion[i] == 1) "En promoción · " else "",
                        s$disponibilidad[i])))
      hc <- hc |> hc_add_series(data = puntos, type = "line", name = NOMBRES[[com]],
                                color = COLORES[[com]], marker = list(enabled = TRUE))
    }
    hc |> hc_exporting(enabled = TRUE)
  })

  unitario <- reactive({
    u <- solo_permitidos(input$unidad, opciones()$unidades)
    validate(need(length(u) == 1, "Elija una unidad."))
    seguro(precio_unitario(con, ejec_ref(), u, filtros()$comercios))
  }) |> bindCache(input$unidad, ejec_ref(), filtros()$comercios, firma())

  output$g_unitario <- renderHighchart({
    d <- unitario()
    validate(need(nrow(d) > 0, "No hay productos comparables con esa unidad para los filtros elegidos."))
    unidad <- d$unidad[1]
    productos <- unique(d$producto)
    hc <- highchart() |>
      hc_chart(type = "bar") |>
      hc_xAxis(categories = as.list(productos)) |>
      hc_yAxis(title = list(text = paste("COP por", unidad))) |>
      hc_tooltip(shared = TRUE, valueDecimals = if (unidad == "und") 0 else 1,
                 valuePrefix = "$ ", valueSuffix = paste(" COP por", unidad)) |>
      hc_subtitle(text = paste("Solo presentaciones medidas en", unidad, "· ejecución",
                               etiqueta_ej(ejec_ref())))
    for (com in unique(d$comercio)) {
      s <- d[d$comercio == com, ]
      hc <- hc |> hc_add_series(name = NOMBRES[[com]], color = COLORES[[com]],
                                data = s$precio_unitario[match(productos, s$producto)])
    }
    hc |> hc_exporting(enabled = TRUE)
  })

  cuartiles <- reactive(seguro(cuartiles_precio(con, filtros()))) |> bindCache(filtros(), firma())

  output$g_distribucion <- renderHighchart({
    d <- cuartiles()
    validate(need(nrow(d) > 0, "No hay datos para los filtros seleccionados."))
    hc <- highchart() |>
      hc_chart(type = "boxplot") |>
      hc_xAxis(categories = as.list(d$nombre)) |>
      hc_yAxis(title = list(text = "Precio del empaque (COP)"),
               labels = list(format = "$ {value:,.0f}")) |>
      hc_legend(enabled = FALSE) |>
      hc_plotOptions(boxplot = list(grouping = FALSE, lineWidth = 2)) |>
      hc_tooltip(headerFormat = "<b>{point.key}</b><br>",
                 pointFormat = paste("Máximo: $ {point.high:,.0f}<br>Q3: $ {point.q3:,.0f}<br>",
                                     "Mediana: $ {point.median:,.0f}<br>Q1: $ {point.q1:,.0f}<br>",
                                     "Mínimo: $ {point.low:,.0f}<br>Observaciones: {point.n}")) |>
      hc_subtitle(text = paste("Mínimo, cuartiles y máximo ·", periodo_txt(),
                               "· filtre por subcategoría para comparar productos similares"))
    for (i in seq_len(nrow(d))) {
      hc <- hc |> hc_add_series(
        name = d$nombre[i], color = COLORES[[d$comercio[i]]], fillColor = "#ffffff",
        data = list(list(x = i - 1, low = d$minimo[i], q1 = d$q1[i], median = d$mediana[i],
                         q3 = d$q3[i], high = d$maximo[i], n = d$n[i])))
    }
    hc |> hc_exporting(enabled = TRUE)
  })

  output$g_ahorro <- renderHighchart({
    d <- ahorros()
    validate(need(nrow(d) > 0, "No hay productos comparables para los comercios elegidos."))
    validate(need(length(filtros()$comercios) >= 2, "Elija al menos dos comercios para comparar."))
    puntos <- lapply(seq_len(nrow(d)), function(i) {
      donde <- strsplit(d$comercio_mas_barato[i], ", ")[[1]]
      list(y = d$ahorro_cop[i], pct = d$ahorro_pct[i],
           donde = paste(NOMBRES[donde], collapse = " o "),
           color = if (length(donde) == 1) COLORES[[donde]] else "#7f8c8d")
    })
    highchart() |>
      hc_chart(type = "bar") |>
      hc_xAxis(categories = as.list(d$producto)) |>
      hc_yAxis(title = list(text = "Ahorro frente al precio más alto (COP por empaque)"),
               labels = list(format = "$ {value:,.0f}")) |>
      hc_add_series(name = "Ahorro", data = puntos, showInLegend = FALSE) |>
      hc_plotOptions(bar = list(dataLabels = list(enabled = TRUE, format = "{point.pct:,.1f} %"))) |>
      hc_tooltip(pointFormat = "Ahorro: <b>$ {point.y:,.0f} COP</b> ({point.pct:,.1f} %)<br>Más barato en: {point.donde}") |>
      hc_subtitle(text = paste("El color indica el comercio más barato (gris = empate) · ejecución",
                               etiqueta_ej(ejec_ref()))) |>
      hc_exporting(enabled = TRUE)
  })

  # --- Tabla de productos ----------------------------------------------------
  tabla <- reactive(seguro(productos_filtrados(con, filtros()))) |> bindCache(filtros(), firma())

  tabla_mostrar <- reactive({
    d <- tabla()
    data.frame(
      Comercio = d$comercio, Nombre = d$nombre, Marca = d$marca,
      `Presentación` = ifelse(is.na(d$contenido), "—",
                              paste(format(d$contenido, decimal.mark = ",", drop0trailing = TRUE),
                                    d$unidad)),
      `Precio (COP)` = d$precio,
      `Precio unitario (COP)` = d$precio_unitario,
      `Unidad del precio unitario` = ifelse(is.na(d$unidad), "—", paste("por", d$unidad)),
      `Promoción` = ifelse(d$promocion == 1, "Sí", "No"),
      Disponibilidad = d$disponibilidad,
      `Fecha de consulta` = fmt_fecha(d$fecha_hora_consulta),
      url = d$url,
      check.names = FALSE
    )
  })

  output$titulo_tabla <- renderUI({
    span(sprintf("%s registros · %s", format(nrow(tabla()), big.mark = ".", decimal.mark = ","), periodo_txt()))
  })

  output$tabla <- renderDT({
    d <- tabla_mostrar()
    validate(need(nrow(d) > 0, "No hay productos para los filtros seleccionados."))
    ok <- grepl("^https?://", d$url)
    d$Enlace <- ifelse(ok, sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">Ver anuncio</a>',
                                   htmltools::htmlEscape(d$url, attribute = TRUE)), "")
    d$url <- NULL
    datatable(d, rownames = FALSE, escape = setdiff(names(d), "Enlace"),
              filter = "top",
              options = list(pageLength = 25, scrollX = TRUE,
                             language = list(url = "https://cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json"))) |>
      formatCurrency("Precio (COP)", currency = "$ ", mark = ".", dec.mark = ",", digits = 0) |>
      formatCurrency("Precio unitario (COP)", currency = "$ ", mark = ".", dec.mark = ",", digits = 1)
  })

  output$descargar <- downloadHandler(
    filename = function() paste0("productos_filtrados_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      d <- tabla()
      utils::write.csv(d, file, row.names = FALSE, fileEncoding = "UTF-8", na = "")
    }
  )

  # --- Cambios de precio entre dos ejecuciones -------------------------------
  cambios <- reactive({
    ids <- opciones()$ejecuciones$id_ejecucion
    a <- solo_permitidos(input$ejec_a, ids); b <- solo_permitidos(input$ejec_b, ids)
    validate(need(length(a) == 1 && length(b) == 1, "Elija dos ejecuciones."))
    validate(need(a != b, "Elija dos ejecuciones distintas."))
    if (a > b) { t <- a; a <- b; b <- t }            # siempre anterior -> posterior
    seguro(cambios_entre(con, a, b, filtros()$comercios, isTRUE(input$cambios_comparables)))
  }) |> bindCache(input$ejec_a, input$ejec_b, filtros()$comercios, input$cambios_comparables, firma())

  output$vc_sube   <- renderText(sum(cambios()$cambios$direccion == "subió"))
  output$vc_baja   <- renderText(sum(cambios()$cambios$direccion == "bajó"))
  output$vc_nuevos <- renderText(nrow(cambios()$nuevos))
  output$vc_no_obs <- renderText(nrow(cambios()$no_observados))

  dt_es <- list(pageLength = 15, scrollX = TRUE,
                language = list(url = "https://cdn.datatables.net/plug-ins/1.13.6/i18n/es-ES.json"))

  output$t_cambios <- renderDT({
    d <- cambios()$cambios
    validate(need(nrow(d) > 0, "No hubo cambios de precio entre esas ejecuciones."))
    umbral <- validar_numero(input$umbral, 0, 100, 10)
    d$grande <- as.integer(abs(d$cambio_pct) >= umbral)
    d$comparable <- ifelse(d$comparable == 1, "Sí", "No")
    names(d) <- c("Comercio", "Nombre", "Subcategoría", "Comparable", "Precio anterior (COP)",
                  "Precio nuevo (COP)", "Cambio (COP)", "Cambio (%)", "Dirección",
                  "Disponibilidad", "grande")
    datatable(d, rownames = FALSE, options = c(dt_es, list(columnDefs = list(
      list(visible = FALSE, targets = ncol(d) - 1))))) |>
      formatCurrency(c("Precio anterior (COP)", "Precio nuevo (COP)", "Cambio (COP)"),
                     currency = "$ ", mark = ".", dec.mark = ",", digits = 0) |>
      formatRound("Cambio (%)", digits = 1, mark = ".", dec.mark = ",") |>
      formatStyle("Cambio (%)", valueColumns = "grande", fontWeight = styleEqual(1, "bold"),
                  backgroundColor = styleEqual(1, "#fff3cd")) |>
      formatStyle("Dirección", color = styleEqual(c("subió", "bajó"), c("#FF3030", "#00FF7F")))
  })
  output$t_nuevos <- renderDT({
    d <- cambios()$nuevos
    validate(need(nrow(d) > 0, "No hay productos nuevos entre esas ejecuciones."))
    names(d) <- c("Comercio", "Nombre", "Subcategoría", "Precio (COP)", "Disponibilidad")
    datatable(d, rownames = FALSE, options = dt_es) |>
      formatCurrency("Precio (COP)", currency = "$ ", mark = ".", dec.mark = ",", digits = 0)
  })
  output$t_no_obs <- renderDT({
    d <- cambios()$no_observados
    validate(need(nrow(d) > 0, "Todos los productos de la ejecución anterior se volvieron a observar."))
    names(d) <- c("Comercio", "Nombre", "Subcategoría", "Último precio (COP)")
    datatable(d, rownames = FALSE, options = dt_es) |>
      formatCurrency("Último precio (COP)", currency = "$ ", mark = ".", dec.mark = ",", digits = 0)
  })

  # --- Canasta ---------------------------------------------------------------
  id_cantidad <- function(id) paste0("cant_", make.names(id))

  output$canasta_cantidades <- renderUI({
    ids <- solo_permitidos(input$canasta_prod, opciones()$comparables$id_producto)
    if (length(ids) == 0) return(helpText("Elija productos para indicar la cantidad de cada uno."))
    comp <- opciones()$comparables
    lapply(ids, function(id) {
      actual <- isolate(input[[id_cantidad(id)]])
      numericInput(id_cantidad(id), paste("Cantidad:", comp$nombre_std[comp$id_producto == id]),
                   value = if (is.null(actual)) 1 else actual, min = 1, max = 20, step = 1)
    })
  })

  items_canasta <- reactive({
    ids <- solo_permitidos(input$canasta_prod, opciones()$comparables$id_producto)
    validate(need(length(ids) > 0, "Elija al menos un producto para armar la canasta."))
    cant <- vapply(ids, function(id) round(validar_numero(input[[id_cantidad(id)]], 1, 20, 1)),
                   numeric(1))
    data.frame(id_producto = ids, cantidad = as.integer(cant))
  }) |> debounce(300)

  resultado_canasta <- reactive({
    ej <- solo_permitidos(input$ejec_canasta, opciones()$ejecuciones$id_ejecucion)
    validate(need(length(ej) == 1, "Elija una ejecución."))
    seguro(canasta(con, ej, items_canasta(), exigir_disponible = isTRUE(input$canasta_disp)))
  }) |> bindCache(input$ejec_canasta, items_canasta(), input$canasta_disp, firma())

  output$canasta_resumen <- renderUI({
    r <- resultado_canasta()
    comercios_sel <- NOMBRES[filtros()$comercios]
    completos <- r$por_comercio[!is.na(r$por_comercio$total) & r$por_comercio$nombre %in% comercios_sel, ]
    layout_column_wrap(
      width = "180px", fill = FALSE,
      value_box("Costo mínimo (cada producto donde es más barato)",
                if (is.na(r$costo_minimo)) "No disponible" else paste(cop(r$costo_minimo), "COP")),
      value_box("Mejor compra en un solo comercio",
                if (nrow(completos) == 0) "Ningún comercio tiene todo" else
                  paste(cop(min(completos$total)), "COP"),
                if (nrow(completos) > 0) completos$nombre[which.min(completos$total)]),
      value_box("Ahorro de dividir la compra",
                if (is.na(r$ahorro)) "—" else paste(cop(r$ahorro), "COP"))
    )
  })
  output$canasta_comercios <- renderTable({
    d <- resultado_canasta()$por_comercio
    d <- d[d$comercio %in% filtros()$comercios, ]
    validate(need(nrow(d) > 0, "No hay comercios para mostrar."))
    data.frame(Comercio = d$nombre,
               `Total (COP)` = ifelse(is.na(d$total), "Incompleta", cop(d$total)),
               `Productos con precio` = sprintf("%d de %d", d$productos_con_precio, d$productos_canasta),
               Faltan = ifelse(is.na(d$faltantes), "", d$faltantes), check.names = FALSE)
  })
  output$canasta_optimo <- renderTable({
    d <- resultado_canasta()$optimo
    data.frame(Producto = d$producto, Cantidad = d$cantidad,
               `Precio unitario (COP)` = cop(d$precio_min), `Subtotal (COP)` = cop(d$subtotal),
               `Dónde` = ifelse(is.na(d$donde), "Sin precio en ningún comercio", d$donde),
               check.names = FALSE)
  })

  # --- Actualización en segundo plano (Módulo 2) ------------------------------
  tarea <- ExtendedTask$new(function(modo, corrida, dir) {
    future_promise({
      options(comparador.dir = dir)
      source(file.path(dir, "scraper.R"), encoding = "UTF-8")
      res <- ejecutar_recoleccion(corrida = corrida, offline = (modo == "sin_conexion"))
      list(id = res$id_ejecucion[1], modo = modo,
           resumen = as.data.frame(res[, c("comercio", "estado", "detalle")]))
    }, seed = TRUE)
  }) |> bind_task_button("actualizar")

  observeEvent(input$actualizar, {
    modo <- if (identical(input$modo_act, "sin_conexion")) "sin_conexion" else "en_linea"
    corrida <- NULL
    if (modo == "sin_conexion") {
      corrida <- solo_permitidos(input$corrida_raw, corridas_crudas())
      if (length(corrida) != 1) {
        showNotification("No hay copias crudas para reprocesar.", type = "error")
        return()
      }
    }
    tarea$invoke(modo, corrida, DIR_APP)
  })

  resultado_act <- reactive({
    st <- tarea$status()
    if (st == "initial") return(NULL)
    if (st == "running") return(list(estado = "running"))
    if (st == "error") {
      return(list(estado = "error",
                  mensaje = tryCatch({ tarea$result(); "" }, error = conditionMessage)))
    }
    list(estado = "ok", r = tarea$result())
  })

  output$act_mensaje <- renderUI({
    r <- resultado_act()
    if (is.null(r)) return(helpText("Aún no se ha ejecutado una actualización en esta sesión."))
    if (r$estado == "running") {
      return(div(class = "alert alert-info", "Actualizando… los resultados aparecerán aquí."))
    }
    if (r$estado == "error") {
      return(div(class = "alert alert-danger",
                 "La actualización no pudo completarse: ", r$mensaje))
    }
    res <- r$r$resumen
    if (all(res$estado == "fallida")) {
      return(div(class = "alert alert-danger",
                 if (r$r$modo == "en_linea")
                   paste("No fue posible consultar ninguno de los sitios desde este servidor.",
                         "Es común que los comercios bloqueen las plataformas de alojamiento",
                         "como shinyapps.io. Use el modo sin conexión para reprocesar las",
                         "copias crudas guardadas en raw/.")
                 else "No fue posible reprocesar las copias crudas."))
    }
    fallos <- res$comercio[res$estado != "completa"]
    div(class = if (length(fallos) == 0) "alert alert-success" else "alert alert-warning",
        sprintf("Ejecución %s registrada (%s).", r$r$id,
                if (r$r$modo == "en_linea") "en línea" else "sin conexión"),
        if (length(fallos) > 0)
          paste("Revise:", paste(NOMBRES[fallos], collapse = ", "),
                "(detalle en la tabla). Los demás comercios se cargaron normalmente."))
  })

  output$act_resumen <- renderTable({
    r <- resultado_act()
    req(r, r$estado == "ok")
    d <- seguro(resumen_actualizacion(con, r$r$id))
    data.frame(Comercio = d$comercio, Estado = d$estado, Recolectados = d$recolectados,
               Nuevos = d$nuevos, `Cambios de precio` = d$cambios_precio,
               `No observados` = d$no_observados, Rechazados = d$rechazados,
               Detalle = d$detalle, check.names = FALSE)
  })

  # --- Calidad de los datos -----------------------------------------------------
  output$t_ejecuciones <- renderDT({
    firma()
    d <- seguro(tabla_ejecuciones(con))
    datatable(d, rownames = FALSE, options = dt_es,
              colnames = c("Ejecución", "Comercio", "Inicio", "Modo", "Registros",
                           "Total del sitio", "En la categoría", "Estado", "Detalle",
                           "Último reproceso"))
  })
  output$t_correcciones <- renderDT({
    firma()
    d <- seguro(tabla_correcciones(con))
    validate(need(nrow(d) > 0, "No hay correcciones registradas."))
    datatable(d, rownames = FALSE, options = c(dt_es, list(pageLength = 8)),
              colnames = c("Fecha", "Tabla", "Registro", "Campo", "Valor anterior",
                           "Valor nuevo", "Motivo"))
  })
  output$t_rechazos <- renderTable({
    firma()
    d <- seguro(resumen_rechazos(con))
    validate(need(nrow(d) > 0, "Ninguna observación ha sido rechazada en la validación."))
    data.frame(`Ejecución` = d$id_ejecucion, Comercio = d$comercio, Motivo = d$motivo,
               Observaciones = d$observaciones, check.names = FALSE)
  })
}

shinyApp(ui, server)
