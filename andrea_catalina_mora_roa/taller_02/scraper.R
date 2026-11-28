# Categoría 29: Medicamentos para dolor e inflamación
#
# Comercios: La Rebaja (API VTEX), Locatel (API VTEX), Cafam (HTML paginado)
#
# Este archivo SOLO extrae (no escribe en la base): la validación está en validacion.R
# y la inserción en actualizacion.R.
#
# Cada recolección:
#   - respeta el robots.txt (User-agent: *) y no consulta rutas prohibidas;
#   - hace una pausa entre peticiones, se identifica con su agente de usuario y no supera
#     CFG$max_peticiones peticiones por comercio y ejecución;
#   - guarda las respuestas originales comprimidas en raw/<comercio>/<ejecucion>/ con su índice
#     (clave, URL, fecha y hora de consulta, estado HTTP).

suppressPackageStartupMessages({
  library(httr)
})
# Solo se toma fromJSON de jsonlite: adjuntar el paquete completo enmascara shiny::validate()
fromJSON <- jsonlite::fromJSON

CFG <- list(
  ruta_db    = "comparador_precios.sqlite",
  dir_raw    = "raw",
  pausa      = 3,     # segundos entre peticiones (subida de 1.5: los sitios se saturaron)
  timeout    = 300,   # segundos máximos TOTALES por petición (las páginas de Cafam pesan ~2 MB y
                      # el sitio puede servirlas lento; antes 60)
  lento_bps  = 500,   # se aborta (y reintenta) solo si la transferencia se estanca:
  lento_seg  = 60,    #   menos de `lento_bps` bytes/s durante `lento_seg` segundos seguidos
  intentos   = 3,     # reintentos por petición, con espera exponencial
  max_peticiones = 120L,  # tope de peticiones por comercio y ejecución (categoría completa: ~40)
  zona       = "America/Bogota",
  user_agent = "TallerMineriaDatos-UNAL/1.0 (uso academico)"
)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

chr <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  v <- x[[1]]
  if (is.null(v) || (length(v) == 1 && is.na(v)) || !nzchar(as.character(v))) return(NA_character_)
  as.character(v)
}
num <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  v <- suppressWarnings(as.numeric(x[[1]]))
  if (is.na(v)) NA_real_ else v
}

# Precio en texto o número -> número (COP). Formato colombiano: punto de miles y coma decimal.
#   "$ 12.900" -> 12900   "12.900,50" -> 12900.5   "12,900" -> 12900   "12.5" -> 12.5   18900 -> 18900
# Lo que no se puede interpretar queda NA (nunca se inventa un valor).
limpiar_precio <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  if (is.list(x)) x <- x[[1]]
  if (is.null(x) || length(x) == 0) return(NA_real_)
  if (is.numeric(x)) return(as.numeric(x))
  vapply(as.character(x), function(t) {
    if (is.na(t)) return(NA_real_)
    t <- gsub("[^0-9.,-]", "", t)                   # quita $, COP, espacios (incluido el no separable)
    if (!nzchar(t) || !grepl("[0-9]", t)) return(NA_real_)
    if (grepl("\\.", t) && grepl(",", t)) {       # los dos separadores: el último es el decimal
      if (regexpr(",", t) > max(gregexpr("\\.", t)[[1]])) { t <- gsub(".", "", t, fixed = TRUE); t <- sub(",", ".", t, fixed = TRUE) }
      else t <- gsub(",", "", t, fixed = TRUE)
    } else if (grepl("^-?[0-9]{1,3}(\\.[0-9]{3})+$", t)) {
      t <- gsub(".", "", t, fixed = TRUE)            # 12.900 / 1.250.000: puntos de miles
    } else if (grepl("^-?[0-9]{1,3}(,[0-9]{3})+$", t)) {
      t <- gsub(",", "", t, fixed = TRUE)            # 12,900: comas de miles
    } else {
      t <- sub(",", ".", t, fixed = TRUE)            # 12,5: coma decimal
    }
    suppressWarnings(as.numeric(t))
  }, numeric(1), USE.NAMES = FALSE)
}

# Fecha y hora en ISO 8601 con hora de Colombia, p. ej. 2026-10-08T11:35:00-05:00
ahora_iso <- function() {
  x <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = CFG$zona)
  sub("([+-][0-9]{2})([0-9]{2})$", "\\1:\\2", x)
}

