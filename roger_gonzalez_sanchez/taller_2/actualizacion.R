# actualizacion.R
# Botón "Actualizar precios" (Módulo 2). Une el scraper del Taller 1 con la base:


PAUSA_ENTRE_COMERCIOS <- 3          
MAX_PAGINAS_POR_CATEGORIA <- 30     
MINUTOS_ENTRE_ACTUALIZACIONES <- 10 

#Punto de conexión con el scraper del Taller 1 

comercios_del_scraper <- function() COMERCIOS_SELECCIONADOS

nombre_comercio <- function(clave) COMERCIOS[[clave]]$nombre

# Recolecta un comercio con el scraper del Taller 1 y aplica su filtro de la
# categoría. Sin conexión, el scraper relee raw/{comercio}/{fecha}/ y conserva
# el id de ejecución y la hora de la captura original.
llamar_scraper <- function(clave, sin_conexion = FALSE, id_ejecucion = NULL) {
  crudo <- FUNCIONES_SCRAPE[[clave]](offline = sin_conexion, id_ejecucion = id_ejecucion,
                                     max_paginas = MAX_PAGINAS_POR_CATEGORIA)
  incluidos <- filtrar_categoria_respiratorios(crudo, verbose = FALSE)
  for (a in c("id_ejecucion", "inicio_captura", "entorno_captura", "resumen_peticiones")) {
    attr(incluidos, a) <- attr(crudo, a)
  }
  attr(incluidos, "n_crudos") <- nrow(crudo)
  incluidos
}



resumen_vacio <- function(comercio) {
  data.frame(comercio = comercio, estado = "FALLIDA", motivo = NA_character_,
             recolectadas = 0L, validas = 0L, rechazadas = 0L, insertadas = 0L,
             nuevos = 0L, cambios_precio = 0L, no_observados = 0L)
}

archivos_raw_de <- function(dir_raw, clave) {
  basename(list.files(file.path(dir_raw, clave), recursive = TRUE))
}

peticiones_fallidas <- function(datos) {
  res <- attr(datos, "resumen_peticiones")
  if (is.null(res) || nrow(res) == 0) return(c(total = 0, fallidas = 0))
  c(total = nrow(res), fallidas = sum(is.na(res$http_status) | res$http_status >= 400))
}

