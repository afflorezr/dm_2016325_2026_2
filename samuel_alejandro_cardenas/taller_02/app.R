requeridos <- c('shiny','bslib','DBI','RSQLite','DT','highcharter','future','promises')
no_instalados <- requeridos[!vapply(requeridos, requireNamespace, logical(1), quietly=TRUE)]
if (length(no_instalados)) {
  stop('Instala primero: install.packages(c(', paste(sprintf('"%s"',no_instalados),collapse=','), '))')
}
library(shiny)
library(bslib)
source('db.R', local=TRUE)
`%||%` <- function(x, y) if (is.null(x) || length(x)==0L) y else x

future::plan(future::multisession, workers=2L)
colores <- c('Cafam'='#0C7C86','Locatel'='#E19B29','Cruz Verde'='#824BB3')
formato_cop <- function(x) {
  if (!length(x) || is.na(x) || !is.finite(x)) return('Sin dato')
  paste0('$',format(round(x),big.mark='.',decimal.mark=',',scientific=FALSE,trim=TRUE))
}
formato_n <- function(x) vapply(x, function(z) if (is.na(z)) '0' else format(z,big.mark='.',scientific=FALSE,trim=TRUE), character(1))

lista <- opciones_filtros()
ejes <- ejecuciones_disponibles()
if (!nrow(ejes)) stop('La base no tiene ejecuciones para mostrar.')
nombres_ejecucion <- paste0(ejes$fecha, ' | ',ejes$id_ejecucion,
                            ' (',ejes$comercios,' comercios)')
valores_ejecucion <- stats::setNames(ejes$id_ejecucion,nombres_ejecucion)


ejes_3 <- ejes[ejes$comercios == 3L, , drop=FALSE]
if (!nrow(ejes_3)) stop('No existen capturas que incluyan los tres comercios.')
nombres_ejecucion_3 <- paste0(ejes_3$fecha, ' | ',ejes_3$id_ejecucion,
                              ' (3 comercios; cobertura por verificar)')
valores_ejecucion_3 <- stats::setNames(ejes_3$id_ejecucion,nombres_ejecucion_3)
ultima <- ejes_3$id_ejecucion[[1L]]
previa <- if (nrow(ejes_3)>=2L) ejes_3$id_ejecucion[[2L]] else ultima

base_grafico <- function(titulo, eje_y=NULL, tipo='column') {
  alto <- highcharter::highchart() |>
    highcharter::hc_chart(type=tipo,backgroundColor='transparent') |>
    highcharter::hc_title(text=titulo) |>
    highcharter::hc_exporting(enabled=TRUE) |>
    highcharter::hc_legend(enabled=TRUE)
  if (!is.null(eje_y)) alto <- highcharter::hc_yAxis(alto,title=list(text=eje_y))
  alto
}

