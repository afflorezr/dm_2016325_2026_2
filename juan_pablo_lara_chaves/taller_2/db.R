# db.R | acceso a datos (sin SQL en la interfaz)
library(DBI); library(RSQLite); library(dplyr)

abrir_db <- function(ruta = "comparador_precios.sqlite") {
  con <- dbConnect(SQLite(), ruta)
  invisible(dbExecute(con, "PRAGMA foreign_keys = ON"))
  con
}
cerrar_db <- function(con) if (dbIsValid(con)) dbDisconnect(con)

crear_esquema <- function(con) {
  sentencias <- c(
    "CREATE TABLE IF NOT EXISTS comercios (
       comercio TEXT PRIMARY KEY, nombre_comercial TEXT, url_base TEXT, plataforma TEXT)",
    
    "CREATE TABLE IF NOT EXISTS productos (
       producto_id TEXT PRIMARY KEY, marca TEXT, tipo TEXT, presentacion TEXT,
       contenido REAL, unidad TEXT CHECK (unidad IN ('mL','g','unidad') OR unidad IS NULL))",
    
    "CREATE TABLE IF NOT EXISTS ejecuciones (
       ejecucion_id TEXT NOT NULL, comercio TEXT NOT NULL,
       fecha_inicio TEXT NOT NULL, fecha_fin TEXT, n_registros INTEGER,
       estado TEXT CHECK (estado IN ('completa','parcial','fallida')), nota TEXT,
       con_raw INTEGER NOT NULL DEFAULT 1,
       PRIMARY KEY (ejecucion_id, comercio))",
    
    "CREATE TABLE IF NOT EXISTS observaciones (
       obs_id INTEGER PRIMARY KEY AUTOINCREMENT,
       ejecucion_id TEXT NOT NULL,
       comercio TEXT NOT NULL REFERENCES comercios(comercio),
       categoria_sitio TEXT, subcategoria_std TEXT,
       nombre TEXT NOT NULL, nombre_norm TEXT, marca_std TEXT,
       sku TEXT, id_anuncio TEXT, n_unidades INTEGER,
       producto_comercio TEXT NOT NULL,
       precio REAL CHECK (precio IS NULL OR precio > 0),
       precio_lista REAL, descuento TEXT, en_promocion INTEGER,
       disponibilidad TEXT CHECK (disponibilidad IN ('disponible','agotado') OR disponibilidad IS NULL),
       url TEXT, url_origen TEXT,
       fecha_hora TEXT NOT NULL,
       producto_id TEXT REFERENCES productos(producto_id),
       comparable INTEGER NOT NULL DEFAULT 0,
       descartada INTEGER NOT NULL DEFAULT 0,
       FOREIGN KEY (ejecucion_id, comercio) REFERENCES ejecuciones(ejecucion_id, comercio),
       UNIQUE (comercio, producto_comercio, fecha_hora))",
    
    "CREATE TABLE IF NOT EXISTS correcciones (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       fecha TEXT DEFAULT (datetime('now','-5 hours')),
       tabla TEXT, registro_id TEXT, campo TEXT,
       valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT)",
    
    "CREATE TABLE IF NOT EXISTS rechazos (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       fecha TEXT DEFAULT (datetime('now','-5 hours')),
       ejecucion_id TEXT, comercio TEXT, fila_json TEXT, regla TEXT, motivo TEXT)",
    
    "CREATE INDEX IF NOT EXISTS ix_obs_comercio  ON observaciones (comercio)",
    "CREATE INDEX IF NOT EXISTS ix_obs_ejecucion ON observaciones (ejecucion_id)",
    "CREATE INDEX IF NOT EXISTS ix_obs_anuncio   ON observaciones (comercio, producto_comercio, fecha_hora)",
    "CREATE INDEX IF NOT EXISTS ix_obs_producto  ON observaciones (producto_id)",
    "CREATE INDEX IF NOT EXISTS ix_obs_marca     ON observaciones (marca_std)",
    
    "DROP VIEW IF EXISTS v_ultimo_precio",
    "CREATE VIEW v_ultimo_precio AS
       SELECT o.* FROM observaciones o
       WHERE o.descartada = 0
         AND o.fecha_hora = (SELECT MAX(x.fecha_hora) FROM observaciones x
                             WHERE x.comercio = o.comercio
                               AND x.producto_comercio = o.producto_comercio
                               AND x.descartada = 0)",
    
    "DROP VIEW IF EXISTS v_cambios_precio",
    "CREATE VIEW v_cambios_precio AS
       SELECT *, precio - precio_anterior AS delta,
              ROUND(100.0 * (precio - precio_anterior) / precio_anterior, 2) AS delta_pct
       FROM (SELECT comercio, producto_comercio, nombre, ejecucion_id, fecha_hora, precio,
                    LAG(precio)       OVER w AS precio_anterior,
                    LAG(ejecucion_id) OVER w AS ejecucion_anterior
             FROM observaciones WHERE descartada = 0 AND precio IS NOT NULL
             WINDOW w AS (PARTITION BY comercio, producto_comercio ORDER BY fecha_hora))
       WHERE precio_anterior IS NOT NULL",
    
    "DROP VIEW IF EXISTS v_comparables",
    "CREATE VIEW v_comparables AS
       SELECT o.*, p.marca AS marca_producto, p.tipo, p.presentacion, p.contenido, p.unidad,
              CASE WHEN p.contenido > 0 THEN o.precio * 1.0 / p.contenido END AS precio_unitario
       FROM observaciones o JOIN productos p ON p.producto_id = o.producto_id
       WHERE o.comparable = 1 AND o.descartada = 0",
    
    "DROP VIEW IF EXISTS v_referencia",
    "CREATE VIEW v_referencia AS
       SELECT ejecucion_id, producto_id, comercio,
              MAX(precio)     AS precio,
              MIN(precio)     AS precio_min,
              COUNT(*)        AS n_anuncios,
              MAX(fecha_hora) AS fecha_hora
       FROM v_comparables
       WHERE precio > 0
       GROUP BY ejecucion_id, producto_id, comercio"
  )
  for (s in sentencias) invisible(dbExecute(con, s))
  invisible(TRUE)
}

