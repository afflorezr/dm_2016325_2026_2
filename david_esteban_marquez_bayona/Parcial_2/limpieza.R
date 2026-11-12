# limpieza.R — Normalización y correspondencia de productos (reglas R1–R9 del Taller 1).
# Taller 2 · Minería de Datos (2016325) · UNAL · Categoría: cuidado bucal.
#
# Es la versión en R de limpieza.py del Taller 1: mismas reglas, mismo orden y mismos
# identificadores (se verificó reconstruyendo la base desde raw/ y comparándola con la
# entregada). No consulta ningún sitio: trabaja sobre los campos originales que guarda
# scraper.R y escribe los campos estandarizados; nunca modifica el texto original.
#
#   R1 Texto: minúsculas, sin tildes, coma decimal -> punto, sin signos.
#   R2 Marca: marca conocida en el nombre (MARCAS); si no, el campo marca del comercio.
#   R3 Subcategoría: expresiones regulares en orden de prioridad (SUBCATEGORIAS).
#   R4 Exclusión: anuncios de la sección que no son cuidado bucal (EXCLUSIONES).
#   R5 Contenido en mL, g o m y número de unidades; contenido total = unitario x unidades.
#   R6 Concentración de flúor (ppm) o de principio activo (%).
#   R7 Familia: nombre sin tamaño, empaque ni marca; tokens ordenados.
#   R8 Correspondencia: (a) manual, (b) EAN/GTIN válido, (c) clave normalizada.
#   R9 Comparable: presentación con precio disponible en todos los comercios de la
#      ejecución de referencia.
# Nuevo en el Taller 2 (ver README, «Correcciones»):
#   C0 Correcciones registradas a mano en la tabla `correcciones` (se reaplican siempre).
#   C1 Contenido homologado por EAN: si los anuncios de un mismo EAN declaran contenidos
#      distintos (p. ej. 75 mL en un comercio y 100 g en otro), se usa el de la mayoría
#      estricta; si no hay mayoría, la presentación queda sin precio unitario.
#   C2 Subcategoría homologada por EAN con la misma regla de mayoría.

# ---------------------------------------------------------------------------
# Utilidades de expresiones regulares (PCRE, equivalentes a `re` de Python)
# ---------------------------------------------------------------------------
re_buscar <- function(patron, x) {
  m <- regexec(patron, x, perl = TRUE)[[1]]
  if (m[1] == -1) return(NULL)
  list(g = regmatches(x, list(m))[[1]], inicio = as.integer(m[1]))
}
re_hay <- function(patron, x) grepl(patron, x, perl = TRUE)
re_todos <- function(patron, x) {        # matriz: fila 1 = coincidencia, filas 2.. = grupos
  m <- regmatches(x, gregexec(patron, x, perl = TRUE))[[1]]
  if (length(m) == 0) NULL else m
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
es_nulo <- function(x) is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))
fmt_g <- function(x) sprintf("%g", x)                                  # formato «:g» de Python
titulo <- function(s) gsub("(?<![a-z])([a-z])", "\\U\\1", s, perl = TRUE)  # str.title() en ASCII
moda <- function(x) {                    # valor más frecuente; en empate, el primero que aparece
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA)
  u <- unique(x)
  u[which.max(tabulate(match(x, u)))]
}

# ---------------------------------------------------------------------------
# R1 · Texto
# ---------------------------------------------------------------------------
normalizar_texto <- function(s) {
  if (es_nulo(s)) return("")
  s <- stringi::stri_trans_nfkd(as.character(s))
  s <- stringi::stri_replace_all_regex(s, "[^\\p{ccc=0}]", "")        # quita tildes y diéresis
  s <- stringi::stri_trans_tolower(s, locale = "en_US")
  s <- gsub("<[^>]+>", " ", s, perl = TRUE)                           # etiquetas HTML
  s <- gsub("(\\d),(\\d)", "\\1.\\2", s, perl = TRUE)                 # coma decimal
  s <- gsub("-", " ", s, fixed = TRUE)
  s <- gsub("[^a-z0-9.%+ ]+", " ", s, perl = TRUE)
  s <- gsub("(?<!\\d)\\.|\\.(?!\\d)", " ", s, perl = TRUE)            # puntos no decimales
  s <- gsub("\\btotal\\s*12\\b", "total12", s, perl = TRUE)           # números del nombre comercial
  s <- gsub("\\b3\\s*d\\b", "3d", s, perl = TRUE)
  trimws(gsub("\\s+", " ", s, perl = TRUE))
}

# ---------------------------------------------------------------------------
# R2 · Marcas
# ---------------------------------------------------------------------------
MARCAS <- c(
  "colgate palmolive" = "Colgate", "colgate" = "Colgate", "plax" = "Colgate",
  "periogard" = "Colgate", "oral b" = "Oral-B", "oralb" = "Oral-B",
  "sensodyne" = "Sensodyne", "parodontax" = "Parodontax", "listerine" = "Listerine",
  "close up" = "Close Up", "closeup" = "Close Up", "fortident" = "Fortident",
  "pepsodent" = "Pepsodent", "crest" = "Crest", "aquafresh" = "Aquafresh",
  "sunstar gum" = "GUM", "gum" = "GUM", "corega" = "Corega", "fixodent" = "Fixodent",
  "polident" = "Polident", "kin" = "Kin", "vitis" = "Vitis", "bexident" = "Bexident",
  "lacer" = "Lacer", "elmex" = "Elmex", "meridol" = "Meridol", "curaprox" = "Curaprox",
  "tepe" = "TePe", "philips" = "Philips", "sonicare" = "Philips", "kolynos" = "Kolynos",
  "biotene" = "Biotène", "perioaid" = "PerioAid", "perio aid" = "PerioAid",
  "fluocaril" = "Fluocaril", "signal" = "Signal", "dentiplus" = "Dentiplus",
  "encident" = "Encident", "johnson" = "Johnson's", "hexident" = "Hexident"
)   # «clorhexidina» es principio activo, no marca
.MARCAS_ORDEN <- names(MARCAS)[order(-nchar(names(MARCAS)))]          # primero las más largas
.LINEAS <- c("plax", "periogard", "sonicare")
.MARCAS_GENERICAS <- c("", "generico", "generica", "sin marca", "varios", "otros", "otro", "na", "n a")

