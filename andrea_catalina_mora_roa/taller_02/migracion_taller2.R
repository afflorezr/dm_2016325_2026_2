# Se ejecutó UNA vez sobre la copia de comparador_precios.sqlite del Taller 1:
#   Rscript migracion_taller2.R
# Es idempotente (correrlo otra vez no duplica nada ni cambia lo ya corregido).
#
#  1. Estructura nueva (esquema.R): tablas correcciones, rechazos, validaciones,
#     log_actualizaciones y canasta_referencia; disponibilidad, contenido total y unidad
#     normalizada; unicidad, índices y vistas.
#  2. Correcciones, registradas en `correcciones` (nada se modifica en silencio):
#     a) observaciones sin precio: no cumplen la regla "precio > 0" del Taller 2; no se borran,
#        se marcan como descartadas;
#     b) subcategoría estandarizada de los productos: en el Taller 1 se tomaba la del PRIMER
#        anuncio, de modo que un nombre incompleto en un comercio (p. ej. "DICLOFEN" en La Rebaja)
#        cambiaba la subcategoría del producto. Ahora se usa el consenso entre comercios.
#  3. Canasta de referencia: 8 productos comparables cuya presencia se exige en cada comercio.
#  4. Validación retroactiva de la ejecución del Taller 1: se reprocesan sus copias de raw/ en
#     modo sin conexión; no se inserta nada nuevo, pero quedan registradas las reglas y rechazos.

source("actualizacion.R", encoding = "UTF-8")   # carga scraper, limpieza, validacion y esquema

con <- conectar_escritura(RUTA_DB)
preparar_base(con)
hoy <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

sin_precio <- dbGetQuery(con, "SELECT obs_id FROM observaciones
                               WHERE (precio IS NULL OR precio <= 0) AND descartada = 0")$obs_id
dbWithTransaction(con, {
  for (id in sin_precio) {
    registrar_correccion(con, "observaciones", "obs_id", id, "descartada", 1L,
      "Precio ausente (el sitio publicaba 0): no cumple la regla precio > 0 del Taller 2. Se conserva la fila y se marca descartada.",
      fecha = hoy)
    dbExecute(con, "UPDATE observaciones SET motivo_descarte = ? WHERE obs_id = ?",
              params = list("precio ausente en el sitio", id))
  }
})

# Se recalcula la limpieza de cada ejecución con limpieza.R corregido y se registran las diferencias
antes <- dbGetQuery(con, "SELECT producto_id, subcategoria_std FROM productos")
for (e in dbGetQuery(con, "SELECT DISTINCT ejecucion_id FROM observaciones ORDER BY 1")$ejecucion_id) {
  d <- ejecutar_limpieza(con, e, comercios = COMERCIOS$comercio)
  # se registran y aplican solo los cambios de subcategoría (el resto de la limpieza no cambió)
  nuevos <- do.call(rbind, lapply(split(d[!is.na(d$producto_id), ], d$producto_id[!is.na(d$producto_id)]),
                                  function(g) data.frame(producto_id = g$producto_id[1],
                                                         subcategoria_std = moda(g$subcategoria_std))))
  cmp <- merge(antes, nuevos, by = "producto_id", suffixes = c("_ant", "_nva"))
  cmp <- cmp[!mapply(identical, cmp$subcategoria_std_ant, cmp$subcategoria_std_nva), ]
  dbWithTransaction(con, {
    for (i in seq_len(nrow(cmp)))
      registrar_correccion(con, "productos", "producto_id", cmp$producto_id[i], "subcategoria_std",
        cmp$subcategoria_std_nva[i],
        sprintf("Subcategoría por consenso entre comercios (antes: la del primer anuncio). Ejecución %s.", e),
        fecha = hoy)
  })
}

ref <- data.frame(
  producto_id = c("EAN7707172688939-10.0un",   # Dolex Avanzado 500 mg x 10 (acetaminofén de marca)
                  "EAN7702057732905-16.0un",   # Acetaminofén MK 500 mg x 16 (genérico)
                  "EAN7702132008611-10.0un",   # Advil Max 400 mg x 10 (ibuprofeno)
                  "EAN7702605101931-10.0un",   # Naproxeno Genfar 250 mg x 10 (genérico)
                  "EAN7702123009528-20.0un",   # Aspirina Ultra 500 mg x 20
                  "EAN7501043130769-120.0ml",  # Dolex Niños jarabe 120 mL (pediátrico líquido)
                  "EAN7501124814090-100.0g",   # Voltaren Emulgel 100 g (tópico)
                  "EAN7703153041847-10.0un"),  # Dolofen Xtra x 10 (combinación)
  orden = 1:8,
  motivo = c("acetaminofén de marca, sólido oral", "acetaminofén genérico, sólido oral",
             "ibuprofeno de marca", "naproxeno genérico", "ácido acetilsalicílico",
             "acetaminofén pediátrico líquido (mL)", "antiinflamatorio tópico (g)",
             "combinación analgésica oral"),
  stringsAsFactors = FALSE)
dbWithTransaction(con, {
  dbExecute(con, "INSERT OR IGNORE INTO canasta_referencia (producto_id, orden, motivo) VALUES (?,?,?)",
            params = unname(as.list(ref)))
})
dbDisconnect(con)

res <- actualizar_precios(modo = "offline", ejecucion_raw = "20261008T123757",
                          actualizacion_id = "migracion-taller2")
print(res)
