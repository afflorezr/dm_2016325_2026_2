# db.R · Consultas a comparador_precios.sqlite
# Cada función recibe la conexión y los filtros y devuelve un data.frame.
# Lo que escribe el usuario va como parámetro (?) o con glue_sql(), nunca
# pegado al texto del SQL.

library(DBI)
library(RSQLite)
library(glue)

RUTA_BD <- "comparador_precios.sqlite"

# Conexión de la aplicación (se cierra con onStop() en app.R). La migración
# no se aplica aquí sino en conectar_bd() de scraper.R.
abrir_conexion <- function(ruta = RUTA_BD) {
  con <- dbConnect(RSQLite::SQLite(), ruta)
  dbExecute(con, "PRAGMA busy_timeout = 10000")   # espera si el scraper está escribiendo
  con
}

# ---- Validación de la búsqueda por texto ----
# Solo letras, números, espacios y . - &, máximo 60 caracteres. Si el texto no
# cumple, se devuelve "" y la búsqueda no se aplica.
limpiar_busqueda <- function(texto, max_caracteres = 60) {
  if (is.null(texto) || is.na(texto)) return("")
  texto <- trimws(texto)
  if (nchar(texto) > max_caracteres) return("")
  if (!grepl("^[[:alnum:][:space:]áéíóúÁÉÍÓÚñÑüÜ.&-]*$", texto)) return("")
  texto
}

# Condición SQL de la búsqueda: cada palabra debe estar en el nombre o en la
# marca. Así "Versace Eros" encuentra también los anuncios que traen la marca
# en un campo aparte.
condicion_busqueda <- function(con, texto, columna_nombre) {
  palabras <- strsplit(trimws(limpiar_busqueda(texto)), " +")[[1]]
  if (length(palabras) == 0) return(DBI::SQL("1 = 1"))
  partes <- vapply(palabras, function(p) {
    patron <- paste0("%", p, "%")
    glue_sql("({`columna_nombre`} LIKE {patron} OR marca LIKE {patron})", .con = con)
  }, character(1))
  DBI::SQL(paste(partes, collapse = " AND "))
}

