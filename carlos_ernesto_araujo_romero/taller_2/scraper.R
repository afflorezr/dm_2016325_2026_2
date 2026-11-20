# =============================================================================
# scraper.R
# Módulo de extracción, almacenamiento y verificación del comparador de precios
# de confitería (Carulla, Jumbo y Olímpica).
#
# Curso: Minería de Datos — Universidad Nacional de Colombia
# Estudiante: Carlos Ernesto Araujo Romero
#
# El módulo tiene tres responsabilidades:
#   1. Descargar la categoría completa de cada comercio usando las APIs públicas
#      de catálogo (JSON) que alimentan las páginas de producto.
#   2. Guardar copias crudas comprimidas en raw/ y permitir reprocesarlas sin
#      volver a consultar los sitios (modo offline).
#   3. Validar e insertar las observaciones en SQLite sin sobrescribir
#      ejecuciones anteriores y aplicar la correspondencia manual de productos.
#
# Éxito se conserva en el catálogo de comercios, pero queda inactivo: el
# 2026-11-11 Cloudflare bloqueó todo su dominio con HTTP 403. Sus observaciones
# históricas siguen en la base y Olímpica lo reemplaza en las ejecuciones nuevas
# (decisión documentada en la tabla correcciones).
#
# Uso rápido:
#   source("scraper.R")
#   ejecutar_recoleccion(offline = FALSE)          # recolección en vivo
#   ejecutar_recoleccion(offline = TRUE,
#                        id_ejecucion = "EJEC_...") # reprocesar raw/
# =============================================================================

suppressPackageStartupMessages({
  library(curl)
  library(jsonlite)
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(stringr)
  library(purrr)
  library(tibble)
  library(readr)
})

# -----------------------------------------------------------------------------
# 0. Configuración general
# -----------------------------------------------------------------------------

RUTA_DB_POR_DEFECTO <- "comparador_precios.sqlite"
RUTA_RAW            <- "raw"
RUTA_MAPEO          <- "mapeo_productos.csv"
RUTA_ESQUEMA        <- file.path("db", "schema.sql")
RUTA_VISTAS         <- file.path("db", "vistas.sql")

# Identificación honesta del agente que consulta los sitios.
USER_AGENT <- paste(
  "TallerMineriaDatos-UNAL/1.0",
  "(estudiante Carlos Ernesto Araujo Romero; Universidad Nacional de Colombia)"
)

ESPERA_ENTRE_PAGINAS <- 0.25   # segundos; cortesía con los servidores
TAMANO_PAGINA        <- 50     # máximo permitido por la API de VTEX
REINTENTOS           <- 3

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) b else a
}

# Cada comercio declara las ramas que se consideran equivalentes a la categoría
# registrada. "nucleo" = rama propia de confitería; "filtro_chocolate" = rama
# mixta de la que solo se conservan productos de chocolate.
COMERCIOS <- list(
  carulla = list(
    id_comercio = "carulla",
    nombre      = "Carulla",
    host        = "www.carulla.com",
    grupo       = "Grupo Éxito",
    activo      = TRUE,
    motivo_estado = NULL,
    categoria_equivalente = "Bebidas, snacks y dulces > Dulces y chocolates (chocolates, confitería, chicles y gomitas) + chocolate de mesa",
    robots_url  = "https://www.carulla.com/robots.txt",
    ramas = list(
      list(nombre = "Chocolates",           ruta = "Bebidas, snacks y dulces/Dulces y chocolates/Chocolates",           tipo = "nucleo"),
      list(nombre = "Confitería",           ruta = "Bebidas, snacks y dulces/Dulces y chocolates/Confitería",           tipo = "nucleo"),
      list(nombre = "Chicles",              ruta = "Bebidas, snacks y dulces/Dulces y chocolates/Chicles",              tipo = "nucleo"),
      list(nombre = "Gomitas y masmelos",   ruta = "Bebidas, snacks y dulces/Dulces y chocolates/Gomitas y masmelos",   tipo = "nucleo"),
      list(nombre = "Chocolate de mesa",    ruta = "Despensa/Chocolate, té e infusiones/Chocolate",                      tipo = "filtro_chocolate")
    )
  ),
  jumbo = list(
    id_comercio = "jumbo",
    nombre      = "Jumbo",
    host        = "www.jumbocolombia.com",
    grupo       = "Cencosud",
    activo      = TRUE,
    motivo_estado = NULL,
    categoria_equivalente = "Supermercado > Dulces y postres (confitería y chocolatería) + chocolate de mesa",
    robots_url  = "https://www.jumbocolombia.com/robots.txt",
    ramas = list(
      list(nombre = "Confitería",           ruta = "Supermercado/Dulces Y Postres/Confitería",     tipo = "nucleo"),
      list(nombre = "Chocolatería",         ruta = "Supermercado/Dulces Y Postres/Chocolatería",   tipo = "nucleo"),
      list(nombre = "Chocolate de mesa",    ruta = "Supermercado/Despensa/Chocolate De Mesa",     tipo = "filtro_chocolate")
    )
  ),
  olimpica = list(
    id_comercio = "olimpica",
    nombre      = "Olímpica",
    host        = "www.olimpica.com",
    grupo       = "Organización Olímpica",
    activo      = TRUE,
    motivo_estado = NULL,
    categoria_equivalente = "Supermercado > Pasabocas y helados > Confitería + Supermercado > Desayuno > Chocolates de mesa",
    robots_url  = "https://www.olimpica.com/robots.txt",
    ramas = list(
      list(nombre = "Confitería",           ruta = "Supermercado/Pasabocas y Helados/Confitería",  tipo = "nucleo"),
      list(nombre = "Chocolates de mesa",   ruta = "Supermercado/Desayuno/Chocolates de Mesa",    tipo = "nucleo")
    )
  ),
  exito = list(
    id_comercio = "exito",
    nombre      = "Éxito",
    host        = "www.exito.com",
    grupo       = "Grupo Éxito",
    activo      = FALSE,
    motivo_estado = paste(
      "Cloudflare bloquea todo el dominio con HTTP 403 desde el 2026-11-11;",
      "se reemplaza por Olímpica y se conservan sus observaciones históricas."
    ),
    categoria_equivalente = "Mercado > Dulces y chocolatería (chocolatería, confitería, chicles y masmelos) + chocolate de mesa",
    robots_url  = "https://www.exito.com/robots.txt",
    ramas = list(
      list(nombre = "Chocolatería",         ruta = "Mercado/Dulces y chocolatería/Chocolatería",         tipo = "nucleo"),
      list(nombre = "Confitería",           ruta = "Mercado/Dulces y chocolatería/Confitería",           tipo = "nucleo"),
      list(nombre = "Chicles",              ruta = "Mercado/Dulces y chocolatería/Chicles",              tipo = "nucleo"),
      list(nombre = "Masmelos y gomitas",   ruta = "Mercado/Dulces y chocolatería/Masmelos y gomitas",   tipo = "nucleo"),
      list(nombre = "Chocolate de mesa",    ruta = "Mercado/Despensa/Café, chocolate y cremas no lácteas", tipo = "filtro_chocolate")
    )
  )
)

comercios_activos <- function() {
  names(Filter(function(x) isTRUE(x$activo), COMERCIOS))
}

# -----------------------------------------------------------------------------
# 1. Utilidades de texto, fechas y contenido
# -----------------------------------------------------------------------------

normalizar_texto <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  x <- tolower(x)
  x <- gsub("[^a-z0-9%.,]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

slugify <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_|_$", "", x)
}

ahora_colombia <- function() {
  # Colombia no aplica horario de verano: la zona es UTC-05:00 todo el año.
  paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota"), "-05:00")
}

fecha_colombia <- function() {
  format(Sys.time(), "%Y-%m-%d", tz = "America/Bogota")
}

nuevo_id_ejecucion <- function() {
  paste0("EJEC_", format(Sys.time(), "%Y%m%d_%H%M%S", tz = "America/Bogota"))
}

num_seguro <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  suppressWarnings(as.numeric(x[[1]]))
}

logi_seguro <- function(x) {
  if (is.null(x) || length(x) == 0) return(FALSE)
  isTRUE(x[[1]])
}

