# Mineria de Datos (2016325) - Taller 2
# Paso 16: probar la conexion scraper -> normalizacion -> validacion.
# Exclusivamente modo offline. No abre, modifica ni reinicia SQLite.
# NO es una nueva extraccion: reproduce los RAW del Taller 1.

previsualizar_actualizacion_t2 <- function(
    raw_root = "raw",
    ejecuciones_fuente = EJECUCIONES_OFFLINE_T1) {

  funciones_necesarias <- c(
    "scrapear_cafam", "scrapear_cruz_verde", "scrapear_la_rebaja",
    "normalizar_resultado_cafam", "normalizar_resultado_cv",
    "normalizar_resultado_lr", "validar_lote",
    "crear_id_offline_determinista"
  )
  faltan <- funciones_necesarias[!vapply(
    funciones_necesarias,
    function(nm) exists(nm, mode = "function", inherits = TRUE),
    logical(1)
  )]
  if (length(faltan)) {
    stop("Carga primero scraper.R y validacion.R. Faltan: ",
         paste(faltan, collapse = ", "))
  }
  if (!dir.exists(raw_root)) stop("No existe la carpeta RAW: ", raw_root)
  claves <- c("cafam", "cruz_verde", "la_rebaja")
  if (!all(claves %in% names(ejecuciones_fuente))) {
    stop("Faltan identificadores originales de: ",
         paste(setdiff(claves, names(ejecuciones_fuente)), collapse = ", "))
  }

  ejecucion_global <- crear_id_offline_determinista(
    ejecuciones_fuente[claves]
  )
  configuracion <- list(
    cafam = list(
      nombre = "Droguerías Cafam", extraer = scrapear_cafam,
      normalizar = normalizar_resultado_cafam
    ),
    cruz_verde = list(
      nombre = "Cruz Verde", extraer = scrapear_cruz_verde,
      normalizar = normalizar_resultado_cv
    ),
    la_rebaja = list(
      nombre = "La Rebaja", extraer = scrapear_la_rebaja,
      normalizar = normalizar_resultado_lr
    )
  )

  resultados <- list()
  filas <- list()
  for (clave in claves) {
    conf <- configuracion[[clave]]
    id_fuente <- unname(ejecuciones_fuente[[clave]])
    cat("\n======================================\n")
    cat("COMERCIO:", conf$nombre, "\n")
    cat("RAW original:", id_fuente, "\n")

    proceso <- tryCatch({
      # 1. Reutiliza el scraper original, sin conectarse a sitios web.
      resultado <- conf$extraer(
        modo = "offline", raw_root = raw_root, ejecucion_id = id_fuente
      )
      # 2. Normaliza usando exactamente el mapeo del Taller 1.
      datos <- conf$normalizar(
        resultado,
        ejecucion_global = ejecucion_global,
        ejecucion_fuente = id_fuente
      )
      # 3. Valida antes de cualquier intento de insercion.
      validacion <- validar_lote(
        datos,
        comercios_esperados = conf$nombre
      )
      list(resultado = resultado, datos = datos, validacion = validacion)
    }, error = function(e) e)

    if (inherits(proceso, "error")) {
      cat("ERROR:", conditionMessage(proceso), "\n")
      filas[[clave]] <- data.frame(
        comercio = conf$nombre,
        obtenidos = NA_integer_, validos = NA_integer_,
        rechazados = NA_integer_, comparables_validos = NA_integer_,
        cumple_ocho = FALSE, estado = "error"
      )
      resultados[[clave]] <- list(error = conditionMessage(proceso))
      next
    }

    v <- proceso$validacion
    n_comparables <- v$cobertura$productos_comparables_validos[1]
    cumple <- isTRUE(v$cobertura$cumple_ocho[1])
    cat("Filas RAW normalizadas:", nrow(proceso$datos), "\n")
    cat("Observaciones validas:", nrow(v$validas), "\n")
    cat("Observaciones rechazadas:", nrow(v$rechazadas), "\n")
    cat("Productos comparables validos:", n_comparables, "/8\n")
    if (nrow(v$rechazadas)) {
      cat("Motivos de rechazo:\n")
      print(as.data.frame(table(v$rechazadas$motivo_rechazo)))
    }
    filas[[clave]] <- data.frame(
      comercio = conf$nombre,
      obtenidos = nrow(proceso$datos),
      validos = nrow(v$validas),
      rechazados = nrow(v$rechazadas),
      comparables_validos = n_comparables,
      cumple_ocho = cumple,
      estado = if (cumple) "reprocesado" else "cobertura_incompleta"
    )
    resultados[[clave]] <- proceso
  }

  resumen <- do.call(rbind, filas)
  rownames(resumen) <- NULL
  cat("\n=== RESUMEN DE PREVISUALIZACION ===\n")
  print(resumen, row.names = FALSE)
  cat("\nNo se ha modificado SQLite ni se ha generado una nueva fecha de captura.\n")
  invisible(list(resumen = resumen, resultados = resultados))
}
