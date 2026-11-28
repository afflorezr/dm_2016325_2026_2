# =============================================================================
# db.R — Taller 2, Módulo 3: capa de acceso a datos
#
# Todas las consultas de la aplicación están aquí. Cada función recibe la
# conexión y los filtros como argumentos y devuelve un data.frame (o una lista
# de data.frames). La interfaz (app.R) no contiene SQL.
#
# Seguridad (Módulo 4): los valores que vienen del usuario SIEMPRE van en
# `params`. En el texto de la consulta solo se insertan marcadores `?`
# (por ejemplo "comercio IN (?, ?, ?)" según cuántos comercios se elijan) y
# nombres de columnas fijos escritos en este archivo.
# =============================================================================
library(DBI)
library(RSQLite)

# -----------------------------------------------------------------------------
# Conexión
# -----------------------------------------------------------------------------
# La aplicación abre UNA conexión de solo lectura al iniciar y la cierra al
# terminar (onStop en app.R). Las escrituras las hace scraper.R en la tarea de
# actualización, con su propia conexión.
abrir_conexion <- function(ruta = "comparador_precios.sqlite", solo_lectura = TRUE) {
  if (!file.exists(ruta)) stop("No se encontró la base de datos: ", ruta)
  con <- dbConnect(RSQLite::SQLite(), ruta,
                   flags = if (solo_lectura) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC)
  dbExecute(con, "PRAGMA busy_timeout = 10000")
  faltan <- setdiff(c("v_observaciones", "v_ultimo_precio", "v_cambios_precio",
                      "v_comparables", "v_disponibilidad", "correcciones",
                      "observaciones_rechazadas"),
                    dbListTables(con))
  if (length(faltan) > 0) {
    dbDisconnect(con)
    stop("La base no tiene el esquema del Taller 2 (faltan: ",
         paste(faltan, collapse = ", "), "). Ejecute source(\"migracion.R\").")
  }
  con
}

consultar <- function(con, sql, params = list()) {
  if (length(params) == 0) dbGetQuery(con, sql) else dbGetQuery(con, sql, params = unname(params))
}

# "?, ?, ?" para n valores
marcadores <- function(n) paste(rep("?", n), collapse = ", ")

# -----------------------------------------------------------------------------
# Validación de entradas (Módulo 4)
# -----------------------------------------------------------------------------
MAX_TEXTO <- 60
PATRON_TEXTO <- "^[\\p{L}\\p{N} .,+\\-/&()]*$"

# Devuelve el texto limpio (o NULL si está vacío). Error con mensaje claro si
# es demasiado largo o tiene caracteres no permitidos.
validar_texto <- function(x, max = MAX_TEXTO) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) return(NULL)
  x <- trimws(as.character(x[1]))
  if (!nzchar(x)) return(NULL)
  if (nchar(x) > max) stop("La búsqueda admite como máximo ", max, " caracteres.")
  if (!grepl(PATRON_TEXTO, x, perl = TRUE)) {
    stop("La búsqueda solo admite letras, números, espacios y los signos . , + - / & ( )")
  }
  x
}

# Conserva solo valores que existen en la base (lo que no está en `permitidos`
# se descarta en silencio: no puede llegar a una consulta).
solo_permitidos <- function(x, permitidos) {
  if (is.null(x)) return(character())
  intersect(as.character(x), as.character(permitidos))
}

validar_numero <- function(x, minimo = -Inf, maximo = Inf, defecto = NA_real_) {
  x <- suppressWarnings(as.numeric(x))
  if (length(x) != 1 || is.na(x) || !is.finite(x)) return(defecto)
  min(max(x, minimo), maximo)
}

validar_fecha <- function(x) {
  x <- suppressWarnings(as.Date(as.character(x)))
  if (length(x) != 1 || is.na(x)) NULL else format(x, "%Y-%m-%d")
}