# Columnas que TODA función de comercio debe devolver, siempre en este orden
COLS <- c("comercio", "producto_id", "sku_comercio", "ean", "referencia",
          "nombre_original", "marca_original", "descripcion_original",
          "categoria_origen", "categoria_consulta", "url",
          "precio", "precio_lista", "en_promocion", "disponible", "moneda",
          "texto_original", "fecha_hora")

unico_por_sku <- function(df) df[!duplicated(df[, c("comercio", "sku_comercio")]), , drop = FALSE]

leer_robots <- function(base) {
  vacio <- list(reglas = character(), delay = NA_real_)
  r <- tryCatch(GET(paste0(base, "/robots.txt"), user_agent(CFG$user_agent), timeout(30)),
                error = function(e) NULL)
  if (is.null(r) || status_code(r) != 200) return(vacio)
  lin <- trimws(strsplit(content(r, "text", encoding = "UTF-8"), "\r?\n")[[1]])
  reglas <- character(); delay <- NA_real_; grupo <- FALSE; prev_ua <- FALSE
  for (l in lin) {
    if (grepl("^user-agent:", l, ignore.case = TRUE)) {
      agente <- trimws(sub("^user-agent:", "", l, ignore.case = TRUE))
      if (!prev_ua) grupo <- FALSE
      grupo <- grupo || identical(agente, "*")
      prev_ua <- TRUE
    } else if (nzchar(l)) {
      prev_ua <- FALSE
      if (grupo && grepl("^disallow:", l, ignore.case = TRUE)) {
        v <- trimws(sub("^disallow:", "", l, ignore.case = TRUE))
        if (nzchar(v)) reglas <- c(reglas, v)
      } else if (grupo && grepl("^crawl-delay:", l, ignore.case = TRUE)) {
        delay <- suppressWarnings(as.numeric(trimws(sub("^crawl-delay:", "", l, ignore.case = TRUE))))
      }
    }
  }
  list(reglas = reglas, delay = delay)
}

regla_a_regex <- function(regla) {
  x <- gsub("([.+?(){}|^\\[\\]\\\\])", "\\\\\\1", regla, perl = TRUE)
  x <- gsub("*", ".*", x, fixed = TRUE)
  paste0("^", x)
}

# Se ignoran las reglas Allow: criterio conservador (más estricto que el robots.txt)
permitido <- function(reglas, ruta) {
  if (!length(reglas)) return(TRUE)
  !any(vapply(reglas, function(r) grepl(regla_a_regex(r), ruta, perl = TRUE), logical(1)))
}

.robots_cache <- new.env()
reglas_robots <- function(base) {
  if (is.null(.robots_cache[[base]])) .robots_cache[[base]] <- leer_robots(base)
  .robots_cache[[base]]
}

