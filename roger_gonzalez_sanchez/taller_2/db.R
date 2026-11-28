# db.R
# Capa de acceso a datos de la app. Todo el SQL de la interfaz está aquí
# (y en sql/esquema_taller2.sql). La interfaz solo llama estas funciones.
#
# Trabaja sobre la base del Taller 1: tablas comercios, ejecuciones,
# productos_comunes y observaciones, con sus mismos nombres de columna.
#


library(DBI)
library(RSQLite)

RUTA_BD <- "comparador_precios.sqlite"
ZONA_HORARIA <- "America/Bogota"

# Mismo formato de fecha que el Taller 1: 2026-11-11T10:32:05-05:00
ahora <- function() paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S", tz = ZONA_HORARIA), "-05:00")

# ---------- Conexión ----------

abrir_conexion <- function(ruta = RUTA_BD) {
  con <- dbConnect(SQLite(), ruta)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  # si la actualización está escribiendo en otro proceso, espera en vez de fallar
  dbExecute(con, "PRAGMA busy_timeout = 10000")
  con
}

cerrar_conexion <- function(con) {
  if (dbIsValid(con)) dbDisconnect(con)
  invisible(TRUE)
}

# Agrega lo del Taller 2 sin borrar nada: columnas nuevas, tablas, índices y vistas.
db_inicializar <- function(con, archivo = "sql/esquema_taller2.sql") {
  faltan <- setdiff(c("comercios", "ejecuciones", "productos_comunes", "observaciones"),
                    dbListTables(con))
  if (length(faltan) > 0) {
    stop("La base no tiene las tablas del Taller 1 (", paste(faltan, collapse = ", "),
         "). Ejecute crear_esquema() de R/06_base_datos.R.")
  }
  if (!"descartada" %in% dbListFields(con, "observaciones")) {
    dbExecute(con, "ALTER TABLE observaciones ADD COLUMN descartada INTEGER NOT NULL DEFAULT 0
                    CHECK (descartada IN (0, 1))")
  }
  contadores <- c("n_validas", "n_rechazadas", "n_insertadas", "n_nuevos", "n_cambios",
                  "n_no_observados")
  for (col in setdiff(contadores, dbListFields(con, "ejecuciones"))) {
    dbExecute(con, paste("ALTER TABLE ejecuciones ADD COLUMN", col, "INTEGER"))
  }

  texto <- paste(readLines(archivo, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  texto <- gsub("--[^\n]*", "", texto)
  sentencias <- trimws(strsplit(texto, ";", fixed = TRUE)[[1]])
  for (s in sentencias[nzchar(sentencias)]) dbExecute(con, s)
  invisible(TRUE)
}


consultar <- function(con, sql, params = list()) {
  if (length(params) == 0) return(dbGetQuery(con, sql))
  dbGetQuery(con, sql, params = unname(params))
}

marcadores <- function(n) paste(rep("?", n), collapse = ", ")

# Para LIKE: que % y _ escritos por el usuario se busquen como texto normal
escapar_like <- function(x) gsub("([\\\\%_])", "\\\\\\1", x)

# Convierte los filtros de la interfaz en un WHERE con marcadores.
# f puede traer: comercios, subcategorias, marcas, precio_min, precio_max,
# id_ejecucion, fecha_desde, fecha_hasta, solo_promocion, solo_comparables, texto
armar_filtros <- function(f) {
  cond <- character(0)
  params <- list()

  agregar <- function(sql, valores = NULL) {
    cond <<- c(cond, sql)
    params <<- c(params, as.list(valores))
  }

  if (length(f$comercios) > 0)
    agregar(paste0("comercio IN (", marcadores(length(f$comercios)), ")"), f$comercios)
  if (length(f$subcategorias) > 0)
    agregar(paste0("subcategoria_estandar IN (", marcadores(length(f$subcategorias)), ")"), f$subcategorias)
  if (length(f$marcas) > 0)
    agregar(paste0("marca_estandarizada IN (", marcadores(length(f$marcas)), ")"), f$marcas)
  if (!is.null(f$precio_min)) agregar("precio_cop >= ?", f$precio_min)
  if (!is.null(f$precio_max)) agregar("precio_cop <= ?", f$precio_max)
  if (!is.null(f$id_ejecucion)) agregar("id_ejecucion = ?", f$id_ejecucion)
  if (!is.null(f$fecha_desde)) agregar("fecha_hora_consulta >= ?", format(as.Date(f$fecha_desde)))
  if (!is.null(f$fecha_hasta)) agregar("fecha_hora_consulta < ?", format(as.Date(f$fecha_hasta) + 1))
  if (isTRUE(f$solo_promocion)) agregar("es_promocion = 1")
  if (isTRUE(f$solo_comparables)) agregar("comparable = 1")
  if (!is.null(f$texto) && nzchar(f$texto)) {
    patron <- paste0("%", escapar_like(f$texto), "%")
    agregar(paste("(producto_nombre_original LIKE ? ESCAPE '\\'",
                  "OR presentacion_original LIKE ? ESCAPE '\\'",
                  "OR descripcion_original LIKE ? ESCAPE '\\')"), c(patron, patron, patron))
  }

  where <- if (length(cond) > 0) paste("WHERE", paste(cond, collapse = " AND ")) else ""
  list(where = where, params = params)
}

filtro_comercios <- function(comercios, columna = "comercio") {
  if (length(comercios) == 0) return(list(sql = "", params = list()))
  list(sql = paste0(" AND ", columna, " IN (", marcadores(length(comercios)), ")"),
       params = as.list(comercios))
}

# ---------- Opciones para los filtros ----------

# Cambia cada vez que entra o se corrige algo; la app la usa como llave de caché.
db_firma <- function(con) {
  r <- dbGetQuery(con, "
    SELECT (SELECT COUNT(*) FROM observaciones) AS n_obs,
           (SELECT COUNT(*) FROM ejecuciones) AS n_ejec,
           (SELECT COALESCE(MAX(fecha_inicio), '') FROM ejecuciones) AS ult_ejec,
           (SELECT COUNT(*) FROM correcciones) AS n_corr")
  paste(unlist(r), collapse = "|")
}

db_comercios <- function(con) {
  dbGetQuery(con, "SELECT DISTINCT comercio FROM observaciones ORDER BY comercio")$comercio
}

db_subcategorias <- function(con) {
  dbGetQuery(con, "SELECT DISTINCT subcategoria_estandar AS s FROM observaciones
                   WHERE subcategoria_estandar IS NOT NULL ORDER BY s")$s
}

db_marcas <- function(con) {
  dbGetQuery(con, "SELECT DISTINCT marca_estandarizada AS m FROM observaciones
                   WHERE marca_estandarizada IS NOT NULL ORDER BY m")$m
}

db_rango_precios <- function(con) {
  dbGetQuery(con, "SELECT MIN(precio_cop) AS minimo, MAX(precio_cop) AS maximo FROM v_observaciones")
}

# substr y no date(): date() pasaría la hora -05:00 a UTC y cambiaría el día
db_rango_fechas <- function(con) {
  dbGetQuery(con, "SELECT MIN(substr(fecha_hora_consulta, 1, 10)) AS desde,
                          MAX(substr(fecha_hora_consulta, 1, 10)) AS hasta
                   FROM v_observaciones")
}

db_lista_comparables <- function(con) {
  dbGetQuery(con, "SELECT id_producto_comun AS id_comparable, descripcion AS nombre
                   FROM productos_comunes ORDER BY descripcion")
}

# Ejecuciones con datos (para los selectores), de la más reciente a la más antigua
db_ejecuciones_con_datos <- function(con) {
  dbGetQuery(con, "SELECT * FROM v_ejecuciones WHERE n_observaciones > 0
                   ORDER BY fecha_inicio DESC")
}

db_historial_ejecuciones <- function(con) {
  dbGetQuery(con, "SELECT * FROM v_ejecuciones ORDER BY fecha_inicio DESC")
}

db_ultima_ejecucion <- function(con) {
  dbGetQuery(con, "SELECT * FROM v_ejecuciones ORDER BY fecha_inicio DESC LIMIT 1")
}

db_ultima_ejecucion_con_datos <- function(con) {
  dbGetQuery(con, "SELECT * FROM v_ejecuciones WHERE n_observaciones > 0
                   ORDER BY fecha_inicio DESC LIMIT 1")
}

# Última ejecución con datos dentro de un rango de fechas
db_ejecucion_en_rango <- function(con, desde, hasta) {
  r <- consultar(con, "
    SELECT id_ejecucion FROM v_ejecuciones
    WHERE n_observaciones > 0 AND fecha_inicio >= ? AND fecha_inicio < ?
    ORDER BY fecha_inicio DESC LIMIT 1",
    list(format(as.Date(desde)), format(as.Date(hasta) + 1)))
  if (nrow(r) == 0) NA_character_ else r$id_ejecucion
}

db_detalle_ejecuciones <- function(con) {
  dbGetQuery(con, "SELECT * FROM ejecuciones ORDER BY fecha_inicio DESC, comercio")
}

db_rechazos <- function(con, limite = 500) {
  consultar(con, "SELECT id_ejecucion, comercio, sku_comercio, producto_nombre_original,
                         precio_cop, fecha_hora_consulta, motivo
                  FROM observaciones_rechazadas ORDER BY id_rechazo DESC LIMIT ?",
            list(limite))
}

db_correcciones <- function(con) {
  dbGetQuery(con, "SELECT * FROM correcciones ORDER BY id_correccion DESC")
}

# ---------- Productos e indicadores (usan los filtros) ----------
# Los alias (AS precio, AS nombre...) son solo para la interfaz.

db_productos <- function(con, f, limite = 20000) {
  w <- armar_filtros(f)
  sql <- paste(
    "SELECT comercio, producto_nombre_original AS nombre, marca_estandarizada AS marca,",
    "subcategoria_estandar AS subcategoria, contenido_num, unidad_medida,",
    "precio_cop AS precio, precio_regular_cop, precio_unitario, es_promocion,",
    "estado_disponibilidad, fecha_hora_consulta, url_producto, id_producto_comun,",
    "id_ejecucion, sku_comercio, archivo_raw",
    "FROM v_observaciones", w$where,
    "ORDER BY comercio, producto_nombre_original LIMIT ?")
  consultar(con, sql, c(w$params, limite))
}

db_indicadores <- function(con, f) {
  w <- armar_filtros(f)
  sql <- paste(
    "SELECT COUNT(DISTINCT comercio || '|' || sku_comercio) AS productos,",
    "COUNT(*) AS observaciones,",
    "100.0 * AVG(es_promocion) AS pct_promocion",
    "FROM v_observaciones", w$where)
  consultar(con, sql, w$params)
}

db_por_comercio <- function(con, f) {
  w <- armar_filtros(f)
  sql <- paste(
    "SELECT comercio, COUNT(DISTINCT sku_comercio) AS productos, COUNT(*) AS observaciones,",
    "MIN(precio_cop) AS precio_min, MAX(precio_cop) AS precio_max",
    "FROM v_observaciones", w$where,
    "GROUP BY comercio ORDER BY comercio")
  consultar(con, sql, w$params)
}

# SQLite no tiene MEDIAN: se ordena y se toma el valor (o los dos) del centro
db_mediana <- function(con, f) {
  w <- armar_filtros(f)
  sql <- paste(
    "WITH r AS (SELECT precio_cop, ROW_NUMBER() OVER (ORDER BY precio_cop) AS i,",
    "COUNT(*) OVER () AS n FROM v_observaciones", w$where, ")",
    "SELECT AVG(precio_cop) AS mediana FROM r WHERE i IN ((n + 1) / 2, (n + 2) / 2)")
  consultar(con, sql, w$params)$mediana
}

db_mediana_subcategoria <- function(con, f) {
  w <- armar_filtros(f)
  sql <- paste(
    "WITH r AS (SELECT subcategoria_estandar AS subcategoria, precio_cop,",
    "ROW_NUMBER() OVER (PARTITION BY subcategoria_estandar ORDER BY precio_cop) AS i,",
    "COUNT(*) OVER (PARTITION BY subcategoria_estandar) AS n",
    "FROM v_observaciones", w$where, ")",
    "SELECT COALESCE(subcategoria, 'Sin subcategoría') AS subcategoria,",
    "AVG(precio_cop) AS mediana, MAX(n) AS observaciones",
    "FROM r WHERE i IN ((n + 1) / 2, (n + 2) / 2)",
    "GROUP BY subcategoria ORDER BY mediana DESC")
  consultar(con, sql, w$params)
}

db_disponibilidad <- function(con, id_ejecucion, comercios = NULL) {
  fc <- filtro_comercios(comercios)
  sql <- paste0("SELECT estado, COUNT(*) AS n FROM v_disponibilidad
                 WHERE id_ejecucion = ?", fc$sql, " GROUP BY estado")
  consultar(con, sql, c(list(id_ejecucion), fc$params))
}

# Mayor diferencia de precio de un mismo comparable entre comercios
db_ahorro_maximo <- function(con, id_ejecucion, comercios = NULL) {
  fc <- filtro_comercios(comercios)
  sql <- paste0("
    SELECT comparable, MIN(precio_cop) AS precio_min, MAX(precio_cop) AS precio_max,
           MAX(precio_cop) - MIN(precio_cop) AS ahorro, COUNT(*) AS n_comercios
    FROM v_comparables
    WHERE id_ejecucion = ? AND precio_cop IS NOT NULL AND estado <> 'agotado'", fc$sql, "
    GROUP BY id_producto_comun HAVING COUNT(*) >= 2
    ORDER BY ahorro DESC LIMIT 1")
  consultar(con, sql, c(list(id_ejecucion), fc$params))
}

db_cambios_en_ejecucion <- function(con, id_ejecucion, comercios = NULL) {
  fc <- filtro_comercios(comercios)
  sql <- paste0("
    SELECT COUNT(*) AS cambios,
           COALESCE(SUM(diferencia > 0), 0) AS subidas,
           COALESCE(SUM(diferencia < 0), 0) AS bajadas
    FROM v_cambios_precio WHERE id_ejecucion = ?", fc$sql)
  consultar(con, sql, c(list(id_ejecucion), fc$params))
}

#Gráficos

db_evolucion_comparable <- function(con, id_comparable, comercios = NULL) {
  fc <- filtro_comercios(comercios)
  sql <- paste0("
    SELECT comercio, fecha_hora_consulta, precio_cop AS precio, estado
    FROM v_comparables
    WHERE id_producto_comun = ? AND precio_cop IS NOT NULL", fc$sql, "
    ORDER BY fecha_hora_consulta")
  consultar(con, sql, c(list(id_comparable), fc$params))
}

db_unidades_comparables <- function(con, id_ejecucion) {
  consultar(con, "SELECT DISTINCT unidad_medida FROM v_comparables
                  WHERE id_ejecucion = ? AND unidad_medida IS NOT NULL ORDER BY unidad_medida",
            list(id_ejecucion))$unidad_medida
}

# Se filtra por la unidad del Taller 1 (mL, unidad, sobres, dosis) para no
# comparar, por ejemplo, el precio de un sobre con el de una tableta.
db_precio_unitario <- function(con, id_ejecucion, unidad, comercios = NULL) {
  fc <- filtro_comercios(comercios)
  sql <- paste0("
    SELECT comparable, comercio, precio_cop AS precio, contenido_num, unidad_medida,
           precio_unitario
    FROM v_comparables
    WHERE id_ejecucion = ? AND unidad_medida = ? AND precio_unitario IS NOT NULL", fc$sql, "
    ORDER BY comparable, comercio")
  consultar(con, sql, c(list(id_ejecucion, unidad), fc$params))
}

db_precios_para_distribucion <- function(con, f) {
  w <- armar_filtros(f)
  consultar(con, paste("SELECT comercio, precio_cop AS precio FROM v_observaciones", w$where),
            w$params)
}

# Cuántos comparables tiene más baratos cada comercio (los empates cuentan para todos)
db_veces_mas_barato <- function(con, id_ejecucion, comercios = NULL) {
  fc <- filtro_comercios(comercios)
  sql <- paste0("
    WITH d AS (
      SELECT id_producto_comun, comercio, precio_cop FROM v_comparables
      WHERE id_ejecucion = ? AND precio_cop IS NOT NULL AND estado <> 'agotado'", fc$sql, "
    ),
    m AS (
      SELECT id_producto_comun, MIN(precio_cop) AS minimo FROM d
      GROUP BY id_producto_comun HAVING COUNT(*) >= 2
    )
    SELECT d.comercio, COUNT(*) AS veces
    FROM d JOIN m ON m.id_producto_comun = d.id_producto_comun AND d.precio_cop = m.minimo
    GROUP BY d.comercio ORDER BY veces DESC")
  consultar(con, sql, c(list(id_ejecucion), fc$params))
}

#Cambios de precio entre dos ejecuciones

# Compara el mismo producto (sku) en el mismo comercio. Solo cuenta los
# comercios con datos en las dos ejecuciones, para no confundir una falla del
# scraper con productos nuevos o retirados.
db_comparar_ejecuciones <- function(con, id_anterior, id_reciente) {
  sql <- "
    WITH a AS (SELECT comercio, sku_comercio, producto_nombre_original AS nombre,
                      precio_cop, url_producto
               FROM v_observaciones WHERE id_ejecucion = ?),
         b AS (SELECT comercio, sku_comercio, producto_nombre_original AS nombre,
                      precio_cop, url_producto
               FROM v_observaciones WHERE id_ejecucion = ?),
         comunes AS (SELECT comercio FROM a INTERSECT SELECT comercio FROM b)
    SELECT b.comercio, b.sku_comercio, b.nombre,
           a.precio_cop AS precio_anterior, b.precio_cop AS precio_reciente,
           b.precio_cop - a.precio_cop AS diferencia,
           ROUND(100.0 * (b.precio_cop - a.precio_cop) / a.precio_cop, 2) AS variacion_pct,
           CASE WHEN a.sku_comercio IS NULL THEN 'nuevo'
                WHEN b.precio_cop > a.precio_cop THEN 'sube'
                WHEN b.precio_cop < a.precio_cop THEN 'baja'
                ELSE 'sin_cambio' END AS tipo,
           b.url_producto AS url
    FROM b LEFT JOIN a ON a.comercio = b.comercio AND a.sku_comercio = b.sku_comercio
    WHERE b.comercio IN (SELECT comercio FROM comunes)
    UNION ALL
    SELECT a.comercio, a.sku_comercio, a.nombre, a.precio_cop, NULL, NULL, NULL,
           'no_observado', a.url_producto
    FROM a LEFT JOIN b ON b.comercio = a.comercio AND b.sku_comercio = a.sku_comercio
    WHERE b.sku_comercio IS NULL AND a.comercio IN (SELECT comercio FROM comunes)
    ORDER BY 1, 3"
  consultar(con, sql, list(id_anterior, id_reciente))
}

#Canasta

db_precios_canasta <- function(con, id_ejecucion, ids_comparables) {
  if (length(ids_comparables) == 0) return(data.frame())
  sql <- paste0("
    SELECT id_producto_comun AS id_comparable, comparable, comercio,
           precio_cop AS precio, estado, url_producto
    FROM v_comparables
    WHERE id_ejecucion = ? AND id_producto_comun IN (", marcadores(length(ids_comparables)), ")
    ORDER BY comparable, comercio")
  consultar(con, sql, c(list(id_ejecucion), as.list(ids_comparables)))
}

#Escritura (la usa actualizacion.R)

# Mismas columnas que inserta el Taller 1 (COLUMNAS_ESTANDAR + COLUMNAS_EXTRA)
COLUMNAS_OBSERVACION <- c(
  "comercio", "sku_comercio", "producto_nombre_original", "marca_estandarizada",
  "subcategoria_estandar", "contenido_num", "unidad_medida", "precio_cop",
  "precio_regular_cop", "es_promocion", "url_producto", "fecha_hora_consulta",
  "id_ejecucion", "presentacion_original", "descripcion_original",
  "ficha_tecnica_original", "categoria_origen", "url_consulta", "archivo_raw", "disponible"
)

# Inserta solo lo que no existe (UNIQUE del Taller 1). Devuelve cuántas entraron.
db_insertar_observaciones <- function(con, d) {
  if (nrow(d) == 0) return(0L)
  sql <- paste0("INSERT INTO observaciones (", paste(COLUMNAS_OBSERVACION, collapse = ", "),
                ") VALUES (", marcadores(length(COLUMNAS_OBSERVACION)), ")",
                " ON CONFLICT (comercio, sku_comercio, fecha_hora_consulta) DO NOTHING")
  dbExecute(con, sql, params = unname(as.list(as.data.frame(d)[, COLUMNAS_OBSERVACION])))
}

db_insertar_rechazos <- function(con, d, id_ejecucion) {
  if (nrow(d) == 0) return(0L)
  dbExecute(con, "
    INSERT INTO observaciones_rechazadas
      (id_ejecucion, comercio, sku_comercio, producto_nombre_original, precio_cop,
       url_producto, fecha_hora_consulta, archivo_raw, motivo, fecha_registro)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(rep(id_ejecucion, nrow(d)), d$comercio, d$sku_comercio,
                  d$producto_nombre_original, suppressWarnings(as.numeric(d$precio_cop)),
                  d$url_producto, d$fecha_hora_consulta, d$archivo_raw, d$motivo,
                  rep(ahora(), nrow(d))))
}

# Guarda en la fila de ejecuciones los conteos del resumen del Taller 2
db_guardar_conteos <- function(con, id_ejecucion, comercio, r) {
  dbExecute(con, "
    UPDATE ejecuciones SET n_validas = ?, n_rechazadas = ?, n_insertadas = ?,
           n_nuevos = ?, n_cambios = ?, n_no_observados = ?
    WHERE id_ejecucion = ? AND comercio = ?",
    params = list(r$validas, r$rechazadas, r$insertadas, r$nuevos, r$cambios_precio,
                  r$no_observados, id_ejecucion, comercio))
}

# Último precio conocido de cada producto de un comercio (antes de insertar)
db_ultimos_precios_comercio <- function(con, comercio) {
  consultar(con, "SELECT sku_comercio, precio_cop, fecha_hora_consulta FROM v_ultimo_precio
                  WHERE comercio = ?", list(comercio))
}

# Productos vistos en la ejecución anterior de ese comercio (la más reciente
# con datos que empezó antes de fecha_ref, sin contar las de `excluir`)
db_skus_ejecucion_previa <- function(con, comercio, fecha_ref, excluir) {
  excluir <- unique(excluir)
  consultar(con, paste0("
    SELECT o.sku_comercio FROM observaciones o
    WHERE o.comercio = ? AND o.descartada = 0 AND o.id_ejecucion = (
      SELECT e.id_ejecucion FROM ejecuciones e
      WHERE e.comercio = ? AND e.fecha_inicio <= ?
        AND e.id_ejecucion NOT IN (", marcadores(length(excluir)), ")
        AND EXISTS (SELECT 1 FROM observaciones x
                    WHERE x.id_ejecucion = e.id_ejecucion AND x.comercio = e.comercio)
      ORDER BY e.fecha_inicio DESC LIMIT 1)"),
    c(list(comercio, comercio, fecha_ref), as.list(excluir)))$sku_comercio
}

db_comparables_marcados <- function(con, id_ejecucion) {
  consultar(con, "SELECT comercio, COUNT(DISTINCT id_producto_comun) AS n
                  FROM observaciones WHERE id_ejecucion = ? AND comparable = 1
                  GROUP BY comercio", list(id_ejecucion))
}

db_ultima_en_linea <- function(con) {
  dbGetQuery(con, "SELECT MAX(fecha_inicio) AS fecha FROM ejecuciones WHERE modo = 'online'")$fecha
}

#Correcciones (Módulo 1, sección 3.2)

# Campos que se pueden corregir. El nombre de la columna no puede ir como
# parámetro "?", por eso solo se aceptan los de esta lista. Los textos
# originales (nombre, descripción, ficha) no se corrigen: son lo que dijo el sitio.
CAMPOS_CORREGIBLES <- c("marca_estandarizada", "subcategoria_estandar", "contenido_num",
                        "unidad_medida", "precio_cop", "precio_regular_cop", "es_promocion",
                        "disponible", "comparable", "id_producto_comun", "familia_producto",
                        "descartada")

db_corregir_observacion <- function(con, id_observacion, campo, valor_nuevo, motivo) {
  campo <- match.arg(campo, CAMPOS_CORREGIBLES)
  if (!nzchar(trimws(motivo))) stop("Toda corrección necesita un motivo.")
  dbWithTransaction(con, {
    anterior <- consultar(con, paste0("SELECT ", campo, " AS v FROM observaciones
                                       WHERE id_observacion = ?"), list(id_observacion))
    if (nrow(anterior) == 0) stop("No existe la observación ", id_observacion)
    dbExecute(con, paste0("UPDATE observaciones SET ", campo, " = ? WHERE id_observacion = ?"),
              params = list(valor_nuevo, id_observacion))
    dbExecute(con, "INSERT INTO correcciones (fecha, tabla, id_registro, campo,
                      valor_anterior, valor_nuevo, motivo)
                    VALUES (?, 'observaciones', ?, ?, ?, ?, ?)",
              params = list(ahora(), as.character(id_observacion), campo,
                            as.character(anterior$v), as.character(valor_nuevo), motivo))
  })
  invisible(TRUE)
}

db_descartar_observacion <- function(con, id_observacion, motivo) {
  db_corregir_observacion(con, id_observacion, "descartada", 1L, motivo)
}
