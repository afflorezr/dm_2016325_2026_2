# scraper.R | Taller 1 y 2 - Minería de datos | Categoría: Ortopedia y rehabilitación
library(rvest)
library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(readr)

# =============================================================================
# 1. CONFIGURACIÓN
# =============================================================================
USER_AGENT     <- "TallerMineriaDatos-UNAL/1.0 (uso academico)"
MAX_PETICIONES <- 400L
COMERCIOS      <- c("farmatodo", "locatel", "ortopedicos_futuro")

DOMINIOS <- c(
  farmatodo          = "https://www.farmatodo.com.co",
  locatel            = "https://www.locatelcolombia.com",
  ortopedicos_futuro = "https://www.ortopedicosfuturo.com"
)

# Farmatodo queda "parcial" por diseño: se excluye "muletas" (robots.txt bloquea /buscar*)
ESTADO_BASE <- c(farmatodo = "parcial", locatel = "completa", ortopedicos_futuro = "completa")
NOTA_BASE   <- c(farmatodo = "Sin subcategoria 'muletas' (robots.txt bloquea /buscar*)",
                 locatel = NA_character_, ortopedicos_futuro = NA_character_)

URLS_CATEGORIAS <- list(
  ortopedicos_futuro = c(
    "https://www.ortopedicosfuturo.com/cuidado-corporal/tratamiento-de-lesiones/rodilla",
    "https://www.ortopedicosfuturo.com/cuidado-corporal/tratamiento-de-lesiones/tobillo",
    "https://www.ortopedicosfuturo.com/cuidado-corporal/tratamiento-de-lesiones/brazo-y-mano",
    "https://www.ortopedicosfuturo.com/cuidado-corporal/prendas-de-vestir",
    "https://www.ortopedicosfuturo.com/medias-de-compresion",
    "https://www.ortopedicosfuturo.com/bienestar-en-casa/movilidad-asistida/bastones-y-caminador-y-muletas",
    "https://www.ortopedicosfuturo.com/deporte-y-fitness/terapia-fisica"
  ),
  locatel = c(
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/ortopedia-traumatologia/extremidades-inferiores",
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/ortopedia-traumatologia/extremidades-superiores",
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/ortopedia-traumatologia/tronco",
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/ortopedia-traumatologia/prendas-vestir",
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/aparatos-movilidad-asistida/bastones",
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/aparatos-movilidad-asistida/muletas",
    "https://www.locatelcolombia.com/dispositivos-medicos-en-casa/ortopedia-traumatologia/fisioterapia"
  ),
  farmatodo = paste0(
    "https://www.farmatodo.com.co/categorias/salud-y-medicamentos/rehabilitacion-y-equipos-medicos/",
    c("rodilleras", "tobilleras", "munequeras", "fajas-lumbares-y-abdominales",
      "calcetines-y-medias-terapeuticas", "andadores", "productos-para-rehabilitacion")
  )
)

COLUMNAS <- c("comercio", "categoria", "nombre", "marca", "sku", "id_anuncio",
              "precio", "precio_lista", "descuento", "disponibilidad",
              "url", "url_origen", "fecha_hora")

configurar_agente <- function() {
  try(chromote::set_chrome_args(
    c(chromote::default_chrome_args(), paste0("--user-agent=", USER_AGENT))), silent = TRUE)
  invisible(USER_AGENT)
}

.estado <- new.env()
.estado$peticiones <- 0L
reiniciar_peticiones <- function() .estado$peticiones <- 0L
registrar_peticion <- function() {
  .estado$peticiones <- .estado$peticiones + 1L
  .estado$peticiones <= MAX_PETICIONES
}

# =============================================================================
# 2. UTILIDADES
# =============================================================================
limpiar_precio <- function(x) {
  uno <- function(v) {
    if (length(v) == 0 || is.na(v) || v == "") return(NA_real_)
    v <- str_remove_all(v, "[^0-9,]")
    if (v == "") return(NA_real_)
    suppressWarnings(as.numeric(str_replace(v, ",", ".")))
  }
  map_dbl(x, uno)
}
parsear_precio_cop <- limpiar_precio

ahora_iso <- function() paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota"), "-05:00")

detectar_disponibilidad <- function(texto, precio) {
  if (!is.na(texto) && str_detect(str_to_lower(texto), "agotad|sin stock|sin existencias|no disponible")) {
    return("agotado")
  }
  if (!is.na(precio)) return("disponible")
  NA_character_
}

texto_o_na <- function(x) if (length(x) == 0 || is.na(x) || x == "") NA_character_ else x

