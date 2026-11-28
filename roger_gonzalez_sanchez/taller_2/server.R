#Paquetes

#install.packages(c("shiny", "bslib", "DT", "highcharter", "pointblank", "future",
                   #"promises", "testthat", "renv", "rsconnect"))

# server.R
# Lógica de la app. No contiene SQL: todo pasa por las funciones de db.R.

# Si la base falla, mostrar un mensaje entendible en vez del error técnico
consulta_segura <- function(expr) {
  res <- tryCatch(expr, error = function(e) {
    message("Error en consulta: ", conditionMessage(e))
    NULL
  })
  validate(need(!is.null(res), paste(
    "No fue posible consultar la base de datos. Intente de nuevo;",
    "si el problema sigue, revise que comparador_precios.sqlite esté en la carpeta de la app.")))
  res
}

modo_texto <- function(m) ifelse(is.na(m), "sin dato", unname(ETIQUETA_MODO[m]))

tabla_dt <- function(df, colores = NULL, monedas = NULL, filas = 10, escapar = TRUE, ...) {
  dt <- datatable(df, rownames = FALSE, escape = escapar, selection = "none",
                  options = list(language = DT_ESPANOL, pageLength = filas, scrollX = TRUE, ...))
  if (length(monedas) > 0) {
    dt <- formatCurrency(dt, monedas, currency = "$", mark = ".", dec.mark = ",", digits = 0)
  }
  if (!is.null(colores) && "Comercio" %in% names(df)) {
    dt <- formatStyle(dt, "Comercio", fontWeight = "bold",
                      backgroundColor = styleEqual(names(colores), unname(tono_claro(colores))))
  }
  dt
}

