# scraper.R — Taller 2 (refactor del módulo de extracción del Taller 1)
#
# Cambios respecto al Taller 1:
#  * library() en vez de pacman (rsconnect detecta los paquetes al desplegar).
#  * chromote (Farmatodo) protegido: si no está, o no hay Chrome, se informa
#    con claridad y se sigue con los demás comercios.
#  * Cada ejecución tiene id y carpeta raw propios: comercio_AAAA-MM-DD_HHMMSS
#    (las dos ejecuciones antiguas conservan comercio_AAAA-MM-DD).
#  * Validación antes de insertar (validacion.R); rechazadas -> tabla `rechazadas`.
#  * Inserción de cada comercio dentro de una transacción.
#  * Resumen por comercio: recolectados, nuevos, cambios de precio, no observados.
#  * Tabla `correcciones` y columnas de auditoría en `ejecuciones`.

library(rvest)
library(httr2)
library(jsonlite)
library(DBI)
library(RSQLite)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)

if (!exists("validar_observaciones", mode = "function")) {
  for (r in c("validacion.R", "../validacion.R")) {
    if (file.exists(r)) { source(r); break }
  }
}
if (!exists("migrar_esquema", mode = "function")) {
  for (r in c("esquema.R", "../esquema.R")) {
    if (file.exists(r)) { source(r); break }
  }
}

USER_AGENT_SCRAPER <- "TallerMineriaDatos (ejercicio academico, no comercial)"

# ---- Constantes de Farmatodo -----------------------------------------

sitio_farmatodo <- "https://www.farmatodo.com.co"
base_farmatodo  <- paste0(sitio_farmatodo,
                          "/categorias/salud-y-medicamentos/botiquin-y-primeros-auxilios")

# Subcategorías a recolectar. Quedan FUERA (no son de la categoría asignada):
# "jeringas-guantes-y-material-hosp" y "aparatos-medicos-y-pastilleros".
slugs_farmatodo <- c(
  "curitas-algodones-adhesivos-y-botiquin",
  "antisepticos",
  "vendas",
  "compresas"
)

# ---- Utilidades -------------------------------------------------------

ahora_iso <- function() {
  x <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  sub("(\\d{2})$", ":\\1", x)
}

# Identificador de una actualización (se comparte entre los comercios):
# también es el nombre de la carpeta en raw/<comercio>/
sello_captura <- function() format(Sys.time(), "%Y-%m-%d_%H%M%S", tz = "America/Bogota")

# ---- Parser: de cada tarjeta de producto a una fila -------------------

parsear_farmatodo <- function(pagina, subcategoria, id_ejecucion, ts) {
  tarjetas <- html_elements(pagina, "div.product-card-handler")
  if (length(tarjetas) == 0) return(tibble())

  map_dfr(tarjetas, function(t) {
    enlace <- html_element(t, "a.product-card-handler__detail-description")
    href_det <- html_attr(enlace, "href")
    href_img <- html_attr(html_element(t, "a.product-card-handler__image-link"), "href")
    href     <- dplyr::coalesce(href_det, href_img)
    sku_card <- str_match(html_attr(t, "data-test"), "product-card-(\\d+)")[, 2]
    sku      <- dplyr::coalesce(str_match(href, "/producto/(\\d+)")[, 2], sku_card)

    bloque <- trimws(html_text2(html_element(t, "app-product-all-price")))
    montos <- as.numeric(gsub("[^0-9]", "",
                              str_extract_all(bloque, "\\$\\s*[0-9.]+")[[1]]))

    tibble(
      comercio               = "Farmatodo",
      sku                    = sku,
      nombre_original        = trimws(html_text(enlace)),
      marca_original         = trimws(html_text(html_element(t, ".product-card-handler__brand-value"))),
      subcategoria_origen    = subcategoria,
      # Sin precio publicado (producto agotado) => NA
      precio                 = if (length(montos) == 0) NA_real_ else min(montos),
      precio_antes           = if (length(montos) >= 2) max(montos) else NA_real_,
      es_promocion           = as.integer(length(montos) >= 2),  # SUPOSICIÓN: verificar con una oferta real
      precio_bloque_original = bloque,
      pum_texto              = trimws(html_text(html_element(t, ".product-card-handler__pum"))),
      vendedor               = str_match(html_text2(t), "Vendido por:\\s*([^\\n]+)")[, 2],
      url                    = if (is.na(href)) NA_character_ else paste0(sitio_farmatodo, href),
      fecha_hora_consulta    = ts,
      id_ejecucion           = id_ejecucion
    )
  })
}

# ---- Una subcategoría completa, con Chrome (read_html_live) -----------

