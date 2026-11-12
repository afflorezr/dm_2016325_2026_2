# db.R — Capa de acceso a datos · Taller 2 · cuidado bucal.
#
# Todas las consultas SQL de la aplicación están aquí. Cada función recibe la conexión y los
# filtros como argumentos y devuelve una tabla; la interfaz (app.R) no contiene SQL.
# Filtros, indicadores y agregaciones se calculan en SQLite sobre las vistas de vistas.sql.
# Los valores que vienen del usuario nunca se concatenan al texto de la consulta: van como
# parámetros (`params`) o se interpolan con glue::glue_sql(), que los escapa como literales.

# ---------------------------------------------------------------------------
# Conexión
# ---------------------------------------------------------------------------

# Abre la conexión de lectura de la aplicación (una sola por proceso; se cierra con cerrar_conexion).
abrir_conexion <- function(db_path = "comparador_precios.sqlite") {
  if (!file.exists(db_path)) stop("No se encontró la base de datos: ", db_path, call. = FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  DBI::dbExecute(con, "PRAGMA busy_timeout = 15000")
  DBI::dbExecute(con, "PRAGMA query_only = ON")
  con
}
cerrar_conexion <- function(con) {
  if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con)
  invisible(TRUE)
}
.q <- function(con, sql, ...) {
  if (...length() == 0) DBI::dbGetQuery(con, sql) else DBI::dbGetQuery(con, sql, params = unname(list(...)))
}

# ---------------------------------------------------------------------------
# Validación de entradas de texto
# ---------------------------------------------------------------------------
MAX_BUSQUEDA <- 60L

# Valida el texto de búsqueda: longitud máxima y solo letras, números, espacios y . , % + -
# Devuelve list(ok, palabras, mensaje).
validar_busqueda <- function(texto) {
  texto <- trimws(if (is.null(texto) || length(texto) == 0 || is.na(texto[1])) "" else as.character(texto[1]))
  if (!nzchar(texto)) return(list(ok = TRUE, palabras = character(0), mensaje = NULL))
  if (nchar(texto) > MAX_BUSQUEDA) {
    return(list(ok = FALSE, palabras = character(0),
                mensaje = sprintf("La búsqueda admite máximo %d caracteres.", MAX_BUSQUEDA)))
  }
  if (!grepl("^[\\p{L}\\p{N} .,%+-]+$", texto, perl = TRUE)) {
    return(list(ok = FALSE, palabras = character(0),
                mensaje = "La búsqueda solo admite letras, números, espacios y los signos . , % + -"))
  }
  list(ok = TRUE, palabras = utils::head(strsplit(texto, "\\s+")[[1]], 6), mensaje = NULL)
}

# Lista de filtros con valores por defecto (NULL = sin filtrar por ese criterio).
filtros <- function(comercios = NULL, subcategorias = NULL, marcas = NULL, precio_min = NULL, precio_max = NULL,
                    ejecucion = NULL, fecha_desde = NULL, fecha_hasta = NULL, solo_promociones = FALSE,
                    solo_comparables = FALSE, texto = NULL) {
  list(comercios = comercios, subcategorias = subcategorias, marcas = marcas, precio_min = precio_min,
       precio_max = precio_max, ejecucion = ejecucion, fecha_desde = fecha_desde, fecha_hasta = fecha_hasta,
       solo_promociones = isTRUE(solo_promociones), solo_comparables = isTRUE(solo_comparables), texto = texto)
}

# Condición WHERE (sobre v_catalogo, alias v) que corresponde a los filtros.
.where <- function(con, f) {
  cond <- list(DBI::SQL("1 = 1"))
  agregar <- function(x) cond[[length(cond) + 1]] <<- x
  if (length(f$comercios)) agregar(glue::glue_sql("v.comercio_id IN ({f$comercios*})", .con = con))
  if (length(f$subcategorias)) agregar(glue::glue_sql("v.subcategoria IN ({f$subcategorias*})", .con = con))
  if (length(f$marcas)) agregar(glue::glue_sql("v.marca IN ({f$marcas*})", .con = con))
  if (!is.null(f$precio_min)) agregar(glue::glue_sql("v.precio >= {as.numeric(f$precio_min)}", .con = con))
  if (!is.null(f$precio_max)) agregar(glue::glue_sql("v.precio <= {as.numeric(f$precio_max)}", .con = con))
  if (!is.null(f$ejecucion)) agregar(glue::glue_sql("v.ejecucion_id = {as.character(f$ejecucion)}", .con = con))
  if (!is.null(f$fecha_desde)) agregar(glue::glue_sql("v.fecha >= {as.character(f$fecha_desde)}", .con = con))
  if (!is.null(f$fecha_hasta)) agregar(glue::glue_sql("v.fecha <= {as.character(f$fecha_hasta)}", .con = con))
  if (f$solo_promociones) agregar(DBI::SQL("v.es_promocion = 1"))
  if (f$solo_comparables) agregar(DBI::SQL("v.comparable = 1"))
  b <- validar_busqueda(f$texto)
  if (b$ok) {
    for (palabra in b$palabras) {
      patron <- paste0("%", gsub("([%_\\\\])", "\\\\\\1", palabra), "%")      # % y _ se buscan como texto
      agregar(glue::glue_sql("(v.nombre LIKE {patron} ESCAPE '\\' OR v.texto_original LIKE {patron} ESCAPE '\\')",
                             .con = con))
    }
  }
  glue::glue_sql_collapse(cond, sep = " AND ")
}

