# Reglas de esta capa:
#   - todo valor del usuario va como parámetro (?); en el texto SQL solo se insertan marcadores;
#   - el texto libre se valida antes (longitud y caracteres permitidos);
#   - filtros, indicadores y agregaciones se calculan en SQLite (nunca se lee la tabla completa).

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a   # (base R lo trae desde 4.4)

RUTA_DB_APP <- "comparador_precios.sqlite"
MAX_TEXTO <- 60L

# Si la carpeta de la aplicación no admite escritura (algunos servidores), se trabaja sobre una
# copia temporal de la base: la aplicación funciona igual, pero los cambios no se conservan.
ruta_base_trabajo <- function(ruta = RUTA_DB_APP) {
  if (!file.exists(ruta)) stop("No se encontró la base ", ruta)
  if (file.access(dirname(normalizePath(ruta)), 2) == 0 && file.access(ruta, 2) == 0) return(ruta)
  copia <- file.path(tempdir(), basename(ruta))
  if (!file.exists(copia)) file.copy(ruta, copia)
  copia
}

abrir_base <- function(ruta = ruta_base_trabajo()) {
  con <- dbConnect(SQLite(), ruta)
  dbExecute(con, "PRAGMA busy_timeout = 30000")
  con
}

cerrar_base <- function(con) if (!is.null(con) && dbIsValid(con)) dbDisconnect(con)

consultar <- function(con, sql, params = list()) {
  if (length(params)) dbGetQuery(con, sql, params = unname(params)) else dbGetQuery(con, sql)
}

marcadores <- function(n) paste(rep("?", n), collapse = ", ")

# Devuelve list(ok, valor, mensaje). Se permiten letras (con tildes), números, espacios y . , % / + -
validar_texto <- function(x, max = MAX_TEXTO) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return(list(ok = TRUE, valor = "", mensaje = ""))
  x <- trimws(as.character(x)[1])
  if (!nzchar(x)) return(list(ok = TRUE, valor = "", mensaje = ""))
  if (nchar(x) > max)
    return(list(ok = FALSE, valor = "", mensaje = sprintf("La búsqueda admite máximo %d caracteres.", max)))
  if (!grepl("^[[:alnum:] áéíóúüñÁÉÍÓÚÜÑ.,%/+-]+$", x, perl = TRUE))
    return(list(ok = FALSE, valor = "",
                mensaje = "La búsqueda solo admite letras, números, espacios y los signos . , % / + -"))
  list(ok = TRUE, valor = x, mensaje = "")
}

# f: lista con comercios, subcategorias, marcas, precio_min, precio_max, ejecucion (id o "todas"),
#    fecha_desde, fecha_hasta (si usar_fechas = TRUE), solo_promo, solo_comparables,
#    solo_categoria, texto. Devuelve list(sql = "WHERE ...", params = list(...)) sobre la vista v.
filtros_vacios <- function() list(comercios = character(), subcategorias = character(), marcas = character(),
                                  precio_min = NA, precio_max = NA, ejecucion = NA, usar_fechas = FALSE,
                                  fecha_desde = NA, fecha_hasta = NA, solo_promo = FALSE,
                                  solo_comparables = FALSE, solo_categoria = TRUE, texto = "")

