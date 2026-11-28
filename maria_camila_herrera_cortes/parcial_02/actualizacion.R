# actualizacion.R -- Taller 2, Módulo 2: actualización de precios desde la aplicación
# Orquesta (no reescribe) el scraper y la carga del Taller 1:
#   scraper.R         -> scrape_vtex(), reprocesar_raw(), pedir_pagina()
#   limpieza_sqlite.R -> limpiar_datos(), cargar_sqlite()  (valida e inserta en una transacción)
#   db.R              -> db_resumen_ejecucion()
# Un comercio a la vez: si uno falla (red, bloqueo, cambio de estructura) los demás continúan,
# la ejecución de ese comercio queda `fallida` o `parcial` con su motivo, y lo que se alcanzó a
# guardar de él se deshace (cargar_sqlite usa una transacción por llamada).

if (!exists("scrape_vtex",   mode = "function")) source("scraper.R",         encoding = "UTF-8")
if (!exists("cargar_sqlite", mode = "function")) source("limpieza_sqlite.R", encoding = "UTF-8")
if (!exists("db_consultar",  mode = "function")) source("db.R",              encoding = "UTF-8")
suppressPackageStartupMessages({ library(httr2); library(jsonlite) })

COMERCIOS <- c("exito", "jumbo", "olimpica")

escribir_progreso <- function(archivo, texto) {
  if (!is.null(archivo)) cat(format(Sys.time(), "%H:%M:%S"), texto, "\n", file = archivo, append = TRUE)
  message(texto)
}

motivo_http <- function(status) {
  if (is.na(status)) "sin respuesta del sitio (sin conexión a internet, o el servidor bloqueó la consulta)"
  else if (status %in% c(401, 403)) sprintf("el sitio bloqueó la consulta (HTTP %s)", status)
  else if (status == 429) "el sitio limitó las consultas (HTTP 429): demasiadas peticiones"
  else if (status >= 500) sprintf("error del servidor del comercio (HTTP %s)", status)
  else sprintf("respuesta inesperada del sitio (HTTP %s)", status)
}

# Una sola petición de prueba: evita hacer decenas de intentos inútiles cuando el sitio
# bloquea o no hay red (caso típico de shinyapps.io y otras plataformas de despliegue).
sondear_comercio <- function(comercio) {
  cats <- CATEGORIAS_VTEX[CATEGORIAS_VTEX$comercio == comercio, ]
  pg <- tryCatch(pedir_pagina(SITIOS[[comercio]], cats$ruta_ids[1], 0, 0),
                 error = function(e) list(status = NA_integer_))
  ok <- isTRUE(pg$status %in% c(200, 206))
  list(ok = ok, motivo = if (ok) NA_character_ else motivo_http(pg$status))
}

# Deja constancia de un comercio que no se pudo actualizar (sin tocar observaciones)
registrar_ejecucion_fallida <- function(db, comercio, ejecucion, motivo) {
  con <- dbConnect(SQLite(), db); on.exit(dbDisconnect(con))
  crear_esquema(con)
  dbWithTransaction(con, {
    dbExecute(con, "INSERT OR IGNORE INTO comercios (nombre) VALUES (?)", params = list(comercio))
    id <- dbGetQuery(con, "SELECT comercio_id FROM comercios WHERE nombre = ?", params = list(comercio))$comercio_id
    dbExecute(con, "INSERT OR REPLACE INTO ejecuciones
                      (ejecucion_id, comercio_id, fecha_hora_inicio, n_registros, estado, motivo)
                    VALUES (?,?,?,0,'fallida',?)",
              params = list(ejecucion, id, inicio_iso(ejecucion), motivo))
  })
  invisible(TRUE)
}

poner_motivo <- function(db, comercio, ejecucion, motivo) {
  con <- dbConnect(SQLite(), db); on.exit(dbDisconnect(con))
  dbExecute(con, "UPDATE ejecuciones SET motivo = ? WHERE ejecucion_id = ?
                  AND comercio_id = (SELECT comercio_id FROM comercios WHERE nombre = ?)",
            params = list(motivo, ejecucion, comercio))
}