scrape_subcat_live <- function(slug, id_ejecucion = "prueba", max_clics = 60,
                               dir_raw = NULL) {
  url <- paste0(base_farmatodo, "/", slug)
  ts  <- ahora_iso()

  s <- rvest::read_html_live(url)
  on.exit(s$session$close(), add = TRUE)
  Sys.sleep(5)

  contar <- function() {
    s |> html_elements("a.product-card-handler__detail-description") |>
      html_attr("href") |> unique() |> length()
  }

  clic_cargar_mas <- function() {
    r <- s$session$Runtime$evaluate("
      (() => {
        const b = [...document.querySelectorAll('button')]
          .find(x => x.textContent.trim() === 'Cargar más');
        if (!b) return false;
        b.scrollIntoView();
        b.click();
        return true;
      })()
    ")
    isTRUE(r$result$value)
  }

  n_prev <- contar()
  cat("[", slug, "] inicial:", n_prev, "productos\n")

  for (i in seq_len(max_clics)) {
    if (!clic_cargar_mas()) { cat("   ya no hay botón\n"); break }
    Sys.sleep(3)
    n_act <- contar()
    if (n_act == n_prev) {            # confirmar: esperar más y recontar
      Sys.sleep(6)
      n_act <- contar()
      if (n_act == n_prev) { cat("   sin más productos tras esperar\n"); break }
    }
    cat("   clic", i, "->", n_act, "productos\n")
    n_prev <- n_act
  }

  # Copia cruda
  if (!is.null(dir_raw)) {
    dir.create(dir_raw, recursive = TRUE, showWarnings = FALSE)
    html_crudo <- s$session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
    con <- gzfile(file.path(dir_raw, paste0(slug, ".html.gz")), "w")
    writeLines(html_crudo, con, useBytes = TRUE)
    close(con)
    writeLines(ts, file.path(dir_raw, paste0(slug, ".ts.txt")))   # fecha-hora de captura
    cat("   copia cruda guardada en", dir_raw, "\n")
  }

  df <- parsear_farmatodo(s, slug, id_ejecucion, ts)
  if (nrow(df) > 0) df <- distinct(df, sku, nombre_original, .keep_all = TRUE)
  cat("   FILAS FINALES:", nrow(df), "\n")
  df
}

# ---- MODO SIN CONEXIÓN (reprocesar una copia cruda) ---------------------

parsear_desde_raw <- function(archivo, slug, id_ejecucion = "offline") {
  html <- paste(readLines(gzfile(archivo), encoding = "UTF-8", warn = FALSE),
                collapse = "\n")
  pagina <- read_html(charToRaw(html), encoding = "UTF-8")
  archivo_ts <- sub("\\.html\\.gz$", ".ts.txt", archivo)
  ts <- if (file.exists(archivo_ts)) readLines(archivo_ts, warn = FALSE)[1] else NA_character_
  df <- parsear_farmatodo(pagina, slug, id_ejecucion, ts)
  if (nrow(df) > 0) df <- distinct(df, sku, nombre_original, .keep_all = TRUE)
  df
}

# ---- Recolección completa de Farmatodo ---------------------------------
# Un fallo en una subcategoría no frena las demás; los errores quedan en
# attr(resultado, "errores") para mostrarlos en el resumen.

recolectar_farmatodo <- function(id_ejecucion, dir_raw,
                                 modo = c("online", "offline"),
                                 slugs = slugs_farmatodo) {
  modo <- match.arg(modo)
  errores <- character()

  if (modo == "online") {
    if (!requireNamespace("chromote", quietly = TRUE)) {
      stop("Farmatodo necesita un navegador automatizado (paquete chromote), ",
           "que no está disponible en este entorno. Use el modo sin conexión.")
    }
    res <- map(slugs, function(s) {
      tryCatch(
        scrape_subcat_live(s, id_ejecucion = id_ejecucion, dir_raw = dir_raw),
        error = function(e) {
          errores <<- c(errores, paste0(s, ": ", conditionMessage(e)))
          tibble()
        })
    })
  } else {
    res <- map(slugs, function(s) {
      f <- file.path(dir_raw, paste0(s, ".html.gz"))
      if (!file.exists(f)) {
        errores <<- c(errores, paste0("No existe la copia cruda: ", basename(f)))
        return(tibble())
      }
      parsear_desde_raw(f, s, id_ejecucion)
    })
  }

  names(res) <- slugs
  out <- bind_rows(res)
  attr(out, "errores") <- errores
  out
}


# ---- La Rebaja y Locatel (servicio JSON de VTEX) -----------------------

vtex_url <- function(dominio, ruta) {
  paste0("https://", dominio, "/api/catalog_system/pub/products/search/", ruta)
}

descargar_vtex_pagina <- function(dominio, ruta, desde, hasta) {
  resp <- request(vtex_url(dominio, ruta)) |>
    req_url_query(`_from` = desde, `_to` = hasta) |>
    req_user_agent(USER_AGENT_SCRAPER) |>
    req_retry(max_tries = 3) |>
    req_perform()
  cab   <- resp_header(resp, "resources")
  total <- if (is.null(cab)) NA_integer_ else as.integer(sub("^.*/", "", cab))
  list(texto = resp_body_string(resp, encoding = "UTF-8"), total = total)
}

parsear_vtex <- function(productos, comercio, dominio, id_ejecucion, ts) {
  map_dfr(productos, function(p) {
    cats <- unlist(p$categories)

    campo <- function(patron) {
      nm <- names(p)[str_detect(names(p), regex(patron, ignore_case = TRUE))]
      if (length(nm) == 0) return(NA_character_)
      paste(unlist(p[[nm[1]]]), collapse = " | ")
    }
    presentacion     <- campo("^Presentaci[oó]n$")
    contenido_cant   <- dplyr::coalesce(campo("^Cantidadunidadesmedida$"), campo("^PUM - Medida$"))
    contenido_unidad <- dplyr::coalesce(campo("^Unidadmedida$"), campo("^PUM - Unidad de Medida$"))
    pres_texto       <- campo("^Presentacionunidadmedida$")
    unidades_pack    <- campo("^ML_UnidadesPorPack$")
    peso_origen      <- campo("^Peso$")

    map_dfr(p$items, function(it) {
      venta  <- pluck(it, "sellers", 1, .default = list())
      oferta <- pluck(venta, "commertialOffer", .default = list())

      precio_vtex <- suppressWarnings(as.numeric(pluck(oferta, "Price", .default = NA)))
      lista_vtex  <- suppressWarnings(as.numeric(pluck(oferta, "ListPrice", .default = NA)))
      stock       <- suppressWarnings(as.numeric(pluck(oferta, "AvailableQuantity", .default = NA)))

      # Sin precio vigente (agotado) => NA, nunca 0
      precio <- if (!is.na(precio_vtex) && precio_vtex > 0) precio_vtex else NA_real_
      antes  <- if (!is.na(precio) && !is.na(lista_vtex) && lista_vtex > precio) lista_vtex else NA_real_

      tibble(
        comercio              = comercio,
        id_producto           = as.character(pluck(p, "productId", .default = NA)),
        sku                   = as.character(pluck(it, "itemId", .default = NA)),
        ean                   = as.character(pluck(it, "ean", .default = NA)),
        nombre_original       = as.character(pluck(p, "productName", .default = NA)),
        variante_original     = as.character(pluck(it, "name", .default = NA)),
        descripcion_original  = as.character(pluck(p, "description", .default = NA)),
        marca_original        = as.character(pluck(p, "brand", .default = NA)),
        presentacion_original = presentacion,
        presentacion_texto_origen = pres_texto,
        contenido_origen      = contenido_cant,
        contenido_unidad_origen = contenido_unidad,
        unidades_pack_origen  = unidades_pack,
        peso_origen           = peso_origen,
        subcategoria_origen   = if (length(cats) > 0) cats[1] else NA_character_,
        categorias_origen     = if (length(cats) > 0) paste(cats, collapse = " ; ") else NA_character_,
        precio                = precio,
        precio_antes          = antes,
        es_promocion          = as.integer(!is.na(antes)),
        disponible            = as.integer(!is.na(stock) && stock > 0),
        vendedor              = as.character(pluck(venta, "sellerName", .default = NA)),
        url                   = as.character(pluck(p, "link", .default = NA)),
        fecha_hora_consulta   = ts,
        id_ejecucion          = id_ejecucion
      )
    })
  })
}

# Recolección completa de un comercio VTEX.
#   modo "online":  consulta el servicio y guarda cada respuesta en dir_raw
#   modo "offline": reprocesa lo que haya en dir_raw, sin consultar el sitio
# max_paginas limita el número de peticiones por ejecución.
recolectar_vtex <- function(comercio, dominio, ruta, id_ejecucion, dir_raw,
                            modo = c("online", "offline"), paso = 50L,
                            max_paginas = 20L) {
  modo  <- match.arg(modo)
  total <- NA_integer_

  if (modo == "online") {
    dir.create(dir_raw, recursive = TRUE, showWarnings = FALSE)
    unlink(list.files(dir_raw, pattern = "^pag_\\d+\\.json(\\.gz)?$", full.names = TRUE))
    ts <- ahora_iso()
    writeLines(ts, file.path(dir_raw, "ts.txt"))

    desde <- 0L
    n_pag <- 0L
    repeat {
      hasta <- desde + paso - 1L
      r <- descargar_vtex_pagina(dominio, ruta, desde, hasta)
      n_pag <- n_pag + 1L
      total <- r$total
      con_gz <- gzfile(file.path(dir_raw, sprintf("pag_%04d.json.gz", desde)), "w")
      writeLines(r$texto, con_gz, useBytes = TRUE)
      close(con_gz)
      cat("  [", comercio, "] ", desde, "-", hasta, " de ", total, "\n", sep = "")
      if (is.na(total) || nchar(r$texto) <= 2 || hasta + 1L >= total) break
      if (n_pag >= max_paginas) {
        warning("Se alcanzó el máximo de peticiones (", max_paginas, ") en ", comercio)
        break
      }
      desde <- hasta + 1L
      Sys.sleep(1)
    }
    writeLines(as.character(total), file.path(dir_raw, "total_sitio.txt"))
  } else {
    tot_file <- file.path(dir_raw, "total_sitio.txt")
    total <- if (file.exists(tot_file)) suppressWarnings(as.integer(readLines(tot_file, warn = FALSE)[1])) else NA_integer_
    ts_file <- file.path(dir_raw, "ts.txt")
    ts <- if (file.exists(ts_file)) readLines(ts_file, warn = FALSE)[1] else NA_character_
  }

  archivos <- sort(list.files(dir_raw, pattern = "^pag_\\d+\\.json(\\.gz)?$", full.names = TRUE))
  if (length(archivos) == 0) {
    stop("No hay copias crudas en ", dir_raw)
  }
  productos <- unlist(map(archivos, function(f) {
    txt <- paste(readLines(gzfile(f), encoding = "UTF-8", warn = FALSE), collapse = "\n")
    jsonlite::fromJSON(txt, simplifyVector = FALSE)
  }), recursive = FALSE)

  df <- parsear_vtex(productos, comercio, dominio, id_ejecucion, ts)
  attr(df, "total_sitio") <- total
  df
}

# ---- Funciones por comercio --------------------------------------------

columnas_estandar <- c(
  "comercio", "id_producto", "sku", "ean",
  "nombre_original", "variante_original", "descripcion_original",
  "marca_original", "presentacion_original", "presentacion_texto_origen",
  "contenido_origen", "contenido_unidad_origen", "unidades_pack_origen", "peso_origen",
  "subcategoria_origen", "categorias_origen",
  "precio", "precio_antes", "es_promocion", "disponible", "vendedor",
  "precio_texto_origen", "url", "fecha_hora_consulta", "id_ejecucion"
)

estandarizar_columnas <- function(df) {
  total   <- attr(df, "total_sitio")
  errores <- attr(df, "errores")
  if (nrow(df) > 0) {
    if (!"id_producto" %in% names(df)) df$id_producto <- df$sku
    if (!"disponible"  %in% names(df)) df$disponible  <- as.integer(!is.na(df$precio))
    if (!"precio_texto_origen" %in% names(df)) {
      df$precio_texto_origen <- if ("precio_bloque_original" %in% names(df)) df$precio_bloque_original else NA_character_
    }
  }
  for (col in setdiff(columnas_estandar, names(df))) df[[col]] <- rep(NA, nrow(df))
  df <- df[, columnas_estandar]
  numericas <- c("precio", "precio_antes")
  enteras   <- c("es_promocion", "disponible")
  texto     <- setdiff(columnas_estandar, c(numericas, enteras))
  df[texto]     <- lapply(df[texto], as.character)
  df[numericas] <- lapply(df[numericas], as.numeric)
  df[enteras]   <- lapply(df[enteras], as.integer)
  attr(df, "total_sitio") <- total
  attr(df, "errores")     <- errores
  df
}

scrape_farmatodo <- function(id_ejecucion, dir_raw, modo = c("online", "offline")) {
  modo <- match.arg(modo)
  estandarizar_columnas(recolectar_farmatodo(id_ejecucion, dir_raw, modo))
}

scrape_la_rebaja <- function(id_ejecucion, dir_raw, modo = c("online", "offline")) {
  modo <- match.arg(modo)
  estandarizar_columnas(recolectar_vtex("La Rebaja", "www.larebajavirtual.com",
                                        "drogueria/cuidado-de-la-herida", id_ejecucion, dir_raw, modo))
}

scrape_locatel <- function(id_ejecucion, dir_raw, modo = c("online", "offline")) {
  modo <- match.arg(modo)
  estandarizar_columnas(recolectar_vtex("Locatel", "www.locatelcolombia.com",
                                        "drogueria/cuidado-heridas", id_ejecucion, dir_raw, modo))
}

# Catálogo de comercios: carpeta en raw/, prefijo del id de ejecución,
# número de subcategorías esperadas y función de extracción.
COMERCIOS <- list(
  "Farmatodo" = list(carpeta = "farmatodo", prefijo = "farmatodo",
                     n_sub = length(slugs_farmatodo), f = scrape_farmatodo),
  "La Rebaja" = list(carpeta = "la_rebaja", prefijo = "larebaja",
                     n_sub = NA_integer_, f = scrape_la_rebaja),
  "Locatel"   = list(carpeta = "locatel",   prefijo = "locatel",
                     n_sub = NA_integer_, f = scrape_locatel)
)


# ======================================================================
# BASE DE DATOS SQLITE
# ======================================================================

agregar_columna_si_falta <- function(con, tabla, columna, tipo) {
  cols <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", tabla, ")"))$name
  if (!columna %in% cols) {
    DBI::dbExecute(con, paste0("ALTER TABLE ", tabla, " ADD COLUMN ", columna, " ", tipo))
  }
  invisible(TRUE)
}

