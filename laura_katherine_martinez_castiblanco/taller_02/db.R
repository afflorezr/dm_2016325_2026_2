# =============================================================================
# db.R · Capa de acceso a datos (SQLite). La interfaz NO contiene SQL.
# - Toda consulta recibe filtros como argumentos y devuelve data.frames.
# - Valores del usuario SIEMPRE como parámetros (?); en el texto solo se insertan marcadores.
# - Conexión: se abre y se cierra dentro de cada función (on.exit), nunca queda abierta.
# =============================================================================
suppressPackageStartupMessages({ library(DBI); library(RSQLite) })

DB_PATH <- if (exists("CFG") && !is.null(CFG$db_path)) CFG$db_path else "comparador_precios.sqlite"
DIR_SQL <- "sql"

# ------------------------------------------------------------------------------
# 1. CONEXIÓN
# ------------------------------------------------------------------------------
db_abrir <- function(path = DB_PATH) {
  con <- dbConnect(SQLite(), path)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  dbExecute(con, "PRAGMA busy_timeout = 5000")
  con
}
# Ejecuta f(con) y cierra la conexión pase lo que pase
db_con <- function(f, path = DB_PATH) { con <- db_abrir(path); on.exit(dbDisconnect(con), add = TRUE); f(con) }
db_q <- function(sql, params = NULL, path = DB_PATH) {
  db_con(function(con) if (length(params) == 0) dbGetQuery(con, sql) else dbGetQuery(con, sql, params = unname(as.list(params))), path)
}
marcadores <- function(x) paste(rep("?", length(x)), collapse = ",")

# ------------------------------------------------------------------------------
# 2. MIGRACIÓN (idempotente): crea tablas/vistas/índices del Taller 2
# ------------------------------------------------------------------------------
ejecutar_script_sql <- function(con, archivo) {
  lin <- readLines(archivo, warn = FALSE, encoding = "UTF-8")
  lin <- lin[!grepl("^\\s*--", lin)]
  sentencias <- trimws(strsplit(paste(lin, collapse = "\n"), ";", fixed = TRUE)[[1]])
  for (s in sentencias[nzchar(sentencias)]) dbExecute(con, s)
  invisible(length(sentencias))
}
db_migrar <- function(path = DB_PATH, dir_sql = DIR_SQL) {
  db_con(function(con) {
    # tablas base del Taller 1 si faltan (las crea el scraper); en la entrega ya existen
    if (!"observaciones" %in% dbListTables(con) && exists("db_crear_esquema")) db_crear_esquema(con)
    if (!"productos_comunes" %in% dbListTables(con))
      dbExecute(con, "CREATE TABLE productos_comunes(id_corrida TEXT NOT NULL, id_producto_comun TEXT NOT NULL,
        clave_producto TEXT NOT NULL, marca TEXT, subcategoria TEXT, variante TEXT, contenido_total_ml REAL,
        unidades INTEGER, n_comercios INTEGER, lista_comercios TEXT, PRIMARY KEY(id_corrida, id_producto_comun))")
    dbBegin(con)
    tryCatch({
      for (f in sort(list.files(dir_sql, pattern = "^0[123]_.*\\.sql$", full.names = TRUE))) ejecutar_script_sql(con, f)
      dbCommit(con)
    }, error = function(e) { try(dbRollback(con), silent = TRUE); stop("Migración fallida: ", conditionMessage(e)) })
    invisible(TRUE)
  }, path)
}

# ------------------------------------------------------------------------------
# 3. CORRECCIONES AUDITADAS (nunca se borran observaciones)
# ------------------------------------------------------------------------------
CAMPOS_CORREGIBLES <- c("marca_estandarizada", "subcategoria", "precio_cop", "precio_lista_cop", "es_promocion",
                        "contenido_total_ml", "unidades", "unidad_medida", "disponibilidad", "precio_por_litro",
                        "id_producto_comun", "comparable")
ahora_bogota <- function() sub("(\\d{2})(\\d{2})$", "\\1:\\2", format(as.POSIXct(Sys.time(), tz = "America/Bogota"), "%Y-%m-%dT%H:%M:%S%z"))

