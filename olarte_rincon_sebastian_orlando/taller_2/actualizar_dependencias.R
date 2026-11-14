# Ejecutar en consola y desde taller_2 antes de hacer deploy. Instala faltantes si hay Internet.
paquetes <- c('shiny','bslib','plotly','DT','DBI','RSQLite',
              'future','promises','testthat','rsconnect','renv',
              'rvest','xml2','httr2','dplyr','purrr','stringr','tibble',
              'readr','jsonlite','stringi')
faltantes <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly=TRUE)]
if (length(faltantes)) {
  message('Paquetes faltantes: ', paste(faltantes,collapse=', '))
  install.packages(faltantes)
}
if (!requireNamespace('renv',quietly=TRUE)) stop('No se pudo instalar renv')
# NO sobrescribir un lock sin revisar: esta llamada recoge dependencias usadas por el proyecto.
renv::snapshot(prompt=FALSE)
cat('Dependencias registradas en renv.lock. Comprueba que incluyan shiny, plotly y testthat.\n')
