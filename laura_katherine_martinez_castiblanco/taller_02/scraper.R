# =============================================================================
# scraper.R · Módulo de extracción v3 (SOLO FUNCIONES; no se ejecuta al cargarlo)
# Éxito, Carulla, PriceSmart: listado (enlaces) -> ficha individual (JSON-LD > NEXT_DATA > DOM)
# Comunal: listado -> ficha. Modo offline reprocesa raw/ con el mismo parser.
# =============================================================================
if (!exists("CFG")) source("config.R")

suppressPackageStartupMessages({
  library(dplyr); library(purrr); library(stringr); library(stringi)
  library(readr); library(tibble); library(rvest); library(xml2)
  library(DBI);   library(RSQLite); library(digest); library(lubridate)
})

# ------------------------------------------------------------------------------
# 1. UTILIDADES
# ------------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.LOG <- new.env(); .LOG$file <- NULL
log_msg <- function(comercio, msg, nivel = "INFO") {
  linea <- sprintf("[%s][%-5s][%-20s] %s", format(Sys.time(), "%H:%M:%S"), nivel, comercio, msg)
  cat(linea, "\n", sep = ""); flush.console()
  if (!is.null(.LOG$file)) cat(linea, "\n", file = .LOG$file, append = TRUE, sep = "")
}
ahora_iso <- function() {
  x <- format(with_tz(Sys.time(), CFG$tz), "%Y-%m-%dT%H:%M:%S%z")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", x)
}
dir_crear <- function(...) { d <- file.path(...); dir.create(d, recursive = TRUE, showWarnings = FALSE); d }
pausa <- function() Sys.sleep(runif(1, CFG$pausa[1], CFG$pausa[2]))
normalizar <- function(x) {
  x[is.na(x)] <- ""
  str_squish(str_to_lower(stri_trans_general(x, "Latin-ASCII")))
}
slug <- function(x) str_replace_all(normalizar(x), "[^a-z0-9]+", "_")
slug_url <- function(u, n = 40) {                      # parte legible de la URL para nombrar el archivo raw
  s <- str_match(u, "/([^/]+)/p$")[1, 2]
  if (is.na(s)) s <- str_match(u, "/([^/]+)/\\d+$")[1, 2]
  if (is.na(s)) s <- str_match(u, "/([^/]+?)(?:\\.html)?$")[1, 2]
  str_trunc(slug(s %||% "producto"), n, ellipsis = "")
}
css1 <- function(sel) {
  sel <- sel[!is.na(sel) & nzchar(sel)]
  if (!length(sel)) return("html")
  paste(sel, collapse = ", ")
}
nodos_sel <- function(doc, selectores) {
  for (s in selectores[!is.na(selectores)]) {
    n <- tryCatch(html_elements(doc, s), error = function(e) NULL)
    if (!is.null(n) && length(n) > 0) return(n)
  }
  xml2::xml_find_all(doc, ".//__nada__")
}
txt_sel <- function(doc, selectores, min_char = 1L) {
  for (s in selectores[!is.na(selectores)]) {
    el <- tryCatch(html_element(doc, s), error = function(e) NULL)
    if (is.null(el) || length(el) == 0) next
    t <- tryCatch(str_squish(html_text2(el)), error = function(e) NA_character_)
    if (!is.na(t) && nchar(t) >= min_char) return(t)
  }
  NA_character_
}
attr_sel <- function(doc, selectores, atributo = "content") {
  for (s in selectores[!is.na(selectores)]) {
    el <- tryCatch(html_element(doc, s), error = function(e) NULL)
    if (is.null(el) || length(el) == 0) next
    v <- tryCatch(html_attr(el, atributo), error = function(e) NA_character_)
    if (!is.na(v) && nzchar(str_squish(v))) return(str_squish(v))
  }
  NA_character_
}

# ------------------------------------------------------------------------------
# 2. REGLAS DE LIMPIEZA
# ------------------------------------------------------------------------------
PATRON_EXCLUSIONES <- paste0(
  "\\b(teclado|telon|proyector|parlante|bluetooth|celular|televisor|bateria|lego|carro|balon|peluche|",
  "juguete|figura|pinata|colchon|cuadro|cojin|lampara|mug|taza|termo|nevera|dispensador|libro|shampoo|",
  "detergente|jabon|mascota|perro|gato|vinagreta|nachos|dulce|arequipe|molido|liofilizado|grano|tostado|",
  "polvo|sobres?|capsulas?|bolsas?\\s+(de\\s+)?(te|cafe|aromatica|infusion)|filtrante|yerba|matcha|infusion|aromatica|refajo|pola|",
  "cerveza|vino|ron|aguardiente|whisky|vodka|licor|tequila|sidra|",
  "faja|acondicionador|guante|cojin|cojines|pantaloneta|muneca|perfume|crema|lubricante|suavizante|ambientador|",
  "desodorante|vajilla|cuenco|colageno|cafetera|prensa|micelar|oxigenada|destilada|sodastream|ampolletas?|termica|",
  "vaso|copa|jarra|enfriadora|agua de mar|agua de linos|mermelada|vinagre|",
  "gatorade|powerade|electrolit|pedialyte|suero|leche|yogur|kumis|avena)\\b"
)

MARCAS <- c(
  "coca cola" = "COCA-COLA", "pepsi" = "PEPSI", "colombiana" = "COLOMBIANA", "quatro" = "QUATRO",
  "sprite" = "SPRITE", "fanta" = "FANTA", "7 up" = "7UP", "schweppes" = "SCHWEPPES",
  "canada dry" = "CANADA DRY", "premio rojo" = "PREMIO ROJO",
  "manzana postobon" = "POSTOBON", "postobon" = "POSTOBON", "hit" = "HIT", "del valle" = "DEL VALLE",
  "tropicana" = "TROPICANA", "tampico" = "TAMPICO", "alpina" = "ALPINA", "hatsu" = "HATSU",
  "fuze tea" = "FUZE TEA", "nestea" = "NESTEA", "lipton" = "LIPTON", "mr tea" = "MR TEA",
  "red bull" = "RED BULL", "monster" = "MONSTER", "vive 100" = "VIVE 100", "speed max" = "SPEED MAX",
  "cristal" = "CRISTAL", "brisa" = "BRISA", "manantial" = "MANANTIAL", "san pellegrino" = "SAN PELLEGRINO",
  "perrier" = "PERRIER", "evian" = "EVIAN", "vittel" = "VITTEL", "oasis" = "OASIS", "bretana" = "BRETANA"
)
MARCAS <- MARCAS[order(-nchar(names(MARCAS)))]

detectar_marca <- function(txt) {
  t <- str_replace_all(normalizar(txt), "-", " ")        # "coca-cola" -> "coca cola"
  vapply(t, function(x) {
    for (i in seq_along(MARCAS))
      if (str_detect(x, paste0("\\b", names(MARCAS)[i], "\\b"))) return(unname(MARCAS[i]))
    NA_character_
  }, character(1), USE.NAMES = FALSE)
}

determinar_subcategoria <- function(txt) {
  t <- normalizar(txt)
  case_when(
    str_detect(t, "\\b(energizantes?|energy|red bull|monster|vive 100|speed max)\\b")                      ~ "Energizantes",
    str_detect(t, "\\bcafe\\b")                                                                             ~ "Café preparado",
    str_detect(t, "\\b(te|tea|hatsu|fuze|nestea|lipton|mr tea)\\b")                                         ~ "Té preparado",
    str_detect(t, "\\b(jugos?|nectar(es)?|refrescos?|bebida de frutas|hit|del valle|tampico|tropicana|limonadas?|pulpa)\\b") ~ "Jugos",
    str_detect(t, "\\b(gaseosas?|coca cola|pepsi|colombiana|quatro|sprite|fanta|7 up|schweppes|canada dry|tonica|manzana postobon)\\b") ~ "Gaseosas",
    str_detect(t, "\\b(aguas?|cristal|brisa|manantial|pellegrino|perrier|evian|vittel|soda|oasis|bretana)\\b") ~ "Agua",
    TRUE ~ "Sin categorizar"
  )
}

# Montos en COP. Ignora precios por unidad: "(Ml a $ 4,63)", "($ 6/Mililitro)", "$94 /ml".
extraer_montos_cop <- function(texto) {
  texto <- texto[!is.na(texto)]
  if (!length(texto)) return(numeric())
  texto  <- str_replace_all(texto, "\\([^)]*\\)", "|")
  partes <- unlist(str_split(texto, "\\||\\n"))
  partes <- partes[nzchar(str_squish(partes))]
  malas  <- "/|\\bml\\s+a\\b|\\bpor\\s+(ml|l|lt|litro|g|gr|kg|100)|\\b(ml|cc|gr?|kg)\\s*$|\\bx\\s*(ml|l|g|gr|kg|100)\\b"
  partes <- partes[!str_detect(str_to_lower(partes), malas)]
  m <- unlist(str_extract_all(partes, "\\$\\s*\\d[\\d.,]*"))
  m <- m[!str_detect(m, "^\\$\\s*\\d{1,2},\\d{1,2}$")]
  if (!length(m)) return(numeric())
  x <- str_remove(m, "^\\$\\s*")
  x <- str_remove(x, ",\\d{1,2}$")
  x <- str_remove_all(x, "[.,]")
  x <- suppressWarnings(as.numeric(x))
  unique(x[!is.na(x)])
}

