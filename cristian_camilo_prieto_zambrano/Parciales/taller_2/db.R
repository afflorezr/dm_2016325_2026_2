# =============================================================================
# db.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
# Categoría: Nutrición clínica
#
# Capa de acceso a datos: todo el SQL del proyecto está en este archivo.
#   1. crear_base()              abre (o crea) la base en la versión actual
#   2. migrar_base()             lleva una base del Taller 1 a la versión actual
#   3. registrar_correcciones()  única vía para cambiar un dato ya insertado
#   4. insertar_lote()           escribe una ejecución validada (y sus rechazos)
#      aplicar_correspondencia(), verificar_correspondencia()
#   5. crear_vistas()            vistas SQL que usa la aplicación
#
# scraper.R, la aplicación y las pruebas cargan este archivo, así que todos
# usan exactamente la misma definición de la base.
# =============================================================================

library(DBI)
library(RSQLite)

# Versión de la estructura, guardada en PRAGMA user_version:
#   0  base del Taller 1 (sin versión)
#   2  Taller 2: correcciones, rechazos, disponibilidad, contenido total, índices
#   3  Taller 2: presentación (contenido, unidad, unidades) en cada observación
VERSION_ESQUEMA <- 3L

# -----------------------------------------------------------------------------
# 1. Abrir o crear la base
# -----------------------------------------------------------------------------

# Tablas del Taller 1, sin cambios. Se crean solo si no existen: en la base
# entregada en el Taller 1 ya están y no se tocan.
ESQUEMA_T1 <- c(
  "CREATE TABLE IF NOT EXISTS comercios (
     id_comercio TEXT PRIMARY KEY,
     nombre      TEXT NOT NULL,
     url_base    TEXT NOT NULL)",
  "CREATE TABLE IF NOT EXISTS productos (
     id_producto      TEXT PRIMARY KEY,
     nombre_std       TEXT NOT NULL,
     marca_std        TEXT NOT NULL,
     subcategoria_std TEXT,
     variante         TEXT,
     contenido        REAL NOT NULL,
     unidad           TEXT NOT NULL,
     n_unidades       INTEGER NOT NULL)",
  "CREATE TABLE IF NOT EXISTS ejecuciones (
     id_ejecucion INTEGER PRIMARY KEY AUTOINCREMENT,
     corrida      TEXT NOT NULL,
     id_comercio  TEXT NOT NULL REFERENCES comercios(id_comercio),
     inicio       TEXT NOT NULL,
     fin          TEXT,
     n_registros  INTEGER NOT NULL,
     total_sitio  INTEGER,
     estado       TEXT NOT NULL CHECK (estado IN ('completa','parcial','fallida')),
     modo         TEXT NOT NULL CHECK (modo IN ('en_linea','sin_conexion')))",
  "CREATE TABLE IF NOT EXISTS anuncios (
     id_anuncio       INTEGER PRIMARY KEY AUTOINCREMENT,
     id_comercio      TEXT NOT NULL REFERENCES comercios(id_comercio),
     sku              TEXT NOT NULL,
     seccion          TEXT,
     ean              TEXT,
     nombre           TEXT,
     marca            TEXT,
     subcategoria     TEXT,
     texto_original   TEXT,
     url              TEXT,
     contenido        REAL,
     unidad           TEXT,
     n_unidades       INTEGER,
     marca_std        TEXT,
     subcategoria_std TEXT,
     es_paquete       INTEGER NOT NULL DEFAULT 0,
     excluido         INTEGER NOT NULL DEFAULT 0,
     motivo_exclusion TEXT,
     id_producto      TEXT REFERENCES productos(id_producto),
     comparable       INTEGER NOT NULL DEFAULT 0,
     UNIQUE (id_comercio, sku))",
  "CREATE TABLE IF NOT EXISTS observaciones (
     id_obs              INTEGER PRIMARY KEY AUTOINCREMENT,
     id_anuncio          INTEGER NOT NULL REFERENCES anuncios(id_anuncio),
     id_ejecucion        INTEGER NOT NULL REFERENCES ejecuciones(id_ejecucion),
     precio              REAL,
     precio_lista        REAL,
     precio_club         REAL,
     promocion           INTEGER,
     disponible          INTEGER,
     fecha_hora_consulta TEXT NOT NULL,
     UNIQUE (id_anuncio, fecha_hora_consulta))"
)

# Ajustes de cada conexión: claves foráneas activas y espera de hasta 10 s si
# otra conexión está escribiendo (la actualización corre en otro proceso
# mientras la aplicación sigue leyendo), en lugar de fallar con
# "database is locked".
configurar_conexion <- function(con) {
  dbExecute(con, "PRAGMA foreign_keys = ON")
  dbExecute(con, "PRAGMA busy_timeout = 10000")
  invisible(con)
}

# Abre la base, crea lo que falte y la migra a la versión actual.
# Devuelve la conexión; quien la abre es responsable de cerrarla.
crear_base <- function(db = "comparador_precios.sqlite") {
  con <- dbConnect(SQLite(), db)
  configurar_conexion(con)
  for (s in ESQUEMA_T1) dbExecute(con, s)
  dbExecute(con, "INSERT OR IGNORE INTO comercios VALUES
    ('locatel',   'Locatel',    'https://www.locatelcolombia.com'),
    ('cruzverde', 'Cruz Verde', 'https://www.cruzverde.com.co'),
    ('farmatodo', 'Farmatodo',  'https://www.farmatodo.com.co')")
  migrar_base(con)
  crear_vistas(con)
  con
}

# -----------------------------------------------------------------------------
# 2. Migración Taller 1 -> Taller 2
#
# La base avanza versión por versión (0 -> 2 -> 3). Cada paso corre en su
# propia transacción y fija la versión al final: si falla, la base queda en la
# versión anterior, intacta. Correr migrar_base() otra vez no hace nada.
# Ningún paso borra ni modifica datos existentes; solo agrega tablas,
# columnas e índices y completa las columnas nuevas.
# -----------------------------------------------------------------------------

columna_existe <- function(con, tabla, columna) {
  # table_xinfo incluye las columnas generadas, que table_info no muestra
  columna %in% dbGetQuery(con, sprintf("PRAGMA table_xinfo(%s)", tabla))$name
}

agregar_columna <- function(con, tabla, columna, definicion) {
  if (!columna_existe(con, tabla, columna)) {
    dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s %s", tabla, columna, definicion))
  }
}

# Contenido total y unidad normalizada (sección 3.6). Se definen como columnas
# generadas: SQLite las calcula a partir de contenido, unidad y n_unidades, así
# que no pueden quedar desactualizadas si esos campos se corrigen.
#   - Con contenido conocido: contenido x unidades, en g o mL.
#   - Sin contenido pero con varias unidades (paquetes cuyo tamaño por unidad
#     no publica el sitio): número de unidades, en "unidad".
#   - En otro caso: NULL. Nunca se completa un dato que no se extrajo.
SQL_CONTENIDO_TOTAL <- "REAL GENERATED ALWAYS AS (
  CASE WHEN contenido IS NOT NULL AND unidad IS NOT NULL
         THEN contenido * COALESCE(n_unidades, 1)
       WHEN n_unidades > 1 THEN n_unidades
  END) VIRTUAL"
SQL_UNIDAD_NORM <- "TEXT GENERATED ALWAYS AS (
  CASE WHEN contenido IS NOT NULL AND unidad IS NOT NULL THEN unidad
       WHEN n_unidades > 1 THEN 'unidad'
  END) VIRTUAL"

# Disponibilidad según el sitio (sección 3.5). Se deriva de "disponible" (0/1),
# que es lo que entrega el scraper. El tercer estado, "no observado", no es una
# observación: lo calcula la vista v_disponibilidad.
SQL_DISPONIBILIDAD <- "TEXT GENERATED ALWAYS AS (
  CASE disponible WHEN 1 THEN 'disponible' WHEN 0 THEN 'agotado' END) VIRTUAL"

migrar_base <- function(con) {
  version <- dbGetQuery(con, "PRAGMA user_version")$user_version
  if (version >= VERSION_ESQUEMA) return(invisible(FALSE))
  if (version < 2) dbWithTransaction(con, { migrar_a_v2(con); fijar_version(con, 2L) })
  if (version < 3) dbWithTransaction(con, { migrar_a_v3(con); fijar_version(con, 3L) })
  invisible(TRUE)
}

fijar_version <- function(con, v) dbExecute(con, sprintf("PRAGMA user_version = %d", v))

