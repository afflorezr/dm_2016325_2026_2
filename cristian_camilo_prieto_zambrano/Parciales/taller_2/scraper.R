# =============================================================================
# scraper.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
# Categoría: Nutrición clínica
#
# Módulo de extracción del Taller 1, reutilizado en el Taller 2. La aplicación
# y las pruebas llaman a sus funciones; no se copia dentro de la aplicación.
#
# Contenido:
#   1-4.  Configuración y utilidades (tabla común, copias crudas, solicitudes)
#   5-8.  Funciones por comercio: scrape_locatel(), scrape_cruzverde(),
#         scrape_farmatodo()
#   9.    Limpieza y estandarización
#   10.   Base SQLite: definida en db.R (antes estaba aquí)
#   11.   Función general: ejecutar_recoleccion() y, para la aplicación,
#         actualizar_precios() y corridas_en_raw()
#
# Archivos relacionados:
#   db.R          estructura de la base y escritura (todo el SQL)
#   validacion.R  reglas que se comprueban antes de insertar
#
# Uso:
#   source("scraper.R")
#   ejecutar_recoleccion()                                             # en línea
#   ejecutar_recoleccion(offline = TRUE, corrida = "20261010T213019")  # desde raw/
#
# Cambios respecto al Taller 1:
#   - La base y su escritura pasaron a db.R; la validación, a validacion.R.
#   - extraer_contenido() distingue el punto de miles ("1.000 g" = 1000 g).
#   - Reglas de subcategoría y lista blanca revisadas (ver correcciones_t1.R).
#   - ejecutar_recoleccion() valida cada observación antes de insertarla,
#     registra los rechazos y verifica los comparables de cada comercio.
#
# Estrategia general: los sitios arman sus listados con JavaScript a partir de
# servicios internos que responden JSON. Como pasó con Éxito, Carulla y Jumbo
# en el taller, el HTML descargado con read_html() no trae productos; por eso
# se consultan directamente esos servicios con httr2.
#
# Locatel (plataforma VTEX):
#   https://www.locatelcolombia.com/api/catalog_system/pub/products/search
#     ?fq=C:/<id de categoría>/&O=OrderByNameASC&_from=<desde>&_to=<hasta>
#   (desde el Taller 2 con orden fijo por nombre: ver ORDEN_VTEX)
#   Hasta 50 productos por página. El encabezado HTTP "resources"
#   (p. ej. "0-49/383") informa el total del sitio.
#
# Cruz Verde (Salesforce Commerce Cloud, API propia en api.cruzverde.com.co):
#   1) POST customer-service/login       -> abre una sesión de invitado (cookie)
#   2) GET  product-service/products/search?refine[]=cgid=<categoría>
#                                          -> listado y precios, 48 por página;
#                                             el campo "total" da el total del sitio
#   3) GET  product-service/products/product-summary?ids=...
#                                          -> descripción de cada producto
#
# Farmatodo (Angular + buscador Algolia):
#   POST https://vcojeyd2po-dsn.algolia.net/1/indexes/products-colombia/query
#   con el filtro de la sección. La aplicación, el índice y la clave pública de
#   solo búsqueda están en el código JavaScript que carga la propia página.
#   Desde el Taller 2 la clave se lee de .Renviron (FARMATODO_ALGOLIA_KEY).
# =============================================================================

# Un library() por paquete: así renv los detecta y los registra en renv.lock.
# Las dependencias se instalan con renv::restore() (ver README), no desde aquí.
library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(readr)
library(DBI)
library(RSQLite)
library(pointblank)

source("db.R")           # estructura de la base y escritura
source("validacion.R")   # reglas de validación antes de insertar

# -----------------------------------------------------------------------------
# 1. Configuración general
# -----------------------------------------------------------------------------

# Buenas prácticas de recolección (Módulo 4 del Taller 2):
#   - agente de usuario identificable: nombre del proyecto y contacto. Solo
#     caracteres ASCII, como exige un encabezado HTTP.
#   - pausa entre solicitudes y tiempo máximo de espera por solicitud;
#   - número máximo de solicitudes por comercio en cada ejecución.
URL_CONTACTO <- "https://github.com/CAPRI7A"
AGENTE_USUARIO <- sprintf(paste0(
  "Mozilla/5.0 (compatible; ComparadorPreciosUNAL/2.0; proyecto academico de ",
  "Mineria de Datos, Universidad Nacional de Colombia; +%s)"), URL_CONTACTO)

PAUSA           <- 1.5    # segundos entre solicitudes
MAX_SOLICITUDES <- 40L    # por comercio y ejecución; hoy se usan entre 2 y 13
DIR_RAW <- "raw"
ZONA    <- "America/Bogota"

# Contador de solicitudes del comercio en curso (se reinicia por comercio)
contador_solicitudes <- new.env()
contador_solicitudes$n <- 0L
reiniciar_contador <- function() contador_solicitudes$n <- 0L

# Secciones de Locatel consideradas equivalentes a la categoría de la planilla.
# Se recolectan COMPLETAS; lo que no pertenezca a la delimitación se marca
# como excluido en la limpieza, no se filtra aquí.
SECCIONES_LOCATEL <- c(
  suplementos = "C:/6/41/",     # Alimentos nutricionales > Suplementos (383 en el sitio)
  cereales_regulares = "C:/6/40/251/"  # Locatel clasifica aquí Ensure Advance líquido (11)
)

# Cruz Verde: Bienestar y Nutrición > Nutrición (243 en el sitio)
SECCIONES_CRUZVERDE <- c(nutricion = "bienynut-nutricion")
CRUZVERDE <- list(
  api  = "https://api.cruzverde.com.co",
  web  = "https://www.cruzverde.com.co",
  zona = "COCV_zona64"   # zona de inventario que el sitio asigna por defecto
)

# Farmatodo: Bienestar y nutrición deportiva > Nutrición (166 activos).
# Filtro equivalente a la página /categorias/bienestar-y-nutricion-deportiva/nutricion
# (verificado: todos los productos que muestra la página están en este filtro).
SECCIONES_FARMATODO <- c(
  nutricion = paste0('departments:"Bienestar y nutrición deportiva" AND ',
                     'categorie:"Nutrición" AND status:"A"')
)
FARMATODO <- list(
  url = "https://vcojeyd2po-dsn.algolia.net/1/indexes/products-colombia/query",
  app = "VCOJEYD2PO",     # identificador de la aplicación Algolia (no es una clave)
  web = "https://www.farmatodo.com.co"
)

# Clave de búsqueda de Farmatodo. Es la clave pública de solo búsqueda que el
# sitio entrega a todos sus visitantes, pero no se guarda en el código: se lee
# de la variable de entorno FARMATODO_ALGOLIA_KEY, definida en .Renviron
# (archivo excluido del repositorio; ver .Renviron.example y el README).
clave_farmatodo <- function() {
  clave <- Sys.getenv("FARMATODO_ALGOLIA_KEY")
  if (!nzchar(clave) && file.exists(".Renviron")) {
    readRenviron(".Renviron")
    clave <- Sys.getenv("FARMATODO_ALGOLIA_KEY")
  }
  if (!nzchar(clave)) {
    stop("falta la variable FARMATODO_ALGOLIA_KEY: créela en .Renviron siguiendo ",
         ".Renviron.example (solo se necesita para consultar Farmatodo en línea)")
  }
  clave
}

# Hora de Colombia en ISO 8601, p. ej. 2026-10-10T10:35:00-05:00
ahora_co <- function() {
  x <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = ZONA)
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", x)
}