# Presentación: unidades, volumen por unidad y total (mL).
# vol_es_total = TRUE (Éxito/Carulla): el "(N ml)" final del nombre ya es el contenido TOTAL del pack.
extraer_volumen <- function(texto, vol_es_total = FALSE) {
  vacio <- list(unidades = NA_integer_, vol_unit_ml = NA_real_, total_ml = NA_real_)
  if (length(texto) != 1 || is.na(texto) || !nzchar(texto)) return(vacio)
  t <- normalizar(texto)
  t <- str_replace_all(t, "(?<=\\d)[.,](?=\\d{3}\\s*(ml|cc|cm3)\\b)", "")
  t <- str_replace_all(t, "(?<=\\d),(?=\\d)", ".")
  vol  <- "(\\d+(?:\\.\\d+)?)\\s*(ml|cc|cm3|l|lt|lts|litro|litros)\\b"
  a_ml <- function(v, u) as.numeric(v) * ifelse(u %in% c("l", "lt", "lts", "litro", "litros"), 1000, 1)
  re_m1 <- paste0("(\\d{1,3})\\s*(?:und|unds|unidades|latas|botellas)?\\s*x\\s*", vol)
  n_pack <- function() {
    m3 <- str_match(t, "(?:pack|paquete|caja|combo)\\s*(?:de|x)?\\s*(\\d{1,3})\\b|\\bx\\s*(\\d{1,3})\\s*(?:und|unds|unidades|latas|botellas)\\b|(\\d{1,3})\\s*(?:unds?|unidades|latas|botellas)\\b")
    as.integer(na.omit(m3[1, 2:4])[1] %||% 1)
  }
  
  if (isTRUE(vol_es_total)) {
    mt <- str_match(t, paste0("\\(\\s*", vol, "\\s*\\)\\s*$"))
    if (!is.na(mt[1, 1])) {
      total <- a_ml(mt[1, 2], mt[1, 3])
      m1 <- str_match(t, re_m1)
      n  <- max(1L, if (!is.na(m1[1, 1])) as.integer(m1[1, 2]) else n_pack())
      return(list(unidades = n, vol_unit_ml = total / n, total_ml = total))
    }
  }
  m1 <- str_match(t, re_m1)
  if (!is.na(m1[1, 1])) {
    n <- as.integer(m1[1, 2]); v <- a_ml(m1[1, 3], m1[1, 4])
    return(list(unidades = n, vol_unit_ml = v, total_ml = n * v))
  }
  m0 <- str_match(t, vol)
  if (is.na(m0[1, 1])) return(vacio)
  v  <- a_ml(m0[1, 2], m0[1, 3])
  m2 <- str_match(t, paste0(vol, "\\s*x\\s*(\\d{1,3})\\b"))
  n  <- if (!is.na(m2[1, 1])) as.integer(m2[1, 4]) else n_pack()
  if (isTRUE(vol_es_total)) return(list(unidades = n, vol_unit_ml = v / n, total_ml = v))
  list(unidades = n, vol_unit_ml = v, total_ml = n * v)
}

extraer_sku_url <- function(href) {
  if (is.na(href)) return(NA_character_)
  str_match(href, "(?:-|/)(\\d{4,})(?:/p|\\.html)?(?:[?#].*)?$")[1, 2]
}

extraer_total_sitio <- function(doc) {
  txt <- tryCatch(html_text(html_element(doc, "body")), error = function(e) "")
  m <- str_match(txt %||% "", "(?i)(\\d{1,3}(?:[.,]\\d{3})*|\\d+)\\s+(?:resultados|productos|art[ií]culos?)")[1, 2]
  if (is.na(m)) NA_integer_ else suppressWarnings(as.integer(str_remove_all(m, "[.,]")))
}

# Disponibilidad con evidencia. El JSON "OutOfStock" NO basta (PriceSmart lo reporta según el club elegido):
# "agotado" exige texto de agotado en la página SIN botón de compra. Sin evidencia -> "no_observado".
inferir_disponibilidad <- function(txt_pag, hay_boton = FALSE, disp_json = NA_character_) {
  if (identical(disp_json, "disponible")) return("disponible")
  agotado_txt <- str_detect(normalizar(txt_pag), "producto agotado|sin existencias|sin stock|no disponible")
  if (agotado_txt && !hay_boton) return("agotado")
  if (hay_boton) return("disponible")
  "no_observado"
}
hay_boton_compra <- function(txt) str_detect(normalizar(txt), "agregar a carrito|agregar al carrito|anadir al carrito|add to cart|pal carrito")

# ------------------------------------------------------------------------------
# 3. ESQUEMAS VACÍOS TIPADOS
# ------------------------------------------------------------------------------
OBS_COLS <- c("id_ejecucion","fecha_hora_consulta","comercio","sku_comercio","sku_origen",
              "producto_raw","texto_original_anuncio","marca_raw","marca_estandarizada",
              "subcategoria","presentacion_raw","unidades","volumen_unit_ml",
              "contenido_total_ml","unidad_medida","precio_cop","precio_lista_cop",
              "es_promocion","disponibilidad","precio_por_litro","url_extraccion",
              "url_producto","url_imagen","archivo_raw","termino_busqueda",
              "comparable","id_producto_comun")
OBS_NUM <- c("precio_cop","precio_lista_cop","volumen_unit_ml","contenido_total_ml","precio_por_litro")
OBS_INT <- c("unidades","es_promocion","comparable")

obs_vacia <- function() {
  l <- setNames(vector("list", length(OBS_COLS)), OBS_COLS)
  for (c in OBS_COLS) l[[c]] <- if (c %in% OBS_NUM) numeric() else if (c %in% OBS_INT) integer() else character()
  as_tibble(l)
}
desc_vacia <- function()
  tibble(id_ejecucion = character(), fecha_hora_consulta = character(), comercio = character(),
         producto_raw = character(), motivo = character(), detalle = character(), archivo_raw = character())
cob_vacia <- function(ctx, cm, n = 0L)
  tibble(id_ejecucion = ctx$id_ejecucion, comercio = cm$nombre,
         termino = ctx$termino %||% NA_character_, tipo = ctx$tipo %||% "busqueda",
         url = ctx$url %||% NA_character_, fecha_hora = ctx$fecha_hora %||% NA_character_,
         total_sitio = NA_integer_, n_tarjetas = as.integer(n),
         n_validos = 0L, n_descartes = 0L, archivo_raw = ctx$archivo_raw %||% NA_character_)

cast_obs <- function(df) {
  if (is.null(df) || !nrow(df)) return(obs_vacia())
  for (c in setdiff(OBS_COLS, names(df))) df[[c]] <- NA
  df <- as.data.frame(df)[, OBS_COLS, drop = FALSE]
  if (all(is.na(df$unidades)) && !all(is.na(df$presentacion_raw)))
    df$unidades <- suppressWarnings(as.integer(str_match(df$presentacion_raw, "^(\\d+)x")[, 2]))
  for (c in OBS_NUM) df[[c]] <- suppressWarnings(as.numeric(df[[c]]))
  for (c in OBS_INT) df[[c]] <- suppressWarnings(as.integer(df[[c]]))
  for (c in setdiff(OBS_COLS, c(OBS_NUM, OBS_INT))) df[[c]] <- as.character(df[[c]])
  df$disponibilidad[is.na(df$disponibilidad)] <- "no_observado"
  df$disponibilidad[!df$disponibilidad %in% c("disponible","agotado","no_observado")] <- "no_observado"
  as_tibble(df)
}

# ------------------------------------------------------------------------------
# 4. CONSTRUCCIÓN DE FILA
# ------------------------------------------------------------------------------
construir_fila_ficha <- function(cm, nombre, texto, precio_actual, precio_lista, href, img,
                                 marca_sitio, sku, descripcion, ctx, disp = NA_character_) {
  nombre <- str_squish(nombre %||% "")
  desc <- function(motivo, detalle = NA_character_) tibble(
    id_ejecucion = ctx$id_ejecucion, fecha_hora_consulta = ctx$fecha_hora, comercio = cm$nombre,
    producto_raw = if (nzchar(nombre)) nombre else NA_character_,
    motivo = motivo, detalle = detalle, archivo_raw = ctx$archivo_raw)
  
  if (!nzchar(nombre)) return(list(obs = NULL, desc = desc("sin_nombre")))
  if (str_detect(normalizar(nombre), PATRON_EXCLUSIONES)) return(list(obs = NULL, desc = desc("fuera_de_categoria")))
  
  texto <- str_trunc(str_squish(texto %||% nombre), 3000, ellipsis = "")
  if (is.na(precio_actual) || precio_actual <= 0) return(list(obs = NULL, desc = desc("sin_precio")))
  if (precio_actual < CFG$precio_min || precio_actual > CFG$precio_max)
    return(list(obs = NULL, desc = desc("precio_fuera_de_rango", as.character(precio_actual))))
  
  # precio de lista solo si es MAYOR (tachado real); si no, queda ausente (NULL), no se inventa
  if (!is.na(precio_lista) && (precio_lista <= precio_actual || precio_lista / precio_actual > 3)) precio_lista <- NA_real_
  
  ves <- isTRUE(cm$volumen_es_total)
  v <- extraer_volumen(nombre, ves)
  if (is.na(v$total_ml)) v <- extraer_volumen(texto, ves)
  if (is.na(v$total_ml) && nzchar(descripcion %||% "")) v <- extraer_volumen(descripcion, ves)
  if (is.na(v$total_ml) || v$total_ml <= 0) return(list(obs = NULL, desc = desc("sin_volumen_liquido")))
  ppl <- if (!is.na(v$total_ml) && v$total_ml > 0) round(precio_actual / (v$total_ml / 1000), 2) else NA_real_
  if (!is.na(ppl) && (ppl < CFG$ppl_min || ppl > CFG$ppl_max))
    return(list(obs = NULL, desc = desc("precio_por_litro_implausible",
                                        sprintf("precio=%s total_ml=%s ppl=%s", precio_actual, v$total_ml, ppl))))
  
  href_abs <- if (!is.na(href %||% NA)) url_absolute(href, cm$base) else NA_character_
  sku_origen <- "atributo"
  if (is.na(sku %||% NA)) { sku <- extraer_sku_url(href_abs); sku_origen <- "url" }
  if (is.na(sku %||% NA)) { sku <- digest(paste(cm$nombre, normalizar(nombre)), algo = "md5"); sku_origen <- "hash_nombre" }
  
  marca_sitio <- str_squish(marca_sitio %||% "")
  if (!nzchar(marca_sitio) || nchar(marca_sitio) > 25 || str_detect(marca_sitio, "\\d")) marca_sitio <- NA_character_
  marca_std <- detectar_marca(nombre)
  if (is.na(marca_std) && !is.na(marca_sitio)) marca_std <- detectar_marca(marca_sitio)
  if (is.na(marca_std) && !is.na(marca_sitio)) marca_std <- str_to_upper(marca_sitio)
  
  obs <- tibble(
    id_ejecucion = ctx$id_ejecucion, fecha_hora_consulta = ctx$fecha_hora, comercio = cm$nombre,
    sku_comercio = paste0(cm$prefijo_sku, "-", sku), sku_origen = sku_origen,
    producto_raw = nombre, texto_original_anuncio = texto,
    marca_raw = marca_sitio, marca_estandarizada = marca_std,
    subcategoria = determinar_subcategoria(nombre),
    presentacion_raw = if (!is.na(v$unidades)) sprintf("%sx%sml", v$unidades, round(v$vol_unit_ml, 1)) else NA_character_,
    unidades = v$unidades, volumen_unit_ml = v$vol_unit_ml, contenido_total_ml = v$total_ml,
    unidad_medida = if (!is.na(v$total_ml)) "ml" else NA_character_,
    precio_cop = precio_actual, precio_lista_cop = precio_lista,
    es_promocion = as.integer(!is.na(precio_lista)),
    disponibilidad = disp %||% "no_observado",
    precio_por_litro = ppl, url_extraccion = ctx$url, url_producto = href_abs,
    url_imagen = if (!is.na(img %||% NA) && !str_starts(img, "data:")) img else NA_character_,
    archivo_raw = ctx$archivo_raw, termino_busqueda = ctx$termino %||% NA_character_,
    comparable = 0L, id_producto_comun = NA_character_
  )
  list(obs = obs, desc = NULL)
}

