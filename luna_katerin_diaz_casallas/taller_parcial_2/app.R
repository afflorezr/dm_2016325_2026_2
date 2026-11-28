##### 1. LIBRERÍAS Y DATOS INICIALES

# Arranque liviano: db + UI. scraper/chromote/pointblank solo al actualizar o validar.
# En shinyapps un arranque pesado supera incluso 300 s de Startup Timeout.
source("db.R")

# library() explícitos para que rsconnect detecte e instale cada paquete en shinyapps
library(shiny)
library(bslib)
library(highcharter)
library(DT)
library(future)
library(promises)
library(readr)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)

en_shinyapps <- nzchar(Sys.getenv("SHINY_PORT"))
if (en_shinyapps) {
  plan(sequential)
} else {
  plan(multisession, workers = 1)
}
options(highcharter.lang = list(thousandsSep = ".", decimalPoint = ","))

# Aviso de Chrome sin cargar scraper/chromote al arranque (en shinyapps no hay navegador)
MENSAJE_SIN_NAVEGADOR <- paste(
  "Desde esta página no se pueden consultar las droguerías en este momento.",
  "Elija la opción sin conexión, o abra la aplicación en su computador para actualizar los precios."
)
navegador_disponible <- function() {
  if (en_shinyapps) return(FALSE)
  if (!requireNamespace("chromote", quietly = TRUE)) return(FALSE)
  ruta <- tryCatch(chromote::find_chrome(), error = function(e) NULL, warning = function(w) NULL)
  !is.null(ruta) && length(ruta) == 1 && !is.na(ruta) && nzchar(ruta) && file.exists(ruta)
}

if (!file.exists(DB_PATH)) stop("No está la base comparador_precios.sqlite.")
preparar_base()
opciones <- opciones_filtros()

# Cada comercio conserva el mismo color en toda la aplicación
colores_comercio <- c("CAFAM" = "#2a78d6", "LA ALEMANA" = "#eb6834", "LA REBAJA" = "#1baf7a")
nombres_comercio <- c("CAFAM" = "Cafam", "LA ALEMANA" = "La Alemana", "LA REBAJA" = "La Rebaja")
meses <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")

##### 2. FUNCIONES DE FORMATO

# Selección vacía como vector de texto vacío
como_texto <- function(x) if (is.null(x)) character() else x

# Pesos colombianos: $12.900
cop <- function(x) {
  if_else(
    is.na(x),
    "-",
    paste0(if_else(x < 0, "-$", "$"), formatC(abs(round(x)), format = "d", big.mark = ".", decimal.mark = ","))
  )
}
entero_es <- function(x) formatC(as.integer(x), format = "d", big.mark = ".", decimal.mark = ",")
num_es <- function(x, digitos = 1) {
  if_else(is.na(x), "-", formatC(x, format = "f", digits = digitos, decimal.mark = ",", big.mark = "."))
}
etiqueta_unidad <- function(x) if_else(!is.na(x) & x == "und", "unidad", x)
nombre_comercio <- function(x) if_else(x %in% names(nombres_comercio), unname(nombres_comercio[x]), x)

# Fecha de la ejecución (13 oct 2026); el texto ISO ya está en hora de Colombia
etiqueta_fecha <- function(iso) {
  fecha <- as.Date(substr(iso, 1, 10))
  if_else(
    is.na(fecha),
    iso,
    paste(as.integer(format(fecha, "%d")), meses[as.integer(format(fecha, "%m"))], format(fecha, "%Y"))
  )
}

# Fecha y hora de consulta: 14/11/2026 12:53
fecha_hora <- function(iso) {
  paste0(substr(iso, 9, 10), "/", substr(iso, 6, 7), "/", substr(iso, 1, 4), " ", substr(iso, 12, 16))
}

# Opciones del selector de ejecución: se muestra la fecha y el valor es el identificador
etiquetas_ejecucion <- function(tabla) {
  set_names(tabla$id_ejecucion, etiqueta_fecha(tabla$fecha_inicio))
}

