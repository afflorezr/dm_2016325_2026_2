# db.R: acceso a la base SQLite. Sin codigo de interfaz.
RUTA_BD <- "comparador_precios.sqlite"

# Fecha y hora actual en ISO 8601 con zona de Bogota: 2026-11-07T10:30:00-05:00
ahora_iso <- function() {
  f <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", f)
}

# Abre la conexion con las llaves foraneas activas. Quien la abre la cierra con DBI::dbDisconnect().
conectar <- function(ruta = RUTA_BD) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

# SKU de los productos comparables (conjunto de 8) en cada comercio
skus_conjunto <- function(con) {
  DBI::dbGetQuery(con,
                  "SELECT c.codigo AS comercio, a.sku
       FROM anuncios a
       JOIN comercios c ON c.id_comercio  = a.id_comercio
       JOIN productos p ON p.id_producto  = a.id_producto
      WHERE p.en_conjunto = 1")
}

# Guarda en `rechazos` las observaciones que no pasaron la validacion
registrar_rechazos <- function(con, rechazadas) {
  if (is.null(rechazadas) || nrow(rechazadas) == 0) return(invisible(0L))
  n <- DBI::dbExecute(con,
                      "INSERT OR IGNORE INTO rechazos (fecha_hora_registro, codigo_corrida, comercio, sku, nombre,
                           precio_texto, regla, motivo)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                      params = list(rep(ahora_iso(), nrow(rechazadas)),
                                    rechazadas$codigo_corrida, rechazadas$comercio, rechazadas$sku,
                                    rechazadas$nombre, rechazadas$precio_texto,
                                    rechazadas$regla, rechazadas$motivo))
  invisible(n)
}

# Ejecuta un archivo .sql (sentencias terminadas en ; al final de linea) en una sola transaccion
aplicar_sql <- function(con, archivo) {
  sql <- paste(readLines(archivo, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  sentencias <- strsplit(sql, ";[[:space:]]*\n")[[1]]
  DBI::dbWithTransaction(con, {
    for (s in sentencias) {
      if (nzchar(trimws(gsub("--[^\n]*", "", s)))) DBI::dbExecute(con, s)
    }
  })
  invisible(length(sentencias))
}

# Guarda las tarjetas "agotado segun el sitio". Solo entran las de ejecuciones ya registradas.
# `agotados` conserva las columnas del scraper (id_ejecucion = codigo de la corrida)
registrar_agotados <- function(con, agotados) {
  if (is.null(agotados) || nrow(agotados) == 0) return(invisible(0L))
  n <- DBI::dbExecute(con,
                      "INSERT OR IGNORE INTO agotados (id_ejecucion, id_comercio, fecha_hora_consulta, nombre, url, texto_original)
     SELECT e.id_ejecucion, c.id_comercio, ?, ?, ?, ?
       FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
      WHERE e.codigo_corrida = ? AND c.codigo = ?",
                      params = list(agotados$fecha_consulta, agotados$nombres, agotados$url,
                                    agotados$texto_original_anuncio, agotados$id_ejecucion, agotados$comercio))
  invisible(n)
}

# =====================================================================
# F2. CONSULTAS PARA LA APP
# Reglas: todas reciben `con` (no abren ni cierran conexiones), devuelven
# tablas (data.frame) o listas de tablas, y pasan todo valor del usuario
# como parametro (? o :nombre). Nunca se concatena texto del usuario en el SQL.
# `f` es una lista con cualquiera de estos campos (NULL o vacio = sin filtro):
#   comercios, subcategorias, marcas  (vectores de texto)
#   precio (c(min, max) en COP), corrida (codigo_corrida), fechas (c(desde, hasta))
#   solo_promociones, solo_comparables (TRUE/FALSE), texto (busqueda libre)
# Fuente de datos: con `corrida` -> observaciones de esa corrida;
# con `fechas` -> observaciones entre esas fechas (inclusive);
# sin ninguno -> el ultimo precio de cada anuncio (v_ultimo_precio).
# "comparables" = productos del conjunto de 8 (en_conjunto = 1).
# =====================================================================

# ---------- S3: validacion de entradas del usuario ----------
MAX_TEXTO    <- 60L   # caracteres maximos de la busqueda
MAX_PALABRAS <- 5L
MAX_OPCIONES <- 50L
RX_CORRIDA   <- "^[0-9]{14}$"

# Error con mensaje en espanol para mostrar al usuario (clase "error_validacion")
error_validacion <- function(mensaje) {
  stop(structure(class = c("error_validacion", "error", "condition"),
                 list(message = mensaje, call = NULL)))
}

# Devuelve el texto limpio, NULL si esta vacio, o error_validacion si no es valido
validar_texto <- function(x, max_car = MAX_TEXTO) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) return(NULL)
  x <- trimws(gsub("[[:space:]]+", " ", enc2utf8(as.character(x[1]))))
  if (!nzchar(x)) return(NULL)
  if (nchar(x) > max_car)
    error_validacion(sprintf("La b\u00fasqueda admite m\u00e1ximo %d caracteres.", max_car))
  if (!grepl("^[\\p{L}\\p{N} .,'-]+$", x, perl = TRUE))
    error_validacion("La b\u00fasqueda solo admite letras, n\u00fameros, espacios y los signos . , ' -")
  if (length(strsplit(x, " ", fixed = TRUE)[[1]]) > MAX_PALABRAS)
    error_validacion(sprintf("La b\u00fasqueda admite m\u00e1ximo %d palabras.", MAX_PALABRAS))
  x
}

