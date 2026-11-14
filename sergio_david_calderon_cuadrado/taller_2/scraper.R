# =====================================================================
# scraper.R -- Scraping en linea + carga a la base. SIN efectos al hacer source().
#
# Las definiciones vienen SIN CAMBIOS de scraper_general_1.R y sqlite_scraper.R (Taller 1);
# se quitaron solo la configuracion de arranque, la instalacion de paquetes y la corrida
# automatica. Cambios menores marcados con "[Taller 2]". Lo nuevo esta al final.
#   ejecutar_recoleccion(modo = "scrape")   actualizacion EN LINEA (requiere navegador)
#   ejecutar_recoleccion(modo = "respaldo") modo SIN CONEXION: reprocesa raw/
# La app NO carga este archivo al iniciar: se carga bajo demanda desde el boton.
# =====================================================================
suppressPackageStartupMessages(for (.p in c("rvest", "xml2", "dplyr", "stringr", "purrr", "tibble", "tidyr", "DBI", "RSQLite"))
  library(.p, character.only = TRUE))
rm(.p)


COMERCIOS_A_CORRER <- c("exito", "farmatodo", "larebaja")

TERMINOS_A_BUSCAR  <- NULL

PAUSA_PAGINA       <- 4

RESPALDAR          <- TRUE

COMPLETAR_CON_RESPALDOS <- TRUE

TIMEOUT_CHROMOTE <- 120