estandarizar_marca <- function(nombre, marca_sitio) {
  texto <- paste0(" ", normalizar_texto(nombre), " ")
  mejor_pos <- NA_integer_; mejor <- NA_character_
  for (patron in .MARCAS_ORDEN) {
    m <- re_buscar(paste0("(?<![a-z0-9])", patron, "(?![a-z0-9])"), texto)
    if (!is.null(m) && (is.na(mejor_pos) || m$inicio < mejor_pos)) {
      mejor_pos <- m$inicio; mejor <- MARCAS[[patron]]
    }
  }
  if (!is.na(mejor)) return(mejor)
  b <- normalizar_texto(marca_sitio)
  if (b %in% .MARCAS_GENERICAS) return(NA_character_)
  for (patron in .MARCAS_ORDEN) {
    if (b == patron || startsWith(b, paste0(patron, " "))) return(MARCAS[[patron]])
  }
  titulo(b)
}

# ---------------------------------------------------------------------------
# R3 · Subcategorías y R4 · exclusiones
# ---------------------------------------------------------------------------
SUBCATEGORIAS <- list(
  c("Kits y combos", "\\b(kit|kits|combo|combos|estuche|set)\\b"),
  c("Cuidado de prótesis dental", "\\b(protesis|dentadura|dentaduras|adhesivo|adhesiva|fijador|corega|fixodent|polident|retenedor|retenedores)\\b"),
  c("Seda e hilo dental", "\\b(seda|sedas|hilo|hilos|cinta) dental(es)?\\b|\\bfloss|\\bflosser|\\bportahilo|\\barcos? dental"),
  c("Cepillo interdental", "\\b(interdental|interdentales|interproximal|interproximales)\\b"),
  c("Repuesto de cepillo eléctrico", "^(repuesto|repuestos|cabezal|cabezales|refill)\\b|\\b(repuesto|repuestos|cabezales|refill) (de |para )?cepillo"),
  c("Cepillo dental eléctrico", "\\bcepillos?\\b.*\\b(electrico|electricos|bateria|baterias|recargable|pilas|sonico|sonic)\\b"),
  c("Cepillo dental", "\\bcepillos?\\b"),
  c("Crema dental", "\\b(cremas?|pastas?|geles?|gel) (de )?(dental|dentales|dientes)\\b|\\bdentifrico|\\btoothpaste"),
  c("Enjuague bucal", "\\b(enjuague|enjuagues|colutorio|antiseptico bucal|agua bucal|mouthwash|plax|listerine)\\b"),
  c("Blanqueamiento dental", "\\b(blanqueador|blanqueadora|blanqueamiento|tiras blanqueadoras|lapiz blanqueador)\\b"),
  c("Aliento y spray bucal", "\\b(spray|aliento|refrescante bucal)\\b"),
  c("Limpiador lingual", "\\b(lingual|raspador|limpiador de lengua|limpia lengua)\\b")
)
SUBCATEGORIA_RESTO <- "Otros cuidado bucal"
EXCLUSIONES <- paste0(
  "\\b(chicle|chicles|goma de mascar|caramelo|caramelos|bombon|bombones|labial|labiales|",
  "balsamo labial|protector labial|mascota|mascotas|perro|perros|gato|gatos|tapabocas|",
  "termometro|preservativo|preservativos|condon|condones|desodorante|shampoo|jabon corporal)\\b")

# Devuelve list(subcategoria, motivo). Si se excluye, subcategoria = NA.
clasificar <- function(nombre, categoria_sitio) {
  n <- normalizar_texto(nombre)
  ex <- re_buscar(EXCLUSIONES, n)
  if (!is.null(ex)) {
    return(list(subcategoria = NA_character_,
                motivo = paste0("R4: no pertenece a cuidado bucal (", ex$g[1], ")")))
  }
  tipos <- sum(vapply(c("\\bcrema|\\bpasta", "\\bcepillo", "\\benjuague", "\\bseda|\\bhilo"),
                      re_hay, logical(1), x = n))
  if (tipos >= 2 && re_hay("\\+|\\bgratis\\b|\\bobsequio\\b|\\bmas\\b", n)) {
    return(list(subcategoria = "Kits y combos", motivo = NA_character_))
  }
  for (texto in c(n, paste(n, normalizar_texto(categoria_sitio)))) {
    for (s in SUBCATEGORIAS) {
      if (re_hay(s[2], texto)) return(list(subcategoria = s[1], motivo = NA_character_))
    }
  }
  list(subcategoria = SUBCATEGORIA_RESTO, motivo = NA_character_)
}

