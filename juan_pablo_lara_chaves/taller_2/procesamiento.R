# procesamiento.R | limpieza + emparejamiento de comparables (de taller_1.Rmd)
library(dplyr); library(stringr); library(stringi); library(purrr); library(tidyr); library(tibble)

# --- Normalización y diccionarios --------------------------------------------
normalizar <- function(x) {
  x |> str_to_lower() |>
    str_replace_all("[\u00ae\u2122*]", "") |>
    stri_trans_general("Latin-ASCII") |>
    str_replace_all("\\(r\\)", "") |>
    str_replace_all("no[- ]*varix", "no-varix") |>
    str_squish()
}

MARCAS <- tribble(
  ~patron,            ~marca,
  "no-varix",         "No-Varix",   "kamex",            "Kamex",
  "recovery",         "Recovery",   "medivaric",        "Medivaric",
  "actimove",         "Actimove",   "everlast",         "Everlast",
  "\\bk6\\b",         "K6",         "trulife",          "Trulife",
  "vivo\\+",          "Vivo+",      "wilson",           "Wilson",
  "neoflex",          "Neoflex",    "pura\\+|\\bpura\\b", "Pura+",
  "kromia",           "Kromia",     "yuwell",           "Yuwell",
  "plenia",           "Plenia",     "\\bdrive\\b",      "Drive",
  "konfort",          "Konfort",    "carex",            "Carex",
  "anne shant?h?el",  "Anne Shantel", "sportiva",       "Sportiva",
  "scholl",           "Dr. Scholl", "theraband",        "Theraband",
  "interfisica",      "Interfisica","physio ?trauma",   "Physio Trauma",
  "\\btme\\b",        "TME",        "impormedical",     "Impormedical",
  "\\blowe\\b",       "Lowe",       "unimarc",          "Unimarc",
  "\\bmyd\\b",        "MYD",        "samsara",          "Samsara",
  "tecnomed",         "Tecnomed",   "\\btulis\\b",      "Tulis",
  "aspen",            "Aspen",      "maxwell",          "Maxwell"
)
detectar_marca <- function(x) map_chr(x, function(n) {
  i <- which(str_detect(n, MARCAS$patron)); if (length(i)) MARCAS$marca[i[1]] else NA_character_ })

SUBCATEGORIAS <- tribble(
  ~patron,                                                              ~subcategoria_std,
  "\\bmedias?\\b|calcet|pantimedia|leotardo|antiemb",                    "medias de compresión",
  "tobiller|tobillo|talomotion",                                         "tobilleras",
  "rodiller|rodilla|genumotion|rotul",                                   "rodilleras",
  "munequ|muneca|pulgar|rhizo|codera|epimotion|cabestrillo|hombro",      "muñequeras y miembro superior",
  "faja|lumbar|costillero|corrector|columna|sacro|cinturilla|abdomen|bicicletero|brassier|soporte cardiaco", "fajas y tronco",
  "baston|muleta|andador|caminador|axilar|canadiense|regaton|manilar",   "bastones, muletas y andadores"
)
detectar_subcat <- function(x) map_chr(x, function(n) {
  i <- which(str_detect(n, SUBCATEGORIAS$patron)); if (length(i)) SUBCATEGORIAS$subcategoria_std[i[1]] else "otros de rehabilitación" })

# --- Preparación ---------------------------------------------------------------
# `crudo`: salida de reprocesar_raw() (13 columnas, precio numérico). El texto original (nombre) no se modifica.
preparar_datos <- function(crudo) {
  crudo |>
    arrange(fecha_hora) |>
    distinct(comercio, categoria, nombre, precio, url, .keep_all = TRUE) |>
    mutate(
      nombre_norm      = normalizar(nombre),
      marca_std        = coalesce(detectar_marca(nombre_norm), str_to_title(marca)),
      subcategoria_std = detectar_subcat(nombre_norm),
      en_promocion     = if_else(!is.na(precio) & !is.na(precio_lista) & precio < precio_lista, 1L, 0L),
      descuento_pct    = if_else(en_promocion == 1L, round(100 * (precio_lista - precio) / precio_lista, 1), NA_real_),
      n_unidades       = coalesce(
        as.integer(str_match(nombre_norm, "\\bx ?(\\d{1,3}) ?(?:und|unid\\w*|pares?)\\b")[, 2]),
        as.integer(str_match(nombre_norm, "\\bindividual x (\\d{1,3})\\b")[, 2])),
      ejecucion_id     = paste0("ejec_", format(as.Date(substr(fecha_hora, 1, 10)), "%Y%m%d")),
      producto_comercio0 = coalesce(sku, id_anuncio, nombre_norm)) |>
    group_by(comercio, producto_comercio0, fecha_hora) |>
    mutate(k = row_number(),
           producto_comercio = if_else(k == 1, producto_comercio0, paste0(producto_comercio0, "#", k))) |>
    ungroup() |> select(-producto_comercio0, -k) |>
    mutate(obs_id = row_number())
}

# --- Reglas de emparejamiento --------------------------------------------------
y <- function(...) paste0("^", paste0("(?=.*", c(...), ")", collapse = ""))