# Recolecta, valida e inserta un comercio. Nunca lanza error: si algo falla,
# deja el comercio como FALLIDA con el motivo y la app sigue con el siguiente.
procesar_comercio <- function(con, id_ejecucion, clave, sin_conexion, recolectar, dir_raw) {
  nombre <- nombre_comercio(clave)
  modo <- if (sin_conexion) "offline" else "online"
  inicio <- ahora()
  r <- resumen_vacio(nombre)

  fallar <- function(motivo) {
    r$motivo <- motivo
    registrar_ejecucion(con, id_ejecucion, nombre, inicio, 0L, "FALLIDA", modo, motivo, entorno_actual())
    r
  }

  datos <- tryCatch(recolectar(clave, sin_conexion, id_ejecucion), error = function(e) e)
  if (inherits(datos, "error")) {
    return(fallar(paste("No se pudo consultar el comercio:", conditionMessage(datos))))
  }
  pet <- peticiones_fallidas(datos)
  if (is.null(datos) || nrow(datos) == 0) {
    return(fallar(sprintf(
      "El scraper no devolvió productos (%d de %d peticiones fallidas; posible bloqueo o cambio de estructura del sitio)",
      pet[["fallidas"]], pet[["total"]])))
  }
  r$recolectadas <- nrow(datos)
  id_datos <- attr(datos, "id_ejecucion") %||% id_ejecucion   # sin conexión: la captura original
  inicio_datos <- attr(datos, "inicio_captura") %||% inicio

  revisado <- tryCatch(
    validar_observaciones(preparar_observaciones(datos), archivos_raw_de(dir_raw, clave)),
    error = function(e) e)
  if (inherits(revisado, "error")) return(fallar(conditionMessage(revisado)))
  validas <- revisado$validas
  r$validas <- nrow(validas)
  r$rechazadas <- nrow(revisado$rechazadas)

  # Comparación con lo que ya había, antes de insertar
  previos <- db_ultimos_precios_comercio(con, nombre)
  vistos_antes <- db_skus_ejecucion_previa(con, nombre, inicio_datos, c(id_ejecucion, id_datos))
  cruce <- merge(validas[, c("sku_comercio", "precio_cop", "fecha_hora_consulta")], previos,
                 by = "sku_comercio", suffixes = c("", "_previo"))
  r$nuevos <- sum(!validas$sku_comercio %in% previos$sku_comercio)
  r$cambios_precio <- sum(cruce$fecha_hora_consulta != cruce$fecha_hora_consulta_previo &
                            cruce$precio_cop != cruce$precio_cop_previo)
  r$no_observados <- sum(!vistos_antes %in% validas$sku_comercio)

  # Estado del comercio
  motivos <- character(0)
  faltan <- if (nrow(validas) > 0) faltan_comparables(validas) else character(0)
  if (length(faltan) > 0) motivos <- c(motivos, paste("Faltan comparables:", paste(faltan, collapse = ", ")))
  if (pet[["fallidas"]] > 0) {
    motivos <- c(motivos, sprintf("%d de %d peticiones fallaron", pet[["fallidas"]], pet[["total"]]))
  }
  if (r$rechazadas > 0) motivos <- c(motivos, paste(r$rechazadas, "observaciones rechazadas"))
  r$estado <- if (nrow(validas) == 0) "FALLIDA"
              else if (length(faltan) > 0 || pet[["fallidas"]] > 0) "PARCIAL"
              else "COMPLETA"
  if (nrow(validas) == 0) motivos <- c("Ninguna observación pasó la validación", motivos)
  r$motivo <- if (length(motivos) > 0) paste(motivos, collapse = ". ") else NA_character_

  detalle <- sprintf("peticiones=%d; fallidas=%d; crudos=%d; incluidos_filtro=%d; validas=%d; rechazadas=%d",
                     as.integer(pet[["total"]]), as.integer(pet[["fallidas"]]),
                     as.integer(attr(datos, "n_crudos") %||% NA), r$recolectadas, r$validas, r$rechazadas)
  if (sin_conexion) detalle <- paste0(detalle, "; reprocesa raw/ de ", id_datos)
  if (!is.na(r$motivo)) detalle <- paste0(detalle, ". ", r$motivo)

  # Todo lo de este comercio entra junto o no entra nada
  guardado <- tryCatch({
    dbWithTransaction(con, {
      if (sin_conexion) {
        # Las observaciones conservan la ejecución de su captura original (la
        # que aparece en raw/.../manifiesto.jsonl). Si esa ejecución no estaba
        # en la base, se registra; si ya estaba, no se modifica.
        if (!ejecucion_existe(con, id_datos, nombre)) {
          registrar_ejecucion(con, id_datos, nombre, inicio_datos, nrow(validas), r$estado,
                              "offline", detalle, attr(datos, "entorno_captura") %||% NA)
        }
      } else {
        registrar_ejecucion(con, id_ejecucion, nombre, inicio, 0L, "EN_CURSO", modo, NA, entorno_actual())
      }
      r$insertadas <- db_insertar_observaciones(con, validas)
      db_insertar_rechazos(con, revisado$rechazadas, id_ejecucion)
      registrar_ejecucion(con, id_ejecucion, nombre, inicio, nrow(validas), r$estado, modo,
                          paste0(detalle, "; insertados=", r$insertadas), entorno_actual())
      db_guardar_conteos(con, id_ejecucion, nombre, r)
    })
    TRUE
  }, error = function(e) e)

  if (!isTRUE(guardado)) {
    r <- resumen_vacio(nombre)
    return(fallar(paste("Error al guardar en la base (no se insertó nada de este comercio):",
                        conditionMessage(guardado))))
  }
  attr(r, "id_datos") <- id_datos
  r
}

