# Taller de Web Scraping con R - Parte 2
# 7.2 Ejercicio propuesto: precios de cerveza en Éxito, Carulla y Jumbo

paquetes <- c("rvest", "xml2", "dplyr", "stringr", "purrr",
              "tibble", "readr", "chromote")

tipo <- if (.Platform$OS.type == "windows") "binary" else getOption("pkgType")

pendientes <- setdiff(paquetes, rownames(installed.packages()))
if (length(pendientes) > 0) install.packages(pendientes, type = tipo)

if (packageVersion("rvest") < "1.0.5") install.packages("rvest", type = tipo)
if (packageVersion("rvest") < "1.0.5") {
  stop("Se necesita rvest 1.0.5 o posterior. Reinicie R e intente de nuevo.")
}

invisible(lapply(paquetes, library, character.only = TRUE))

if (is.null(chromote::find_chrome())) {
  stop("No se encontró Google Chrome. Ábralo una vez, ciérrelo y reinicie RStudio.")
}


# Parámetros ------------------------------------------------------------

cervezas <- tibble(
  marca  = c("Michelob", "Stella Artois", "Club Colombia"),
  busqueda = c("michelob", "stella artois", "club colombia"),
  patron = c("michelob", "stella\\s*artois", "club\\s*colombia")
)

supermercados <- tibble(
  supermercado = c("Éxito", "Carulla", "Jumbo"),
  id = c("exito", "carulla", "jumbo"),
  base = c("https://www.exito.com", "https://www.carulla.com",
           "https://www.jumbocolombia.com"),
  plantilla = c("https://www.exito.com/s?q={q}",
                "https://www.carulla.com/s?q={q}",
                "https://www.jumbocolombia.com/{q}?_q={q}&map=ft")
)

pausa         <- 5
espera_max    <- 30
carpeta_html  <- "html_supermercados"
archivo_salida <- "precios_cerveza_supermercados.csv"
dir.create(carpeta_html, showWarnings = FALSE)

construir_url <- function(plantilla, termino) {
  str_replace_all(plantilla, fixed("{q}"), URLencode(termino, reserved = TRUE))
}


# Lectura con read_html_live ---------------------------------------------

# espera a que carguen los productos (enlaces terminados en /p)
leer_busqueda <- function(url, archivo) {
  sesion <- read_html_live(url)
  on.exit(sesion$session$close(), add = TRUE)

  inicio <- Sys.time()
  previos <- -1
  repeat {
    Sys.sleep(3)
    sesion$scroll_by(top = 1200)
    n <- length(html_elements(sesion, "a[href$='/p'], a[href*='/p?']"))
    listo <- n > 0 && n == previos
    tiempo <- as.numeric(difftime(Sys.time(), inicio, units = "secs"))
    if (listo || tiempo > espera_max) break
    previos <- n
  }

  html <- sesion$session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  write_lines(html, archivo)
  html
}


# Extracción -------------------------------------------------------------

a_pesos <- function(x) as.numeric(str_remove_all(x, "[^0-9]"))

# precio de venta, sin el precio por ml/und
precio_tarjeta <- function(texto) {
  lineas <- str_split(texto, "\n")[[1]]
  lineas <- lineas[!str_detect(str_to_lower(lineas),
                               "ml a|x ml|por ml|/ml|x und|und a|unidad|x lt|x kg|gr a")]
  precios <- str_extract_all(paste(lineas, collapse = " "),
                             "\\$\\s*[0-9]{1,3}(\\.[0-9]{3})+|\\$\\s*[0-9]{4,}")[[1]]
  precios <- a_pesos(precios)
  precios <- precios[precios >= 500]
  if (length(precios) == 0) NA_real_ else min(precios)
}

# tarjeta del producto
tarjeta_de <- function(enlace) {
  for (nodo in xml_parents(enlace)) {
    if (xml_name(nodo) %in% c("article", "section")) {
      texto <- html_text2(nodo)
      if (str_detect(texto, "\\$\\s*[0-9]")) return(nodo)
    }
  }
  for (nodo in xml_parents(enlace)) {
    texto <- html_text2(nodo)
    if (str_detect(texto, "\\$\\s*[0-9]")) {
      if (nchar(texto) > 1500) return(NULL)
      return(nodo)
    }
  }
  NULL
}

nombre_tarjeta <- function(enlaces_producto, tarjeta) {
  candidatos <- c(
    html_text2(enlaces_producto),
    html_attr(enlaces_producto, "title"),
    html_attr(enlaces_producto, "aria-label"),
    html_attr(html_elements(tarjeta, "img"), "alt"),
    html_text2(html_elements(tarjeta, "h2, h3, [class*='productTitle'], [class*='productBrand']"))
  )
  candidatos <- str_squish(candidatos[!is.na(candidatos)])
  candidatos <- candidatos[!str_detect(candidatos, "\\$") & candidatos != ""]
  if (length(candidatos) == 0) return(NA_character_)
  candidatos[which.max(nchar(candidatos))]
}

