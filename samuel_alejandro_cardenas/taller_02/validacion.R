normalizar_unidad_t2 <- function(cantidad, unidad) {
  if (length(cantidad) != 1L || length(unidad) != 1L ||
      is.na(cantidad) || is.na(unidad)) {
    return(list(contenido_total = NA_real_, unidad_normalizada = NA_character_))
  }
  valor <- suppressWarnings(as.numeric(cantidad))
  u <- tolower(trimws(as.character(unidad)))
  if (!is.finite(valor) || valor <= 0) {
    return(list(contenido_total = NA_real_, unidad_normalizada = NA_character_))
  }
  if (u %in% c("ml", "mililitro", "mililitros")) {
    return(list(contenido_total = valor, unidad_normalizada = "mL"))
  }
  if (u %in% c("g", "gr", "gramo", "gramos")) {
    return(list(contenido_total = valor, unidad_normalizada = "g"))
  }
  if (u %in% c("mg", "miligramo", "miligramos")) {
    return(list(contenido_total = valor / 1000, unidad_normalizada = "g"))
  }
  if (u %in% c("unidad", "unidades", "und", "unds")) {
    return(list(contenido_total = valor, unidad_normalizada = "unidad"))
  }
  list(contenido_total = NA_real_, unidad_normalizada = NA_character_)
}

mapa_comparables_t2 <- function(ruta = "config/equivalencias_revisar.csv") {
  if (!file.exists(ruta)) stop("No existe el mapa de equivalencias: ", ruta)
  mapa <- read.csv(ruta, stringsAsFactors = FALSE, colClasses = "character")
  requeridas <- c("comercio", "sku", "id_comun")
  if (!all(requeridas %in% names(mapa))) stop("Faltan columnas del mapa")
  mapa <- mapa[, requeridas, drop = FALSE]
  if (nrow(mapa) != 24L || anyNA(mapa) ||
      anyDuplicated(mapa[, c("comercio", "sku")]) ||
      length(unique(mapa$id_comun)) != 8L) {
    stop("El mapa debe contener 24 anuncios y 8 productos comunes sin duplicados")
  }
  if (!all(table(mapa$id_comun) == 3L) ||
      !setequal(unique(mapa$comercio), c("Cafam", "Locatel", "Cruz Verde"))) {
    stop("Cada producto comun debe estar en los tres comercios")
  }
  mapa
}

validar_lote_t2 <- function(datos, comercio, ejecucion, mapa = mapa_comparables_t2()) {
  requeridas <- c("comercio", "sku", "producto_original", "precio", "url",
                  "fecha_consulta", "id_ejecucion", "cantidad", "unidad",
                  "origen_raw", "id_comun", "comparable")
  if (!is.data.frame(datos)) stop("datos debe ser un data.frame")
  if (!all(requeridas %in% names(datos))) {
    stop("Faltan columnas: ", paste(setdiff(requeridas, names(datos)), collapse = ", "))
  }
  datos <- as.data.frame(datos, stringsAsFactors = FALSE)
  if (nrow(datos) == 0L) {
    datos$contenido_total <- numeric(0)
    datos$unidad_normalizada <- character(0)
    datos$disponibilidad <- character(0)
    return(list(validas = datos, rechazadas = datos,
                faltantes_comparables = unique(mapa$id_comun[mapa$comercio == comercio]),
                completos = FALSE))
  }
  llave_mapa <- paste(mapa$comercio, mapa$sku, sep = "\r")
  llave_datos <- paste(datos$comercio, datos$sku, sep = "\r")
  indice <- match(llave_datos, llave_mapa)
  datos$id_comun <- mapa$id_comun[indice]
  datos$comparable <- as.integer(!is.na(indice))
  unidades <- lapply(seq_len(nrow(datos)), function(i) {
    normalizar_unidad_t2(datos$cantidad[[i]], datos$unidad[[i]])
  })
  datos$contenido_total <- vapply(unidades, `[[`, numeric(1), "contenido_total")
  datos$unidad_normalizada <- vapply(unidades, `[[`, character(1), "unidad_normalizada")
  if (!"disponibilidad" %in% names(datos)) datos$disponibilidad <- NA_character_

  cantidad_esperada <- c(
    durex_placer_prolongado_3 = 3, durex_real_feel_3 = 3,
    ky_lubricante_100_g = 100, ky_lubricante_50_g = 50,
    today_long_action_6 = 6, today_real_sensation_6 = 6,
    today_triple_pleasure_6 = 6, today_triple_pleasure_8 = 8
  )
  motivos <- character(nrow(datos))
  agregar <- function(i, causa) {
    motivos[[i]] <<- paste(c(motivos[[i]][nzchar(motivos[[i]])], causa), collapse = "; ")
  }
  llave_ejecucion <- paste(datos$id_ejecucion, datos$comercio, datos$sku, sep = "\r")
  repetidas <- duplicated(llave_ejecucion)

  for (i in seq_len(nrow(datos))) {
    sin_texto <- function(x) length(x) == 0L || is.na(x) || !nzchar(trimws(as.character(x)))
    if (sin_texto(datos$comercio[[i]]) || datos$comercio[[i]] != comercio) agregar(i, "comercio ausente o incorrecto")
    if (sin_texto(datos$sku[[i]])) agregar(i, "SKU ausente")
    if (sin_texto(datos$producto_original[[i]])) agregar(i, "nombre ausente")
    if (sin_texto(datos$id_ejecucion[[i]]) || datos$id_ejecucion[[i]] != ejecucion) agregar(i, "ejecucion incorrecta")
    precio <- suppressWarnings(as.numeric(datos$precio[[i]]))
    if (length(precio) != 1L || !is.finite(precio) || precio <= 0) agregar(i, "precio no numerico o no positivo")
    url <- datos$url[[i]]
    if (sin_texto(url) || !grepl("^https?://", url, ignore.case = TRUE)) agregar(i, "URL ausente o invalida")
    fecha <- datos$fecha_consulta[[i]]
    if (sin_texto(fecha) || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}", fecha)) {
      agregar(i, "fecha y hora ausentes o invalidas")
    }
    raw <- datos$origen_raw[[i]]
    if (sin_texto(raw) || !file.exists(raw)) agregar(i, "no existe la copia cruda raw")
    if (repetidas[[i]]) agregar(i, "duplicado dentro de la ejecucion")
    estado <- datos$disponibilidad[[i]]
    if (!is.na(estado) && !estado %in% c("disponible", "agotado")) agregar(i, "disponibilidad invalida")
    if (datos$comparable[[i]] == 1L) {
      id <- datos$id_comun[[i]]
      unidad_esperada <- if (startsWith(id, "ky_")) "g" else "unidad"
      if (!(id %in% names(cantidad_esperada)) ||
          is.na(datos$contenido_total[[i]]) ||
          !isTRUE(all.equal(datos$contenido_total[[i]], unname(cantidad_esperada[[id]]))) ||
          is.na(datos$unidad_normalizada[[i]]) || datos$unidad_normalizada[[i]] != unidad_esperada) {
        agregar(i, "presentacion comparable no corresponde a la validada")
      }
    }
  }
  datos$motivo_rechazo <- motivos
  validas <- datos[!nzchar(motivos), , drop = FALSE]
  rechazadas <- datos[nzchar(motivos), , drop = FALSE]
  faltantes <- setdiff(unique(mapa$id_comun[mapa$comercio == comercio]),
                      unique(validas$id_comun[validas$comparable == 1L]))
  list(validas = validas, rechazadas = rechazadas,
       faltantes_comparables = faltantes,
       completos = length(faltantes) == 0L)
}