# Actualiza UN comercio: sondeo -> recolección -> limpieza -> validación e inserción (transacción)
actualizar_comercio <- function(comercio, ejecucion, db, recolector = scrape_vtex,
                                sondeo = sondear_comercio, archivo_progreso = NULL) {
  escribir_progreso(archivo_progreso, sprintf("%s: consultando el sitio...", comercio))
  sd <- sondeo(comercio)
  if (!isTRUE(sd$ok)) {
    registrar_ejecucion_fallida(db, comercio, ejecucion, sd$motivo)
    escribir_progreso(archivo_progreso, sprintf("%s: FALLÓ -- %s", comercio, sd$motivo))
    return(invisible("fallida"))
  }
  res <- tryCatch(recolector(comercio, ejecucion), error = function(e) e)
  if (inherits(res, "error")) {
    registrar_ejecucion_fallida(db, comercio, ejecucion,
                                paste("error al extraer los datos:", conditionMessage(res)))
    escribir_progreso(archivo_progreso, sprintf("%s: FALLÓ -- %s", comercio, conditionMessage(res)))
    return(invisible("fallida"))
  }
  if (is.null(res$datos) || !nrow(res$datos) || all(is.na(res$datos$product_id))) {
    registrar_ejecucion_fallida(db, comercio, ejecucion,
                                "el sitio respondió pero no se obtuvo ningún producto (posible cambio de estructura)")
    escribir_progreso(archivo_progreso, sprintf("%s: FALLÓ -- no se obtuvieron productos", comercio))
    return(invisible("fallida"))
  }
  escribir_progreso(archivo_progreso, sprintf("%s: validando e insertando %d registros...", comercio, nrow(res$datos)))
  # igual que recolectar_todo(): un mismo producto puede salir en dos categorías del mismo comercio
  # (no es un duplicado "rechazable", es el mismo anuncio): se conserva una sola vez
  d0 <- res$datos[!duplicated(res$datos[, c("comercio", "product_id", "sku")]), ]
  rownames(d0) <- NULL
  datos <- limpiar_datos(d0)
  avisos <- character()
  r <- tryCatch(withCallingHandlers(
    cargar_sqlite(datos, res$resumen, db),
    warning = function(w) { avisos <<- c(avisos, conditionMessage(w)); invokeRestart("muffleWarning") }),
    error = function(e) e)
  if (inherits(r, "error")) {          # la transacción de cargar_sqlite ya deshizo lo insertado
    registrar_ejecucion_fallida(db, comercio, ejecucion,
                                paste0("no se pudo guardar (se deshicieron los cambios de este comercio): ", conditionMessage(r)))
    escribir_progreso(archivo_progreso, sprintf("%s: FALLÓ al guardar -- %s", comercio, conditionMessage(r)))
    return(invisible("fallida"))
  }
  omit <- sum(res$resumen$n_omitidos, na.rm = TRUE)
  falta <- sum(res$resumen$total_sitio, na.rm = TRUE) - sum(res$resumen$n_productos, na.rm = TRUE)
  motivos <- c(if (omit > 0) sprintf("%d productos omitidos por páginas que fallaron", omit),
               if (omit == 0 && falta > 0) sprintf("el sitio informó %d productos más de los obtenidos", falta),
               avisos)
  if (length(motivos)) poner_motivo(db, comercio, ejecucion, paste(motivos, collapse = "; "))
  escribir_progreso(archivo_progreso, sprintf("%s: listo", comercio))
  invisible("ok")
}

# ---- Actualización en línea (el botón) --------------------------------------------
# `recolector` y `sondeo` se pueden reemplazar (así se prueba sin tocar los sitios).
actualizar_precios <- function(db = DB_RUTA, comercios = COMERCIOS, recolector = scrape_vtex,
                               sondeo = sondear_comercio, archivo_progreso = NULL) {
  reiniciar_peticiones()
  ejecucion <- nueva_ejecucion()
  for (cm in comercios)
    tryCatch(actualizar_comercio(cm, ejecucion, db, recolector, sondeo, archivo_progreso),
             error = function(e) {            # último recurso: nada debe tumbar la aplicación
               registrar_ejecucion_fallida(db, cm, ejecucion, paste("error inesperado:", conditionMessage(e)))
               escribir_progreso(archivo_progreso, sprintf("%s: FALLÓ -- %s", cm, conditionMessage(e)))
             })
  resumen <- db_resumen_ejecucion(ejecucion, db)
  list(modo = "en_linea", ejecucion_id = ejecucion, db = db, resumen = resumen,
       todos_fallaron = all(resumen$estado == "fallida"),
       version = db_version(db),
       mensaje = if (all(resumen$estado == "fallida"))
         "No se pudo consultar ningún comercio desde este equipo. Puede usar el modo sin conexión, que reprocesa las copias guardadas en raw/."
       else if (any(resumen$estado != "completa"))
         "La actualización terminó con comercios parciales o fallidos; revise el motivo de cada uno."
       else "Actualización completa.")
}