crear_base <- function(ruta_db) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta_db)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 10000")

  sentencias <- c(
    "CREATE TABLE IF NOT EXISTS comercios (
       id_comercio INTEGER PRIMARY KEY AUTOINCREMENT,
       nombre      TEXT NOT NULL UNIQUE
     )",

    "CREATE TABLE IF NOT EXISTS productos_comparables (
       id_comparable         INTEGER PRIMARY KEY AUTOINCREMENT,
       nombre_comun          TEXT NOT NULL,
       marca_comun           TEXT,
       contenido_valor       REAL,
       contenido_unidad      TEXT,
       regla_correspondencia TEXT
     )",

    "CREATE TABLE IF NOT EXISTS anuncios (
       id_anuncio                INTEGER PRIMARY KEY AUTOINCREMENT,
       id_comercio               INTEGER NOT NULL REFERENCES comercios(id_comercio),
       sku                       TEXT NOT NULL,
       ean                       TEXT,
       nombre_original           TEXT NOT NULL,
       descripcion_original      TEXT,
       marca_original            TEXT,
       presentacion_texto_origen TEXT,
       contenido_origen          TEXT,
       contenido_unidad_origen   TEXT,
       subcategoria_origen       TEXT,
       url                       TEXT,
       contenido_valor           REAL,
       contenido_unidad          TEXT,
       comparable                INTEGER NOT NULL DEFAULT 0,
       id_comparable             INTEGER REFERENCES productos_comparables(id_comparable),
       incluido                  INTEGER NOT NULL DEFAULT 1,
       motivo_exclusion          TEXT,
       nombre_estandar           TEXT,
       marca                     TEXT,
       subcategoria              TEXT,
       UNIQUE (id_comercio, sku)
     )",

    "CREATE TABLE IF NOT EXISTS ejecuciones (
       id_ejecucion      TEXT PRIMARY KEY,
       id_comercio       INTEGER NOT NULL REFERENCES comercios(id_comercio),
       fecha_hora_inicio TEXT NOT NULL,
       registros         INTEGER,
       productos         INTEGER,
       total_sitio       INTEGER,
       estado            TEXT NOT NULL CHECK (estado IN ('completa', 'parcial', 'fallida'))
     )",

    "CREATE TABLE IF NOT EXISTS observaciones (
       id_observacion      INTEGER PRIMARY KEY AUTOINCREMENT,
       id_anuncio          INTEGER NOT NULL REFERENCES anuncios(id_anuncio),
       id_ejecucion        TEXT NOT NULL REFERENCES ejecuciones(id_ejecucion),
       fecha_hora_consulta TEXT NOT NULL,
       precio              REAL,
       precio_antes        REAL,
       es_promocion        INTEGER,
       disponible          INTEGER,
       vendedor            TEXT,
       UNIQUE (id_anuncio, fecha_hora_consulta)
     )",

    # Observaciones que no superaron la validación (no entran a `observaciones`)
    "CREATE TABLE IF NOT EXISTS rechazadas (
       id_rechazo          INTEGER PRIMARY KEY AUTOINCREMENT,
       id_ejecucion        TEXT NOT NULL REFERENCES ejecuciones(id_ejecucion),
       comercio            TEXT,
       sku                 TEXT,
       nombre_original     TEXT,
       url                 TEXT,
       precio              REAL,
       fecha_hora_consulta TEXT,
       motivo              TEXT NOT NULL,
       fecha_registro      TEXT NOT NULL
     )",

    # Correcciones a datos ya almacenados (nunca se borran observaciones)
    "CREATE TABLE IF NOT EXISTS correcciones (
       id_correccion  INTEGER PRIMARY KEY AUTOINCREMENT,
       fecha          TEXT NOT NULL,
       tabla          TEXT NOT NULL,
       registro       TEXT NOT NULL,
       campo          TEXT NOT NULL,
       valor_anterior TEXT,
       valor_nuevo    TEXT,
       motivo         TEXT NOT NULL
     )"
  )
  for (s in sentencias) DBI::dbExecute(con, s)

  # Migración: columnas de auditoría de las ejecuciones (bases del Taller 1)
  agregar_columna_si_falta(con, "ejecuciones", "modo", "TEXT")
  agregar_columna_si_falta(con, "ejecuciones", "mensaje", "TEXT")
  agregar_columna_si_falta(con, "ejecuciones", "rechazadas", "INTEGER")
  agregar_columna_si_falta(con, "ejecuciones", "ruta_raw", "TEXT")
  con
}