# ------------------------------------------------------------------------------
# 5. JSON EMBEBIDO (JSON-LD y __NEXT_DATA__)
# ------------------------------------------------------------------------------
num_json <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  v <- x[[1]]
  if (is.null(v) || is.list(v)) return(NA_real_)
  suppressWarnings(as.numeric(str_replace_all(as.character(v), "[^0-9.\\-]", "")))
}
# Texto de un campo JSON. Si es objeto ({"@type":"Brand","name":"X"}) devuelve name/url, no el @type.
chr_json <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  for (k in 1:3) {
    if (!is.list(x)) break
    nm <- names(x)
    if (!is.null(nm) && "name" %in% nm)      x <- x[["name"]]
    else if (!is.null(nm) && "url" %in% nm)  x <- x[["url"]]
    else if (length(x) > 0)                  x <- x[[1]]
    else return(NA_character_)
  }
  if (is.null(x) || length(x) == 0 || is.list(x) || is.na(x[1])) return(NA_character_)
  str_squish(as.character(x[1]))
}
recolectar_productos_json <- function(x, prof = 0L) {
  if (prof > 8L || !is.list(x)) return(list())
  tp <- x[["@type"]]
  if (!is.null(tp) && any(str_detect(tolower(as.character(unlist(tp))), "^product$"))) return(list(x))
  out <- list()
  for (el in x) out <- c(out, recolectar_productos_json(el, prof + 1L))
  out
}
json_ld_productos <- function(html) {
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(list())
  scripts <- tryCatch(html_elements(doc, "script[type='application/ld+json']"), error = function(e) NULL)
  if (!length(scripts)) return(list())
  out <- list()
  for (s in scripts) {
    txt <- tryCatch(html_text(s), error = function(e) NA_character_)
    if (is.na(txt) || !nzchar(str_squish(txt))) next
    j <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(j)) out <- c(out, recolectar_productos_json(j))
  }
  out
}
next_data <- function(html) {
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(NULL)
  el <- tryCatch(html_element(doc, "script#__NEXT_DATA__"), error = function(e) NULL)
  if (is.null(el) || length(el) == 0) return(NULL)
  txt <- tryCatch(html_text(el), error = function(e) NA_character_)
  if (is.na(txt) || !nzchar(txt)) return(NULL)
  tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
}
buscar_producto_next <- function(x, prof = 0L) {
  if (prof > 12L || !is.list(x)) return(NULL)
  nm <- names(x)
  if (!is.null(nm)) {
    if ("name" %in% nm && any(c("sku", "productId", "slug", "id") %in% nm) &&
        any(c("offers", "price", "sellers", "listPrice", "image") %in% nm)) return(x)
    if ("product" %in% nm && is.list(x[["product"]])) {
      r <- buscar_producto_next(x[["product"]], prof + 1L); if (!is.null(r)) return(r)
    }
  }
  for (el in x) { r <- buscar_producto_next(el, prof + 1L); if (!is.null(r)) return(r) }
  NULL
}
ofertas_json <- function(p) {
  of <- p$offers %||% p$Offers %||% NULL
  if (is.null(of)) return(list(precio = NA_real_, lista = NA_real_, disp = NA_character_))
  if (is.null(names(of)) && length(of) > 0) of <- of[[1]]
  if (!is.null(of$offers)) of <- of$offers[[1]] %||% of
  precio <- num_json(of$price %||% of$lowPrice %||% of$priceSpecification$price)
  lista  <- num_json(of$listPrice)
  if (!is.na(lista) && !is.na(precio) && lista <= precio) lista <- NA_real_
  av <- chr_json(of$availability)
  disp <- if (is.na(av)) NA_character_
  else if (str_detect(tolower(av), "outofstock|soldout|discontinued")) "agotado"
  else if (str_detect(tolower(av), "instock|presale|preorder|limited")) "disponible"
  else NA_character_
  list(precio = precio, lista = lista, disp = disp)
}
ofertas_next <- function(p) {
  of <- p$offers %||% NULL
  precio <- NA_real_; lista <- NA_real_; disp <- NA_character_
  if (!is.null(of)) {
    if (is.null(names(of)) && length(of) > 0) of <- of[[1]]
    precio <- num_json(of$lowPrice %||% of$price)
    if (is.na(precio)) {
      sel <- of$sellers
      if (!is.null(sel) && length(sel)) {
        o <- sel[[1]]$commertialOffer %||% sel[[1]]
        precio <- num_json(o$Price %||% o$price)
        lista  <- num_json(o$ListPrice %||% o$listPrice)
        av <- num_json(o$AvailableQuantity)
        if (!is.na(av)) disp <- if (av > 0) "disponible" else "agotado"
      }
    }
  }
  if (is.na(precio)) precio <- num_json(p$price)
  if (is.na(lista))  lista  <- num_json(p$listPrice)
  if (!is.na(lista) && !is.na(precio) && lista <= precio) lista <- NA_real_
  list(precio = precio, lista = lista, disp = disp)
}

# ------------------------------------------------------------------------------
# 6. FASE 1: enlaces de producto desde el listado
# ------------------------------------------------------------------------------
PATRON_URL_PRODUCTO <- "(/p$|/p\\?|/p#|/producto/|-\\d{4,}/p|/pd/)"
PATRON_URL_BASURA   <- "(/s\\?|/buscar|/busqueda|/checkout|/cart|/login|/account|/ayuda|javascript:|^#|/content/|/institucional)"
extraer_links_busqueda <- function(html, clave) {
  cm  <- COMERCIOS[[clave]]
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(character())
  hrefs <- tryCatch(html_attr(html_elements(doc, "a[href]"), "href"), error = function(e) character())
  hrefs <- hrefs[!is.na(hrefs)]
  extra <- character()
  for (s in cm$sel_link_producto[!is.na(cm$sel_link_producto)]) {
    els <- tryCatch(html_elements(doc, s), error = function(e) NULL)
    if (length(els)) extra <- c(extra, html_attr(els, "href"))
  }
  hrefs <- c(hrefs, extra[!is.na(extra)])
  if (!length(hrefs)) return(character())
  links <- ifelse(str_starts(hrefs, "http"), hrefs, tryCatch(url_absolute(hrefs, cm$base), error = function(e) NA_character_))
  links <- links[!is.na(links)]
  links <- str_remove(links, "[?#].*$")
  links <- links[str_detect(links, PATRON_URL_PRODUCTO) & !str_detect(links, PATRON_URL_BASURA)]
  links <- links[str_detect(links, fixed(cm$base, ignore_case = TRUE))]
  unique(links)
}

SECCIONES_BEBIDA <- "bebida|gaseosa|jugo|refresco|energizante|agua|nectar|soda|hidrat|malta|\\bte\\b|infusion|cafe"
buscar_breadcrumb <- function(x, prof = 0L) {
  if (prof > 8L || !is.list(x)) return(NULL)
  tp <- x[["@type"]]
  if (!is.null(tp) && any(str_detect(as.character(unlist(tp)), "BreadcrumbList")))
    return(unlist(lapply(x$itemListElement, function(e) chr_json(e$name %||% e$item$name))))
  for (el in x) { r <- buscar_breadcrumb(el, prof + 1L); if (!is.null(r)) return(r) }
  NULL
}
breadcrumb_ficha <- function(doc) {
  for (s in html_elements(doc, "script[type='application/ld+json']")) {
    j <- tryCatch(jsonlite::fromJSON(html_text(s), simplifyVector = FALSE), error = function(e) NULL)
    r <- if (!is.null(j)) buscar_breadcrumb(j) else NULL
    if (length(r)) return(na.omit(r))
  }
  d <- tryCatch(html_text2(html_elements(doc, "nav[aria-label*='readcrumb'] a, [data-fs-breadcrumb] a, ol.breadcrumb li, [class*='readcrumb'] a")),
                error = function(e) character())
  d[nzchar(d)]
}
# TRUE/FALSE si hay breadcrumb; NA si no se pudo leer (entonces no se filtra por sección)
seccion_es_bebida <- function(bc) if (!length(bc)) NA else any(str_detect(normalizar(bc), SECCIONES_BEBIDA))

