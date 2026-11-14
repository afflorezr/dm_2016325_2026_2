# =============================================================================
# db.R — Capa de acceso a datos, consultas parametrizadas y lógica de negocio
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(glue)
  library(dplyr)
  library(tibble)
})

DB_PATH_DEFAULT <- "comparador_precios.sqlite"

# Apertura controlada de conexión (Módulo 3)
abrir_conexion <- function(db_path = DB_PATH_DEFAULT) {
  con <- dbConnect(RSQLite::SQLite(), db_path)
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  con
}

# Sanitización y validación de texto libre (Módulo 4)
validar_texto_busqueda <- function(texto, max_len = 80) {
  if (is.null(texto) || length(texto) == 0 || is.na(texto)) return("")
  txt <- trimws(as.character(texto[[1]]))
  if (nchar(txt) > max_len) {
    txt <- substr(txt, 1, max_len)
  }
  # Conserva letras (incluyendo tildes/ñ), números, espacios y puntuación básica
  gsub("[^[:alnum:][:space:].,/%-]", "", txt)
}

# ---- 1. Catálogos para filtros de la interfaz -------------------------------
obtener_opciones_filtros <- function(db_path = DB_PATH_DEFAULT) {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  comercios <- dbGetQuery(con, "SELECT DISTINCT comercio FROM observaciones ORDER BY comercio")$comercio
  
  subcategorias <- dbGetQuery(con, "
    SELECT DISTINCT COALESCE(NULLIF(TRIM(subcategoria_std), ''), NULLIF(TRIM(subcategoria), '')) AS subcat
    FROM v_ultimo_precio
    WHERE COALESCE(NULLIF(TRIM(subcategoria_std), ''), NULLIF(TRIM(subcategoria), '')) IS NOT NULL
    ORDER BY subcat
  ")$subcat
  
  marcas <- dbGetQuery(con, "
    SELECT DISTINCT TRIM(marca) AS marca
    FROM v_ultimo_precio
    WHERE marca IS NOT NULL AND TRIM(marca) <> ''
    ORDER BY marca
  ")$marca
  
  rango_precio <- dbGetQuery(con, "
    SELECT COALESCE(MIN(precio), 0) AS pmin,
           COALESCE(MAX(precio), 500000) AS pmax
    FROM observaciones
    WHERE descartada = 0 AND precio IS NOT NULL
  ")
  rango_precio$pmin <- floor(as.numeric(rango_precio$pmin))
  rango_precio$pmax <- ceiling(as.numeric(rango_precio$pmax))
  
  ejecuciones <- dbGetQuery(con, "
    SELECT DISTINCT e.id_ejecucion,
           MIN(e.inicio) AS fecha_inicio,
           GROUP_CONCAT(e.comercio || ': ' || e.estado, ' | ') AS resumen_estado
    FROM ejecuciones e
    GROUP BY e.id_ejecucion
    ORDER BY e.id_ejecucion DESC
  ")
  
  comparables <- dbGetQuery(con, "
    SELECT id_producto, nombre_std, marca_std, subcategoria_std, contenido_total, unidad_norm
    FROM productos
    ORDER BY id_producto
  ")
  
  list(
    comercios     = comercios,
    subcategorias = subcategorias,
    marcas        = marcas,
    pmin          = as.numeric(rango_precio$pmin),
    pmax          = as.numeric(rango_precio$pmax),
    ejecuciones   = ejecuciones,
    comparables   = comparables
  )
}

# Constructor dinámico de cláusula WHERE parametrizada (Módulo 4)
construir_where_productos <- function(con, comercios = NULL, subcategorias = NULL,
                                      marcas = NULL, rango_precio = NULL,
                                      ejecuciones = NULL, solo_promociones = FALSE,
                                      solo_comparables = FALSE, busqueda = "") {
  clausulas <- c("1 = 1")
  params <- list()
  
  if (!is.null(comercios) && length(comercios) > 0) {
    clausulas <- c(clausulas, as.character(glue_sql("v.comercio IN ({comercios*})", .con = con)))
  }
  
  if (!is.null(subcategorias) && length(subcategorias) > 0) {
    clausulas <- c(clausulas, as.character(glue_sql(
      "COALESCE(NULLIF(TRIM(v.subcategoria_std), ''), NULLIF(TRIM(v.subcategoria), '')) IN ({subcategorias*})",
      .con = con
    )))
  }
  
  if (!is.null(marcas) && length(marcas) > 0) {
    clausulas <- c(clausulas, as.character(glue_sql("TRIM(v.marca) IN ({marcas*})", .con = con)))
  }
  
  if (!is.null(rango_precio) && length(rango_precio) == 2) {
    clausulas <- c(clausulas, "v.precio BETWEEN ? AND ?")
    params <- c(params, list(as.numeric(rango_precio[1]), as.numeric(rango_precio[2])))
  }
  
  if (!is.null(ejecuciones) && length(ejecuciones) > 0) {
    clausulas <- c(clausulas, as.character(glue_sql("v.id_ejecucion IN ({ejecuciones*})", .con = con)))
  }
  
  if (isTRUE(solo_promociones)) {
    clausulas <- c(clausulas, "v.promocion = 1")
  }
  
  if (isTRUE(solo_comparables)) {
    clausulas <- c(clausulas, "v.comparable = 1")
  }
  
  txt <- validar_texto_busqueda(busqueda)
  if (nchar(txt) > 0) {
    patron <- paste0("%", tolower(txt), "%")
    clausulas <- c(clausulas, "(LOWER(COALESCE(v.nombre_original, '')) LIKE ? OR LOWER(COALESCE(v.descripcion_original, '')) LIKE ? OR LOWER(COALESCE(v.nombre_std, '')) LIKE ?)")
    params <- c(params, list(patron, patron, patron))
  }
  
  list(where = paste(clausulas, collapse = " AND "), params = params)
}

# ---- 2. Tabla principal filtrada en SQLite ----------------------------------
consultar_productos_filtrados <- function(db_path = DB_PATH_DEFAULT, comercios = NULL,
                                          subcategorias = NULL, marcas = NULL,
                                          rango_precio = NULL, ejecuciones = NULL,
                                          solo_promociones = FALSE, solo_comparables = FALSE,
                                          busqueda = "") {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Si el usuario no filtró ejecuciones específicas, usa v_ultimo_precio; si filtró, usa todas las observaciones
  usar_vista_ultima <- is.null(ejecuciones) || length(ejecuciones) == 0
  
  filtro <- construir_where_productos(
    con, comercios, subcategorias, marcas, rango_precio,
    if (usar_vista_ultima) NULL else ejecuciones,
    solo_promociones, solo_comparables, busqueda
  )
  
  if (usar_vista_ultima) {
    sql <- sprintf("
      SELECT v.id_ejecucion, v.comercio, v.sku,
             COALESCE(v.nombre_std, v.nombre_original) AS producto,
             v.nombre_original, v.marca,
             COALESCE(NULLIF(TRIM(v.subcategoria_std), ''), v.subcategoria) AS subcategoria,
             CASE WHEN v.contenido_total IS NOT NULL
                  THEN CAST(v.contenido_total AS TEXT) || ' ' || v.unidad_norm
                  ELSE 'N/D' END AS presentacion,
             v.precio, v.precio_antes, v.precio_unitario, v.unidad_norm,
             v.promocion, v.comparable,
             COALESCE(v.estado_disponibilidad, 'sin_dato') AS disponibilidad,
             v.fecha_hora_consulta, v.url
      FROM v_ultimo_precio v
      WHERE %s
      ORDER BY v.comercio, producto
    ", filtro$where)
  } else {
    sql <- sprintf("
      SELECT v.id_ejecucion, v.comercio, v.sku,
             COALESCE(p.nombre_std, v.nombre_original) AS producto,
             v.nombre_original, v.marca,
             COALESCE(NULLIF(TRIM(p.subcategoria_std), ''), v.subcategoria) AS subcategoria,
             CASE WHEN p.contenido_total IS NOT NULL
                  THEN CAST(p.contenido_total AS TEXT) || ' ' || p.unidad_norm
                  ELSE 'N/D' END AS presentacion,
             v.precio, v.precio_antes,
             CASE WHEN p.contenido_total > 0 THEN ROUND(v.precio / p.contenido_total, 2) ELSE NULL END AS precio_unitario,
             p.unidad_norm,
             v.promocion,
             CASE WHEN c.id_producto IS NULL THEN 0 ELSE 1 END AS comparable,
             COALESCE(v.estado_disponibilidad, 'sin_dato') AS disponibilidad,
             v.fecha_hora_consulta, v.url
      FROM observaciones v
      LEFT JOIN correspondencia c ON c.comercio = v.comercio AND c.sku = v.sku
      LEFT JOIN productos p       ON p.id_producto = c.id_producto
      WHERE v.descartada = 0 AND v.precio IS NOT NULL AND %s
      ORDER BY v.id_ejecucion DESC, v.comercio, producto
    ", filtro$where)
  }
  
  if (length(filtro$params) > 0) {
    dbGetQuery(con, sql, params = filtro$params)
  } else {
    dbGetQuery(con, sql)
  }
}

# ---- 3. Indicadores principales en SQL (Módulo 5.3) -------------------------
consultar_indicadores <- function(db_path = DB_PATH_DEFAULT, comercios = NULL,
                                  subcategorias = NULL, marcas = NULL,
                                  rango_precio = NULL, ejecuciones = NULL,
                                  solo_promociones = FALSE, solo_comparables = FALSE,
                                  busqueda = "") {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  usar_vista_ultima <- is.null(ejecuciones) || length(ejecuciones) == 0
  filtro <- construir_where_productos(
    con, comercios, subcategorias, marcas, rango_precio,
    if (usar_vista_ultima) NULL else ejecuciones,
    solo_promociones, solo_comparables, busqueda
  )
  
  tabla_base <- if (usar_vista_ultima) {
    "v_ultimo_precio v"
  } else {
    "(SELECT o.*, c.id_producto,
             CASE WHEN c.id_producto IS NULL THEN 0 ELSE 1 END AS comparable,
             p.nombre_std, p.subcategoria_std, p.contenido_total, p.unidad_norm
      FROM observaciones o
      LEFT JOIN correspondencia c ON c.comercio = o.comercio AND c.sku = o.sku
      LEFT JOIN productos p ON p.id_producto = c.id_producto
      WHERE o.descartada = 0 AND o.precio IS NOT NULL) v"
  }
  
  sql_kpis <- sprintf("
    SELECT COUNT(*) AS n_observaciones,
           COUNT(DISTINCT v.comercio || '|' || v.sku) AS n_productos_unicos,
           ROUND(100.0 * AVG(COALESCE(v.promocion, 0)), 1) AS pct_promocion,
           MIN(v.precio) AS precio_min,
           MAX(v.precio) AS precio_max,
           MAX(v.fecha_hora_consulta) AS ultima_fecha
    FROM %s
    WHERE %s
  ", tabla_base, filtro$where)
  
  kpis <- if (length(filtro$params) > 0) {
    dbGetQuery(con, sql_kpis, params = filtro$params)
  } else {
    dbGetQuery(con, sql_kpis)
  }
  
  # Mediana exacta en SQL sobre el subconjunto filtrado
  sql_mediana <- sprintf("
    WITH filtrado AS (
      SELECT v.precio FROM %s WHERE %s AND v.precio IS NOT NULL ORDER BY v.precio
    ),
    conteo AS (SELECT COUNT(*) AS n FROM filtrado)
    SELECT AVG(precio) AS mediana
    FROM (
      SELECT precio FROM filtrado
      LIMIT 2 - (SELECT n FROM conteo) %% 2
      OFFSET (SELECT (n - 1) / 2 FROM conteo)
    )
  ", tabla_base, filtro$where)
  
  mediana <- if (length(filtro$params) > 0) {
    dbGetQuery(con, sql_mediana, params = filtro$params)$mediana
  } else {
    dbGetQuery(con, sql_mediana)$mediana
  }
  
  # Ahorro máximo entre comercios en la última ejecución disponible
  ahorro_max <- dbGetQuery(con, "
    WITH ult AS (
      SELECT id_producto, nombre_std, MAX(precio) - MIN(precio) AS ahorro_cop,
             ROUND(100.0 * (MAX(precio) - MIN(precio)) / MAX(precio), 1) AS ahorro_pct
      FROM v_ultimo_precio
      WHERE comparable = 1 AND precio IS NOT NULL
      GROUP BY id_producto
      HAVING COUNT(DISTINCT comercio) >= 2
    )
    SELECT nombre_std, ahorro_cop, ahorro_pct
    FROM ult
    ORDER BY ahorro_cop DESC
    LIMIT 1
  ")
  
  # Estado de la última ejecución global y cambios de precio en ella
  ult_ej <- dbGetQuery(con, "
    SELECT id_ejecucion,
           MIN(inicio) AS inicio,
           GROUP_CONCAT(comercio || ': ' || estado, ' | ') AS detalle_estado
    FROM ejecuciones
    WHERE id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones)
    GROUP BY id_ejecucion
  ")
  
  n_cambios_ult <- dbGetQuery(con, "
    SELECT COUNT(*) AS n
    FROM v_cambios_precio
    WHERE id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones)
      AND cambio_cop <> 0
  ")$n
  
  # Conteo por comercio filtrado
  sql_por_com <- sprintf("
    SELECT v.comercio, COUNT(DISTINCT v.sku) AS n_productos
    FROM %s
    WHERE %s
    GROUP BY v.comercio
    ORDER BY v.comercio
  ", tabla_base, filtro$where)
  
  por_comercio <- if (length(filtro$params) > 0) {
    dbGetQuery(con, sql_por_com, params = filtro$params)
  } else {
    dbGetQuery(con, sql_por_com)
  }
  
  list(
    n_observaciones    = kpis$n_observaciones %||% 0L,
    n_productos_unicos = kpis$n_productos_unicos %||% 0L,
    pct_promocion      = kpis$pct_promocion %||% 0,
    mediana_precio     = mediana %||% NA_real_,
    ultima_fecha       = kpis$ultima_fecha %||% NA_character_,
    ahorro_max         = ahorro_max,
    ultima_ejecucion   = ult_ej,
    n_cambios_ult      = n_cambios_ult %||% 0L,
    por_comercio       = por_comercio
  )
}

# ---- 4. Datos para los 4 gráficos interactivos (Módulo 5.4) -----------------

# Gráfico 1: Evolución histórica del precio de un producto comparable por comercio
consultar_evolucion_producto <- function(db_path = DB_PATH_DEFAULT, id_producto) {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  dbGetQuery(con, "
    SELECT id_ejecucion,
           SUBSTR(fecha_hora_consulta, 1, 16) AS fecha_corta,
           fecha_hora_consulta,
           comercio,
           nombre_std,
           precio,
           precio_unitario,
           unidad_norm,
           promocion
    FROM v_comparables
    WHERE id_producto = ? AND precio IS NOT NULL
    ORDER BY fecha_hora_consulta ASC, comercio ASC
  ", params = list(id_producto))
}

# Gráfico 2: Precio por unidad normalizada (sin mezclar mL, g y unidad)
consultar_precio_unitario_por_unidad <- function(db_path = DB_PATH_DEFAULT, unidad_sel = "mL",
                                                 comercios = NULL) {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  clausula_com <- if (!is.null(comercios) && length(comercios) > 0) {
    as.character(glue_sql("AND comercio IN ({comercios*})", .con = con))
  } else {
    ""
  }
  
  sql <- sprintf("
    SELECT id_producto, nombre_std, comercio, precio, contenido_total,
           unidad_norm, precio_unitario, promocion
    FROM v_ultimo_precio
    WHERE comparable = 1
      AND unidad_norm = ?
      AND precio_unitario IS NOT NULL
      %s
    ORDER BY id_producto, comercio
  ", clausula_com)
  
  dbGetQuery(con, sql, params = list(unidad_sel))
}

# Gráfico 3: Distribución de precios de la categoría por comercio (última ejecución)
consultar_distribucion_precios <- function(db_path = DB_PATH_DEFAULT, comercios = NULL,
                                           rango_precio = NULL) {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  filtro <- construir_where_productos(con, comercios = comercios, rango_precio = rango_precio)
  
  sql <- sprintf("
    SELECT v.comercio, v.precio, COALESCE(v.nombre_std, v.nombre_original) AS producto
    FROM v_ultimo_precio v
    WHERE %s AND v.precio IS NOT NULL
    ORDER BY v.comercio, v.precio
  ", filtro$where)
  
  if (length(filtro$params) > 0) {
    dbGetQuery(con, sql, params = filtro$params)
  } else {
    dbGetQuery(con, sql)
  }
}

# Gráfico 4 (Pregunta del consumidor): Ahorro potencial (%) y en COP entre el comercio
# más caro y el más barato por producto comparable en la última ejecución
consultar_brecha_ahorro_comparables <- function(db_path = DB_PATH_DEFAULT) {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  dbGetQuery(con, "
    WITH base AS (
      SELECT id_producto, nombre_std, comercio, precio
      FROM v_ultimo_precio
      WHERE comparable = 1 AND precio IS NOT NULL
    ),
    resumen AS (
      SELECT id_producto, nombre_std,
             MIN(precio) AS precio_min,
             MAX(precio) AS precio_max,
             MAX(precio) - MIN(precio) AS ahorro_cop,
             ROUND(100.0 * (MAX(precio) - MIN(precio)) / MAX(precio), 1) AS ahorro_pct
      FROM base
      GROUP BY id_producto, nombre_std
      HAVING COUNT(DISTINCT comercio) >= 2
    )
    SELECT r.*,
           (SELECT GROUP_CONCAT(comercio, ', ') FROM base b
            WHERE b.id_producto = r.id_producto AND b.precio = r.precio_min) AS mas_barato,
           (SELECT GROUP_CONCAT(comercio, ', ') FROM base b
            WHERE b.id_producto = r.id_producto AND b.precio = r.precio_max) AS mas_caro
    FROM resumen r
    ORDER BY r.ahorro_pct DESC
  ")
}

# ---- 5. Comparación entre dos ejecuciones (Módulo 6.2) ----------------------
comparar_dos_ejecuciones <- function(db_path = DB_PATH_DEFAULT, ej_anterior, ej_actual) {
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Comparamos el mismo anuncio (comercio + sku) entre ej_anterior y ej_actual
  sql <- "
    WITH ant AS (
      SELECT comercio, sku, nombre_original, marca, precio, promocion, url
      FROM observaciones
      WHERE id_ejecucion = ? AND descartada = 0 AND precio IS NOT NULL
    ),
    act AS (
      SELECT comercio, sku, nombre_original, marca, precio, promocion, url
      FROM observaciones
      WHERE id_ejecucion = ? AND descartada = 0 AND precio IS NOT NULL
    ),
    en_ambas AS (
      SELECT act.comercio,
             act.sku,
             act.nombre_original AS producto,
             act.marca,
             ant.precio AS precio_anterior,
             act.precio AS precio_actual,
             (act.precio - ant.precio) AS cambio_cop,
             ROUND(100.0 * (act.precio - ant.precio) / ant.precio, 2) AS cambio_pct,
             CASE
               WHEN act.precio > ant.precio THEN 'Subió'
               WHEN act.precio < ant.precio THEN 'Bajó'
               ELSE 'Sin cambio'
             END AS estado_cambio,
             act.url
      FROM act
      JOIN ant ON ant.comercio = act.comercio AND ant.sku = act.sku
    ),
    nuevos AS (
      SELECT act.comercio,
             act.sku,
             act.nombre_original AS producto,
             act.marca,
             NULL AS precio_anterior,
             act.precio AS precio_actual,
             NULL AS cambio_cop,
             NULL AS cambio_pct,
             'Nuevo en ejecución' AS estado_cambio,
             act.url
      FROM act
      LEFT JOIN ant ON ant.comercio = act.comercio AND ant.sku = act.sku
      WHERE ant.sku IS NULL
    ),
    no_observados AS (
      SELECT ant.comercio,
             ant.sku,
             ant.nombre_original AS producto,
             ant.marca,
             ant.precio AS precio_anterior,
             NULL AS precio_actual,
             NULL AS cambio_cop,
             NULL AS cambio_pct,
             'Dejó de observarse' AS estado_cambio,
             ant.url
      FROM ant
      LEFT JOIN act ON act.comercio = ant.comercio AND act.sku = ant.sku
      WHERE act.sku IS NULL
    )
    SELECT * FROM en_ambas
    UNION ALL
    SELECT * FROM nuevos
    UNION ALL
    SELECT * FROM no_observados
    ORDER BY cambio_pct DESC, comercio, producto
  "
  
  dbGetQuery(con, sql, params = list(ej_anterior, ej_actual))
}

# ---- 6. Calculadora de Canasta del Consumidor (Módulo 6.3) ------------------
calcular_canasta <- function(db_path = DB_PATH_DEFAULT, items_df, id_ejecucion = NULL) {
  # items_df debe contener: id_producto, cantidad (> 0)
  if (is.null(items_df) || nrow(items_df) == 0) {
    return(list(
      por_comercio = tibble(),
      optima_detalle = tibble(),
      costo_optimo = NA_real_,
      ahorro_vs_mejor_tienda = NA_real_,
      ahorro_vs_peor_tienda = NA_real_
    ))
  }
  
  items_df <- items_df |>
    filter(!is.na(id_producto), !is.na(cantidad), cantidad > 0) |>
    group_by(id_producto) |>
    summarise(cantidad = sum(as.integer(cantidad)), .groups = "drop")
  
  if (nrow(items_df) == 0) {
    return(list(por_comercio = tibble(), optima_detalle = tibble(),
                costo_optimo = NA_real_, ahorro_vs_mejor_tienda = NA_real_,
                ahorro_vs_peor_tienda = NA_real_))
  }
  
  con <- abrir_conexion(db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  
  if (is.null(id_ejecucion) || id_ejecucion == "") {
    id_ejecucion <- dbGetQuery(con, "SELECT MAX(id_ejecucion) AS ej FROM ejecuciones")$ej
  }
  
  ids <- items_df$id_producto
  comercios_todos <- dbGetQuery(con, "SELECT DISTINCT comercio FROM observaciones ORDER BY comercio")$comercio
  
  sql <- as.character(glue_sql("
    SELECT id_producto, nombre_std, comercio, precio,
           COALESCE(estado_disponibilidad, 'sin_dato') AS disponibilidad
    FROM v_comparables
    WHERE id_ejecucion = {id_ejecucion}
      AND id_producto IN ({ids*})
      AND precio IS NOT NULL
  ", .con = con))
  
  precios_ej <- dbGetQuery(con, sql)
  nombres_prod <- dbGetQuery(con, as.character(glue_sql(
    "SELECT id_producto, nombre_std FROM productos WHERE id_producto IN ({ids*})", .con = con
  )))
  
  # 1. Evaluación por comercio: solo calcula total si tiene TODOS los productos pedidos
  resumen_comercios <- lapply(comercios_todos, function(com) {
    sub_com <- precios_ej |> filter(comercio == com)
    faltantes <- setdiff(ids, sub_com$id_producto)
    
    if (length(faltantes) > 0) {
      nombres_falt <- nombres_prod |> filter(id_producto %in% faltantes) |> pull(nombre_std)
      tibble(
        comercio        = com,
        completa        = FALSE,
        items_cubiertos = sprintf("%d / %d", nrow(items_df) - length(faltantes), nrow(items_df)),
        costo_total     = NA_real_,
        estado_canasta  = paste("Incompleta — faltan:", paste(nombres_falt, collapse = "; "))
      )
    } else {
      detalle <- inner_join(items_df, sub_com, by = "id_producto")
      total <- sum(detalle$cantidad * detalle$precio)
      tibble(
        comercio        = com,
        completa        = TRUE,
        items_cubiertos = sprintf("%d / %d", nrow(items_df), nrow(items_df)),
        costo_total     = total,
        estado_canasta  = "Canasta completa disponible"
      )
    }
  }) |> bind_rows()
  
  # 2. Canasta óptima (comprando cada producto donde sea más barato, manejando empates)
  optima_detalle <- lapply(seq_len(nrow(items_df)), function(i) {
    pid <- items_df$id_producto[i]
    cant <- items_df$cantidad[i]
    nom <- nombres_prod$nombre_std[nombres_prod$id_producto == pid][1]
    ofertas <- precios_ej |> filter(id_producto == pid)
    
    if (nrow(ofertas) == 0) {
      tibble(
        id_producto     = pid,
        producto        = nom,
        cantidad        = cant,
        precio_min_unit = NA_real_,
        mejor_comercio  = "Sin oferta en esta ejecución",
        subtotal        = NA_real_
      )
    } else {
      pmin <- min(ofertas$precio)
      ganadores <- sort(unique(ofertas$comercio[ofertas$precio == pmin]))
      tibble(
        id_producto     = pid,
        producto        = nom,
        cantidad        = cant,
        precio_min_unit = pmin,
        mejor_comercio  = paste(ganadores, collapse = " / "),
        subtotal        = cant * pmin
      )
    }
  }) |> bind_rows()
  
  costo_optimo <- if (any(is.na(optima_detalle$subtotal))) NA_real_ else sum(optima_detalle$subtotal)
  
  completas <- resumen_comercios |> filter(completa, !is.na(costo_total))
  mejor_tienda <- if (nrow(completas) > 0 && !is.na(costo_optimo)) min(completas$costo_total) else NA_real_
  peor_tienda  <- if (nrow(completas) > 0 && !is.na(costo_optimo)) max(completas$costo_total) else NA_real_
  
  list(
    por_comercio           = resumen_comercios,
    optima_detalle         = optima_detalle,
    costo_optimo           = costo_optimo,
    ahorro_vs_mejor_tienda = if (!is.na(mejor_tienda)) mejor_tienda - costo_optimo else NA_real_,
    ahorro_vs_peor_tienda  = if (!is.na(peor_tienda))  peor_tienda  - costo_optimo else NA_real_
  )
}