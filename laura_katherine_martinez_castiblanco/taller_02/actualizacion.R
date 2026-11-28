# =============================================================================
# actualizacion.R · Motor de actualización que invoca el botón de la app (y la consola).
# NO reescribe el scraper: llama a ejecutar_corrida() de scraper.R (Taller 1).
# Se ejecuta en un proceso aparte (future) para no bloquear la interfaz.
# =============================================================================
TRIO_COMPARABLE <- c("Éxito", "Carulla", "Supermercado Comunal")   # mismos comercios del Taller 1
MIN_COMPARABLES <- 8

# Carga todo el motor (se usa en el proceso de segundo plano y desde la consola)
cargar_motor <- function() {
  for (f in c("config.R", "scraper.R", "validacion.R", "db.R", "comparables.R")) source(f, encoding = "UTF-8")
  invisible(TRUE)
}

# ¿Este equipo puede hacer scraping en línea? (los servidores de despliegue normalmente no)
estado_scraping <- function() {
  if (!requireNamespace("chromote", quietly = TRUE))
    return(list(ok = FALSE, motivo = "Falta el paquete chromote."))
  ch <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  if (is.null(ch) || !nzchar(ch))
    return(list(ok = FALSE, motivo = "No se encontró Google Chrome/Chromium en este equipo (lo habitual en servidores de despliegue). Use el modo sin conexión."))
  list(ok = TRUE, motivo = NA_character_)
}