# Convierte "1.234,5 g", "450 gr", "1,5 kg", "200 ml", "x12und x132g", etc.
# Devuelve contenido total en g/ml/unidad, unidad, número de empaques mencionado
# y origen del dato. No imputa valores: si no hay contenido, devuelve NA.
parsear_contenido <- function(texto) {
  vacio <- list(valor = NA_real_, unidad = NA_character_, origen = NA_character_,
                empaque = NA_integer_)
  if (is.null(texto) || length(texto) == 0 || is.na(texto) || !nzchar(texto)) return(vacio)

  t <- normalizar_texto(texto)
  empaque <- NA_integer_

  # "x12und", "12 und", "x 8 unidades", "x18 chicles", "100 pastillas"
  m_emp <- str_match(t, "(?:x\\s*)?(\\d+)\\s*(?:und|un|unidades|u|chicles|pastillas)\\b")
  if (!is.na(m_emp[1, 1])) empaque <- as.integer(m_emp[1, 2])

  # "12x80g" = 12 unidades de 80 g -> 960 g totales
  m_mult <- str_match(t, "\\b(\\d+)\\s*x\\s*(\\d+(?:[.,]\\d+)?)\\s*(kg|grs|gr|g|ml|lt|l|litros)\\b")
  if (!is.na(m_mult[1, 1])) {
    n <- as.integer(m_mult[1, 2])
    v <- as.numeric(gsub(",", ".", m_mult[1, 3]))
    u <- m_mult[1, 4]
    if (u == "kg") { v <- v * 1000; u <- "g" }
    if (u %in% c("gr", "grs")) u <- "g"
    if (u %in% c("lt", "l", "litros")) { v <- v * 1000; u <- "ml" }
    return(list(valor = v * n, unidad = u, origen = "nombre_multipack",
                empaque = n))
  }

  # Última aparición de una cantidad con unidad (suele ser el contenido total).
  m <- str_match_all(t, "(\\d+(?:[.,]\\d+)?)\\s*(kg|gramos|gramo|grs|gr|g|ml|lt|l|litros)\\b")[[1]]
  if (nrow(m) == 0) {
    # Si no hay peso/volumen pero sí unidades contables, se usa la unidad.
    if (!is.na(empaque)) {
      return(list(valor = as.numeric(empaque), unidad = "unidad",
                  origen = "nombre_unidades", empaque = empaque))
    }
    return(list(valor = NA_real_, unidad = NA_character_, origen = NA_character_,
                empaque = empaque))
  }

  ultimo <- m[nrow(m), ]
  valor <- as.numeric(gsub(",", ".", ultimo[2]))
  unidad <- ultimo[3]
  if (unidad == "kg") { valor <- valor * 1000; unidad <- "g" }
  if (unidad %in% c("gr", "grs", "gramo", "gramos")) unidad <- "g"
  if (unidad %in% c("lt", "l", "litros")) { valor <- valor * 1000; unidad <- "ml" }

  list(valor = valor, unidad = unidad, origen = "nombre", empaque = empaque)
}

# -----------------------------------------------------------------------------
# 2. Clasificación de subcategoría y reglas de exclusión
# -----------------------------------------------------------------------------

clasificar_subcategoria <- function(texto, marca, categoria_sitio) {
  # Primero se mira el nombre del producto; la ruta del sitio solo es un apoyo.
  n <- normalizar_texto(paste(texto, marca))
  c <- normalizar_texto(categoria_sitio)

  reglas_nombre <- function(x) {
    if (str_detect(x, "\\bchicle|goma de mascar|trident|orbit|clorets|bubbaloo")) return("Chicles")
    if (str_detect(x, "\\bmenta|tic tac|mentol|eucalipto|confite mentolado")) return("Mentas")
    if (str_detect(x, "gomita|gomas|masmelo|marshmallow|malvavisco|grissly|trululu|haribo|vidal|mogul|trolli|fini|millows")) {
      return("Gomitas y masmelos")
    }
    if (str_detect(x, "chocolate|chocolatina|bombon|trufa|ferrero|kinder|milka|lindt|hershey|nestle|corona|luker|\\bjet\\b|jumbo man|nucita|snickers|twix|m&m|milo|cacao hunters|girones")) {
      return("Chocolates")
    }
    if (str_detect(x, "caramelo|chupeta|dulce|confite|bon bon|barrilete|quipitos|nerds|masticable|supercoco|tirudito")) return("Caramelos")
    NA_character_
  }

  sub <- reglas_nombre(n)
  if (!is.na(sub)) return(sub)

  # Apoyo en la categoría del sitio cuando el nombre no es concluyente.
  if (str_detect(c, "chicles")) return("Chicles")
  if (str_detect(c, "masmelos|gomitas")) return("Gomitas y masmelos")
  if (str_detect(c, "chocolateria|chocolates|chocolate de mesa")) return("Chocolates")
  if (str_detect(c, "confiteria")) return("Caramelos")
  "Otros"
}

# Suplementos en gomitas/pastillas: se excluyen por delimitación explícita.
PATRON_SUPLEMENTO <- paste(
  "suplemento", "dietary supplement", "multivitamin", "colagen", "biotin",
  "probiot", "melatonin", "omega 3", "vitamin gumm",
  "gummies? (de |con )?(vitamina|colageno|biotina|probiotico)",
  "gomitas? (vitamina|colageno|biotina|probiotico|multivit)",
  "vitaminas? en gomita", sep = "|"
)

# Pastillas medicinales para la garganta: se excluyen por delimitación explícita.
PATRON_MEDICINAL <- paste(
  "halls", "vick", "vitacreme", "garganta", "antigrip", "jarabe",
  "medicament", "farmaceutic", "analges", "antiacido", "laxante",
  "descongestion", "resfriado", "\\btos\\b", sep = "|"
)

# Productos que no son confitería aunque el sitio los haya clasificado allí.
PATRON_NO_CONFITERIA <- paste(
  "molde", "pinata", "bolsa papel", "juguete", "globo", "vela",
  "decoracion", "invitacion", "dulcero", "base para",
  "mercado familiar", "muneca", "ancheta", "combo regalo", "canasta",
  "adorno", "recipiente", "bombonera", sep = "|"
)

# Productos que son panadería, repostería o platos preparados, no confitería.
PATRON_OTRA_CATEGORIA <- paste(
  "^galleta", "^galletas", "^ponque", "^torta", "^brownie", "^postre",
  "^mousse", "^flan", "^pudin", "^chocoramo", "^gansito", "^mermelada",
  "^arequipe", "^bocadillo", "^pan ", "^panela", "^agua", "^bebida",
  "^cafe", "^café", "^jugo", "^cerveza", "^vino", "^helado",
  "^arroz", "^aceite", "^harina", sep = "|"
)

evaluar_exclusion <- function(texto, marca, rama, tipo_rama) {
  t <- normalizar_texto(paste(texto, marca, rama))
  t_prod <- normalizar_texto(paste(texto, marca))

  if (str_detect(t, PATRON_SUPLEMENTO)) return("suplemento")
  if (str_detect(t, PATRON_MEDICINAL)) return("medicinal_garganta")
  if (str_detect(t, PATRON_NO_CONFITERIA)) return("no_confiteria")
  if (str_detect(t, PATRON_OTRA_CATEGORIA)) return("otra_categoria")

  if (identical(tipo_rama, "filtro_chocolate")) {
    # La rama mezcla café, cocoa y chocolate: se decide por el nombre del producto,
    # no por el nombre de la rama.
    if (!str_detect(t_prod, "chocolate|chocolatina|chocolates|chocolat|\\blindt\\b|\\bferrero\\b|\\bkinder\\b|\\bmilka\\b|\\bcorona\\b|\\bluker\\b|\\bjet\\b")) {
      return("no_es_chocolate")
    }
    if (str_detect(t_prod, "cocoa en polvo|cacao en polvo|instantane|bebida|malteada|crema no lactea|chocolate en polvo")) {
      return("bebida_o_polvo")
    }
  }

  NA_character_
}

# -----------------------------------------------------------------------------
# 3. Acceso HTTP y lectura de la API de catálogo (VTEX)
# -----------------------------------------------------------------------------

codificar_ruta <- function(ruta) {
  segmentos <- strsplit(ruta, "/", fixed = TRUE)[[1]]
  paste(vapply(segmentos, utils::URLencode, character(1), reserved = TRUE), collapse = "/")
}

http_get <- function(url) {
  ultimo_error <- NULL
  for (intento in seq_len(REINTENTOS)) {
    h <- curl::new_handle()
    curl::handle_setopt(
      h,
      useragent = USER_AGENT,
      timeout = 90,
      connecttimeout = 20,
      followlocation = TRUE,
      ssl_verifypeer = TRUE
    )
    curl::handle_setheaders(h, "Accept" = "application/json")
    res <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) e)
    if (!inherits(res, "error") && res$status_code < 400) {
      return(list(
        contenido = res$content,
        headers   = curl::parse_headers_list(rawToChar(res$headers)),
        status    = res$status_code
      ))
    }
    ultimo_error <- if (inherits(res, "error")) conditionMessage(res) else paste("HTTP", res$status_code)
    Sys.sleep(1.5 * intento)
  }
  stop("No fue posible descargar ", url, ": ", ultimo_error)
}

parsear_total_reportado <- function(headers) {
  x <- headers[["resources"]]
  if (is.null(x)) return(NA_integer_)
  x <- x[[length(x)]]
  suppressWarnings(as.integer(sub(".*/", "", x)))
}

