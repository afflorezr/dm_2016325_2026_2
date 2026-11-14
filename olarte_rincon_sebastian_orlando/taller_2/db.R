# Mineria de Datos 2016325 - Taller 2
# Modulo de consultas SQL para Shiny. No ejecuta scraping ni modifica datos.
# Todas las rutas son relativas al proyecto.

abrir_db <- function(ruta = "comparador_precios.sqlite") {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Se requieren DBI y RSQLite")
  }
  if (!file.exists(ruta)) stop("No se encuentra SQLite: ", ruta)
  DBI::dbConnect(RSQLite::SQLite(), dbname = ruta,
                 flags = RSQLite::SQLITE_RO)
}

cerrar_db <- function(con) {
  if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
  invisible(NULL)
}

consulta_db <- function(con, sql, params = list()) {
  if (!DBI::dbIsValid(con)) stop("La conexion SQLite esta cerrada")
  if (length(params)) {
    DBI::dbGetQuery(con, sql, params = params)
  } else {
    DBI::dbGetQuery(con, sql)
  }
}

# Construye solamente fragmentos SQL conocidos; los valores siempre son parametros.
# Filtros disponibles: comercio, marca, subcategoria, ejecucion,
# precio_min, precio_max, comparable, categoria, promocion, texto, desde, hasta.
preparar_filtros_db <- function(filtros = list()) {
  if (!is.list(filtros)) stop("Los filtros deben entregarse como lista")
  condiciones <- character()
  parametros <- list()

  agregar_lista <- function(campo, valores) {
    if (is.null(valores) || !length(valores)) return(invisible(NULL))
    valores <- unique(trimws(as.character(valores)))
    valores <- valores[!is.na(valores) & nzchar(valores)]
    if (!length(valores)) return(invisible(NULL))
    if (length(valores) > 50L || any(nchar(valores) > 120L)) {
      stop("Filtro de texto demasiado largo")
    }
    # El campo solo procede del codigo (nunca de la interfaz).
    marcadores <- paste(rep("?", length(valores)), collapse = ", ")
    condiciones <<- c(condiciones, paste0("p.", campo, " IN (", marcadores, ")"))
    parametros <<- c(parametros, as.list(valores))
    invisible(NULL)
  }

  agregar_lista("comercio", filtros$comercio)
  agregar_lista("marca_estandar", filtros$marca)
  agregar_lista("subcategoria_estandar", filtros$subcategoria)
  agregar_lista("ejecucion_id", filtros$ejecucion)

  agregar_numero <- function(campo, operador, valor) {
    if (is.null(valor) || length(valor) == 0L) return(invisible(NULL))
    if (length(valor) != 1L || is.na(valor) ||
        !is.finite(suppressWarnings(as.numeric(valor)))) {
      stop("El filtro de precio debe ser un numero finito")
    }
    valor <- as.numeric(valor)
    if (valor < 0) stop("El precio no puede ser negativo")
    condiciones <<- c(condiciones, paste("p.", campo, operador, "?"))
    parametros <<- c(parametros, list(valor))
    invisible(NULL)
  }
  agregar_numero("precio_cop", ">=", filtros$precio_min)
  agregar_numero("precio_cop", "<=", filtros$precio_max)

  agregar_bandera <- function(campo, valor) {
    if (is.null(valor) || !length(valor)) return(invisible(NULL))
    if (length(valor) != 1L || is.na(valor) || !is.logical(valor)) {
      stop("Los filtros de bandera deben ser TRUE o FALSE")
    }
    condiciones <<- c(condiciones, paste0("p.", campo, " = ?"))
    parametros <<- c(parametros, list(as.integer(valor)))
    invisible(NULL)
  }
  agregar_bandera("comparable", filtros$comparable)
  agregar_bandera("incluido_categoria", filtros$categoria)
  agregar_bandera("promocion", filtros$promocion)

  if (!is.null(filtros$texto) && length(filtros$texto)) {
    if (length(filtros$texto) != 1L || is.na(filtros$texto) ||
        nchar(as.character(filtros$texto)) > 100L) {
      stop("La busqueda admite hasta 100 caracteres")
    }
    texto <- trimws(as.character(filtros$texto))
    if (nzchar(texto)) {
      # instr evita comodines y evita concatenar texto del usuario al SQL.
      condiciones <- c(condiciones,
        "(instr(lower(coalesce(p.producto_original, '')), lower(?)) > 0
          OR EXISTS (
            SELECT 1 FROM anuncios a_busqueda
            WHERE a_busqueda.ejecucion_id = p.ejecucion_id
              AND a_busqueda.comercio_id = p.comercio_id
              AND a_busqueda.producto_comercio_id = p.producto_comercio_id
              AND instr(lower(coalesce(a_busqueda.texto_original, '')), lower(?)) > 0
          ))")
      parametros <- c(parametros, list(texto, texto))
    }
  }

  agregar_fecha <- function(operador, valor) {
    if (is.null(valor) || !length(valor)) return(invisible(NULL))
    if (length(valor) != 1L || is.na(valor)) stop("Fecha invalida")
    valor <- as.character(valor)
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", valor) ||
        is.na(suppressWarnings(as.Date(valor)))) {
      stop("Fecha debe tener formato AAAA-MM-DD")
    }
    condiciones <<- c(condiciones,
                       paste("substr(p.fecha_hora_consulta, 1, 10)", operador, "?"))
    parametros <<- c(parametros, list(valor))
    invisible(NULL)
  }
  agregar_fecha(">=", filtros$desde)
  agregar_fecha("<=", filtros$hasta)

  list(
    sql = if (length(condiciones)) paste("WHERE", paste(condiciones, collapse = " AND ")) else "",
    params = parametros
  )
}

