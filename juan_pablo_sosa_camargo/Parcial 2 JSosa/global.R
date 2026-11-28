# =============================================================================
# global.R  -  Carga de dependencias, modulos y constantes de la aplicacion
# -----------------------------------------------------------------------------
# Se ejecuta una vez al arrancar la app (Shiny). Aqui NO hay SQL ni logica de
# servidor: solo fuentes y configuracion compartida.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(highcharter)
  library(DT)
  library(future)
  library(promises)
  library(jsonlite)
})

# Rutas relativas a la raiz del proyecto (sin setwd ni rutas absolutas)
source("validacion.R", local = FALSE)
source("scraper.R",     local = FALSE)
source("db.R",          local = FALSE)

# Tareas en segundo plano para el boton de actualizacion (Modulo 2).
# 1 worker: los servidores gratuitos suelen tener un solo nucleo.
plan(multisession, workers = 1)

DB_PATH <- "comparador_precios.sqlite"

# Rango de fechas y precio maximo observados en la base (para los filtros del
# panel lateral: slider de precio y calendario de fechas).
.rango_precio <- local({
  fechas <- rep(Sys.Date(), 2)
  precio <- 300000
  con0 <- abrir_conexion(DB_PATH)
  on.exit(cerrar_conexion(con0), add = TRUE)
  f <- rango_fechas_observadas(con0)
  if (!is.na(f$mn[1])) fechas <- as.Date(c(substr(f$mn[1], 1, 10), substr(f$mx[1], 1, 10)))
  p <- precio_maximo_observado(con0)
  if (!is.na(p)) precio <- ceiling(p / 500) * 500
  list(fechas = fechas, precio = precio)
})
RANGO_FECHAS <- .rango_precio$fechas
PRECIO_MAX <- .rango_precio$precio

# Tablas DT en espanol y compactas en toda la aplicacion
options(DT.options = list(
  pageLength = 10,
  scrollX = TRUE,
  language = list(
    search = "Buscar:",
    lengthMenu = "Mostrar _MENU_",
    info = "Mostrando _START_–_END_ de _TOTAL_",
    infoEmpty = "Sin filas",
    infoFiltered = "(filtrado de _MAX_)",
    zeroRecords = "Sin coincidencias",
    emptyTable = "Sin datos para mostrar",
    paginate = list(`next` = "Siguiente", previous = "Anterior")
  )
))

# Colores fijos por comercio en TODA la aplicacion (Modulo 5)
COLORES_COMERCIO <- c(
  "Farmatodo" = "#E4002B",
  "Jumbo"     = "#0071CE",
  "Éxito"     = "#F5A623"
)

UNIDAD_LABEL <- c(ml = "COP por 100 mL", g = "COP por 100 g",
                  unidad = "COP por unidad")

# Formato de enteros con punto de miles (evita el aviso de format() con
# big.mark y decimal.mark iguales)
fmt_entero <- function(x) {
  if (length(x) == 0 || is.na(x[1])) return("—")
  formatC(as.numeric(x[1]), format = "f", digits = 0,
          big.mark = ".", decimal.mark = ",")
}

# Color de un comercio como escalar sin nombre (jsonlite avisa con named vectors)
color_comercio <- function(cm) {
  v <- unname(COLORES_COMERCIO[cm])
  if (length(v) == 0 || is.na(v[1])) "#888888" else as.character(v[1])
}

# Mensajes en espanol cuando un filtro no devuelve datos (Modulo 5)
MSG_SIN_DATOS <- "No hay productos que cumplan los filtros seleccionados. Pruebe a ampliar el rango de precio o quitar algun filtro."
MSG_ERROR <- "Ocurrio un error al consultar la base de datos. Intente de nuevo."

# Convierte el texto del input de productos extra ("pañales, toallitas") en un
# vector de terminos de busqueda para el scraper.
parsear_terminos <- function(x) {
  t <- unlist(strsplit(x %||% "", "[,;\\n]+"))
  t <- trimws(t)
  unique(t[t != ""])
}
