# =============================================================================
# scraper.R  -  Taller 2 Minería de Datos: Comparador de precios infantiles
# -----------------------------------------------------------------------------
# SOLO DEFINICIONES (constantes y funciones). Al hacer source("scraper.R") no se
# ejecuta nada: ni descargas, ni lectura de argumentos, ni escritura en disco.
# Todo se invoca desde otro archivo (la app Shiny):
#     source("scraper.R"); res <- ejecutar_scraper(modo = "online")
#
# Comercios: Farmatodo, Jumbo, Éxito (una función de scraping por comercio).
# Requisitos: R >= 4.4, Chrome/Chromium (chromote renderiza el JS de las
# tiendas) y los paquetes de PAQUETES_REQUERIDOS.
# Uso académico: respetar términos de uso/robots.txt y mantener las pausas.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(tibble)
  library(purrr)
})

# ----------------------------------------------------------------------------
# 0. CONFIGURACIÓN
# ----------------------------------------------------------------------------
TZ_CO <- "America/Bogota"
PAUSA_SEG <- c(3, 6)
UA <- paste("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

TERMINOS_BUSQUEDA <- c("jabon bebe", "champu bebe", "locion bebe",
                       "aceite bebe", "crema hidratante bebe", "colonia bebe",
                       "johnson baby", "mustela", "jabon liquido bebe",
                       "shampoo bebe")

COLUMNAS <- c("comercio", "producto", "texto_original", "marca", "subcategoria",
              "contenido_valor", "contenido_unidad", "precio_cop", "precio_antes",
              "en_promocion", "sku", "disponibilidad", "url", "fecha_consulta",
              "id_ejecucion", "comparable", "id_comun")

PAQUETES_REQUERIDOS <- c("rvest", "xml2", "DBI", "RSQLite", "pointblank",
                         "jsonlite", "stringi")

`%||%` <- function(a, b) if (is.null(a)) b else a

verificar_paquetes <- function(modo = "online") {
  req <- c(PAQUETES_REQUERIDOS, if (modo == "online") "chromote")
  falta <- req[!vapply(req, requireNamespace, logical(1), quietly = TRUE)]
  if (length(falta))
    stop("Faltan paquetes: install.packages(c(",
         paste0('"', falta, '"', collapse = ", "), "))", call. = FALSE)
}

# ----------------------------------------------------------------------------
# 1. UTILIDADES
# ----------------------------------------------------------------------------
ahora_co <- function() Sys.time()

iso_co <- function(t) {
  sub("([+-]\\d{2})(\\d{2})$", "\\1:\\2",
      format(t, "%Y-%m-%dT%H:%M:%S%z", tz = TZ_CO))
}

norm <- function(x) stringi::stri_trans_general(str_to_lower(x), "Latin-ASCII")

slugify <- function(x) str_replace_all(norm(x), "[^a-z0-9]+", "-") |> str_remove("-+$")

# "$ 60.500" -> 60500 ; "$ 313,50" -> 313.5 ; "$4.450" -> 4450
parse_cop <- function(x) {
  x <- str_extract(as.character(x), "\\d[\\d.,]*")
  x <- if_else(str_detect(x, ","),
               str_replace(str_remove_all(x, "\\."), ",", "."),
               str_remove_all(x, "\\."))
  suppressWarnings(as.numeric(x))
}

precio_con_signo <- function(textos) {
  m <- str_extract(textos, "\\$\\s*\\d[\\d.,]*")
  m <- m[!is.na(m)]
  if (length(m) == 0) NA_real_ else parse_cop(m[1])
}

abs_url <- function(href, base) {
  if_else(is.na(href), NA_character_,
          if_else(str_detect(href, "^https?://"), href, paste0(base, href)))
}

.txt <- function(nodo, css = NULL, xpath = NULL) {
  el <- if (!is.null(xpath)) rvest::html_element(nodo, xpath = xpath)
  else rvest::html_element(nodo, css)
  na_if(str_squish(rvest::html_text(el)), "")
}
.attr <- function(nodo, attr, css = NULL, xpath = NULL) {
  el <- if (!is.null(xpath)) rvest::html_element(nodo, xpath = xpath)
  else rvest::html_element(nodo, css)
  rvest::html_attr(el, attr)
}

reintentar <- function(f, intentos = 2, espera = 3) {
  for (i in seq_len(intentos)) {
    r <- tryCatch(f(), error = function(e) e)
    if (!inherits(r, "error")) return(r)
    if (grepl("Bloqueo detectado", conditionMessage(r))) break
    if (i < intentos) Sys.sleep(espera)
  }
  stop(r)
}

# ----------------------------------------------------------------------------
# 2. NORMALIZACIÓN: presentación, subcategoría, marca
# ----------------------------------------------------------------------------
extraer_presentacion <- function(nombre) {
  n <- norm(nombre)
  m1 <- str_match(n, "(\\d+(?:[.,]\\d+)?)\\s*(ml|cc|cm3|litros?|lts?|l|kg|kilos?|gramos?|grs?|g)\\b")
  m2 <- str_match(n, "(\\d+(?:[.,]\\d+)?)\\s*(unidades|unidad|unds?|und|uds?|un)\\b")
  usar1 <- !is.na(m1[, 1])
  v <- if_else(usar1, m1[, 2], m2[, 2])
  u <- if_else(usar1, m1[, 3], m2[, 3])
  v <- if_else(str_detect(v, "^\\d{1,3}\\.\\d{3}$"), str_remove(v, "\\."), v)
  v <- suppressWarnings(as.numeric(str_replace(v, ",", ".")))
  unidad <- case_when(
    u %in% c("ml", "cc", "cm3")                  ~ "ml",
    str_detect(u, "^(l|lt|lts|litro|litros)$")   ~ "ml",
    u %in% c("g", "gr", "grs", "gramo", "gramos") ~ "g",
    u %in% c("kg", "kilo", "kilos")              ~ "g",
    !is.na(u)                                    ~ "unidad",
    TRUE                                         ~ NA_character_)
  mult <- case_when(str_detect(u, "^(l|lt|lts|litro|litros|kg|kilo|kilos)$") ~ 1000, TRUE ~ 1)
  tibble(valor = v * mult, unidad = unidad)
}

RX_EXCLUIR <- paste0("panal|panalitis|pomada|unguento|protector solar|proteccion solar|",
                     "bloqueador|\\bfps\\b|\\bspf\\b|bucal|dental|cepillo|\\bkit\\b|\\bset\\b|",
                     "combo|estuche|\\bpack\\b|peine|peinado|gel para peinar|crema para peinar|",
                     "crema de peinar|spray para peinar|toallita|biberon|detergente|",
                     "lavado|limpieza|\\bropa\\b")
RX_BEBE <- paste0("bebe|baby|infantil|nino|nina|recien nacido|kids|pediatric|",
                  "johnson|mustela|babaria|huggies|pequenin|bubchen")
RX_SUBCAT <- c("Colonia"          = "colonia|fragancia|perfume|eau de",
               "Champú"           = "champu|shampoo|shampu",
               "Jabón"            = "jabon|syndet|bano liquido|gel de bano|gel de ducha|barra limpiadora",
               "Aceite"           = "aceite",
               "Loción"           = "locion|emulsion",
               "Crema hidratante" = "crema|hidratante|humectante|leche corporal")

clasificar_subcategoria <- function(nombre, requerir_bebe = TRUE) {
  n <- norm(nombre)
  if (length(n) == 0) return(character(0))
  pos <- do.call(cbind, lapply(RX_SUBCAT, function(rx) str_locate(n, rx)[, "start"]))
  idx <- apply(matrix(pos, nrow = length(n)), 1,
               function(r) if (all(is.na(r))) NA_integer_ else which.min(r))
  sub <- names(RX_SUBCAT)[idx]
  sub[str_detect(n, RX_EXCLUIR) %in% TRUE] <- NA_character_
  if (requerir_bebe) sub[!(str_detect(n, RX_BEBE) %in% TRUE)] <- NA_character_
  sub
}

MARCAS_CONOCIDAS <- c(johnson = "Johnson's", mustela = "Mustela", eucerin = "Eucerin",
                      cetaphil = "Cetaphil", sebamed = "Sebamed", babaria = "Babaria",
                      aveeno = "Aveeno", nivea = "Nivea", dove = "Dove", huggies = "Huggies",
                      pequenin = "Pequeñín", bubchen = "Bübchen", avent = "Avent")

completar_marca <- function(marca, producto) {
  n <- norm(producto)
  desde_nombre <- map_chr(n, function(x) {
    hit <- names(MARCAS_CONOCIDAS)[map_lgl(names(MARCAS_CONOCIDAS), ~ str_detect(x, fixed(.x)))]
    if (length(hit)) MARCAS_CONOCIDAS[[hit[1]]] else NA_character_
  })
  coalesce(na_if(marca, ""), desde_nombre)
}

plantilla_crudo <- function() {
  tibble(producto = character(), texto_original = character(), marca = character(),
         precio_cop = numeric(), precio_antes = numeric(),
         en_promocion = integer(), sku = character(),
         disponibilidad = character(), url = character())
}

# Evidencia de agotamiento en el texto de la tarjeta; si hay precio y no hay
# evidencia contraria se asume "disponible" (lo decide el sitio, no el scraper).
detectar_disponibilidad <- function(texto, precio_cop) {
  agotado <- str_detect(texto, regex("agotado|sin stock|sold ?out|no disponible",
                                     ignore_case = TRUE)) %in% TRUE
  ifelse(agotado, "agotado",
         ifelse(!is.na(precio_cop) & precio_cop > 0, "disponible", NA_character_))
}

# Texto original del anuncio: nombre + marca + extras del sitio, sin limpiar.
# Vectorizado: todos los argumentos deben tener el mismo largo (una fila por
# tarjeta de producto).
armar_texto_original <- function(..., sep = " | ") {
  partes <- list(...)
  partes <- Filter(function(x) !is.null(x) && length(x) > 0, partes)
  if (!length(partes)) return(character(0))
  n <- max(vapply(partes, length, integer(1)))
  out <- rep(NA_character_, n)
  for (p in partes) {
    p <- rep_len(str_squish(as.character(p)), n)
    p[is.na(p) | !nzchar(p)] <- NA_character_
    out <- ifelse(is.na(out), p,
                  ifelse(is.na(p), out, paste(out, p, sep = sep)))
  }
  out
}

normalizar_observaciones <- function(crudo, comercio, fecha_iso, id_ejecucion,
                                     requerir_bebe = TRUE) {
  vacio <- as_tibble(setNames(replicate(length(COLUMNAS), logical(0), simplify = FALSE), COLUMNAS))
  if (nrow(crudo) == 0) return(list(datos = vacio, fuera_categoria = 0L))
  pres <- extraer_presentacion(crudo$producto)
  out <- crudo |>
    mutate(comercio = comercio,
           texto_original = coalesce(texto_original, producto),
           marca = completar_marca(marca, producto),
           subcategoria = clasificar_subcategoria(producto, requerir_bebe),
           contenido_valor = pres$valor,
           contenido_unidad = pres$unidad,
           precio_antes = coalesce(precio_antes, NA_real_),
           en_promocion = as.integer(en_promocion),
           sku = coalesce(sku, NA_character_),
           disponibilidad = coalesce(disponibilidad, NA_character_),
           fecha_consulta = fecha_iso,
           id_ejecucion = id_ejecucion,
           comparable = 0L,
           id_comun = NA_character_)
  list(datos = out |> filter(!is.na(subcategoria)) |> select(all_of(COLUMNAS)),
       fuera_categoria = sum(is.na(out$subcategoria)))
}

# ----------------------------------------------------------------------------
# 3. DESCARGA (chromote) + COPIAS CRUDAS (raw/<comercio>/<fecha>/)
# ----------------------------------------------------------------------------
.chrome <- new.env()
sesion_chrome <- function() {
  if (is.null(.chrome$b)) {
    .chrome$b <- chromote::ChromoteSession$new()
    try(.chrome$b$Network$setUserAgentOverride(userAgent = UA), silent = TRUE)
  }
  .chrome$b
}
cerrar_chrome <- function() {
  if (!is.null(.chrome$b)) try(.chrome$b$close(), silent = TRUE)
  .chrome$b <- NULL
  invisible(NULL)
}

fetch_html_renderizado <- function(url, selector_espera, scrolls = 6,
                                   timeout = 30, pausa = 1.5) {
  b <- sesion_chrome()
  b$Page$navigate(url, wait_ = FALSE)
  try(b$Page$loadEventFired(wait_ = TRUE, timeout_ = timeout), silent = TRUE)
  
  sel_js <- jsonlite::toJSON(selector_espera, auto_unbox = TRUE)
  contar <- function() {
    r <- b$Runtime$evaluate(sprintf("document.querySelectorAll(%s).length", sel_js))
    as.integer(r$result$value %||% 0L)
  }
  t0 <- Sys.time()
  while (contar() == 0L && as.numeric(difftime(Sys.time(), t0, units = "secs")) < timeout)
    Sys.sleep(0.5)
  
  clic_ver_mas <- function() {
    r <- b$Runtime$evaluate("(function(){
      var bs = Array.from(document.querySelectorAll('button, a, div[role=button]'));
      var x = bs.find(function(e){ return /(ver|cargar|mostrar)\\s+m[aá]s/i.test(e.innerText || '') && e.offsetParent !== null; });
      if (x) { x.scrollIntoView(); x.click(); return true; } return false; })()")
    isTRUE(r$result$value)
  }
  
  previo <- contar(); sin_cambio <- 0L
  for (i in seq_len(scrolls)) {
    b$Runtime$evaluate("window.scrollTo(0, document.body.scrollHeight)")
    Sys.sleep(pausa)
    clico <- clic_ver_mas()
    if (clico) Sys.sleep(pausa * 1.5)
    actual <- contar()
    sin_cambio <- if (actual == previo && !clico) sin_cambio + 1L else 0L
    if (sin_cambio >= 3L) break
    previo <- actual
  }
  b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
}