# ---------------------------------------------------------------------------
# R5 · Contenido y unidades · R6 · concentración
# ---------------------------------------------------------------------------
UNIDADES <- list(
  ml = list("ml", 1), mililitros = list("ml", 1), mililitro = list("ml", 1), cc = list("ml", 1),
  l = list("ml", 1000), lt = list("ml", 1000), lts = list("ml", 1000), litro = list("ml", 1000),
  litros = list("ml", 1000),
  g = list("g", 1), gr = list("g", 1), grs = list("g", 1), gramos = list("g", 1), gramo = list("g", 1),
  kg = list("g", 1000), mg = list("g", 0.001),
  m = list("m", 1), mt = list("m", 1), mts = list("m", 1), metro = list("m", 1), metros = list("m", 1),
  yd = list("m", 0.9144), yds = list("m", 0.9144), yardas = list("m", 0.9144),
  oz = list("oz", 1), onzas = list("oz", 1)
)
.U <- paste(names(UNIDADES)[order(-nchar(names(UNIDADES)))], collapse = "|")
.UND <- "(?:und|unid|unids|unidad|unidades|uds|ud|u|un|tubos|cepillos|piezas|pzs)"
.EMPAQUE <- "(?:caja|tubo|tubos|frasco|frascos|bolsa|paquete|pack|blister|sobre|tarro|botella|und|unidad)"

RE_CONT <- paste0("(?<![a-z0-9.])(\\d+(?:\\.\\d+)?)\\s*(", .U, ")(?![a-z0-9])")
RE_N_ANTES <- paste0("(?<![a-z0-9.])(\\d{1,2})\\s*x\\s*(\\d+(?:\\.\\d+)?)\\s*(", .U, ")(?![a-z0-9])")
RE_N_DESPUES <- paste0("(\\d+(?:\\.\\d+)?)\\s*(?:", .U, ")(?:\\s+", .EMPAQUE,
                       ")?\\s*x\\s*(\\d{1,2})(?![0-9.])(?!\\s*(?:", .U, ")(?![a-z0-9]))")
RE_N_UND <- paste0("(?<![a-z0-9.])(\\d{1,2})\\s*", .UND, "(?![a-z0-9])")
RE_PROMO <- paste0("\\blleve\\s*(\\d{1,2})\\s*pague\\s*\\d{1,2}\\b|\\bpague\\s*\\d{1,2}\\s*lleve\\s*(\\d{1,2})\\b",
                   "|(?<![a-z0-9.])(\\d)\\s*x\\s*(\\d)(?![a-z0-9.])")
RE_N_SOLO <- paste0("(?:\\bx|\\bpack|\\bpaquete|\\bpaq)\\s*(\\d{1,2})(?![0-9.])(?!\\s*(?:", .U, ")(?![a-z0-9]))")
PALABRAS_N <- list(c("\\b(duo|dupla|doble|bipack|twin pack|twinpack)\\b", 2),
                   c("\\b(tripack|tri pack|trio|triple)\\b", 3), c("\\b(tetrapack|cuadruple)\\b", 4))
RE_PPM <- "(\\d{3,5})\\s*ppm\\b"
RE_PCT <- "(?<![a-z0-9.])(\\d+(?:\\.\\d+)?)\\s*%"
RE_ACTIVO <- "clorhexidina|cetilpiridinio|peroxido|triclosan|fluoruro|hexetidina"
SUBCAT_CONTABLES <- c("Cepillo dental", "Cepillo dental eléctrico", "Cepillo interdental",
                      "Repuesto de cepillo eléctrico", "Limpiador lingual")

# Convierte un valor a la unidad base: mL, g o m. normalizar_unidad(1, "l") -> 1000 "ml".
normalizar_unidad <- function(valor, unidad) {
  u <- UNIDADES[[unidad]]
  if (is.null(u)) return(list(valor = NA_real_, unidad = NA_character_))
  list(valor = round(valor * u[[2]], 4), unidad = u[[1]])
}

# Número de unidades del empaque y regla que lo determinó.
extraer_unidades <- function(n) {
  m <- re_buscar(RE_N_ANTES, n)
  if (!is.null(m) && as.integer(m$g[2]) >= 2) return(list(n = as.integer(m$g[2]), regla = "N x contenido"))
  m <- re_buscar(RE_N_DESPUES, n)
  if (!is.null(m) && as.integer(m$g[3]) >= 2) return(list(n = as.integer(m$g[3]), regla = "contenido x N"))
  m <- re_buscar(RE_PROMO, n)
  if (!is.null(m)) {
    g <- m$g[-1]; g <- g[nzchar(g)]
    if (nzchar(m$g[4]) && nzchar(m$g[5])) {                     # forma «3x2»: lleve 3 pague 2
      if (as.integer(m$g[4]) > as.integer(m$g[5])) {
        return(list(n = as.integer(m$g[4]), regla = "promoción lleve N pague M"))
      }
    } else if (length(g) > 0) {
      return(list(n = as.integer(g[1]), regla = "promoción lleve N pague M"))
    }
  }
  m <- re_buscar(RE_N_UND, n)
  if (!is.null(m) && as.integer(m$g[2]) >= 1) return(list(n = as.integer(m$g[2]), regla = "N und"))
  m <- re_buscar(RE_N_SOLO, n)
  if (!is.null(m) && as.integer(m$g[2]) >= 2) return(list(n = as.integer(m$g[2]), regla = "x N"))
  for (p in PALABRAS_N) if (re_hay(p[1], n)) return(list(n = as.integer(p[2]), regla = "palabra de paquete"))
  list(n = 1L, regla = NA_character_)
}