# ---------------------------------------------------------------------------
# Opciones de los filtros y ejecuciones
# ---------------------------------------------------------------------------

# Ejecuciones de la base, de la más reciente a la más antigua, con su estado por comercio.
listar_ejecuciones <- function(con) {
  .q(con, paste(
    "SELECT e.ejecucion_id, MIN(e.inicio) AS inicio, MAX(e.fin) AS fin, substr(MIN(e.inicio), 1, 10) AS fecha,",
    "COUNT(*) AS comercios, SUM(e.estado = 'completa') AS completas, SUM(e.estado = 'parcial') AS parciales,",
    "SUM(e.estado = 'fallida') AS fallidas, SUM(e.n_registros) AS registros, SUM(e.n_rechazadas) AS rechazadas,",
    "GROUP_CONCAT(DISTINCT e.modo_carga) AS modo,",
    "CASE WHEN SUM(e.estado = 'fallida') = COUNT(*) THEN 'fallida'",
    "     WHEN SUM(e.estado = 'completa') = COUNT(*) THEN 'completa' ELSE 'parcial' END AS estado",
    "FROM ejecuciones e GROUP BY e.ejecucion_id ORDER BY e.ejecucion_id DESC"))
}

# Detalle de las ejecuciones por comercio (pestaña de calidad de datos).
detalle_ejecuciones <- function(con) {
  .q(con, paste(
    "SELECT e.ejecucion_id, c.nombre AS comercio, e.inicio, e.fin, e.modo_carga, e.estado, e.n_registros,",
    "e.n_productos, e.total_reportado_sitio, e.n_rechazadas, e.mensaje, e.carpeta_raw",
    "FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id ORDER BY e.ejecucion_id DESC, c.nombre"))
}

# Valores disponibles para armar los filtros.
opciones_filtros <- function(con) {
  list(
    comercios = .q(con, "SELECT comercio_id, nombre FROM comercios ORDER BY nombre"),
    subcategorias = .q(con, "SELECT subcategoria, COUNT(DISTINCT anuncio_id) AS n FROM v_catalogo WHERE subcategoria IS NOT NULL GROUP BY subcategoria ORDER BY subcategoria"),
    marcas = .q(con, "SELECT marca, COUNT(DISTINCT anuncio_id) AS n FROM v_catalogo WHERE marca IS NOT NULL GROUP BY marca ORDER BY n DESC, marca"),
    precios = .q(con, "SELECT MIN(precio) AS minimo, MAX(precio) AS maximo FROM v_catalogo WHERE precio IS NOT NULL"),
    fechas = .q(con, "SELECT MIN(fecha) AS desde, MAX(fecha) AS hasta FROM v_catalogo"))
}

