# dia2_pasos.R -- Taller 2, Día 2. Ejecutar LÍNEA POR LÍNEA desde la carpeta taller_2/
# (con taller_2 abierto como proyecto de RStudio).
#
# Antes: copia a taller_2/ los archivos de este paquete (reemplazan scraper.R, esquema_taller2.R, db.R
#        y tests/helper-datos.R; agregan actualizacion.R, mod_actualizar.R, prueba_boton.R, .gitignore
#        y tests/test_actualizacion_analisis.R). NO reemplaces limpieza_sqlite.R (es el tuyo, con el cambio de P06).
#        Paquetes nuevos que necesitas instalar si no los tienes:
#        install.packages(c("shiny", "bslib", "future", "promises"))   # shiny >= 1.8.1

# 1) Migrar la base otra vez (agrega la columna `motivo` a ejecuciones; seguro de repetir)
source("esquema_taller2.R")
migrar_esquema_t2("comparador_precios.sqlite")

# 2) Correr TODAS las pruebas (las del Día 1 + las nuevas). Debe terminar en FAIL 0
testthat::test_dir("tests")

# 3) Verificar el origen de los datos: reprocesa cada ejecución desde raw/ y la compara con la base.
#    Debe dar verificado = TRUE en todas (tarda ~30 s por ejecución). Guarda esta salida para el README.
source("actualizacion.R")
ids <- db_consultar("SELECT DISTINCT ejecucion_id FROM observaciones ORDER BY 1")$ejecucion_id
verificacion <- do.call(rbind, lapply(ids, function(e) verificar_origen(ejecucion = e)))
verificacion

# 4) Probar el botón en la aplicación mínima
shiny::runApp("prueba_boton.R")
#    a) "Modo sin conexión (usar raw/)": debe cargar la base de demostración y mostrar el resumen
#       por comercio, con un aviso amarillo y el enlace "Volver a la base real".
#    b) "Actualizar precios": hace scraping REAL (varios minutos) y agrega una ejecución nueva a la
#       base real. Mientras corre, la página debe seguir respondiendo. Al terminar, el resumen muestra
#       estado, recolectados, nuevos, cambios de precio, no observados y rechazados por comercio.
#       (Si lo haces, queda una ejecución más en la base: es válida, no hay que borrarla.)