# -----------------------------------------------------------------------------
# 2. Tabla vacía con las columnas comunes a todos los comercios
# -----------------------------------------------------------------------------
tabla_productos_vacia <- function() {
  tibble(
    comercio            = character(),
    seccion             = character(),  # sección del sitio de donde salió
    sku                 = character(),  # id interno del comercio
    ean                 = character(),  # código de barras
    nombre              = character(),
    marca               = character(),
    subcategoria        = character(),
    contenido           = numeric(),    # normalizado a g o mL
    unidad              = character(),
    n_unidades          = integer(),
    precio              = numeric(),    # precio de venta (COP)
    precio_lista        = numeric(),    # precio antes del descuento
    precio_club         = numeric(),    # solo Cruz Verde: precio para afiliados (no se compara)
    promocion           = integer(),
    disponible          = integer(),
    url                 = character(),
    texto_original      = character(),  # nombre | descripción, sin limpiar
    fecha_hora_consulta = character()
  )
}

# Contenido y unidad desde el nombre, normalizados a g y mL.
# "Tarro X 400Gr" -> 400 g ; "X 237 ml" -> 237 mL ; "X 2lb" -> 907.2 g
# Taller 2: el punto o la coma seguidos de exactamente tres cifras se leen como
# separador de miles en g, mL y mg ("1.000 g" -> 1000 g, no 1 g). En kg, L, lb
# y oz se leen como decimal ("1.5 kg" -> 1500 g), porque un millar de esas
# unidades no es una presentación plausible. Un número que empieza en 0
# ("0.400 kg") siempre es decimal.
extraer_contenido <- function(texto) {
  m <- str_match(
    str_to_lower(texto),
    "(\\d+(?:[.,]\\d+)*)\\s*(kg|mg|gramos|gramo|grs?|g|lbs?|oz|mililitros|ml|lts?|l)\\b"
  )
  numero <- m[, 2]
  unidad <- recode(m[, 3], gramos = "g", gramo = "g", mililitros = "ml")
  miles  <- !is.na(numero) &
    str_detect(numero, "^[1-9]\\d{0,2}([.,]\\d{3})+$") &
    unidad %in% c("g", "gr", "grs", "mg", "ml")
  valor  <- suppressWarnings(ifelse(
    miles,
    as.numeric(str_remove_all(numero, "[.,]")),
    as.numeric(str_replace(numero, ",", "."))
  ))
  tibble(
    contenido = case_when(
      unidad == "kg"                  ~ valor * 1000,
      unidad == "mg"                  ~ valor / 1000,
      unidad %in% c("lb", "lbs")      ~ round(valor * 453.592, 1),
      unidad == "oz"                  ~ round(valor * 28.3495, 1),
      unidad %in% c("l", "lt", "lts") ~ valor * 1000,
      TRUE                            ~ valor
    ),
    unidad = case_when(
      unidad %in% c("kg", "mg", "g", "gr", "grs", "lb", "lbs", "oz") ~ "g",
      unidad %in% c("ml", "l", "lt", "lts")                          ~ "mL",
      TRUE ~ NA_character_
    )
  )
}

# Precio de la respuesta de un sitio a número. Las tres APIs entregan los
# precios como números, no como texto, así que no hay que quitar "$" ni
# separadores. La regla que sí se aplica en los tres comercios: un precio 0,
# vacío, ausente o no numérico significa "sin precio publicado" y queda NA,
# nunca 0 (un 0 haría parecer gratis el producto y bajaría los promedios).
limpiar_precio <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  v <- suppressWarnings(as.numeric(unlist(x)))
  if (length(v) == 0) return(NA_real_)
  v[!is.finite(v) | v <= 0] <- NA_real_
  v
}

# Número de unidades del empaque: "X 6Und", "X 8 Botellas"
extraer_unidades <- function(texto) {
  n <- str_match(str_to_lower(texto),
                 "(?:x|por)\\s*(\\d+)\\s*(?:und|unds|uni|unidades|botellas|frascos|sobres|tetrapack)")[, 2]
  as.integer(ifelse(is.na(n), 1L, n))
}

# -----------------------------------------------------------------------------
# 3. Copias crudas y modo sin conexión
#    raw/<comercio>/<corrida>/<pagina>__<fecha-hora>.json.gz
#    La hora de consulta queda en el nombre del archivo: al reprocesar sin
#    conexión se conserva la hora original, no la del reprocesamiento.
# -----------------------------------------------------------------------------
guardar_crudo <- function(texto, comercio, corrida, nombre, fecha_hora) {
  dir <- file.path(DIR_RAW, comercio, corrida)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  marca_tiempo <- gsub(":", "", fecha_hora)          # ':' no es válido en Windows
  archivo <- file.path(dir, paste0(nombre, "__", marca_tiempo, ".json.gz"))
  con <- gzfile(archivo, "w", encoding = "UTF-8")
  writeLines(texto, con)
  close(con)
  invisible(archivo)
}

leer_crudos <- function(comercio, corrida) {
  archivos <- sort(list.files(file.path(DIR_RAW, comercio, corrida),
                              pattern = "\\.json\\.gz$", full.names = TRUE))
  if (length(archivos) == 0) {
    stop("No hay copias crudas en ", file.path(DIR_RAW, comercio, corrida))
  }
  map(archivos, function(a) {
    partes <- str_match(basename(a), "^(.+)__(.+)\\.json\\.gz$")
    # 2026-10-10T103500-0500 -> 2026-10-10T10:35:00-05:00
    fh <- sub("T(\\d{2})(\\d{2})(\\d{2})([+-]\\d{2})(\\d{2})$",
              "T\\1:\\2:\\3\\4:\\5", partes[, 3])
    con <- gzfile(a, encoding = "UTF-8")
    on.exit(close(con))
    list(texto = paste(readLines(con, warn = FALSE), collapse = "\n"),
         fecha_hora = fh,
         nombre = partes[, 2],
         seccion = str_remove(partes[, 2], "_p\\d+$"))
  })
}

# El total que informa el sitio se guarda junto a las copias crudas
# (raw/<comercio>/<corrida>/totales.csv). Así el modo sin conexión puede
# repetir la verificación de completitud: en VTEX ese total solo viene en
# un encabezado HTTP, que no queda dentro del JSON.
guardar_totales <- function(totales, comercio, corrida) {
  dir <- file.path(DIR_RAW, comercio, corrida)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_csv(totales, file.path(dir, "totales.csv"))
}

leer_totales <- function(comercio, corrida) {
  archivo <- file.path(DIR_RAW, comercio, corrida, "totales.csv")
  if (!file.exists(archivo)) return(NULL)
  read_csv(archivo, col_types = "ci")
}

# Quita los SKU repetidos y verifica la completitud.
#   - Repetidos dentro de una misma sección: la lista del sitio cambió mientras
#     se paginaba (unos productos se repiten y otros no llegan).
#   - Repetidos entre secciones: el mismo producto está en dos secciones; se
#     conserva una sola fila. No indica que falte nada.
# La completitud se mide por sección con SKU únicos, antes de quitar los
# repetidos entre secciones, para que un producto en dos secciones no parezca
# faltante. Deja en los atributos la verificación y los conteos de repetidos.
depurar_y_verificar <- function(datos, totales, comercio) {
  por_seccion <- datos %>% distinct(seccion, sku, .keep_all = TRUE)
  rep_seccion <- nrow(datos) - nrow(por_seccion)
  final       <- por_seccion %>% distinct(sku, .keep_all = TRUE)
  rep_entre   <- nrow(por_seccion) - nrow(final)
  verificado  <- verificar_completitud(por_seccion, totales, comercio)
  attr(final, "verificacion")          <- attr(verificado, "verificacion")
  attr(final, "repetidos_en_seccion")  <- rep_seccion
  attr(final, "repetidos_entre_secciones") <- rep_entre
  final
}

# Compara lo obtenido (SKU únicos) con lo que informa el sitio, por sección
verificar_completitud <- function(datos, totales, comercio) {
  if (is.null(totales) || nrow(totales) == 0) {
    message("Verificación de completitud (", comercio, "): sin total del sitio.")
    return(datos)
  }
  verificacion <- datos %>%
    count(seccion, name = "obtenidos") %>%
    right_join(totales, by = "seccion")
  message("Verificación de completitud (", comercio, "):")
  print(verificacion)
  attr(datos, "verificacion") <- verificacion
  datos
}