# ---- Opciones de los filtros ----
# Una ejecución en la que fallaron todos los comercios no tiene datos: queda
# en la tabla ejecuciones como registro, pero no se ofrece en la aplicación.
lista_ejecuciones <- function(con) {
  dbGetQuery(con, "SELECT id_ejecucion, fecha, inicio, comercios_completos, comercios
                     FROM v_ejecuciones
                    WHERE id_ejecucion IN (SELECT id_ejecucion FROM ejecuciones WHERE estado <> 'fallida')
                    ORDER BY id_ejecucion DESC")
}

ultima_ejecucion <- function(con) {
  dbGetQuery(con, "SELECT MAX(id_ejecucion) AS id FROM ejecuciones WHERE estado <> 'fallida'")$id
}

lista_comercios <- function(con) {
  dbGetQuery(con, "SELECT nombre FROM comercios ORDER BY comercio_id")$nombre
}

lista_subcategorias <- function(con) {
  dbGetQuery(con, "SELECT DISTINCT subcategoria FROM v_precios
                    WHERE subcategoria IS NOT NULL ORDER BY 1")$subcategoria
}

lista_marcas <- function(con) {
  dbGetQuery(con, "SELECT marca, COUNT(*) AS n FROM v_precios
                    WHERE marca IS NOT NULL GROUP BY marca ORDER BY marca")$marca
}

rango_precios <- function(con) {
  dbGetQuery(con, "SELECT MIN(precio) AS minimo, MAX(precio) AS maximo FROM v_precios")
}

lista_comparables <- function(con) {
  dbGetQuery(con, "SELECT DISTINCT producto_id, presentacion FROM v_comparables
                    ORDER BY presentacion")
}

# ---- Productos filtrados (tabla y gráfico de distribución) ----
# f es una lista con: ejecucion, comercios, subcategoria, marca, precio_min,
# precio_max, solo_promo, solo_comparables y busqueda. "Todas" en subcategoría
# o marca significa sin filtro.
precios_filtrados <- function(con, f) {
  if (length(f$comercios) == 0) return(data.frame())
  busqueda <- condicion_busqueda(con, f$busqueda, "nombre_original")
  sql <- glue_sql("
    SELECT comercio, nombre_original AS nombre, marca, subcategoria,
           contenido_total, unidad_norm, precio,
           ROUND(precio / contenido_total, 1) AS precio_por_ml,
           promocion, disponibilidad, fecha_hora_consulta, url_producto
      FROM v_precios
     WHERE id_ejecucion = {f$ejecucion}
       AND comercio IN ({f$comercios*})
       AND precio BETWEEN {f$precio_min} AND {f$precio_max}
       AND ({f$subcategoria} = 'Todas' OR subcategoria = {f$subcategoria}
            OR ({f$subcategoria} = 'Sin clasificar' AND subcategoria IS NULL))
       AND ({f$marca} = 'Todas' OR marca = {f$marca})
       AND ({as.integer(f$solo_promo)} = 0 OR promocion = 1)
       AND ({as.integer(f$solo_comparables)} = 0 OR comparable = 1)
       AND {busqueda}
     ORDER BY comercio, precio", .con = con)
  dbGetQuery(con, sql)
}

# ---- Indicadores del resumen (todos para una ejecución) ----
productos_por_comercio <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT comercio, COUNT(DISTINCT anuncio_id) AS productos, COUNT(*) AS observaciones
      FROM v_precios WHERE id_ejecucion = ?
     GROUP BY comercio ORDER BY comercio", params = list(ejecucion))
}

estado_ejecucion <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT c.nombre AS comercio, e.estado, e.modo, e.fecha_hora_inicio, e.n_registros, e.detalle
      FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id
     WHERE e.id_ejecucion = ? ORDER BY c.comercio_id", params = list(ejecucion))
}

proporcion_promocion <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT ROUND(100.0 * SUM(promocion = 1) / COUNT(*), 1) AS porcentaje
      FROM v_precios WHERE id_ejecucion = ?", params = list(ejecucion))$porcentaje
}

# SQLite no tiene MEDIAN(): se ordenan los precios de cada subcategoría y se
# promedian el o los valores del centro.
mediana_por_subcategoria <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT subcategoria, AVG(precio) AS mediana, MAX(n) AS productos
      FROM (SELECT subcategoria, precio,
                   ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS fila,
                   COUNT(*)     OVER (PARTITION BY subcategoria)                 AS n
              FROM v_precios
             WHERE id_ejecucion = ? AND subcategoria IS NOT NULL)
     WHERE fila IN ((n + 1) / 2, (n + 2) / 2)
     GROUP BY subcategoria ORDER BY subcategoria", params = list(ejecucion))
}

# precio más bajo, más alto y diferencia de cada presentación comparable
ahorro_por_presentacion <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT presentacion, MIN(precio) AS precio_min, MAX(precio) AS precio_max,
           MAX(precio) - MIN(precio) AS ahorro, COUNT(DISTINCT comercio) AS comercios
      FROM v_comparables WHERE id_ejecucion = ?
     GROUP BY presentacion
    HAVING COUNT(DISTINCT comercio) > 1
     ORDER BY ahorro DESC", params = list(ejecucion))
}

numero_cambios <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT COUNT(*) AS cambios FROM v_cambios_precio
     WHERE id_ejecucion = ? AND cambio_cop <> 0", params = list(ejecucion))$cambios
}

