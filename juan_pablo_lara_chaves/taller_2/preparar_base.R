# preparar_base.R | crea la base, migra el Taller 1, carga las ejecuciones nuevas y llena correcciones
source("scraper.R"); source("procesamiento.R"); source("db.R");source("validacion.R")
library(readr)

FECHAS <- c("2026-11-16", "2026-11-17", "2026-11-18")
RUTA_T1 <- "../taller_1/comparador_precios.sqlite"

# Si ya copiaste la base del Taller 1 a taller_2/ o quedó una vacía, bórrala antes
con <- abrir_db("comparador_precios.sqlite")
crear_esquema(con)

# Dimensiones
dbWriteTable(con, "comercios", tibble(
  comercio = COMERCIOS,
  nombre_comercial = c("Farmatodo", "Locatel", "Ortopédicos Futuro"),
  url_base = unname(DOMINIOS[COMERCIOS]),
  plataforma = c("Angular", "VTEX", "VTEX")), append = TRUE)

# Catálogo de los 8 comparables (cada uno se vende por unidad: contenido 1, unidad "unidad")
productos <- tribble(
  ~producto_id,                         ~marca,     ~tipo,                         ~presentacion,
  "NOVARIX_MEDIA_HOMBRE_15-20",         "No-Varix", "media de compresión",         "hombre, 15-20 mmHg",
  "NOVARIX_PANTIMEDIA_15-20",           "No-Varix", "pantimedia",                  "15-20 mmHg",
  "NOVARIX_MEDIA_MUJER_15-20_DIAMANTE", "No-Varix", "media de compresión",         "mujer, 15-20 mmHg, diseño diamante",
  "NOVARIX_MEDIA_HOMBRE_8-15",          "No-Varix", "media de compresión",         "hombre, 8-15 mmHg",
  "NOVARIX_MEDIA_MUJER_8-15",           "No-Varix", "media de compresión",         "mujer, 8-15 mmHg",
  "NOVARIX_PANTIMEDIA_8-15",            "No-Varix", "pantimedia",                  "8-15 mmHg",
  "NOVARIX_MEDIA_HOMBRE_20-30",         "No-Varix", "media de compresión",         "hombre, 20-30 mmHg",
  "ACTIMOVE_RHIZO_FORTE_IZQ_S",         "Actimove", "soporte de pulgar Rhizo Forte", "izquierda, talla S"
) |> mutate(contenido = 1, unidad = "unidad")
dbWriteTable(con, "productos", productos, append = TRUE)
dbWriteTable(con, "reglas_emparejamiento", REGLAS, overwrite = TRUE)

# Taller 1: se conserva, sin copia cruda => ejecución con_raw = 0 y observaciones descartadas
migrar_taller1(con, RUTA_T1)

# Ejecuciones nuevas (cada fecha se procesa por separado, para que la deduplicación no mezcle días)
ejec_desde_datos <- function(datos)
  datos |> group_by(ejecucion_id, comercio) |>
  summarise(fecha_inicio = min(fecha_hora), fecha_fin = max(fecha_hora), n_registros = n(), .groups = "drop") |>
  mutate(estado = unname(ESTADO_BASE[comercio]), nota = unname(NOTA_BASE[comercio]), con_raw = 1L)

ESTADO_FORZADO <- list("2026-11-16" = c(ortopedicos_futuro = "parcial"))   # añade otros comercios si aplica
NOTA_FORZADA   <- list("2026-11-16" = "Ejecución incompleta: fallas de red en el scraper (499 productos frente a 535 el 17-nov)")

for (f in FECHAS) {
  crudo <- map_dfr(COMERCIOS, reprocesar_raw, fecha = f)
  datos <- preparar_datos(crudo) |> asignar_comparables()

  ej <- ejec_desde_datos(datos)                    # n_registros = recolectados, antes de validar
  for (cm in names(ESTADO_FORZADO[[f]] %||% character())) {
    ej$estado[ej$comercio == cm] <- ESTADO_FORZADO[[f]][[cm]]
    ej$nota[ej$comercio == cm]   <- NOTA_FORZADA[[f]]
  }
  registrar_ejecuciones(con, ej)

  v <- validar_observaciones(datos)
  rc <- verificar_comparables(v$validas, productos$producto_id)
  if (!rc$ok) { warning(f, ": faltan comparables"); print(rc$faltan) }

  # Rechazos, uno por regla, con su motivo
  walk(split(v$rechazadas, v$rechazadas$.regla), \(r)
       registrar_rechazos(con, r, r$ejecucion_id[1], r$.regla[1], r$.motivo[1]))

  cat(f, ": recolectadas", nrow(datos), "| válidas", nrow(v$validas),
      "| rechazadas", nrow(v$rechazadas), "|", insertar_observaciones(con, v$validas), "insertadas\n")
}

# Correcciones respecto al Taller 1
registrar_correccion(con, "productos", "conjunto_comparables", "producto_id",
                     "NOVARIX_ANTIEMBOLICA_RODILLA_18-22_UNISEX; NOVARIX_MEDIA_RODILLA_MUJER_8-15; NOVARIX_MEDIA_HOMBRE_20-30; NOVARIX_MEDIA_HOMBRE_15-20; NOVARIX_MEDIA_MUJER_15-20_DIAMANTE; KAMEX_RODILLERA_MAGNETICA; ACTIMOVE_RODILLA_PATELA_ABIERTA_M; RECOVERY_ANILLO_DINAMICO_SMALL",
                     paste(productos$producto_id, collapse = "; "),
                     "Reselección de los 8 comparables tras revisar cada página: la Kamex de Locatel (MG012) no era el mismo modelo y otras correspondencias eran dudosas")

registrar_correccion(con, "ejecuciones", "ejec_20261009", "con_raw", "1", "0",
                     "La ejecución del 9-oct no tiene copia cruda en raw/; sus observaciones no son verificables")
registrar_correccion(con, "observaciones", "ejec_20261009", "descartada", "0", "1",
                     "Observaciones del 9-oct marcadas como descartadas por no tener copia cruda (no se borran)")

# Verificación
print(resumen_comercios(con))
print(dbGetQuery(con, "SELECT ejecucion_id, COUNT(*) AS obs, COUNT(DISTINCT producto_id || comercio) AS comparables
                       FROM v_comparables GROUP BY ejecucion_id"))
print(dbGetQuery(con, "SELECT ejecucion_id, comercio, estado, con_raw, n_registros FROM ejecuciones"))
cerrar_db(con)