precio_tope <- max(1000, ceiling(opciones$precio_max / 1000) * 1000)
eleccion_ejecucion <- etiquetas_ejecucion(opciones$ejecuciones)
id_reciente <- unname(eleccion_ejecucion[1])
ids_recientes <- unname(eleccion_ejecucion[seq_len(min(2, length(eleccion_ejecucion)))])
nombres_producto <- set_names(opciones$productos$nombre_corto, opciones$productos$id_producto)
eleccion_producto <- set_names(opciones$productos$id_producto, opciones$productos$nombre_corto)
familias <- unique(opciones$productos$familia)
nombres_familia <- c(
  omega3_procaps = "Omega 3 Procaps",
  complejo_b_genfar = "Complejo B Genfar",
  cebion_gotas_fresa = "Cebion gotas",
  vitacerebrina_caramelo = "Vitacerebrina",
  aquasol_e_800 = "Aquasol E",
  acido_folico_ecar_1mg = "Ácido fólico Ecar",
  kola_tarrito_rojo_fresa = "Kola Tarrito Rojo fresa",
  centrum_silver_women = "Centrum Silver Women"
)

tema <- bs_theme(
  version = 5,
  bg = "#fcfcfb",
  fg = "#1c1b19",
  primary = "#2a78d6",
  success = "#1baf7a",
  warning = "#eb6834",
  base_font = font_collection("Segoe UI", "Helvetica Neue", "Arial", "sans-serif")
)

# Textos de las tablas DT en español
idioma_dt <- list(
  search = "Buscar:",
  lengthMenu = "Mostrar _MENU_",
  info = "_START_ a _END_ de _TOTAL_",
  infoEmpty = "Sin registros",
  zeroRecords = "Ningún producto coincide",
  paginate = list(previous = "Anterior", `next` = "Siguiente")
)

##### 3. GRÁFICOS

# Gráfico highcharter con el formato común de la aplicación; el título va en la tarjeta
grafico_base <- function(titulo_y = "Precio (COP)") {
  highchart() %>%
    hc_chart(backgroundColor = "#fcfcfb", style = list(fontFamily = "Segoe UI, Helvetica, Arial, sans-serif")) %>%
    hc_xAxis(labels = list(style = list(color = "#52514e"))) %>%
    hc_yAxis(
      title = list(text = titulo_y, style = list(color = "#52514e")),
      labels = list(format = "{value:,.0f}", style = list(color = "#52514e"))
    ) %>%
    hc_legend(align = "left", verticalAlign = "top") %>%
    hc_credits(enabled = FALSE) %>%
    hc_exporting(enabled = FALSE)
}

# Highcharts necesita arreglos: un vector con nombres o de largo 1 no se convierte en arreglo
como_arreglo <- function(x) as.list(unname(x))

# Agrega la serie de un comercio con su color
agregar_serie_comercio <- function(hc, comercio, valores, tipo = "line") {
  hc %>%
    hc_add_series(
      type = tipo,
      name = unname(nombres_comercio[comercio]),
      data = como_arreglo(valores),
      color = unname(colores_comercio[comercio])
    )
}

# Valor de cada categoría para un comercio; NA si el comercio no la tiene
valores_por_categoria <- function(datos, categorias, columna_categoria, columna_valor) {
  map_dbl(categorias, function(categoria) {
    valor <- datos[[columna_valor]][datos[[columna_categoria]] == categoria]
    if (length(valor) == 0) NA_real_ else valor[[1]]
  })
}

##### 4. INTERFAZ

# Unidad del indicador, debajo del valor
nota_kpi <- function(id) tags$p(style = "font-size:0.85rem; margin:0;", textOutput(id, inline = TRUE))