leer_pagina <- function(id_comercio, rama_cfg, desde, hasta) {
  cfg <- COMERCIOS[[id_comercio]]
  url <- paste0(
    "https://", cfg$host,
    "/api/catalog_system/pub/products/search/",
    codificar_ruta(rama_cfg$ruta),
    "?_from=", desde, "&_to=", hasta
  )
  res <- http_get(url)
  texto <- rawToChar(res$contenido)
  datos <- jsonlite::fromJSON(texto, simplifyVector = FALSE)
  list(
    url = url,
    texto = texto,
    datos = datos,
    total = parsear_total_reportado(res$headers),
    status = res$status
  )
}

# -----------------------------------------------------------------------------
# 4. Parseo de un producto de la API a una fila homogénea
# -----------------------------------------------------------------------------

extraer_precio <- function(producto) {
  items <- producto$items
  if (is.null(items) || length(items) == 0) {
    return(list(precio = NA_real_, lista = NA_real_, disponible = FALSE,
                sku = NA_character_, item_nombre = NA_character_,
                unit_multiplier = 1, measurement_unit = NA_character_))
  }

  # Si el primer ítem no tiene oferta disponible, se busca el primero que sí.
  elegido <- NULL
  for (i in seq_along(items)) {
    item <- items[[i]]
    sellers <- item$sellers
    if (is.null(sellers) || length(sellers) == 0) next
    ofertas <- lapply(sellers, function(s) {
      co <- s$commertialOffer
      precio <- num_seguro(co$Price)
      list(
        precio = precio,
        lista = num_seguro(co$ListPrice),
        sin_descuento = num_seguro(co$PriceWithoutDiscount),
        disponible = logi_seguro(co$IsAvailable) && !is.na(precio) && precio > 0,
        predeterminado = logi_seguro(s$sellerDefault)
      )
    })
    disponibles <- keep(ofertas, ~ isTRUE(.x$disponible))
    if (length(disponibles) > 0) {
      pred <- keep(disponibles, ~ isTRUE(.x$predeterminado))
      oferta <- if (length(pred) > 0) pred[[1]] else disponibles[[which.min(map_dbl(disponibles, "precio"))]]
      elegido <- list(item = item, oferta = oferta)
      break
    }
  }

  if (is.null(elegido)) {
    item <- items[[1]]
    sellers <- item$sellers
    oferta <- list(precio = NA_real_, lista = NA_real_, sin_descuento = NA_real_,
                   disponible = FALSE, predeterminado = TRUE)
    if (!is.null(sellers) && length(sellers) > 0) {
      co <- sellers[[1]]$commertialOffer
      oferta$precio <- num_seguro(co$Price)
      oferta$lista <- num_seguro(co$ListPrice)
      oferta$sin_descuento <- num_seguro(co$PriceWithoutDiscount)
      oferta$disponible <- logi_seguro(co$IsAvailable) &&
        !is.na(oferta$precio) && oferta$precio > 0
    }
    elegido <- list(item = item, oferta = oferta)
  }

  item <- elegido$item
  oferta <- elegido$oferta

  lista <- oferta$lista
  if (is.na(lista) || lista <= 0) lista <- oferta$sin_descuento
  if (!is.na(lista) && !is.na(oferta$precio) && lista < oferta$precio) lista <- oferta$precio

  list(
    precio = oferta$precio,
    lista = lista,
    disponible = isTRUE(oferta$disponible),
    sku = as.character(item$itemId %||% NA_character_),
    item_nombre = as.character(item$name %||% NA_character_),
    unit_multiplier = as.numeric(item$unitMultiplier %||% 1),
    measurement_unit = as.character(item$measurementUnit %||% NA_character_)
  )
}

parsear_producto <- function(producto, id_comercio, rama, tipo_rama, fecha_consulta) {
  cfg <- COMERCIOS[[id_comercio]]
  texto <- as.character(producto$productName %||% "")
  if (!nzchar(texto)) return(NULL)

  marca <- as.character(producto$brand %||% "")
  categoria_sitio <- as.character(producto$categories[[1]] %||% "")
  precio_info <- extraer_precio(producto)

  contenido <- parsear_contenido(texto)
  if (is.na(contenido$valor) && !is.na(precio_info$item_nombre)) {
    contenido <- parsear_contenido(precio_info$item_nombre)
    if (!is.na(contenido$valor)) contenido$origen <- "nombre_sku"
  }

  descripcion <- as.character(producto$description %||% "")
  if (!nzchar(descripcion)) descripcion <- as.character(producto$metaTagDescription %||% "")

  especificaciones <- producto$allSpecifications
  especificaciones_json <- if (is.null(especificaciones) || length(especificaciones) == 0) {
    NA_character_
  } else {
    as.character(jsonlite::toJSON(especificaciones, auto_unbox = TRUE, null = "null"))
  }

  precio <- precio_info$precio
  lista <- precio_info$lista
  # Un precio no disponible se guarda como NULL, nunca como cero.
  if (!is.na(precio) && precio <= 0) precio <- NA_real_
  if (!is.na(lista) && lista <= 0) lista <- NA_real_
  es_promocion <- as.integer(!is.na(lista) && !is.na(precio) && lista > precio + 0.5)
  descuento <- if (es_promocion == 1 && lista > 0) round(100 * (lista - precio) / lista, 2) else 0

  unidad <- contenido$unidad
  unidad_normalizada <- dplyr::case_when(
    is.na(unidad) ~ NA_character_,
    unidad == "g" ~ "g",
    unidad == "ml" ~ "mL",
    unidad == "unidad" ~ "unidad",
    TRUE ~ NA_character_
  )
  estado_disponibilidad <- if (isTRUE(precio_info$disponible)) "disponible" else "agotado"

  precio_por_unidad <- if (!is.na(precio) && !is.na(contenido$valor) && contenido$valor > 0) {
    round(precio / contenido$valor, 4)
  } else {
    NA_real_
  }
  unidad_precio <- dplyr::case_when(
    is.na(unidad) ~ NA_character_,
    unidad == "g" ~ "COP/g",
    unidad == "ml" ~ "COP/ml",
    unidad == "unidad" ~ "COP/unidad",
    TRUE ~ NA_character_
  )

  unidades_paquete <- precio_info$unit_multiplier
  if (is.na(unidades_paquete) || unidades_paquete <= 0) unidades_paquete <- 1

  tibble::tibble(
    id_comercio          = id_comercio,
    id_producto_comercio = as.character(producto$productId %||% NA_character_),
    sku_comercio         = precio_info$sku,
    texto_original       = texto,
    descripcion_original = descripcion,
    especificaciones_json = especificaciones_json,
    marca                = marca,
    categoria_sitio      = categoria_sitio,
    subcategoria         = clasificar_subcategoria(texto, marca, categoria_sitio),
    contenido_valor      = contenido$valor,
    contenido_unidad     = contenido$unidad,
    contenido_total      = contenido$valor,
    unidad_normalizada   = unidad_normalizada,
    contenido_origen     = contenido$origen,
    unidades_por_paquete = as.integer(unidades_paquete),
    empaque_mencionado   = as.integer(contenido$empaque),
    precio_cop           = precio,
    precio_lista_cop     = lista,
    es_promocion         = es_promocion,
    descuento_pct        = descuento,
    disponible           = as.integer(precio_info$disponible),
    estado_disponibilidad = estado_disponibilidad,
    precio_por_unidad    = precio_por_unidad,
    unidad_precio        = unidad_precio,
    url_producto         = paste0("https://", cfg$host, "/", producto$linkText %||% "", "/p"),
    fecha_consulta       = fecha_consulta,
    rama                 = rama,
    tipo_rama            = tipo_rama
  )
}

# -----------------------------------------------------------------------------
# 5. Descarga de una rama y guardado de copias crudas
# -----------------------------------------------------------------------------

guardar_pagina_raw <- function(dir_rama, numero, texto, meta_pagina) {
  dir.create(dir_rama, recursive = TRUE, showWarnings = FALSE)
  archivo <- file.path(dir_rama, sprintf("pagina_%03d.json.gz", numero))
  con <- gzfile(archivo, "wt", encoding = "UTF-8")
  writeLines(texto, con)
  close(con)
  meta_pagina$archivo <- basename(archivo)
  meta_pagina$sha256 <- digest::digest(texto, algo = "sha256", serialize = FALSE)
  meta_pagina
}

