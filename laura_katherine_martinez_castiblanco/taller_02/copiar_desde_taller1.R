# =============================================================================
# copiar_desde_taller1.R · Trae los productos del Taller 1 que el Taller 2 REUTILIZA.
# Ejecutar UNA vez desde taller_2/ (rutas relativas). Supone que taller_01/ está al lado de taller_2/.
# No modifica nada del Taller 1: solo copia.
# =============================================================================
origen <- file.path("..", "taller_01")
if (!dir.exists(origen)) stop("No se encontró ", origen, ". Ajuste 'origen' a la carpeta de su Taller 1.")

archivos <- c("config.R", "scraper.R", "comparables.R", "comparador_precios.sqlite")
for (f in archivos) {
  if (!file.exists(file.path(origen, f))) { warning("Falta ", f, " en el Taller 1"); next }
  file.copy(file.path(origen, f), f, overwrite = TRUE); message("Copiado: ", f)
}
# Copias crudas (verificación del origen de los datos) + manifiesto
if (dir.exists(file.path(origen, "raw"))) {
  file.copy(file.path(origen, "raw"), ".", recursive = TRUE, overwrite = TRUE); message("Copiado: raw/")
}
# Tamaño: ningún archivo puede superar 100 MB (límite de GitHub)
f <- list.files(c(".", "raw"), recursive = TRUE, full.names = TRUE)
gr <- f[file.size(f) > 100 * 1024^2]
if (length(gr)) warning("Archivos > 100 MB: ", paste(gr, collapse = ", ")) else message("Ningún archivo supera 100 MB.")
