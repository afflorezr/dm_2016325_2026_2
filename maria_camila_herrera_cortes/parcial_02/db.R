# db.R -- Taller 2, Minería de Datos
# Capa de acceso a datos: TODO el SQL de la aplicación vive aquí; la interfaz solo
# llama a estas funciones, que reciben los filtros como argumentos y devuelven tablas.
#  - Filtros e indicadores se calculan en SQLite (nunca se lee la tabla completa).
#  - Todo valor que viene del usuario se pasa como parámetro (?), nunca se concatena.
#  - Cada función abre la conexión, ejecuta y la cierra (on.exit), también si hay error.

suppressPackageStartupMessages({ library(DBI); library(RSQLite) })

DB_RUTA <- "comparador_precios.sqlite"

# ---- conexión controlada ------------------------------------------------------
db_consultar <- function(sql, params = list(), ruta = DB_RUTA) {
  con <- dbConnect(SQLite(), ruta, flags = SQLITE_RO)   # solo lectura: la UI no escribe
  on.exit(dbDisconnect(con))
  if (length(params)) dbGetQuery(con, sql, params = unname(params)) else dbGetQuery(con, sql)
}

marcadores <- function(n) paste(rep("?", n), collapse = ",")   # "?,?,?" para IN (...)

# ---- validación de entradas de texto -----------------------------------------
# Largo máximo y caracteres permitidos (letras con tilde, dígitos, espacio y . , - % & ' / +)
validar_texto <- function(x, max_chars = 60) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) return("")
  x <- trimws(as.character(x[1]))
  invalida <- function(msg) stop(structure(class = c("entrada_invalida", "error", "condition"),
                                          list(message = msg, call = NULL)))
  if (nchar(x) > max_chars) invalida(paste0("El texto de búsqueda es demasiado largo (máximo ", max_chars, " caracteres)."))
  if (nzchar(x) && !grepl("^[[:alnum:] .,%&'/+-]+$", x, perl = TRUE))
    invalida("El texto de búsqueda tiene caracteres no permitidos. Use letras, números y espacios.")
  x
}

# Los comodines de LIKE (% y _) escritos por el usuario se tratan como texto literal
escapar_like <- function(x) gsub("([%_\\\\])", "\\\\\\1", x)