extraer_rama_online <- function(id_comercio, rama_cfg, id_ejecucion, fecha_ejecucion,
                                max_paginas = Inf, verboso = TRUE) {
  cfg <- COMERCIOS[[id_comercio]]
  dir_rama <- file.path(RUTA_RAW, id_comercio, fecha_ejecucion, id_ejecucion,
                        slugify(rama_cfg$nombre))
  dir.create(dir_rama, recursive = TRUE, showWarnings = FALSE)

  meta <- list(
    id_ejecucion = id_ejecucion,
    id_comercio = id_comercio,
    comercio = cfg$nombre,
    rama = rama_cfg$nombre,
    ruta = rama_cfg$ruta,
    tipo_rama = rama_cfg$tipo,
    fecha_inicio = ahora_colombia(),
    fecha_fin = NA_character_,
    n_reportado = NA_integer_,
    n_paginas = 0L,
    paginas = list()
  )

  todas <- list()
  desde <- 0L
  pagina <- 1L
  repeat {
    if (pagina > max_paginas) break
    hasta <- desde + TAMANO_PAGINA - 1L
    if (verboso) message(sprintf("  [%s] %s página %d (%d-%d)", cfg$nombre, rama_cfg$nombre, pagina, desde, hasta))

    res <- leer_pagina(id_comercio, rama_cfg, desde, hasta)
    fecha_consulta <- ahora_colombia()
    if (is.na(meta$n_reportado) && !is.na(res$total)) meta$n_reportado <- res$total

    meta_pagina <- list(
      numero = pagina,
      url = res$url,
      desde = desde,
      hasta = hasta,
      fecha_consulta = fecha_consulta,
      n_reportado = res$total,
      n = length(res$datos),
      status = res$status
    )
    meta$paginas[[pagina]] <- guardar_pagina_raw(dir_rama, pagina, res$texto, meta_pagina)
    meta$n_paginas <- pagina

    if (length(res$datos) == 0) break
    filas <- purrr::map_dfr(
      res$datos,
      parsear_producto,
      id_comercio = id_comercio,
      rama = rama_cfg$nombre,
      tipo_rama = rama_cfg$tipo,
      fecha_consulta = fecha_consulta
    )
    todas[[pagina]] <- filas

    if (length(res$datos) < TAMANO_PAGINA) break
    if (!is.na(res$total) && (desde + length(res$datos)) >= res$total) break

    desde <- desde + TAMANO_PAGINA
    pagina <- pagina + 1L
    Sys.sleep(ESPERA_ENTRE_PAGINAS)
  }

  meta$fecha_fin <- ahora_colombia()
  jsonlite::write_json(meta, file.path(dir_rama, "metadata.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")

  datos <- if (length(todas) > 0) bind_rows(todas) else tibble()
  list(datos = datos, meta = meta, descartes = tibble())
}

# -----------------------------------------------------------------------------
# 6. Lectura offline de las copias crudas
# -----------------------------------------------------------------------------

leer_rama_offline <- function(id_comercio, rama_cfg, id_ejecucion, fecha_ejecucion) {
  cfg <- COMERCIOS[[id_comercio]]
  dir_rama <- file.path(RUTA_RAW, id_comercio, fecha_ejecucion, id_ejecucion,
                        slugify(rama_cfg$nombre))
  ruta_meta <- file.path(dir_rama, "metadata.json")
  if (!file.exists(ruta_meta)) {
    stop("No existe la copia cruda de ", cfg$nombre, " / ", rama_cfg$nombre,
         " en ", dir_rama)
  }
  meta <- jsonlite::fromJSON(ruta_meta, simplifyVector = FALSE)

  todas <- list()
  for (p in meta$paginas) {
    archivo <- file.path(dir_rama, p$archivo)
    con <- gzfile(archivo, "rt", encoding = "UTF-8")
    texto <- paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    close(con)
    datos <- jsonlite::fromJSON(texto, simplifyVector = FALSE)
    filas <- purrr::map_dfr(
      datos,
      parsear_producto,
      id_comercio = id_comercio,
      rama = meta$rama,
      tipo_rama = meta$tipo_rama,
      fecha_consulta = p$fecha_consulta
    )
    todas[[length(todas) + 1L]] <- filas
  }

  datos <- if (length(todas) > 0) bind_rows(todas) else tibble()
  list(datos = datos, meta = meta, descartes = tibble())
}

encontrar_fecha_raw <- function(id_comercio, id_ejecucion) {
  base <- file.path(RUTA_RAW, id_comercio)
  if (!dir.exists(base)) return(NA_character_)
  fechas <- list.dirs(base, recursive = FALSE, full.names = FALSE)
  for (f in fechas) {
    if (dir.exists(file.path(base, f, id_ejecucion))) return(f)
  }
  NA_character_
}

# -----------------------------------------------------------------------------
# 7. Extracción de un comercio completo (todas las ramas)
# -----------------------------------------------------------------------------

extraer_comercio <- function(id_comercio, id_ejecucion, offline = FALSE,
                             fecha_ejecucion = NULL, max_paginas = Inf,
                             verboso = TRUE, id_origen = id_ejecucion) {
  cfg <- COMERCIOS[[id_comercio]]
  datos_ramas <- list()
  descartes <- list()
  metas <- list()

  for (i in seq_along(cfg$ramas)) {
    rama_cfg <- cfg$ramas[[i]]
    if (verboso) message(sprintf("\n[%s] Rama %d/%d: %s", cfg$nombre, i, length(cfg$ramas), rama_cfg$nombre))
    res <- tryCatch(
      if (offline) {
        leer_rama_offline(id_comercio, rama_cfg, id_origen, fecha_ejecucion)
      } else {
        extraer_rama_online(id_comercio, rama_cfg, id_ejecucion, fecha_ejecucion,
                            max_paginas = max_paginas, verboso = verboso)
      },
      error = function(e) {
        message("  ERROR en rama ", rama_cfg$nombre, ": ", conditionMessage(e))
        list(datos = tibble(), meta = list(
          id_ejecucion = id_ejecucion, id_comercio = id_comercio, comercio = cfg$nombre,
          rama = rama_cfg$nombre, ruta = rama_cfg$ruta, tipo_rama = rama_cfg$tipo,
          fecha_inicio = ahora_colombia(), fecha_fin = ahora_colombia(),
          n_reportado = NA_integer_, n_paginas = 0L, paginas = list(),
          error = conditionMessage(e)
        ), descartes = tibble())
      }
    )

    if (nrow(res$datos) > 0) {
      res$datos$prioridad <- i
      datos_ramas[[length(datos_ramas) + 1L]] <- res$datos
    }
    metas[[length(metas) + 1L]] <- res$meta
    if (nrow(res$descartes) > 0) descartes[[length(descartes) + 1L]] <- res$descartes
  }

  datos <- if (length(datos_ramas) > 0) bind_rows(datos_ramas) else tibble()
  meta_df <- purrr::map_dfr(metas, function(m) {
    tibble::tibble(
      id_comercio = m$id_comercio,
      rama = m$rama,
      url_categoria = paste0("https://", COMERCIOS[[m$id_comercio]]$host,
                             "/api/catalog_system/pub/products/search/",
                             codificar_ruta(m$ruta)),
      n_reportado = as.integer(m$n_reportado %||% NA_integer_),
      n_extraido = as.integer(m$n_paginas * TAMANO_PAGINA),
      n_incluido = NA_integer_,
      n_excluido = NA_integer_,
      n_paginas = as.integer(m$n_paginas %||% 0L),
      estado = if (!is.null(m$error)) "fallida" else "completa"
    )
  })

  if (nrow(datos) == 0) {
    return(list(datos = tibble(), descartes = tibble(), meta = meta_df,
                n_extraido = 0L, n_incluido = 0L, n_excluido = 0L, n_con_precio = 0L))
  }

  # Deduplicar productos que aparecen en más de una rama (mismo productId).
  datos <- datos[order(datos$prioridad), ]
  duplicados <- duplicated(datos$id_producto_comercio)
  if (any(duplicados)) {
    desc_dup <- datos[duplicados, , drop = FALSE] %>%
      transmute(
        id_comercio = id_comercio,
        sku_comercio = sku_comercio,
        texto_original = texto_original,
        motivo = "duplicado_categoria",
        detalle = paste0("También aparecía en la rama ", rama, "; se conservó la primera.")
      )
    descartes[[length(descartes) + 1L]] <- desc_dup
    datos <- datos[!duplicados, , drop = FALSE]
  }

  # Aplicar reglas de exclusión de la delimitación de la categoría.
  motivos <- mapply(
    evaluar_exclusion,
    texto = datos$texto_original,
    marca = datos$marca,
    rama = datos$rama,
    tipo_rama = datos$tipo_rama,
    USE.NAMES = FALSE
  )
  datos$motivo_exclusion <- motivos

  excluidos <- datos[!is.na(datos$motivo_exclusion), , drop = FALSE]
  incluidos <- datos[is.na(datos$motivo_exclusion), , drop = FALSE]

  if (nrow(excluidos) > 0) {
    desc_exc <- excluidos %>%
      transmute(
        id_comercio = id_comercio,
        sku_comercio = sku_comercio,
        texto_original = texto_original,
        motivo = motivo_exclusion,
        detalle = paste0("Rama: ", rama, " | Categoría del sitio: ", categoria_sitio)
      )
    descartes[[length(descartes) + 1L]] <- desc_exc
  }

  # Completar conteos por rama con lo efectivamente incluido/excluido.
  for (i in seq_len(nrow(meta_df))) {
    r <- meta_df$rama[i]
    meta_df$n_extraido[i] <- sum(datos$rama == r)
    meta_df$n_incluido[i] <- sum(incluidos$rama == r)
    meta_df$n_excluido[i] <- sum(excluidos$rama == r)
  }

  descartes_df <- if (length(descartes) > 0) bind_rows(descartes) else tibble()

  list(
    datos = incluidos,
    descartes = descartes_df,
    meta = meta_df,
    n_extraido = nrow(datos),
    n_incluido = nrow(incluidos),
    n_excluido = nrow(excluidos),
    n_con_precio = sum(incluidos$disponible == 1, na.rm = TRUE)
  )
}

# -----------------------------------------------------------------------------
# 8. Base de datos: creación, inserción y ejecuciones
# -----------------------------------------------------------------------------

ejecutar_sql_script <- function(con, ruta) {
  lineas <- readLines(ruta, warn = FALSE, encoding = "UTF-8")
  lineas <- lineas[!grepl("^\\s*--", lineas)]
  sql <- paste(lineas, collapse = "\n")
  sentencias <- strsplit(sql, ";", fixed = TRUE)[[1]]
  for (s in sentencias) {
    s <- trimws(s)
    if (nzchar(s)) dbExecute(con, s)
  }
}

crear_esquema <- function(con, ruta_esquema = RUTA_ESQUEMA, ruta_vistas = RUTA_VISTAS) {
  if (!file.exists(ruta_esquema)) stop("No se encontró el esquema: ", ruta_esquema)
  if (!file.exists(ruta_vistas)) stop("No se encontraron las vistas: ", ruta_vistas)
  ejecutar_sql_script(con, ruta_esquema)
  migrar_esquema(con)
  ejecutar_sql_script(con, ruta_vistas)
  invisible(TRUE)
}

columna_existe <- function(con, tabla, columna) {
  columna %in% dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tabla))$name
}