# Escapa los comodines de LIKE (\ % _) para que se busquen como texto literal
escapar_like <- function(x) gsub("([\\\\%_])", "\\\\\\1", x)

# ---------- utilidades internas ----------
marcadores <- function(n) paste(rep("?", n), collapse = ", ")

consultar <- function(con, sql, params = NULL) {
  if (length(params) == 0) params <- NULL else if (is.null(names(params))) params <- unname(params)
  DBI::dbGetQuery(con, sql, params = params)
}

# Un solo valor de texto, o NULL si viene vacio
un_valor <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x[1]) || !nzchar(as.character(x[1]))) return(NULL)
  as.character(x[1])
}

validar_corrida <- function(x) {
  x <- un_valor(x)
  if (!is.null(x) && !grepl(RX_CORRIDA, x)) error_validacion("Ejecuci\u00f3n no v\u00e1lida.")
  x
}

# Codigo de la corrida mas reciente (cualquier estado) o NA
corrida_ultima <- function(con) {
  r <- consultar(con, "SELECT codigo_corrida FROM ejecuciones
                        GROUP BY codigo_corrida ORDER BY MIN(fecha_hora_inicio) DESC LIMIT 1")$codigo_corrida
  if (length(r)) r else NA_character_
}

# Corridas en que TODOS los comercios quedaron `completa`, de la mas reciente a la mas antigua
corridas_completas <- function(con, n = 2L) {
  consultar(con, "SELECT codigo_corrida FROM ejecuciones
                   GROUP BY codigo_corrida HAVING SUM(estado <> 'completa') = 0
                   ORDER BY MIN(fecha_hora_inicio) DESC LIMIT ?",
            list(as.integer(n)))$codigo_corrida
}

fecha_corrida <- function(con, codigo) {
  if (is.null(codigo) || is.na(codigo)) return(NA_character_)
  r <- consultar(con, "SELECT MIN(fecha_hora_inicio) AS f FROM ejecuciones WHERE codigo_corrida = ?",
                 list(codigo))$f
  if (length(r)) r else NA_character_
}

# ---------- filtros: validacion y construccion del WHERE ----------
normalizar_filtros <- function(f = NULL) {
  f <- if (is.null(f)) list() else as.list(f)

  lista <- function(x, que) {
    if (is.null(x) || length(x) == 0) return(NULL)
    x <- unique(as.character(x)); x <- x[!is.na(x) & nzchar(x)]
    if (length(x) == 0) return(NULL)
    if (length(x) > MAX_OPCIONES || any(nchar(x) > 100))
      error_validacion(sprintf("El filtro de %s no es v\u00e1lido.", que))
    x
  }

  precio <- f[["precio"]]
  if (!is.null(precio) && length(precio) > 0) {
    p <- suppressWarnings(as.numeric(precio))
    if (length(p) != 2 || anyNA(p) || !all(is.finite(p)))
      error_validacion("El rango de precio no es v\u00e1lido.")
    precio <- sort(p)
  } else precio <- NULL

  fechas <- f[["fechas"]]
  if (!is.null(fechas) && length(fechas) > 0) {
    d <- tryCatch(as.Date(as.character(fechas)), error = function(e) NA)
    if (length(d) != 2 || anyNA(d)) error_validacion("El rango de fechas no es v\u00e1lido.")
    d <- sort(d)
    # desde (inclusive) y hasta (exclusivo, dia siguiente): sirve para comparar texto ISO con indice
    fechas <- c(paste0(format(d[1]), "T00:00:00"), paste0(format(d[2] + 1), "T00:00:00"))
  } else fechas <- NULL

  texto <- validar_texto(f[["texto"]])

  list(comercios = lista(f[["comercios"]], "comercio"),
       subcategorias = lista(f[["subcategorias"]], "subcategor\u00eda"),
       marcas = lista(f[["marcas"]], "marca"),
       precio = precio,
       corrida = validar_corrida(f[["corrida"]]),
       fechas = fechas,
       solo_promociones = isTRUE(f[["solo_promociones"]]),
       solo_comparables = isTRUE(f[["solo_comparables"]]),
       palabras = if (is.null(texto)) NULL else strsplit(texto, " ", fixed = TRUE)[[1]])
}

# Devuelve la subconsulta `fuente` (SQL con marcadores ?) y sus `params`
construir_filtro <- function(f = NULL) {
  f <- normalizar_filtros(f)
  w <- character(); p <- list()
  agregar <- function(clausula, valores = list()) {
    w <<- c(w, clausula); p <<- c(p, as.list(valores))
  }
  if (!is.null(f$corrida)) {
    vista <- "v_precios"; tipo <- "ejecucion"
    agregar("codigo_corrida = ?", f$corrida)
  } else if (!is.null(f$fechas)) {
    vista <- "v_precios"; tipo <- "fechas"
    agregar("fecha_hora_consulta >= ? AND fecha_hora_consulta < ?", f$fechas)
  } else {
    vista <- "v_ultimo_precio"; tipo <- "ultimo_precio"
  }
  if (!is.null(f$comercios))     agregar(sprintf("comercio IN (%s)", marcadores(length(f$comercios))), f$comercios)
  if (!is.null(f$subcategorias)) agregar(sprintf("subcategoria IN (%s)", marcadores(length(f$subcategorias))), f$subcategorias)
  if (!is.null(f$marcas))        agregar(sprintf("marca IN (%s)", marcadores(length(f$marcas))), f$marcas)
  if (!is.null(f$precio))        agregar("precio BETWEEN ? AND ?", f$precio)
  if (f$solo_promociones)        agregar("es_promocion = 1")
  if (f$solo_comparables)        agregar("en_conjunto = 1")
  for (pal in f$palabras) {
    patron <- paste0("%", escapar_like(pal), "%")
    agregar("(nombre LIKE ? ESCAPE '\\' OR texto_original_anuncio LIKE ? ESCAPE '\\')", list(patron, patron))
  }
  donde <- if (length(w)) paste("WHERE", paste(w, collapse = " AND ")) else ""
  list(fuente = sprintf("SELECT * FROM %s %s", vista, donde), params = p, tipo = tipo,
       corrida = f$corrida)
}

# ---------- estadisticos en SQL (SQLite no tiene MEDIAN ni percentiles) ----------
# Percentil con interpolacion lineal (igual a quantile(type = 7) de R) sobre ROW_NUMBER.
sql_percentil <- function(p) {
  pos <- sprintf("(1.0 + (n - 1) * %.4f)", p)
  sprintf(paste0("SUM(CASE WHEN rn = CAST(%1$s AS INTEGER) THEN val * (1.0 - (%1$s - CAST(%1$s AS INTEGER))) ",
                 "WHEN rn = CAST(%1$s AS INTEGER) + 1 THEN val * (%1$s - CAST(%1$s AS INTEGER)) END)"), pos)
}

# `base`: SQL que expone las columnas de `grupos` y `valor`. Nombres internos, nunca del usuario.
estadisticos_sql <- function(base, valor, grupos = character(),
                             stats = c("n", "minimo", "q1", "mediana", "q3", "maximo")) {
  g    <- paste(grupos, collapse = ", ")
  part <- if (length(grupos)) paste("PARTITION BY", g) else ""
  sel  <- c(n = "MAX(n)", minimo = "MIN(val)", q1 = sql_percentil(0.25),
            mediana = sql_percentil(0.5), q3 = sql_percentil(0.75), maximo = "MAX(val)")
  sel  <- paste(sprintf("%s AS %s", sel[stats], stats), collapse = ", ")
  sprintf(paste0("WITH b AS (%s), ",
                 "r AS (SELECT %s%s AS val, ROW_NUMBER() OVER (%s ORDER BY %s) AS rn, ",
                 "COUNT(*) OVER (%s) AS n FROM b WHERE %s IS NOT NULL) ",
                 "SELECT %s%s FROM r %s"),
          base,
          if (length(grupos)) paste0(g, ", ") else "", valor, part, valor, part, valor,
          if (length(grupos)) paste0(g, ", ") else "", sel,
          if (length(grupos)) sprintf("GROUP BY %s ORDER BY %s", g, g) else "")
}

# ---------- 1. opciones de los filtros ----------
opciones_filtros <- function(con) {
  rango <- consultar(con, "SELECT MIN(precio_cop) AS minimo, MAX(precio_cop) AS maximo FROM observaciones")
  fech  <- consultar(con, "SELECT SUBSTR(MIN(fecha_hora_consulta), 1, 10) AS desde,
                                  SUBSTR(MAX(fecha_hora_consulta), 1, 10) AS hasta FROM observaciones")
  list(
    comercios     = consultar(con, "SELECT nombre FROM comercios ORDER BY id_comercio")$nombre,
    subcategorias = consultar(con, "SELECT DISTINCT subcategoria_std AS x FROM anuncios
                                     WHERE subcategoria_std IS NOT NULL ORDER BY 1")$x,
    marcas        = consultar(con, "SELECT DISTINCT marca_std AS x FROM anuncios
                                     WHERE marca_std IS NOT NULL ORDER BY 1")$x,
    precio        = c(minimo = rango$minimo, maximo = rango$maximo),
    fechas        = c(desde = fech$desde, hasta = fech$hasta),
    # una corrida agrupa a los comercios; completa solo si todos quedaron completos
    ejecuciones   = consultar(con,
      "SELECT codigo_corrida, MIN(fecha_hora_inicio) AS fecha_hora_inicio, COUNT(*) AS comercios,
              CASE WHEN SUM(estado <> 'completa') = 0 THEN 'completa'
                   WHEN SUM(estado = 'fallida') = COUNT(*) THEN 'fallida'
                   ELSE 'parcial' END AS estado
         FROM ejecuciones GROUP BY codigo_corrida ORDER BY MIN(fecha_hora_inicio) DESC"),
    productos     = consultar(con, "SELECT id_producto, nombre AS producto FROM productos
                                     WHERE en_conjunto = 1 ORDER BY id_producto")
  )
}

# ---------- 2. tabla de productos filtrados ----------
filtrar_precios <- function(con, f = NULL) {
  b <- construir_filtro(f)
  sql <- sprintf(
    "SELECT id_observacion, id_anuncio, comercio, sku, nombre, marca, subcategoria, presentacion,
            precio, precio_lista, es_promocion, medida, precio_por_medida, disponibilidad,
            es_comparable, en_conjunto, id_producto, fecha_hora_consulta, codigo_corrida, url_producto
       FROM (%s) ORDER BY comercio, nombre", b$fuente)
  consultar(con, sql, b$params)
}

# ---------- 3. indicadores (todo en SQL) ----------
# por_comercio, resumen, mediana_subcategoria dependen de los filtros (describen lo filtrado).
# ultima_ejecucion, ahorro_maximo y cambios_ultima describen la base: ahorro_maximo respeta `corrida`.
indicadores <- function(con, f = NULL) {
  b <- construir_filtro(f)

  por_comercio <- consultar(con, sprintf(
    "SELECT comercio, COUNT(DISTINCT id_anuncio) AS productos, COUNT(*) AS observaciones
       FROM (%s) GROUP BY comercio ORDER BY comercio", b$fuente), b$params)

  resumen <- consultar(con, sprintf(
    "SELECT COUNT(DISTINCT id_anuncio) AS productos, COUNT(*) AS observaciones,
            COUNT(DISTINCT CASE WHEN es_promocion = 1 THEN id_anuncio END) AS productos_en_promocion,
            ROUND(100.0 * COUNT(DISTINCT CASE WHEN es_promocion = 1 THEN id_anuncio END)
                  / NULLIF(COUNT(DISTINCT id_anuncio), 0), 1) AS pct_promocion,
            MIN(fecha_hora_consulta) AS fecha_desde, MAX(fecha_hora_consulta) AS fecha_hasta
       FROM (%s)", b$fuente), b$params)
  med <- consultar(con, estadisticos_sql(sprintf("SELECT precio FROM (%s)", b$fuente),
                                         "precio", stats = "mediana"), b$params)
  resumen$mediana_precio <- med$mediana
  resumen$periodo <- b$tipo   # ultimo_precio | ejecucion | fechas

  mediana_subcategoria <- consultar(con, estadisticos_sql(
    sprintf("SELECT COALESCE(subcategoria, 'sin dato') AS subcategoria, precio FROM (%s)", b$fuente),
    "precio", "subcategoria", stats = c("n", "mediana")), b$params)

  ult <- corrida_ultima(con)
  ultima_ejecucion <- consultar(con,
    "SELECT e.codigo_corrida, c.nombre AS comercio, e.estado, e.fecha_hora_inicio, e.n_registros, e.mensaje
       FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
      WHERE e.codigo_corrida = ? ORDER BY c.id_comercio", list(ult))

  cor_ahorro <- if (!is.null(b$corrida)) b$corrida else {
    x <- corridas_completas(con, 1); if (length(x)) x else NA_character_ }
  ahorro_maximo <- consultar(con,
    "WITH p AS (SELECT id_producto, producto, comercio, MIN(precio) AS precio
                  FROM v_precios
                 WHERE codigo_corrida = ? AND en_conjunto = 1 AND disponibilidad = 'disponible'
                 GROUP BY id_producto, producto, comercio),
          g AS (SELECT id_producto, producto, MIN(precio) AS precio_min, MAX(precio) AS precio_max
                  FROM p GROUP BY id_producto, producto HAVING COUNT(*) >= 2)
     SELECT ? AS codigo_corrida, g.id_producto, g.producto,
            (SELECT comercio FROM p WHERE p.id_producto = g.id_producto AND p.precio = g.precio_min
              ORDER BY comercio LIMIT 1) AS comercio_barato, g.precio_min,
            (SELECT comercio FROM p WHERE p.id_producto = g.id_producto AND p.precio = g.precio_max
              ORDER BY comercio DESC LIMIT 1) AS comercio_caro, g.precio_max,
            g.precio_max - g.precio_min AS ahorro_cop,
            ROUND(100.0 * (g.precio_max - g.precio_min) / g.precio_max, 1) AS ahorro_pct
       FROM g ORDER BY ahorro_cop DESC, g.id_producto LIMIT 1",
    list(cor_ahorro, cor_ahorro))
  ahorro_maximo$fecha_corrida <- rep(fecha_corrida(con, cor_ahorro), nrow(ahorro_maximo))

  cambios_ultima <- consultar(con,
    "SELECT ? AS codigo_corrida, COUNT(*) AS comparados,
            COALESCE(SUM(variacion_cop > 0), 0) AS suben,
            COALESCE(SUM(variacion_cop < 0), 0) AS bajan,
            COALESCE(SUM(variacion_cop = 0), 0) AS sin_cambio,
            COALESCE(SUM(variacion_cop <> 0 AND id_producto IN
                         (SELECT id_producto FROM productos WHERE en_conjunto = 1)), 0) AS cambios_conjunto
       FROM v_cambios_precio
      WHERE id_ejecucion IN (SELECT id_ejecucion FROM ejecuciones WHERE codigo_corrida = ?)",
    list(ult, ult))

  list(por_comercio = por_comercio, resumen = resumen, mediana_subcategoria = mediana_subcategoria,
       ultima_ejecucion = ultima_ejecucion, ahorro_maximo = ahorro_maximo, cambios_ultima = cambios_ultima)
}

# ---------- 4. grafico 1: evolucion del precio de un producto comparable ----------
serie_precio <- function(con, id_producto) {
  id <- suppressWarnings(as.integer(un_valor(id_producto)))
  if (is.na(id)) error_validacion("Elige un producto.")
  consultar(con,
    "SELECT comercio, codigo_corrida, estado_ejecucion, fecha_hora_consulta, precio, precio_lista,
            es_promocion, disponibilidad
       FROM v_precios WHERE id_producto = ? ORDER BY comercio, fecha_hora_consulta", list(id))
}

# ---------- 5. grafico 2: precio por mL o g, sin mezclar unidades ----------
# Una fila por comercio y unidad (medida). Anuncios sin contenido leido se excluyen (su precio unitario es NULL).
precio_unitario <- function(con, f = NULL) {
  b <- construir_filtro(f)
  base <- sprintf("SELECT comercio, medida, precio_por_medida FROM (%s)
                    WHERE medida IS NOT NULL AND precio_por_medida IS NOT NULL", b$fuente)
  consultar(con, estadisticos_sql(base, "precio_por_medida", c("comercio", "medida"),
                                  stats = c("n", "minimo", "mediana", "maximo")), b$params)
}

# ---------- 6. grafico 3: distribucion de precios por comercio ----------
distribucion_precios <- function(con, f = NULL) {
  b <- construir_filtro(f)
  base <- sprintf("SELECT comercio, precio FROM (%s)", b$fuente)
  consultar(con, estadisticos_sql(base, "precio", "comercio"), b$params)
}

# ---------- 7. cambios entre dos ejecuciones ----------
# ej_a y ej_b son codigos de corrida. Sin ellos: las dos ultimas corridas completas (a = anterior, b = reciente).
# variacion = precio en b menos precio en a, sobre el mismo anuncio (y por tanto el mismo comercio).
# situacion: sube, baja, igual, nuevo (solo en b), no_observado (solo en a), agotado_segun_sitio (solo en a y el sitio lo mostro agotado en b)
cambios_entre <- function(con, ej_a = NULL, ej_b = NULL, umbral = 10) {
  ej_a <- validar_corrida(ej_a); ej_b <- validar_corrida(ej_b)
  if (is.null(ej_a) != is.null(ej_b)) error_validacion("Elige las dos ejecuciones que quieres comparar.")
  if (is.null(ej_a)) {
    ult <- corridas_completas(con, 2L)
    if (length(ult) < 2) error_validacion("Se necesitan al menos dos ejecuciones completas para comparar.")
    ej_b <- ult[1]; ej_a <- ult[2]
  }
  if (ej_a == ej_b) error_validacion("Elige dos ejecuciones distintas.")
  umbral <- suppressWarnings(as.numeric(umbral))
  if (length(umbral) != 1 || is.na(umbral) || umbral < 0 || umbral > 1000)
    error_validacion("El umbral debe estar entre 0 y 1000 (%).")
  n <- consultar(con, "SELECT COUNT(DISTINCT codigo_corrida) AS n FROM ejecuciones WHERE codigo_corrida IN (?, ?)",
                 list(ej_a, ej_b))$n
  if (n != 2) error_validacion("Alguna de las ejecuciones elegidas no existe.")

  consultar(con,
    "WITH a AS (SELECT id_anuncio, precio FROM v_precios WHERE codigo_corrida = :ej_a),
          b AS (SELECT id_anuncio, precio FROM v_precios WHERE codigo_corrida = :ej_b),
          ids AS (SELECT id_anuncio FROM a UNION SELECT id_anuncio FROM b)
     SELECT c.nombre AS comercio, n.id_anuncio, n.sku, n.nombre_original AS nombre, n.id_producto,
            a.precio AS precio_a, b.precio AS precio_b,
            b.precio - a.precio AS variacion_cop,
            ROUND(100.0 * (b.precio - a.precio) / a.precio, 1) AS variacion_pct,
            CASE WHEN a.precio IS NULL THEN 'nuevo'
                 WHEN b.precio IS NULL THEN
                   CASE WHEN EXISTS (SELECT 1 FROM agotados g JOIN ejecuciones e ON e.id_ejecucion = g.id_ejecucion
                                      WHERE e.codigo_corrida = :ej_b AND g.id_comercio = n.id_comercio
                                        AND g.url = n.url_producto)
                        THEN 'agotado_segun_sitio' ELSE 'no_observado' END
                 WHEN b.precio > a.precio THEN 'sube'
                 WHEN b.precio < a.precio THEN 'baja'
                 ELSE 'igual' END AS situacion,
            CASE WHEN a.precio IS NOT NULL AND b.precio IS NOT NULL
                  AND ABS(100.0 * (b.precio - a.precio) / a.precio) >= :umbral THEN 1 ELSE 0 END AS supera_umbral,
            n.url_producto
       FROM ids i
       JOIN anuncios  n ON n.id_anuncio  = i.id_anuncio
       JOIN comercios c ON c.id_comercio = n.id_comercio
       LEFT JOIN a ON a.id_anuncio = i.id_anuncio
       LEFT JOIN b ON b.id_anuncio = i.id_anuncio
      ORDER BY c.id_comercio, ABS(100.0 * (b.precio - a.precio) / a.precio) DESC, n.nombre_original",
    list(ej_a = ej_a, ej_b = ej_b, umbral = umbral))
}

# ---------- 8. canasta ----------
AVISO_CANASTA <- "El resultado no incluye env\u00edo, m\u00ednimos de compra ni las condiciones de las promociones."

# items: data.frame(id_producto, cantidad) con productos del conjunto comparable.
# ejecucion: codigo de corrida; sin ella, la ultima corrida completa.
# Un comercio solo tiene total si ofrece TODOS los productos (disponibles) en esa corrida.
canasta <- function(con, items, ejecucion = NULL) {
  if (!is.data.frame(items) || !all(c("id_producto", "cantidad") %in% names(items)) || nrow(items) == 0)
    error_validacion("Elige al menos un producto para la canasta.")
  if (nrow(items) > 20) error_validacion("La canasta admite m\u00e1ximo 20 productos.")
  id  <- suppressWarnings(as.numeric(items$id_producto))
  can <- suppressWarnings(as.numeric(items$cantidad))
  if (anyNA(id) || anyNA(can) || any(id != round(id)) || any(can != round(can)) || any(can < 1 | can > 99))
    error_validacion("Las cantidades deben ser n\u00fameros enteros entre 1 y 99.")
  if (anyDuplicated(id)) error_validacion("Un producto no puede repetirse en la canasta.")
  id <- as.integer(id); can <- as.integer(can)
  validos <- consultar(con, "SELECT id_producto FROM productos WHERE en_conjunto = 1")$id_producto
  if (!all(id %in% validos)) error_validacion("Solo se pueden elegir productos comparables.")

  ejecucion <- validar_corrida(ejecucion)
  if (is.null(ejecucion)) {
    x <- corridas_completas(con, 1L)
    if (!length(x)) error_validacion("No hay ninguna ejecuci\u00f3n completa para calcular la canasta.")
    ejecucion <- x
  }
  if (consultar(con, "SELECT COUNT(*) AS n FROM ejecuciones WHERE codigo_corrida = ?", list(ejecucion))$n == 0)
    error_validacion("La ejecuci\u00f3n elegida no existe.")

  cte <- sprintf(
    "WITH items(id_producto, cantidad) AS (VALUES %s),
          precios AS (SELECT id_comercio, id_producto, MIN(precio) AS precio FROM v_precios
                       WHERE codigo_corrida = ? AND en_conjunto = 1 AND disponibilidad = 'disponible'
                       GROUP BY id_comercio, id_producto) ",
    paste(rep("(?, ?)", length(id)), collapse = ", "))
  par <- c(as.list(as.vector(rbind(id, can))), list(ejecucion))

  detalle <- consultar(con, paste0(cte,
    "SELECT c.nombre AS comercio, i.id_producto, p.nombre AS producto, i.cantidad,
            pr.precio AS precio_unitario, pr.precio * i.cantidad AS subtotal
       FROM comercios c CROSS JOIN items i
       JOIN productos p ON p.id_producto = i.id_producto
       LEFT JOIN precios pr ON pr.id_comercio = c.id_comercio AND pr.id_producto = i.id_producto
      ORDER BY c.id_comercio, i.id_producto"), par)

  totales <- consultar(con, paste0(cte,
    "SELECT c.nombre AS comercio, COUNT(*) AS productos_pedidos, COUNT(pr.precio) AS productos_con_precio,
            CASE WHEN COUNT(pr.precio) = COUNT(*) THEN 1 ELSE 0 END AS completa,
            CASE WHEN COUNT(pr.precio) = COUNT(*) THEN SUM(pr.precio * i.cantidad) END AS costo,
            GROUP_CONCAT(CASE WHEN pr.precio IS NULL THEN p.nombre END, '; ') AS faltantes
       FROM comercios c CROSS JOIN items i
       JOIN productos p ON p.id_producto = i.id_producto
       LEFT JOIN precios pr ON pr.id_comercio = c.id_comercio AND pr.id_producto = i.id_producto
      GROUP BY c.id_comercio, c.nombre ORDER BY c.id_comercio"), par)

  compra_optima <- consultar(con, paste0(cte,
    "SELECT id_producto, producto, cantidad, comercio, precio_unitario, subtotal FROM (
       SELECT i.id_producto, p.nombre AS producto, i.cantidad, c.nombre AS comercio,
              pr.precio AS precio_unitario, pr.precio * i.cantidad AS subtotal,
              ROW_NUMBER() OVER (PARTITION BY i.id_producto ORDER BY pr.precio, c.nombre) AS rn
         FROM items i JOIN productos p ON p.id_producto = i.id_producto
         CROSS JOIN comercios c
         JOIN precios pr ON pr.id_comercio = c.id_comercio AND pr.id_producto = i.id_producto)
      WHERE rn = 1 ORDER BY id_producto"), par)

  completos   <- totales[totales$completa == 1, , drop = FALSE]
  unico       <- if (nrow(completos)) completos[which.min(completos$costo), ] else NULL
  optimo_ok   <- nrow(compra_optima) == length(id)
  costo_min   <- if (optimo_ok) sum(compra_optima$subtotal) else NA_real_
  costo_unico <- if (is.null(unico)) NA_real_ else unico$costo
  ahorro      <- if (optimo_ok && !is.null(unico)) costo_unico - costo_min else NA_real_

  list(ejecucion = data.frame(codigo_corrida = ejecucion, fecha = fecha_corrida(con, ejecucion)),
       detalle = detalle, totales = totales, compra_optima = compra_optima,
       resumen = data.frame(costo_minimo_combinado = costo_min,
                            mejor_comercio_unico = if (is.null(unico)) NA_character_ else unico$comercio,
                            costo_mejor_comercio_unico = costo_unico,
                            ahorro_cop = ahorro,
                            ahorro_pct = if (is.na(ahorro)) NA_real_ else round(100 * ahorro / costo_unico, 1)),
       advertencia = AVISO_CANASTA)
}