extraer_productos <- function(html, base) {
  pagina <- read_html(html)
  enlaces <- html_elements(pagina, "a[href$='/p'], a[href*='/p?']")
  if (length(enlaces) == 0) stop("No aparecieron productos en la página")

  hrefs <- url_absolute(html_attr(enlaces, "href"), base) %>%
    str_remove("\\?.*$")

  map_dfr(unique(hrefs), function(h) {
    del_producto <- enlaces[hrefs == h]
    tarjeta <- tarjeta_de(del_producto[[1]])
    if (is.null(tarjeta)) return(NULL)

    texto_tarjeta <- html_text2(tarjeta)
    if (!str_detect(texto_tarjeta, "\n")) {
      texto_tarjeta <- paste(html_text2(html_elements(tarjeta, "div, span, p")), collapse = "\n")
    }

    tibble(
      presentacion = nombre_tarjeta(del_producto, tarjeta),
      precio       = precio_tarjeta(texto_tarjeta),
      enlace       = h
    )
  })
}


# Recorrido por supermercado y cerveza -----------------------------------

consultar <- function(supermercado, id, base, plantilla, marca, busqueda) {
  url <- construir_url(plantilla, busqueda)
  archivo <- file.path(carpeta_html, paste0(
    id, "_", str_replace_all(busqueda, " ", "_"), ".html"))

  message(supermercado, " - ", marca)
  html <- if (file.exists(archivo)) {
    paste(read_lines(archivo), collapse = "\n")
  } else {
    Sys.sleep(pausa)
    leer_busqueda(url, archivo)
  }

  extraer_productos(html, base) %>%
    mutate(supermercado = supermercado, marca_buscada = marca, url_busqueda = url)
}

consultar_seguro <- safely(consultar)

combinaciones <- merge(supermercados, cervezas, by = NULL) %>%
  as_tibble()

respuestas <- pmap(
  list(combinaciones$supermercado, combinaciones$id, combinaciones$base,
       combinaciones$plantilla,
       combinaciones$marca, combinaciones$busqueda),
  consultar_seguro
)

errores <- combinaciones %>%
  select(supermercado, marca) %>%
  mutate(error = map_chr(respuestas, ~ if (is.null(.x$error)) NA_character_
                                       else conditionMessage(.x$error))) %>%
  filter(!is.na(error))

errores

resultados <- respuestas %>%
  map("result") %>%
  compact() %>%
  list_rbind()

if (is.null(resultados) || nrow(resultados) == 0) {
  stop("No se obtuvo ningún producto. Revise la tabla 'errores'.")
}


# Limpieza y filtro de productos -----------------------------------------

# volumen total en ml
numero <- function(x) {
  x <- if_else(str_detect(x, "^\\d{1,3}\\.\\d{3}$"), str_remove(x, "\\."), x)
  as.numeric(str_replace(x, ",", "."))
}

unidades_paquete <- function(p) {
  p <- str_to_lower(p)
  n <- coalesce(
    numero(str_match(p, "x\\s*(\\d+)\\s*(und|unid|unidades|uds|un)\\b")[, 2]),
    numero(str_match(p, "(\\d+)\\s*(und|unidades|latas|botellas)\\b")[, 2]),
    numero(str_match(p, "x\\s*(\\d+)(?!\\d|\\s*(ml|cc|l\\b|lt))")[, 2]),
    if_else(str_detect(p, "six\\s*-?\\s*pack|sixpack"), 6, NA_real_),
    if_else(str_detect(p, "\\bfour\\b"), 4, NA_real_)
  )
  coalesce(n, 1)
}

volumen_ml <- function(p) {
  p <- str_to_lower(p)
  total_parentesis <- numero(str_match(p, "\\((\\d+[.,]?\\d*)\\s*ml\\)")[, 2])
  ml <- coalesce(
    numero(str_match(p, "(\\d+[.,]?\\d*)\\s*(ml|cc)\\b")[, 2]),
    numero(str_match(p, "\\b(\\d{3})\\s*c-?u\\b")[, 2])
  )
  litros <- numero(str_match(p, "(\\d+[.,]?\\d*)\\s*(l|lt|lts|litros?)\\b")[, 2]) * 1000
  base <- coalesce(ml, litros)
  n <- unidades_paquete(p)

  case_when(
    !is.na(total_parentesis) ~ total_parentesis,
    is.na(base)              ~ NA_real_,
    n > 1 & base <= 1000     ~ base * n,
    TRUE                     ~ base
  )
}

inferir_unidades <- function(total) {
  tamanos <- c(269, 330, 355, 300, 473, 250, 210)
  exacto <- tamanos[total %% tamanos == 0 & total / tamanos <= 30]
  if (length(exacto) == 0) 1 else total / exacto[1]
}