agregar_columna <- function(con, tabla, columna, definicion) {
  if (columna_existe(con, tabla, columna)) return(FALSE)
  dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s %s", tabla, columna, definicion))
  TRUE
}

# Reconstruye observaciones sin la restricción UNIQUE heredada del Taller 1
# (id_comercio, sku_comercio, fecha_consulta). Esa restricción impide reprocesar
# una copia cruda en una ejecución nueva con la misma hora de consulta; la
# unicidad por ejecución se conserva en ux_observaciones_ejecucion_anuncio.
reconstruir_observaciones <- function(con, ruta_migracion = file.path("db", "migracion_observaciones.sql")) {
  indices <- dbGetQuery(con, "PRAGMA index_list(observaciones)")
  if (!any(grepl("^sqlite_autoindex_observaciones", indices$name))) return(FALSE)
  if (!file.exists(ruta_migracion)) stop("No se encontró la migración: ", ruta_migracion)

  cols <- dbGetQuery(con, "PRAGMA table_info(observaciones)")$name
  vistas <- dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'view'")$name
  for (v in vistas) dbExecute(con, sprintf("DROP VIEW IF EXISTS %s", v))
  dbExecute(con, "PRAGMA foreign_keys = OFF")
  dbBegin(con)
  ejecutar_sql_script(con, ruta_migracion)
  dbExecute(con, sprintf(
    "INSERT INTO observaciones_nueva (%s) SELECT %s FROM observaciones",
    paste(cols, collapse = ", "), paste(cols, collapse = ", ")))
  dbExecute(con, "DROP TABLE observaciones")
  dbExecute(con, "ALTER TABLE observaciones_nueva RENAME TO observaciones")
  dbCommit(con)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  ejecutar_sql_script(con, RUTA_ESQUEMA)
  ejecutar_sql_script(con, RUTA_VISTAS)
  message("observaciones reconstruida sin la restricción UNIQUE heredada.")
  TRUE
}