# Contenido unitario, unidades, contenido total y unidad base (R5, R6).
extraer_contenido <- function(nombre, ficha = NULL, subcategoria = NA_character_) {
  n <- normalizar_texto(nombre)
  alerta <- character(0)
  conts <- list()
  cm <- re_todos(RE_CONT, n)
  if (!is.null(cm)) conts <- lapply(seq_len(ncol(cm)), function(j) list(as.numeric(cm[2, j]), cm[3, j]))
  hay_ficha <- !es_nulo(ficha) && nzchar(ficha)
  if (length(conts) == 0 && hay_ficha) {
    f <- normalizar_texto(ficha)
    for (clave in c("contenido", "cantidad", "peso", "volumen", "tamano", "presentacion")) {
      m <- re_buscar(paste0("\\b", clave, "\\w*\\s+(\\d+(?:\\.\\d+)?)\\s*(", .U, ")(?![a-z0-9])"), f)
      if (!is.null(m)) { conts <- list(list(as.numeric(m$g[2]), m$g[3])); break }
    }
  }
  und <- extraer_unidades(n)
  if (is.na(und$regla) && hay_ficha) {
    m <- re_buscar("\\bunidades\\w*( por)?( paquete| empaque)?\\s+(\\d{1,2})\\b", normalizar_texto(ficha))
    if (!is.null(m)) und <- list(n = as.integer(m$g[4]), regla = "ficha técnica")
  }
  cont_unit <- NA_real_; unidad <- NA_character_
  if (length(conts) > 0) {
    bases <- lapply(conts, function(c) normalizar_unidad(c[[1]], c[[2]]))
    cont_unit <- bases[[1]]$valor; unidad <- bases[[1]]$unidad
    claves <- unique(vapply(bases, function(b) paste(b$valor, b$unidad), ""))
    if (length(claves) > 1) {
      if (grepl("+", n, fixed = TRUE) && length(unique(vapply(bases, function(b) b$unidad, ""))) == 1) {
        cont_unit <- round(sum(vapply(bases, function(b) b$valor, 0)), 4)   # suma todos, como el Taller 1
        alerta <- c(alerta, "contenido adicional sumado (+)")
      } else {
        alerta <- c(alerta, "varios contenidos en el nombre; se usa el primero")
      }
    }
  } else if (!is.na(subcategoria) && subcategoria %in% SUBCAT_CONTABLES) {
    cont_unit <- 1; unidad <- "und"
  }
  ppm <- re_buscar(RE_PPM, n)
  pct <- if (re_hay(RE_ACTIVO, n)) re_buscar(RE_PCT, n) else NULL
  concentracion <- if (!is.null(ppm)) paste(ppm$g[2], "ppm")
                   else if (!is.null(pct) && as.numeric(pct$g[2]) > 0) paste(pct$g[2], "%")
                   else NA_character_
  list(contenido_unitario = cont_unit, n_unidades = und$n,
       contenido_total = if (is.na(cont_unit)) NA_real_ else round(cont_unit * und$n, 4),
       unidad = unidad, concentracion = concentracion, alerta = if (length(alerta)) paste(alerta, collapse = "; ") else NA_character_)
}

# ---------------------------------------------------------------------------
# R7 · Familia (producto sin tamaño)
# ---------------------------------------------------------------------------
.GENERICAS <- strsplit(paste(
  "crema cremas pasta pastas dental dentales dientes gel enjuague enjuagues bucal bucales cepillo cepillos",
  "seda hilo cinta oral de del la el los las con para y en x und unid unids unidad unidades uds ud u un",
  "caja tubo tubos frasco frascos bolsa paquete pack paq blister sobre tarro botella oferta precio especial",
  "promo promocion gratis obsequio lleve pague mas antiseptico antibacterial adultos adulto producto"), " ")[[1]]

# list(clave = tokens ordenados, legible = nombre en el orden original)
familia_de <- function(nombre, marca) {
  n <- normalizar_texto(nombre)
  for (rx in c(RE_N_ANTES, RE_N_DESPUES, RE_CONT, RE_PROMO, RE_N_UND, RE_N_SOLO, RE_PPM)) {
    n <- gsub(rx, " ", n, perl = TRUE)
  }
  marca_n <- character(0)
  if (!es_nulo(marca) && nzchar(marca)) {
    marca_n <- strsplit(normalizar_texto(marca), " ", fixed = TRUE)[[1]]
    for (patron in .MARCAS_ORDEN) {
      if (MARCAS[[patron]] == marca && !(patron %in% .LINEAS)) {
        marca_n <- c(marca_n, strsplit(patron, " ", fixed = TRUE)[[1]])
      }
    }
  }
  tokens <- strsplit(trimws(n), "\\s+", perl = TRUE)[[1]]
  tokens <- tokens[nzchar(tokens)]
  ok <- !(tokens %in% .GENERICAS) & !(tokens %in% marca_n) & (nchar(tokens) > 1 | grepl("^[0-9]$", tokens))
  orden <- unique(tokens[ok])
  legible <- titulo(gsub("total12", "total 12", paste(orden, collapse = " "), fixed = TRUE))
  list(clave = paste(sort(orden, method = "radix"), collapse = " "), legible = legible)
}

# Nombre del SKU: el del ítem si contiene al del producto; si no, ambos.
nombre_para_analisis <- function(nombre_producto, nombre_item) {
  p <- trimws(if (es_nulo(nombre_producto)) "" else nombre_producto)
  i <- trimws(if (es_nulo(nombre_item)) "" else nombre_item)
  if (!nzchar(i) || !nzchar(p)) return(if (nzchar(i)) i else p)
  np <- normalizar_texto(p); ni <- normalizar_texto(i)
  if (!nzchar(np) || grepl(np, ni, fixed = TRUE)) return(i)
  if (!nzchar(ni) || grepl(ni, np, fixed = TRUE)) return(p)
  paste(i, p)
}

