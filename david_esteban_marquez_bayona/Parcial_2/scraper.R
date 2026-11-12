# scraper.R — Extracción · Taller 2 · Minería de Datos (2016325) · UNAL · cuidado bucal.
#
# Versión en R de scraper.py del Taller 1 (el taller exige un solo lenguaje y la aplicación
# es Shiny). Mismo método, mismas rutas y mismo formato de raw/, de modo que las copias
# crudas del Taller 1 se siguen leyendo sin cambios.
#
# Éxito, Olímpica y Locatel usan la plataforma VTEX: sus páginas de categoría se llenan con
# servicios JSON públicos del propio sitio, que aquí se consultan con peticiones HTTP:
#   1. GET /api/catalog_system/pub/category/tree/4 -> secciones de «cuidado oral/bucal/dental».
#   2. GET /api/catalog_system/pub/products/search?fq=C:/<ids>/&_from=&_to= -> 50 productos por
#      página; el encabezado `resources: 0-49/N` informa el total N que reporta el sitio.
#   3. Cada respuesta se guarda sin modificar en raw/<comercio>/<fecha>/<ejecución>/ (gzip) con
#      un manifest.json. Los datos SIEMPRE se procesan desde raw/: en línea y sin conexión el
#      resultado es idéntico y cada observación se puede rastrear hasta su copia cruda.
#
# Uso desde la consola (carpeta taller_2/):
#   Rscript scraper.R                  nueva ejecución en línea
#   Rscript scraper.R --sin-conexion   reprocesa raw/ sin consultar los sitios
#   Rscript scraper.R --robots         revisa y guarda robots.txt

if (!exists("normalizar_texto")) source("limpieza.R", encoding = "UTF-8")
if (!exists("validar_observaciones")) source("validacion.R", encoding = "UTF-8")

TZ <- "America/Bogota"
DB_PATH <- "comparador_precios.sqlite"
RAW_DIR <- "raw"
PAGINA <- 50L; LIMITE <- 2500L        # VTEX no pagina más allá de _from = 2500
PAUSA <- 1.0; INTENTOS <- 4L          # pausa entre peticiones (s) y reintentos con espera exponencial
MAX_PETICIONES <- 80L                 # tope de peticiones por comercio en una ejecución
USER_AGENT <- paste0("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ",
                     "Chrome/129.0 Safari/537.36 TallerMineriaDatosUNAL/2.0 (uso academico)")
ARBOL <- "/api/catalog_system/pub/category/tree/4"
BUSQUEDA <- "/api/catalog_system/pub/products/search"
PATRON <- "\\b(cuidado|salud|higiene)\\s+(oral|bucal|dental)\\b"
RESPALDO <- "\\b(cremas?|pastas?) (dental|dentales)\\b|\\bcepillos? (dental|dentales)\\b|\\benjuagues? bucal|\\b(seda|hilo) dental"
EXCLUIR <- "\\b(mascotas?|perros?|gatos?)\\b"

COMERCIOS <- list(   # comercio_id = c(nombre, tipo, url_base)
  exito = c("\u00c9xito", "Gran superficie", "https://www.exito.com"),
  olimpica = c("Ol\u00edmpica", "Supermercado y droguer\u00eda", "https://www.olimpica.com"),
  locatel = c("Locatel", "Droguer\u00eda / salud", "https://www.locatelcolombia.com")
)
FILTROS <- list()    # para fijar secciones a mano, p. ej. list(exito = c("/12/345/"))

COLUMNAS <- c(
  "comercio_id", "ejecucion_id", "fecha_hora_consulta", "url_fuente", "seccion_id", "seccion_nombre",
  "product_id_comercio", "sku_comercio", "ean", "referencia",
  "nombre_original", "nombre_item_original", "marca_original", "categoria_original",
  "descripcion_original", "ficha_tecnica_original", "texto_original", "url_producto",
  "precio", "precio_lista", "es_promocion", "texto_promocion", "disponible", "vendedor")
.COLS_NUM <- c("precio", "precio_lista"); .COLS_INT <- c("es_promocion", "disponible")

# Fecha y hora de Colombia en ISO 8601, p. ej. 2026-11-09T10:35:00-05:00.
ahora_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00", tz = TZ)

# Convierte un precio (número o texto) en número. «$ 12.900» -> 12900; «12.900,50» -> 12900.5.
# Un precio ausente, no numérico, cero o negativo queda como NA (NULL en la base), nunca 0.
limpiar_precio <- function(x) {
  if (is.null(x) || length(x) != 1 || is.na(x)) return(NA_real_)
  if (is.numeric(x)) return(if (is.finite(x) && x > 0) as.numeric(x) else NA_real_)
  s <- gsub("[^0-9.,-]", "", as.character(x))
  if (!nzchar(s) || grepl("-", s, fixed = TRUE)) return(NA_real_)
  if (grepl(".", s, fixed = TRUE) && grepl(",", s, fixed = TRUE)) {
    # el separador que aparece de último es el decimal
    if (regexpr("\\.[^.]*$", s) > regexpr(",[^,]*$", s)) s <- gsub(",", "", s, fixed = TRUE)
    else s <- sub(",", ".", gsub(".", "", s, fixed = TRUE), fixed = TRUE)
  } else if (grepl("^\\d{1,3}([.,]\\d{3})+$", s)) {
    s <- gsub("[.,]", "", s)                                   # separador de miles: 12.900 / 12,900
  } else {
    s <- sub(",", ".", s, fixed = TRUE)                        # coma decimal: 12900,5
  }
  v <- suppressWarnings(as.numeric(s))
  if (is.na(v) || v <= 0) NA_real_ else v
}