# ------------------------------------------------------------------------------
# 7. FASE 2: ficha individual (JSON-LD > __NEXT_DATA__ > Open Graph > DOM)
# ------------------------------------------------------------------------------
parsear_ficha_producto <- function(html, clave, ctx) {
  cm  <- COMERCIOS[[clave]]
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  vacia <- function(motivo, detalle = NA_character_) {
    d <- tibble(id_ejecucion = ctx$id_ejecucion, fecha_hora_consulta = ctx$fecha_hora, comercio = cm$nombre,
                producto_raw = NA_character_, motivo = motivo, detalle = detalle, archivo_raw = ctx$archivo_raw)
    cob <- cob_vacia(ctx, cm, 1L); cob$tipo <- "producto"; cob$n_descartes <- 1L
    list(obs = obs_vacia(), desc = d, cob = cob)
  }
  if (is.null(doc)) return(vacia("html_ilegible"))
  
  nombre <- NA_character_; marca <- NA_character_; sku <- NA_character_
  precio <- NA_real_; lista <- NA_real_; img <- NA_character_
  descr <- NA_character_; disp_json <- NA_character_; fuente <- NA_character_
  
  # (1) JSON-LD
  lds <- json_ld_productos(html)
  if (length(lds)) {
    p <- lds[[1]]; of <- ofertas_json(p)
    nombre <- chr_json(p$name); marca <- chr_json(p$brand)
    sku <- chr_json(p$sku %||% p$mpn %||% p$productID %||% p$gtin13)
    descr <- chr_json(p$description); img <- chr_json(p$image)
    precio <- of$precio; lista <- of$lista; disp_json <- of$disp
    fuente <- "ld+json"
  }
  # (2) __NEXT_DATA__
  if (is.na(nombre) || is.na(precio) || is.na(sku) || is.na(marca)) {
    nd <- next_data(html)
    p2 <- if (!is.null(nd)) buscar_producto_next(nd) else NULL
    if (!is.null(p2)) {
      of2 <- ofertas_next(p2)
      if (is.na(nombre)) nombre <- chr_json(p2$name %||% p2$productName)
      if (is.na(marca))  marca  <- chr_json(p2$brand)
      if (is.na(sku))    sku    <- chr_json(p2$sku %||% p2$productId %||% p2$id)
      if (is.na(descr))  descr  <- chr_json(p2$description)
      if (is.na(precio)) precio <- of2$precio
      if (is.na(lista))  lista  <- of2$lista
      if (is.na(disp_json)) disp_json <- of2$disp
      if (is.na(img)) img <- chr_json(p2$image)
      fuente <- paste(na.omit(c(fuente, "__NEXT_DATA__")), collapse = "+")
    }
  }
  # (3) Open Graph
  if (is.na(nombre)) nombre <- attr_sel(doc, c("meta[property='og:title']", "meta[name='twitter:title']"))
  if (is.na(img))    img    <- attr_sel(doc, c("meta[property='og:image']", "meta[name='twitter:image']"))
  if (is.na(descr))  descr  <- attr_sel(doc, c("meta[property='og:description']", "meta[name='description']"))
  if (is.na(precio)) precio <- num_json(attr_sel(doc, c("meta[property='product:price:amount']", "meta[itemprop='price']")))
  
  # (4) DOM
  if (is.na(nombre)) {
    nombre <- txt_sel(doc, cm$sel_nombre_ficha, min_char = 3L)
    if (!is.na(nombre)) fuente <- paste(na.omit(c(fuente, "dom")), collapse = "+")
  }
  if (is.na(marca)) marca <- txt_sel(doc, cm$sel_marca_ficha)
  if (is.na(descr)) descr <- txt_sel(doc, cm$sel_descripcion_ficha)
  if (is.na(sku))   sku   <- str_extract(txt_sel(doc, cm$sel_sku_ficha) %||% "", "\\d{3,}")
  
  # Precio general mostrado en pantalla (Éxito/Carulla): manda sobre el JSON si difiere
  if (!is.null(cm$sel_precio_general_ficha)) {
    g <- extraer_montos_cop(txt_sel(doc, cm$sel_precio_general_ficha))
    if (length(g)) {
      if (is.na(precio) || abs(precio - min(g)) > 1) fuente <- paste(na.omit(c(fuente, "dom_precio_general")), collapse = "+")
      precio <- min(g)
    }
  }
  if (is.na(precio)) {
    for (s in cm$sel_precio_ficha[!is.na(cm$sel_precio_ficha)]) {
      m <- extraer_montos_cop(txt_sel(doc, s)); if (length(m)) { precio <- min(m); break }
    }
  }
  # Precio de lista (tachado): máximo del bloque de precios si supera al precio general
  if (!is.null(cm$sel_bloque_precios_ficha) && !is.na(precio)) {
    m <- extraer_montos_cop(txt_sel(doc, cm$sel_bloque_precios_ficha)); m <- m[m > precio]
    if (length(m) && (is.na(lista) || lista <= precio)) lista <- max(m)
  }
  if (is.na(lista) || (!is.na(precio) && lista <= precio)) {
    lista <- NA_real_
    for (s in cm$sel_precio_lista_ficha[!is.na(cm$sel_precio_lista_ficha)]) {
      m <- extraer_montos_cop(txt_sel(doc, s)); m <- m[is.na(precio) | m > precio]
      if (length(m)) { lista <- max(m); break }
    }
  }
  if (is.na(img)) img <- attr_sel(doc, cm$sel_imagen_ficha, "src")
  
  # Ficha técnica
  ficha_txt <- tryCatch({
    tb <- html_elements(doc, "table tr, [class*='specification'] tr, [class*='Specification'] li")
    if (length(tb)) paste(html_text2(tb), collapse = " | ") else NA_character_
  }, error = function(e) NA_character_)
  if (is.na(marca) && !is.na(ficha_txt))
    marca <- str_squish(str_match(ficha_txt, "(?:^|\\| )Marca\\s+([^|]+)")[1, 2])
  
  # Disponibilidad
  txt_pag <- tryCatch(str_squish(html_text2(html_element(doc, "body"))), error = function(e) "")
  boton <- length(tryCatch(html_elements(doc, css1(cm$sel_disponibilidad_ficha)), error = function(e) NULL)) > 0 ||
    hay_boton_compra(txt_pag)
  disp <- inferir_disponibilidad(txt_pag, boton, disp_json)
  dl <- ctx$disp_listado %||% NA_character_
  if (!is.na(dl)) disp <- dl
  
  nombre <- str_squish(nombre %||% "")
  nombre <- str_squish(str_remove(nombre, "(?i)\\(\\s*ml\\s+a\\s*\\$.*$"))
  if (!nzchar(nombre)) return(vacia("sin_nombre", paste("url:", ctx$url)))
  if (isTRUE(CFG$filtro_breadcrumb)) {
    bc <- breadcrumb_ficha(doc)
    if (identical(seccion_es_bebida(bc), FALSE))
      return(vacia("fuera_de_seccion_bebida", paste(bc, collapse = " > ")))
  }
  
  texto <- str_trunc(str_squish(paste(nombre, descr %||% "", ficha_txt %||% "")), 3000, ellipsis = "")
  r <- construir_fila_ficha(cm, nombre, texto, precio_actual = precio, precio_lista = lista,
                            href = ctx$url, img = img, marca_sitio = marca, sku = sku,
                            descripcion = paste(descr %||% "", ficha_txt %||% ""), ctx = ctx, disp = disp)
  obs <- cast_obs(r$obs %||% obs_vacia())
  des <- r$desc %||% desc_vacia()
  if (nrow(des)) des$detalle <- paste(na.omit(c(des$detalle, paste("fuente:", fuente))), collapse = " ")
  cob <- cob_vacia(ctx, cm, 1L); cob$tipo <- "producto"
  cob$n_validos <- nrow(obs); cob$n_descartes <- nrow(des)
  list(obs = obs, desc = des, cob = cob)
}

# ------------------------------------------------------------------------------
# 8. COMUNAL (PrestaShop): ficha individual y enlaces
# ------------------------------------------------------------------------------
parsear_producto_comunal <- function(html, ctx) {
  cm  <- COMERCIOS$supercomunal
  doc <- read_html(html)
  nombre <- html_element(doc, "h3.product-title, h1.product-title, [class*='product-title'], h1") |> html_text2()
  p_el   <- html_element(doc, "[itemprop='price'], .current-price span[itemprop='price'], .current-price .price, .product-price .price, span.price")
  p_cont <- suppressWarnings(as.numeric(html_attr(p_el, "content")))
  montos <- if (!is.na(p_cont)) p_cont else extraer_montos_cop(html_text2(p_el))
  tachado <- extraer_montos_cop(html_text2(html_elements(doc, ".regular-price")))
  precio_lista  <- if (length(tachado)) max(tachado) else NA_real_
  precio_actual <- if (length(montos)) min(montos) else NA_real_
  sku <- html_element(doc, "[itemprop='sku'], .reference span, .reference") |> html_text2() |> str_extract("\\d+")
  if (is.na(sku)) sku <- str_match(ctx$url %||% "", "/(\\d+)-")[1, 2]
  descr <- html_element(doc, ".description, .sync-content") |> html_text2()
  txt_pag <- tryCatch(str_squish(html_text2(html_element(doc, "body"))), error = function(e) "")
  disp  <- inferir_disponibilidad(txt_pag, hay_boton_compra(txt_pag), NA_character_)
  texto <- paste(nombre, descr %||% "")
  img   <- attr_sel(doc, c("meta[property='og:image']"), "content")
  if (is.na(img)) img <- attr_sel(doc, c("img[itemprop='image']", ".product-cover img", ".images-container img"), "src")
  if (!is.na(img) && str_detect(tolower(img), "logo")) img <- NA_character_   # el logo del sitio no es la foto del producto
  r <- construir_fila_ficha(cm, nombre, texto, precio_actual, precio_lista,
                            href = ctx$url, img = img, marca_sitio = NA_character_,
                            sku = sku, descripcion = descr, ctx = ctx, disp = disp)
  obs <- cast_obs(r$obs %||% obs_vacia())
  des <- r$desc %||% desc_vacia()
  cob <- cob_vacia(ctx, cm, 1L); cob$tipo <- "producto"
  cob$n_validos <- nrow(obs); cob$n_descartes <- nrow(des)
  list(obs = obs, desc = des, cob = cob)
}

extraer_links_comunal <- function(html) {
  l <- read_html(html) |> html_elements("a") |> html_attr("href")
  l <- l[!is.na(l)]
  l <- l[str_detect(l, "/\\d+-[a-z0-9-]+\\.html") & !str_detect(l, "/13-bebidas|/jolisearch|/content/|/contactenos")]
  l <- ifelse(str_starts(l, "http"), l, url_absolute(l, COMERCIOS$supercomunal$base))
  unique(str_remove(l, "[?#].*$"))
}

parsear_html <- function(html, clave, ctx) {
  if (clave == "supercomunal") parsear_producto_comunal(html, ctx)
  else parsear_ficha_producto(html, clave, ctx)
}

