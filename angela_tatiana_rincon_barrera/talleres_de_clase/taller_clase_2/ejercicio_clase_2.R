# Taller de Web Scraping con R - Parte 1
# Ejercicio: temperaturas diarias de Bogotá 2024-2025 (AccuWeather)

paquetes <- c("rvest", "xml2", "httr", "dplyr", "stringr",
              "purrr", "tibble", "readr")

pendientes <- setdiff(paquetes, rownames(installed.packages()))
if (length(pendientes) > 0) {
  stop("Faltan paquetes: ", paste(pendientes, collapse = ", "))
}
invisible(lapply(paquetes, library, character.only = TRUE))


# Parámetros ------------------------------------------------------------

base_url     <- "https://www.accuweather.com"
location_key <- "107487"
anios        <- c(2024, 2025)
pausa        <- 3
agente       <- "Taller Web Scraping R - Mineria de Datos UNAL"

carpeta_cache        <- "cache_accuweather"
archivo_salida       <- "temperaturas_bogota_2024_2025.csv"
archivo_limitaciones <- "limitaciones_scraping_accuweather.csv"
dir.create(carpeta_cache, showWarnings = FALSE)

# Cambiar a TRUE después de leer los términos de uso del sitio
terminos_revisados <- FALSE


# URL por mes -----------------------------------------------------------

meses_en <- c("january", "february", "march", "april", "may", "june",
              "july", "august", "september", "october", "november",
              "december")

construir_url_mes <- function(anio, mes) {
  paste0(base_url, "/es/co/bogota/", location_key, "/", meses_en[mes],
         "-weather/", location_key, "?year=", anio)
}

urls_meses <- expand.grid(mes = 1:12, anio = anios) %>%
  as_tibble() %>%
  select(anio, mes) %>%
  mutate(url = map2_chr(anio, mes, construir_url_mes))


# robots.txt ------------------------------------------------------------

leer_reglas_robots <- function(texto) {
  lineas <- str_split(texto, "\n")[[1]] %>%
    str_remove("#.*$") %>%
    str_squish()
  lineas <- lineas[lineas != ""]

  reglas <- tibble(tipo = character(), ruta = character())
  aplica <- FALSE
  en_agentes <- FALSE

  for (linea in lineas) {
    campo <- str_to_lower(str_extract(linea, "^[^:]+"))
    valor <- str_squish(str_remove(linea, "^[^:]+:"))

    if (campo == "user-agent") {
      if (!en_agentes) aplica <- FALSE
      en_agentes <- TRUE
      if (valor == "*") aplica <- TRUE
    } else {
      en_agentes <- FALSE
      if (aplica && campo %in% c("allow", "disallow") && valor != "") {
        reglas <- add_row(reglas, tipo = campo, ruta = valor)
      }
    }
  }
  reglas
}

regla_a_regex <- function(ruta) {
  patron <- str_replace_all(ruta, "([.?+^(){}|\\[\\]\\\\])", "\\\\\\1")
  paste0("^", str_replace_all(patron, "\\*", ".*"))
}

ruta_permitida <- function(ruta, reglas) {
  if (nrow(reglas) == 0) return(TRUE)
  coinciden <- reglas %>%
    filter(map_lgl(ruta, ~ str_detect(.env$ruta, regla_a_regex(.x)))) %>%
    mutate(largo = nchar(ruta))
  if (nrow(coinciden) == 0) return(TRUE)
  ganadora <- coinciden %>% arrange(desc(largo), tipo != "allow") %>% slice(1)
  ganadora$tipo == "allow"
}

resp_robots <- GET(paste0(base_url, "/robots.txt"), user_agent(agente))

if (status_code(resp_robots) != 200) {
  tibble(
    recurso        = "robots.txt",
    url            = paste0(base_url, "/robots.txt"),
    estado_http    = status_code(resp_robots),
    fecha_consulta = as.character(Sys.time()),
    descripcion    = paste("El servidor rechazó la solicitud hecha desde R;",
                           "no se pudo verificar robots.txt ni se consultaron",
                           "las páginas mensuales.")
  ) %>%
    write_csv(archivo_limitaciones)
  stop("robots.txt respondió con estado HTTP ", status_code(resp_robots),
       ". Ver ", archivo_limitaciones)
}

reglas_robots <- leer_reglas_robots(content(resp_robots, as = "text",
                                            encoding = "UTF-8"))