asegurar_columnas <- function(df) {
  if (nrow(df) == 0) {
    return(tibble(comercio = character(), categoria = character(), nombre = character(),
                  marca = character(), sku = character(), id_anuncio = character(),
                  precio = double(), precio_lista = double(), descuento = character(),
                  disponibilidad = character(), url = character(), url_origen = character(),
                  fecha_hora = character()))
  }
  for (col in setdiff(COLUMNAS, names(df))) {
    df[[col]] <- if (col %in% c("precio", "precio_lista")) rep(NA_real_, nrow(df)) else rep(NA_character_, nrow(df))
  }
  df[, COLUMNAS]
}

# Copia cruda: DOM ya renderizado (tras JS y scroll), validado antes de escribir.
# raw/<comercio>/<fecha>/html/<categoria>_p<N>.html.gz
guardar_html_crudo <- function(pagina, comercio, etiqueta, raw_dir = "raw",
                               fecha = format(Sys.Date(), "%Y-%m-%d"), selector = NULL) {
  dir <- file.path(raw_dir, comercio, fecha, "html")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  ruta <- file.path(dir, paste0(etiqueta, ".html.gz"))
  html <- pagina$session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  if (is.null(html) || nchar(html) < 5000) stop("HTML demasiado corto: no se guarda")
  if (!is.null(selector) && length(html_elements(xml2::read_html(html), selector)) == 0)
    stop("El HTML no contiene ", selector)
  con <- gzfile(ruta, "w")
  on.exit(close(con))
  writeLines(html, con)
  invisible(ruta)
}

# =============================================================================
# 3. EXTRACTORES DE TARJETA (mismo esquema de salida)
# =============================================================================
extraer_item_vtex <- function(comercio) {
  function(a, url, categoria) {
    nombre <- a %>% html_element(".vtex-product-summary-2-x-productBrand") %>% html_text2()
    if (is.na(texto_o_na(nombre))) {
      nombre <- a %>% html_element(".vtex-product-summary-2-x-nameContainer") %>% html_attr("aria-label")
    }
    p_txt <- a %>% html_element(".vtex-product-price-1-x-sellingPrice") %>% html_text2()
    l_txt <- a %>% html_element(".vtex-product-price-1-x-listPrice") %>% html_text2()
    if (is.na(texto_o_na(p_txt))) p_txt <- l_txt
    
    href <- texto_o_na(a %>% html_element("a") %>% html_attr("href"))
    url_producto <- if (is.na(href)) NA_character_ else if (str_detect(href, "^https?://")) href else paste0(DOMINIOS[[comercio]], href)
    id_anuncio <- if (is.na(url_producto)) NA_character_ else
      url_producto %>% str_remove("^https?://[^/]+/") %>% str_remove("\\?.*$") %>% str_remove("/p$")
    
    precio     <- limpiar_precio(p_txt)
    url_pagina <- url
    tibble(
      comercio       = comercio,
      categoria      = categoria,
      nombre         = texto_o_na(nombre),
      marca          = NA_character_,
      sku            = NA_character_,
      id_anuncio     = id_anuncio,
      precio         = precio,
      precio_lista   = limpiar_precio(l_txt),
      descuento      = NA_character_,
      disponibilidad = detectar_disponibilidad(html_text2(a), precio),
      url            = if (is.na(url_producto)) url_pagina else url_producto,
      url_origen     = url_pagina,
      fecha_hora     = ahora_iso()
    )
  }
}

extraer_item_farmatodo <- function(tarjeta, url, categoria) {
  link   <- tarjeta %>% html_element("a.product-card-handler__detail-description")
  nombre <- link %>% html_attr("title")
  href   <- texto_o_na(link %>% html_attr("href"))
  url_producto <- if (is.na(href)) NA_character_ else paste0(DOMINIOS[["farmatodo"]], href)
  
  sku   <- tarjeta %>% html_element("[data-cuf]") %>% html_attr("data-cuf")
  marca <- tarjeta %>% html_element("p.product-card-handler__brand-value") %>% html_text2()
  p_txt <- tarjeta %>% html_element(".product-all-price__offer") %>% html_text2()
  l_txt <- tarjeta %>% html_element(".product-all-price__normal") %>% html_text2()
  if (is.na(texto_o_na(p_txt))) p_txt <- l_txt
  desc  <- tarjeta %>% html_element(".product-offer-description__band-text--bold") %>% html_text2()
  
  precio     <- limpiar_precio(p_txt)
  url_pagina <- url
  tibble(
    comercio       = "farmatodo",
    categoria      = categoria,
    nombre         = texto_o_na(nombre),
    marca          = texto_o_na(marca),
    sku            = texto_o_na(sku),
    id_anuncio     = texto_o_na(sku),
    precio         = precio,
    precio_lista   = limpiar_precio(l_txt),
    descuento      = texto_o_na(desc),
    disponibilidad = detectar_disponibilidad(html_text2(tarjeta), precio),
    url            = if (is.na(url_producto)) url_pagina else url_producto,
    url_origen     = url_pagina,
    fecha_hora     = ahora_iso()
  )
}

