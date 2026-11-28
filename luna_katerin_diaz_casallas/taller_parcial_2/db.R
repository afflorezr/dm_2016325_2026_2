##### 1. LIBRERÍAS Y CONEXIÓN

if (!exists("estandarizar", mode = "function")) {
  source("validacion.R")
}

paquetes_db <- c("DBI", "RSQLite", "dplyr", "glue", "tibble")

# En shinyapps los paquetes ya vienen en la imagen; instalar en runtime cuelga el arranque
if (!nzchar(Sys.getenv("SHINY_PORT"))) {
  pendientes_db <- setdiff(paquetes_db, rownames(installed.packages()))
  if (length(pendientes_db) > 0) {
    install.packages(pendientes_db, repos = "https://cloud.r-project.org")
  }
}

invisible(lapply(paquetes_db, library, character.only = TRUE))

DB_PATH <- "comparador_precios.sqlite"
IDS_COMPARABLES <- sprintf("P%02d", 1:10)

# Abre la conexión a SQLite con las llaves foráneas activas
abrir_conexion <- function(path = DB_PATH) {
  con <- dbConnect(RSQLite::SQLite(), path)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

# Ejecuta una consulta parametrizada y cierra la conexión al terminar
consultar <- function(sql, params = NULL, path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  if (is.null(params) || length(params) == 0) {
    dbGetQuery(con, sql)
  } else {
    dbGetQuery(con, sql, params = params)
  }
}

# Ejecuta una instrucción parametrizada (UPDATE, INSERT) y cierra la conexión al terminar
ejecutar <- function(sql, params = NULL, path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  if (is.null(params) || length(params) == 0) {
    dbExecute(con, sql)
  } else {
    dbExecute(con, sql, params = params)
  }
}

##### 2. ESQUEMA DE LA BASE

# Agrega a la base del Taller 1 la disponibilidad, el motivo de la ejecución, las tablas
# correcciones y observaciones_rechazadas, y los índices de los filtros
migrar_esquema <- function(path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)

  if (!"disponibilidad" %in% dbListFields(con, "historico_productos")) {
    dbExecute(con, "ALTER TABLE historico_productos ADD COLUMN disponibilidad TEXT")
  }
  if (!"motivo" %in% dbListFields(con, "ejecuciones")) {
    dbExecute(con, "ALTER TABLE ejecuciones ADD COLUMN motivo TEXT")
  }

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS correcciones (
      id_correccion INTEGER PRIMARY KEY AUTOINCREMENT,
      fecha TEXT NOT NULL,
      tabla TEXT NOT NULL,
      registro TEXT NOT NULL,
      campo TEXT NOT NULL,
      valor_anterior TEXT,
      valor_nuevo TEXT,
      motivo TEXT NOT NULL
    )
  ")
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
      id_rechazo INTEGER PRIMARY KEY AUTOINCREMENT,
      id_ejecucion TEXT,
      comercio TEXT,
      enlace TEXT,
      fecha_extraccion TEXT,
      motivo TEXT NOT NULL,
      detalle TEXT,
      fecha_registro TEXT NOT NULL
    )
  ")

  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_hist_comercio_enlace ON historico_productos (comercio, enlace)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_hist_ejecucion ON historico_productos (id_ejecucion, comercio)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_hist_fecha ON historico_productos (fecha_extraccion)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_rechazo_ejecucion ON observaciones_rechazadas (id_ejecucion, comercio)")
  invisible(path)
}