guardar_raw <- function(html, raw_dir, key, id_ejecucion, t_consulta, slug) {
  dir <- file.path(raw_dir, key, format(t_consulta, "%Y-%m-%d", tz = TZ_CO))
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  ruta <- file.path(dir, sprintf("%s__%s.html", id_ejecucion, slug))
  writeLines(html, ruta, useBytes = TRUE)
  ruta
}

listar_raw_ultima <- function(raw_dir, key, raw_fecha = NULL) {
  archivos <- list.files(file.path(raw_dir, key), pattern = "\\.html$",
                         recursive = TRUE, full.names = TRUE)
  if (!is.null(raw_fecha)) archivos <- archivos[basename(dirname(archivos)) == raw_fecha]
  if (length(archivos) == 0)
    return(tibble(path = character(), id_origen = character(), t_origen = as.POSIXct(character())))
  df <- tibble(path = archivos,
               id_origen = str_extract(basename(archivos), "^ejec_\\d{8}T\\d{6}"))
  df <- df |> filter(!is.na(id_origen)) |> filter(id_origen == max(id_origen))
  df$t_origen <- rep(as.POSIXct(strptime(sub("ejec_", "", df$id_origen[1]),
                                         "%Y%m%dT%H%M%S", tz = TZ_CO)), nrow(df))
  df
}

detectar_bloqueo <- function(html) {
  str_extract(html, regex("captcha|access denied|just a moment|attention required|are you a human|request blocked|forbidden",
                          ignore_case = TRUE))
}