# -----------------------------------------------------------------------------
# 4. Solicitud HTTP
# -----------------------------------------------------------------------------
solicitar <- function(req, etiqueta) {
  # Límite de solicitudes por comercio: al alcanzarlo no se consulta más y la
  # ejecución queda parcial, con el motivo
  if (contador_solicitudes$n >= MAX_SOLICITUDES) {
    message(PREFIJO_FALLA, etiqueta, ": se alcanzó el límite de ", MAX_SOLICITUDES,
            " solicitudes por comercio en esta ejecución")
    return(NULL)
  }
  contador_solicitudes$n <- contador_solicitudes$n + 1L
  Sys.sleep(PAUSA)
  respuesta <- tryCatch(
    req %>%
      req_user_agent(AGENTE_USUARIO) %>%
      req_headers(`accept-language` = "es-CO,es;q=0.9") %>%
      req_timeout(seconds = 30) %>%
      req_retry(max_tries = 3) %>%
      req_error(is_error = function(resp) FALSE) %>%
      req_perform(),
    error = function(e) {
      # Un solo mensaje por falla, en una línea y con el prefijo que
      # ejecutar_recoleccion() recoge para explicar una ejecución parcial o fallida
      message(PREFIJO_FALLA, etiqueta, ": ", resumir_error(conditionMessage(e)))
      NULL
    }
  )
  if (is.null(respuesta)) return(NULL)
  if (resp_status(respuesta) >= 400) {
    message(PREFIJO_FALLA, etiqueta, ": respuesta HTTP ", resp_status(respuesta))
    return(NULL)
  }
  respuesta
}
PREFIJO_FALLA <- "Solicitud fallida - "

# Mensaje de error de httr2/curl en una sola línea, sin los encabezados genéricos:
# "Could not connect to server [host]: CONNECT tunnel failed, response 403"
resumir_error <- function(texto) {
  lineas <- trimws(strsplit(texto, "\n")[[1]])
  lineas <- sub("^[!\u2716\u2139x>*] *", "", lineas)
  utiles <- lineas[nzchar(lineas) & !grepl("^(Failed to perform HTTP request|Caused by error)", lineas)]
  if (length(utiles) == 0) utiles <- lineas[nzchar(lineas)]
  substr(paste(utiles, collapse = " "), 1, 200)
}

# =============================================================================
# 5. Plataforma VTEX (Locatel)
# =============================================================================

# Orden fijo de la lista. Sin él, el sitio usa su propio orden (relevancia o
# ventas), que puede cambiar mientras se pagina: unos productos se repiten
# entre páginas y otros no llegan (le pasó a Locatel el 2026-11-14: 3 de 398).
ORDEN_VTEX <- "OrderByNameASC"

url_vtex <- function(dominio, fq, desde) {
  sprintf("https://%s/api/catalog_system/pub/products/search?fq=%s&O=%s&_from=%d&_to=%d",
          dominio, fq, ORDEN_VTEX, desde, desde + 49)
}

# Recorre todas las páginas de cada sección y guarda la copia cruda.
# Devuelve la lista de páginas y una tabla con el total que informa el sitio.
descargar_vtex <- function(comercio, dominio, secciones, corrida) {
  paginas <- list()
  totales <- tibble(seccion = character(), total_sitio = integer())
  for (nombre_sec in names(secciones)) {
    fq <- secciones[[nombre_sec]]
    desde <- 0
    total <- NA_integer_
    repeat {
      url <- url_vtex(dominio, fq, desde)
      resp <- solicitar(request(url), paste(comercio, nombre_sec, "desde", desde))
      if (is.null(resp)) break
      texto <- resp_body_string(resp)
      fh <- ahora_co()
      guardar_crudo(texto, comercio, corrida,
                    sprintf("%s_p%04d", nombre_sec, desde), fh)
      paginas[[length(paginas) + 1]] <- list(texto = texto, fecha_hora = fh,
                                             seccion = nombre_sec)
      n <- length(fromJSON(texto, simplifyVector = FALSE))
      total <- as.integer(str_extract(resp_header(resp, "resources"), "\\d+$"))
      desde <- desde + 50
      # VTEX no entrega más allá del resultado 2500 en una misma consulta
      if (n < 50 || (!is.na(total) && desde >= total) || desde >= 2500) break
    }
    totales <- bind_rows(totales, tibble(seccion = nombre_sec, total_sitio = total))
  }
  attr(paginas, "totales") <- totales
  paginas
}

# Convierte las páginas crudas VTEX en la tabla común (una fila por SKU).
parsear_vtex <- function(paginas, comercio) {
  espec <- function(p, campo) {      # las especificaciones vienen como listas
    v <- p[[campo]]
    if (is.null(v) || length(v) == 0) NA_character_ else as.character(v[[1]])
  }
  map_dfr(paginas, function(pag) {
    productos <- fromJSON(pag$texto, simplifyVector = FALSE)
    if (length(productos) == 0) return(tabla_productos_vacia())
    map_dfr(productos, function(p) {
      # Un producto puede tener varios SKU (variantes): una fila por SKU
      map_dfr(p$items, function(it) {
        vendedor <- keep(it$sellers, ~ isTRUE(.x$sellerDefault))
        vendedor <- if (length(vendedor) > 0) vendedor[[1]] else it$sellers[[1]]
        oferta   <- vendedor$commertialOffer
        # La Rebaja pone el tamaño en "Presentacionunidadmedida"; Locatel en el nombre
        presentacion <- espec(p, "Presentacionunidadmedida")
        # Con un solo SKU se usa el nombre del producto (La Rebaja agrega
        # "SKU12345" a nameComplete); con variantes, el nombre de cada SKU
        base <- if (length(p$items) > 1) it$nameComplete %||% p$productName else p$productName
        nombre <- str_squish(paste(base, ifelse(is.na(presentacion), "", presentacion)))
        ean <- if (!is.null(it$ean) && nzchar(it$ean)) it$ean else espec(p, "ML_EAN")
        cont <- extraer_contenido(nombre)
        precio <- limpiar_precio(oferta$Price)
        lista  <- limpiar_precio(oferta$ListPrice)
        tibble(
          comercio            = comercio,
          seccion             = pag$seccion,
          sku                 = as.character(it$itemId),
          ean                 = as.character(ean),
          nombre              = nombre,
          marca               = p$brand %||% NA_character_,
          subcategoria        = p$categories[[1]] %||% NA_character_,
          contenido           = cont$contenido,
          unidad              = cont$unidad,
          n_unidades          = extraer_unidades(nombre),
          precio              = precio,
          precio_lista        = lista,
          precio_club         = NA_real_,
          promocion           = as.integer(isTRUE(lista > precio)),
          disponible          = as.integer(isTRUE(oferta$IsAvailable)),
          url                 = p$link %||% NA_character_,
          texto_original      = paste(p$productName, p$description %||% "", sep = " | "),
          fecha_hora_consulta = pag$fecha_hora
        )
      })
    })
  })
}

# Recolección completa de un comercio VTEX (en línea o desde raw/)
scrape_vtex <- function(comercio, dominio, secciones, corrida, offline = FALSE) {
  if (offline) {
    paginas <- leer_crudos(comercio, corrida)
    totales <- leer_totales(comercio, corrida)
  } else {
    paginas <- descargar_vtex(comercio, dominio, secciones, corrida)
    if (length(paginas) == 0) stop("no se obtuvo ninguna página del sitio")
    totales <- attr(paginas, "totales")
    guardar_totales(totales, comercio, corrida)
  }
  # SKU repetidos y verificación de completitud frente a lo que informa el sitio
  depurar_y_verificar(parsear_vtex(paginas, comercio), totales, comercio)
}

