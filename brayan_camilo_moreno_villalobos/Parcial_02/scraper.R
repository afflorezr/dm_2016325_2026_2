# =======================================================================
# CONFIGURACIÓN INICIAL Y CARGA DE LIBRERÍAS
# Propósito: Prepara el entorno de trabajo verificando la disponibilidad 
#            del navegador Chrome (necesario para chromote), configurando 
#            el directorio de trabajo e instalando/cargando los paquetes 
#            requeridos dinámicamente.
# =======================================================================
chrome_disponible <- tryCatch({
  chromote::chromote_info()
  TRUE
}, error = function(e) FALSE)
options(chromote.timeout=60)
#setwd("brayan_camilo_moreno_villalobos/Parcial_01") 

library(rvest)
library(xml2)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)
library(janitor)
library(highcharter)
library(readr)
library(DBI)
library(RSQLite)
library(stringi)
# ==============================================================================
# PARÁMETROS Y DICCIONARIO DE SUPERMERCADOS 
# ==============================================================================


config_sitios <- list(
  olimpica = list(
    nombre = "Olimpica",
    url_template = "https://www.olimpica.com/supermercado/para-tu-mascota",
    param_paginacion = "?page=",
    selector_item = "section.vtex-product-summary-2-x-container", 
    selector_nombre = "span.vtex-product-summary-2-x-productBrand",
    selector_precio = "span.olimpica-dinamic-flags-0-x-currencyContainer",
    selector_marca = "span.vtex-product-summary-2-x-productBrandName"
  ),
  exito = list(
    nombre = "Exito",
    url_template = "https://www.exito.com/mercado/mascotas?category-1=mercado&category-2=mascotas&facets=category-1%2Ccategory-2&sort=score_desc",
    param_paginacion = "&page=",
    selector_item = "div.product-grid_fs-product-grid___qKN2 ul li",
    selector_nombre = "h3",
    selector_precio = "div.ProductPrice_container__JKbri  p",
    selector_marca = "no existe selector"
  ),
  jumbo = list(
    nombre = "Jumbo",
    url_template = "https://www.jumbocolombia.com/co/mascotas",
    param_paginacion = "?page=",
    selector_item = "div.tiendasjumboqaio-custom-search-0-x-product__container ",
    selector_nombre = "h3",
    selector_precio = 'span.jumbo-ds-commerce-ProductCard-ProductCardstyles-price-1szk4on',
    selector_marca = "p.jumbo-ds-commerce-ProductCard-ProductCardstyles-subtitle-1szk4om"
  )
)#render-store\.product > div > div.vtex-store__template.bg-base > div > div:nth-child(4) > div > div.vtex-render__container-id-custom-plp > div.tiendasjumboqaio-custom-search-0-x-plpController > div > div > div.tiendasjumboqaio-custom-search-0-x-searchLayout__leftContent > div:nth-child(2) > div > div:nth-child(6) > a > div > div.jumbo-ds-commerce-ProductCard-ProductCardstyles-mobileRow-1szk4o4 > div.jumbo-ds-commerce-ProductCard-ProductCardstyles-mobileBodySection-1szk4o6 > div > div.jumbo-ds-commerce-ProductCard-ProductCardstyles-priceRow-1szk4of > span:nth-child(2)
# =======================================================================
# Función: extraer_texto_seguro
# Propósito: Extrae el texto de un nodo HTML de forma segura, evitando 
#            que selectores inexistentes, nulos o nodos vacíos rompan 
#            la ejecución del bucle principal.
# 
# Parámetros:
#   - nodo (xml_node): El fragmento HTML del cual se extraerá la información.
#   - selector (character): El selector CSS que apunta al dato específico.
#
# Retorna:
#   - character: El texto extraído limpio de espacios, o NA_character_ 
#                si la extracción falla o el selector es inválido.
# =======================================================================
extraer_texto_seguro <- function(nodo, selector) {
  if (is.na(selector) || selector == "no existe selector") return(NA_character_)
  texto <- html_element(nodo, selector) %>% html_text(trim = TRUE)
  if (length(texto) == 0 || is.na(texto)) return(NA_character_)
  return(texto)
}
extraer_enlace_seguro <- function(nodo) {
  # Busca el primer hipervínculo dentro de la tarjeta y extrae la ruta
  enlace <- rvest::html_element(nodo, "a") %>% rvest::html_attr("href")
  if (length(enlace) == 0 || is.na(enlace)) return(NA_character_)
  return(enlace)
}
# =======================================================================
# Función: .motor_scraping (Uso interno)
# Propósito: Motor core que gestiona la recolección de datos, la paginación,
#            el manejo del DOM y la lógica de respaldo (fallback recursivo) 
#            entre los modos Offline y Online.
# 
# Parámetros:
#   - sitio_cfg (list): Diccionario con la configuración del comercio (URLs, CSS).
#   - max_paginas (numeric): Límite de iteraciones para evitar bucles infinitos.
#   - modo_offline (logical): Define si lee archivos locales (TRUE) o usa Chrome (FALSE).
#   - fecha_offline (character): Fecha de formato "YYYYMMDD" para buscar archivos locales.
#
# Retorna:
#   - data.frame: Tabla unificada con los datos crudos extraídos de un comercio.
# =======================================================================
.motor_scraping <- function(sitio_cfg, max_paginas , modo_offline = TRUE, fecha_offline = NULL) {
  ruta_raw <- file.path("raw")
  fecha_hoy <- format(Sys.Date(), "%Y%m%d")
  fecha_carpeta <- format(Sys.Date(), "%Y-%m-%d") # Nueva variable para la carpeta
  
  
  nombre_carpeta <- tolower(iconv(sitio_cfg$nombre, from = "UTF-8", to = "ASCII//TRANSLIT"))
  if (is.na(nombre_carpeta) || nombre_carpeta == "") nombre_carpeta <- tolower(sitio_cfg$nombre)
  nombre_carpeta <- gsub("[^a-z0-9]", "", nombre_carpeta)
  
  resultados_comercio <- list()
  
  # ==========================================
  # MODO SIN CONEXIÓN (OFFLINE)
  # ==========================================
  if (modo_offline) {
    message("--> [OFFLINE] Extrayendo ", sitio_cfg$nombre, " desde archivos locales...")
    
    dir_comercio <- file.path(ruta_raw, nombre_carpeta)
    
    if (is.null(fecha_offline)) {
      if (dir.exists(dir_comercio)) {
        fechas_disponibles <- list.dirs(dir_comercio, recursive = FALSE, full.names = FALSE)
      } else {
        fechas_disponibles <- character(0)
      }
      
      if (length(fechas_disponibles) == 0) {
        message("    ⚠️ No se encontraron copias crudas válidas o con fecha para ", sitio_cfg$nombre, ".")
        message("    🔄 Cambiando automáticamente a modo ONLINE...")
        return(.motor_scraping(sitio_cfg, max_paginas, modo_offline = FALSE))
      }
      
      fecha_busqueda <- max(fechas_disponibles, na.rm = TRUE)
      message("    ℹ️ No se especificó fecha. Usando la más reciente encontrada: ", fecha_busqueda)
    } else {
      fecha_busqueda <- fecha_offline
    }
    
    dir_busqueda <- file.path(dir_comercio, fecha_busqueda)
    patron_busqueda <- paste0("^", sitio_cfg$nombre, ".*_pag_\\d+\\.html(\\.gz)?$")
    archivos_locales <- list.files(dir_busqueda, pattern = patron_busqueda, full.names = TRUE)
    
    if (length(archivos_locales) == 0) {
      stop("No se encontraron archivos crudos para ", sitio_cfg$nombre, " en la carpeta ", dir_busqueda)
    }
    
    for (archivo in archivos_locales) {
      pagina_estatica <- rvest::read_html(archivo)
      nodos <- html_elements(pagina_estatica, sitio_cfg$selector_item)
      pag_num <- stringr::str_extract(archivo, "(?<=pag_)\\d+")
      url_paginada <- paste0(sitio_cfg$url_template, sitio_cfg$param_paginacion, pag_num)
      
      df_pagina <- map_dfr(nodos, function(nodo) {
        nombre <- extraer_texto_seguro(nodo, sitio_cfg$selector_nombre)
        precio <- extraer_texto_seguro(nodo, sitio_cfg$selector_precio)
        marca <- extraer_texto_seguro(nodo, sitio_cfg$selector_marca)
        sku <- extraer_enlace_seguro(nodo)
        tibble(
          precio = precio,
          id_anuncio = sku,
          supermercado = sitio_cfg$nombre,
          pagina_origen = url_paginada,
          presentacion = nombre,
          marca = marca,
          fecha_consulta = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z") 
        )
      })
      resultados_comercio[[length(resultados_comercio) + 1]] <- df_pagina
    }
    df_final <- dplyr::bind_rows(resultados_comercio)
    
    return(df_final)
    
    # ==========================================
    # MODO CON CONEXIÓN (ONLINE)
    # ==========================================
  } else {
    message("--> [ONLINE] Conectando a ", sitio_cfg$nombre, " y extrayendo ...")
    
    # Aseguramos que la estructura de carpetas (ej. raw/olimpica/2026-11-13) exista
    dir_guardado <- file.path(ruta_raw, nombre_carpeta, fecha_carpeta)
    if (!dir.exists(dir_guardado)) {
      dir.create(dir_guardado, recursive = TRUE, showWarnings = FALSE)
    }
    
    for (pag in 1:max_paginas) {
      if (grepl("limpica", sitio_cfg$nombre, ignore.case = TRUE)) { pag_a <- pag } else { pag_a <- pag - 1 } 
      url_paginada <- paste0(sitio_cfg$url_template, sitio_cfg$param_paginacion, pag_a)
      
      Sys.sleep(runif(1, 4, 7))
      Sys.sleep(4)
      
      sess <- tryCatch({
        pagina_viva <- rvest::read_html_live(url_paginada)
        pagina_viva$session$Network$setUserAgentOverride(
          userAgent = "MascotasScraper/1.0 (bcmorenov@unal.edu.co)"
        )
        pagina_viva$session$Emulation$setDeviceMetricsOverride(
          width = 1920L,
          height = 5000L,
          deviceScaleFactor = 1,
          mobile = FALSE
        )
        Sys.sleep(4)
        pagina_viva$session$Runtime$evaluate("window.scrollBy(0, 600);")
        js_script <- paste0("
              document.querySelectorAll('", sitio_cfg$selector_item, "').forEach(el => {
                el.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
                el.dispatchEvent(new MouseEvent('mousemove', {bubbles: true}));
              });
              ")
        pagina_viva$session$Runtime$evaluate(js_script)
        pagina_viva
      }, error = function(e) { return(NULL) }) 
      
      if (is.null(sess)) {
        message("    ⚠️ Error de sesión en página ", pag, ". Saltando...")
        next
        return(tibble())
      }
      
      
      tryCatch({
        doc_root <- pagina_viva$session$DOM$getDocument()
        html_string <- pagina_viva$session$DOM$getOuterHTML(nodeId = doc_root$root$nodeId)$outerHTML
        
        nombre_archivo <- paste0(sitio_cfg$nombre, "_", fecha_hoy, "_pag_", pag, ".html.gz")
        con_gz <- gzfile(file.path(dir_guardado, nombre_archivo), "w")
        writeLines(text = html_string, con = con_gz, useBytes = TRUE)
        close(con_gz)
        
      }, error = function(e) {
      })
      
      nodos <- tryCatch({
        html_elements(pagina_viva, sitio_cfg$selector_item)
      }, error = function(e) {
        return(list()) 
      })
      
      if (length(nodos) == 0) {
        break 
      }
      
      df_pagina <- map_dfr(nodos, function(nodo) {
        nombre <- extraer_texto_seguro(nodo, sitio_cfg$selector_nombre)
        precio <- extraer_texto_seguro(nodo, sitio_cfg$selector_precio)
        marca <- extraer_texto_seguro(nodo, sitio_cfg$selector_marca)
        sku <- extraer_enlace_seguro(nodo)
        tibble(
          precio = precio,
          id_anuncio = sku,
          supermercado = sitio_cfg$nombre,
          pagina_origen = url_paginada,
          presentacion = nombre,
          marca = marca,
          fecha_consulta = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z") 
        )
      })
      nombres_limpios <- trimws(df_pagina$presentacion)
      nombres_validos <- nombres_limpios[!is.na(nombres_limpios) & nombres_limpios != ""]
      
      if (length(nombres_validos) == 0) {
        break 
      }
      
      resultados_comercio[[length(resultados_comercio) + 1]] <- df_pagina
    }
    
    df_final_comercio <- dplyr::bind_rows(resultados_comercio)
    
    total_paginas_extraidas <- length(resultados_comercio)
    total_productos <- nrow(df_final_comercio)
    
    message("--> [", sitio_cfg$nombre, "] Extracción finalizada: ", 
            total_paginas_extraidas, " páginas recorridas, ", 
            total_productos, " productos obtenidos.")
  
    return(df_final_comercio)
  }
}
# =======================================================================
# Funciones Envolventes (Wrappers): scrapear_olimpica, scrapear_exito, scrapear_jumbo
# Propósito: Inyectan la configuración específica de cada supermercado al 
#            motor principal sin necesidad de reescribir código.
# 
# Parámetros compartidos:
#   - max_paginas (numeric), offline (logical), fecha (character).
# =======================================================================

scrapear_olimpica <- function(max_paginas , offline , fecha = NULL) {
  .motor_scraping(config_sitios$olimpica, max_paginas, modo_offline = offline, fecha_offline = fecha)
}
scrapear_exito <- function(max_paginas , offline , fecha = NULL) {
  .motor_scraping(config_sitios$exito, max_paginas, modo_offline = offline, fecha_offline = fecha)
}
scrapear_jumbo <- function(max_paginas , offline , fecha = NULL) {
  .motor_scraping(config_sitios$jumbo, max_paginas, modo_offline = offline, fecha_offline = fecha)
}



# =======================================================================
# Función: ejecutar_recoleccion_completa
# Propósito: Orquesta la recolección en bloque de todos los supermercados
#            definidos, ejecutándolos secuencialmente y unificando los 
#            resultados en un solo consolidado.
# 
# Parámetros:
#   - max_paginas (numeric): Límite global de iteración por comercio (por defecto 55).
#   - modo_offline (logical): Interruptor maestro para extracción local vs en vivo.
#   - fecha_offline (character): Fecha específica para el modo sin conexión.
#
# Retorna:
#   - data.frame (tibble): Base de datos unificada (df_consolidado) que contiene 
#                          las extracciones crudas de todos los comercios.
# =======================================================================
ejecutar_recoleccion_completa <- function(max_paginas = 55, 
                                          modo_offline , 
                                          fecha_offline = NULL) {
  
  message("Iniciando recolección de datos...")
  
  # 1. Extracción por cada comercio
  datos_exito    <- scrapear_exito(max_paginas, offline = modo_offline, fecha = fecha_offline)
  datos_olimpica <- scrapear_olimpica(max_paginas, offline = modo_offline, fecha = fecha_offline)
  datos_jumbo    <- scrapear_jumbo(max_paginas, offline = modo_offline, fecha = fecha_offline)
  
  # 2. Unir todo en una sola tabla cruda
  df_crudo <- dplyr::bind_rows(datos_exito, datos_olimpica, datos_jumbo)
  
  message("Recolección finalizada. Total registros crudos: ", nrow(df_crudo))
  return(df_crudo)
}
# =============================================================================
# Función: limpiar_datos
# Propósito: Transforma los datos crudos extraídos mediante web scraping, 
#            estandarizando textos y convirtiendo precios a formato numérico.
# 
# Parámetros:
#   - df_crudo (data.frame/tibble): La tabla unificada con los datos 
#     crudos de los tres supermercados.
#
# Retorna:
#   - data.frame: Una tabla filtrada y limpia lista para ser insertada 
#     en SQLite, con precios numéricos y marcas homologadas.
# =============================================================================

limpiar_datos <- function(df_crudo, id_ejecucion) {
  
  if (nrow(df_crudo) == 0) {
    warning("El dataframe está vacío. No hay datos para limpiar.")
    return(df_crudo)
  }
  
  marcas_conocidas <- c("CHUNKY", "DOGOURMET", "AGILITY GOLD", "MONELLO", 
                        "MIRRINGO", "RINGO", "TASTE OF THE WILD", "PEDIGREE", 
                        "DOG CHOW", "CAT CHOW", "WHISKAS", "FELIX", 
                        "ROYAL CANIN", "HILL'S", "NUTRECAN", "MAX", "BIOCAT", 
                        "CALABAZA", "BENTYSANDY", "MICHIKO", "PUKI", "DONKAT", 
                        "DONCAN", "HILLS", "ROYAL", "ONE", "PRO PLAN", "OHMAIGAT",
                        "WON CAN","AGILITY","NUTRION", "KELDOG", "PUKI")
  patron_marcas <- paste0("\\b(", paste(marcas_conocidas, collapse = "|"), ")\\b")
  
  df_procesado <- df_crudo %>%
    dplyr::mutate(
      `Texto original del anuncio` = presentacion,
      
      presentacion_limpia = stringr::str_squish(stringi::stri_trans_general(stringr::str_to_lower(presentacion), "Latin-ASCII")),
      presentacion_limpia = stringr::str_replace_all(presentacion_limpia, "(?i)x\\s*([0-9]+[.,]?[0-9]*)\\s*(kg|Kg|kG|KG|G|g|GR|Gr|gR|gr|grs|Grs|LB|Lb|lB|lb|ML|Ml|mL|ml|l|L|kilo|kilos|Kilo|Kilos|kls)\\b", "\\1 \\2"),
      marca_limpia = stringr::str_squish(stringi::stri_trans_general(stringr::str_to_upper(marca), "Latin-ASCII")),
      
      
      marca_limpia = dplyr::coalesce(
        stringr::str_extract(stringr::str_to_upper(presentacion_limpia), patron_marcas), 
        marca_limpia
      ),
      # ==============================================================
      # MANEJO DE PROMOCIONES Y CANTIDAD DE PAQUETES
      # ==============================================================
      
      # 1. Identificamos promociones ANTES de borrar la "x"
      es_promocion = stringr::str_detect(presentacion_limpia, "(?i)(\\d+\\s*x\\s*\\d+|lleve\\s*\\d+\\s*pague\\s*\\d+|pague\\s*\\d+\\s*lleve\\s*\\d+)"),
      
      # 2. Extraemos la cantidad para paquetes normales
      cantidad_paquete = stringr::str_extract(presentacion_limpia, "(?i)([0-9]+\\s*(unid|und|ud|x\\b)|\\b(?i)x\\s*[0-9]+)"),
      cantidad_paquete = readr::parse_number(cantidad_paquete),
      cantidad_paquete = tidyr::replace_na(cantidad_paquete, 1),
      
      # 3. Determinamos cuántos paquetes se LLEVA realmente el cliente (Ideal para el precio efectivo)
      cantidad_lleva = dplyr::if_else(
        es_promocion,
        readr::parse_number(stringr::str_extract(presentacion_limpia, "(?i)(\\d+)\\s*x|lleve\\s*(\\d+)")),
        cantidad_paquete
      ),
      
      
      presentacion_limpia = stringr::str_replace_all(presentacion_limpia, "x\\s*([0-9]+)", " \\1"),
      
      marca_limpia = tidyr::replace_na(marca_limpia, "OTRA/SIN MARCA"),
      
      
      
      cantidad_unidad = stringr::str_extract(presentacion_limpia,"[0-9]+[.,]?[0-9]*[\\s-]*(kg|Kg|kG|KG|G|g|GR|Gr|gR|gr|grs|Grs|LB|Lb|lB|lb|ML|Ml|mL|ml|l|L|kilo|kilos|Kilo|Kilos|kls)\\b" ),
      cantidad_unidad = stringr::str_replace(cantidad_unidad, "([0-9.,]+)\\s*(GR|Gr|gR|gr|grs|Grs)$", "\\1 gr"),
      cantidad_unidad = stringr::str_replace(cantidad_unidad, "([0-9.,]+)\\s*(kg|Kg|kG|K|kilo|kilos|Kilo|Kilos|kls)$", "\\1 kg"),
      cantidad_unidad = stringr::str_replace(cantidad_unidad, "([0-9.,]+)\\s*(LB|Lb|lB|lb)$", "\\1 lb"),
      cantidad_unidad = stringr::str_replace(cantidad_unidad, "([0-9.,]+)\\s*(ML|Ml|mL|ml)$", "\\1 ml"),
      cantidad_unidad = stringr::str_replace(cantidad_unidad, "([0-9.,]+)\\s*(l|L)$", "\\1 l"),
      
      # ==============================================================
      # CONVERSIÓN MATEMÁTICA ESTANDARIZADA (kg a gr, l a ml)
      # ==============================================================
      
      # 1. Separamos el número de la unidad
      num_temp = as.numeric(stringr::str_replace(stringr::str_extract(cantidad_unidad, "[0-9.,]+"), ",", ".")),
      uni_temp = stringr::str_extract(stringr::str_to_lower(cantidad_unidad), "[a-z]+"),
      
      # 2. Hacemos la multiplicación según la unidad
      num_temp = dplyr::case_when(
        uni_temp == "kg" ~ num_temp * 1000,
        uni_temp == "lb" ~ num_temp * 500, 
        uni_temp == "l"  ~ num_temp * 1000,
        TRUE ~ num_temp
      ),
      
      # 3. Unificamos la etiqueta final (todo queda en 'gr' o 'ml')
      uni_temp = dplyr::case_when(
        uni_temp %in% c("kg", "g", "gr", "lb") ~ "gr",
        uni_temp %in% c("l", "ml") ~ "ml",
        TRUE ~ uni_temp
      ),
      
      # 4. Volvemos a unir el número y la etiqueta en la variable cantidad_unidad
      cantidad_unidad = dplyr::if_else(!is.na(num_temp), paste(num_temp, uni_temp), cantidad_unidad),
      
      # ==============================================================
      
      precio_limpio = stringr::str_remove_all(precio, "[^0-9,]"),
      precio_limpio = stringr::str_replace(precio_limpio, ",", "."),
      precio_numerico = as.numeric(precio_limpio),
      precio_unitario = precio_numerico / cantidad_lleva,
      
      Categoria_Producto = dplyr::case_when(
        stringr::str_detect(presentacion_limpia, "(?i)arena|litter|piedras") ~ "Arena",
        stringr::str_detect(presentacion_limpia, "(?i)juguete|pelota|rascador|raton|mordedor") ~ "Juguete",
        stringr::str_detect(presentacion_limpia, "(?i)medicamento|desparasitante|pulga|garrapata|nexgard|bravecto") ~ "Medicamento",
        stringr::str_detect(presentacion_limpia, "(?i)galleta|snack|deshidratado|cabanos|cabanitos|bocaditos|desidratada|gomitas|hueso") ~ "Snack",
        stringr::str_detect(presentacion_limpia, "(?i)bebedero|cepillo|tapete|cepillo|cama|maquina|tapete|collar|arnes|corta|pañito|pan|plato|loci[óo]n|arenero|jaula|dispensador|toallas|comedero|repelente|capa|talco|bandeja|shampoo|olores|guacal") ~ "Accesorios",
        stringr::str_detect(presentacion_limpia, "(?i)h[úu]m|pouche|sobre|lata|filete|trozos|pat[ée]|stdo|surtido") ~ "Alimento Humedo",
        stringr::str_detect(presentacion_limpia, "(?i)alimento|comida|alim|pollo|res|carne|pavo|salm[oó]n|adulto|cachorro|puppy|adt|pack") & num_temp < 500 ~ "Alimento Húmedo",
        stringr::str_detect(presentacion_limpia, "(?i)alimento|comida") | marca_limpia %in% marcas_conocidas ~ "Alimento Seco",
        TRUE ~ "Sin categoria" 
      ),
      # ==============================================================
      # EXTRACCIÓN DE VARIABLES CLAVE PARA EL ID HOMOLOGADO
      # ==============================================================
      
      # 1. Detectar tipo de mascota
      Mascota = dplyr::case_when(
        stringr::str_detect(presentacion_limpia, "(?i)gato|cat|felino|gatito|kitten|michiko") ~ "GATO",
        stringr::str_detect(presentacion_limpia, "(?i)perro|dog|canino|cachorro|puppy|doncan|won can") ~ "PERRO",
        TRUE ~ "GENERAL"
      ),
      
      # 2. Detectar etapa de vida
      Etapa_Vida = dplyr::case_when(
        stringr::str_detect(presentacion_limpia, "(?i)cachorro|puppy|gatito|kitten") ~ "CACHORRO",
        stringr::str_detect(presentacion_limpia, "(?i)senior|mayor|edad avanzada|7\\+") ~ "SENIOR",
        stringr::str_detect(presentacion_limpia, "(?i)adulto|adt|adult|hogareño") ~ "ADULTO",
        stringr::str_detect(presentacion_limpia, "(?i)este") ~ "ESTERILIZADO",
        TRUE ~ "TODA_ETAPA"
      ),
      
      # 3. Detectar sabor principal (presentacion_limpia ya no tiene tildes gracias a tu stringi)
      Sabor = stringr::str_to_upper(stringr::str_extract(presentacion_limpia, "(?i)\\b(pollo|carne|salmon|cordero|cord|res|pavo|pescado|atun|cerdo|pato|conejo)\\b")),
      Sabor = tidyr::replace_na(Sabor, "MIXTO_ND"),
      
      # 4. Construir el ID Automático concatenando sin espacios
      # Usamos toupper y reemplazamos espacios por guiones bajos para que sea un ID limpio
      id_homologado = paste(
        stringr::str_replace_all(marca_limpia, " ", ""),
        Mascota,
        Etapa_Vida,
        stringr::str_replace_all(stringr::str_to_upper(Categoria_Producto), " ", ""),
        stringr::str_replace_all(stringr::str_to_upper(cantidad_unidad), " ", ""),
        Sabor,
        sep = "_"
      ),
      # ==============================================================
      
      
      
      Comercio = supermercado,
      `Marca` = marca_limpia,
      Presentación = cantidad_unidad,
      `Precio x und` = round(precio_unitario),
      `URL de extracción` = pagina_origen,
      `Fecha y hora de consulta` = fecha_consulta,
      Ejecución = id_ejecucion,
      precio = precio_numerico
    ) %>%
    dplyr::filter(!is.na(`Precio x und`), precio > 0) %>%
    dplyr::distinct(Comercio, id_anuncio, .keep_all = TRUE) %>%
    dplyr::select(
      id_anuncio, 
      id_homologado,      
      Comercio,
      `Marca`,
      Mascota,            
      Etapa_Vida,         
      Sabor,              
      Categoria_Producto,
      Presentación,
      precio,
      `Precio x und`,
      `Texto original del anuncio`,
      `URL de extracción`,
      `Fecha y hora de consulta`,
      Ejecución
    )
  
  return(df_procesado)
}
# ==========================================================
# VALIDACION Y BASE DE DATOS
# ==========================================================

ejecutar_pipeline <- function(modo_ejecucion_offline = TRUE, max_pag =3){
  
  id_ejecucion_actual <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  df_crudo <- ejecutar_recoleccion_completa(max_paginas = max_pag, modo_offline = modo_ejecucion_offline)
  df_limpio <- limpiar_datos(df_crudo, id_ejecucion_actual)
  
  # ==========================================================
  # 1. BLOQUE DE VALIDACIÓN 
  # ==========================================================
  source("validacion.R", local = TRUE)
  if (!validar_observaciones(df_limpio)) {
    stop("Validación fallida: Los datos contienen precios en 0, nulos o duplicados. No se insertarán.")
  } else{
    message("validacion completada")
  }

  df_comercios <- df_limpio %>% dplyr::distinct(Comercio) %>% dplyr::mutate(id_comercio = dplyr::row_number())
  df_limpio <- df_limpio %>% dplyr::left_join(df_comercios, by = "Comercio")
  
  df_homologados <- df_limpio %>%
    dplyr::filter(id_homologado != "OTRA/SINMARCA_GENERAL_TODA_ETAPA_SINCATEGORIA_NA_MIXTO_ND") %>%
    dplyr::distinct(id_homologado, .keep_all = TRUE) %>%
    dplyr::select(id_homologado, marca = `Marca`, mascota = Mascota, etapa_vida = Etapa_Vida,
                  sabor = Sabor, categoria = Categoria_Producto, presentacion_estandar = Presentación)
  
  df_anuncios <- df_limpio %>% dplyr::distinct(id_anuncio, .keep_all = TRUE) %>%
    dplyr::select(id_anuncio, id_comercio, id_homologado, marca = `Marca`,
                  texto_original = `Texto original del anuncio`, pagina_origen = `URL de extracción`)
  
  df_precios <- df_limpio %>% dplyr::select(id_anuncio, precio, precio_x_und = `Precio x und`,
                                            fecha_consulta = `Fecha y hora de consulta`, id_ejecucion = Ejecución)
  
  # ==========================================================
  # 2. BLOQUE DE TRANSACCIÓN SQL 
  # ==========================================================
  con <- DBI::dbConnect(RSQLite::SQLite(), "comparador_precios.sqlite")
  DBI::dbBegin(con)
  
  tryCatch({
    
    ids_homologados_bd <- DBI::dbGetQuery(con, "SELECT id_homologado FROM productos_homologados")$id_homologado
    nuevos_homologados <- df_homologados %>% dplyr::filter(!id_homologado %in% ids_homologados_bd)
    if (nrow(nuevos_homologados) > 0) {
      DBI::dbWriteTable(con, "productos_homologados", nuevos_homologados, append = TRUE)
    }
    
    
    ids_anuncios_bd <- DBI::dbGetQuery(con, "SELECT id_anuncio FROM anuncios")$id_anuncio
    nuevos_anuncios <- df_anuncios %>% dplyr::filter(!id_anuncio %in% ids_anuncios_bd)
    if (nrow(nuevos_anuncios) > 0) {
      DBI::dbWriteTable(con, "anuncios", nuevos_anuncios, append = TRUE)
    }
    

    DBI::dbWriteTable(con, "precios_historial", df_precios, append = TRUE)
    
    DBI::dbCommit(con)
    
  }, error = function(e) {

    DBI::dbRollback(con)
    stop("Error al insertar en SQLite. Se revirtieron los cambios: ", e$message)
  })
  
  DBI::dbDisconnect(con)
  message("Scraping finalizado, validado y guardado en la base de datos exitosamente.")
}