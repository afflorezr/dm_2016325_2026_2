suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

COMERCIOS_BASE <- data.frame(
  comercio = c("larebaja", "cafam", "locatel"),
  nombre   = c("La Rebaja", "Droguerías Cafam", "Locatel Colombia"),
  base_url = c("https://www.larebajavirtual.com", "https://www.drogueriascafam.com.co",
               "https://www.locatelcolombia.com"),
  stringsAsFactors = FALSE)

tiene_columna <- function(con, tabla, columna) columna %in% dbListFields(con, tabla)

agregar_columna <- function(con, tabla, definicion) {
  col <- strsplit(definicion, " ")[[1]][1]
  if (!tiene_columna(con, tabla, col))
    dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s", tabla, definicion))
}

crear_tablas_base <- function(con) {
  s <- c(
    "CREATE TABLE IF NOT EXISTS comercios (
       comercio TEXT PRIMARY KEY, nombre TEXT, base_url TEXT)",
    "CREATE TABLE IF NOT EXISTS ejecuciones (
       ejecucion_id TEXT NOT NULL, comercio TEXT NOT NULL REFERENCES comercios(comercio),
       inicio TEXT NOT NULL, fin TEXT, modo TEXT,
       n_registros INTEGER, n_productos INTEGER, total_sitio INTEGER,
       estado TEXT CHECK (estado IN ('completa','parcial','fallida')), notas TEXT,
       PRIMARY KEY (ejecucion_id, comercio))",
    "CREATE TABLE IF NOT EXISTS anuncios (
       anuncio_id INTEGER PRIMARY KEY AUTOINCREMENT,
       comercio TEXT NOT NULL REFERENCES comercios(comercio),
       producto_id TEXT, sku_comercio TEXT NOT NULL, ean TEXT, referencia TEXT,
       nombre_original TEXT, marca_original TEXT, descripcion_original TEXT,
       categoria_origen TEXT, categoria_consulta TEXT, url TEXT, texto_original TEXT,
       primera_ejecucion TEXT,
       UNIQUE (comercio, sku_comercio))",
    "CREATE TABLE IF NOT EXISTS observaciones (
       obs_id INTEGER PRIMARY KEY AUTOINCREMENT,
       ejecucion_id TEXT NOT NULL, comercio TEXT NOT NULL,
       anuncio_id INTEGER NOT NULL REFERENCES anuncios(anuncio_id),
       fecha_hora TEXT NOT NULL,
       precio REAL, precio_lista REAL, en_promocion INTEGER, disponible INTEGER,
       moneda TEXT DEFAULT 'COP', url TEXT,
       UNIQUE (comercio, anuncio_id, fecha_hora),
       FOREIGN KEY (ejecucion_id, comercio) REFERENCES ejecuciones(ejecucion_id, comercio))",
    "CREATE TABLE IF NOT EXISTS productos (
       producto_id TEXT PRIMARY KEY, descripcion TEXT, marca_std TEXT, subcategoria_std TEXT,
       contenido_valor REAL, contenido_unidad TEXT, unidades_empaque INTEGER,
       concentracion TEXT, comparable INTEGER DEFAULT 0, principio_activo_std TEXT)",
    "CREATE TABLE IF NOT EXISTS correspondencia (
       anuncio_id INTEGER PRIMARY KEY REFERENCES anuncios(anuncio_id),
       producto_id TEXT REFERENCES productos(producto_id),
       comparable INTEGER DEFAULT 0, regla TEXT)",
    "CREATE TABLE IF NOT EXISTS clasificacion (
       anuncio_id INTEGER PRIMARY KEY REFERENCES anuncios(anuncio_id),
       en_categoria INTEGER, motivo_categoria TEXT, confianza_categoria TEXT, principio_activo_std TEXT, forma TEXT,
       venta TEXT, es_paquete_promo INTEGER, pediatrico INTEGER, ean_norm TEXT,
       marca_std TEXT, subcategoria_std TEXT, concentracion TEXT,
       contenido_valor REAL, contenido_unidad TEXT, n_dup_en_comercio INTEGER, dup_conflicto INTEGER)",
    "CREATE TABLE IF NOT EXISTS obs_comparable (
       obs_id INTEGER PRIMARY KEY REFERENCES observaciones(obs_id),
       ejecucion_id TEXT NOT NULL, comparable INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS familias (
       producto_id TEXT PRIMARY KEY REFERENCES productos(producto_id), familia TEXT NOT NULL, n_tamanos INTEGER)")
  for (x in s) dbExecute(con, x)
  dbExecute(con, "INSERT OR IGNORE INTO comercios (comercio, nombre, base_url) VALUES (?,?,?)",
            params = unname(as.list(COMERCIOS_BASE)))
}