ui <- bslib::page_sidebar(
  title='Comparador de precios | Salud sexual',
  theme=bslib::bs_theme(version=5,bootswatch='flatly',primary='#116875'),
  sidebar=bslib::sidebar(
    width=320,
    h5('Filtros combinables'),
    selectInput('comercios','Comercios',choices=lista$comercios,
                selected=lista$comercios,multiple=TRUE),
    selectInput('subcategoria','Subcategoria',
                choices=c('Todas'='',stats::setNames(lista$subcategorias,lista$subcategorias))),
    selectInput('marca','Marca',
                choices=c('Todas'='',stats::setNames(lista$marcas,lista$marcas))),
    sliderInput('precio','Precio (COP)',min=0,max=500000,
                value=c(0,500000),step=1000),
    dateRangeInput('fechas','Fechas',start=as.Date('2026-10-01'),end=Sys.Date(),
                   format='yyyy-mm-dd',language='es'),
    checkboxInput('promos','Solo promociones',FALSE),
    checkboxInput('solo_comparables','Solo productos comparables',FALSE),
    textInput('buscar','Buscar anuncio','',placeholder='Nombre o descripcion'),
    tags$hr(),
    h5('Actualizar datos'),
    bslib::input_task_button('actualizar','Consultar comercios ahora',type='primary'),
    bslib::input_task_button('demostracion','Reprocesar RAW sin internet'),
    tags$small('El modo offline no modifica precios ni crea una fecha de captura.'),
    textOutput('estado_actualizacion')
  ),
  bslib::navset_tab(
    bslib::nav_panel('Resumen',
      tags$p('Precios expresados en pesos colombianos (COP). Todos los datos indican su fecha de consulta.'),
      bslib::layout_columns(
        bslib::value_box('Ofertas visibles',textOutput('kpi_ofertas'),theme='primary'),
        bslib::value_box('Marcas distintas',textOutput('kpi_marcas'),theme='info'),
        bslib::value_box('Comercios',textOutput('kpi_comercios'),theme='success'),
        col_widths=c(4,4,4)
      ),
      bslib::layout_columns(
        bslib::value_box('En promocion',textOutput('kpi_promos'),theme='warning'),
        bslib::value_box('Precio medio (COP)',textOutput('kpi_precio'),theme='primary'),
        bslib::value_box('Comparables distintos',textOutput('kpi_comparables'),theme='info'),
        col_widths=c(4,4,4)
      ),
      tags$p(tags$strong('Fecha de datos mas reciente: '),textOutput('fecha_datos',inline=TRUE)),
      bslib::layout_columns(
        bslib::card(bslib::card_header('Distribucion de precios por comercio'),
                    highcharter::highchartOutput('grafico_distribucion',height='360px')),
        bslib::card(bslib::card_header('Cambios frente a la observacion anterior'),
                    highcharter::highchartOutput('grafico_cambios',height='360px')),
        col_widths=c(6,6)
      )
    ),
    bslib::nav_panel('Comparar productos',
      selectInput('producto','Producto comparable',choices=lista$productos,
                  selected=lista$productos[[1L]]),
      selectInput('ejecucion_grafico','Ejecucion para comparar precio por unidad',
                  choices=valores_ejecucion_3,selected=ultima),
      bslib::layout_columns(
        bslib::card(bslib::card_header('Evolucion temporal del precio'),
                    highcharter::highchartOutput('grafico_serie',height='410px')),
        bslib::card(bslib::card_header('Precio por unidad normalizada'),
                    highcharter::highchartOutput('grafico_unidad',height='410px')),
        col_widths=c(6,6)
      ),
      tags$small('Se usan capturas con los tres comercios; eso no certifica cobertura total. Las unidades (g, mL y unidad) no se mezclan.')
    ),
    bslib::nav_panel('Cambios entre fechas',
      bslib::layout_columns(
        selectInput('ejecucion_antes','Ejecucion anterior',
                    choices=valores_ejecucion_3,selected=previa),
        selectInput('ejecucion_despues','Ejecucion posterior',
                    choices=valores_ejecucion_3,selected=ultima),
        numericInput('umbral','Umbral de variacion destacada (%)',value=10,min=0,max=100),
        col_widths=c(5,5,2)
      ),
      tags$p('Se comparan capturas con tres comercios, el mismo anuncio y el mismo comercio. La ausencia de registro no prueba agotamiento; tres comercios tampoco certifican cobertura total.'),
      DT::DTOutput('tabla_cambios')
    ),
    bslib::nav_panel('Canasta',
      selectInput('canasta_items','Productos para comprar',choices=lista$productos,
                  selected=head(lista$productos,2),multiple=TRUE),
      selectInput('ejecucion_canasta','Fecha / ejecucion de la canasta',
                  choices=valores_ejecucion_3,selected=ultima),
      uiOutput('cantidades_canasta'),
      tags$p('Los totales solo se muestran si están presentes y disponibles TODOS los productos en esa tienda. Stock no confirmado no equivale a disponible.'),
      DT::DTOutput('tabla_canasta'),
      textOutput('ahorro_canasta'),
      tags$small('Un precio capturado no certifica inventario. Los artículos con stock no confirmado quedan fuera del mínimo multitienda; no se incluyen envíos ni otras condiciones comerciales.')
    ),
    bslib::nav_panel('Catalogo',
      tags$p('Tabla filtrada por SQL: buscar, ordenar y exportar los datos consultados.'),
      downloadButton('descargar_csv','Descargar CSV filtrado'),
      DT::DTOutput('tabla_catalogo')
    ),
    bslib::nav_panel('Trazabilidad',
      selectInput('ejecucion_cobertura','Ejecucion',choices=valores_ejecucion,selected=ultima),
      tags$p('Una ruta recorrida no garantiza por si sola la cobertura total de la categoria.'),
      DT::DTOutput('tabla_cobertura')
    )
  )
)