# ---- metadatos -----------------------------------------------------------------
# Clave que cambia cuando entran datos nuevos: sirve para invalidar la caché
# (bindCache / st.cache_data) al terminar una actualización.
db_version <- function(ruta = DB_RUTA) {
  r <- db_consultar("SELECT COUNT(*) AS n, COALESCE(MAX(observacion_id), 0) AS ultimo
                     FROM observaciones", ruta = ruta)
  paste(r$n, r$ultimo, sep = "-")
}

db_ejecuciones <- function(ruta = DB_RUTA) {
  db_consultar("SELECT e.ejecucion_id, MIN(e.fecha_hora_inicio) AS fecha_hora,
                       GROUP_CONCAT(c.nombre || ':' || e.estado, ', ') AS estado_por_comercio,
                       CASE WHEN SUM(e.estado <> 'completa') = 0 THEN 'completa'
                            WHEN SUM(e.estado IN ('completa','parcial')) = 0 THEN 'fallida'
                            ELSE 'parcial' END AS estado_global,
                       SUM(e.n_registros) AS n_registros
                FROM ejecuciones e JOIN comercios c USING (comercio_id)
                GROUP BY e.ejecucion_id ORDER BY fecha_hora DESC", ruta = ruta)
}

db_filtros <- function(ruta = DB_RUTA) {
  list(
    comercios = db_consultar("SELECT nombre FROM comercios ORDER BY nombre", ruta = ruta)$nombre,
    subcategorias = db_consultar("SELECT DISTINCT subcategoria FROM v_ultimo_precio
                                  WHERE subcategoria IS NOT NULL ORDER BY 1", ruta = ruta)$subcategoria,
    marcas = db_consultar("SELECT DISTINCT marca FROM v_ultimo_precio
                           WHERE marca IS NOT NULL ORDER BY 1", ruta = ruta)$marca,
    precio = db_consultar("SELECT COALESCE(MIN(precio_cop), 0) AS min, COALESCE(MAX(precio_cop), 0) AS max
                           FROM v_ultimo_precio", ruta = ruta),
    productos_comparables = db_consultar("SELECT producto_id, producto_estandar FROM productos
                                          ORDER BY producto_id", ruta = ruta),
    unidades = db_consultar("SELECT DISTINCT unidad_norm FROM v_comparables
                             WHERE unidad_norm IS NOT NULL", ruta = ruta)$unidad_norm)
}

# ---- filtros del panel lateral -> fragmento SQL parametrizado ---------------------
# ejecucion = NULL y sin fechas -> última ejecución de cada comercio (v_ultimo_precio).
# ejecucion = c("run_...") o fechas "AAAA-MM-DD" -> v_precios filtrada.
# Devuelve la fuente, el WHERE (con marcadores ?) y los parámetros; el texto del usuario nunca se
# concatena: va en `par`.
filtros_sql <- function(comercios = NULL, subcategorias = NULL, marcas = NULL,
                        precio_min = NULL, precio_max = NULL, ejecucion = NULL,
                        fecha_desde = NULL, fecha_hasta = NULL,
                        solo_promocion = FALSE, solo_comparables = FALSE, busqueda = "") {
  donde <- character(); par <- list()
  agregar_in <- function(col, vals) if (length(vals)) {
    donde <<- c(donde, sprintf("%s IN (%s)", col, marcadores(length(vals))))
    par   <<- c(par, as.list(as.character(vals))) }
  agregar_in("comercio", comercios)
  agregar_in("subcategoria", subcategorias)
  agregar_in("marca", marcas)
  agregar_in("ejecucion_id", ejecucion)
  if (!is.null(precio_min) && is.finite(precio_min)) { donde <- c(donde, "precio_cop >= ?"); par <- c(par, list(precio_min)) }
  if (!is.null(precio_max) && is.finite(precio_max)) { donde <- c(donde, "precio_cop <= ?"); par <- c(par, list(precio_max)) }
  if (length(fecha_desde)) { donde <- c(donde, "SUBSTR(fecha_hora_consulta, 1, 10) >= ?"); par <- c(par, list(as.character(fecha_desde))) }
  if (length(fecha_hasta)) { donde <- c(donde, "SUBSTR(fecha_hora_consulta, 1, 10) <= ?"); par <- c(par, list(as.character(fecha_hasta))) }
  if (isTRUE(solo_promocion))   donde <- c(donde, "en_promocion = 1")
  if (isTRUE(solo_comparables)) donde <- c(donde, "comparable = 1")
  palabras <- strsplit(validar_texto(busqueda), "[[:space:]]+")[[1]]
  palabras <- head(palabras[nzchar(palabras)], 5)
  for (w in palabras) {
    donde <- c(donde, "texto_anuncio LIKE ? ESCAPE '\\'")
    par   <- c(par, list(paste0("%", escapar_like(w), "%")))
  }
  list(fuente = if (is.null(ejecucion) && !length(fecha_desde) && !length(fecha_hasta))
                  "v_ultimo_precio" else "v_precios",
       donde = if (length(donde)) paste(" WHERE", paste(donde, collapse = " AND ")) else "",
       par = par)
}

# ---- tabla de productos filtrados -------------------------------------------------
db_precios_filtrados <- function(..., ruta = DB_RUTA) {
  f <- filtros_sql(...)
  db_consultar(paste0(
    "SELECT comercio, nombre, marca, subcategoria,
            CASE WHEN contenido_valor IS NULL THEN NULL
                 ELSE contenido_valor || ' ' || COALESCE(unidad_norm, '') END AS presentacion,
            precio_cop, precio_unitario, unidad_norm, en_promocion,
            estado_disponibilidad, fecha_hora_consulta, ejecucion_id, producto_id, comparable, url
     FROM ", f$fuente, f$donde, " ORDER BY comercio, nombre"), f$par, ruta)
}

# ---- evolución del precio de un producto comparable -----------------------------
db_serie_precio <- function(producto_id, comercios = NULL, ruta = DB_RUTA) {
  par <- list(as.character(producto_id))
  extra <- ""
  if (length(comercios)) { extra <- sprintf(" AND comercio IN (%s)", marcadores(length(comercios)))
                           par <- c(par, as.list(as.character(comercios))) }
  db_consultar(paste0("SELECT comercio, ejecucion_id, fecha_hora_consulta, precio_cop,
                              precio_unitario, unidad_norm, estado_disponibilidad
                       FROM v_comparables WHERE producto_id = ?", extra,
                      " ORDER BY fecha_hora_consulta"), par, ruta)
}

# ---- precio por unidad (sin mezclar unidades) -----------------------------------
db_precio_unitario <- function(ejecucion = NULL, unidad = "mL", ruta = DB_RUTA) {
  stopifnot(unidad %in% c("mL", "g", "unidad"))
  if (is.null(ejecucion))
    ejecucion <- db_consultar("SELECT ejecucion_id FROM v_ultima_ejecucion
                               ORDER BY fecha_hora_inicio DESC LIMIT 1", ruta = ruta)$ejecucion_id
  db_consultar("SELECT comercio, producto_id, producto_estandar, precio_cop, contenido,
                       precio_unitario, unidad_norm, ejecucion_id, fecha_hora_consulta
                FROM v_comparables
                WHERE ejecucion_id = ? AND unidad_norm = ? AND precio_unitario IS NOT NULL
                ORDER BY producto_id, precio_unitario", list(ejecucion, unidad), ruta)
}

# ---- comparación de dos ejecuciones (mismo anuncio, mismo comercio) -----------
db_comparar_ejecuciones <- function(ej_anterior, ej_actual, ruta = DB_RUTA) {
  # solo comercios con ejecución válida en ambas: así "no observado" no es una falla de red
  db_consultar(
    "WITH validos AS (
       SELECT c.nombre FROM ejecuciones e JOIN comercios c USING (comercio_id)
       WHERE e.ejecucion_id IN (?, ?) AND e.estado IN ('completa','parcial')
       GROUP BY c.nombre HAVING COUNT(DISTINCT e.ejecucion_id) = 2),
     x AS (SELECT anuncio_id, comercio, nombre, producto_id, url FROM v_precios
           WHERE ejecucion_id IN (?, ?) AND comercio IN (SELECT nombre FROM validos)
           GROUP BY anuncio_id)
     SELECT x.comercio, x.nombre, x.producto_id, x.url,
            a.precio_cop AS precio_anterior, b.precio_cop AS precio_actual,
            a.ejecucion_id IS NOT NULL AS estaba, b.ejecucion_id IS NOT NULL AS esta
     FROM x
     LEFT JOIN v_precios a ON a.anuncio_id = x.anuncio_id AND a.ejecucion_id = ?
     LEFT JOIN v_precios b ON b.anuncio_id = x.anuncio_id AND b.ejecucion_id = ?",
    list(ej_anterior, ej_actual, ej_anterior, ej_actual, ej_anterior, ej_actual), ruta)
}

# Clasifica el resultado de db_comparar_ejecuciones; `umbral_pct` resalta variaciones grandes
clasificar_cambios <- function(d, umbral_pct = 10) {
  d$variacion_cop <- d$precio_actual - d$precio_anterior
  d$variacion_pct <- 100 * d$variacion_cop / d$precio_anterior
  d$tipo <- ifelse(!d$estaba & d$esta, "nuevo",
            ifelse(d$estaba & !d$esta, "no observado",
            ifelse(is.na(d$precio_anterior) | is.na(d$precio_actual), "sin precio en alguna ejecución",
            ifelse(d$variacion_cop > 0, "subió",
            ifelse(d$variacion_cop < 0, "bajó", "igual")))))
  d$variacion_grande <- !is.na(d$variacion_pct) & abs(d$variacion_pct) >= umbral_pct
  d
}

# ---- resumen de una ejecución (lo que muestra el botón al terminar) -------------
# Una fila por comercio: estado, productos recolectados, nuevos, cambios de precio,
# no observados y observaciones rechazadas. Todo calculado con SQL sobre la base.
db_resumen_ejecucion <- function(ejecucion, ruta = DB_RUTA) {
  inicio <- inicio_iso_ejecucion(ejecucion)
  db_consultar(
    "SELECT c.nombre AS comercio, e.estado, e.motivo, e.n_registros AS recolectados,
            (SELECT COUNT(*) FROM anuncios a JOIN observaciones o USING (anuncio_id)
              WHERE a.comercio_id = c.comercio_id AND a.incluido = 1 AND o.ejecucion_id = e.ejecucion_id
                AND o.descartada = 0
                AND NOT EXISTS (SELECT 1 FROM observaciones o2 WHERE o2.anuncio_id = a.anuncio_id
                                  AND o2.fecha_hora_consulta < ?)) AS nuevos,
            (SELECT COUNT(*) FROM v_cambios_precio v WHERE v.comercio = c.nombre
                AND v.ejecucion_actual = e.ejecucion_id) AS cambios_precio,
            (SELECT COUNT(*) FROM v_disponibilidad d WHERE d.comercio = c.nombre
                AND d.ejecucion_id = e.ejecucion_id AND d.estado = 'no_observado') AS no_observados,
            (SELECT COUNT(*) FROM observaciones_rechazadas r WHERE r.comercio = c.nombre
                AND r.ejecucion_id = e.ejecucion_id) AS rechazados
     FROM ejecuciones e JOIN comercios c USING (comercio_id)
     WHERE e.ejecucion_id = ? ORDER BY c.nombre", list(inicio, ejecucion), ruta)
}

inicio_iso_ejecucion <- function(ejecucion_id) {
  t <- as.POSIXct(sub("^run_", "", ejecucion_id), format = "%Y%m%d_%H%M%S", tz = "America/Bogota")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", format(t, "%Y-%m-%dT%H:%M:%S%z"))
}

# ---- ahorro por producto entre comercios (maneja empates) ------------------------
# precio mínimo y máximo por producto comparable en UNA ejecución; `comercios_mas_baratos`
# lista TODOS los que empatan en el mínimo; si todos cobran lo mismo, el ahorro es 0.
db_ahorro_producto <- function(ejecucion = NULL, ruta = DB_RUTA) {
  if (is.null(ejecucion)) ejecucion <- db_ultima_ejecucion(ruta)
  db_consultar(
    "WITH p AS (SELECT producto_id, producto_estandar, comercio, precio_cop FROM v_comparables
                WHERE ejecucion_id = ? AND precio_cop IS NOT NULL),
          m AS (SELECT producto_id, MIN(precio_cop) AS precio_min, MAX(precio_cop) AS precio_max,
                       COUNT(*) AS n_comercios FROM p GROUP BY producto_id)
     SELECT m.producto_id, p.producto_estandar, m.n_comercios, m.precio_min, m.precio_max,
            m.precio_max - m.precio_min AS ahorro_cop,
            ROUND(100.0 * (m.precio_max - m.precio_min) / m.precio_max, 2) AS ahorro_pct,
            (SELECT GROUP_CONCAT(comercio, ', ') FROM p p2
              WHERE p2.producto_id = m.producto_id AND p2.precio_cop = m.precio_min) AS comercios_mas_baratos
     FROM m JOIN (SELECT DISTINCT producto_id, producto_estandar FROM p) p USING (producto_id)
     ORDER BY m.producto_id", list(ejecucion), ruta)
}

# Ejecución de referencia para comparar comercios: la más reciente que quedó COMPLETA en todos los
# comercios (así un comercio caído no deja huecos); si no hay, la más reciente completa en alguno.
db_ultima_ejecucion <- function(ruta = DB_RUTA) {
  r <- db_consultar("SELECT ejecucion_id FROM ejecuciones WHERE estado = 'completa'
                     GROUP BY ejecucion_id
                     HAVING COUNT(DISTINCT comercio_id) = (SELECT COUNT(*) FROM comercios)
                     ORDER BY MIN(fecha_hora_inicio) DESC LIMIT 1", ruta = ruta)$ejecucion_id
  if (length(r)) return(r)
  db_consultar("SELECT ejecucion_id FROM v_ultima_ejecucion ORDER BY fecha_hora_inicio DESC LIMIT 1",
               ruta = ruta)$ejecucion_id
}

# ---- canasta -----------------------------------------------------------------------
# items: data.frame(producto_id, cantidad). Con precios de UNA misma ejecución:
#  - total por comercio SOLO si el comercio tiene todos los productos (si falta alguno, NA y
#    `faltantes` lo indica: nunca un total incompleto);
#  - mínimo comprando cada producto donde es más barato, y ahorro frente a comprar todo en
#    el comercio más barato que tenga la canasta completa.
# No incluye envío, mínimos de compra ni condiciones de las promociones.
db_canasta <- function(items, ejecucion = NULL, ruta = DB_RUTA) {
  items <- items[!is.na(items$cantidad) & items$cantidad > 0, , drop = FALSE]
  if (!nrow(items)) stop("Elige al menos un producto con cantidad mayor que cero.")
  if (is.null(ejecucion)) ejecucion <- db_ultima_ejecucion(ruta)
  pedido <- paste(rep("(?, ?)", nrow(items)), collapse = ", ")
  par_items <- as.list(as.vector(rbind(as.character(items$producto_id), as.numeric(items$cantidad))))
  por_comercio <- db_consultar(sprintf(
    "WITH pedido(producto_id, cantidad) AS (VALUES %s),
          precio AS (SELECT comercio, producto_id, precio_cop FROM v_comparables
                     WHERE ejecucion_id = ? AND precio_cop IS NOT NULL),
          cm AS (SELECT DISTINCT comercio FROM v_comparables WHERE ejecucion_id = ?)
     SELECT cm.comercio,
            COUNT(*) AS productos_pedidos,
            SUM(pr.precio_cop IS NOT NULL) AS productos_con_precio,
            GROUP_CONCAT(CASE WHEN pr.precio_cop IS NULL THEN pe.producto_id END, ', ') AS faltantes,
            CASE WHEN COUNT(*) = SUM(pr.precio_cop IS NOT NULL)
                 THEN SUM(pr.precio_cop * pe.cantidad) END AS total_cop
     FROM cm CROSS JOIN pedido pe
     LEFT JOIN precio pr ON pr.comercio = cm.comercio AND pr.producto_id = pe.producto_id
     GROUP BY cm.comercio ORDER BY cm.comercio", pedido),
    c(par_items, list(ejecucion, ejecucion)), ruta)
  mejor <- db_consultar(sprintf(
    "WITH pedido(producto_id, cantidad) AS (VALUES %s),
          p AS (SELECT producto_id, comercio, precio_cop FROM v_comparables
                WHERE ejecucion_id = ? AND precio_cop IS NOT NULL)
     SELECT pe.producto_id, pe.cantidad, MIN(p.precio_cop) AS precio_min,
            MIN(p.precio_cop) * pe.cantidad AS subtotal_min,
            (SELECT GROUP_CONCAT(p2.comercio, ', ') FROM p p2
              WHERE p2.producto_id = pe.producto_id AND p2.precio_cop = MIN(p.precio_cop)) AS comercios_mas_baratos
     FROM pedido pe LEFT JOIN p ON p.producto_id = pe.producto_id
     GROUP BY pe.producto_id, pe.cantidad ORDER BY pe.producto_id", pedido),
    c(par_items, list(ejecucion)), ruta)
  detalle <- db_consultar(sprintf(
    "WITH pedido(producto_id, cantidad) AS (VALUES %s),
          cm AS (SELECT DISTINCT comercio FROM v_comparables WHERE ejecucion_id = ?)
     SELECT cm.comercio, pe.producto_id, pe.cantidad, pr.precio_cop, pr.precio_cop * pe.cantidad AS subtotal
     FROM cm CROSS JOIN pedido pe
     LEFT JOIN v_comparables pr ON pr.comercio = cm.comercio AND pr.producto_id = pe.producto_id
                               AND pr.ejecucion_id = ? AND pr.precio_cop IS NOT NULL
     ORDER BY pe.producto_id, cm.comercio", pedido),
    c(par_items, list(ejecucion, ejecucion)), ruta)
  completos <- por_comercio[!is.na(por_comercio$total_cop), ]
  total_min <- if (all(!is.na(mejor$precio_min))) sum(mejor$subtotal_min) else NA_real_
  mejor_unico <- if (nrow(completos)) min(completos$total_cop) else NA_real_
  list(ejecucion = ejecucion, por_comercio = por_comercio, mejor_por_producto = mejor, detalle = detalle,
       total_minimo = total_min, mejor_un_comercio = mejor_unico,
       ahorro_cop = if (is.na(total_min) || is.na(mejor_unico)) NA_real_ else mejor_unico - total_min,
       aviso = "El resultado no incluye envío, mínimos de compra ni condiciones de las promociones.")
}


# ======================= Indicadores y datos de los gráficos (todo con SQL) ===================
# `f` es la lista de filtros del panel lateral (los mismos argumentos de filtros_sql()).

# 1. Productos y observaciones por comercio (según los filtros)
db_ind_productos <- function(f = list(), ruta = DB_RUTA) {
  q <- do.call(filtros_sql, f)
  db_consultar(paste0("SELECT comercio, COUNT(*) AS observaciones, COUNT(DISTINCT anuncio_id) AS productos,
                              SUM(precio_cop IS NOT NULL) AS con_precio, MAX(fecha_hora_consulta) AS fecha_hora,
                              GROUP_CONCAT(DISTINCT ejecucion_id) AS ejecuciones
                       FROM ", q$fuente, q$donde, " GROUP BY comercio ORDER BY comercio"), q$par, ruta)
}

# 2. Última ejecución INTENTADA por comercio (aunque haya sido parcial o fallida), con su motivo
db_ind_ultima_ejecucion <- function(ruta = DB_RUTA) {
  db_consultar("SELECT c.nombre AS comercio, e.ejecucion_id, e.fecha_hora_inicio, e.estado, e.motivo
                FROM ejecuciones e JOIN comercios c USING (comercio_id)
                WHERE e.fecha_hora_inicio = (SELECT MAX(e2.fecha_hora_inicio) FROM ejecuciones e2
                                             WHERE e2.comercio_id = e.comercio_id)
                ORDER BY c.nombre", ruta = ruta)
}

# 3. Proporción de productos en promoción
db_ind_promocion <- function(f = list(), ruta = DB_RUTA) {
  q <- do.call(filtros_sql, f)
  db_consultar(paste0("SELECT COUNT(*) AS productos, COALESCE(SUM(en_promocion = 1), 0) AS en_promocion,
                              ROUND(100.0 * COALESCE(SUM(en_promocion = 1), 0) / NULLIF(COUNT(*), 0), 1) AS pct
                       FROM ", q$fuente, q$donde), q$par, ruta)
}

# 4. Mediana del precio (global y por subcategoría). Mediana con funciones de ventana en SQLite.
db_ind_mediana <- function(f = list(), ruta = DB_RUTA, por = c("subcategoria", "global")) {
  por <- match.arg(por)
  q <- do.call(filtros_sql, f)
  grp <- if (por == "subcategoria") "COALESCE(subcategoria, 'Sin subcategoría')" else "'Todos'"
  db_consultar(paste0(
    "WITH b AS (SELECT ", grp, " AS grupo, precio_cop FROM ", q$fuente, q$donde,
    if (nzchar(q$donde)) " AND" else " WHERE", " precio_cop IS NOT NULL),
          r AS (SELECT grupo, precio_cop,
                       ROW_NUMBER() OVER (PARTITION BY grupo ORDER BY precio_cop) AS rn,
                       COUNT(*) OVER (PARTITION BY grupo) AS n FROM b)
     SELECT grupo AS subcategoria, AVG(precio_cop) AS mediana_cop, MAX(n) AS n
     FROM r WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY grupo ORDER BY mediana_cop DESC"),
    q$par, ruta)
}

# 5. Ahorro máximo entre comercios (producto comparable con mayor diferencia de precio)
db_ind_ahorro_max <- function(ejecucion = NULL, ruta = DB_RUTA) {
  a <- db_ahorro_producto(ejecucion, ruta)
  if (!nrow(a)) return(a)
  a[order(-a$ahorro_cop, -a$ahorro_pct), ][1, , drop = FALSE]
}

# 6. Cambios de precio en la última ejecución (respecto a la observación anterior del mismo anuncio)
db_ind_cambios <- function(ejecucion = NULL, ruta = DB_RUTA) {
  if (is.null(ejecucion)) ejecucion <- db_ultima_ejecucion(ruta)
  db_consultar("SELECT COUNT(*) AS cambios, COALESCE(SUM(variacion_cop > 0), 0) AS subieron,
                       COALESCE(SUM(variacion_cop < 0), 0) AS bajaron,
                       MAX(ejecucion_anterior) AS ejecucion_anterior
                FROM v_cambios_precio WHERE ejecucion_actual = ?", list(ejecucion), ruta)
}

# 7. En cuántos productos comparables es el más barato cada comercio (los empates cuentan para todos)
db_ind_mas_barato <- function(ejecucion = NULL, ruta = DB_RUTA) {
  if (is.null(ejecucion)) ejecucion <- db_ultima_ejecucion(ruta)
  db_consultar("WITH c AS (SELECT producto_id, comercio, precio_cop FROM v_comparables
                           WHERE ejecucion_id = ? AND precio_cop IS NOT NULL),
                    m AS (SELECT producto_id, MIN(precio_cop) AS pmin, COUNT(*) AS n FROM c GROUP BY producto_id)
               SELECT c.comercio, COUNT(*) AS productos_mas_barato, (SELECT COUNT(*) FROM m WHERE n > 1) AS comparables
               FROM c JOIN m USING (producto_id)
               WHERE c.precio_cop = m.pmin AND m.n > 1 GROUP BY c.comercio ORDER BY productos_mas_barato DESC",
               list(ejecucion), ruta)
}

# Promoción y disponibilidad por comercio (según los filtros)
db_promocion_por_comercio <- function(f = list(), ruta = DB_RUTA) {
  q <- do.call(filtros_sql, f)
  db_consultar(paste0("SELECT comercio, COUNT(*) AS productos, COALESCE(SUM(en_promocion = 1), 0) AS en_promocion,
                              ROUND(100.0 * COALESCE(SUM(en_promocion = 1), 0) / COUNT(*), 1) AS pct,
                              COALESCE(SUM(estado_disponibilidad = 'disponible'), 0) AS disponibles,
                              COALESCE(SUM(estado_disponibilidad = 'agotado'), 0) AS agotados
                       FROM ", q$fuente, q$donde, " GROUP BY comercio ORDER BY comercio"), q$par, ruta)
}

# Cobertura de los productos comparables en una ejecución: unidad y en cuántos comercios hay precio
# (explica por qué un producto no aparece en un gráfico)
db_cobertura_comparables <- function(ejecucion = NULL, ruta = DB_RUTA) {
  if (is.null(ejecucion)) ejecucion <- db_ultima_ejecucion(ruta)
  db_consultar("SELECT pr.producto_id, pr.producto_estandar,
                       CASE pr.unidad WHEN 'ml' THEN 'mL' WHEN 'g' THEN 'g' WHEN 'und' THEN 'unidad' END AS unidad_norm,
                       COALESCE(c.n, 0) AS n_comercios, COALESCE(c.comercios, '') AS comercios
                FROM productos pr LEFT JOIN (
                  SELECT producto_id, COUNT(*) AS n, GROUP_CONCAT(comercio, ', ') AS comercios
                  FROM v_comparables WHERE ejecucion_id = ? AND precio_cop IS NOT NULL GROUP BY producto_id) c
                  USING (producto_id) ORDER BY pr.producto_id", list(ejecucion), ruta)
}

# Distribución de precios por comercio: P5, P25, mediana, P75 y P95 (rango por posición, en SQL)
db_cuantiles_precio <- function(f = list(), ruta = DB_RUTA) {
  q <- do.call(filtros_sql, f)
  db_consultar(paste0(
    "WITH b AS (SELECT comercio, precio_cop FROM ", q$fuente, q$donde,
    if (nzchar(q$donde)) " AND" else " WHERE", " precio_cop IS NOT NULL),
          r AS (SELECT comercio, precio_cop,
                       ROW_NUMBER() OVER (PARTITION BY comercio ORDER BY precio_cop) AS rn,
                       COUNT(*) OVER (PARTITION BY comercio) AS n FROM b)
     SELECT comercio, MAX(n) AS n,
            MAX(CASE WHEN rn = CAST(0.05 * (n - 1) AS INTEGER) + 1 THEN precio_cop END) AS p5,
            MAX(CASE WHEN rn = CAST(0.25 * (n - 1) AS INTEGER) + 1 THEN precio_cop END) AS p25,
            MAX(CASE WHEN rn = CAST(0.50 * (n - 1) AS INTEGER) + 1 THEN precio_cop END) AS mediana,
            MAX(CASE WHEN rn = CAST(0.75 * (n - 1) AS INTEGER) + 1 THEN precio_cop END) AS p75,
            MAX(CASE WHEN rn = CAST(0.95 * (n - 1) AS INTEGER) + 1 THEN precio_cop END) AS p95
     FROM r GROUP BY comercio ORDER BY comercio"), q$par, ruta)
}

# Sobrecosto frente al comercio más barato, por producto comparable (gráfico libre)
db_sobrecosto <- function(ejecucion = NULL, ruta = DB_RUTA) {
  if (is.null(ejecucion)) ejecucion <- db_ultima_ejecucion(ruta)
  db_consultar("WITH c AS (SELECT producto_id, producto_estandar, comercio, precio_cop FROM v_comparables
                           WHERE ejecucion_id = ? AND precio_cop IS NOT NULL),
                    m AS (SELECT producto_id, MIN(precio_cop) AS pmin, COUNT(*) AS n FROM c GROUP BY producto_id)
               SELECT c.producto_id, c.producto_estandar, c.comercio, c.precio_cop, m.pmin,
                      ROUND(100.0 * (c.precio_cop - m.pmin) / m.pmin, 1) AS sobrecosto_pct
               FROM c JOIN m USING (producto_id) WHERE m.n > 1 ORDER BY c.producto_id, c.comercio",
               list(ejecucion), ruta)
}