patron_no_cerveza <- "llanta|neum[aá]tico|destapador|camiseta|nevera|gorra|combo|pasabocas"
patron_accesorio  <- "vaso|copa|c[aá]liz"

precios <- resultados %>%
  left_join(cervezas %>% select(marca, patron), by = c("marca_buscada" = "marca")) %>%
  mutate(presentacion = str_squish(presentacion),
         texto = str_to_lower(presentacion)) %>%
  filter(
    !is.na(presentacion), !is.na(precio),
    str_detect(texto, patron),
    !str_detect(texto, patron_no_cerveza),
    !(str_detect(texto, patron_accesorio) & !str_detect(texto, "cerveza"))
  ) %>%
  mutate(
    unidades   = unidades_paquete(presentacion),
    volumen_ml = volumen_ml(presentacion),
    unidades   = if_else(unidades == 1 & !is.na(volumen_ml) & volumen_ml > 750,
                         map_dbl(volumen_ml, inferir_unidades), unidades),
    ml_unidad  = volumen_ml / unidades,
    precio_ml  = precio / volumen_ml
  ) %>%
  distinct(supermercado, enlace, .keep_all = TRUE) %>%
  select(supermercado, marca = marca_buscada, presentacion, precio,
         unidades, volumen_ml, ml_unidad, precio_ml, enlace, url_busqueda)

precios %>% count(supermercado, marca)

write_excel_csv(precios, archivo_salida)


# Preguntas ---------------------------------------------------------------

# 1.
p1 <- precios %>%
  group_by(marca) %>%
  slice_min(precio, n = 1, with_ties = TRUE) %>%
  select(marca, supermercado, presentacion, precio)
p1

# 2.
p2 <- precios %>%
  filter(!is.na(precio_ml)) %>%
  group_by(supermercado) %>%
  summarise(productos = n(), precio_ml_promedio = mean(precio_ml)) %>%
  arrange(precio_ml_promedio)
p2

# 3.
p3 <- precios %>%
  filter(!is.na(precio_ml)) %>%
  group_by(marca, supermercado) %>%
  summarise(precio_ml_promedio = mean(precio_ml), .groups = "drop_last") %>%
  slice_min(precio_ml_promedio, n = 1) %>%
  ungroup()
p3

n_distinct(p3$supermercado) == 1

# 4.
individuales <- precios %>%
  filter(unidades == 1, !is.na(volumen_ml), volumen_ml <= 750)

volumen_comparable <- individuales %>%
  group_by(marca, volumen_ml) %>%
  filter(n_distinct(supermercado) >= 2) %>%
  group_by(marca) %>%
  summarise(volumen_ml = min(volumen_ml))

p4 <- individuales %>%
  semi_join(volumen_comparable, by = c("marca", "volumen_ml")) %>%
  group_by(marca, volumen_ml, supermercado) %>%
  summarise(precio = min(precio), .groups = "drop") %>%
  arrange(marca, precio)
p4

p4 %>% group_by(marca) %>% slice_min(precio, n = 1)

# 5. productos descartados
resultados %>%
  anti_join(precios, by = c("supermercado", "enlace")) %>%
  select(supermercado, marca_buscada, presentacion, precio)


# Respuestas (precios del 20/11/2026) -----------------------------------
#
# 1. Por precio total, Michelob y Club Colombia salen más baratas en Jumbo
#    (lata 269 ml a $2.790 y lata 330 ml a $3.690) y Stella Artois en Éxito
#    (lata 269 ml a $3.990). Esto favorece las presentaciones pequeñas.
#
# 2. Por ml, Jumbo es el más conveniente ($11,99), luego Carulla ($12,08)
#    y Éxito ($12,29). La diferencia es pequeña.
#
# 3. Cambia según la marca: Club Colombia en Éxito ($11,43/ml, casi igual
#    en los tres), Michelob en Carulla ($10,34/ml) y Stella Artois en Éxito
#    ($14,04/ml). Ninguno gana en las tres.
#
# 4. Con la lata individual más pequeña (269 ml Michelob y Stella, 330 ml
#    Club Colombia), Jumbo es más barato en Michelob y Club Colombia y Éxito
#    en Stella Artois. Coincide con la pregunta 1 pero no con la 3, porque el
#    promedio por ml depende de las presentaciones y promociones de cada
#    tienda (p. ej. el six pack de Michelob en descuento en Éxito y Carulla).
#
# 5. Se dejaron solo productos con la marca en el nombre y se quitaron
#    llantas, combos y accesorios sin cerveza; para el precio por ml solo se
#    usaron productos con volumen. Se descartaron 23 resultados: 13 llantas
#    Michelin que salieron al buscar "michelob" y 10 productos de otras
#    marcas (otras cervezas, miel, kale).