# Indicadores agregados en SQLite; devuelve una sola fila con al menos 6 KPI.
indicadores_db <- function(con, filtros = list()) {
  f <- preparar_filtros_db(filtros)
  sql <- paste0("
    SELECT COUNT(*) AS ofertas,
           COUNT(DISTINCT p.comercio_id) AS comercios,
           COUNT(DISTINCT CASE WHEN p.comparable = 1
                 THEN p.producto_comun_id END) AS productos_comparables,
           SUM(CASE WHEN p.comparable = 1 THEN 1 ELSE 0 END) AS ofertas_comparables,
           ROUND(AVG(p.precio_cop), 2) AS precio_promedio_cop,
           MIN(p.precio_cop) AS precio_minimo_cop,
           MAX(p.precio_cop) AS precio_maximo_cop,
           SUM(CASE WHEN p.promocion = 1 THEN 1 ELSE 0 END) AS promociones
    FROM v_ultimo_precio p ", f$sql)
  consulta_db(con, sql, f$params)
}

# Opciones para los filtros: devuelve data.frames pequenos, no toda la base.
opciones_db <- function(con) {
  list(
    comercios = consulta_db(con,
      "SELECT nombre FROM comercios ORDER BY nombre")$nombre,
    marcas = consulta_db(con,
      "SELECT DISTINCT marca_estandar AS valor FROM v_ultimo_precio
       WHERE marca_estandar IS NOT NULL AND trim(marca_estandar) <> ''
       ORDER BY valor")$valor,
    subcategorias = consulta_db(con,
      "SELECT DISTINCT subcategoria_estandar AS valor FROM v_ultimo_precio
       WHERE subcategoria_estandar IS NOT NULL AND trim(subcategoria_estandar) <> ''
       ORDER BY valor")$valor,
    productos = consulta_db(con,
      "SELECT producto_comun_id, producto_comun
       FROM productos_comunes ORDER BY producto_comun")
  )
}

# Tabla paginada y filtrada en SQLite. La interfaz nunca carga toda la tabla.
tabla_precios_db <- function(con, filtros = list(), limite = 100L, pagina = 1L) {
  if (length(limite) != 1L || is.na(limite) || limite < 1L || limite > 1000L ||
      limite != as.integer(limite)) stop("limite debe estar entre 1 y 1000")
  if (length(pagina) != 1L || is.na(pagina) || pagina < 1L ||
      pagina != as.integer(pagina)) stop("pagina invalida")
  f <- preparar_filtros_db(filtros)
  sql <- paste0("
    SELECT p.comercio, p.producto_original, p.marca_estandar,
           p.subcategoria_estandar,
           COALESCE(NULLIF(TRIM(a.presentacion_original), ''),
                    CASE WHEN p.contenido_valor_estandar > 0
                       THEN CAST(p.contenido_valor_estandar AS TEXT) || ' ' || COALESCE(p.unidad_estandar, '')
                       ELSE NULL END) AS presentacion,
           p.precio_cop,
           CASE WHEN p.comparable = 1 AND p.contenido_valor_estandar > 0
                THEN ROUND(p.precio_cop / p.contenido_valor_estandar, 2)
                ELSE NULL END AS precio_unitario_cop,
           p.unidad_estandar AS unidad_contenido,
           p.precio_antes_cop, p.promocion, p.comparable,
           p.fecha_hora_consulta, p.estado_disponibilidad,
           p.url, p.ejecucion_id
    FROM v_ultimo_precio p
    LEFT JOIN anuncios a ON a.ejecucion_id = p.ejecucion_id
      AND a.comercio_id = p.comercio_id
      AND a.producto_comercio_id = p.producto_comercio_id ", f$sql, "
    ORDER BY p.fecha_hora_consulta DESC, p.comercio, p.producto_original
    LIMIT ? OFFSET ?")
  parametros <- c(f$params, list(as.integer(limite),
                                 as.integer((pagina - 1L) * limite)))
  consulta_db(con, sql, parametros)
}

# Gráfico 1: precios promedio diarios por comercio para comparables.
serie_comparables_db <- function(con, producto_comun_id = NULL) {
  condicion <- ""
  parametros <- list()
  if (!is.null(producto_comun_id) && length(producto_comun_id)) {
    if (length(producto_comun_id) != 1L || is.na(producto_comun_id))
      stop("Seleccione un producto comparable")
    condicion <- "AND a.producto_comun_id = ?"
    parametros <- list(as.character(producto_comun_id))
  }
  sql <- paste0("
    SELECT substr(o.fecha_hora_consulta, 1, 10) AS fecha,
           c.nombre AS comercio,
           ROUND(AVG(o.precio_cop), 2) AS precio_promedio_cop,
           COUNT(*) AS observaciones
    FROM observaciones o
    JOIN anuncios a ON a.ejecucion_id = o.ejecucion_id
       AND a.comercio_id = o.comercio_id
       AND a.producto_comercio_id = o.producto_comercio_id
    JOIN comercios c ON c.comercio_id = o.comercio_id
    WHERE a.comparable = 1 AND a.incluido_categoria = 1
      AND o.precio_cop > 0 AND o.estado_validacion <> 'rechazada'
      ", condicion, "
    GROUP BY substr(o.fecha_hora_consulta, 1, 10), c.nombre
    ORDER BY fecha, comercio")
  consulta_db(con, sql, parametros)
}

# Gráfico 2 y canasta posterior: precio por unidad de los comparables.
comparables_db <- function(con, comercio = NULL, producto_comun_id = NULL) {
  condiciones <- character()
  parametros <- list()
  if (!is.null(comercio) && length(comercio)) {
    comercio <- unique(as.character(comercio))
    if (length(comercio) > 20L) stop("Demasiados comercios")
    condiciones <- c(condiciones, paste0("comercio IN (",
      paste(rep("?", length(comercio)), collapse = ","), ")"))
    parametros <- c(parametros, as.list(comercio))
  }
  if (!is.null(producto_comun_id) && length(producto_comun_id)) {
    producto_comun_id <- unique(as.character(producto_comun_id))
    if (length(producto_comun_id) > 50L) stop("Demasiados productos")
    condiciones <- c(condiciones, paste0("producto_comun_id IN (",
      paste(rep("?", length(producto_comun_id)), collapse = ","), ")"))
    parametros <- c(parametros, as.list(producto_comun_id))
  }
  sql <- paste0("SELECT * FROM v_comparables",
    if (length(condiciones)) paste(" WHERE", paste(condiciones, collapse = " AND ")) else "",
    " ORDER BY producto_comun, comercio")
  consulta_db(con, sql, parametros)
}

# Gráfico 3: resumen de precios agrupados por comercio.
distribucion_db <- function(con, filtros = list(), ancho = 20000) {
  if (length(ancho) != 1L || is.na(ancho) || !is.finite(ancho) || ancho <= 0)
    stop("Ancho de intervalo invalido")
  f <- preparar_filtros_db(filtros)
  sql <- paste0("
    SELECT p.comercio,
           CAST(p.precio_cop / ? AS INTEGER) * ? AS precio_desde_cop,
           COUNT(*) AS cantidad
    FROM v_ultimo_precio p ", f$sql, "
    GROUP BY p.comercio, CAST(p.precio_cop / ? AS INTEGER)
    ORDER BY precio_desde_cop, p.comercio")
  consulta_db(con, sql, c(list(ancho, ancho), f$params, list(ancho)))
}

# Gráfico 4: precios por subcategoria desde SQLite.
subcategorias_db <- function(con, filtros = list(), limite = 15L) {
  if (length(limite) != 1L || is.na(limite) || limite < 1L || limite > 100L)
    stop("Limite fuera de rango")
  f <- preparar_filtros_db(filtros)
  sql <- paste0("
    SELECT COALESCE(NULLIF(p.subcategoria_estandar, ''), 'Sin clasificar')
             AS subcategoria,
           COUNT(*) AS ofertas,
           ROUND(AVG(p.precio_cop), 2) AS precio_promedio_cop
    FROM v_ultimo_precio p ", f$sql, "
    GROUP BY COALESCE(NULLIF(p.subcategoria_estandar, ''), 'Sin clasificar')
    ORDER BY ofertas DESC LIMIT ?")
  consulta_db(con, sql, c(f$params, list(as.integer(limite))))
}

# No confundir cantidad de comparaciones con cantidad de cambios efectivos.
resumen_cambios_db <- function(con) {
  consulta_db(con, "
    SELECT COUNT(*) AS comparaciones,
           SUM(CASE WHEN cambio_cop <> 0 THEN 1 ELSE 0 END) AS cambios_efectivos,
           SUM(CASE WHEN cambio_cop > 0 THEN 1 ELSE 0 END) AS aumentos,
           SUM(CASE WHEN cambio_cop < 0 THEN 1 ELSE 0 END) AS disminuciones,
           SUM(CASE WHEN cambio_cop = 0 THEN 1 ELSE 0 END) AS sin_cambio
    FROM v_cambios_precio")
}

cambios_detalle_db <- function(con, solo_cambios = TRUE, limite = 500L) {
  if (length(limite) != 1L || is.na(limite) || limite < 1L || limite > 2000L)
    stop("Limite fuera de rango")
  sql <- paste0("
    SELECT comercio, producto_original, fecha_hora_anterior,
           fecha_hora_actual, precio_anterior_cop, precio_actual_cop,
           cambio_cop, cambio_pct, comparable
    FROM v_cambios_precio",
    if (isTRUE(solo_cambios)) " WHERE cambio_cop <> 0" else "",
    " ORDER BY ABS(cambio_cop) DESC LIMIT ?")
  consulta_db(con, sql, list(as.integer(limite)))
}

ejecuciones_db <- function(con) {
  consulta_db(con, "
    SELECT c.nombre AS comercio, e.ejecucion_id,
           e.fecha_hora_inicio, e.fecha_hora_fin,
           e.modo, e.estado, e.raw_dir,
           COUNT(o.observacion_id) AS observaciones
    FROM ejecuciones e
    JOIN comercios c ON c.comercio_id = e.comercio_id
    LEFT JOIN observaciones o ON o.ejecucion_id = e.ejecucion_id
       AND o.comercio_id = e.comercio_id
    GROUP BY c.comercio_id, e.ejecucion_id
    ORDER BY e.fecha_hora_inicio DESC")
}

# Demostracion de lectura. No cambia SQLite ni consulta sitios web.
probar_db_taller2 <- function(ruta = "comparador_precios.sqlite") {
  con <- abrir_db(ruta)
  on.exit(cerrar_db(con), add = TRUE)
  cat("\n=== PASO 20: MODULO db.R ===\n")
  cat("\nIndicadores SQL:\n")
  print(indicadores_db(con))
  cat("\nCambios de precio:\n")
  print(resumen_cambios_db(con))
  cat("\nComparables por comercio:\n")
  print(consulta_db(con, "
    SELECT comercio, COUNT(*) AS comparables,
           COUNT(precio_por_unidad_cop) AS unitarios_validos
    FROM v_comparables GROUP BY comercio ORDER BY comercio"))
  cat("\nHistorial por comercio:\n")
  print(serie_comparables_db(con))
  invisible(TRUE)
}
