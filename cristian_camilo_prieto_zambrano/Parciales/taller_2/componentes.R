# =============================================================================
# componentes.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Piezas de la interfaz armadas en HTML (Módulo 5): tarjetas de comparación de
# los productos comparables, tarjetas de indicadores y resultados de la canasta.
# Reciben tablas calculadas en SQL por db.R.
# =============================================================================

# -----------------------------------------------------------------------------
# Tarjeta de comparación de un producto (estilo de los comparadores de precios):
# comercios ordenados de más barato a más caro, el mejor precio resaltado, la
# diferencia de los demás, y el historial de cada precio.
# -----------------------------------------------------------------------------
tarjeta_comparable <- function(d) {
  d <- d[order(d$precio, d$comercio), ]
  ahorro <- d$ahorro_pct[1]
  filas <- lapply(seq_len(nrow(d)), function(i) {
    r <- d[i, ]
    mejor <- isTRUE(r$es_mas_barato == 1)
    notas <- tagList(
      if (!is.na(r$variacion_pct) && r$variacion_pct != 0)
        span(class = paste("pildora", if (r$variacion_pct < 0) "baja" else "sube"),
             icon(if (r$variacion_pct < 0) "arrow-down" else "arrow-up", class = "fa-xs"),
             paste(porcentaje(abs(r$variacion_pct)), "vs. corrida anterior")),
      if (identical(r$historial, "más bajo registrado"))
        span(class = "pildora minimo", icon("star", class = "fa-xs"), "Precio más bajo registrado"),
      if (identical(r$historial, "más alto registrado"))
        span(class = "pildora sube", "Precio más alto registrado"),
      if (isTRUE(r$promocion == 1)) span(class = "pildora", icon("tag", class = "fa-xs"), "Promoción"),
      if (identical(r$disponibilidad, "agotado")) span(class = "pildora agotado", "Agotado en el sitio")
    )
    div(
      div(class = paste("fila-tienda", if (mejor) "mejor"),
          div(insignia(r$id_comercio),
              div(class = "unitario", cop_unidad(r$precio_unitario, r$unidad_norm))),
          div(style = "text-align:right",
              tags$a(class = "precio", href = r$url, target = "_blank", rel = "noopener",
                     style = "color:inherit;text-decoration:none", title = "Ver el anuncio en el sitio",
                     cop(r$precio)),
              if (mejor) div(class = "mejor-precio", icon("trophy", class = "fa-xs"), " Mejor precio")
              else div(class = "dif", paste0("+", cop(r$sobrecosto))))),
      if (length(Filter(Negate(is.null), notas)) > 0) div(class = "notas-tienda", notas)
    )
  })
  div(class = "tarjeta-comp",
      div(class = "encabezado",
          if (!is.na(ahorro) && ahorro > 0) span(class = "ahorro", paste0("-", ahorro, " %"))
          else span(class = "pildora", "Mismo precio"),
          span(class = "tiendas", icon("store", class = "fa-xs"), paste(nrow(d), "comercios"))),
      div(class = "nombre", d$producto[1]),
      filas)
}

tarjetas_comparacion <- function(d) {
  if (nrow(d) == 0) return(mensaje_vacio("Ningún producto comparable cumple los filtros."))
  layout_column_wrap(width = "290px", gap = "1rem", fill = FALSE,
                     !!!unname(lapply(split(d, d$id_producto), tarjeta_comparable)))
}

# -----------------------------------------------------------------------------
# Tarjetas de indicadores: cada una con su valor, unidad, detalle por comercio
# y periodo o ejecución a la que corresponde (sección 7.3)
# -----------------------------------------------------------------------------
detalle_comercios <- function(nombres, textos) {
  ids <- names(COMERCIOS)[match(nombres, COMERCIOS)]
  tagList(lapply(seq_along(ids), function(i)
    div(style = "display:flex;justify-content:space-between;gap:.5rem;margin-top:.15rem",
        span(style = sprintf("color:%s;font-weight:700;white-space:nowrap", COLOR_COMERCIO[[ids[i]]]), nombres[i]),
        span(style = "text-align:right", textos[i]))))
}

caja_indicador <- function(titulo, valor, unidad, periodo, icono, detalle = NULL) {
  # Las fechas del periodo (AAAA-MM-DD) se muestran como "14 nov 2026"
  fechas <- regmatches(periodo, gregexpr("\\d{4}-\\d{2}-\\d{2}", periodo))[[1]]
  for (f in fechas) periodo <- sub(f, fecha_corta(f), periodo, fixed = TRUE)
  value_box(
    title = tagList(span(class = "icono-vb", icon(icono)), titulo),
    value = tags$span(valor, tags$small(style = "font-size:.95rem;font-weight:600;color:#6B7280", unidad)),
    theme = value_box_theme(bg = "#FFFFFF", fg = COLOR_TEXTO),
    div(class = "vb-detalle", detalle),
    div(class = "vb-periodo", icon("calendar", class = "fa-xs"), " ", periodo)
  )
}