crear_tablas_taller2 <- function(con) {
  s <- c(
    # Correcciones a la base del Taller 1 (y posteriores): nada se modifica en silencio
    "CREATE TABLE IF NOT EXISTS correcciones (
       correccion_id INTEGER PRIMARY KEY AUTOINCREMENT,
       fecha TEXT NOT NULL, tabla TEXT NOT NULL, registro TEXT NOT NULL, campo TEXT NOT NULL,
       valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT NOT NULL)",
    # Observaciones que no superaron la validación (no entran a `observaciones`)
    "CREATE TABLE IF NOT EXISTS rechazos (
       rechazo_id INTEGER PRIMARY KEY AUTOINCREMENT,
       ejecucion_id TEXT NOT NULL, comercio TEXT, sku_comercio TEXT, nombre_original TEXT,
       url TEXT, fecha_hora TEXT, precio REAL, regla TEXT NOT NULL, motivo TEXT NOT NULL,
       registrado TEXT NOT NULL,
       UNIQUE (ejecucion_id, comercio, sku_comercio, regla))",
    "CREATE TABLE IF NOT EXISTS validaciones (
       ejecucion_id TEXT NOT NULL, comercio TEXT NOT NULL, regla TEXT NOT NULL,
       evaluadas INTEGER, fallas INTEGER, resultado TEXT CHECK (resultado IN ('cumple','no cumple')),
       detalle TEXT, registrado TEXT NOT NULL,
       PRIMARY KEY (ejecucion_id, comercio, regla))",
    # Cada vez que se pulsa "Actualizar" (en línea o sin conexión): resumen por comercio
    "CREATE TABLE IF NOT EXISTS log_actualizaciones (
       log_id INTEGER PRIMARY KEY AUTOINCREMENT,
       actualizacion_id TEXT NOT NULL, ejecucion_id TEXT NOT NULL, comercio TEXT NOT NULL,
       modo TEXT NOT NULL, inicio TEXT NOT NULL, fin TEXT,
       estado TEXT CHECK (estado IN ('en curso','completa','parcial','fallida')),
       recolectados INTEGER, nuevos INTEGER, insertadas INTEGER, rechazadas INTEGER,
       cambios_precio INTEGER, no_observados INTEGER, motivo TEXT)",
    # Canasta de referencia: los 8 productos comparables cuya presencia se exige en cada comercio
    "CREATE TABLE IF NOT EXISTS canasta_referencia (
       producto_id TEXT PRIMARY KEY REFERENCES productos(producto_id),
       orden INTEGER NOT NULL, motivo TEXT)")
  for (x in s) dbExecute(con, x)

  agregar_columna(con, "observaciones",
                  "estado_disponibilidad TEXT CHECK (estado_disponibilidad IN ('disponible','agotado','sin dato'))")
  agregar_columna(con, "observaciones", "descartada INTEGER NOT NULL DEFAULT 0")
  agregar_columna(con, "observaciones", "motivo_descarte TEXT")
  agregar_columna(con, "productos", "contenido_total REAL")
  agregar_columna(con, "productos", "unidad_norm TEXT CHECK (unidad_norm IN ('mL','g','unidad'))")
  if (!tiene_columna(con, "productos", "principio_activo_std"))
    dbExecute(con, "ALTER TABLE productos ADD COLUMN principio_activo_std TEXT")
}

