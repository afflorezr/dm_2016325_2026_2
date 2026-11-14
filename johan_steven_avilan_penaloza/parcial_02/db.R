# db.R — Taller 2
# Capa de acceso a datos: la interfaz no contiene SQL. Cada función recibe la
# conexión y los filtros como argumentos y devuelve tablas.
# Seguridad: todo valor que viene del usuario se pasa como parámetro (?).
# En el texto del SQL solo se insertan marcadores "?" y nombres fijos de
# columnas o vistas escritos en este archivo.

library(DBI)
library(RSQLite)

RUTA_DB_DEFECTO  <- "comparador_precios.sqlite"
COLORES_COMERCIO <- c("Farmatodo" = "#1b9e77", "La Rebaja" = "#d95f02", "Locatel" = "#7570b3")

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- Conexión ----------------------------------------------------------

abrir_db <- function(ruta = RUTA_DB_DEFECTO) {
  if (!file.exists(ruta) || file.size(ruta) == 0) {
    stop("No se encontró la base de datos '", ruta, "'.")
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta)
  DBI::dbExecute(con, "PRAGMA busy_timeout = 10000")
  con
}

cerrar_db <- function(con) {
  if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con)
  invisible(TRUE)
}

# ---- Utilidades de entrada ----------------------------------------------

marcadores <- function(n) paste(rep("?", n), collapse = ", ")
params_o_null <- function(p) if (length(p) > 0) unname(p) else NULL

# Valida el texto de búsqueda: longitud máxima y caracteres permitidos
# (letras, números, espacio y . , / + -). Se eliminan comillas, punto y coma,
# %, _ y cualquier otro carácter.
limpiar_busqueda <- function(x, max_car = 60L) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) return("")
  x <- substr(as.character(x[1]), 1L, max_car)
  x <- gsub("[^[:alnum:] .,/+-]", "", x)
  trimws(gsub(" +", " ", x))
}

normalizar_busqueda <- function(x) {
  tolower(stringi::stri_trans_general(x, "Latin-ASCII"))
}

# ---- Filtros -------------------------------------------------------------
# f: list(comercios, subcategorias, marcas, precio_min, precio_max,
#         solo_promo, solo_comparables, busqueda, fecha)
# fecha NULL o "ultima": última ejecución de cada comercio (v_ultimo_precio);
# otra fecha AAAA-MM-DD: esa captura (v_precios).
construir_filtros <- function(f = list()) {
  cond <- character(); par <- list()

  en_lista <- function(col, vals) {
    vals <- vals[!is.na(vals) & nzchar(vals)]
    if (length(vals) > 0) {
      cond <<- c(cond, sprintf("%s IN (%s)", col, marcadores(length(vals))))
      par  <<- c(par, as.list(vals))
    }
  }
  en_lista("comercio",     f$comercios)
  en_lista("subcategoria", f$subcategorias)
  en_lista("marca",        f$marcas)

  if (!is.null(f$precio_min) && !is.null(f$precio_max)) {
    cond <- c(cond, "precio BETWEEN ? AND ?")
    par  <- c(par, list(as.numeric(f$precio_min), as.numeric(f$precio_max)))
  }
  if (isTRUE(f$solo_promo))       cond <- c(cond, "es_promocion = 1")
  if (isTRUE(f$solo_comparables)) cond <- c(cond, "id_comparable IS NOT NULL")

  palabras <- strsplit(limpiar_busqueda(f$busqueda), " ", fixed = TRUE)[[1]]
  palabras <- head(palabras[nzchar(palabras)], 5L)
  for (p in palabras) {
    cond <- c(cond, paste0("(nombre LIKE ? OR id_anuncio IN ",
                           "(SELECT id_anuncio FROM anuncios WHERE nombre_estandar LIKE ?))"))
    par  <- c(par, list(paste0("%", p, "%"), paste0("%", normalizar_busqueda(p), "%")))
  }

  fuente <- "v_ultimo_precio"
  if (!is.null(f$fecha) && nzchar(f$fecha) && f$fecha != "ultima") {
    fuente <- "v_precios"
    cond <- c(cond, "fecha = ?")
    par  <- c(par, list(as.character(f$fecha)))
  }
  list(fuente = fuente,
       where  = if (length(cond) > 0) paste("WHERE", paste(cond, collapse = " AND ")) else "",
       params = par)
}