# Una fila por comercio. variante = qué precio tomar entre variantes del mismo producto (min | max)
r3 <- function(id, f, l, o, conf = "alta", var_f = "min", nota = "", excl_f = NA, excl_o = NA)
  tibble(producto_id = id, comercio = c("farmatodo", "locatel", "ortopedicos_futuro"),
         patron = c(f, l, o), excluir = c(excl_f, NA, excl_o), confianza = conf,
         variante = c(var_f, "min", "min"), nota = nota)

REGLAS <- bind_rows(
  r3("NOVARIX_MEDIA_HOMBRE_15-20",
     y("no-varix", "mediana compresion", "caballero"),
     "^calcetin navy 15-20 no-varix$",
     y("media de compresion", "no-varix", "hombre", "15-20"),
     var_f = "max", excl_f = "pantimedia", excl_o = "jasped|algodon|cobre|fibras",
     nota = "Farmatodo: variante más cara (talla/color afectan precio); OF: precio igual entre variantes"),
  
  r3("NOVARIX_PANTIMEDIA_15-20",
     y("no-varix", "pantimedia", "mediana compresion"),
     "^pantimedia 15-20 no-varix$",
     "^pantimedia no-varix 15-20 mmhg transparente$",
     var_f = "max", nota = "Mediana compresión = 15-20 mmHg; Farmatodo: variante más cara; OF: transparente simple"),
  
  r3("NOVARIX_MEDIA_MUJER_15-20_DIAMANTE",
     y("no-varix", "mujer", "15-20", "diamante"),
     "^calcetin no-varix 15-20 diamante$",
     y("no-varix", "mujer", "15-20", "diamante"),
     nota = "Farmatodo diamante grande, OF diamante pequeño; Locatel no indica sexo ni tamaño"),
  
  r3("NOVARIX_MEDIA_HOMBRE_8-15",
     y("no-varix", "baja compresion", "caballero"),
     "^calcetin hombre 8-15 no-varix$",
     y("media de compresion", "no-varix", "hombre", "8-15"),
     var_f = "max", excl_f = "pantimedia",
     nota = "Baja compresión = 8-15 mmHg; Farmatodo: variante más cara; reemplaza a Kamex (MG012 de Locatel no era el mismo modelo)"),
  
  r3("NOVARIX_MEDIA_MUJER_8-15",
     y("medias? de compresion", "no-varix", "mujer", "8-15"),
     "^media rodilla 8-15 no-varix$",
     y("medias? de compresion", "no-varix", "mujer", "8-15"),
     nota = "Locatel no indica sexo"),
  
  
  r3("NOVARIX_PANTIMEDIA_8-15",
     y("no-varix", "pantimedia", "baja compresion"),
     "^pantimedia 8-15 no-varix$",
     "^pantimedia no-varix 8-15 mmhg transparente$",
     var_f = "max", nota = "Baja compresión = 8-15 mmHg; Farmatodo: variante más cara; OF: transparente simple"),
  
  r3("NOVARIX_MEDIA_HOMBRE_20-30",
     y("medias? de compresion", "no-varix", "hombre", "20-30"),
     "^calcetin( hombre)? 20-30 no-varix$",
     y("medias? de compresion", "no-varix", "hombre", "20-30"),
     excl_f = "clasica", excl_o = "clasica"),
  
  r3("ACTIMOVE_RHIZO_FORTE_IZQ_S",
     "^rhizo actimove forte izquierda s( |$)",
     "^soporte pulgar actimove rhizo forte$",
     "^rhizo actimove forte izquierda s$",
     nota = "Locatel no indica lado ni talla; se emparejó por nombre del modelo")
)

buscar <- function(datos, id, com, patron, excluir) {
  d <- datos |> filter(comercio == com, str_detect(nombre_norm, patron))
  if (!is.na(excluir)) d <- d |> filter(!str_detect(nombre_norm, excluir))
  d |> mutate(producto_id = id) |> select(obs_id, producto_id)
}

asignar_comparables <- function(datos, reglas = REGLAS) {
  emp <- pmap_dfr(reglas |> select(id = producto_id, com = comercio, patron, excluir),
                  \(id, com, patron, excluir) buscar(datos, id, com, patron, excluir))
  stopifnot(!anyDuplicated(emp$obs_id))     # ninguna observación en dos productos
  datos |> select(-any_of(c("producto_id", "comparable"))) |>
    left_join(emp, by = "obs_id") |>
    mutate(comparable = as.integer(!is.na(producto_id)))
}

# Cobertura: 8 productos x 3 comercios = 24 combinaciones
cobertura_comparables <- function(datos) {
  tab <- datos |> filter(comparable == 1) |> count(producto_id, comercio) |>
    pivot_wider(names_from = comercio, values_from = n, values_fill = 0)
  cob <- datos |> filter(comparable == 1) |> distinct(producto_id, comercio)
  list(tabla = tab, ok = n_distinct(cob$producto_id) >= 8 && nrow(cob) >= 24)
}

# Observación de referencia por producto y comercio (max/min según `variante`)
referencia_comparables <- function(datos, reglas = REGLAS) {
  datos |> filter(comparable == 1, !is.na(precio)) |>
    left_join(distinct(reglas, producto_id, comercio, variante), by = c("producto_id", "comercio")) |>
    group_by(producto_id, comercio) |>
    slice(if (first(variante) == "max") which.max(precio) else which.min(precio)) |>
    ungroup()
}