registrar_correccion <- function(con, tabla, registro, campo, valor_anterior,
                                 valor_nuevo, motivo, fecha = ahora_iso()) {
  DBI::dbExecute(con, "
    INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo)
    VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(fecha, tabla, as.character(registro), campo,
                  as.character(valor_anterior), as.character(valor_nuevo), motivo))
}

# completa / parcial / fallida (según lo recolectado, antes de validar)
estado_ejecucion <- function(df, total_sitio = NA_integer_, n_subcats_esperadas = NA_integer_) {
  if (nrow(df) == 0) return("fallida")
  if (!is.na(total_sitio) && "id_producto" %in% names(df) &&
      n_distinct(df$id_producto) < total_sitio) return("parcial")
  if (!is.na(n_subcats_esperadas) &&
      n_distinct(df$subcategoria_origen) < n_subcats_esperadas) return("parcial")
  "completa"
}

obtener_id_comercio <- function(con, comercio) {
  DBI::dbExecute(con, "INSERT OR IGNORE INTO comercios (nombre) VALUES (?)",
                 params = list(comercio))
  DBI::dbGetQuery(con, "SELECT id_comercio FROM comercios WHERE nombre = ?",
                  params = list(comercio))$id_comercio
}

registrar_ejecucion <- function(con, id_com, id_ejecucion, ts_inicio, registros,
                                productos, total_sitio, estado, modo, mensaje,
                                rechazadas, ruta_raw) {
  DBI::dbExecute(con, "
    INSERT INTO ejecuciones
      (id_ejecucion, id_comercio, fecha_hora_inicio, registros, productos,
       total_sitio, estado, modo, mensaje, rechazadas, ruta_raw)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (id_ejecucion) DO UPDATE SET
      fecha_hora_inicio = excluded.fecha_hora_inicio,
      registros         = excluded.registros,
      productos         = excluded.productos,
      total_sitio       = excluded.total_sitio,
      estado            = excluded.estado,
      modo              = COALESCE(ejecuciones.modo, excluded.modo),
      mensaje           = excluded.mensaje,
      rechazadas        = excluded.rechazadas,
      ruta_raw          = excluded.ruta_raw",
    params = list(id_ejecucion, id_com, ts_inicio, as.integer(registros),
                  as.integer(productos), as.integer(total_sitio), estado, modo,
                  mensaje, as.integer(rechazadas), ruta_raw))
}

