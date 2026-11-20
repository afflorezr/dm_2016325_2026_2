# Instalación de las dependencias del Taller Parcial 1.
# Las versiones exactas usadas para generar la entrega están en renv.lock.
# Uso:
#   Rscript dependencias.R
#   # o, si se usa renv:
#   renv::restore()

paquetes <- c(
  "curl",       # descarga HTTP de la API de catálogo
  "jsonlite",   # lectura de JSON
  "DBI",        # interfaz de base de datos
  "RSQLite",    # motor SQLite
  "dplyr",      # manipulación de datos
  "tidyr",      # pivotar la tabla de correspondencia
  "stringr",    # expresiones regulares y texto
  "purrr",      # iteración funcional
  "tibble",     # tablas
  "readr",      # lectura del mapeo CSV
  "ggplot2",    # gráficos
  "ggrepel",    # etiquetas sin solapamiento
  "scales",     # escalas y colores
  "digest",     # hash SHA-256 de las copias crudas
  "knitr",      # tablas y compilación
  "rmarkdown"   # render del informe HTML
)

faltantes <- setdiff(paquetes, rownames(installed.packages()))
if (length(faltantes) > 0) {
  install.packages(faltantes, repos = "https://cloud.r-project.org")
} else {
  message("Todas las dependencias están instaladas.")
}

for (p in paquetes) {
  message(sprintf("%-10s %s", p, as.character(packageVersion(p))))
}