# --- Escritura -----------------------------------------------------------------
COLS_OBS <- c("ejecucion_id", "comercio", "categoria_sitio", "subcategoria_std", "nombre", "nombre_norm",
              "marca_std", "sku", "id_anuncio", "n_unidades", "producto_comercio", "precio", "precio_lista",
              "descuento", "en_promocion", "disponibilidad", "url", "url_origen", "fecha_hora",
              "producto_id", "comparable", "descartada")

# `datos` YA validados. Una transacción; las observaciones repetidas se ignoran (UNIQUE).
insertar_observaciones <- function(con, datos) {
  d <- datos
  if ("categoria" %in% names(d) && !"categoria_sitio" %in% names(d))
    d <- dplyr::rename(d, categoria_sitio = categoria)
  for (col in setdiff(COLS_OBS, names(d)))
    d[[col]] <- if (col %in% c("comparable", "descartada")) 0L else NA
  d <- d[, COLS_OBS]
  cols <- paste(COLS_OBS, collapse = ", ")
  dbWithTransaction(con, {
    dbWriteTable(con, "tmp_obs", d, temporary = TRUE, overwrite = TRUE)
    n <- dbExecute(con, sprintf("INSERT OR IGNORE INTO observaciones (%s) SELECT %s FROM tmp_obs", cols, cols))
    dbExecute(con, "DROP TABLE tmp_obs")
    n
  })
}

