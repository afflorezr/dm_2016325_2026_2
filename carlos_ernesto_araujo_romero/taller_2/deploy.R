# Publica la aplicación en Posit Connect Cloud.
#
# 1. Instale rsconnect una sola vez:
#      install.packages("rsconnect")
# 2. Autorice la cuenta en la consola (abre el navegador):
#      rsconnect::connectCloudUser()
#    o, sin navegador, con un client ID y secret de
#    https://login.posit.cloud/identity/credentials:
#      rsconnect::connectCloudClientCredentials(
#        clientId = "<CLIENT_ID>", clientSecret = "<CLIENT_SECRET>",
#        accountName = "carl0sarauj0")
# 3. Desde esta carpeta:
#      source("deploy.R")

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Instale rsconnect con install.packages('rsconnect')")
}

rsconnect::deployApp(
  appDir = ".",
  appName = "comparador-confiteria",
  appTitle = "Comparador de precios de confitería",
  account = "carl0sarauj0",
  appVisibility = "public",
  forceUpdate = TRUE,
  launch.browser = FALSE
)
