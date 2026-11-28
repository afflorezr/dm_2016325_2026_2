# =============================================================================
# db.R — Capa de acceso a datos (Módulo 3 del Taller 2)
# =============================================================================

library(DBI)
library(RSQLite)
library(dplyr)

# Función para conectar a la base de datos de forma segura
conectar_db <- function() {
  dbConnect(SQLite(), "comparador_precios.sqlite")
}

# 1. Obtener la lista de comercios disponibles
obtener_comercios <- function(con) {
  dbGetQuery(con, "SELECT DISTINCT comercio FROM observaciones WHERE descartada = 0 ORDER BY comercio")$comercio
}

# 2. Obtener la lista de productos comparables (los 8 que definimos)
obtener_productos_comparables <- function(con) {
  dbGetQuery(con, "
    SELECT p.id_producto, p.nombre_std 
    FROM productos p
    INNER JOIN correspondencia c ON p.id_producto = c.id_producto
    GROUP BY p.id_producto, p.nombre_std
    HAVING COUNT(DISTINCT c.comercio) = 3
    ORDER BY p.nombre_std
  ")
}

# 3. Obtener el último precio de todos los productos con filtros (para la tabla principal)
# Usamos v_ultimo_precio y hacemos JOIN con v_observaciones para saber si es comparable
obtener_ultimos_precios <- function(con, comercios_filtro = NULL, solo_comparables = FALSE) {
  sql <- "
    SELECT v.*, o.id_producto, o.comparable
    FROM v_ultimo_precio v
    LEFT JOIN v_observaciones o ON v.comercio = o.comercio AND v.sku = o.sku AND v.id_ejecucion = o.id_ejecucion
    WHERE 1=1
    "
    sql <- "
  SELECT v.*, o.id_producto, o.comparable
  FROM v_ultimo_precio v
  LEFT JOIN v_observaciones o ON v.comercio = o.comercio AND v.sku = o.sku AND v.id_ejecucion = o.id_ejecucion
  WHERE v.precio > 0  -- <--- Agrega esta línea
  "
  params <- list()
  
  if (!is.null(comercios_filtro) && length(comercios_filtro) > 0) {
    placeholders <- paste(rep("?", length(comercios_filtro)), collapse = ", ")
    sql <- paste(sql, "AND v.comercio IN (", placeholders, ")")
    params <- as.list(comercios_filtro)
  }
  
  if (solo_comparables) {
    sql <- paste(sql, "AND o.comparable = 1")
  }
  
  dbGetQuery(con, sql, params = params)
}

# 4. Obtener datos para el gráfico de evolución de precios de un producto específico
obtener_evolucion_precio <- function(con, id_producto) {
  dbGetQuery(con, "
    SELECT o.fecha_hora_consulta, o.comercio, o.precio
    FROM observaciones o
    INNER JOIN correspondencia c ON o.comercio = c.comercio AND o.sku = c.sku
    WHERE c.id_producto = ? AND o.descartada = 0
    ORDER BY o.fecha_hora_consulta
  ", params = list(id_producto))
}

# 5. Obtener los indicadores (KPIs) para los value boxes
obtener_indicadores <- function(con) {
  total_productos <- dbGetQuery(con, "SELECT COUNT(DISTINCT sku) as n FROM observaciones WHERE descartada = 0")$n
  total_observaciones <- dbGetQuery(con, "SELECT COUNT(*) as n FROM observaciones WHERE descartada = 0")$n
  ultima_fecha <- dbGetQuery(con, "SELECT MAX(fecha_hora_consulta) as f FROM observaciones WHERE descartada = 0")$f
  
  list(
    total_productos = total_productos,
    total_observaciones = total_observaciones,
    ultima_fecha = ultima_fecha
  )
}



# 6. Obtener precios de los 8 productos comparables para la canasta
obtener_precios_canasta <- function(con) {
  dbGetQuery(con, "
    SELECT c.id_producto, p.nombre_std, c.comercio, o.precio
    FROM correspondencia c
    INNER JOIN productos p ON p.id_producto = c.id_producto
    INNER JOIN v_ultimo_precio o ON o.comercio = c.comercio AND o.sku = c.sku
    WHERE o.precio > 0
  ")
}

# 7. Calcular el costo de la canasta según las cantidades
calcular_canasta <- function(con, cantidades) {
  # cantidades es un named vector: c("P01" = 2, "P03" = 1, ...)
  df_precios <- obtener_precios_canasta(con)
  
  # Filtrar solo los productos seleccionados
  df_precios <- df_precios[df_precios$id_producto %in% names(cantidades), ]
  
  # Agregar la cantidad y calcular subtotal
  df_precios$cantidad <- cantidades[df_precios$id_producto]
  df_precios$subtotal <- df_precios$precio * df_precios$cantidad
  
  # 1. Costo total por comercio (solo si tiene todos los productos)
  comercios <- unique(df_precios$comercio)
  resumen_comercios <- data.frame(comercio = comercios, costo_total = NA, completo = FALSE)
  
  for (i in seq_along(comercios)) {
    df_com <- df_precios[df_precios$comercio == comercios[i], ]
    if (nrow(df_com) == length(cantidades)) {
      resumen_comercios$costo_total[i] <- sum(df_com$subtotal)
      resumen_comercios$completo[i] <- TRUE
    }
  }
  
  # 2. Costo mínimo (comprando cada producto donde es más barato)
  df_minimos <- df_precios |>
    group_by(id_producto) |>
    slice_min(order_by = precio, n = 1, with_ties = FALSE) |>
    ungroup()
  
  costo_minimo <- sum(df_minimos$subtotal)
  
  list(
    precios_crudos = df_precios,
    resumen_comercios = resumen_comercios,
    minimos = df_minimos,
    costo_minimo = costo_minimo
  )
}


# 8. Obtener los cambios de precio entre las dos últimas ejecuciones
obtener_cambios_recientes <- function(con) {
  # Obtenemos los dos IDs de ejecución más recientes (que no sean descartadas)
  ejecuciones <- dbGetQuery(con, "
    SELECT DISTINCT id_ejecucion 
    FROM observaciones 
    WHERE descartada = 0 
    ORDER BY id_ejecucion DESC 
    LIMIT 2
  ")$id_ejecucion
  
  if (length(ejecuciones) < 2) return(data.frame()) 
  
  ejec_actual <- ejecuciones[1]
  ejec_anterior <- ejecuciones[2]
  
  # Buscamos el mismo SKU en el mismo comercio en ambas ejecuciones
  dbGetQuery(con, "
    SELECT 
      a.comercio, a.nombre_original, 
      ant.precio AS precio_anterior, 
      a.precio AS precio_actual,
      (a.precio - ant.precio) AS diferencia_absoluta,
      ROUND(((a.precio - ant.precio) / ant.precio) * 100, 2) AS diferencia_pct
    FROM observaciones a
    INNER JOIN observaciones ant 
      ON a.comercio = ant.comercio AND a.sku = ant.sku
    WHERE a.id_ejecucion = ? 
      AND ant.id_ejecucion = ?
      AND a.descartada = 0 AND ant.descartada = 0
      AND ant.precio > 0 AND a.precio > 0
    ORDER BY ABS(a.precio - ant.precio) DESC
  ", params = list(ejec_actual, ejec_anterior))
}

# 9. Datos para el gráfico de distribución de precios por comercio
obtener_distribucion_precios <- function(con) {
  dbGetQuery(con, "
    SELECT comercio, precio 
    FROM v_ultimo_precio 
    WHERE precio > 0 AND descartada = 0
  ")
}

# 10. Datos para el gráfico de productos en promoción
obtener_promociones_por_comercio <- function(con) {
  dbGetQuery(con, "
    SELECT comercio, 
           COUNT(*) AS total_productos,
           SUM(promocion) AS en_promocion
    FROM v_ultimo_precio 
    WHERE precio > 0 AND descartada = 0
    GROUP BY comercio
  ")
}