urls_meses <- urls_meses %>%
  mutate(ruta = str_remove(url, fixed(base_url)),
         permitida = map_lgl(ruta, ruta_permitida, reglas = reglas_robots))

if (!all(urls_meses$permitida)) stop("robots.txt no permite estas URL.")
if (!terminos_revisados) stop("Falta revisar los términos de uso.")


# Descarga y extracción -------------------------------------------------

descargar_mes <- function(url, anio, mes) {
  archivo <- file.path(carpeta_cache, sprintf("bogota_%d_%02d.html", anio, mes))
  if (file.exists(archivo)) return(read_file(archivo))

  Sys.sleep(pausa)
  message("Consultando: ", url)
  resp <- GET(url, user_agent(agente),
              add_headers(`Accept-Language` = "es-CO,es;q=0.9"))

  if (status_code(resp) != 200) stop("HTTP ", status_code(resp))
  html <- content(resp, as = "text", encoding = "UTF-8")
  write_file(html, archivo)
  html
}

# El calendario incluye días del mes anterior y del siguiente;
# cuando el número de día se reinicia, cambia el mes
mes_relativo <- function(dias) {
  actual <- if (dias[1] == 1) 0L else -1L
  salida <- integer(length(dias))
  salida[1] <- actual
  for (i in seq_along(dias)[-1]) {
    if (dias[i] < dias[i - 1]) actual <- actual + 1L
    salida[i] <- actual
  }
  salida
}

a_numero <- function(x) {
  as.numeric(str_extract(str_replace_all(x, "−", "-"), "-?\\d+(\\.\\d+)?"))
}

extraer_mes <- function(html, url, anio, mes) {
  casillas <- read_html(html) %>%
    html_elements(".monthly-calendar .monthly-daypanel")

  if (length(casillas) == 0) {
    stop("El calendario no aparece en el HTML recibido por R")
  }

  tibble(
    dia  = a_numero(html_text2(html_element(casillas, ".date"))),
    high = a_numero(html_text2(html_element(casillas, ".high"))),
    low  = a_numero(html_text2(html_element(casillas, ".low")))
  ) %>%
    filter(mes_relativo(dia) == 0) %>%
    transmute(fecha = as.Date(sprintf("%d-%02d-%02d", anio, mes, dia)),
              high, low, url_origen = url)
}

procesar_mes <- safely(function(url, anio, mes) {
  extraer_mes(descargar_mes(url, anio, mes), url, anio, mes)
})

respuestas <- pmap(list(urls_meses$url, urls_meses$anio, urls_meses$mes),
                   procesar_mes)

errores <- urls_meses %>%
  select(anio, mes, url) %>%
  mutate(error = map_chr(respuestas, ~ if (is.null(.x$error)) NA_character_
                                       else conditionMessage(.x$error))) %>%
  filter(!is.na(error))

if (nrow(errores) > 0) {
  write_csv(errores, archivo_limitaciones)
  message(nrow(errores), " mes(es) con error. Ver ", archivo_limitaciones)
}

temperaturas <- respuestas %>%
  map("result") %>%
  compact() %>%
  list_rbind() %>%
  arrange(fecha)

if (nrow(temperaturas) == 0) stop("No se extrajo ningún mes.")

# Si los valores vienen en °F se pasan a °C
if (median(temperaturas$high, na.rm = TRUE) > 45) {
  temperaturas <- temperaturas %>%
    mutate(high = round((high - 32) * 5 / 9),
           low  = round((low - 32) * 5 / 9))
}


# Validación ------------------------------------------------------------

fechas_esperadas <- seq(as.Date("2024-01-01"), as.Date("2025-12-31"), by = "day")
fechas_faltantes <- fechas_esperadas[!fechas_esperadas %in% temperaturas$fecha]

temperaturas %>%
  summarise(
    filas          = n(),
    duplicados     = sum(duplicated(fecha)),
    na_high        = sum(is.na(high)),
    na_low         = sum(is.na(low)),
    high_menor_low = sum(high < low, na.rm = TRUE),
    desde          = min(fecha),
    hasta          = max(fecha),
    cobertura_pct  = round(100 * n_distinct(fecha) / length(fechas_esperadas), 1)
  )

fechas_faltantes

temperaturas <- distinct(temperaturas, fecha, .keep_all = TRUE)

head(temperaturas, 10)
write_csv(temperaturas, archivo_salida)
