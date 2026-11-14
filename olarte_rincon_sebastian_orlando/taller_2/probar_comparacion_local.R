# Paso 41 - prueba con la base real; SOLO LECTURA
stopifnot(file.exists("comparacion_ejecuciones.R"),
          file.exists("comparador_precios.sqlite"))
source("comparacion_ejecuciones.R", encoding = "UTF-8")
local({
  con <- DBI::dbConnect(RSQLite::SQLite(),
                        dbname = "comparador_precios.sqlite",
                        flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  cat("\n=== EJECUCIONES DISPONIBLES ===\n")
  e <- listar_ejecuciones_comparacion_db(con)
  print(e, row.names = FALSE)
  if (nrow(e) < 2L) stop("Se necesitan dos ejecuciones reales")

  # Estan ordenadas de la mas reciente a la mas antigua.
  resultado <- comparar_ejecuciones_db(con,
    anterior_id = e$ejecucion_id[2L],
    actual_id = e$ejecucion_id[1L],
    umbral_pct = 10)

  cat("\n=== ESTADOS ENTRE EJECUCIONES ===\n")
  print(resultado$resumen, row.names = FALSE)
  cat("\nCambios destacados (>= 10 %):", resultado$cambios_grandes, "\n")
  cat("Comercios comparados:", paste(resultado$comercios_comparados, collapse = ", "), "\n")

  cat("\n=== DIEZ PRIMEROS RESULTADOS ===\n")
  print(utils::head(resultado$detalle[, c("comercio", "producto", "precio_anterior_cop",
   "precio_actual_cop", "cambio_cop", "cambio_pct", "estado", "supera_umbral")], 10L), row.names = FALSE)

  stopifnot(nrow(resultado$detalle) > 0,
            sum(resultado$resumen$cantidad) == nrow(resultado$detalle),
            all(resultado$detalle$estado %in% resultado$resumen$estado),
            all(resultado$detalle$supera_umbral %in% c(0L, 1L)),
            all(is.na(resultado$detalle$cambio_cop[resultado$detalle$estado %in%
                  c("Nuevo", "No observado", "Sin precio valido")])))
  cat("\nPRUEBA SUPERADA: comparacion por anuncio/comercio, sin escribir SQLite.\n")
})