# Las copias se escriben y leen como BYTES UTF-8 (modo binario): así no dependen de la
# configuración regional de R ni del sistema operativo (Windows, macOS, Linux, Colab).
guardar_raw <- function(texto, archivo) {
  con <- gzfile(archivo, "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(texto)), con)
}
leer_raw <- function(archivo) {
  con <- gzfile(archivo, "rb")
  on.exit(close(con))
  partes <- list()
  repeat {
    b <- readBin(con, "raw", n = 1048576L)
    if (!length(b)) break
    partes[[length(partes) + 1L]] <- b
  }
  texto <- rawToChar(do.call(c, partes))
  Encoding(texto) <- "UTF-8"
  texto
}

# Reintenta con espera exponencial y respeta Retry-After. Un 400/401/403/404 NO se reintenta
# (no se intenta eludir bloqueos). El error final informa el motivo real del último intento.
get_con_reintentos <- function(url, intentos = CFG$intentos) {
  motivo <- "sin respuesta"
  for (i in seq_len(intentos)) {
    r <- tryCatch(GET(url, user_agent(CFG$user_agent),
                      add_headers(`Accept-Language` = "es-CO,es;q=0.9"),
                      config(connecttimeout = 30, low_speed_limit = CFG$lento_bps,
                             low_speed_time = CFG$lento_seg),
                      timeout(CFG$timeout)),
                  error = function(e) e)
    espera <- CFG$pausa * 2^i * 2
    if (inherits(r, "error")) {
      motivo <- paste("error de conexión:", conditionMessage(r))
    } else {
      st <- status_code(r)
      if (st %in% c(200, 206)) return(r)
      motivo <- sprintf("HTTP %d", st)
      if (st %in% c(400, 401, 403, 404)) stop(sprintf("HTTP %d en %s", st, url))
      ra <- suppressWarnings(as.numeric(headers(r)[["retry-after"]]))
      if (length(ra) == 1 && !is.na(ra)) espera <- max(espera, min(ra, 300))
    }
    message(sprintf("   ! intento %d/%d fallido (%s)", i, intentos, motivo))
    if (i < intentos) Sys.sleep(espera)
  }
  stop(sprintf("No se pudo obtener tras %d intentos (%s): %s", intentos, motivo, url))
}

# Devuelve list(texto, fecha_hora, extra).
#  - modo offline: lee raw/ (NULL si no hay más archivos).
#  - modo online con ctx$reanudar: si la página ya está en raw/ de esa ejecución, la reutiliza
#    sin tocar el sitio y solo consulta las páginas que faltan.
fuente <- function(ctx, comercio, clave, url, ext = "json") {
  dir_run <- file.path(CFG$dir_raw, comercio, ctx$ejecucion_id)
  archivo <- file.path(dir_run, paste0(clave, ".", ext, ".gz"))
  indice  <- file.path(dir_run, "indice.csv")

  hay_copia <- file.exists(archivo) && file.exists(indice)
  if (ctx$modo == "offline" && !hay_copia) return(NULL)
  if (hay_copia && (ctx$modo == "offline" || isTRUE(ctx$reanudar))) {
    idx <- read.csv(indice, stringsAsFactors = FALSE)
    fila <- idx[idx$clave == clave, , drop = FALSE][1, ]
    return(list(texto = leer_raw(archivo), fecha_hora = fila$fecha_hora,
                extra = if (is.na(fila$extra)) "" else fila$extra))
  }

  base <- sub("^(https?://[^/]+).*$", "\\1", url)
  ruta <- sub("^https?://[^/]+", "", url)
  rb <- reglas_robots(base)
  if (!is.na(rb$delay) && rb$delay > 30)
    stop(sprintf("%s pide Crawl-delay de %s s: no se consulta.", base, rb$delay))
  if (!permitido(rb$reglas, ruta))
    stop("robots.txt (User-agent: *) no permite la ruta: ", ruta)

  ctx$contador$n <- ctx$contador$n + 1L
  if (ctx$contador$n > CFG$max_peticiones)
    stop(sprintf("se alcanzó el tope de %d peticiones por ejecución", CFG$max_peticiones))
  Sys.sleep(CFG$pausa)
  r <- get_con_reintentos(url)
  fecha_hora <- ahora_iso()
  texto <- content(r, "text", encoding = "UTF-8")

  dir.create(dir_run, recursive = TRUE, showWarnings = FALSE)
  guardar_raw(texto, archivo)
  extra <- headers(r)[["resources"]] %||% ""
  fila <- data.frame(clave = clave, url = url, fecha_hora = fecha_hora,
                     status = status_code(r), extra = extra, stringsAsFactors = FALSE)
  write.table(fila, indice, sep = ",", row.names = FALSE, qmethod = "double",
              col.names = !file.exists(indice), append = file.exists(indice))
  list(texto = texto, fecha_hora = fecha_hora, extra = extra)
}

# La Rebaja y Locatel usan la API pública de VTEX:
#   /api/catalog_system/pub/products/search?fq=C:/<ruta de ids>/&_from=0&_to=49
#   El total de la categoría viene en el header "resources" (p. ej. "0-49/280").
parsear_vtex_api <- function(texto, comercio, fecha_hora, categoria_consulta) {
  prods <- fromJSON(texto, simplifyVector = FALSE)
  filas <- list()
  for (p in prods) {
    espec <- vapply(unlist(p$allSpecifications), function(s)
      paste0(s, ": ", paste(unlist(p[[s]]), collapse = ", ")), character(1))
    for (it in p$items) {
      of <- tryCatch(it$sellers[[1]]$commertialOffer, error = function(e) NULL)
      precio <- limpiar_precio(of$Price); lista <- limpiar_precio(of$ListPrice)
      if (!is.na(precio) && precio <= 0) precio <- NA_real_   # 0 = sin precio, no es un precio
      if (!is.na(lista)  && lista  <= 0) lista  <- NA_real_
      promo <- if (!is.na(precio) && !is.na(lista)) as.integer(lista > precio) else NA_integer_
      disp_n <- num(of$AvailableQuantity)
      filas[[length(filas) + 1]] <- data.frame(
        comercio = comercio,
        producto_id = chr(p$productId),
        sku_comercio = chr(it$itemId %||% p$productId),
        ean = chr(it$ean),
        referencia = chr(p$productReference),
        nombre_original = chr(p$productName),
        marca_original = chr(p$brand),
        descripcion_original = chr(p$description),
        categoria_origen = chr(paste(unlist(p$categories), collapse = " || ")),
        categoria_consulta = categoria_consulta,
        url = chr(p$link),
        precio = precio, precio_lista = lista, en_promocion = promo,
        disponible = if (is.na(disp_n)) NA_integer_ else as.integer(disp_n > 0),
        moneda = "COP",
        texto_original = paste(c(p$productName, p$description, espec), collapse = " | "),
        fecha_hora = fecha_hora, stringsAsFactors = FALSE)
    }
  }
  list(datos = if (length(filas)) do.call(rbind, filas) else NULL, n_productos = length(prods))
}

scrape_vtex_api <- function(ctx, comercio, base, categorias, tam = 50L) {
  filas <- list(); completo <- TRUE; notas <- character(); total_sitio <- 0L
  cortado <- FALSE   # TRUE tras un fallo de red: no se sigue pidiendo al sitio
  for (cat in categorias) {
    if (cortado) {
      notas <- c(notas, paste("categoría", cat, ": no consultada (recolección detenida tras un fallo)"))
      next
    }
    desde <- 0L; total_cat <- NA_integer_; recibidos <- 0L
    repeat {
      ruta <- sprintf("/api/catalog_system/pub/products/search?fq=C:/%s/&_from=%d&_to=%d",
                      cat, desde, desde + tam - 1L)
      clave <- sprintf("cat_%s_%05d", gsub("/", "-", cat), desde)
      res <- tryCatch(fuente(ctx, comercio, clave, paste0(base, ruta), ext = "json"),
                      error = function(e) {
                        notas <<- c(notas, paste(clave, conditionMessage(e)))
                        completo <<- FALSE
                        cortado <<- TRUE
                        NULL
                      })
      if (is.null(res)) break
      if (is.na(total_cat) && nzchar(res$extra))
        total_cat <- suppressWarnings(as.integer(sub(".*/", "", res$extra)))
      pp <- parsear_vtex_api(res$texto, comercio, res$fecha_hora, cat)
      if (pp$n_productos == 0) break
      filas[[length(filas) + 1]] <- pp$datos
      recibidos <- recibidos + pp$n_productos
      desde <- desde + tam
      if (!is.na(total_cat) && desde >= total_cat) break
      if (desde >= 2500L) {   # límite de VTEX para el desplazamiento
        notas <- c(notas, paste("categoría", cat, ": límite de 2500 alcanzado")); completo <- FALSE; break
      }
    }
    if (is.na(total_cat) || recibidos != total_cat) completo <- FALSE
    if (!is.na(total_cat)) total_sitio <- total_sitio + total_cat
    notas <- c(notas, sprintf("categoría %s: sitio=%s, recibidos=%d",
                              cat, ifelse(is.na(total_cat), "NA", total_cat), recibidos))
  }
  datos <- if (length(filas)) unico_por_sku(do.call(rbind, filas)) else NULL
  list(datos = datos, total_sitio = total_sitio, completo = completo, notas = notas)
}

# La Rebaja: Droguería > Dolor e Inflamación (9/50, con sus subcategorías) y los tres
# "Droga blanca > dolor" (9/51/253, 931, 932). Se excluyen Naturales/Homeopáticos,
# genéricos con fórmula (0 productos) y Mascotas.
scrape_larebaja <- function(ctx) {
  scrape_vtex_api(ctx, "larebaja", "https://www.larebajavirtual.com",
                  categorias = c("9/50", "9/51/253", "9/51/931", "9/51/932"))
}

# Locatel clasifica por sistema/aparato (no hay categoría "dolor"). Se recolectan por
# completo estas cuatro categorías y la pertenencia a la categoría 29 se decide luego,
# en la limpieza, con reglas documentadas (principio activo):
#   4/25/165 Medicamentos > sistema-nervioso      4/25/160 Medicamentos > aparato-locomotor
#   4/28/190 Medicamentos Otc > sistema-nervioso  4/28/187 Medicamentos Otc > aparato-locomotor
# ORDEN: primero las categorías OTC y aparato locomotor (las más relevantes para el tema) y al
# final la de sistema nervioso con receta, que es la más grande. Si el sitio falla, la
# recolección se detiene (ver `cortado` en scrape_vtex_api) y lo importante ya quedó guardado.
scrape_locatel <- function(ctx) {
  scrape_vtex_api(ctx, "locatel", "https://www.locatelcolombia.com",
                  categorias = c("4/28/190", "4/28/187", "4/25/160", "4/25/165"))
}

# Cafam: HTML de categoría con ?page=N. Los datos están en el HTML:
#   - window.__STATE__ = {...}  (caché de VTEX IO)  -> fuente principal
#   - <script type="application/ld+json"> ItemList  -> respaldo
#   - "recordsFiltered":N                           -> total de la categoría
extraer_objeto_json <- function(txt) {
  cod <- utf8ToInt(txt)
  if (anyNA(cod)) return(NULL)
  prof <- 0L; en_cadena <- FALSE; escape <- FALSE
  for (i in seq_along(cod)) {
    ch <- cod[i]
    if (en_cadena) {
      if (escape) escape <- FALSE
      else if (ch == 92L) escape <- TRUE
      else if (ch == 34L) en_cadena <- FALSE
    } else if (ch == 34L) en_cadena <- TRUE
    else if (ch == 123L) prof <- prof + 1L
    else if (ch == 125L) {
      prof <- prof - 1L
      if (prof == 0L) return(intToUtf8(cod[1:i]))
    }
  }
  NULL
}

extraer_state <- function(html) {
  m <- regexpr("__STATE__\\s*=\\s*\\{", html, perl = TRUE)
  if (m < 0) return(NULL)
  inicio <- m + attr(m, "match.length") - 1L
  # substr con límite explícito: substring() corta en 1.000.000 de caracteres por defecto
  resto <- substr(html, inicio, nchar(html))
  fin <- regexpr("</script>", resto, fixed = TRUE)
  if (fin > 0) resto <- substr(resto, 1, fin - 1L)
  obj <- extraer_objeto_json(resto)
  if (is.null(obj)) return(NULL)
  tryCatch(fromJSON(obj, simplifyVector = FALSE), error = function(e) NULL)
}

# Reemplaza las referencias {"type":"id","id":"..."} del caché por sus nodos
resolver <- function(x, st, prof = 0L) {
  if (prof > 8L || is.null(x)) return(x)
  if (is.list(x)) {
    if (identical(x[["type"]], "id") && !is.null(x[["id"]]))
      return(resolver(st[[x[["id"]]]], st, prof + 1L))
    if (identical(x[["type"]], "json") && !is.null(x[["json"]])) return(x[["json"]])
    return(lapply(x, resolver, st = st, prof = prof + 1L))
  }
  x
}

campo <- function(x, prefijo) {   # campos con argumentos, p. ej. items({"filter":"ALL"})
  if (!is.list(x) || is.null(names(x))) return(NULL)
  nm <- names(x)[startsWith(names(x), prefijo)]
  if (length(nm)) x[[nm[1]]] else NULL
}

productos_desde_state <- function(st, base, fecha_hora, categoria_consulta) {
  claves <- names(st)
  pk <- grep("^Product:[^.]+$", claves, value = TRUE)
  filas <- list()
  for (k in pk) {
    p <- resolver(st[[k]], st)
    items <- campo(p, "items")
    it <- if (length(items)) items[[1]] else NULL
    of <- tryCatch(it$sellers[[1]]$commertialOffer, error = function(e) NULL)
    precio <- limpiar_precio(p$priceRange$sellingPrice$lowPrice)
    lista  <- limpiar_precio(p$priceRange$listPrice$lowPrice)
    if (is.na(precio)) precio <- limpiar_precio(of$Price)
    if (is.na(lista))  lista  <- limpiar_precio(of$ListPrice)
    if (!is.na(precio) && precio <= 0) precio <- NA_real_
    if (!is.na(lista)  && lista  <= 0) lista  <- NA_real_
    promo <- if (!is.na(precio) && !is.na(lista)) as.integer(lista > precio) else NA_integer_
    disp_n <- num(of$AvailableQuantity)
    url <- chr(p$link)
    if (is.na(url) && !is.na(chr(p$linkText))) url <- paste0(base, "/", p$linkText, "/p")
    filas[[length(filas) + 1]] <- data.frame(
      comercio = "cafam",
      producto_id = chr(p$productId),
      sku_comercio = chr(it$itemId %||% p$productId),
      ean = chr(it$ean),
      referencia = chr(p$productReference),
      nombre_original = chr(p$productName),
      marca_original = chr(p$brand),
      descripcion_original = chr(p$description),
      categoria_origen = chr(paste(unlist(p$categories), collapse = " || ")),
      categoria_consulta = categoria_consulta,
      url = url,
      precio = precio, precio_lista = lista, en_promocion = promo,
      disponible = if (is.na(disp_n)) NA_integer_ else as.integer(disp_n > 0),
      moneda = "COP",
      texto_original = paste(c(p$productName, p$description), collapse = " | "),
      fecha_hora = fecha_hora, stringsAsFactors = FALSE)
  }
  if (length(filas)) do.call(rbind, filas) else NULL
}

productos_desde_ldjson <- function(html, fecha_hora, categoria_consulta) {
  bl <- regmatches(html, gregexpr('(?s)<script type="application/ld\\+json"[^>]*>.*?</script>',
                                  html, perl = TRUE))[[1]]
  filas <- list()
  for (b in bl) {
    j <- sub("</script>$", "", sub("(?s)^<script[^>]*>", "", b, perl = TRUE))
    obj <- tryCatch(fromJSON(j, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(obj) || !identical(obj[["@type"]], "ItemList")) next
    for (el in obj$itemListElement) {
      it <- el$item
      ofe <- it$offers
      precio <- limpiar_precio(ofe$lowPrice %||% ofe$price)
      if (is.na(precio)) precio <- limpiar_precio(tryCatch(ofe$offers[[1]]$price, error = function(e) NULL))
      if (!is.na(precio) && precio <= 0) precio <- NA_real_
      id <- chr(it[["@id"]])
      filas[[length(filas) + 1]] <- data.frame(
        comercio = "cafam", producto_id = NA_character_,
        sku_comercio = chr(it$sku %||% id), ean = chr(it$gtin13 %||% it$gtin),
        referencia = NA_character_,
        nombre_original = chr(it$name), marca_original = chr(it$brand$name),
        descripcion_original = chr(it$description),
        categoria_origen = NA_character_, categoria_consulta = categoria_consulta,
        url = id, precio = precio, precio_lista = NA_real_, en_promocion = NA_integer_,
        disponible = NA_integer_, moneda = "COP",
        texto_original = paste(c(it$name, it$description), collapse = " | "),
        fecha_hora = fecha_hora, stringsAsFactors = FALSE)
    }
  }
  if (length(filas)) do.call(rbind, filas) else NULL
}

parsear_cafam_html <- function(html, fecha_hora, base, categoria_consulta) {
  st <- extraer_state(html)
  datos <- if (!is.null(st) && !is.null(names(st)))
    productos_desde_state(st, base, fecha_hora, categoria_consulta) else NULL
  origen <- "state"
  if (is.null(datos) || nrow(datos) == 0) {
    datos <- productos_desde_ldjson(html, fecha_hora, categoria_consulta)
    origen <- "ld+json (respaldo)"
  }
  if (is.null(datos)) { datos <- data.frame(); origen <- "ninguno" }
  list(datos = datos, origen = origen)
}

scrape_cafam <- function(ctx) {
  base <- "https://www.drogueriascafam.com.co"
  ruta <- "/salud-y-medicamentos/dolor-y-malestar"
  cat_consulta <- "1/10"   # Salud y medicamentos > Dolor y malestar (sus 4 subcategorías)
  filas <- list(); total <- NA_integer_; completo <- TRUE; notas <- character()
  pagina <- 1L
  repeat {
    ruta_p <- if (pagina == 1L) ruta else paste0(ruta, "?page=", pagina)
    res <- tryCatch(fuente(ctx, "cafam", sprintf("pag_%03d", pagina), paste0(base, ruta_p), ext = "html"),
                    error = function(e) {
                      notas <<- c(notas, paste("pág.", pagina, conditionMessage(e)))
                      completo <<- FALSE
                      NULL
                    })
    if (is.null(res)) break
    if (is.na(total)) {
      m <- regmatches(res$texto, regexpr('"recordsFiltered"\\s*:\\s*[0-9]+', res$texto, perl = TRUE))
      if (length(m)) total <- as.integer(sub(".*:\\s*", "", m))
    }
    pp <- parsear_cafam_html(res$texto, res$fecha_hora, base, cat_consulta)
    notas <- c(notas, sprintf("pág.%d: %d filas desde %s", pagina, nrow(pp$datos), pp$origen))
    if (nrow(pp$datos) == 0) break
    filas[[length(filas) + 1]] <- pp$datos
    acumulado <- nrow(unico_por_sku(do.call(rbind, filas)))
    if (!is.na(total) && acumulado >= total) break
    pagina <- pagina + 1L
    if (pagina > 60L) { notas <- c(notas, "Máximo de 60 páginas alcanzado"); completo <- FALSE; break }
  }
  datos <- if (length(filas)) unico_por_sku(do.call(rbind, filas)) else NULL
  if (is.null(datos) || is.na(total) || nrow(datos) < total) completo <- FALSE
  notas <- c(notas, sprintf("Cafam: total del sitio=%s, productos obtenidos=%d",
                            ifelse(is.na(total), "NA", total), if (is.null(datos)) 0L else nrow(datos)))
  list(datos = datos, total_sitio = total, completo = completo, notas = notas)
}

SCRAPERS <- list(larebaja = scrape_larebaja, cafam = scrape_cafam, locatel = scrape_locatel)

COMERCIOS <- data.frame(
  comercio = c("larebaja", "cafam", "locatel"),
  nombre   = c("La Rebaja", "Droguerías Cafam", "Locatel Colombia"),
  base_url = c("https://www.larebajavirtual.com", "https://www.drogueriascafam.com.co",
               "https://www.locatelcolombia.com"),
  stringsAsFactors = FALSE)

# ctx: modo ("online" / "offline"), id de la ejecución, si se reanuda una ejecución con copias
# en raw/ y un contador de peticiones (entorno, para que fuente() lo incremente).
nuevo_contexto <- function(modo = c("online", "offline"), ejecucion_id = NULL, reanudar = FALSE) {
  modo <- match.arg(modo)
  if (is.null(ejecucion_id)) {
    if (modo == "offline") stop("El modo sin conexión necesita el id de una ejecución guardada en raw/.")
    ejecucion_id <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = CFG$zona)
  }
  cont <- new.env(); cont$n <- 0L
  list(modo = modo, ejecucion_id = ejecucion_id, reanudar = isTRUE(reanudar), contador = cont)
}

# Ejecuciones con copias crudas disponibles (carpetas raw/<comercio>/<ejecucion>/)
ejecuciones_raw <- function(comercios = COMERCIOS$comercio) {
  ids <- unlist(lapply(comercios, function(nm)
    list.dirs(file.path(CFG$dir_raw, nm), full.names = FALSE, recursive = FALSE)))
  sort(unique(ids[nzchar(ids)]), decreasing = TRUE)
}

# ¿Responde el sitio? (una sola petición corta al robots.txt; no cuenta como página de la categoría)
# Sirve para informar rápido, por ejemplo desde un servidor en la nube que los comercios bloquean.
probar_conexion <- function(comercio, segundos = 15) {
  base <- COMERCIOS$base_url[COMERCIOS$comercio == comercio]
  r <- tryCatch(GET(paste0(base, "/robots.txt"), user_agent(CFG$user_agent), timeout(segundos)),
                error = function(e) e)
  if (inherits(r, "error")) return(list(ok = FALSE, motivo = paste("sin conexión con el sitio:", conditionMessage(r))))
  st <- status_code(r)
  if (st >= 400) return(list(ok = FALSE, motivo = sprintf("el sitio respondió HTTP %d (posible bloqueo)", st)))
  list(ok = TRUE, motivo = "")
}

# Recolecta UN comercio con el scraper del Taller 1. Nunca escribe en la base.
recolectar_comercio <- function(comercio, ctx) {
  if (!comercio %in% names(SCRAPERS)) stop("Comercio desconocido: ", comercio)
  SCRAPERS[[comercio]](ctx)
}