construir_where <- function(f) {
  f <- modifyList(filtros_vacios(), f)
  cond <- "v.precio > 0"; p <- list()
  add <- function(c, ...) { cond <<- c(cond, c); p <<- c(p, list(...)) }
  if (isTRUE(f$usar_fechas)) {
    if (!is.na(f$fecha_desde)) add("v.fecha >= ?", as.character(f$fecha_desde))
    if (!is.na(f$fecha_hasta)) add("v.fecha <= ?", as.character(f$fecha_hasta))
  } else if (!is.null(f$ejecucion) && !is.na(f$ejecucion) && f$ejecucion != "todas") {
    add("v.ejecucion_id = ?", f$ejecucion)
  }
  if (length(f$comercios)) { cond <- c(cond, sprintf("v.comercio IN (%s)", marcadores(length(f$comercios)))); p <- c(p, as.list(f$comercios)) }
  if (length(f$subcategorias)) { cond <- c(cond, sprintf("v.subcategoria_std IN (%s)", marcadores(length(f$subcategorias)))); p <- c(p, as.list(f$subcategorias)) }
  if (length(f$marcas)) { cond <- c(cond, sprintf("v.marca_std IN (%s)", marcadores(length(f$marcas)))); p <- c(p, as.list(f$marcas)) }
  if (!is.null(f$precio_min) && !is.na(f$precio_min)) add("v.precio >= ?", as.numeric(f$precio_min))
  if (!is.null(f$precio_max) && !is.na(f$precio_max)) add("v.precio <= ?", as.numeric(f$precio_max))
  if (isTRUE(f$solo_promo)) cond <- c(cond, "v.en_promocion = 1")
  if (isTRUE(f$solo_comparables)) cond <- c(cond, "v.comparable = 1")
  if (isTRUE(f$solo_categoria)) cond <- c(cond, "v.en_categoria = 1")
  t <- validar_texto(f$texto)
  if (t$ok && nzchar(t$valor)) {
    patron <- paste0("%", gsub("([%_\\\\])", "\\\\\\1", t$valor), "%")
    add("(v.nombre_original LIKE ? ESCAPE '\\' OR v.texto_original LIKE ? ESCAPE '\\')", patron, patron)
  }
  list(sql = paste("WHERE", paste(cond, collapse = " AND ")), params = p)
}

listar_comercios <- function(con) consultar(con, "SELECT comercio, nombre FROM comercios ORDER BY nombre")