# ----------------------------------------------------------------------------
# 4. PARSERS (HTML -> tabla cruda). Firma común: parser(doc, base)
# ----------------------------------------------------------------------------
# --- Farmatodo: <app-product-card-handler> ---------------------------------
parsear_farmatodo <- function(doc, base) {
  tarjetas <- as.list(rvest::html_elements(doc, "app-product-card-handler"))
  if (length(tarjetas) == 0) return(plantilla_crudo())
  precio_normal <- map_dbl(tarjetas, ~ parse_cop(.txt(.x, css = "span.product-all-price__normal")))
  precio_oferta <- map_dbl(tarjetas, function(t) {
    els <- rvest::html_elements(t, xpath =
                                  ".//*[contains(@class,'product-all-price__offer') and not(contains(@class,'offer-and-normal'))]")
    precio_con_signo(rvest::html_text(els))
  })
  precio_cop <- coalesce(precio_oferta, precio_normal)
  precio_antes <- if_else(!is.na(precio_oferta) & !is.na(precio_normal) &
                            precio_normal > precio_oferta, precio_normal, NA_real_)
  nombres  <- map_chr(tarjetas, ~ .txt(.x, css = "a.product-card-handler__detail-description"))
  marcas   <- map_chr(tarjetas, ~ .txt(.x, css = "p.product-card-handler__brand-value"))
  hrefs    <- map_chr(tarjetas, ~ .attr(.x, "href", css = "a.product-card-handler__detail-description"))
  pum      <- map_chr(tarjetas, ~ .txt(.x, css = "div.product-card-handler__pum"))
  bandas   <- map_chr(tarjetas, ~ .txt(.x, css = "span.product-offer-description__text-value"))
  # SKU interno: id del producto en el href /producto/<id>-...
  skus <- str_match(hrefs, "/producto/(\\d+)-")[, 2]
  txt_tarjeta <- map_chr(tarjetas, ~ str_squish(rvest::html_text2(.x)))
  tibble(
    producto = nombres,
    texto_original = armar_texto_original(nombres, marcas, pum, bandas),
    marca    = marcas,
    precio_cop   = precio_cop,
    precio_antes = precio_antes,
    en_promocion = as.integer(!is.na(precio_oferta)),
    sku          = skus,
    disponibilidad = detectar_disponibilidad(txt_tarjeta, precio_cop),
    url = abs_url(hrefs, base)
  )
}

# --- Jumbo (diseño "jumbo-ds") ----------------------------------------------
# Tarjeta = padre del <h3 class*='ProductCardstyles'>.
#   "Paga $ X"  -> precio con tarjeta Jumbo Más (solo se usa si no hay otro precio)
#   1.er $      -> precio público actual  (precio_cop)
#   2.º $       -> precio anterior tachado (si es mayor => en_promocion = 1)
SELECTOR_FICHA_JUMBO <- "h3[class*='ProductCardstyles']"

parsear_jumbo <- function(doc, base) {
  h3 <- rvest::html_elements(doc, SELECTOR_FICHA_JUMBO)
  if (length(h3) == 0) return(plantilla_crudo())
  nodos   <- as.list(xml2::xml_parent(h3))
  nombres <- str_squish(rvest::html_text2(h3))
  
  marcas <- map_chr(nodos, function(n) {
    m <- str_squish(rvest::html_text2(rvest::html_element(n, "p")))
    if (is.na(m) || !nzchar(m) || str_detect(m, "^\\$")) NA_character_ else m
  })
  
  txt <- map_chr(nodos, ~ str_squish(str_replace_all(rvest::html_text2(.x), "\u00a0", " ")))
  tarjeta  <- str_match(txt, "Paga\\s*\\$\\s*(\\d[\\d\\.]*)")[, 2]
  sin_paga <- str_remove(txt, "Paga\\s*\\$\\s*\\d[\\d\\.]*")
  pr <- str_extract_all(sin_paga, "\\$\\s*\\d[\\d\\.]*")
  actual <- map_dbl(pr, ~ if (length(.x) >= 1) parse_cop(.x[1]) else NA_real_)
  antes  <- map_dbl(pr, ~ if (length(.x) >= 2) parse_cop(.x[2]) else NA_real_)
  actual <- coalesce(actual, parse_cop(tarjeta))
  precio_antes <- if_else(!is.na(antes) & !is.na(actual) & antes > actual,
                          antes, NA_real_)

  href <- map_chr(nodos, function(n) {
    a <- rvest::html_element(n, "a")
    if (inherits(a, "xml_missing")) a <- rvest::html_element(n, xpath = "ancestor::a[1]")
    rvest::html_attr(a, "href")
  })
  # SKU interno: data-product-id del contenedor o el id del href "...-<id>/p"
  sku_cont <- map_chr(nodos, function(n) {
    rvest::html_attr(rvest::html_element(n, xpath = "ancestor::div[@data-product-id][1]"),
                     "data-product-id")
  })
  sku_href <- str_match(href, "-(\\d+)/p$")[, 2]
  skus <- coalesce(sku_cont, sku_href)

  tibble(
    producto = nombres,
    texto_original = armar_texto_original(nombres, marcas),
    marca    = marcas,
    precio_cop   = actual,
    precio_antes = precio_antes,
    en_promocion = as.integer(!is.na(precio_antes)),
    sku          = skus,
    disponibilidad = detectar_disponibilidad(txt, actual),
    url = abs_url(href, base)
  ) |> filter(!is.na(producto), nzchar(producto))
}

# --- Éxito (VTEX FastStore) --------------------------------------------------
parsear_exito <- function(doc, base) {
  tarjetas <- as.list(rvest::html_elements(doc, "div[class*='productCard_contentInfo']"))
  if (length(tarjetas) == 0) return(plantilla_crudo())
  precio_antes <- map_dbl(tarjetas, ~ parse_cop(.txt(.x, css = "p[class*='price-dashed']")))
  precio_cop   <- map_dbl(tarjetas, ~ parse_cop(.txt(.x, css = "p[data-fs-container-price-otros]")))
  nombres <- map_chr(tarjetas, ~ .txt(.x, css = "h3[class*='styles_name']"))
  hrefs   <- map_chr(tarjetas, ~ .attr(.x, "href", css = "a[data-testid='product-link']"))
  # En las tarjetas de Éxito "styles_brand" suele contener el precio unitario
  # "(Ml a $ 53,16)" y no la marca: si parece precio se descarta (NULL).
  marcas <- map_chr(tarjetas, ~ .txt(.x, css = "div[class*='styles_brand']"))
  marcas <- if_else(!is.na(marcas) &
                      str_detect(marcas, regex("\\$|\\b(a|gr|ml|und)\\s*\\$",
                                               ignore_case = TRUE)),
                    NA_character_, marcas)
  unit_txt <- map_chr(tarjetas, ~ .txt(.x, css = "span[class*='product-unit_price-unit']"))
  txt_tarjeta <- map_chr(tarjetas, ~ str_squish(rvest::html_text2(.x)))
  # SKU interno: el id numérico del href "...-<id>/p"
  skus <- str_match(hrefs, "-(\\d+)/p$")[, 2]
  tibble(
    producto = nombres,
    texto_original = armar_texto_original(nombres, marcas, unit_txt),
    marca    = marcas,
    precio_cop   = precio_cop,
    precio_antes = if_else(!is.na(precio_antes) & !is.na(precio_cop) &
                             precio_antes > precio_cop, precio_antes, NA_real_),
    en_promocion = as.integer(!is.na(precio_antes)),
    sku          = skus,
    disponibilidad = detectar_disponibilidad(txt_tarjeta, precio_cop),
    url = abs_url(hrefs, base)
  )
}