ui <- page_navbar(
  title = "Comparador de precios de vitaminas",
  theme = tema,
  lang = "es",
  fillable = FALSE,
  sidebar = sidebar(
    width = 300,
    selectInput("ejecucion", "Ejecución", choices = eleccion_ejecucion, selected = id_reciente),
    # Etiqueta amigable → código de la base (CAFAM / LA ALEMANA / LA REBAJA)
    selectInput(
      "comercio", "Comercio",
      choices = setNames(names(nombres_comercio), unname(nombres_comercio)),
      multiple = TRUE
    ),
    selectInput("subcategoria", "Subcategoría", choices = opciones$subcategorias, multiple = TRUE),
    selectInput("marca", "Marca", choices = opciones$marcas, multiple = TRUE),
    sliderInput("precio", "Precio (COP)", min = 0, max = precio_tope, value = c(0, precio_tope), step = 1000, pre = "$", sep = "."),
    checkboxInput("solo_promo", "Solo promociones", FALSE),
    checkboxInput("solo_comparables", "Solo productos comparables", FALSE),
    textInput("buscar", "Buscar", placeholder = "Ej.: omega"),
    helpText("Un filtro vacío incluye todos los valores.")
  ),
  nav_panel(
    "Resumen",
    uiOutput("periodo"),
    layout_columns(
      col_widths = c(4, 4, 4, 4, 4, 4),
      value_box("Productos", textOutput("kpi_productos", inline = TRUE), nota_kpi("nota_productos"), theme = "primary"),
      value_box("Observaciones", textOutput("kpi_observaciones", inline = TRUE), nota_kpi("nota_observaciones"), theme = "primary"),
      value_box("En promoción", textOutput("kpi_promo", inline = TRUE), nota_kpi("nota_promo"), theme = "success"),
      value_box("Precio mediano", textOutput("kpi_mediana", inline = TRUE), nota_kpi("nota_mediana"), theme = "primary"),
      value_box("Ahorro máximo", textOutput("kpi_ahorro", inline = TRUE), nota_kpi("nota_ahorro"), theme = "warning"),
      value_box("Cambios de precio", textOutput("kpi_cambios", inline = TRUE), nota_kpi("nota_cambios"), theme = "warning")
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Distribución de precios por comercio"),
        highchartOutput("grafico_distribucion", height = "380px")
      ),
      card(
        card_header("Diferencia de precio entre comercios"),
        highchartOutput("grafico_ahorro", height = "380px")
      )
    )
  ),
  nav_panel(
    "Comparar",
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Evolución del precio"),
        selectInput("producto", "Presentación", choices = eleccion_producto, selected = "P01", width = "100%"),
        highchartOutput("grafico_evolucion", height = "380px")
      ),
      card(
        card_header("Precio por unidad"),
        selectInput(
          "familia", "Producto",
          choices = set_names(familias, nombres_familia[familias]),
          width = "100%"
        ),
        highchartOutput("grafico_unitario", height = "380px")
      )
    )
  ),
  nav_panel(
    "Cambios",
    layout_columns(
      col_widths = c(4, 4, 4),
      selectInput("ejec_antes", "Desde", choices = eleccion_ejecucion, selected = ids_recientes[length(ids_recientes)]),
      selectInput("ejec_despues", "Hasta", choices = eleccion_ejecucion, selected = ids_recientes[1]),
      sliderInput("umbral", "Resaltar desde (%)", min = 0, max = 50, value = 10, step = 1, width = "100%")
    ),
    card(
      card_header(textOutput("resumen_cambios", inline = TRUE)),
      radioButtons(
        "tipo_cambio", NULL, inline = TRUE,
        choices = c("Cambiaron de precio" = "cambio", "Nuevos" = "nuevo", "Ya no aparecen" = "no_observado")
      ),
      DTOutput("tabla_cambios", fill = FALSE),
      card_footer("Se compara el mismo anuncio en el mismo comercio. Que un producto ya no aparezca no significa que esté agotado.")
    )
  ),
  nav_panel(
    "Canasta",
    layout_columns(
      col_widths = c(4, 8),
      card(
        card_header("Productos"),
        selectInput("ejec_canasta", "Ejecución", choices = eleccion_ejecucion, selected = id_reciente),
        selectInput("ids_canasta", "Presentaciones", choices = eleccion_producto, multiple = TRUE, selected = c("P01", "P03")),
        uiOutput("cantidades_ui")
      ),
      card(
        card_header("Costo por comercio"),
        tableOutput("tabla_canasta"),
        uiOutput("minimo_canasta"),
        card_footer("No incluye envío, mínimos de compra ni condiciones de las promociones.")
      )
    )
  ),
  nav_panel(
    "Catálogo",
    card(
      card_header("Productos"),
      downloadButton("descargar", "Descargar CSV", class = "btn-sm", style = "width: fit-content;"),
      DTOutput("tabla_catalogo", fill = FALSE)
    )
  ),
  nav_panel(
    "Actualizar",
    card(
      card_header("Actualizar precios"),
      radioButtons(
        "modo_actualizacion", NULL,
        choices = c("Sin conexión" = "offline", "En línea" = "online"),
        selected = "offline"
      ),
      if (!navegador_disponible()) tags$div(class = "alert alert-warning", MENSAJE_SIN_NAVEGADOR),
      input_task_button("actualizar", "Actualizar", label_busy = "Actualizando...", style = "width: fit-content;"),
      helpText("La consulta en línea tarda unos 35 minutos.")
    ),
    card(card_header("Resultado"), tableOutput("tabla_actualizacion"), uiOutput("error_actualizacion"))
  )
)

