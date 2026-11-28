# =============================================================================
# run_scraper.R · Punto de entrada. Se ejecuta DESDE RStudio con el .Rproj abierto
#   (la carpeta de trabajo debe ser taller_01/; no se usa setwd()).
# Edita las opciones y ejecuta:  source("run_scraper.R")
# =============================================================================

if (!file.exists("scraper.R") || !file.exists("config.R"))
  stop("Abre taller_01.Rproj (o ejecuta desde la carpeta taller_01/). Directorio actual: ", getwd())

# ---- OPCIONES -----------------------------------------------------------------
MODO       <- "offline"    # "online" = scraping real | "offline" = reprocesa raw/ (verificacion)
VISIBLE    <- FALSE        # TRUE abre el visor de Chrome para ver el avance y diagnosticar
PRUEBA     <- FALSE        # TRUE = corrida corta (2 busquedas, 3 scrolls, 3 fichas). FALSE = completa
COMERCIOS_A_CORRER <- c("exito", "carulla", "pricesmart", "supercomunal")
ID_CORRIDA_OFFLINE <- "20261108-174507"  # p. ej. "20261105-153000" (carpeta en raw/<comercio>/)
# -------------------------------------------------------------------------------

source("config.R")
source("scraper.R")

res <- ejecutar_corrida(comercios = COMERCIOS_A_CORRER, modo = MODO, visible = VISIBLE,
                        prueba = PRUEBA, id_corrida = ID_CORRIDA_OFFLINE)

# Chequeo rapido de lo guardado
con <- db_conectar(if (MODO == "online") CFG$db_path else sub("\\.sqlite$", "_reproc.sqlite", CFG$db_path))
print(DBI::dbGetQuery(con, "SELECT comercio, COUNT(*) AS obs, MIN(precio_cop) AS p_min, MAX(precio_cop) AS p_max,
                            SUM(es_promocion) AS promos, SUM(marca_estandarizada IS NULL) AS sin_marca
                            FROM observaciones GROUP BY comercio"))
DBI::dbDisconnect(con)