# =============================================================================
# 6. Funciones por comercio (todas devuelven las mismas columnas)
#    scrape_locatel("20261010T163000")                  # en línea
#    scrape_locatel("20261010T163000", offline = TRUE)  # desde raw/
# =============================================================================
scrape_locatel <- function(corrida, offline = FALSE) {
  scrape_vtex("locatel", "www.locatelcolombia.com", SECCIONES_LOCATEL,
              corrida, offline)
}

# =============================================================================
# 7. Cruz Verde
# =============================================================================

# Solicitud a la API de Cruz Verde, conservando la cookie de sesión
req_cruzverde <- function(url, cookies) {
  request(url) %>%
    req_cookie_preserve(cookies) %>%
    req_headers(Origin = CRUZVERDE$web, Referer = paste0(CRUZVERDE$web, "/"))
}

descargar_cruzverde <- function(corrida, secciones = SECCIONES_CRUZVERDE, por_pagina = 48) {
  cookies <- tempfile(fileext = ".txt")       # cookie de sesión, solo para esta corrida
  on.exit(unlink(cookies), add = TRUE)

  # 1) Sesión de invitado (sin ella el servicio responde 401)
  login <- solicitar(
    req_cruzverde(paste0(CRUZVERDE$api, "/customer-service/login"), cookies) %>%
      req_method("POST") %>%
      req_body_raw("{}", type = "application/json"),
    "cruzverde login"
  )
  if (is.null(login)) stop("Cruz Verde: no se pudo abrir la sesión de invitado.")

  paginas <- list()
  totales <- tibble(seccion = character(), total_sitio = integer())
  for (nombre_sec in names(secciones)) {
    cgid <- secciones[[nombre_sec]]
    desde <- 0
    total <- NA_integer_
    repeat {
      # 2) Listado con precios
      url <- sprintf(
        "%s/product-service/products/search?limit=%d&offset=%d&sort=&q=&refine[]=cgid=%s&inventoryId=%s&inventoryZone=%s",
        CRUZVERDE$api, por_pagina, desde, cgid, CRUZVERDE$zona, CRUZVERDE$zona
      )
      resp <- solicitar(req_cruzverde(url, cookies),
                        paste("cruzverde", nombre_sec, "desde", desde))
      if (is.null(resp)) break
      texto_busqueda <- resp_body_string(resp)
      fh <- ahora_co()
      js <- fromJSON(texto_busqueda, simplifyVector = FALSE)
      total <- as.integer(js$total %||% NA)
      hits <- js$hits %||% list()

      # 3) Descripción de los productos de esta página
      texto_resumen <- "{}"
      if (length(hits) > 0) {
        ids <- map_chr(hits, "productId")
        url_res <- paste0(
          CRUZVERDE$api, "/product-service/products/product-summary?",
          paste0("ids=", ids, collapse = "&"),
          "&fields=name&fields=description&fields=brand&fields=pum&fields=pageURL",
          "&inventoryId=", CRUZVERDE$zona
        )
        resp_res <- solicitar(req_cruzverde(url_res, cookies),
                              paste("cruzverde resumen", nombre_sec, "desde", desde))
        if (!is.null(resp_res)) texto_resumen <- resp_body_string(resp_res)
      }

      base <- sprintf("%s_p%04d", nombre_sec, desde)
      guardar_crudo(texto_busqueda, "cruzverde", corrida, paste0(base, "_busqueda"), fh)
      guardar_crudo(texto_resumen,  "cruzverde", corrida, paste0(base, "_resumen"),  fh)
      paginas[[length(paginas) + 1]] <- list(busqueda = texto_busqueda,
                                             resumen = texto_resumen,
                                             fecha_hora = fh, seccion = nombre_sec)
      desde <- desde + por_pagina
      if (length(hits) < por_pagina || (!is.na(total) && desde >= total)) break
    }
    totales <- bind_rows(totales, tibble(seccion = nombre_sec, total_sitio = total))
  }
  attr(paginas, "totales") <- totales
  paginas
}

# Reconstruye las páginas (búsqueda + resumen) desde raw/
leer_crudos_cruzverde <- function(corrida) {
  crudos <- leer_crudos("cruzverde", corrida)
  nombres <- map_chr(crudos, "nombre")
  bases <- unique(str_remove(nombres, "_(busqueda|resumen)$"))
  map(bases, function(b) {
    bus <- crudos[[which(nombres == paste0(b, "_busqueda"))]]
    i_res <- which(nombres == paste0(b, "_resumen"))
    list(busqueda = bus$texto,
         resumen = if (length(i_res) == 1) crudos[[i_res]]$texto else "{}",
         fecha_hora = bus$fecha_hora,
         seccion = str_remove(b, "_p\\d+$"))
  })
}

parsear_cruzverde <- function(paginas) {
  map_dfr(paginas, function(pag) {
    hits <- fromJSON(pag$busqueda, simplifyVector = FALSE)$hits %||% list()
    if (length(hits) == 0) return(tabla_productos_vacia())
    resumen <- fromJSON(pag$resumen, simplifyVector = FALSE)   # lista con nombre = id
    map_dfr(hits, function(h) {
      id     <- h$productId
      det    <- resumen[[id]] %||% list()
      nombre <- str_squish(h$productName %||% det$name %||% NA_character_)
      cont   <- extraer_contenido(nombre)
      pr     <- h$prices %||% list()
      lista  <- limpiar_precio(pr[["price-list-col"]])
      oferta <- limpiar_precio(pr[["price-sale-col"]])
      club   <- limpiar_precio(pr[["price-club-col"]])
      # Precio comparable: oferta abierta a todos si existe; si no, el de lista.
      # El precio Club exige afiliación y se guarda aparte.
      precio <- if (!is.na(oferta)) oferta else lista
      slug   <- h$pageURL %||% det$pageURL
      tibble(
        comercio            = "cruzverde",
        seccion             = pag$seccion,
        sku                 = as.character(id),
        ean                 = NA_character_,          # la API no lo publica
        nombre              = nombre,
        marca               = h$brand %||% det$brand %||% NA_character_,
        subcategoria        = SECCIONES_CRUZVERDE[[pag$seccion]] %||% pag$seccion,
        contenido           = cont$contenido,
        unidad              = cont$unidad,
        n_unidades          = extraer_unidades(nombre),
        precio              = precio,
        precio_lista        = lista,
        precio_club         = club,
        promocion           = as.integer(isTRUE(oferta < lista)),
        disponible          = as.integer(isTRUE((h$stock %||% 0) > 0)),
        url                 = if (is.null(slug)) NA_character_ else
                                sprintf("%s/%s/%s.html", CRUZVERDE$web, slug, id),
        texto_original      = paste(h$productName %||% "", det$description %||% "",
                                    h$pum %||% "", sep = " | "),
        fecha_hora_consulta = pag$fecha_hora
      )
    })
  })
}

scrape_cruzverde <- function(corrida, offline = FALSE) {
  if (offline) {
    paginas <- leer_crudos_cruzverde(corrida)
    # Si la corrida no tiene totales.csv, el total está en el JSON ("total")
    totales <- leer_totales("cruzverde", corrida) %||% total_desde_json(
      paginas, function(p) fromJSON(p$busqueda, simplifyVector = FALSE)$total)
  } else {
    paginas <- descargar_cruzverde(corrida)
    if (length(paginas) == 0) stop("no se obtuvo ninguna página del sitio")
    totales <- attr(paginas, "totales")
    guardar_totales(totales, "cruzverde", corrida)
  }
  depurar_y_verificar(parsear_cruzverde(paginas), totales, "cruzverde")
}