##### 5. SERVIDOR

server <- function(input, output, session) {
  cache_token <- reactiveVal(0L)

  # 1. Filtros del panel lateral y resultados en caché
  filtros_actuales <- reactive({
    texto <- validar_texto_busqueda(input$buscar)
    if (!isTRUE(texto$ok)) return(list(ok = FALSE, mensaje = texto$mensaje, filtros = NULL))
    list(
      ok = TRUE,
      mensaje = NA_character_,
      filtros = list(
        id_ejecucion = input$ejecucion,
        comercios = como_texto(input$comercio),
        subcategorias = como_texto(input$subcategoria),
        marcas = como_texto(input$marca),
        pmin = input$precio[1],
        pmax = input$precio[2],
        solo_promo = isTRUE(input$solo_promo),
        solo_comparables = isTRUE(input$solo_comparables),
        busqueda = texto$valor
      )
    )
  })

  indicadores_actuales <- reactive({
    cache_token()
    f <- filtros_actuales()
    validate(need(f$ok, f$mensaje))
    validate(need(!is.null(f$filtros$id_ejecucion) && nzchar(f$filtros$id_ejecucion), "Elija una ejecución."))
    indicadores(f$filtros)
  }) %>% bindCache(
    input$ejecucion, input$comercio, input$subcategoria, input$marca, input$precio,
    input$solo_promo, input$solo_comparables, input$buscar, cache_token(),
    cache = "session"
  )

  catalogo <- reactive({
    cache_token()
    f <- filtros_actuales()
    validate(need(f$ok, f$mensaje))
    productos_filtrados(f$filtros)
  }) %>% bindCache(
    input$ejecucion, input$comercio, input$subcategoria, input$marca, input$precio,
    input$solo_promo, input$solo_comparables, input$buscar, cache_token(),
    cache = "session"
  )

  # 2. Indicadores
  output$periodo <- renderUI({
    meta <- indicadores_actuales()$meta
    validate(need(nrow(meta) > 0, "No hay datos de esa ejecución."))
    texto <- paste0("Datos del ", etiqueta_fecha(meta$fecha_inicio[[1]]), ". Precios en COP.")
    if (!is.na(meta$parciales[[1]])) {
      texto <- paste0(texto, " Recolección parcial en: ", paste(nombre_comercio(str_split(meta$parciales[[1]], ",")[[1]]), collapse = ", "), ".")
    }
    tags$p(style = "color:#52514e; margin-bottom: 0.75rem;", texto)
  })

  output$kpi_productos <- renderText(entero_es(indicadores_actuales()$productos))
  output$kpi_observaciones <- renderText(entero_es(indicadores_actuales()$observaciones))
  output$kpi_promo <- renderText({
    valor <- indicadores_actuales()$pct_promocion
    if (is.null(valor) || is.na(valor)) "Sin datos" else paste0(num_es(valor, 1), " %")
  })
  output$kpi_mediana <- renderText({
    valor <- indicadores_actuales()$mediana
    if (is.null(valor) || is.na(valor)) "Sin datos" else cop(valor)
  })
  output$kpi_ahorro <- renderText({
    ahorro <- indicadores_actuales()$ahorro_maximo
    if (is.null(ahorro) || nrow(ahorro) == 0) "Sin datos" else cop(ahorro$ahorro[[1]])
  })
  output$kpi_cambios <- renderText(entero_es(indicadores_actuales()$cambios))

  output$nota_productos <- renderText("anuncios de la categoría")
  output$nota_observaciones <- renderText("lecturas de precio")
  output$nota_promo <- renderText("de los productos con precio")
  output$nota_mediana <- renderText("COP por empaque")
  output$nota_ahorro <- renderText({
    ahorro <- indicadores_actuales()$ahorro_maximo
    if (is.null(ahorro) || nrow(ahorro) == 0) return("COP")
    paste0("COP en ", ahorro$nombre_corto[[1]], " (", num_es(ahorro$ahorro_pct[[1]], 1), " %)")
  })
  output$nota_cambios <- renderText("anuncios, frente a la ejecución anterior")

  # 3. Gráficos
  output$grafico_distribucion <- renderHighchart({
    cache_token()
    f <- filtros_actuales()
    validate(need(f$ok, f$mensaje))
    resumen <- distribucion_precios(f$filtros)
    validate(need(nrow(resumen) > 0, "Ningún producto con precio cumple los filtros."))
    hc <- grafico_base() %>%
      hc_xAxis(categories = como_arreglo(nombres_comercio[resumen$comercio])) %>%
      hc_legend(enabled = FALSE)
    for (i in seq_len(nrow(resumen))) {
      punto <- rep(list(NULL), nrow(resumen))
      punto[[i]] <- list(resumen$minimo[i], resumen$q1[i], resumen$mediana[i], resumen$q3[i], resumen$maximo[i])
      hc <- agregar_serie_comercio(hc, resumen$comercio[i], punto, tipo = "boxplot")
    }
    hc %>% hc_tooltip(shared = FALSE, valueDecimals = 0, valuePrefix = "$")
  }) %>% bindCache(
    input$ejecucion, input$comercio, input$subcategoria, input$marca, input$precio,
    input$solo_promo, input$solo_comparables, input$buscar, cache_token(),
    cache = "session"
  )

  output$grafico_ahorro <- renderHighchart({
    cache_token()
    f <- filtros_actuales()
    validate(need(f$ok, f$mensaje))
    datos <- ahorro_por_presentacion(f$filtros$id_ejecucion, f$filtros$comercios)
    validate(need(nrow(datos) > 0, "Se necesitan al menos dos comercios para comparar."))
    grafico_base("COP") %>%
      hc_chart(type = "bar") %>%
      hc_xAxis(categories = como_arreglo(datos$nombre_corto)) %>%
      hc_legend(enabled = FALSE) %>%
      hc_add_series(name = "Ahorro", data = como_arreglo(datos$ahorro), color = "#2a78d6") %>%
      hc_tooltip(valueDecimals = 0, valuePrefix = "$")
  }) %>% bindCache(input$ejecucion, input$comercio, cache_token(), cache = "session")

  output$grafico_evolucion <- renderHighchart({
    validate(need(!is.null(input$producto) && nzchar(input$producto), "Elija una presentación."))
    datos <- evolucion_precio(input$producto) %>%
      mutate(etiqueta = etiqueta_fecha(fecha_extraccion))
    validate(need(nrow(datos) > 0, "Esta presentación no tiene precios guardados."))
    fechas <- unique(datos$etiqueta)
    hc <- grafico_base() %>%
      hc_xAxis(categories = como_arreglo(fechas)) %>%
      hc_tooltip(shared = TRUE, valueDecimals = 0, valuePrefix = "$")
    for (com in intersect(names(colores_comercio), unique(datos$comercio))) {
      valores <- valores_por_categoria(filter(datos, comercio == com), fechas, "etiqueta", "precio")
      hc <- agregar_serie_comercio(hc, com, valores, tipo = "line")
    }
    hc
  }) %>% bindCache(input$producto, cache_token(), cache = "session")

  output$grafico_unitario <- renderHighchart({
    validate(need(!is.null(input$familia) && nzchar(input$familia), "Elija un producto."))
    validate(need(!is.null(input$ejecucion) && nzchar(input$ejecucion), "Elija una ejecución."))
    datos <- precio_unitario_familia(input$familia, input$ejecucion)
    validate(need(nrow(datos) > 0, "Este producto no está en la ejecución elegida."))
    validate(need(n_distinct(datos$unidad) == 1, "Las presentaciones tienen unidades distintas."))
    categorias <- unique(datos$nombre_corto)
    hc <- grafico_base(paste0("COP por ", etiqueta_unidad(datos$unidad[[1]]))) %>%
      hc_chart(type = "column") %>%
      hc_xAxis(categories = como_arreglo(categorias)) %>%
      hc_tooltip(shared = TRUE, valueDecimals = 1, valuePrefix = "$")
    for (com in intersect(names(colores_comercio), unique(datos$comercio))) {
      valores <- valores_por_categoria(filter(datos, comercio == com), categorias, "nombre_corto", "precio_unitario")
      hc <- agregar_serie_comercio(hc, com, valores, tipo = "column")
    }
    hc
  }) %>% bindCache(input$familia, input$ejecucion, cache_token(), cache = "session")

  # 4. Cambios de precio entre dos ejecuciones
  cambios <- reactive({
    cache_token()
    validate(need(input$ejec_antes != input$ejec_despues, "Elija dos ejecuciones distintas."))
    comparar_ejecuciones(
      input$ejec_antes, input$ejec_despues, input$umbral,
      comercios = como_texto(input$comercio)
    )
  })

  output$resumen_cambios <- renderText({
    datos <- cambios()
    paste0(
      sum(datos$tipo == "subio"), " subieron, ",
      sum(datos$tipo == "bajo"), " bajaron, ",
      sum(datos$tipo == "nuevo"), " nuevos y ",
      sum(datos$tipo == "no_observado"), " ya no aparecen"
    )
  })

  output$tabla_cambios <- renderDT({
    datos <- cambios()
    if (input$tipo_cambio == "cambio") {
      datos <- datos %>%
        filter(tipo %in% c("subio", "bajo")) %>%
        arrange(desc(abs(delta_pct)))
      tabla <- tibble(
        Comercio = nombre_comercio(datos$comercio),
        Producto = datos$n_producto,
        Antes = datos$precio_antes,
        Después = datos$precio_despues,
        Diferencia = datos$delta_cop,
        `Variación (%)` = datos$delta_pct,
        grande = datos$variacion_grande %in% TRUE
      )
      monedas <- c("Antes", "Después", "Diferencia")
      porcentajes <- "Variación (%)"
    } else {
      datos <- filter(datos, tipo == input$tipo_cambio)
      tabla <- tibble(
        Comercio = nombre_comercio(datos$comercio),
        Producto = datos$n_producto,
        Precio = if (input$tipo_cambio == "nuevo") datos$precio_despues else datos$precio_antes,
        grande = FALSE
      )
      monedas <- "Precio"
      porcentajes <- character()
    }
    validate(need(nrow(tabla) > 0, "No hay productos en esta categoría."))

    tabla_dt <- datatable(
      tabla,
      rownames = FALSE,
      options = list(
        pageLength = 10,
        language = idioma_dt,
        columnDefs = list(list(visible = FALSE, targets = ncol(tabla) - 1))
      )
    ) %>%
      formatCurrency(monedas, currency = "$", digits = 0, mark = ".", dec.mark = ",")
    if (length(porcentajes) > 0) {
      tabla_dt <- formatRound(tabla_dt, porcentajes, digits = 1, mark = ".", dec.mark = ",")
    }
    tabla_dt %>%
      formatStyle(
        setdiff(names(tabla), "grande"),
        valueColumns = "grande",
        backgroundColor = styleEqual(TRUE, "#fdebdc")
      )
  })

  # 5. Canasta
  output$cantidades_ui <- renderUI({
    ids <- como_texto(input$ids_canasta)
    if (length(ids) == 0) return(NULL)
    map(ids, function(id) {
      numericInput(paste0("cant_", id), unname(nombres_producto[id]), value = 1, min = 1, max = 20, step = 1)
    })
  })

  canasta <- reactive({
    ids <- como_texto(input$ids_canasta)
    validate(need(length(ids) > 0, "Elija al menos una presentación."))
    cantidades <- map_dbl(ids, function(id) {
      valor <- input[[paste0("cant_", id)]]
      if (is.null(valor) || is.na(valor)) 1 else valor
    })
    validate(need(all(cantidades >= 1), "Cada cantidad debe ser al menos 1."))
    pedido <- tibble(id_producto = ids, cantidad = cantidades)

    # Los comercios sin ningún producto de la canasta también aparecen, como incompletos
    precios <- precios_canasta(input$ejec_canasta, ids)
    faltan <- setdiff(names(nombres_comercio), precios$comercio)
    precios <- bind_rows(precios, tibble(comercio = faltan, id_producto = ids[[1]], precio = NA_real_))
    costo_canasta(precios, pedido)
  })

  output$tabla_canasta <- renderTable({
    tabla <- canasta()$por_comercio
    faltantes <- map_chr(tabla$faltantes, function(texto) {
      if (is.na(texto) || !nzchar(texto)) return("")
      paste("Falta", paste(unname(nombres_producto[str_split(texto, ", ")[[1]]]), collapse = ", "))
    })
    tibble(
      Comercio = nombre_comercio(tabla$comercio),
      Costo = if_else(tabla$completo, cop(tabla$costo), faltantes),
      `Diferencia con el mínimo` = if_else(tabla$completo, cop(tabla$ahorro_vs_minimo), "-")
    )
  }, striped = TRUE, hover = TRUE, width = "100%")

  output$minimo_canasta <- renderUI({
    resultado <- canasta()
    if (is.na(resultado$costo_minimo)) {
      tags$p("Ningún comercio tiene alguno de los productos elegidos.")
    } else {
      tags$p(
        "Comprando cada producto donde es más barato: ",
        tags$strong(cop(resultado$costo_minimo))
      )
    }
  })

  # 6. Catálogo
  output$tabla_catalogo <- renderDT({
    datos <- catalogo()
    validate(need(nrow(datos) > 0, "Ningún producto cumple los filtros."))
    visible <- tibble(
      Comercio = nombre_comercio(datos$comercio),
      Nombre = datos$nombre,
      Marca = datos$marca,
      Presentación = datos$presentacion,
      Precio = datos$precio,
      `Precio unitario` = datos$precio_unitario,
      Unidad = etiqueta_unidad(datos$unidad),
      Promoción = if_else(datos$promocion == 1, "Sí", "No"),
      Disponibilidad = case_when(
        datos$disponibilidad == "disponible" ~ "Disponible",
        datos$disponibilidad == "agotado" ~ "Agotado",
        TRUE ~ "-"
      ),
      Consulta = fecha_hora(datos$fecha_extraccion),
      Enlace = if_else(
        str_detect(datos$enlace, "^https?://"),
        paste0("<a href=\"", htmltools::htmlEscape(datos$enlace), "\" target=\"_blank\" rel=\"noopener\">Ver</a>"),
        "-"
      )
    )
    datatable(
      visible,
      escape = FALSE,
      rownames = FALSE,
      options = list(pageLength = 15, scrollX = TRUE, language = idioma_dt)
    ) %>%
      formatCurrency("Precio", currency = "$", digits = 0, mark = ".", dec.mark = ",") %>%
      formatCurrency("Precio unitario", currency = "$", digits = 0, mark = ".", dec.mark = ",")
  })

  output$descargar <- downloadHandler(
    filename = function() paste0("vitaminas_", input$ejecucion, ".csv"),
    content = function(archivo) write_excel_csv(catalogo(), archivo)
  )

  # 7. Actualización en segundo plano
  tarea <- ExtendedTask$new(function(modo_offline) {
    directorio <- getwd()
    future_promise(
      expr = {
        tryCatch({
          source(file.path(directorio, "scraper.R"), chdir = TRUE)
          ejecutar_recoleccion_completa(
            db_path = file.path(directorio, "comparador_precios.sqlite"),
            dir_raw = file.path(directorio, "raw"),
            modo_offline = modo_offline
          )
        }, error = function(e) {
          tibble(
            comercio = "-",
            estado = "fallida",
            productos_recolectados = 0L,
            productos_nuevos = 0L,
            cambios_precio = 0L,
            no_observados = 0L,
            rechazados = 0L,
            motivo = substr(conditionMessage(e), 1, 500)
          )
        })
      },
      globals = list(directorio = directorio, modo_offline = modo_offline),
      packages = "tibble",
      seed = TRUE
    )
  }) %>% bind_task_button("actualizar")

  observeEvent(input$actualizar, tarea$invoke(identical(input$modo_actualizacion, "offline")))

  observeEvent(tarea$status(), {
    if (identical(tarea$status(), "success")) cache_token(isolate(cache_token()) + 1L)
  }, ignoreInit = TRUE)

  # Al terminar una actualización se recargan las opciones de los filtros
  observeEvent(cache_token(), {
    if (cache_token() == 0L) return()
    nuevas <- opciones_filtros()
    elecciones <- etiquetas_ejecucion(nuevas$ejecuciones)
    actual <- isolate(input$ejecucion)
    if (!actual %in% elecciones) actual <- unname(elecciones[1])
    updateSelectInput(session, "ejecucion", choices = elecciones, selected = actual)
    updateSelectInput(session, "ejec_antes", choices = elecciones)
    updateSelectInput(session, "ejec_despues", choices = elecciones, selected = unname(elecciones[1]))
    updateSelectInput(session, "ejec_canasta", choices = elecciones, selected = unname(elecciones[1]))
    updateSelectInput(session, "subcategoria", choices = nuevas$subcategorias)
    updateSelectInput(session, "marca", choices = nuevas$marcas)
  }, ignoreInit = TRUE)

  output$tabla_actualizacion <- renderTable({
    validate(need(tarea$status() != "initial", "Todavía no se ha actualizado en esta sesión."))
    resultado <- tarea$result()
    validate(need(!is.null(resultado) && nrow(resultado) > 0, "La actualización no devolvió resultados."))
    tibble(
      Comercio = nombre_comercio(resultado$comercio),
      Estado = resultado$estado,
      Recolectados = resultado$productos_recolectados,
      Nuevos = resultado$productos_nuevos,
      `Cambios de precio` = resultado$cambios_precio,
      `No observados` = resultado$no_observados,
      Rechazados = resultado$rechazados,
      Motivo = if_else(is.na(resultado$motivo) | resultado$motivo == "", "-", resultado$motivo)
    )
  }, striped = TRUE, width = "100%")

  output$error_actualizacion <- renderUI({
    if (identical(tarea$status(), "error")) {
      tags$p(style = "color:#9a3412;", "La actualización no terminó. Intente de nuevo o use el modo sin conexión.")
    }
  })
}

shinyApp(ui, server)