configurar_navegador <- function() {
  if (!nzchar(Sys.getenv("CHROMOTE_CHROME"))) {
    sistema <- Sys.info()[["sysname"]]
    candidatos <- switch(sistema,
      Windows = c(
        file.path(Sys.getenv("ProgramFiles"),        "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
        file.path(Sys.getenv("ProgramFiles(x86)"),   "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
        file.path(Sys.getenv("LOCALAPPDATA"),        "BraveSoftware", "Brave-Browser", "Application", "brave.exe")),
      Darwin = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
      c("/usr/bin/brave-browser", "/usr/bin/brave", "/snap/bin/brave", "/opt/brave.com/brave/brave-browser"))
    brave <- candidatos[file.exists(candidatos)]
    if (length(brave) > 0) Sys.setenv(CHROMOTE_CHROME = brave[1])
  }
  ruta <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  if (is.null(ruta) || !nzchar(ruta)) {
    stop("La actualizacion en linea necesita Brave, Chrome, Chromium o Edge instalado.\n",
         "  Instala uno, o define CHROMOTE_CHROME con la ruta del ejecutable,\n",
         "  o usa el modo sin conexion (no scrapea: reprocesa los CSV de raw/).", call. = FALSE)
  }
  cat("Navegador para el scraping:", ruta, "\n")
  invisible(ruta)
}

CATALOGO_COMPARABLES <- tibble::tribble(
  ~id_producto, ~producto_comparable,                     ~exito,    ~farmatodo,  ~larebaja,
  1L, "Lubriderm humectación diaria 200 ml",              "3155351", "293400550", "3493",
  2L, "Lubriderm humectación diaria 400 ml",              "3155352", "293400592", "2589",
  3L, "Lubriderm humectación diaria 946 ml",              "3155353", "291550571", "9796",
  4L, "Lubriderm humectación delicada 400 ml",            "3179125", "203000123", "2642",
  5L, "Lubriderm reparación intensiva 946 ml",            "869499",  "1046197",   "9795",
  6L, "Lubriderm humectación diaria 120 ml",              "3155350", "293400568", "2588",
  7L, "Lubriderm FPS 15 200 ml",                          "311800",  "1015664",   "3494",
  8L, "Lubriderm FPS 15 400 ml",                          "128396",  "213300197", "4608",
  9L, "Nivea hidratación express 1000 ml",                "283481",  "1043756",   "1431"
)

catalogo_largo <- CATALOGO_COMPARABLES %>%
  tidyr::pivot_longer(-c(id_producto, producto_comparable),
                      names_to = "comercio", values_to = "sku") %>%
  filter(!is.na(sku))

stopifnot(
  !anyDuplicated(CATALOGO_COMPARABLES$id_producto),
  !anyDuplicated(catalogo_largo[, c("comercio", "sku")])
)

REINTENTOS <- 2

REGEX_DESCUENTO_CONDICIONAL <- "(?i)\\b(1ra|primera|prime|tarjeta|cup[oó]n|app|web|membres[ií]a|banco|bancolombia|davivienda|afiliad[oa]s?|suscri\\w*|c[oó]digo|club)\\b"

COLUMNAS_FINALES <- c(
  "comercio", "busqueda", "id_ejecucion", "fecha_consulta",
  "sku", "nombres", "marca", "presentacion", "envase",
  "medida", "cantidad_unidad", "unidades", "cantidad_total",
  "precio_lista_cop", "precio_real_cop", "oferta_general", "precio_medida",
  "url", "texto_original_anuncio"
)

TIPOS_COLUMNAS <- c(
  comercio = "character", busqueda = "character", id_ejecucion = "character",
  fecha_consulta = "character", sku = "character", nombres = "character",
  marca = "character", presentacion = "character", envase = "character",
  medida = "character", cantidad_unidad = "numeric", unidades = "numeric",
  cantidad_total = "numeric", precio_lista_cop = "integer", precio_real_cop = "integer",
  oferta_general = "integer", precio_medida = "numeric", url = "character",
  texto_original_anuncio = "character"
)

tipificar_base <- function(df) {
  faltan <- setdiff(COLUMNAS_FINALES, names(df))
  if (length(faltan) > 0) {
    stop("Faltan columnas del esquema final: ", paste(faltan, collapse = ", "), call. = FALSE)
  }
  df <- dplyr::select(tibble::as_tibble(df), dplyr::all_of(COLUMNAS_FINALES))
  for (col in COLUMNAS_FINALES) {
    df[[col]] <- switch(TIPOS_COLUMNAS[[col]],
                        character = as.character(df[[col]]),
                        integer   = suppressWarnings(as.integer(df[[col]])),
                        numeric   = suppressWarnings(as.numeric(df[[col]])))
  }
  df
}

normalizar_texto <- function(x) {
  x <- tolower(x)
  x <- chartr("áéíóúüñ", "aeiouun", x)
  trimws(gsub("\\s+", " ", x))
}

precio_a_cop <- function(x) {
  x <- str_remove_all(x, "[^0-9.,]")
  x <- str_remove(x, ",\\d{1,2}$")
  as.integer(round(as.numeric(str_remove_all(x, "[.,]"))))
}

a_numero <- function(x) {
  x <- str_remove_all(x, "\\s")
  miles <- str_detect(x, "^\\d{1,3}([.,]\\d{3})+$")
  x <- if_else(miles, str_remove_all(x, "[.,]"), str_replace(x, ",", "."))
  as.numeric(x)
}

unir_textos <- function(x) {
  x <- unique(str_squish(x[!is.na(x)]))
  x <- x[nzchar(x)]
  if (length(x) == 0) NA_character_ else paste(x, collapse = " | ")
}

marca_tiempo <- function(momento = Sys.time()) {
  fecha <- format(momento, "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  list(
    fecha_consulta = sub("(\\d{2})(\\d{2})$", "\\1:\\2", fecha),
    id_ejecucion   = format(momento, "%Y%m%d%H%M%S", tz = "America/Bogota")
  )
}

tabla_productos_vacia <- function() {
  tibble(id_ejecucion = character(),
         fecha_consulta = character(),
         nombres = character(),
         presentacion = character(),
         marca = character(),
         precio_cop = character(),
         precio_oferta = character(),
         condicion_promocion = character(),
         url = character(),
         sku = character(),
         texto_original_anuncio = character())
}

obtener_config_busqueda <- function(cm, termino_busqueda) {
  clave <- normalizar_texto(paste(termino_busqueda, collapse = " "))
  for (k in names(cm$catalogo)) {
    cfg <- cm$catalogo[[k]]
    if (clave %in% c(k, normalizar_texto(cfg$alias))) {
      if (is.null(cfg$termino)) cfg$termino <- k
      return(cfg)
    }
  }
  stop("[", cm$nombre, "] La busqueda '", clave, "' no esta en su catalogo.\n  Disponibles: ",
       paste(names(cm$catalogo), collapse = " | "), call. = FALSE)
}

aplicar_regla_descarte <- function(datos, regla, conservar = character(0)) {
  if (is.null(regla) || nrow(datos) == 0) return(datos)
  
  n     <- normalizar_texto(datos$nombres)
  tiene <- function(palabra) grepl(paste0("\\b", palabra, "\\b"), n, perl = TRUE)
  
  ok <- rep(TRUE, length(n))
  for (p in regla$requerir) ok <- ok & tiene(p)
  for (p in regla$excluir)  ok <- ok & !tiene(p)
  ok <- ok | (trimws(datos$sku) %in% conservar)
  
  datos[ok, , drop = FALSE]
}

LOG <- new.env()

reiniciar_log <- function() {
  LOG$filtros <- tibble(comercio = character(), id_ejecucion = character(),
                        busqueda = character(), filtro = character(),
                        url = character(), estado = character(), intentos = integer(),
                        n_capturados = integer(), n_tras_descarte = integer(), mensaje = character())
}

reiniciar_log()

registrar_log <- function(comercio, id_ejecucion, busqueda, filtro = NA_character_, url = NA_character_,
                          estado, intentos = NA_integer_, n_capturados = NA_integer_,
                          n_tras_descarte = NA_integer_, mensaje = NA_character_) {
  LOG$filtros <- bind_rows(LOG$filtros, tibble(
    comercio = comercio, id_ejecucion = id_ejecucion, busqueda = busqueda, filtro = filtro,
    url = url, estado = estado, intentos = as.integer(intentos),
    n_capturados = as.integer(n_capturados), n_tras_descarte = as.integer(n_tras_descarte),
    mensaje = mensaje))
}

scrapear_pagina_segura <- function(cm, url, pausa = 4, ts = marca_tiempo(), reintentos = REINTENTOS) {
  force(ts)
  mensaje <- NA_character_
  datos   <- tabla_productos_vacia()
  for (i in seq_len(reintentos + 1)) {
    res <- tryCatch(cm$scrapear_pagina(url, pausa = pausa, ts = ts), error = function(e) e)
    
    if (inherits(res, "error")) {
      mensaje <- conditionMessage(res)
      cat("   intento", i, "de", reintentos + 1, "FALLO:", mensaje, "\n")
    } else if (nrow(res) == 0) {
      mensaje <- NA_character_
      cat("   intento", i, "de", reintentos + 1, "sin productos\n")
    } else {
      return(list(datos = res, estado = "ok", intentos = i, mensaje = NA_character_))
    }
    if (i <= reintentos) Sys.sleep(3 * i)
  }
  estado <- if (is.na(mensaje)) "sin_resultados" else "error"
  list(datos = datos, estado = estado, intentos = reintentos + 1, mensaje = mensaje)
}

scrapear_busqueda <- function(cm, termino_busqueda, pausa = 4, ts = marca_tiempo()) {
  force(ts)                      # misma fecha / id_ejecucion para TODAS las URLs
  cfg <- obtener_config_busqueda(cm, termino_busqueda)
  conservar <- catalogo_largo$sku[catalogo_largo$comercio == cm$nombre]
  
  resultados <- purrr::map(cfg$filtros, function(f) {
    url <- cm$url_del_filtro(cfg, f)
    cat("\n>>", f$etiqueta, "\n   ", url, "\n")
    
    r <- scrapear_pagina_segura(cm, url, pausa = pausa, ts = ts)
    
    datos <- tryCatch(aplicar_regla_descarte(r$datos, f$regla, conservar), error = function(e) {
      r$estado  <<- "error"
      r$mensaje <<- paste("descarte:", conditionMessage(e))
      tabla_productos_vacia()
    })
    
    cat("   estado:", r$estado, "|", nrow(r$datos), "capturados ->", nrow(datos), "tras el descarte\n")
    registrar_log(cm$nombre, ts$id_ejecucion, cfg$termino, f$etiqueta, url, r$estado, r$intentos,
                  nrow(r$datos), nrow(datos), r$mensaje)
    datos
  })
  
  # todo lo crudo es texto: se fuerza para que ningun filtro pueda romper la union
  resultados <- purrr::map(resultados, ~ dplyr::mutate(.x, dplyr::across(dplyr::everything(), as.character)))
  res <- dplyr::bind_rows(resultados)
  if (nrow(res) == 0) return(res)
  
  n_antes <- nrow(res)
  res <- res %>% distinct(sku, .keep_all = TRUE)       # una busqueda por filtro => coincidencias
  cat("\nDuplicados eliminados entre filtros:", n_antes - nrow(res), "\n")
  # informativo: nunca debe poder tumbar una busqueda ya scrapeada
  tryCatch(reportar_promociones(res), error = function(e) cat("   (no se pudo resumir las promociones: ", conditionMessage(e), ")\n", sep = ""))
  res
}

normalizar_precios <- function(df) {
  df %>%
    mutate(
      precio_lista_cop = precio_a_cop(precio_cop),
      .oferta      = precio_a_cop(precio_oferta),
      .condicional = str_detect(coalesce(condicion_promocion, ""), REGEX_DESCUENTO_CONDICIONAL),
      oferta_general = as.integer(!is.na(.oferta) & !is.na(precio_lista_cop) &
                                    .oferta < precio_lista_cop & !.condicional),
      precio_real_cop = if_else(oferta_general == 1L, .oferta, precio_lista_cop)
    )
}

reportar_promociones <- function(df) {
  if (nrow(df) == 0) return(invisible(NULL))
  lista  <- precio_a_cop(df$precio_cop)
  oferta <- precio_a_cop(df$precio_oferta)
  con_desc <- !is.na(oferta) & !is.na(lista) & oferta < lista
  cond <- df$condicion_promocion[con_desc]
  
  general <- con_desc & !str_detect(coalesce(df$condicion_promocion, ""), REGEX_DESCUENTO_CONDICIONAL)
  cat("   descuentos: ", sum(con_desc), " de ", nrow(df), " productos | oferta general: ", sum(general), "\n", sep = "")
  
  vistos <- table(coalesce(cond, "(sin condicion)"))
  for (t in names(vistos)) {
    clase <- if (t == "(sin condicion)") "GENERAL (sin condicion)" else
      if (str_detect(t, REGEX_DESCUENTO_CONDICIONAL)) "condicional (NO general)" else "GENERAL"
    cat(sprintf("      %-38s -> %-26s n = %d\n", t, clase, vistos[[t]]))
  }
  invisible(NULL)
}

RX_NUM  <- "\\d+(?:[.,]\\d+)*"

RX_UNID <- "(?:ml|cc|mililitros?|l|lt|lts|litros?|g|gr|grs|gramos?|kg|kilos?)"

RX_ENVASE <- "\\b(botella|frasco|pote|tarro|tubo|caja|barra|sobre|bolsa|dispensador|atomizador|spray|ampolla|sachet|lata)\\b"

rx_cont_x   <- regex(paste0("\\bx\\s*(", RX_NUM, ")\\s*(", RX_UNID, ")\\b"), ignore_case = TRUE)

rx_cont_any <- regex(paste0("(?<![\\d.,])(", RX_NUM, ")\\s*(", RX_UNID, ")\\b"), ignore_case = TRUE)

contenido_cantidad <- function(texto) {
  a_numero(coalesce(str_match(texto, rx_cont_x)[, 2], str_match(texto, rx_cont_any)[, 2]))
}

contenido_unidad <- function(texto) {
  str_to_lower(coalesce(str_match(texto, rx_cont_x)[, 3], str_match(texto, rx_cont_any)[, 3]))
}

RX_N      <- "([2-9]|[12][0-9]|3[0-6])"

NO_MEDIDA <- paste0("(?!\\s*", RX_UNID, "\\b)")

rx_six  <- regex("\\bsix\\s*-?\\s*pack\\b", ignore_case = TRUE)

rx_x    <- regex(paste0("\\bx\\s*", RX_N, NO_MEDIDA, "\\s*(?:und(?:s)?|unidades?)?\\b"), ignore_case = TRUE)

rx_pack <- regex(paste0("\\b", RX_N, "\\s*-?\\s*pack\\b"), ignore_case = TRUE)

rx_und  <- regex(paste0("\\b", RX_N, "\\s*(?:und(?:s)?|unidades?)\\b"), ignore_case = TRUE)

estandarizar_contenido <- function(df) {
  df %>%
    mutate(
      .texto_medida = str_squish(str_replace_all(paste(coalesce(presentacion, ""), nombres), "[()]", " ")),
      
      envase = coalesce(
        str_extract(normalizar_texto(presentacion), RX_ENVASE),
        str_extract(normalizar_texto(nombres),      RX_ENVASE)
      ) %>% str_replace("^tarro$", "pote"),
      
      .cant = contenido_cantidad(.texto_medida),
      .uni  = contenido_unidad(.texto_medida),
      .uni_std = case_when(
        .uni %in% c("ml", "cc") | str_detect(.uni, "^mililitro") ~ "ml",
        .uni %in% c("l", "lt", "lts") | str_detect(.uni, "^litro") ~ "l",
        .uni %in% c("g", "gr", "grs") | str_detect(.uni, "^gramo") ~ "g",
        .uni == "kg" | str_detect(.uni, "^kilo") ~ "kg"
      ),
      
      medida = case_when(.uni_std %in% c("ml", "l") ~ "ml",
                         .uni_std %in% c("g", "kg") ~ "g"),
      cantidad_unidad = case_when(.uni_std %in% c("ml", "g") ~ .cant,
                                  .uni_std %in% c("l", "kg") ~ .cant * 1000),
      
      unidades = case_when(
        str_detect(.texto_medida, rx_six)  ~ 6,
        str_detect(.texto_medida, rx_x)    ~ as.numeric(str_match(.texto_medida, rx_x)[, 2]),
        str_detect(.texto_medida, rx_pack) ~ as.numeric(str_match(.texto_medida, rx_pack)[, 2]),
        str_detect(.texto_medida, rx_und)  ~ as.numeric(str_match(.texto_medida, rx_und)[, 2]),
        TRUE ~ 1
      ),
      
      cantidad_total = unidades * cantidad_unidad,
      precio_medida  = round(precio_real_cop / cantidad_total, 2)
    )
}

estandarizar_productos <- function(df) {
  if (nrow(df) == 0) return(df)
  df %>% normalizar_precios() %>% estandarizar_contenido()
}

rescatar_datos <- function(df, ruta_base, motivo) {
  slug   <- gsub("[^a-z0-9]+", "_", normalizar_texto(df$busqueda[1]))
  nombre <- paste0("RESCATE_", df$id_ejecucion[1], "_", slug, "_", basename(ruta_base))
  ruta_r <- file.path(dirname(ruta_base), nombre)
  
  old <- options(scipen = 999); on.exit(options(old), add = TRUE)
  ok <- tryCatch({ write.csv(df, ruta_r, row.names = FALSE); TRUE }, error = function(e) FALSE)
  if (!ok) { ruta_r <- file.path(tempdir(), nombre); write.csv(df, ruta_r, row.names = FALSE) }
  
  cat("!! NO se pudo escribir el respaldo (", motivo, ").\n   Los datos nuevos quedaron en: ", ruta_r, "\n", sep = "")
  invisible(FALSE)
}

guardar_respaldo <- function(df, ruta_base) {
  if (nrow(df) == 0) return(invisible(TRUE))
  old <- options(scipen = 999); on.exit(options(old), add = TRUE)
  
  ok <- tryCatch({
    dir.create(dirname(ruta_base), recursive = TRUE, showWarnings = FALSE)
    existe <- file.exists(ruta_base) && file.size(ruta_base) > 0
    encabezado <- if (existe) {
      tryCatch(names(read.csv(ruta_base, nrows = 0, check.names = FALSE)), error = function(e) character(0))
    } else NULL
    
    if (!existe) {
      write.csv(df, ruta_base, row.names = FALSE)
    } else if (identical(encabezado, COLUMNAS_FINALES)) {
      write.table(df, ruta_base, sep = ",", row.names = FALSE, col.names = FALSE,
                  append = TRUE, qmethod = "double")
    } else {
      copia <- sub("\\.csv$", paste0("_ANTES_DE_UNIFICAR_", format(Sys.time(), "%Y%m%d%H%M%S"), ".csv"), ruta_base)
      if (!file.rename(ruta_base, copia)) stop("no se pudo apartar la base anterior")
      cat("   (respaldo con otro esquema: el archivo anterior quedo en ", basename(copia), ")\n", sep = "")
      write.csv(df, ruta_base, row.names = FALSE)
    }
    TRUE
  }, error = function(e) e)
  
  if (inherits(ok, "error")) return(rescatar_datos(df, ruta_base, conditionMessage(ok)))
  cat("   respaldo: ", nrow(df), " filas -> ", basename(ruta_base), "\n", sep = "")
  invisible(TRUE)
}

ejecutar_busquedas <- function(cm, terminos = NULL, ts = marca_tiempo(), ruta_base = NULL,
                               pausa = 4, respaldar = TRUE) {
  force(ts)
  if (is.null(terminos)) terminos <- names(cm$catalogo)
  acumulado <- list()
  
  for (t in terminos) {
    cat("\n====================", toupper(cm$nombre), "|", t, "====================\n")
    
    cfg <- tryCatch(obtener_config_busqueda(cm, t), error = function(e) e)
    if (inherits(cfg, "error")) {
      cat("!! La busqueda '", t, "' fallo: ", conditionMessage(cfg), "\n", sep = "")
      registrar_log(cm$nombre, ts$id_ejecucion, t, estado = "error_busqueda", mensaje = conditionMessage(cfg))
      next
    }
    
    # 1) scraping
    datos <- tryCatch(scrapear_busqueda(cm, t, pausa = pausa, ts = ts), error = function(e) {
      cat("!! La busqueda '", t, "' fallo: ", conditionMessage(e), "\n", sep = "")
      registrar_log(cm$nombre, ts$id_ejecucion, cfg$termino, estado = "error_busqueda", mensaje = conditionMessage(e))
      NULL
    })
    if (is.null(datos) || nrow(datos) == 0) { cat("   (sin productos para guardar)\n"); next }
    
    # 2) estandarizacion al esquema final
    out <- tryCatch(
      datos %>%
        estandarizar_productos() %>%
        mutate(comercio = cm$nombre, busqueda = cfg$termino) %>%
        select(all_of(COLUMNAS_FINALES)) %>%
        tipificar_base(),
      error = function(e) {
        registrar_log(cm$nombre, ts$id_ejecucion, cfg$termino, estado = "error_estandarizacion", mensaje = conditionMessage(e))
        if (respaldar && !is.null(ruta_base)) {
          rescatar_datos(mutate(datos, busqueda = cfg$termino), ruta_base, paste("estandarizacion:", conditionMessage(e)))
        } else cat("!! estandarizacion fallo: ", conditionMessage(e), "\n", sep = "")
        NULL
      })
    if (is.null(out)) next
    
    # 3) respaldo (solo escribe) y 4) memoria
    if (respaldar && !is.null(ruta_base)) guardar_respaldo(out, ruta_base)
    acumulado[[length(acumulado) + 1]] <- out
  }
  
  # ---- resumen del comercio ----
  cat("\n\n==================== RESUMEN ", toupper(cm$nombre), " ====================\n", sep = "")
  log_cm <- LOG$filtros %>% filter(comercio == cm$nombre)
  if (nrow(log_cm) > 0) {
    print(as.data.frame(log_cm[, c("busqueda", "filtro", "estado", "intentos", "n_capturados", "n_tras_descarte")]),
          row.names = FALSE, right = FALSE)
  }
  
  todo <- if (length(acumulado) > 0) dplyr::bind_rows(acumulado) else tibble()
  if (nrow(todo) > 0) {
    cat("\n")
    print(as.data.frame(todo %>% group_by(busqueda) %>%
                          summarise(productos = n(), con_oferta_general = sum(oferta_general == 1L, na.rm = TRUE),
                                    sin_medida = sum(is.na(medida)), .groups = "drop")),
          row.names = FALSE)
  }
  
  problemas <- log_cm %>% filter(estado != "ok")
  if (nrow(problemas) > 0) {
    cat("\n!! REVISAR: ", nrow(problemas), " consulta(s) de ", cm$nombre,
        " no terminaron en 'ok' (ver estado y mensaje en el log)\n", sep = "")
  } else {
    cat("\nTodas las consultas de ", cm$nombre, " terminaron en 'ok'.\n", sep = "")
  }
  invisible(todo)
}

leer_respaldos <- function(dir_raw, comercios) {
  piezas <- list()
  for (cmn in comercios) {
    ruta <- file.path(dir_raw, paste0("resultado_seguro_", cmn, ".csv"))
    if (!file.exists(ruta)) { warning("No existe el respaldo de ", cmn, ": ", ruta, call. = FALSE); next }
    d <- read.csv(ruta, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE,
                  encoding = "UTF-8")
    if (!identical(names(d), COLUMNAS_FINALES)) {
      warning("El respaldo de ", cmn, " no tiene el esquema final (se omite): ", ruta, call. = FALSE)
      next
    }
    cat("  respaldo leido:", basename(ruta), "->", nrow(d), "filas\n")
    piezas[[cmn]] <- tipificar_base(d)
  }
  if (length(piezas) == 0) stop("No se pudo leer ningun respaldo en: ", dir_raw, call. = FALSE)
  dplyr::bind_rows(piezas)
}

EX_BASE_URL      <- "https://www.exito.com"

EX_SEL_NODOS     <- "ul[data-fs-product-grid-list='true'] > li"

EX_SEL_LINKS     <- "ul[data-fs-product-grid-list='true'] > li a[data-testid='product-link']"

EX_SEL_BOTON_SIG <- "button[aria-label*='xima']:not([disabled])"

ex_extraer_producto <- function(nodo) {
  txt <- function(css) nodo %>% html_element(css) %>% html_text2()
  
  nombres <- txt("h3")
  
  # ("... (946 gr)", "... X1000ml", "... 562 Ml")
  presentacion <- nombres %>%
    str_extract("(?i)\\d+(?:[.,]\\d+)?\\s*(?:ml|gr|g|kg|lt|l|oz|und|unds|unidades)\\b")
  
  marca <- nombres %>%
    str_extract("\\b[A-ZÁÉÍÓÚÑ]{2,}(?:\\s+[A-ZÁÉÍÓÚÑ]{1,}\\b)*")
  
  precio_final_txt <- txt("p[data-fs-container-price-otros='true']")
  precio_lista_txt <- txt("p[class*='price-dashed']")
  hay_desc <- !is.na(precio_a_cop(precio_lista_txt)) && !is.na(precio_a_cop(precio_final_txt)) &&
    precio_a_cop(precio_lista_txt) > precio_a_cop(precio_final_txt)
  
  href <- nodo %>% html_element("a[data-testid='product-link']") %>% html_attr("href")
  url  <- if (is.na(href)) NA_character_ else url_absolute(href, EX_BASE_URL)
  
  # Exito no expone SKU en la tarjeta: se usa el id numerico del final de la URL
  # (".../crema-corporal-uv15-878339/p" -> 878339; ".../...-104294822-mp/p" -> 104294822)
  sku <- str_match(href, "-(\\d+)(?:-mp)?/p/?$")[, 2]
  if (is.na(sku)) sku <- str_remove_all(href, "^/|/p/?$")
  
  tibble(
    nombres = nombres,
    presentacion = presentacion,
    marca = marca,
    precio_cop = if (hay_desc) precio_lista_txt else precio_final_txt,
    precio_oferta = if (hay_desc) precio_final_txt else NA_character_,
    condicion_promocion = NA_character_,
    url = url,
    sku = sku,
    texto_original_anuncio = html_text2(nodo)
  )
}

EX_CAT_CREMAS  <- c("category-1" = "cuidado-personal",
                    "category-2" = "cuidado-corporal",
                    "category-3" = "cremas-de-manos-y-cuerpo")

EX_CAT_ACEITES <- c("category-1" = "cuidado-personal",
                    "category-2" = "cuidado-corporal",
                    "category-3" = "aceites-corporales")

EX_PALABRAS_MANOS_BEBES <- c("mano", "manos", "baby", "bebe", "bebes")

EX_CATALOGO_BUSQUEDAS <- list(
  
  "crema hidratante corporal" = list(
    termino = "crema hidratante corporal",
    alias   = c("crema hidrante corporal"),
    filtros = list(
      list(etiqueta = "subcategoria: Cremas de manos y cuerpo",
           cats     = EX_CAT_CREMAS,
           regla    = list(requerir = "corporal",
                           excluir  = EX_PALABRAS_MANOS_BEBES))
    )
  ),
  
  "aceite corporal" = list(
    termino = "aceite corporal",
    filtros = list(
      list(etiqueta = "subcategoria: Aceites corporales",
           cats     = EX_CAT_ACEITES,
           regla    = list(requerir = "corporal",
                           excluir  = EX_PALABRAS_MANOS_BEBES))
    )
  ),
  
  # Solo cremas: se exige "crema" y "corporal", se descartan las de manos
  "exfoliante" = list(
    termino = "exfoliante",
    filtros = list(
      list(etiqueta = "subcategoria: Cremas de manos y cuerpo",
           cats     = EX_CAT_CREMAS,
           regla    = list(requerir = c("crema", "corporal"),
                           excluir  = c("mano", "manos")))
    )
  ),
  
  # Se toman TODOS los productos de ambas subcategorias (sin descarte):
  # cremas, aceites, mantequillas, productos de masaje, etc.
  "estrias" = list(
    termino = "estrías",
    filtros = list(
      list(etiqueta = "subcategoria: Cremas de manos y cuerpo",
           cats     = EX_CAT_CREMAS),
      list(etiqueta = "subcategoria: Aceites corporales",
           cats     = EX_CAT_ACEITES)
    )
  )
)

ex_codificar_q <- function(x) {
  x <- utils::URLencode(enc2utf8(x), reserved = TRUE)
  gsub("%20", "+", x, fixed = TRUE)
}

ex_construir_url_busqueda <- function(termino_busqueda, cats = NULL, pagina = 0,
                                      orden = "score_desc") {
  q <- ex_codificar_q(paste(termino_busqueda, collapse = " "))
  
  partes <- paste0("q=", q)
  if (!is.null(cats) && length(cats) > 0) {
    partes <- c(partes,
                paste0(names(cats), "=", cats),
                paste0("facets=", paste(names(cats), collapse = "%2C")))
  }
  partes <- c(partes, paste0("sort=", orden), paste0("page=", pagina))
  
  paste0(EX_BASE_URL, "/s?", paste(partes, collapse = "&"))
}

ex_url_del_filtro <- function(cfg, f) ex_construir_url_busqueda(cfg$termino, f$cats)

ex_html_actual <- function(sesion) {
  r <- tryCatch(
    sesion$session$Runtime$evaluate("document.documentElement.outerHTML")$result$value,
    error = function(e) NULL)
  if (is.null(r) || !is.character(r) || !nzchar(r)) return(NULL)
  xml2::read_html(r)
}

ex_firma_pagina <- function(sesion) {
  doc <- ex_html_actual(sesion)
  if (is.null(doc)) return("")
  h <- doc %>% html_elements(EX_SEL_LINKS) %>% html_attr("href")
  paste(head(h, 6), collapse = "|")
}

ex_esperar_productos <- function(sesion, max_seg = 25) {
  for (i in seq_len(max_seg)) {
    doc <- ex_html_actual(sesion)
    if (!is.null(doc) && length(html_elements(doc, EX_SEL_NODOS)) > 0) return(TRUE)
    Sys.sleep(1)
  }
  FALSE
}

ex_clic_siguiente <- function(sesion) {
  js <- "(function(){
    var b = document.querySelector(\"button[aria-label*='xima']:not([disabled])\");
    if (!b) return false;
    b.scrollIntoView({block: 'center'});
    b.click();
    return true;
  })()"
  r <- tryCatch(sesion$session$Runtime$evaluate(js)$result$value, error = function(e) FALSE)
  isTRUE(r)
}

ex_ir_a_siguiente <- function(sesion, espera_max = 20) {
  antes <- ex_firma_pagina(sesion)
  if (!ex_clic_siguiente(sesion)) return(FALSE)     # sin boton activo = ultima pagina
  
  for (i in seq_len(espera_max)) {
    Sys.sleep(1)
    ahora <- ex_firma_pagina(sesion)
    if (nzchar(ahora) && ahora != antes) {
      Sys.sleep(1.5)                                # deja terminar de pintar la grilla
      return(TRUE)
    }
  }
  FALSE
}

ex_abrir_sesion <- function(url, intentos = 3) {
  for (i in seq_len(intentos)) {
    sesion <- tryCatch(abrir_pagina_live(url), error = function(e) {
      cat("   intento", i, "de", intentos, "fallo al abrir:", conditionMessage(e), "\n")
      NULL
    })
    if (!is.null(sesion)) return(sesion)
    Sys.sleep(3 * i)
  }
  NULL
}

ex_scrapear_pagina_live <- function(url, pausa = 4, ts = marca_tiempo(), max_paginas = 60) {
  force(ts)                      # fija la fecha AL INICIO de la consulta
  sesion <- ex_abrir_sesion(url)
  if (is.null(sesion)) {
    warning("No se pudo abrir: ", url, call. = FALSE)
    return(tabla_productos_vacia())
  }
  on.exit(try(sesion$session$close(), silent = TRUE), add = TRUE)
  
  Sys.sleep(pausa)
  if (!ex_esperar_productos(sesion)) return(tabla_productos_vacia())
  
  acumulado <- list()
  for (pag in seq_len(max_paginas)) {
    doc <- ex_html_actual(sesion)
    if (is.null(doc)) break
    nodos <- doc %>% html_elements(EX_SEL_NODOS)
    if (length(nodos) == 0) break
    
    acumulado[[pag]] <- purrr::map_dfr(nodos, ex_extraer_producto)
    cat("  pagina", pag, "->", length(nodos), "productos\n")
    
    if (!ex_ir_a_siguiente(sesion)) break
  }
  
  if (length(acumulado) == 0) return(tabla_productos_vacia())
  
  dplyr::bind_rows(acumulado) %>%
    filter(!is.na(nombres)) %>%                     # <li> que no son productos
    distinct(sku, .keep_all = TRUE) %>%
    mutate(
      id_ejecucion   = ts$id_ejecucion,
      fecha_consulta = ts$fecha_consulta,
      .before = 1
    )
}

fa_extraer_producto <- function(nodo) {
  nombres <- nodo %>% html_element("a.product-card-handler__detail-description") %>% html_text2()
  
  presentacion <- nodo %>% html_element("a.product-card-handler__detail-description") %>% html_text2() %>%
    str_extract("(?i)(?:(?:botella|pote|frasco|tubo|caja|barra|sobre|bolsa|dispensador)\\s+)?x\\s*\\d+(?:[.,]\\d+)?\\s*(?:ml|gr|g|kg|lt|l|oz|und|unds|unidades)\\b")
  
  marca <- nodo %>% html_element("p.product-card-handler__brand-value") %>% html_text2()
  
  precio_cop    <- nodo %>% html_element("span.product-all-price__normal") %>% html_text2()
  precio_oferta <- nodo %>% html_element("span.product-all-price__offer") %>% html_text2()
  
  condicion_promocion <- nodo %>% html_elements("span.product-offer-description__text-value") %>%
    html_text2() %>% unir_textos()
  
  url <- nodo %>% html_element("a.product-card-handler__detail-description") %>% html_attr("href") %>%
    url_absolute("https://www.farmatodo.com.co")
  
  sku <- nodo %>% html_element("button.app-button__icon-plus") %>% html_attr("data-cuf")
  
  texto_original_anuncio <- nodo %>% html_text2()
  
  tibble(
    nombres = nombres,
    presentacion = presentacion,
    marca = marca,
    precio_cop = precio_cop,
    precio_oferta = precio_oferta,
    condicion_promocion = condicion_promocion,
    url = url,
    sku = sku,
    texto_original_anuncio = texto_original_anuncio
  )
}

FA_CATALOGO_BUSQUEDAS <- list(
  
  "crema hidratante corporal" = list(
    termino = "crema hidratante corporal",
    alias   = c("crema hidrante corporal"),
    filtros = list(
      list(etiqueta = "categoria: Corporal",
           expr     = "categorie:'Corporal'"),
      list(etiqueta = "subcategoria: Cuidado corporal",
           expr     = "subCategory:'Cuidado corporal'",
           regla    = list(requerir = c("crema", "corporal")))
    )
  ),
  
  "aceite corporal" = list(
    termino = "aceite corporal",
    filtros = list(
      list(etiqueta = "categoria: Corporal",
           expr     = "categorie:'Corporal'"),
      list(etiqueta = "subcategoria: Cuidado corporal",
           expr     = "subCategory:'Cuidado corporal'",
           regla    = list(requerir = "aceite",
                           excluir  = c("locion", "gel", "crema", "solar")))
    )
  ),
  
  # una sola URL con ambos filtros combinados (como la arma la pagina)
  "exfoliante" = list(
    termino = "exfoliante",
    filtros = list(
      list(etiqueta = "categoria: Corporal o Cuidado de la piel + subcategoria: Cuidado corporal",
           expr     = "categorie:'Corporal' OR categorie:'Cuidado de la piel' AND subCategory:'Cuidado corporal'")
    )
  ),
  
  "estrias" = list(
    termino = "estrías",
    filtros = list(
      list(etiqueta = "categoria: Corporal",
           expr     = "categorie:'Corporal'"),
      list(etiqueta = "subcategoria: Cuidado corporal",
           expr     = "subCategory:'Cuidado corporal'",
           regla    = list(excluir = c("locion", "gel hidratante", "crema de sol", "solar"))),
      list(etiqueta = "subcategoria: Aceites corporales",
           expr     = "subCategory:'Aceites corporales'",
           regla    = list(excluir = c("locion", "gel hidratante", "crema de sol", "solar")))
    )
  )
)

fa_codificar_url <- function(x) {
  x <- utils::URLencode(enc2utf8(x), reserved = TRUE)
  gsub("%3A", ":", x, fixed = TRUE)
}

fa_construir_url_busqueda <- function(termino_busqueda, expr_filtro = NULL) {
  termino_url <- fa_codificar_url(paste(termino_busqueda, collapse = " "))
  filtros <- if (is.null(expr_filtro)) "" else paste0(" AND  ", expr_filtro)
  paste0("https://www.farmatodo.com.co/buscar?product=", termino_url,
         "&departamento=Todos&filtros=", fa_codificar_url(filtros))
}

fa_url_del_filtro <- function(cfg, f) fa_construir_url_busqueda(cfg$termino, f$expr)

FA_SEL_NODOS        <- "div.cont-card-ftd.cont-group-view__row > div.card-ftd"

FA_SEL_BOTON_ACTIVO <- "#group-view-load-more:not([disabled])"

fa_clic_cargar_mas <- function(sesion) {
  ok <- tryCatch({ sesion$click("#group-view-load-more"); TRUE }, error = function(e) FALSE)
  if (!ok) {   # plan B: clic por JavaScript
    sesion$session$Runtime$evaluate(
      expression = "document.querySelector('#group-view-load-more').click()")
  }
  invisible(ok)
}

fa_cargar_todo <- function(sesion, max_clics = 60, pausa = 2) {
  for (i in 1:20) {                                   # esperar los primeros productos (hasta 20 s)
    if (length(html_elements(sesion, FA_SEL_NODOS)) > 0) break
    Sys.sleep(1)
  }
  sin_cambio <- 0
  for (i in seq_len(max_clics)) {
    antes <- length(html_elements(sesion, FA_SEL_NODOS))
    sesion$scroll_by(top = 5000); Sys.sleep(1)        # el boton esta al final de la lista
    
    if (length(html_elements(sesion, FA_SEL_BOTON_ACTIVO)) == 0) {
      Sys.sleep(pausa)                                # puede estar deshabilitado mientras carga
      if (length(html_elements(sesion, FA_SEL_BOTON_ACTIVO)) == 0) break
    }
    fa_clic_cargar_mas(sesion)
    Sys.sleep(pausa)
    
    despues <- length(html_elements(sesion, FA_SEL_NODOS))
    cat("clic", i, "-> productos:", despues, "\n")
    sin_cambio <- if (despues <= antes) sin_cambio + 1 else 0
    if (sin_cambio >= 2) break                        # el clic no esta cargando nada
  }
  invisible(sesion)
}

fa_scrapear_pagina_live <- function(url, pausa = 4, ts = marca_tiempo()) {
  force(ts)                      # fija la fecha AL INICIO de la consulta
  sesion <- abrir_pagina_live(url)
  on.exit(try(sesion$session$close(), silent = TRUE), add = TRUE)
  
  Sys.sleep(pausa)
  fa_cargar_todo(sesion, pausa = 2)
  
  nodos <- sesion %>% html_elements(FA_SEL_NODOS)
  
  if (length(nodos) == 0) {
    return(tabla_productos_vacia())
  }
  
  purrr::map_dfr(nodos, fa_extraer_producto) %>%
    distinct(sku, .keep_all = TRUE) %>%
    mutate(
      id_ejecucion   = ts$id_ejecucion,
      fecha_consulta = ts$fecha_consulta,
      .before = 1
    )
}

lr_extraer_producto <- function(nodo) {
  nombres      <- nodo %>% html_element("h3.vtex-product-summary-2-x-productNameContainer") %>% html_text2()
  presentacion <- nodo %>% html_element("div.copservir-larebaja-theme-9-x-PUM-content-wrapper > span") %>% html_text2()
  marca        <- nodo %>% html_element("span.vtex-store-components-3-x-productBrandName") %>% html_text2()
  
  precio_venta <- nodo %>% html_element("span.vtex-product-price-1-x-sellingPriceValue") %>% html_text2()
  precio_antes <- nodo %>% html_element("span.vtex-product-price-1-x-listPriceValue") %>% html_text2()
  precio_cop    <- coalesce(precio_antes, precio_venta)
  precio_oferta <- if_else(!is.na(precio_antes), precio_venta, NA_character_)
  
  condicion_promocion <- nodo %>% html_elements("div.copservir-larebaja-theme-9-x-flagsConditionsCont") %>%
    html_text2() %>% unir_textos()
  
  url <- nodo %>% html_element("a.vtex-product-summary-2-x-clearLink") %>% html_attr("href") %>%
    url_absolute("https://www.larebajavirtual.com")
  
  sku <- nodo %>% html_attr("data-af-product-id")
  
  texto_original_anuncio <- nodo %>% html_text2()
  
  tibble(
    nombres = nombres,
    presentacion = presentacion,
    marca = marca,
    precio_cop = precio_cop,
    precio_oferta = precio_oferta,
    condicion_promocion = condicion_promocion,
    url = url,
    sku = sku,
    texto_original_anuncio = texto_original_anuncio
  )
}

LR_CATALOGO_BUSQUEDAS <- list(
  
  "crema corporal" = list(
    termino = "crema corporal",
    alias   = c("crema  corporal", "crema cuerpo"),   # como aparece en tus URLs
    filtros = list(
      list(etiqueta  = "categoria: Cuidado corporal",
           categoria = "cuidado-corporal",
           regla     = list(requerir = c("crema", "corporal")))   # "gel hidratante" o "crema" sin "corporal" se descartan
    )
  ),
  
  "aceite corporal" = list(
    termino = "aceite corporal",
    filtros = list(
      list(etiqueta  = "categoria: Cuidado corporal",
           categoria = "cuidado-corporal")
    )
  ),
  
  "exfoliante" = list(
    termino = "exfoliante",
    filtros = list(
      list(etiqueta  = "categoria: Cuidado corporal",
           categoria = "cuidado-corporal")
    )
  ),
  
  # sin categoria: las estrias se presentan tanto en facial como en corporal
  "estrias" = list(
    termino = "estrías",
    filtros = list(
      list(etiqueta  = "sin categoria",
           categoria = NULL)
    )
  )
)

lr_codificar_url <- function(x) utils::URLencode(enc2utf8(x), reserved = TRUE)

lr_construir_url_busqueda <- function(termino_busqueda, categoria = NULL, pagina = 1) {
  termino_url <- lr_codificar_url(paste(termino_busqueda, collapse = " "))
  base <- paste0("https://www.larebajavirtual.com/", termino_url, "?_q=", termino_url)
  
  if (is.null(categoria)) {
    paste0(base, "&map=ft&page=", pagina)
  } else {
    paste0(base, "&fuzzy=0&initialMap=ft&initialQuery=", termino_url,
           "&map=category-2,ft&operator=and&query=/", categoria, "/", termino_url,
           "&searchState&page=", pagina)
  }
}

lr_url_del_filtro <- function(cfg, f) lr_construir_url_busqueda(cfg$termino, f$categoria)

LR_SEL_NODOS     <- "#gallery-layout-container > div.vtex-search-result-3-x-galleryItem"

LR_SEL_BOTON_MAS <- "button.vtex-button.min-h-small"

lr_hay_boton_mostrar_mas <- function(sesion) {
  b <- html_elements(sesion, LR_SEL_BOTON_MAS)
  length(b) > 0 && any(str_detect(html_text2(b), regex("^\\s*mostrar m[aá]s\\s*$", ignore_case = TRUE)))
}

lr_clic_mostrar_mas <- function(sesion) {
  js <- paste0(
    "(function(){",
    "const b=[...document.querySelectorAll('", LR_SEL_BOTON_MAS, "')]",
    ".find(e=>/mostrar m(a|\\u00e1)s/i.test(e.innerText||''));",
    "if(!b) return false;",
    "b.scrollIntoView({block:'center'}); b.click(); return true;",
    "})()")
  r <- sesion$session$Runtime$evaluate(expression = js, returnByValue = TRUE)
  invisible(isTRUE(r$result$value))
}

lr_cargar_todo <- function(sesion, max_clics = 60, pausa = 2) {
  for (i in 1:20) {                                   # esperar los primeros productos (hasta 20 s)
    if (length(html_elements(sesion, LR_SEL_NODOS)) > 0) break
    Sys.sleep(1)
  }
  sin_cambio <- 0
  for (i in seq_len(max_clics)) {
    antes <- length(html_elements(sesion, LR_SEL_NODOS))
    sesion$scroll_by(top = 5000); Sys.sleep(1)        # el boton esta al final de la lista
    
    if (!lr_hay_boton_mostrar_mas(sesion)) {
      Sys.sleep(pausa)                                # puede desaparecer un momento mientras carga
      if (!lr_hay_boton_mostrar_mas(sesion)) break
    }
    lr_clic_mostrar_mas(sesion)
    Sys.sleep(pausa)
    
    despues <- length(html_elements(sesion, LR_SEL_NODOS))
    cat("clic", i, "-> productos:", despues, "\n")
    sin_cambio <- if (despues <= antes) sin_cambio + 1 else 0
    if (sin_cambio >= 2) break                        # el clic no esta cargando nada
  }
  invisible(sesion)
}

lr_scrapear_pagina_live <- function(url, pausa = 4, ts = marca_tiempo()) {
  force(ts)                      # fija la fecha AL INICIO de la consulta
  sesion <- abrir_pagina_live(url)
  on.exit(try(sesion$session$close(), silent = TRUE), add = TRUE)
  
  Sys.sleep(pausa)
  lr_cargar_todo(sesion, pausa = 2)
  
  nodos <- sesion %>% html_elements(LR_SEL_NODOS)
  
  if (length(nodos) == 0) {
    return(tabla_productos_vacia())
  }
  
  purrr::map_dfr(nodos, lr_extraer_producto) %>%
    distinct(sku, .keep_all = TRUE) %>%
    mutate(
      id_ejecucion   = ts$id_ejecucion,
      fecha_consulta = ts$fecha_consulta,
      .before = 1
    )
}

COMERCIOS <- list(
  exito = list(
    nombre          = "exito",
    catalogo        = EX_CATALOGO_BUSQUEDAS,
    url_del_filtro  = ex_url_del_filtro,
    scrapear_pagina = ex_scrapear_pagina_live
  ),
  farmatodo = list(
    nombre          = "farmatodo",
    catalogo        = FA_CATALOGO_BUSQUEDAS,
    url_del_filtro  = fa_url_del_filtro,
    scrapear_pagina = fa_scrapear_pagina_live
  ),
  larebaja = list(
    nombre          = "larebaja",
    catalogo        = LR_CATALOGO_BUSQUEDAS,
    url_del_filtro  = lr_url_del_filtro,
    scrapear_pagina = lr_scrapear_pagina_live
  )
)

for (.k in names(COMERCIOS)) {
  .cm <- COMERCIOS[[.k]]
  stopifnot(
    identical(.cm$nombre, .k),
    is.list(.cm$catalogo), length(.cm$catalogo) > 0,
    is.function(.cm$url_del_filtro), is.function(.cm$scrapear_pagina)
  )
}

.desconocidos <- setdiff(COMERCIOS_A_CORRER, names(COMERCIOS))

if (length(.desconocidos) > 0) {
  stop("Comercios sin ficha en COMERCIOS: ", paste(.desconocidos, collapse = ", "), call. = FALSE)
}

rm(.k, .cm, .desconocidos)

NOMBRES_COMERCIO <- c(exito = "\u00c9xito", farmatodo = "Farmatodo", larebaja = "La Rebaja")

SITIOS_COMERCIO  <- c(exito = "https://www.exito.com",
                      farmatodo = "https://www.farmatodo.com.co",
                      larebaja = "https://www.larebajavirtual.com")

SUBCATEGORIA_COMPARABLES <- "crema_corporal"

MARCAS_ALIAS <- c("NIVEA SUN" = "NIVEA", "LUBRIDERM FPS" = "LUBRIDERM")

RX_ISO8601 <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$"

marcar_comparables <- function(base) {
  cat_sku <- catalogo_largo %>%
    dplyr::transmute(comercio, .sku_limpio = trimws(sku),
                     id_producto = as.integer(id_producto), producto_comparable)
  base %>%
    dplyr::select(-dplyr::any_of(c("es_comparable", "id_producto", "producto_comparable"))) %>%
    dplyr::mutate(.sku_limpio = trimws(sku)) %>%
    dplyr::left_join(cat_sku, by = c("comercio", ".sku_limpio")) %>%
    dplyr::mutate(es_comparable = as.integer(!is.na(id_producto))) %>%
    dplyr::select(-.sku_limpio) %>%
    dplyr::relocate(es_comparable, id_producto, producto_comparable, .after = busqueda)
}

estandarizar_marca <- function(x) {
  m <- toupper(normalizar_texto(x))
  m <- trimws(gsub("[^A-Z0-9 ]", "", m))
  m[!nzchar(m)] <- NA_character_
  alias <- m %in% names(MARCAS_ALIAS)
  m[alias] <- unname(MARCAS_ALIAS[m[alias]])
  m
}

estandarizar_subcategoria <- function(nombres) {
  n <- normalizar_texto(nombres)
  dplyr::case_when(
    grepl("\\b(exfoliante|scrub)\\b", n)                                      ~ "exfoliante_corporal",
    grepl("\\b(crema|cremas|locion|leche|mantequilla|emulsion|hidratante)\\b", n) ~ "crema_corporal",
    grepl("\\baceite", n)                                                     ~ "aceite_corporal",
    TRUE                                                                      ~ "otros_corporal"
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

iso_desde_codigo <- function(codigo) {
  t <- as.POSIXct(codigo, format = "%Y%m%d%H%M%S", tz = "America/Bogota")
  f <- format(t, "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", f)
}

leer_log_csv <- function(ruta) {
  if (!file.exists(ruta)) return(NULL)
  tryCatch(read.csv(ruta, stringsAsFactors = FALSE, colClasses = "character"),
           error = function(e) NULL)
}

calcular_estado <- function(n, log_cm, n_faltan_catalogo) {
  errores <- log_cm$estado[log_cm$estado != "ok"]
  if (n == 0 || any(log_cm$estado == "error_comercio")) {
    return(list(estado = "fallida",
                mensaje = (log_cm$mensaje[!is.na(log_cm$mensaje) & nzchar(log_cm$mensaje)])[1] %||%
                  "sin registros"))
  }
  partes <- character(0)
  if (nrow(log_cm) == 0)       partes <- c(partes, "sin log de consultas para esta corrida")
  if (length(errores) > 0)     partes <- c(partes, sprintf("%d consulta(s) sin 'ok'", length(errores)))
  if (n_faltan_catalogo > 0)   partes <- c(partes, sprintf("%d producto(s) del catalogo sin precio", n_faltan_catalogo))
  if (length(partes) > 0) return(list(estado = "parcial", mensaje = paste(partes, collapse = "; ")))
  list(estado = "completa", mensaje = NA_character_)
}

asegurar_comercios <- function(con, codigos) {
  codigos <- unique(codigos[!is.na(codigos)])
  if (length(codigos) == 0) return(invisible(NULL))
  nombre <- ifelse(codigos %in% names(NOMBRES_COMERCIO), NOMBRES_COMERCIO[codigos], codigos)
  sitio  <- ifelse(codigos %in% names(SITIOS_COMERCIO),  SITIOS_COMERCIO[codigos],  NA_character_)
  DBI::dbExecute(con,
    "INSERT INTO comercios (codigo, nombre, sitio_web) VALUES (?, ?, ?)
     ON CONFLICT (codigo) DO NOTHING",
    params = list(codigos, unname(nombre), unname(sitio)))
  invisible(NULL)
}

guardar_en_sqlite <- function(con, base, log = NULL) {
  base <- tibble::as_tibble(base)
  if (!"url_extraccion" %in% names(base)) {
    # el scraper aun no guarda la URL de la pagina de busqueda: se usa la del producto
    base$url_extraccion <- base$url
  }

  # ---- 1. depuracion previa (lo que violaria el esquema se informa, no se oculta) ----
  base <- base %>%
    dplyr::mutate(sku = trimws(sku)) %>%
    dplyr::arrange(fecha_consulta)
  valida <- !is.na(base$sku) & nzchar(base$sku) & !is.na(base$nombres) &
    !is.na(base$precio_real_cop) & !is.na(base$precio_lista_cop) &
    base$precio_real_cop > 0 & base$precio_lista_cop > 0 &
    grepl(RX_ISO8601, base$fecha_consulta %||% "") & !is.na(base$url_extraccion)
  if (any(!valida)) {
    cat("!! ", sum(!valida), " fila(s) NO se guardan (sin sku, nombre, precio, fecha ISO 8601 o url):\n", sep = "")
    print(utils::head(base[!valida, c("comercio", "sku", "nombres", "precio_real_cop", "fecha_consulta")], 10))
  }
  descartadas <- base[!valida, ]
  base <- base[valida, ]

  # ---- 2. comparables: columna es_comparable / id_producto de la base general ----
  base <- marcar_comparables(base)
  cat(sprintf("Comparables en esta carga: %d de %d fila(s) validas\n", sum(base$es_comparable), nrow(base)))

  runs <- dplyr::bind_rows(
    dplyr::distinct(base, codigo_corrida = id_ejecucion, comercio),
    if (!is.null(log) && nrow(log) > 0) {
      dplyr::distinct(log[!is.na(log$comercio) & !is.na(log$id_ejecucion), ],
                      codigo_corrida = id_ejecucion, comercio)
    })
  runs <- dplyr::distinct(runs)
  ids_conjunto <- DBI::dbGetQuery(con, "SELECT id_producto FROM productos WHERE en_conjunto = 1")$id_producto  # [Taller 2]

  res <- DBI::dbWithTransaction(con, {

    asegurar_comercios(con, c(runs$comercio, base$comercio))
    cmap <- DBI::dbGetQuery(con, "SELECT id_comercio, codigo AS comercio FROM comercios")

    # ---- 3. ejecuciones (estado y n_registros se completan al final) ----
    runs <- dplyr::left_join(runs, cmap, by = "comercio")
    runs$fecha_hora_inicio <- iso_desde_codigo(runs$codigo_corrida)
    DBI::dbExecute(con,
      "INSERT INTO ejecuciones (codigo_corrida, id_comercio, fecha_hora_inicio, estado)
       VALUES (?, ?, ?, 'fallida')
       ON CONFLICT (codigo_corrida, id_comercio) DO NOTHING",
      params = list(runs$codigo_corrida, runs$id_comercio, runs$fecha_hora_inicio))
    emap <- DBI::dbGetQuery(con,
      "SELECT id_ejecucion, codigo_corrida, id_comercio FROM ejecuciones")

    # ---- 4. anuncios: atributos = ultima vez visto; texto_original = primera vez ----
    anu <- base %>%
      dplyr::group_by(comercio, sku) %>%
      dplyr::summarise(
        nombre_original       = dplyr::last(nombres),
        presentacion_original = dplyr::last(presentacion),
        marca_original        = dplyr::last(marca),
        envase                = dplyr::last(envase),
        medida                = dplyr::last(medida),
        cantidad_unidad       = dplyr::last(cantidad_unidad),
        unidades              = dplyr::last(unidades),
        cantidad_total        = dplyr::last(cantidad_total),
        url_producto          = dplyr::last(url),
        texto_original        = dplyr::first(texto_original_anuncio),
        primera_consulta      = dplyr::first(fecha_consulta),
        ultima_consulta       = dplyr::last(fecha_consulta),
        .groups = "drop") %>%
      dplyr::mutate(marca_std        = estandarizar_marca(marca_original),
                    subcategoria_std = estandarizar_subcategoria(nombre_original)) %>%
      dplyr::left_join(cmap, by = "comercio")

    # los vinculos con el catalogo se rehacen siempre (por si cambia un SKU)
    DBI::dbExecute(con, "UPDATE anuncios SET id_producto = NULL WHERE id_producto IS NOT NULL")

    if (nrow(anu) > 0) {
      DBI::dbExecute(con,
        "INSERT INTO anuncios (id_comercio, sku, nombre_original, presentacion_original,
                               marca_original, marca_std, subcategoria_std, envase, medida,
                               cantidad_unidad, unidades, cantidad_total, url_producto,
                               texto_original, primera_consulta, ultima_consulta)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (id_comercio, sku) DO UPDATE SET
           nombre_original = excluded.nombre_original,
           presentacion_original = excluded.presentacion_original,
           marca_original = excluded.marca_original, marca_std = excluded.marca_std,
           subcategoria_std = excluded.subcategoria_std, envase = excluded.envase,
           medida = excluded.medida, cantidad_unidad = excluded.cantidad_unidad,
           unidades = excluded.unidades, cantidad_total = excluded.cantidad_total,
           url_producto = excluded.url_producto,
           primera_consulta = MIN(anuncios.primera_consulta, excluded.primera_consulta),
           ultima_consulta  = MAX(anuncios.ultima_consulta,  excluded.ultima_consulta)",
        params = unname(as.list(anu[, c("id_comercio", "sku", "nombre_original",
          "presentacion_original", "marca_original", "marca_std", "subcategoria_std",
          "envase", "medida", "cantidad_unidad", "unidades", "cantidad_total",
          "url_producto", "texto_original", "primera_consulta", "ultima_consulta")])))
    }

    # vinculo con el catalogo: marca y subcategoria de los comparables vienen de `productos`
    for (i in seq_len(nrow(catalogo_largo))) {
      DBI::dbExecute(con,
        "UPDATE anuncios
            SET id_producto      = :id,
                marca_std        = (SELECT marca_std        FROM productos WHERE id_producto = :id),
                subcategoria_std = (SELECT subcategoria_std FROM productos WHERE id_producto = :id)
          WHERE sku = :sku
            AND id_comercio = (SELECT id_comercio FROM comercios WHERE codigo = :cm)",
        params = list(id = as.integer(catalogo_largo$id_producto[i]),
                      sku = trimws(catalogo_largo$sku[i]),
                      cm  = catalogo_largo$comercio[i]))
    }

    # control: el SKU del catalogo debe tener el mismo contenido que el producto comun
    desajuste <- DBI::dbGetQuery(con,
      "SELECT c.codigo AS comercio, a.sku, a.nombre_original, p.nombre AS producto_catalogo,
              a.cantidad_total AS total_anuncio, p.cantidad_total AS total_catalogo
         FROM anuncios a JOIN productos p ON p.id_producto = a.id_producto
         JOIN comercios c ON c.id_comercio = a.id_comercio
        WHERE a.cantidad_total IS NULL OR a.cantidad_total <> p.cantidad_total")
    if (nrow(desajuste) > 0) {
      cat("!! REVISAR: el contenido del anuncio no coincide con el del producto comun (SKU mal asignado?)\n")
      print(desajuste)
    }

    # ---- 5. observaciones (ON CONFLICT: solo ignora la duplicada, no otros errores) ----
    amap <- DBI::dbGetQuery(con, "SELECT id_anuncio, id_comercio, sku FROM anuncios")
    obs <- base %>%
      dplyr::left_join(cmap, by = "comercio") %>%
      dplyr::left_join(amap, by = c("id_comercio", "sku")) %>%
      dplyr::mutate(codigo_corrida = id_ejecucion, id_ejecucion = NULL) %>%
      dplyr::left_join(emap, by = c("id_comercio", "codigo_corrida")) %>%
      dplyr::distinct(id_anuncio, fecha_consulta, .keep_all = TRUE)

    n_insertadas <- 0L
    if (nrow(obs) > 0) {
      n_insertadas <- DBI::dbExecute(con,
        "INSERT INTO observaciones (id_anuncio, id_comercio, id_ejecucion, fecha_hora_consulta,
                                    precio_cop, precio_lista_cop, es_promocion, url_extraccion,
                                    texto_original_anuncio, busqueda)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (id_anuncio, fecha_hora_consulta) DO NOTHING",
        params = unname(as.list(data.frame(
          obs$id_anuncio, obs$id_comercio, obs$id_ejecucion, obs$fecha_consulta,
          as.integer(obs$precio_real_cop), as.integer(obs$precio_lista_cop),
          as.integer(obs$oferta_general %in% 1L), obs$url_extraccion,
          obs$texto_original_anuncio, obs$busqueda,
          stringsAsFactors = FALSE))))
    }

    # ---- 6. cierre de cada ejecucion: n_registros y estado ----
    for (i in seq_len(nrow(runs))) {
      cm  <- runs$comercio[i];  cod <- runs$codigo_corrida[i]
      id_e <- emap$id_ejecucion[emap$codigo_corrida == cod & emap$id_comercio == runs$id_comercio[i]]
      n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones WHERE id_ejecucion = ?",
                           params = list(id_e))$n
      log_cm <- if (is.null(log)) data.frame(estado = character(), mensaje = character())
                else log[log$comercio == cm & log$id_ejecucion == cod, c("estado", "mensaje")]
      esperados <- trimws(catalogo_largo$sku[catalogo_largo$comercio == cm & catalogo_largo$id_producto %in% ids_conjunto])  # [Taller 2]
      vistos    <- base$sku[base$comercio == cm & base$id_ejecucion == cod]
      st <- calcular_estado(n, log_cm, length(setdiff(esperados, vistos)))
      DBI::dbExecute(con,
        "UPDATE ejecuciones SET n_registros = ?, estado = ?, mensaje = ? WHERE id_ejecucion = ?",
        params = list(as.integer(n), st$estado, st$mensaje, id_e))
    }

    list(n_filas = nrow(base), n_unicas = nrow(obs), n_insertadas = n_insertadas,
         n_descartadas = nrow(descartadas))
  })

  cat(sprintf("SQLite: %d fila(s) recibidas, %d nueva(s) insertadas, %d ya existian, %d descartadas por datos incompletos\n",
              res$n_filas, res$n_insertadas, res$n_unicas - res$n_insertadas, res$n_descartadas))
  print(DBI::dbGetQuery(con,
    "SELECT e.codigo_corrida, c.codigo AS comercio, e.n_registros, e.estado, e.mensaje
       FROM ejecuciones e JOIN comercios c USING (id_comercio)
      ORDER BY e.codigo_corrida DESC, c.codigo LIMIT 9"), row.names = FALSE)
  invisible(res)
}

# ---------------------------------------------------------------------
# Lo nuevo del Taller 2
# ---------------------------------------------------------------------
estado_base <- function(con) {
  list(max_ejecucion = DBI::dbGetQuery(con, "SELECT COALESCE(MAX(id_ejecucion), 0) AS m FROM ejecuciones")$m,
       observaciones = DBI::dbGetQuery(con, "SELECT c.codigo AS comercio, COUNT(*) AS n FROM observaciones o JOIN comercios c ON c.id_comercio = o.id_comercio GROUP BY c.codigo"),
       anuncios      = DBI::dbGetQuery(con, "SELECT c.codigo AS comercio, COUNT(*) AS n FROM anuncios a JOIN comercios c ON c.id_comercio = a.id_comercio GROUP BY c.codigo"))
}

# Resumen por comercio de lo que cambio en la base. `comercios`: los que se intentaron (incluye los que fallaron).
resumen_actualizacion <- function(con, antes, base, comercios = unique(base$comercio)) {
  n_de <- function(df, cm) { v <- df$n[df$comercio == cm]; if (length(v)) v else 0L }
  despues <- estado_base(con)
  nuevas <- DBI::dbGetQuery(con,
    "SELECT c.codigo AS comercio, e.codigo_corrida, e.estado, e.n_registros
       FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
      WHERE e.id_ejecucion > ? ORDER BY c.codigo, e.codigo_corrida", params = list(antes$max_ejecucion))
  cambios <- DBI::dbGetQuery(con,
    "SELECT comercio, COUNT(*) AS n FROM v_cambios_precio WHERE id_ejecucion > ? AND variacion_cop <> 0 GROUP BY comercio",
    params = list(antes$max_ejecucion))
  no_obs <- DBI::dbGetQuery(con,
    "SELECT comercio, COUNT(*) AS n FROM v_no_observados WHERE id_ejecucion > ? GROUP BY comercio",
    params = list(antes$max_ejecucion))
  nombres <- c(exito = "Éxito", farmatodo = "Farmatodo", larebaja = "La Rebaja")
  cms <- comercios
  nombre_de <- function(cm) unname(ifelse(cm %in% names(nombres), nombres[cm], cm))
  data.frame(
    comercio = nombre_de(cms),
    recolectados = vapply(cms, function(cm) sum(base$comercio == cm), numeric(1)),
    nuevas_observaciones = vapply(cms, function(cm) n_de(despues$observaciones, cm) - n_de(antes$observaciones, cm), numeric(1)),
    anuncios_nuevos = vapply(cms, function(cm) n_de(despues$anuncios, cm) - n_de(antes$anuncios, cm), numeric(1)),
    ejecuciones_nuevas = vapply(cms, function(cm) sum(nuevas$comercio == cm), numeric(1)),
    cambios_de_precio = vapply(cms, function(cm) n_de(cambios, nombre_de(cm)), numeric(1)),
    no_observados = vapply(cms, function(cm) n_de(no_obs, nombre_de(cm)), numeric(1)),
    row.names = NULL, check.names = FALSE)
}

# ---- avance por comercio (la app lo lee mientras la tarea corre en segundo plano) ----
crear_progreso <- function(ruta) {
  filas <- data.frame(comercio = character(), estado = character(), detalle = character(), stringsAsFactors = FALSE)
  function(comercio, estado, detalle = "") {
    filas <<- rbind(filas[filas$comercio != comercio, ],
                    data.frame(comercio = comercio, estado = estado, detalle = detalle, stringsAsFactors = FALSE))
    try(utils::write.csv(filas, ruta, row.names = FALSE), silent = TRUE)
    invisible(NULL)
  }
}
leer_progreso <- function(ruta) {
  if (!file.exists(ruta)) return(NULL)
  tryCatch(utils::read.csv(ruta, stringsAsFactors = FALSE), error = function(e) NULL)
}

# ---- navegador (solo scraping en linea) ----
# Agente de usuario identificable (buenas practicas de scraping). Contacto opcional: variable de entorno TALLER_CONTACTO.
agente_usuario <- function() {
  contacto <- Sys.getenv("TALLER_CONTACTO", unset = "")
  paste0("ComparadorPreciosTaller2/1.0 (trabajo academico de Mineria de Datos",
         if (nzchar(contacto)) paste0("; contacto: ", contacto), ")")
}

# [Taller 2] rvest::read_html_live() fija por su cuenta un agente de usuario de Chrome (y pisa cualquier opcion del navegador).
# Esta funcion abre una pagina en blanco, cambia el agente por el nuestro ANTES de pedir la pagina real y recien
# entonces navega: asi la primera peticion ya va identificada. Reemplaza a read_html_live() en las funciones *_scrapear_pagina_live.
abrir_pagina_live <- function(url) {
  sesion <- rvest::read_html_live("about:blank")
  s <- sesion$session
  s$Network$setUserAgentOverride(userAgent = agente_usuario())
  cargada <- s$Page$loadEventFired(wait_ = FALSE)
  s$Page$navigate(url, wait_ = FALSE)
  s$wait_for(cargada)
  sesion
}

iniciar_navegador <- function() {
  if (!requireNamespace("chromote", quietly = TRUE))
    stop("La actualización en línea necesita el paquete chromote y un navegador (Brave, Chrome, Chromium o Edge). ",
         "Usa el modo sin conexión.", call. = FALSE)
  options(chromote.timeout = TIMEOUT_CHROMOTE)
  ruta <- configurar_navegador()          # detiene con mensaje claro si no hay navegador
  try({
    nav <- chromote::default_chromote_object()
    nav$default_timeout <- TIMEOUT_CHROMOTE
  }, silent = TRUE)
  invisible(ruta)
}

# Recolecta UN comercio. NUNCA lanza error: si falla por completo, lo registra en el log y devuelve el motivo.
recolectar_comercio <- function(nm, ts, dir_raw = "raw", terminos = NULL, pausa = PAUSA_PAGINA,
                                respaldar = TRUE, fichas = COMERCIOS) {
  cm <- fichas[[nm]]
  if (is.null(cm)) {
    registrar_log(nm, ts$id_ejecucion, NA_character_, estado = "error_comercio", mensaje = "comercio sin ficha")
    return(list(comercio = nm, base = tibble::tibble(), error = "comercio sin ficha"))
  }
  ruta_respaldo <- file.path(dir_raw, paste0("resultado_seguro_", cm$nombre, ".csv"))
  err <- NULL
  base <- tryCatch(
    ejecutar_busquedas(cm, terminos = terminos, ts = ts, ruta_base = ruta_respaldo,
                       pausa = pausa, respaldar = respaldar),
    error = function(e) {
      err <<- conditionMessage(e)
      registrar_log(nm, ts$id_ejecucion, NA_character_, estado = "error_comercio", mensaje = err)
      tibble::tibble()
    })
  if (is.null(err) && nrow(base) == 0) err <- "no se obtuvo ningún producto (posible bloqueo o cambio en el sitio)"
  list(comercio = nm, base = base, error = err)
}

base_vacia <- function() tipificar_base(stats::setNames(
  as.data.frame(matrix(character(), 0, length(COLUMNAS_FINALES)), stringsAsFactors = FALSE), COLUMNAS_FINALES))

# Punto de entrada de la app.
#   modo = "scrape":  scraping EN LINEA de cada comercio (requiere navegador). Si un comercio falla, sigue con los demas
#                     y deja su ejecucion como parcial/fallida. Cada comercio se guarda en su propia transaccion.
#   modo = "respaldo": modo SIN CONEXION. Reprocesa raw/ (idempotente). No consulta los sitios.
# `con`: conexion abierta; si es NULL, abre `ruta_bd` y la cierra al terminar (para correr en un proceso aparte).
# `progreso`: funcion(comercio, estado, detalle) opcional (ver crear_progreso()).
# Devuelve list(modo, resumen, ejecuciones_nuevas, fallos, mensajes).
ejecutar_recoleccion <- function(con = NULL, modo = c("scrape", "respaldo"), dir_raw = "raw",
                                 comercios = c("exito", "farmatodo", "larebaja"),
                                 ruta_bd = "comparador_precios.sqlite", terminos = NULL,
                                 pausa = PAUSA_PAGINA, progreso = NULL,
                                 fichas = COMERCIOS, usar_navegador = TRUE) {
  modo <- match.arg(modo)
  if (is.null(con)) {
    con <- DBI::dbConnect(RSQLite::SQLite(), ruta_bd)
    DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
    DBI::dbExecute(con, "PRAGMA busy_timeout = 30000")
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }
  avisar <- function(cm, estado, detalle = "") if (is.function(progreso)) progreso(cm, estado, detalle)
  antes <- estado_base(con)
  mensajes <- character(); fallos <- data.frame(comercio = character(), motivo = character(), stringsAsFactors = FALSE)

  if (modo == "respaldo") {
    if (!dir.exists(dir_raw)) stop("No existe la carpeta de respaldos: ", dir_raw, call. = FALSE)
    base <- leer_respaldos(dir_raw, comercios)
    log  <- leer_log_csv(file.path(dir_raw, "log_consultas.csv"))
    mensajes <- utils::capture.output(guardar_en_sqlite(con, base, log))
    intentados <- unique(base$comercio)
  } else {
    if (usar_navegador) iniciar_navegador()
    ts <- marca_tiempo(); reiniciar_log()
    dir.create(dir_raw, recursive = TRUE, showWarnings = FALSE)
    bases <- list(); intentados <- character()
    for (nm in comercios) {
      intentados <- c(intentados, nm)
      avisar(nm, "scrapeando")
      mensajes <- c(mensajes, utils::capture.output(
        r <- recolectar_comercio(nm, ts, dir_raw, terminos, pausa, fichas = fichas)))
      if (!is.null(r$error)) fallos[nrow(fallos) + 1, ] <- list(nm, r$error)
      bases[[nm]] <- r$base
      # guardado de ESTE comercio en su propia transaccion: una falla no afecta a los demas
      avisar(nm, "guardando", paste(nrow(r$base), "productos"))
      b <- if (nrow(r$base) > 0) tipificar_base(r$base) else base_vacia()
      log_cm <- LOG$filtros[LOG$filtros$comercio == nm, ]
      ok <- tryCatch({
        mensajes <- c(mensajes, utils::capture.output(guardar_en_sqlite(con, b, log_cm)))
        TRUE
      }, error = function(e) {
        fallos[nrow(fallos) + 1, ] <<- list(nm, paste("no se pudo guardar:", conditionMessage(e)))
        FALSE
      })
      avisar(nm, if (!is.null(r$error) || !ok) "fallo" else "listo",
             if (!is.null(r$error)) r$error else paste(nrow(r$base), "productos"))
    }
    base <- dplyr::bind_rows(bases)
    tryCatch({                                      # log de consultas, como el scraper original
      ruta_log <- file.path(dir_raw, "log_consultas.csv"); existe <- file.exists(ruta_log)
      utils::write.table(LOG$filtros, ruta_log, sep = ",", row.names = FALSE,
                         col.names = !existe, append = existe, qmethod = "double")
    }, error = function(e) NULL)
  }
  list(modo = modo,
       resumen = resumen_actualizacion(con, antes, base, intentados),
       ejecuciones_nuevas = DBI::dbGetQuery(con,
         "SELECT c.nombre AS comercio, e.codigo_corrida, e.estado, e.n_registros, e.mensaje
            FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
           WHERE e.id_ejecucion > ? ORDER BY e.codigo_corrida, c.id_comercio", params = list(antes$max_ejecucion)),
       fallos = fallos, mensajes = mensajes)
}