config_sitio <- function(comercio) {
  if (comercio == "farmatodo") {
    list(
      construir_url  = function(base, p) if (p == 1) base else paste0(base, "?pag=", p - 1),
      selector_items = "div.card-ftd",
      scroll_js      = "document.querySelector('#app-component-router-outlet').scrollBy(0, 500);",
      scrolls        = 10,
      extractor      = extraer_item_farmatodo
    )
  } else {
    list(
      construir_url  = function(base, p) if (p == 1) base else paste0(base, "?page=", p),
      selector_items = "article.vtex-product-summary-2-x-element",
      scroll_js      = "window.scrollBy(0, 1000);",
      scrolls        = 8,
      extractor      = extraer_item_vtex(comercio)
    )
  }
}

# =============================================================================
# 4. RECORRIDO DE UNA CATEGORÍA
# =============================================================================
# Atributo "fin": "pagina_vacia" | "error_carga" | "limite_peticiones" | "limite_paginas"
recorrer_categoria <- function(url_base, comercio, raw_dir = "raw",
                               fecha_raw = format(Sys.Date(), "%Y-%m-%d"),
                               max_paginas = 100, pausa_carga = 8, pausa_scroll = 1.5,
                               pausa_estab = 3, guardar_html = TRUE) {
  cfg       <- config_sitio(comercio)
  categoria <- str_extract(url_base, "[^/]+$")
  todos     <- list()
  fin       <- "limite_paginas"
  
  for (page in seq_len(max_paginas)) {
    if (!registrar_peticion()) { fin <- "limite_peticiones"; break }
    url <- cfg$construir_url(url_base, page)
    message("[", comercio, " | ", categoria, "] Página ", page)
    
    pagina <- tryCatch(read_html_live(url), error = function(e) NULL)
    if (is.null(pagina)) { fin <- "error_carga"; break }
    
    items <- tryCatch({
      Sys.sleep(pausa_carga)
      for (s in seq_len(cfg$scrolls)) {
        pagina$session$Runtime$evaluate(cfg$scroll_js)
        Sys.sleep(pausa_scroll)
      }
      Sys.sleep(pausa_estab)
      
      n_prev <- 0
      for (k in 1:10) {
        n_ahora <- length(html_elements(pagina, cfg$selector_items))
        if (n_ahora == n_prev && n_ahora > 0) break
        n_prev <- n_ahora
        Sys.sleep(1)
      }
      
      # Copia cruda (si falla, avisa pero no detiene el scraping)
      if (guardar_html) {
        try(guardar_html_crudo(pagina, comercio, paste0(categoria, "_p", page),
                               raw_dir, fecha_raw, selector = cfg$selector_items),
            silent = FALSE)
      }
      
      elementos <- html_elements(pagina, cfg$selector_items)
      message("  Productos cargados: ", length(elementos))
      map(elementos, cfg$extractor, url = url, categoria = categoria)
    },
    error   = function(e) { message("  Error en la página: ", conditionMessage(e)); NULL },
    finally = try(pagina$session$close(), silent = TRUE))
    
    if (is.null(items)) { fin <- "error_carga"; break }
    datos <- bind_rows(compact(items))
    if (nrow(datos) == 0) { fin <- "pagina_vacia"; message("  Página vacía. Fin."); break }
    
    message("  Extraídos: ", nrow(datos))
    todos <- c(todos, list(datos))
    Sys.sleep(1)
  }
  
  res <- asegurar_columnas(bind_rows(todos))
  attr(res, "fin") <- fin
  res
}

# =============================================================================
# 5. UNA FUNCIÓN POR COMERCIO
# =============================================================================
scrapear_comercio <- function(comercio, urls, raw_dir = "raw",
                              fecha_raw = format(Sys.Date(), "%Y-%m-%d")) {
  resultados <- map(urls, function(u) {
    tryCatch(
      recorrer_categoria(u, comercio, raw_dir = raw_dir, fecha_raw = fecha_raw),
      error = function(e) {
        r <- asegurar_columnas(tibble())
        attr(r, "fin") <- paste0("error: ", conditionMessage(e))
        r
      })
  })
  datos <- bind_rows(resultados) %>%
    asegurar_columnas() %>%
    distinct(comercio, categoria, nombre, precio, url, .keep_all = TRUE)
  attr(datos, "fin_por_categoria") <- set_names(map_chr(resultados, ~ attr(.x, "fin") %||% NA_character_),
                                                str_extract(urls, "[^/]+$"))
  datos
}

scrapear_ortopedicos_futuro <- function(urls = URLS_CATEGORIAS$ortopedicos_futuro, ...)
  scrapear_comercio("ortopedicos_futuro", urls, ...)
scrapear_locatel <- function(urls = URLS_CATEGORIAS$locatel, ...)
  scrapear_comercio("locatel", urls, ...)