# --- Versión 2 ---------------------------------------------------------------
migrar_a_v2 <- function(con) {
    # --- Tablas nuevas -------------------------------------------------------

    # Registro de cambios a datos ya insertados (sección 3.2). Ningún dato se
    # modifica sin dejar aquí el valor anterior, el nuevo y el motivo.
    dbExecute(con, "
      CREATE TABLE IF NOT EXISTS correcciones (
        id_correccion  INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha          TEXT NOT NULL,
        tabla          TEXT NOT NULL,
        id_registro    INTEGER NOT NULL,
        campo          TEXT NOT NULL,
        valor_anterior TEXT,
        valor_nuevo    TEXT,
        motivo         TEXT NOT NULL)")

    # Observaciones que no superaron la validación (sección 3.4). No entran a
    # observaciones; aquí queda qué se rechazó, en qué ejecución y por qué.
    dbExecute(con, "
      CREATE TABLE IF NOT EXISTS rechazos (
        id_rechazo          INTEGER PRIMARY KEY AUTOINCREMENT,
        id_ejecucion        INTEGER NOT NULL REFERENCES ejecuciones(id_ejecucion),
        id_comercio         TEXT NOT NULL REFERENCES comercios(id_comercio),
        sku                 TEXT,
        regla               TEXT NOT NULL,
        detalle             TEXT,
        fecha_hora_consulta TEXT,
        registro            TEXT)")   # la fila rechazada completa, en JSON

    # --- Columnas nuevas -----------------------------------------------------

    # ejecuciones: momento de la captura (puede ser distinto del de la carga si
    # la corrida se reprocesa desde raw/) y motivo de un estado parcial o fallido
    agregar_columna(con, "ejecuciones", "captura_inicio", "TEXT")
    agregar_columna(con, "ejecuciones", "captura_fin",    "TEXT")
    agregar_columna(con, "ejecuciones", "motivo",         "TEXT")

    # observaciones: disponibilidad y descarte (no se borra una observación mala)
    agregar_columna(con, "observaciones", "disponibilidad",  SQL_DISPONIBILIDAD)
    agregar_columna(con, "observaciones", "descartada",      "INTEGER NOT NULL DEFAULT 0")
    agregar_columna(con, "observaciones", "motivo_descarte", "TEXT")

    # anuncios y productos: contenido total y unidad normalizada
    agregar_columna(con, "anuncios",  "contenido_total", SQL_CONTENIDO_TOTAL)
    agregar_columna(con, "anuncios",  "unidad_norm",     SQL_UNIDAD_NORM)
    agregar_columna(con, "productos", "contenido_total", SQL_CONTENIDO_TOTAL)
    agregar_columna(con, "productos", "unidad_norm",     SQL_UNIDAD_NORM)

    # --- Completar columnas nuevas en los datos existentes ---------------------

    # Momento de captura de las ejecuciones ya cargadas: primera y última hora
    # de consulta de sus observaciones (que vienen del nombre de la copia cruda)
    dbExecute(con, "
      UPDATE ejecuciones
      SET captura_inicio = (SELECT MIN(fecha_hora_consulta) FROM observaciones o
                            WHERE o.id_ejecucion = ejecuciones.id_ejecucion),
          captura_fin    = (SELECT MAX(fecha_hora_consulta) FROM observaciones o
                            WHERE o.id_ejecucion = ejecuciones.id_ejecucion)
      WHERE captura_inicio IS NULL")

    # --- Unicidad e índices ----------------------------------------------------

    # Una observación por anuncio y ejecución. Se suma a la restricción del
    # Taller 1, UNIQUE(id_anuncio, fecha_hora_consulta). SQLite no permite
    # agregar UNIQUE con ALTER TABLE; un índice único cumple la misma función.
    dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS uq_obs_anuncio_ejecucion
                    ON observaciones (id_anuncio, id_ejecucion)")

    # Columnas que usan los filtros y las uniones de la aplicación
    indices <- c(
      "ix_obs_ejecucion      ON observaciones (id_ejecucion)",
      "ix_obs_fecha          ON observaciones (fecha_hora_consulta)",
      "ix_anuncios_comercio  ON anuncios (id_comercio)",
      "ix_anuncios_producto  ON anuncios (id_producto)",
      "ix_anuncios_subcat    ON anuncios (subcategoria_std)",
      "ix_anuncios_marca     ON anuncios (marca_std)",
      "ix_anuncios_filtro    ON anuncios (excluido, comparable)",
      "ix_ejecuciones_corrida ON ejecuciones (corrida, id_comercio)",
      "ix_rechazos_ejecucion ON rechazos (id_ejecucion)"
    )
    for (ix in indices) dbExecute(con, paste("CREATE INDEX IF NOT EXISTS", ix))
}

# --- Versión 3 ---------------------------------------------------------------
# La presentación (contenido, unidad y número de unidades) se guarda también en
# cada observación, tal como se leyó en esa consulta. En anuncios queda la
# presentación más reciente, que sirve para los filtros; el precio unitario y
# los cambios de precio usan la de la observación.
#
# Motivo: un comercio puede reutilizar el SKU para otra presentación (Locatel,
# SKU 27148: "Prowhey Renal Crónico X 400G" en octubre y "X 900G" en
# noviembre). Con la presentación solo en anuncios, la observación de octubre
# pasaba a figurar como de 900 g.
migrar_a_v3 <- function(con) {
  agregar_columna(con, "observaciones", "contenido",       "REAL")
  agregar_columna(con, "observaciones", "unidad",          "TEXT")
  agregar_columna(con, "observaciones", "n_unidades",      "INTEGER")
  agregar_columna(con, "observaciones", "contenido_total", SQL_CONTENIDO_TOTAL)
  agregar_columna(con, "observaciones", "unidad_norm",     SQL_UNIDAD_NORM)

  # Observaciones ya cargadas: se completan con la presentación de su anuncio...
  dbExecute(con, "
    UPDATE observaciones SET
      contenido  = (SELECT a.contenido  FROM anuncios a WHERE a.id_anuncio = observaciones.id_anuncio),
      unidad     = (SELECT a.unidad     FROM anuncios a WHERE a.id_anuncio = observaciones.id_anuncio),
      n_unidades = (SELECT a.n_unidades FROM anuncios a WHERE a.id_anuncio = observaciones.id_anuncio)")

  # ...salvo las anteriores a un recálculo de la presentación del anuncio: esas
  # toman el valor anterior, registrado en correcciones por insertar_lote()
  # ("Recalculado al cargar la ejecución N: ..."). Se recorren de la ejecución
  # más reciente a la más antigua, para que cada observación quede con el
  # valor vigente en su momento. Las correcciones de errores de extracción
  # (correcciones_t1.R) no entran aquí: corrigen también la historia.
  recalculos <- dbGetQuery(con, "
    SELECT id_registro, campo, valor_anterior, motivo FROM correcciones
    WHERE tabla = 'anuncios' AND campo IN ('contenido', 'unidad', 'n_unidades')
      AND motivo LIKE 'Recalculado al cargar la ejecución %'")
  if (nrow(recalculos) > 0) {
    recalculos$ejecucion <- as.integer(sub("^Recalculado al cargar la ejecución (\\d+):.*$", "\\1",
                                           recalculos$motivo))
    recalculos <- recalculos[order(-recalculos$ejecucion), ]
    for (i in seq_len(nrow(recalculos))) {
      r <- recalculos[i, ]
      valor <- switch(r$campo,
                      contenido  = as.numeric(r$valor_anterior),
                      n_unidades = as.integer(r$valor_anterior),
                      r$valor_anterior)
      dbExecute(con, sprintf("UPDATE observaciones SET %s = ?
                              WHERE id_anuncio = ? AND id_ejecucion < ?", r$campo),
                params = list(valor, r$id_registro, r$ejecucion))
    }
  }
}

# -----------------------------------------------------------------------------
# 3. Correcciones registradas (sección 3.2)
#
# Única vía para cambiar un dato ya insertado: actualiza el campo y deja en
# correcciones el valor anterior, el nuevo y el motivo, en una sola
# transacción. Si el valor ya es el nuevo, no hace nada; así un script de
# correcciones puede correrse varias veces sin duplicar registros.
# -----------------------------------------------------------------------------

# Tablas corregibles y su llave primaria (todas enteras, como id_registro)
TABLAS_CORREGIBLES <- c(anuncios      = "id_anuncio",
                        observaciones = "id_obs",
                        ejecuciones   = "id_ejecucion")

ahora_iso <- function() {
  x <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", x)
}

# cambios: data frame con columnas tabla, id_registro, campo, valor_nuevo, motivo.
# Devuelve las correcciones aplicadas (las que cambiaron algo).
registrar_correcciones <- function(con, cambios) {
  requeridas <- c("tabla", "id_registro", "campo", "valor_nuevo", "motivo")
  faltan <- setdiff(requeridas, names(cambios))
  if (length(faltan) > 0) stop("Faltan columnas en 'cambios': ", paste(faltan, collapse = ", "))

  # Los nombres de tabla y campo van dentro del texto SQL (no pueden ser
  # parámetros), así que se aceptan solo si existen en el esquema. Las columnas
  # generadas no aparecen en table_info y por tanto no se pueden corregir:
  # se corrige el dato del que dependen.
  for (i in seq_len(nrow(cambios))) {
    tabla <- cambios$tabla[i]
    if (!tabla %in% names(TABLAS_CORREGIBLES)) stop("Tabla no corregible: ", tabla)
    campos <- dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tabla))$name
    if (!cambios$campo[i] %in% setdiff(campos, TABLAS_CORREGIBLES[[tabla]])) {
      stop("Campo no corregible: ", tabla, ".", cambios$campo[i])
    }
    if (is.na(cambios$motivo[i]) || !nzchar(cambios$motivo[i])) {
      stop("Toda corrección necesita un motivo (fila ", i, ").")
    }
  }

  fecha <- ahora_iso()
  dbWithTransaction(con, {
    aplicadas <- list()
    for (i in seq_len(nrow(cambios))) {
      tabla <- cambios$tabla[i]; campo <- cambios$campo[i]
      pk    <- TABLAS_CORREGIBLES[[tabla]]
      id    <- cambios$id_registro[i]
      nuevo <- cambios$valor_nuevo[i]

      actual <- dbGetQuery(con, sprintf("SELECT %s AS v FROM %s WHERE %s = ?", campo, tabla, pk),
                           params = list(id))
      if (nrow(actual) == 0) stop("No existe ", tabla, " con ", pk, " = ", id)
      anterior <- actual$v[[1]]

      # Sin cambio real: no se toca nada ni se registra
      if (identical(as.character(anterior), as.character(nuevo))) next

      dbExecute(con, sprintf("UPDATE %s SET %s = ? WHERE %s = ?", tabla, campo, pk),
                params = list(nuevo, id))
      dbExecute(con, "
        INSERT INTO correcciones (fecha, tabla, id_registro, campo,
                                  valor_anterior, valor_nuevo, motivo)
        VALUES (?, ?, ?, ?, ?, ?, ?)",
        params = list(fecha, tabla, id, campo,
                      if (is.null(anterior) || is.na(anterior)) NA_character_ else as.character(anterior),
                      if (is.na(nuevo)) NA_character_ else as.character(nuevo),
                      cambios$motivo[i]))
      aplicadas[[length(aplicadas) + 1]] <- cbind(cambios[i, ], valor_anterior = as.character(anterior))
    }
    if (length(aplicadas) == 0) cambios[0, ] else do.call(rbind, aplicadas)
  })
}

# -----------------------------------------------------------------------------
# 4. Escritura de una ejecución
#
# Movidas desde scraper.R (sección 10 del Taller 1): así todo el SQL del
# proyecto está en este archivo. ejecutar_recoleccion() las llama.
# -----------------------------------------------------------------------------

# Campos de anuncios que se derivan del nombre con las reglas de limpieza
CAMPOS_DERIVADOS <- c("contenido", "unidad", "n_unidades", "marca_std",
                      "subcategoria_std", "es_paquete", "excluido", "motivo_exclusion")

# Escribe en una sola transacción lo que dejó la validación de un comercio:
#   aceptadas   -> anuncios (nuevos o actualizados) y observaciones
#   rechazadas  -> rechazos
# Si algo falla, no queda nada escrito de ese comercio.
#
# Un anuncio que ya existe actualiza sus datos descriptivos (los publica el
# sitio en cada consulta), pero conserva id_anuncio, id_producto y comparable.
# Si cambia un campo derivado (contenido, subcategoría, exclusión...), el
# cambio queda en correcciones: nada se modifica en silencio.
#
# Devuelve el número de observaciones nuevas, de rechazos y de campos
# recalculados.
insertar_lote <- function(con, aceptadas, rechazadas, id_ejecucion) {
  dbWithTransaction(con, escribir_lote(con, aceptadas, rechazadas, id_ejecucion))
}

# Lo mismo sin abrir transacción: la usa guardar_ejecucion(), que escribe la
# ejecución y sus datos dentro de una sola transacción.
escribir_lote <- function(con, aceptadas, rechazadas, id_ejecucion) {
  resultado <- list(nuevas = 0L, rechazos = 0L, recalculados = 0L)
  if (nrow(aceptadas) == 0 && nrow(rechazadas) == 0) return(resultado)

  {
    if (nrow(aceptadas) > 0) {
      # 1) Anuncios
      anuncios <- data.frame(
        id_comercio = aceptadas$comercio, sku = aceptadas$sku,
        seccion = aceptadas$seccion, ean = aceptadas$ean, nombre = aceptadas$nombre,
        marca = aceptadas$marca, subcategoria = aceptadas$subcategoria,
        texto_original = aceptadas$texto_original, url = aceptadas$url,
        contenido = aceptadas$contenido, unidad = aceptadas$unidad,
        n_unidades = aceptadas$n_unidades, marca_std = aceptadas$marca_std,
        subcategoria_std = aceptadas$subcategoria_std, es_paquete = aceptadas$es_paquete,
        excluido = aceptadas$excluido, motivo_exclusion = aceptadas$motivo_exclusion
      )
      dbWriteTable(con, "tmp_anuncios", anuncios, temporary = TRUE, overwrite = TRUE)

      # 1a) Cambios en campos derivados de anuncios existentes -> correcciones
      motivo <- sprintf(paste("Recalculado al cargar la ejecución %d: cambió el nombre",
                              "publicado por el sitio o las reglas de limpieza."), id_ejecucion)
      fecha <- ahora_iso()
      for (campo in CAMPOS_DERIVADOS) {
        resultado$recalculados <- resultado$recalculados + dbExecute(con, sprintf("
          INSERT INTO correcciones (fecha, tabla, id_registro, campo,
                                    valor_anterior, valor_nuevo, motivo)
          SELECT ?, 'anuncios', a.id_anuncio, '%1$s',
                 CAST(a.%1$s AS TEXT), CAST(t.%1$s AS TEXT), ?
          FROM anuncios a
          JOIN tmp_anuncios t ON a.id_comercio = t.id_comercio AND a.sku = t.sku
          WHERE a.%1$s IS NOT t.%1$s", campo), params = list(fecha, motivo))
      }

      # 1b) Inserción o actualización
      dbExecute(con, "
        INSERT INTO anuncios (id_comercio, sku, seccion, ean, nombre, marca,
          subcategoria, texto_original, url, contenido, unidad, n_unidades,
          marca_std, subcategoria_std, es_paquete, excluido, motivo_exclusion)
        SELECT * FROM tmp_anuncios WHERE true
        ON CONFLICT (id_comercio, sku) DO UPDATE SET
          seccion = excluded.seccion, ean = excluded.ean, nombre = excluded.nombre,
          marca = excluded.marca, subcategoria = excluded.subcategoria,
          texto_original = excluded.texto_original, url = excluded.url,
          contenido = excluded.contenido, unidad = excluded.unidad,
          n_unidades = excluded.n_unidades, marca_std = excluded.marca_std,
          subcategoria_std = excluded.subcategoria_std, es_paquete = excluded.es_paquete,
          excluido = excluded.excluido, motivo_exclusion = excluded.motivo_exclusion")

      # 2) Observaciones: las restricciones de unicidad impiden duplicarlas
      obs <- data.frame(
        id_comercio = aceptadas$comercio, sku = aceptadas$sku,
        precio = aceptadas$precio, precio_lista = aceptadas$precio_lista,
        precio_club = aceptadas$precio_club, promocion = aceptadas$promocion,
        disponible = aceptadas$disponible,
        fecha_hora_consulta = aceptadas$fecha_hora_consulta,
        contenido = aceptadas$contenido, unidad = aceptadas$unidad,
        n_unidades = aceptadas$n_unidades
      )
      dbWriteTable(con, "tmp_obs", obs, temporary = TRUE, overwrite = TRUE)
      resultado$nuevas <- dbExecute(con, "
        INSERT OR IGNORE INTO observaciones (id_anuncio, id_ejecucion, precio,
          precio_lista, precio_club, promocion, disponible, fecha_hora_consulta,
          contenido, unidad, n_unidades)
        SELECT a.id_anuncio, ?, t.precio, t.precio_lista, t.precio_club,
               t.promocion, t.disponible, t.fecha_hora_consulta,
               t.contenido, t.unidad, t.n_unidades
        FROM tmp_obs t
        JOIN anuncios a ON a.id_comercio = t.id_comercio AND a.sku = t.sku",
        params = list(id_ejecucion))
      dbExecute(con, "DROP TABLE tmp_anuncios")
      dbExecute(con, "DROP TABLE tmp_obs")
    }

    # 3) Rechazos de la validación. Como en observaciones, volver a insertar
    # el mismo lote no los duplica: se omite un rechazo que ya esté guardado
    # para esa ejecución (mismo comercio, SKU, regla y fila). La consulta se
    # evalúa contra la tabla antes de insertar, así que dos rechazos idénticos
    # dentro de un mismo lote sí se conservan.
    if (nrow(rechazadas) > 0) {
      dbWriteTable(con, "tmp_rech", as.data.frame(rechazadas), temporary = TRUE, overwrite = TRUE)
      resultado$rechazos <- dbExecute(con, "
        INSERT INTO rechazos (id_ejecucion, id_comercio, sku, regla, detalle,
                              fecha_hora_consulta, registro)
        SELECT ?, t.comercio, t.sku, t.regla, t.detalle, t.fecha_hora_consulta, t.registro
        FROM tmp_rech t
        WHERE NOT EXISTS (
          SELECT 1 FROM rechazos r
          WHERE r.id_ejecucion = ? AND r.id_comercio = t.comercio AND r.sku IS t.sku
            AND r.regla = t.regla AND r.registro IS t.registro)",
        params = list(id_ejecucion, id_ejecucion))
      dbExecute(con, "DROP TABLE tmp_rech")
    }
  }
  resultado
}

# Registra la ejecución de un comercio y escribe sus datos en UNA transacción:
# si cualquier paso falla, no queda ni la ejecución ni parte de sus datos.
#   ejecucion: lista con corrida, id_comercio, inicio, n_registros, total_sitio,
#              estado, modo, captura_inicio, captura_fin, motivo
# Devuelve el id de la ejecución y los conteos de escribir_lote().
guardar_ejecucion <- function(con, ejecucion, aceptadas = NULL, rechazadas = NULL) {
  valor <- function(x) if (is.null(x) || length(x) == 0) NA else x
  dbWithTransaction(con, {
    dbExecute(con,
      "INSERT INTO ejecuciones (corrida, id_comercio, inicio, n_registros, total_sitio,
                                estado, modo, captura_inicio, captura_fin, motivo)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      params = unname(lapply(ejecucion[c("corrida", "id_comercio", "inicio", "n_registros", "total_sitio",
                                         "estado", "modo", "captura_inicio", "captura_fin", "motivo")], valor)))
    id <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
    res <- if (is.null(aceptadas)) list(nuevas = 0L, rechazos = 0L, recalculados = 0L)
           else escribir_lote(con, aceptadas, rechazadas, id)
    dbExecute(con, "UPDATE ejecuciones SET fin = ? WHERE id_ejecucion = ?",
              params = list(ahora_iso(), id))
    c(list(id_ejecucion = id), res)
  })
}

# Ejecución ya cargada de una corrida y un comercio (con observaciones), o NULL
ejecucion_cargada <- function(con, corrida, id_comercio) {
  r <- dbGetQuery(con, "
    SELECT e.id_ejecucion FROM ejecuciones e
    WHERE e.corrida = ? AND e.id_comercio = ?
      AND EXISTS (SELECT 1 FROM observaciones o WHERE o.id_ejecucion = e.id_ejecucion)
    ORDER BY e.id_ejecucion LIMIT 1", params = list(corrida, id_comercio))
  if (nrow(r) == 0) NULL else r$id_ejecucion
}

# Observaciones guardadas de una ejecución (para compararlas con raw/)
observaciones_de_ejecucion <- function(con, id_ejecucion) {
  dbGetQuery(con, "
    SELECT a.sku, o.precio, o.fecha_hora_consulta, o.descartada
    FROM observaciones o JOIN anuncios a USING (id_anuncio)
    WHERE o.id_ejecucion = ?", params = list(id_ejecucion))
}

# Resumen de una ejecución frente a la anterior del mismo comercio (solo
# productos de la categoría): nuevos, subieron, bajaron, no observados.
# Sin ejecución anterior, los conteos quedan en NA.
resumen_ejecucion <- function(con, id_ejecucion) {
  r <- dbGetQuery(con, "
    SELECT (SELECT COUNT(*) FROM v_observaciones WHERE id_ejecucion = ?) AS en_categoria,
           COUNT(c.id_anuncio) AS comparados,
           SUM(c.tipo_cambio = 'nuevo')        AS nuevos,
           SUM(c.tipo_cambio = 'subió')        AS subieron,
           SUM(c.tipo_cambio = 'bajó')         AS bajaron,
           SUM(c.tipo_cambio = 'no observado') AS no_observados,
           SUM(c.tipo_cambio = 'cambió la presentación') AS cambio_presentacion,
           MAX(c.fecha_anterior) AS fecha_anterior
    FROM v_cambios_precio c WHERE c.id_ejecucion_actual = ?",
    params = list(id_ejecucion, id_ejecucion))
  if (r$comparados == 0) r[c("nuevos", "subieron", "bajaron", "no_observados", "cambio_presentacion")] <- NA
  r
}

# Registra los productos comparables y su correspondencia (correspondencia.csv).
# Devuelve las filas del archivo que no encontraron su anuncio en la base.
aplicar_correspondencia <- function(con, archivo = "correspondencia.csv") {
  corr <- readr::read_csv(archivo, col_types = readr::cols(.default = "c"),
                          locale = readr::locale(encoding = "UTF-8"))
  productos <- unique(corr[, c("id_producto", "nombre_std", "marca_std", "subcategoria_std",
                               "variante", "contenido", "unidad", "n_unidades")])
  productos$contenido  <- as.numeric(productos$contenido)
  productos$n_unidades <- as.integer(productos$n_unidades)

  dbWithTransaction(con, {
    dbWriteTable(con, "tmp_prod", as.data.frame(productos), temporary = TRUE, overwrite = TRUE)
    # Se nombran las columnas: productos tiene columnas generadas al final
    dbExecute(con, "INSERT OR REPLACE INTO productos (id_producto, nombre_std, marca_std,
                      subcategoria_std, variante, contenido, unidad, n_unidades)
                    SELECT id_producto, nombre_std, marca_std, subcategoria_std,
                           variante, contenido, unidad, n_unidades FROM tmp_prod")
    dbWriteTable(con, "tmp_corr", as.data.frame(corr[, c("id_producto", "id_comercio", "sku")]),
                 temporary = TRUE, overwrite = TRUE)
    # Se reinicia la marca para que quitar una fila del archivo también la quite de la base
    dbExecute(con, "UPDATE anuncios SET comparable = 0, id_producto = NULL")
    dbExecute(con, "
      UPDATE anuncios
      SET id_producto = (SELECT c.id_producto FROM tmp_corr c
                         WHERE c.id_comercio = anuncios.id_comercio
                           AND c.sku = anuncios.sku),
          comparable = 1
      WHERE EXISTS (SELECT 1 FROM tmp_corr c
                    WHERE c.id_comercio = anuncios.id_comercio
                      AND c.sku = anuncios.sku)")
    sin_anuncio <- dbGetQuery(con, "
      SELECT c.* FROM tmp_corr c
      LEFT JOIN anuncios a ON a.id_comercio = c.id_comercio AND a.sku = c.sku
      WHERE a.id_anuncio IS NULL")
    dbExecute(con, "DROP TABLE tmp_prod")
    dbExecute(con, "DROP TABLE tmp_corr")
    sin_anuncio
  })
}

# Revisa que cada anuncio comparable coincida con su producto en
# contenido, unidad, número de unidades y marca.
verificar_correspondencia <- function(con) {
  dbGetQuery(con, "
    SELECT p.id_producto, a.id_comercio, a.sku, a.nombre,
           p.marca_std AS marca_esperada, a.marca_std AS marca_anuncio,
           p.contenido AS contenido_esperado, a.contenido AS contenido_anuncio,
           p.unidad AS unidad_esperada, a.unidad AS unidad_anuncio,
           p.n_unidades AS unidades_esperadas, a.n_unidades AS unidades_anuncio,
           CASE WHEN a.contenido = p.contenido AND a.unidad = p.unidad
                 AND a.n_unidades = p.n_unidades AND a.marca_std = p.marca_std
                THEN 1 ELSE 0 END AS coincide
    FROM anuncios a
    JOIN productos p ON p.id_producto = a.id_producto
    WHERE a.comparable = 1
    ORDER BY p.id_producto, a.id_comercio")
}

# -----------------------------------------------------------------------------
# 5. Vistas que usa la aplicación
#
# Las vistas no guardan datos: se recrean cada vez que se abre la base con
# crear_base(), así siempre corresponden a este código.
#
# Criterios comunes:
#   - Solo observaciones válidas (descartada = 0) de anuncios de la categoría
#     (excluido = 0). Las demás siguen en las tablas, por trazabilidad.
#   - La presentación y el precio unitario son los de cada observación.
#   - Ejecución vigente: la más reciente de cada comercio que no sea fallida.
#     Es por comercio: si un comercio falla, se sigue mostrando su último
#     dato válido, con su fecha.
#   - Precio unitario = precio / contenido total, en COP por g, por mL o por
#     unidad; la unidad va siempre en unidad_norm y nunca se mezclan.
# -----------------------------------------------------------------------------
VISTAS <- c(

  # Ejecuciones con su orden dentro del comercio (solo las no fallidas) y la vigente
  v_ejecuciones = "
    CREATE VIEW v_ejecuciones AS
    WITH ordenadas AS (
      SELECT id_ejecucion,
             ROW_NUMBER() OVER (PARTITION BY id_comercio ORDER BY captura_inicio, id_ejecucion) AS orden,
             COUNT(*)     OVER (PARTITION BY id_comercio) AS total
      FROM ejecuciones WHERE estado <> 'fallida')
    SELECT e.id_ejecucion, e.corrida, e.id_comercio, c.nombre AS comercio,
           e.estado, e.modo, e.captura_inicio, e.captura_fin,
           substr(e.captura_inicio, 1, 10) AS fecha,
           e.n_registros, e.total_sitio, e.motivo,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = e.id_ejecucion AND o.descartada = 0) AS n_observaciones,
           (SELECT COUNT(*) FROM rechazos r WHERE r.id_ejecucion = e.id_ejecucion) AS n_rechazos,
           od.orden,
           COALESCE(od.orden = od.total, 0) AS vigente
    FROM ejecuciones e
    JOIN comercios c ON c.id_comercio = e.id_comercio
    LEFT JOIN ordenadas od ON od.id_ejecucion = e.id_ejecucion",

  # Base de las demás: una fila por observación válida de la categoría
  v_observaciones = "
    CREATE VIEW v_observaciones AS
    SELECT o.id_obs, o.id_ejecucion, e.corrida, e.orden AS orden_ejecucion, e.vigente,
           a.id_anuncio, a.id_comercio, e.comercio, a.sku, a.nombre,
           a.marca_std AS marca, a.subcategoria_std AS subcategoria,
           a.comparable, a.id_producto, a.es_paquete,
           o.contenido_total, o.unidad_norm,
           o.precio, o.precio_lista, o.promocion, o.disponibilidad,
           CASE WHEN o.precio IS NOT NULL AND o.contenido_total > 0
                THEN o.precio / o.contenido_total END AS precio_unitario,
           o.fecha_hora_consulta, substr(o.fecha_hora_consulta, 1, 10) AS fecha,
           a.url, a.texto_original
    FROM observaciones o
    JOIN anuncios a       ON a.id_anuncio   = o.id_anuncio
    JOIN v_ejecuciones e  ON e.id_ejecucion = o.id_ejecucion
    WHERE o.descartada = 0 AND a.excluido = 0",

  # El dato más reciente de cada anuncio: solo la ejecución vigente de cada comercio
  v_ultimo_precio = "
    CREATE VIEW v_ultimo_precio AS
    SELECT * FROM v_observaciones WHERE vigente = 1",

  # Productos comparables: precio de cada comercio frente a los otros, por corrida.
  # Solo cuentan los comercios con precio y con la misma presentación del producto
  # (si el comercio cambió la presentación, la fila queda con coincide = 0).
  # Empates: todos los comercios con el precio mínimo quedan como más baratos.
  v_comparables = "
    CREATE VIEW v_comparables AS
    WITH base AS (
      SELECT v.id_producto, p.nombre_std AS producto, v.id_comercio, v.comercio,
             v.id_ejecucion, v.corrida, v.fecha, v.vigente, v.id_anuncio, v.sku,
             v.precio, v.precio_unitario, v.contenido_total, v.unidad_norm,
             v.promocion, v.disponibilidad, v.url,
             (v.contenido_total = p.contenido_total AND v.unidad_norm = p.unidad_norm) AS coincide
      FROM v_observaciones v JOIN productos p ON p.id_producto = v.id_producto
      WHERE v.comparable = 1),
    validos AS (
      SELECT b.*, CASE WHEN b.coincide = 1 THEN b.precio END AS precio_comparable FROM base b),
    extremos AS (
      SELECT x.*,
             MIN(precio_comparable)   OVER w AS precio_min,
             MAX(precio_comparable)   OVER w AS precio_max,
             COUNT(precio_comparable) OVER w AS comercios_con_precio
      FROM validos x
      WINDOW w AS (PARTITION BY id_producto, corrida))
    SELECT id_producto, producto, id_comercio, comercio, id_ejecucion, corrida, fecha,
           vigente, id_anuncio, sku, precio, precio_unitario, contenido_total, unidad_norm,
           promocion, disponibilidad, url, coincide,
           precio_min, precio_max, comercios_con_precio,
           CASE WHEN precio_comparable IS NULL THEN NULL
                WHEN precio_comparable = precio_min THEN 1 ELSE 0 END AS es_mas_barato,
           SUM(CASE WHEN precio_comparable = precio_min THEN 1 ELSE 0 END)
             OVER (PARTITION BY id_producto, corrida) AS n_mas_baratos,
           precio_comparable - precio_min AS sobrecosto,
           precio_max - precio_min AS ahorro_maximo
    FROM extremos",

  # Cambios entre ejecuciones consecutivas (no fallidas) del mismo comercio,
  # sobre el mismo anuncio. Un cambio de presentación no se cuenta como cambio
  # de precio.
  v_cambios_precio = "
    CREATE VIEW v_cambios_precio AS
    WITH pares AS (
      SELECT e.id_comercio, e.comercio,
             p.id_ejecucion AS id_ejecucion_anterior, p.corrida AS corrida_anterior,
             p.fecha AS fecha_anterior,
             e.id_ejecucion AS id_ejecucion_actual, e.corrida AS corrida_actual,
             e.fecha AS fecha_actual, e.vigente
      FROM v_ejecuciones e
      JOIN v_ejecuciones p ON p.id_comercio = e.id_comercio AND p.orden = e.orden - 1),
    filas AS (
      SELECT DISTINCT pr.*, v.id_anuncio
      FROM pares pr
      JOIN v_observaciones v
        ON v.id_ejecucion IN (pr.id_ejecucion_anterior, pr.id_ejecucion_actual))
    SELECT f.id_comercio, f.comercio,
           f.id_ejecucion_anterior, f.corrida_anterior, f.fecha_anterior,
           f.id_ejecucion_actual, f.corrida_actual, f.fecha_actual, f.vigente,
           f.id_anuncio, a.sku, a.nombre, a.marca_std AS marca,
           a.subcategoria_std AS subcategoria, a.comparable, a.id_producto,
           an.precio AS precio_anterior, ac.precio AS precio_actual,
           an.contenido_total AS contenido_anterior, ac.contenido_total AS contenido_actual,
           COALESCE(ac.unidad_norm, an.unidad_norm) AS unidad_norm,
           CASE WHEN an.id_obs IS NULL THEN 'nuevo'
                WHEN ac.id_obs IS NULL THEN 'no observado'
                WHEN an.contenido_total IS NOT ac.contenido_total
                  OR an.unidad_norm IS NOT ac.unidad_norm THEN 'cambió la presentación'
                WHEN an.precio IS NULL OR ac.precio IS NULL THEN 'sin precio'
                WHEN ac.precio > an.precio THEN 'subió'
                WHEN ac.precio < an.precio THEN 'bajó'
                ELSE 'igual' END AS tipo_cambio,
           CASE WHEN an.contenido_total IS ac.contenido_total AND an.unidad_norm IS ac.unidad_norm
                THEN ac.precio - an.precio END AS diferencia,
           CASE WHEN an.contenido_total IS ac.contenido_total AND an.unidad_norm IS ac.unidad_norm
                     AND an.precio > 0
                THEN round(100.0 * (ac.precio - an.precio) / an.precio, 2) END AS variacion_pct
    FROM filas f
    JOIN anuncios a ON a.id_anuncio = f.id_anuncio
    LEFT JOIN v_observaciones an ON an.id_ejecucion = f.id_ejecucion_anterior AND an.id_anuncio = f.id_anuncio
    LEFT JOIN v_observaciones ac ON ac.id_ejecucion = f.id_ejecucion_actual   AND ac.id_anuncio = f.id_anuncio",

  # Disponibilidad en cada ejecución de todo anuncio ya visto en ese comercio:
  # disponible o agotado (según el sitio) o no_observado (no apareció en la
  # ejecución). Un anuncio no observado no se interpreta como agotado: se
  # muestra su último precio conocido y la fecha en que se vio.
  v_disponibilidad = "
    CREATE VIEW v_disponibilidad AS
    WITH vistos AS (
      SELECT e.id_ejecucion, e.corrida, e.id_comercio, e.comercio, e.estado AS estado_ejecucion,
             e.fecha, e.orden, e.vigente, v.id_anuncio,
             MAX(v.orden_ejecucion) AS orden_ultima_vez
      FROM v_ejecuciones e
      JOIN v_observaciones v ON v.id_comercio = e.id_comercio AND v.orden_ejecucion <= e.orden
      GROUP BY e.id_ejecucion, v.id_anuncio),
    ultimo AS (
      SELECT x.id_ejecucion, x.id_anuncio,
             (SELECT o.precio FROM v_observaciones o
               WHERE o.id_anuncio = x.id_anuncio AND o.orden_ejecucion <= x.orden
                 AND o.precio IS NOT NULL
               ORDER BY o.orden_ejecucion DESC LIMIT 1) AS ultimo_precio,
             (SELECT o.fecha FROM v_observaciones o
               WHERE o.id_anuncio = x.id_anuncio AND o.orden_ejecucion <= x.orden
                 AND o.precio IS NOT NULL
               ORDER BY o.orden_ejecucion DESC LIMIT 1) AS fecha_ultimo_precio
      FROM vistos x)
    SELECT x.id_ejecucion, x.corrida, x.id_comercio, x.comercio, x.estado_ejecucion,
           x.fecha, x.vigente, x.id_anuncio, a.sku, a.nombre,
           a.subcategoria_std AS subcategoria, a.comparable, a.id_producto,
           CASE WHEN v.id_obs IS NULL THEN 'no_observado'
                ELSE COALESCE(v.disponibilidad, 'sin_informacion') END AS estado,
           u.ultimo_precio, u.fecha_ultimo_precio
    FROM vistos x
    JOIN anuncios a ON a.id_anuncio = x.id_anuncio
    JOIN ultimo u   ON u.id_ejecucion = x.id_ejecucion AND u.id_anuncio = x.id_anuncio
    LEFT JOIN v_observaciones v ON v.id_ejecucion = x.id_ejecucion AND v.id_anuncio = x.id_anuncio"
)

# Recrea todas las vistas en una transacción (se borran en orden inverso, porque
# unas dependen de otras)
crear_vistas <- function(con) {
  dbWithTransaction(con, {
    for (v in rev(names(VISTAS))) dbExecute(con, paste("DROP VIEW IF EXISTS", v))
    for (v in names(VISTAS)) dbExecute(con, VISTAS[[v]])
  })
  invisible(names(VISTAS))
}

# =============================================================================
# 6. Consultas para la aplicación (Módulo 3)
#
# La interfaz no contiene SQL: llama a estas funciones, que reciben la conexión
# y los filtros como argumentos y devuelven tablas. Filtros, indicadores y
# agregaciones (medianas y cuartiles incluidos) se calculan en SQL; nunca se
# lee una tabla completa para filtrarla en R.
#
# Seguridad (Módulo 4): todo valor del usuario va como parámetro (?). En el
# texto SQL solo se insertan marcadores y nombres de columnas definidos en este
# archivo. El texto de búsqueda se valida antes de consultar.
#
# Filtros: una lista con estos elementos (todos opcionales; ver filtros_por_defecto())
#   comercios          ids de comercio; vacío = todos
#   subcategorias      subcategorías estandarizadas; vacío = todas
#   marcas             marcas estandarizadas; vacío = todas
#   precio_min/max     rango de precio en COP; NA = sin límite
#   corrida            "vigente" (ejecución más reciente de cada comercio) o el
#                      identificador de una corrida
#   solo_promociones   TRUE/FALSE
#   solo_comparables   TRUE/FALSE
#   busqueda           palabras a buscar en el nombre o el texto del anuncio
# =============================================================================

# Abre la base para la aplicación: deja la estructura y las vistas al día y
# devuelve un pool de conexiones. La aplicación lo cierra con pool::poolClose()
# al terminar (onStop).
conectar_app <- function(db = "comparador_precios.sqlite") {
  if (!file.exists(db)) stop("No se encontró la base ", db)
  con <- crear_base(db)
  dbDisconnect(con)
  pool::dbPool(RSQLite::SQLite(), dbname = db, onCreate = configurar_conexion)
}

ADVERTENCIA_CANASTA <- paste(
  "El resultado no incluye costos de envío, compras mínimas ni las condiciones",
  "de las promociones. Los precios son los del momento de la consulta.")

filtros_por_defecto <- function() {
  list(comercios = character(), subcategorias = character(), marcas = character(),
       precio_min = NA_real_, precio_max = NA_real_, corrida = "vigente",
       solo_promociones = FALSE, solo_comparables = FALSE, busqueda = "")
}

completar_filtros <- function(f) {
  d <- filtros_por_defecto()
  for (k in intersect(names(f), names(d))) if (!is.null(f[[k]])) d[[k]] <- f[[k]]
  d
}

# Error propio para que la interfaz distinga una entrada inválida de una falla
error_entrada <- function(mensaje) {
  e <- simpleError(mensaje)
  class(e) <- c("entrada_invalida", class(e))
  stop(e)
}

# -----------------------------------------------------------------------------
# Búsqueda por palabras
# Máximo 60 caracteres; letras (con tildes, ñ y ü), números, espacios, punto,
# guion y "+". Como % y _ no se admiten, no hay comodines de LIKE que escapar.
# No distingue mayúsculas ni tildes, y todas las palabras deben aparecer.
# -----------------------------------------------------------------------------
# La validación y la normalización no dependen de la configuración regional del
# equipo o del servidor: se trabaja en UTF-8 y con expresiones Unicode.
BUSQUEDA_MAX        <- 60L
BUSQUEDA_PERMITIDOS <- "^[\\p{L}\\p{N} .+-]*$"   # letras (con tildes), números, espacio, . + -

TILDES <- c("á" = "a", "é" = "e", "í" = "i", "ó" = "o", "ú" = "u", "ü" = "u", "ñ" = "n",
            "Á" = "a", "É" = "e", "Í" = "i", "Ó" = "o", "Ú" = "u", "Ü" = "u", "Ñ" = "n")

normalizar_texto <- function(x) {
  x <- enc2utf8(x)
  for (k in names(TILDES)) x <- gsub(enc2utf8(k), TILDES[[k]], x, fixed = TRUE, useBytes = TRUE)
  tolower(x)
}

validar_busqueda <- function(texto) {
  if (is.null(texto) || length(texto) == 0 || all(is.na(texto))) texto <- ""
  if (length(texto) != 1 || !is.character(texto)) {
    return(list(ok = FALSE, mensaje = "La búsqueda debe ser un solo texto.", terminos = character()))
  }
  texto <- trimws(texto)
  if (nchar(texto) > BUSQUEDA_MAX) {
    return(list(ok = FALSE, terminos = character(),
                mensaje = sprintf("La búsqueda admite máximo %d caracteres.", BUSQUEDA_MAX)))
  }
  if (!grepl(BUSQUEDA_PERMITIDOS, enc2utf8(texto), perl = TRUE)) {
    return(list(ok = FALSE, terminos = character(),
                mensaje = "La búsqueda solo admite letras, números, espacios y los signos . + -"))
  }
  terminos <- unique(strsplit(normalizar_texto(texto), "\\s+")[[1]])
  list(ok = TRUE, mensaje = NULL, terminos = terminos[nzchar(terminos)])
}

# Expresión SQL que pasa una columna a minúsculas y sin tildes
# (lower() de SQLite solo convierte letras sin tilde)
sql_normalizado <- function(col) {
  expr <- sprintf("lower(%s)", col)
  for (k in names(TILDES)) expr <- sprintf("replace(%s, '%s', '%s')", expr, enc2utf8(k), TILDES[[k]])
  enc2utf8(expr)
}

# -----------------------------------------------------------------------------
# Constructor del WHERE con parámetros
#   usar  qué filtros aplica la consulta
#   cols  nombre de cada columna en la tabla o vista consultada
# Devuelve list(where = "WHERE ...", params = list(...))
# -----------------------------------------------------------------------------
COLUMNAS_FILTRO <- list(comercio = "id_comercio", subcategoria = "subcategoria",
                        marca = "marca", precio = "precio", promocion = "promocion",
                        comparable = "comparable", nombre = "nombre",
                        texto = "texto_original", corrida = "corrida", vigente = "vigente")
TODOS_LOS_FILTROS <- c("tiempo", "comercio", "subcategoria", "marca", "precio",
                       "promocion", "comparable", "busqueda")

armar_filtros <- function(f, usar = TODOS_LOS_FILTROS, cols = COLUMNAS_FILTRO,
                          condiciones_extra = character()) {
  f <- completar_filtros(f)
  cols <- modifyList(COLUMNAS_FILTRO, cols)
  cond <- condiciones_extra
  params <- list()
  marcadores <- function(n) paste(rep("?", n), collapse = ", ")

  if ("tiempo" %in% usar) {
    if (identical(f$corrida, "vigente")) {
      cond <- c(cond, sprintf("%s = 1", cols$vigente))
    } else {
      if (!is.character(f$corrida) || length(f$corrida) != 1 || !grepl("^\\d{8}T\\d{6}$", f$corrida)) {
        error_entrada("La ejecución seleccionada no es válida.")
      }
      cond <- c(cond, sprintf("%s = ?", cols$corrida)); params <- c(params, list(f$corrida))
    }
  }
  en <- function(col, valores) {
    valores <- unique(as.character(valores))
    cond   <<- c(cond, sprintf("%s IN (%s)", col, marcadores(length(valores))))
    params <<- c(params, as.list(valores))
  }
  if ("comercio" %in% usar && length(f$comercios) > 0)         en(cols$comercio, f$comercios)
  if ("subcategoria" %in% usar && length(f$subcategorias) > 0) en(cols$subcategoria, f$subcategorias)
  if ("marca" %in% usar && length(f$marcas) > 0)               en(cols$marca, f$marcas)

  if ("precio" %in% usar) {
    for (lim in c("precio_min", "precio_max")) {
      v <- f[[lim]]
      if (length(v) == 1 && !is.na(v)) {
        if (!is.numeric(v) || v < 0) error_entrada("El rango de precio no es válido.")
        cond <- c(cond, sprintf("%s %s ?", cols$precio, if (lim == "precio_min") ">=" else "<="))
        params <- c(params, list(as.numeric(v)))
      }
    }
  }
  if ("promocion" %in% usar && isTRUE(f$solo_promociones))  cond <- c(cond, sprintf("%s = 1", cols$promocion))
  if ("comparable" %in% usar && isTRUE(f$solo_comparables)) cond <- c(cond, sprintf("%s = 1", cols$comparable))

  if ("busqueda" %in% usar) {
    b <- validar_busqueda(f$busqueda)
    if (!b$ok) error_entrada(b$mensaje)
    for (t in b$terminos) {
      partes <- vapply(unique(c(cols$nombre, cols$texto)),
                       function(cl) sprintf("%s LIKE ?", sql_normalizado(cl)), character(1))
      cond   <- c(cond, sprintf("(%s)", paste(partes, collapse = " OR ")))
      params <- c(params, rep(list(paste0("%", t, "%")), length(partes)))
    }
  }
  list(where = if (length(cond) > 0) paste("WHERE", paste(cond, collapse = " AND ")) else "",
       params = params)
}

consultar <- function(con, sql, params = list()) {
  if (length(params) > 0) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
}

# -----------------------------------------------------------------------------
# Medianas y cuartiles en SQL (SQLite no tiene MEDIAN). Interpolación lineal
# entre los dos valores vecinos, la misma definición de quantile() de R
# (tipo 7). base_sql debe devolver una columna precio; grupo es una columna o
# expresión de base_sql.
# -----------------------------------------------------------------------------
sql_resumen_precios <- function(base_sql, grupo) {
  sprintf("
    WITH base AS (%1$s),
    ord AS (
      SELECT %2$s AS grupo, precio AS x,
             ROW_NUMBER() OVER (PARTITION BY %2$s ORDER BY precio) AS rn,
             COUNT(*)     OVER (PARTITION BY %2$s) AS n
      FROM base WHERE precio IS NOT NULL),
    ps(p) AS (VALUES (0.25), (0.5), (0.75)),
    pos AS (SELECT DISTINCT grupo, n, p, 1 + p * (n - 1) AS h FROM ord, ps),
    cuantiles AS (
      SELECT pos.grupo, pos.p,
             lo.x + (pos.h - CAST(pos.h AS INTEGER)) * (COALESCE(hi.x, lo.x) - lo.x) AS valor
      FROM pos
      JOIN ord lo      ON lo.grupo = pos.grupo AND lo.rn = CAST(pos.h AS INTEGER)
      LEFT JOIN ord hi ON hi.grupo = pos.grupo AND hi.rn = CAST(pos.h AS INTEGER) + 1)
    SELECT o.grupo, COUNT(*) AS n, MIN(o.x) AS minimo,
           (SELECT valor FROM cuantiles c WHERE c.grupo = o.grupo AND c.p = 0.25) AS q1,
           (SELECT valor FROM cuantiles c WHERE c.grupo = o.grupo AND c.p = 0.5)  AS mediana,
           (SELECT valor FROM cuantiles c WHERE c.grupo = o.grupo AND c.p = 0.75) AS q3,
           MAX(o.x) AS maximo, AVG(o.x) AS promedio
    FROM ord o GROUP BY o.grupo ORDER BY o.grupo", base_sql, grupo)
}

# -----------------------------------------------------------------------------
# Opciones de los controles y referencias de tiempo
# -----------------------------------------------------------------------------
opciones_filtros <- function(con) {
  list(
    comercios     = dbGetQuery(con, "SELECT id_comercio, nombre FROM comercios ORDER BY nombre"),
    subcategorias = dbGetQuery(con, "SELECT DISTINCT subcategoria FROM v_observaciones
                                     WHERE subcategoria IS NOT NULL ORDER BY 1")[[1]],
    marcas        = dbGetQuery(con, "SELECT DISTINCT marca FROM v_observaciones
                                     WHERE marca IS NOT NULL AND trim(marca) <> ''
                                     ORDER BY 1")[[1]],
    precio        = dbGetQuery(con, "SELECT MIN(precio) AS minimo, MAX(precio) AS maximo
                                     FROM v_observaciones"),
    corridas      = dbGetQuery(con, "
      SELECT corrida, MIN(fecha) AS fecha, COUNT(*) AS comercios,
             SUM(estado = 'completa') AS completas
      FROM v_ejecuciones WHERE orden IS NOT NULL
      GROUP BY corrida ORDER BY corrida DESC"),
    comparables   = dbGetQuery(con, "
      SELECT id_producto, nombre_std AS producto, contenido_total, unidad_norm
      FROM productos ORDER BY id_producto")
  )
}

# Corrida con la que se comparan comercios (comparables, canasta, ahorro): la
# elegida o, en modo "vigente", la más reciente con datos de dos o más comercios.
corrida_referencia <- function(con, f = list()) {
  f <- completar_filtros(f)
  if (!identical(f$corrida, "vigente")) return(f$corrida)
  r <- dbGetQuery(con, "
    SELECT corrida FROM v_ejecuciones WHERE orden IS NOT NULL
    GROUP BY corrida HAVING COUNT(*) >= 2
    ORDER BY MAX(captura_inicio) DESC LIMIT 1")
  if (nrow(r) == 0) NA_character_ else r$corrida
}

# Inicio de la última actualización en línea, de cualquier comercio y con
# cualquier resultado (también las fallidas: un intento cuenta igual para no
# insistir contra un sitio). NA si no hay ninguna.
ultima_actualizacion_en_linea <- function(con) {
  dbGetQuery(con, "SELECT MAX(inicio) AS inicio FROM ejecuciones WHERE modo = 'en_linea'")$inicio
}

# Las dos corridas más recientes con datos de dos o más comercios (anterior, actual)
corridas_recientes <- function(con) {
  r <- dbGetQuery(con, "
    SELECT corrida FROM v_ejecuciones WHERE orden IS NOT NULL
    GROUP BY corrida HAVING COUNT(*) >= 2
    ORDER BY MAX(captura_inicio) DESC LIMIT 2")$corrida
  if (length(r) < 2) return(NULL)
  c(anterior = r[2], actual = r[1])
}

etiqueta_periodo <- function(con, f) {
  f <- completar_filtros(f)
  if (identical(f$corrida, "vigente")) return("Ejecución más reciente de cada comercio")
  fecha <- dbGetQuery(con, "SELECT MIN(fecha) AS fecha FROM v_ejecuciones WHERE corrida = ?",
                      params = list(f$corrida))$fecha
  sprintf("Corrida del %s", fecha)
}

# -----------------------------------------------------------------------------
# Tabla de productos (sección 7.5)
# -----------------------------------------------------------------------------
productos_filtrados <- function(con, f = list()) {
  w <- armar_filtros(f)
  consultar(con, paste("
    SELECT comercio, id_comercio, nombre, marca, subcategoria,
           contenido_total, unidad_norm, precio, precio_unitario, precio_lista,
           promocion, disponibilidad, fecha_hora_consulta, url,
           sku, comparable, id_producto, corrida
    FROM v_observaciones", w$where,
    "ORDER BY subcategoria, nombre, comercio"), w$params)
}

# -----------------------------------------------------------------------------
# Indicadores (sección 7.3). Cada uno con su valor o tabla, unidad y periodo.
# -----------------------------------------------------------------------------
indicadores <- function(con, f = list()) {
  f <- completar_filtros(f)
  periodo <- etiqueta_periodo(con, f)
  w_actual <- armar_filtros(f)
  w_todas  <- armar_filtros(f, usar = setdiff(TODOS_LOS_FILTROS, "tiempo"))

  productos <- consultar(con, paste("
    SELECT comercio, COUNT(*) AS productos, SUM(precio IS NOT NULL) AS con_precio
    FROM v_observaciones", w_actual$where, "GROUP BY comercio ORDER BY comercio"), w_actual$params)

  observaciones <- consultar(con, paste("
    SELECT comercio, COUNT(*) AS observaciones, COUNT(DISTINCT id_ejecucion) AS ejecuciones
    FROM v_observaciones", w_todas$where, "GROUP BY comercio ORDER BY comercio"), w_todas$params)

  w_com <- armar_filtros(f, usar = "comercio", cols = list(comercio = "e.id_comercio"))
  ultima <- consultar(con, paste("
    SELECT c.nombre AS comercio, e.corrida,
           COALESCE(substr(e.captura_inicio, 1, 10), substr(e.inicio, 1, 10)) AS fecha,
           e.estado, e.modo, e.motivo
    FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio",
    if (nzchar(w_com$where)) paste(w_com$where, "AND") else "WHERE",
    "e.id_ejecucion IN (
       SELECT id_ejecucion FROM (
         SELECT id_ejecucion, ROW_NUMBER() OVER (
                  PARTITION BY id_comercio
                  ORDER BY COALESCE(captura_inicio, inicio) DESC, id_ejecucion DESC) AS rn
         FROM ejecuciones) WHERE rn = 1)
    ORDER BY c.nombre"), w_com$params)

  promo <- consultar(con, paste("
    SELECT COUNT(*) AS productos, SUM(promocion) AS en_promocion,
           ROUND(100.0 * SUM(promocion) / COUNT(*), 1) AS porcentaje
    FROM v_observaciones", w_actual$where,
    if (nzchar(w_actual$where)) "AND precio IS NOT NULL" else "WHERE precio IS NOT NULL"),
    w_actual$params)

  base_actual <- paste("SELECT subcategoria, precio FROM v_observaciones", w_actual$where)
  mediana <- consultar(con, sql_resumen_precios(base_actual, "'Todas'"), w_actual$params)

  corrida <- corrida_referencia(con, f)
  # Mayor ahorro entre los comercios elegidos y con los demás filtros: se
  # recalcula el mínimo y el máximo solo con los precios que quedan
  ahorro <- if (is.na(corrida)) data.frame() else {
    wa <- armar_filtros(f, usar = c("comercio", "subcategoria", "marca", "busqueda"),
                        cols = list(comercio = "v.id_comercio", subcategoria = "p.subcategoria_std",
                                    marca = "p.marca_std", nombre = "p.nombre_std", texto = "p.nombre_std"),
                        condiciones_extra = c("v.corrida = ?", "v.coincide = 1", "v.precio IS NOT NULL"))
    consultar(con, paste("
      WITH c AS (
        SELECT v.id_producto, v.producto, v.comercio, v.fecha, v.precio
        FROM v_comparables v JOIN productos p ON p.id_producto = v.id_producto", wa$where, "),
      r AS (
        SELECT id_producto, producto, MIN(fecha) AS fecha, MIN(precio) AS precio_min,
               MAX(precio) AS precio_max
        FROM c GROUP BY id_producto, producto HAVING COUNT(*) >= 2),
      top AS (SELECT * FROM r ORDER BY precio_max - precio_min DESC, id_producto LIMIT 1)
      SELECT t.id_producto, t.producto, t.fecha, t.precio_max - t.precio_min AS ahorro,
             t.precio_min, t.precio_max,
             ROUND(100.0 * (t.precio_max - t.precio_min) / t.precio_max, 1) AS porcentaje,
             group_concat(CASE WHEN c.precio = t.precio_min THEN c.comercio END, ', ') AS mas_barato,
             group_concat(CASE WHEN c.precio = t.precio_max THEN c.comercio END, ', ') AS mas_caro
      FROM top t JOIN c ON c.id_producto = t.id_producto
      GROUP BY t.id_producto, t.producto, t.fecha, t.precio_min, t.precio_max"),
      c(list(corrida), wa$params))
  }

  w_cambios <- armar_filtros(f, usar = c("comercio", "subcategoria", "marca", "comparable", "busqueda"),
                             cols = list(texto = "nombre"), condiciones_extra = "vigente = 1")
  cambios <- consultar(con, paste("
    SELECT SUM(tipo_cambio = 'subió') AS subidas, SUM(tipo_cambio = 'bajó') AS bajadas,
           SUM(tipo_cambio IN ('subió', 'bajó')) AS cambios,
           MIN(fecha_anterior) AS desde, MAX(fecha_actual) AS hasta
    FROM v_cambios_precio", w_cambios$where), w_cambios$params)

  list(
    productos_por_comercio = list(
      titulo = "Productos por comercio", tabla = productos,
      unidad = "productos", periodo = periodo),
    observaciones_por_comercio = list(
      titulo = "Observaciones por comercio", tabla = observaciones,
      unidad = "observaciones", periodo = "Todas las ejecuciones"),
    ultima_ejecucion = list(
      titulo = "Última ejecución", tabla = ultima,
      unidad = NA_character_, periodo = "Última ejecución de cada comercio"),
    promocion = list(
      titulo = "Productos en promoción", valor = promo$porcentaje, tabla = promo,
      unidad = "%", periodo = periodo),
    mediana_precio = list(
      titulo = "Precio mediano", valor = mediana$mediana, tabla = mediana,
      unidad = "COP", periodo = periodo),
    ahorro_maximo = list(
      titulo = "Mayor ahorro entre comercios", valor = if (nrow(ahorro)) ahorro$ahorro else NA,
      tabla = ahorro, unidad = "COP",
      periodo = if (nrow(ahorro)) sprintf("Corrida del %s", ahorro$fecha) else NA_character_),
    cambios_precio = list(
      titulo = "Cambios de precio en la última ejecución", valor = cambios$cambios,
      tabla = cambios, unidad = "cambios",
      periodo = if (!is.na(cambios$desde)) sprintf("Del %s al %s", cambios$desde, cambios$hasta)
                else NA_character_)
  )
}

# -----------------------------------------------------------------------------
# Datos de los gráficos (sección 7.4). Los numera igual que graficos.R:
#   1. serie_precio()           aquí
#   2. matriz_comparables()     sección 7
#   3. distribucion_precios()   aquí
#   4. comparacion_tamanos()    sección 7
# -----------------------------------------------------------------------------

# 1. Evolución del precio de un producto comparable, una serie por comercio
serie_precio <- function(con, id_producto, f = list()) {
  if (!is.character(id_producto) || length(id_producto) != 1 || !grepl("^P\\d{2}$", id_producto)) {
    error_entrada("El producto seleccionado no es válido.")
  }
  w <- armar_filtros(f, usar = "comercio", condiciones_extra = "id_producto = ?")
  consultar(con, paste("
    SELECT comercio, id_comercio, corrida, fecha, precio, precio_unitario,
           contenido_total, unidad_norm, coincide, disponibilidad, promocion
    FROM v_comparables", w$where, "ORDER BY fecha, comercio"),
    c(list(id_producto), w$params))
}

# 3. Distribución de precios de la categoría por comercio (mínimo, cuartiles,
#    mediana, máximo), calculada en SQL
distribucion_precios <- function(con, f = list()) {
  w <- armar_filtros(f)
  r <- consultar(con, sql_resumen_precios(
    paste("SELECT comercio, precio FROM v_observaciones", w$where), "comercio"), w$params)
  names(r)[names(r) == "grupo"] <- "comercio"
  r
}

# -----------------------------------------------------------------------------
# Comparación de dos ejecuciones (sección 8.2)
# Mismo anuncio en el mismo comercio, entre dos corridas elegidas por el
# usuario. Solo se comparan los comercios con datos en ambas; los demás se
# informan en $omitidos. destacado = 1 si la variación supera el umbral (%).
# -----------------------------------------------------------------------------
comparar_ejecuciones <- function(con, corrida_anterior, corrida_actual,
                                 umbral_pct = 10, f = list()) {
  for (cr in c(corrida_anterior, corrida_actual)) {
    if (!is.character(cr) || length(cr) != 1 || !grepl("^\\d{8}T\\d{6}$", cr)) {
      error_entrada("Las ejecuciones seleccionadas no son válidas.")
    }
  }
  if (!is.numeric(umbral_pct) || length(umbral_pct) != 1 || is.na(umbral_pct) ||
      umbral_pct < 0 || umbral_pct > 1000) {
    error_entrada("El umbral debe ser un porcentaje entre 0 y 1000.")
  }
  w <- armar_filtros(f, usar = c("comercio", "subcategoria", "marca", "comparable", "busqueda"),
                     cols = list(comercio = "a.id_comercio", subcategoria = "a.subcategoria_std",
                                 marca = "a.marca_std", comparable = "a.comparable",
                                 nombre = "a.nombre", texto = "a.texto_original"),
                     condiciones_extra = "a.id_comercio IN (SELECT id_comercio FROM comercios_ok)")
  cte <- paste("
    WITH ant AS (SELECT * FROM v_observaciones WHERE corrida = ?),
         act AS (SELECT * FROM v_observaciones WHERE corrida = ?),
         comercios_ok AS (SELECT id_comercio FROM ant INTERSECT SELECT id_comercio FROM act),
         ids AS (SELECT id_anuncio FROM ant UNION SELECT id_anuncio FROM act),
         cmp AS (
           SELECT c.nombre AS comercio, a.id_comercio, a.id_anuncio, a.sku, a.nombre,
                  a.marca_std AS marca, a.subcategoria_std AS subcategoria,
                  a.comparable, a.id_producto, a.url,
                  an.precio AS precio_anterior, ac.precio AS precio_actual,
                  an.contenido_total AS contenido_anterior, ac.contenido_total AS contenido_actual,
                  COALESCE(ac.unidad_norm, an.unidad_norm) AS unidad_norm,
                  CASE WHEN an.id_obs IS NULL THEN 'nuevo'
                       WHEN ac.id_obs IS NULL THEN 'no observado'
                       WHEN an.contenido_total IS NOT ac.contenido_total
                         OR an.unidad_norm IS NOT ac.unidad_norm THEN 'cambió la presentación'
                       WHEN an.precio IS NULL OR ac.precio IS NULL THEN 'sin precio'
                       WHEN ac.precio > an.precio THEN 'subió'
                       WHEN ac.precio < an.precio THEN 'bajó'
                       ELSE 'igual' END AS tipo_cambio,
                  CASE WHEN an.contenido_total IS ac.contenido_total
                        AND an.unidad_norm IS ac.unidad_norm
                       THEN ac.precio - an.precio END AS diferencia,
                  CASE WHEN an.contenido_total IS ac.contenido_total
                        AND an.unidad_norm IS ac.unidad_norm AND an.precio > 0
                       THEN round(100.0 * (ac.precio - an.precio) / an.precio, 2) END AS variacion_pct
           FROM ids
           JOIN anuncios a  ON a.id_anuncio = ids.id_anuncio
           JOIN comercios c ON c.id_comercio = a.id_comercio
           LEFT JOIN ant an ON an.id_anuncio = ids.id_anuncio
           LEFT JOIN act ac ON ac.id_anuncio = ids.id_anuncio",
    w$where, ")")
  p_base <- c(list(corrida_anterior, corrida_actual), w$params)

  cambios <- consultar(con, paste(cte, "
    SELECT *, CASE WHEN abs(variacion_pct) >= ? THEN 1 ELSE 0 END AS destacado
    FROM cmp
    ORDER BY CASE tipo_cambio WHEN 'subió' THEN 1 WHEN 'bajó' THEN 2 WHEN 'nuevo' THEN 3
                              WHEN 'no observado' THEN 4 ELSE 5 END,
             abs(variacion_pct) DESC, comercio, nombre"), c(p_base, list(umbral_pct)))

  resumen <- consultar(con, paste(cte, "
    SELECT comercio, SUM(tipo_cambio = 'subió') AS subieron, SUM(tipo_cambio = 'bajó') AS bajaron,
           SUM(tipo_cambio = 'igual') AS iguales, SUM(tipo_cambio = 'nuevo') AS nuevos,
           SUM(tipo_cambio = 'no observado') AS no_observados,
           SUM(tipo_cambio = 'cambió la presentación') AS cambio_presentacion,
           SUM(abs(variacion_pct) >= ?) AS destacados
    FROM cmp GROUP BY comercio ORDER BY comercio"), c(p_base, list(umbral_pct)))

  omitidos <- consultar(con, "
    SELECT c.nombre AS comercio FROM comercios c
    WHERE c.id_comercio NOT IN (
      SELECT id_comercio FROM v_observaciones WHERE corrida = ?
      INTERSECT SELECT id_comercio FROM v_observaciones WHERE corrida = ?)
    ORDER BY c.nombre", list(corrida_anterior, corrida_actual))$comercio

  list(cambios = cambios, resumen = resumen, omitidos = omitidos,
       corrida_anterior = corrida_anterior, corrida_actual = corrida_actual,
       umbral_pct = umbral_pct)
}

# -----------------------------------------------------------------------------
# Canasta (sección 8.3)
# productos: ids de comparables (P01...); cantidades: enteros de 1 a 99.
# Con precios de una misma corrida:
#   - total por comercio, solo si el comercio tiene todos los productos con
#     precio; si falta alguno, total = NULL y se indican los faltantes;
#   - costo mínimo comprando cada producto donde es más barato (en un empate,
#     se listan todos los comercios empatados; el precio cuenta una vez);
#   - ahorro frente al mejor comercio único.
# -----------------------------------------------------------------------------
costo_canasta <- function(con, productos, cantidades, corrida = NULL) {
  if (!is.character(productos) || length(productos) < 1 || length(productos) > 20 ||
      any(!grepl("^P\\d{2}$", productos)) || anyDuplicated(productos)) {
    error_entrada("Seleccione entre 1 y 20 productos comparables, sin repetir.")
  }
  if (length(cantidades) != length(productos) || any(is.na(cantidades)) ||
      any(cantidades != round(cantidades)) || any(cantidades < 1 | cantidades > 99)) {
    error_entrada("Cada cantidad debe ser un número entero entre 1 y 99.")
  }
  if (is.null(corrida)) corrida <- corrida_referencia(con)
  if (is.na(corrida) || !grepl("^\\d{8}T\\d{6}$", corrida)) error_entrada("La ejecución no es válida.")

  valores <- paste(rep("(?, ?)", length(productos)), collapse = ", ")
  p_canasta <- as.list(c(rbind(productos, as.integer(cantidades))))
  p_canasta <- lapply(seq_along(p_canasta), function(i)
    if (i %% 2 == 0) as.integer(p_canasta[[i]]) else as.character(p_canasta[[i]]))
  cte <- sprintf("
    WITH canasta(id_producto, cantidad) AS (VALUES %s),
    precios AS (
      SELECT id_producto, id_comercio, comercio, precio FROM v_comparables
      WHERE corrida = ? AND coincide = 1 AND precio IS NOT NULL),
    comercios_corrida AS (
      SELECT DISTINCT id_comercio, comercio FROM v_comparables WHERE corrida = ?),
    por_comercio AS (
      SELECT cc.comercio, cc.id_comercio,
             COUNT(p.precio) AS productos_con_precio,
             (SELECT COUNT(*) FROM canasta) AS productos_canasta,
             CASE WHEN COUNT(p.precio) = (SELECT COUNT(*) FROM canasta)
                  THEN SUM(p.precio * k.cantidad) END AS total,
             group_concat(CASE WHEN p.precio IS NULL THEN k.id_producto END, ', ') AS faltantes
      FROM comercios_corrida cc CROSS JOIN canasta k
      LEFT JOIN precios p ON p.id_comercio = cc.id_comercio AND p.id_producto = k.id_producto
      GROUP BY cc.id_comercio, cc.comercio),
    minimos AS (
      SELECT k.id_producto, k.cantidad, MIN(p.precio) AS precio_min
      FROM canasta k LEFT JOIN precios p ON p.id_producto = k.id_producto
      GROUP BY k.id_producto, k.cantidad),
    combinado AS (
      SELECT CASE WHEN COUNT(precio_min) = COUNT(*) THEN SUM(precio_min * cantidad) END AS total
      FROM minimos)", valores)
  p_base <- c(p_canasta, list(corrida, corrida))

  por_comercio <- consultar(con, paste(cte, "
    SELECT pc.comercio, pc.id_comercio, pc.productos_con_precio, pc.productos_canasta,
           pc.total, pc.faltantes, pc.total - cb.total AS diferencia_vs_combinado
    FROM por_comercio pc CROSS JOIN combinado cb
    ORDER BY pc.total IS NULL, pc.total, pc.comercio"), p_base)

  detalle <- consultar(con, paste(cte, "
    SELECT m.id_producto, pr.nombre_std AS producto, m.cantidad, m.precio_min,
           m.precio_min * m.cantidad AS subtotal,
           (SELECT group_concat(p.comercio, ', ') FROM precios p
             WHERE p.id_producto = m.id_producto AND p.precio = m.precio_min) AS donde
    FROM minimos m JOIN productos pr ON pr.id_producto = m.id_producto
    ORDER BY m.id_producto"), p_base)

  resumen <- consultar(con, paste(cte, "
    SELECT cb.total AS total_combinado,
           (SELECT MIN(total) FROM por_comercio) AS mejor_total_un_comercio,
           (SELECT group_concat(comercio, ', ') FROM por_comercio
             WHERE total = (SELECT MIN(total) FROM por_comercio)) AS mejor_comercio,
           (SELECT MIN(total) FROM por_comercio) - cb.total AS ahorro_combinado,
           (SELECT COUNT(*) FROM por_comercio WHERE total IS NOT NULL) AS comercios_completos
    FROM combinado cb"), p_base)

  fecha <- dbGetQuery(con, "SELECT MIN(fecha) AS fecha FROM v_ejecuciones WHERE corrida = ?",
                      params = list(corrida))$fecha
  list(por_comercio = por_comercio, detalle = detalle, resumen = resumen,
       corrida = corrida, fecha = fecha, advertencia = ADVERTENCIA_CANASTA)
}

# =============================================================================
# 7. Consultas de la interfaz (Módulo 5)
# =============================================================================

# Fecha de los datos que muestra la aplicación: la captura más reciente de las
# ejecuciones vigentes, y la de cada comercio
fecha_datos <- function(con) {
  dbGetQuery(con, "
    SELECT comercio, id_comercio, fecha, captura_fin, estado
    FROM v_ejecuciones WHERE vigente = 1 ORDER BY comercio")
}

# Ejecuciones registradas, de la más reciente a la más antigua (pestaña Datos)
listar_ejecuciones <- function(con) {
  dbGetQuery(con, "
    SELECT id_ejecucion, corrida, id_comercio, comercio, fecha, estado, modo,
           n_registros, total_sitio, n_observaciones, n_rechazos, vigente, motivo
    FROM v_ejecuciones ORDER BY id_ejecucion DESC")
}

# Filtros que aplican a los productos comparables (tabla productos)
filtros_comparables <- function(f, alias_comercio) {
  armar_filtros(f, usar = c("comercio", "subcategoria", "marca", "busqueda"),
                cols = list(comercio = alias_comercio, subcategoria = "p.subcategoria_std",
                            marca = "p.marca_std", nombre = "p.nombre_std", texto = "p.nombre_std"))
}

# Gráfico 2 (cuadrícula): cada producto comparable en cada comercio de la
# corrida, con su precio por unidad de contenido y cuánto más caro está frente
# al más barato (%). Las celdas sin dato (sin precio o con otra presentación)
# vienen con NA. Como cada comparable tiene la misma presentación en todos los
# comercios, el sobrecosto en precio y en precio por unidad es el mismo.
matriz_comparables <- function(con, f = list()) {
  corrida <- corrida_referencia(con, f)
  if (is.na(corrida)) return(data.frame())
  w <- filtros_comparables(f, "com.id_comercio")
  consultar(con, paste("
    WITH c AS (SELECT * FROM v_comparables WHERE corrida = ?),
         com AS (SELECT DISTINCT id_comercio, comercio FROM c)
    SELECT p.id_producto, p.nombre_std AS producto, p.contenido_total AS contenido_producto,
           p.unidad_norm, com.id_comercio, com.comercio, c.fecha, c.precio,
           CASE WHEN c.coincide = 1 THEN c.precio_unitario END AS precio_unitario,
           c.coincide, c.disponibilidad, c.promocion, c.es_mas_barato, c.n_mas_baratos,
           CASE WHEN c.coincide = 1 AND c.precio IS NOT NULL AND c.precio_min > 0
                THEN ROUND(100.0 * (c.precio - c.precio_min) / c.precio_min, 1) END AS sobrecosto_pct,
           c.precio - c.precio_min AS sobrecosto
    FROM productos p CROSS JOIN com
    LEFT JOIN c ON c.id_producto = p.id_producto AND c.id_comercio = com.id_comercio",
    w$where, "ORDER BY p.id_producto, com.comercio"), c(list(corrida), w$params))
}

# Gráfico 4 (libre): ¿conviene la presentación grande? Pares de tamaños del
# mismo producto, detectados en la tabla productos: misma marca, subcategoría,
# variante y unidad, con dos o más contenidos distintos (se comparan el menor y
# el mayor). Para cada comercio: precio por unidad de cada tamaño y el ahorro
# porcentual de comprar el grande.
comparacion_tamanos <- function(con, f = list()) {
  corrida <- corrida_referencia(con, f)
  if (is.na(corrida)) return(data.frame())
  # Subcategoría, marca y búsqueda eligen familias: un par se muestra si alguno
  # de sus tamaños cumple los filtros. El comercio filtra los precios.
  wf <- armar_filtros(f, usar = c("subcategoria", "marca", "busqueda"),
                      cols = list(subcategoria = "subcategoria_std", marca = "marca_std",
                                  nombre = "nombre_std", texto = "nombre_std"))
  w <- armar_filtros(f, usar = "comercio", cols = list(comercio = "c.id_comercio"))
  r <- consultar(con, paste("
    WITH elegidas AS (
      SELECT DISTINCT marca_std, subcategoria_std, COALESCE(variante, '') AS variante, unidad_norm
      FROM productos", wf$where, "),
    fam AS (
      SELECT p.marca_std, p.subcategoria_std, p.variante, p.unidad_norm FROM productos p
      JOIN elegidas el ON el.marca_std = p.marca_std AND el.subcategoria_std = p.subcategoria_std
                      AND el.variante = COALESCE(p.variante, '') AND el.unidad_norm = p.unidad_norm
      GROUP BY p.marca_std, p.subcategoria_std, p.variante, p.unidad_norm
      HAVING COUNT(DISTINCT p.contenido_total) >= 2),
    miembros AS (
      SELECT p.id_producto, p.nombre_std, p.contenido_total, p.unidad_norm,
             p.marca_std || '|' || p.subcategoria_std || '|' || COALESCE(p.variante, '') || '|' || p.unidad_norm AS familia,
             MIN(p.contenido_total) OVER w AS cont_min,
             MAX(p.contenido_total) OVER w AS cont_max
      FROM productos p
      JOIN fam ON fam.marca_std = p.marca_std AND fam.subcategoria_std = p.subcategoria_std
              AND COALESCE(fam.variante, '') = COALESCE(p.variante, '') AND fam.unidad_norm = p.unidad_norm
      WINDOW w AS (PARTITION BY p.marca_std, p.subcategoria_std, p.variante, p.unidad_norm)),
    extremos AS (SELECT * FROM miembros WHERE contenido_total IN (cont_min, cont_max)),
    c AS (SELECT * FROM v_comparables WHERE corrida = ? AND coincide = 1 AND precio IS NOT NULL),
    pares AS (
      SELECT e.familia, c.id_comercio, c.comercio, MIN(c.fecha) AS fecha, e.unidad_norm,
             MAX(CASE WHEN e.contenido_total = e.cont_min THEN e.id_producto END)     AS id_pequeno,
             MAX(CASE WHEN e.contenido_total = e.cont_max THEN e.id_producto END)     AS id_grande,
             MAX(CASE WHEN e.contenido_total = e.cont_min THEN e.nombre_std END)      AS nombre_pequeno,
             MAX(CASE WHEN e.contenido_total = e.cont_max THEN e.nombre_std END)      AS nombre_grande,
             MAX(e.cont_min) AS contenido_pequeno, MAX(e.cont_max) AS contenido_grande,
             MAX(CASE WHEN e.contenido_total = e.cont_min THEN c.precio END)          AS precio_pequeno,
             MAX(CASE WHEN e.contenido_total = e.cont_max THEN c.precio END)          AS precio_grande,
             MAX(CASE WHEN e.contenido_total = e.cont_min THEN c.precio_unitario END) AS pu_pequeno,
             MAX(CASE WHEN e.contenido_total = e.cont_max THEN c.precio_unitario END) AS pu_grande
      FROM extremos e JOIN c ON c.id_producto = e.id_producto",
    w$where, "
      GROUP BY e.familia, c.id_comercio, c.comercio, e.unidad_norm)
    SELECT *, ROUND(100.0 * (pu_pequeno - pu_grande) / pu_pequeno, 1) AS ahorro_pct
    FROM pares WHERE pu_pequeno IS NOT NULL AND pu_grande IS NOT NULL
    ORDER BY familia, comercio"), c(wf$params, list(corrida), w$params))
  # Nombre del producto sin el tamaño, para el título de cada par
  r$producto <- trimws(sub("\\s+\\d+([.,]\\d+)?\\s*(g|mL|ml|gr)$", "", r$nombre_pequeno))
  r
}

# Tarjetas de comparación: cada comparable con sus comercios ordenados por
# precio en la corrida de referencia, la diferencia frente al más barato, y el
# historial de cada anuncio (cambio frente a la corrida anterior y si es el
# precio más bajo o más alto registrado).
tarjetas_comparables <- function(con, f = list()) {
  corrida <- corrida_referencia(con, f)
  if (is.na(corrida)) return(data.frame())
  w <- armar_filtros(f, usar = c("comercio", "subcategoria", "marca", "busqueda"),
                     cols = list(comercio = "h.id_comercio", subcategoria = "p.subcategoria_std",
                                 marca = "p.marca_std", nombre = "p.nombre_std", texto = "p.nombre_std"),
                     condiciones_extra = "h.corrida = ?")
  consultar(con, paste("
    WITH h AS (
      SELECT id_producto, producto, id_comercio, comercio, id_anuncio, corrida, fecha,
             precio, precio_unitario, contenido_total, unidad_norm, promocion, disponibilidad,
             url, es_mas_barato, n_mas_baratos, sobrecosto, precio_min, precio_max,
             ahorro_maximo, comercios_con_precio,
             LAG(precio)  OVER w AS precio_anterior,
             MIN(precio)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS min_previo,
             MAX(precio)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS max_previo,
             COUNT(precio) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS n_previas
      FROM v_comparables WHERE coincide = 1 AND precio IS NOT NULL
      WINDOW w AS (PARTITION BY id_anuncio ORDER BY fecha))
    SELECT h.*, p.subcategoria_std AS subcategoria, p.marca_std AS marca,
           CASE WHEN h.precio_anterior > 0
                THEN ROUND(100.0 * (h.precio - h.precio_anterior) / h.precio_anterior, 1) END AS variacion_pct,
           CASE WHEN h.n_previas = 0 THEN 'sin historial'
                WHEN h.precio < h.min_previo THEN 'más bajo registrado'
                WHEN h.precio > h.max_previo THEN 'más alto registrado'
                ELSE 'dentro del rango' END AS historial,
           CASE WHEN h.precio_max > 0
                THEN ROUND(100.0 * h.ahorro_maximo / h.precio_max, 0) END AS ahorro_pct
    FROM h JOIN productos p ON p.id_producto = h.id_producto",
    w$where, "ORDER BY h.id_producto, h.precio, h.comercio"), c(list(corrida), w$params))
}