# Total del sitio leído de las copias crudas (Cruz Verde y Farmatodo lo
# incluyen en el cuerpo de la respuesta; se toma el de la primera página)
total_desde_json <- function(paginas, extraer) {
  map_dfr(paginas, function(p) {
    tibble(seccion = p$seccion, total_sitio = as.integer(extraer(p) %||% NA))
  }) %>%
    distinct(seccion, .keep_all = TRUE)
}

# =============================================================================
# 8. Farmatodo (buscador Algolia que usa la propia página)
#    POST al índice "products-colombia" con el filtro de la sección.
#    Hasta 100 productos por página; "nbHits" da el total y "nbPages" las páginas.
# =============================================================================
descargar_farmatodo <- function(corrida, secciones = SECCIONES_FARMATODO, por_pagina = 100) {
  clave <- clave_farmatodo()
  paginas <- list()
  totales <- tibble(seccion = character(), total_sitio = integer())
  for (nombre_sec in names(secciones)) {
    pagina <- 0
    total <- NA_integer_
    repeat {
      req <- request(FARMATODO$url) %>%
        req_headers(`X-Algolia-Application-Id` = FARMATODO$app,
                    `X-Algolia-API-Key` = clave) %>%
        req_body_json(list(query = "", filters = secciones[[nombre_sec]],
                           hitsPerPage = por_pagina, page = pagina))
      resp <- solicitar(req, paste("farmatodo", nombre_sec, "página", pagina))
      if (is.null(resp)) break
      texto <- resp_body_string(resp)
      fh <- ahora_co()
      guardar_crudo(texto, "farmatodo", corrida,
                    sprintf("%s_p%04d", nombre_sec, pagina), fh)
      paginas[[length(paginas) + 1]] <- list(texto = texto, fecha_hora = fh,
                                             seccion = nombre_sec)
      js <- fromJSON(texto, simplifyVector = FALSE)
      total <- as.integer(js$nbHits %||% NA)
      pagina <- pagina + 1
      if (pagina >= (js$nbPages %||% 0)) break
    }
    totales <- bind_rows(totales, tibble(seccion = nombre_sec, total_sitio = total))
  }
  attr(paginas, "totales") <- totales
  paginas
}

parsear_farmatodo <- function(paginas) {
  map_dfr(paginas, function(pag) {
    hits <- fromJSON(pag$texto, simplifyVector = FALSE)$hits %||% list()
    if (length(hits) == 0) return(tabla_productos_vacia())
    map_dfr(hits, function(h) {
      nombre <- str_squish(h$mediaDescription %||% NA_character_)
      cont   <- extraer_contenido(nombre)
      lleno  <- limpiar_precio(h$fullPrice)
      oferta <- limpiar_precio(h$offerPrice)   # 0 = sin oferta
      tibble(
        comercio            = "farmatodo",
        seccion             = pag$seccion,
        sku                 = as.character(h$id %||% h$objectID),
        ean                 = as.character(h$barcode %||% NA_character_),
        nombre              = nombre,
        marca               = h$marca %||% NA_character_,
        subcategoria        = paste(h$categorie %||% "", h$subCategory %||% "", sep = " > "),
        contenido           = cont$contenido,
        unidad              = cont$unidad,
        n_unidades          = extraer_unidades(nombre),
        # Precio base (fullPrice) y precio de oferta (offerPrice > 0)
        precio              = if (!is.na(oferta)) oferta else lleno,
        precio_lista        = lleno,
        precio_club         = NA_real_,
        promocion           = as.integer(isTRUE(oferta < lleno)),
        disponible          = as.integer(length(h$stores_with_stock %||% list()) > 0),
        url                 = if (is.null(h$url)) NA_character_ else
                                paste0(FARMATODO$web, "/producto/", h$url),
        texto_original      = paste(h$mediaDescription %||% "",
                                    h$largeDescription %||% "", sep = " | "),
        fecha_hora_consulta = pag$fecha_hora
      )
    })
  })
}

scrape_farmatodo <- function(corrida, offline = FALSE) {
  if (offline) {
    paginas <- leer_crudos("farmatodo", corrida)
    # Si la corrida no tiene totales.csv, el total está en el JSON ("nbHits")
    totales <- leer_totales("farmatodo", corrida) %||% total_desde_json(
      paginas, function(p) fromJSON(p$texto, simplifyVector = FALSE)$nbHits)
  } else {
    paginas <- descargar_farmatodo(corrida)
    if (length(paginas) == 0) stop("no se obtuvo ninguna página del sitio")
    totales <- attr(paginas, "totales")
    guardar_totales(totales, "farmatodo", corrida)
  }
  depurar_y_verificar(parsear_farmatodo(paginas), totales, "farmatodo")
}

# Taller 2: ya no se usan versiones "seguras" con possibly(), que ocultaban el
# motivo de la falla. ejecutar_recoleccion() captura el error de cada comercio,
# lo registra como motivo de la ejecución y continúa con los demás.

# =============================================================================
# 9. Limpieza y estandarización
#    Las versiones estandarizadas van en columnas propias; nombre, marca,
#    subcategoría y texto_original quedan tal como los publicó cada sitio.
#
#    Taller 2: las reglas se revisaron contra la base del Taller 1. Los cambios
#    a anuncios ya cargados se registraron en la tabla correcciones
#    (ver correcciones_t1.R).
# =============================================================================

# Marcas conocidas de la categoría, buscadas en el nombre del producto.
# Se busca en el nombre porque el campo "marca" de cada sitio no es uniforme:
# el mismo Glucerna llega como "Glucerna", "GLUCERNA" o "Abbott".
MARCAS_STD <- c(
  "ensure" = "Ensure", "glucerna" = "Glucerna", "pediasure" = "PediaSure",
  "prowhey" = "ProWhey", "proklein" = "Proklein", "diben" = "Diben",
  "nutren" = "Nutren", "fresubin" = "Fresubin", "fortisip" = "Fortisip",
  "ascenda" = "Ascenda", "enterex" = "Enterex", "boost" = "Boost",
  "kalori" = "ProWhey", "nutrione" = "Nutrione", "supportan" = "Supportan",
  "glutament" = "Glutament", "ketocal" = "Ketocal", "monogen" = "Monogen",
  "prosure" = "Prosure", "pulmocare" = "Pulmocare", "nepro" = "Nepro",
  "casilan" = "Nutricia Casilan", "prosource" = "Prosource", "frebin" = "Frebini",
  "fortini" = "Fortini", "anamix" = "Anamix", "ensoy" = "Ensoy",
  "gerifood" = "Gerifood", "aukena" = "Aukena", "espezante" = "ProWhey"
)

# Lista blanca de la categoría "Nutrición clínica" (delimitación de la planilla):
# fórmulas nutricionales completas o especializadas, suplementos para soporte
# nutricional, módulos de proteína y espesantes, incluidas fórmulas pediátricas
# clínicas. Todo lo que no coincide se marca como excluido.
# Taller 2: se agregan renament, argiment y nutriadvance. Antes entraban solo
# porque su nombre dice "Complemento nutricional".
NUTRICION_CLINICA <- paste(
  "ensure|glucerna|pediasure|prowhey|proklein|diben|nutren|fresubin|frebin",
  "fortisip|fortini|ascenda|enterex|glytrol|supportan|glutament|ketocal|monogen",
  "nutrione|boost|kalori|prosure|oncare|pulmocare|nepro|casilan|prosource|anamix",
  "ensoy|gerifood|aukena|espezante|espesante|thicken",
  "renament|argiment|nutriadvance",
  "f[oó]rmula nutricional|f[oó]rmula especializada|nutrici[oó]n especializada",
  "alimento l[ií]quido|complemento nutricional",
  sep = "|"
)

estandarizar_marca <- function(nombre, marca) {
  n <- str_to_lower(nombre)
  encontrada <- map_chr(n, function(x) {
    i <- which(str_detect(x, fixed(names(MARCAS_STD))))
    if (length(i) > 0) MARCAS_STD[[i[1]]] else NA_character_
  })
  # Si el nombre no trae una marca conocida, se usa el campo del sitio en formato título
  coalesce(encontrada, str_to_title(str_squish(marca)))
}

