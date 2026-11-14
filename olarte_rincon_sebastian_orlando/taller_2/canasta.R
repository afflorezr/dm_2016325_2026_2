# Taller 2 de Mineria de Datos - calculo de canastas con datos reales.
# Solo lectura. No crea tablas, no altera SQLite ni ejecuta scraping.
# Las cantidades son NUMEROS DE ENVASES de productos homologados.

listar_ejecuciones_canasta_db <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT ejecucion_id,
           MIN(substr(fecha_hora_inicio, 1, 19)) AS fecha_hora,
           COUNT(DISTINCT comercio_id) AS comercios
    FROM ejecuciones
    GROUP BY ejecucion_id
    ORDER BY fecha_hora DESC, ejecucion_id DESC
  ")
}

listar_productos_canasta_db <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT producto_comun_id, producto_comun
    FROM productos_comunes
    ORDER BY producto_comun_id
  ")
}

calcular_canasta_db <- function(con, ejecucion_id, cantidades) {
  if (!DBI::dbIsValid(con)) stop("Conexion SQLite invalida")
  if (length(ejecucion_id) != 1L || is.na(ejecucion_id) ||
      !nzchar(as.character(ejecucion_id)) || nchar(ejecucion_id) > 150L) {
    stop("Seleccione una ejecucion valida")
  }
  if (is.null(names(cantidades)) || !length(cantidades) ||
      anyNA(names(cantidades)) || any(!nzchar(names(cantidades))) ||
      anyDuplicated(names(cantidades))) {
    stop("Indique cantidades con nombres P01, P02, etc., sin repetir productos")
  }

  cantidades_num <- suppressWarnings(as.numeric(cantidades))
  if (anyNA(cantidades_num) ||
      any(!is.finite(cantidades_num)) ||
      any(cantidades_num < 1 | cantidades_num > 100) ||
      any(cantidades_num != floor(cantidades_num))) {
    stop("Cada cantidad debe ser un entero entre 1 y 100 envases")
  }

  productos <- listar_productos_canasta_db(con)
  ids <- names(cantidades)
  if (!length(ids) || length(ids) > nrow(productos) ||
      !all(ids %in% productos$producto_comun_id)) {
    stop("Hay productos no homologados en la canasta")
  }
  ejecuciones <- listar_ejecuciones_canasta_db(con)
  if (!(as.character(ejecucion_id) %in% ejecuciones$ejecucion_id)) {
    stop("La ejecucion seleccionada no figura en SQLite")
  }
  cantidades_num <- setNames(cantidades_num, ids)
  productos_seleccionados <- productos[match(ids, productos$producto_comun_id), , drop = FALSE]
  productos_seleccionados$cantidad <- as.integer(cantidades_num)

  # Se selecciona UN precio valido por producto y comercio dentro de LA MISMA ejecucion.
  # Si existieran anuncios duplicados para un comparable, se utiliza el menor
  # precio documentado, con desempate reproducible por fecha e identificador.
  marcadores <- paste(rep("?", length(ids)), collapse = ", ")
  consulta <- paste0("
    WITH ofertas AS (
      SELECT o.ejecucion_id, o.comercio_id, c.nombre AS comercio,
             a.producto_comun_id, o.precio_cop, o.fecha_hora_consulta,
             o.observacion_id, a.producto_original,
             ROW_NUMBER() OVER (
               PARTITION BY o.comercio_id, a.producto_comun_id
               ORDER BY o.precio_cop ASC,
                        o.fecha_hora_consulta DESC, o.observacion_id DESC
             ) AS posicion
      FROM observaciones o
      JOIN anuncios a ON a.ejecucion_id = o.ejecucion_id
          AND a.comercio_id = o.comercio_id
          AND a.producto_comercio_id = o.producto_comercio_id
      JOIN comercios c ON c.comercio_id = o.comercio_id
      WHERE o.ejecucion_id = ?
        AND a.comparable = 1 AND a.incluido_categoria = 1
        AND o.precio_cop > 0
        AND COALESCE(o.estado_validacion, '') <> 'rechazada'
        AND COALESCE(lower(o.estado_disponibilidad), '')
            NOT IN ('agotado', 'no_observado')
        AND a.producto_comun_id IN (", marcadores, ")
    )
    SELECT ejecucion_id, comercio_id, comercio, producto_comun_id,
           precio_cop, fecha_hora_consulta, observacion_id, producto_original
    FROM ofertas
    WHERE posicion = 1
    ORDER BY comercio, producto_comun_id
  ")
  precios <- DBI::dbGetQuery(con, consulta,
    params = c(list(as.character(ejecucion_id)), as.list(ids)))
  comercios <- DBI::dbGetQuery(con,
    "SELECT comercio_id, nombre AS comercio FROM comercios ORDER BY nombre")
  if (!nrow(comercios)) stop("No hay comercios registrados")

  resumen <- lapply(seq_len(nrow(comercios)), function(i) {
    comercio_actual <- comercios$comercio[i]
    disponibles <- precios[precios$comercio_id == comercios$comercio_id[i], , drop = FALSE]
    idx <- match(ids, disponibles$producto_comun_id)
    ausentes <- productos_seleccionados$producto_comun[is.na(idx)]
    completa <- length(ausentes) == 0L
    data.frame(
      comercio = comercio_actual,
      estado = if (completa) "Completa" else "Incompleta",
      productos_encontrados = sum(!is.na(idx)),
      productos_requeridos = length(ids),
      costo_total_cop = if (completa) sum(disponibles$precio_cop[idx] * cantidades_num) else NA_real_,
      productos_faltantes = if (completa) "" else paste(ausentes, collapse = "; "),
      stringsAsFactors = FALSE
    )
  })
  por_comercio <- do.call(rbind, resumen)
  rownames(por_comercio) <- NULL

  faltantes_globales <- productos_seleccionados$producto_comun[
    !ids %in% precios$producto_comun_id]
  detalle_mixto <- data.frame()
  costo_mixto_cop <- NA_real_

  if (!length(faltantes_globales)) {
    partes <- lapply(seq_along(ids), function(i) {
      ofertas <- precios[precios$producto_comun_id == ids[i], , drop = FALSE]
      ofertas <- ofertas[order(ofertas$precio_cop, ofertas$comercio), , drop = FALSE]
      mejor <- ofertas[1L, , drop = FALSE]
      minimo <- mejor$precio_cop[1L]
      empatados <- ofertas$comercio[abs(ofertas$precio_cop - minimo) < 0.000001]
      data.frame(
        producto_comun_id = ids[i],
        producto = productos_seleccionados$producto_comun[i],
        cantidad = cantidades_num[i],
        comercio_elegido = mejor$comercio[1L],
        precio_envase_cop = minimo,
        subtotal_cop = minimo * cantidades_num[i],
        empate = length(empatados) > 1L,
        comercios_empatados = paste(empatados, collapse = "; "),
        stringsAsFactors = FALSE
      )
    })
    detalle_mixto <- do.call(rbind, partes)
    rownames(detalle_mixto) <- NULL
    costo_mixto_cop <- sum(detalle_mixto$subtotal_cop)
  }

  completos <- por_comercio[!is.na(por_comercio$costo_total_cop), , drop = FALSE]
  mejor_comercio <- NA_character_
  mejor_total_cop <- NA_real_
  ahorro_cop <- NA_real_
  ahorro_pct <- NA_real_
  if (nrow(completos)) {
    completos <- completos[order(completos$costo_total_cop, completos$comercio), , drop = FALSE]
    mejor_comercio <- completos$comercio[1L]
    mejor_total_cop <- completos$costo_total_cop[1L]
    if (!is.na(costo_mixto_cop)) {
      ahorro_cop <- max(0, mejor_total_cop - costo_mixto_cop)
      ahorro_pct <- if (mejor_total_cop > 0) 100 * ahorro_cop / mejor_total_cop else NA_real_
    }
  }

  mensaje <- if (length(faltantes_globales)) {
    paste0("No se calcula la canasta mixta: faltan los productos ",
           paste(faltantes_globales, collapse = "; "))
  } else if (!nrow(completos)) {
    "Ningun comercio ofrece la canasta completa. No existe un total de una sola tienda contra el cual calcular el ahorro."
  } else {
    "Canasta calculada con los precios observados en una sola ejecucion. La disponibilidad actual no esta garantizada."
  }

  list(
    ejecucion_id = as.character(ejecucion_id),
    productos = productos_seleccionados,
    por_comercio = por_comercio,
    detalle_mixto = detalle_mixto,
    faltantes_globales = faltantes_globales,
    costo_mixto_cop = costo_mixto_cop,
    mejor_comercio_completo = mejor_comercio,
    mejor_total_cop = mejor_total_cop,
    ahorro_cop = ahorro_cop,
    ahorro_pct = ahorro_pct,
    mensaje = mensaje,
    advertencia = paste(
      "Los precios corresponden a la captura seleccionada;",
      "no incluyen envio, minimos de compra ni condiciones de promociones.",
      "La existencia real no se confirma cuando el sitio no da evidencia de disponibilidad."
    )
  )
}