# Texto del tamaño que acompaña al nombre estándar: «75 ml», «3 x 75 ml», «2 und».
texto_tamano <- function(contenido_total, contenido_unitario, n_unidades, unidad, concentracion) {
  tam <- ""
  if (!is.na(contenido_total)) {
    tam <- paste(fmt_g(contenido_total), unidad)
    if (n_unidades > 1 && unidad != "und") tam <- paste(n_unidades, "x", fmt_g(contenido_unitario), unidad)
  }
  if (!is.na(concentracion)) tam <- trimws(paste0(tam, " (", concentracion, ")"))
  tam
}

# Estandarización completa de un anuncio (R1–R7).
estandarizar <- function(nombre, marca_sitio, categoria_sitio, ficha) {
  cl <- clasificar(nombre, categoria_sitio)
  marca <- estandarizar_marca(nombre, marca_sitio)
  cont <- extraer_contenido(nombre, ficha, cl$subcategoria)
  fam <- familia_de(nombre, marca)
  tam <- texto_tamano(cont$contenido_total, cont$contenido_unitario, cont$n_unidades, cont$unidad, cont$concentracion)
  nombre_std <- paste0(trimws(paste(if (is.na(marca)) "Sin marca" else marca, fam$legible)),
                       if (nzchar(tam)) paste0(" — ", tam) else "")
  py <- function(x) if (is.na(x)) "None" else x          # la clave de familia conserva el formato del Taller 1
  c(list(nombre_std = nombre_std, marca_std = marca, subcategoria_std = cl$subcategoria,
         familia = paste(py(cl$subcategoria), py(marca), fam$clave, sep = "|"),
         incluido = as.integer(is.na(cl$motivo)), motivo_exclusion = cl$motivo), cont)
}

# ---------------------------------------------------------------------------
# R8 · Correspondencia
# ---------------------------------------------------------------------------

# GTIN normalizado a 14 dígitos si el dígito de control es válido; si no, NA.
gtin_valido <- function(codigo) {
  s <- gsub("\\D", "", if (es_nulo(codigo)) "" else as.character(codigo))
  if (!(nchar(s) %in% c(8, 12, 13, 14)) || grepl("^0+$", s)) return(NA_character_)
  d <- as.integer(strsplit(s, "")[[1]])
  cuerpo <- rev(d[-length(d)])
  suma <- sum(cuerpo * ifelse(seq_along(cuerpo) %% 2 == 1, 3, 1))
  if ((10 - suma %% 10) %% 10 == d[length(d)]) paste0(strrep("0", 14 - nchar(s)), s) else NA_character_
}

.clave_nombre <- function(subcat, marca, familia, total, unidad, n_unidades, conc) {
  tam <- if (!is.na(total)) paste0(fmt_g(total), unidad) else "?"
  paste(if (is.na(subcat)) "" else subcat, if (is.na(marca)) "" else marca, familia, tam,
        as.character(n_unidades), if (is.na(conc)) "" else conc, sep = "|")
}
.id_nombre <- function(clave) {
  paste0("N", substr(digest::digest(enc2utf8(clave), algo = "sha1", serialize = FALSE), 1, 12))
}

# Correspondencias manuales del Taller 1: data.frame(comercio_id, sku_comercio, producto_id, nota).
leer_manuales <- function(ruta = "correspondencias_manuales.csv") {
  vacio <- data.frame(comercio_id = character(0), sku_comercio = character(0),
                      producto_id = character(0), nota = character(0))
  if (!file.exists(ruta)) return(vacio)
  d <- tryCatch(utils::read.csv(ruta, colClasses = "character", encoding = "UTF-8", fill = TRUE,
                                comment.char = "", strip.white = TRUE), error = function(e) vacio)
  if (!all(c("comercio_id", "sku_comercio", "producto_id") %in% names(d))) return(vacio)
  if (!"nota" %in% names(d)) d$nota <- ""
  d[nzchar(d$comercio_id) & !startsWith(d$comercio_id, "#"), c("comercio_id", "sku_comercio", "producto_id", "nota")]
}

CAMPOS_CORREGIBLES <- c("subcategoria_std", "marca_std", "contenido_unitario", "n_unidades",
                        "contenido_total", "unidad", "incluido", "nombre_std")

.hay_tabla <- function(con, tabla) {
  DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sqlite_master WHERE name = ?", params = list(tabla))$n > 0
}

# Re-estandariza todos los anuncios, asigna producto_id común y marca comparables.
# Es idempotente y corre dentro de una transacción. Si existe la tabla `correcciones`
# (Taller 2) reaplica las correcciones registradas y las reglas C1 y C2.
actualizar_correspondencias <- function(con, ejecucion_ref = NULL, ruta_manual = "correspondencias_manuales.csv",
                                        min_comercios = 3, fecha = NULL, correcciones = TRUE) {
  DBI::dbWithTransaction(con, .actualizar_correspondencias(con, ejecucion_ref, ruta_manual, min_comercios, fecha,
                                                           correcciones))
}

