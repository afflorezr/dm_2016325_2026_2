# =============================================================================
# db.R
# Capa de acceso a datos de la aplicación. Toda la interfaz pasa por aquí:
# no hay SQL en app.R. Las consultas son parametrizadas y los filtros se
# resuelven con SQL sobre SQLite, nunca filtrando la tabla completa en memoria.
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

ruta_db <- function() "comparador_precios.sqlite"

conectar <- function(ruta = ruta_db()) {
  if (!file.exists(ruta)) stop("No se encontró la base: ", ruta)
  con <- dbConnect(SQLite(), ruta)
  dbExecute(con, "PRAGMA busy_timeout = 8000")
  dbExecute(con, "PRAGMA foreign_keys = ON")
  dbGetQuery(con, "PRAGMA journal_mode = WAL")
  con
}

desconectar <- function(con) {
  if (!is.null(con) && dbIsValid(con)) dbDisconnect(con)
  invisible(NULL)
}

# -----------------------------------------------------------------------------
# Catálogos para los controles de la interfaz
# -----------------------------------------------------------------------------

listar_comercios <- function(con) {
  dbGetQuery(con, "
    SELECT c.id_comercio, c.nombre, c.activo, c.motivo_estado,
           COUNT(o.id_observacion) AS n_observaciones
      FROM comercios c
      LEFT JOIN observaciones o ON o.id_comercio = c.id_comercio
     GROUP BY c.id_comercio
     ORDER BY c.activo DESC, c.nombre")
}

listar_ejecuciones <- function(con, solo_completas = FALSE) {
  sql <- "
    SELECT e.id_ejecucion, e.fecha_inicio, e.fecha_fin, e.modo, e.estado,
           e.n_registros, e.n_obs_comparables, e.n_productos_comparables,
           e.n_comercios,
           (SELECT GROUP_CONCAT(nombre, ', ')
              FROM (SELECT DISTINCT c.nombre
                      FROM observaciones o
                      JOIN comercios c ON c.id_comercio = o.id_comercio
                     WHERE o.id_ejecucion = e.id_ejecucion
                     ORDER BY c.nombre)) AS comercios
      FROM ejecuciones e
     WHERE e.estado IN ('completa', 'parcial')"
  if (solo_completas) sql <- paste(sql, "AND e.estado = 'completa'")
  sql <- paste(sql, "ORDER BY e.fecha_inicio DESC")
  dbGetQuery(con, sql)
}

ultima_ejecucion <- function(con) {
  filas <- dbGetQuery(con, "
    SELECT id_ejecucion
      FROM ejecuciones
     WHERE estado = 'completa' AND n_productos_comparables >= 8
     ORDER BY fecha_inicio DESC
     LIMIT 1")
  if (nrow(filas) == 0) return(NA_character_)
  filas$id_ejecucion[1]
}

opciones_filtros <- function(con, id_ejecucion) {
  dbGetQuery(con, "
    SELECT DISTINCT subcategoria, marca
      FROM observaciones
     WHERE id_ejecucion = ?
     ORDER BY subcategoria, marca", params = list(id_ejecucion))
}

rango_precios <- function(con, id_ejecucion) {
  x <- dbGetQuery(con, "
    SELECT MIN(precio_cop) AS minimo, MAX(precio_cop) AS maximo
      FROM observaciones
     WHERE id_ejecucion = ? AND precio_cop IS NOT NULL", params = list(id_ejecucion))
  if (is.na(x$maximo)) return(c(0, 100000))
  c(0, ceiling(max(x$maximo) / 1000) * 1000)
}

productos_comparables <- function(con, solo_vigentes = TRUE) {
  sql <- "SELECT * FROM v_comparables"
  if (solo_vigentes) sql <- paste(sql, "WHERE vigente = 1")
  sql <- paste(sql, "ORDER BY subcategoria, nombre_canonico")
  dbGetQuery(con, sql)
}

# -----------------------------------------------------------------------------
# Filtros reutilizables (siempre parametrizados)
# -----------------------------------------------------------------------------

marcadores <- function(n) paste(rep("?", n), collapse = ", ")

# Valida el texto libre antes de usarlo en una consulta: longitud y caracteres.
validar_texto <- function(x, maximo = 60) {
  if (is.null(x) || length(x) == 0) return("")
  x <- trimws(as.character(x)[1])
  if (is.na(x) || nchar(x) > maximo) return("")
  if (grepl("[[:cntrl:]]", x)) return("")
  if (!grepl("^[[:alnum:]áéíóúÁÉÍÓÚñÑüÜ .,%-]*$", x)) return("")
  x <- gsub("[%_]", " ", x)
  trimws(gsub("\\s+", " ", x))
}

texto_uno <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) "" else as.character(x[1])
}

construir_filtros <- function(filtros, alias = "o") {
  filtros$subcategoria <- texto_uno(filtros$subcategoria)
  filtros$marca <- texto_uno(filtros$marca)
  filtros$buscar <- validar_texto(texto_uno(filtros$buscar))
  condiciones <- c("1 = 1")
  params <- list()

  if (length(filtros$comercios) > 0) {
    condiciones <- c(condiciones,
                     sprintf("%s.id_comercio IN (%s)", alias, marcadores(length(filtros$comercios))))
    params <- c(params, as.list(filtros$comercios))
  }
  if (nzchar(filtros$subcategoria)) {
    condiciones <- c(condiciones, sprintf("%s.subcategoria = ?", alias))
    params <- c(params, list(filtros$subcategoria[1]))
  }
  if (nzchar(filtros$marca)) {
    condiciones <- c(condiciones, sprintf("%s.marca = ?", alias))
    params <- c(params, list(filtros$marca[1]))
  }
  if (!is.null(filtros$precio_min) && is.finite(filtros$precio_min)) {
    condiciones <- c(condiciones, sprintf("%s.precio_cop >= ?", alias))
    params <- c(params, list(filtros$precio_min))
  }
  if (!is.null(filtros$precio_max) && is.finite(filtros$precio_max)) {
    condiciones <- c(condiciones, sprintf("%s.precio_cop <= ?", alias))
    params <- c(params, list(filtros$precio_max))
  }
  if (isTRUE(filtros$solo_promo)) {
    condiciones <- c(condiciones, sprintf("%s.es_promocion = 1", alias))
  }
  if (isTRUE(filtros$solo_comparables)) {
    condiciones <- c(condiciones, sprintf("%s.es_comparable = 1", alias))
  }
  if (nzchar(filtros$buscar)) {
    condiciones <- c(condiciones,
                     sprintf("(%s.texto_original LIKE ? OR p.nombre_canonico LIKE ?)", alias))
    patron <- paste0("%", filtros$buscar, "%")
    params <- c(params, list(patron, patron))
  }

  list(where = paste(condiciones, collapse = " AND "), params = params)
}

# -----------------------------------------------------------------------------
# Indicadores
# -----------------------------------------------------------------------------

kpis <- function(con, id_ejecucion, filtros) {
  f <- construir_filtros(filtros)
  base <- sprintf("
    FROM observaciones o
    LEFT JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun
   WHERE o.id_ejecucion = ? AND %s", f$where)
  params <- c(list(id_ejecucion), f$params)

  totales <- dbGetQuery(con, sprintf("
    SELECT COUNT(*) AS observaciones,
           COUNT(DISTINCT o.id_producto_comun) AS productos,
           COUNT(DISTINCT o.id_comercio) AS comercios,
           ROUND(100.0 * SUM(o.es_promocion) / NULLIF(COUNT(*), 0), 1) AS pct_promocion,
           SUM(CASE WHEN o.estado_disponibilidad = 'agotado' THEN 1 ELSE 0 END) AS agotados
    %s", base), params = params)

  mediana <- dbGetQuery(con, sprintf("
    WITH x AS (
      SELECT o.precio_cop,
             ROW_NUMBER() OVER (ORDER BY o.precio_cop) AS rn,
             COUNT(*) OVER () AS n
      %s AND o.precio_cop IS NOT NULL
    )
    SELECT ROUND(AVG(precio_cop), 0) AS mediana
      FROM x
     WHERE rn IN ((n + 1) / 2, (n + 2) / 2)", base), params = params)

  ahorro <- dbGetQuery(con, sprintf("
    SELECT a.ahorro_pct, a.ahorro_cop
      FROM v_ahorro_presentacion a
      JOIN productos_comparables p ON p.id_producto_comun = a.id_producto_comun
     WHERE a.id_ejecucion = ? AND p.vigente = 1 AND a.n_comercios = 3
       %s
     ORDER BY a.ahorro_pct DESC
     LIMIT 1", if (nzchar(texto_uno(filtros$subcategoria))) "AND p.subcategoria = ?" else ""),
    params = c(list(id_ejecucion), if (nzchar(texto_uno(filtros$subcategoria))) list(texto_uno(filtros$subcategoria)) else list()))
  if (nrow(ahorro) == 0) ahorro <- data.frame(ahorro_pct = NA_real_, ahorro_cop = NA_real_)

  ejec <- dbGetQuery(con, "
    SELECT e.id_ejecucion, e.fecha_inicio, e.estado, e.modo,
           r.n_observaciones_comparables
      FROM ejecuciones e
      LEFT JOIN v_resumen_ejecucion r ON r.id_ejecucion = e.id_ejecucion
     WHERE e.id_ejecucion = ?", params = list(id_ejecucion))
  anterior <- ejecucion_anterior_misma_cobertura(con, id_ejecucion)
  cambios <- if (is.na(anterior)) 0L else as.integer(dbGetQuery(con, "
    SELECT COUNT(*) AS n FROM v_cambios_precio
     WHERE ejecucion_anterior = ? AND ejecucion_actual = ?
       AND ABS(cambio_pct) >= 1", params = list(anterior, id_ejecucion))$n[1])

  pct_promo <- if (is.na(totales$pct_promocion)) "—" else paste0(totales$pct_promocion, " %")
  mediana_txt <- if (is.na(mediana$mediana)) "—" else paste0("$ ", format(mediana$mediana, big.mark = ".", decimal.mark = ","))
  ahorro_txt <- if (is.na(ahorro$ahorro_pct) || totales$observaciones == 0) "—" else paste0(ahorro$ahorro_pct, " %")
  ahorro_det <- if (is.na(ahorro$ahorro_cop) || totales$observaciones == 0) "sin datos para comparar" else paste0("$ ", format(ahorro$ahorro_cop, big.mark = ".", decimal.mark = ","), " entre comercios")

  data.frame(
    indicador = c("Presentaciones comparables", "Observaciones", "Comercios",
                  "En promoción", "Precio mediano", "Ahorro máximo",
                  "Cambios de precio", "Última ejecución"),
    valor = c(
      format(totales$productos, big.mark = ".", decimal.mark = ","),
      format(totales$observaciones, big.mark = ".", decimal.mark = ","),
      totales$comercios, pct_promo, mediana_txt, ahorro_txt, cambios,
      substr(ejec$fecha_inicio, 1, 16)
    ),
    detalle = c(
      "productos canónicos distintos en el filtro",
      "anuncios con precio en el filtro actual",
      "con datos en la ejecución",
      paste0(totales$agotados, " observaciones agotadas"),
      "COP por unidad vendida", ahorro_det,
      "variaciones de al menos 1 % frente a la ejecución anterior",
      paste0("estado ", ejec$estado[1], " · modo ", ejec$modo[1])
    ),
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# Tabla de productos y precios
# -----------------------------------------------------------------------------

productos <- function(con, id_ejecucion, filtros) {
  f <- construir_filtros(filtros)
  dbGetQuery(con, sprintf("
    SELECT o.id_observacion, o.id_comercio, c.nombre AS comercio,
           o.id_producto_comun,
           COALESCE(p.nombre_canonico, o.texto_original) AS producto,
           o.texto_original, o.marca, o.subcategoria,
           o.contenido_total, o.unidad_normalizada,
           o.precio_cop, o.precio_lista_cop, o.es_promocion, o.descuento_pct,
           o.estado_disponibilidad, o.precio_por_unidad, o.unidad_precio,
           o.fecha_consulta, o.url_producto, o.es_comparable
      FROM observaciones o
      JOIN comercios c ON c.id_comercio = o.id_comercio
      LEFT JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun
     WHERE o.id_ejecucion = ? AND %s
     ORDER BY o.es_comparable DESC, o.precio_cop IS NULL, o.precio_cop ASC", f$where),
    params = c(list(id_ejecucion), f$params))
}

# Distribución de precios por comercio en intervalos de COP, calculada en SQL.
distribucion_precios <- function(con, id_ejecucion, filtros, ancho = 5000) {
  f <- construir_filtros(filtros)
  dbGetQuery(con, sprintf("
    SELECT c.nombre AS comercio,
           CAST(o.precio_cop / ? AS INTEGER) * ? AS desde,
           COUNT(*) AS n
      FROM observaciones o
      JOIN comercios c ON c.id_comercio = o.id_comercio
      LEFT JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun
     WHERE o.id_ejecucion = ? AND o.precio_cop IS NOT NULL AND o.estado_disponibilidad = 'disponible'
       AND %s
     GROUP BY c.nombre, desde
     ORDER BY desde", f$where),
    params = c(list(ancho, ancho, id_ejecucion), f$params))
}

precio_unidad <- function(con, id_ejecucion, id_producto = NULL, unidades = NULL) {
  sql <- "
    SELECT u.*
      FROM v_precio_unitario u
     WHERE u.id_ejecucion = ?"
  params <- list(id_ejecucion)
  if (!is.null(id_producto) && nzchar(id_producto)) {
    sql <- paste(sql, "AND u.id_producto_comun = ?")
    params <- c(params, list(id_producto))
  }
  if (!is.null(unidades) && length(unidades) > 0) {
    sql <- paste(sql, sprintf("AND u.unidad_normalizada IN (%s)", marcadores(length(unidades))))
    params <- c(params, as.list(unidades))
  }
  sql <- paste(sql, "ORDER BY u.unidad_normalizada, u.precio_por_unidad")
  dbGetQuery(con, sql, params = params)
}

serie_precio <- function(con, id_producto, comercios = NULL) {
  sql <- "
    SELECT v.fecha_consulta, v.comercio, v.precio_cop, v.es_promocion, v.estado_disponibilidad
      FROM v_observaciones v
     WHERE v.id_producto_comun = ? AND v.es_comparable = 1 AND v.precio_cop IS NOT NULL"
  params <- list(id_producto)
  if (length(comercios) > 0) {
    sql <- paste(sql, sprintf("AND v.id_comercio IN (%s)", marcadores(length(comercios))))
    params <- c(params, as.list(comercios))
  }
  sql <- paste(sql, "ORDER BY v.fecha_consulta")
  dbGetQuery(con, sql, params = params)
}

# -----------------------------------------------------------------------------
# Cambios de precio entre dos ejecuciones
# -----------------------------------------------------------------------------

ejecucion_anterior <- function(con, id_ejecucion) {
  x <- dbGetQuery(con, "
    SELECT id_ejecucion
      FROM ejecuciones
     WHERE fecha_inicio < (SELECT fecha_inicio FROM ejecuciones WHERE id_ejecucion = ?)
       AND estado IN ('completa', 'parcial')
     ORDER BY fecha_inicio DESC
     LIMIT 1", params = list(id_ejecucion))
  if (nrow(x) == 0) NA_character_ else x$id_ejecucion[1]
}

# Ejecución anterior con exactamente los mismos comercios. Evita comparar
# precios entre surtidos distintos (por ejemplo, antes y después de reemplazar
# un comercio bloqueado).
ejecucion_anterior_misma_cobertura <- function(con, id_ejecucion) {
  x <- dbGetQuery(con, "
    WITH actual AS (
      SELECT id_comercio FROM observaciones WHERE id_ejecucion = ? GROUP BY id_comercio
    ),
    candidatas AS (
      SELECT e.id_ejecucion, e.fecha_inicio,
             (SELECT GROUP_CONCAT(id_comercio) FROM actual) AS cobertura_actual,
             (SELECT GROUP_CONCAT(id_comercio)
                FROM (SELECT id_comercio FROM observaciones
                       WHERE id_ejecucion = e.id_ejecucion GROUP BY id_comercio)) AS cobertura
        FROM ejecuciones e
       WHERE e.fecha_inicio < (SELECT fecha_inicio FROM ejecuciones WHERE id_ejecucion = ?)
         AND e.estado IN ('completa', 'parcial')
    )
    SELECT id_ejecucion FROM candidatas
     WHERE cobertura = cobertura_actual
     ORDER BY fecha_inicio DESC LIMIT 1", params = list(id_ejecucion, id_ejecucion))
  if (nrow(x) == 0) NA_character_ else x$id_ejecucion[1]
}

cambios_entre <- function(con, ejecucion_anterior, ejecucion_actual,
                          umbral = 5, solo_comparables = TRUE) {
  cambios <- dbGetQuery(con, "
    SELECT ejecucion_anterior, ejecucion_actual, id_comercio, comercio,
           sku_comercio, id_producto_comun, nombre_canonico, texto_original,
           precio_anterior, precio_actual, cambio_cop, cambio_pct,
           fecha_anterior, fecha_actual
      FROM v_cambios_precio
     WHERE ejecucion_anterior = ? AND ejecucion_actual = ?
       AND ABS(cambio_pct) >= ? AND ABS(cambio_cop) >= 0.5",
    params = list(ejecucion_anterior, ejecucion_actual, umbral))

  nuevos <- dbGetQuery(con, "
    SELECT b.id_comercio, c.nombre AS comercio, b.sku_comercio, b.id_producto_comun,
           p.nombre_canonico, b.texto_original,
           NULL AS precio_anterior, b.precio_cop AS precio_actual,
           b.precio_cop AS cambio_cop, NULL AS cambio_pct,
           NULL AS fecha_anterior, b.fecha_consulta AS fecha_actual
      FROM observaciones b
      JOIN comercios c ON c.id_comercio = b.id_comercio
      LEFT JOIN productos_comparables p ON p.id_producto_comun = b.id_producto_comun
     WHERE b.id_ejecucion = ? AND b.precio_cop IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM observaciones a
          WHERE a.id_ejecucion = ? AND a.id_comercio = b.id_comercio
            AND a.sku_comercio = b.sku_comercio)",
    params = list(ejecucion_actual, ejecucion_anterior))

  retirados <- dbGetQuery(con, "
    SELECT a.id_comercio, c.nombre AS comercio, a.sku_comercio, a.id_producto_comun,
           p.nombre_canonico, a.texto_original,
           a.precio_cop AS precio_anterior, NULL AS precio_actual,
           NULL AS cambio_cop, NULL AS cambio_pct,
           a.fecha_consulta AS fecha_anterior, NULL AS fecha_actual
      FROM observaciones a
      JOIN comercios c ON c.id_comercio = a.id_comercio
      LEFT JOIN productos_comparables p ON p.id_producto_comun = a.id_producto_comun
     WHERE a.id_ejecucion = ? AND a.precio_cop IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM observaciones b
          WHERE b.id_ejecucion = ? AND b.id_comercio = a.id_comercio
            AND b.sku_comercio = a.sku_comercio)",
    params = list(ejecucion_anterior, ejecucion_actual))

  if (solo_comparables) {
    comparables <- dbGetQuery(con, "
      SELECT DISTINCT id_producto_comun FROM observaciones
       WHERE id_ejecucion = ? AND es_comparable = 1", params = list(ejecucion_actual))$id_producto_comun
    cambios <- cambios[cambios$id_producto_comun %in% comparables, , drop = FALSE]
    nuevos <- nuevos[nuevos$id_producto_comun %in% comparables, , drop = FALSE]
    retirados <- retirados[retirados$id_producto_comun %in% comparables, , drop = FALSE]
  }

  cambios$tipo <- if (nrow(cambios) > 0) ifelse(cambios$cambio_cop > 0, "Subió", "Bajó") else character(0)
  nuevos$tipo <- rep("Nuevo", nrow(nuevos))
  retirados$tipo <- rep("Dejó de observarse", nrow(retirados))

  columnas <- c("tipo", "comercio", "nombre_canonico", "texto_original",
                "precio_anterior", "precio_actual", "cambio_cop", "cambio_pct",
                "fecha_anterior", "fecha_actual", "id_comercio", "sku_comercio",
                "id_producto_comun")
  rbind(
    cambios[, columnas, drop = FALSE],
    nuevos[, columnas, drop = FALSE],
    retirados[, columnas, drop = FALSE]
  )
}

# -----------------------------------------------------------------------------
# Canasta
# -----------------------------------------------------------------------------

precios_canasta <- function(con, id_ejecucion, id_productos) {
  if (length(id_productos) == 0) return(data.frame())
  dbGetQuery(con, sprintf("
    SELECT o.id_comercio, c.nombre AS comercio, o.id_producto_comun,
           p.nombre_canonico, o.precio_cop, o.estado_disponibilidad
      FROM observaciones o
      JOIN comercios c ON c.id_comercio = o.id_comercio
      JOIN productos_comparables p ON p.id_producto_comun = o.id_producto_comun
     WHERE o.id_ejecucion = ? AND o.es_comparable = 1
       AND o.id_producto_comun IN (%s)", marcadores(length(id_productos))),
    params = c(list(id_ejecucion), as.list(id_productos)))
}

# Calcula el costo de la canasta por comercio y el óptimo comprando cada
# producto donde está más barato. Si falta un producto, el total es NA.
calcular_canasta <- function(precios, cantidades, comercios = NULL) {
  if (is.null(precios) || nrow(precios) == 0) {
    return(list(por_comercio = data.frame(), optimo = NA_real_, ahorro = NA_real_,
                completo = FALSE, faltantes = character()))
  }
  if (is.null(comercios)) comercios <- unique(precios$comercio)
  cantidades <- cantidades[names(cantidades) %in% unique(precios$id_producto_comun)]
  productos <- names(cantidades)
  if (length(productos) == 0) {
    return(list(por_comercio = data.frame(), optimo = NA_real_, ahorro = NA_real_,
                completo = FALSE, faltantes = character()))
  }

  filas <- lapply(comercios, function(com) {
    sub <- precios[precios$comercio == com, , drop = FALSE]
    disponibles <- sub$id_producto_comun[sub$estado_disponibilidad == "disponible" &
                                           !is.na(sub$precio_cop)]
    faltan <- setdiff(productos, disponibles)
    if (length(faltan) > 0) {
      return(data.frame(comercio = com, costo = NA_real_, completo = FALSE,
                        faltantes = paste(faltan, collapse = ", ")))
    }
    costo <- sum(vapply(productos, function(p) {
      precio <- sub$precio_cop[sub$id_producto_comun == p][1]
      precio * cantidades[[p]]
    }, numeric(1)))
    data.frame(comercio = com, costo = costo, completo = TRUE, faltantes = "")
  })
  por_comercio <- do.call(rbind, filas)

  optimo <- sum(vapply(productos, function(p) {
    sub <- precios[precios$id_producto_comun == p & precios$estado_disponibilidad == "disponible" &
                     !is.na(precios$precio_cop), , drop = FALSE]
    if (nrow(sub) == 0) return(NA_real_)
    min(sub$precio_cop) * cantidades[[p]]
  }, numeric(1)))

  completos <- por_comercio$costo[por_comercio$completo]
  ahorro <- if (length(completos) > 0 && !is.na(optimo)) min(completos) - optimo else NA_real_

  list(por_comercio = por_comercio, optimo = optimo, ahorro = ahorro,
       completo = any(por_comercio$completo),
       faltantes = unique(unlist(strsplit(por_comercio$faltantes[nzchar(por_comercio$faltantes)], ", "))))
}

# Ahorro entre el precio mínimo y máximo de una presentación, con empates.
calcular_ahorro <- function(precios, comercios) {
  ok <- !is.na(precios)
  if (!any(ok)) {
    return(list(minimo = NA_real_, maximo = NA_real_, ahorro_cop = NA_real_,
                ahorro_pct = NA_real_, empates = character()))
  }
  pmin <- min(precios[ok]); pmax <- max(precios[ok])
  list(
    minimo = pmin,
    maximo = pmax,
    ahorro_cop = pmax - pmin,
    ahorro_pct = if (pmax > 0) round(100 * (pmax - pmin) / pmax, 2) else NA_real_,
    empates = comercios[ok & precios == pmin]
  )
}

# -----------------------------------------------------------------------------
# Resumen de una actualización
# -----------------------------------------------------------------------------

resumen_actualizacion <- function(con, id_ejecucion) {
  stores <- dbGetQuery(con, "
    SELECT DISTINCT id_comercio FROM observaciones WHERE id_ejecucion = ?",
    params = list(id_ejecucion))$id_comercio

  filas <- lapply(stores, function(com) {
    anterior <- dbGetQuery(con, "
      SELECT id_ejecucion FROM ejecuciones
       WHERE fecha_inicio < (SELECT fecha_inicio FROM ejecuciones WHERE id_ejecucion = ?)
         AND id_ejecucion IN (SELECT id_ejecucion FROM observaciones WHERE id_comercio = ?)
         AND estado IN ('completa', 'parcial')
       ORDER BY fecha_inicio DESC LIMIT 1",
      params = list(id_ejecucion, com))$id_ejecucion[1]

    recolectados <- dbGetQuery(con,
      "SELECT COUNT(*) AS n FROM observaciones WHERE id_ejecucion = ? AND id_comercio = ?",
      params = list(id_ejecucion, com))$n[1]

    if (is.na(anterior)) {
      return(data.frame(comercio = com, recolectados = recolectados,
                        nuevos = recolectados, cambios = 0L, no_observados = 0L,
                        estado = "primera ejecución"))
    }

    nuevos <- dbGetQuery(con, "
      SELECT COUNT(*) AS n FROM observaciones b
       WHERE b.id_ejecucion = ? AND b.id_comercio = ?
         AND NOT EXISTS (SELECT 1 FROM observaciones a
                          WHERE a.id_ejecucion = ? AND a.id_comercio = b.id_comercio
                            AND a.sku_comercio = b.sku_comercio)",
      params = list(id_ejecucion, com, anterior))$n[1]

    cambios <- dbGetQuery(con, "
      SELECT COUNT(*) AS n FROM v_cambios_precio
       WHERE ejecucion_anterior = ? AND ejecucion_actual = ? AND id_comercio = ?
         AND ABS(cambio_cop) >= 0.5",
      params = list(anterior, id_ejecucion, com))$n[1]

    no_obs <- dbGetQuery(con, "
      SELECT COUNT(*) AS n FROM observaciones a
       WHERE a.id_ejecucion = ? AND a.id_comercio = ?
         AND NOT EXISTS (SELECT 1 FROM observaciones b
                          WHERE b.id_ejecucion = ? AND b.id_comercio = a.id_comercio
                            AND b.sku_comercio = a.sku_comercio)",
      params = list(anterior, com, id_ejecucion))$n[1]

    data.frame(comercio = com, recolectados = recolectados, nuevos = nuevos,
               cambios = cambios, no_observados = no_obs, estado = "comparado")
  })
  do.call(rbind, filas)
}

# Estado de una ejecución en curso, para el panel de actualización.
progreso_ejecucion <- function(con, id_ejecucion) {
  dbGetQuery(con, "
    SELECT c.nombre AS comercio, ec.estado, ec.n_extraido, ec.n_incluido,
           ec.n_con_precio, ec.mensaje
      FROM ejecuciones_comercio ec
      JOIN comercios c ON c.id_comercio = ec.id_comercio
     WHERE ec.id_ejecucion = ?
     ORDER BY c.nombre", params = list(id_ejecucion))
}