# Clasifica la disponibilidad de las observaciones que aún no la tienen
completar_disponibilidad <- function(path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  pendientes <- dbGetQuery(con, "
    SELECT id_observacion, precio, precio_num
    FROM historico_productos
    WHERE disponibilidad IS NULL
  ")
  if (nrow(pendientes) == 0) return(invisible(0L))

  pendientes <- mutate(pendientes, disponibilidad = clasificar_disponibilidad(precio, precio_num))
  rs <- dbSendStatement(con, "
    UPDATE historico_productos
    SET disponibilidad = ?
    WHERE id_observacion = ?
  ")
  dbBind(rs, list(pendientes$disponibilidad, pendientes$id_observacion))
  dbClearResult(rs)
  invisible(nrow(pendientes))
}

# Guarda las observaciones rechazadas sin repetir las ya registradas en la misma ejecución
registrar_rechazos <- function(con, rechazadas, id_ejecucion) {
  if (is.null(rechazadas) || nrow(rechazadas) == 0) return(invisible(0L))
  ahora <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00")
  detalle <- if ("n_producto" %in% names(rechazadas)) rechazadas$n_producto else NA_character_
  lote <- tibble(
    id_ejecucion = id_ejecucion,
    comercio = rechazadas$comercio,
    enlace = rechazadas$enlace,
    fecha_extraccion = rechazadas$fecha_extraccion,
    motivo = rechazadas$motivo_rechazo,
    detalle = detalle,
    fecha_registro = ahora
  )
  previas <- dbGetQuery(con, "
    SELECT comercio, COALESCE(enlace, '') AS enlace, motivo
    FROM observaciones_rechazadas
    WHERE id_ejecucion = ?
  ", params = list(id_ejecucion))
  if (nrow(previas) > 0) {
    lote <- lote %>%
      mutate(enlace_clave = coalesce(enlace, "")) %>%
      anti_join(previas, by = c("comercio", "enlace_clave" = "enlace", "motivo")) %>%
      select(-enlace_clave)
  }
  if (nrow(lote) == 0) return(invisible(0L))
  dbAppendTable(con, "observaciones_rechazadas", lote)
  invisible(nrow(lote))
}

##### 3. LIMPIEZA Y CORRESPONDENCIA DE PRODUCTOS

# Las 10 presentaciones comparables (8 productos) con su contenido y unidad normalizada
catalogo_comparables <- function() {
  tribble(
    ~id_producto, ~producto, ~nombre_corto, ~marca, ~subcategoria, ~presentacion, ~contenido, ~unidad, ~familia,
    "P01", "Omega 3 cápsulas blandas", "Omega 3 Procaps x30", "Procaps", "Omega 3 y aceites de pescado", "30 cápsulas", 30, "und", "omega3_procaps",
    "P02", "Complejo B tabletas", "Complejo B Genfar x250", "Genfar", "Complejo B y ácido fólico", "250 tabletas", 250, "und", "complejo_b_genfar",
    "P03", "Cebion gotas vitamina C 100 mg/mL sabor fresa", "Cebion gotas fresa 30 mL", "Cebion", "Vitamina C", "30 mL", 30, "mL", "cebion_gotas_fresa",
    "P04", "Vitacerebrina jarabe sabor caramelo", "Vitacerebrina caramelo 180 mL", "Vitacerebrina", "Multivitamínicos", "180 mL", 180, "mL", "vitacerebrina_caramelo",
    "P05", "Aquasol E 800 UI cápsulas blandas", "Aquasol E 800 UI x30", "Aquasol", "Vitamina E", "30 cápsulas", 30, "und", "aquasol_e_800",
    "P06", "Ácido fólico 1 mg tabletas", "Ácido fólico Ecar 1 mg x100", "Ecar", "Complejo B y ácido fólico", "100 tabletas", 100, "und", "acido_folico_ecar_1mg",
    "P07", "Kola granulada Tarrito Rojo sabor fresa", "Kola Tarrito Rojo fresa 380 g", "Tarrito Rojo (JGB)", "Kola granulada y tónicos", "380 g", 380, "g", "kola_tarrito_rojo_fresa",
    "P08", "Kola granulada Tarrito Rojo sabor fresa", "Kola Tarrito Rojo fresa 135 g", "Tarrito Rojo (JGB)", "Kola granulada y tónicos", "135 g", 135, "g", "kola_tarrito_rojo_fresa",
    "P09", "Centrum Silver Women +50", "Centrum Silver Women x30", "Centrum", "Multivitamínicos", "30 tabletas", 30, "und", "centrum_silver_women",
    "P10", "Centrum Silver Women +50", "Centrum Silver Women x60", "Centrum", "Multivitamínicos", "60 tabletas", 60, "und", "centrum_silver_women"
  )
}

# Subcategoría según palabras del nombre; se aplica la primera regla que coincide
reglas_subcategoria <- function() {
  tribble(
    ~subcategoria, ~patron,
    "Multivitamínicos", "\\b(MULTIVITAMIN\\w*|MULTI ?VIT\\w*|CENTRUM|SUPRADYN|PHARMATON|VITACEREBRINA|GESTAVIT|REDOXITOS|DAYAMINERAL)\\b",
    "Omega 3 y aceites de pescado", "\\b(OMEGA|FISH OIL|PESCADO|BACALAO|KRILL)\\b",
    "Colágeno", "\\b(COLAGENO|COLLAGEN|GELICART|NUTRIGEL)\\b",
    "Kola granulada y tónicos", "\\b(KOLA|TONICO|EMULSION|LEVADURA|JALEA)\\b",
    "Alimentos y fórmulas nutricionales", "\\b(ALIMENTO|LACTEO|GLUCERNA|KLIM|ENSURE|PEDIASURE|FORMULA|NESTOGENO|PEDIALYTE|SCANDISHAKE|ALULA)\\b",
    "Proteínas y nutrición deportiva", "\\b(PROTEIN\\w*|PROTEINA|PROWHEY|WHEY|CREATIN\\w*|GLUTAMIN\\w*|CARNITIN\\w*|AMINOACIDOS?|PRE-ENTRENO)\\b",
    "Probióticos y enzimas", "\\b(PROBIOTIC\\w*|BIOFLOR|ENTEROPHYLUS|ENZYMAX|LACTOBACILL\\w*)\\b",
    "Vitamina C", "\\b(VITAMINA C|VITAMIN C|VIT C|VITA C|CEBION|REDOXON|ACIDO ASCORBICO)\\b",
    "Calcio", "\\b(CALCIO|CALCIUM|BIOCALCIUM|CALCIBON|CITRAGEL|CALTRATE|CALCITRAL|KIDCAL)\\b",
    "Vitamina D", "\\b(VITAMINA D3?|VITAMIN D3?|D3|DEFEROL|FARMA D|DEBLAX)\\b",
    "Vitamina E", "\\b(VITAMINA E|VITAMIN E|AQUASOL)\\b",
    "Complejo B y ácido fólico", "\\b(COMPLEJO B|B12|B-12|B1|B6|BIOTIN\\w*|TIAMINA|NEUROBION|FOLICO|B-VIT|BEDOYECTA)\\b",
    "Minerales (magnesio, zinc, hierro y otros)", "\\b(MAGNES\\w*|ZINC|HIERRO|FERR\\w*|FERPRO|ANEMIDOX|SELENI\\w*|POTAS\\w*|CHROMIUM|CROMO)\\b"
  )
}

# Reglas de correspondencia: nombre, marca, contenido y unidad de cada presentación comparable
reglas_correspondencia <- function() {
  tribble(
    ~id_producto, ~patron_nombre, ~patron_excluir, ~patron_marca, ~cantidad, ~unidad,
    "P01", "\\bOMEGA[ -]?3\\b", NA_character_, "PROCAPS", 30, "und",
    "P02", "\\bCOMPLEJO B\\b", NA_character_, "GENFAR", 250, "und",
    "P03", "\\bCEBION\\b.*\\bFRESA\\b", NA_character_, NA_character_, 30, "mL",
    "P04", "\\bVITACEREBRINA\\b.*\\bCARAMELO\\b", NA_character_, NA_character_, 180, "mL",
    "P05", "\\bAQUASOL\\b.*\\bE[ -]?800\\b", NA_character_, NA_character_, 30, "und",
    "P06", "\\bACIDO FOLICO 1 MG\\b", NA_character_, "ECAR", 100, "und",
    "P07", "\\bTARRITO ROJO\\b.*\\bFRESA\\b", "TRADICIONAL|OFERTA|\\+", NA_character_, 380, "g",
    "P08", "\\bTARRITO ROJO\\b.*\\bFRESA\\b", "TRADICIONAL|OFERTA|\\+", NA_character_, 135, "g",
    "P09", "\\bCENTRUM SILVER WOMEN\\b", NA_character_, NA_character_, 30, "und",
    "P10", "\\bCENTRUM SILVER WOMEN\\b", NA_character_, NA_character_, 60, "und"
  )
}

# Asigna la subcategoría a cada nombre estandarizado
asignar_subcategoria <- function(nombre_std) {
  reglas <- reglas_subcategoria()
  subcategoria <- rep("Otros suplementos", length(nombre_std))
  asignado <- rep(FALSE, length(nombre_std))
  for (i in seq_len(nrow(reglas))) {
    coincide <- !asignado & str_detect(nombre_std, reglas$patron[i]) %in% TRUE
    subcategoria[coincide] <- reglas$subcategoria[i]
    asignado <- asignado | coincide
  }
  subcategoria
}

# Asigna el identificador común (P01-P10) a los anuncios que cumplen una regla
asignar_producto <- function(df, reglas = reglas_correspondencia()) {
  id <- rep(NA_character_, nrow(df))
  for (i in seq_len(nrow(reglas))) {
    r <- reglas[i, ]
    cumple <- str_detect(df$nombre_std, r$patron_nombre) &
      df$cantidad %in% r$cantidad &
      df$unidad %in% r$unidad
    if (!is.na(r$patron_excluir)) cumple <- cumple & !str_detect(df$nombre_std, r$patron_excluir)
    if (!is.na(r$patron_marca)) cumple <- cumple & str_detect(coalesce(df$marca_std, ""), r$patron_marca)
    id[is.na(id) & cumple %in% TRUE] <- r$id_producto
  }
  id
}

# Un anuncio por comercio y enlace, con campos estandarizados, motivo de descarte e id_producto
construir_anuncios <- function(obs) {
  if (nrow(obs) == 0) {
    return(tibble(
      comercio = character(), enlace = character(), codigo_producto = character(),
      n_producto = character(), marca = character(), nombre_std = character(),
      marca_std = character(), subcategoria = character(), cantidad = numeric(),
      unidad = character(), n_observaciones = integer(), motivo_descarte = character(),
      id_producto = character(), comparable = integer()
    ))
  }

  enlaces_ambiguos <- obs %>%
    group_by(id_ejecucion, comercio, enlace) %>%
    filter(n_distinct(n_producto) > 1) %>%
    ungroup() %>%
    distinct(comercio, enlace) %>%
    mutate(ambiguo = TRUE)

  df <- obs %>%
    arrange(comercio, enlace, desc(fecha_extraccion)) %>%
    group_by(comercio, enlace) %>%
    summarise(
      n_producto = first(n_producto),
      marca = first(marca),
      contenido = first(contenido),
      n_observaciones = n(),
      .groups = "drop"
    ) %>%
    left_join(enlaces_ambiguos, by = c("comercio", "enlace")) %>%
    mutate(motivo_descarte = case_when(
      !str_detect(enlace, "/p(\\?|$)") ~ "enlace_no_es_producto",
      ambiguo %in% TRUE ~ "enlace_ambiguo",
      is.na(n_producto) | str_trim(n_producto) == "" ~ "anuncio_sin_nombre",
      TRUE ~ NA_character_
    )) %>%
    select(-ambiguo) %>%
    mutate(
      codigo_producto = str_match(enlace, "-(\\d+)/p$")[, 2],
      nombre_std = estandarizar(n_producto),
      marca_std = estandarizar(marca),
      contenido_std = estandarizar(contenido)
    )

  patron_exclusiones <- paste0(
    "\\b(SERUM|PANAL(ES)?|PANITOS?|RUBOR|REMOVEDOR|MASCARILLAS?|SHAMPOO|CHAMPU|CREMAS?|GEL|",
    "DESODORANTE|LACA|LECHE CORPORAL|LOCAO|LOCION|ACEITE|MICELAR|TOALLITAS|ACONDICIONADOR|",
    "JABON|PROTECTOR SOLAR|BLOQUEADOR)\\b"
  )
  patron_excepciones <- "\\b(OMEGA|PESCADO|BACALAO)\\b"
  cont_campo <- extraer_contenido(df$contenido_std)
  cont_nombre <- extraer_contenido(df$nombre_std)
  usar_campo <- !is.na(cont_campo$cantidad)

  df <- df %>%
    mutate(
      cantidad = if_else(usar_campo, cont_campo$cantidad, cont_nombre$cantidad),
      unidad = if_else(usar_campo, cont_campo$unidad, cont_nombre$unidad),
      motivo_descarte = if_else(
        is.na(motivo_descarte) &
          str_detect(nombre_std, patron_exclusiones) &
          !str_detect(nombre_std, patron_excepciones),
        "fuera_de_categoria",
        motivo_descarte
      ),
      subcategoria = asignar_subcategoria(nombre_std)
    )
  ids <- asignar_producto(df)
  df %>%
    mutate(
      id_producto = if_else(is.na(motivo_descarte), ids, NA_character_),
      comparable = as.integer(!is.na(id_producto))
    ) %>%
    select(
      comercio, enlace, codigo_producto, n_producto, marca, nombre_std, marca_std,
      subcategoria, cantidad, unidad, n_observaciones, motivo_descarte, id_producto, comparable
    )
}

##### 4. VISTAS Y CAPA ANALÍTICA

# Vistas que usa la aplicación (descritas en diccionario_datos.md)
crear_vistas <- function(con) {
  dbExecute(con, "
    CREATE VIEW v_observaciones AS
    SELECT h.id_observacion, h.id_ejecucion, h.comercio, h.enlace, h.n_producto, h.marca,
           h.contenido, h.precio_num, h.precio_sin_promo_num, h.promocion, h.fecha_extraccion,
           h.disponibilidad,
           a.nombre_std, a.marca_std, a.subcategoria, a.cantidad, a.unidad, a.motivo_descarte,
           a.id_producto, COALESCE(a.comparable, 0) AS comparable
    FROM historico_productos h
    LEFT JOIN anuncios a ON a.comercio = h.comercio AND a.enlace = h.enlace
  ")
  dbExecute(con, "
    CREATE VIEW v_precios_comparables AS
    SELECT o.id_ejecucion, o.comercio, o.id_producto, p.producto, p.nombre_corto, p.presentacion,
           p.familia, p.contenido, p.unidad, o.precio_num AS precio,
           o.precio_sin_promo_num AS precio_lista, o.promocion,
           CASE WHEN p.contenido > 0 THEN o.precio_num / p.contenido END AS precio_unitario,
           o.enlace, o.n_producto, o.fecha_extraccion, o.disponibilidad
    FROM (
      SELECT v.*,
             ROW_NUMBER() OVER (
               PARTITION BY v.id_ejecucion, v.comercio, v.id_producto
               ORDER BY v.fecha_extraccion, v.id_observacion
             ) AS n_obs
      FROM v_observaciones v
      WHERE v.comparable = 1
    ) o
    JOIN productos_comparables p ON p.id_producto = o.id_producto
    WHERE o.n_obs = 1
  ")
  dbExecute(con, "
    CREATE VIEW v_ultimo_precio AS
    SELECT h.id_observacion, h.id_ejecucion, h.comercio, h.enlace, h.n_producto, h.marca,
           h.contenido, h.precio_num, h.precio_sin_promo_num, h.promocion, h.fecha_extraccion,
           h.disponibilidad, a.nombre_std, a.marca_std, a.subcategoria, a.cantidad, a.unidad,
           a.motivo_descarte, a.id_producto, COALESCE(a.comparable, 0) AS comparable,
           p.nombre_corto, p.presentacion, p.familia, p.contenido AS contenido_comp,
           p.unidad AS unidad_comp,
           CASE
             WHEN p.contenido > 0 AND h.precio_num > 0 THEN h.precio_num / p.contenido
             WHEN a.cantidad > 0 AND h.precio_num > 0 THEN h.precio_num / a.cantidad
           END AS precio_unitario
    FROM historico_productos h
    INNER JOIN (
      SELECT comercio, enlace, MAX(fecha_extraccion) AS fecha_extraccion
      FROM historico_productos
      GROUP BY comercio, enlace
    ) ult
      ON ult.comercio = h.comercio AND ult.enlace = h.enlace
     AND ult.fecha_extraccion = h.fecha_extraccion
    LEFT JOIN anuncios a ON a.comercio = h.comercio AND a.enlace = h.enlace
    LEFT JOIN productos_comparables p ON p.id_producto = a.id_producto
  ")
  dbExecute(con, "
    CREATE VIEW v_cambios_precio AS
    WITH lecturas AS (
      SELECT h.comercio, h.enlace, h.n_producto, h.id_ejecucion, h.id_observacion, h.precio_num,
             h.fecha_extraccion, h.disponibilidad,
             ROW_NUMBER() OVER (
               PARTITION BY h.comercio, h.enlace, h.id_ejecucion
               ORDER BY h.fecha_extraccion, h.id_observacion
             ) AS n_lectura
      FROM historico_productos h
      JOIN anuncios a ON a.comercio = h.comercio AND a.enlace = h.enlace
      WHERE a.motivo_descarte IS NULL
    ),
    orden AS (
      SELECT comercio, enlace, n_producto, id_ejecucion, id_observacion, precio_num,
             fecha_extraccion, disponibilidad,
             LAG(precio_num) OVER (
               PARTITION BY comercio, enlace
               ORDER BY fecha_extraccion, id_observacion
             ) AS precio_anterior,
             LAG(id_ejecucion) OVER (
               PARTITION BY comercio, enlace
               ORDER BY fecha_extraccion, id_observacion
             ) AS ejecucion_anterior
      FROM lecturas
      WHERE n_lectura = 1
    )
    SELECT comercio, enlace, n_producto, id_ejecucion, ejecucion_anterior,
           precio_anterior, precio_num,
           precio_num - precio_anterior AS delta_cop,
           CASE WHEN precio_anterior > 0
                THEN 100.0 * (precio_num - precio_anterior) / precio_anterior
           END AS delta_pct,
           CASE
             WHEN precio_num > precio_anterior THEN 'subio'
             WHEN precio_num < precio_anterior THEN 'bajo'
             WHEN precio_num = precio_anterior THEN 'igual'
             ELSE 'sin_precio'
           END AS tipo,
           disponibilidad, fecha_extraccion
    FROM orden
    WHERE ejecucion_anterior IS NOT NULL
  ")
  dbExecute(con, "
    CREATE VIEW v_comparables AS
    SELECT c.id_ejecucion, c.comercio, c.id_producto, c.producto, c.nombre_corto,
           c.presentacion, c.familia, c.contenido, c.unidad, c.precio, c.precio_lista,
           c.promocion, c.precio_unitario, c.enlace, c.n_producto, c.fecha_extraccion,
           c.disponibilidad,
           CASE
             WHEN c.precio IS NOT NULL
              AND c.precio = MIN(c.precio) OVER (PARTITION BY c.id_ejecucion, c.id_producto)
             THEN 1 ELSE 0
           END AS es_mas_barato
    FROM v_precios_comparables c
  ")
}

# Reconstruye anuncios, productos_comparables y las vistas desde historico_productos
reconstruir_capa_analitica <- function(path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)

  obs <- dbGetQuery(con, "
    SELECT id_observacion, id_ejecucion, comercio, n_producto, enlace, marca, contenido,
           fecha_extraccion
    FROM historico_productos
  ")
  anuncios <- construir_anuncios(as_tibble(obs))
  comparables <- catalogo_comparables()

  for (vista in c(
    "v_comparables", "v_ultimo_precio", "v_precios_comparables",
    "v_observaciones", "v_cambios_precio"
  )) {
    dbExecute(con, paste0("DROP VIEW IF EXISTS ", vista))
  }
  dbExecute(con, "DROP TABLE IF EXISTS anuncios")
  dbExecute(con, "DROP TABLE IF EXISTS productos_comparables")

  dbExecute(con, "
    CREATE TABLE productos_comparables (
      id_producto TEXT PRIMARY KEY,
      producto TEXT NOT NULL,
      nombre_corto TEXT NOT NULL,
      marca TEXT NOT NULL,
      subcategoria TEXT NOT NULL,
      presentacion TEXT NOT NULL,
      contenido REAL NOT NULL,
      unidad TEXT NOT NULL,
      familia TEXT NOT NULL
    )
  ")
  dbExecute(con, "
    CREATE TABLE anuncios (
      comercio TEXT NOT NULL,
      enlace TEXT NOT NULL,
      codigo_producto TEXT,
      n_producto TEXT,
      marca TEXT,
      nombre_std TEXT,
      marca_std TEXT,
      subcategoria TEXT,
      cantidad REAL,
      unidad TEXT,
      n_observaciones INTEGER,
      motivo_descarte TEXT,
      id_producto TEXT REFERENCES productos_comparables (id_producto),
      comparable INTEGER NOT NULL,
      PRIMARY KEY (comercio, enlace)
    )
  ")
  dbAppendTable(con, "productos_comparables", comparables)
  if (nrow(anuncios) > 0) dbAppendTable(con, "anuncios", anuncios)
  crear_vistas(con)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_anuncios_producto ON anuncios (id_producto)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_anuncios_subcategoria ON anuncios (subcategoria)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_anuncios_marca ON anuncios (marca_std)")
  invisible(anuncios)
}

##### 5. CORRECCIONES DE LA BASE DEL TALLER 1
# No se borran observaciones: se corrige el campo y queda el registro en correcciones

# Registra una corrección una sola vez (misma tabla, registro, campo y valor nuevo)
registrar_correccion <- function(con, tabla, registro, campo, valor_anterior, valor_nuevo, motivo) {
  existe <- dbGetQuery(con, "
    SELECT COUNT(*) AS n FROM correcciones
    WHERE tabla = ? AND registro = ? AND campo = ? AND COALESCE(valor_nuevo, '') = COALESCE(?, '')
  ", params = list(tabla, registro, campo, valor_nuevo))$n
  if (existe > 0) return(invisible(0L))
  dbExecute(con, "
    INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00"), tabla, registro, campo,
    valor_anterior, valor_nuevo, motivo
  ))
}

# La ejecución de Cafam del 11-oct no recorrió toda la categoría: pasa a parcial
corregir_ejecucion_cafam_11oct <- function(con) {
  fila <- dbGetQuery(con, "
    SELECT estado, productos_unicos, paginas_consultadas FROM ejecuciones
    WHERE id_ejecucion = '20261011_195616' AND comercio = 'CAFAM'
  ")
  if (nrow(fila) == 0 || fila$estado[[1]] != "completa") return(invisible(0L))
  motivo <- paste0(
    "Recorrió ", fila$paginas_consultadas[[1]], " páginas y ", fila$productos_unicos[[1]],
    " productos; dos días después el sitio mostraba 400 productos en 34 páginas. ",
    "La categoría quedó incompleta."
  )
  dbExecute(con, "
    UPDATE ejecuciones SET estado = 'parcial', motivo = ?
    WHERE id_ejecucion = '20261011_195616' AND comercio = 'CAFAM'
  ", params = list(motivo))
  registrar_correccion(
    con, "ejecuciones", "20261011_195616|CAFAM", "estado", "completa", "parcial", motivo
  )
}

# Registra las correcciones hechas en las reglas: anuncios sin nombre y unidad normalizada
registrar_correcciones_reglas <- function(con) {
  sin_nombre <- dbGetQuery(con, "
    SELECT comercio, enlace FROM anuncios WHERE motivo_descarte = 'anuncio_sin_nombre'
  ")
  for (i in seq_len(nrow(sin_nombre))) {
    registrar_correccion(
      con, "anuncios", paste(sin_nombre$comercio[i], sin_nombre$enlace[i], sep = "|"),
      "motivo_descarte", NA_character_, "anuncio_sin_nombre",
      "El anuncio no tiene nombre ni precio: es un enlace publicitario. En el Taller 1 quedaba dentro de la categoría."
    )
  }
  unidades_t1 <- c(P01 = "cápsula", P02 = "tableta", P05 = "cápsula", P06 = "tableta", P09 = "tableta", P10 = "tableta")
  for (id in names(unidades_t1)) {
    registrar_correccion(
      con, "productos_comparables", id, "unidad", unname(unidades_t1[id]), "und",
      "La unidad del contenido se normaliza a mL, g o unidad; la forma farmacéutica queda en presentacion."
    )
  }
}

# Ejecuciones marcadas parciales solo por una presentación faltante: si están los 8 productos,
# pasan a completa
reevaluar_cobertura_presentaciones <- function(con) {
  pendientes <- dbGetQuery(con, "
    SELECT id_ejecucion, comercio, motivo FROM ejecuciones
    WHERE estado = 'parcial' AND motivo LIKE 'Faltan presentaciones comparables:%'
  ")
  for (i in seq_len(nrow(pendientes))) {
    id <- pendientes$id_ejecucion[i]
    com <- pendientes$comercio[i]
    presentes <- dbGetQuery(con, "
      SELECT DISTINCT id_producto FROM v_observaciones
      WHERE id_ejecucion = ? AND comercio = ? AND comparable = 1
    ", params = list(id, com))$id_producto
    faltan <- faltantes_comparables(presentes)
    if (length(faltan$productos) > 0) next

    nota <- paste0(
      "Presentación no observada: ", paste(faltan$presentaciones, collapse = ", "),
      ". El producto sigue cubierto por otra presentación."
    )
    dbExecute(con, "UPDATE ejecuciones SET estado = 'completa', motivo = ? WHERE id_ejecucion = ? AND comercio = ?",
              params = list(nota, id, com))
    dbExecute(con, "
      UPDATE observaciones_rechazadas SET motivo = 'presentacion_no_observada', detalle = ?
      WHERE id_ejecucion = ? AND comercio = ? AND motivo = 'cobertura_comparables'
    ", params = list(nota, id, com))
    registrar_correccion(
      con, "ejecuciones", paste(id, com, sep = "|"), "estado", "parcial", "completa",
      paste0(
        "La regla exige los 8 productos comparables y todos están. ", pendientes$motivo[i],
        " es otra presentación de un producto cubierto; el comercio no la listó ese día."
      )
    )
  }
}

# Aplica todas las correcciones en una transacción; volver a ejecutarla no repite registros
aplicar_correcciones <- function(path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  dbWithTransaction(con, {
    corregir_ejecucion_cafam_11oct(con)
    registrar_correcciones_reglas(con)
    reevaluar_cobertura_presentaciones(con)
  })
  invisible(path)
}

# Deja la base lista para la aplicación: esquema, disponibilidad, capa analítica y correcciones
preparar_base <- function(path = DB_PATH) {
  if (!file.exists(path)) stop("No está la base comparador_precios.sqlite en el directorio de la aplicación.")
  migrar_esquema(path)
  completar_disponibilidad(path)
  reconstruir_capa_analitica(path)
  aplicar_correcciones(path)
  invisible(path)
}

##### 6. COBERTURA DE LOS PRODUCTOS COMPARABLES

# Presentaciones y productos (familias) comparables que no están entre los observados
faltantes_comparables <- function(presentes) {
  catalogo <- catalogo_comparables()
  cubiertos <- filter(catalogo, id_producto %in% presentes)
  list(
    presentaciones = setdiff(catalogo$id_producto, presentes),
    productos = setdiff(unique(catalogo$familia), cubiertos$familia)
  )
}

# Presentaciones y productos comparables que faltan en un comercio y una ejecución
cobertura_comparables <- function(path, id_ejecucion, comercio) {
  presentes <- consultar("
    SELECT DISTINCT id_producto
    FROM v_observaciones
    WHERE id_ejecucion = ? AND comercio = ? AND comparable = 1
  ", params = list(id_ejecucion, comercio), path = path)$id_producto
  faltantes_comparables(presentes)
}

# Anota en observaciones_rechazadas un aviso de cobertura de la ejecución
anotar_cobertura <- function(path, id_ejecucion, comercio, motivo_rechazo, detalle) {
  ejecutar("
    INSERT INTO observaciones_rechazadas
      (id_ejecucion, comercio, enlace, fecha_extraccion, motivo, detalle, fecha_registro)
    VALUES (?, ?, NULL, NULL, ?, ?, ?)
  ", params = list(
    id_ejecucion, comercio, motivo_rechazo, detalle,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S-05:00")
  ), path = path)
}

# Si falta uno de los 8 productos, la ejecución del comercio queda parcial. Si solo falta una
# presentación de un producto cubierto por otra (P07/P08, P09/P10), se anota sin cambiar el estado
verificar_cobertura <- function(path, id_ejecucion, comercio) {
  faltan <- cobertura_comparables(path, id_ejecucion, comercio)
  if (length(faltan$productos) > 0) {
    motivo <- paste0("Faltan productos comparables: ", paste(faltan$productos, collapse = ", "))
    ejecutar("
      UPDATE ejecuciones
      SET estado = CASE WHEN estado = 'fallida' THEN estado ELSE 'parcial' END,
          motivo = ?
      WHERE id_ejecucion = ? AND comercio = ?
    ", params = list(motivo, id_ejecucion, comercio), path = path)
    anotar_cobertura(path, id_ejecucion, comercio, "cobertura_comparables", motivo)
    return(list(ok = FALSE, motivo = motivo))
  }
  if (length(faltan$presentaciones) > 0) {
    nota <- paste0(
      "Presentación no observada: ", paste(faltan$presentaciones, collapse = ", "),
      ". El producto sigue cubierto por otra presentación."
    )
    ejecutar("UPDATE ejecuciones SET motivo = ? WHERE id_ejecucion = ? AND comercio = ?",
             params = list(nota, id_ejecucion, comercio), path = path)
    anotar_cobertura(path, id_ejecucion, comercio, "presentacion_no_observada", nota)
    return(list(ok = TRUE, motivo = nota))
  }
  list(ok = TRUE, motivo = NA_character_)
}

##### 7. CONSULTAS PARA LA APLICACIÓN

# Condición WHERE con los filtros del panel lateral; los valores van como parámetros
clausula_filtro <- function(con, id_ejecucion, comercios = character(), subcategorias = character(),
                            marcas = character(), pmin = NULL, pmax = NULL,
                            solo_promo = FALSE, solo_comparables = FALSE, busqueda = "") {
  partes <- list(
    glue_sql("o.id_ejecucion = {id_ejecucion}", .con = con),
    glue_sql("o.motivo_descarte IS NULL", .con = con)
  )
  if (length(comercios) > 0) {
    partes <- c(partes, list(glue_sql("o.comercio IN ({comercios*})", .con = con)))
  }
  if (length(subcategorias) > 0) {
    partes <- c(partes, list(glue_sql("o.subcategoria IN ({subcategorias*})", .con = con)))
  }
  if (length(marcas) > 0) {
    partes <- c(partes, list(glue_sql("o.marca_std IN ({marcas*})", .con = con)))
  }
  if (is.numeric(pmin) && is.numeric(pmax) && length(pmin) == 1 && length(pmax) == 1 &&
      is.finite(pmin) && is.finite(pmax)) {
    if (pmin <= 0) {
      partes <- c(partes, list(glue_sql(
        "(o.precio_num BETWEEN {pmin} AND {pmax} OR o.precio_num IS NULL)", .con = con
      )))
    } else {
      partes <- c(partes, list(glue_sql("o.precio_num BETWEEN {pmin} AND {pmax}", .con = con)))
    }
  }
  if (isTRUE(solo_promo)) partes <- c(partes, list(glue_sql("o.promocion = 1", .con = con)))
  if (isTRUE(solo_comparables)) partes <- c(partes, list(glue_sql("o.comparable = 1", .con = con)))
  if (nzchar(busqueda)) {
    patron <- paste0("%", estandarizar(busqueda), "%")
    partes <- c(partes, list(glue_sql(
      "(o.nombre_std LIKE {patron} OR UPPER(COALESCE(o.n_producto, '')) LIKE {patron})",
      .con = con
    )))
  }
  SQL(paste(partes, collapse = " AND "))
}

# Valida la búsqueda y devuelve la conexión con la condición de los filtros
con_filtros <- function(filtros, path = DB_PATH) {
  texto <- validar_texto_busqueda(filtros$busqueda)
  if (!isTRUE(texto$ok)) stop(texto$mensaje)
  con <- abrir_conexion(path)
  list(
    con = con,
    where = clausula_filtro(
      con,
      id_ejecucion = filtros$id_ejecucion,
      comercios = filtros$comercios,
      subcategorias = filtros$subcategorias,
      marcas = filtros$marcas,
      pmin = filtros$pmin,
      pmax = filtros$pmax,
      solo_promo = filtros$solo_promo,
      solo_comparables = filtros$solo_comparables,
      busqueda = texto$valor
    )
  )
}

# Valores posibles de cada filtro: ejecuciones, comercios, subcategorías, marcas y precio máximo
opciones_filtros <- function(path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  ejecuciones <- dbGetQuery(con, "
    SELECT id_ejecucion,
           MIN(fecha_inicio) AS fecha_inicio,
           SUM(estado = 'fallida') AS fallidas,
           COUNT(DISTINCT comercio) AS comercios
    FROM ejecuciones
    GROUP BY id_ejecucion
    ORDER BY id_ejecucion DESC
  ")
  list(
    ejecuciones = ejecuciones,
    comercios = dbGetQuery(con, "SELECT DISTINCT comercio FROM ejecuciones ORDER BY comercio")$comercio,
    subcategorias = dbGetQuery(con, "
      SELECT DISTINCT subcategoria FROM anuncios
      WHERE motivo_descarte IS NULL AND subcategoria IS NOT NULL
      ORDER BY subcategoria
    ")$subcategoria,
    marcas = dbGetQuery(con, "
      SELECT DISTINCT marca_std FROM anuncios
      WHERE motivo_descarte IS NULL AND marca_std IS NOT NULL AND marca_std != ''
      ORDER BY marca_std
    ")$marca_std,
    precio_max = dbGetQuery(con, "
      SELECT COALESCE(MAX(precio_num), 1000) AS maximo
      FROM historico_productos
    ")$maximo[[1]],
    productos = dbGetQuery(con, "
      SELECT id_producto, nombre_corto, familia, unidad, presentacion
      FROM productos_comparables
      ORDER BY id_producto
    ")
  )
}

# Tabla de productos con los filtros activos: una fila por anuncio
productos_filtrados <- function(filtros, path = DB_PATH) {
  ctx <- con_filtros(filtros, path)
  on.exit(dbDisconnect(ctx$con), add = TRUE)
  sql <- glue_sql("
    WITH base AS (
      SELECT o.*,
             ROW_NUMBER() OVER (
               PARTITION BY o.comercio, o.enlace
               ORDER BY o.fecha_extraccion DESC, o.id_observacion DESC
             ) AS rn
      FROM v_observaciones o
      WHERE {ctx$where}
    )
    SELECT b.comercio,
           b.n_producto AS nombre,
           b.marca,
           COALESCE(
             p.presentacion,
             CASE
               WHEN b.cantidad IS NOT NULL AND b.unidad IS NOT NULL
               THEN printf('%g ', b.cantidad) || b.unidad
             END
           ) AS presentacion,
           b.precio_num AS precio,
           CASE
             WHEN p.contenido > 0 AND b.precio_num > 0 THEN b.precio_num / p.contenido
             WHEN b.cantidad > 0 AND b.precio_num > 0 THEN b.precio_num / b.cantidad
           END AS precio_unitario,
           COALESCE(p.unidad, b.unidad) AS unidad,
           b.promocion,
           b.disponibilidad,
           b.fecha_extraccion,
           b.enlace,
           b.subcategoria,
           b.id_producto,
           b.id_ejecucion
    FROM base b
    LEFT JOIN productos_comparables p ON p.id_producto = b.id_producto
    WHERE b.rn = 1
    ORDER BY b.comercio, b.n_producto
  ", .con = ctx$con)
  dbGetQuery(ctx$con, sql)
}

# Indicadores del resumen, calculados en SQL para la ejecución y los filtros elegidos
indicadores <- function(filtros, path = DB_PATH) {
  ctx <- con_filtros(filtros, path)
  on.exit(dbDisconnect(ctx$con), add = TRUE)
  con <- ctx$con
  where <- ctx$where
  id <- filtros$id_ejecucion

  conteos <- dbGetQuery(con, glue_sql("
    WITH base AS (
      SELECT o.comercio, o.enlace, o.precio_num, o.promocion,
             ROW_NUMBER() OVER (
               PARTITION BY o.comercio, o.enlace
               ORDER BY o.fecha_extraccion DESC, o.id_observacion DESC
             ) AS rn
      FROM v_observaciones o
      WHERE {where}
    )
    SELECT
      SUM(CASE WHEN rn = 1 THEN 1 ELSE 0 END) AS productos,
      COUNT(*) AS observaciones
    FROM base
  ", .con = con))

  promocion <- dbGetQuery(con, glue_sql("
    WITH base AS (
      SELECT o.promocion, o.precio_num,
             ROW_NUMBER() OVER (
               PARTITION BY o.comercio, o.enlace
               ORDER BY o.fecha_extraccion DESC, o.id_observacion DESC
             ) AS rn
      FROM v_observaciones o
      WHERE {where} AND o.precio_num IS NOT NULL
    )
    SELECT ROUND(100.0 * AVG(promocion), 1) AS pct_promocion,
           COUNT(*) AS con_precio
    FROM base
    WHERE rn = 1
  ", .con = con))

  mediana <- dbGetQuery(con, glue_sql("
    WITH base AS (
      SELECT o.precio_num,
             ROW_NUMBER() OVER (
               PARTITION BY o.comercio, o.enlace
               ORDER BY o.fecha_extraccion DESC, o.id_observacion DESC
             ) AS rn
      FROM v_observaciones o
      WHERE {where} AND o.precio_num IS NOT NULL
    ),
    ord AS (
      SELECT precio_num,
             ROW_NUMBER() OVER (ORDER BY precio_num) AS rn_precio,
             COUNT(*) OVER () AS n
      FROM base
      WHERE rn = 1
    )
    SELECT AVG(precio_num) AS mediana
    FROM ord
    WHERE rn_precio IN ((n + 1) / 2, (n + 2) / 2)
  ", .con = con))

  ahorro <- dbGetQuery(con, glue_sql("
    WITH precios AS (
      SELECT c.id_producto, c.nombre_corto, c.comercio, c.precio
      FROM v_comparables c
      WHERE c.id_ejecucion = {id}
        AND c.precio IS NOT NULL
        AND ({comercios_sql})
    ),
    rango AS (
      SELECT id_producto, nombre_corto, MIN(precio) AS minimo, MAX(precio) AS maximo,
             COUNT(DISTINCT comercio) AS comercios
      FROM precios
      GROUP BY id_producto, nombre_corto
      HAVING comercios >= 2
    )
    SELECT nombre_corto, minimo, maximo,
           maximo - minimo AS ahorro,
           ROUND(100.0 * (maximo - minimo) / maximo, 1) AS ahorro_pct
    FROM rango
    ORDER BY ahorro DESC
    LIMIT 1
  ", comercios_sql = sql_comercios(con, filtros$comercios), id = id, .con = con))

  cambios <- dbGetQuery(con, glue_sql("
    SELECT COUNT(*) AS n
    FROM (
      SELECT c.comercio, c.enlace
      FROM v_cambios_precio c
      WHERE c.id_ejecucion = {id}
        AND c.ejecucion_anterior IS NOT NULL
        AND c.ejecucion_anterior <> c.id_ejecucion
        AND c.tipo IN ('subio', 'bajo')
        AND ({comercios_sql})
      GROUP BY c.comercio, c.enlace
    )
  ", comercios_sql = sql_comercios(con, filtros$comercios, "c.comercio"), id = id, .con = con))

  meta <- dbGetQuery(con, glue_sql("
    SELECT id_ejecucion,
           MIN(fecha_inicio) AS fecha_inicio,
           MAX(fecha_fin) AS fecha_fin,
           GROUP_CONCAT(CASE WHEN estado <> 'completa' THEN comercio END) AS parciales
    FROM ejecuciones
    WHERE id_ejecucion = {id}
    GROUP BY id_ejecucion
  ", .con = con))

  list(
    productos = o_valor(conteos$productos, 0L),
    observaciones = o_valor(conteos$observaciones, 0L),
    pct_promocion = promocion$pct_promocion[[1]],
    mediana = mediana$mediana[[1]],
    ahorro_maximo = if (nrow(ahorro) == 0) NULL else ahorro,
    cambios = o_valor(cambios$n, 0L),
    meta = meta
  )
}

# Condición de comercio; sin selección, todos
sql_comercios <- function(con, comercios, columna = "comercio") {
  if (length(comercios) == 0) return(SQL("1 = 1"))
  glue_sql(paste0(columna, " IN ({comercios*})"), .con = con)
}

# Primer valor de un resultado, o el reemplazo si viene vacío
o_valor <- function(x, reemplazo = NA) {
  if (length(x) == 0 || is.null(x) || all(is.na(x))) reemplazo else x[[1]]
}

# Mínimo, cuartiles, mediana y máximo del precio por comercio
distribucion_precios <- function(filtros, path = DB_PATH) {
  ctx <- con_filtros(filtros, path)
  on.exit(dbDisconnect(ctx$con), add = TRUE)
  dbGetQuery(ctx$con, glue_sql("
    WITH base AS (
      SELECT o.comercio, o.precio_num,
             ROW_NUMBER() OVER (
               PARTITION BY o.comercio, o.enlace
               ORDER BY o.fecha_extraccion DESC, o.id_observacion DESC
             ) AS rn
      FROM v_observaciones o
      WHERE {ctx$where} AND o.precio_num IS NOT NULL
    ),
    ord AS (
      SELECT comercio, precio_num AS precio,
             ROW_NUMBER() OVER (PARTITION BY comercio ORDER BY precio_num) AS rn_precio,
             COUNT(*) OVER (PARTITION BY comercio) AS n
      FROM base
      WHERE rn = 1
    )
    SELECT comercio,
           MIN(precio) AS minimo,
           AVG(CASE WHEN rn_precio IN ((n + 1) / 4, (n + 2) / 4) THEN precio END) AS q1,
           AVG(CASE WHEN rn_precio IN ((n + 1) / 2, (n + 2) / 2) THEN precio END) AS mediana,
           AVG(CASE WHEN rn_precio IN ((3 * n + 1) / 4, (3 * n + 2) / 4) THEN precio END) AS q3,
           MAX(precio) AS maximo,
           MAX(n) AS productos
    FROM ord
    GROUP BY comercio
    ORDER BY comercio
  ", .con = ctx$con))
}

# Ahorro (COP y %) entre el mayor y el menor precio de cada presentación comparable
ahorro_por_presentacion <- function(id_ejecucion, comercios = character(), path = DB_PATH) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, glue_sql("
    WITH precios AS (
      SELECT id_producto, nombre_corto, comercio, precio
      FROM v_comparables
      WHERE id_ejecucion = {id_ejecucion}
        AND precio IS NOT NULL
        AND ({comercios_sql})
    )
    SELECT nombre_corto,
           MIN(precio) AS minimo,
           MAX(precio) AS maximo,
           MAX(precio) - MIN(precio) AS ahorro,
           ROUND(100.0 * (MAX(precio) - MIN(precio)) / MAX(precio), 1) AS ahorro_pct,
           COUNT(DISTINCT comercio) AS comercios
    FROM precios
    GROUP BY id_producto, nombre_corto
    HAVING comercios >= 2
    ORDER BY ahorro DESC
  ", comercios_sql = sql_comercios(con, comercios), .con = con))
}

# Precio de una presentación comparable en cada ejecución y comercio
evolucion_precio <- function(id_producto, path = DB_PATH) {
  consultar("
    SELECT id_ejecucion, fecha_extraccion, comercio, precio, nombre_corto, presentacion
    FROM v_comparables
    WHERE id_producto = ? AND precio IS NOT NULL
    ORDER BY fecha_extraccion, comercio
  ", params = list(id_producto), path = path)
}

# Precio por unidad de contenido de los tamaños de un mismo producto
precio_unitario_familia <- function(familia, id_ejecucion, path = DB_PATH) {
  consultar("
    SELECT comercio, nombre_corto, presentacion, unidad, contenido, precio, precio_unitario
    FROM v_comparables
    WHERE familia = ? AND id_ejecucion = ? AND precio_unitario IS NOT NULL
    ORDER BY contenido, comercio
  ", params = list(familia, id_ejecucion), path = path)
}

# Compara dos ejecuciones sobre el mismo anuncio y el mismo comercio
comparar_ejecuciones <- function(id_antes, id_despues, umbral_pct = 0,
                                 comercios = character(), path = DB_PATH) {
  if (identical(id_antes, id_despues)) {
    stop("Elija dos ejecuciones distintas.")
  }
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  comercios_sql <- sql_comercios(con, comercios, "comercio")
  crudo <- dbGetQuery(con, glue_sql("
    WITH validas AS (
      SELECT h.*
      FROM historico_productos h
      JOIN anuncios a ON a.comercio = h.comercio AND a.enlace = h.enlace
      WHERE a.motivo_descarte IS NULL
    ),
    antes AS (
      SELECT comercio, enlace, n_producto, precio_num
      FROM (
        SELECT comercio, enlace, n_producto, precio_num,
               ROW_NUMBER() OVER (
                 PARTITION BY comercio, enlace
                 ORDER BY fecha_extraccion DESC, id_observacion DESC
               ) AS rn
        FROM validas
        WHERE id_ejecucion = {id_antes} AND ({comercios_sql})
      )
      WHERE rn = 1
    ),
    despues AS (
      SELECT comercio, enlace, n_producto, precio_num, disponibilidad
      FROM (
        SELECT comercio, enlace, n_producto, precio_num, disponibilidad,
               ROW_NUMBER() OVER (
                 PARTITION BY comercio, enlace
                 ORDER BY fecha_extraccion DESC, id_observacion DESC
               ) AS rn
        FROM validas
        WHERE id_ejecucion = {id_despues} AND ({comercios_sql})
      )
      WHERE rn = 1
    )
    SELECT
      COALESCE(d.comercio, a.comercio) AS comercio,
      COALESCE(d.enlace, a.enlace) AS enlace,
      COALESCE(d.n_producto, a.n_producto) AS n_producto,
      a.precio_num AS precio_antes,
      d.precio_num AS precio_despues,
      d.disponibilidad
    FROM antes a
    LEFT JOIN despues d ON d.comercio = a.comercio AND d.enlace = a.enlace
    UNION
    SELECT d.comercio, d.enlace, d.n_producto,
           NULL AS precio_antes, d.precio_num AS precio_despues, d.disponibilidad
    FROM despues d
    WHERE NOT EXISTS (
      SELECT 1 FROM antes a WHERE a.comercio = d.comercio AND a.enlace = d.enlace
    )
  ", .con = con))
  if (nrow(crudo) == 0) return(detectar_cambios_precio(crudo, umbral_pct))
  detectar_cambios_precio(as_tibble(crudo), umbral_pct)
}

# Precios de las presentaciones elegidas para la canasta en una ejecución
precios_canasta <- function(id_ejecucion, ids, path = DB_PATH) {
  if (length(ids) == 0) {
    return(tibble(comercio = character(), id_producto = character(), precio = numeric()))
  }
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, glue_sql("
    SELECT comercio, id_producto, precio
    FROM v_comparables
    WHERE id_ejecucion = {id_ejecucion}
      AND id_producto IN ({ids*})
  ", .con = con))
}

##### 8. RESUMEN DE UNA ACTUALIZACIÓN

# Productos recolectados, nuevos, con cambio de precio, no observados y rechazados de un comercio
resumen_carga <- function(path, id_ejecucion, comercio, estado, motivo = NA_character_,
                          recolectados = 0L) {
  con <- abrir_conexion(path)
  on.exit(dbDisconnect(con), add = TRUE)
  nuevos <- dbGetQuery(con, "
    SELECT COUNT(DISTINCT h.enlace) AS n
    FROM historico_productos h
    JOIN anuncios a ON a.comercio = h.comercio AND a.enlace = h.enlace
    WHERE h.id_ejecucion = ? AND h.comercio = ?
      AND a.motivo_descarte IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM historico_productos p
        WHERE p.comercio = h.comercio AND p.enlace = h.enlace
          AND p.id_ejecucion < h.id_ejecucion
      )
  ", params = list(id_ejecucion, comercio))$n
  cambios <- dbGetQuery(con, "
    SELECT COUNT(*) AS n
    FROM v_cambios_precio
    WHERE id_ejecucion = ? AND comercio = ? AND tipo IN ('subio', 'bajo')
  ", params = list(id_ejecucion, comercio))$n
  no_observados <- dbGetQuery(con, "
    WITH anterior AS (
      SELECT id_ejecucion
      FROM ejecuciones
      WHERE comercio = ? AND id_ejecucion < ?
      ORDER BY id_ejecucion DESC
      LIMIT 1
    )
    SELECT COUNT(DISTINCT h.enlace) AS n
    FROM historico_productos h
    JOIN anuncios a ON a.comercio = h.comercio AND a.enlace = h.enlace
    WHERE h.comercio = ?
      AND h.id_ejecucion = (SELECT id_ejecucion FROM anterior)
      AND a.motivo_descarte IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM historico_productos a
        WHERE a.comercio = h.comercio AND a.enlace = h.enlace
          AND a.id_ejecucion = ?
      )
  ", params = list(comercio, id_ejecucion, comercio, id_ejecucion))$n
  rechazados <- dbGetQuery(con, "
    SELECT COUNT(*) AS n
    FROM observaciones_rechazadas
    WHERE id_ejecucion = ? AND comercio = ?
  ", params = list(id_ejecucion, comercio))$n

  tibble(
    comercio = comercio,
    estado = estado,
    productos_recolectados = as.integer(recolectados),
    productos_nuevos = as.integer(o_valor(nuevos, 0)),
    cambios_precio = as.integer(o_valor(cambios, 0)),
    no_observados = as.integer(o_valor(no_observados, 0)),
    rechazados = as.integer(o_valor(rechazados, 0)),
    motivo = motivo
  )
}