.actualizar_correspondencias <- function(con, ejecucion_ref, ruta_manual, min_comercios, fecha, correcciones) {
  A <- DBI::dbGetQuery(con, paste(
    "SELECT anuncio_id, comercio_id, sku_comercio, ean, nombre_original, nombre_item_original,",
    "marca_original, categoria_original, ficha_tecnica_original FROM anuncios ORDER BY anuncio_id"))
  n <- nrow(A)
  if (n == 0) return(marcar_comparables(con, ejecucion_ref, min_comercios))
  manuales <- leer_manuales(ruta_manual)
  clave_manual <- paste(manuales$comercio_id, manuales$sku_comercio)

  # 1. Estandarización (R1–R7)
  est <- lapply(seq_len(n), function(i) {
    estandarizar(nombre_para_analisis(A$nombre_original[i], A$nombre_item_original[i]),
                 A$marca_original[i], A$categoria_original[i], A$ficha_tecnica_original[i])
  })
  for (campo in names(est[[1]])) A[[campo]] <- vapply(est, function(e) e[[campo]], est[[1]][[campo]])
  A$gtin <- vapply(A$ean, gtin_valido, "", USE.NAMES = FALSE)
  A$metodo <- NA_character_; A$alerta_corr <- NA_character_; A$producto_id <- NA_character_
  pos_manual <- match(paste(A$comercio_id, A$sku_comercio), clave_manual)
  excl <- !is.na(pos_manual) & toupper(manuales$producto_id[pos_manual]) == "EXCLUIR"
  A$incluido[excl] <- 0L
  A$motivo_exclusion[excl] <- paste0("Manual: ", ifelse(nzchar(manuales$nota[pos_manual[excl]]),
                                                      manuales$nota[pos_manual[excl]], "excluido"))

  # 1b. Correcciones del Taller 2 (C0, C1, C2)
  if (correcciones && .hay_tabla(con, "correcciones")) A <- .aplicar_correcciones(con, A, fecha)

  incl <- which(A$incluido == 1)

  # 2. Grupos por GTIN, separados por número de unidades (R8b)
  con_gtin <- incl[!is.na(A$gtin[incl])]
  for (idx in split(con_gtin, factor(A$gtin[con_gtin], levels = unique(A$gtin[con_gtin])))) {
    gtin <- A$gtin[idx[1]]
    moda_n <- moda(A$n_unidades[idx])
    igual <- A$n_unidades[idx] == moda_n
    conts <- unique(stats::na.omit(A$contenido_total[idx[igual]]))
    A$producto_id[idx[igual]] <- paste0("G", gtin); A$metodo[idx[igual]] <- "EAN"
    if (length(conts) > 1) A$alerta_corr[idx[igual]] <- "EAN con contenidos distintos entre comercios"
    otros <- idx[!igual]
    A$producto_id[otros] <- paste0("G", gtin, "-x", A$n_unidades[otros])
    A$metodo[otros] <- "EAN + unidades"
    A$alerta_corr[otros] <- "mismo EAN con distinto número de unidades"
  }

  # 3. Clave normalizada para los que no tienen GTIN válido (R8c)
  claves <- rep(NA_character_, n)
  claves[incl] <- vapply(incl, function(i) .clave_nombre(
    A$subcategoria_std[i], A$marca_std[i], A$familia[i], A$contenido_total[i], A$unidad[i],
    A$n_unidades[i], A$concentracion[i]), "")
  con_m <- incl[!is.na(A$metodo[incl])]
  clave_a_ean <- lapply(split(A$producto_id[con_m], claves[con_m]), unique)
  for (i in incl[is.na(A$metodo[incl])]) {
    candidatos <- clave_a_ean[[claves[i]]]
    if (length(candidatos) == 1) {
      A$producto_id[i] <- candidatos; A$metodo[i] <- "clave normalizada (unida a EAN)"
    } else {
      A$producto_id[i] <- .id_nombre(claves[i]); A$metodo[i] <- "clave normalizada"
    }
  }

  # 4. Correspondencias manuales (R8a): tienen prioridad
  man <- incl[!is.na(pos_manual[incl]) & !excl[incl]]
  A$producto_id[man] <- manuales$producto_id[pos_manual[man]]; A$metodo[man] <- "manual"

  # 5. Familias unidas a través de productos compartidos (R7), con union-find sobre índices.
  #    La raíz de cada grupo es la familia que va primero en orden de bytes (como en el Taller 1).
  fams <- unique(A$familia[incl])
  rango <- integer(length(fams)); rango[order(enc2utf8(fams), method = "radix")] <- seq_along(fams)
  padre <- seq_along(fams)
  buscar <- function(i) { while (padre[i] != i) i <- padre[i]; i }
  fam_i <- match(A$familia, fams)
  grupos <- split(incl, factor(A$producto_id[incl], levels = unique(A$producto_id[incl])))
  for (g in grupos) {
    for (x in g[-1]) {
      if (identical(A$unidad[x], A$unidad[g[1]])) {
        ra <- buscar(fam_i[g[1]]); rb <- buscar(fam_i[x])
        if (ra != rb) { if (rango[ra] < rango[rb]) padre[rb] <- ra else padre[ra] <- rb }
      }
    }
  }
  A$familia[incl] <- fams[vapply(fam_i[incl], buscar, 1L)]

  # 6. Escritura: primero productos (tabla referenciada), luego anuncios
  DBI::dbExecute(con, "UPDATE anuncios SET producto_id = NULL, comparable = 0")
  DBI::dbExecute(con, "UPDATE observaciones SET comparable = 0")
  DBI::dbExecute(con, "DELETE FROM productos")
  distintos <- function(x) length(unique(x)) > 1
  P <- do.call(rbind, lapply(grupos, function(g) {
    alertas <- unique(c(stats::na.omit(A$alerta_corr[g]),
      if (distintos(A$marca_std[g])) "marcas distintas en el grupo",
      if (distintos(A$subcategoria_std[g])) "subcategorías distintas en el grupo",
      if (distintos(A$contenido_total[g])) "contenidos distintos en el grupo"))
    alertas <- alertas[order(enc2utf8(alertas), method = "radix")]
    nombres <- A$nombre_std[g]; u <- unique(nombres)
    frec <- tabulate(match(nombres, u))
    nombre <- u[order(-frec, nchar(u))[1]]
    par <- unique(data.frame(t = A$contenido_total[g], u = A$unidad[g]))
    data.frame(
      producto_id = A$producto_id[g[1]], nombre_estandar = nombre, marca = moda(A$marca_std[g]),
      subcategoria = moda(A$subcategoria_std[g]), familia = moda(A$familia[g]),
      contenido_unitario = moda(A$contenido_unitario[g]), n_unidades = moda(A$n_unidades[g]),
      contenido_total = moda(A$contenido_total[g]), unidad = moda(A$unidad[g]),
      concentracion = moda(A$concentracion[g]), ean = (A$gtin[g][!is.na(A$gtin[g])])[1],
      metodo_correspondencia = moda(A$metodo[g]), n_comercios = length(unique(A$comercio_id[g])),
      alerta = if (length(alertas)) paste(alertas, collapse = "; ") else NA_character_,
      contenido_verificado = as.integer(nrow(par) == 1 && !is.na(par$t[1]) && !is.na(par$u[1])),
      stringsAsFactors = FALSE)
  }))
  rep_nombre <- P$nombre_estandar %in% P$nombre_estandar[duplicated(P$nombre_estandar)]
  ult6 <- function(s) substr(s, pmax(nchar(s) - 5, 1), nchar(s))
  P$nombre_estandar[rep_nombre] <- paste0(P$nombre_estandar[rep_nombre], " [",
    ifelse(is.na(P$ean[rep_nombre]), ult6(P$producto_id[rep_nombre]), ult6(P$ean[rep_nombre])), "]")
  con_verif <- "contenido_verificado" %in% DBI::dbListFields(con, "productos")
  cols_p <- setdiff(names(P), if (con_verif) character(0) else "contenido_verificado")
  DBI::dbExecute(con, sprintf("INSERT INTO productos (%s) VALUES (%s)", paste(cols_p, collapse = ", "),
                              paste(rep("?", length(cols_p)), collapse = ", ")),
                 params = unname(as.list(P[cols_p])))
  DBI::dbExecute(con, paste(
    "UPDATE anuncios SET nombre_std = ?, marca_std = ?, subcategoria_std = ?, contenido_unitario = ?,",
    "n_unidades = ?, contenido_total = ?, unidad = ?, concentracion = ?, familia = ?, incluido = ?,",
    "motivo_exclusion = ?, alerta_limpieza = ?, ean_valido = ?, metodo_correspondencia = ? WHERE anuncio_id = ?"),
    params = unname(as.list(A[c("nombre_std", "marca_std", "subcategoria_std", "contenido_unitario", "n_unidades",
                                "contenido_total", "unidad", "concentracion", "familia", "incluido",
                                "motivo_exclusion", "alerta", "gtin", "metodo", "anuncio_id")])))
  DBI::dbExecute(con, "UPDATE anuncios SET producto_id = ? WHERE anuncio_id = ?",
                 params = list(A$producto_id[incl], A$anuncio_id[incl]))

  # Nombre legible de la familia: el de su presentación más pequeña
  DBI::dbExecute(con, "DELETE FROM familias")
  DBI::dbExecute(con, paste(
    "INSERT INTO familias (familia, nombre_familia)",
    "SELECT familia, MIN(CASE WHEN instr(nombre_estandar, ' — ') > 0",
    "THEN substr(nombre_estandar, 1, instr(nombre_estandar, ' — ') - 1) ELSE nombre_estandar END)",
    "FROM productos GROUP BY familia"))
  marcar_comparables(con, ejecucion_ref, min_comercios)
}