server <- function(input,output,session) {
  version_datos <- reactiveVal(0L)
  filtros <- reactive({
    fechas <- input$fechas
    list(comercios=input$comercios,
         subcategoria=input$subcategoria %||% '',
         marca=input$marca %||% '',
         minimo=input$precio[[1]],maximo=input$precio[[2]],
         desde=if(length(fechas)>=1L) as.character(fechas[[1L]]) else '',
         hasta=if(length(fechas)>=2L) as.character(fechas[[2L]]) else '',
         promocion=isTRUE(input$promos),
         comparables=isTRUE(input$solo_comparables),
         texto=trimws(input$buscar %||% ''))
  })
  datos <- reactive({
    version_datos()
    datos_filtrados_sql(filtros())
  }) |> bindCache(filtros(),version_datos())
  indicadores <- reactive({
    version_datos()
    kpis_sql(filtros())
  }) |> bindCache(filtros(),version_datos())

  output$kpi_ofertas <- renderText(formato_n(indicadores()$ofertas[[1L]]))
  output$kpi_marcas <- renderText(formato_n(indicadores()$marcas[[1L]]))
  output$kpi_comercios <- renderText(formato_n(indicadores()$comercios[[1L]]))
  output$kpi_promos <- renderText(formato_n(indicadores()$promociones[[1L]]))
  output$kpi_precio <- renderText(formato_cop(indicadores()$precio_promedio[[1L]]))
  output$kpi_comparables <- renderText(formato_n(indicadores()$productos_comparables[[1L]]))
  output$fecha_datos <- renderText(indicadores()$fecha_mas_reciente[[1L]] %||% 'Sin dato')

  output$tabla_catalogo <- DT::renderDT({
    x <- datos()
    validate(need(nrow(x)>0,'No hay productos que cumplan estos filtros.'))
    DT::datatable(x,rownames=FALSE,filter='top',
                  options=list(pageLength=12,scrollX=TRUE,autoWidth=TRUE))
  })
  output$descargar_csv <- downloadHandler(
    filename=function() paste0('comparador_',Sys.Date(),'.csv'),
    content=function(file) utils::write.csv(datos(),file,row.names=FALSE,fileEncoding='UTF-8')
  )

  output$grafico_serie <- highcharter::renderHighchart({
    version_datos()
    req(input$producto)
    d <- serie_producto_sql(input$producto,input$comercios)
    validate(need(nrow(d)>0,'No hay historial para el producto seleccionado.'))
    fechas <- sort(unique(as.character(d$fecha)))
    h <- base_grafico('Precio historico por comercio','COP',tipo='line') |>
      highcharter::hc_xAxis(categories=fechas,title=list(text='Fecha'))
    for (com in unique(d$comercio)) {
      t <- d[d$comercio==com,,drop=FALSE]
      vals <- vapply(fechas,function(fecha) {
        z <- t$precio[t$fecha==fecha]
        if (length(z)) as.numeric(tail(z,1L)) else NA_real_
      },numeric(1L))
      h <- highcharter::hc_add_series(
        h, name=com, type='line', data=as.list(unname(vals)),
        marker=list(enabled=TRUE,radius=4),
        color=unname(colores[com])
      )
    }
    h |> highcharter::hc_tooltip(shared=TRUE,valuePrefix='$')
  })

  output$grafico_unidad <- highcharter::renderHighchart({
    version_datos()
    req(input$producto,input$ejecucion_grafico)
    d <- precio_unitario_sql(input$producto,input$ejecucion_grafico)
    validate(need(nrow(d)>0,'Esta ejecucion no contiene un precio unitario valido.'))
    validate(need(length(unique(d$unidad_calculable))==1L,
                  'Hay unidades incompatibles; no se pueden comparar.'))
    h <- base_grafico('Costo por unidad',paste0('COP / ',d$unidad_calculable[[1L]])) |>
      highcharter::hc_xAxis(categories=as.character(d$comercio))
    h |> highcharter::hc_add_series(
      name='Precio unitario',
      data=lapply(seq_len(nrow(d)),function(i) list(
        y=as.numeric(d$precio_unitario[[i]]),color=unname(colores[d$comercio[[i]]])
      )),type='column')
  })

  output$grafico_distribucion <- highcharter::renderHighchart({
    version_datos()
    d <- distribucion_sql(filtros())
    validate(need(nrow(d)>0,'No hay precios para representar.'))
    bins <- sort(unique(d$tramo))
    bins <- head(bins,35L)
    categorias <- paste0(formato_n(bins*10000),'–',formato_n((bins+1)*10000),' COP')
    h <- base_grafico('Frecuencia por intervalo de $10.000','Cantidad de anuncios') |>
      highcharter::hc_xAxis(categories=categorias,title=list(text='Tramo de precio'))
    for (com in unique(d$comercio)) {
      t <- d[d$comercio==com,,drop=FALSE]
      vals <- vapply(bins,function(b) {
        z <- t$frecuencia[t$tramo==b]
        if (length(z)) as.numeric(z[[1L]]) else 0
      },numeric(1L))
      h <- highcharter::hc_add_series(h,name=com,data=as.list(vals),
                                     color=unname(colores[com]),type='column')
    }
    h
  })

  output$grafico_cambios <- highcharter::renderHighchart({
    version_datos()
    ids <- ejecuciones_disponibles()$id_ejecucion
    validate(need(length(ids)>0,'No hay ejecuciones.'))
    d <- cambios_por_comercio_sql(ids[[1L]])
    validate(need(nrow(d)>0,'Sin cambios de precio para representar.'))
    h <- base_grafico('Cambios en la ejecucion reciente','Cantidad de anuncios') |>
      highcharter::hc_xAxis(categories=c('Subieron','Bajaron','Iguales'))
    for (com in unique(d$comercio)) {
      z <- d[d$comercio==com,,drop=FALSE]
      nums <- as.numeric(unlist(z[1L,c('subieron','bajaron','iguales')],use.names=FALSE))
      h <- highcharter::hc_add_series(h,name=com,data=as.list(nums),
                                     color=unname(colores[com]),type='column')
    }
    h
  })

  output$tabla_cambios <- DT::renderDT({
    version_datos()
    req(input$ejecucion_antes,input$ejecucion_despues)
    validate(need(input$ejecucion_antes!=input$ejecucion_despues,
                  'Selecciona dos ejecuciones distintas.'))
    a <- comparar_ejecuciones_sql(input$ejecucion_antes,input$ejecucion_despues)
    validate(need(nrow(a)>0,'No hay anuncios comparables entre esas ejecuciones.'))
    umbral <- as.numeric(input$umbral)
    a$destacado <- ifelse(!is.na(a$variacion_pct) & abs(a$variacion_pct)>=umbral,
                          'Variacion relevante','')
    DT::datatable(a,rownames=FALSE,
                  options=list(pageLength=15,scrollX=TRUE))
  })

  output$cantidades_canasta <- renderUI({
    items <- input$canasta_items
    if (!length(items)) return(tags$em('Selecciona al menos un producto.'))
    tagList(lapply(items,function(id) {
      numericInput(paste0('cantidad_',id),paste('Cantidad:',gsub('_',' ',id)),
                   value=1,min=1,max=100,step=1)
    }))
  })
  cantidades <- reactive({
    ids <- input$canasta_items
    if (!length(ids)) return(integer())
    vapply(ids,function(id) {
      z <- input[[paste0('cantidad_',id)]]
      if (is.null(z) || !is.finite(z)) 1L else as.integer(z)
    },integer(1))
  })
  resultado_canasta <- reactive({
    version_datos()
    req(input$ejecucion_canasta)
    ids <- input$canasta_items
    validate(need(length(ids)>0,'Selecciona al menos un producto.'))
    canasta_sql(ids,cantidades(),input$ejecucion_canasta)
  })
  output$tabla_canasta <- DT::renderDT({
    d <- resultado_canasta()
    validate(need(nrow(d)>0,'No hay precios para esta canasta y ejecucion.'))
    d$estado_canasta <- ifelse(d$presentes<length(input$canasta_items),'Incompleta',
                              ifelse(d$agotados>0,'Contiene agotados',
                                     ifelse(d$sin_confirmar>0,'Stock no confirmado','Disponible')))
    d$total_cop <- ifelse(d$presentes==length(input$canasta_items) &
                            d$agotados==0 & d$sin_confirmar==0,
                          d$total_estimado,NA_real_)
    DT::datatable(d[,c('comercio','presentes','agotados','sin_confirmar','total_cop','estado_canasta')],
                  rownames=FALSE,options=list(dom='t'))
  })
  output$ahorro_canasta <- renderText({
    d <- resultado_canasta()
    minimo <- minimo_canasta_sql(input$canasta_items,cantidades(),input$ejecucion_canasta)
    if (nrow(minimo)!=length(input$canasta_items) || anyNA(minimo$subtotal))
      return('No se puede calcular el mínimo multitienda: falta al menos un precio con disponibilidad confirmada.')
    minimo_total <- sum(minimo$subtotal)
    tiendas <- d[d$presentes==length(input$canasta_items) &
                   d$agotados==0 & d$sin_confirmar==0,,drop=FALSE]
    if (!nrow(tiendas)) return(paste('Mínimo entre productos con disponibilidad confirmada:',
                                     formato_cop(minimo_total),
                                     '| ninguna tienda tiene confirmada toda la canasta.'))
    mejor <- min(tiendas$total_estimado)
    paste('Mínimo multitienda (solo disponibilidad confirmada):',formato_cop(minimo_total),
          '| mejor tienda completa:',formato_cop(mejor),
          '| ahorro estimado:',formato_cop(max(0,mejor-minimo_total)),
          '| no incluye domicilio, mínimos de compra ni condiciones de promociones.')
  })

  output$tabla_cobertura <- DT::renderDT({
    version_datos()
    req(input$ejecucion_cobertura)
    d <- cobertura_sql(input$ejecucion_cobertura)
    validate(need(nrow(d)>0,'No hay cobertura registrada para la ejecucion.'))
    DT::datatable(d,rownames=FALSE,options=list(dom='t',scrollX=TRUE))
  })

  tarea_actualizar <- shiny::ExtendedTask$new(function() {
    promises::future_promise({
      source('actualizacion_taller2.R',local=TRUE)
      actualizar_precios_t2()
    })
  }) |> bslib::bind_task_button('actualizar')
  observeEvent(input$actualizar,tarea_actualizar$invoke())

  tarea_offline <- shiny::ExtendedTask$new(function(id) {
    promises::future_promise({
      source('actualizacion_taller2.R',local=TRUE)
      lapply(c('Cafam','Locatel','Cruz Verde'),function(com) {
        z <- reprocesar_raw_t2(id,com)
        list(comercio=com,validas=z$validas,rechazadas=z$rechazadas)
      })
    })
  }) |> bslib::bind_task_button('demostracion')
  observeEvent(input$demostracion, {
    ids <- ejecuciones_disponibles()$id_ejecucion
    if (length(ids)) tarea_offline$invoke(ids[[1L]])
  })

  observeEvent(tarea_actualizar$status(), {
    if (identical(tarea_actualizar$status(),'success')) {
      version_datos(version_datos()+1L)
      nue <- ejecuciones_disponibles()
      if (nrow(nue)) {
        todos <- stats::setNames(nue$id_ejecucion,
          paste0(nue$fecha,' | ',nue$id_ejecucion,' (',nue$comercios,' comercios)'))
        nueva_3 <- nue[nue$comercios == 3L, , drop=FALSE]
        if (nrow(nueva_3)) {
          candidatos <- stats::setNames(nueva_3$id_ejecucion,
            paste0(nueva_3$fecha,' | ',nueva_3$id_ejecucion,
                   ' (3 comercios; cobertura por verificar)'))
          updateSelectInput(session,'ejecucion_grafico',choices=candidatos,
                            selected=nueva_3$id_ejecucion[[1L]])
          updateSelectInput(session,'ejecucion_canasta',choices=candidatos,
                            selected=nueva_3$id_ejecucion[[1L]])
          updateSelectInput(session,'ejecucion_despues',choices=candidatos,
                            selected=nueva_3$id_ejecucion[[1L]])
          updateSelectInput(session,'ejecucion_antes',choices=candidatos,
                            selected=nueva_3$id_ejecucion[[min(2,nrow(nueva_3))]])
        }
        updateSelectInput(session,'ejecucion_cobertura',choices=todos,
                          selected=nue$id_ejecucion[[1L]])
      }
      showNotification('Nueva consulta terminada. Revisa el estado de cobertura.',type='message')
    }
  })
  output$estado_actualizacion <- renderText({
    estado <- tarea_actualizar$status()
    offline <- tarea_offline$status()
    if (estado=='running') return('Consultando tiendas sin bloquear la app...')
    if (estado=='success') {
      x <- tarea_actualizar$result()
      return(paste('Captura',x$id_ejecucion,':',
                   paste(x$resumen$comercio,x$resumen$estado,collapse='; ')))
    }
    if (estado=='error') return('La actualizacion tuvo un error. Revisa la consola de RStudio.')
    if (offline=='running') return('Reprocesando archivos RAW...')
    if (offline=='success') return('RAW reprocesados. No se alteraron fechas ni precios.')
    if (offline=='error') return('Fallo el reprocesamiento RAW; revisa los archivos.')
    'Modo lectura: observa precios historicos. El boton consulta sitios reales.'
  })
}

shinyApp(ui,server)