# ------------------------------------------------------------------------------
# 9. CHROME (chromote)
# ------------------------------------------------------------------------------
abrir_sesion <- function(visible = FALSE) {
  if (!requireNamespace("chromote", quietly = TRUE)) stop("Falta el paquete chromote (renv::restore()).")
  b <- chromote::ChromoteSession$new()
  try(b$Emulation$setDeviceMetricsOverride(width = 1366, height = 900, deviceScaleFactor = 1, mobile = FALSE), silent = TRUE)
  try(b$Network$setUserAgentOverride(userAgent = CFG$user_agent), silent = TRUE)
  if (visible) { b$view(); Sys.sleep(2) }
  b
}
navegar <- function(b, url, espera, comercio = "") {
  ok <- tryCatch({ b$Page$navigate(url = url); TRUE },
                 error = function(e) { log_msg(comercio, paste("fallo navigate:", conditionMessage(e)), "WARN"); FALSE })
  Sys.sleep(espera)
  if (ok) esperar_ready(b, comercio)
  invisible(ok)
}
esperar_ready <- function(b, comercio = "", timeout = CFG$timeout_carga) {
  t0 <- Sys.time()
  repeat {
    st <- tryCatch(b$Runtime$evaluate("document.readyState", returnByValue = TRUE)$result$value, error = function(e) "complete")
    if (identical(st, "complete")) return(invisible(TRUE))
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > timeout) {
      log_msg(comercio, "readyState no llego a 'complete' (se continua)", "DEBUG"); return(invisible(FALSE))
    }
    Sys.sleep(0.4)
  }
}
obtener_html <- function(b) b$Runtime$evaluate("document.documentElement.outerHTML", returnByValue = TRUE)$result$value
contar_js <- function(b, sel) {
  js <- sprintf("document.querySelectorAll(%s).length", jsonlite::toJSON(css1(sel), auto_unbox = TRUE))
  v <- tryCatch(b$Runtime$evaluate(js, returnByValue = TRUE)$result$value, error = function(e) 0L)
  if (is.null(v) || length(v) == 0) 0L else as.integer(v)
}
esperar_selector <- function(b, sel, timeout = 12, cada = 0.6) {
  t0 <- Sys.time()
  repeat {
    n <- contar_js(b, sel)
    if (n > 0L) return(n)
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > timeout) return(0L)
    Sys.sleep(cada)
  }
}
cerrar_modales <- function(b) {
  js <- paste0(
    "(function(){",
    "if(!document.querySelector(\"[role='dialog'],[class*='modal'],[class*='Modal']\"))return 0;",
    "var ok=['aceptar','continuar','entendido','cerrar','ahora no','listo'];var n=0;",
    "document.querySelectorAll(\"button,[role='button']\").forEach(function(b){",
    "var t=(b.innerText||'').trim().toLowerCase();",
    "var a=(b.getAttribute('aria-label')||'').toLowerCase();",
    "if((t.length<25&&ok.indexOf(t)>=0)||a.indexOf('cerrar')>=0||a.indexOf('close')>=0){",
    "try{b.click();n++;}catch(e){}}});return n;})()")
  tryCatch(b$Runtime$evaluate(js, returnByValue = TRUE)$result$value %||% 0L, error = function(e) 0L)
}
scroll_hasta_fin <- function(b, sel, comercio, max_scrolls) {
  previo <- -1L; estable <- 0L
  for (i in seq_len(max_scrolls)) {
    try(b$Runtime$evaluate("window.scrollBy(0, Math.max(document.body.scrollHeight*0.85, 800))"), silent = TRUE)
    Sys.sleep(1.2)
    n <- contar_js(b, sel)
    log_msg(comercio, sprintf("   scroll %d/%d -> %d nodos", i, max_scrolls, n), "DEBUG")
    if (n == previo) { estable <- estable + 1L; if (estable >= 2L) break } else estable <- 0L
    previo <- n
  }
  invisible(previo)
}
detectar_bloqueo <- function(html, comercio, visible) {
  titulo <- tryCatch(html_text2(html_element(read_html(html), "title")), error = function(e) "")
  bloqueado <- str_detect(normalizar(titulo %||% ""), "captcha|robot|denied|denegado|forbidden|just a moment|cloudflare|unusual traffic|verific")
  if (bloqueado) {
    log_msg(comercio, sprintf("POSIBLE BLOQUEO (titulo: '%s')", titulo), "WARN")
    if (visible && interactive()) readline("Resuelve el captcha en la ventana de Chrome y pulsa Enter para continuar...")
  }
  bloqueado
}
reducir_html <- function(html) {
  html <- str_replace_all(html, "(?is)<style[^>]*>.*?</style>", "")
  html <- str_replace_all(html, "(?is)<svg[^>]*>.*?</svg>", "")
  str_replace_all(html, "(?is)<script(?![^>]*(?:ld\\+json|__NEXT_DATA__))[\\s\\S]*?</script>", "")
}
guardar_raw <- function(html, carpeta, id_corrida, nombre) {
  dir  <- dir_crear(CFG$dir_raw, carpeta, id_corrida)
  ruta <- file.path(dir, paste0(nombre, ".html.gz"))
  con  <- gzfile(ruta, "wt"); writeLines(reducir_html(html), con, useBytes = TRUE); close(con)
  ruta
}
leer_raw <- function(ruta) paste(readLines(gzfile(ruta), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
capturar_pantalla <- function(b, carpeta, id_corrida, nombre) {
  if (!isTRUE(CFG$pantallas)) return(NA_character_)
  ruta <- file.path(dir_crear(CFG$dir_diag, id_corrida, "pantallas", carpeta), paste0(nombre, ".png"))
  tryCatch({ b$screenshot(ruta, show = FALSE); ruta }, error = function(e) NA_character_)
}
MANIFEST_COLS <- c("id_corrida", "clave", "tipo", "termino", "url", "fecha_hora", "archivo", "bytes",
                   "n_tarjetas", "total_sitio", "pantalla", "disp_listado")
registrar_manifest <- function(fila) {
  ruta <- file.path(dir_crear(CFG$dir_raw), "manifest.csv")
  for (c in setdiff(MANIFEST_COLS, names(fila))) fila[[c]] <- NA
  fila <- fila[, MANIFEST_COLS]
  fila[] <- lapply(fila, as.character)
  if (!file.exists(ruta)) { write_csv(fila, ruta); return(invisible(TRUE)) }
  hdr <- names(read_csv(ruta, n_max = 0, col_types = cols(.default = col_character()), show_col_types = FALSE))
  if (identical(hdr, MANIFEST_COLS)) write_csv(fila, ruta, append = TRUE)
  else {                                            # manifest de una versión anterior: se migra
    ant <- read_csv(ruta, col_types = cols(.default = col_character()), show_col_types = FALSE)
    write_csv(bind_rows(ant, fila), ruta)
  }
  invisible(TRUE)
}
verificar_robots <- function(clave, id_corrida) {
  cm <- COMERCIOS[[clave]]
  tryCatch({
    r <- readLines(paste0(cm$base, "/robots.txt"), warn = FALSE)
    writeLines(r, file.path(dir_crear(CFG$dir_diag, id_corrida, cm$carpeta), paste0("robots_", cm$carpeta, ".txt")))
    log_msg(cm$nombre, sprintf("robots.txt guardado (%d lineas). Revisalo antes de la corrida final.", length(r)))
  }, error = function(e) log_msg(cm$nombre, "no se pudo leer robots.txt", "WARN"))
}

# ------------------------------------------------------------------------------
# 10. VALIDACIÓN PREVIA A LA INSERCIÓN
# ------------------------------------------------------------------------------
validar_obs <- function(obs, ctx_id) {
  obs <- cast_obs(obs)
  if (!nrow(obs)) return(list(ok = obs_vacia(), mal = desc_vacia()))
  motivos <- rep(NA_character_, nrow(obs))
  marcar <- function(cond, motivo) { idx <- which(cond & is.na(motivos)); motivos[idx] <<- motivo }
  marcar(is.na(obs$precio_cop) | obs$precio_cop <= 0, "validacion_precio")
  marcar(is.na(obs$comercio) | !nzchar(obs$comercio), "validacion_comercio")
  marcar(is.na(obs$url_extraccion) & is.na(obs$url_producto), "validacion_url")
  marcar(is.na(obs$fecha_hora_consulta) | !str_detect(obs$fecha_hora_consulta, "^\\d{4}-\\d{2}-\\d{2}T"), "validacion_fecha")
  marcar(is.na(obs$sku_comercio) | !nzchar(obs$sku_comercio), "validacion_sku")
  marcar(duplicated(paste(obs$comercio, obs$sku_comercio)), "validacion_duplicado")
  idx <- which(!is.na(motivos))
  mal <- if (length(idx)) tibble(
    id_ejecucion = obs$id_ejecucion[idx], fecha_hora_consulta = obs$fecha_hora_consulta[idx],
    comercio = obs$comercio[idx], producto_raw = obs$producto_raw[idx], motivo = motivos[idx],
    detalle = paste("sku:", obs$sku_comercio[idx]), archivo_raw = obs$archivo_raw[idx]) else desc_vacia()
  list(ok = obs[is.na(motivos), , drop = FALSE], mal = mal)
}

# ------------------------------------------------------------------------------
# 11. BASE DE DATOS
# ------------------------------------------------------------------------------
db_conectar <- function(path = CFG$db_path) {
  con <- dbConnect(SQLite(), path)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  if ("ejecuciones" %in% dbListTables(con) && !"id_corrida" %in% dbListFields(con, "ejecuciones"))
    stop("La base '", path, "' tiene el esquema ANTIGUO. Muevela a archivo y vuelve a correr.")
  db_crear_esquema(con); con
}
db_crear_esquema <- function(con) {
  sql <- c(
    "CREATE TABLE IF NOT EXISTS ejecuciones(
       id_ejecucion TEXT PRIMARY KEY, id_corrida TEXT NOT NULL, comercio TEXT NOT NULL,
       fecha_inicio TEXT NOT NULL, fecha_fin TEXT, modo TEXT NOT NULL,
       n_registros INTEGER DEFAULT 0, n_descartados INTEGER DEFAULT 0,
       estado TEXT NOT NULL CHECK(estado IN('en_curso','completa','parcial','fallida')), detalle TEXT)",
    "CREATE TABLE IF NOT EXISTS observaciones(
       id_obs INTEGER PRIMARY KEY AUTOINCREMENT,
       id_ejecucion TEXT NOT NULL REFERENCES ejecuciones(id_ejecucion),
       comercio TEXT NOT NULL, fecha_hora_consulta TEXT NOT NULL,
       sku_comercio TEXT NOT NULL, sku_origen TEXT, producto_raw TEXT NOT NULL, texto_original_anuncio TEXT,
       marca_raw TEXT, marca_estandarizada TEXT, subcategoria TEXT, presentacion_raw TEXT, unidades INTEGER,
       volumen_unit_ml REAL, contenido_total_ml REAL, unidad_medida TEXT,
       precio_cop REAL NOT NULL CHECK(precio_cop > 0), precio_lista_cop REAL, es_promocion INTEGER,
       disponibilidad TEXT CHECK(disponibilidad IN('disponible','agotado','no_observado')),
       precio_por_litro REAL, url_extraccion TEXT, url_producto TEXT, url_imagen TEXT,
       archivo_raw TEXT, termino_busqueda TEXT, comparable INTEGER DEFAULT 0, id_producto_comun TEXT,
       UNIQUE(comercio, sku_comercio, fecha_hora_consulta),
       UNIQUE(id_ejecucion, sku_comercio))",
    "CREATE TABLE IF NOT EXISTS descartes(
       id_descarte INTEGER PRIMARY KEY AUTOINCREMENT,
       id_ejecucion TEXT NOT NULL REFERENCES ejecuciones(id_ejecucion),
       comercio TEXT, fecha_hora_consulta TEXT, producto_raw TEXT, motivo TEXT NOT NULL, detalle TEXT, archivo_raw TEXT)",
    "CREATE TABLE IF NOT EXISTS cobertura_sitio(
       id_cobertura INTEGER PRIMARY KEY AUTOINCREMENT,
       id_ejecucion TEXT NOT NULL REFERENCES ejecuciones(id_ejecucion),
       comercio TEXT, termino TEXT, tipo TEXT, url TEXT, fecha_hora TEXT,
       total_sitio INTEGER, n_tarjetas INTEGER, n_validos INTEGER, n_descartes INTEGER, archivo_raw TEXT)",
    "CREATE TABLE IF NOT EXISTS correcciones(
       id_correccion INTEGER PRIMARY KEY AUTOINCREMENT, fecha TEXT NOT NULL, tabla TEXT NOT NULL,
       id_registro TEXT NOT NULL, campo TEXT NOT NULL, valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_obs_comercio_sku ON observaciones(comercio, sku_comercio)",
    "CREATE INDEX IF NOT EXISTS idx_obs_ejecucion    ON observaciones(id_ejecucion)",
    "CREATE INDEX IF NOT EXISTS idx_obs_comparable   ON observaciones(comparable, id_producto_comun)",
    "CREATE INDEX IF NOT EXISTS idx_obs_fecha        ON observaciones(fecha_hora_consulta)",
    "CREATE INDEX IF NOT EXISTS idx_obs_filtros      ON observaciones(subcategoria, marca_estandarizada)",
    "CREATE INDEX IF NOT EXISTS idx_ejec_corrida     ON ejecuciones(id_corrida)"
  )
  for (s in sql) dbExecute(con, s)
  db_crear_vistas(con)
  invisible(TRUE)
}
db_crear_vistas <- function(con) {
  v <- c(
    "CREATE VIEW IF NOT EXISTS v_ultimo_precio AS
       SELECT o.* FROM observaciones o
       JOIN (SELECT comercio, sku_comercio, MAX(fecha_hora_consulta) AS f FROM observaciones GROUP BY comercio, sku_comercio) u
         ON o.comercio = u.comercio AND o.sku_comercio = u.sku_comercio AND o.fecha_hora_consulta = u.f",
    "CREATE VIEW IF NOT EXISTS v_cambios_precio AS
       SELECT comercio, sku_comercio, producto_raw, id_ejecucion, fecha_hora_consulta, precio_cop,
              LAG(precio_cop) OVER w AS precio_anterior, LAG(fecha_hora_consulta) OVER w AS fecha_anterior,
              precio_cop - LAG(precio_cop) OVER w AS delta_cop,
              CASE WHEN LAG(precio_cop) OVER w > 0
                   THEN 100.0*(precio_cop - LAG(precio_cop) OVER w)/LAG(precio_cop) OVER w END AS delta_pct
       FROM observaciones
       WINDOW w AS (PARTITION BY comercio, sku_comercio ORDER BY fecha_hora_consulta)",
    "CREATE VIEW IF NOT EXISTS v_comparables AS
       SELECT * FROM observaciones WHERE comparable = 1 AND id_producto_comun IS NOT NULL"
  )
  for (s in v) try(dbExecute(con, s), silent = TRUE)
  invisible(TRUE)
}
db_guardar_comercio <- function(con, id_ejec, obs, des, cob, estado, detalle) {
  ok <- tryCatch({
    dbBegin(con)
    if (nrow(obs)) {
      cols <- intersect(names(obs), dbListFields(con, "observaciones"))
      dbWriteTable(con, "temp_obs", as.data.frame(obs[, cols, drop = FALSE]), temporary = TRUE, overwrite = TRUE)
      dbExecute(con, sprintf("INSERT OR IGNORE INTO observaciones(%s) SELECT %s FROM temp_obs",
                             paste(cols, collapse = ","), paste(cols, collapse = ",")))
      dbExecute(con, "DROP TABLE IF EXISTS temp_obs")
    }
    if (nrow(des)) dbAppendTable(con, "descartes", as.data.frame(des[, intersect(names(des), dbListFields(con, "descartes"))]))
    if (nrow(cob)) dbAppendTable(con, "cobertura_sitio", as.data.frame(cob[, intersect(names(cob), dbListFields(con, "cobertura_sitio"))]))
    dbExecute(con, "UPDATE ejecuciones SET fecha_fin=?, n_registros=?, n_descartados=?, estado=?, detalle=? WHERE id_ejecucion=?",
              params = list(ahora_iso(), nrow(obs), nrow(des), estado, detalle, id_ejec))
    dbCommit(con); TRUE
  }, error = function(e) {
    try(dbRollback(con), silent = TRUE)
    log_msg(id_ejec, paste("ROLLBACK:", conditionMessage(e)), "ERROR"); FALSE
  })
  if (!ok) dbExecute(con, "UPDATE ejecuciones SET fecha_fin=?, estado='fallida', detalle=? WHERE id_ejecucion=?",
                     params = list(ahora_iso(), "fallo al guardar en SQLite (ver log); datos en datos/staging", id_ejec))
  ok
}