# Corrige UN campo de UNA observación y deja la huella en `correcciones`, en una sola transacción.
db_corregir_campo <- function(con, id_obs, campo, valor_nuevo, motivo) {
  stopifnot(campo %in% CAMPOS_CORREGIBLES, is.character(motivo), nzchar(motivo))
  ant <- dbGetQuery(con, sprintf("SELECT %s AS v FROM observaciones WHERE id_obs = ?", dbQuoteIdentifier(con, campo)),
                    params = list(id_obs))
  if (!nrow(ant)) stop("No existe id_obs = ", id_obs)
  if (identical(as.character(ant$v), as.character(valor_nuevo))) return(invisible(FALSE))
  dbBegin(con)
  tryCatch({
    dbExecute(con, sprintf("UPDATE observaciones SET %s = ? WHERE id_obs = ?", dbQuoteIdentifier(con, campo)),
              params = list(valor_nuevo, id_obs))
    dbExecute(con, "INSERT INTO correcciones(fecha, tabla, id_registro, campo, valor_anterior, valor_nuevo, motivo)
                    VALUES(?,?,?,?,?,?,?)",
              params = list(ahora_bogota(), "observaciones", as.character(id_obs), campo,
                            as.character(ant$v), as.character(valor_nuevo), motivo))
    dbCommit(con)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop(e) })
  invisible(TRUE)
}
# Marca una observación como descartada (queda en la base, deja de usarse en vistas)
db_descartar_obs <- function(con, id_obs, motivo) {
  dbBegin(con)
  tryCatch({
    n <- dbExecute(con, "INSERT OR IGNORE INTO obs_descartadas(id_obs, fecha, motivo) VALUES(?,?,?)",
                   params = list(id_obs, ahora_bogota(), motivo))
    if (n > 0) dbExecute(con, "INSERT INTO correcciones(fecha, tabla, id_registro, campo, valor_anterior, valor_nuevo, motivo)
                               VALUES(?,?,?,?,?,?,?)",
                         params = list(ahora_bogota(), "observaciones", as.character(id_obs), "descartada", "0", "1", motivo))
    dbCommit(con)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop(e) })
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# 4. INSERCIÓN ATÓMICA SIN DUPLICADOS (usada por pruebas y por reprocesos)
#    La unicidad la garantiza UNIQUE(comercio, sku_comercio, fecha_hora_consulta).
# ------------------------------------------------------------------------------
db_registrar_ejecucion <- function(con, id_ejecucion, id_corrida, comercio, modo = "online", estado = "en_curso") {
  dbExecute(con, "INSERT OR IGNORE INTO ejecuciones(id_ejecucion, id_corrida, comercio, fecha_inicio, modo, estado)
                  VALUES(?,?,?,?,?,?)", params = list(id_ejecucion, id_corrida, comercio, ahora_bogota(), modo, estado))
}
db_insertar_obs <- function(con, obs) {
  if (!nrow(obs)) return(0L)
  cols <- setdiff(intersect(names(obs), dbListFields(con, "observaciones")), "id_obs")
  dbBegin(con)
  tryCatch({
    dbWriteTable(con, "temp_obs", as.data.frame(obs[, cols, drop = FALSE]), temporary = TRUE, overwrite = TRUE)
    n <- dbExecute(con, sprintf("INSERT OR IGNORE INTO observaciones(%s) SELECT %s FROM temp_obs",
                                paste(cols, collapse = ","), paste(cols, collapse = ",")))
    dbExecute(con, "DROP TABLE IF EXISTS temp_obs")
    dbCommit(con); as.integer(n)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop(e) })
}

# ------------------------------------------------------------------------------
# 5. FILTROS COMBINABLES -> WHERE parametrizado
#    f: list(comercios, subcategorias, marcas, precio = c(min,max), corridas, solo_promo,
#            solo_comparables, texto, disponibilidad)
# ------------------------------------------------------------------------------
filtros_where <- function(f, alias = "v") {
  w <- character(); p <- list(); a <- function(x) paste0(alias, ".", x)
  en <- function(col, vals) if (length(vals)) { w <<- c(w, sprintf("%s IN (%s)", a(col), marcadores(vals))); p <<- c(p, as.list(vals)) }
  en("comercio", f$comercios); en("subcategoria", f$subcategorias)
  en("marca_estandarizada", f$marcas); en("id_corrida", f$corridas); en("disponibilidad", f$disponibilidad)
  if (length(f$precio) == 2) { w <- c(w, sprintf("%s BETWEEN ? AND ?", a("precio_cop"))); p <- c(p, as.list(f$precio)) }
  if (isTRUE(f$solo_promo)) w <- c(w, sprintf("%s = 1", a("es_promocion")))
  if (isTRUE(f$solo_comparables)) w <- c(w, sprintf("%s = 1", a("comparable")))
  if (!is.null(f$texto) && nzchar(f$texto)) {
    pat <- paste0("%", escapar_like(f$texto), "%")
    w <- c(w, sprintf("(%s LIKE ? ESCAPE '\\' OR %s LIKE ? ESCAPE '\\')", a("producto_raw"), a("texto_original_anuncio")))
    p <- c(p, list(pat, pat))
  }
  list(sql = if (length(w)) paste("WHERE", paste(w, collapse = " AND ")) else "", params = p)
}
db_filtrado <- function(f, columnas = "v.*", extra_sql = "", params_extra = list(), path = DB_PATH) {
  fw <- filtros_where(f)
  db_q(sprintf("SELECT %s FROM v_obs_validas v %s %s", columnas, fw$sql, extra_sql), c(fw$params, params_extra), path)
}

# ------------------------------------------------------------------------------
# 6. CATÁLOGOS (alimentan los controles de la interfaz)
# ------------------------------------------------------------------------------
db_catalogos <- function(path = DB_PATH) {
  list(
    comercios = db_q("SELECT DISTINCT comercio FROM v_obs_validas ORDER BY comercio", path = path)$comercio,
    subcategorias = db_q("SELECT DISTINCT subcategoria FROM v_obs_validas WHERE subcategoria IS NOT NULL ORDER BY 1", path = path)$subcategoria,
    marcas = db_q("SELECT DISTINCT marca_estandarizada AS m FROM v_obs_validas WHERE marca_estandarizada IS NOT NULL ORDER BY 1", path = path)$m,
    rango_precio = unlist(db_q("SELECT MIN(precio_cop) AS lo, MAX(precio_cop) AS hi FROM v_obs_validas", path = path)),
    corridas = db_q("SELECT id_corrida, fecha_hora, fecha, estado, n_obs FROM v_corridas ORDER BY id_corrida DESC", path = path),
    corridas_comp = db_corridas_comparables(path)
  )
}
db_corridas <- function(path = DB_PATH) db_q("SELECT * FROM v_corridas ORDER BY id_corrida DESC", path = path)
db_productos_comparables <- function(path = DB_PATH) {
  db_q("SELECT clave_producto, MAX(etiqueta) AS etiqueta, MAX(id_corrida) AS ultima_corrida
        FROM v_productos_comparables GROUP BY clave_producto ORDER BY etiqueta", path = path)
}

# Corridas que SÍ tienen productos comparables (las únicas útiles para Comparador y Canasta)
db_corridas_comparables <- function(path = DB_PATH) {
  db_q("SELECT c.id_corrida, c.fecha_hora, c.estado, COUNT(DISTINCT p.id_producto_comun) AS n_comparables
        FROM v_corridas c JOIN productos_comunes p ON p.id_corrida = c.id_corrida
        GROUP BY c.id_corrida, c.fecha_hora, c.estado ORDER BY c.id_corrida DESC", path = path)
}

# ------------------------------------------------------------------------------
# 7. INDICADORES (todo en SQL)
# ------------------------------------------------------------------------------
db_kpi_general <- function(f, path = DB_PATH) {
  fw <- filtros_where(f)
  db_q(sprintf("SELECT COUNT(DISTINCT v.comercio || '|' || v.sku_comercio) AS n_productos, COUNT(*) AS n_obs,
                       ROUND(AVG(v.precio_cop), 0) AS precio_prom,
                       ROUND(100.0 * SUM(v.es_promocion = 1) / NULLIF(COUNT(*), 0), 1) AS pct_promo,
                       MAX(v.fecha_hora_consulta) AS ultima_consulta
                FROM v_obs_validas v %s", fw$sql), fw$params, path)
}
db_obs_por_comercio <- function(f, path = DB_PATH) {
  fw <- filtros_where(f)
  db_q(sprintf("SELECT v.comercio, COUNT(DISTINCT v.sku_comercio) AS productos, COUNT(*) AS observaciones,
                       ROUND(100.0 * SUM(v.es_promocion = 1) / COUNT(*), 1) AS pct_promo,
                       ROUND(AVG(v.precio_cop), 0) AS precio_prom
                FROM v_obs_validas v %s GROUP BY v.comercio ORDER BY v.comercio", fw$sql), fw$params, path)
}
# Mediana de COP/L por subcategoría (y comercio): SQL con ROW_NUMBER; sin mezclar unidades (unidad_base)
db_mediana_unitario <- function(f, por_comercio = TRUE, path = DB_PATH) {
  fw <- filtros_where(f)
  part <- if (por_comercio) "v.comercio, v.subcategoria, v.unidad_base" else "v.subcategoria, v.unidad_base"
  sel  <- if (por_comercio) "comercio, subcategoria, unidad_base" else "subcategoria, unidad_base"
  extra <- if (nzchar(fw$sql)) "AND v.precio_por_l IS NOT NULL" else "WHERE v.precio_por_l IS NOT NULL"
  db_q(sprintf("WITH r AS (SELECT %s, v.precio_por_l AS x,
                  ROW_NUMBER() OVER (PARTITION BY %s ORDER BY v.precio_por_l) AS rn,
                  COUNT(*) OVER (PARTITION BY %s) AS n
                FROM v_obs_validas v %s %s)
                SELECT %s, MAX(n) AS n, ROUND(AVG(x), 0) AS mediana_cop_l
                FROM r WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY %s ORDER BY %s",
               gsub("v\\.", "v.", paste0(if (por_comercio) "v.comercio," else "", " v.subcategoria, v.unidad_base")),
               part, part, fw$sql, extra, sel, sel, sel), fw$params, path)
}
# Atípicos: precio por litro > 3 veces la mediana de su subcategoría (en la selección)
db_atipicos <- function(f, path = DB_PATH) {
  fw <- filtros_where(f)
  extra <- if (nzchar(fw$sql)) "AND v.precio_por_l IS NOT NULL" else "WHERE v.precio_por_l IS NOT NULL"
  db_q(sprintf("WITH base AS (SELECT v.comercio, v.sku_comercio, v.producto_raw, v.subcategoria, v.precio_cop, v.precio_por_l,
                  ROW_NUMBER() OVER (PARTITION BY v.subcategoria ORDER BY v.precio_por_l) AS rn,
                  COUNT(*) OVER (PARTITION BY v.subcategoria) AS n
                FROM v_obs_validas v %s %s),
                med AS (SELECT subcategoria, AVG(precio_por_l) AS mediana FROM base
                        WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY subcategoria)
                SELECT b.comercio, b.producto_raw, b.subcategoria, b.precio_cop, ROUND(b.precio_por_l, 0) AS precio_por_l,
                       ROUND(m.mediana, 0) AS mediana_subcategoria
                FROM base b JOIN med m ON m.subcategoria = b.subcategoria
                WHERE b.precio_por_l > 3 * m.mediana ORDER BY b.precio_por_l DESC", fw$sql, extra), fw$params, path)
}
# Distribución (cuartiles) del precio o del precio por litro por comercio, calculada en SQL
db_distribucion <- function(f, medida = c("precio_cop", "precio_por_l"), path = DB_PATH) {
  medida <- match.arg(medida); fw <- filtros_where(f)
  extra <- if (nzchar(fw$sql)) sprintf("AND v.%s IS NOT NULL", medida) else sprintf("WHERE v.%s IS NOT NULL", medida)
  db_q(sprintf("WITH r AS (SELECT v.comercio, v.%s AS x,
                  ROW_NUMBER() OVER (PARTITION BY v.comercio ORDER BY v.%s) AS rn,
                  COUNT(*) OVER (PARTITION BY v.comercio) AS n
                FROM v_obs_validas v %s %s)
                SELECT comercio, MAX(n) AS n, MIN(x) AS minimo,
                  MAX(CASE WHEN rn = (n + 3) / 4 THEN x END) AS q1,
                  MAX(CASE WHEN rn = (n + 1) / 2 THEN x END) AS mediana,
                  MAX(CASE WHEN rn = (3 * n + 3) / 4 THEN x END) AS q3,
                  MAX(x) AS maximo
                FROM r GROUP BY comercio ORDER BY comercio", medida, medida, fw$sql, extra), fw$params, path)
}
# Mayor ahorro entre comercios para un mismo producto comparable (una corrida)
db_ahorro_max <- function(id_corrida, path = DB_PATH) {
  db_q("SELECT etiqueta, MIN(precio_cop) AS minimo, MAX(precio_cop) AS maximo,
               MAX(precio_cop) - MIN(precio_cop) AS ahorro_cop,
               ROUND(100.0 * (MAX(precio_cop) - MIN(precio_cop)) / MAX(precio_cop), 1) AS ahorro_pct
        FROM v_comparables WHERE id_corrida = ? GROUP BY clave_producto, etiqueta
        ORDER BY ahorro_cop DESC LIMIT 1", list(id_corrida), path)
}
# Ahorro por producto comparable (para el gráfico de libre elección)
db_ahorro_por_producto <- function(id_corrida, comercios = NULL, path = DB_PATH) {
  sql <- "SELECT clave_producto, etiqueta, COUNT(*) AS n_comercios, MIN(precio_cop) AS minimo, MAX(precio_cop) AS maximo,
                 MAX(precio_cop) - MIN(precio_cop) AS ahorro_cop,
                 ROUND(100.0 * (MAX(precio_cop) - MIN(precio_cop)) / MAX(precio_cop), 1) AS ahorro_pct
          FROM v_comparables WHERE id_corrida = ?"
  p <- list(id_corrida)
  if (length(comercios)) { sql <- paste0(sql, " AND comercio IN (", marcadores(comercios), ")"); p <- c(p, as.list(comercios)) }
  db_q(paste(sql, "GROUP BY clave_producto, etiqueta ORDER BY ahorro_pct DESC"), p, path)
}
db_ultima_corrida <- function(path = DB_PATH) db_q("SELECT * FROM v_corridas ORDER BY id_corrida DESC LIMIT 1", path = path)
db_cambios_ultima <- function(path = DB_PATH) {
  db_q("SELECT sentido, COUNT(*) AS n FROM v_cambios_precio
        WHERE id_corrida = (SELECT MAX(id_corrida) FROM v_corridas) AND sentido IN ('sube','baja') GROUP BY sentido", path = path)
}

# ------------------------------------------------------------------------------
# 8. COMPARABLES, HISTORIAL, CAMBIOS Y CANASTA
# ------------------------------------------------------------------------------
db_comparables_corrida <- function(id_corrida, comercios = NULL, path = DB_PATH) {
  sql <- "SELECT clave_producto, etiqueta, comercio, precio_cop, precio_por_l, es_promocion, disponibilidad,
                 url_producto, fecha_hora_consulta, id_corrida
          FROM v_comparables WHERE id_corrida = ?"
  p <- list(id_corrida)
  if (length(comercios)) { sql <- paste0(sql, " AND comercio IN (", marcadores(comercios), ")"); p <- c(p, as.list(comercios)) }
  db_q(paste(sql, "ORDER BY etiqueta, precio_cop"), p, path)
}
db_serie_producto <- function(clave, comercios = NULL, path = DB_PATH) {
  sql <- "SELECT comercio, fecha_hora_consulta, fecha, id_corrida, precio_cop, es_promocion
          FROM v_historial_precios WHERE clave_producto = ?"
  p <- list(clave)
  if (length(comercios)) { sql <- paste0(sql, " AND comercio IN (", marcadores(comercios), ")"); p <- c(p, as.list(comercios)) }
  db_q(paste(sql, "ORDER BY fecha_hora_consulta"), p, path)
}
db_obs_corrida <- function(id_corrida, path = DB_PATH) {
  db_q("SELECT comercio, sku_comercio, producto_raw, precio_cop, url_producto FROM v_obs_validas WHERE id_corrida = ?",
       list(id_corrida), path)
}
# Comparación de dos corridas: mismo anuncio, mismo comercio (la lógica es la función pura detectar_cambios)
db_cambios_entre <- function(corrida_ant, corrida_nue, umbral_pct = 10, path = DB_PATH) {
  detectar_cambios(db_obs_corrida(corrida_ant, path), db_obs_corrida(corrida_nue, path), umbral_pct)
}
# Resumen por comercio tras una actualización: recolectados, nuevos, cambios, no observados
db_resumen_actualizacion <- function(id_corrida, path = DB_PATH) {
  db_q("SELECT e.comercio, e.estado, e.n_registros AS recolectados, e.n_descartados AS descartados,
          COALESCE((SELECT COUNT(*) FROM v_cambios_precio c WHERE c.id_corrida = e.id_corrida AND c.comercio = e.comercio
                    AND c.sentido = 'nuevo'), 0) AS nuevos,
          COALESCE((SELECT COUNT(*) FROM v_cambios_precio c WHERE c.id_corrida = e.id_corrida AND c.comercio = e.comercio
                    AND c.sentido IN ('sube','baja')), 0) AS cambios_precio,
          COALESCE((SELECT COUNT(DISTINCT p.sku_comercio) FROM v_obs_validas p
                    WHERE p.comercio = e.comercio AND p.id_corrida < e.id_corrida AND NOT EXISTS
                      (SELECT 1 FROM v_obs_validas q WHERE q.id_corrida = e.id_corrida AND q.comercio = p.comercio
                       AND q.sku_comercio = p.sku_comercio)), 0) AS no_observados,
          e.detalle
        FROM ejecuciones e WHERE e.id_corrida = ? AND e.modo = 'online' ORDER BY e.comercio", list(id_corrida), path)
}

# ------------------------------------------------------------------------------
# 9. TABLA, AUDITORÍA Y DICCIONARIO
# ------------------------------------------------------------------------------
db_tabla <- function(f, limite = 5000L, path = DB_PATH) {
  fw <- filtros_where(f)
  db_q(sprintf("SELECT v.comercio AS Comercio, v.producto_raw AS Producto, v.marca_estandarizada AS Marca,
                       v.subcategoria AS Subcategoria, v.presentacion_raw AS Presentacion,
                       v.precio_cop AS Precio_COP, ROUND(v.precio_por_l, 0) AS Precio_por_litro_COP,
                       CASE WHEN v.es_promocion = 1 THEN 'Sí' ELSE 'No' END AS Promocion,
                       v.disponibilidad AS Disponibilidad, v.fecha_hora_consulta AS Fecha_consulta,
                       v.url_producto AS Enlace, v.id_corrida AS Corrida
                FROM v_obs_validas v %s ORDER BY v.comercio, v.producto_raw LIMIT ?", fw$sql),
       c(fw$params, list(as.integer(limite))), path)
}
db_auditoria <- function(path = DB_PATH) db_q("SELECT * FROM v_ejecuciones_resumen ORDER BY id_ejecucion", path = path)
db_correcciones_lista <- function(path = DB_PATH) db_q("SELECT * FROM correcciones ORDER BY id_correccion DESC", path = path)
db_descartes_resumen <- function(id_corrida = NULL, path = DB_PATH) {
  if (is.null(id_corrida))
    db_q("SELECT comercio, motivo, COUNT(*) AS n FROM descartes GROUP BY comercio, motivo ORDER BY n DESC", path = path)
  else db_q("SELECT d.comercio, d.motivo, COUNT(*) AS n FROM descartes d JOIN ejecuciones e ON e.id_ejecucion = d.id_ejecucion
             WHERE e.id_corrida = ? GROUP BY d.comercio, d.motivo ORDER BY n DESC", list(id_corrida), path)
}
db_disponibilidad_resumen <- function(f, path = DB_PATH) {
  fw <- filtros_where(f)
  db_q(sprintf("SELECT v.comercio, v.disponibilidad, COUNT(*) AS n FROM v_obs_validas v %s
                GROUP BY v.comercio, v.disponibilidad", fw$sql), fw$params, path)
}
db_validaciones <- function(path = DB_PATH) db_q("SELECT * FROM validaciones ORDER BY id_validacion DESC LIMIT 300", path = path)