# Escribe las observaciones válidas en una tabla temporal. Se hace ANTES de
# abrir la transacción (dbWriteTable abre la suya).
preparar_carga <- function(con, df, id_com, id_ejecucion) {
  cols <- c("sku", "ean", "nombre_original", "descripcion_original", "marca_original",
            "presentacion_texto_origen", "contenido_origen", "contenido_unidad_origen",
            "subcategoria_origen", "url", "precio", "precio_antes", "es_promocion",
            "disponible", "vendedor", "fecha_hora_consulta")
  for (f in setdiff(cols, names(df))) df[[f]] <- NA
  if (all(is.na(df$disponible))) df$disponible <- as.integer(!is.na(df$precio))
  carga <- as.data.frame(df[, cols])
  carga$id_comercio  <- id_com
  carga$id_ejecucion <- id_ejecucion
  DBI::dbWriteTable(con, "tmp_carga", carga, temporary = TRUE, overwrite = TRUE)
  invisible(nrow(carga))
}

# Dentro de la transacción: pasa de tmp_carga a anuncios y observaciones.
# Devuelve cuántos anuncios y observaciones NUEVOS se insertaron.
insertar_carga <- function(con) {
  n_anuncios <- DBI::dbExecute(con, "
    INSERT OR IGNORE INTO anuncios
      (id_comercio, sku, ean, nombre_original, descripcion_original, marca_original,
       presentacion_texto_origen, contenido_origen, contenido_unidad_origen,
       subcategoria_origen, url)
    SELECT id_comercio, sku, ean, nombre_original, descripcion_original, marca_original,
           presentacion_texto_origen, contenido_origen, contenido_unidad_origen,
           subcategoria_origen, url
    FROM tmp_carga")
  n_obs <- DBI::dbExecute(con, "
    INSERT OR IGNORE INTO observaciones
      (id_anuncio, id_ejecucion, fecha_hora_consulta, precio, precio_antes,
       es_promocion, disponible, vendedor)
    SELECT a.id_anuncio, t.id_ejecucion, t.fecha_hora_consulta, t.precio, t.precio_antes,
           t.es_promocion, t.disponible, t.vendedor
    FROM tmp_carga t
    JOIN anuncios a ON a.id_comercio = t.id_comercio AND a.sku = t.sku")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_carga")
  list(anuncios = n_anuncios, observaciones = n_obs)
}

insertar_rechazadas <- function(con, rech, id_ejecucion) {
  DBI::dbExecute(con, "
    INSERT INTO rechazadas
      (id_ejecucion, comercio, sku, nombre_original, url, precio,
       fecha_hora_consulta, motivo, fecha_registro)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(rep(id_ejecucion, nrow(rech)), rech$comercio, rech$sku,
                  rech$nombre_original, rech$url, rech$precio,
                  rech$fecha_hora_consulta, rech$motivo,
                  rep(ahora_iso(), nrow(rech))))
}

# ----------------------------------------------------------------------
# Persistir UNA ejecución de UN comercio ya recolectada (df en memoria):
# valida, inserta en transacción y devuelve el resumen de una fila.
# ----------------------------------------------------------------------
persistir_ejecucion <- function(con, comercio, id_ejecucion, df,
                                total_sitio = NA_integer_, n_sub = NA_integer_,
                                ts_inicio = NULL, modo = "online",
                                ruta_raw = NA_character_, mensajes = character()) {
  if (is.null(total_sitio)) total_sitio <- NA_integer_
  if (is.null(ts_inicio)) {
    ts_inicio <- if (nrow(df) > 0 && any(!is.na(df$fecha_hora_consulta)))
      min(df$fecha_hora_consulta, na.rm = TRUE) else ahora_iso()
  }

  estado <- estado_ejecucion(df, total_sitio, n_sub)
  if (nrow(df) > 0) {
    val        <- validar_observaciones(df)
    validas    <- val$validas
    rechazadas <- val$rechazadas
    faltan     <- comparables_faltantes(validas, comercio)
    if (nrow(validas) == 0) {
      estado   <- "fallida"
      mensajes <- c(mensajes, "Ninguna observación superó la validación")
    } else if (length(faltan) > 0) {
      mensajes <- c(mensajes, paste0("Comparables ausentes o sin precio: ",
                                     paste(faltan, collapse = ", ")))
      if (estado == "completa") estado <- "parcial"
    }
  } else {
    validas <- df; rechazadas <- tibble(); faltan <- integer(0)
  }
  productos <- if (nrow(df) > 0) n_distinct(df$id_producto) else 0L
  mensaje   <- if (length(mensajes) > 0) paste(mensajes, collapse = " | ") else NA_character_

  id_com <- obtener_id_comercio(con, comercio)
  if (nrow(validas) > 0) preparar_carga(con, validas, id_com, id_ejecucion)

  ins <- tryCatch({
    DBI::dbWithTransaction(con, {
      previo <- DBI::dbGetQuery(con,
        "SELECT fecha_hora_inicio FROM ejecuciones WHERE id_ejecucion = ?",
        params = list(id_ejecucion))
      if (nrow(previo) == 1 && !is.na(previo$fecha_hora_inicio) &&
          previo$fecha_hora_inicio != ts_inicio) {
        registrar_correccion(con, "ejecuciones", id_ejecucion, "fecha_hora_inicio",
          previo$fecha_hora_inicio, ts_inicio,
          "La hora de inicio se había guardado al reprocesar raw/ sin conexión; se restituye la hora de la captura original (ts.txt)")
      }
      registrar_ejecucion(con, id_com, id_ejecucion, ts_inicio, nrow(df), productos,
                          total_sitio, estado, modo, mensaje, nrow(rechazadas), ruta_raw)
      DBI::dbExecute(con, "DELETE FROM rechazadas WHERE id_ejecucion = ?",
                     params = list(id_ejecucion))
      if (nrow(rechazadas) > 0) insertar_rechazadas(con, rechazadas, id_ejecucion)
      if (nrow(validas) > 0) insertar_carga(con) else list(anuncios = 0L, observaciones = 0L)
    })
  }, error = function(e) e)

  if (inherits(ins, "error")) {
    # La transacción se revirtió: la base queda como estaba. Se deja constancia.
    try(DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_carga"), silent = TRUE)
    msg <- paste0("Falló la inserción (no se guardó nada): ", conditionMessage(ins))
    try(registrar_ejecucion(con, id_com, id_ejecucion, ts_inicio, nrow(df), productos,
                            total_sitio, "fallida", modo, msg, nrow(rechazadas), ruta_raw),
        silent = TRUE)
    return(tibble(comercio = comercio, id_ejecucion = id_ejecucion, estado = "fallida",
                  recolectados = nrow(df), rechazados = nrow(rechazadas),
                  productos_nuevos = 0L, observaciones_nuevas = 0L,
                  cambios_precio = 0L, no_observados = 0L, mensaje = msg))
  }

  cambios <- 0L; no_obs <- 0L
  if (estado != "fallida") {
    cambios <- DBI::dbGetQuery(con, "
      WITH previa AS (
        SELECT o.id_observacion,
               (SELECT p.precio FROM observaciones p
                 WHERE p.id_anuncio = o.id_anuncio
                   AND p.fecha_hora_consulta < o.fecha_hora_consulta
                   AND p.precio IS NOT NULL
                 ORDER BY p.fecha_hora_consulta DESC LIMIT 1) AS precio_prev
        FROM observaciones o WHERE o.id_ejecucion = ?)
      SELECT COUNT(*) AS n
      FROM previa JOIN observaciones o USING (id_observacion)
      WHERE previa.precio_prev IS NOT NULL AND o.precio IS NOT NULL
        AND o.precio <> previa.precio_prev",
      params = list(id_ejecucion))$n
    no_obs <- DBI::dbGetQuery(con, "
      WITH previa AS (
        SELECT id_ejecucion FROM ejecuciones
        WHERE id_comercio = ? AND fecha_hora_inicio < ? AND id_ejecucion <> ?
        ORDER BY fecha_hora_inicio DESC LIMIT 1)
      SELECT COUNT(*) AS n FROM observaciones o
      WHERE o.id_ejecucion IN (SELECT id_ejecucion FROM previa)
        AND o.id_anuncio NOT IN
            (SELECT id_anuncio FROM observaciones WHERE id_ejecucion = ?)",
      params = list(id_com, ts_inicio, id_ejecucion, id_ejecucion))$n
  }

  tibble(comercio = comercio, id_ejecucion = id_ejecucion, estado = estado,
         recolectados = nrow(df), rechazados = nrow(rechazadas),
         productos_nuevos = as.integer(ins$anuncios),
         observaciones_nuevas = as.integer(ins$observaciones),
         cambios_precio = as.integer(cambios), no_observados = as.integer(no_obs),
         mensaje = if (is.na(mensaje)) "" else mensaje)
}

# Recolecta (o reprocesa) un comercio y lo persiste. NULL si no hay copia
# cruda para esa captura en modo sin conexión.
procesar_comercio <- function(con, comercio, modo, captura, dir_proyecto = ".") {
  def      <- COMERCIOS[[comercio]]
  id       <- paste0(def$prefijo, "_", captura)
  dir_raw  <- file.path(dir_proyecto, "raw", def$carpeta, captura)
  ruta_raw <- file.path("raw", def$carpeta, captura)
  if (modo == "offline" && !dir.exists(dir_raw)) return(NULL)

  cat("\n== ", comercio, " (", modo, ", ", captura, ") ==\n", sep = "")
  ts_inicio <- if (modo == "online") ahora_iso() else NULL
  res <- tryCatch(list(df = def$f(id, dir_raw, modo), error = NA_character_),
                  error = function(e) list(df = tibble(), error = conditionMessage(e)))
  df <- res$df
  mensajes <- c(if (!is.na(res$error)) res$error, attr(df, "errores"))
  total <- attr(df, "total_sitio")

  out <- persistir_ejecucion(con, comercio, id, df, total_sitio = total,
                             n_sub = def$n_sub, ts_inicio = ts_inicio, modo = modo,
                             ruta_raw = ruta_raw, mensajes = mensajes)
  cat("  [", comercio, "] ", out$estado, ": ", out$recolectados, " recolectados, ",
      out$observaciones_nuevas, " observaciones nuevas, ", out$rechazados,
      " rechazadas\n", sep = "")
  out
}

# Lista las carpetas de captura (una por ejecución) de un comercio
listar_capturas <- function(dir_proyecto, carpeta) {
  d <- file.path(dir_proyecto, "raw", carpeta)
  if (!dir.exists(d)) return(character())
  sort(list.dirs(d, full.names = FALSE, recursive = FALSE))
}

# ----------------------------------------------------------------------
# FUNCIÓN GENERAL (la que llama el botón de la aplicación)
#   modo "online":  una captura nueva de todos los comercios
#   modo "offline": reprocesa TODAS las capturas guardadas en raw/
# Si un comercio falla, continúa con los demás. Devuelve el resumen por comercio.
# ----------------------------------------------------------------------
ejecutar_recoleccion <- function(dir_proyecto = ".",
                                 ruta_db = file.path(dir_proyecto, "comparador_precios.sqlite"),
                                 modo = c("online", "offline"),
                                 comercios = names(COMERCIOS),
                                 captura = NULL, progreso = NULL) {
  modo <- match.arg(modo)
  con  <- crear_base(ruta_db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  capturas <- if (modo == "online") {
    if (is.null(captura)) sello_captura() else captura
  } else if (!is.null(captura)) {
    captura
  } else {
    sort(unique(unlist(lapply(comercios, function(c)
      listar_capturas(dir_proyecto, COMERCIOS[[c]]$carpeta)))))
  }

  resumen <- list()
  for (cap in capturas) {
    for (cm in comercios) {
      if (is.function(progreso)) progreso(cm)
      r <- procesar_comercio(con, cm, modo, cap, dir_proyecto)
      if (!is.null(r)) resumen[[length(resumen) + 1]] <- r
    }
  }
  resumen <- bind_rows(resumen)

  if (nrow(resumen) > 0 && any(resumen$estado != "fallida")) {
    aplicar_exclusiones(con)
    estandarizar_anuncios(con)
    # Re-enlaza los comparables; si una regla ya no encuentra su anuncio, avisa
    # pero conserva el enlace anterior.
    tryCatch(resolver_comparables(con, ruta_csv = NULL),
             error = function(e) warning("Comparables no re-enlazados: ", conditionMessage(e)))
    # Contenido normalizado, índices y vistas (idempotente)
    if (exists("migrar_esquema", mode = "function")) migrar_esquema(con)
  }
  invisible(resumen)
}

# Compatibilidad con el Taller 1 (README anterior)
ejecutar_recoleccion_completa <- function(dir_proyecto,
                                          ruta_db = file.path(dir_proyecto, "comparador_precios.sqlite"),
                                          modo = c("online", "offline"), fecha = NULL) {
  ejecutar_recoleccion(dir_proyecto, ruta_db, match.arg(modo), captura = fecha)
}


# ======================================================================
# DELIMITACIÓN DE LA CATEGORÍA Y CORRESPONDENCIA DE PRODUCTOS
# (sin cambios respecto al Taller 1)
# ======================================================================

reglas_exclusion <- tibble::tribble(
  ~motivo,                                                  ~campo,                ~patron,
  "Ostomías (bolsas y accesorios), fuera de la categoría",  "subcategoria_origen", "ostomi",
  "Bolsas de drenaje o de ostomía",                         "nombre_original",     "bolsa.*(drenaje|orina|colostom|ileostom|ostom)|drenaje",
  "Guantes, tapabocas y mascarillas (protección personal)", "nombre_original",     "guante|tapaboca|mascarilla|cubrebocas",
  "Jeringas y agujas",                                      "nombre_original",     "jeringa|aguja",
  "Instrumentos de medición o diagnóstico",                 "nombre_original",     "pulsiox|term[oó]metro|tensi[oó]metro|nebuliz|glucom",
  "Removedores de adhesivo y limpiadores de piel",          "nombre_original",     "removedor|removed",
  "Copitos e hisopos (cuidado personal)",                   "nombre_original",     "copito|hisopo",
  "Antisépticos de manos (no son para heridas)",            "nombre_original",     "antibacterial|glicerinad|desinfectante de manos"
)

aplicar_exclusiones <- function(con) {
  a <- DBI::dbGetQuery(con, "SELECT id_anuncio, nombre_original, subcategoria_origen FROM anuncios")
  a$motivo <- NA_character_
  for (i in seq_len(nrow(reglas_exclusion))) {
    r   <- reglas_exclusion[i, ]
    txt <- dplyr::coalesce(a[[r$campo]], "")
    hit <- str_detect(txt, regex(r$patron, ignore_case = TRUE)) & is.na(a$motivo)
    a$motivo[hit] <- r$motivo
  }
  DBI::dbExecute(con, "UPDATE anuncios SET incluido = 1, motivo_exclusion = NULL")
  excl <- a[!is.na(a$motivo), ]
  if (nrow(excl) > 0) {
    DBI::dbExecute(con, "UPDATE anuncios SET incluido = 0, motivo_exclusion = ? WHERE id_anuncio = ?",
                   params = list(excl$motivo, excl$id_anuncio))
  }
  invisible(nrow(excl))
}

cargar_comparables <- function(con, ruta_csv) {
  if (!file.exists(ruta_csv)) stop("Falta el archivo de correspondencia: ", ruta_csv)
  cmp <- utils::read.csv(ruta_csv, stringsAsFactors = FALSE, encoding = "UTF-8",
                         colClasses = c(sku = "character", ean = "character"),
                         na.strings = c("", "NA"))
  necesarias <- c("id_comparable", "nombre_comun", "marca_comun", "contenido_valor",
                  "contenido_unidad", "comercio", "sku", "ean", "regla")
  stopifnot(all(necesarias %in% names(cmp)))
  cargar_comparables_df(con, cmp)
}

cargar_comparables_df <- function(con, cmp) {
  DBI::dbExecute(con, "UPDATE anuncios SET id_comparable = NULL, comparable = 0,
                       contenido_valor = NULL, contenido_unidad = NULL")
  DBI::dbExecute(con, "DELETE FROM productos_comparables")

  prod <- cmp |>
    group_by(id_comparable) |>
    summarise(nombre_comun = first(nombre_comun), marca_comun = first(marca_comun),
              contenido_valor = first(contenido_valor), contenido_unidad = first(contenido_unidad),
              regla = paste(unique(regla), collapse = " | "), .groups = "drop")
  for (i in seq_len(nrow(prod))) {
    DBI::dbExecute(con, "INSERT INTO productos_comparables
        (id_comparable, nombre_comun, marca_comun, contenido_valor, contenido_unidad, regla_correspondencia)
        VALUES (?, ?, ?, ?, ?, ?)", params = unname(as.list(prod[i, ])))
  }

  for (i in seq_len(nrow(cmp))) {
    por_sku <- !is.na(cmp$sku[i]) && nzchar(cmp$sku[i])
    campo   <- if (por_sku) "sku" else "ean"
    valor   <- if (por_sku) cmp$sku[i] else cmp$ean[i]
    n <- DBI::dbExecute(con, paste0("UPDATE anuncios
        SET id_comparable = ?, comparable = 1, contenido_valor = ?, contenido_unidad = ?
        WHERE ", campo, " = ? AND id_comercio = (SELECT id_comercio FROM comercios WHERE nombre = ?)"),
        params = list(cmp$id_comparable[i], cmp$contenido_valor[i], cmp$contenido_unidad[i],
                      valor, cmp$comercio[i]))
    if (n == 0) warning("No se encontró ", toupper(campo), " ", valor, " en ", cmp$comercio[i])
    if (n > 1)  warning(toupper(campo), " ", valor, " en ", cmp$comercio[i],
                        " corresponde a ", n, " anuncios; debe ser uno solo")
  }

  cobertura <- DBI::dbGetQuery(con, "
    SELECT p.id_comparable, p.nombre_comun, COUNT(DISTINCT a.id_comercio) AS comercios
    FROM productos_comparables p
    LEFT JOIN anuncios a ON a.id_comparable = p.id_comparable
    GROUP BY p.id_comparable, p.nombre_comun")
  if (any(cobertura$comercios < 3)) warning("Hay comparables que no están en los 3 comercios")
  invisible(cobertura)
}

especificacion_comparables <- tibble::tribble(
  ~id_comparable, ~nombre_comun,                                                  ~marca_comun, ~contenido_valor, ~contenido_unidad, ~ean,            ~patron_farmatodo,
  1, "Alcohol antiséptico MK botella 700 mL",                                     "MK",         700,              "mL",              "7702057075101", "alcohol mk.*700 ?ml",
  2, "Micropore Nexcare (3M) color piel 12 mm x 5 m",                             "Nexcare",    5,                "m",               "7702098400184", "micropore.*nexcare.*beige.*12 ?mm",
  3, "Micropore Nexcare (3M) color piel 24 mm x 5 m",                             "Nexcare",    5,                "m",               "7702098400191", "micropore.*nexcare.*beige.*24 ?mm",
  4, "Curas Cure Band Standard caja x 10",                                        "CureBand",   10,               "unidad",          "7702136646628", "cura cure band standard.*x 10 und",
  5, "Microporo Cure Band color piel 5 cm x 4,5 m (2 x 5 yd)",                    "CureBand",   4.5,              "m",               "7702136648325", "microporo cure band.*5 ?cm",
  6, "Cinta de fijación Fixo Roll Cure Band 10 cm x 2 m",                         "CureBand",   2,                "m",               "7702136663366", "fixo roll.*10 ?cm",
  7, "Gasa estéril no tejida Alfa Safe 7,5 x 7,5 cm (3 x 3 pulg) caja x 12 sobres","Alfa Safe",  12,               "sobre",           "7707228362288", "gasa alfa.*no tejida.*3x3",
  8, "Cinta Transpore Nexcare (3M) transparente 24 mm x 5 m",                     "Nexcare",    5,                "m",               "7702098400153", "nexcare transpore.*24"
)

resolver_comparables <- function(con, especificacion = especificacion_comparables, ruta_csv = NULL) {
  anuncios <- DBI::dbGetQuery(con, "
    SELECT c.nombre AS comercio, a.sku, a.ean, a.nombre_original
    FROM anuncios a JOIN comercios c ON c.id_comercio = a.id_comercio")

  unico <- function(df, e, comercio, criterio) {
    if (nrow(df) != 1) {
      stop("Regla del comparable ", e$id_comparable, " (", e$nombre_comun, ") en ", comercio,
           ": se esperaba 1 anuncio y hay ", nrow(df), " con ", criterio,
           if (nrow(df) > 0) paste0("\n  ", df$sku, " | ", df$nombre_original, collapse = "") else "")
    }
    df
  }

  filas <- list()
  for (i in seq_len(nrow(especificacion))) {
    e <- especificacion[i, ]
    for (cm in c("La Rebaja", "Locatel")) {
      r <- anuncios[anuncios$comercio == cm & !is.na(anuncios$ean) & anuncios$ean == e$ean, ]
      r <- unico(r, e, cm, paste0("EAN ", e$ean))
      filas[[length(filas) + 1]] <- data.frame(
        e[, c("id_comparable", "nombre_comun", "marca_comun", "contenido_valor", "contenido_unidad")],
        comercio = cm, sku = r$sku, ean = r$ean,
        regla = paste0("EAN ", e$ean, " idéntico en La Rebaja y Locatel"),
        stringsAsFactors = FALSE)
    }
    f <- anuncios[anuncios$comercio == "Farmatodo" &
                  str_detect(anuncios$nombre_original, regex(e$patron_farmatodo, ignore_case = TRUE)), ]
    f <- unico(f, e, "Farmatodo", paste0("el patrón /", e$patron_farmatodo, "/"))
    filas[[length(filas) + 1]] <- data.frame(
      e[, c("id_comparable", "nombre_comun", "marca_comun", "contenido_valor", "contenido_unidad")],
      comercio = "Farmatodo", sku = f$sku, ean = NA_character_,
      regla = paste0("Farmatodo: el nombre coincide con /", e$patron_farmatodo, "/ (marca, producto y medida)"),
      stringsAsFactors = FALSE)
  }
  cmp <- do.call(rbind, filas)

  if (!is.null(ruta_csv)) utils::write.csv(cmp, ruta_csv, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(cargar_comparables_df(con, cmp))
}


# ======================================================================
# ESTANDARIZACIÓN: campos propios; el texto original NO se modifica
# (sin cambios respecto al Taller 1)
# ======================================================================

normalizar_texto <- function(x) {
  x |> stringi::stri_trans_general("Latin-ASCII") |> str_to_lower() |>
    str_replace_all("[^a-z0-9%.,/+ ]", " ") |> str_squish()
}

estandarizar_marca <- function(x) {
  m <- x |> stringi::stri_trans_general("Latin-ASCII") |> str_to_upper() |> str_remove_all("[^A-Z0-9]")
  ifelse(is.na(m) | m == "", NA_character_, m)
}

reglas_subcategoria <- tibble::tribble(
  ~subcategoria,                         ~patron,
  "Gasas y compresas",                   "\\bgasas?\\b|compresas?",
  "Vendas",                              "\\bvendas?\\b|\\bcoban\\b",
  "Esparadrapos y cintas",               "esparadrapo|micropor|transpore|\\bcinta|fixomull|fixo ?roll|fixosafe|leukopor|tela adhesiva",
  "Curitas y apósitos",                  "\\bcuras?\\b|curitas?|venditas?|aposito|tegaderm|parche|hidrocoloide|duoderm|aquacel|cure ?band",
  "Antisépticos y limpieza de heridas",  "alcohol|isodine|yodopovidona|povidona|agua oxigenada|peroxido|clorhexidina|merthiolate|mertiolate|microdacyn|antisept|desinfect|suero fisiologico",
  "Algodón",                             "algodon|copito|hisopo",
  "Botiquines y kits",                   "botiquin|\\bkit\\b",
  "Cicatrizantes, geles y cremas",       "cicatri|\\bgel\\b|crema|pomada|spray|solucion"
)
subcategoria_por_defecto <- "Otros productos de curación"

estandarizar_anuncios <- function(con) {
  a <- DBI::dbGetQuery(con, "SELECT id_anuncio, nombre_original, marca_original FROM anuncios")
  if (nrow(a) == 0) return(invisible(0L))
  nombre_norm <- normalizar_texto(a$nombre_original)
  sub <- rep(NA_character_, nrow(a))
  for (i in seq_len(nrow(reglas_subcategoria))) {
    hit <- which(is.na(sub) & str_detect(nombre_norm, regex(reglas_subcategoria$patron[i], ignore_case = TRUE)))
    sub[hit] <- reglas_subcategoria$subcategoria[i]
  }
  sub[is.na(sub)] <- subcategoria_por_defecto
  DBI::dbExecute(con, "UPDATE anuncios SET nombre_estandar = ?, marca = ?, subcategoria = ?
                       WHERE id_anuncio = ?",
                 params = list(nombre_norm, estandarizar_marca(a$marca_original), sub, a$id_anuncio))
  invisible(nrow(a))
}