# ---------------------------------------------------------------------------
# Tabla de productos
# ---------------------------------------------------------------------------
productos_filtrados <- function(con, f, limite = NULL) {
  sql <- glue::glue_sql(
    "SELECT v.comercio, v.nombre, v.marca, v.subcategoria, v.presentacion, v.precio, v.precio_unitario, v.unidad,
            v.es_promocion, v.precio_lista, COALESCE(v.disponibilidad, 'sin dato') AS disponibilidad,
            v.fecha_hora_consulta, v.ejecucion_id, v.comparable, v.url_producto, v.nombre_original
       FROM v_catalogo v WHERE {.where(con, f)}
      ORDER BY v.nombre, v.comercio, v.fecha_hora_consulta", .con = con)
  if (!is.null(limite)) sql <- glue::glue_sql("{sql} LIMIT {as.integer(limite)}", .con = con)
  DBI::dbGetQuery(con, sql)
}

# ---------------------------------------------------------------------------
# Indicadores
# ---------------------------------------------------------------------------

# Indicadores generales de la selección: productos, observaciones, promociones, agotados y mediana.
indicadores <- function(con, f) {
  w <- .where(con, f)
  DBI::dbGetQuery(con, glue::glue_sql(
    "WITH sel AS (SELECT v.* FROM v_catalogo v WHERE {w}),
          ord AS (SELECT precio, ROW_NUMBER() OVER (ORDER BY precio) AS rn, COUNT(*) OVER () AS n
                    FROM sel WHERE precio IS NOT NULL)
     SELECT (SELECT COUNT(DISTINCT anuncio_id) FROM sel) AS productos,
            (SELECT COUNT(*) FROM sel) AS observaciones,
            (SELECT COUNT(*) FROM sel WHERE precio IS NOT NULL) AS con_precio,
            (SELECT 100.0 * SUM(es_promocion) / COUNT(*) FROM sel WHERE precio IS NOT NULL) AS pct_promocion,
            (SELECT 100.0 * SUM(disponibilidad = 'agotado') / COUNT(*) FROM sel) AS pct_agotado,
            (SELECT AVG(precio) FROM ord WHERE rn IN ((n + 1) / 2, (n + 2) / 2)) AS mediana_precio", .con = con))
}

# Productos y observaciones por comercio en la selección.
conteo_por_comercio <- function(con, f) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT v.comercio_id, v.comercio, COUNT(DISTINCT v.anuncio_id) AS productos, COUNT(*) AS observaciones,
            SUM(v.precio IS NOT NULL) AS con_precio, SUM(v.es_promocion) AS en_promocion,
            SUM(v.disponibilidad = 'agotado') AS agotados
       FROM v_catalogo v WHERE {.where(con, f)} GROUP BY v.comercio_id, v.comercio ORDER BY v.comercio", .con = con))
}

# Mediana del precio (COP) por subcategoría en la selección.
mediana_por_subcategoria <- function(con, f) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT subcategoria, AVG(precio) AS mediana, MAX(n) AS observaciones
       FROM (SELECT v.subcategoria, v.precio,
                    ROW_NUMBER() OVER (PARTITION BY v.subcategoria ORDER BY v.precio) AS rn,
                    COUNT(*) OVER (PARTITION BY v.subcategoria) AS n
               FROM v_catalogo v WHERE {.where(con, f)} AND v.precio IS NOT NULL AND v.subcategoria IS NOT NULL)
      WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY subcategoria ORDER BY mediana DESC", .con = con))
}

# Fecha y estado de la última ejecución (una fila por comercio).
ultima_ejecucion <- function(con) {
  .q(con, paste(
    "SELECT e.ejecucion_id, c.nombre AS comercio, e.inicio, e.fin, e.estado, e.modo_carga, e.n_registros, e.mensaje",
    "FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id",
    "WHERE e.ejecucion_id = (SELECT MAX(ejecucion_id) FROM ejecuciones) ORDER BY c.nombre"))
}

# Número de cambios de precio de una ejecución frente a la observación anterior de cada anuncio.
cambios_en_ejecucion <- function(con, ejecucion) {
  .q(con, paste(
    "SELECT COUNT(*) AS cambios, COALESCE(SUM(tipo_cambio = 'subió'), 0) AS subieron,",
    "COALESCE(SUM(tipo_cambio = 'bajó'), 0) AS bajaron FROM v_cambios_precio WHERE ejecucion_id = ?"), ejecucion)
}

# ---------------------------------------------------------------------------
# Productos comparables
# ---------------------------------------------------------------------------

# Presentaciones comparables (para los selectores). Las ocho de referencia van primero.
lista_comparables <- function(con, solo_verificados = FALSE) {
  d <- .q(con, paste(
    "SELECT p.producto_id, p.nombre_estandar AS producto, p.subcategoria, p.marca, p.contenido_total,",
    "CASE p.unidad WHEN 'ml' THEN 'mL' WHEN 'und' THEN 'unidad' ELSE p.unidad END AS unidad,",
    "p.contenido_verificado, r.orden AS orden_referencia",
    "FROM productos p LEFT JOIN comparables_referencia r ON r.producto_id = p.producto_id",
    "WHERE p.comparable = 1 ORDER BY (r.orden IS NULL), r.orden, p.subcategoria, p.nombre_estandar"))
  if (solo_verificados) d[d$contenido_verificado == 1, , drop = FALSE] else d
}

# Precio de una presentación comparable en cada comercio y ejecución (gráfico de evolución).
evolucion_precio <- function(con, producto_id, comercios = NULL) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT c.ejecucion_id, c.comercio_id, c.comercio, c.fecha_hora_consulta, c.precio, c.disponibilidad, c.producto
       FROM v_comparables c WHERE c.producto_id = {as.character(producto_id)}
        {if (length(comercios)) glue::glue_sql('AND c.comercio_id IN ({comercios*})', .con = con) else DBI::SQL('')}
      ORDER BY c.ejecucion_id, c.comercio", .con = con))
}

