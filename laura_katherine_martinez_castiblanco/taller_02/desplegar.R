# =============================================================================
# desplegar.R · Publicación en shinyapps.io (solo deployApp; NO contiene credenciales)
# ANTES, en la CONSOLA de R (nunca en un archivo del proyecto):
#   rsconnect::setAccountInfo(name = "<cuenta>", token = "<token>", secret = "<secreto>")
# Ejecutar desde taller_2/ :  source("desplegar.R")
# Si una credencial se publicó por error: revóquela en la plataforma (borrarla del archivo no basta).
# =============================================================================
archivos <- c("app.R", "config.R", "scraper.R", "comparables.R", "validacion.R", "db.R", "actualizacion.R", "utils_ui.R",
              "diccionario_datos.md", "comparador_precios.sqlite",
              list.files("modulos", full.names = TRUE), list.files("sql", full.names = TRUE),
              list.files("www", full.names = TRUE), list.files("raw", recursive = TRUE, full.names = TRUE))
rsconnect::deployApp(appDir = ".", appFiles = archivos, appName = "comparador-precios-bebidas", launch.browser = TRUE)
