# dia1_pasos.R -- Taller 2, Día 1. Ejecutar LÍNEA POR LÍNEA desde la carpeta taller_2/
# (abre taller_2 como proyecto de RStudio para que el directorio de trabajo sea esa carpeta).
#
# Antes: copia a taller_2/ lo de parcial_01: scraper.R, consultas_sql.R,
#        comparador_precios.sqlite, renv.lock y raw/  (ver nota sobre raw/ en el chat).
#        Los archivos de este paquete (db.R, validacion.R, esquema_taller2.R,
#        limpieza_sqlite.R y tests/) reemplazan/agregan a los de parcial_01.

setwd("C:/Users/Usuario/Downloads/parcial_02")
getwd()
list.files()

# 1) Migrar la base a la estructura del Taller 2 (seguro de repetir: solo agrega)
source("esquema_taller2.R")
migrar_esquema_t2("comparador_precios.sqlite")

# 2) Comprobar que las vistas responden y que no se perdió nada
library(DBI); library(RSQLite)
con <- dbConnect(SQLite(), "comparador_precios.sqlite")
dbGetQuery(con, "SELECT COUNT(*) AS observaciones FROM observaciones")        # debe ser 19562
dbGetQuery(con, "SELECT * FROM v_ultima_ejecucion")
dbGetQuery(con, "SELECT estado, COUNT(*) AS n FROM v_disponibilidad GROUP BY estado")
dbDisconnect(con)

# 3) Correr las pruebas de este día (deben pasar todas)
testthat::test_dir("tests")

# 4) NUEVA EJECUCIÓN del scraper (sitios en línea; tarda varios minutos).
#    Pasa por la validación y agrega a la MISMA base, sin sobrescribir lo anterior.
source("scraper.R")
ejecutar_y_guardar()

# 5) Revisar el resultado: la nueva ejecución, rechazos y comparables completos
con <- dbConnect(SQLite(), "comparador_precios.sqlite")
dbGetQuery(con, "SELECT ejecucion_id, COUNT(*) AS obs FROM observaciones GROUP BY 1")
dbGetQuery(con, "SELECT * FROM ejecuciones ORDER BY fecha_hora_inicio DESC LIMIT 3")   # estado por comercio
dbGetQuery(con, "SELECT motivo_rechazo, COUNT(*) AS n FROM observaciones_rechazadas GROUP BY 1")
dbGetQuery(con, "SELECT ejecucion_id, comercio, COUNT(DISTINCT producto_id) AS productos
                 FROM v_comparables GROUP BY 1, 2 ORDER BY 1 DESC, 2 LIMIT 6")        # 10 por comercio
dbDisconnect(con)
