# =============================================================================
# migracion.R — Taller 2, sección 3.2: corrección de la base del Taller 1
#
# Se ejecuta UNA vez desde la carpeta taller_2/ (repetirlo no cambia nada):
#   source("migracion.R")
#
# 1. Crea las tablas, columnas, índices y vistas nuevas (crear_esquema() de
#    scraper.R).
# 2. Corrige los errores encontrados en la base del Taller 1. Cada cambio queda
#    en la tabla `correcciones` (fecha, registro, valor anterior, valor nuevo,
#    motivo). No se borra ninguna observación.
# =============================================================================
source("scraper.R", encoding = "UTF-8")

registrar_correccion <- function(con, tabla, registro, campo, anterior, nuevo, motivo) {
  dbExecute(con, "
    INSERT OR IGNORE INTO correcciones
      (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo)
    VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(ahora_co(), tabla, registro, campo,
                  as.character(anterior), as.character(nuevo), motivo))
}

migrar_taller1 <- function(db = DB_PATH) {
  con <- conectar_db(db)                     # aplica el esquema del Taller 2
  on.exit(dbDisconnect(con), add = TRUE)
  n <- 0L

  dbWithTransaction(con, {
    # -- 1. Modo, inicio y fin de las ejecuciones del Taller 1 ----------------
    # Las corridas 20261011T204915 y 20261011T205340 se hicieron en línea (la
    # hora de consulta de cada copia cruda es la de la corrida), pero al
    # reprocesarlas sin conexión registrar_ejecucion() sobrescribió el modo
    # y el inicio/fin con la hora del reproceso. Se restauran a partir de la
    # primera y la última hora de consulta de las observaciones de cada una.
    ej <- dbGetQuery(con, "
      SELECT e.id_ejecucion, e.comercio, e.modo, e.inicio, e.fin,
             MIN(o.fecha_hora_consulta) AS primera, MAX(o.fecha_hora_consulta) AS ultima
      FROM ejecuciones e
      JOIN observaciones o ON o.id_ejecucion = e.id_ejecucion AND o.comercio = e.comercio
      WHERE e.modo = 'sin_conexion' AND e.id_ejecucion < '20261101'
      GROUP BY e.id_ejecucion, e.comercio")
    for (i in seq_len(nrow(ej))) {
      r <- ej[i, ]
      clave <- paste(r$id_ejecucion, r$comercio, sep = "/")
      motivo <- paste("Corrida hecha en línea; el reproceso sin conexión del Taller 1",
                      "sobrescribió modo, inicio y fin. Se toman de las horas de consulta",
                      "de sus copias crudas en raw/.")
      registrar_correccion(con, "ejecuciones", clave, "modo", r$modo, "en_linea", motivo)
      registrar_correccion(con, "ejecuciones", clave, "inicio", r$inicio, r$primera, motivo)
      registrar_correccion(con, "ejecuciones", clave, "fin", r$fin, r$ultima, motivo)
      dbExecute(con, "
        UPDATE ejecuciones SET modo = 'en_linea', inicio = ?, fin = ?
        WHERE id_ejecucion = ? AND comercio = ?",
        params = list(r$primera, r$ultima, r$id_ejecucion, r$comercio))
      n <- n + 3L
    }

    # -- 2. Contenido faltante de estuches y limpiadores de gafas -------------
    # Son artículos contables; en el Taller 1 quedaban sin contenido ni unidad,
    # por lo que no tenían precio unitario. scraper.R ya los clasifica así.
    sin_cont <- dbGetQuery(con, "
      SELECT comercio, sku, contenido, unidad, COALESCE(n_unidades, 1) AS n
      FROM anuncios
      WHERE en_categoria = 1 AND contenido IS NULL
        AND subcategoria_std IN ('Estuches', 'Limpieza de gafas')")
    for (i in seq_len(nrow(sin_cont))) {
      r <- sin_cont[i, ]
      clave <- paste(r$comercio, r$sku, sep = "/")
      motivo <- "Campo faltante: artículo contable sin contenido en mL/g; se registra en unidades"
      registrar_correccion(con, "anuncios", clave, "contenido", r$contenido, r$n, motivo)
      registrar_correccion(con, "anuncios", clave, "unidad", r$unidad, "und", motivo)
      dbExecute(con, "UPDATE anuncios SET contenido = ?, unidad = 'und'
                      WHERE comercio = ? AND sku = ?",
                params = list(r$n, r$comercio, r$sku))
      n <- n + 2L
    }

    # -- 3. Marca faltante: Colsubsidio escribe "Foster Gran" -----------------
    sin_marca <- dbGetQuery(con, "
      SELECT comercio, sku, marca_std FROM anuncios
      WHERE marca_std IS NULL AND LOWER(nombre_original) LIKE '%foster gran%'")
    for (i in seq_len(nrow(sin_marca))) {
      r <- sin_marca[i, ]
      registrar_correccion(con, "anuncios", paste(r$comercio, r$sku, sep = "/"),
                           "marca_std", NA, "FOSTER GRANT",
                           "Campo faltante: el nombre trae la marca abreviada 'Foster Gran'")
      dbExecute(con, "UPDATE anuncios SET marca_std = 'FOSTER GRANT'
                      WHERE comercio = ? AND sku = ?", params = list(r$comercio, r$sku))
      n <- n + 1L
    }
  })
  message(n, " correcciones aplicadas. Total en la tabla: ",
          dbGetQuery(con, "SELECT COUNT(*) AS n FROM correcciones")$n)
  invisible(n)
}

migrar_taller1()