# Precio por unidad de contenido de las presentaciones comparables de UNA unidad de medida
# (mL, g, m o unidad) en una ejecución: nunca se mezclan unidades en la misma comparación.
precio_unitario_comparables <- function(con, ejecucion, unidad, subcategoria = NULL, comercios = NULL) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT c.producto_id, c.producto, c.subcategoria, c.presentacion, c.contenido_total, c.unidad, c.comercio_id,
            c.comercio, c.precio, c.precio_unitario
       FROM v_comparables c
      WHERE c.ejecucion_id = {as.character(ejecucion)} AND c.unidad = {as.character(unidad)}
        AND c.comprable = 1 AND c.precio_unitario IS NOT NULL
        {if (length(subcategoria)) glue::glue_sql('AND c.subcategoria IN ({subcategoria*})', .con = con) else DBI::SQL('')}
        {if (length(comercios)) glue::glue_sql('AND c.comercio_id IN ({comercios*})', .con = con) else DBI::SQL('')}
      ORDER BY c.producto, c.comercio", .con = con))
}

# Unidades de medida que tienen comparables con precio unitario en una ejecución.
unidades_comparables <- function(con, ejecucion) {
  .q(con, paste("SELECT unidad, COUNT(DISTINCT producto_id) AS n FROM v_comparables",
                "WHERE ejecucion_id = ? AND comprable = 1 AND precio_unitario IS NOT NULL GROUP BY unidad ORDER BY n DESC"),
     ejecucion)
}

# Resumen de la distribución de precios por comercio en la selección: mínimo, percentil 5,
# cuartiles, percentil 95 y máximo (posiciones calculadas en SQL por rango más cercano).
distribucion_precios <- function(con, f) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT comercio_id, comercio, MAX(n) AS observaciones, MIN(precio) AS minimo,
            MAX(CASE WHEN rn = (n + 19) / 20 THEN precio END) AS p05,
            MAX(CASE WHEN rn = (n + 3) / 4 THEN precio END) AS q1,
            AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN precio END) AS mediana,
            MAX(CASE WHEN rn = (3 * n + 3) / 4 THEN precio END) AS q3,
            MAX(CASE WHEN rn = (19 * n + 19) / 20 THEN precio END) AS p95, MAX(precio) AS maximo
       FROM (SELECT v.comercio_id, v.comercio, v.precio,
                    ROW_NUMBER() OVER (PARTITION BY v.comercio_id ORDER BY v.precio) AS rn,
                    COUNT(*) OVER (PARTITION BY v.comercio_id) AS n
               FROM v_catalogo v WHERE {.where(con, f)} AND v.precio IS NOT NULL)
      GROUP BY comercio_id, comercio ORDER BY comercio", .con = con))
}

# Ahorro por presentación comparable en una ejecución: diferencia entre el comercio más caro y el
# más barato (COP y %). En caso de empate en el precio mínimo se listan todos los comercios.
ahorro_por_producto <- function(con, ejecucion, comercios = NULL, subcategorias = NULL) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "WITH p AS (SELECT c.* FROM v_comparables c WHERE c.ejecucion_id = {as.character(ejecucion)} AND c.comprable = 1
                 {if (length(comercios)) glue::glue_sql('AND c.comercio_id IN ({comercios*})', .con = con) else DBI::SQL('')}
                 {if (length(subcategorias)) glue::glue_sql('AND c.subcategoria IN ({subcategorias*})', .con = con) else DBI::SQL('')}),
          r AS (SELECT producto_id, MIN(precio) AS precio_min, MAX(precio) AS precio_max, COUNT(*) AS n_comercios
                  FROM p GROUP BY producto_id HAVING COUNT(*) >= 2)
     SELECT p.producto_id, p.producto, p.subcategoria, r.n_comercios, r.precio_min, r.precio_max,
            r.precio_max - r.precio_min AS ahorro_cop,
            100.0 * (r.precio_max - r.precio_min) / r.precio_max AS ahorro_pct,
            GROUP_CONCAT(CASE WHEN p.precio = r.precio_min THEN p.comercio END, ' / ') AS comercio_mas_barato,
            SUM(p.precio = r.precio_min) AS n_empatados,
            MIN(CASE WHEN p.precio = r.precio_min THEN p.comercio_id END) AS comercio_id_min
       FROM p JOIN r ON r.producto_id = p.producto_id
      GROUP BY p.producto_id, p.producto, p.subcategoria, r.n_comercios, r.precio_min, r.precio_max
      ORDER BY ahorro_cop DESC, p.producto", .con = con))
}