# ----------------------------------------------------------------------------
# 5. NÚCLEO GENÉRICO DE SCRAPING POR COMERCIO
# ----------------------------------------------------------------------------
procesar_html <- function(html, cfg) {
  doc <- xml2::read_html(html)
  crudo <- cfg$parser(doc, cfg$base)
  if (nrow(crudo) > 0)
    crudo <- crudo |>
    filter(!is.na(producto)) |>
    mutate(url = coalesce(url, paste0(cfg$base, "/#sin-url-", slugify(producto))))
  if (nrow(crudo) == 0) {
    b <- detectar_bloqueo(html)
    stop(if (!is.na(b)) paste0("Bloqueo detectado ('", b, "')")
         else "0 tarjetas de producto: posible cambio de estructura o contenido no renderizado",
         call. = FALSE)
  }
  crudo
}

scrape_comercio <- function(cfg, modo, id_ejecucion, t_consulta, raw_dir, terminos,
                            max_paginas, raw_fecha, requerir_bebe, progress) {
  errores <- character(); ok <- 0L; fallidas <- 0L
  crudos <- list(); vistas <- character(); origen <- NA_character_
  
  procesar_y_acumular <- function(crudo, etiqueta) {
    nuevas <- setdiff(crudo$url, vistas)
    if (length(nuevas) > 0) {
      crudos[[length(crudos) + 1]] <<- crudo |> filter(url %in% nuevas) |> distinct(url, .keep_all = TRUE)
      vistas <<- c(vistas, nuevas)
    }
    length(nuevas)
  }
  
  if (modo == "offline") {
    fuentes <- listar_raw_ultima(raw_dir, cfg$key, raw_fecha)
    if (nrow(fuentes) == 0)
      stop("Modo sin conexión: no hay copias crudas en '", file.path(raw_dir, cfg$key), "'", call. = FALSE)
    t_consulta <- fuentes$t_origen[1]; origen <- fuentes$id_origen[1]
    for (ruta in fuentes$path) {
      progress(sprintf("[%s] reprocesando %s", cfg$nombre, basename(ruta)))
      r <- tryCatch({
        html <- paste(readLines(ruta, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        procesar_y_acumular(procesar_html(html, cfg), basename(ruta)); TRUE
      }, error = function(e) { errores <<- c(errores, paste0(basename(ruta), ": ", conditionMessage(e))); FALSE })
      if (r) ok <- ok + 1L else fallidas <- fallidas + 1L
    }
  } else {
    cerrar_chrome()
    for (term in terminos) {
      paginas <- if (cfg$paginado) seq_len(max_paginas) - 1L else 0L
      for (pg in paginas) {
        url_p <- cfg$url_fun(term, pg)
        slug <- sprintf("%s_p%d", slugify(term), pg)
        progress(sprintf("[%s] %s (página %d)", cfg$nombre, term, pg + 1L))
        res <- tryCatch(reintentar(function() {
          tryCatch({
            html <- fetch_html_renderizado(url_p, cfg$selector_tarjeta, scrolls = cfg$scrolls)
            guardar_raw(html, raw_dir, cfg$key, id_ejecucion, t_consulta, slug)
            procesar_html(html, cfg)
          }, error = function(e) {
            if (!grepl("Bloqueo detectado|^0 tarjetas", conditionMessage(e))) cerrar_chrome()
            stop(e)
          })
        }), error = function(e) e)
        
        if (inherits(res, "error")) {
          if (!str_detect(conditionMessage(res), "^0 tarjetas")) cerrar_chrome()
          if (str_detect(conditionMessage(res), "Bloqueo detectado")) Sys.sleep(20)
          if (pg > 0 && str_detect(conditionMessage(res), "^0 tarjetas")) break
          fallidas <- fallidas + 1L
          errores <- c(errores, sprintf("'%s' p%d: %s", term, pg, conditionMessage(res)))
          break
        }
        ok <- ok + 1L
        if (procesar_y_acumular(res, slug) == 0) break
        Sys.sleep(runif(1, PAUSA_SEG[1], PAUSA_SEG[2]))
      }
    }
  }
  
  crudo_all <- if (length(crudos)) bind_rows(crudos) else plantilla_crudo()
  norm_res <- normalizar_observaciones(crudo_all, cfg$nombre, iso_co(t_consulta),
                                       id_ejecucion, requerir_bebe)
  list(datos = norm_res$datos, tarjetas = nrow(crudo_all),
       fuera_categoria = norm_res$fuera_categoria,
       errores = errores, paginas_ok = ok, paginas_fallidas = fallidas,
       fecha_consulta = iso_co(t_consulta), origen_raw = origen, fatal = NULL)
}

# ----------------------------------------------------------------------------
# 6. UNA FUNCIÓN POR COMERCIO
# ----------------------------------------------------------------------------
scrape_farmatodo <- function(...) scrape_comercio(COMERCIOS$farmatodo, ...)
scrape_jumbo     <- function(...) scrape_comercio(COMERCIOS$jumbo,     ...)
scrape_exito     <- function(...) scrape_comercio(COMERCIOS$exito,     ...)

COMERCIOS <- list(
  farmatodo = list(
    key = "farmatodo", nombre = "Farmatodo", base = "https://www.farmatodo.com.co",
    url_fun = function(term, pg) sprintf(
      "https://www.farmatodo.com.co/buscar?product=%s&departamento=Todos&filtros=",
      utils::URLencode(term, reserved = TRUE)),
    paginado = FALSE, scrolls = 20, selector_tarjeta = "app-product-card-handler",
    parser = parsear_farmatodo, scraper = scrape_farmatodo),
  jumbo = list(
    key = "jumbo", nombre = "Jumbo", base = "https://www.jumbocolombia.com",
    # pg llega 0-based; Jumbo pagina desde 1
    url_fun = function(term, pg) sprintf(
      "https://www.jumbocolombia.com/search?query=%s&type=term&page=%d",
      utils::URLencode(term, reserved = TRUE), pg + 1L),
    paginado = TRUE, scrolls = 6, selector_tarjeta = SELECTOR_FICHA_JUMBO,
    parser = parsear_jumbo, scraper = scrape_jumbo),
  exito = list(
    key = "exito", nombre = "Éxito", base = "https://www.exito.com",
    url_fun = function(term, pg) sprintf(
      "https://www.exito.com/s?q=%s&sort=score_desc&page=%d", gsub(" ", "+", term), pg),
    paginado = TRUE, scrolls = 3, selector_tarjeta = "div[class*='productCard_contentInfo']",
    parser = parsear_exito, scraper = scrape_exito)
)

# ----------------------------------------------------------------------------
# 7. VALIDACION (modulo aparte: validacion.R)
# ----------------------------------------------------------------------------
if (!exists("validar_observaciones", mode = "function")) {
  .archivos_validacion <- c("validacion.R", file.path("..", "validacion.R"))
  .hit <- .archivos_validacion[file.exists(.archivos_validacion)]
  if (length(.hit)) source(.hit[1])
}
if (!exists("validar_observaciones", mode = "function"))
  stop("No se encontro validacion.R (ejecutar desde la raiz del proyecto o tests/)", call. = FALSE)

# ----------------------------------------------------------------------------
# 8. BASE SQLITE
# ----------------------------------------------------------------------------
ESQUEMA_OBSERVACIONES <- "
  CREATE TABLE IF NOT EXISTS observaciones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    comercio TEXT NOT NULL,
    producto TEXT NOT NULL,
    texto_original TEXT,
    marca TEXT,
    subcategoria TEXT,
    contenido_valor REAL CHECK (contenido_valor IS NULL OR contenido_valor > 0),
    contenido_unidad TEXT CHECK (contenido_unidad IS NULL OR contenido_unidad IN ('ml','g','unidad')),
    precio_cop REAL NOT NULL CHECK (precio_cop > 0),
    precio_antes REAL CHECK (precio_antes IS NULL OR precio_antes > 0),
    en_promocion INTEGER CHECK (en_promocion IN (0,1)),
    sku TEXT,
    disponibilidad TEXT CHECK (disponibilidad IS NULL OR disponibilidad IN ('disponible','agotado')),
    url TEXT NOT NULL,
    fecha_consulta TEXT NOT NULL,
    id_ejecucion TEXT NOT NULL,
    comparable INTEGER NOT NULL DEFAULT 0 CHECK (comparable IN (0,1)),
    id_comun TEXT,
    UNIQUE (comercio, url, fecha_consulta)
  )"

ESQUEMA_EJECUCIONES <- "
  CREATE TABLE IF NOT EXISTS ejecuciones (
    id_ejecucion TEXT NOT NULL,
    comercio TEXT NOT NULL,
    modo TEXT NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('exitosa','parcial','fallida')),
    motivo TEXT,
    fecha_consulta TEXT NOT NULL,
    origen_raw TEXT,
    tarjetas_leidas INTEGER,
    recolectados INTEGER,
    insertados INTEGER,
    rechazados INTEGER,
    nuevos INTEGER,
    cambios_precio INTEGER,
    no_observados INTEGER,
    PRIMARY KEY (id_ejecucion, comercio)
  )"