cajas_indicadores <- function(ind) {
  valor <- function(x) if (length(x) == 0) NA else x
  p   <- ind$productos_por_comercio
  o   <- ind$observaciones_por_comercio
  u   <- ind$ultima_ejecucion
  pr  <- ind$promocion
  me  <- ind$mediana_precio
  ah  <- ind$ahorro_maximo
  ca  <- ind$cambios_precio
  list(
    caja_indicador("Productos con precio", numero(sum(p$tabla$con_precio)), "productos", p$periodo,
                   "boxes-stacked", detalle_comercios(p$tabla$comercio, numero(p$tabla$con_precio))),
    caja_indicador("Observaciones de precio", numero(sum(o$tabla$observaciones)), "observaciones",
                   o$periodo, "database",
                   detalle_comercios(o$tabla$comercio,
                                     sprintf("%s en %s ejec.", numero(o$tabla$observaciones), o$tabla$ejecuciones))),
    caja_indicador("Última ejecución", if (nrow(u$tabla)) fecha_corta(max(u$tabla$fecha)) else "—",
                   "", u$periodo, "rotate",
                   detalle_comercios(u$tabla$comercio, paste(fecha_corta(u$tabla$fecha), "·", u$tabla$estado))),
    caja_indicador("Productos en promoción", porcentaje(valor(pr$valor)), "", pr$periodo, "tags",
                   if (nrow(pr$tabla) && !is.na(valor(pr$valor))) sprintf("%s de %s productos con precio", numero(pr$tabla$en_promocion),
                                               numero(pr$tabla$productos))),
    caja_indicador("Precio mediano", cop(valor(me$valor)), "COP", me$periodo, "scale-balanced",
                   if (nrow(me$tabla)) sprintf("La mitad de los productos cuesta menos de %s; rango %s a %s",
                                               cop(me$valor), cop(me$tabla$minimo), cop(me$tabla$maximo))),
    caja_indicador("Mayor ahorro entre comercios", cop(ah$valor), "COP",
                   if (is.na(ah$periodo)) "—" else ah$periodo, "piggy-bank",
                   if (nrow(ah$tabla)) tagList(
                     div(strong(ah$tabla$producto)),
                     div(sprintf("%s más barato en %s que en %s", porcentaje(ah$tabla$porcentaje),
                                 ah$tabla$mas_barato, ah$tabla$mas_caro)))),
    caja_indicador("Cambios de precio", numero(valor(ca$valor)), "cambios",
                   if (is.na(ca$periodo)) "No hay dos ejecuciones que comparar con estos filtros" else ca$periodo,
                   "arrow-trend-up",
                   if (nrow(ca$tabla) && !is.na(valor(ca$valor)))
                     sprintf("%s subieron · %s bajaron, en la última ejecución frente a la anterior",
                             numero(ca$tabla$subidas), numero(ca$tabla$bajadas)))
  )
}

# -----------------------------------------------------------------------------
# Canasta: total por comercio y compra combinada
# -----------------------------------------------------------------------------
resultado_canasta <- function(k) {
  pc <- k$por_comercio
  rs <- k$resumen
  mejor_total <- rs$mejor_total_un_comercio
  tarjetas <- lapply(seq_len(nrow(pc)), function(i) {
    r <- pc[i, ]
    completo <- !is.na(r$total)
    es_mejor <- completo && !is.na(mejor_total) && r$total == mejor_total
    div(class = "tarjeta-comp",
        div(class = "encabezado", insignia(r$id_comercio),
            if (es_mejor) span(class = "ahorro", "Más barato") else NULL),
        if (completo) tagList(
          div(class = "titular", style = "font-size:1.8rem", cop(r$total)),
          div(class = "tiendas", if (es_mejor) "Comprando todo aquí"
              else paste0(cop(r$total - mejor_total), " más que el comercio más barato")))
        else tagList(
          div(class = "titular", style = "font-size:1.2rem;color:#6B7280", "Sin total"),
          div(class = "tiendas", sprintf("Falta%s: %s. No se muestra un total incompleto.",
                                         if (grepl(",", r$faltantes)) "n" else "", r$faltantes))))
  })
  combinado <- if (is.na(rs$total_combinado)) {
    div(class = "tarjeta-comp", div(class = "nombre", "Comprando cada producto donde es más barato"),
        div(class = "tiendas", "No se puede calcular: algún producto no tiene precio en ningún comercio."))
  } else {
    div(class = "tarjeta-comp", style = "box-shadow: inset 0 0 0 2px #D9480F",
        div(class = "etiqueta-seccion", "Compra combinada"),
        div(class = "nombre", "Comprando cada producto donde es más barato"),
        div(class = "titular", style = "font-size:1.8rem", cop(rs$total_combinado)),
        div(class = "tiendas",
            if (is.na(rs$ahorro_combinado)) "Ningún comercio tiene todos los productos."
            else if (rs$ahorro_combinado > 0)
              sprintf("Ahorra %s frente a comprar todo en %s (%s).", cop(rs$ahorro_combinado),
                      rs$mejor_comercio, cop(rs$mejor_total_un_comercio))
            else sprintf("Igual que comprar todo en %s: no hay ahorro al repartir la compra.",
                         rs$mejor_comercio)))
  }
  tagList(
    layout_column_wrap(width = "230px", gap = "1rem", fill = FALSE, !!!tarjetas, combinado),
    div(class = "aviso-canasta mt-3", icon("circle-info"), " ", k$advertencia,
        sprintf(" Precios de la corrida del %s.", fecha_corta(k$fecha)))
  )
}
