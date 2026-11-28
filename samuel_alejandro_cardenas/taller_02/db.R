RUTA_BD <- 'comparador_precios_taller2.sqlite'

conectar_consulta <- function(sql, params = list(), db = RUTA_BD) {
  if (!file.exists(db)) stop('No encuentro la base del Taller 2: ', db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (length(params)) DBI::dbGetQuery(con, sql, params = params)
  else DBI::dbGetQuery(con, sql)
}

condiciones_sql <- function(f) {
  wh <- character()
  ps <- list()
  agregar <- function(termino, valores) {
    wh <<- c(wh, termino)
    ps <<- c(ps, as.list(valores))
  }
  if (length(f$comercios)) {
    n <- length(f$comercios)
    agregar(paste0('comercio IN (', paste(rep('?', n), collapse = ','), ')'), f$comercios)
  }
  if (!is.null(f$subcategoria) && nzchar(f$subcategoria)) agregar('subcategoria = ?', f$subcategoria)
  if (!is.null(f$marca) && nzchar(f$marca)) agregar('marca = ?', f$marca)
  if (!is.null(f$minimo) && is.finite(f$minimo)) agregar('precio >= ?', as.numeric(f$minimo))
  if (!is.null(f$maximo) && is.finite(f$maximo)) agregar('precio <= ?', as.numeric(f$maximo))
  if (!is.null(f$desde) && nzchar(f$desde)) agregar('substr(fecha_consulta,1,10) >= ?', f$desde)
  if (!is.null(f$hasta) && nzchar(f$hasta)) agregar('substr(fecha_consulta,1,10) <= ?', f$hasta)
  if (isTRUE(f$promocion)) wh <- c(wh, 'promocion = 1')
  if (isTRUE(f$comparables)) wh <- c(wh, 'comparable = 1')
  if (!is.null(f$texto) && nzchar(f$texto)) {
    q <- substr(f$texto, 1L, 80L)
    q <- gsub('!', '!!', q, fixed = TRUE)
    q <- gsub('%', '!%', q, fixed = TRUE)
    q <- gsub('_', '!_', q, fixed = TRUE)
    agregar("(LOWER(producto_original) LIKE ? ESCAPE '!' OR LOWER(COALESCE(descripcion_original,'')) LIKE ? ESCAPE '!')",
            rep(paste0('%', tolower(q), '%'), 2L))
  }
  list(where = if (length(wh)) paste0(' WHERE ',paste(wh,collapse=' AND ')) else '',
       params = ps)
}

opciones_filtros <- function() {
  list(
    comercios = conectar_consulta('SELECT DISTINCT comercio AS valor FROM v_ultimo_precio ORDER BY comercio')$valor,
    subcategorias = conectar_consulta("SELECT DISTINCT subcategoria AS valor FROM v_ultimo_precio WHERE subcategoria IS NOT NULL AND subcategoria<>'' ORDER BY subcategoria")$valor,
    marcas = conectar_consulta("SELECT DISTINCT marca AS valor FROM v_ultimo_precio WHERE marca IS NOT NULL AND marca<>'' ORDER BY marca")$valor,
    productos = conectar_consulta('SELECT DISTINCT id_comun AS valor FROM v_comparables WHERE id_comun IS NOT NULL ORDER BY id_comun')$valor
  )
}

ejecuciones_disponibles <- function() {
  conectar_consulta("SELECT id_ejecucion, COUNT(DISTINCT comercio) AS comercios,
                            MIN(substr(inicio,1,10)) AS fecha,
                            GROUP_CONCAT(comercio || ': ' || estado, '; ') AS estados
                     FROM ejecuciones GROUP BY id_ejecucion ORDER BY id_ejecucion DESC")
}

datos_filtrados_sql <- function(f, limite = 10000L) {
  cond <- condiciones_sql(f)
  conectar_consulta(paste0(
    "SELECT comercio,sku,producto_original,marca,subcategoria,precio,
            CASE WHEN contenido_total > 0 THEN ROUND(precio/contenido_total,2)
                 WHEN cantidad > 0 THEN ROUND(precio/cantidad,2) END AS precio_unitario,
            COALESCE(unidad_normalizada,unidad) AS unidad,
            promocion,COALESCE(disponibilidad,'no informado') AS disponibilidad,
            fecha_consulta,id_ejecucion,url,comparable,id_comun
      FROM v_ultimo_precio", cond$where,
    ' ORDER BY comercio, producto_original LIMIT ?'), base::c(cond$params,list(as.integer(limite))))
}

kpis_sql <- function(f) {
  cond <- condiciones_sql(f)
  conectar_consulta(paste0(
    "SELECT COUNT(*) AS ofertas,
            COUNT(DISTINCT marca) AS marcas,
            COUNT(DISTINCT comercio) AS comercios,
            SUM(CASE WHEN promocion=1 THEN 1 ELSE 0 END) AS promociones,
            ROUND(AVG(precio),0) AS precio_promedio,
            COUNT(DISTINCT CASE WHEN comparable=1 THEN id_comun END) AS productos_comparables,
            MAX(fecha_consulta) AS fecha_mas_reciente
      FROM v_ultimo_precio", cond$where), cond$params)
}

serie_producto_sql <- function(id, comercios = character()) {
  sql <- "SELECT id_ejecucion,substr(fecha_consulta,1,10) AS fecha,
                 comercio,precio FROM v_comparables WHERE id_comun=?"
  params <- list(id)
  if (length(comercios)) {
    sql <- paste0(sql,' AND comercio IN (',paste(rep('?',length(comercios)),collapse=','),')')
    params <- c(params,as.list(comercios))
  }
  conectar_consulta(paste0(sql,' ORDER BY fecha_consulta,comercio'),params)
}

precio_unitario_sql <- function(id, ejecucion) {
  conectar_consulta(
    "SELECT comercio,precio_unitario,unidad_calculable,contenido_calculable,
            precio,COALESCE(disponibilidad,'no informado') AS disponibilidad
     FROM v_comparables
     WHERE id_comun=? AND id_ejecucion=? AND precio_unitario IS NOT NULL
     ORDER BY comercio",list(id,ejecucion))
}

distribucion_sql <- function(f, ancho = 10000) {
  cond <- condiciones_sql(f)
  conectar_consulta(paste0(
    "SELECT comercio, CAST(precio / ? AS INTEGER) AS tramo,
            COUNT(*) AS frecuencia FROM v_ultimo_precio", cond$where,
    ' GROUP BY comercio,tramo ORDER BY tramo,comercio'),
    base::c(list(ancho),cond$params))
}

cambios_por_comercio_sql <- function(ejecucion) {
  conectar_consulta("SELECT comercio,
    SUM(CASE WHEN cambio_cop > 0 THEN 1 ELSE 0 END) AS subieron,
    SUM(CASE WHEN cambio_cop < 0 THEN 1 ELSE 0 END) AS bajaron,
    SUM(CASE WHEN cambio_cop = 0 THEN 1 ELSE 0 END) AS iguales
    FROM v_cambios_precio WHERE id_ejecucion=? GROUP BY comercio ORDER BY comercio",
    list(ejecucion))
}

comparar_ejecuciones_sql <- function(anterior, nueva) {
  conectar_consulta("WITH base AS (
      SELECT comercio,sku,producto_original,precio FROM observaciones WHERE id_ejecucion=?
    ), actual AS (
      SELECT comercio,sku,producto_original,precio FROM observaciones WHERE id_ejecucion=?
    ), todos AS (
      SELECT a.comercio,a.sku,a.producto_original,a.precio AS actual,b.precio AS anterior
      FROM actual a LEFT JOIN base b ON a.comercio=b.comercio AND a.sku=b.sku
      UNION ALL
      SELECT b.comercio,b.sku,b.producto_original,NULL AS actual,b.precio AS anterior
      FROM base b LEFT JOIN actual a ON a.comercio=b.comercio AND a.sku=b.sku
      WHERE a.sku IS NULL
    )
    SELECT comercio,sku,producto_original,anterior,actual,
      CASE WHEN anterior IS NULL THEN 'nuevo'
           WHEN actual IS NULL THEN 'sin registro nuevo'
           WHEN actual>anterior THEN 'subio'
           WHEN actual<anterior THEN 'bajo'
           ELSE 'igual' END AS situacion,
      CASE WHEN actual IS NOT NULL AND anterior IS NOT NULL
           THEN ROUND(actual-anterior,0) END AS variacion_cop,
      CASE WHEN actual IS NOT NULL AND anterior>0
           THEN ROUND(100.0*(actual-anterior)/anterior,2) END AS variacion_pct
    FROM todos ORDER BY comercio,situacion,producto_original",
    list(anterior,nueva))
}

canasta_sql <- function(ids,cantidades,ejecucion) {
  if (!length(ids) || length(ids)!=length(cantidades)) return(data.frame())
  if (any(!is.finite(cantidades)) || any(cantidades<1) || any(cantidades!=floor(cantidades)))
    stop('Cantidades invalidas')
  marcadores <- paste(rep('(?,?)',length(ids)),collapse=',')
  parametros <- c(as.list(as.vector(rbind(ids,as.integer(cantidades)))),list(ejecucion))
  conectar_consulta(paste0(
    'WITH solicitud(id_comun,cantidad) AS (VALUES ',marcadores,'), ',
    'precios AS (SELECT comercio,id_comun,precio,disponibilidad ',
    'FROM v_comparables WHERE id_ejecucion=?) ',
    'SELECT p.comercio,COUNT(DISTINCT p.id_comun) AS presentes, ',
    'SUM(CASE WHEN p.disponibilidad="agotado" THEN 1 ELSE 0 END) AS agotados, ',
    'SUM(CASE WHEN p.disponibilidad IS NULL THEN 1 ELSE 0 END) AS sin_confirmar, ',
    'SUM(s.cantidad*p.precio) AS total_estimado ',
    'FROM solicitud s INNER JOIN precios p ON p.id_comun=s.id_comun ',
    'GROUP BY p.comercio ORDER BY p.comercio'), parametros)
}

minimo_canasta_sql <- function(ids,cantidades,ejecucion) {
  if (!length(ids) || length(ids)!=length(cantidades)) return(data.frame())
  marcadores <- paste(rep('(?,?)',length(ids)),collapse=',')
  parametros <- c(as.list(as.vector(rbind(ids,as.integer(cantidades)))),list(ejecucion))
  conectar_consulta(paste0(
    'WITH solicitud(id_comun,cantidad) AS (VALUES ',marcadores,'), ',
    'precios AS (SELECT id_comun,MIN(precio) AS precio_minimo FROM v_comparables ',
    "WHERE id_ejecucion=? AND disponibilidad = 'disponible' GROUP BY id_comun) ",
    'SELECT s.id_comun,s.cantidad,p.precio_minimo, ',
    's.cantidad*p.precio_minimo AS subtotal FROM solicitud s ',
    'LEFT JOIN precios p ON p.id_comun=s.id_comun ORDER BY s.id_comun'), parametros)
}

cobertura_sql <- function(ejecucion) {
  conectar_consulta('SELECT comercio,seccion,esperados,capturados,paginas,estado FROM cobertura WHERE id_ejecucion=? ORDER BY comercio,seccion',list(ejecucion))
}
