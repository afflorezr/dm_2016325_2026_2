# =============================================================================
# validacion.R — Migración del esquema SQLite, vistas, índices y validación
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(tibble)
  library(jsonlite)
  library(pointblank)
})

# ---- 1. Migración e inicialización del esquema (idempotente) ----------------
migrar_esquema_t2 <- function(con) {
  intentar <- function(sql) tryCatch(dbExecute(con, sql), error = function(e) NULL)
  
  # Tablas base (garantiza funcionamiento también en bases temporales de tests)
  dbExecute(con, "CREATE TABLE IF NOT EXISTS ejecuciones (
    id_ejecucion TEXT NOT NULL,
    comercio     TEXT NOT NULL,
    inicio       TEXT NOT NULL,
    fin          TEXT,
    modo         TEXT NOT NULL,
    n_registros  INTEGER NOT NULL,
    n_esperado   INTEGER,
    estado       TEXT NOT NULL CHECK (estado IN ('completa', 'parcial', 'fallida')),
    detalle      TEXT,
    PRIMARY KEY (id_ejecucion, comercio)
  )")
  
  dbExecute(con, "CREATE TABLE IF NOT EXISTS observaciones (
    id_obs                INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion          TEXT NOT NULL,
    comercio              TEXT NOT NULL,
    sku                   TEXT NOT NULL,
    nombre_original       TEXT,
    marca                 TEXT,
    subcategoria          TEXT,
    descripcion_original  TEXT,
    precio                REAL,
    precio_antes          REAL,
    promocion             INTEGER,
    disponible            INTEGER,
    estado_disponibilidad TEXT CHECK (estado_disponibilidad IN ('disponible','agotado')),
    descartada            INTEGER NOT NULL DEFAULT 0,
    url                   TEXT NOT NULL,
    fecha_hora_consulta   TEXT NOT NULL,
    UNIQUE (comercio, sku, fecha_hora_consulta),
    FOREIGN KEY (id_ejecucion, comercio) REFERENCES ejecuciones (id_ejecucion, comercio)
  )")
  
  dbExecute(con, "CREATE TABLE IF NOT EXISTS productos (
    id_producto      TEXT PRIMARY KEY,
    nombre_std       TEXT NOT NULL,
    marca_std        TEXT,
    subcategoria_std TEXT,
    contenido        REAL,
    unidad           TEXT,
    n_unidades       INTEGER,
    contenido_total  REAL,
    unidad_norm      TEXT CHECK (unidad_norm IN ('mL','g','unidad'))
  )")
  
  dbExecute(con, "CREATE TABLE IF NOT EXISTS correspondencia (
    id_producto TEXT NOT NULL REFERENCES productos (id_producto),
    comercio    TEXT NOT NULL,
    sku         TEXT NOT NULL,
    verificado  INTEGER NOT NULL,
    nota        TEXT,
    PRIMARY KEY (comercio, sku)
  )")
  
  # Tablas de auditoría: correcciones y observaciones rechazadas
  dbExecute(con, "CREATE TABLE IF NOT EXISTS correcciones (
    id_correccion  INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha          TEXT NOT NULL,
    tabla          TEXT NOT NULL,
    registro       TEXT NOT NULL,
    campo          TEXT NOT NULL,
    valor_anterior TEXT,
    valor_nuevo    TEXT,
    motivo         TEXT NOT NULL
  )")
  
  dbExecute(con, "CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
    id_rechazo   INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion TEXT,
    comercio     TEXT,
    sku          TEXT,
    motivo       TEXT NOT NULL,
    datos_json   TEXT,
    fecha        TEXT NOT NULL
  )")
  
  # Columnas nuevas sobre tablas existentes del Taller 1
  intentar("ALTER TABLE observaciones ADD COLUMN estado_disponibilidad TEXT
            CHECK (estado_disponibilidad IN ('disponible','agotado'))")
  intentar("ALTER TABLE observaciones ADD COLUMN descartada INTEGER NOT NULL DEFAULT 0")
  
  dbExecute(con, "UPDATE observaciones SET estado_disponibilidad =
    CASE disponible WHEN 1 THEN 'disponible' WHEN 0 THEN 'agotado' END
    WHERE estado_disponibilidad IS NULL")
  
  intentar("ALTER TABLE productos ADD COLUMN contenido_total REAL")
  intentar("ALTER TABLE productos ADD COLUMN unidad_norm TEXT CHECK (unidad_norm IN ('mL','g','unidad'))")
  
  dbExecute(con, "UPDATE productos SET
    contenido_total = contenido,
    unidad_norm = CASE LOWER(unidad)
      WHEN 'ml' THEN 'mL'
      WHEN 'g'  THEN 'g'
      ELSE 'unidad'
    END
    WHERE contenido_total IS NULL OR unidad_norm IS NULL")
  
  # Índices para los filtros de la app
  for (s in c(
    "CREATE INDEX IF NOT EXISTS ix_obs_ejec    ON observaciones (id_ejecucion)",
    "CREATE INDEX IF NOT EXISTS ix_obs_com_sku ON observaciones (comercio, sku, fecha_hora_consulta)",
    "CREATE INDEX IF NOT EXISTS ix_obs_precio  ON observaciones (precio)",
    "CREATE INDEX IF NOT EXISTS ix_obs_promo   ON observaciones (promocion)",
    "CREATE INDEX IF NOT EXISTS ix_corr_prod   ON correspondencia (id_producto)"
  )) {
    dbExecute(con, s)
  }
  
  # Vistas SQL
  for (v in c("v_ultimo_precio", "v_cambios_precio", "v_comparables", "v_no_observados")) {
    dbExecute(con, paste("DROP VIEW IF EXISTS", v))
  }
  
  # Vista 1: Último precio por comercio y SKU (enriquecida con comparables y precio unitario)
  dbExecute(con, "CREATE VIEW v_ultimo_precio AS
    WITH ult AS (
      SELECT o.*,
             ROW_NUMBER() OVER (PARTITION BY o.comercio, o.sku
                                ORDER BY o.fecha_hora_consulta DESC) AS rn
      FROM observaciones o
      WHERE o.descartada = 0 AND o.precio IS NOT NULL
    )
    SELECT u.id_obs, u.id_ejecucion, u.comercio, u.sku, u.nombre_original,
           u.marca, u.subcategoria, u.descripcion_original,
           u.precio, u.precio_antes, u.promocion, u.disponible,
           u.estado_disponibilidad, u.url, u.fecha_hora_consulta,
           c.id_producto,
           CASE WHEN c.id_producto IS NULL THEN 0 ELSE 1 END AS comparable,
           p.nombre_std, p.subcategoria_std, p.contenido_total, p.unidad_norm,
           CASE WHEN p.contenido_total IS NOT NULL AND p.contenido_total > 0
                THEN ROUND(u.precio / p.contenido_total, 2)
                ELSE NULL END AS precio_unitario
    FROM ult u
    LEFT JOIN correspondencia c ON c.comercio = u.comercio AND c.sku = u.sku
    LEFT JOIN productos p       ON p.id_producto = c.id_producto
    WHERE u.rn = 1")
  
  # Vista 2: Cambios de precio históricos consecutivos por comercio y SKU
  dbExecute(con, "CREATE VIEW v_cambios_precio AS
    SELECT comercio, sku, nombre_original, id_ejecucion, fecha_hora_consulta, precio,
           LAG(precio) OVER w          AS precio_anterior,
           LAG(id_ejecucion) OVER w    AS ejecucion_anterior,
           precio - LAG(precio) OVER w AS cambio_cop,
           ROUND(100.0 * (precio - LAG(precio) OVER w) / LAG(precio) OVER w, 1) AS cambio_pct
    FROM observaciones
    WHERE descartada = 0 AND precio IS NOT NULL
    WINDOW w AS (PARTITION BY comercio, sku ORDER BY fecha_hora_consulta)")
  
  # Vista 3: Observaciones de productos comparables con precio por unidad normalizada
  dbExecute(con, "CREATE VIEW v_comparables AS
    SELECT o.id_obs, o.id_ejecucion, o.comercio, o.sku, o.nombre_original, o.marca,
           o.precio, o.precio_antes, o.promocion, o.estado_disponibilidad, o.url,
           o.fecha_hora_consulta, p.id_producto, p.nombre_std, p.marca_std,
           p.subcategoria_std, p.contenido_total, p.unidad_norm,
           ROUND(o.precio / p.contenido_total, 2) AS precio_unitario
    FROM observaciones o
    JOIN correspondencia c ON c.comercio = o.comercio AND c.sku = o.sku
    JOIN productos p       ON p.id_producto = c.id_producto
    WHERE o.descartada = 0")
  
  # Vista 4: Anuncios vistos antes pero ausentes en la última ejecución de su comercio
  dbExecute(con, "CREATE VIEW v_no_observados AS
    WITH ult AS (
      SELECT comercio, MAX(fecha_hora_consulta) AS f
      FROM ejecuciones e
      JOIN observaciones o USING (id_ejecucion, comercio)
      GROUP BY comercio
    ),
    ult_ej AS (
      SELECT DISTINCT o.comercio, o.id_ejecucion
      FROM observaciones o
      JOIN ult u ON u.comercio = o.comercio AND u.f = o.fecha_hora_consulta
    )
    SELECT DISTINCT o.comercio, o.sku, o.nombre_original, o.id_ejecucion AS visto_en
    FROM observaciones o
    WHERE o.descartada = 0
      AND NOT EXISTS (
        SELECT 1 FROM ult_ej e
        JOIN observaciones n ON n.id_ejecucion = e.id_ejecucion AND n.comercio = e.comercio
        WHERE n.comercio = o.comercio AND n.sku = o.sku
      )")
  
  invisible(TRUE)
}

# ---- 2. Validación de observaciones antes de insertar (Módulo 1.4) ----------
validar_observaciones <- function(df, con = NULL, comercio_nombre = NULL, id_ejecucion = NULL) {
  if (is.null(df) || nrow(df) == 0) {
    return(list(validas = tibble(), rechazadas = tibble(), alertas = character()))
  }
  
  fecha_val <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  
  df_eval <- df |>
    mutate(
      .dup = duplicated(paste(comercio, sku, fecha_hora_consulta)),
      .motivo = case_when(
        is.na(comercio) | trimws(as.character(comercio)) == "" ~ "Comercio ausente",
        is.na(sku) | trimws(as.character(sku)) == "" ~ "SKU ausente",
        is.na(url) | trimws(as.character(url)) == "" ~ "URL ausente",
        is.na(fecha_hora_consulta) | trimws(as.character(fecha_hora_consulta)) == "" ~ "Fecha/hora de consulta ausente",
        is.na(precio) | !is.numeric(precio) | precio <= 0 ~ "Precio nulo, no numérico o <= 0",
        .dup ~ "Observación duplicada en la misma ejecución",
        TRUE ~ NA_character_
      )
    )
  
  validas <- df_eval |>
    filter(is.na(.motivo)) |>
    select(-.dup, -.motivo) |>
    mutate(
      estado_disponibilidad = case_when(
        disponible == 1 ~ "disponible",
        disponible == 0 ~ "agotado",
        TRUE ~ NA_character_
      ),
      descartada = 0L
    )
  
  filas_rech <- df_eval |> filter(!is.na(.motivo))
  rechazadas <- if (nrow(filas_rech) > 0) {
    filas_datos <- filas_rech |> select(-.dup, -.motivo)
    json_por_fila <- vapply(seq_len(nrow(filas_datos)), function(i) {
      as.character(toJSON(as.list(filas_datos[i, ]), auto_unbox = TRUE, null = "null"))
    }, character(1))
    
    tibble(
      id_ejecucion = id_ejecucion %||% NA_character_,
      comercio     = as.character(filas_rech$comercio),
      sku          = as.character(filas_rech$sku),
      motivo       = filas_rech$.motivo,
      datos_json   = json_por_fila,
      fecha        = fecha_val
    )
  } else {
    tibble()
  }
  
  # Verificación formal con pointblank (Anexo C)
  alertas <- character()
  if (nrow(validas) > 0) {
    agente <- create_agent(tbl = validas) |>
      col_vals_gt(columns = precio, value = 0) |>
      col_vals_not_null(columns = c(comercio, url, fecha_hora_consulta)) |>
      rows_distinct(columns = c(comercio, sku, fecha_hora_consulta)) |>
      interrogate()
    
    if (!all_passed(agente)) {
      alertas <- c(alertas, "Fallo en validación pointblank sobre observaciones.")
    }
  }
  
  # Verificar presencia de los productos comparables esperados en ese comercio
  if (!is.null(con) && !is.null(comercio_nombre) && dbExistsTable(con, "correspondencia")) {
    esperados <- dbGetQuery(con,
                            "SELECT DISTINCT sku FROM correspondencia WHERE comercio = ?",
                            params = list(comercio_nombre)
    )$sku
    
    if (length(esperados) > 0) {
      faltantes <- setdiff(esperados, validas$sku)
      if (length(faltantes) > 0) {
        alertas <- c(alertas, sprintf(
          "Faltan %d SKUs comparables en %s: %s",
          length(faltantes), comercio_nombre, paste(faltantes, collapse = ", ")
        ))
      }
    }
  }
  
  list(validas = validas, rechazadas = rechazadas, alertas = alertas)
}