# ---------------------------------------------------------------------------
# Correcciones del Taller 2: C0 (registradas), C1 y C2 (homologación por EAN)
# ---------------------------------------------------------------------------

.registrar_correccion <- function(con, fecha, anuncio_id, campo, anterior, nuevo, motivo, regla) {
  DBI::dbExecute(con, paste(
    "INSERT OR IGNORE INTO correcciones (fecha, tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo, regla)",
    "VALUES (?, 'anuncios', ?, ?, ?, ?, ?, ?)"),
    params = list(rep(fecha, length(anuncio_id)), as.character(anuncio_id), campo,
                  as.character(anterior), as.character(nuevo), motivo, regla))
}

.aplicar_correcciones <- function(con, A, fecha = NULL) {
  fecha <- fecha %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00", tz = "America/Bogota")
  poner <- function(A, fila, campo, valor) {
    A[[campo]][fila] <- methods::as(valor, class(A[[campo]]))
    A
  }
  # C0: correcciones ya registradas (manuales o de ejecuciones anteriores)
  C <- DBI::dbGetQuery(con, paste(
    "SELECT registro_id, campo, valor_nuevo FROM correcciones",
    "WHERE tabla = 'anuncios' AND activa = 1 ORDER BY correccion_id"))
  C <- C[C$campo %in% CAMPOS_CORREGIBLES, ]
  fila <- match(C$registro_id, as.character(A$anuncio_id))
  for (k in which(!is.na(fila))) A <- poner(A, fila[k], C$campo[k], C$valor_nuevo[k])

  # C1 y C2: mayoría estricta entre los anuncios incluidos del mismo EAN y mismas unidades
  cand <- which(A$incluido == 1 & !is.na(vapply(A$ean, gtin_valido, "", USE.NAMES = FALSE)))
  gt <- vapply(A$ean[cand], gtin_valido, "", USE.NAMES = FALSE)
  for (idx in split(cand, factor(gt, levels = unique(gt)))) {
    if (length(idx) < 2) next
    idx <- idx[A$n_unidades[idx] == moda(A$n_unidades[idx])]
    par <- paste(A$contenido_total[idx], A$unidad[idx])
    validos <- !is.na(A$contenido_total[idx]) & !is.na(A$unidad[idx])
    if (length(unique(par[validos])) > 1 || (any(validos) && any(!validos))) {
      frec <- table(par[validos])
      if (max(frec) * 2 > length(idx)) {                          # mayoría estricta del grupo
        mayor <- names(frec)[which.max(frec)]
        ref <- idx[match(mayor, par)]
        for (i in idx[par != mayor | !validos]) {
          motivo <- sprintf("C1: contenido homologado al de la mayoría de anuncios del EAN %s (%s %s)",
                            A$ean[ref], fmt_g(A$contenido_total[ref]), A$unidad[ref])
          for (campo in c("contenido_total", "unidad", "contenido_unitario")) {
            nuevo <- if (campo == "contenido_unitario") round(A$contenido_total[ref] / A$n_unidades[i], 4) else A[[campo]][ref]
            .registrar_correccion(con, fecha, A$anuncio_id[i], campo, A[[campo]][i], nuevo, motivo, "C1")
            A <- poner(A, i, campo, nuevo)
          }
          tam <- texto_tamano(A$contenido_total[i], A$contenido_unitario[i], A$n_unidades[i], A$unidad[i], A$concentracion[i])
          nuevo <- paste0(sub(" — .*$", "", A$nombre_std[i]), " — ", tam)
          .registrar_correccion(con, fecha, A$anuncio_id[i], "nombre_std", A$nombre_std[i], nuevo, motivo, "C1")
          A$nombre_std[i] <- nuevo
        }
      }
    }
    sub <- A$subcategoria_std[idx]
    if (length(unique(sub)) > 1) {
      frec <- table(sub)
      if (max(frec) * 2 > length(idx)) {
        mayor <- names(frec)[which.max(frec)]
        for (i in idx[is.na(sub) | sub != mayor]) {
          .registrar_correccion(con, fecha, A$anuncio_id[i], "subcategoria_std", A$subcategoria_std[i], mayor,
            sprintf("C2: subcategoría homologada a la de la mayoría de anuncios del EAN %s", A$ean[i]), "C2")
          A$subcategoria_std[i] <- mayor
        }
      }
    }
  }
  A
}