# ---- Modo sin conexión -------------------------------------------------------------
# Reprocesa las copias crudas de raw/ hacia una base TEMPORAL (la base entregada no se toca):
# sirve de demostración cuando un sitio no responde. Pasa por la misma limpieza y validación.
ejecuciones_en_raw <- function(carpeta = "raw") {
  f <- basename(list.files(carpeta, pattern = "\\.json\\.gz$", recursive = TRUE))
  f <- f[grepl("^run_[0-9]{8}_[0-9]{6}_", f)]
  sort(unique(sub("^(run_[0-9]{8}_[0-9]{6}).*", "\\1", f)))
}

# Una ejecución sirve para la demostración si trae todos los comercios y casi todos los productos
# que el sitio informó (una ejecución interrumpida, con unas pocas páginas, se omite).
resumen_es_completo <- function(resumen, n_comercios = 3, umbral = 0.95) {
  length(unique(resumen$comercio)) >= n_comercios &&
    sum(resumen$n_productos, na.rm = TRUE) >= umbral * sum(resumen$total_sitio, na.rm = TRUE)
}

reprocesar_sin_conexion <- function(carpeta = "raw", db_destino = tempfile(fileext = ".sqlite"),
                                    ejecuciones = NULL, archivo_progreso = NULL) {
  ids <- if (is.null(ejecuciones)) ejecuciones_en_raw(carpeta) else ejecuciones
  if (!length(ids)) stop("No hay copias crudas en ", carpeta)
  ok <- character(); omitidas <- character()
  for (e in ids) {
    escribir_progreso(archivo_progreso, sprintf("Reprocesando %s desde raw/...", e))
    r <- tryCatch({
      res <- reprocesar_raw(carpeta, e)
      if (!resumen_es_completo(res$resumen)) {
        escribir_progreso(archivo_progreso, sprintf("  %s omitida: ejecución incompleta en raw/", e)); "omitida"
      } else { cargar_sqlite(limpiar_datos(res$datos), res$resumen, db_destino); "ok" } },
      error = function(err) { escribir_progreso(archivo_progreso, paste("  omitida:", conditionMessage(err))); "omitida" })
    if (r == "ok") ok <- c(ok, e) else omitidas <- c(omitidas, e)
  }
  if (!length(ok)) stop("No se pudo reprocesar ninguna ejecución completa de ", carpeta)
  list(modo = "sin_conexion", db = db_destino, ejecuciones = ok, omitidas = omitidas, ejecucion_id = max(ok),
       resumen = db_resumen_ejecucion(max(ok), db_destino), version = db_version(db_destino),
       mensaje = paste0("Modo sin conexión: datos reprocesados desde las copias crudas de raw/ (base temporal; ",
                        length(ok), " ejecuciones", if (length(omitidas)) paste0(", ", length(omitidas), " incompleta(s) omitida(s)"), ")."))
}

# ---- Verificación del origen de los datos ------------------------------------------
# Reprocesa una ejecución desde raw/ y la compara observación por observación con la base.
verificar_origen <- function(db = DB_RUTA, carpeta = "raw", ejecucion = NULL) {
  res <- reprocesar_raw(carpeta, ejecucion); ejecucion <- res$ejecucion
  tmp <- tempfile(fileext = ".sqlite"); on.exit(unlink(tmp), add = TRUE)
  cargar_sqlite(limpiar_datos(res$datos), res$resumen, tmp)
  con <- dbConnect(SQLite(), db, flags = SQLITE_RO); on.exit(dbDisconnect(con), add = TRUE)
  dbExecute(con, "ATTACH DATABASE ? AS cruda", params = list(tmp))
  q <- function(esq) sprintf("SELECT c.nombre AS comercio, a.product_id_comercio AS pid, a.sku,
        o.precio_cop, o.estado_disponibilidad AS estado
        FROM %1$s.observaciones o JOIN %1$s.anuncios a USING (anuncio_id)
        JOIN %1$s.comercios c USING (comercio_id) WHERE o.ejecucion_id = ?", esq)
  r <- dbGetQuery(con, sprintf(
    "WITH base AS (%s), cruda AS (%s)
     SELECT (SELECT COUNT(*) FROM base) AS n_base, (SELECT COUNT(*) FROM cruda) AS n_raw,
            (SELECT COUNT(*) FROM base b JOIN cruda r USING (comercio, pid, sku)
              WHERE b.precio_cop IS r.precio_cop AND b.estado IS r.estado) AS n_coinciden",
    q("main"), q("cruda")), params = list(ejecucion, ejecucion))
  cbind(ejecucion_id = ejecucion, r, verificado = r$n_base == r$n_raw && r$n_raw == r$n_coinciden)
}