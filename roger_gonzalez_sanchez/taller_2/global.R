# global.R
# Se ejecuta una sola vez al arrancar la app (antes de ui.R y server.R).
# Carga paquetes, abre la conexión a la base y define lo que comparten las sesiones.

library(shiny)
library(bslib)
library(DT)
library(promises)
library(future)

source("db.R")
source("validacion.R")
source("analisis.R")
source("presentacion.R")

# La actualización corre en otro proceso de R (ExtendedTask + future)
plan(multisession, workers = 2)

# Una sola conexión para la app; se cierra cuando la app se detiene
con <- abrir_conexion(RUTA_BD)
db_inicializar(con)
onStop(function() cerrar_conexion(con))

# Colores fijos por comercio para toda la app
colores_comercio <- asignar_colores(db_comercios(con))

# En shinyapps.io / Posit Connect esta variable viene definida
EN_SERVIDOR <- Sys.getenv("R_CONFIG_ACTIVE") %in% c("shinyapps", "rsconnect")

# Evita dos actualizaciones al mismo tiempo (compartido entre sesiones)
estado_global <- new.env()
estado_global$actualizando <- FALSE
