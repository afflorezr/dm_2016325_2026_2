# =============================================================================
# config.R · Parámetros únicos del Taller 1 (se carga con source("config.R"))
# =============================================================================
CFG <- list(
  # --- rutas ---------------------------------------------------------------
  db_path     = "comparador_precios.sqlite",
  dir_raw     = "raw",
  dir_diag    = "diagnostico",
  dir_staging = file.path("datos", "staging"),
  
  # --- comportamiento ------------------------------------------------------
  tz            = "America/Bogota",
  user_agent    = "TallerMineriaDatosUNAL/1.0 (proyecto academico, Universidad Nacional de Colombia)",
  pausa         = c(1.5, 3.5),
  timeout_carga = 20,
  max_scrolls   = 2,
  max_paginas_comunal  = 30,
  max_paginas_busqueda = 12,   # términos de categoría
  max_paginas_marca    = 1,    # términos de marca: solo la 1.ª página (después sale ruido)
  paginas_prueba = 2,
  fichas_prueba  = 7,
  max_fichas     = 1000,   # tope de fichas POR COMERCIO (se reparte entre términos de búsqueda)
  pantallas      = TRUE,
  
  # --- reglas de sanidad -----------------------------------------------------
  precio_min = 100, precio_max = 3e6,
  ppl_min = 300,    ppl_max = 80000,
  
  # --- términos de búsqueda (Bebidas no alcohólicas) -------------------------
  busquedas_categoria = c("gaseosa", "jugo", "agua", "agua con gas", "te frio", "cafe frio", "energizante"),
  busquedas_marca     = c("coca cola", "pepsi", "postobon", "hit", "del valle", "hatsu", "red bull",
                          "monster", "speed max", "manzana postobon", "colombiana", "quatro",
                          "sprite", "fanta", "brisa", "cristal", "manantial"),
  filtro_breadcrumb = TRUE,
  # secciones de Comunal aceptadas en la URL (/<seccion>/<id>-nombre.html); ajusta con el table() de abajo
  comunal_secciones_ok = c("aguas-y-refrescos", "bebidas", "gaseosas", "jugos", "aguas", "energizantes", "te-y-cafe")
)
CFG$busquedas <- c(CFG$busquedas_categoria, CFG$busquedas_marca)

# --- Selectores compartidos por Éxito y Carulla (plataforma FastStore/VTEX) ----
SEL_FASTSTORE <- list(
  pagina_inicial = 0, espera = 3.5, espera_ficha = 2.5, dos_fases = TRUE,
  volumen_es_total = TRUE,       # "(3000 ml)" al final del nombre = contenido TOTAL del pack
  sel_link_producto = c("a[data-testid='product-link']", "a.vtex-product-summary-2-x-clearLink",
                        "a[href*='/producto/']", "a.product-title", "h3 a"),
  sel_nombre_ficha  = c("h1[class*='product-title']", "h1[data-testid='heading-product-title']",
                        "h1.vtex-product-summary-2-x-productNameContainer", "h1[class*='productName']",
                        "h1", "[data-testid='product-title']"),
  # precio general = el que paga cualquiera (etiqueta "Otros" en Éxito); NO el precio con tarjeta
  sel_precio_general_ficha = "[data-fs-container-price-otros]",
  sel_bloque_precios_ficha = "[data-fs-product-details-prices]",   # contiene tachado + precios
  sel_precio_ficha        = c("[data-testid='price']", "[data-fs-product-prices__price]",
                              ".vtex-product-price-1-x-sellingPriceValue", "[itemprop='price']", ".product-price"),
  sel_precio_lista_ficha  = c("[data-testid='previous-price']", "[data-fs-product-prices__list-price]",
                              ".vtex-product-price-1-x-listPrice", ".product-price-old"),
  sel_marca_ficha         = c("[data-testid='brand']", ".vtex-product-identifier-0-x-product-identifier__value",
                              "[itemprop='brand']"),
  sel_descripcion_ficha   = c("[data-testid='product-description']", ".vtex-product-description-1-x-productDescription",
                              "[itemprop='description']"),
  sel_sku_ficha           = c("[data-testid='sku']", "[itemprop='sku']"),
  sel_imagen_ficha        = c("[data-testid='product-image']", ".vtex-product-summary-2-x-imageNormal",
                              "img[class*='product']", "[itemprop='image']"),
  sel_disponibilidad_ficha = c("[data-testid='add-to-cart-button']", ".vtex-add-to-cart-button-0-x-buttonText",
                               "button[class*='add-to-cart']", "button[data-testid='buy-button']")
)

# --- Comercios -------------------------------------------------------------------
COMERCIOS <- list(
  exito = modifyList(SEL_FASTSTORE, list(
    nombre = "Éxito", carpeta = "exito", prefijo_sku = "EXI", base = "https://www.exito.com",
    url_busqueda = "https://www.exito.com/s?q={q}&sort=score_desc&page={p}"
  )),
  
  carulla = modifyList(SEL_FASTSTORE, list(
    nombre = "Carulla", carpeta = "carulla", prefijo_sku = "CAR", base = "https://www.carulla.com",
    url_busqueda = "https://www.carulla.com/s?q={q}&sort=score_desc&page={p}"
  )),
  
  # PriceSmart: "12 Unidades / 400 mL" -> 400 mL es POR unidad (volumen_es_total = FALSE)
  pricesmart = list(
    nombre = "PriceSmart", carpeta = "pricesmart", prefijo_sku = "PSM", base = "https://www.pricesmart.com",
    url_busqueda = "https://www.pricesmart.com/es-co/busqueda?q={q}&page={p}",
    pagina_inicial = 1, espera = 4.5, espera_ficha = 3.0, volumen_es_total = FALSE, dos_fases = TRUE,
    sel_link_producto = c("a.product-card__title-container", "a[href*='/producto/']", "h3 a"),
    sel_nombre_ficha  = c("h1.sf-heading__title", "h1.product-page__title", "h1[class*='product-title']", "h1"),
    sel_precio_ficha  = c("[data-testid='price']", ".product-price__selling", "[itemprop='price']",
                          ".sf-price__regular"),
    sel_precio_lista_ficha = c("[data-testid='previous-price']", ".product-price__list"),
    sel_marca_ficha   = c("[data-testid='brand']", "[itemprop='brand']", ".product-details__brand"),
    sel_descripcion_ficha = c("[data-testid='product-description']", ".product-details__description",
                              "[itemprop='description']"),
    sel_sku_ficha     = c("[data-testid='sku']", "[itemprop='sku']", ".product-details__sku"),
    sel_imagen_ficha = c("[data-testid='image-wrapper'] img", ".sf-gallery__stage img.sf-image", "img.sf-image-loaded", ".sf-image--wrapper img", "[data-testid='product-image']", "[itemprop='image']", ".product-gallery__main-image img"),
    sel_disponibilidad_ficha = c("[data-testid='add-to-cart-button']", ".sf-button--add-to-cart",
                                 "button[class*='add-to-cart']")
  ),
  
  supercomunal = list(
    nombre = "Supermercado Comunal", carpeta = "supercomunal", prefijo_sku = "SCO",
    base = "https://supermercadocomunal.com", espera = 2.5,
    categoria = "13-bebidas",
    busquedas = c("gaseosa", "jugo", "agua", "te frio", "energizante", "coca cola", "pepsi", "postobon", "hit")
  )
)