# ------------------------------------------------------------------------------
# Comparables con el MISMO trío de comercios en todas las corridas
# (la clave_producto es estable entre corridas; el id PROD_COM_nn se reasigna por corrida)
# ------------------------------------------------------------------------------
asignar_comparables_fijo <- function(db_path = DB_PATH, id_corrida, trio = TRIO_COMPARABLE, min_productos = MIN_COMPARABLES) {
  con <- db_abrir(db_path); on.exit(dbDisconnect(con), add = TRUE)
  obs <- dbGetQuery(con, "SELECT id_obs, comercio, sku_comercio, producto_raw, marca_estandarizada AS marca,
                           subcategoria, contenido_total_ml, unidades FROM v_obs_validas WHERE id_corrida = ?",
                    params = list(id_corrida))
  cand <- obs |>
    dplyr::filter(!is.na(marca), subcategoria != "Sin categorizar", !is.na(contenido_total_ml), !is.na(unidades)) |>
    dplyr::mutate(variante = clave_variante(producto_raw),
                  clave = paste(marca, subcategoria, variante, round(contenido_total_ml), unidades, sep = "|"))
  claves <- sort(Reduce(intersect, lapply(trio, function(cm) cand$clave[cand$comercio == cm])))
  if (length(claves) < min_productos)
    warning("Solo ", length(claves), " productos comunes en ", paste(trio, collapse = ", "), " (mínimo ", min_productos, ").")
  ids <- setNames(sprintf("PROD_COM_%02d", seq_along(claves)), claves)
  rep_obs <- cand |>
    dplyr::filter(clave %in% claves, comercio %in% trio) |>
    dplyr::arrange(clave, comercio, sku_comercio) |>
    dplyr::group_by(clave, comercio) |> dplyr::slice(1) |> dplyr::ungroup() |>
    dplyr::mutate(id_producto_comun = unname(ids[clave]))
  info <- rep_obs |>
    dplyr::group_by(id_producto_comun, clave) |>
    dplyr::summarise(marca = dplyr::first(marca), subcategoria = dplyr::first(subcategoria), variante = dplyr::first(variante),
                     contenido_total_ml = dplyr::first(contenido_total_ml), unidades = dplyr::first(unidades),
                     n_comercios = dplyr::n_distinct(comercio), lista_comercios = paste(sort(comercio), collapse = " | "),
                     .groups = "drop")
  dbBegin(con)
  tryCatch({
    dbExecute(con, "UPDATE observaciones SET comparable = 0, id_producto_comun = NULL
                    WHERE id_ejecucion IN (SELECT id_ejecucion FROM ejecuciones WHERE id_corrida = ?)", params = list(id_corrida))
    if (nrow(rep_obs))
      dbExecute(con, "UPDATE observaciones SET comparable = 1, id_producto_comun = ? WHERE id_obs = ?",
                params = list(rep_obs$id_producto_comun, rep_obs$id_obs))
    dbExecute(con, "DELETE FROM productos_comunes WHERE id_corrida = ?", params = list(id_corrida))
    if (nrow(info))
      dbAppendTable(con, "productos_comunes", data.frame(
        id_corrida = id_corrida, id_producto_comun = info$id_producto_comun, clave_producto = info$clave,
        marca = info$marca, subcategoria = info$subcategoria, variante = info$variante,
        contenido_total_ml = info$contenido_total_ml, unidades = info$unidades,
        n_comercios = info$n_comercios, lista_comercios = info$lista_comercios))
    dbCommit(con)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop(e) })
  invisible(info)
}

# ------------------------------------------------------------------------------
# Validación a nivel de lote (se guarda en la tabla `validaciones`)
# ------------------------------------------------------------------------------
validar_lote <- function(db_path = DB_PATH, id_corrida, trio = TRIO_COMPARABLE, min_productos = MIN_COMPARABLES) {
  con <- db_abrir(db_path); on.exit(dbDisconnect(con), add = TRUE)
  g <- function(sql) dbGetQuery(con, sql, params = list(id_corrida))[1, 1]
  n   <- g("SELECT COUNT(*) FROM v_obs_validas WHERE id_corrida = ?")
  r <- data.frame(regla = c("precio_numerico_mayor_que_cero", "comercio_url_fecha_presentes", "sin_duplicados_en_ejecucion"),
                  n_evaluadas = n, n_fallidas = c(
    g("SELECT COUNT(*) FROM v_obs_validas WHERE id_corrida = ? AND (precio_cop IS NULL OR precio_cop <= 0)"),
    g("SELECT COUNT(*) FROM v_obs_validas WHERE id_corrida = ? AND (comercio IS NULL OR fecha_hora_consulta IS NULL OR (url_producto IS NULL AND url_extraccion IS NULL))"),
    g("SELECT COUNT(*) - COUNT(DISTINCT comercio || '|' || sku_comercio) FROM v_obs_validas WHERE id_corrida = ?")),
    detalle = NA_character_, stringsAsFactors = FALSE)
  comp <- dbGetQuery(con, "SELECT comercio, clave_producto FROM v_comparables WHERE id_corrida = ?", params = list(id_corrida))
  pres <- validar_comparables_presentes(comp, trio, min_productos)
  r <- rbind(r, data.frame(regla = paste0("comparables_presentes:", pres$comercio), n_evaluadas = min_productos,
                           n_fallidas = pmax(0L, min_productos - pres$n_comparables),
                           detalle = paste(pres$n_comparables, "comparables"), stringsAsFactors = FALSE))
  r$resultado <- ifelse(r$n_fallidas == 0, "ok", "falla")
  dbBegin(con)
  tryCatch({
    for (i in seq_len(nrow(r)))
      dbExecute(con, "INSERT INTO validaciones(id_ejecucion, fecha_hora, regla, n_evaluadas, n_fallidas, resultado, detalle)
                      VALUES(?,?,?,?,?,?,?)",
                params = list(id_corrida, ahora_bogota(), r$regla[i], r$n_evaluadas[i], r$n_fallidas[i], r$resultado[i], r$detalle[i]))
    dbCommit(con)
  }, error = function(e) { try(dbRollback(con), silent = TRUE); stop(e) })
  r
}

# ------------------------------------------------------------------------------
# Modo sin conexión: reprocesa raw/ en una base temporal, verifica contra lo guardado
# y registra (sin duplicar) lo que falte.
# ------------------------------------------------------------------------------
reproceso_offline <- function(id_corrida, comercios, db_path = DB_PATH) {
  tmp <- tempfile(fileext = ".sqlite"); on.exit(unlink(tmp), add = TRUE)
  ejecutar_corrida(comercios = comercios, modo = "offline", id_corrida = id_corrida, db_path = tmp)
  ct <- db_abrir(tmp); on.exit(dbDisconnect(ct), add = TRUE)
  ej <- dbGetQuery(ct, "SELECT id_ejecucion, id_corrida, comercio FROM ejecuciones")
  ob <- dbGetQuery(ct, "SELECT * FROM observaciones")
  con <- db_abrir(db_path); on.exit(dbDisconnect(con), add = TRUE)
  for (i in seq_len(nrow(ej))) {
    db_registrar_ejecucion(con, ej$id_ejecucion[i], ej$id_corrida[i], ej$comercio[i], modo = "offline")
    n_ins <- db_insertar_obs(con, ob[ob$id_ejecucion == ej$id_ejecucion[i], , drop = FALSE])
    dbExecute(con, "UPDATE ejecuciones SET fecha_fin = ?, n_registros = ?, estado = 'completa',
                    detalle = 'Reproceso offline de raw/: n_registros = observaciones nuevas insertadas' WHERE id_ejecucion = ?",
              params = list(ahora_bogota(), n_ins, ej$id_ejecucion[i]))
  }
  guardadas <- dbGetQuery(con, "SELECT comercio, sku_comercio, precio_cop FROM v_obs_validas WHERE id_corrida = ?",
                          params = list(id_corrida))
  m <- merge(ob[, c("comercio", "sku_comercio", "precio_cop")], guardadas, by = c("comercio", "sku_comercio"),
             all.x = TRUE, suffixes = c("_raw", "_base"))
  do.call(rbind, lapply(split(m, m$comercio), function(g)
    data.frame(comercio = g$comercio[1], reprocesadas = nrow(g), en_base = sum(!is.na(g$precio_cop_base)),
               precio_coincide = sum(!is.na(g$precio_cop_base) & g$precio_cop_raw == g$precio_cop_base), stringsAsFactors = FALSE)))
}

# ------------------------------------------------------------------------------
# PUNTO DE ENTRADA: lo llama el botón (ExtendedTask) y actualizar_desde_consola.R
# Devuelve siempre una lista (nunca lanza error hacia la interfaz).
# ------------------------------------------------------------------------------
ejecutar_actualizacion <- function(modo = c("online", "offline"), comercios = NULL, prueba = FALSE,
                                   id_corrida_offline = NULL, db_path = DB_PATH) {
  modo <- match.arg(modo)
  if (is.null(comercios) || !length(comercios)) comercios <- names(COMERCIOS)
  es_prueba <- isTRUE(prueba) && modo == "online"
  t0 <- Sys.time()
  salida <- function(ok, mensaje, ...) c(list(ok = ok, modo = modo, prueba = es_prueba, mensaje = mensaje,
                                              segundos = round(as.numeric(difftime(Sys.time(), t0, units = "secs")))), list(...))
  tryCatch({
    if (modo == "online") {
      est <- estado_scraping()
      if (!est$ok) return(salida(FALSE, est$motivo, tipo = "sin_scraping"))
      if (es_prueba) {                                   # copia temporal: la prueba NUNCA entra a la base ni a raw/
        tmp <- tempfile("prueba_"); dir.create(tmp)
        viejo <- CFG[c("dir_raw", "dir_staging")]
        on.exit({ CFG$dir_raw <<- viejo$dir_raw; CFG$dir_staging <<- viejo$dir_staging
        unlink(tmp, recursive = TRUE) }, add = TRUE)
        db_real <- db_path; db_path <- file.path(tmp, "prueba.sqlite")
        file.copy(db_real, db_path)
        CFG$dir_raw <<- file.path(tmp, "raw"); CFG$dir_staging <<- file.path(tmp, "staging")
      }
    }
    db_migrar(db_path)
    if (modo == "online") {
      res <- ejecutar_corrida(comercios = comercios, modo = "online", visible = FALSE, prueba = prueba, db_path = db_path)
      id <- attr(res, "id_corrida")
      adv <- character()
      tryCatch(asignar_comparables_fijo(db_path, id), warning = function(w) adv <<- c(adv, conditionMessage(w)),
               error = function(e) adv <<- c(adv, paste("Comparables:", conditionMessage(e))))
      val <- tryCatch(validar_lote(db_path, id), error = function(e) { adv <<- c(adv, conditionMessage(e)); NULL })
      resumen <- db_resumen_actualizacion(id, db_path)
      if (any(resumen$estado != "completa")) adv <- c(adv, "Uno o más comercios quedaron parciales o fallidos (ver columna 'detalle').")
      if (es_prueba) adv <- c(adv, "CORRIDA DE PRUEBA: se ejecutó sobre una copia temporal y NO se guardó en la base ni en raw/.")
      salida(TRUE, if (es_prueba) sprintf("Prueba terminada (%s). No se guardó nada.", id)
             else sprintf("Actualización terminada (corrida %s).", id),
             id_corrida = id, resumen = resumen, validacion = val, advertencias = adv)
    } else {
      if (is.null(id_corrida_offline) || !nzchar(id_corrida_offline)) return(salida(FALSE, "Elija la corrida de raw/ que desea reprocesar."))
      ver <- reproceso_offline(id_corrida_offline, comercios, db_path)
      salida(TRUE, sprintf("Reproceso sin conexión terminado (corrida %s).", id_corrida_offline),
             id_corrida = id_corrida_offline, verificacion = ver)
    }
  }, error = function(e) salida(FALSE, paste("La actualización falló:", conditionMessage(e)), tipo = "error"))
}