# Campos derivados que se recalculan sin perder información (solo rellenan lo que falta)
completar_derivados <- function(con) {
  dbExecute(con, "UPDATE observaciones SET estado_disponibilidad =
                    CASE disponible WHEN 1 THEN 'disponible' WHEN 0 THEN 'agotado' ELSE 'sin dato' END
                  WHERE estado_disponibilidad IS NULL")
  dbExecute(con, "UPDATE productos SET contenido_total = contenido_valor,
                    unidad_norm = CASE contenido_unidad WHEN 'ml' THEN 'mL' WHEN 'g' THEN 'g'
                                                       WHEN 'un' THEN 'unidad' END
                  WHERE contenido_valor IS NOT NULL")
}

crear_indices <- function(con) {
  s <- c(
    # Unicidad: un anuncio se observa una sola vez por ejecución
    "CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_ejecucion_anuncio ON observaciones(ejecucion_id, anuncio_id)",
    "CREATE INDEX IF NOT EXISTS ix_obs_ejecucion_comercio ON observaciones(ejecucion_id, comercio)",
    "CREATE INDEX IF NOT EXISTS ix_obs_anuncio ON observaciones(anuncio_id)",
    "CREATE INDEX IF NOT EXISTS ix_obs_fecha ON observaciones(fecha_hora)",
    "CREATE INDEX IF NOT EXISTS ix_obs_precio ON observaciones(precio)",
    "CREATE INDEX IF NOT EXISTS ix_obscomp_ejecucion ON obs_comparable(ejecucion_id, comparable)",
    "CREATE INDEX IF NOT EXISTS ix_corresp_producto ON correspondencia(producto_id)",
    "CREATE INDEX IF NOT EXISTS ix_clasif_subcat ON clasificacion(subcategoria_std)",
    "CREATE INDEX IF NOT EXISTS ix_clasif_marca ON clasificacion(marca_std)",
    "CREATE INDEX IF NOT EXISTS ix_clasif_categoria ON clasificacion(en_categoria)",
    "CREATE INDEX IF NOT EXISTS ix_anuncios_comercio ON anuncios(comercio)",
    "CREATE INDEX IF NOT EXISTS ix_rechazos_ejecucion ON rechazos(ejecucion_id, comercio)",
    "CREATE INDEX IF NOT EXISTS ix_log_actualizacion ON log_actualizaciones(actualizacion_id)")
  for (x in s) dbExecute(con, x)
}

VISTAS <- list(
  # Una fila por observación con todo lo estandarizado. La subcategoría de un anuncio con
  # producto emparejado es la del producto (consenso entre comercios).
  v_observaciones = "
    SELECT o.obs_id, o.ejecucion_id, o.fecha_hora, substr(o.fecha_hora, 1, 10) AS fecha,
           c.nombre AS comercio_nombre, a.comercio, a.anuncio_id,
           a.sku_comercio, a.nombre_original, a.marca_original, a.descripcion_original, a.texto_original,
           CASE WHEN a.url LIKE '/%' THEN c.base_url || a.url ELSE a.url END AS url_anuncio,
           o.url AS url_extraccion,
           o.precio, o.precio_lista, o.en_promocion, o.disponible, o.estado_disponibilidad, o.moneda,
           o.descartada, o.motivo_descarte,
           cl.en_categoria, cl.motivo_categoria, cl.confianza_categoria,
           COALESCE(p.principio_activo_std, cl.principio_activo_std) AS principio_activo_std,
           COALESCE(p.subcategoria_std, cl.subcategoria_std) AS subcategoria_std,
           COALESCE(p.marca_std, cl.marca_std) AS marca_std, cl.concentracion, cl.forma,
           cl.contenido_valor, cl.contenido_unidad,
           CASE cl.contenido_unidad WHEN 'ml' THEN 'mL' WHEN 'g' THEN 'g' WHEN 'un' THEN 'unidad' END AS unidad_norm,
           cl.es_paquete_promo, cl.n_dup_en_comercio, cl.dup_conflicto,
           co.producto_id, co.regla, COALESCE(oc.comparable, 0) AS comparable,
           CASE WHEN o.precio > 0 AND cl.contenido_valor > 0 THEN o.precio / cl.contenido_valor END AS precio_por_unidad
    FROM observaciones o
    JOIN anuncios a ON a.anuncio_id = o.anuncio_id
    JOIN comercios c ON c.comercio = a.comercio
    LEFT JOIN clasificacion cl ON cl.anuncio_id = a.anuncio_id
    LEFT JOIN correspondencia co ON co.anuncio_id = a.anuncio_id
    LEFT JOIN productos p ON p.producto_id = co.producto_id
    LEFT JOIN obs_comparable oc ON oc.obs_id = o.obs_id
    WHERE o.descartada = 0",

  v_ultimo_precio = "
    SELECT v.* FROM v_observaciones v
    JOIN (SELECT anuncio_id, MAX(fecha_hora) AS fmax FROM observaciones
          WHERE descartada = 0 GROUP BY anuncio_id) u
      ON u.anuncio_id = v.anuncio_id AND u.fmax = v.fecha_hora",

  # Cambios de precio del MISMO anuncio entre ejecuciones consecutivas en que fue observado
  v_cambios_precio = "
    WITH serie AS (
      SELECT anuncio_id, comercio, ejecucion_id, fecha_hora, precio,
             LAG(ejecucion_id) OVER (PARTITION BY anuncio_id ORDER BY fecha_hora) AS ejecucion_anterior,
             LAG(precio)       OVER (PARTITION BY anuncio_id ORDER BY fecha_hora) AS precio_anterior
      FROM observaciones WHERE descartada = 0 AND precio > 0)
    SELECT s.anuncio_id, s.comercio, a.nombre_original, co.producto_id,
           s.ejecucion_anterior, s.ejecucion_id AS ejecucion_actual,
           s.precio_anterior, s.precio AS precio_actual,
           s.precio - s.precio_anterior AS cambio_cop,
           ROUND(100.0 * (s.precio - s.precio_anterior) / s.precio_anterior, 2) AS cambio_pct,
           CASE WHEN s.precio > s.precio_anterior THEN 'subió'
                WHEN s.precio < s.precio_anterior THEN 'bajó' ELSE 'igual' END AS direccion
    FROM serie s JOIN anuncios a ON a.anuncio_id = s.anuncio_id
    LEFT JOIN correspondencia co ON co.anuncio_id = s.anuncio_id
    WHERE s.ejecucion_anterior IS NOT NULL",

  # Presentaciones comparables: una fila por producto, comercio y ejecución (precio mínimo del
  # comercio si tuviera dos anuncios del mismo producto con el mismo precio)
  v_comparables = "
    SELECT v.ejecucion_id, v.producto_id, p.descripcion, p.marca_std, p.subcategoria_std,
           p.principio_activo_std, p.contenido_total, p.unidad_norm,
           v.comercio, v.comercio_nombre, MIN(v.precio) AS precio,
           MIN(v.precio) / p.contenido_total AS precio_por_unidad,
           MAX(v.en_promocion) AS en_promocion, MAX(v.estado_disponibilidad) AS estado_disponibilidad,
           MIN(v.fecha_hora) AS fecha_hora, MIN(v.url_anuncio) AS url_anuncio
    FROM v_observaciones v JOIN productos p ON p.producto_id = v.producto_id
    WHERE v.comparable = 1 AND v.precio > 0
    GROUP BY v.ejecucion_id, v.producto_id, v.comercio",

  # Disponibilidad: disponible / agotado según el sitio / no observado en la ejecución.
  # Un anuncio se considera esperado en una ejecución si ya se conocía (primera_ejecucion <=).
  v_disponibilidad = "
    SELECT e.ejecucion_id, a.comercio, a.anuncio_id, a.nombre_original,
           CASE WHEN o.obs_id IS NULL THEN 'no observado'
                ELSE COALESCE(o.estado_disponibilidad, 'sin dato') END AS estado
    FROM (SELECT DISTINCT ejecucion_id, comercio FROM ejecuciones WHERE estado <> 'fallida') e
    JOIN anuncios a ON a.comercio = e.comercio AND a.primera_ejecucion <= e.ejecucion_id
    LEFT JOIN observaciones o ON o.anuncio_id = a.anuncio_id AND o.ejecucion_id = e.ejecucion_id
                             AND o.descartada = 0",

  v_resumen_ejecuciones = "
    SELECT e.ejecucion_id, e.comercio, c.nombre AS comercio_nombre, e.inicio, e.fin, e.modo, e.estado,
           e.total_sitio, e.n_registros,
           (SELECT COUNT(*) FROM observaciones o WHERE o.ejecucion_id = e.ejecucion_id
               AND o.comercio = e.comercio AND o.descartada = 0) AS observaciones_validas,
           (SELECT COUNT(*) FROM rechazos r WHERE r.ejecucion_id = e.ejecucion_id
               AND r.comercio = e.comercio) AS rechazadas,
           e.notas
    FROM ejecuciones e JOIN comercios c ON c.comercio = e.comercio")

crear_vistas <- function(con) {
  # se borran en orden inverso (unas dependen de otras) y se crean en orden
  for (v in rev(names(VISTAS))) dbExecute(con, sprintf("DROP VIEW IF EXISTS %s", v))
  for (v in names(VISTAS)) dbExecute(con, sprintf("CREATE VIEW %s AS %s", v, VISTAS[[v]]))
}

# Idempotente: crea lo que falte y no borra datos.
preparar_base <- function(con) {
  dbExecute(con, "PRAGMA foreign_keys = ON")
  dbWithTransaction(con, {
    crear_tablas_base(con)
    crear_tablas_taller2(con)
    completar_derivados(con)
    crear_indices(con)
    crear_vistas(con)
  })
  invisible(TRUE)
}

# Registra una corrección y aplica el cambio en la misma transacción
registrar_correccion <- function(con, tabla, clave_col, clave, campo, valor_nuevo, motivo,
                                 fecha = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")) {
  ant <- dbGetQuery(con, sprintf("SELECT %s AS v FROM %s WHERE %s = ?", campo, tabla, clave_col),
                    params = list(clave))$v
  if (!length(ant)) stop("No existe ", tabla, ".", clave_col, " = ", clave)
  if (identical(as.character(ant), as.character(valor_nuevo))) return(invisible(FALSE))
  dbExecute(con, sprintf("UPDATE %s SET %s = ? WHERE %s = ?", tabla, campo, clave_col),
            params = list(valor_nuevo, clave))
  dbExecute(con, "INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo)
                  VALUES (?,?,?,?,?,?,?)",
            params = list(fecha, tabla, paste0(clave_col, "=", clave), campo,
                          as.character(ant), as.character(valor_nuevo), motivo))
  invisible(TRUE)
}
