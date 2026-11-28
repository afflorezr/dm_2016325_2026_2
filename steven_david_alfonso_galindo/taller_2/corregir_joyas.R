# corregir_joyas.R · Segunda corrección (11/11/2026)
# Al revisar la aplicación se encontraron 24 joyas de Falabella (collares,
# dijes y charms) dentro de la categoría de perfumes. Se agregaron a la regla
# de accesorios de procesamiento.R. Este script se corre UNA vez:
#
#   source("corregir_joyas.R")

source("scraper.R", encoding = "UTF-8")
source("procesamiento.R", encoding = "UTF-8")

con <- conectar_bd()
procesar_y_registrar(con, "Joyas de Falabella (collar, dije, charm) excluidas: no son perfume")
dbGetQuery(con, "SELECT valor_nuevo AS motivo, COUNT(*) AS n FROM correcciones
                  WHERE motivo LIKE 'Joyas%' AND campo = 'motivo_exclusion' GROUP BY 1")
dbDisconnect(con)