# Subcategoría común a los tres comercios, por reglas sobre el nombre.
# El orden importa: la primera regla que se cumple es la que se asigna.
# Taller 2: se agregan a las reglas las marcas de la lista blanca que no tenían
# subcategoría (quedaban en "Otro (revisar)"):
#   pediátrica    + proklein net  (el sitio la describe como nutrición pediátrica)
#   renal         + renament      (la página del producto la indica para ERC)
#   especializada + ketocal, monogen
#   completa      + nutriadvance  (el sitio la describe como alimento completo)
#   proteína      + glutament, argiment (módulos de aminoácidos)
estandarizar_subcategoria <- function(nombre) {
  n <- str_to_lower(nombre)
  case_when(
    str_detect(n, "espesante|thicken|spezante")                          ~ "Espesante / módulo de carbohidrato",
    str_detect(n, "pediasure|kids|niñ|infantil|fortini|frebin|anamix|junior|proklein net") ~ "Fórmula pediátrica",
    str_detect(n, "glucerna|diben|glytrol|diabet|prowhey dm|\\bdm\\b")   ~ "Fórmula para diabetes",
    str_detect(n, "renal|nepro|renament")                                ~ "Fórmula renal",
    str_detect(n, "pulmocare|prosure|oncare|neumo|ketocal|monogen|f[oó]rmula especializada|nutrici[oó]n especializada") ~
      "Fórmula especializada (otra patología)",
    # Las fórmulas completas van antes que los módulos: "Ensure ... con Proteína"
    # sigue siendo una fórmula completa, no un módulo de proteína
    str_detect(n, "ensure|nutren|fresubin|fortisip|ascenda|enterex|boost|nutrione|supportan|gerifood|aukena|nutriadvance") ~
      "Fórmula completa adulto",
    str_detect(n, "prowhey|proklein|casilan|prosource|glutament|argiment|prote[ií]na|protein|whey") ~ "Módulo de proteína",
    TRUE ~ "Otro (revisar)"
  )
}

# Exclusiones según la delimitación de la planilla. Se marcan; no se borran.
# Regla: lo que está en la lista blanca NUTRICION_CLINICA pertenece a la
# categoría; lo demás se excluye y el motivo indica a qué tipo de producto
# corresponde. Devuelve NA si el producto pertenece a la categoría.
motivo_exclusion <- function(nombre, seccion) {
  n <- str_to_lower(nombre)
  case_when(
    str_detect(n, "jeringa|sonda|equipo de alimentaci") ~
      "Dispositivo médico (no es un alimento)",
    str_detect(n, NUTRICION_CLINICA) ~ NA_character_,
    str_detect(n, "creatin|crea stack|gainer|mass\\b|burner|termog|pre.?workout|pre.?entreno|bcaa|amino|isolate|aislada|whey|bipro|beef|carnitin|hidratante|energ|waffles|recuperante|sports") ~
      "Nutrición deportiva (otra categoría de la planilla)",
    str_detect(n, "vitamin|multivit|centrum|magnes|calci|col[aá]geno|collagen|omega|biotin|zinc|hierro|selenio|gomas|gomitas|c[aá]psul|cap\\b|tableta|comprimido|grageas|jarabe|emulsi[oó]n scott|suplemento dietario|resveratrol|melena de le|espirulina|maca|inositol|probi[oó]tic|prebi[oó]tic|fibra|cranberry|ar[aá]ndano") ~
      "Vitaminas o suplemento dietario (otra categoría de la planilla)",
    str_detect(n, "lubricante|vaginal|[oó]vulo|crema|shampoo|gel\\b|aciclovir|postday|postinor|evinet|seguret|anticoncep|buscapina|spray|loci[oó]n") ~
      "Medicamento o producto de cuidado personal (otra categoría de la planilla)",
    str_detect(n, "similac|enfagrow|leche|infantil.*f[oó]rmula") ~
      "Leche o fórmula infantil de consumo general (otra categoría de la planilla)",
    seccion == "cereales_regulares" ~
      "Cereal o alimento regular (sección de Locatel incluida solo por Ensure líquido)",
    TRUE ~ "Alimento, bebida o suplemento que no es nutrición clínica (fuera de la delimitación)"
  )
}

# Paquetes y ofertas compuestas: no son la presentación individual
es_paquete <- function(nombre, n_unidades) {
  n <- str_to_lower(nombre)
  # "+" solo cuenta si suma otro producto ("850G + 400G", "+ 1 Tarro"), no "+ HMB";
  # "pack" solo como palabra, no dentro de "Tetrapack"
  as.integer(n_unidades > 1 |
             str_detect(n, "\\+\\s*(\\d|botella|lata|tarro|frasco|gratis)") |
             str_detect(n, "oferta|promo|pague|lleve|gratis|\\boft\\b|\\bpaca\\b|\\bpack\\b|\\bkit\\b|combo"))
}

limpiar <- function(datos) {
  datos %>%
    mutate(
      marca_std        = estandarizar_marca(nombre, marca),
      subcategoria_std = estandarizar_subcategoria(nombre),
      es_paquete       = es_paquete(nombre, n_unidades),
      motivo_exclusion = motivo_exclusion(nombre, seccion),
      excluido         = as.integer(!is.na(motivo_exclusion))
    )
}

# =============================================================================
# 10. Base SQLite
#     Desde el Taller 2 la estructura de la base y toda su escritura están en
#     db.R: crear_base(), insertar_lote(), aplicar_correspondencia() y
#     verificar_correspondencia(). Este archivo ya no contiene SQL de escritura.
# =============================================================================

# =============================================================================
# 11. Función general: una sola llamada ejecuta todo
#
#   ejecutar_recoleccion()                                   # en línea, corrida nueva
#   ejecutar_recoleccion(offline = TRUE, corrida = "...")    # desde raw/
#
#   Por cada comercio, y de forma independiente (si uno falla, se registra su
#   falla con el motivo y se sigue con los demás):
#     extraer -> limpiar -> validar (validacion.R) -> comparables ->
#     guardar la ejecución y sus datos en una sola transacción (db.R) ->
#     resumen frente a la ejecución anterior
#
#   Estado de la ejecución de cada comercio:
#     fallida   no se obtuvo ningún registro o hubo un error; el motivo lo dice
#     parcial   menos productos de los que informa el sitio, o menos de
#               MIN_COMPARABLES comparables con precio
#     completa  en los demás casos
#
#   Modo sin conexión: si la corrida de un comercio no está en la base, se
#   carga desde raw/. Si ya está cargada, no se escribe nada: se reprocesa
#   raw/ en memoria y se compara con lo guardado (verificación del origen de
#   los datos). La hora de consulta siempre es la original, tomada del nombre
#   de la copia cruda.
# =============================================================================
SCRAPERS <- list(
  locatel   = scrape_locatel,
  cruzverde = scrape_cruzverde,
  farmatodo = scrape_farmatodo
)

# Corridas disponibles en raw/ (las carpetas con al menos una copia cruda)
corridas_en_raw <- function(dir_raw = DIR_RAW) {
  carpetas <- list.dirs(dir_raw, recursive = TRUE, full.names = TRUE)
  carpetas <- carpetas[grepl("^\\d{8}T\\d{6}$", basename(carpetas))]
  carpetas <- carpetas[vapply(carpetas, function(d)
    length(list.files(d, pattern = "\\.json\\.gz$")) > 0, logical(1))]
  if (length(carpetas) == 0) {
    return(tibble(corrida = character(), fecha = character(), comercios = character()))
  }
  tibble(corrida = basename(carpetas), comercio = basename(dirname(carpetas))) %>%
    group_by(corrida) %>%
    summarise(comercios = paste(sort(comercio), collapse = ", "), .groups = "drop") %>%
    mutate(fecha = sprintf("%s-%s-%s", substr(corrida, 1, 4), substr(corrida, 5, 6), substr(corrida, 7, 8))) %>%
    arrange(desc(corrida)) %>%
    select(corrida, fecha, comercios)
}