ESQUEMA_CORRECCIONES <- "
  CREATE TABLE IF NOT EXISTS correcciones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha TEXT NOT NULL,
    tabla TEXT NOT NULL,
    registro TEXT NOT NULL,
    campo TEXT,
    valor_anterior TEXT,
    valor_nuevo TEXT,
    motivo TEXT NOT NULL
  )"

ESQUEMA_RECHAZADAS <- "
  CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion TEXT,
    comercio TEXT,
    producto TEXT,
    url TEXT,
    fecha_consulta TEXT,
    motivo TEXT NOT NULL,
    fecha_registro TEXT NOT NULL,
    datos_json TEXT
  )"

VISTA_ULTIMO_PRECIO <- "
  CREATE VIEW IF NOT EXISTS v_ultimo_precio AS
  SELECT id, comercio, producto, texto_original, marca, subcategoria,
         contenido_valor, contenido_unidad, precio_cop, precio_antes,
         en_promocion, sku, disponibilidad, url, fecha_consulta,
         id_ejecucion, comparable, id_comun
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY comercio, url
                                 ORDER BY fecha_consulta DESC) AS rn
    FROM observaciones
  ) WHERE rn = 1"

VISTA_CAMBIOS <- "
  CREATE VIEW IF NOT EXISTS v_cambios_precio AS
  SELECT comercio, url, producto, id_comun,
         fecha_consulta AS fecha_actual, id_ejecucion AS id_ejecucion_actual,
         precio_cop AS precio_actual, precio_anterior, fecha_anterior,
         ROUND(precio_cop - precio_anterior, 2) AS variacion_cop,
         ROUND(100.0 * (precio_cop - precio_anterior) / precio_anterior, 2)
           AS variacion_pct
  FROM (
    SELECT *,
           LAG(precio_cop) OVER (PARTITION BY comercio, url
                                 ORDER BY fecha_consulta) AS precio_anterior,
           LAG(fecha_consulta) OVER (PARTITION BY comercio, url
                                     ORDER BY fecha_consulta) AS fecha_anterior
    FROM observaciones
  )
  WHERE precio_anterior IS NOT NULL AND precio_cop <> precio_anterior"

VISTA_COMPARABLES <- "
  CREATE VIEW IF NOT EXISTS v_comparables AS
  SELECT id_comun, marca, subcategoria, contenido_valor, contenido_unidad,
         comercio, producto, precio_cop, en_promocion, disponibilidad,
         url, fecha_consulta, id_ejecucion,
         CASE WHEN contenido_valor > 0
              THEN ROUND(100.0 * precio_cop / contenido_valor, 2) END
           AS precio_por_100
  FROM v_ultimo_precio
  WHERE comparable = 1 AND id_comun IS NOT NULL"

INDICES_OBS <- c(
  "CREATE INDEX IF NOT EXISTS ix_obs_url ON observaciones (comercio, url, fecha_consulta)",
  "CREATE INDEX IF NOT EXISTS ix_obs_comercio_fecha ON observaciones (comercio, fecha_consulta)",
  "CREATE INDEX IF NOT EXISTS ix_obs_fecha ON observaciones (fecha_consulta)",
  "CREATE INDEX IF NOT EXISTS ix_obs_subcategoria ON observaciones (subcategoria)",
  "CREATE INDEX IF NOT EXISTS ix_obs_marca ON observaciones (marca)",
  "CREATE INDEX IF NOT EXISTS ix_obs_comparable ON observaciones (comparable, id_comun)",
  "CREATE INDEX IF NOT EXISTS ix_obs_promo ON observaciones (en_promocion)",
  "CREATE INDEX IF NOT EXISTS ix_ejec_fecha ON ejecuciones (fecha_consulta)"
)

# Migración de la base del Taller 1 al esquema del Taller 2.
# No borra datos: crea la tabla nueva, copia y registra el cambio en correcciones.
migrar_esquema_observaciones <- function(con) {
  viejas <- DBI::dbListFields(con, "observaciones")
  nuevas <- c("texto_original", "precio_antes", "sku", "disponibilidad",
              "comparable", "id_comun")
  if (all(nuevas %in% viejas)) return(FALSE)

  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "ALTER TABLE observaciones RENAME TO observaciones_v1")
    DBI::dbExecute(con, ESQUEMA_OBSERVACIONES)
    DBI::dbExecute(con, "
      INSERT INTO observaciones
        (id, comercio, producto, texto_original, marca, subcategoria,
         contenido_valor, contenido_unidad, precio_cop, precio_antes,
         en_promocion, sku, disponibilidad, url, fecha_consulta,
         id_ejecucion, comparable, id_comun)
      SELECT id, comercio, producto, producto, marca, subcategoria,
             contenido_valor, contenido_unidad, precio_cop, NULL,
             en_promocion, NULL, NULL, url, fecha_consulta,
             id_ejecucion, 0, NULL
      FROM observaciones_v1")
    DBI::dbExecute(con, "DROP TABLE observaciones_v1")
    DBI::dbExecute(con, "
      INSERT INTO correcciones (fecha, tabla, registro, campo,
                                valor_anterior, valor_nuevo, motivo)
      VALUES (?, 'observaciones', 'ESQUEMA', 'esquema de la tabla',
              'Taller 1: 12 columnas, UNIQUE(comercio, producto, fecha_consulta)',
              'Taller 2: 18 columnas, UNIQUE(comercio, url, fecha_consulta)',
              ?)",
      params = list(iso_co(Sys.time()),
                    paste("Migracion al esquema del Taller 2: se agregan",
                          "texto_original, precio_antes, sku, disponibilidad,",
                          "comparable e id_comun; texto_original se rellena",
                          "con el producto observado (no habia descripcion",
                          "en las copias crudas de esa ejecucion).")))
  })
  TRUE
}

registrar_correccion <- function(con, tabla, registro, campo,
                                 valor_anterior, valor_nuevo, motivo) {
  tryCatch(DBI::dbExecute(con, "
    INSERT INTO correcciones (fecha, tabla, registro, campo,
                              valor_anterior, valor_nuevo, motivo)
    VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(iso_co(Sys.time()), tabla, registro, campo,
                  as.character(valor_anterior), as.character(valor_nuevo), motivo)),
    error = function(e) NULL)
  invisible(TRUE)
}