# ------------------------------------------------------------------------------
# 12. PROCESAR UNA CAPTURA
# ------------------------------------------------------------------------------
procesar_captura <- function(acc, clave, html, ctx) {
  cm <- COMERCIOS[[clave]]
  ctx$fecha_hora <- as.character(ctx$fecha_hora)
  r  <- parsear_html(html, clave, ctx)
  r$obs  <- cast_obs(r$obs)
  r$desc <- if (is.null(r$desc) || !nrow(r$desc)) desc_vacia() else r$desc
  skus <- if (nrow(r$obs)) r$obs$sku_comercio else character()
  r$nuevos <- length(setdiff(skus, acc$vistos))
  acc$vistos <- union(acc$vistos, skus)
  acc$obs[[length(acc$obs) + 1]] <- r$obs
  acc$des[[length(acc$des) + 1]] <- r$desc
  acc$cob[[length(acc$cob) + 1]] <- r$cob
  if (nrow(r$obs)) {
    f <- file.path(dir_crear(CFG$dir_staging, ctx$id_corrida), paste0(cm$carpeta, "_observaciones.csv"))
    write_csv(r$obs, f, append = file.exists(f), col_names = !file.exists(f))
  }
  if (identical(ctx$modo, "online"))
    registrar_manifest(tibble(
      id_corrida = ctx$id_corrida, clave = clave, tipo = ctx$tipo, termino = ctx$termino %||% NA_character_,
      url = ctx$url, fecha_hora = ctx$fecha_hora, archivo = ctx$archivo_raw, bytes = file.size(ctx$archivo_raw),
      n_tarjetas = r$cob$n_tarjetas, total_sitio = r$cob$total_sitio, pantalla = ctx$pantalla %||% NA_character_,
      disp_listado = ctx$disp_listado %||% NA_character_))
  log_msg(cm$nombre, sprintf("   [%s] validas=%d nuevos=%d descartes=%d | acumulado=%d",
                             ctx$tipo, nrow(r$obs), r$nuevos, nrow(r$desc), sum(map_int(acc$obs, nrow))))
  invisible(r)
}