# Normaliza la lista de filtros que arma la interfaz:
#   comercios, subcategorias, marcas (vectores), precio (c(min, max)),
#   periodo ("ejecucion" | "fechas"), ejecucion, fechas (c(desde, hasta)),
#   solo_promo, solo_comparables (lógicos), texto (búsqueda)
limpiar_filtros <- function(f, opciones) {
  list(
    comercios        = solo_permitidos(f$comercios, opciones$comercios$comercio),
    subcategorias    = solo_permitidos(f$subcategorias, opciones$subcategorias),
    marcas           = solo_permitidos(f$marcas, opciones$marcas),
    # el rango completo del deslizador equivale a "sin filtro de precio", para
    # no excluir los productos agotados que el sitio publica sin precio
    precio_min       = { x <- validar_numero(f$precio[1], 0, 1e8, NA_real_)
                         if (!is.na(x) && x <= opciones$precio[1]) NA_real_ else x },
    precio_max       = { x <- validar_numero(f$precio[2], 0, 1e8, NA_real_)
                         if (!is.na(x) && x >= opciones$precio[2]) NA_real_ else x },
    periodo          = if (identical(f$periodo, "fechas")) "fechas" else "ejecucion",
    ejecucion        = solo_permitidos(f$ejecucion, opciones$ejecuciones$id_ejecucion)[1],
    fecha_desde      = validar_fecha(f$fechas[1]),
    fecha_hasta      = validar_fecha(f$fechas[2]),
    solo_promo       = isTRUE(f$solo_promo),
    solo_comparables = isTRUE(f$solo_comparables),
    texto            = validar_texto(f$texto)
  )
}

# Construye el WHERE (sobre v_observaciones con alias v) a partir de filtros
# ya limpios. Devuelve list(sql, params). `usar` permite omitir filtros.
where_filtros <- function(f, usar = c("comercio", "subcategoria", "marca", "precio",
                                     "periodo", "promo", "comparables", "texto")) {
  sql <- "v.en_categoria = 1"
  p <- list()
  agrega <- function(cond, valores = list()) {
    sql <<- paste(sql, "AND", cond)
    p <<- c(p, as.list(valores))
  }
  if ("comercio" %in% usar && length(f$comercios) > 0)
    agrega(sprintf("v.comercio IN (%s)", marcadores(length(f$comercios))), f$comercios)
  if ("subcategoria" %in% usar && length(f$subcategorias) > 0)
    agrega(sprintf("v.subcategoria_std IN (%s)", marcadores(length(f$subcategorias))), f$subcategorias)
  if ("marca" %in% usar && length(f$marcas) > 0)
    agrega(sprintf("v.marca_std IN (%s)", marcadores(length(f$marcas))), f$marcas)
  if ("precio" %in% usar && !is.na(f$precio_min)) agrega("v.precio >= ?", f$precio_min)
  if ("precio" %in% usar && !is.na(f$precio_max)) agrega("v.precio <= ?", f$precio_max)
  if ("periodo" %in% usar) {
    if (f$periodo == "fechas" && !is.null(f$fecha_desde) && !is.null(f$fecha_hasta)) {
      agrega("substr(v.fecha_hora_consulta, 1, 10) BETWEEN ? AND ?",
             c(f$fecha_desde, f$fecha_hasta))
    } else if (length(f$ejecucion) == 1 && !is.na(f$ejecucion)) {
      agrega("v.id_ejecucion = ?", f$ejecucion)
    }
  }
  if ("promo" %in% usar && isTRUE(f$solo_promo)) agrega("v.promocion = 1")
  if ("comparables" %in% usar && isTRUE(f$solo_comparables)) agrega("v.comparable = 1")
  if ("texto" %in% usar && !is.null(f$texto)) {
    agrega("(v.nombre_original LIKE '%' || ? || '%' OR v.texto_original LIKE '%' || ? || '%')",
           c(f$texto, f$texto))
  }
  list(sql = sql, params = p)
}