# ---------------------------------------------------------------------------
# R9 · Comparables
# ---------------------------------------------------------------------------

.comercios_ejecucion <- function(con, eid) {
  DBI::dbGetQuery(con, paste("SELECT comercio_id FROM ejecuciones WHERE ejecucion_id = ? AND estado <> 'fallida'",
                             "ORDER BY comercio_id"), params = list(eid))$comercio_id
}

.comunes <- function(con, eid) {
  comercios <- .comercios_ejecucion(con, eid)
  if (length(comercios) == 0) return(character(0))
  sql <- glue::glue_sql(
    "SELECT a.producto_id FROM observaciones o JOIN anuncios a ON a.anuncio_id = o.anuncio_id
      WHERE o.ejecucion_id = {eid} AND a.incluido = 1 AND a.producto_id IS NOT NULL
        AND o.precio IS NOT NULL AND o.disponible = 1 AND o.comercio_id IN ({comercios*})
      GROUP BY a.producto_id HAVING COUNT(DISTINCT o.comercio_id) = {length(comercios)}", .con = con)
  DBI::dbGetQuery(con, sql)$producto_id
}

# Ejecución más reciente con >= min_comercios no fallidos y al menos 8 presentaciones comunes.
elegir_ejecucion_referencia <- function(con, min_comercios = 3) {
  cand <- DBI::dbGetQuery(con, paste(
    "SELECT ejecucion_id FROM ejecuciones WHERE estado <> 'fallida'",
    "GROUP BY ejecucion_id HAVING COUNT(*) >= ? ORDER BY ejecucion_id DESC"),
    params = list(min_comercios))$ejecucion_id
  mejor <- NULL; mejor_n <- -1
  for (eid in cand) {
    k <- length(.comunes(con, eid))
    if (k >= 8) return(eid)
    if (k > mejor_n) { mejor <- eid; mejor_n <- k }
  }
  mejor
}

marcar_comparables <- function(con, ejecucion_ref = NULL, min_comercios = 3) {
  eid <- ejecucion_ref %||% elegir_ejecucion_referencia(con, min_comercios)
  DBI::dbExecute(con, "UPDATE productos SET comparable = 0")
  DBI::dbExecute(con, "UPDATE anuncios SET comparable = 0")
  DBI::dbExecute(con, "UPDATE observaciones SET comparable = 0")
  if (is.null(eid)) return(list(ejecucion_referencia = NULL, comercios = character(0), n_comparables = 0L))
  comunes <- .comunes(con, eid)
  comercios <- .comercios_ejecucion(con, eid)
  if (length(comunes) > 0) {
    DBI::dbExecute(con, "UPDATE productos SET comparable = 1 WHERE producto_id = ?", params = list(comunes))
  }
  DBI::dbExecute(con, glue::glue_sql(
    "UPDATE anuncios SET comparable = 1
      WHERE producto_id IN (SELECT producto_id FROM productos WHERE comparable = 1)
        AND incluido = 1 AND comercio_id IN ({comercios*})", .con = con))
  DBI::dbExecute(con, paste("UPDATE observaciones SET comparable = 1",
                            "WHERE anuncio_id IN (SELECT anuncio_id FROM anuncios WHERE comparable = 1)"))
  DBI::dbExecute(con, "DELETE FROM parametros WHERE clave IN ('ejecucion_referencia', 'comercios_referencia')")
  DBI::dbExecute(con, "INSERT INTO parametros (clave, valor) VALUES (?, ?)",
                 params = list(c("ejecucion_referencia", "comercios_referencia"),
                               c(eid, paste(comercios, collapse = ","))))
  list(ejecucion_referencia = eid, comercios = comercios, n_comparables = length(comunes))
}