# Aplica los cambios del Taller 2 sobre una base creada con el esquema del
# Taller 1. Es idempotente: se puede ejecutar en cada apertura de la base.
migrar_esquema <- function(con) {
  nuevos <- c(
    agregar_columna(con, "comercios", "activo", "INTEGER NOT NULL DEFAULT 1"),
    agregar_columna(con, "comercios", "motivo_estado", "TEXT"),
    agregar_columna(con, "productos_comparables", "contenido_total", "REAL"),
    agregar_columna(con, "productos_comparables", "unidad_normalizada", "TEXT"),
    agregar_columna(con, "productos_comparables", "vigente", "INTEGER NOT NULL DEFAULT 1"),
    agregar_columna(con, "observaciones", "contenido_total", "REAL"),
    agregar_columna(con, "observaciones", "unidad_normalizada", "TEXT"),
    agregar_columna(
      con, "observaciones", "estado_disponibilidad",
      "TEXT NOT NULL DEFAULT 'no_observado' CHECK (estado_disponibilidad IN ('disponible', 'agotado', 'no_observado'))"
    )
  )

  dbExecute(con, "
    UPDATE observaciones
       SET estado_disponibilidad = CASE WHEN disponible = 1 THEN 'disponible' ELSE 'agotado' END
     WHERE estado_disponibilidad = 'no_observado'")

  dbExecute(con, "
    UPDATE observaciones
       SET contenido_total = contenido_valor,
           unidad_normalizada = CASE contenido_unidad
                                  WHEN 'g' THEN 'g' WHEN 'ml' THEN 'mL'
                                  WHEN 'unidad' THEN 'unidad' END
     WHERE contenido_total IS NULL")

  dbExecute(con, "
    UPDATE productos_comparables
       SET contenido_total = contenido_valor,
           unidad_normalizada = CASE contenido_unidad
                                  WHEN 'g' THEN 'g' WHEN 'ml' THEN 'mL'
                                  WHEN 'unidad' THEN 'unidad' END
     WHERE contenido_total IS NULL")

  reconstruir_observaciones(con)
  invisible(sum(nuevos))
}

registrar_comercios <- function(con) {
  for (cfg in COMERCIOS) {
    dbExecute(
      con,
      "INSERT INTO comercios
         (id_comercio, nombre, url_base, grupo, categoria_equivalente, robots_url,
          activo, motivo_estado, notas)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id_comercio) DO UPDATE SET
         nombre = excluded.nombre,
         url_base = excluded.url_base,
         grupo = excluded.grupo,
         categoria_equivalente = excluded.categoria_equivalente,
         robots_url = excluded.robots_url,
         activo = excluded.activo,
         motivo_estado = excluded.motivo_estado,
         notas = excluded.notas",
      params = list(
        cfg$id_comercio, cfg$nombre, paste0("https://", cfg$host), cfg$grupo,
        cfg$categoria_equivalente, cfg$robots_url, as.integer(isTRUE(cfg$activo)),
        cfg$motivo_estado %||% NA_character_,
        "Consulta a la API pública de catálogo (VTEX) que alimenta la vitrina."
      )
    )
  }
}

columnas_observacion <- c(
  "id_ejecucion", "id_comercio", "id_producto_comercio", "sku_comercio",
  "texto_original", "descripcion_original", "especificaciones_json", "marca",
  "categoria_sitio", "subcategoria", "contenido_valor", "contenido_unidad",
  "contenido_total", "unidad_normalizada", "contenido_origen",
  "unidades_por_paquete", "empaque_mencionado", "precio_cop", "precio_lista_cop",
  "es_promocion", "descuento_pct", "disponible", "estado_disponibilidad",
  "precio_por_unidad", "unidad_precio", "url_producto", "fecha_consulta",
  "id_producto_comun", "es_comparable"
)

insertar_rechazadas <- function(con, rechazadas, id_ejecucion) {
  if (is.null(rechazadas) || nrow(rechazadas) == 0) return(0L)
  rechazadas$id_ejecucion <- id_ejecucion
  rechazadas$fecha <- ahora_colombia()
  cols <- c("fecha", "id_ejecucion", "id_comercio", "sku_comercio",
            "texto_original", "precio_cop", "motivo", "detalle")
  dbAppendTable(con, "observaciones_rechazadas", rechazadas[, cols, drop = FALSE])
  nrow(rechazadas)
}

# Valida y guarda las observaciones de un comercio. La transacción la maneja
# ejecutar_recoleccion(); aquí no se abre ni se cierra.
insertar_observaciones <- function(con, datos, id_ejecucion) {
  vacio <- list(n_insertados = 0L, n_rechazados = 0L)
  if (nrow(datos) == 0) return(vacio)

  datos$id_ejecucion <- id_ejecucion
  datos$id_producto_comun <- NA_character_
  datos$es_comparable <- 0L

  # Una sola fila por SKU dentro de la ejecución (la primera página consultada).
  datos <- datos[!duplicated(datos$sku_comercio), , drop = FALSE]
  datos <- datos[, columnas_observacion, drop = FALSE]

  datos$contenido_valor <- as.numeric(datos$contenido_valor)
  datos$contenido_total <- as.numeric(datos$contenido_total)
  datos$precio_cop <- as.numeric(datos$precio_cop)
  datos$precio_lista_cop <- as.numeric(datos$precio_lista_cop)
  datos$precio_por_unidad <- as.numeric(datos$precio_por_unidad)
  datos$es_promocion <- as.integer(datos$es_promocion)
  datos$disponible <- as.integer(datos$disponible)
  datos$es_comparable <- as.integer(datos$es_comparable)
  datos$unidades_por_paquete <- as.integer(datos$unidades_por_paquete)
  datos$empaque_mencionado <- as.integer(datos$empaque_mencionado)

  if (!exists("validar_observaciones", mode = "function")) source("validacion.R")
  validacion <- validar_observaciones(datos, con = con, id_ejecucion = id_ejecucion)

  n_rechazados <- insertar_rechazadas(con, validacion$rechazadas, id_ejecucion)
  datos <- validacion$validas
  if (nrow(datos) == 0) return(list(n_insertados = 0L, n_rechazados = n_rechazados))

  dbAppendTable(con, "observaciones", datos)
  list(n_insertados = nrow(datos), n_rechazados = n_rechazados)
}

insertar_descartes <- function(con, descartes, id_ejecucion) {
  if (is.null(descartes) || nrow(descartes) == 0) return(0L)
  descartes$id_ejecucion <- id_ejecucion
  descartes$fecha_registro <- ahora_colombia()
  cols <- c("id_ejecucion", "id_comercio", "sku_comercio", "texto_original",
            "motivo", "detalle", "fecha_registro")
  descartes <- descartes[, cols, drop = FALSE]
  dbAppendTable(con, "descartes", descartes)
  nrow(descartes)
}

insertar_meta_categorias <- function(con, meta, id_ejecucion) {
  if (is.null(meta) || nrow(meta) == 0) return(0L)
  meta$id_ejecucion <- id_ejecucion
  cols <- c("id_ejecucion", "id_comercio", "rama", "url_categoria", "n_reportado",
            "n_extraido", "n_incluido", "n_excluido", "n_paginas", "estado")
  meta <- meta[, cols, drop = FALSE]
  dbAppendTable(con, "ejecuciones_categoria", meta)
  nrow(meta)
}

# -----------------------------------------------------------------------------
# 9. Correspondencia manual de productos comparables
# -----------------------------------------------------------------------------

leer_mapeo <- function(ruta = RUTA_MAPEO) {
  if (!file.exists(ruta)) return(NULL)
  m <- readr::read_csv(
    ruta,
    show_col_types = FALSE,
    locale = readr::locale(encoding = "UTF-8"),
    col_types = readr::cols(sku_comercio = readr::col_character(), .default = readr::col_guess())
  )
  requeridas <- c("id_producto_comun", "nombre_canonico", "marca", "variante",
                  "contenido_valor", "contenido_unidad", "subcategoria",
                  "id_comercio", "sku_comercio", "nombre_comercio", "regla", "confianza")
  faltantes <- setdiff(requeridas, names(m))
  if (length(faltantes) > 0) {
    stop("Faltan columnas en el mapeo: ", paste(faltantes, collapse = ", "))
  }
  m
}

aplicar_mapeo <- function(con, id_ejecucion, ruta_mapeo = RUTA_MAPEO,
                          comercios_esperados = comercios_activos()) {
  m <- leer_mapeo(ruta_mapeo)
  if (is.null(m) || nrow(m) == 0) {
    message("No hay archivo de mapeo; la ejecución queda sin productos comparables.")
    return(invisible(NULL))
  }

  fecha <- ahora_colombia()

  # 1. Catálogo canónico
  productos <- m %>%
    distinct(id_producto_comun, .keep_all = TRUE) %>%
    transmute(
      id_producto_comun, nombre_canonico, marca, variante,
      contenido_valor = as.numeric(contenido_valor),
      contenido_unidad,
      contenido_total = as.numeric(contenido_valor),
      unidad_normalizada = dplyr::case_when(
        contenido_unidad == "g" ~ "g",
        contenido_unidad == "ml" ~ "mL",
        contenido_unidad == "unidad" ~ "unidad",
        TRUE ~ NA_character_
      ),
      subcategoria,
      unidad_base = contenido_unidad,
      justificacion = paste0(
        "Misma marca, variante y contenido. ",
        "Correspondencia manual verificada contra el texto original de cada comercio."
      ),
      fecha_creacion = fecha
    )
  # Upsert: la misma correspondencia se reutiliza en ejecuciones posteriores.
  for (i in seq_len(nrow(productos))) {
    dbExecute(con, "
      INSERT INTO productos_comparables
        (id_producto_comun, nombre_canonico, marca, variante, contenido_valor,
         contenido_unidad, contenido_total, unidad_normalizada, subcategoria,
         unidad_base, justificacion, fecha_creacion)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id_producto_comun) DO UPDATE SET
        nombre_canonico = excluded.nombre_canonico,
        marca = excluded.marca,
        variante = excluded.variante,
        contenido_valor = excluded.contenido_valor,
        contenido_unidad = excluded.contenido_unidad,
        contenido_total = excluded.contenido_total,
        unidad_normalizada = excluded.unidad_normalizada,
        subcategoria = excluded.subcategoria,
        unidad_base = excluded.unidad_base,
        justificacion = excluded.justificacion",
      params = unname(as.list(productos[i, ])))
  }

  # 2. Mapeo SKU -> producto canónico
  mapeo <- m %>%
    transmute(
      id_producto_comun, id_comercio, sku_comercio = as.character(sku_comercio),
      nombre_comercio, regla, confianza = as.character(confianza),
      validado_por = "Carlos Ernesto Araujo Romero",
      fecha_validacion = fecha
    )
  # Un producto está vigente solo si tiene correspondencia en todos los
  # comercios activos de esta ejecución.
  activos <- comercios_activos()
  con_mapeo <- mapeo %>%
    filter(id_comercio %in% activos) %>%
    count(id_producto_comun) %>%
    filter(n == length(activos)) %>%
    pull(id_producto_comun)
  vigente <- as.integer(productos$id_producto_comun %in% con_mapeo)
  dbExecute(con, "UPDATE productos_comparables SET vigente = 0")
  for (i in seq_len(nrow(productos))) {
    dbExecute(con, "UPDATE productos_comparables SET vigente = ? WHERE id_producto_comun = ?",
              params = list(vigente[i], productos$id_producto_comun[i]))
  }

  for (i in seq_len(nrow(mapeo))) {
    dbExecute(con, "
      INSERT INTO mapeo_productos
        (id_producto_comun, id_comercio, sku_comercio, nombre_comercio, regla,
         confianza, validado_por, fecha_validacion)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id_producto_comun, id_comercio, sku_comercio) DO UPDATE SET
        nombre_comercio = excluded.nombre_comercio,
        regla = excluded.regla,
        confianza = excluded.confianza,
        validado_por = excluded.validado_por,
        fecha_validacion = excluded.fecha_validacion",
      params = unname(as.list(mapeo[i, ])))
  }

  # 3. Resetear y aplicar solo los productos vigentes (correspondencia en
  # todos los comercios activos). Los demás conservan su correspondencia
  # histórica en mapeo_productos, pero no se marcan como comparables.
  dbExecute(con, "UPDATE observaciones SET id_producto_comun = NULL, es_comparable = 0
                  WHERE id_ejecucion = ?", params = list(id_ejecucion))

  mapeo_aplicable <- mapeo[mapeo$id_producto_comun %in% con_mapeo, , drop = FALSE]
  actualizados <- 0L
  dbBegin(con)
  for (i in seq_len(nrow(mapeo_aplicable))) {
    actualizados <- actualizados + dbExecute(
      con,
      "UPDATE observaciones
          SET id_producto_comun = ?, es_comparable = 1
        WHERE id_ejecucion = ? AND id_comercio = ? AND sku_comercio = ?",
      params = list(mapeo_aplicable$id_producto_comun[i], id_ejecucion,
                    mapeo_aplicable$id_comercio[i], mapeo_aplicable$sku_comercio[i])
    )
  }
  dbCommit(con)

  # 4. Si un SKU aparece más de una vez (no debería), conservar el más barato.
  dups <- dbGetQuery(con, "
    SELECT id_comercio, id_producto_comun, COUNT(*) AS n
      FROM observaciones
     WHERE id_ejecucion = ? AND es_comparable = 1
     GROUP BY id_comercio, id_producto_comun
    HAVING COUNT(*) > 1", params = list(id_ejecucion))
  if (nrow(dups) > 0) {
    for (i in seq_len(nrow(dups))) {
      filas <- dbGetQuery(con, "
        SELECT id_observacion
          FROM observaciones
         WHERE id_ejecucion = ? AND id_comercio = ? AND id_producto_comun = ?
         ORDER BY (precio_cop IS NULL), precio_cop ASC, id_observacion ASC",
        params = list(id_ejecucion, dups$id_comercio[i], dups$id_producto_comun[i]))
      conservar <- filas$id_observacion[1]
      dbExecute(con, "
        UPDATE observaciones SET es_comparable = 0
         WHERE id_ejecucion = ? AND id_comercio = ? AND id_producto_comun = ?
           AND id_observacion <> ?",
        params = list(id_ejecucion, dups$id_comercio[i], dups$id_producto_comun[i], conservar))
    }
  }

  # 5. Validar cobertura completa (todos los comercios esperados con precio).
  cobertura <- dbGetQuery(con, "
    SELECT id_producto_comun,
           COUNT(DISTINCT CASE WHEN es_comparable = 1 AND estado_disponibilidad = 'disponible'
                               THEN id_comercio END) AS n_comercios
      FROM observaciones
     WHERE id_ejecucion = ?
     GROUP BY id_producto_comun", params = list(id_ejecucion))
  incompletos <- intersect(
    cobertura$id_producto_comun[
      !is.na(cobertura$id_producto_comun) &
        cobertura$n_comercios < length(comercios_esperados)
    ],
    con_mapeo
  )
  if (length(incompletos) > 0) {
    for (p in incompletos) {
      dbExecute(con, "UPDATE observaciones SET es_comparable = 0
                      WHERE id_ejecucion = ? AND id_producto_comun = ?",
                params = list(id_ejecucion, p))
      dbExecute(con, "INSERT INTO descartes
        (id_ejecucion, id_comercio, sku_comercio, texto_original, motivo, detalle, fecha_registro)
        VALUES (?, NULL, NULL, NULL, 'cobertura_incompleta', ?, ?)",
        params = list(id_ejecucion, paste("El producto", p, "no tiene precio en los tres comercios."), fecha))
    }
  }

  message(sprintf("Mapeo aplicado: %d filas actualizadas; %d productos incompletos.",
                  actualizados, length(incompletos)))
  invisible(list(actualizados = actualizados, incompletos = incompletos))
}

# Reaplica la correspondencia y cierra una ejecución ya insertada. Sirve
# cuando se corrige mapeo_productos.csv sin volver a consultar los sitios.
reaplicar_correspondencia <- function(id_ejecucion, ruta_db = RUTA_DB_POR_DEFECTO,
                                      ruta_mapeo = RUTA_MAPEO) {
  con <- dbConnect(SQLite(), ruta_db)
  on.exit(dbDisconnect(con), add = TRUE)
  comercios <- dbGetQuery(con,
    "SELECT DISTINCT id_comercio FROM observaciones WHERE id_ejecucion = ?",
    params = list(id_ejecucion))$id_comercio
  aplicar_mapeo(con, id_ejecucion, ruta_mapeo = ruta_mapeo,
                comercios_esperados = intersect(comercios, comercios_activos()))
  cierre <- actualizar_ejecucion(con, id_ejecucion)
  invisible(cierre)
}

# -----------------------------------------------------------------------------
# 10. Cierre y verificación de una ejecución
# -----------------------------------------------------------------------------

actualizar_ejecucion <- function(con, id_ejecucion, n_comercios_esperados = length(comercios_activos())) {
  tot <- dbGetQuery(con, "
    SELECT COUNT(*) AS n_registros,
           COALESCE(SUM(CASE WHEN es_comparable = 1 THEN 1 ELSE 0 END), 0) AS n_obs_comparables,
           COUNT(DISTINCT CASE WHEN es_comparable = 1 THEN id_producto_comun END) AS n_productos_comparables,
           COUNT(DISTINCT id_comercio) AS n_comercios
      FROM observaciones
     WHERE id_ejecucion = ?", params = list(id_ejecucion))
  n_registros <- as.integer(tot$n_registros[1] %||% 0)
  n_obs <- as.integer(tot$n_obs_comparables[1] %||% 0)
  n_prod <- as.integer(tot$n_productos_comparables[1] %||% 0)
  n_com <- as.integer(tot$n_comercios[1] %||% 0)

  estado <- if (n_registros == 0) {
    "fallida"
  } else if (n_com >= n_comercios_esperados && n_prod >= 8 && n_obs >= 24) {
    "completa"
  } else {
    "parcial"
  }

  dbExecute(con, "
    UPDATE ejecuciones
       SET fecha_fin = ?, estado = ?, n_registros = ?,
           n_obs_comparables = ?, n_productos_comparables = ?, n_comercios = ?
     WHERE id_ejecucion = ?",
    params = list(ahora_colombia(), estado, n_registros, n_obs, n_prod, n_com, id_ejecucion))

  invisible(list(estado = estado, n_registros = n_registros,
                 n_obs_comparables = n_obs, n_productos_comparables = n_prod,
                 n_comercios = n_com))
}

verificar_cobertura <- function(con, id_ejecucion) {
  activos <- dbGetQuery(con, "SELECT id_comercio FROM comercios WHERE activo = 1 ORDER BY id_comercio")
  casos <- paste0(
    "MAX(CASE WHEN o.id_comercio = '", activos$id_comercio,
    "' AND o.es_comparable = 1 AND o.estado_disponibilidad = 'disponible' THEN o.precio_cop END) AS ",
    activos$id_comercio,
    collapse = ",\n           "
  )
  dbGetQuery(
    con,
    sprintf("
      SELECT p.id_producto_comun, p.nombre_canonico, p.subcategoria,
             %s,
             COUNT(DISTINCT CASE WHEN o.es_comparable = 1
                                  AND o.estado_disponibilidad = 'disponible'
                                 THEN o.id_comercio END) AS n_comercios
        FROM productos_comparables p
        LEFT JOIN observaciones o
          ON o.id_producto_comun = p.id_producto_comun
         AND o.id_ejecucion = ?
       GROUP BY p.id_producto_comun, p.nombre_canonico, p.subcategoria
       ORDER BY p.id_producto_comun", casos),
    params = list(id_ejecucion)
  )
}

# Comercios que tienen copias crudas de una ejecución concreta.
comercios_con_raw <- function(id_ejecucion) {
  if (!dir.exists(RUTA_RAW)) return(character(0))
  com <- list.dirs(RUTA_RAW, recursive = FALSE, full.names = FALSE)
  com[vapply(com, function(x) {
    any(grepl(id_ejecucion, list.dirs(file.path(RUTA_RAW, x), recursive = TRUE, full.names = FALSE),
              fixed = TRUE))
  }, logical(1))]
}

registrar_correccion <- function(con, tabla, campo, id_registro, valor_anterior,
                                 valor_nuevo, motivo, id_ejecucion = NULL,
                                 autor = "Carlos Ernesto Araujo Romero") {
  if (is.null(id_ejecucion)) id_ejecucion <- NA_character_
  dbExecute(con, "
    INSERT INTO correcciones
      (fecha, tabla, campo, id_registro, valor_anterior, valor_nuevo, motivo,
       id_ejecucion, autor)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(ahora_colombia(), tabla, campo, id_registro,
                  as.character(valor_anterior), as.character(valor_nuevo),
                  motivo, id_ejecucion, autor))
}

# -----------------------------------------------------------------------------
# 11. Función general de recolección
# -----------------------------------------------------------------------------

ejecutar_recoleccion <- function(offline = FALSE,
                                 ruta_db = RUTA_DB_POR_DEFECTO,
                                 id_ejecucion = NULL,
                                 id_origen = NULL,
                                 comercios = NULL,
                                 fecha_ejecucion = NULL,
                                 max_paginas = Inf,
                                 aplicar_correspondencia = TRUE,
                                 ruta_mapeo = RUTA_MAPEO,
                                 verboso = TRUE) {
  con <- dbConnect(SQLite(), ruta_db)
  dbExecute(con, "PRAGMA busy_timeout = 15000")
  on.exit(dbDisconnect(con), add = TRUE)

  crear_esquema(con)
  registrar_comercios(con)

  if (is.null(id_ejecucion)) id_ejecucion <- nuevo_id_ejecucion()
  ya_existe <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM ejecuciones WHERE id_ejecucion = ?",
                          params = list(id_ejecucion))$n[1]
  if (ya_existe > 0) stop("La ejecución ", id_ejecucion, " ya existe en la base.")

  if (is.null(id_origen)) id_origen <- id_ejecucion
  if (offline) {
    if (is.null(comercios)) comercios <- comercios_con_raw(id_origen)
    if (length(comercios) == 0) stop("No se encontraron copias crudas para ", id_origen)
    if (is.null(fecha_ejecucion)) {
      fechas <- vapply(comercios, function(c) encontrar_fecha_raw(c, id_origen), character(1))
      fechas <- unique(fechas[!is.na(fechas)])
      if (length(fechas) == 0) stop("No se encontraron copias crudas para ", id_ejecucion)
      fecha_ejecucion <- fechas[1]
    }
  } else {
    if (is.null(comercios)) comercios <- comercios_activos()
    if (is.null(fecha_ejecucion)) fecha_ejecucion <- fecha_colombia()
  }

  modo <- if (offline) "offline" else "online"
  dbExecute(con, "
    INSERT INTO ejecuciones
      (id_ejecucion, fecha_inicio, fecha_fin, modo, estado, n_registros,
       n_obs_comparables, n_productos_comparables, n_comercios, notas)
    VALUES (?, ?, NULL, ?, 'en_curso', 0, 0, 0, 0, ?)",
    params = list(id_ejecucion, ahora_colombia(), modo,
                  paste0("Comercios: ", paste(comercios, collapse = ", "),
                         if (offline) paste0(" | reprocesado desde ", id_origen) else "")))

  resumen_comercios <- list()

  for (id_comercio in comercios) {
    cfg <- COMERCIOS[[id_comercio]]
    if (verboso) message("\n=== ", cfg$nombre, " ===")
    dbExecute(con, "
      INSERT INTO ejecuciones_comercio (id_ejecucion, id_comercio, fecha_inicio, estado)
      VALUES (?, ?, ?, 'en_curso')",
      params = list(id_ejecucion, id_comercio, ahora_colombia()))

    res <- tryCatch(
      extraer_comercio(id_comercio, id_ejecucion, offline = offline,
                       fecha_ejecucion = fecha_ejecucion,
                       max_paginas = max_paginas, verboso = verboso,
                       id_origen = id_origen),
      error = function(e) {
        message("ERROR extrayendo ", cfg$nombre, ": ", conditionMessage(e))
        NULL
      }
    )

    if (is.null(res)) {
      dbExecute(con, "UPDATE ejecuciones_comercio
                         SET fecha_fin = ?, estado = 'fallida', mensaje = ?
                       WHERE id_ejecucion = ? AND id_comercio = ?",
                params = list(ahora_colombia(), "Error durante la extracción",
                              id_ejecucion, id_comercio))
      resumen_comercios[[id_comercio]] <- tibble::tibble(
        comercio = cfg$nombre, n_extraido = 0L, n_incluido = 0L,
        n_excluido = 0L, n_con_precio = 0L, n_insertados = 0L, n_rechazados = 0L)
      next
    }

    estado_com <- if (nrow(res$datos) == 0) {
      "fallida"
    } else if (all(res$meta$estado == "completa")) {
      "completa"
    } else {
      "parcial"
    }

    ins <- list(n_insertados = 0L, n_rechazados = 0L)
    exito <- tryCatch({
      dbBegin(con)
      ins <- insertar_observaciones(con, res$datos, id_ejecucion)
      insertar_descartes(con, res$descartes, id_ejecucion)
      insertar_meta_categorias(con, res$meta, id_ejecucion)
      dbExecute(con, "
        UPDATE ejecuciones_comercio
           SET fecha_fin = ?, n_paginas = ?, n_reportado_sitio = ?,
               n_extraido = ?, n_incluido = ?, n_excluido = ?, n_con_precio = ?,
               estado = ?, url_categoria = ?, mensaje = ?
         WHERE id_ejecucion = ? AND id_comercio = ?",
        params = list(
          ahora_colombia(), sum(res$meta$n_paginas, na.rm = TRUE),
          sum(res$meta$n_reportado, na.rm = TRUE),
          res$n_extraido, res$n_incluido, res$n_excluido, res$n_con_precio,
          estado_com, paste(res$meta$url_categoria, collapse = " | "),
          paste0("Ramas consultadas: ", nrow(res$meta),
                 "; rechazadas por validación: ", ins$n_rechazados),
          id_ejecucion, id_comercio))
      dbCommit(con)
      TRUE
    }, error = function(e) {
      try(dbRollback(con), silent = TRUE)
      message("  Falló la inserción de ", cfg$nombre, ": ", conditionMessage(e))
      FALSE
    })

    if (!exito) {
      dbExecute(con, "UPDATE ejecuciones_comercio
                         SET fecha_fin = ?, estado = 'fallida', mensaje = ?
                       WHERE id_ejecucion = ? AND id_comercio = ?",
                params = list(ahora_colombia(), "Error al insertar en SQLite",
                              id_ejecucion, id_comercio))
      estado_com <- "fallida"
    }

    resumen_comercios[[id_comercio]] <- tibble::tibble(
      comercio = cfg$nombre,
      n_extraido = res$n_extraido,
      n_incluido = res$n_incluido,
      n_excluido = res$n_excluido,
      n_con_precio = res$n_con_precio,
      n_insertados = ins$n_insertados,
      n_rechazados = ins$n_rechazados
    )
  }

  if (isTRUE(aplicar_correspondencia)) {
    aplicar_mapeo(con, id_ejecucion, ruta_mapeo = ruta_mapeo,
                  comercios_esperados = intersect(comercios, comercios_activos()))
  }

  cierre <- actualizar_ejecucion(con, id_ejecucion)
  cobertura <- if (isTRUE(aplicar_correspondencia)) verificar_cobertura(con, id_ejecucion) else tibble()

  list(
    id_ejecucion = id_ejecucion,
    modo = modo,
    fecha_ejecucion = fecha_ejecucion,
    estado = cierre$estado,
    n_registros = cierre$n_registros,
    n_obs_comparables = cierre$n_obs_comparables,
    n_productos_comparables = cierre$n_productos_comparables,
    resumen_comercios = if (length(resumen_comercios) > 0) bind_rows(resumen_comercios) else tibble(),
    cobertura = cobertura
  )
}

# -----------------------------------------------------------------------------
# 12. Utilidades de auditoría y modo offline
# -----------------------------------------------------------------------------

listar_ejecuciones <- function(ruta_db = RUTA_DB_POR_DEFECTO) {
  con <- dbConnect(SQLite(), ruta_db)
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, "SELECT * FROM ejecuciones ORDER BY fecha_inicio DESC")
}

resumen_ejecucion <- function(id_ejecucion, ruta_db = RUTA_DB_POR_DEFECTO) {
  con <- dbConnect(SQLite(), ruta_db)
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, "
    SELECT ec.id_comercio, c.nombre AS comercio, ec.n_paginas,
           ec.n_reportado_sitio, ec.n_extraido, ec.n_incluido, ec.n_excluido,
           ec.n_con_precio, ec.estado
      FROM ejecuciones_comercio ec
      JOIN comercios c ON c.id_comercio = ec.id_comercio
     WHERE ec.id_ejecucion = ?
     ORDER BY c.nombre", params = list(id_ejecucion))
}

# Reproduce una ejecución desde raw/ en una base distinta (verificación offline).
verificar_offline <- function(id_ejecucion, ruta_db_verificacion = "verificacion_offline.sqlite",
                              ruta_db_original = RUTA_DB_POR_DEFECTO) {
  if (file.exists(ruta_db_verificacion)) file.remove(ruta_db_verificacion)
  res <- ejecutar_recoleccion(
    offline = TRUE,
    ruta_db = ruta_db_verificacion,
    id_ejecucion = id_ejecucion,
    fecha_ejecucion = NULL,
    aplicar_correspondencia = TRUE,
    ruta_mapeo = RUTA_MAPEO,
    verboso = FALSE
  )

  con_o <- dbConnect(SQLite(), ruta_db_original)
  con_v <- dbConnect(SQLite(), ruta_db_verificacion)
  on.exit({ dbDisconnect(con_o); dbDisconnect(con_v) }, add = TRUE)

  consulta <- "
    SELECT id_comercio, COUNT(*) AS n, ROUND(SUM(COALESCE(precio_cop, 0)), 2) AS suma_precios,
           SUM(CASE WHEN disponible = 1 THEN 1 ELSE 0 END) AS n_disponibles
      FROM observaciones WHERE id_ejecucion = ? GROUP BY id_comercio ORDER BY id_comercio"
  original <- dbGetQuery(con_o, consulta, params = list(id_ejecucion))
  verificado <- dbGetQuery(con_v, consulta, params = list(id_ejecucion))

  comparacion <- dplyr::full_join(original, verificado, by = "id_comercio",
                                  suffix = c("_original", "_offline"))
  comparacion$igual <- with(comparacion,
    n_original == n_offline &
    abs(suma_precios_original - suma_precios_offline) < 0.01 &
    n_disponibles_original == n_disponibles_offline)

  list(resultado = res, comparacion = comparacion, todo_igual = all(comparacion$igual))
}

# -----------------------------------------------------------------------------
# 13. Descarga de robots.txt para auditoría de condiciones de uso
# -----------------------------------------------------------------------------

descargar_robots <- function(dir_salida = file.path("docs", "robots")) {
  dir.create(dir_salida, recursive = TRUE, showWarnings = FALSE)
  for (cfg in COMERCIOS) {
    destino <- file.path(dir_salida, paste0(cfg$id_comercio, "_robots.txt"))
    res <- tryCatch(http_get(cfg$robots_url), error = function(e) NULL)
    if (!is.null(res)) {
      writeLines(rawToChar(res$contenido), destino, useBytes = TRUE)
      message("Guardado ", destino)
    } else {
      message("No fue posible descargar robots.txt de ", cfg$nombre)
    }
  }
}