function(input, output, session) {

#Datos que cambian con cada actualización

  actualizado <- reactiveVal(0)
#revisa cada 15 s si la base cambió (por ejemplo, una actualización de otra sesión)
  firma <- reactivePoll(15000, session,
                        checkFunc = function() db_firma(con),
                        valueFunc = function() db_firma(con))
  version_datos <- reactive(paste(firma(), actualizado()))

  opciones <- reactive({
    version_datos()
    list(
      comercios = db_comercios(con),
      subcategorias = db_subcategorias(con),
      marcas = db_marcas(con),
      ejecuciones = db_ejecuciones_con_datos(con),
      comparables = db_lista_comparables(con),
      precios = db_rango_precios(con),
      fechas = db_rango_fechas(con),
      ultima = db_ultima_ejecucion(con),
      ultima_con_datos = db_ultima_ejecucion_con_datos(con)
    )
  })

  colores <- reactive(asignar_colores(opciones()$comercios))

#Llenar los selectores con lo que hay en la base
  observeEvent(opciones(), {
    op <- opciones()
    ej <- op$ejecuciones
    lista_ej <- setNames(ej$id_ejecucion, etiqueta_ejecucion(ej$id_ejecucion, ej$fecha_inicio, ej$estado))
    lista_comp <- setNames(op$comparables$id_comparable, op$comparables$nombre)

    updateSelectizeInput(session, "f_comercio", choices = op$comercios,
                         selected = isolate(input$f_comercio))
    updateSelectizeInput(session, "f_subcategoria", choices = op$subcategorias,
                         selected = isolate(input$f_subcategoria))
    updateSelectizeInput(session, "f_marca", choices = op$marcas, server = TRUE,
                         selected = isolate(input$f_marca))
    updateSelectInput(session, "f_ejecucion", choices = lista_ej, selected = lista_ej[1])
    updateSelectInput(session, "c_reciente", choices = lista_ej, selected = lista_ej[1])
    updateSelectInput(session, "c_anterior", choices = lista_ej,
                      selected = if (length(lista_ej) > 1) lista_ej[2] else lista_ej[1])
    updateSelectInput(session, "k_ejecucion", choices = lista_ej, selected = lista_ej[1])
    actual <- isolate(input$g_comparable)
    updateSelectInput(session, "g_comparable", choices = lista_comp,
                      selected = if (isTRUE(actual %in% lista_comp)) actual else lista_comp[1])
    updateSelectizeInput(session, "k_productos", choices = lista_comp,
                         selected = isolate(input$k_productos))

    if (!is.na(op$precios$maximo)) {
      tope <- ceiling(op$precios$maximo / 1000) * 1000
      updateSliderInput(session, "f_precio", min = 0, max = tope, value = c(0, tope))
    }
    if (!is.na(op$fechas$desde)) {
      updateDateRangeInput(session, "f_fechas", start = op$fechas$desde, end = op$fechas$hasta,
                           min = op$fechas$desde, max = op$fechas$hasta)
    }
  })

  observeEvent(input$f_limpiar, {
    updateSelectizeInput(session, "f_comercio", selected = character(0))
    updateSelectizeInput(session, "f_subcategoria", selected = character(0))
    updateSelectizeInput(session, "f_marca", selected = character(0))
    updateCheckboxInput(session, "f_promo", value = FALSE)
    updateCheckboxInput(session, "f_comparables", value = FALSE)
    updateTextInput(session, "f_texto", value = "")
    tope <- ceiling(opciones()$precios$maximo / 1000) * 1000
    if (!is.na(tope)) updateSliderInput(session, "f_precio", value = c(0, tope))
  })

#Filtros

  texto_busqueda <- debounce(reactive(input$f_texto), 600)
  busqueda <- reactive(validar_busqueda(texto_busqueda()))

  output$aviso_busqueda <- renderUI({
    if (is.null(busqueda())) {
      div(class = "text-danger small mb-2",
          sprintf("La búsqueda no se aplicó: use hasta %d caracteres (letras, números, espacios y . , + & %% ' -).",
                  LARGO_MAXIMO_BUSQUEDA))
    }
  })

  comercios_elegidos <- reactive(solo_permitidos(input$f_comercio, opciones()$comercios))

  filtros <- reactive({
    op <- opciones()
    precio <- suppressWarnings(as.numeric(input$f_precio))
    f <- list(
      comercios = comercios_elegidos(),
      subcategorias = solo_permitidos(input$f_subcategoria, op$subcategorias),
      marcas = solo_permitidos(input$f_marca, op$marcas),
      precio_min = if (length(precio) == 2 && !anyNA(precio)) precio[1] else NULL,
      precio_max = if (length(precio) == 2 && !anyNA(precio)) precio[2] else NULL,
      solo_promocion = isTRUE(input$f_promo),
      solo_comparables = isTRUE(input$f_comparables),
      texto = if (is.null(busqueda())) "" else busqueda()
    )
    if (identical(input$f_periodo, "fechas")) {
      fechas <- input$f_fechas
      req(length(fechas) == 2, !anyNA(fechas))
      validate(need(fechas[1] <= fechas[2], "La fecha inicial debe ser anterior a la final."))
      f$fecha_desde <- fechas[1]
      f$fecha_hasta <- fechas[2]
    } else {
      id <- input$f_ejecucion
      req(length(id) == 1, id %in% op$ejecuciones$id_ejecucion)
      f$id_ejecucion <- id
    }
    f
  })

# Ejecución de referencia para lo que necesita una sola ejecución
  ejecucion_ref <- reactive({
    f <- filtros()
    if (!is.null(f$id_ejecucion)) return(f$id_ejecucion)
    consulta_segura(db_ejecucion_en_rango(con, f$fecha_desde, f$fecha_hasta))
  })

  texto_ejecucion <- function(id) {
    ej <- opciones()$ejecuciones
    fila <- ej[ej$id_ejecucion == id, ]
    if (nrow(fila) == 0) return("sin ejecución en el periodo")
    etiqueta_ejecucion(fila$id_ejecucion, fila$fecha_inicio)
  }

  etiqueta_periodo <- reactive({
    f <- filtros()
    if (!is.null(f$id_ejecucion)) return(texto_ejecucion(f$id_ejecucion))
    paste("Del", format(as.Date(f$fecha_desde), "%d/%m/%Y"),
          "al", format(as.Date(f$fecha_hasta), "%d/%m/%Y"))
  })
  etiqueta_ref <- reactive(texto_ejecucion(ejecucion_ref()))

#Consultas con caché

  ind <- reactive({
    f <- filtros()
    consulta_segura(db_indicadores(con, f))
  }) |> bindCache(filtros(), version_datos())

  mediana <- reactive({
    f <- filtros()
    consulta_segura(db_mediana(con, f))
  }) |> bindCache(filtros(), version_datos())

  por_comercio <- reactive({
    f <- filtros()
    consulta_segura(db_por_comercio(con, f))
  }) |> bindCache(filtros(), version_datos())

  mediana_sub <- reactive({
    f <- filtros()
    consulta_segura(db_mediana_subcategoria(con, f))
  }) |> bindCache(filtros(), version_datos())

  productos <- reactive({
    f <- filtros()
    consulta_segura(db_productos(con, f))
  }) |> bindCache(filtros(), version_datos())

  ahorro <- reactive({
    id <- ejecucion_ref()
    com <- comercios_elegidos()
    if (is.na(id)) return(data.frame())
    consulta_segura(db_ahorro_maximo(con, id, com))
  }) |> bindCache(ejecucion_ref(), comercios_elegidos(), version_datos())

  cambios_ref <- reactive({
    id <- ejecucion_ref()
    com <- comercios_elegidos()
    if (is.na(id)) return(data.frame(cambios = NA, subidas = NA, bajadas = NA))
    consulta_segura(db_cambios_en_ejecucion(con, id, com))
  }) |> bindCache(ejecucion_ref(), comercios_elegidos(), version_datos())

  disponibilidad <- reactive({
    id <- ejecucion_ref()
    com <- comercios_elegidos()
    if (is.na(id)) return(data.frame(estado = character(0), n = integer(0)))
    consulta_segura(db_disponibilidad(con, id, com))
  }) |> bindCache(ejecucion_ref(), comercios_elegidos(), version_datos())

#Resumen
  
  output$fecha_datos <- renderText({
    u <- opciones()$ultima_con_datos
    if (nrow(u) == 0) return("Sin datos todavía")
    paste0("Datos al ", fecha_corta(u$fecha_inicio), " (", u$id_ejecucion, ")")
  })

  output$aviso_sin_datos <- renderUI({
    if (nrow(opciones()$ejecuciones) == 0) {
      return(div(class = "alert alert-info",
                 "La base todavía no tiene observaciones. Cargue los datos del Taller 1",
                 "o use la página 'Actualizar datos'."))
    }
    if (ind()$observaciones == 0) {
      div(class = "alert alert-warning",
          "No hay productos que cumplan los filtros elegidos. Pruebe quitando alguno.")
    }
  })

  output$ind_productos <- renderText(numero(ind()$productos))
  output$ind_productos_nota <- renderText(paste("en el periodo ·", etiqueta_periodo()))

  output$ind_observaciones <- renderText(numero(ind()$observaciones))
  output$ind_observaciones_nota <- renderText(paste("precios registrados ·", etiqueta_periodo()))

  output$ind_ultima <- renderText({
    u <- opciones()$ultima
    if (nrow(u) == 0) "Ninguna" else fecha_corta(u$fecha_inicio)
  })
  output$ind_ultima_nota <- renderText({
    u <- opciones()$ultima
    if (nrow(u) == 0) return("")
    paste0(u$id_ejecucion, " · ", u$estado, " · ", modo_texto(u$modo),
           " · ", numero(u$n_observaciones), " observaciones")
  })

  output$ind_promo <- renderText(porcentaje(ind()$pct_promocion))
  output$ind_promo_nota <- renderText(paste("de las observaciones ·", etiqueta_periodo()))

  output$ind_mediana <- renderText(cop(mediana()))
  output$ind_mediana_nota <- renderText(paste("COP ·", etiqueta_periodo()))

  output$ind_ahorro <- renderText({
    a <- ahorro()
    if (nrow(a) == 0) "sin dato" else cop(a$ahorro)
  })
  output$ind_ahorro_nota <- renderText({
    a <- ahorro()
    if (nrow(a) == 0) return(paste("se necesitan comparables en 2 comercios ·", etiqueta_ref()))
    paste0(a$comparable, ": de ", cop(a$precio_max), " a ", cop(a$precio_min), " · ", etiqueta_ref())
  })

  output$ind_cambios <- renderText(numero(cambios_ref()$cambios))
  output$ind_cambios_nota <- renderText({
    cc <- cambios_ref()
    paste0("productos (", numero(cc$subidas), " suben, ", numero(cc$bajadas),
           " bajan) frente a su precio anterior · ", etiqueta_ref())
  })

  output$ind_disponibilidad <- renderText({
    d <- disponibilidad()
    numero(sum(d$n[d$estado == "agotado"]))
  })
  output$ind_disponibilidad_nota <- renderText({
    d <- disponibilidad()
    paste0("productos según el sitio; ", numero(sum(d$n[d$estado == "no_observado"])),
           " no observados (no implica agotado); ", numero(sum(d$n[d$estado == "sin_dato"])),
           " sin dato del sitio · ", etiqueta_ref())
  })

  output$tabla_por_comercio <- renderDT({
    d <- por_comercio()
    validate(need(nrow(d) > 0, "No hay datos para los filtros elegidos."))
    tabla_dt(data.frame(Comercio = d$comercio, Productos = d$productos,
                        Observaciones = d$observaciones,
                        `Precio mínimo (COP)` = d$precio_min,
                        `Precio máximo (COP)` = d$precio_max, check.names = FALSE),
             colores = colores(), monedas = c("Precio mínimo (COP)", "Precio máximo (COP)"),
             dom = "t")
  })

  output$tabla_mediana_sub <- renderDT({
    d <- mediana_sub()
    validate(need(nrow(d) > 0, "No hay datos para los filtros elegidos."))
    tabla_dt(data.frame(`Subcategoría` = d$subcategoria, `Mediana (COP)` = d$mediana,
                        Observaciones = d$observaciones, check.names = FALSE),
             monedas = "Mediana (COP)", filas = 8)
  })

#Gráficos

  # Solo ofrecer las unidades que existen en la ejecución elegida
  observeEvent(ejecucion_ref(), {
    id <- ejecucion_ref()
    if (is.na(id)) return()
    unidades <- db_unidades_comparables(con, id)
    if (length(unidades) > 0) {
      actual <- isolate(input$g_unidad)
      updateRadioButtons(session, "g_unidad", choices = setNames(unidades, paste("por", ETIQUETA_POR[unidades])),
                         selected = if (actual %in% unidades) actual else unidades[1], inline = TRUE)
    }
  })

  output$g_evolucion <- renderHighchart({
    comps <- opciones()$comparables
    validate(need(nrow(comps) > 0, "No hay productos comparables cargados en la base."))
    id <- input$g_comparable
    validate(need(length(id) == 1 && id %in% comps$id_comparable, "Elija un producto comparable."))
    com <- comercios_elegidos()
    d <- consulta_segura(db_evolucion_comparable(con, id, com))
    validate(need(nrow(d) > 0, "Este producto no tiene precios para los comercios elegidos."))
    grafico_evolucion(d, comps$nombre[comps$id_comparable == id], colores(),
                      "Precio en COP en cada ejecución. Una serie por comercio.")
  }) |> bindCache(input$g_comparable, comercios_elegidos(), version_datos())

  output$g_unitario <- renderHighchart({
    id <- ejecucion_ref()
    validate(need(!is.na(id), "No hay una ejecución con datos en el periodo elegido."))
    unidad <- input$g_unidad
    validate(need(unidad %in% names(ETIQUETA_POR), "Elija una unidad."))
    com <- comercios_elegidos()
    d <- consulta_segura(db_precio_unitario(con, id, unidad, com))
    validate(need(nrow(d) > 0, paste("No hay productos comparables medidos en", unidad, "en esta ejecución.")))
    grafico_precio_unitario(d, unidad, colores(),
                            paste("Solo productos medidos en", unidad, "(no se mezclan unidades) ·", etiqueta_ref()))
  }) |> bindCache(ejecucion_ref(), input$g_unidad, comercios_elegidos(), version_datos())

  output$g_distribucion <- renderHighchart({
    f <- filtros()
    d <- consulta_segura(db_precios_para_distribucion(con, f))
    validate(need(nrow(d) > 0, "No hay precios para los filtros elegidos."))
    grafico_distribucion(d, colores(), paste("Precios en COP ·", etiqueta_periodo()))
  }) |> bindCache(filtros(), version_datos())

  output$g_mas_barato <- renderHighchart({
    id <- ejecucion_ref()
    validate(need(!is.na(id), "No hay una ejecución con datos en el periodo elegido."))
    com <- comercios_elegidos()
    d <- consulta_segura(db_veces_mas_barato(con, id, com))
    validate(need(nrow(d) > 0, "No hay comparables con precio en al menos dos comercios en esta ejecución."))
    todos <- if (length(com) > 0) com else opciones()$comercios
    d <- merge(data.frame(comercio = todos), d, all.x = TRUE)
    d$veces[is.na(d$veces)] <- 0
    d <- d[order(-d$veces), ]
    grafico_mas_barato(d, nrow(opciones()$comparables), colores(),
                       paste("Empates cuentan para todos los comercios empatados ·", etiqueta_ref()))
  }) |> bindCache(ejecucion_ref(), comercios_elegidos(), version_datos())

#Tabla de productos

  output$titulo_tabla <- renderText({
    paste0("Productos filtrados: ", numero(nrow(productos())), " filas · ", etiqueta_periodo())
  })

  output$tabla_productos <- renderDT({
    d <- productos()
    validate(need(nrow(d) > 0, "No hay productos para los filtros elegidos. Pruebe quitando algún filtro."))
    tabla <- data.frame(
      Comercio = d$comercio,
      Nombre = d$nombre,
      Marca = d$marca,
      `Presentación` = ifelse(is.na(d$contenido_num), "sin dato",
                              paste(numero(d$contenido_num), d$unidad_medida)),
      `Precio (COP)` = d$precio,
      `Precio unitario (COP)` = round(d$precio_unitario, 1),
      `Por` = ifelse(is.na(d$unidad_medida), "", unname(ETIQUETA_POR[d$unidad_medida])),
      `Promoción` = ifelse(is.na(d$es_promocion), "Sin dato", ifelse(d$es_promocion == 1, "Sí", "No")),
      Disponibilidad = unname(ETIQUETA_ESTADO[d$estado_disponibilidad]),
      `Fecha de consulta` = fecha_corta(d$fecha_hora_consulta),
      Anuncio = enlace(d$url_producto),
      check.names = FALSE
    )
    tabla_dt(tabla, colores = colores(), monedas = "Precio (COP)", filas = 15,
             escapar = setdiff(names(tabla), "Anuncio")) |>
      formatRound("Precio unitario (COP)", digits = 1, mark = ".", dec.mark = ",")
  })

  output$descargar_csv <- downloadHandler(
    filename = function() paste0("productos_filtrados_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(archivo) {
      utils::write.csv(productos(), archivo, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    }
  )

#Cambios de precio

  par_ejecuciones <- reactive({
    ids <- opciones()$ejecuciones$id_ejecucion
    ej <- opciones()$ejecuciones
    a <- input$c_anterior
    b <- input$c_reciente
    req(length(a) == 1, length(b) == 1)
    validate(need(length(ids) >= 2, "Se necesitan al menos dos ejecuciones con datos para comparar."))
    validate(need(a %in% ids && b %in% ids, "Elija dos ejecuciones de la lista."))
    validate(need(a != b, "Elija dos ejecuciones distintas."))
    # siempre de la más antigua a la más reciente
    if (ej$fecha_inicio[ej$id_ejecucion == a] > ej$fecha_inicio[ej$id_ejecucion == b]) c(b, a) else c(a, b)
  })

  comparacion <- reactive({
    p <- par_ejecuciones()
    consulta_segura(db_comparar_ejecuciones(con, p[1], p[2]))
  }) |> bindCache(par_ejecuciones(), version_datos())

  nota_comparacion <- reactive({
    p <- par_ejecuciones()
    paste("productos · de", p[1], "a", p[2])
  })
  contar_tipo <- function(tipo) numero(sum(comparacion()$tipo == tipo))

  output$c_suben <- renderText(contar_tipo("sube"))
  output$c_suben_nota <- renderText(nota_comparacion())
  output$c_bajan <- renderText(contar_tipo("baja"))
  output$c_bajan_nota <- renderText(nota_comparacion())
  output$c_nuevos <- renderText(contar_tipo("nuevo"))
  output$c_nuevos_nota <- renderText(nota_comparacion())
  output$c_no_obs <- renderText(contar_tipo("no_observado"))
  output$c_no_obs_nota <- renderText(nota_comparacion())

  output$tabla_cambios <- renderDT({
    d <- comparacion()
    d <- d[d$tipo %in% input$c_tipos, ]
    validate(need(nrow(d) > 0, "No hay productos de los tipos elegidos entre estas dos ejecuciones."))
    umbral <- input$c_umbral
    tabla <- data.frame(
      Comercio = d$comercio,
      Producto = d$nombre,
      Cambio = unname(ETIQUETA_TIPO[d$tipo]),
      `Precio anterior (COP)` = d$precio_anterior,
      `Precio reciente (COP)` = d$precio_reciente,
      `Diferencia (COP)` = d$diferencia,
      `Variación (%)` = d$variacion_pct,
      Anuncio = enlace(d$url),
      grande = as.integer(!is.na(d$variacion_pct) & abs(d$variacion_pct) >= umbral),
      check.names = FALSE
    )
    tabla_dt(tabla, colores = colores(), filas = 15,
             monedas = c("Precio anterior (COP)", "Precio reciente (COP)", "Diferencia (COP)"),
             escapar = setdiff(names(tabla), "Anuncio"),
             order = list(list(6, "desc")),
             columnDefs = list(list(visible = FALSE, targets = ncol(tabla) - 1))) |>
      formatStyle(setdiff(names(tabla), c("Comercio", "grande")), valueColumns = "grande",
                  backgroundColor = styleEqual(1, "#FFE69C")) |>
      formatStyle("Variación (%)", valueColumns = "grande", fontWeight = styleEqual(1, "bold")) |>
      formatRound("Variación (%)", digits = 1, mark = ".", dec.mark = ",")
  })

#Canasta

  output$k_cantidades <- renderUI({
    comps <- opciones()$comparables
    ids <- solo_permitidos(input$k_productos, comps$id_comparable)
    if (length(ids) == 0) {
      return(p(class = "text-muted small", "Elija productos para indicar la cantidad de cada uno."))
    }
    lapply(ids, function(id) {
      control <- paste0("k_cant_", id)
      anterior <- isolate(input[[control]])
      numericInput(control, paste("Cantidad:", comps$nombre[comps$id_comparable == id]),
                   value = if (is.null(anterior)) 1 else anterior, min = 1, max = 50, step = 1)
    })
  })

  canasta <- reactive({
    comps <- opciones()$comparables
    ids <- solo_permitidos(input$k_productos, comps$id_comparable)
    validate(need(length(ids) > 0, "Elija al menos un producto comparable para armar la canasta."))
    cantidades <- lapply(ids, function(id) input[[paste0("k_cant_", id)]])
    req(!any(vapply(cantidades, is.null, logical(1))))
    cantidades <- suppressWarnings(as.numeric(unlist(cantidades)))
    validate(need(all(!is.na(cantidades) & cantidades >= 1 & cantidades <= 50 &
                        cantidades == round(cantidades)),
                  "Las cantidades deben ser números enteros entre 1 y 50."))
    ej <- input$k_ejecucion
    validate(need(length(ej) == 1 && ej %in% opciones()$ejecuciones$id_ejecucion,
                  "Elija una ejecución."))
    precios <- consulta_segura(db_precios_canasta(con, ej, ids))
    validate(need(nrow(precios) > 0, "No hay precios de estos productos en la ejecución elegida."))
    calcular_canasta(precios, data.frame(id_comparable = ids, cantidad = cantidades))
  })

  nota_canasta <- reactive(texto_ejecucion(input$k_ejecucion))

  output$k_minimo <- renderText({
    k <- canasta()
    if (is.na(k$costo_minimo)) "No se puede calcular" else cop(k$costo_minimo)
  })
  output$k_minimo_nota <- renderText({
    k <- canasta()
    if (is.na(k$costo_minimo)) return("algún producto no está disponible en ningún comercio")
    paste("comprando cada producto donde es más barato ·", nota_canasta())
  })

  output$k_mejor <- renderText({
    k <- canasta()
    if (is.na(k$mejor_comercio)) "Ningún comercio tiene todo" else k$mejor_comercio
  })
  output$k_mejor_nota <- renderText({
    k <- canasta()
    if (is.na(k$mejor_comercio)) return("revise la tabla para ver qué falta en cada uno")
    paste("total", cop(k$mejor_total), "·", nota_canasta())
  })

  output$k_ahorro <- renderText({
    k <- canasta()
    if (is.na(k$ahorro)) "sin dato" else cop(k$ahorro)
  })
  output$k_ahorro_nota <- renderText({
    k <- canasta()
    if (is.na(k$ahorro)) return("se necesita al menos un comercio con todos los productos")
    paste("frente a comprar todo en", k$mejor_comercio)
  })

  output$k_tabla_comercios <- renderDT({
    k <- canasta()$por_comercio
    tabla_dt(data.frame(
      Comercio = k$comercio,
      `Total (COP)` = ifelse(k$completa, cop(k$total), "No se calcula: faltan productos"),
      `Le faltan` = ifelse(k$completa, "", k$faltan),
      `Paga de más frente a combinar (COP)` = ifelse(k$completa, cop(k$ahorro_vs_minimo), ""),
      check.names = FALSE), colores = colores(), dom = "t", ordering = FALSE)
  })

  output$k_tabla_detalle <- renderDT({
    k <- canasta()$detalle
    tabla_dt(data.frame(
      Producto = k$comparable, Cantidad = k$cantidad,
      `Precio más bajo (COP)` = k$precio_min,
      `Dónde (empates con /)` = k$donde,
      `Subtotal (COP)` = k$subtotal, check.names = FALSE),
      monedas = c("Precio más bajo (COP)", "Subtotal (COP)"), dom = "t")
  })

#Actualización en segundo plano

  tarea <- ExtendedTask$new(function(sin_conexion, ruta_bd) {
    future_promise({
      if (!file.exists("scraper.R")) stop("No se encontró scraper.R en la carpeta de la aplicación.")
      source("scraper.R")
      source("db.R")
      source("validacion.R")
      source("actualizacion.R")
      ejecutar_actualizacion(ruta_bd, sin_conexion = sin_conexion)
    }, seed = TRUE, globals = list(sin_conexion = sin_conexion, ruta_bd = ruta_bd))
  }) |> bind_task_button("actualizar")

  observeEvent(input$actualizar, {
    if (isTRUE(estado_global$actualizando)) {
      showNotification("Ya hay una actualización en curso. Espere a que termine.", type = "warning")
      return()
    }
    estado_global$actualizando <- TRUE
    estado_global$sesion <- session$token
    tarea$invoke(isTRUE(input$modo_sin_conexion), RUTA_BD)
  })

  session$onSessionEnded(function() {
    if (identical(estado_global$sesion, session$token)) estado_global$actualizando <- FALSE
  })

  observeEvent(tarea$status(), {
    st <- tarea$status()
    if (st %in% c("success", "error")) estado_global$actualizando <- FALSE
    if (st == "success") {
      actualizado(actualizado() + 1)   # invalida la caché y refresca todo
      r <- tarea$result()
      showNotification(sprintf("Actualización terminada: %s, estado %s.", r$id_ejecucion, r$estado),
                       type = if (r$estado == "COMPLETA") "message" else "warning", duration = 8)
    }
  })

  output$aviso_servidor <- renderUI({
    if (EN_SERVIDOR) {
      div(class = "alert alert-info small mt-3",
          "Está usando la versión publicada. Los comercios suelen bloquear las peticiones",
          "que vienen de estos servidores, por eso el modo sin conexión viene activado.",
          "Además, la plataforma no conserva los cambios en la base cuando reinicia la app.")
    }
  })

  output$estado_actualizacion <- renderUI({
    st <- tarea$status()
    if (st == "running") {
      return(div(class = "alert alert-secondary small mt-3",
                 "Consultando los comercios... puede seguir usando las otras páginas."))
    }
    if (st == "error") {
      motivo <- tryCatch({ tarea$result(); "" }, error = function(e) conditionMessage(e))
      return(div(class = "alert alert-danger small mt-3",
                 strong("La actualización no se completó. "), motivo))
    }
    if (st != "success") return(NULL)
    r <- tarea$result()
    fallo_red <- r$modo == "online" && all(r$comercios$estado == "FALLIDA")
    nuevas <- sum(r$comercios$insertadas)
    con_problema <- r$comercios[r$comercios$estado != "COMPLETA", ]
    tagList(
      div(class = paste("alert small mt-3", if (r$estado == "COMPLETA") "alert-success" else "alert-warning"),
          sprintf("Ejecución %s (%s): %s. Entraron %d observaciones nuevas a la base.",
                  r$id_ejecucion, modo_texto(r$modo), r$estado, nuevas),
          if (r$modo == "offline" && nuevas == 0) {
            p(class = "mb-0 mt-1", "Las copias de raw/ ya estaban en la base; no se duplicó nada.")
          }),
      if (nrow(con_problema) > 0) {
        div(class = "small mb-3",
            strong("Comercios con problemas:"),
            tags$ul(lapply(seq_len(nrow(con_problema)), function(i)
              tags$li(paste0(con_problema$comercio[i], " (", con_problema$estado[i], "): ",
                             con_problema$motivo[i])))))
      },
      if (length(r$notas) > 0) {
        div(class = "small text-muted mb-2", strong("Notas del marcado de comparables: "),
            paste(r$notas, collapse = " | "))
      },
      if (fallo_red) {
        div(class = "alert alert-danger small",
            strong("No fue posible obtener datos de ningún comercio desde este equipo o servidor. "),
            "Es común que los comercios bloqueen las plataformas de alojamiento.",
            "Active el modo sin conexión para reprocesar las copias de raw/.")
      }
    )
  })

  output$tabla_resumen_actualizacion <- renderDT({
    st <- tarea$status()
    validate(need(st == "success", switch(st,
      running = "Actualizando... el resumen aparecerá aquí al terminar.",
      error = "La última actualización no se completó; vea el mensaje a la izquierda.",
      "Todavía no se ha corrido una actualización en esta sesión.")))
    r <- tarea$result()$comercios
    tabla_dt(data.frame(
      Comercio = r$comercio, Estado = r$estado,
      Motivo = ifelse(is.na(r$motivo), "", r$motivo),
      `Productos recolectados` = r$recolectadas, `Válidos` = r$validas,
      Rechazados = r$rechazadas, `Insertados` = r$insertadas,
      `Productos nuevos` = r$nuevos, `Cambios de precio` = r$cambios_precio,
      `No observados` = r$no_observados,
      check.names = FALSE), colores = colores(), dom = "t")
  })

  output$tabla_ejecuciones <- renderDT({
    version_datos()
    d <- consulta_segura(db_historial_ejecuciones(con))
    validate(need(nrow(d) > 0, "No hay ejecuciones registradas."))
    tabla_dt(data.frame(`Ejecución` = d$id_ejecucion, Inicio = fecha_corta(d$fecha_inicio),
                        Modo = modo_texto(d$modo), Estado = d$estado,
                        `Comercios intentados` = d$comercios_intentados,
                        `Comercios con datos` = d$n_comercios,
                        Observaciones = d$n_observaciones, check.names = FALSE))
  })

  output$tabla_ejecuciones_comercio <- renderDT({
    version_datos()
    d <- consulta_segura(db_detalle_ejecuciones(con))
    validate(need(nrow(d) > 0, "No hay ejecuciones registradas."))
    tabla_dt(data.frame(`Ejecución` = d$id_ejecucion, Comercio = d$comercio,
                        Inicio = fecha_corta(d$fecha_inicio), Estado = d$estado,
                        Modo = modo_texto(d$modo), Registros = d$registros_obtenidos,
                        Rechazadas = d$n_rechazadas, Insertadas = d$n_insertadas,
                        Nuevos = d$n_nuevos, `Cambios de precio` = d$n_cambios,
                        `No observados` = d$n_no_observados, Detalle = d$detalle,
                        check.names = FALSE), colores = colores())
  })

  output$tabla_rechazos <- renderDT({
    version_datos()
    d <- consulta_segura(db_rechazos(con))
    validate(need(nrow(d) > 0, "No hay observaciones rechazadas."))
    tabla_dt(data.frame(`Ejecución` = d$id_ejecucion, Comercio = d$comercio, SKU = d$sku_comercio,
                        Nombre = d$producto_nombre_original, `Precio (COP)` = d$precio_cop,
                        `Fecha de consulta` = fecha_corta(d$fecha_hora_consulta),
                        Motivo = d$motivo, check.names = FALSE),
             colores = colores(), monedas = "Precio (COP)")
  })

  output$tabla_correcciones <- renderDT({
    version_datos()
    d <- consulta_segura(db_correcciones(con))
    validate(need(nrow(d) > 0, "No hay correcciones registradas."))
    tabla_dt(data.frame(Fecha = d$fecha, Tabla = d$tabla, Registro = d$id_registro, Campo = d$campo,
                        `Valor anterior` = d$valor_anterior, `Valor nuevo` = d$valor_nuevo,
                        Motivo = d$motivo, check.names = FALSE))
  })
}
