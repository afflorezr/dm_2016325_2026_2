# =============================================================================
# instalar_dependencias.R · Entorno reproducible (renv). Ejecutar desde taller_2/ en la consola de R.
#   1) PRIMERA VEZ (crear el entorno y fijar versiones):   source("instalar_dependencias.R"); fijar_entorno()
#   2) En OTRO computador (reproducir):                     renv::restore()
# renv.lock debe quedar en la entrega y reflejar los paquetes de abajo.
# =============================================================================
PAQUETES <- c(
  # aplicación
  "shiny", "bslib", "highcharter", "DT", "htmltools", "promises", "future", "markdown", "writexl", "bsicons",
  # datos y validación
  "DBI", "RSQLite", "dplyr", "tidyr", "purrr", "stringr", "stringi", "readr", "tibble", "pointblank",
  # scraping (Taller 1)
  "rvest", "xml2", "jsonlite", "chromote", "digest", "lubridate",
  # pruebas y despliegue
  "testthat", "rsconnect", "renv")

fijar_entorno <- function() {
  if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
  if (!file.exists("renv.lock")) renv::init(bare = TRUE)
  faltan <- setdiff(PAQUETES, rownames(installed.packages()))
  if (length(faltan)) renv::install(faltan)
  renv::snapshot(packages = PAQUETES, prompt = FALSE)   # escribe renv.lock con versiones exactas
  message("renv.lock actualizado. Versión de shiny: ", as.character(packageVersion("shiny")), " (se requiere >= 1.8.1 para ExtendedTask)")
}