# Cuántos productos comparables son más baratos en cada comercio (empates aparte), con los mismos
# criterios que ahorro_por_producto(). Devuelve grupo (comercio_id o "empate"), comercio y n.
quien_es_mas_barato <- function(con, ejecucion, comercios = NULL, subcategorias = NULL) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "WITH p AS (SELECT c.* FROM v_comparables c WHERE c.ejecucion_id = {as.character(ejecucion)} AND c.comprable = 1
                 {if (length(comercios)) glue::glue_sql('AND c.comercio_id IN ({comercios*})', .con = con) else DBI::SQL('')}
                 {if (length(subcategorias)) glue::glue_sql('AND c.subcategoria IN ({subcategorias*})', .con = con) else DBI::SQL('')}),
          r AS (SELECT producto_id, MIN(precio) AS precio_min FROM p GROUP BY producto_id HAVING COUNT(*) >= 2),
          g AS (SELECT p.producto_id, CASE WHEN COUNT(*) > 1 THEN 'empate' ELSE MIN(p.comercio_id) END AS grupo,
                       CASE WHEN COUNT(*) > 1 THEN 'Empate entre comercios' ELSE MIN(p.comercio) END AS comercio
                  FROM p JOIN r ON r.producto_id = p.producto_id AND p.precio = r.precio_min GROUP BY p.producto_id)
     SELECT grupo, comercio, COUNT(*) AS n FROM g GROUP BY grupo, comercio
      ORDER BY (grupo = 'empate'), n DESC", .con = con))
}

# Composición del catálogo de cada comercio: anuncios por subcategoría y su porcentaje dentro del
# comercio. Las `n` subcategorías con más anuncios en la selección se muestran; el resto va a «Otras».
composicion_catalogo <- function(con, f, n = 6L) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "WITH base AS (SELECT v.comercio_id, v.comercio, v.subcategoria, COUNT(DISTINCT v.anuncio_id) AS anuncios
                     FROM v_catalogo v WHERE {.where(con, f)} AND v.subcategoria IS NOT NULL
                    GROUP BY v.comercio_id, v.comercio, v.subcategoria),
          top AS (SELECT subcategoria FROM base GROUP BY subcategoria ORDER BY SUM(anuncios) DESC LIMIT {as.integer(n)}),
          agr AS (SELECT comercio_id, comercio,
                         CASE WHEN subcategoria IN (SELECT subcategoria FROM top) THEN subcategoria ELSE 'Otras' END AS grupo,
                         SUM(anuncios) AS anuncios FROM base GROUP BY 1, 2, 3)
     SELECT a.comercio_id, a.comercio, a.grupo, a.anuncios,
            100.0 * a.anuncios / SUM(a.anuncios) OVER (PARTITION BY a.comercio_id) AS pct
       FROM agr a LEFT JOIN (SELECT grupo, SUM(anuncios) AS total FROM agr GROUP BY grupo) t ON t.grupo = a.grupo
      ORDER BY a.comercio, (a.grupo = 'Otras'), t.total DESC", .con = con))
}

# Marcas con más anuncios en cada comercio (las `n` primeras de cada uno).
marcas_por_comercio <- function(con, f, n = 9L) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT comercio_id, comercio, marca, anuncios FROM (
       SELECT v.comercio_id, v.comercio, v.marca, COUNT(DISTINCT v.anuncio_id) AS anuncios,
              ROW_NUMBER() OVER (PARTITION BY v.comercio_id ORDER BY COUNT(DISTINCT v.anuncio_id) DESC, v.marca) AS rn
         FROM v_catalogo v WHERE {.where(con, f)} AND v.marca IS NOT NULL GROUP BY v.comercio_id, v.comercio, v.marca)
      WHERE rn <= {as.integer(n)} ORDER BY comercio, anuncios DESC", .con = con))
}

