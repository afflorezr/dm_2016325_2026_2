# Publica la aplicación en shinyapps.io.
#
# 1. Instale rsconnect una sola vez:
#      install.packages("rsconnect")
# 2. Registre la cuenta en la consola de R (nunca en un archivo del proyecto):
#      rsconnect::setAccountInfo(name = "<CUENTA>",
#                                token = "<TOKEN>",
#                                secret = "<SECRETO>")
#    El token y el secreto se obtienen en shinyapps.io > Account > Tokens.
# 3. Desde esta carpeta:
#      source("deploy.R")

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Instale rsconnect con install.packages('rsconnect')")
}

rsconnect::deployApp(
  appDir = ".",
  appName = "comparador-confiteria",
  appTitle = "Comparador de precios de confitería",
  forceUpdate = TRUE,
  launch.browser = FALSE
)
