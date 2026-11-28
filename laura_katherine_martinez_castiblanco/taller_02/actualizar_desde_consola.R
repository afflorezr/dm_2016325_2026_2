# =============================================================================
# actualizar_desde_consola.R · Misma actualización que el botón, sin interfaz.
# Úselo para la NUEVA corrida completa (tarda horas): ejecútelo desde la carpeta taller_2/
#   Rscript actualizar_desde_consola.R            # corrida completa en línea
#   Rscript actualizar_desde_consola.R prueba     # corrida corta de ensayo
#   Rscript actualizar_desde_consola.R offline 20261108-174507   # reproceso de raw/
# =============================================================================
if (!file.exists("actualizacion.R")) stop("Ejecute este script desde la carpeta taller_2/ (directorio actual: ", getwd(), ")")
source("actualizacion.R", encoding = "UTF-8"); cargar_motor()

args <- commandArgs(trailingOnly = TRUE)
modo <- if (length(args) && args[1] == "offline") "offline" else "online"
res <- ejecutar_actualizacion(modo = modo, prueba = length(args) && args[1] == "prueba",
                              id_corrida_offline = if (modo == "offline" && length(args) > 1) args[2] else NULL)
cat("\n", res$mensaje, "\n")
if (!is.null(res$resumen)) print(res$resumen)
if (!is.null(res$verificacion)) print(res$verificacion)
if (length(res$advertencias)) cat("Advertencias:\n", paste("-", res$advertencias, collapse = "\n"), "\n")