scrapear_farmatodo <- function(urls = URLS_CATEGORIAS$farmatodo, ...)
  scrapear_comercio("farmatodo", urls, ...)

# =============================================================================
# 6. RECOLECCIÓN (tolerante a fallas)
# =============================================================================
recolectar_comercio <- function(comercio, raw_dir = "raw",
                                ejecucion_id = paste0("ejec_", format(Sys.time(), "%Y%m%d", tz = "America/Bogota"))) {
  funciones <- list(farmatodo = scrapear_farmatodo, locatel = scrapear_locatel,
                    ortopedicos_futuro = scrapear_ortopedicos_futuro)
  inicio <- ahora_iso()
  sello  <- format(Sys.time(), "%Y-%m-%d_%H%M%S", tz = "America/Bogota")
  
  datos <- tryCatch(funciones[[comercio]](raw_dir = raw_dir, fecha_raw = substr(sello, 1, 10)),
                    error = function(e) e)
  
  if (inherits(datos, "error") || nrow(datos) == 0) {
    motivo <- if (inherits(datos, "error")) conditionMessage(datos) else "sin productos extraidos"
    return(tibble(ejecucion_id = ejecucion_id, comercio = comercio, fecha_inicio = inicio,
                  fecha_fin = ahora_iso(), n_registros = 0L, estado = "fallida", motivo = motivo))
  }
  
  dir.create(file.path(raw_dir, comercio), recursive = TRUE, showWarnings = FALSE)
  write_csv(datos, file.path(raw_dir, comercio, paste0("productos_", sello, ".csv")))
  
  fines  <- attr(datos, "fin_por_categoria")
  fallas <- fines[is.na(fines) | fines != "pagina_vacia"]
  estado <- ESTADO_BASE[[comercio]]
  motivo <- NOTA_BASE[[comercio]]
  if (length(fallas) > 0) {
    estado <- "parcial"
    motivo <- paste(na.omit(c(motivo, paste0(names(fallas), ": ", fallas, collapse = "; "))), collapse = " | ")
  }
  
  tibble(ejecucion_id = ejecucion_id, comercio = comercio, fecha_inicio = inicio,
         fecha_fin = ahora_iso(), n_registros = nrow(datos), estado = estado,
         motivo = if (is.na(motivo)) NA_character_ else motivo)
}

ejecutar_recoleccion <- function(comercios = COMERCIOS, raw_dir = "raw") {
  configurar_agente()
  reiniciar_peticiones()
  ejecucion_id <- paste0("ejec_", format(Sys.time(), "%Y%m%d", tz = "America/Bogota"))
  map_dfr(comercios, recolectar_comercio, raw_dir = raw_dir, ejecucion_id = ejecucion_id)
}

# =============================================================================
# 7. MODO SIN CONEXIÓN: reprocesa raw/<comercio>/<fecha>/html/*.html.gz
# =============================================================================
reprocesar_raw <- function(comercio, fecha, raw_dir = "raw") {
  cfg   <- config_sitio(comercio)
  bases <- URLS_CATEGORIAS[[comercio]]
  fs <- list.files(file.path(raw_dir, comercio, fecha, "html"), "\\.html\\.gz$", full.names = TRUE)
  if (length(fs) == 0) stop("No hay HTML en ", file.path(raw_dir, comercio, fecha, "html"))
  
  map_dfr(fs, function(f) {
    et   <- str_remove(basename(f), "\\.html\\.gz$")
    cat  <- str_remove(et, "_p\\d+$")
    p    <- as.integer(str_extract(et, "\\d+$"))
    base <- bases[str_extract(bases, "[^/]+$") == cat][1]
    url  <- cfg$construir_url(base, p)
    pg   <- xml2::read_html(paste(readLines(gzfile(f), warn = FALSE), collapse = "\n"))
    hora <- paste0(format(file.mtime(f), "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota"), "-05:00")
    map_dfr(html_elements(pg, cfg$selector_items), cfg$extractor, url = url, categoria = cat) %>%
      mutate(fecha_hora = hora)   # hora de captura, no del reprocesamiento
  }) %>%
    asegurar_columnas() %>%
    distinct(comercio, categoria, nombre, precio, url, .keep_all = TRUE)
}

leer_raw_csv <- function(comercio, raw_dir = "raw") {
  archivos <- list.files(file.path(raw_dir, comercio), pattern = "^productos_.*\\.csv$", full.names = TRUE)
  if (length(archivos) == 0) stop("No hay CSV en ", file.path(raw_dir, comercio))
  map_dfr(archivos, function(a) {
    read_csv(a, col_types = cols(.default = col_character()), show_col_types = FALSE) %>%
      mutate(comercio = comercio, archivo_raw = basename(a))
  })
}

# Ejecutar a mano:
#   registron <- ejecutar_recoleccion()
   