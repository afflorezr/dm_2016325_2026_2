# validacion.R · Reglas que debe cumplir una observación antes de entrar a la
# base. Se revisan con pointblank.

library(pointblank)

# Patrón de la fecha y hora de consulta, igual al CHECK de la base.
PATRON_FECHA <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}-05:00$"

# Recibe las filas que devuelve el scraper de un comercio y devuelve, para
# cada fila, la regla que no cumple (NA si las cumple todas).
validar_observaciones <- function(datos) {
  if (nrow(datos) == 0) return(character(0))
  datos$fila <- seq_len(nrow(datos))

  agente <- create_agent(tbl = datos, label = "Observaciones nuevas") |>
    col_vals_gt(columns = precio, value = 0, na_pass = FALSE,
                label = "precio numérico y mayor que cero") |>
    col_vals_not_null(columns = comercio, label = "comercio presente") |>
    col_vals_not_null(columns = url_extraccion, label = "URL presente") |>
    col_vals_regex(columns = fecha_hora_consulta, regex = PATRON_FECHA, na_pass = FALSE,
                   label = "fecha y hora de consulta presente y válida") |>
    col_vals_not_null(columns = id_producto_comercio, label = "identificador presente") |>
    rows_distinct(columns = c(comercio, id_producto_comercio, id_ejecucion),
                  label = "sin duplicados en la ejecución") |>
    interrogate(get_first_n = nrow(datos))   # guarda todas las filas que fallan

  motivo <- rep(NA_character_, nrow(datos))
  if (all_passed(agente)) return(motivo)

  reglas <- agente$validation_set$label
  extractos <- get_data_extracts(agente)
  for (paso in names(extractos)) {
    filas <- extractos[[paso]]$fila
    regla <- reglas[as.integer(paso)]
    if (regla == "sin duplicados en la ejecución") {
      # De un grupo repetido se conserva la primera fila y se rechazan las demás.
      repetida <- duplicated(datos[, c("comercio", "id_producto_comercio", "id_ejecucion")])
      filas <- intersect(filas, which(repetida))
    }
    motivo[filas] <- coalesce(motivo[filas], regla)
  }
  motivo
}

# Guarda en la tabla rechazos las filas que no pasaron la validación.
registrar_rechazos <- function(con, filas, motivos, clave) {
  # Al reprocesar una ejecución no se vuelve a anotar un rechazo que ya estaba.
  dbExecute(con, "
    INSERT INTO rechazos (id_ejecucion, comercio_id, id_producto_comercio,
                          nombre_original, precio, regla, fecha_hora_registro)
    SELECT :ej, :comercio, :id, :nombre, :precio, :regla, :fecha
     WHERE NOT EXISTS (SELECT 1 FROM rechazos
                        WHERE id_ejecucion = :ej AND comercio_id = :comercio
                          AND id_producto_comercio IS :id AND regla = :regla)",
    params = list(ej = filas$id_ejecucion, comercio = rep(id_comercio(clave), nrow(filas)),
                  id = filas$id_producto_comercio, nombre = filas$nombre, precio = filas$precio,
                  regla = motivos, fecha = rep(ahora_iso(), nrow(filas))))
}

# Regla de la ejecución completa: los comparables deben estar en los tres
# comercios. Se revisa después de procesar_base(), porque la correspondencia
# con el catálogo se hace ahí. Devuelve una fila por comercio.
validar_comparables <- function(con, id_ejecucion, minimo = 8) {
  conteo <- dbGetQuery(con, "
    SELECT c.nombre AS comercio, COUNT(DISTINCT a.producto_id) AS comparables
      FROM comercios c
      LEFT JOIN observaciones o
             ON o.comercio_id = c.comercio_id AND o.id_ejecucion = ? AND o.comparable = 1
      LEFT JOIN anuncios a ON a.anuncio_id = o.anuncio_id
     GROUP BY c.nombre", params = list(id_ejecucion))
  conteo$cumple <- conteo$comparables >= minimo
  conteo
}