auditar_base_t2 <- function(archivo = "comparador_precios_taller2.sqlite") {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Instala los paquetes DBI y RSQLite")
  }
  if (!file.exists(archivo)) stop("No existe la base de trabajo: ", archivo)
  con <- DBI::dbConnect(RSQLite::SQLite(), archivo,
                        flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  integridad <- DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]][[1]]
  if (integridad != "ok") stop("Fallo la integridad de la base SQLite")
  tabla <- DBI::dbGetQuery(con, "
    SELECT e.id_ejecucion, e.comercio, e.estado,
           COUNT(o.id) AS observaciones,
           SUM(CASE WHEN o.precio IS NOT NULL AND o.precio > 0 THEN 1 ELSE 0 END) AS precios_validos,
           SUM(CASE WHEN o.comparable = 1 THEN 1 ELSE 0 END) AS comparables,
           COUNT(DISTINCT CASE WHEN o.comparable = 1 THEN o.id_comun END) AS presentaciones
    FROM ejecuciones e
    LEFT JOIN observaciones o
      ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
    GROUP BY e.id_ejecucion, e.comercio, e.estado
    ORDER BY e.id_ejecucion, e.comercio
  ")
  faltantes_raw <- DBI::dbGetQuery(con,
    "SELECT id, origen_raw FROM observaciones WHERE origen_raw IS NULL OR TRIM(origen_raw)=''"
  )
  obs_raw <- DBI::dbGetQuery(con, "SELECT id, origen_raw FROM observaciones")
  en_disco <- !is.na(obs_raw$origen_raw) & nzchar(obs_raw$origen_raw) &
    file.exists(obs_raw$origen_raw)
  faltantes_disco <- obs_raw[!en_disco, , drop = FALSE]
  duplicados <- DBI::dbGetQuery(con, "
    SELECT id_ejecucion, comercio, sku, COUNT(*) AS n
    FROM observaciones
    GROUP BY id_ejecucion, comercio, sku HAVING COUNT(*) > 1
  ")
  coberturas <- DBI::dbGetQuery(con, "
    SELECT id_ejecucion, comercio, seccion, estado, esperados, capturados, paginas
    FROM cobertura ORDER BY id_ejecucion, comercio, seccion
  ")
  cat("\n=== AUDITORIA DE LA BASE PARA TALLER 2 ===\n")
  cat("Integridad SQLite:", integridad, "\n")
  cat("\nHistorial por comercio:\n")
  print(tabla, row.names = FALSE)
  cat("\nDuplicados:", nrow(duplicados), "\n")
  cat("Referencias raw sin ruta:", nrow(faltantes_raw), "\n")
  cat("Referencias raw cuyos archivos no existen:", nrow(faltantes_disco), "\n")
  if (nrow(faltantes_disco)) print(faltantes_disco, row.names = FALSE)
  cat("\nCobertura declarada por fuente:\n")
  print(coberturas, row.names = FALSE)
  cat("\nATENCION: ruta_recorrida no demuestra por si sola categoria completa.\n")
  cat("ATENCION: no ejecutar todavia extraer_en_vivo() del Taller 1.\n")
  invisible(list(integridad = integridad, ejecuciones = tabla,
                 duplicados = duplicados, raw_faltantes = faltantes_disco,
                 cobertura = coberturas))
}
