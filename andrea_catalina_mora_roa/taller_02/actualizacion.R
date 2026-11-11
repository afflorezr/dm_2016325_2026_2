for (f in c("scraper.R", "limpieza.R", "validacion.R", "esquema.R")) source(f, local = environment(), encoding = "UTF-8")

RUTA_DB <- "comparador_precios.sqlite"

conectar_escritura <- function(ruta_db) {
  con <- dbConnect(SQLite(), ruta_db)
  dbExecute(con, "PRAGMA busy_timeout = 30000")   # la aplicación puede estar leyendo
  dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

# producto_id (EAN + contenido) de un lote recién recolectado, con las mismas reglas de limpieza.R.
# Se usa para comprobar la canasta de referencia ANTES de insertar.
ids_producto <- function(d) {
  if (is.null(d) || !nrow(d)) return(character())
  x <- asignar_producto(clasificar_categoria(enriquecer(d)))
  unique(x$producto_id[!is.na(x$producto_id)])
}

ejecucion_previa <- function(con, comercio, ejecucion_id) {
  x <- dbGetQuery(con, "SELECT MAX(ejecucion_id) AS e FROM observaciones
                        WHERE comercio = ? AND ejecucion_id < ? AND descartada = 0",
                  params = list(comercio, ejecucion_id))$e
  if (length(x) && !is.na(x)) x else NA_character_
}

# Cambios de precio del mismo anuncio y anuncios no observados, frente a la ejecución anterior
comparar_con_previa <- function(con, comercio, ejecucion_id) {
  prev <- ejecucion_previa(con, comercio, ejecucion_id)
  if (is.na(prev)) return(list(previa = NA_character_, cambios = 0L, no_observados = 0L))
  cambios <- dbGetQuery(con, "
    SELECT COUNT(*) AS n FROM observaciones a JOIN observaciones b ON a.anuncio_id = b.anuncio_id
    WHERE a.comercio = ? AND a.ejecucion_id = ? AND b.ejecucion_id = ?
      AND a.descartada = 0 AND b.descartada = 0 AND a.precio > 0 AND b.precio > 0 AND a.precio <> b.precio",
    params = list(comercio, ejecucion_id, prev))$n
  no_obs <- dbGetQuery(con, "
    SELECT COUNT(*) AS n FROM observaciones b
    WHERE b.comercio = ? AND b.ejecucion_id = ? AND b.descartada = 0
      AND NOT EXISTS (SELECT 1 FROM observaciones a WHERE a.anuncio_id = b.anuncio_id AND a.ejecucion_id = ?)",
    params = list(comercio, prev, ejecucion_id))$n
  list(previa = prev, cambios = as.integer(cambios), no_observados = as.integer(no_obs))
}

log_inicio <- function(con, actualizacion_id, ejecucion_id, comercio, modo) {
  dbExecute(con, "INSERT INTO log_actualizaciones (actualizacion_id, ejecucion_id, comercio, modo, inicio, estado)
                  VALUES (?,?,?,?,?, 'en curso')",
            params = list(actualizacion_id, ejecucion_id, comercio, modo, ahora_iso()))
  dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
}

log_fin <- function(con, log_id, r) {
  dbExecute(con, "UPDATE log_actualizaciones SET fin = ?, estado = ?, recolectados = ?, nuevos = ?,
                  insertadas = ?, rechazadas = ?, cambios_precio = ?, no_observados = ?, motivo = ?
                  WHERE log_id = ?",
            params = list(ahora_iso(), r$estado, r$recolectados, r$nuevos, r$insertadas, r$rechazadas,
                          r$cambios_precio, r$no_observados, r$motivo, log_id))
}

# Inserta lo validado de UN comercio en una sola transacción (todo o nada)
insertar_comercio <- function(con, ctx, comercio, val, res, r6, inicio, existia_ejecucion) {
  datos <- val$validas
  ahora <- ahora_iso()
  dbWithTransaction(con, {
    completo <- isTRUE(res$completo) && r6$resultado == "cumple" && nrow(datos) > 0
    estado <- if (!nrow(datos)) "fallida" else if (completo) "completa" else "parcial"
    notas <- paste(c(if (ctx$modo == "offline") sprintf("reprocesada desde raw/ el %s", ahora),
                     sprintf("validas=%d, rechazadas=%d", nrow(datos), nrow(val$rechazadas)),
                     if (r6$resultado != "cumple") paste("canasta de referencia:", r6$detalle),
                     res$notas), collapse = " | ")
    if (!existia_ejecucion) {
      # Un reproceso de una ejecución que no estaba en la base conserva el modo de captura
      # (las copias de raw/ se obtuvieron en línea; indice.csv guarda la hora y el estado HTTP).
      modo_reg <- "online"
      ini <- if (ctx$modo == "offline" && nrow(datos)) min(datos$fecha_hora) else inicio
      dbExecute(con, "INSERT INTO ejecuciones (ejecucion_id, comercio, inicio, fin, modo, n_registros,
                      n_productos, total_sitio, estado, notas) VALUES (?,?,?,?,?,?,?,?,?,?)",
                params = list(ctx$ejecucion_id, comercio, ini,
                              if (ctx$modo == "offline" && nrow(datos)) max(datos$fecha_hora) else ahora,
                              modo_reg, nrow(res$datos %||% data.frame()),
                              length(unique(res$datos$producto_id)), as.integer(res$total_sitio %||% NA),
                              estado, notas))
    } else if (ctx$modo == "online") {
      # reanudación de una ejecución en línea: se actualiza su estado
      dbExecute(con, "UPDATE ejecuciones SET fin = ?, n_registros = ?, total_sitio = ?, estado = ?, notas = ?
                      WHERE ejecucion_id = ? AND comercio = ?",
                params = list(ahora, nrow(res$datos %||% data.frame()), as.integer(res$total_sitio %||% NA),
                              estado, notas, ctx$ejecucion_id, comercio))
    }
    nuevos <- 0L; insertadas <- 0L
    if (nrow(datos)) {
      a <- unique(datos[, c("comercio", "producto_id", "sku_comercio", "ean", "referencia", "nombre_original",
                            "marca_original", "descripcion_original", "categoria_origen",
                            "categoria_consulta", "url", "texto_original")])
      a <- a[!duplicated(a$sku_comercio), ]
      a$primera_ejecucion <- ctx$ejecucion_id
      nuevos <- dbExecute(con, "INSERT OR IGNORE INTO anuncios
        (comercio, producto_id, sku_comercio, ean, referencia, nombre_original, marca_original,
         descripcion_original, categoria_origen, categoria_consulta, url, texto_original, primera_ejecucion)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", params = unname(as.list(a)))
      ids <- dbGetQuery(con, "SELECT anuncio_id, sku_comercio FROM anuncios WHERE comercio = ?",
                        params = list(comercio))
      o <- merge(datos, ids, by = "sku_comercio")
      o$ejecucion_id <- ctx$ejecucion_id
      o$estado_disponibilidad <- ifelse(is.na(o$disponible), "sin dato",
                                        ifelse(o$disponible == 1L, "disponible", "agotado"))
      insertadas <- dbExecute(con, "INSERT OR IGNORE INTO observaciones
        (ejecucion_id, comercio, anuncio_id, fecha_hora, precio, precio_lista, en_promocion,
         disponible, estado_disponibilidad, moneda, url) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        params = unname(as.list(o[, c("ejecucion_id", "comercio", "anuncio_id", "fecha_hora", "precio",
                                      "precio_lista", "en_promocion", "disponible",
                                      "estado_disponibilidad", "moneda", "url")])))
    }
    rz <- val$rechazadas
    if (nrow(rz)) {
      rz$ejecucion_id <- ctx$ejecucion_id; rz$registrado <- ahora
      dbExecute(con, "INSERT OR IGNORE INTO rechazos (ejecucion_id, comercio, sku_comercio, nombre_original,
                      url, fecha_hora, precio, regla, motivo, registrado) VALUES (?,?,?,?,?,?,?,?,?,?)",
                params = unname(as.list(rz[, c("ejecucion_id", "comercio", "sku_comercio", "nombre_original",
                                               "url", "fecha_hora", "precio", "regla", "motivo", "registrado")])))
    }
    vr <- rbind(val$resumen, r6)
    vr$ejecucion_id <- ctx$ejecucion_id; vr$comercio <- comercio; vr$registrado <- ahora
    dbExecute(con, "INSERT OR REPLACE INTO validaciones (ejecucion_id, comercio, regla, evaluadas, fallas,
                    resultado, detalle, registrado) VALUES (?,?,?,?,?,?,?,?)",
              params = unname(as.list(vr[, c("ejecucion_id", "comercio", "regla", "evaluadas", "fallas",
                                             "resultado", "detalle", "registrado")])))
    list(estado = estado, nuevos = as.integer(nuevos), insertadas = as.integer(insertadas))
  })
}