# Estado y motivo de la ejecución de un comercio
evaluar_ejecucion <- function(n_obtenidos, verif, comp, n_rechazadas, problemas = character(),
                              repetidos = c(en_seccion = 0L, entre_secciones = 0L)) {
  total_sitio <- if (is.null(verif)) NA_integer_ else sum(verif$total_sitio, na.rm = TRUE)
  incompleta  <- !is.null(verif) &&
    any(is.na(verif$obtenidos) | verif$obtenidos < verif$total_sitio)
  if (n_obtenidos == 0) {
    return(list(estado = "fallida", total_sitio = total_sitio,
                motivo = unir_motivos(c("no se obtuvieron registros", problemas))))
  }
  rep_sec <- repetidos[["en_seccion"]]; rep_entre <- repetidos[["entre_secciones"]]
  motivos <- c(
    if (incompleta) sprintf("se obtuvieron %d de %d productos que informa el sitio",
                            sum(verif$obtenidos, na.rm = TRUE), total_sitio),
    if (rep_sec > 0) sprintf("%d %s entre páginas de una misma sección (la lista del sitio cambió durante la consulta)",
                             rep_sec, if (rep_sec == 1) "SKU repetido" else "SKU repetidos"),
    if (rep_entre > 0) sprintf("%d %s en dos secciones (se conservó una fila)",
                               rep_entre, if (rep_entre == 1) "SKU presente" else "SKU presentes"),
    if (!is.na(comp$motivo)) comp$motivo,
    if (n_rechazadas > 0) sprintf("%d %s por la validación (tabla rechazos)", n_rechazadas,
                                  if (n_rechazadas == 1) "observación rechazada" else "observaciones rechazadas"),
    problemas
  )
  list(
    estado      = if (incompleta || isFALSE(comp$cumple)) "parcial" else "completa",
    total_sitio = total_sitio,
    motivo      = unir_motivos(motivos)
  )
}

# Une motivos en un texto; resume las fallas de solicitudes repetidas
unir_motivos <- function(motivos) {
  motivos <- unique(motivos[!is.na(motivos) & nzchar(motivos)])
  if (length(motivos) == 0) return(NA_character_)
  if (length(motivos) > 4) motivos <- c(motivos[1:4], sprintf("y %d más", length(motivos) - 4))
  paste(motivos, collapse = "; ")
}

# Fila del resumen de un comercio
fila_resumen <- function(cm, estado, motivo, registros = NA, en_categoria = NA, nuevos = NA,
                         subieron = NA, bajaron = NA, no_observados = NA, rechazados = NA,
                         observaciones_nuevas = NA, comparables = NA) {
  tibble(comercio = cm, estado = estado,
         registros = as.integer(registros), en_categoria = as.integer(en_categoria),
         nuevos = as.integer(nuevos), subieron = as.integer(subieron),
         bajaron = as.integer(bajaron), no_observados = as.integer(no_observados),
         rechazados = as.integer(rechazados), comparables = as.integer(comparables),
         observaciones_nuevas = as.integer(observaciones_nuevas), motivo = motivo)
}

# Extrae, limpia y valida un comercio, recogiendo las solicitudes fallidas.
# Si algo falla, devuelve el error con su mensaje en lugar de detener la corrida.
extraer_y_validar <- function(cm, corrida, offline, correspondencia) {
  problemas <- character()
  reiniciar_contador()
  resultado <- tryCatch(
    withCallingHandlers({
      datos <- SCRAPERS[[cm]](corrida = corrida, offline = offline)
      verif <- attr(datos, "verificacion")
      repetidos <- c(en_seccion = attr(datos, "repetidos_en_seccion") %||% 0L,
                     entre_secciones = attr(datos, "repetidos_entre_secciones") %||% 0L)
      datos <- limpiar(datos)
      v     <- validar_observaciones(datos, etiqueta = paste(cm, "- corrida", corrida))
      comp  <- verificar_comparables(v$aceptadas, cm, correspondencia)
      list(datos = datos, verif = verif, repetidos = repetidos, v = v, comp = comp, error = NULL)
    },
    message = function(m) {
      txt <- trimws(conditionMessage(m))
      if (startsWith(txt, PREFIJO_FALLA)) problemas <<- c(problemas, sub(PREFIJO_FALLA, "", txt, fixed = TRUE))
    }),
    error = function(e) list(error = resumir_error(conditionMessage(e)))
  )
  resultado$problemas <- problemas
  resultado
}

# Verificación contra raw/ de una corrida ya cargada: se reprocesan las copias
# crudas y se comparan con las observaciones guardadas (SKU, precio y hora de
# consulta). No escribe nada en la base.
verificar_contra_raw <- function(con, cm, corrida, id_ejecucion, correspondencia) {
  r <- extraer_y_validar(cm, corrida, offline = TRUE, correspondencia)
  if (!is.null(r$error)) {
    return(fila_resumen(cm, "verificación fallida",
                        unir_motivos(c(paste("no se pudo reprocesar raw/:", r$error), r$problemas))))
  }
  crudo <- r$v$aceptadas %>% transmute(sku, precio_raw = precio, fecha_hora_consulta)
  guardado <- observaciones_de_ejecucion(con, id_ejecucion) %>% filter(descartada == 0)
  clave <- c("sku", "fecha_hora_consulta")
  cruce <- inner_join(guardado, crudo, by = clave)
  igual <- (is.na(cruce$precio) & is.na(cruce$precio_raw)) |
           (!is.na(cruce$precio) & !is.na(cruce$precio_raw) & cruce$precio == cruce$precio_raw)
  coinciden <- sum(igual)
  distintas <- nrow(cruce) - coinciden
  solo_base <- nrow(anti_join(guardado, crudo, by = clave))
  solo_raw  <- nrow(anti_join(crudo, guardado, by = clave))
  motivo <- sprintf("ya cargada (ejecución %d); verificación contra raw/: %d de %d observaciones coinciden con la copia cruda",
                    id_ejecucion, coinciden, nrow(guardado))
  if (solo_base + solo_raw + distintas > 0) {
    motivo <- paste0(motivo, sprintf(" (%d solo en la base, %d solo en raw/, %d con precio distinto)",
                                     solo_base, solo_raw, distintas))
  }
  fila_resumen(cm, if (distintas + solo_base + solo_raw == 0) "verificada" else "con diferencias",
               motivo, registros = nrow(r$datos), observaciones_nuevas = 0L)
}

