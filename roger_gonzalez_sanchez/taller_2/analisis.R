# analisis.R


# Un producto se puede comprar si se observó con precio y no estaba agotado
se_puede_comprar <- function(precios) {
  !is.na(precios$precio) & precios$estado %in% c("disponible", "sin_dato")
}

# precios:    data.frame con id_comparable, comparable, comercio, precio, estado
# cantidades: data.frame con id_comparable y cantidad
calcular_canasta <- function(precios, cantidades) {
  precios$compra <- se_puede_comprar(precios)
  precios <- merge(precios, cantidades, by = "id_comparable")
  comercios <- sort(unique(precios$comercio))
  productos <- unique(precios[, c("id_comparable", "comparable", "cantidad")])

  # 1. Costo de la canasta en cada comercio (solo si tiene todo)
  por_comercio <- do.call(rbind, lapply(comercios, function(com) {
    p <- precios[precios$comercio == com & precios$compra, ]
    faltan <- setdiff(productos$comparable, p$comparable)
    data.frame(
      comercio = com,
      completa = length(faltan) == 0,
      total = if (length(faltan) == 0) sum(p$precio * p$cantidad) else NA_real_,
      faltan = if (length(faltan) == 0) "" else paste(sort(faltan), collapse = ", ")
    )
  }))

  # 2. Comprando cada producto donde es más barato
  detalle <- do.call(rbind, lapply(seq_len(nrow(productos)), function(i) {
    p <- precios[precios$id_comparable == productos$id_comparable[i] & precios$compra, ]
    if (nrow(p) == 0) {
      return(data.frame(comparable = productos$comparable[i], cantidad = productos$cantidad[i],
                        precio_min = NA_real_, donde = "No disponible en ningún comercio",
                        subtotal = NA_real_))
    }
    minimo <- min(p$precio)
    data.frame(comparable = productos$comparable[i], cantidad = productos$cantidad[i],
               precio_min = minimo,
               donde = paste(sort(p$comercio[p$precio == minimo]), collapse = " / "),
               subtotal = minimo * productos$cantidad[i])
  }))

  costo_minimo <- if (anyNA(detalle$subtotal)) NA_real_ else sum(detalle$subtotal)

  # 3. Ahorro frente a comprar todo en un solo comercio
  completos <- por_comercio[por_comercio$completa, ]
  if (nrow(completos) > 0 && !is.na(costo_minimo)) {
    mejor_total <- min(completos$total)
    mejor_comercio <- paste(sort(completos$comercio[completos$total == mejor_total]), collapse = " / ")
    ahorro <- mejor_total - costo_minimo
    por_comercio$ahorro_vs_minimo <- ifelse(por_comercio$completa,
                                            por_comercio$total - costo_minimo, NA_real_)
  } else {
    mejor_total <- NA_real_
    mejor_comercio <- NA_character_
    ahorro <- NA_real_
    por_comercio$ahorro_vs_minimo <- NA_real_
  }

  list(por_comercio = por_comercio, detalle = detalle, costo_minimo = costo_minimo,
       mejor_comercio = mejor_comercio, mejor_total = mejor_total, ahorro = ahorro)
}