# Texto legible del periodo que cubren los filtros
describir_periodo <- function(f, ejecuciones) {
  if (f$periodo == "fechas" && !is.null(f$fecha_desde)) {
    sprintf("del %s al %s", f$fecha_desde, f$fecha_hasta)
  } else if (length(f$ejecucion) == 1 && !is.na(f$ejecucion)) {
    e <- ejecuciones[ejecuciones$id_ejecucion == f$ejecucion, ]
    paste("ejecución", if (nrow(e) == 1) e$etiqueta else f$ejecucion)
  } else "todas las ejecuciones"
}

# -----------------------------------------------------------------------------
# Catálogos para los filtros
# -----------------------------------------------------------------------------
lista_ejecuciones <- function(con) {
  e <- consultar(con, "
    SELECT id_ejecucion,
           MIN(inicio)                 AS inicio,
           COUNT(*)                    AS n_comercios,
           SUM(estado = 'completa')    AS n_completas,
           SUM(estado = 'fallida')     AS n_fallidas,
           GROUP_CONCAT(comercio || ': ' || estado, ', ') AS estados
    FROM ejecuciones
    GROUP BY id_ejecucion
    HAVING SUM(estado <> 'fallida') > 0
    ORDER BY id_ejecucion DESC")
  n_total <- consultar(con, "SELECT COUNT(*) AS n FROM comercios")$n
  e$estado_general <- ifelse(e$n_completas == n_total, "completa",
                             ifelse(e$n_fallidas == 0, "parcial", "con fallas"))
  e$etiqueta <- sprintf("%s %s · %s (%d/%d)",
                        substr(e$inicio, 1, 10), substr(e$inicio, 12, 16),
                        e$estado_general, e$n_completas, n_total)
  e
}

# Ejecución de referencia: la más reciente con todos los comercios completos
ejecucion_referencia <- function(ejecuciones) {
  comp <- ejecuciones[ejecuciones$estado_general == "completa", ]
  if (nrow(comp) > 0) comp$id_ejecucion[1] else ejecuciones$id_ejecucion[1]
}

opciones_filtros <- function(con) {
  ej <- lista_ejecuciones(con)
  rango <- consultar(con, "
    SELECT MIN(precio) AS pmin, MAX(precio) AS pmax,
           MIN(substr(fecha_hora_consulta, 1, 10)) AS fmin,
           MAX(substr(fecha_hora_consulta, 1, 10)) AS fmax
    FROM v_observaciones WHERE en_categoria = 1")
  list(
    comercios     = consultar(con, "SELECT comercio, nombre FROM comercios ORDER BY nombre"),
    subcategorias = consultar(con, "
      SELECT DISTINCT subcategoria_std FROM anuncios
      WHERE en_categoria = 1 ORDER BY 1")$subcategoria_std,
    marcas        = consultar(con, "
      SELECT DISTINCT marca_std FROM anuncios
      WHERE en_categoria = 1 AND marca_std IS NOT NULL ORDER BY 1")$marca_std,
    comparables   = consultar(con, "
      SELECT id_producto, nombre_std, unidad FROM productos ORDER BY nombre_std"),
    unidades      = consultar(con, "SELECT DISTINCT unidad FROM productos ORDER BY 1")$unidad,
    ejecuciones   = ej,
    referencia    = ejecucion_referencia(ej),
    precio        = c(floor(rango$pmin), ceiling(rango$pmax)),
    fechas        = c(rango$fmin, rango$fmax)
  )
}

# -----------------------------------------------------------------------------
# Tabla de productos filtrados
# -----------------------------------------------------------------------------
productos_filtrados <- function(con, f) {
  w <- where_filtros(f)
  consultar(con, paste("
    SELECT c.nombre AS comercio, v.nombre_original AS nombre, v.marca_std AS marca,
           v.subcategoria_std AS subcategoria, v.contenido, v.unidad,
           v.precio, v.precio_lista, ROUND(v.precio_por_unidad, 1) AS precio_unitario,
           v.promocion, v.disponibilidad, v.comparable,
           v.fecha_hora_consulta, v.id_ejecucion, v.url
    FROM v_observaciones v JOIN comercios c ON c.comercio = v.comercio
    WHERE", w$sql, "
    ORDER BY v.subcategoria_std, v.nombre_original, c.nombre, v.fecha_hora_consulta"),
    w$params)
}

# -----------------------------------------------------------------------------
# Indicadores (Módulo 5, sección 7.3). Todos en SQL.
# -----------------------------------------------------------------------------
# Productos (anuncios distintos) y observaciones por comercio
ind_por_comercio <- function(con, f) {
  w <- where_filtros(f)
  consultar(con, paste("
    SELECT c.nombre AS comercio, v.comercio AS clave,
           COUNT(DISTINCT v.sku) AS productos, COUNT(*) AS observaciones
    FROM v_observaciones v JOIN comercios c ON c.comercio = v.comercio
    WHERE", w$sql, "GROUP BY v.comercio ORDER BY productos DESC"), w$params)
}

# Fecha y estado de la última ejecución registrada (no depende de filtros)
ind_ultima_ejecucion <- function(con) {
  consultar(con, "
    SELECT e.id_ejecucion, MIN(e.inicio) AS inicio, MAX(e.fin) AS fin,
           SUM(e.estado = 'completa') AS completas, COUNT(*) AS comercios,
           GROUP_CONCAT(e.comercio || ': ' || e.estado, ', ') AS detalle
    FROM ejecuciones e
    WHERE e.id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones)
    GROUP BY e.id_ejecucion")
}

# Proporción de observaciones con precio en promoción (%)
ind_promocion <- function(con, f) {
  w <- where_filtros(f)
  consultar(con, paste("
    SELECT ROUND(100.0 * AVG(v.promocion), 1) AS pct_promocion,
           SUM(v.promocion) AS en_promocion, COUNT(*) AS con_precio
    FROM v_observaciones v WHERE", w$sql, "AND v.precio IS NOT NULL"), w$params)
}

# Mediana del precio (SQLite no tiene MEDIAN: se calcula con ROW_NUMBER).
# por_subcategoria = TRUE devuelve una fila por subcategoría.
mediana_precio <- function(con, f, por_subcategoria = FALSE) {
  w <- where_filtros(f)
  grupo <- if (por_subcategoria) "v.subcategoria_std" else "'Todas'"
  consultar(con, paste0("
    WITH base AS (
      SELECT ", grupo, " AS subcategoria, v.precio
      FROM v_observaciones v WHERE ", w$sql, " AND v.precio IS NOT NULL
    ),
    ord AS (
      SELECT subcategoria, precio,
             ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS rn,
             COUNT(*)     OVER (PARTITION BY subcategoria)                 AS n
      FROM base
    )
    SELECT subcategoria, AVG(precio) AS mediana, MAX(n) AS observaciones
    FROM ord WHERE rn IN ((n + 1) / 2, (n + 2) / 2)
    GROUP BY subcategoria ORDER BY mediana DESC"), w$params)
}

# Comparación de precios por producto comparable en una ejecución, con
# empates: comercio_mas_barato lista TODOS los comercios con el precio mínimo.
ahorro_por_producto <- function(con, ejecucion, comercios = character()) {
  filtro <- if (length(comercios) > 0) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste("
    WITH obs AS (
      SELECT id_producto, nombre_std AS producto, unidad, contenido, comercio,
             MIN(precio) AS precio, MAX(promocion) AS promocion
      FROM v_comparables
      WHERE id_ejecucion = ? AND precio IS NOT NULL", filtro, "
      GROUP BY id_producto, comercio
    ),
    res AS (
      SELECT id_producto, producto, unidad, contenido,
             MIN(precio) AS precio_min, MAX(precio) AS precio_max,
             COUNT(*) AS n_comercios, SUM(promocion) AS en_promocion
      FROM obs GROUP BY id_producto
    )
    SELECT r.id_producto, r.producto, r.unidad, r.contenido, r.precio_min, r.precio_max,
           r.precio_max - r.precio_min AS ahorro_cop,
           ROUND(100.0 * (r.precio_max - r.precio_min) / r.precio_max, 1) AS ahorro_pct,
           r.n_comercios, r.en_promocion,
           (SELECT GROUP_CONCAT(comercio, ', ') FROM (
              SELECT o.comercio FROM obs o
              WHERE o.id_producto = r.id_producto AND o.precio = r.precio_min
              ORDER BY o.comercio)) AS comercio_mas_barato,
           (SELECT COUNT(*) FROM obs o
             WHERE o.id_producto = r.id_producto AND o.precio = r.precio_min) AS n_empatados
    FROM res r
    ORDER BY ahorro_cop DESC, r.producto"), c(list(ejecucion), as.list(comercios)))
}

# Número de cambios de precio (mismo anuncio) en la última ejecución
ind_cambios_ultima <- function(con, comercios = character()) {
  filtro <- if (length(comercios) > 0) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste("
    SELECT id_ejecucion,
           SUM(direccion = 'subió') AS subieron,
           SUM(direccion = 'bajó')  AS bajaron,
           COUNT(*)                 AS comparados
    FROM v_cambios_precio
    WHERE en_categoria = 1 AND direccion <> 'sin precio'
      AND id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones WHERE estado <> 'fallida')",
    filtro, "GROUP BY id_ejecucion"), as.list(comercios))
}

# -----------------------------------------------------------------------------
# Gráficos (Módulo 5, sección 7.4)
# -----------------------------------------------------------------------------
# 1. Evolución del precio de un producto comparable, una serie por comercio
serie_producto <- function(con, id_producto, comercios = character()) {
  filtro <- if (length(comercios) > 0) sprintf("AND v.comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste("
    SELECT v.comercio, c.nombre, v.id_ejecucion, v.fecha_hora_consulta,
           v.precio, v.promocion, v.disponibilidad, v.nombre_std
    FROM v_comparables v JOIN comercios c ON c.comercio = v.comercio
    WHERE v.id_producto = ? AND v.precio IS NOT NULL", filtro, "
    ORDER BY v.comercio, v.fecha_hora_consulta"),
    c(list(id_producto), as.list(comercios)))
}

# 2. Precio por unidad de contenido de los comparables, UNA unidad a la vez
precio_unitario <- function(con, ejecucion, unidad, comercios = character()) {
  filtro <- if (length(comercios) > 0) sprintf("AND v.comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste("
    SELECT v.id_producto, v.nombre_std AS producto, v.linea, v.contenido, v.unidad,
           v.comercio, c.nombre, MIN(v.precio) AS precio,
           ROUND(MIN(v.precio_unitario), 2) AS precio_unitario
    FROM v_comparables v JOIN comercios c ON c.comercio = v.comercio
    WHERE v.id_ejecucion = ? AND v.unidad = ? AND v.precio IS NOT NULL", filtro, "
    GROUP BY v.id_producto, v.comercio
    ORDER BY v.linea, v.contenido, v.comercio"),
    c(list(ejecucion, unidad), as.list(comercios)))
}

# 3. Distribución de precios de la categoría por comercio
distribucion_precios <- function(con, f) {
  w <- where_filtros(f)
  consultar(con, paste("
    SELECT v.comercio, c.nombre, v.subcategoria_std, v.precio
    FROM v_observaciones v JOIN comercios c ON c.comercio = v.comercio
    WHERE", w$sql, "AND v.precio IS NOT NULL"), w$params)
}

# 4. (libre) usa ahorro_por_producto(): ¿cuánto me ahorro comprando cada
#    presentación en el comercio más barato?

# -----------------------------------------------------------------------------
# Módulo 6. Cambios de precio entre dos ejecuciones (mismo anuncio, mismo comercio)
# -----------------------------------------------------------------------------
cambios_entre <- function(con, ejec_a, ejec_b, comercios = character(), solo_comparables = FALSE) {
  fc  <- if (length(comercios) > 0) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  fcp <- if (solo_comparables) "AND comparable = 1" else ""
  pc  <- as.list(comercios)
  base <- function(alias, ejec) sprintf("
    %s AS (SELECT comercio, sku, producto, nombre_original, subcategoria_std, comparable,
                  precio, disponibilidad, fecha_hora_consulta
           FROM v_observaciones
           WHERE id_ejecucion = ? AND en_categoria = 1 %s %s)", alias, fc, fcp)
  cte <- paste("WITH", base("a", ejec_a), ",", base("b", ejec_b), ",
    recolectados AS (SELECT comercio FROM ejecuciones WHERE id_ejecucion = ? AND estado <> 'fallida')")
  p <- c(list(ejec_a), pc, list(ejec_b), pc, list(ejec_b))

  cambios <- consultar(con, paste(cte, "
    SELECT c.nombre AS comercio, b.nombre_original AS nombre, b.subcategoria_std AS subcategoria,
           b.comparable, a.precio AS precio_anterior, b.precio AS precio_nuevo,
           b.precio - a.precio AS cambio_cop,
           ROUND(100.0 * (b.precio - a.precio) / a.precio, 2) AS cambio_pct,
           CASE WHEN b.precio > a.precio THEN 'subió' ELSE 'bajó' END AS direccion,
           b.disponibilidad
    FROM a JOIN b ON a.comercio = b.comercio AND a.sku = b.sku
    JOIN comercios c ON c.comercio = b.comercio
    WHERE a.precio IS NOT NULL AND b.precio IS NOT NULL AND a.precio <> b.precio
    ORDER BY ABS(100.0 * (b.precio - a.precio) / a.precio) DESC"), p)

  nuevos <- consultar(con, paste(cte, "
    SELECT c.nombre AS comercio, b.nombre_original AS nombre, b.subcategoria_std AS subcategoria,
           b.precio, b.disponibilidad
    FROM b JOIN comercios c ON c.comercio = b.comercio
    WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.comercio = b.comercio AND a.sku = b.sku)
    ORDER BY c.nombre, b.nombre_original"), p)

  # Solo cuenta como "dejó de observarse" si el comercio SÍ se recolectó en b
  no_observados <- consultar(con, paste(cte, "
    SELECT c.nombre AS comercio, a.nombre_original AS nombre, a.subcategoria_std AS subcategoria,
           a.precio AS ultimo_precio
    FROM a JOIN comercios c ON c.comercio = a.comercio
    WHERE a.comercio IN (SELECT comercio FROM recolectados)
      AND NOT EXISTS (SELECT 1 FROM b WHERE b.comercio = a.comercio AND b.sku = a.sku)
    ORDER BY c.nombre, a.nombre_original"), p)

  list(cambios = cambios, nuevos = nuevos, no_observados = no_observados)
}

# -----------------------------------------------------------------------------
# Módulo 6. Canasta
#   items: data.frame(id_producto, cantidad). Precios de UNA ejecución.
#   Un comercio solo tiene total si tiene TODOS los productos (con precio y,
#   si exigir_disponible = TRUE, disponibles); si no, se listan los faltantes.
# -----------------------------------------------------------------------------
canasta <- function(con, ejecucion, items, exigir_disponible = TRUE) {
  items <- items[!is.na(items$id_producto) & items$cantidad > 0, , drop = FALSE]
  if (nrow(items) == 0) stop("La canasta está vacía.")
  valores <- paste(rep("(?, ?)", nrow(items)), collapse = ", ")
  p_items <- list()
  for (i in seq_len(nrow(items))) {
    p_items <- c(p_items, list(as.character(items$id_producto[i]), as.integer(items$cantidad[i])))
  }
  cte <- paste0("
    WITH items(id_producto, cantidad) AS (VALUES ", valores, "),
    precios AS (
      SELECT comercio, id_producto, MIN(precio) AS precio
      FROM v_comparables
      WHERE id_ejecucion = ? AND precio IS NOT NULL AND (disponible = 1 OR ? = 0)
      GROUP BY comercio, id_producto
    ),
    comercios_ej AS (
      SELECT comercio FROM ejecuciones WHERE id_ejecucion = ? AND estado <> 'fallida'
    ),
    detalle AS (
      SELECT ce.comercio, i.id_producto, i.cantidad, p.precio,
             p.precio * i.cantidad AS subtotal
      FROM comercios_ej ce CROSS JOIN items i
      LEFT JOIN precios p ON p.comercio = ce.comercio AND p.id_producto = i.id_producto
    )")
  p <- c(p_items, list(ejecucion, as.integer(exigir_disponible), ejecucion))

  por_comercio <- consultar(con, paste(cte, "
    SELECT d.comercio, c.nombre,
           COUNT(d.precio) AS productos_con_precio,
           (SELECT COUNT(*) FROM items) AS productos_canasta,
           CASE WHEN COUNT(d.precio) = (SELECT COUNT(*) FROM items)
                THEN SUM(d.subtotal) END AS total,
           GROUP_CONCAT(CASE WHEN d.precio IS NULL THEN pr.nombre_std END, '; ') AS faltantes
    FROM detalle d
    JOIN comercios c ON c.comercio = d.comercio
    JOIN productos pr ON pr.id_producto = d.id_producto
    GROUP BY d.comercio
    ORDER BY total IS NULL, total"), p)

  optimo <- consultar(con, paste(cte, ",
    minimos AS (
      SELECT id_producto, MIN(precio) AS precio_min FROM detalle
      WHERE precio IS NOT NULL GROUP BY id_producto
    )
    SELECT i.id_producto, pr.nombre_std AS producto, i.cantidad, m.precio_min,
           m.precio_min * i.cantidad AS subtotal,
           (SELECT GROUP_CONCAT(c.nombre, ', ') FROM detalle d
              JOIN comercios c ON c.comercio = d.comercio
             WHERE d.id_producto = i.id_producto AND d.precio = m.precio_min) AS donde
    FROM items i
    JOIN productos pr ON pr.id_producto = i.id_producto
    LEFT JOIN minimos m ON m.id_producto = i.id_producto
    ORDER BY pr.nombre_std"), p)

  completos <- por_comercio[!is.na(por_comercio$total), ]
  costo_minimo <- if (all(!is.na(optimo$precio_min))) sum(optimo$subtotal) else NA_real_
  mejor_unico  <- if (nrow(completos) > 0) min(completos$total) else NA_real_
  list(
    por_comercio = por_comercio,
    optimo       = optimo,
    costo_minimo = costo_minimo,
    mejor_comercio = if (nrow(completos) > 0) completos$nombre[completos$total == mejor_unico] else character(),
    mejor_total_un_comercio = mejor_unico,
    ahorro = mejor_unico - costo_minimo
  )
}

# -----------------------------------------------------------------------------
# Módulo 2. Resumen por comercio de una ejecución (al terminar la actualización)
# -----------------------------------------------------------------------------
resumen_actualizacion <- function(con, id_ejecucion) {
  consultar(con, "
    WITH e AS (SELECT * FROM ejecuciones WHERE id_ejecucion = ?),
    prev AS (
      SELECT e.comercio,
             (SELECT MAX(e2.id_ejecucion) FROM ejecuciones e2
               WHERE e2.comercio = e.comercio AND e2.id_ejecucion < e.id_ejecucion
                 AND e2.estado <> 'fallida') AS anterior
      FROM e
    )
    SELECT c.nombre AS comercio, e.estado, e.modo,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = e.id_ejecucion AND o.comercio = e.comercio) AS recolectados,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = e.id_ejecucion AND o.comercio = e.comercio
               AND NOT EXISTS (SELECT 1 FROM observaciones o2
                                WHERE o2.comercio = o.comercio AND o2.sku = o.sku
                                  AND o2.id_ejecucion < o.id_ejecucion)) AS nuevos,
           (SELECT COUNT(*) FROM v_cambios_precio v
             WHERE v.id_ejecucion = e.id_ejecucion AND v.comercio = e.comercio
               AND v.direccion IN ('subió', 'bajó')) AS cambios_precio,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = prev.anterior AND o.comercio = e.comercio
               AND NOT EXISTS (SELECT 1 FROM observaciones o3
                                WHERE o3.id_ejecucion = e.id_ejecucion
                                  AND o3.comercio = o.comercio AND o3.sku = o.sku)) AS no_observados,
           (SELECT COUNT(DISTINCT r.sku) FROM observaciones_rechazadas r
             WHERE r.id_ejecucion = e.id_ejecucion AND r.comercio = e.comercio) AS rechazados,
           e.detalle
    FROM e JOIN prev ON prev.comercio = e.comercio
    JOIN comercios c ON c.comercio = e.comercio
    ORDER BY c.nombre", list(id_ejecucion))
}

# -----------------------------------------------------------------------------
# Distribución de precios: cuartiles por comercio calculados en SQL
# (rango más cercano: el primer precio cuya posición es >= p * n)
# -----------------------------------------------------------------------------
cuartiles_precio <- function(con, f) {
  w <- where_filtros(f)
  consultar(con, paste("
    WITH base AS (
      SELECT v.comercio, v.precio FROM v_observaciones v
      WHERE", w$sql, "AND v.precio IS NOT NULL
    ),
    ord AS (
      SELECT comercio, precio,
             ROW_NUMBER() OVER (PARTITION BY comercio ORDER BY precio) AS rn,
             COUNT(*)     OVER (PARTITION BY comercio)                 AS n
      FROM base
    )
    SELECT o.comercio, c.nombre, MAX(o.n) AS n,
           MIN(o.precio)                                   AS minimo,
           MIN(CASE WHEN o.rn >= 0.25 * o.n THEN o.precio END) AS q1,
           MIN(CASE WHEN o.rn >= 0.50 * o.n THEN o.precio END) AS mediana,
           MIN(CASE WHEN o.rn >= 0.75 * o.n THEN o.precio END) AS q3,
           MAX(o.precio)                                   AS maximo
    FROM ord o JOIN comercios c ON c.comercio = o.comercio
    GROUP BY o.comercio ORDER BY c.nombre"), w$params)
}

# -----------------------------------------------------------------------------
# Calidad de los datos y control de caché
# -----------------------------------------------------------------------------
# Cambia cada vez que entra una ejecución, una observación o un reproceso.
# La app la consulta cada pocos segundos y la usa como clave de caché, así que
# una actualización invalida los resultados guardados en TODAS las sesiones.
firma_datos <- function(con) {
  consultar(con, "
    SELECT (SELECT COUNT(*) FROM ejecuciones) || '-' ||
           (SELECT COUNT(*) FROM observaciones) || '-' ||
           (SELECT COUNT(*) FROM correcciones) || '-' ||
           COALESCE((SELECT MAX(COALESCE(reprocesada, fin)) FROM ejecuciones), '') AS firma")$firma
}

tabla_ejecuciones <- function(con) {
  consultar(con, "
    SELECT e.id_ejecucion, c.nombre AS comercio, e.inicio, e.modo, e.n_registros,
           e.total_sitio, e.n_en_categoria, e.estado, e.detalle, e.reprocesada
    FROM ejecuciones e JOIN comercios c ON c.comercio = e.comercio
    ORDER BY e.id_ejecucion DESC, c.nombre")
}

tabla_correcciones <- function(con) {
  consultar(con, "
    SELECT fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo
    FROM correcciones ORDER BY id_correccion")
}

resumen_rechazos <- function(con) {
  consultar(con, "
    SELECT r.id_ejecucion, c.nombre AS comercio, r.regla, r.motivo,
           COUNT(*) AS observaciones
    FROM observaciones_rechazadas r JOIN comercios c ON c.comercio = r.comercio
    GROUP BY r.id_ejecucion, r.comercio, r.regla
    ORDER BY r.id_ejecucion DESC, c.nombre")
}