listar_ejecuciones <- function(con) consultar(con, "
  SELECT ejecucion_id, MIN(substr(inicio, 1, 10)) AS fecha, MIN(inicio) AS inicio, MAX(fin) AS fin,
         COUNT(*) AS comercios,
         SUM(estado = 'completa') AS completas,
         CASE WHEN SUM(estado = 'completa') = (SELECT COUNT(*) FROM comercios) THEN 'completa'
              WHEN SUM(estado = 'fallida') = COUNT(*) THEN 'fallida' ELSE 'parcial' END AS estado
  FROM ejecuciones
  WHERE ejecucion_id IN (SELECT DISTINCT ejecucion_id FROM observaciones)
  GROUP BY ejecucion_id ORDER BY ejecucion_id DESC")

listar_subcategorias <- function(con) consultar(con, "
  SELECT DISTINCT subcategoria_std AS valor FROM v_observaciones
  WHERE subcategoria_std IS NOT NULL ORDER BY 1")$valor

listar_marcas <- function(con) consultar(con, "
  SELECT marca_std AS valor, COUNT(DISTINCT anuncio_id) AS n FROM v_observaciones
  WHERE marca_std IS NOT NULL AND en_categoria = 1 GROUP BY marca_std ORDER BY marca_std")$valor

rango_precios <- function(con) consultar(con, "
  SELECT MIN(precio) AS min, MAX(precio) AS max FROM v_observaciones WHERE precio > 0 AND en_categoria = 1")

# Última ejecución con observaciones (y su estado)
ultima_ejecucion <- function(con) {
  e <- listar_ejecuciones(con)
  if (!nrow(e)) return(NULL)
  e[1, ]
}

productos_filtrados <- function(con, f, limite = 5000L) {
  w <- construir_where(f)
  consultar(con, paste("
    SELECT v.comercio_nombre AS comercio, v.nombre_original AS nombre, v.marca_std AS marca,
           v.subcategoria_std AS subcategoria,
           CASE WHEN v.contenido_valor IS NOT NULL THEN
             printf('%g %s', v.contenido_valor, v.unidad_norm) END AS presentacion,
           v.precio, v.precio_lista,
           ROUND(v.precio_por_unidad, 1) AS precio_unitario, v.unidad_norm AS unidad,
           CASE v.en_promocion WHEN 1 THEN 'Sí' WHEN 0 THEN 'No' END AS promocion,
           v.estado_disponibilidad AS disponibilidad,
           CASE v.comparable WHEN 1 THEN 'Sí' ELSE 'No' END AS comparable,
           v.ejecucion_id AS ejecucion, v.fecha_hora AS fecha_consulta, v.url_anuncio AS enlace
    FROM v_observaciones v", w$sql, "ORDER BY v.comercio_nombre, v.nombre_original LIMIT ?"),
    c(w$params, list(as.integer(limite))))
}

ind_por_comercio <- function(con, f) {
  w <- construir_where(f)
  consultar(con, paste("
    SELECT v.comercio_nombre AS comercio, COUNT(DISTINCT v.anuncio_id) AS productos, COUNT(*) AS observaciones,
           ROUND(100.0 * AVG(v.en_promocion = 1), 1) AS pct_promocion,
           SUM(v.estado_disponibilidad = 'agotado') AS agotados
    FROM v_observaciones v", w$sql, "GROUP BY v.comercio_nombre ORDER BY v.comercio_nombre"), w$params)
}

ind_general <- function(con, f) {
  w <- construir_where(f)
  consultar(con, paste("
    SELECT COUNT(DISTINCT v.anuncio_id) AS productos, COUNT(*) AS observaciones,
           ROUND(100.0 * AVG(v.en_promocion = 1), 1) AS pct_promocion,
           COUNT(DISTINCT CASE WHEN v.comparable = 1 THEN v.producto_id END) AS comparables,
           MIN(v.fecha) AS desde, MAX(v.fecha) AS hasta
    FROM v_observaciones v", w$sql), w$params)
}

# Mediana por subcategoría (y total) con funciones de ventana
ind_mediana_subcategoria <- function(con, f) {
  w <- construir_where(f)
  consultar(con, paste("
    WITH x AS (
      SELECT COALESCE(v.subcategoria_std, 'Sin subcategoría') AS subcategoria, v.precio,
             ROW_NUMBER() OVER (PARTITION BY COALESCE(v.subcategoria_std, 'Sin subcategoría') ORDER BY v.precio) AS rn,
             COUNT(*)     OVER (PARTITION BY COALESCE(v.subcategoria_std, 'Sin subcategoría')) AS n
      FROM v_observaciones v", w$sql, ")
    SELECT subcategoria, AVG(precio) AS mediana, MAX(n) AS observaciones
    FROM x WHERE rn IN ((n + 1) / 2, (n + 2) / 2)
    GROUP BY subcategoria ORDER BY subcategoria"), w$params)
}

ind_mediana_total <- function(con, f) {
  w <- construir_where(f)
  consultar(con, paste("
    WITH x AS (SELECT v.precio, ROW_NUMBER() OVER (ORDER BY v.precio) AS rn, COUNT(*) OVER () AS n
               FROM v_observaciones v", w$sql, ")
    SELECT AVG(precio) AS mediana FROM x WHERE rn IN ((n + 1) / 2, (n + 2) / 2)"), w$params)$mediana
}

# Ahorro entre comercios por producto comparable, en una ejecución. Los empates en el precio
# mínimo se reportan todos (comercios_mas_baratos).
ahorro_por_producto <- function(con, ejecucion, comercios = character()) {
  fc <- if (length(comercios)) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste0("
    WITH c AS (SELECT * FROM v_comparables WHERE ejecucion_id = ? ", fc, "),
    m AS (SELECT producto_id, MIN(precio) AS precio_min, MAX(precio) AS precio_max, COUNT(*) AS n_comercios
          FROM c GROUP BY producto_id)
    SELECT m.producto_id, MAX(c.descripcion) AS producto, m.n_comercios, m.precio_min, m.precio_max,
           m.precio_max - m.precio_min AS ahorro_cop,
           ROUND(100.0 * (m.precio_max - m.precio_min) / m.precio_max, 1) AS ahorro_pct,
           GROUP_CONCAT(CASE WHEN c.precio = m.precio_min THEN c.comercio_nombre END, ', ') AS comercios_mas_baratos,
           SUM(c.precio = m.precio_min) AS n_empatados
    FROM m JOIN c ON c.producto_id = m.producto_id
    GROUP BY m.producto_id HAVING m.n_comercios >= 2
    ORDER BY ahorro_cop DESC"), c(list(ejecucion), as.list(comercios)))
}

ind_ahorro_maximo <- function(con, ejecucion, comercios = character()) {
  a <- ahorro_por_producto(con, ejecucion, comercios)
  if (!nrow(a)) return(NULL)
  a[1, ]
}

# Número de cambios de precio de la ejecución frente a la anterior (mismo anuncio)
ind_cambios_precio <- function(con, ejecucion, comercios = character()) {
  fc <- if (length(comercios)) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste0("
    SELECT COUNT(*) AS cambios, SUM(direccion = 'subió') AS subieron, SUM(direccion = 'bajó') AS bajaron,
           MAX(ejecucion_anterior) AS ejecucion_anterior
    FROM v_cambios_precio WHERE ejecucion_actual = ? AND direccion <> 'igual' ", fc),
    c(list(ejecucion), as.list(comercios)))
}

# Productos comparables en alguna ejecución (para elegir en la evolución y en la canasta)
listar_comparables <- function(con, ejecucion = NULL) {
  if (is.null(ejecucion) || is.na(ejecucion) || ejecucion == "todas")
    consultar(con, "SELECT DISTINCT producto_id, descripcion, subcategoria_std, unidad_norm, contenido_total
                    FROM v_comparables ORDER BY descripcion")
  else consultar(con, "SELECT DISTINCT producto_id, descripcion, subcategoria_std, unidad_norm, contenido_total
                       FROM v_comparables WHERE ejecucion_id = ? ORDER BY descripcion", list(ejecucion))
}

# Evolución del precio de un producto: una serie por comercio (todas sus observaciones válidas)
serie_producto <- function(con, producto_id) {
  consultar(con, "
    SELECT v.comercio, v.comercio_nombre, v.ejecucion_id, MIN(v.fecha_hora) AS fecha_hora, MIN(v.precio) AS precio
    FROM v_observaciones v
    WHERE v.producto_id = ? AND v.precio > 0
    GROUP BY v.comercio, v.ejecucion_id ORDER BY v.comercio, fecha_hora", list(producto_id))
}

# Precio por unidad de contenido entre comercios: una sola unidad por consulta (no se mezclan)
precio_unitario_comparables <- function(con, ejecucion, unidad, comercios = character(), subcategorias = character()) {
  fc <- if (length(comercios)) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  fs <- if (length(subcategorias)) sprintf("AND subcategoria_std IN (%s)", marcadores(length(subcategorias))) else ""
  consultar(con, paste0("
    SELECT producto_id, descripcion, subcategoria_std, contenido_total, unidad_norm,
           comercio, comercio_nombre, precio, precio_por_unidad
    FROM v_comparables
    WHERE ejecucion_id = ? AND unidad_norm = ? ", fc, " ", fs, "
    ORDER BY descripcion, comercio"), c(list(ejecucion, unidad), as.list(comercios), as.list(subcategorias)))
}

# Distribución de precios por comercio: cinco números calculados en SQL (rango por posición)
distribucion_precios <- function(con, f) {
  w <- construir_where(f)
  consultar(con, paste("
    WITH x AS (
      SELECT v.comercio, v.comercio_nombre, v.precio,
             ROW_NUMBER() OVER (PARTITION BY v.comercio ORDER BY v.precio) AS rn,
             COUNT(*)     OVER (PARTITION BY v.comercio) AS n
      FROM v_observaciones v", w$sql, ")
    SELECT comercio, comercio_nombre, MAX(n) AS n, MIN(precio) AS minimo,
           MAX(CASE WHEN rn = CAST(0.25 * (n - 1) AS INTEGER) + 1 THEN precio END) AS q1,
           AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN precio END) AS mediana,
           MAX(CASE WHEN rn = CAST(0.75 * (n - 1) AS INTEGER) + 1 THEN precio END) AS q3,
           MAX(precio) AS maximo
    FROM x GROUP BY comercio, comercio_nombre ORDER BY comercio_nombre"), w$params)
}

# Gráfico libre: ¿cuánto cuesta cada tableta/cápsula según la marca? Mismo principio activo y
# concentración, presentaciones sólidas (unidad), en una ejecución.
principios_dosis <- function(con, ejecucion) {
  consultar(con, "
    SELECT principio_activo_std AS principio, concentracion, COUNT(DISTINCT marca_std) AS marcas, COUNT(*) AS n
    FROM v_observaciones
    WHERE ejecucion_id = ? AND en_categoria = 1 AND unidad_norm = 'unidad' AND precio > 0
      AND concentracion IS NOT NULL AND concentracion NOT LIKE '%/%' AND principio_activo_std NOT LIKE '%+%'
      AND es_paquete_promo = 0
    GROUP BY principio_activo_std, concentracion HAVING COUNT(DISTINCT marca_std) >= 3
    ORDER BY n DESC", list(ejecucion))
}

precio_por_dosis <- function(con, ejecucion, principio, concentracion, comercios = character()) {
  fc <- if (length(comercios)) sprintf("AND comercio IN (%s)", marcadores(length(comercios))) else ""
  consultar(con, paste0("
    SELECT marca_std AS marca, comercio, comercio_nombre,
           MIN(precio_por_unidad) AS minimo_por_unidad, AVG(precio_por_unidad) AS promedio_por_unidad,
           COUNT(*) AS presentaciones
    FROM v_observaciones
    WHERE ejecucion_id = ? AND principio_activo_std = ? AND concentracion = ? AND unidad_norm = 'unidad'
      AND en_categoria = 1 AND precio > 0 AND es_paquete_promo = 0 ", fc, "
    GROUP BY marca_std, comercio ORDER BY minimo_por_unidad"),
    c(list(ejecucion, principio, concentracion), as.list(comercios)))
}

# Cambios de precio entre dos ejecuciones elegidas (mismo anuncio, mismo comercio)
comparar_ejecuciones <- function(con, ejecucion_a, ejecucion_b, comercios = character(), solo_categoria = TRUE) {
  fc <- if (length(comercios)) sprintf("AND x.comercio IN (%s)", marcadores(length(comercios))) else ""
  fcat <- if (isTRUE(solo_categoria)) "AND COALESCE(cl.en_categoria, 0) = 1" else ""
  consultar(con, paste0("
    WITH a AS (SELECT anuncio_id, comercio, precio FROM observaciones
               WHERE ejecucion_id = ? AND descartada = 0 AND precio > 0),
         b AS (SELECT anuncio_id, comercio, precio FROM observaciones
               WHERE ejecucion_id = ? AND descartada = 0 AND precio > 0),
         x AS (
           SELECT a.anuncio_id, a.comercio, a.precio AS precio_antes, b.precio AS precio_despues
           FROM a LEFT JOIN b ON b.anuncio_id = a.anuncio_id
           UNION ALL
           SELECT b.anuncio_id, b.comercio, NULL, b.precio FROM b
           WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.anuncio_id = b.anuncio_id))
    SELECT c.nombre AS comercio, an.nombre_original AS producto, x.precio_antes, x.precio_despues,
           x.precio_despues - x.precio_antes AS cambio_cop,
           ROUND(100.0 * (x.precio_despues - x.precio_antes) / x.precio_antes, 2) AS cambio_pct,
           CASE WHEN x.precio_antes IS NULL THEN 'nuevo'
                WHEN x.precio_despues IS NULL THEN 'dejó de observarse'
                WHEN x.precio_despues > x.precio_antes THEN 'subió'
                WHEN x.precio_despues < x.precio_antes THEN 'bajó' ELSE 'sin cambio' END AS tipo,
           CASE WHEN an.url LIKE '/%' THEN c.base_url || an.url ELSE an.url END AS enlace
    FROM x JOIN anuncios an ON an.anuncio_id = x.anuncio_id
    JOIN comercios c ON c.comercio = x.comercio
    LEFT JOIN clasificacion cl ON cl.anuncio_id = x.anuncio_id
    WHERE 1 = 1 ", fc, " ", fcat, "
    ORDER BY ABS(COALESCE(x.precio_despues - x.precio_antes, 0)) DESC, c.nombre, an.nombre_original"),
    c(list(ejecucion_a, ejecucion_b), as.list(comercios)))
}

# seleccion: data.frame(producto_id, cantidad). Con precios de UNA ejecución:
#   por_comercio: total por comercio solo si tiene TODOS los productos (si no, completo = 0 y
#                 total NA, con la lista de faltantes);
#   optima:       costo comprando cada producto donde es más barato (empates: todos los comercios).
canasta <- function(con, ejecucion, seleccion) {
  seleccion <- seleccion[!is.na(seleccion$producto_id) & seleccion$cantidad > 0, , drop = FALSE]
  if (!nrow(seleccion)) return(NULL)
  valores <- paste(rep("(?, ?)", nrow(seleccion)), collapse = ", ")
  p_sel <- unlist(lapply(seq_len(nrow(seleccion)), function(i)
    list(seleccion$producto_id[i], as.integer(seleccion$cantidad[i]))), recursive = FALSE)
  base <- paste0("
    WITH sel(producto_id, cantidad) AS (VALUES ", valores, "),
    precios AS (SELECT producto_id, comercio, comercio_nombre, precio FROM v_comparables WHERE ejecucion_id = ?),
    com AS (SELECT comercio, nombre AS comercio_nombre FROM comercios)")
  por_comercio <- consultar(con, paste0(base, "
    SELECT com.comercio, com.comercio_nombre,
           COUNT(p.precio) AS productos_con_precio, (SELECT COUNT(*) FROM sel) AS productos_pedidos,
           CASE WHEN COUNT(p.precio) = (SELECT COUNT(*) FROM sel) THEN SUM(p.precio * s.cantidad) END AS total,
           CASE WHEN COUNT(p.precio) = (SELECT COUNT(*) FROM sel) THEN 1 ELSE 0 END AS completo,
           GROUP_CONCAT(CASE WHEN p.precio IS NULL THEN s.producto_id END, ', ') AS faltantes
    FROM com CROSS JOIN sel s
    LEFT JOIN precios p ON p.producto_id = s.producto_id AND p.comercio = com.comercio
    GROUP BY com.comercio, com.comercio_nombre ORDER BY total IS NULL, total"), c(p_sel, list(ejecucion)))
  detalle <- consultar(con, paste0(base, ",
    m AS (SELECT p.producto_id, MIN(p.precio) AS precio_min FROM precios p JOIN sel s USING (producto_id)
          GROUP BY p.producto_id)
    SELECT s.producto_id, s.cantidad, m.precio_min, m.precio_min * s.cantidad AS subtotal,
           (SELECT GROUP_CONCAT(p.comercio_nombre, ', ') FROM precios p
             WHERE p.producto_id = s.producto_id AND p.precio = m.precio_min) AS donde_comprar
    FROM sel s LEFT JOIN m ON m.producto_id = s.producto_id"), c(p_sel, list(ejecucion)))
  optima_completa <- all(!is.na(detalle$precio_min))
  list(por_comercio = por_comercio, detalle = detalle,
       optima = if (optima_completa) sum(detalle$subtotal) else NA_real_)
}

progreso_actualizacion <- function(con, actualizacion_id) consultar(con, "
  SELECT l.comercio, c.nombre AS comercio_nombre, l.ejecucion_id, l.modo, l.estado, l.inicio, l.fin,
         l.recolectados, l.nuevos, l.insertadas, l.rechazadas, l.cambios_precio, l.no_observados, l.motivo
  FROM log_actualizaciones l JOIN comercios c ON c.comercio = l.comercio
  WHERE l.actualizacion_id = ? ORDER BY l.log_id", list(actualizacion_id))

resumen_ejecuciones <- function(con) consultar(con, "
  SELECT ejecucion_id, comercio_nombre AS comercio, inicio, fin, modo, estado, total_sitio,
         observaciones_validas, rechazadas FROM v_resumen_ejecuciones ORDER BY ejecucion_id DESC, comercio")

validaciones_ejecucion <- function(con, ejecucion) consultar(con, "
  SELECT c.nombre AS comercio, v.regla, v.evaluadas, v.fallas, v.resultado, v.detalle
  FROM validaciones v JOIN comercios c ON c.comercio = v.comercio
  WHERE v.ejecucion_id = ? ORDER BY c.nombre, v.regla", list(ejecucion))