# Jerarquía comercio > subcategoría > marca (para el sunburst). Por comercio se muestran las
# `n_sub` subcategorías con más anuncios y, dentro de cada una, las `n_marca` marcas principales;
# el resto se agrupa en «Otras subcategorías» y «Otras marcas».
jerarquia_catalogo <- function(con, f, n_sub = 5L, n_marca = 3L) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "WITH base AS (SELECT v.comercio_id, v.comercio, v.subcategoria, COALESCE(v.marca, 'Sin marca') AS marca,
                          COUNT(DISTINCT v.anuncio_id) AS anuncios
                     FROM v_catalogo v WHERE {.where(con, f)} AND v.subcategoria IS NOT NULL
                    GROUP BY 1, 2, 3, 4),
          rs AS (SELECT comercio_id, subcategoria,
                        ROW_NUMBER() OVER (PARTITION BY comercio_id ORDER BY SUM(anuncios) DESC, subcategoria) AS r
                   FROM base GROUP BY comercio_id, subcategoria),
          b2 AS (SELECT b.comercio_id, b.comercio,
                        CASE WHEN rs.r <= {as.integer(n_sub)} THEN b.subcategoria ELSE 'Otras subcategorías' END AS subcategoria,
                        b.marca, b.anuncios
                   FROM base b JOIN rs ON rs.comercio_id = b.comercio_id AND rs.subcategoria = b.subcategoria),
          b3 AS (SELECT comercio_id, comercio, subcategoria, marca, SUM(anuncios) AS anuncios FROM b2 GROUP BY 1, 2, 3, 4),
          rm AS (SELECT b3.*, ROW_NUMBER() OVER (PARTITION BY comercio_id, subcategoria ORDER BY anuncios DESC, marca) AS r FROM b3)
     SELECT comercio_id, comercio, subcategoria,
            CASE WHEN r <= {as.integer(n_marca)} THEN marca ELSE 'Otras marcas' END AS marca, SUM(anuncios) AS anuncios
       FROM rm GROUP BY 1, 2, 3, 4 ORDER BY comercio, subcategoria, anuncios DESC", .con = con))
}