# ---- Gráficos ----
# Evolución del precio de una presentación, una serie por comercio.
evolucion_precio <- function(con, producto_id) {
  dbGetQuery(con, "
    SELECT fecha, comercio, MIN(precio) AS precio
      FROM v_comparables WHERE producto_id = ?
     GROUP BY fecha, comercio ORDER BY fecha", params = list(producto_id))
}

# Precio por mL de las comparables (todas están en mL).
precio_por_ml <- function(con, ejecucion) {
  dbGetQuery(con, "
    SELECT presentacion, comercio, MIN(precio_por_ml) AS precio_por_ml, unidad_norm
      FROM v_comparables WHERE id_ejecucion = ? AND unidad_norm = 'mL'
     GROUP BY presentacion, comercio ORDER BY presentacion", params = list(ejecucion))
}

# Gráfico libre: en cuántas presentaciones cada comercio tiene el menor precio.
veces_mas_barato <- function(con, ejecucion) {
  dbGetQuery(con, "
    WITH precios AS (
      SELECT presentacion, comercio, MIN(precio) AS precio
        FROM v_comparables WHERE id_ejecucion = ?
       GROUP BY presentacion, comercio),
    minimos AS (SELECT presentacion, MIN(precio) AS minimo FROM precios GROUP BY presentacion)
    SELECT p.comercio, COUNT(*) AS veces
      FROM precios p JOIN minimos m
        ON m.presentacion = p.presentacion AND m.minimo = p.precio
     GROUP BY p.comercio ORDER BY veces DESC", params = list(ejecucion))
}

# ---- Cambios de precio entre dos ejecuciones ----
# Compara el mismo anuncio en el mismo comercio. Incluye los anuncios nuevos
# (solo en la ejecución B) y los que dejaron de observarse (solo en la A).
# grande = 1 cuando la variación supera el umbral en porcentaje.
# f son los mismos filtros del panel lateral (sin la ejecución); el rango de
# precio se aplica al precio más reciente que tenga el anuncio.
comparar_ejecuciones <- function(con, ejecucion_a, ejecucion_b, umbral = 10, f = NULL) {
  if (is.null(f)) {
    f <- list(comercios = c("La Riviera", "Falabella", "Farmatodo"), subcategoria = "Todas",
              marca = "Todas", precio_min = 0, precio_max = 1e9, solo_promo = FALSE,
              solo_comparables = FALSE, busqueda = "")
  }
  if (length(f$comercios) == 0) return(data.frame())
  busqueda <- condicion_busqueda(con, f$busqueda, "nombre")
  sql <- glue_sql("
    WITH a AS (SELECT * FROM v_precios WHERE id_ejecucion = {ejecucion_a}),
         b AS (SELECT * FROM v_precios WHERE id_ejecucion = {ejecucion_b}),
    union_ab AS (
      SELECT b.comercio, b.nombre_original AS nombre, b.marca,
             b.subcategoria, b.comparable, b.promocion, a.precio AS precio_a, b.precio AS precio_b
        FROM b LEFT JOIN a ON a.anuncio_id = b.anuncio_id
      UNION ALL
      SELECT a.comercio, a.nombre_original, a.marca,
             a.subcategoria, a.comparable, a.promocion, a.precio, NULL
        FROM a LEFT JOIN b ON b.anuncio_id = a.anuncio_id
       WHERE b.anuncio_id IS NULL)
    SELECT comercio, nombre, comparable, precio_a, precio_b,
           precio_b - precio_a                                   AS cambio_cop,
           ROUND(100.0 * (precio_b - precio_a) / precio_a, 1)    AS cambio_pct,
           CASE WHEN precio_a IS NULL THEN 'Nuevo'
                WHEN precio_b IS NULL THEN 'Dejó de observarse'
                WHEN precio_b > precio_a THEN 'Subió'
                ELSE 'Bajó' END                                  AS situacion,
           COALESCE(ABS(100.0 * (precio_b - precio_a) / precio_a) >= {umbral}, 0) AS grande
      FROM union_ab
     WHERE (precio_a IS NULL OR precio_b IS NULL OR precio_a <> precio_b)
       AND comercio IN ({f$comercios*})
       AND COALESCE(precio_b, precio_a) BETWEEN {f$precio_min} AND {f$precio_max}
       AND ({f$subcategoria} = 'Todas' OR subcategoria = {f$subcategoria}
            OR ({f$subcategoria} = 'Sin clasificar' AND subcategoria IS NULL))
       AND ({f$marca} = 'Todas' OR marca = {f$marca})
       AND ({as.integer(f$solo_promo)} = 0 OR promocion = 1)
       AND ({as.integer(f$solo_comparables)} = 0 OR comparable = 1)
       AND {busqueda}
     ORDER BY situacion, ABS(cambio_pct) DESC", .con = con)
  dbGetQuery(con, sql)
}

# ---- Canasta ----
# Si un comercio tiene varios anuncios de la misma presentación se toma el
# más barato.
precios_canasta <- function(con, ejecucion, productos) {
  if (length(productos) == 0) return(data.frame())
  sql <- glue_sql("
    SELECT producto_id, presentacion, comercio, MIN(precio) AS precio
      FROM v_comparables
     WHERE id_ejecucion = {ejecucion} AND producto_id IN ({productos*})
     GROUP BY producto_id, presentacion, comercio", .con = con)
  dbGetQuery(con, sql)
}

# Con los precios de precios_canasta() y las cantidades (vector con nombres
# = producto_id) calcula el total por comercio, el costo mínimo repartiendo la
# compra y el ahorro. Un comercio al que le falta algún producto no tiene total.
calcular_canasta <- function(precios, cantidades, nombres = names(cantidades)) {
  productos <- names(cantidades)
  comercios <- sort(unique(precios$comercio))
  if (length(comercios) == 0) {   # ninguna presentación elegida tiene precio en esa ejecución
    vacio <- data.frame(comercio = character(), total = numeric(), faltan = character())
    return(list(por_comercio = vacio, minimo = NA_real_, ahorro = NA_real_))
  }

  por_comercio <- data.frame(comercio = comercios, total = NA_real_, faltan = "")
  for (i in seq_along(comercios)) {
    p <- precios[precios$comercio == comercios[i], ]
    faltan <- setdiff(productos, p$producto_id)
    if (length(faltan) == 0) {
      por_comercio$total[i] <- sum(p$precio[match(productos, p$producto_id)] * cantidades)
    } else {
      por_comercio$faltan[i] <- paste(nombres[match(faltan, productos)], collapse = ", ")
    }
  }

  # costo mínimo: cada producto donde es más barato (NA si nadie lo vende)
  if (!all(productos %in% precios$producto_id)) {
    return(list(por_comercio = por_comercio, minimo = NA_real_, ahorro = NA_real_))
  }
  mas_barato <- tapply(precios$precio, precios$producto_id, min)
  minimo <- sum(mas_barato[productos] * cantidades)
  list(por_comercio = por_comercio, minimo = minimo,
       ahorro = calcular_ahorro(por_comercio$total, minimo))
}

# Ahorro frente a comprar todo en el comercio completo más barato. Si dos
# comercios empatan da igual cuál se tome, porque el total es el mismo.
calcular_ahorro <- function(totales, minimo) {
  totales <- totales[!is.na(totales)]
  if (length(totales) == 0 || is.na(minimo)) return(NA_real_)
  min(totales) - minimo
}

# ---- Resumen después de actualizar ----
resumen_actualizacion <- function(con, ejecucion) {
  anterior <- dbGetQuery(con, "SELECT MAX(id_ejecucion) AS id FROM ejecuciones
                                WHERE id_ejecucion < ?", params = list(ejecucion))$id
  dbGetQuery(con, "
    SELECT c.nombre AS comercio, e.estado,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = e.id_ejecucion AND o.comercio_id = e.comercio_id) AS recolectados,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = e.id_ejecucion AND o.comercio_id = e.comercio_id
               AND NOT EXISTS (SELECT 1 FROM observaciones o2
                                WHERE o2.anuncio_id = o.anuncio_id AND o2.id_ejecucion < o.id_ejecucion)) AS nuevos,
           (SELECT COUNT(*) FROM v_cambios_precio v
             WHERE v.id_ejecucion = e.id_ejecucion AND v.comercio_id = e.comercio_id
               AND v.cambio_cop <> 0) AS cambios_precio,
           (SELECT COUNT(*) FROM observaciones o
             WHERE o.id_ejecucion = ? AND o.comercio_id = e.comercio_id
               AND NOT EXISTS (SELECT 1 FROM observaciones o2
                                WHERE o2.anuncio_id = o.anuncio_id
                                  AND o2.id_ejecucion = e.id_ejecucion)) AS no_observados,
           e.detalle
      FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id
     WHERE e.id_ejecucion = ? ORDER BY c.comercio_id",
    params = list(if (is.na(anterior)) "" else anterior, ejecucion))
}