registrar_rechazadas <- function(con, rechazadas, id_ejecucion) {
  if (nrow(rechazadas) == 0) return(invisible(0L))
  fecha_reg <- iso_co(Sys.time())
  for (i in seq_len(nrow(rechazadas))) {
    fila <- rechazadas[i, , drop = FALSE]
    tryCatch(DBI::dbExecute(con, "
      INSERT INTO observaciones_rechazadas
        (id_ejecucion, comercio, producto, url, fecha_consulta,
         motivo, fecha_registro, datos_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      params = list(id_ejecucion, fila$comercio, fila$producto, fila$url,
                    fila$fecha_consulta, fila$motivo %||% "sin motivo",
                    fecha_reg,
                    jsonlite::toJSON(fila, auto_unbox = TRUE, null = "null")),
      error = function(e) NULL))
  }
  invisible(nrow(rechazadas))
}

inicializar_db <- function(con) {
  # Tablas auxiliares primero: la migración registra su cambio en `correcciones`
  DBI::dbExecute(con, ESQUEMA_CORRECCIONES)
  DBI::dbExecute(con, ESQUEMA_RECHAZADAS)
  if ("observaciones" %in% DBI::dbListTables(con)) migrar_esquema_observaciones(con)
  DBI::dbExecute(con, ESQUEMA_OBSERVACIONES)
  DBI::dbExecute(con, ESQUEMA_EJECUCIONES)
  for (sql in INDICES_OBS) DBI::dbExecute(con, sql)
  DBI::dbExecute(con, VISTA_ULTIMO_PRECIO)
  DBI::dbExecute(con, VISTA_CAMBIOS)
  DBI::dbExecute(con, VISTA_COMPARABLES)
  # Correcciones puntuales sobre datos previos del Taller 1 (idempotente)
  tryCatch(corregir_base_taller1(con),
           error = function(e) warning("corregir_base_taller1: ", conditionMessage(e)))
  invisible(TRUE)
}

calcular_diferencias <- function(con, df, comercio, fecha_iso) {
  hist_urls <- DBI::dbGetQuery(con,
                               "SELECT DISTINCT url FROM observaciones WHERE comercio = ? AND fecha_consulta < ?",
                               params = list(comercio, fecha_iso))$url
  prev_last <- DBI::dbGetQuery(con, "
    SELECT url, precio_cop AS precio_anterior FROM (
      SELECT url, precio_cop,
             ROW_NUMBER() OVER (PARTITION BY url ORDER BY fecha_consulta DESC) AS rn
      FROM observaciones WHERE comercio = ? AND fecha_consulta < ?) WHERE rn = 1",
                               params = list(comercio, fecha_iso))
  prev_run <- DBI::dbGetQuery(con, "
    SELECT DISTINCT url, producto FROM observaciones
    WHERE comercio = ? AND id_ejecucion = (
      SELECT id_ejecucion FROM ejecuciones
      WHERE comercio = ? AND estado IN ('exitosa','parcial') AND insertados > 0
        AND fecha_consulta < ? ORDER BY fecha_consulta DESC LIMIT 1)",
                              params = list(comercio, comercio, fecha_iso))
  
  cambios <- df |> select(comercio, producto, url, precio_actual = precio_cop) |>
    inner_join(prev_last, by = "url") |>
    filter(abs(precio_actual - precio_anterior) > 0.005) |>
    mutate(variacion_cop = precio_actual - precio_anterior,
           variacion_pct = round(100 * variacion_cop / precio_anterior, 2))
  list(nuevos = length(setdiff(df$url, hist_urls)),
       cambios = cambios,
       no_observados = prev_run |> filter(!url %in% df$url) |> mutate(comercio = comercio))
}

persistir_comercio <- function(con, df, info) {
  DBI::dbWithTransaction(con, {
    existentes <- DBI::dbGetQuery(con,
                                  "SELECT url FROM observaciones WHERE comercio = ? AND fecha_consulta = ?",
                                  params = list(info$comercio, info$fecha_consulta))$url
    df_ins <- df |> filter(!url %in% existentes)
    dif <- calcular_diferencias(con, df, info$comercio, info$fecha_consulta)
    if (nrow(df_ins) > 0) DBI::dbAppendTable(con, "observaciones", as.data.frame(df_ins))
    # Idempotente: si la ejecucion ya estaba registrada se reemplaza su fila
    DBI::dbExecute(con,
      "DELETE FROM ejecuciones WHERE id_ejecucion = ? AND comercio = ?",
      params = list(info$id_ejecucion, info$comercio))
    DBI::dbAppendTable(con, "ejecuciones", data.frame(
      id_ejecucion = info$id_ejecucion, comercio = info$comercio, modo = info$modo,
      estado = info$estado, motivo = info$motivo, fecha_consulta = info$fecha_consulta,
      origen_raw = info$origen_raw, tarjetas_leidas = info$tarjetas,
      recolectados = nrow(df), insertados = nrow(df_ins), rechazados = info$rechazados,
      nuevos = dif$nuevos, cambios_precio = nrow(dif$cambios),
      no_observados = nrow(dif$no_observados), stringsAsFactors = FALSE))
    list(insertados = nrow(df_ins), dif = dif)
  })
}

registrar_fallida <- function(con, info) {
  tryCatch(DBI::dbAppendTable(con, "ejecuciones", data.frame(
    id_ejecucion = info$id_ejecucion, comercio = info$comercio, modo = info$modo,
    estado = "fallida", motivo = info$motivo, fecha_consulta = info$fecha_consulta,
    origen_raw = info$origen_raw, tarjetas_leidas = info$tarjetas, recolectados = 0L,
    insertados = 0L, rechazados = info$rechazados, nuevos = NA_integer_,
    cambios_precio = NA_integer_, no_observados = NA_integer_, stringsAsFactors = FALSE)),
    error = function(e) NULL)
}

# ----------------------------------------------------------------------------
# 9. ORQUESTADOR PÚBLICO
# ----------------------------------------------------------------------------
procesar_comercio <- function(key, con, modo, id_ejecucion, t_run, raw_dir, terminos,
                              max_paginas, raw_fecha, requerir_bebe, progress) {
  cfg <- COMERCIOS[[key]]
  fila <- function(estado, motivo, tarjetas = 0L, validas = 0L, ins = 0L, rech = 0L,
                   nuevos = NA_integer_, cambios = NA_integer_, noobs = NA_integer_) {
    tibble(comercio = cfg$nombre, estado = estado, tarjetas_leidas = as.integer(tarjetas),
           productos_recolectados = as.integer(validas), insertados = as.integer(ins),
           rechazados = as.integer(rech), productos_nuevos = as.integer(nuevos),
           cambios_precio = as.integer(cambios), no_observados = as.integer(noobs),
           motivo = motivo)
  }
  vacio <- list(cambios = tibble(), no_observados = tibble())
  
  sc <- tryCatch(cfg$scraper(modo = modo, id_ejecucion = id_ejecucion, t_consulta = t_run,
                             raw_dir = raw_dir, terminos = terminos, max_paginas = max_paginas,
                             raw_fecha = raw_fecha, requerir_bebe = requerir_bebe,
                             progress = progress),
                 error = function(e) list(datos = NULL, fatal = conditionMessage(e), errores = character(),
                                          tarjetas = 0L, fuera_categoria = 0L, fecha_consulta = iso_co(t_run),
                                          origen_raw = NA_character_, paginas_fallidas = 0L))
  info <- list(id_ejecucion = id_ejecucion, comercio = cfg$nombre, modo = modo,
               fecha_consulta = sc$fecha_consulta, origen_raw = sc$origen_raw,
               tarjetas = sc$tarjetas, rechazados = 0L)
  
  fallar <- function(motivo) {
    info$motivo <- motivo; registrar_fallida(con, info)
    c(list(resumen = fila("fallida", motivo, sc$tarjetas)), vacio)
  }
  if (!is.null(sc$fatal)) return(fallar(sc$fatal))
  if (nrow(sc$datos) == 0)
    return(fallar(paste0("0 productos en la categoría (tarjetas leídas: ", sc$tarjetas,
                         "; fuera de categoría: ", sc$fuera_categoria, "). ",
                         paste(sc$errores, collapse = " | "))))
  
  val <- tryCatch(validar_observaciones(sc$datos), error = function(e) e)
  if (inherits(val, "error")) return(fallar(paste("Fallo de validación:", conditionMessage(val))))
  if (nrow(val$validas) == 0)
    return(fallar(paste("Ninguna fila superó la validación.", paste(val$motivos, collapse = "; "))))

  # Toda fila rechazada queda registrada con su motivo (Módulo 1)
  if (!is.null(val$rechazadas) && nrow(val$rechazadas) > 0)
    registrar_rechazadas(con, val$rechazadas, id_ejecucion)

  motivos <- c(sc$errores, val$motivos)
  if (val$n_rechazadas / max(nrow(sc$datos), 1) > 0.3)
    motivos <- c("posible cambio de estructura (muchas filas sin precio/campos clave)", motivos)
  estado <- if (sc$paginas_fallidas > 0 || val$n_rechazadas > 0) "parcial" else "exitosa"
  info <- modifyList(info, list(estado = estado, rechazados = val$n_rechazadas,
                                motivo = if (length(motivos)) paste(motivos, collapse = " | ") else NA_character_))
  
  per <- tryCatch(persistir_comercio(con, val$validas, info), error = function(e) e)
  if (inherits(per, "error"))
    return(fallar(paste("Transacción revertida:", conditionMessage(per))))
  
  list(resumen = fila(estado, info$motivo, sc$tarjetas, nrow(val$validas), per$insertados,
                      val$n_rechazadas, per$dif$nuevos, nrow(per$dif$cambios),
                      nrow(per$dif$no_observados)),
       cambios = per$dif$cambios, no_observados = per$dif$no_observados)
}

#' Ejecuta el scraper para uno o varios comercios.
#' @param modo "online" (descarga y guarda raw/) o "offline" (reprocesa raw/).
#' @param raw_fecha en offline: "YYYY-MM-DD" de la carpeta a reprocesar (NULL = la más reciente).
#' @param progress función(msg) para estados de carga en Shiny.
#' @return list(resumen, cambios_precio, no_observados, id_ejecucion, modo)
ejecutar_scraper <- function(comercios = names(COMERCIOS), modo = c("online", "offline"),
                             db_path = "comparador_precios.sqlite", raw_dir = "raw",
                             terminos = TERMINOS_BUSQUEDA, max_paginas = 3,
                             raw_fecha = NULL, requerir_bebe = TRUE, progress = NULL) {
  modo <- match.arg(modo)
  verificar_paquetes(modo)
  comercios <- match.arg(comercios, names(COMERCIOS), several.ok = TRUE)
  progress <- progress %||% function(msg, ...) message(msg)
  
  t_run <- ahora_co()
  id_ejecucion <- paste0("ejec_", format(t_run, "%Y%m%dT%H%M%S", tz = TZ_CO))
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  on.exit(cerrar_chrome(), add = TRUE)
  inicializar_db(con)
  
  res <- lapply(comercios, function(k)
    tryCatch(procesar_comercio(k, con, modo, id_ejecucion, t_run, raw_dir, terminos,
                               max_paginas, raw_fecha, requerir_bebe, progress),
             error = function(e) list(resumen = tibble(
               comercio = COMERCIOS[[k]]$nombre, estado = "fallida", tarjetas_leidas = NA_integer_,
               productos_recolectados = 0L, insertados = 0L, rechazados = NA_integer_,
               productos_nuevos = NA_integer_, cambios_precio = NA_integer_,
               no_observados = NA_integer_, motivo = paste("Error inesperado:", conditionMessage(e))),
               cambios = tibble(), no_observados = tibble())))

  # Recalcula comparable/id_comun sobre toda la base (Taller 1, sección 2.4)
  comp_n <- tryCatch({
    marcar_comparables(db_path = db_path)
  }, error = function(e) {
    warning("No se pudieron recalcular los comparables: ", conditionMessage(e))
    NA_integer_
  })

  list(resumen = bind_rows(map(res, "resumen")),
       cambios_precio = bind_rows(map(res, "cambios")),
       no_observados = bind_rows(map(res, "no_observados")),
       comparables = comp_n,
       id_ejecucion = id_ejecucion, modo = modo)
}

# ----------------------------------------------------------------------------
# 10. PRODUCTOS COMPARABLES ENTRE COMERCIOS
# ----------------------------------------------------------------------------
STOP_NOMBRE <- c("bebe", "baby", "para", "de", "del", "la", "el", "con", "x", "y", "en",
                 "infantil", "ninos", "nina", "nino", "frasco",
                 "botella", "tarro", "und", "unidad", "pack", "tripack")

# Palabras que describen QUÉ es el producto (no la variante): se ignoran al
# decidir si dos nombres refieren a la misma presentación.
PALABRAS_CATEGORIA <- c(
  "shampoo", "champu", "shampu", "jabon", "bano", "liquido", "syndet", "gel",
  "ducha", "barra", "limpiadora", "crema", "corporal", "hidratante", "leche",
  "locion", "emulsion", "aceite", "colonia", "fragancia", "perfume", "eau",
  "facial", "toallita")

tokens_variantes <- function(tokens) {
  prohibidas <- unique(c(PALABRAS_CATEGORIA, names(MARCAS_CONOCIDAS),
                         "johnsons", "johnson", "s", "babaria", "pequenin"))
  setdiff(tokens, prohibidas)
}

clave_nombre <- function(producto, marca) {
  n <- norm(producto)
  n <- str_remove_all(n, "\\d+(?:[.,]\\d+)?\\s*(ml|cc|g|gr|grs|kg|l|lt|oz|un|und|unidades?)\\b")
  m <- norm(coalesce(marca, ""))
  n <- map2_chr(n, m, function(x, mm) if (nzchar(mm)) str_remove_all(x, fixed(mm)) else x)
  n <- str_replace_all(n, "[^a-z ]", " ")
  map_chr(str_split(n, "\\s+"),
          ~ paste(sort(unique(setdiff(.x[nchar(.x) > 1], STOP_NOMBRE))), collapse = " "))
}

marca_canonica <- function(marca, producto) {
  m <- norm(coalesce(marca, "")); n <- norm(producto)
  map2_chr(m, n, function(mm, nn) {
    claves <- names(MARCAS_CONOCIDAS)
    h <- claves[map_lgl(claves, ~ str_detect(mm, fixed(.x)))]
    if (!length(h)) h <- claves[map_lgl(claves, ~ str_detect(nn, fixed(.x)))]
    if (length(h)) h[1] else str_squish(str_replace_all(mm, "[^a-z0-9]+", " "))
  })
}

# ----------------------------------------------------------------------------
# COMPARABLES FLEXIBLES (los nombres NO tienen que ser iguales)
# Dos productos son comparables si, en comercios distintos, tienen:
#   - misma marca canónica, misma subcategoría y misma unidad de contenido,
#   - contenido igual (o dentro de tol_contenido, ej. 0.1 = +-10 %),
#   - nombres con similitud >= umbral,
#   - y sus VARIANTES son compatibles: los tokens de variante (p. ej.
#     original, manzanilla, avena, antes de dormir) deben intersectar, salvo
#     que alguna de las dos variantes esté vacía. Esto evita emparejar
#     "Derma Protect" con "Antes de dormir" o "Manzanilla" con "Recién Nacido".
# Se empareja 1 a 1 (el mejor par) y se arman grupos entre comercios.
# id_comun es estable entre ejecuciones: slug(marca|subcategoría|contenido|unidad|variante).
# ----------------------------------------------------------------------------
productos_comparables <- function(db_path = "comparador_precios.sqlite", min_comercios = 2,
                                  umbral = 0.25, tol_contenido = 0) {
  vacio <- tibble(clave = character(), comercio = character(), producto = character(),
                  marca = character(), subcategoria = character(),
                  contenido_valor = numeric(), contenido_unidad = character(),
                  precio_cop = numeric(), precio_100 = numeric(),
                  en_promocion = integer(), url = character())
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path); on.exit(DBI::dbDisconnect(con))
  obs <- DBI::dbGetQuery(con, "
    SELECT * FROM (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY comercio, url ORDER BY fecha_consulta DESC) rn
      FROM observaciones) WHERE rn = 1") |> as_tibble()
  if (nrow(obs) == 0) return(vacio)

  obs <- obs |>
    filter(!is.na(contenido_valor), !is.na(subcategoria)) |>
    mutate(marca_k = marca_canonica(marca, producto),
           id = paste(comercio, url, sep = "||"),
           tokens = map2(producto, marca, ~ strsplit(clave_nombre(.x, .y), " ")[[1]])) |>
    filter(nzchar(marca_k))
  if (nrow(obs) == 0) return(vacio)
  obs$vars <- map(obs$tokens, tokens_variantes)

  jac <- function(a, b) length(intersect(a, b)) / max(length(union(a, b)), 1)
  vars_compat <- function(a, b) {
    length(a) == 0 || length(b) == 0 || length(intersect(a, b)) > 0
  }
  pares <- inner_join(obs, obs, by = c("marca_k", "subcategoria", "contenido_unidad"),
                      suffix = c("_a", "_b"), relationship = "many-to-many") |>
    filter(comercio_a < comercio_b,
           abs(contenido_valor_a - contenido_valor_b) /
             pmax(contenido_valor_a, contenido_valor_b) <= tol_contenido + 1e-9) |>
    mutate(sim = map2_dbl(tokens_a, tokens_b, jac)) |>
    filter(sim >= umbral,
           map2_lgl(vars_a, vars_b, vars_compat)) |>
    arrange(desc(sim)) |>
    group_by(comercio_a, comercio_b, id_a) |> slice(1) |> ungroup() |>
    group_by(comercio_a, comercio_b, id_b) |> slice(1) |> ungroup()
  if (nrow(pares) == 0) return(vacio)

  # Grupos = componentes conexos de los pares (propagación de etiquetas)
  ids <- unique(c(pares$id_a, pares$id_b))
  g <- setNames(seq_along(ids), ids)
  repeat {
    nuevo <- g
    for (i in seq_len(nrow(pares))) {
      m <- min(g[pares$id_a[i]], g[pares$id_b[i]])
      nuevo[pares$id_a[i]] <- min(nuevo[pares$id_a[i]], m)
      nuevo[pares$id_b[i]] <- min(nuevo[pares$id_b[i]], m)
    }
    if (identical(unname(nuevo), unname(g))) break
    g <- nuevo
  }

  obs_f <- obs |>
    filter(id %in% ids) |>
    mutate(grupo = g[id]) |>
    group_by(grupo) |> filter(n_distinct(comercio) >= min_comercios) |> ungroup()

  if (nrow(obs_f) == 0) return(vacio)

  # id_comun estable: variante = intersección de variantes del grupo;
  # si la intersección está vacía se usa la variante del primer miembro.
  info_grupos <- obs_f |>
    group_by(grupo) |>
    summarise(marca_k = first(marca_k), subcategoria = first(subcategoria),
              contenido_valor = first(contenido_valor),
              contenido_unidad = first(contenido_unidad),
              var_inter = list(Reduce(intersect, vars)),
              var_pri   = list(sort(vars[[1]])),
              .groups = "drop") |>
    mutate(var_elegida = map2(var_inter, var_pri, ~ if (length(.x)) sort(.x) else .y),
           id_comun = pmap_chr(list(marca_k, subcategoria, contenido_valor,
                                    contenido_unidad, var_elegida),
                               function(m, s, v, u, ve) {
                                 pref <- paste(slugify(m), slugify(s),
                                               as.character(v), u, sep = "-")
                                 suf <- if (length(ve)) paste(ve, collapse = "-") else "generico"
                                 paste(pref, suf, sep = "-")
                               }))

  obs_f |>
    select(-any_of("id_comun")) |>
    left_join(info_grupos |> select(grupo, id_comun), by = "grupo") |>
    mutate(clave = id_comun,
           precio_100 = round(100 * precio_cop / contenido_valor, 1)) |>
    arrange(clave, comercio) |>
    select(clave, comercio, producto, marca, subcategoria, contenido_valor,
           contenido_unidad, precio_cop, precio_100, en_promocion, url)
}

