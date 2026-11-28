# dia3_pasos.R -- Taller 2, Día 3. Ejecutar LÍNEA POR LÍNEA desde la carpeta taller_2/
#
# Antes: copia a taller_2/ los archivos de este paquete (reemplazan db.R, esquema_taller2.R,
#        actualizacion.R y tests/helper-datos.R; agregan app.R, graficos.R y
#        tests/test_indicadores_graficos.R). NO reemplaces limpieza_sqlite.R ni scraper.R.

# 1) Paquetes nuevos para la interfaz

#install.packages("highcharter")    # shiny, bslib, future y promises ya los instalaste el Día 2
library(DT)
library(highcharter)

# 2) Migrar la base (cambia la vista v_ultima_ejecucion: ahora prefiere la última ejecución COMPLETA)
source("esquema_taller2.R")
migrar_esquema_t2("comparador_precios.sqlite")

# 3) Pruebas: deben terminar en FAIL 0 | PASS 85
testthat::test_dir("tests")

# 4) La aplicación completa
shiny::runApp()
#
# Qué revisar (yo probé la lógica con tu base, pero no pude VER la pantalla):
#  [Resumen]    7 tarjetas con unidad y periodo; gráfico de distribución (escala log) y de mediana por subcategoría.
#  [Filtros]    comercio, subcategoría, marca, precio, "Una ejecución" / "Rango de fechas", promociones,
#               solo comparables y búsqueda ("esmalte gel"). "Restablecer filtros" debe limpiar todo.
#               Un texto como  a;b  debe mostrar un aviso amable, no un error.
#  [Comparar]   evolución de un producto (una línea por comercio, 3 colores fijos), precio por unidad
#               (solo unidades que existen) y sobrecosto frente al comercio más barato.
#  [Productos]  tabla con orden y búsqueda, enlaces "Ver anuncio" y botón "Descargar CSV".
#  [Cambios]    ejecución anterior/actual, umbral ajustable; filas amarillas = variación grande.
#  [Canasta]    elija P06 junto con otros: Olímpica debe salir "incompleta" (ya no vende P06).
#  [Actualizar] el botón del Día 2 dentro de la app; al terminar, indicadores y gráficos se refrescan solos.
