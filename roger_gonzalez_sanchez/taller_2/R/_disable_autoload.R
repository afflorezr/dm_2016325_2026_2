# Este archivo le dice a Shiny que NO cargue automáticamente los archivos de R/.
# R/ tiene los módulos del scraper del Taller 1: solo los carga scraper.R, y la
# app solo carga scraper.R cuando se pulsa "Actualizar precios" (en otro proceso).
# Sin este archivo, Shiny cargaría jsonlite y dplyr en la interfaz y, por
# ejemplo, jsonlite::validate taparía a shiny::validate.