# ------------------------------------------------------------------------------
# 13. CAPTURA ONLINE: ÉXITO / CARULLA / PRICESMART (listado -> ficha)
# ------------------------------------------------------------------------------
capturar_dos_fases <- function(clave, id_corrida, id_ejec, b, acc, prueba, visible) {
  cm <- COMERCIOS[[clave]]
  terminos <- if (prueba) head(CFG$busquedas, 2) else CFG$busquedas
  max_p0   <- if (prueba) CFG$paginas_prueba else CFG$max_paginas_busqueda
  max_s    <- if (prueba) 4 else CFG$max_scrolls
  tope_f   <- if (prueba) CFG$fichas_prueba else CFG$max_fichas
  p0 <- cm$pagina_inicial %||% 0
  SEL_CONTEO <- "a[href$='/p'], a[href*='/p?'], a[href*='/producto/']"
  urls <- character(); origen <- character(); dispmap <- character()
  
  # FASE 1: enlaces
  for (i in seq_along(terminos)) {
    term <- terminos[i]; sin_nuevos <- 0L; p <- p0
    max_p <- if (term %in% CFG$busquedas_categoria) max_p0 else min(max_p0, CFG$max_paginas_marca)
    log_msg(cm$nombre, sprintf("FASE 1 [%d/%d] '%s'", i, length(terminos), term))
    while (p < p0 + max_p) {
      url <- sub("{q}", URLencode(term, reserved = TRUE), cm$url_busqueda, fixed = TRUE)
      url <- sub("{p}", as.character(p), url, fixed = TRUE)
      seguir <- tryCatch({
        navegar(b, url, cm$espera, cm$nombre)
        cerrar_modales(b)
        n <- esperar_selector(b, SEL_CONTEO, timeout = 15)
        if (n == 0) n <- esperar_selector(b, "a[href]", timeout = 8)
        scroll_hasta_fin(b, SEL_CONTEO, cm$nombre, max_s)
        t_cap <- ahora_iso(); html <- obtener_html(b)
        detectar_bloqueo(html, cm$nombre, visible)
        links  <- extraer_links_busqueda(html, clave)
        dm <- disp_listado(html, clave)
        if (length(dm)) dispmap[names(dm)] <- dm
        fuera <- vapply(links, function(u) str_detect(str_replace_all(slug_url(u, 200), "_", " "), PATRON_EXCLUSIONES), logical(1))
        if (any(fuera)) {                                  # ahorra visitas: la URL ya delata que no es bebida
          acc$des[[length(acc$des) + 1]] <- tibble(
            id_ejecucion = id_ejec, fecha_hora_consulta = t_cap, comercio = cm$nombre, producto_raw = links[fuera],
            motivo = "fuera_de_categoria_url", detalle = paste("termino:", term), archivo_raw = NA_character_)
          links <- links[!fuera]
        }
        nuevos <- setdiff(links, urls)
        urls   <- c(urls, nuevos); origen <- c(origen, rep(term, length(nuevos)))
        total  <- extraer_total_sitio(read_html(html))
        nom  <- sprintf("listado_%02d_%s_p%02d", i, slug(term), p - p0)
        arch <- guardar_raw(html, cm$carpeta, id_corrida, nom)
        pant <- capturar_pantalla(b, cm$carpeta, id_corrida, nom)
        registrar_manifest(tibble(id_corrida = id_corrida, clave = clave, tipo = "listado", termino = term, url = url,
                                  fecha_hora = t_cap, archivo = arch, bytes = file.size(arch),
                                  n_tarjetas = length(links), total_sitio = total, pantalla = pant))
        acc$cob[[length(acc$cob) + 1]] <- tibble(
          id_ejecucion = id_ejec, comercio = cm$nombre, termino = term, tipo = "listado", url = url, fecha_hora = t_cap,
          total_sitio = total, n_tarjetas = length(links), n_validos = NA_integer_, n_descartes = NA_integer_, archivo_raw = arch)
        log_msg(cm$nombre, sprintf("   p%d: %d enlaces (%d nuevos) | total sitio=%s | URLs=%d",
                                   p - p0 + 1, length(links), length(nuevos), format(total), length(urls)))
        if (p == p0 && !is.na(total) && length(links) > 0) max_p <- min(max_p, max(1, ceiling(total / length(links))))
        sin_nuevos <- if (!length(nuevos)) sin_nuevos + 1L else 0L
        length(links) > 0 && sin_nuevos < 2L
      }, error = function(e) {
        acc$errores <- c(acc$errores, sprintf("listado %s p%d: %s", term, p, conditionMessage(e)))
        log_msg(cm$nombre, sprintf("error listado '%s' p%d: %s", term, p, conditionMessage(e)), "ERROR")
        FALSE
      })
      pausa()
      if (!seguir) break
      p <- p + 1L
    }
  }
  if (!length(urls)) {
    acc$errores <- c(acc$errores, "fase 1: 0 enlaces de producto")
    log_msg(cm$nombre, "FASE 1 sin enlaces: revisa diagnostico/<corrida>/pantallas/", "ERROR")
    return(invisible(NULL))
  }
  if (length(urls) > tope_f) {                      # reparto equitativo entre términos (no solo los primeros)
    rango <- ave(seq_along(urls), origen, FUN = seq_along)
    sel   <- head(order(rango, seq_along(urls)), tope_f)
    log_msg(cm$nombre, sprintf("Tope de fichas: %d de %d (repartidas entre %d terminos)", tope_f, length(urls), length(unique(origen))))
    urls <- urls[sel]; origen <- origen[sel]
  }
  
  # FASE 2: fichas
  log_msg(cm$nombre, sprintf("FASE 2: %d fichas de producto", length(urls)))
  for (i in seq_along(urls)) {
    tryCatch({
      navegar(b, urls[i], cm$espera_ficha %||% 2.5, cm$nombre)
      esperar_selector(b, "h1, script[type='application/ld+json']", timeout = 12)
      t_cap <- ahora_iso(); html <- obtener_html(b)
      nom  <- sprintf("prod_%04d_%s", i, slug_url(urls[i]))
      arch <- guardar_raw(html, cm$carpeta, id_corrida, nom)
      pant <- if (i %% 25 == 1) capturar_pantalla(b, cm$carpeta, id_corrida, nom) else NA_character_
      ctx <- list(id_ejecucion = id_ejec, id_corrida = id_corrida, tipo = "producto", termino = origen[i], url = urls[i],
                  fecha_hora = t_cap, archivo_raw = arch, pantalla = pant, modo = "online",
                  disp_listado = unname(dispmap[urls[i]]))
      log_msg(cm$nombre, sprintf("[%d/%d] %s", i, length(urls), urls[i]))
      procesar_captura(acc, clave, html, ctx)
    }, error = function(e) {
      acc$errores <- c(acc$errores, sprintf("ficha %s: %s", urls[i], conditionMessage(e)))
      log_msg(cm$nombre, sprintf("error ficha %s: %s", urls[i], conditionMessage(e)), "ERROR")
    })
    Sys.sleep(runif(1, CFG$pausa[1], CFG$pausa[2]))
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# 14. CAPTURA ONLINE: COMUNAL
# ------------------------------------------------------------------------------
seccion_comunal_ok <- function(links) {
  seg <- str_match(links, "supermercadocomunal\\.com/([^/]+)/")[, 2]
  is.na(seg) | seg %in% CFG$comunal_secciones_ok
}

capturar_comunal <- function(clave, id_corrida, id_ejec, b, acc, prueba, visible) {
  cm <- COMERCIOS$supercomunal
  urls <- character(); origen_c <- character()
  max_pag <- if (prueba) 1 else CFG$max_paginas_comunal
  for (obj in c(cm$categoria, cm$busquedas)) {
    for (pag in seq_len(max_pag)) {
      url <- if (obj == cm$categoria) sprintf("%s/%s?page=%d", cm$base, obj, pag)
      else sprintf("%s/jolisearch?s=%s&page=%d", cm$base, URLencode(obj, reserved = TRUE), pag)
      seguir <- tryCatch({
        navegar(b, url, cm$espera, cm$nombre)
        t_cap <- ahora_iso(); html <- obtener_html(b)
        detectar_bloqueo(html, cm$nombre, visible)
        links <- extraer_links_comunal(html); if (obj != cm$categoria) links <- links[seccion_comunal_ok(links)]
        nuevos <- setdiff(links, urls); urls <- c(urls, nuevos)
        origen_c <- c(origen_c, rep(obj, length(nuevos)))
        total <- extraer_total_sitio(read_html(html))
        nom  <- sprintf("listado_%s_p%02d", slug(obj), pag)
        arch <- guardar_raw(html, cm$carpeta, id_corrida, nom)
        pant <- capturar_pantalla(b, cm$carpeta, id_corrida, nom)
        registrar_manifest(tibble(id_corrida = id_corrida, clave = clave, tipo = "listado", termino = obj, url = url,
                                  fecha_hora = t_cap, archivo = arch, bytes = file.size(arch),
                                  n_tarjetas = length(links), total_sitio = total, pantalla = pant))
        acc$cob[[length(acc$cob) + 1]] <- tibble(
          id_ejecucion = id_ejec, comercio = cm$nombre, termino = obj, tipo = "listado", url = url, fecha_hora = t_cap,
          total_sitio = total, n_tarjetas = length(links), n_validos = NA_integer_, n_descartes = NA_integer_, archivo_raw = arch)
        log_msg(cm$nombre, sprintf("listado '%s' p%d: %d enlaces (%d nuevos) | total sitio=%s | URLs=%d",
                                   obj, pag, length(links), length(nuevos), format(total), length(urls)))
        length(nuevos) > 0
      }, error = function(e) {
        acc$errores <- c(acc$errores, sprintf("listado %s p%d: %s", obj, pag, conditionMessage(e))); FALSE
      })
      pausa()
      if (!seguir) break
    }
  }
  if (prueba) { urls <- head(urls, CFG$fichas_prueba); origen_c <- head(origen_c, CFG$fichas_prueba) }
  log_msg(cm$nombre, sprintf("FASE 2: %d fichas de producto", length(urls)))
  for (i in seq_along(urls)) {
    tryCatch({
      navegar(b, urls[i], 1.5, cm$nombre)
      t_cap <- ahora_iso(); html <- obtener_html(b)
      nom  <- sprintf("prod_%04d_%s", i, slug_url(urls[i]))
      arch <- guardar_raw(html, cm$carpeta, id_corrida, nom)
      pant <- if (i %% 25 == 1) capturar_pantalla(b, cm$carpeta, id_corrida, nom) else NA_character_
      ctx <- list(id_ejecucion = id_ejec, id_corrida = id_corrida, tipo = "producto", termino = origen_c[i], url = urls[i],
                  fecha_hora = t_cap, archivo_raw = arch, pantalla = pant, modo = "online")
      log_msg(cm$nombre, sprintf("[%d/%d] %s", i, length(urls), urls[i]))
      procesar_captura(acc, clave, html, ctx)
    }, error = function(e) {
      acc$errores <- c(acc$errores, sprintf("%s: %s", urls[i], conditionMessage(e)))
      log_msg(cm$nombre, sprintf("error ficha %s: %s", urls[i], conditionMessage(e)), "ERROR")
    })
    Sys.sleep(runif(1, 1, 2))
  }
}

# ------------------------------------------------------------------------------
# 15. MODO SIN CONEXIÓN (reprocesa raw/ según manifest.csv)
# ------------------------------------------------------------------------------
reprocesar_manifest <- function(clave, id_corrida, id_ejec, acc) {
  cm <- COMERCIOS[[clave]]
  ruta <- file.path(CFG$dir_raw, "manifest.csv")
  if (!file.exists(ruta)) stop("No existe ", ruta)
  m <- read_csv(ruta, col_types = cols(.default = col_character()), show_col_types = FALSE) |>
    filter(.data$id_corrida == !!id_corrida, .data$clave == !!clave, .data$tipo != "listado")
  if (!nrow(m)) stop("El manifest no tiene fichas para ", clave, " en la corrida ", id_corrida)
  log_msg(cm$nombre, sprintf("OFFLINE: %d fichas en el manifest", nrow(m)))
  for (i in seq_len(nrow(m))) {
    f <- m[i, ]
    tryCatch({
      ctx <- list(id_ejecucion = id_ejec, id_corrida = id_corrida, tipo = f$tipo, termino = f$termino, url = f$url,
                  fecha_hora = f$fecha_hora, archivo_raw = f$archivo, pantalla = NA_character_, modo = "offline",
                  disp_listado = f$disp_listado %||% NA_character_)
      procesar_captura(acc, clave, leer_raw(f$archivo), ctx)
    }, error = function(e) acc$errores <- c(acc$errores, sprintf("%s: %s", f$archivo, conditionMessage(e))))
  }
}

# ------------------------------------------------------------------------------
# 16. ORQUESTADOR
# ------------------------------------------------------------------------------
scrapear_comercio <- function(clave, id_corrida, modo, b, con, prueba, visible) {
  cm <- COMERCIOS[[clave]]
  id_ejec <- paste0(id_corrida, "_", cm$carpeta, if (modo == "offline") "_reproc" else "")
  dbExecute(con, "DELETE FROM ejecuciones WHERE id_ejecucion = ?", params = list(id_ejec))
  dbExecute(con, "INSERT INTO ejecuciones(id_ejecucion,id_corrida,comercio,fecha_inicio,modo,estado) VALUES(?,?,?,?,?,'en_curso')",
            params = list(id_ejec, id_corrida, cm$nombre, ahora_iso(), modo))
  acc <- new.env()
  acc$obs <- list(); acc$des <- list(); acc$cob <- list(); acc$errores <- character(); acc$vistos <- character()
  
  tryCatch({
    if (modo == "online") {
      verificar_robots(clave, id_corrida)
      if (clave == "supercomunal") capturar_comunal(clave, id_corrida, id_ejec, b, acc, prueba, visible)
      else capturar_dos_fases(clave, id_corrida, id_ejec, b, acc, prueba, visible)
    } else reprocesar_manifest(clave, id_corrida, id_ejec, acc)
  }, error = function(e) {
    acc$errores <- c(acc$errores, conditionMessage(e)); log_msg(cm$nombre, conditionMessage(e), "ERROR")
  })
  
  obs <- cast_obs(bind_rows(compact(acc$obs)))
  des <- bind_rows(compact(acc$des)); if (!nrow(des)) des <- desc_vacia()
  cob <- bind_rows(compact(acc$cob))
  if (nrow(obs)) {
    n0 <- nrow(obs); obs <- distinct(obs, sku_comercio, .keep_all = TRUE)
    if (n0 > nrow(obs)) log_msg(cm$nombre, sprintf("%d filas repetidas (mismo SKU) colapsadas", n0 - nrow(obs)))
  }
  val <- validar_obs(obs, id_ejec); obs <- val$ok
  if (nrow(val$mal)) {
    des <- bind_rows(des, val$mal)
    log_msg(cm$nombre, sprintf("%d observaciones rechazadas por validacion", nrow(val$mal)), "WARN")
  }
  estado  <- if (!nrow(obs)) "fallida" else if (length(acc$errores)) "parcial" else "completa"
  detalle <- if (length(acc$errores)) paste(head(acc$errores, 10), collapse = "||") else NA_character_
  db_guardar_comercio(con, id_ejec, obs, des, cob, estado, detalle)
  log_msg(cm$nombre, sprintf("FIN: estado=%s registros=%d descartados=%d errores=%d", estado, nrow(obs), nrow(des), length(acc$errores)),
          if (estado == "completa") "INFO" else "WARN")
  invisible(list(estado = estado, n = nrow(obs), id_ejecucion = id_ejec))
}

ejecutar_corrida <- function(comercios = names(COMERCIOS), modo = c("online", "offline"),
                             visible = FALSE, prueba = FALSE, id_corrida = NULL, db_path = NULL) {
  modo <- match.arg(modo)
  desconocidos <- setdiff(comercios, names(COMERCIOS))
  if (length(desconocidos)) stop("Comercio no definido en config.R: ", paste(desconocidos, collapse = ", "))
  
  # ---------------------------------------------------------------------------
  # 1. GESTIÓN Y VALIDACIÓN DE id_corrida (DEBE IR PRIMERO)
  # ---------------------------------------------------------------------------
  if (modo == "online" && is.null(id_corrida)) {
    # En online, si id_corrida es NULL, generamos uno nuevo con estampa de tiempo ISO
    id_corrida <- format(Sys.time(), "%Y%m%d-%H%M%S")
  } else if (modo == "offline") {
    # En offline, se valida de inmediato que id_corrida NO sea NULL
    if (is.null(id_corrida)) stop("En modo offline indica id_corrida (ver raw/manifest.csv).")
    
    id_corrida <- as.character(id_corrida)
    man <- file.path(CFG$dir_raw, "manifest.csv")
    if (!file.exists(man)) stop("No existe ", man)
    
    ids <- unique(read_csv(man, col_types = cols(.default = col_character()), show_col_types = FALSE)$id_corrida)
    if (!id_corrida %in% ids) {
      stop("id_corrida '", id_corrida, "' no está en el manifest. ¿Olvidaste las comillas? Disponibles: ",
           paste(ids, collapse = ", "))
    }
  }
  
  # ---------------------------------------------------------------------------
  # 2. CONFIGURACIÓN DE BASE DE DATOS Y LOGS
  # ---------------------------------------------------------------------------
  if (is.null(db_path)) db_path <- if (modo == "online") CFG$db_path else sub("\\.sqlite$", "_reproc.sqlite", CFG$db_path)
  
  # id_corrida ya tiene un valor válido garantizado en texto
  .LOG$file <- file.path(dir_crear(CFG$dir_diag, id_corrida), if (modo == "online") "scraper.log" else "scraper_offline.log")
  log_msg("CORRIDA", sprintf("id=%s modo=%s visible=%s prueba=%s comercios=%s db=%s",
                             id_corrida, modo, visible, prueba, paste(comercios, collapse = ","), db_path))
  con <- db_conectar(db_path); on.exit(dbDisconnect(con), add = TRUE)
  b <- NULL
  if (modo == "online") { b <- abrir_sesion(visible); on.exit(try(b$close(), silent = TRUE), add = TRUE) }
  res <- map(comercios, function(k) scrapear_comercio(k, id_corrida, modo, b, con, prueba, visible)) |> set_names(comercios)
  print(resumen_corrida(con, id_corrida))
  attr(res, "id_corrida") <- id_corrida
  invisible(res)
}

resumen_corrida <- function(con, id_corrida) {
  dbGetQuery(con,
             "SELECT e.comercio, e.estado, e.n_registros AS validos, e.n_descartados AS descartes,
            (SELECT GROUP_CONCAT(motivo || ':' || n) FROM (SELECT motivo, COUNT(*) n FROM descartes d
              WHERE d.id_ejecucion = e.id_ejecucion GROUP BY motivo)) AS motivos
     FROM ejecuciones e WHERE e.id_corrida = ? ORDER BY e.comercio", params = list(id_corrida))
}

# ------------------------------------------------------------------------------
# 17. DEPURACIÓN (sin red, sobre páginas guardadas en raw/)
#   depurar_ficha("raw/exito/<corrida>/prod_0001_....html.gz", "exito")
# ------------------------------------------------------------------------------
depurar_ficha <- function(archivo, clave = "exito", url = NA_character_) {
  html <- leer_raw(archivo)
  cat("== ARCHIVO:", archivo, "\n")
  lds <- json_ld_productos(html)
  cat("== ld+json Product:", length(lds), "\n")
  if (length(lds)) {
    p <- lds[[1]]; of <- ofertas_json(p)
    cat(sprintf("   name=%s\n   brand=%s\n   sku=%s\n   price=%s list=%s disp=%s\n",
                chr_json(p$name), chr_json(p$brand), chr_json(p$sku), of$precio, of$lista, of$disp %||% "NA"))
  }
  ctx <- list(id_ejecucion = "debug", id_corrida = "debug", tipo = "producto", termino = NA_character_,
              url = url, fecha_hora = ahora_iso(), archivo_raw = archivo, modo = "debug")
  r <- if (clave == "supercomunal") parsear_producto_comunal(html, ctx) else parsear_ficha_producto(html, clave, ctx)
  cat(sprintf("\nRESULTADO: validas=%d descartes=%d\n", nrow(r$obs), nrow(r$desc)))
  if (nrow(r$obs)) print(as.data.frame(r$obs[, c("producto_raw", "marca_raw", "marca_estandarizada", "sku_comercio",
                                                 "precio_cop", "precio_lista_cop", "unidades", "contenido_total_ml", "precio_por_litro", "disponibilidad")]), right = FALSE)
  if (nrow(r$desc)) print(as.data.frame(r$desc[, c("motivo", "detalle")]), right = FALSE)
  invisible(r)
}
depurar_listado <- function(archivo, clave = "exito", n = 10) {
  l <- extraer_links_busqueda(leer_raw(archivo), clave)
  cat("enlaces de producto detectados:", length(l), "\n"); cat(paste(head(l, n), collapse = "\n"), "\n")
  invisible(l)
}


# ------------------------------------------------------------------------------
# 18. Disponibilidad que el sitio rotula en el LISTADO (PriceSmart: "Disponible"/"Agotado").
#     Devuelve un vector con nombre = URL de la ficha.
# ------------------------------------------------------------------------------
disp_listado <- function(html, clave) {
  if (clave != "pricesmart") return(character())
  cm  <- COMERCIOS[[clave]]
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(character())
  a <- html_elements(doc, "a.product-card__title-container")
  if (!length(a)) return(character())
  hrefs <- html_attr(a, "href")
  txt <- vapply(seq_along(a), function(i) {
    anc <- xml2::xml_find_first(a[[i]], "ancestor::*[.//*[contains(@class,'product-card__availability')]][1]")
    if (inherits(anc, "xml_missing")) return(NA_character_)
    el <- xml2::xml_find_first(anc, ".//*[contains(@class,'product-card__availability')]")
    str_squish(xml2::xml_text(el))
  }, character(1))
  n <- normalizar(txt)
  est <- ifelse(is.na(txt), NA_character_,
                ifelse(str_detect(n, "agotado|no disponible|sin stock"), "agotado",
                       ifelse(str_detect(n, "disponible"), "disponible", NA_character_)))
  u <- str_remove(ifelse(str_starts(hrefs, "http"), hrefs, url_absolute(hrefs, cm$base)), "[?#].*$")
  keep <- !is.na(est) & !is.na(u)
  setNames(est[keep], u[keep])
}