registrar_ejecuciones <- function(con, ej) {
  dbWithTransaction(con, {
    dbWriteTable(con, "tmp_ej", ej, temporary = TRUE, overwrite = TRUE)
    dbExecute(con, "INSERT OR REPLACE INTO ejecuciones
                    (ejecucion_id, comercio, fecha_inicio, fecha_fin, n_registros, estado, nota, con_raw)
                    SELECT ejecucion_id, comercio, fecha_inicio, fecha_fin, n_registros, estado, nota, con_raw FROM tmp_ej")
    dbExecute(con, "DROP TABLE tmp_ej")
  })
}

registrar_rechazos <- function(con, rechazadas, ejecucion_id, regla, motivo) {
  if (nrow(rechazadas) == 0) return(invisible(0L))
  filas <- data.frame(
    ejecucion_id = ejecucion_id, comercio = rechazadas$comercio,
    fila_json = vapply(seq_len(nrow(rechazadas)),
                       \(i) as.character(jsonlite::toJSON(as.list(rechazadas[i, ]), auto_unbox = TRUE)), ""),
    regla = regla, motivo = motivo)
  dbAppendTable(con, "rechazos", filas)
}

registrar_correccion <- function(con, tabla, registro_id, campo, anterior, nuevo, motivo) {
  dbExecute(con,
            "INSERT INTO correcciones (tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo)
     VALUES (?,?,?,?,?,?)",
            params = list(tabla, as.character(registro_id), campo, as.character(anterior),
                          as.character(nuevo), motivo))
}

# Copia la base del Taller 1 SIN modificarla: ejecuciones sin copia cruda y observaciones descartadas
migrar_taller1 <- function(con, ruta) {
  # La guarda mira las observaciones: la ejecución ya quedó registrada en el intento fallido
  if (dbGetQuery(con, "SELECT COUNT(*) n FROM observaciones WHERE descartada = 1")$n > 0)
    return(invisible(FALSE))
  c1 <- dbConnect(SQLite(), ruta); on.exit(dbDisconnect(c1))
  ej <- dbReadTable(c1, "ejecuciones") |> mutate(con_raw = 0L)
  ob <- dbReadTable(c1, "observaciones") |> select(-any_of("obs_id")) |>
    mutate(producto_id = NA_character_, comparable = 0L, descartada = 1L)
  registrar_ejecuciones(con, ej)
  insertar_observaciones(con, ob)
}

# --- Lectura (parametrizada; los filtros se aplican en SQL) --------------------
precios_filtrados <- function(con, comercios = NULL, pmin = 0, pmax = 1e9,
                              solo_promo = FALSE, solo_comparables = FALSE, texto = NULL) {
  texto <- if (!is.null(texto) && nzchar(texto)) substr(texto, 1, 60) else NULL
  sql <- "SELECT * FROM v_ultimo_precio WHERE precio BETWEEN ? AND ?"
  par <- list(pmin, pmax)
  if (length(comercios) > 0) {
    sql <- paste0(sql, " AND comercio IN (", paste(rep("?", length(comercios)), collapse = ","), ")")
    par <- c(par, as.list(comercios))
  }
  if (solo_promo)       sql <- paste(sql, "AND en_promocion = 1")
  if (solo_comparables) sql <- paste(sql, "AND comparable = 1")
  if (!is.null(texto)) {
    sql <- paste(sql, "AND (LOWER(nombre) LIKE ? OR LOWER(nombre_norm) LIKE ?)")
    par <- c(par, list(paste0("%", tolower(texto), "%"), paste0("%", tolower(texto), "%")))
  }
  dbGetQuery(con, sql, params = par)
}

cambios_entre <- function(con, ejecucion_a, ejecucion_b, umbral_pct = 10) {
  dbGetQuery(con,
             "SELECT a.comercio, a.nombre, a.precio AS precio_a, b.precio AS precio_b,
            b.precio - a.precio AS delta,
            ROUND(100.0 * (b.precio - a.precio) / a.precio, 2) AS delta_pct,
            ABS(100.0 * (b.precio - a.precio) / a.precio) >= ? AS variacion_grande
     FROM observaciones a
     JOIN observaciones b ON b.comercio = a.comercio AND b.producto_comercio = a.producto_comercio
                         AND a.ejecucion_id = ? AND b.ejecucion_id = ?
     WHERE a.descartada = 0 AND b.descartada = 0 AND a.precio <> b.precio",
             params = list(umbral_pct, ejecucion_a, ejecucion_b))
}

resumen_comercios <- function(con) {
  dbGetQuery(con,
             "SELECT comercio, COUNT(DISTINCT producto_comercio) AS productos, COUNT(*) AS observaciones,
            COUNT(DISTINCT ejecucion_id) AS ejecuciones
     FROM observaciones WHERE descartada = 0 GROUP BY comercio")
}

# Actualiza UN comercio: scraper (sin reescribirlo) -> procesa -> valida -> inserta. No borra nada.
actualizar_comercio <- function(con, comercio) {
  id  <- paste0("ejec_", format(Sys.time(), "%Y%m%d_%H%M", tz = "America/Bogota"))  # único aunque haya 2 corridas el mismo día
  reg <- recolectar_comercio(comercio, ejecucion_id = id)                           # scraper.R
  ej  <- reg |> rename(nota = motivo) |> mutate(con_raw = 1L)
  registrar_ejecuciones(con, ej)
  if (reg$estado == "fallida") return(list(registro = reg, recolectadas = 0L, nuevas = 0L, rechazadas = 0L))
  
  csv   <- tail(sort(list.files(file.path("raw", comercio), "^productos_.*\\.csv$", full.names = TRUE)), 1)
  datos <- readr::read_csv(csv, col_types = readr::cols(.default = "c"), show_col_types = FALSE) |>
    mutate(across(c(precio, precio_lista), as.numeric)) |>
    preparar_datos() |> mutate(ejecucion_id = id) |> asignar_comparables()
  
  v <- validar_observaciones(datos)
  purrr::walk(split(v$rechazadas, v$rechazadas$.regla), \(r)
              registrar_rechazos(con, r, id, r$.regla[1], r$.motivo[1]))
  nuevas <- insertar_observaciones(con, v$validas)
  
  list(registro = reg, recolectadas = nrow(datos), nuevas = nuevas, rechazadas = nrow(v$rechazadas))
}

actualizar_offline <- function(con, comercio, ejecucion_ui) {
  # ejecucion_ui: "ejec_20261118" o "ejec_20261118_1530" -> fecha "2026-11-18"
  fecha <- sub("^ejec_(\\d{4})(\\d{2})(\\d{2}).*$", "\\1-\\2-\\3", ejecucion_ui)
  id    <- paste0("ejec_", gsub("-", "", fecha))
  
  datos <- reprocesar_raw(comercio, fecha)                      # scraper.R, lee raw/<cm>/<fecha>/html
  if (nrow(datos) == 0) return(list(recolectadas = 0L, nuevas = 0L, rechazadas = 0L))
  datos <- datos |>
    dplyr::mutate(dplyr::across(c(precio, precio_lista), as.numeric)) |>
    preparar_datos() |> dplyr::mutate(ejecucion_id = id) |> asignar_comparables()
  
  existia <- nrow(dbGetQuery(con,
                             "SELECT 1 FROM ejecuciones WHERE ejecucion_id = ? AND comercio = ?",
                             params = list(id, comercio))) > 0
  if (!existia) {                                               # FK exige la ejecución
    dbExecute(con, "INSERT OR IGNORE INTO ejecuciones
      (ejecucion_id, comercio, fecha_inicio, fecha_fin, n_registros, estado, nota, con_raw)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1)",
              params = list(id, comercio, as.character(min(datos$fecha_hora)),
                            as.character(max(datos$fecha_hora)), nrow(datos),
                            if (comercio == "farmatodo") "parcial" else "completa",
                            "Reprocesado sin conexión desde HTML guardado"))
  }
  
  v <- validar_observaciones(datos)
  if (!existia)                                                 # no duplicar rechazos al repetir
    purrr::walk(split(v$rechazadas, v$rechazadas$.regla), \(r)
                registrar_rechazos(con, r, id, r$.regla[1], r$.motivo[1]))
  nuevas <- insertar_observaciones(con, v$validas)              # INSERT OR IGNORE: repetir no duplica
  
  list(recolectadas = nrow(datos), nuevas = nuevas, rechazadas = nrow(v$rechazadas))
}

ahorro_por_producto <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT producto_id, MAX(precio) AS p_max, MIN(precio) AS p_min,
           ROUND(100.0 * (MAX(precio) - MIN(precio)) / MAX(precio), 1) AS ahorro_pct,
           (SELECT GROUP_CONCAT(r2.comercio, ' | ') FROM v_referencia r2
             WHERE r2.ejecucion_id = r.ejecucion_id AND r2.producto_id = r.producto_id
               AND r2.precio = MIN(r.precio)) AS mas_barato   -- empates: todos los que igualan el mínimo
    FROM v_referencia r WHERE ejecucion_id = ?
    GROUP BY producto_id HAVING COUNT(*) > 1", params = list(ejecucion))
}

canasta_totales <- function(con, ejecucion, productos) {
  if (length(productos) == 0) return(data.frame(comercio = character(), n = integer(),
                                                total = numeric(), completa = logical()))
  ph <- paste(rep("?", length(productos)), collapse = ",")
  d <- dbGetQuery(con, paste0("
    SELECT comercio, COUNT(DISTINCT producto_id) AS n, SUM(precio) AS total
    FROM v_referencia WHERE ejecucion_id = ? AND producto_id IN (", ph, ")
    GROUP BY comercio"), params = c(list(ejecucion), as.list(productos)))
  d$completa <- d$n == length(productos)
  d
}