# Marca comparable=1 e id_comun en TODAS las observaciones históricas de las
# URLs que hoy resultan comparables en >= min_comercios. Idempotente.
marcar_comparables <- function(db_path = "comparador_precios.sqlite",
                               min_comercios = 3, ...) {
  comp <- productos_comparables(db_path = db_path, min_comercios = min_comercios, ...)
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path); on.exit(DBI::dbDisconnect(con))
  n_grupos <- n_distinct(comp$clave)
  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "UPDATE observaciones SET comparable = 0, id_comun = NULL")
    if (nrow(comp) > 0) {
      pares <- distinct(comp, comercio, url, clave)
      for (i in seq_len(nrow(pares))) {
        DBI::dbExecute(con,
          "UPDATE observaciones SET comparable = 1, id_comun = ?
           WHERE comercio = ? AND url = ?",
          params = list(pares$clave[i], pares$comercio[i], pares$url[i]))
      }
    }
  })
  n_grupos
}

# Correcciones sobre datos ya cargados del Taller 1 (se registran en `correcciones`).
corregir_base_taller1 <- function(con) {
  # 1) En Éxito el selector de marca devolvía el precio unitario "(Ml a $ 53,16)"
  malas <- DBI::dbGetQuery(con, "
    SELECT id, marca FROM observaciones
    WHERE comercio = 'Éxito' AND marca IS NOT NULL
      AND (marca LIKE '%$%' OR marca LIKE '% a $%' OR marca LIKE '(%)')")
  for (i in seq_len(nrow(malas))) {
    nueva <- completar_marca(NA_character_,
      DBI::dbGetQuery(con, "SELECT producto FROM observaciones WHERE id = ?",
                      params = list(malas$id[i]))$producto)
    if (length(nueva) == 0 || is.na(nueva)) nueva <- NA_character_
    DBI::dbWithTransaction(con, {
      DBI::dbExecute(con, "UPDATE observaciones SET marca = ? WHERE id = ?",
                     params = list(nueva, malas$id[i]))
      registrar_correccion(con, "observaciones", as.character(malas$id[i]), "marca",
                           malas$marca[i], ifelse(is.na(nueva), "NULL", nueva),
                           paste0("El selector styles_brand de Éxito devolvía el precio unitario; ",
                                  "se deriva la marca del nombre del anuncio."))
    })
  }
  # 2) Producto de limpieza clasificado como Colonía por "sin fragancia"
  sucias <- DBI::dbGetQuery(con, "
    SELECT id, producto, subcategoria FROM observaciones
    WHERE subcategoria IS NOT NULL
      AND (producto LIKE '%Detergente%' OR producto LIKE '%detergente%'
           OR producto LIKE '%Ropa Bebe%' OR producto LIKE '%limpieza%')")
  for (i in seq_len(nrow(sucias))) {
    DBI::dbWithTransaction(con, {
      DBI::dbExecute(con, "UPDATE observaciones SET subcategoria = NULL WHERE id = ?",
                     params = list(sucias$id[i]))
      registrar_correccion(con, "observaciones", as.character(sucias$id[i]),
                           "subcategoria", sucias$subcategoria[i], "NULL",
                           paste0("Fuera de la categoria Cuidado del bebe: producto de limpieza ",
                                  "(la regla 'fragancia' matcheaba 'sin fragancia')."))
    })
  }
  invisible(list(marcas_corregidas = nrow(malas), fuera_categoria = nrow(sucias)))
}