# ---------------------------------------------------------------------------
# Utilidades: verdad «a la Python», JSON de la ficha técnica y archivos gzip
# ---------------------------------------------------------------------------
.vacio <- function(x) {
  is.null(x) || length(x) == 0 || (length(x) == 1 && !is.list(x) &&
    (is.na(x) || identical(x, "") || identical(x, FALSE) || (is.numeric(x) && x == 0)))
}
.o <- function(a, b) if (.vacio(a)) b else a
.txt <- function(x) if (.vacio(x)) NA_character_ else as.character(x)

# Serializa como json.dumps(..., ensure_ascii=False) de Python, para que la ficha técnica y el
# texto original de un anuncio queden idénticos a los del Taller 1.
.json_py <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    if (!is.null(names(x))) {
      return(paste0("{", paste0(vapply(names(x), .json_py, ""), ": ",
                                vapply(x, .json_py, "", USE.NAMES = FALSE), collapse = ", "), "}"))
    }
    return(paste0("[", paste(vapply(x, .json_py, ""), collapse = ", "), "]"))
  }
  if (is.character(x)) {
    s <- gsub("\\", "\\\\", x, fixed = TRUE); s <- gsub("\"", "\\\"", s, fixed = TRUE)
    s <- gsub("\n", "\\n", s, fixed = TRUE); s <- gsub("\r", "\\r", s, fixed = TRUE)
    s <- gsub("\t", "\\t", s, fixed = TRUE); s <- gsub("\b", "\\b", s, fixed = TRUE)
    s <- gsub("\f", "\\f", s, fixed = TRUE)
    return(paste0("\"", s, "\""))
  }
  if (is.logical(x)) return(if (isTRUE(x)) "true" else "false")
  format(x, scientific = FALSE, digits = 15)
}

