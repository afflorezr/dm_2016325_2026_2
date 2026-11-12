# dia3b_pasos.R -- Ajustes del Día 3 (rediseño tras tu revisión). Ejecutar LÍNEA POR LÍNEA desde taller_2/
#
# ANTES DE COPIAR: tú cambiaste colores en app.R (color principal) y en graficos.R (COLORES_COMERCIO).
# Anota esos códigos hexadecimales: los archivos nuevos los reemplazan. Después de copiar, pégalos en
# colores.R (un solo lugar para todos los colores) y listo.
#
# Archivos de este paquete: app.R, graficos.R, db.R, colores.R (NUEVO), diccionario_datos.md (NUEVO),
#                           tests/helper-datos.R y tests/test_indicadores_graficos.R.
# NO reemplaces: limpieza_sqlite.R, scraper.R, esquema_taller2.R, actualizacion.R, mod_actualizar.R.

# 1) Pruebas (deben terminar en FAIL 0 | PASS 108)
testthat::test_dir("tests")

# 2) Abrir la aplicación
shiny::runApp()

# Para cambiar colores: edita colores.R y guarda (no hace falta tocar nada más).
#   COLOR_PRINCIPAL       barra superior, botones y controles
#   COLOR_PESTANA_ACTIVA  texto y subrayado de la pestaña seleccionada
#   COLOR_PESTANA_HOVER   pestaña al pasar el cursor
#   COLOR_ENLACE          enlaces ("Ver anuncio")
#   COLORES_COMERCIO      un color por comercio, igual en todos los gráficos