# Corre la actualización completa. Abre y cierra su propia conexión porque
# se ejecuta en otro proceso. Devuelve el resumen por comercio.
ejecutar_actualizacion <- function(ruta_bd = RUTA_BD, sin_conexion = FALSE, comercios = NULL,
                                   recolectar = llamar_scraper, pausa = PAUSA_ENTRE_COMERCIOS,
                                   esperar_minutos = MINUTOS_ENTRE_ACTUALIZACIONES,
                                   dir_raw = DIR_RAW, id_ejecucion = NULL) {
  con <- abrir_conexion(ruta_bd)
  on.exit(cerrar_conexion(con))
  crear_esquema(con)   
  if (is.null(comercios)) comercios <- comercios_del_scraper()

  if (!sin_conexion && esperar_minutos > 0) {
    ultima <- db_ultima_en_linea(con)
    if (!is.na(ultima)) {
      minutos <- as.numeric(difftime(Sys.time(),
                                     as.POSIXct(substr(ultima, 1, 19), format = "%Y-%m-%dT%H:%M:%S",
                                                tz = ZONA_HORARIA), units = "mins"))
      if (minutos < esperar_minutos) {
        stop(sprintf("La última actualización en línea fue hace %.0f minutos. Espere al menos %d minutos para no saturar los sitios.",
                     minutos, esperar_minutos))
      }
    }
  }

  # Las corridas sin conexión se registran como reprocesamiento (RP_...)
  id <- id_ejecucion %||% nuevo_id_ejecucion(if (sin_conexion) "RP" else "EJ")
  filas <- list()
  for (i in seq_along(comercios)) {
    if (i > 1 && !sin_conexion) Sys.sleep(pausa)
    filas[[i]] <- procesar_comercio(con, id, comercios[i], sin_conexion, recolectar, dir_raw)
  }
  resumen <- do.call(rbind, filas)

  # Marcar los 8 comparables con el motor del Taller 1 en la ejecución que recibió datos
  notas <- character(0)
  ids_con_datos <- unique(unlist(lapply(filas, function(f) if (f$insertadas > 0) attr(f, "id_datos"))))
  for (id_d in ids_con_datos) {
    withCallingHandlers(
      tryCatch(marcar_productos_comparables(ruta_bd, id_d, verbose = FALSE),
               error = function(e) notas <<- c(notas, paste("No se marcaron comparables:", conditionMessage(e)))),
      warning = function(w) { notas <<- c(notas, conditionMessage(w)); invokeRestart("muffleWarning") })
  }

  # Revisión final: los 8 comparables marcados en cada comercio
  if (!sin_conexion && length(ids_con_datos) > 0) {
    marcados <- db_comparables_marcados(con, id)
    for (i in which(resumen$estado == "COMPLETA")) {
      n <- marcados$n[marcados$comercio == resumen$comercio[i]]
      n <- if (length(n) == 0) 0 else n
      if (n < length(IDS_COMPARABLES)) {
        resumen$estado[i] <- "PARCIAL"
        resumen$motivo[i] <- sprintf("Solo %d de %d comparables quedaron marcados", n, length(IDS_COMPARABLES))
        dbExecute(con, "UPDATE ejecuciones SET estado = 'PARCIAL', detalle = detalle || '. ' || ?
                        WHERE id_ejecucion = ? AND comercio = ?",
                  params = list(resumen$motivo[i], id, resumen$comercio[i]))
      }
    }
  }

  estado <- "PARCIAL"
  if (all(resumen$estado == "COMPLETA")) estado <- "COMPLETA"
  if (all(resumen$estado == "FALLIDA")) estado <- "FALLIDA"
  list(id_ejecucion = id, modo = if (sin_conexion) "offline" else "online", estado = estado,
       comercios = resumen, notas = unique(notas))
}