.leer_gz <- function(ruta) {
  con <- gzfile(ruta, "rb"); on.exit(close(con))
  partes <- list()
  repeat {
    b <- readBin(con, "raw", 1e6)
    if (length(b) == 0) break
    partes[[length(partes) + 1]] <- b
  }
  do.call(c, partes)
}
.escribir_gz <- function(bytes, ruta) {
  con <- gzfile(ruta, "wb"); on.exit(close(con))
  writeBin(bytes, con)
}
.leer_json_gz <- function(ruta) {
  txt <- rawToChar(.leer_gz(ruta)); Encoding(txt) <- "UTF-8"
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

# ---------------------------------------------------------------------------
# Fase en línea: consultar el sitio y guardar las respuestas en raw/
# ---------------------------------------------------------------------------

# GET con reintentos y espera exponencial ante 429/5xx o fallas de red.
.get <- function(url, params = NULL) {
  error <- NULL
  for (i in seq_len(INTENTOS)) {
    req <- httr2::request(url)
    if (!is.null(params)) req <- httr2::req_url_query(req, !!!params)
    req <- httr2::req_headers(req, Accept = "application/json, text/plain, */*", `Accept-Language` = "es-CO,es;q=0.9")
    req <- httr2::req_user_agent(req, USER_AGENT)
    req <- httr2::req_timeout(req, 30)
    req <- httr2::req_error(req, is_error = function(resp) FALSE)
    r <- tryCatch(httr2::req_perform(req), error = function(e) e)
    if (inherits(r, "error")) {
      error <- conditionMessage(r)
    } else if (!(httr2::resp_status(r) %in% c(429, 500, 502, 503, 504))) {
      return(r)
    } else {
      error <- paste("HTTP", httr2::resp_status(r))
    }
    Sys.sleep(PAUSA * 2^i)
  }
  stop(sprintf("%s: %s", url, error), call. = FALSE)
}

# Secciones más altas del árbol que corresponden a cuidado bucal (sin bajar dentro de ellas).
secciones <- function(arbol) {
  buscar <- function(patron, nodos, ids = character(0), nombres = character(0)) {
    salida <- list()
    for (n in nodos) {
      ids2 <- c(ids, as.character(n$id)); nombres2 <- c(nombres, .o(n$name, ""))
      ruta <- paste(nombres2, collapse = " > ")
      if (re_hay(patron, normalizar_texto(n$name)) && !re_hay(EXCLUIR, normalizar_texto(ruta))) {
        salida[[length(salida) + 1]] <- list(seccion_id = as.character(n$id), nombre = n$name, ruta_nombres = ruta,
                                             filtro = paste0("/", paste(ids2, collapse = "/"), "/"), url = n$url)
      } else {
        salida <- c(salida, buscar(patron, n$children, ids2, nombres2))
      }
    }
    salida
  }
  s <- buscar(PATRON, arbol)
  if (length(s) == 0) buscar(RESPALDO, arbol) else s
}

# Secciones de la última ejecución completa del comercio guardada en raw/ (respaldo si el árbol falla).
secciones_previas <- function(cid, raw_dir = RAW_DIR) {
  for (m in rev(sort(Sys.glob(file.path(raw_dir, cid, "*", "*", "manifest.json"))))) {
    man <- tryCatch(jsonlite::fromJSON(m, simplifyVector = FALSE), error = function(e) NULL)
    ok <- Filter(function(x) !is.null(x$filtro) && is.null(x$error) && !.vacio(x$total_reportado), man$secciones)
    if (length(ok) > 0) {
      out <- lapply(ok, function(x) list(seccion_id = as.character(x$seccion_id), nombre = x$nombre,
                                         ruta_nombres = x$ruta_nombres, filtro = x$filtro, url = x$url))
      return(structure(out, ejecucion = man$ejecucion_id))
    }
  }
  list()
}

# Recorre todas las páginas de la categoría y guarda cada respuesta original. Devuelve la carpeta.
descargar <- function(cid, ejecucion_id, raw_dir = RAW_DIR, progreso = function(...) NULL) {
  base <- COMERCIOS[[cid]][3]
  inicio <- ahora_iso()
  carpeta <- file.path(raw_dir, cid, substr(inicio, 1, 10), ejecucion_id)
  dir.create(carpeta, recursive = TRUE, showWarnings = FALSE)
  man <- list(ejecucion_id = ejecucion_id, comercio_id = cid, comercio = COMERCIOS[[cid]][1], url_base = base,
              inicio = inicio, fin = NULL, user_agent = USER_AGENT, secciones = list(), peticiones = list(),
              errores = list())
  guardar <- function(r, tipo, seccion_id = NULL, params = NULL) {
    archivo <- sprintf("%04d_%s%s.json.gz", length(man$peticiones), tipo,
                       if (is.null(seccion_id)) "" else paste0("_s", seccion_id))
    cuerpo <- httr2::resp_body_raw(r)
    .escribir_gz(cuerpo, file.path(carpeta, archivo))
    man$peticiones[[length(man$peticiones) + 1]] <<- list(
      archivo = archivo, tipo = tipo, seccion_id = seccion_id, url = httr2::resp_url(r), params = params,
      fecha_hora_consulta = ahora_iso(), status = httr2::resp_status(r),
      resources = httr2::resp_header(r, "resources"), bytes = length(cuerpo))
    if (httr2::resp_status(r) >= 400) stop(sprintf("HTTP %s en %s", httr2::resp_status(r), httr2::resp_url(r)), call. = FALSE)
    txt <- rawToChar(cuerpo); Encoding(txt) <- "UTF-8"
    jsonlite::fromJSON(txt, simplifyVector = FALSE)
  }
  tryCatch({
    if (!is.null(FILTROS[[cid]])) {
      secs <- lapply(seq_along(FILTROS[[cid]]), function(i) {
        f <- FILTROS[[cid]][i]
        list(seccion_id = paste0("manual", i - 1), nombre = f, ruta_nombres = f, filtro = f, url = NULL)
      })
    } else {
      secs <- tryCatch(secciones(guardar(.get(paste0(base, ARBOL)), "arbol")), error = function(e) {
        # Si el sitio rechaza el árbol de categorías (p. ej. HTTP 403), se reutilizan las secciones
        # de la última ejecución exitosa guardada en raw/: el filtro de categoría no cambia.
        previas <- secciones_previas(cid, raw_dir)
        if (length(previas) == 0) stop(conditionMessage(e), call. = FALSE)
        man$errores[[length(man$errores) + 1]] <<- sprintf(
          "aviso: \u00e1rbol de categor\u00edas no disponible (%s); se usaron las secciones de %s",
          conditionMessage(e), attr(previas, "ejecucion"))
        previas
      })
      if (length(secs) == 0) stop("no se encontr\u00f3 una secci\u00f3n de cuidado bucal", call. = FALSE)
    }
    for (sec in secs) {
      sec$api <- "catalogo"; sec["total_reportado"] <- list(NULL); desde <- 0L
      res <- tryCatch({
        while (desde < LIMITE) {
          if (length(man$peticiones) >= MAX_PETICIONES) stop("se alcanz\u00f3 el tope de peticiones por ejecuci\u00f3n", call. = FALSE)
          Sys.sleep(PAUSA)
          params <- list(fq = paste0("C:", sec$filtro), `_from` = desde, `_to` = desde + PAGINA - 1L, O = "OrderByNameASC")
          r <- .get(paste0(base, BUSQUEDA), params)
          lote <- guardar(r, "productos", sec$seccion_id, params)
          total <- re_buscar("/(\\d+)\\s*$", .o(httr2::resp_header(r, "resources"), ""))
          if (!is.null(total)) sec$total_reportado <- as.integer(total$g[2])
          desde <- desde + PAGINA
          progreso(cid, sprintf("%d de %s productos", min(desde, .o(sec$total_reportado, desde)), .o(sec$total_reportado, "?")))
          if (length(lote) < PAGINA || desde >= .o(sec$total_reportado, LIMITE)) break
        }
        NULL
      }, error = function(e) conditionMessage(e))
      if (!is.null(res)) {
        sec$error <- res
        man$errores[[length(man$errores) + 1]] <- sprintf("secci\u00f3n %s: %s", sec$seccion_id, res)
      }
      man$secciones[[length(man$secciones) + 1]] <- sec
    }
  }, error = function(e) man$errores[[length(man$errores) + 1]] <<- paste("general:", conditionMessage(e)))
  man$fin <- ahora_iso()
  writeLines(jsonlite::toJSON(man, auto_unbox = TRUE, null = "null", pretty = 1), file.path(carpeta, "manifest.json"),
             useBytes = TRUE)
  carpeta
}

# ---------------------------------------------------------------------------
# Procesamiento de las copias crudas (igual en línea y sin conexión)
# ---------------------------------------------------------------------------

# Un registro por SKU del producto VTEX, con las columnas de COLUMNAS.
parsear_producto <- function(prod, man, pet, sec) {
  base <- man$url_base
  espec <- unique(unlist(prod$allSpecifications))
  ficha_txt <- if (length(espec)) .json_py(stats::setNames(lapply(espec, function(n) prod[[n]]), espec)) else NA_character_
  url <- .o(prod$link, if (!.vacio(prod$linkText)) sprintf("%s/%s/p", base, prod$linkText) else NULL)
  if (!is.null(url) && startsWith(url, "/")) url <- paste0(base, url)
  lapply(prod$items, function(item) {
    vendedores <- .o(item$sellers, list(list()))
    por_defecto <- Filter(function(v) !.vacio(v$sellerDefault), vendedores)
    con_precio <- Filter(function(v) !is.na(limpiar_precio(v$commertialOffer$Price)), vendedores)
    vendedor <- if (length(por_defecto)) por_defecto[[1]] else if (length(con_precio)) con_precio[[1]] else vendedores[[1]]
    o <- .o(vendedor$commertialOffer, list())
    precio <- limpiar_precio(o$Price)
    lista <- limpiar_precio(o$ListPrice)
    if (is.na(lista)) lista <- limpiar_precio(o$PriceWithoutDiscount)
    promos <- unlist(lapply(c(o$Teasers, o$PromotionTeasers, o$DiscountHighLight), function(t) {
      if (is.list(t) && !is.null(names(t))) .o(.o(t$name, t[["<Name>k__BackingField"]]), NULL) else NULL
    }))
    disponible <- o$IsAvailable
    if (is.null(disponible) && !is.null(o$AvailableQuantity)) disponible <- o$AvailableQuantity > 0
    nombre_item <- .o(item$nameComplete, item$name)
    ref <- item$referenceId
    if (is.list(ref)) {
      v <- unlist(lapply(ref, function(x) if (!.vacio(x$Value)) as.character(x$Value)))
      ref <- if (length(v)) paste(v, collapse = ";") else NULL
    }
    partes <- list(prod$productName, if (!identical(nombre_item, prod$productName)) nombre_item,
                   prod$description, if (!is.na(ficha_txt)) ficha_txt)
    list(
      comercio_id = man$comercio_id, ejecucion_id = man$ejecucion_id,
      fecha_hora_consulta = pet$fecha_hora_consulta, url_fuente = pet$url,
      seccion_id = .txt(sec$seccion_id), seccion_nombre = .txt(sec$ruta_nombres),
      product_id_comercio = as.character(.o(prod$productId, "None")), sku_comercio = as.character(.o(item$itemId, "None")),
      ean = .txt(item$ean), referencia = .txt(ref),
      nombre_original = .txt(prod$productName), nombre_item_original = .txt(nombre_item),
      marca_original = .txt(prod$brand), categoria_original = .txt(if (length(prod$categories)) prod$categories[[1]]),
      descripcion_original = .txt(prod$description), ficha_tecnica_original = ficha_txt,
      texto_original = paste(unlist(Filter(Negate(.vacio), partes)), collapse = "\n"),
      url_producto = .txt(url), precio = precio, precio_lista = lista,
      es_promocion = as.integer(!is.na(precio) && !is.na(lista) && lista - precio >= 1),
      texto_promocion = if (length(promos)) paste(promos, collapse = "; ") else NA_character_,
      disponible = if (is.null(disponible)) NA_integer_ else as.integer(isTRUE(as.logical(disponible))),
      vendedor = .txt(vendedor$sellerName))
  })
}

.tabla_vacia <- function() {
  d <- as.data.frame(stats::setNames(replicate(length(COLUMNAS), character(0), simplify = FALSE), COLUMNAS),
                     stringsAsFactors = FALSE)
  for (k in .COLS_NUM) d[[k]] <- numeric(0)
  for (k in .COLS_INT) d[[k]] <- integer(0)
  d
}

# Lee manifest.json y las respuestas guardadas. Devuelve list(datos, meta, secciones):
# `datos` es la tabla estándar (COLUMNAS); `meta`, el registro de la ejecución.
procesar_raw <- function(carpeta) {
  man <- jsonlite::fromJSON(file.path(carpeta, "manifest.json"), simplifyVector = FALSE)
  secs <- stats::setNames(man$secciones, vapply(man$secciones, function(s) as.character(s$seccion_id), ""))
  filas <- list(); ids <- list()
  for (pet in man$peticiones) {
    if (startsWith(pet$tipo, "productos") && pet$status %in% c(200, 206)) {
      datos <- .leer_json_gz(file.path(carpeta, pet$archivo))
      if (!is.null(names(datos))) datos <- datos$products
      sid <- as.character(pet$seccion_id)
      for (prod in datos) {
        ids[[sid]] <- c(ids[[sid]], as.character(.o(prod$productId, "None")))
        filas <- c(filas, parsear_producto(prod, man, pet, .o(secs[[sid]], list())))
      }
    }
  }
  if (length(filas)) {
    d <- as.data.frame(lapply(stats::setNames(COLUMNAS, COLUMNAS), function(k) {
      tipo <- if (k %in% .COLS_NUM) numeric(1) else if (k %in% .COLS_INT) integer(1) else character(1)
      vapply(filas, function(f) f[[k]], tipo)
    }), stringsAsFactors = FALSE)
  } else {
    d <- .tabla_vacia()
  }
  repetidos <- sum(duplicated(d$sku_comercio))
  d <- d[!duplicated(d$sku_comercio), , drop = FALSE]; rownames(d) <- NULL
  notas <- unlist(man$errores); parcial <- FALSE
  for (sid in names(secs)) {
    secs[[sid]]$n_obtenidos <- length(unique(ids[[sid]]))
    if (!is.null(secs[[sid]]$error) || .o(secs[[sid]]$total_reportado, 0) > secs[[sid]]$n_obtenidos) {
      parcial <- TRUE
      notas <- c(notas, sprintf("secci\u00f3n %s: %d de %s productos", sid, secs[[sid]]$n_obtenidos,
                                .o(secs[[sid]]$total_reportado, "None")))
    }
  }
  if (repetidos > 0) notas <- c(notas, sprintf("%d SKU repetidos entre p\u00e1ginas eliminados", repetidos))
  total <- sum(vapply(secs, function(s) as.numeric(.o(s$total_reportado, 0)), 0))
  ruta <- strsplit(normalizePath(carpeta, winslash = "/"), "/", fixed = TRUE)[[1]]
  list(datos = d, secciones = unname(secs), meta = list(
    ejecucion_id = man$ejecucion_id, comercio_id = man$comercio_id, inicio = man$inicio, fin = .txt(man$fin),
    n_registros = nrow(d), n_productos = length(unique(d$product_id_comercio)),
    total_reportado_sitio = if (total > 0) as.integer(total) else NA_integer_,
    estado = if (nrow(d) == 0) "fallida" else if (parcial) "parcial" else "completa",
    mensaje = if (length(notas)) paste(notas, collapse = " | ") else NA_character_,
    carpeta_raw = paste(utils::tail(ruta, 4), collapse = "/")))
}

.extraer <- function(cid, ejecucion_id, modo, raw_dir, progreso = function(...) NULL) {
  if (modo == "en_linea") return(procesar_raw(descargar(cid, ejecucion_id, raw_dir, progreso)))
  manifiestos <- sort(Sys.glob(file.path(raw_dir, cid, "*", ejecucion_id, "manifest.json")))
  if (length(manifiestos) == 0) {
    stop(sprintf("no hay copias crudas de %s para %s en %s", cid, ejecucion_id, raw_dir), call. = FALSE)
  }
  procesar_raw(dirname(manifiestos[1]))
}

# Una función por comercio: misma firma y mismas columnas de salida (COLUMNAS)
extraer_exito <- function(ejecucion_id, modo = "en_linea", raw_dir = RAW_DIR, progreso = function(...) NULL) {
  .extraer("exito", ejecucion_id, modo, raw_dir, progreso)       # exito.com, API de catálogo VTEX
}
extraer_olimpica <- function(ejecucion_id, modo = "en_linea", raw_dir = RAW_DIR, progreso = function(...) NULL) {
  .extraer("olimpica", ejecucion_id, modo, raw_dir, progreso)    # olimpica.com, API de catálogo VTEX
}
extraer_locatel <- function(ejecucion_id, modo = "en_linea", raw_dir = RAW_DIR, progreso = function(...) NULL) {
  .extraer("locatel", ejecucion_id, modo, raw_dir, progreso)     # locatelcolombia.com, API de catálogo VTEX
}
FUNCIONES <- list(exito = extraer_exito, olimpica = extraer_olimpica, locatel = extraer_locatel)

# ---------------------------------------------------------------------------
# Base de datos SQLite (estructura en esquema.sql)
# ---------------------------------------------------------------------------

.ejecutar_script <- function(con, ruta) {
  lineas <- readLines(ruta, encoding = "UTF-8", warn = FALSE)
  lineas <- sub("\\s+--.*$", "", lineas[!grepl("^\\s*--", lineas)])
  for (s in strsplit(paste(lineas, collapse = "\n"), ";", fixed = TRUE)[[1]]) {
    if (nzchar(trimws(s))) DBI::dbExecute(con, s)
  }
}

# Abre la base y garantiza la estructura del Taller 2 (crea lo que falte; no borra datos).
conectar <- function(db_path = DB_PATH, esquema = "esquema.sql") {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  DBI::dbExecute(con, "PRAGMA busy_timeout = 15000")
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  .ejecutar_script(con, esquema)
  agregar <- function(tabla, columna, definicion) {
    if (!(columna %in% DBI::dbListFields(con, tabla))) {
      DBI::dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s %s", tabla, columna, definicion))
    }
  }
  agregar("observaciones", "disponibilidad", "TEXT CHECK (disponibilidad IN ('disponible', 'agotado'))")
  agregar("observaciones", "descartada", "INTEGER NOT NULL DEFAULT 0 CHECK (descartada IN (0, 1))")
  agregar("observaciones", "motivo_descarte", "TEXT")
  agregar("productos", "contenido_verificado", "INTEGER NOT NULL DEFAULT 0 CHECK (contenido_verificado IN (0, 1))")
  agregar("ejecuciones", "n_rechazadas", "INTEGER NOT NULL DEFAULT 0")
  DBI::dbExecute(con, paste("UPDATE observaciones SET disponibilidad = CASE disponible WHEN 1 THEN 'disponible'",
                            "WHEN 0 THEN 'agotado' END WHERE disponibilidad IS NULL AND disponible IS NOT NULL"))
  .ejecutar_script(con, sub("esquema\\.sql$", "vistas.sql", esquema))
  con
}

# Inserta la ejecución de un comercio sin sobrescribir (se llama dentro de una transacción).
# `datos` ya pasó la validación. Devuelve el número de observaciones nuevas, o NA si esa
# ejecución ya estaba cargada.
insertar <- function(con, cid, lote, modo, n_rechazadas = 0L) {
  meta <- lote$meta
  DBI::dbExecute(con, "INSERT OR IGNORE INTO comercios VALUES (?, ?, ?, ?, 'VTEX')",
                 params = unname(c(list(cid), as.list(COMERCIOS[[cid]]))))
  nueva <- DBI::dbExecute(con, paste(
    "INSERT OR IGNORE INTO ejecuciones (ejecucion_id, comercio_id, inicio, fin, modo_carga, n_registros,",
    "n_productos, total_reportado_sitio, estado, mensaje, carpeta_raw, n_rechazadas)",
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"),
    params = list(meta$ejecucion_id, cid, meta$inicio, meta$fin, modo, meta$n_registros, meta$n_productos,
                  meta$total_reportado_sitio, meta$estado, meta$mensaje, meta$carpeta_raw, n_rechazadas))
  if (nueva == 0) return(NA_integer_)                           # esa ejecución ya estaba cargada
  for (s in lote$secciones) {
    campo <- function(k) if (is.null(s[[k]])) NA else s[[k]]
    DBI::dbExecute(con, "INSERT OR IGNORE INTO secciones VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                   params = list(meta$ejecucion_id, cid, as.character(s$seccion_id), campo("nombre"),
                                 campo("ruta_nombres"), campo("filtro"), campo("url"), campo("api"),
                                 campo("total_reportado"), campo("n_obtenidos"), campo("error")))
  }
  d <- lote$datos
  if (nrow(d) == 0) return(0L)
  DBI::dbExecute(con, paste(
    "INSERT INTO anuncios (comercio_id, sku_comercio, product_id_comercio, ean, referencia, nombre_original,",
    "nombre_item_original, marca_original, categoria_original, descripcion_original, ficha_tecnica_original,",
    "texto_original, url_producto, seccion_origen, primera_consulta, ultima_consulta)",
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    "ON CONFLICT (comercio_id, sku_comercio) DO UPDATE SET",
    "primera_consulta = MIN(primera_consulta, excluded.primera_consulta),",
    "ultima_consulta = MAX(ultima_consulta, excluded.ultima_consulta)"),
    params = unname(as.list(d[c("comercio_id", "sku_comercio", "product_id_comercio", "ean", "referencia",
      "nombre_original", "nombre_item_original", "marca_original", "categoria_original", "descripcion_original",
      "ficha_tecnica_original", "texto_original", "url_producto", "seccion_nombre", "fecha_hora_consulta",
      "fecha_hora_consulta")])))
  DBI::dbExecute(con, paste(
    "INSERT OR IGNORE INTO observaciones (ejecucion_id, comercio_id, anuncio_id, sku_comercio, fecha_hora_consulta,",
    "precio, precio_lista, es_promocion, texto_promocion, disponible, disponibilidad, vendedor, url_fuente)",
    "SELECT ?, ?, anuncio_id, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? FROM anuncios WHERE comercio_id = ? AND sku_comercio = ?"),
    params = unname(c(as.list(d[c("ejecucion_id", "comercio_id", "sku_comercio", "fecha_hora_consulta", "precio",
      "precio_lista", "es_promocion", "texto_promocion", "disponible")]),
      list(ifelse(is.na(d$disponible), NA, ifelse(d$disponible == 1, "disponible", "agotado"))),
      as.list(d[c("vendedor", "url_fuente", "comercio_id", "sku_comercio")]))))
}

.registrar_rechazos <- function(con, rechazadas) {
  if (nrow(rechazadas) == 0) return(0L)
  DBI::dbExecute(con, paste(
    "INSERT INTO observaciones_rechazadas (ejecucion_id, comercio_id, sku_comercio, fecha_hora_consulta, precio,",
    "url_fuente, nombre_original, motivo, fecha_registro) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"),
    params = unname(c(as.list(rechazadas[c("ejecucion_id", "comercio_id", "sku_comercio", "fecha_hora_consulta",
      "precio", "url_fuente", "nombre_original", "motivo")]), list(rep(ahora_iso(), nrow(rechazadas))))))
}

# Resumen de una ejecución de un comercio frente a su ejecución anterior (calculado con SQL).
resumen_ejecucion <- function(con, ejecucion_id, cid) {
  q <- function(sql, ...) DBI::dbGetQuery(con, sql, params = list(...))[[1]]
  anterior <- q(paste("SELECT MAX(ejecucion_id) FROM ejecuciones WHERE comercio_id = ? AND ejecucion_id < ?",
                      "AND estado <> 'fallida'"), cid, ejecucion_id)
  nuevos <- q(paste(
    "SELECT COUNT(*) FROM observaciones o WHERE o.ejecucion_id = ? AND o.comercio_id = ? AND NOT EXISTS",
    "(SELECT 1 FROM observaciones p WHERE p.anuncio_id = o.anuncio_id AND p.ejecucion_id < o.ejecucion_id)"),
    ejecucion_id, cid)
  if (is.na(anterior)) return(list(anterior = NA_character_, nuevos = nuevos, cambios = NA_integer_, no_observados = NA_integer_))
  list(anterior = anterior, nuevos = nuevos,
    cambios = q(paste(
      "SELECT COUNT(*) FROM observaciones o JOIN observaciones p ON p.anuncio_id = o.anuncio_id AND p.ejecucion_id = ?",
      "WHERE o.ejecucion_id = ? AND o.comercio_id = ? AND o.precio IS NOT NULL AND p.precio IS NOT NULL",
      "AND o.precio <> p.precio"), anterior, ejecucion_id, cid),
    no_observados = q(paste(
      "SELECT COUNT(*) FROM observaciones p WHERE p.ejecucion_id = ? AND p.comercio_id = ? AND NOT EXISTS",
      "(SELECT 1 FROM observaciones o WHERE o.anuncio_id = p.anuncio_id AND o.ejecucion_id = ?)"),
      anterior, cid, ejecucion_id))
}

# Verificación del origen: cuántas filas leídas de raw/ coinciden (SKU, precio y disponibilidad)
# con las observaciones de esa ejecución guardadas en la base.
.coinciden_con_base <- function(con, ejecucion_id, cid, datos) {
  if (nrow(datos) == 0) return(0L)
  base <- DBI::dbGetQuery(con, paste("SELECT sku_comercio, precio, disponible FROM observaciones",
                                     "WHERE ejecucion_id = ? AND comercio_id = ?"), params = list(ejecucion_id, cid))
  i <- match(datos$sku_comercio, base$sku_comercio)
  igual <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  sum(!is.na(i) & igual(datos$precio, base$precio[i]) & igual(datos$disponible, base$disponible[i]))
}

# Recolección completa con una sola llamada: extrae cada comercio, valida, registra la ejecución,
# inserta en SQLite sin sobrescribir y actualiza la correspondencia de productos (limpieza.R).
# Si un comercio falla continúa con los demás; cada comercio se inserta en su propia transacción.
# modo = "sin_conexion" reprocesa las copias crudas de `ejecucion_id` sin consultar los sitios.
ejecutar_recoleccion <- function(comercios = NULL, modo = "en_linea", db_path = DB_PATH, raw_dir = RAW_DIR,
                                 ejecucion_id = NULL, verbose = TRUE, progreso = function(...) NULL,
                                 esquema = "esquema.sql", ruta_manual = "correspondencias_manuales.csv",
                                 actualizar = TRUE) {
  comercios <- comercios %||% names(COMERCIOS)
  if (modo == "en_linea") {
    ejecucion_id <- ejecucion_id %||% paste0("E", format(Sys.time(), "%Y%m%dT%H%M%S", tz = TZ))
    try(revisar_robots(comercios, raw_dir), silent = TRUE)
  }
  con <- conectar(db_path, esquema); on.exit(DBI::dbDisconnect(con))
  referencia <- comparables_de_referencia(con)
  resumen <- list()
  for (cid in comercios) {
    nombre <- COMERCIOS[[cid]][1]
    progreso(cid, "consultando\u2026")
    if (verbose) message(sprintf("[%s] %s\u2026", ejecucion_id, nombre))
    lote <- tryCatch(FUNCIONES[[cid]](ejecucion_id, modo, raw_dir, progreso), error = function(e) {
      list(datos = .tabla_vacia(), secciones = list(), meta = list(
        ejecucion_id = ejecucion_id, comercio_id = cid, inicio = ahora_iso(), fin = ahora_iso(), n_registros = 0L,
        n_productos = 0L, total_reportado_sitio = NA_integer_, estado = "fallida",
        mensaje = substr(conditionMessage(e), 1, 500), carpeta_raw = NA_character_))
    })
    progreso(cid, "validando\u2026")
    val <- validar_observaciones(lote$datos, referencia[referencia$comercio_id == cid, , drop = FALSE])
    if (nrow(lote$datos) > 0 && length(val$faltan_referencia) > 0) {
      if (lote$meta$estado == "completa") lote$meta$estado <- "parcial"
      lote$meta$mensaje <- paste(c(stats::na.omit(lote$meta$mensaje), sprintf(
        "faltan %d productos comparables de referencia: %s", length(val$faltan_referencia),
        paste(val$faltan_referencia, collapse = "; "))), collapse = " | ")
    }
    if (nrow(val$rechazadas) > 0) {
      lote$meta$mensaje <- paste(c(stats::na.omit(lote$meta$mensaje), sprintf(
        "%d observaciones rechazadas en la validaci\u00f3n", nrow(val$rechazadas))), collapse = " | ")
    }
    lote$datos <- val$validas
    nuevas <- tryCatch(DBI::dbWithTransaction(con, {
      k <- insertar(con, cid, lote, modo, nrow(val$rechazadas))
      if (!is.na(k)) .registrar_rechazos(con, val$rechazadas)
      k
    }), error = function(e) {
      # la transacción se deshizo: la base queda como estaba y la falla se registra aparte
      lote$meta$estado <<- "fallida"
      lote$meta$mensaje <<- substr(paste("error al insertar:", conditionMessage(e)), 1, 500)
      lote$meta$n_registros <<- 0L; lote$meta$n_productos <<- 0L
      lote$datos <<- .tabla_vacia(); lote$secciones <<- list()
      try(DBI::dbWithTransaction(con, insertar(con, cid, lote, modo, 0L)), silent = TRUE)
      0L
    })
    ya_cargada <- is.na(nuevas)
    r <- resumen_ejecucion(con, ejecucion_id, cid)
    if (lote$meta$estado == "fallida") r$cambios <- r$no_observados <- NA_integer_   # sin datos no hay comparación
    coinciden <- .coinciden_con_base(con, ejecucion_id, cid, val$validas)
    resumen[[cid]] <- data.frame(
      ejecucion_id = ejecucion_id, comercio_id = cid, comercio = nombre, modo = modo, estado = lote$meta$estado,
      recolectados = lote$meta$n_registros, validos = nrow(val$validas), rechazados = nrow(val$rechazadas),
      observaciones_nuevas = if (ya_cargada) 0L else nuevas, ya_cargada = ya_cargada,
      productos_nuevos = r$nuevos, cambios_precio = r$cambios, no_observados = r$no_observados,
      coinciden_raw = coinciden,
      total_reportado_sitio = lote$meta$total_reportado_sitio,
      mensaje = lote$meta$mensaje %||% NA_character_, stringsAsFactors = FALSE)
    progreso(cid, sprintf("%s: %d recolectados, %d nuevos", lote$meta$estado, lote$meta$n_registros,
                          resumen[[cid]]$observaciones_nuevas))
    if (verbose) message("    ", paste(names(resumen[[cid]])[-(1:4)], unlist(resumen[[cid]][-(1:4)]), sep = "=", collapse = ", "))
  }
  if (actualizar) {
    progreso("correspondencia", "actualizando productos comparables\u2026")
    corr <- actualizar_correspondencias(con, ruta_manual = ruta_manual)
    elegir_comparables_referencia(con)
    DBI::dbExecute(con, "PRAGMA optimize")
    if (verbose) message(sprintf("Ejecuci\u00f3n de referencia %s: %d presentaciones comparables en %d comercios.",
                                 corr$ejecucion_referencia %||% "-", corr$n_comparables, length(corr$comercios)))
  }
  out <- do.call(rbind, resumen); rownames(out) <- NULL
  out
}

# Ejecuciones guardadas en raw/: data.frame(ejecucion_id, comercio_id, fecha).
ejecuciones_en_raw <- function(raw_dir = RAW_DIR) {
  m <- sort(Sys.glob(file.path(raw_dir, "*", "*", "*", "manifest.json")))
  d <- data.frame(ejecucion_id = basename(dirname(m)), comercio_id = basename(dirname(dirname(dirname(m)))),
                  fecha = basename(dirname(dirname(m))), stringsAsFactors = FALSE)
  d[d$comercio_id %in% names(COMERCIOS), , drop = FALSE]
}

# Modo sin conexión: carga en la base todas las ejecuciones guardadas en raw/ (o las indicadas).
reprocesar_sin_conexion <- function(db_path = DB_PATH, raw_dir = RAW_DIR, ejecuciones = NULL, verbose = TRUE,
                                    progreso = function(...) NULL, ...) {
  d <- ejecuciones_en_raw(raw_dir)
  if (!is.null(ejecuciones)) d <- d[d$ejecucion_id %in% ejecuciones, , drop = FALSE]
  if (nrow(d) == 0) stop(sprintf("no hay copias crudas en %s", raw_dir), call. = FALSE)
  ids <- sort(unique(d$ejecucion_id))
  out <- lapply(ids, function(e) {
    ejecutar_recoleccion(sort(d$comercio_id[d$ejecucion_id == e]), "sin_conexion", db_path, raw_dir, e, verbose,
                         progreso, actualizar = (e == ids[length(ids)]), ...)
  })
  do.call(rbind, out)
}

# ---------------------------------------------------------------------------
# Condiciones de uso
# ---------------------------------------------------------------------------

# ¿Permite robots.txt (User-agent: *) las rutas usadas? En línea guarda copia en raw/<comercio>/robots/.
revisar_robots <- function(comercios = NULL, raw_dir = RAW_DIR, modo = "en_linea") {
  filas <- lapply(comercios %||% names(COMERCIOS), function(cid) {
    base <- COMERCIOS[[cid]][3]; carpeta <- file.path(raw_dir, cid, "robots")
    tryCatch({
      if (modo == "en_linea") {
        r <- .get(paste0(base, "/robots.txt"))
        dir.create(carpeta, recursive = TRUE, showWarnings = FALSE)
        .escribir_gz(httr2::resp_body_raw(r), file.path(carpeta, sprintf("robots_%s.txt.gz", substr(ahora_iso(), 1, 10))))
      }
      copias <- sort(Sys.glob(file.path(carpeta, "robots_*.txt.gz")))
      if (length(copias) == 0) stop("sin copia de robots.txt", call. = FALSE)
      txt <- rawToChar(.leer_gz(copias[length(copias)])); Encoding(txt) <- "UTF-8"
      lineas <- trimws(sub("#.*$", "", strsplit(txt, "\r?\n")[[1]]))
      agente <- ""; prohibidas <- character(0)
      for (l in lineas) {
        if (grepl("^user-agent\\s*:", l, ignore.case = TRUE)) agente <- trimws(sub("^[^:]*:", "", l))
        else if (agente == "*" && grepl("^disallow\\s*:", l, ignore.case = TRUE)) prohibidas <- c(prohibidas, trimws(sub("^[^:]*:", "", l)))
      }
      prohibidas <- prohibidas[nzchar(prohibidas)]
      data.frame(comercio = COMERCIOS[[cid]][1], ruta = c(ARBOL, BUSQUEDA),
                 permitido = !vapply(c(ARBOL, BUSQUEDA), function(p) any(startsWith(p, sub("\\*.*$", "", prohibidas))), TRUE),
                 fecha_revision = substr(basename(copias[length(copias)]), 8, 17), error = NA_character_,
                 stringsAsFactors = FALSE, row.names = NULL)
    }, error = function(e) data.frame(comercio = COMERCIOS[[cid]][1], ruta = NA_character_, permitido = NA,
                                      fecha_revision = NA_character_, error = substr(conditionMessage(e), 1, 200),
                                      stringsAsFactors = FALSE))
  })
  do.call(rbind, filas)
}

if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--robots" %in% args) print(revisar_robots())
  else if ("--sin-conexion" %in% args) print(reprocesar_sin_conexion())
  else print(ejecutar_recoleccion())
}
