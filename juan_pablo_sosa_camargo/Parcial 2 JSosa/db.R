# =============================================================================
# db.R  -  Capa de acceso a datos (Modulo 3)
# -----------------------------------------------------------------------------
# Todas las consultas de la aplicacion viven aqui, en SQL sobre SQLite, con
# parametros (?). La interfaz (ui.R/server.R) NO contiene SQL. La conexion se
# abre y se cierra de forma controlada: la app mantiene UNA conexion por
# sesion (abrir_conexion/cerrar_conexion) y las funciones de este modulo
# reciben esa conexion como argumento.
# Rutas: siempre relativas a la raiz del proyecto (sin setwd ni rutas absolutas).
# =============================================================================

DB_PATH_DEFAULT <- "comparador_precios.sqlite"

abrir_conexion <- function(db_path = DB_PATH_DEFAULT) {
  if (!file.exists(db_path))
    stop("No se encuentra la base de datos: ", db_path, call. = FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  # WAL permite lecturas concurrentes mientras el scraper escribe
  try(DBI::dbExecute(con, "PRAGMA journal_mode=WAL"), silent = TRUE)
  con
}

cerrar_conexion <- function(con) {
  if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
  invisible(NULL)
}

# Consulta parametrizada generica. Si no hay params, se llama sin ellos
# (RSQLite rechaza params = list() en consultas sin placeholders "?").
q <- function(con, sql, params = list()) {
  if (length(params) == 0) {
    DBI::dbGetQuery(con, sql)
  } else {
    DBI::dbGetQuery(con, sql, params = params)
  }
}

# Marcadores IN seguros: solo se insertan "?" en el texto; valores en params.
marcadores_in <- function(n) paste(rep("?", n), collapse = ", ")

# ---------------------------------------------------------------------------
# Listas para los filtros (dependen de los filtros previos cuando aplica)
# ---------------------------------------------------------------------------
lista_comercios <- function(con) {
  q(con, "SELECT DISTINCT comercio FROM v_ultimo_precio ORDER BY comercio")$comercio
}

lista_subcategorias <- function(con, comercios = character()) {
  if (length(comercios)) {
    q(con, paste0(
      "SELECT DISTINCT subcategoria FROM v_ultimo_precio
       WHERE subcategoria IS NOT NULL AND comercio IN (", marcadores_in(length(comercios)), ")
       ORDER BY subcategoria"), comercios)$subcategoria
  } else {
    q(con, "SELECT DISTINCT subcategoria FROM v_ultimo_precio
            WHERE subcategoria IS NOT NULL ORDER BY subcategoria")$subcategoria
  }
}

lista_marcas <- function(con, comercios = character(), subcategorias = character()) {
  sql <- "SELECT DISTINCT marca FROM v_ultimo_precio WHERE marca IS NOT NULL"
  params <- list()
  if (length(comercios)) {
    sql <- paste0(sql, " AND comercio IN (", marcadores_in(length(comercios)), ")")
    params <- c(params, comercios)
  }
  if (length(subcategorias)) {
    sql <- paste0(sql, " AND subcategoria IN (", marcadores_in(length(subcategorias)), ")")
    params <- c(params, subcategorias)
  }
  q(con, paste0(sql, " ORDER BY marca"), params)$marca
}

lista_ejecuciones <- function(con) {
  q(con, "SELECT id_ejecucion, fecha_consulta, modo, estado
          FROM ejecuciones GROUP BY id_ejecucion
          ORDER BY fecha_consulta DESC")
}

# Productos comparables (id_comun) para los selectores de evolucion y canasta
lista_comparables <- function(con) {
  q(con, "SELECT DISTINCT id_comun FROM v_comparables ORDER BY id_comun")$id_comun
}

# Rango de fechas observado: data.frame con mn y mx (texto ISO 8601)
rango_fechas_observadas <- function(con) {
  q(con, "SELECT MIN(fecha_consulta) mn, MAX(fecha_consulta) mx FROM observaciones")
}

# Precio maximo observado (COP); NA si la base esta vacia
precio_maximo_observado <- function(con) {
  q(con, "SELECT MAX(precio_cop) m FROM observaciones")$m[1]
}

# Numero de productos comparables distintos (id_comun)
contar_comparables <- function(con) {
  q(con, "SELECT COUNT(DISTINCT id_comun) n FROM v_comparables")$n[1]
}

# Numero de observaciones marcadas como comparables
contar_observaciones_comparables <- function(con) {
  q(con, "SELECT COUNT(*) n FROM observaciones WHERE comparable = 1")$n[1]
}

# ---------------------------------------------------------------------------
# Filtrado principal: v_ultimo_precio con todos los filtros de la interfaz.
# comercios/subcategorias/marcas: character() = sin filtro (todos).
# fechas: character() o ISO de fecha (YYYY-MM-DD) o datetime completo.
# ---------------------------------------------------------------------------
filtrar_ultimo_precio <- function(con,
                                  comercios = character(),
                                  subcategorias = character(),
                                  marcas = character(),
                                  pmin = NULL, pmax = NULL,
                                  fecha_desde = NULL, fecha_hasta = NULL,
                                  ejecuciones = character(),
                                  solo_promocion = FALSE,
                                  solo_comparables = FALSE,
                                  busqueda = NULL) {
  sql <- "SELECT * FROM v_ultimo_precio WHERE 1 = 1"
  params <- list()

  if (length(comercios)) {
    sql <- paste0(sql, " AND comercio IN (", marcadores_in(length(comercios)), ")")
    params <- c(params, comercios)
  }
  if (length(subcategorias)) {
    sql <- paste0(sql, " AND subcategoria IN (", marcadores_in(length(subcategorias)), ")")
    params <- c(params, subcategorias)
  }
  if (length(marcas)) {
    sql <- paste0(sql, " AND marca IN (", marcadores_in(length(marcas)), ")")
    params <- c(params, marcas)
  }
  if (length(ejecuciones)) {
    sql <- paste0(sql, " AND id_ejecucion IN (", marcadores_in(length(ejecuciones)), ")")
    params <- c(params, ejecuciones)
  }
  if (!is.null(pmin)) { sql <- paste0(sql, " AND precio_cop >= ?"); params <- c(params, pmin) }
  if (!is.null(pmax)) { sql <- paste0(sql, " AND precio_cop <= ?"); params <- c(params, pmax) }
  if (!is.null(fecha_desde)) {
    # si es solo fecha, incluye desde el inicio del dia
    if (nchar(fecha_desde) == 10) fecha_desde <- paste0(fecha_desde, "T00:00:00")
    sql <- paste0(sql, " AND fecha_consulta >= ?"); params <- c(params, fecha_desde)
  }
  if (!is.null(fecha_hasta)) {
    # si es solo fecha, incluye todo el dia
    if (nchar(fecha_hasta) == 10) fecha_hasta <- paste0(fecha_hasta, "T23:59:59")
    sql <- paste0(sql, " AND fecha_consulta <= ?"); params <- c(params, fecha_hasta)
  }
  if (isTRUE(solo_promocion)) sql <- paste0(sql, " AND en_promocion = 1")
  if (isTRUE(solo_comparables)) sql <- paste0(sql, " AND comparable = 1")
  if (!is.null(busqueda) && nzchar(busqueda)) {
    sql <- paste0(sql, " AND (producto LIKE ? OR texto_original LIKE ?)")
    patron <- paste0("%", busqueda, "%")
    params <- c(params, patron, patron)
  }
  sql <- paste0(sql, " ORDER BY subcategoria, marca, producto, comercio")
  q(con, sql, params)
}

# ---------------------------------------------------------------------------
# INDICADORES (al menos 6, calculados en SQL; cada uno con unidad y periodo)
# ---------------------------------------------------------------------------

# 1) Productos y observaciones por comercio (ultima ejecucion registrada)
indicador_por_comercio <- function(con) {
  q(con, "
    SELECT comercio,
           COUNT(*) AS observaciones,
           COUNT(DISTINCT producto) AS productos,
           COUNT(DISTINCT url) AS anuncios,
           'observaciones / productos' AS unidad,
           (SELECT MAX(fecha_consulta) FROM ejecuciones) AS periodo
    FROM v_ultimo_precio
    GROUP BY comercio
    ORDER BY comercio")
}

# 2) Fecha y estado de la ultima ejecucion
indicador_ultima_ejecucion <- function(con) {
  q(con, "
    SELECT fecha_consulta,
           SUM(CASE WHEN estado = 'exitosa'  THEN 1 ELSE 0 END) AS exitosas,
           SUM(CASE WHEN estado = 'parcial'  THEN 1 ELSE 0 END) AS parciales,
           SUM(CASE WHEN estado = 'fallida'  THEN 1 ELSE 0 END) AS fallidas,
           'fecha ISO 8601 (America/Bogota) y conteo de comercios' AS unidad
    FROM ejecuciones
    WHERE fecha_consulta = (SELECT MAX(fecha_consulta) FROM ejecuciones)
    GROUP BY fecha_consulta")
}

# 3) Proporcion de productos en promocion (ultima observacion por anuncio)
indicador_promocion <- function(con) {
  q(con, "
    SELECT ROUND(100.0 * SUM(CASE WHEN en_promocion = 1 THEN 1 ELSE 0 END) / COUNT(*), 1)
             AS pct_promocion,
           COUNT(*) AS anuncios,
           '% de anuncios en promocion' AS unidad,
           MAX(fecha_consulta) AS periodo
    FROM v_ultimo_precio")
}

# 4) Mediana del precio por subcategoria (COP, ultima observacion)
indicador_mediana_subcategoria <- function(con) {
  q(con, "
    SELECT subcategoria,
           COUNT(*) AS anuncios,
           CAST(ROUND(MEDIAN(precio_cop)) AS INTEGER) AS mediana_cop,
           'COP (mediana)' AS unidad,
           MAX(fecha_consulta) AS periodo
    FROM v_ultimo_precio
    WHERE subcategoria IS NOT NULL
    GROUP BY subcategoria
    ORDER BY mediana_cop DESC")
}

# 5) Ahorro maximo entre comercios por comparable (COP y %, misma ejecucion)
indicador_ahorro_maximo <- function(con) {
  q(con, "
    SELECT ROUND(MAX(precio_cop) - MIN(precio_cop), 0) AS ahorro_max_cop,
           ROUND(100.0 * (MAX(precio_cop) - MIN(precio_cop)) / MAX(precio_cop), 1)
             AS ahorro_max_pct,
           id_comun, marca, subcategoria, contenido_valor, contenido_unidad,
           'COP y % entre el caro y el barato del mismo comparable' AS unidad,
           MAX(fecha_consulta) AS periodo
    FROM v_comparables
    GROUP BY id_comun
    ORDER BY ahorro_max_cop DESC
    LIMIT 1")
}

# 6) Cambios de precio registrados (vista v_cambios_precio)
indicador_cambios <- function(con) {
  q(con, "
    SELECT COUNT(*) AS n_cambios,
           SUM(CASE WHEN variacion_cop > 0 THEN 1 ELSE 0 END) AS subidas,
           SUM(CASE WHEN variacion_cop < 0 THEN 1 ELSE 0 END) AS bajas,
           'cambios de precio entre ejecuciones consecutivas' AS unidad,
           MAX(fecha_actual) AS periodo
    FROM v_cambios_precio")
}

# ---------------------------------------------------------------------------
# GRAFICOS
# ---------------------------------------------------------------------------

# 1) Evolucion del precio de un comparable (serie por comercio, todas las fechas)
serie_evolucion <- function(con, id_comun) {
  q(con, "
    SELECT fecha_consulta, comercio, precio_cop, en_promocion, producto, url
    FROM observaciones
    WHERE id_comun = ?
    ORDER BY fecha_consulta, comercio", list(id_comun))
}

# 2) Precio por unidad de contenido entre comercios (sin mezclar unidades)
#    unidad: 'ml', 'g' o 'unidad'
serie_precio_unitario <- function(con, unidad = "ml", id_comunic = NULL) {
  sql <- "
    SELECT id_comun, marca, subcategoria, contenido_valor, contenido_unidad,
           comercio, producto, precio_cop, precio_por_100
    FROM v_comparables
    WHERE contenido_unidad = ?"
  params <- list(unidad)
  if (!is.null(id_comunic) && length(id_comunic)) {
    sql <- paste0(sql, " AND id_comun IN (", marcadores_in(length(id_comunic)), ")")
    params <- c(params, as.list(id_comunic))
  }
  q(con, paste0(sql, " ORDER BY id_comun, comercio"), params)
}

# 3) Distribucion de precios de la categoria por comercio (para boxplot)
distribucion_precios <- function(con) {
  q(con, "
    SELECT comercio, subcategoria, precio_cop, en_promocion
    FROM v_ultimo_precio
    ORDER BY comercio, precio_cop")
}

# 4) Libre: mayor brecha de precio entre comercios por comparable
serie_brecha <- function(con) {
  q(con, "
    WITH g AS (
      SELECT id_comun, MIN(producto) AS producto,
             MIN(marca) AS marca, MIN(subcategoria) AS subcategoria,
             MIN(contenido_valor) AS contenido_valor, MIN(contenido_unidad) AS contenido_unidad,
             MIN(precio_cop) AS pmin, MAX(precio_cop) AS pmax
      FROM v_comparables
      GROUP BY id_comun
    ),
    quien AS (
      SELECT v.id_comun,
             MAX(CASE WHEN v.precio_cop = v.pmax THEN v.comercio END) AS comercio_caro,
             MAX(CASE WHEN v.precio_cop = v.pmin THEN v.comercio END) AS comercio_barato
      FROM (
        SELECT id_comun, comercio, precio_cop,
               FIRST_VALUE(precio_cop) OVER (PARTITION BY id_comun ORDER BY precio_cop DESC) AS pmax,
               FIRST_VALUE(precio_cop) OVER (PARTITION BY id_comun ORDER BY precio_cop ASC)  AS pmin
        FROM v_comparables
      ) v
      GROUP BY v.id_comun
    )
    SELECT g.id_comun, g.producto, g.marca, g.subcategoria, g.contenido_valor, g.contenido_unidad,
           CAST(g.pmax - g.pmin AS INT) AS brecha_cop,
           ROUND(100.0 * (g.pmax - g.pmin) / g.pmax, 1) AS brecha_pct,
           quien.comercio_caro, quien.comercio_barato
    FROM g JOIN quien USING (id_comun)
    ORDER BY brecha_cop DESC")
}

# ---------------------------------------------------------------------------
# COMPARACION ENTRE DOS EJECUCIONES (Modulo 6.2)
# Devuelve lista(subieron, bajaron, nuevos, desaparecieron) con COP y %.
# ---------------------------------------------------------------------------
comparar_ejecuciones <- function(con, ejec_a, ejec_b) {
  # a = primera (mas antigua), b = segunda (mas reciente)
  base <- "
    WITH a AS (SELECT * FROM observaciones WHERE id_ejecucion = ?),
         b AS (SELECT * FROM observaciones WHERE id_ejecucion = ?)
    "
  pares <- q(con, paste0(base, "
    SELECT a.comercio, a.url, a.producto, a.id_comun,
           a.precio_cop AS precio_a, b.precio_cop AS precio_b,
           a.fecha_consulta AS fecha_a, b.fecha_consulta AS fecha_b,
           ROUND(b.precio_cop - a.precio_cop, 2) AS variacion_cop,
           ROUND(100.0 * (b.precio_cop - a.precio_cop) / a.precio_cop, 2)
             AS variacion_pct
    FROM a JOIN b ON a.comercio = b.comercio AND a.url = b.url"),
    list(ejec_a, ejec_b))
  nuevos <- q(con, paste0(base, "
    SELECT b.comercio, b.url, b.producto, b.id_comun, b.precio_cop AS precio_b,
           b.fecha_consulta AS fecha_b
    FROM b LEFT JOIN a ON a.comercio = b.comercio AND a.url = b.url
    WHERE a.url IS NULL"),
    list(ejec_a, ejec_b))
  fuera <- q(con, paste0(base, "
    SELECT a.comercio, a.url, a.producto, a.id_comun, a.precio_cop AS precio_a,
           a.fecha_consulta AS fecha_a
    FROM a LEFT JOIN b ON a.comercio = b.comercio AND a.url = b.url
    WHERE b.url IS NULL"),
    list(ejec_a, ejec_b))
  list(
    subieron = dplyr::filter(pares, variacion_cop > 0),
    bajaron  = dplyr::filter(pares, variacion_cop < 0),
    iguales  = dplyr::filter(pares, variacion_cop == 0),
    nuevos   = nuevos,
    desaparecieron = fuera
  )
}

# ---------------------------------------------------------------------------
# CANASTA (Modulo 6.3) - todo el calculo en SQL, con precios de UNA ejecucion.
# cantidades: named numeric vector, nombres = id_comun.
# ---------------------------------------------------------------------------

# Ejecucion mas reciente que contiene todos los productos pedidos.
ejecucion_canasta <- function(con, ids) {
  if (!length(ids)) return(NA_character_)
  res <- q(con, paste0("
    SELECT id_ejecucion, MAX(fecha_consulta) AS fecha
    FROM observaciones
    WHERE comparable = 1 AND id_comun IN (", marcadores_in(length(ids)), ")
    GROUP BY id_ejecucion
    HAVING COUNT(DISTINCT id_comun) = ?
    ORDER BY fecha DESC LIMIT 1"),
    c(as.list(ids), length(ids)))
  if (nrow(res) == 0) NA_character_ else res$id_ejecucion[1]
}

.precio_canasta_cte <- function(ejecucion) {
  if (is.null(ejecucion) || (length(ejecucion) == 1 && is.na(ejecucion))) {
    list(sql = "SELECT id_comun, comercio, precio_cop, fecha_consulta
                FROM v_comparables", con_ejecucion = FALSE)
  } else {
    list(sql = "SELECT id_comun, comercio, precio_cop, fecha_consulta
                FROM observaciones
                WHERE comparable = 1 AND id_ejecucion = ?", con_ejecucion = TRUE)
  }
}

# Precio por comercio de la canasta; solo comercios con TODOS los productos.
canasta_por_comercio <- function(con, cantidades, ejecucion = NULL) {
  ids <- names(cantidades)
  if (!length(ids)) return(data.frame())
  vals <- unname(unlist(lapply(seq_along(ids), function(i) c(ids[i], cantidades[i]))))
  cte <- .precio_canasta_cte(ejecucion)
  sql <- paste0("
    WITH canasta AS (
      SELECT ? AS id_comun, ? AS cantidad\n",
    paste(rep("UNION ALL SELECT ?, ?", length(ids) - 1), collapse = "\n      "), "
    ),
    precio AS (
      ", cte$sql, "
    )
    SELECT p.comercio,
           COUNT(DISTINCT p.id_comun) AS productos_ok,
           CAST(ROUND(SUM(p.precio_cop * c.cantidad)) AS INTEGER) AS costo_total,
           MAX(p.fecha_consulta) AS fecha_consulta
    FROM canasta c
    JOIN precio p ON p.id_comun = c.id_comun
    GROUP BY p.comercio
    ORDER BY costo_total")
  params <- as.list(vals)
  if (cte$con_ejecucion) params <- c(params, list(ejecucion))
  q(con, sql, params)
}

# Costo minimo comprando cada producto donde es mas barato.
canasta_minima <- function(con, cantidades, ejecucion = NULL) {
  ids <- names(cantidades)
  if (!length(ids)) return(list(incompleto = TRUE, motivo = "canasta vacia"))
  vals <- unname(unlist(lapply(seq_along(ids), function(i) c(ids[i], cantidades[i]))))
  cte <- .precio_canasta_cte(ejecucion)
  sql <- paste0("
    WITH canasta AS (
      SELECT ? AS id_comun, ? AS cantidad\n",
    paste(rep("UNION ALL SELECT ?, ?", length(ids) - 1), collapse = "\n      "), "
    ),
    precio AS (
      ", cte$sql, "
    ),
    min_por_producto AS (
      SELECT c.id_comun, c.cantidad, MIN(p.precio_cop) AS precio_min
      FROM canasta c JOIN precio p ON p.id_comun = c.id_comun
      GROUP BY c.id_comun, c.cantidad
    )
    SELECT CAST(ROUND(SUM(precio_min * cantidad)) AS INTEGER) AS costo_minimo,
           COUNT(*) AS productos
    FROM min_por_producto")
  params <- as.list(vals)
  if (cte$con_ejecucion) params <- c(params, list(ejecucion))
  res <- q(con, sql, params)
  if (nrow(res) == 0 || res$productos[1] < length(ids))
    return(list(incompleto = TRUE, motivo = "faltan productos en la base"))
  list(incompleto = FALSE, costo_minimo = res$costo_minimo[1],
       productos = res$productos[1])
}

# Detalle: precio minimo por producto con su comercio (para el ahorro)
canasta_detalle <- function(con, cantidades, ejecucion = NULL) {
  ids <- names(cantidades)
  if (!length(ids)) return(data.frame())
  vals <- unname(unlist(lapply(seq_along(ids), function(i) c(ids[i], cantidades[i]))))
  cte <- .precio_canasta_cte(ejecucion)
  sql <- paste0("
    WITH canasta AS (
      SELECT ? AS id_comun, ? AS cantidad\n",
    paste(rep("UNION ALL SELECT ?, ?", length(ids) - 1), collapse = "\n      "), "
    ),
    precio AS (
      ", cte$sql, "
    )
    SELECT c.id_comun, c.cantidad,
           MIN(p.precio_cop) AS precio_min,
           (SELECT p2.comercio FROM precio p2 WHERE p2.id_comun = c.id_comun
             ORDER BY p2.precio_cop LIMIT 1) AS mejor_comercio
    FROM canasta c JOIN precio p ON p.id_comun = c.id_comun
    GROUP BY c.id_comun, c.cantidad")
  params <- as.list(vals)
  if (cte$con_ejecucion) params <- c(params, list(ejecucion))
  q(con, sql, params)
}

# ---------------------------------------------------------------------------
# VALIDACION DE ENTRADA (Modulo 4)
# ---------------------------------------------------------------------------

# Validacion de entrada de texto (Modulo 4): longitud y caracteres permitidos.
validar_texto_busqueda <- function(x, max_len = 80) {
  if (is.null(x) || !nzchar(x)) return("")
  x <- as.character(x)[1]
  if (nchar(x) > max_len) x <- substr(x, 1, max_len)
  # letras, numeros, espacios y puntuacion basica; se elimina lo demas
  x <- gsub("[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9 .,'-]", "", x)
  trimws(x)
}