ejecutar_recoleccion <- function(db = "comparador_precios.sqlite",
                                 offline = FALSE, corrida = NULL,
                                 comercios = names(SCRAPERS),
                                 correspondencia = "correspondencia.csv",
                                 devolver_agentes = TRUE) {
  if (offline && is.null(corrida)) {
    stop("En modo sin conexión indique la corrida: el nombre de la carpeta en raw/<comercio>/.")
  }
  if (is.null(corrida)) corrida <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = ZONA)
  if (!grepl("^\\d{8}T\\d{6}$", corrida)) stop("La corrida debe tener el formato AAAAMMDDTHHMMSS.")
  comercios <- intersect(comercios, names(SCRAPERS))
  modo <- if (offline) "sin_conexion" else "en_linea"

  con <- crear_base(db)
  on.exit(dbDisconnect(con), add = TRUE)
  validaciones <- list()   # agente de pointblank de cada comercio, para el informe

  resumen <- map_dfr(comercios, function(cm) {
    inicio <- ahora_co()
    message("== ", cm, " (", if (offline) "sin conexión" else "en línea", ")")

    # Sin conexión, un comercio sin copias crudas de esa corrida no se procesa
    # ni se registra: no hay nada que reprocesar
    if (offline && length(list.files(file.path(DIR_RAW, cm, corrida), pattern = "\\.json\\.gz$")) == 0) {
      return(fila_resumen(cm, "sin copias crudas",
                          sprintf("no hay copias crudas en %s", file.path(DIR_RAW, cm, corrida))))
    }

    previa <- ejecucion_cargada(con, corrida, cm)
    if (!is.null(previa)) {
      if (!offline) return(fila_resumen(cm, "ya cargada", sprintf("corrida ya cargada (ejecución %d)", previa)))
      return(verificar_contra_raw(con, cm, corrida, previa, correspondencia))
    }

    r <- extraer_y_validar(cm, corrida, offline, correspondencia)
    ejecucion <- list(corrida = corrida, id_comercio = cm, inicio = inicio, modo = modo)

    # Falla al extraer o validar: queda registrada como fallida, con el motivo
    if (!is.null(r$error)) {
      ejecucion <- c(ejecucion, list(n_registros = 0L, total_sitio = NA_integer_, estado = "fallida",
                                     motivo = unir_motivos(c(r$error, r$problemas))))
      tryCatch(guardar_ejecucion(con, ejecucion), error = function(e) NULL)
      return(fila_resumen(cm, "fallida", ejecucion$motivo, registros = 0L))
    }

    if (devolver_agentes) validaciones[[cm]] <<- r$v$agente
    n_rechazadas <- nrow(r$datos) - nrow(r$v$aceptadas)
    ev <- evaluar_ejecucion(nrow(r$datos), r$verif, r$comp, n_rechazadas, r$problemas, r$repetidos)
    captura <- if (nrow(r$datos) > 0) range(r$datos$fecha_hora_consulta) else c(NA_character_, NA_character_)
    ejecucion <- c(ejecucion, list(n_registros = nrow(r$datos), total_sitio = ev$total_sitio,
                                   estado = ev$estado, captura_inicio = captura[1],
                                   captura_fin = captura[2], motivo = ev$motivo))

    # Ejecución y datos en una sola transacción; si falla, nada queda escrito
    # y se registra la ejecución como fallida con el error
    res <- tryCatch(guardar_ejecucion(con, ejecucion, r$v$aceptadas, r$v$rechazadas),
                    error = function(e) list(error = conditionMessage(e)))
    if (!is.null(res$error)) {
      ejecucion$estado <- "fallida"
      ejecucion$motivo <- unir_motivos(c(paste("error al guardar en la base:", res$error), ev$motivo))
      ejecucion[c("captura_inicio", "captura_fin")] <- list(NA_character_, NA_character_)
      tryCatch(guardar_ejecucion(con, ejecucion), error = function(e) NULL)
      return(fila_resumen(cm, "fallida", ejecucion$motivo, registros = nrow(r$datos)))
    }

    rs <- resumen_ejecucion(con, res$id_ejecucion)
    fila_resumen(cm, ev$estado, ev$motivo, registros = nrow(r$datos),
                 en_categoria = rs$en_categoria, nuevos = rs$nuevos, subieron = rs$subieron,
                 bajaron = rs$bajaron, no_observados = rs$no_observados,
                 rechazados = n_rechazadas, observaciones_nuevas = res$nuevas,
                 comparables = r$comp$presentes)
  })

  if (file.exists(correspondencia)) {
    tryCatch({
      sin_anuncio <- aplicar_correspondencia(con, correspondencia)
      if (nrow(sin_anuncio) > 0) {
        message("Filas de la correspondencia sin anuncio en la base:")
        print(sin_anuncio)
      }
      verif_corr <- verificar_correspondencia(con)
      if (any(verif_corr$coincide == 0)) {
        message("Comparables que NO coinciden con su producto (revisar):")
        print(filter(verif_corr, coincide == 0))
      }
    }, error = function(e) message("No se pudo aplicar la correspondencia: ", conditionMessage(e)))
  }

  message("Corrida ", corrida, " terminada.")
  print(as.data.frame(resumen))
  invisible(list(corrida = corrida, modo = modo, resumen = resumen,
                 sitios_inaccesibles = !offline && all(resumen$estado == "fallida"),
                 validaciones = validaciones))
}

# -----------------------------------------------------------------------------
# Actualización desde la aplicación
#
# La aplicación publicada es pública: cualquier visitante puede pulsar
# "Actualizar precios". Para no sobrecargar los sitios de los comercios:
#   - entre dos actualizaciones en línea deben pasar al menos
#     ESPERA_EN_LINEA_MIN minutos (cuenta cualquier intento, también los
#     fallidos). El modo sin conexión no tiene límite;
#   - solo corre una actualización a la vez: un candado (una carpeta, que se
#     crea de forma atómica) marca la que está en curso. Un candado de más de
#     CANDADO_MAX_MIN minutos se considera abandonado (por ejemplo, tras un
#     reinicio del servidor) y se reemplaza.
# ejecutar_recoleccion() desde la consola no tiene estas restricciones.
# -----------------------------------------------------------------------------
ESPERA_EN_LINEA_MIN <- 60
CANDADO_MAX_MIN     <- 30

leer_fecha_iso <- function(x) {
  as.POSIXct(sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", x), format = "%Y-%m-%dT%H:%M:%S%z", tz = ZONA)
}

# Minutos que faltan para poder actualizar en línea (0 si ya se puede)
espera_en_linea <- function(db, minutos = ESPERA_EN_LINEA_MIN, ahora = Sys.time()) {
  con <- dbConnect(SQLite(), db)
  on.exit(dbDisconnect(con))
  ultima <- ultima_actualizacion_en_linea(con)
  if (is.na(ultima)) return(list(minutos = 0, ultima = NA, proxima = NA))
  t <- leer_fecha_iso(ultima)
  restante <- max(0, minutos - as.numeric(difftime(ahora, t, units = "mins")))
  list(minutos = ceiling(restante), ultima = t, proxima = t + minutos * 60)
}

tomar_candado <- function(ruta, max_min = CANDADO_MAX_MIN) {
  if (dir.exists(ruta)) {
    edad <- as.numeric(difftime(Sys.time(), file.info(ruta)$mtime, units = "mins"))
    if (edad < max_min) return(FALSE)
    unlink(ruta, recursive = TRUE)            # candado abandonado
  }
  dir.create(ruta, showWarnings = FALSE)      # FALSE si otro proceso lo tomó primero
}

# Versión para la aplicación: lo que devuelve son solo tablas (se ejecuta en
# otro proceso y el resultado vuelve a la aplicación). Si no se puede
# actualizar, devuelve el motivo en $bloqueo sin consultar los sitios.
actualizar_precios <- function(db = "comparador_precios.sqlite", offline = FALSE, corrida = NULL) {
  hora <- function(t) format(t, "%H:%M", tz = ZONA)
  if (!offline) {
    e <- espera_en_linea(db)
    if (e$minutos > 0) {
      return(list(bloqueo = sprintf(paste(
        "La última actualización en línea fue a las %s. Para no sobrecargar los sitios de los",
        "comercios, la siguiente está disponible desde las %s (en %d min). Mientras tanto",
        "puede usar el modo sin conexión."), hora(e$ultima), hora(e$proxima), e$minutos)))
    }
  }
  candado <- file.path(dirname(db), "actualizacion_en_curso.lock")
  if (!tomar_candado(candado)) {
    return(list(bloqueo = sprintf(
      "Ya hay una actualización en curso (iniciada a las %s). Espere a que termine.",
      hora(file.info(candado)$mtime))))
  }
  on.exit(unlink(candado, recursive = TRUE), add = TRUE)
  r <- ejecutar_recoleccion(db = db, offline = offline, corrida = corrida, devolver_agentes = FALSE)
  r$validaciones <- NULL
  r
}