con_condicion <- function(where, extra) {
  if (nzchar(where)) paste(where, "AND", extra) else paste("WHERE", extra)
}

# ---- Opciones de los filtros ---------------------------------------------

fechas_captura <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT DISTINCT SUBSTR(fecha_hora_inicio, 1, 10) AS fecha
    FROM ejecuciones WHERE estado = 'completa'
    ORDER BY 1 DESC")$fecha
}

fechas_comparables <- function(con) {
  DBI::dbGetQuery(con, "SELECT DISTINCT fecha FROM v_comparables ORDER BY 1 DESC")$fecha
}

fecha_referencia <- function(con) {
  DBI::dbGetQuery(con, "SELECT fecha FROM v_referencia")$fecha
}

lista_comparables <- function(con) {
  DBI::dbGetQuery(con, "SELECT id_comparable, nombre_comun AS producto
                        FROM productos_comparables ORDER BY id_comparable")
}

unidades_comparables <- function(con) {
  DBI::dbGetQuery(con, "SELECT DISTINCT unidad_normalizada AS u FROM anuncios
                        WHERE unidad_normalizada IS NOT NULL ORDER BY 1")$u
}

opciones_filtros <- function(con) {
  rango <- DBI::dbGetQuery(con, "SELECT MAX(precio) AS pmax FROM observaciones")
  list(
    comercios     = DBI::dbGetQuery(con, "SELECT nombre FROM comercios ORDER BY 1")$nombre,
    subcategorias = DBI::dbGetQuery(con, "SELECT DISTINCT subcategoria FROM anuncios
                      WHERE incluido = 1 AND subcategoria IS NOT NULL ORDER BY 1")$subcategoria,
    marcas        = DBI::dbGetQuery(con, "SELECT DISTINCT marca FROM anuncios
                      WHERE incluido = 1 AND marca IS NOT NULL ORDER BY 1")$marca,
    precio_max    = ceiling((rango$pmax %||% 1000) / 1000) * 1000,
    fechas        = fechas_captura(con)
  )
}

# ---- Tabla e indicadores -------------------------------------------------

precios_filtrados <- function(con, f = list()) {
  fl <- construir_filtros(f)
  sql <- paste0("
    SELECT comercio, nombre, marca, subcategoria,
           CASE WHEN contenido_total IS NOT NULL
                THEN printf('%g %s', contenido_total, unidad_normalizada) END AS presentacion,
           precio, precio_unitario, unidad_normalizada AS unidad_unitaria,
           precio_antes, es_promocion, disponibilidad,
           fecha_hora_consulta, url
    FROM ", fl$fuente, " ", fl$where, "
    ORDER BY comercio, nombre")
  DBI::dbGetQuery(con, sql, params = params_o_null(fl$params))
}

# Seis indicadores calculados con SQL. Los tres primeros respetan los filtros;
# los otros tres son globales (última ejecución / fecha de referencia).
indicadores <- function(con, f = list()) {
  fl <- construir_filtros(f)
  p  <- params_o_null(fl$params)

  base <- paste0("SELECT precio, es_promocion, disponibilidad, fecha FROM ",
                 fl$fuente, " ", fl$where)
  r <- DBI::dbGetQuery(con, paste0("
    WITH b AS (", base, ")
    SELECT COUNT(*) AS productos,
           SUM(CASE WHEN precio IS NOT NULL THEN 1 ELSE 0 END)           AS con_precio,
           SUM(CASE WHEN es_promocion = 1 THEN 1 ELSE 0 END)              AS promos,
           SUM(CASE WHEN disponibilidad = 'agotado' THEN 1 ELSE 0 END)    AS agotados,
           MIN(fecha) AS fecha_min, MAX(fecha) AS fecha_max
    FROM b"), params = p)

  # Mediana en SQL (SQLite no tiene función de mediana)
  base_p <- paste0("SELECT precio FROM ", fl$fuente, " ",
                   con_condicion(fl$where, "precio IS NOT NULL"))
  med <- DBI::dbGetQuery(con, paste0("
    WITH b AS (", base_p, ")
    SELECT AVG(precio) AS mediana FROM (
      SELECT precio FROM b ORDER BY precio
      LIMIT 2 - (SELECT COUNT(*) FROM b) % 2
      OFFSET (SELECT (COUNT(*) - 1) / 2 FROM b))"), params = p)

  ult <- DBI::dbGetQuery(con, "
    SELECT MAX(SUBSTR(fecha_hora_inicio, 1, 10)) AS fecha,
           MIN(estado = 'completa')              AS completas
    FROM (SELECT estado, fecha_hora_inicio,
                 ROW_NUMBER() OVER (PARTITION BY id_comercio
                                    ORDER BY fecha_hora_inicio DESC) AS r
          FROM ejecuciones WHERE estado <> 'fallida')
    WHERE r = 1")
  cam <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) AS n FROM v_cambios_precio WHERE tipo IN ('subió', 'bajó')")
  aho <- DBI::dbGetQuery(con, "
    SELECT producto, MAX(precio) - MIN(precio) AS ahorro, fecha
    FROM v_comparables WHERE fecha = (SELECT fecha FROM v_referencia)
      AND disponible = 1
    GROUP BY id_comparable, producto, fecha
    ORDER BY ahorro DESC LIMIT 1")

  list(
    productos = r$productos, con_precio = r$con_precio, promos = r$promos,
    agotados = r$agotados, fecha_min = r$fecha_min, fecha_max = r$fecha_max,
    mediana = med$mediana,
    ultima_fecha = ult$fecha, ultima_completa = isTRUE(ult$completas == 1),
    cambios = cam$n,
    ahorro_max = if (nrow(aho) > 0) aho$ahorro else NA_real_,
    ahorro_producto = if (nrow(aho) > 0) aho$producto else NA_character_,
    ahorro_fecha = if (nrow(aho) > 0) aho$fecha else NA_character_
  )
}

# ---- Datos de los gráficos -----------------------------------------------

serie_precio <- function(con, id_comparable) {
  DBI::dbGetQuery(con, "
    SELECT fecha, comercio, precio FROM v_comparables
    WHERE id_comparable = ? ORDER BY fecha",
    params = list(as.integer(id_comparable)))
}

precio_unitario_comparables <- function(con, unidad, fecha = NULL) {
  DBI::dbGetQuery(con, "
    SELECT id_comparable, producto, comercio, precio, precio_unitario, unidad_normalizada
    FROM v_comparables
    WHERE fecha = COALESCE(?, (SELECT fecha FROM v_referencia))
      AND unidad_normalizada = ?
      AND disponible = 1
    ORDER BY id_comparable, comercio",
    params = list(fecha %||% NA_character_, as.character(unidad)))
}

distribucion_precios <- function(con, f = list()) {
  fl <- construir_filtros(f)
  DBI::dbGetQuery(con, paste0("SELECT comercio, precio FROM ", fl$fuente, " ",
                              con_condicion(fl$where, "precio IS NOT NULL")),
                  params = params_o_null(fl$params))
}

disponibilidad_por_comercio <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT comercio, disponibilidad, COUNT(*) AS n
    FROM v_disponibilidad GROUP BY comercio, disponibilidad")
}

# ---- Cambios de precio entre dos capturas ---------------------------------

# Clasifica cada fila (función pura, probada con testthat).
clasificar_cambios <- function(df) {
  df$cambio_cop <- df$precio_actual - df$precio_anterior
  df$cambio_pct <- round(100 * df$cambio_cop / df$precio_anterior, 1)
  ant <- as.logical(df$en_anterior)
  act <- as.logical(df$en_actual)
  df$tipo <- ifelse(!ant, "nuevo",
             ifelse(!act, "no observado",
             ifelse(is.na(df$precio_anterior) | is.na(df$precio_actual), "sin comparación",
             ifelse(df$precio_actual > df$precio_anterior, "subió",
             ifelse(df$precio_actual < df$precio_anterior, "bajó", "igual")))))
  df
}

# Compara el MISMO anuncio en el MISMO comercio entre dos fechas de captura.
cambios_entre <- function(con, fecha_ant, fecha_act, comercios = NULL) {
  comercios <- comercios[!is.na(comercios) & nzchar(comercios)]
  filtro_c  <- if (length(comercios) > 0)
    paste0(" AND c.nombre IN (", marcadores(length(comercios)), ")") else ""
  sql <- paste0("
    WITH ult AS (
      SELECT MAX(id_observacion) AS id_obs FROM observaciones
      WHERE id_ejecucion IN (SELECT id_ejecucion FROM ejecuciones WHERE estado = 'completa')
      GROUP BY id_anuncio, SUBSTR(fecha_hora_consulta, 1, 10)),
    act AS (
      SELECT o.id_anuncio, o.precio FROM observaciones o
      JOIN ult ON ult.id_obs = o.id_observacion
      WHERE SUBSTR(o.fecha_hora_consulta, 1, 10) = ?),
    ant AS (
      SELECT o.id_anuncio, o.precio FROM observaciones o
      JOIN ult ON ult.id_obs = o.id_observacion
      WHERE SUBSTR(o.fecha_hora_consulta, 1, 10) = ?),
    ids AS (SELECT id_anuncio FROM act UNION SELECT id_anuncio FROM ant)
    SELECT c.nombre AS comercio, a.nombre_original AS nombre, a.marca, a.url,
           ant.precio AS precio_anterior, act.precio AS precio_actual,
           ant.id_anuncio IS NOT NULL AS en_anterior,
           act.id_anuncio IS NOT NULL AS en_actual
    FROM ids
    JOIN anuncios  a ON a.id_anuncio  = ids.id_anuncio
    JOIN comercios c ON c.id_comercio = a.id_comercio
    LEFT JOIN act ON act.id_anuncio = ids.id_anuncio
    LEFT JOIN ant ON ant.id_anuncio = ids.id_anuncio
    WHERE a.incluido = 1
      AND a.id_comercio IN (SELECT id_comercio FROM ejecuciones
                            WHERE estado = 'completa' AND SUBSTR(fecha_hora_inicio, 1, 10) = ?)
      AND a.id_comercio IN (SELECT id_comercio FROM ejecuciones
                            WHERE estado = 'completa' AND SUBSTR(fecha_hora_inicio, 1, 10) = ?)", filtro_c, "
    ORDER BY c.nombre, a.nombre_original")
  d <- DBI::dbGetQuery(con, sql,
                       params = c(list(as.character(fecha_act), as.character(fecha_ant),
                                       as.character(fecha_act), as.character(fecha_ant)),
                                  as.list(comercios)))
  clasificar_cambios(d)
}

# ---- Canasta ----------------------------------------------------------------

# Precios de los comparables elegidos, de una misma captura. Por defecto solo
# cuentan los productos que el sitio marca como disponibles.
precios_canasta <- function(con, ids, fecha = NULL, solo_disponibles = TRUE) {
  ids <- as.integer(ids)
  if (length(ids) == 0) return(data.frame())
  sql <- paste0("
    SELECT id_comparable, producto, comercio, precio
    FROM v_comparables
    WHERE fecha = COALESCE(?, (SELECT fecha FROM v_referencia))
      AND id_comparable IN (", marcadores(length(ids)), ")",
    if (isTRUE(solo_disponibles)) " AND disponible = 1" else "")
  DBI::dbGetQuery(con, sql, params = c(list(fecha %||% NA_character_), as.list(ids)))
}

# Mínimo, máximo y ahorro por producto; con empates en el mínimo se listan
# todos los comercios empatados.
ahorro_por_producto <- function(precios) {
  vacio <- data.frame(id_comparable = character(), producto = character(),
                      minimo = numeric(), maximo = numeric(), ahorro = numeric(),
                      ahorro_pct = numeric(), mas_baratos = character(),
                      stringsAsFactors = FALSE)
  p <- precios[!is.na(precios$precio), ]
  if (nrow(p) == 0) return(vacio)
  out <- lapply(split(p, p$id_comparable), function(d) {
    m <- min(d$precio); M <- max(d$precio)
    data.frame(id_comparable = as.character(d$id_comparable[1]),
               producto = d$producto[1], minimo = m, maximo = M,
               ahorro = M - m, ahorro_pct = round(100 * (M - m) / M, 1),
               mas_baratos = paste(sort(unique(d$comercio[d$precio == m])), collapse = " / "),
               stringsAsFactors = FALSE)
  })
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}

# cantidades: vector numérico con nombres = id_comparable.
# Solo se calcula el costo en un comercio si tiene TODOS los productos; si falta
# alguno se indica en lugar de mostrar un total incompleto.
calcular_canasta <- function(precios, cantidades, nombres = NULL,
                             comercios = names(COLORES_COMERCIO)) {
  ids <- names(cantidades)
  nom <- function(id) if (!is.null(nombres) && !is.na(nombres[id])) unname(nombres[id]) else id
  precios <- precios[as.character(precios$id_comparable) %in% ids, ]

  por_comercio <- do.call(rbind, lapply(comercios, function(cm) {
    p <- precios[precios$comercio == cm & !is.na(precios$precio), ]
    idp <- as.character(p$id_comparable)
    tiene <- ids %in% idp
    total <- NA_real_
    if (all(tiene)) {
      pm <- vapply(ids, function(i) min(p$precio[idp == i]), numeric(1))
      total <- sum(pm * cantidades[ids])
    }
    data.frame(comercio = cm, completo = all(tiene), total = total,
               faltan = paste(vapply(ids[!tiene], nom, character(1)), collapse = "; "),
               stringsAsFactors = FALSE)
  }))

  ap <- ahorro_por_producto(precios)
  detalle <- do.call(rbind, lapply(ids, function(i) {
    fila <- ap[ap$id_comparable == i, ]
    data.frame(id_comparable = i, producto = nom(i), cantidad = unname(cantidades[i]),
               comercio = if (nrow(fila)) fila$mas_baratos else NA_character_,
               precio = if (nrow(fila)) fila$minimo else NA_real_,
               subtotal = if (nrow(fila)) fila$minimo * unname(cantidades[i]) else NA_real_,
               stringsAsFactors = FALSE)
  }))

  minimo <- if (anyNA(detalle$subtotal)) NA_real_ else sum(detalle$subtotal)
  completos <- por_comercio[por_comercio$completo, ]
  mejor_unico <- if (nrow(completos) > 0) min(completos$total) else NA_real_
  mas_caro    <- if (nrow(completos) > 0) max(completos$total) else NA_real_
  ahorro <- if (!is.na(minimo) && !is.na(mejor_unico)) mejor_unico - minimo else NA_real_

  list(por_comercio = por_comercio, detalle = detalle,
       minimo = minimo, mejor_unico = mejor_unico, mas_caro = mas_caro,
       ahorro = ahorro,
       ahorro_pct = if (!is.na(ahorro) && mejor_unico > 0) round(100 * ahorro / mejor_unico, 1) else NA_real_)
}

# ---- Historial de ejecuciones -----------------------------------------------

historial_ejecuciones <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT e.id_ejecucion, c.nombre AS comercio, e.fecha_hora_inicio, e.estado,
           e.registros, e.productos, e.total_sitio, e.rechazadas, e.modo,
           e.mensaje, e.ruta_raw
    FROM   ejecuciones e
    JOIN   comercios c ON c.id_comercio = e.id_comercio
    ORDER  BY e.fecha_hora_inicio DESC")
}