# Perfil de cada comercio en la selección: anuncios, precio mediano, % en promoción y % agotado.
perfil_comercios <- function(con, f) {
  DBI::dbGetQuery(con, glue::glue_sql(
    "WITH sel AS (SELECT v.* FROM v_catalogo v WHERE {.where(con, f)}),
          ord AS (SELECT comercio_id, precio, ROW_NUMBER() OVER (PARTITION BY comercio_id ORDER BY precio) AS rn,
                         COUNT(*) OVER (PARTITION BY comercio_id) AS n FROM sel WHERE precio IS NOT NULL)
     SELECT s.comercio_id, s.comercio, COUNT(DISTINCT s.anuncio_id) AS anuncios, COUNT(DISTINCT s.marca) AS marcas,
            (SELECT AVG(o.precio) FROM ord o WHERE o.comercio_id = s.comercio_id AND o.rn IN ((o.n + 1) / 2, (o.n + 2) / 2)) AS mediana,
            100.0 * SUM(CASE WHEN s.precio IS NOT NULL THEN s.es_promocion ELSE 0 END) / NULLIF(SUM(s.precio IS NOT NULL), 0) AS pct_promocion,
            100.0 * SUM(s.disponibilidad = 'agotado') / COUNT(*) AS pct_agotado
       FROM sel s GROUP BY s.comercio_id, s.comercio ORDER BY s.comercio", .con = con))
}

# ---------------------------------------------------------------------------
# Cambios de precio entre dos ejecuciones
# ---------------------------------------------------------------------------

# Compara dos ejecuciones sobre el MISMO anuncio en el MISMO comercio. Devuelve list(cambios,
# nuevos, no_observados, resumen). `umbral` (porcentaje) marca las variaciones grandes.
comparar_ejecuciones <- function(con, anterior, actual, comercios = NULL, umbral = 10) {
  fc <- function(alias) {
    if (length(comercios)) glue::glue_sql("AND {`alias`}.comercio_id IN ({comercios*})", .con = con) else DBI::SQL("")
  }
  anterior <- as.character(anterior); actual <- as.character(actual); umbral <- as.numeric(umbral)
  cambios <- DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT b.comercio, b.nombre, b.marca, b.presentacion, a.precio AS precio_anterior, b.precio AS precio_actual,
            b.precio - a.precio AS cambio_cop, 100.0 * (b.precio - a.precio) / a.precio AS cambio_pct,
            CASE WHEN b.precio > a.precio THEN 'subió' ELSE 'bajó' END AS tipo,
            CASE WHEN ABS(100.0 * (b.precio - a.precio) / a.precio) >= {umbral} THEN 1 ELSE 0 END AS variacion_grande,
            b.comparable, b.url_producto
       FROM v_catalogo b JOIN v_catalogo a ON a.anuncio_id = b.anuncio_id AND a.ejecucion_id = {anterior}
      WHERE b.ejecucion_id = {actual} AND a.precio IS NOT NULL AND b.precio IS NOT NULL AND a.precio <> b.precio {fc('b')}
      ORDER BY ABS(100.0 * (b.precio - a.precio) / a.precio) DESC", .con = con))
  nuevos <- DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT b.comercio, b.nombre, b.marca, b.presentacion, b.precio, COALESCE(b.disponibilidad, 'sin dato') AS disponibilidad,
            b.url_producto
       FROM v_catalogo b
      WHERE b.ejecucion_id = {actual} {fc('b')}
        AND NOT EXISTS (SELECT 1 FROM observaciones o WHERE o.anuncio_id = b.anuncio_id AND o.ejecucion_id = {anterior})
      ORDER BY b.comercio, b.nombre", .con = con))
  no_obs <- DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT a.comercio, a.nombre, a.marca, a.presentacion, a.precio AS ultimo_precio,
            COALESCE(a.disponibilidad, 'sin dato') AS disponibilidad_anterior, a.url_producto
       FROM v_catalogo a
      WHERE a.ejecucion_id = {anterior} {fc('a')}
        AND EXISTS (SELECT 1 FROM ejecuciones e WHERE e.ejecucion_id = {actual} AND e.comercio_id = a.comercio_id
                       AND e.estado <> 'fallida')
        AND NOT EXISTS (SELECT 1 FROM observaciones o WHERE o.anuncio_id = a.anuncio_id AND o.ejecucion_id = {actual})
      ORDER BY a.comercio, a.nombre", .con = con))
  comunes <- DBI::dbGetQuery(con, glue::glue_sql(
    "SELECT COUNT(*) AS n FROM v_catalogo b JOIN v_catalogo a ON a.anuncio_id = b.anuncio_id AND a.ejecucion_id = {anterior}
      WHERE b.ejecucion_id = {actual} AND a.precio IS NOT NULL AND b.precio IS NOT NULL {fc('b')}", .con = con))$n
  list(cambios = cambios, nuevos = nuevos, no_observados = no_obs,
       resumen = data.frame(comparados = comunes, subieron = sum(cambios$tipo == "subió"),
                            bajaron = sum(cambios$tipo == "bajó"), grandes = sum(cambios$variacion_grande),
                            nuevos = nrow(nuevos), no_observados = nrow(no_obs)))
}

# ---------------------------------------------------------------------------
# Canasta
# ---------------------------------------------------------------------------

# items: data.frame(producto_id, cantidad). Con precios de UNA ejecución calcula:
#   detalle      precio de cada producto en cada comercio (NA si no se puede comprar allí);
#   por_comercio costo de la canasta en cada comercio, solo si tiene TODOS los productos; si
#                falta alguno el total queda NA y `faltantes` dice cuáles;
#   optimo       cada producto en el comercio donde es más barato (en empate se listan todos);
#   resumen      costo mínimo combinando comercios y ahorro frente al mejor comercio único.
calcular_canasta <- function(con, items, ejecucion, comercios = NULL) {
  items <- items[!is.na(items$cantidad) & items$cantidad > 0, , drop = FALSE]
  vacio <- list(detalle = data.frame(), por_comercio = data.frame(), optimo = data.frame(), resumen = NULL)
  if (nrow(items) == 0) return(vacio)
  valores <- glue::glue_sql_collapse(lapply(seq_len(nrow(items)), function(i) {
    glue::glue_sql("({as.character(items$producto_id[i])}, {as.numeric(items$cantidad[i])})", .con = con)
  }), sep = ", ")
  ejecucion <- as.character(ejecucion)
  fcom <- if (length(comercios)) glue::glue_sql("AND e.comercio_id IN ({comercios*})", .con = con) else DBI::SQL("")
  base <- glue::glue_sql(
    "WITH canasta(producto_id, cantidad) AS (VALUES {valores}),
          tiendas AS (SELECT e.comercio_id, c.nombre AS comercio FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id
                       WHERE e.ejecucion_id = {ejecucion} AND e.estado <> 'fallida' {fcom}),
          celda AS (SELECT k.producto_id, k.cantidad, t.comercio_id, t.comercio, p.nombre_estandar AS producto,
                           CASE WHEN v.comprable = 1 THEN v.precio END AS precio
                      FROM canasta k CROSS JOIN tiendas t
                      LEFT JOIN productos p ON p.producto_id = k.producto_id
                      LEFT JOIN v_comparables v ON v.producto_id = k.producto_id AND v.comercio_id = t.comercio_id
                                               AND v.ejecucion_id = {ejecucion})", .con = con)
  detalle <- DBI::dbGetQuery(con, glue::glue_sql(
    "{base} SELECT producto_id, producto, cantidad, comercio_id, comercio, precio, precio * cantidad AS subtotal
              FROM celda ORDER BY producto, comercio", .con = con))
  por_comercio <- DBI::dbGetQuery(con, glue::glue_sql(
    "{base} SELECT comercio_id, comercio, COUNT(*) AS productos, SUM(precio IS NULL) AS n_faltantes,
                   CASE WHEN SUM(precio IS NULL) = 0 THEN SUM(precio * cantidad) END AS total,
                   GROUP_CONCAT(CASE WHEN precio IS NULL THEN producto END, '; ') AS faltantes
              FROM celda GROUP BY comercio_id, comercio ORDER BY (total IS NULL), total, comercio", .con = con))
  optimo <- DBI::dbGetQuery(con, glue::glue_sql(
    "{base}, m AS (SELECT producto_id, MIN(precio) AS precio_min FROM celda GROUP BY producto_id)
     SELECT c.producto_id, c.producto, c.cantidad, m.precio_min AS precio, m.precio_min * c.cantidad AS subtotal,
            GROUP_CONCAT(CASE WHEN c.precio = m.precio_min THEN c.comercio END, ' / ') AS comercio,
            SUM(c.precio = m.precio_min) AS n_empatados
       FROM celda c JOIN m ON m.producto_id = c.producto_id
      GROUP BY c.producto_id, c.producto, c.cantidad, m.precio_min ORDER BY c.producto", .con = con))
  completos <- por_comercio[!is.na(por_comercio$total), , drop = FALSE]
  total_min <- if (nrow(optimo) > 0 && !anyNA(optimo$precio)) sum(optimo$subtotal) else NA_real_
  mejor <- if (nrow(completos)) completos[1, ] else NULL
  list(detalle = detalle, por_comercio = por_comercio, optimo = optimo, resumen = list(
    total_minimo = total_min,
    sin_precio = optimo$producto[is.na(optimo$precio)],
    mejor_comercio = if (is.null(mejor)) NA_character_ else paste(completos$comercio[completos$total == mejor$total], collapse = " / "),
    total_mejor_comercio = if (is.null(mejor)) NA_real_ else mejor$total,
    ahorro = if (is.null(mejor) || is.na(total_min)) NA_real_ else mejor$total - total_min,
    ahorro_pct = if (is.null(mejor) || is.na(total_min)) NA_real_ else 100 * (mejor$total - total_min) / mejor$total))
}

# ---------------------------------------------------------------------------
# Calidad de datos
# ---------------------------------------------------------------------------
listar_correcciones <- function(con) {
  .q(con, paste(
    "SELECT c.fecha, c.regla, c.tabla, c.registro_id, a.comercio_id AS comercio, a.nombre_original AS anuncio, c.campo,",
    "c.valor_anterior, c.valor_nuevo, c.motivo FROM correcciones c",
    "LEFT JOIN anuncios a ON c.tabla = 'anuncios' AND a.anuncio_id = CAST(c.registro_id AS INTEGER)",
    "WHERE c.activa = 1 ORDER BY c.correccion_id"))
}
listar_rechazadas <- function(con) {
  .q(con, paste("SELECT ejecucion_id, comercio_id AS comercio, sku_comercio, nombre_original, precio, motivo, fecha_registro",
                "FROM observaciones_rechazadas ORDER BY rechazo_id DESC"))
}
# Número de anuncios en cada estado de disponibilidad (disponible, agotado, no observado) por ejecución.
resumen_disponibilidad <- function(con, ejecucion) {
  .q(con, paste("SELECT c.nombre AS comercio, d.estado, COUNT(*) AS anuncios FROM v_disponibilidad d",
                "JOIN comercios c ON c.comercio_id = d.comercio_id WHERE d.ejecucion_id = ?",
                "GROUP BY c.nombre, d.estado ORDER BY c.nombre, d.estado"), ejecucion)
}