registrar_fallo <- function(con, ctx, comercio, inicio, motivo) {
  dbWithTransaction(con, {
    dbExecute(con, "INSERT INTO ejecuciones (ejecucion_id, comercio, inicio, fin, modo, n_registros, estado, notas)
                    VALUES (?,?,?,?,?,0,'fallida',?)
                    ON CONFLICT(ejecucion_id, comercio) DO UPDATE SET
                      notas = COALESCE(ejecuciones.notas, '') || ' | ' || excluded.notas",
              params = list(ctx$ejecucion_id, comercio, inicio, ahora_iso(), ctx$modo, motivo))
  })
}

actualizar_precios <- function(ruta_db = RUTA_DB,
                               comercios = COMERCIOS$comercio,
                               modo = c("online", "offline"),
                               ejecucion_raw = NULL,
                               reanudar = NULL,
                               actualizacion_id = format(Sys.time(), "%Y%m%dT%H%M%S", tz = CFG$zona),
                               probar = TRUE) {
  modo <- match.arg(modo)
  if (modo == "offline") {
    disponibles <- ejecuciones_raw(comercios)
    if (!length(disponibles)) stop("No hay copias en raw/ para reprocesar.")
    if (is.null(ejecucion_raw)) ejecucion_raw <- disponibles[1]
    if (!ejecucion_raw %in% disponibles) stop("No existe la ejecución ", ejecucion_raw, " en raw/.")
    ctx <- nuevo_contexto("offline", ejecucion_raw)
  } else if (!is.null(reanudar)) {
    ctx <- nuevo_contexto("online", reanudar, reanudar = TRUE)
  } else {
    ctx <- nuevo_contexto("online")
  }

  con <- conectar_escritura(ruta_db)
  on.exit(dbDisconnect(con), add = TRUE)
  preparar_base(con)
  referencia <- dbGetQuery(con, "SELECT producto_id FROM canasta_referencia ORDER BY orden")$producto_id

  resumen <- list()
  for (nm in comercios) {
    message(sprintf("[%s | %s] %s ...", ctx$ejecucion_id, modo, nm))
    inicio <- ahora_iso()
    log_id <- log_inicio(con, actualizacion_id, ctx$ejecucion_id, nm, modo)
    ctx$contador$n <- 0L
    r <- list(estado = "fallida", recolectados = 0L, nuevos = 0L, insertadas = 0L, rechazadas = 0L,
              cambios_precio = 0L, no_observados = 0L, motivo = "")
    r <- tryCatch({
      if (modo == "online" && probar) {
        pc <- probar_conexion(nm)
        if (!pc$ok) stop(pc$motivo)
      }
      res <- recolectar_comercio(nm, ctx)
      if (is.null(res$datos) || !nrow(res$datos))
        stop(paste(c("no se obtuvieron productos", res$notas), collapse = " | "))
      val <- validar_observaciones(res$datos)
      r6 <- validar_canasta_referencia(ids_producto(val$validas), referencia)
      existia <- nrow(dbGetQuery(con, "SELECT 1 FROM ejecuciones WHERE ejecucion_id = ? AND comercio = ?",
                                 params = list(ctx$ejecucion_id, nm))) > 0
      ins <- insertar_comercio(con, ctx, nm, val, res, r6, inicio, existia)
      cp <- comparar_con_previa(con, nm, ctx$ejecucion_id)
      list(estado = ins$estado,
           recolectados = nrow(res$datos), nuevos = ins$nuevos, insertadas = ins$insertadas,
           rechazadas = nrow(val$rechazadas), cambios_precio = cp$cambios, no_observados = cp$no_observados,
           motivo = paste(c(if (!isTRUE(res$completo)) "categoría incompleta frente al total del sitio",
                            if (r6$resultado != "cumple") paste("canasta de referencia:", r6$detalle),
                            if (modo == "offline" && ins$insertadas == 0) "sin observaciones nuevas (ya estaban en la base)",
                            if (!is.na(cp$previa)) paste("comparado con", cp$previa)),
                          collapse = "; "))
    }, error = function(e) {
      msg <- conditionMessage(e)
      tryCatch(registrar_fallo(con, ctx, nm, inicio, msg), error = function(e2) NULL)
      modifyList(r, list(estado = "fallida", motivo = msg))
    })
    log_fin(con, log_id, r)
    resumen[[nm]] <- data.frame(ejecucion = ctx$ejecucion_id, comercio = nm, modo = modo,
                                estado = r$estado, recolectados = r$recolectados, nuevos = r$nuevos,
                                insertadas = r$insertadas, rechazadas = r$rechazadas,
                                cambios_precio = r$cambios_precio, no_observados = r$no_observados,
                                motivo = r$motivo, stringsAsFactors = FALSE)
    message(sprintf("   -> %s: %s (%d recolectados, %d insertados, %d rechazados)",
                    nm, r$estado, r$recolectados, r$insertadas, r$rechazadas))
  }
  out <- do.call(rbind, c(resumen, make.row.names = FALSE))

  hay <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones WHERE ejecucion_id = ?",
                    params = list(ctx$ejecucion_id))$n
  if (hay > 0 && sum(out$insertadas) > 0) {
    tryCatch({
      d <- ejecutar_limpieza(con, ctx$ejecucion_id, comercios = COMERCIOS$comercio)
      guardar_limpieza(con, d)
      guardar_familias(con, construir_familias(con, ctx$ejecucion_id))
      dbWithTransaction(con, completar_derivados(con))
    }, error = function(e) {
      out$motivo <<- paste(out$motivo, "| limpieza no completada:", conditionMessage(e))
    })
  }
  attr(out, "ejecucion_id") <- ctx$ejecucion_id
  out
}
