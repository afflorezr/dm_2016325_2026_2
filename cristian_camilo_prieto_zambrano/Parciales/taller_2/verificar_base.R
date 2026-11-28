# =============================================================================
# verificar_base.R — Taller parcial 2, Minería de Datos (UNAL)
# Cristian Camilo Prieto Zambrano
#
# Informe del estado de la base: estructura, ejecuciones, observaciones,
# comparables, rechazos, correcciones, calidad y trazabilidad hasta raw/.
# Solo consulta; no modifica datos (crear_base() solo crea lo que falte y
# recrea las vistas).
#
# Uso, desde la carpeta taller_2:
#   source("verificar_base.R")                        # base de la entrega
#   verificar_base("otra_base.sqlite")                # otra base
# Al final imprime cada comprobación con OK o FALLA.
# =============================================================================

source("db.R")

verificar_base <- function(db = "comparador_precios.sqlite", dir_raw = "raw") {
  if (!file.exists(db)) stop("No existe la base ", db)
  con <- crear_base(db)
  on.exit(dbDisconnect(con), add = TRUE)
  q <- function(sql) dbGetQuery(con, sql)
  titulo <- function(t) cat("\n", strrep("=", 78), "\n ", t, "\n", strrep("=", 78), "\n", sep = "")
  ver <- function(x) print(x, row.names = FALSE)
  comprobaciones <- list()
  comprobar <- function(nombre, ok, detalle = "") {
    comprobaciones[[length(comprobaciones) + 1]] <<- data.frame(
      resultado = if (isTRUE(ok)) "OK" else "FALLA", comprobacion = nombre, detalle = detalle)
  }

  # --- 1. Estructura -----------------------------------------------------------
  titulo("1. Estructura")
  version  <- q("PRAGMA user_version")[[1]]
  integ    <- q("PRAGMA integrity_check")[[1]][1]
  fk       <- nrow(q("PRAGMA foreign_key_check"))
  objetos  <- q("SELECT type, name FROM sqlite_master
                 WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name")
  cat("Versión del esquema:", version, "| integridad:", integ,
      "| referencias rotas:", fk, "\n")
  ver(objetos)
  comprobar("Esquema en la versión actual", version == VERSION_ESQUEMA, paste("versión", version))
  comprobar("Integridad del archivo", integ == "ok")
  comprobar("Sin referencias rotas (claves foráneas)", fk == 0, paste(fk, "filas"))
  comprobar("Al menos tres vistas", sum(objetos$type == "view") >= 3,
            paste(sum(objetos$type == "view"), "vistas"))

  # --- 2. Ejecuciones ----------------------------------------------------------
  titulo("2. Ejecuciones")
  ej <- q("SELECT id_ejecucion, corrida, comercio, fecha, estado, modo, n_registros,
                  total_sitio, n_observaciones, n_rechazos, vigente, motivo
           FROM v_ejecuciones ORDER BY id_ejecucion")
  ver(ej)
  completas <- q("SELECT corrida, MIN(fecha) AS fecha FROM v_ejecuciones
                  WHERE estado = 'completa'
                  GROUP BY corrida HAVING COUNT(DISTINCT id_comercio) = 3")
  cat("\nCorridas completas en los tres comercios:\n"); ver(completas)
  comprobar("Dos o más corridas completas en fechas distintas",
            length(unique(completas$fecha)) >= 2,
            paste(length(unique(completas$fecha)), "fechas"))

  # --- 3. Observaciones --------------------------------------------------------
  titulo("3. Observaciones por ejecución")
  ver(q("SELECT o.id_ejecucion, e.id_comercio, e.corrida,
                COUNT(*) AS total,
                SUM(o.descartada = 1) AS descartadas,
                SUM(o.descartada = 0 AND a.excluido = 0) AS de_la_categoria,
                SUM(o.precio IS NULL) AS sin_precio,
                SUM(o.disponibilidad = 'agotado') AS agotadas
         FROM observaciones o
         JOIN anuncios a USING (id_anuncio)
         JOIN ejecuciones e USING (id_ejecucion)
         GROUP BY o.id_ejecucion ORDER BY o.id_ejecucion"))

  # --- 4. Comparables ----------------------------------------------------------
  titulo("4. Comparables con precio y presentación correcta")
  comp <- q("SELECT corrida, id_comercio, SUM(precio IS NOT NULL AND coincide = 1) AS con_precio
             FROM v_comparables GROUP BY corrida, id_comercio ORDER BY corrida, id_comercio")
  ver(comp)
  minimo <- if (exists("MIN_COMPARABLES")) MIN_COMPARABLES else 8L
  bajas <- comp[comp$con_precio < minimo, ]
  comprobar(sprintf("Cada comercio con al menos %d comparables con precio en cada corrida", minimo),
            nrow(bajas) == 0,
            if (nrow(bajas) == 0) "" else paste(bajas$corrida, bajas$id_comercio, collapse = "; "))

  # --- 5. Rechazos y correcciones ----------------------------------------------
  titulo("5. Rechazos de la validación")
  ver(q("SELECT id_ejecucion, id_comercio, regla, COUNT(*) AS n FROM rechazos
         GROUP BY id_ejecucion, id_comercio, regla ORDER BY id_ejecucion"))
  titulo("6. Correcciones registradas")
  ver(q("SELECT tabla, campo, COUNT(*) AS n FROM correcciones GROUP BY tabla, campo"))

  # --- 7. Calidad --------------------------------------------------------------
  titulo("7. Calidad de los datos")
  calidad <- q("
    SELECT
      (SELECT COUNT(*) FROM anuncios WHERE excluido = 0
          AND subcategoria_std = 'Otro (revisar)')                                AS sin_subcategoria,
      (SELECT COUNT(*) FROM observaciones WHERE precio IS NOT NULL AND precio <= 0) AS precios_no_positivos,
      (SELECT COUNT(*) FROM (SELECT 1 FROM observaciones
          GROUP BY id_anuncio, id_ejecucion HAVING COUNT(*) > 1))                 AS duplicadas,
      (SELECT COUNT(*) FROM observaciones o JOIN anuncios a USING (id_anuncio)
          WHERE o.descartada = 0 AND (a.url IS NULL OR a.url = ''))               AS validas_sin_url,
      (SELECT COUNT(*) FROM observaciones WHERE disponibilidad IS NULL)           AS sin_disponibilidad,
      (SELECT COUNT(*) FROM v_comparables WHERE coincide = 0)                     AS comparables_otra_presentacion")
  ver(calidad)
  comprobar("Anuncios de la categoría con subcategoría asignada", calidad$sin_subcategoria == 0,
            paste(calidad$sin_subcategoria, "en 'Otro (revisar)'"))
  comprobar("Precios presentes mayores que cero", calidad$precios_no_positivos == 0)
  comprobar("Sin observaciones duplicadas por anuncio y ejecución", calidad$duplicadas == 0)
  comprobar("Observaciones válidas con URL", calidad$validas_sin_url == 0)
  comprobar("Disponibilidad registrada en todas las observaciones", calidad$sin_disponibilidad == 0)

  # --- 8. Trazabilidad hasta raw/ ----------------------------------------------
  titulo("8. Trazabilidad: copias crudas de cada ejecución")
  traz <- q("SELECT DISTINCT e.corrida, e.id_comercio FROM ejecuciones e
             WHERE EXISTS (SELECT 1 FROM observaciones o WHERE o.id_ejecucion = e.id_ejecucion)")
  traz$carpeta  <- file.path(dir_raw, traz$id_comercio, traz$corrida)
  traz$archivos <- vapply(traz$carpeta, function(d)
    length(list.files(d, pattern = "\\.json\\.gz$")), integer(1))
  traz$totales  <- file.exists(file.path(traz$carpeta, "totales.csv"))
  ver(traz)
  sin_raw <- traz[traz$archivos == 0, ]
  comprobar("Cada ejecución cargada tiene sus copias crudas en raw/", nrow(sin_raw) == 0,
            if (nrow(sin_raw) == 0) "" else paste(sin_raw$carpeta, collapse = "; "))

  # Cada hora de consulta debe corresponder a un archivo de raw/
  horas <- q("SELECT DISTINCT e.corrida, e.id_comercio, o.fecha_hora_consulta
              FROM observaciones o JOIN ejecuciones e USING (id_ejecucion)")
  marca <- gsub(":", "", horas$fecha_hora_consulta)
  con_archivo <- mapply(function(d, m) length(list.files(d, pattern = paste0("__", m, "\\.json\\.gz$"))) > 0,
                        file.path(dir_raw, horas$id_comercio, horas$corrida), marca)
  comprobar("Cada hora de consulta tiene su copia cruda", all(con_archivo),
            sprintf("%d de %d horas con archivo", sum(con_archivo), length(con_archivo)))

  # --- Resumen -----------------------------------------------------------------
  titulo("Resumen de comprobaciones")
  resumen <- do.call(rbind, comprobaciones)
  ver(resumen)
  cat("\n", sum(resumen$resultado == "OK"), "de", nrow(resumen), "comprobaciones superadas.\n")
  invisible(resumen)
}

verificar_base()
