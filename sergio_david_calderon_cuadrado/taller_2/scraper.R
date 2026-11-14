# =====================================================================
# scraper.R -- Carga de datos a la base (sin efectos al hacer source()).
#
# Contiene las definiciones puras tomadas SIN CAMBIOS de scraper_general_1.R y
# sqlite_scraper.R (Taller 1), mas ejecutar_recoleccion(), que es lo unico que llama la app.
# El unico cambio a guardar_en_sqlite() esta marcado con "[Taller 2]".
# Modo "respaldo" (sin conexion): reprocesa raw/ de forma idempotente.
# Modo "scrape" (en linea): requiere Chrome/Brave y chromote; aun no esta integrado.
# La app NO carga este archivo al iniciar: se carga bajo demanda desde el boton.
# =====================================================================
suppressPackageStartupMessages({ library(dplyr); library(tidyr) })
`%>%` <- magrittr::`%>%`


COLUMNAS_FINALES <- c(
  "comercio", "busqueda", "id_ejecucion", "fecha_consulta",
  "sku", "nombres", "marca", "presentacion", "envase",
  "medida", "cantidad_unidad", "unidades", "cantidad_total",
  "precio_lista_cop", "precio_real_cop", "oferta_general", "precio_medida",
  "url", "texto_original_anuncio"
)

TIPOS_COLUMNAS <- c(
  comercio = "character", busqueda = "character", id_ejecucion = "character",
  fecha_consulta = "character", sku = "character", nombres = "character",
  marca = "character", presentacion = "character", envase = "character",
  medida = "character", cantidad_unidad = "numeric", unidades = "numeric",
  cantidad_total = "numeric", precio_lista_cop = "integer", precio_real_cop = "integer",
  oferta_general = "integer", precio_medida = "numeric", url = "character",
  texto_original_anuncio = "character"
)

tipificar_base <- function(df) {
  faltan <- setdiff(COLUMNAS_FINALES, names(df))
  if (length(faltan) > 0) {
    stop("Faltan columnas del esquema final: ", paste(faltan, collapse = ", "), call. = FALSE)
  }
  df <- dplyr::select(tibble::as_tibble(df), dplyr::all_of(COLUMNAS_FINALES))
  for (col in COLUMNAS_FINALES) {
    df[[col]] <- switch(TIPOS_COLUMNAS[[col]],
                        character = as.character(df[[col]]),
                        integer   = suppressWarnings(as.integer(df[[col]])),
                        numeric   = suppressWarnings(as.numeric(df[[col]])))
  }
  df
}

normalizar_texto <- function(x) {
  x <- tolower(x)
  x <- chartr("áéíóúüñ", "aeiouun", x)
  trimws(gsub("\\s+", " ", x))
}

leer_respaldos <- function(dir_raw, comercios) {
  piezas <- list()
  for (cmn in comercios) {
    ruta <- file.path(dir_raw, paste0("resultado_seguro_", cmn, ".csv"))
    if (!file.exists(ruta)) { warning("No existe el respaldo de ", cmn, ": ", ruta, call. = FALSE); next }
    d <- read.csv(ruta, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE,
                  encoding = "UTF-8")
    if (!identical(names(d), COLUMNAS_FINALES)) {
      warning("El respaldo de ", cmn, " no tiene el esquema final (se omite): ", ruta, call. = FALSE)
      next
    }
    cat("  respaldo leido:", basename(ruta), "->", nrow(d), "filas\n")
    piezas[[cmn]] <- tipificar_base(d)
  }
  if (length(piezas) == 0) stop("No se pudo leer ningun respaldo en: ", dir_raw, call. = FALSE)
  dplyr::bind_rows(piezas)
}

CATALOGO_COMPARABLES <- tibble::tribble(
  ~id_producto, ~producto_comparable,                     ~exito,    ~farmatodo,  ~larebaja,
  1L, "Lubriderm humectación diaria 200 ml",              "3155351", "293400550", "3493",
  2L, "Lubriderm humectación diaria 400 ml",              "3155352", "293400592", "2589",
  3L, "Lubriderm humectación diaria 946 ml",              "3155353", "291550571", "9796",
  4L, "Lubriderm humectación delicada 400 ml",            "3179125", "203000123", "2642",
  5L, "Lubriderm reparación intensiva 946 ml",            "869499",  "1046197",   "9795",
  6L, "Lubriderm humectación diaria 120 ml",              "3155350", "293400568", "2588",
  7L, "Lubriderm FPS 15 200 ml",                          "311800",  "1015664",   "3494",
  8L, "Lubriderm FPS 15 400 ml",                          "128396",  "213300197", "4608",
  9L, "Nivea hidratación express 1000 ml",                "283481",  "1043756",   "1431"
)

catalogo_largo <- CATALOGO_COMPARABLES %>%
  tidyr::pivot_longer(-c(id_producto, producto_comparable),
                      names_to = "comercio", values_to = "sku") %>%
  filter(!is.na(sku))

NOMBRES_COMERCIO <- c(exito = "\u00c9xito", farmatodo = "Farmatodo", larebaja = "La Rebaja")

SITIOS_COMERCIO  <- c(exito = "https://www.exito.com",
                      farmatodo = "https://www.farmatodo.com.co",
                      larebaja = "https://www.larebajavirtual.com")

MARCAS_ALIAS <- c("NIVEA SUN" = "NIVEA", "LUBRIDERM FPS" = "LUBRIDERM")

RX_ISO8601 <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$"

marcar_comparables <- function(base) {
  cat_sku <- catalogo_largo %>%
    dplyr::transmute(comercio, .sku_limpio = trimws(sku),
                     id_producto = as.integer(id_producto), producto_comparable)
  base %>%
    dplyr::select(-dplyr::any_of(c("es_comparable", "id_producto", "producto_comparable"))) %>%
    dplyr::mutate(.sku_limpio = trimws(sku)) %>%
    dplyr::left_join(cat_sku, by = c("comercio", ".sku_limpio")) %>%
    dplyr::mutate(es_comparable = as.integer(!is.na(id_producto))) %>%
    dplyr::select(-.sku_limpio) %>%
    dplyr::relocate(es_comparable, id_producto, producto_comparable, .after = busqueda)
}

estandarizar_marca <- function(x) {
  m <- toupper(normalizar_texto(x))
  m <- trimws(gsub("[^A-Z0-9 ]", "", m))
  m[!nzchar(m)] <- NA_character_
  alias <- m %in% names(MARCAS_ALIAS)
  m[alias] <- unname(MARCAS_ALIAS[m[alias]])
  m
}

estandarizar_subcategoria <- function(nombres) {
  n <- normalizar_texto(nombres)
  dplyr::case_when(
    grepl("\\b(exfoliante|scrub)\\b", n)                                      ~ "exfoliante_corporal",
    grepl("\\b(crema|cremas|locion|leche|mantequilla|emulsion|hidratante)\\b", n) ~ "crema_corporal",
    grepl("\\baceite", n)                                                     ~ "aceite_corporal",
    TRUE                                                                      ~ "otros_corporal"
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

iso_desde_codigo <- function(codigo) {
  t <- as.POSIXct(codigo, format = "%Y%m%d%H%M%S", tz = "America/Bogota")
  f <- format(t, "%Y-%m-%dT%H:%M:%S%z", tz = "America/Bogota")
  sub("(\\d{2})(\\d{2})$", "\\1:\\2", f)
}

leer_log_csv <- function(ruta) {
  if (!file.exists(ruta)) return(NULL)
  tryCatch(read.csv(ruta, stringsAsFactors = FALSE, colClasses = "character"),
           error = function(e) NULL)
}

calcular_estado <- function(n, log_cm, n_faltan_catalogo) {
  errores <- log_cm$estado[log_cm$estado != "ok"]
  if (n == 0 || any(log_cm$estado == "error_comercio")) {
    return(list(estado = "fallida",
                mensaje = (log_cm$mensaje[!is.na(log_cm$mensaje) & nzchar(log_cm$mensaje)])[1] %||%
                  "sin registros"))
  }
  partes <- character(0)
  if (nrow(log_cm) == 0)       partes <- c(partes, "sin log de consultas para esta corrida")
  if (length(errores) > 0)     partes <- c(partes, sprintf("%d consulta(s) sin 'ok'", length(errores)))
  if (n_faltan_catalogo > 0)   partes <- c(partes, sprintf("%d producto(s) del catalogo sin precio", n_faltan_catalogo))
  if (length(partes) > 0) return(list(estado = "parcial", mensaje = paste(partes, collapse = "; ")))
  list(estado = "completa", mensaje = NA_character_)
}

asegurar_comercios <- function(con, codigos) {
  codigos <- unique(codigos[!is.na(codigos)])
  if (length(codigos) == 0) return(invisible(NULL))
  nombre <- ifelse(codigos %in% names(NOMBRES_COMERCIO), NOMBRES_COMERCIO[codigos], codigos)
  sitio  <- ifelse(codigos %in% names(SITIOS_COMERCIO),  SITIOS_COMERCIO[codigos],  NA_character_)
  DBI::dbExecute(con,
    "INSERT INTO comercios (codigo, nombre, sitio_web) VALUES (?, ?, ?)
     ON CONFLICT (codigo) DO NOTHING",
    params = list(codigos, unname(nombre), unname(sitio)))
  invisible(NULL)
}

guardar_en_sqlite <- function(con, base, log = NULL) {
  base <- tibble::as_tibble(base)
  if (!"url_extraccion" %in% names(base)) {
    # el scraper aun no guarda la URL de la pagina de busqueda: se usa la del producto
    base$url_extraccion <- base$url
  }

  # ---- 1. depuracion previa (lo que violaria el esquema se informa, no se oculta) ----
  base <- base %>%
    dplyr::mutate(sku = trimws(sku)) %>%
    dplyr::arrange(fecha_consulta)
  valida <- !is.na(base$sku) & nzchar(base$sku) & !is.na(base$nombres) &
    !is.na(base$precio_real_cop) & !is.na(base$precio_lista_cop) &
    base$precio_real_cop > 0 & base$precio_lista_cop > 0 &
    grepl(RX_ISO8601, base$fecha_consulta %||% "") & !is.na(base$url_extraccion)
  if (any(!valida)) {
    cat("!! ", sum(!valida), " fila(s) NO se guardan (sin sku, nombre, precio, fecha ISO 8601 o url):\n", sep = "")
    print(utils::head(base[!valida, c("comercio", "sku", "nombres", "precio_real_cop", "fecha_consulta")], 10))
  }
  descartadas <- base[!valida, ]
  base <- base[valida, ]

  # ---- 2. comparables: columna es_comparable / id_producto de la base general ----
  base <- marcar_comparables(base)
  cat(sprintf("Comparables en esta carga: %d de %d fila(s) validas\n", sum(base$es_comparable), nrow(base)))

  runs <- dplyr::bind_rows(
    dplyr::distinct(base, codigo_corrida = id_ejecucion, comercio),
    if (!is.null(log) && nrow(log) > 0) {
      dplyr::distinct(log[!is.na(log$comercio) & !is.na(log$id_ejecucion), ],
                      codigo_corrida = id_ejecucion, comercio)
    })
  runs <- dplyr::distinct(runs)
  ids_conjunto <- DBI::dbGetQuery(con, "SELECT id_producto FROM productos WHERE en_conjunto = 1")$id_producto  # [Taller 2]

  res <- DBI::dbWithTransaction(con, {

    asegurar_comercios(con, c(runs$comercio, base$comercio))
    cmap <- DBI::dbGetQuery(con, "SELECT id_comercio, codigo AS comercio FROM comercios")

    # ---- 3. ejecuciones (estado y n_registros se completan al final) ----
    runs <- dplyr::left_join(runs, cmap, by = "comercio")
    runs$fecha_hora_inicio <- iso_desde_codigo(runs$codigo_corrida)
    DBI::dbExecute(con,
      "INSERT INTO ejecuciones (codigo_corrida, id_comercio, fecha_hora_inicio, estado)
       VALUES (?, ?, ?, 'fallida')
       ON CONFLICT (codigo_corrida, id_comercio) DO NOTHING",
      params = list(runs$codigo_corrida, runs$id_comercio, runs$fecha_hora_inicio))
    emap <- DBI::dbGetQuery(con,
      "SELECT id_ejecucion, codigo_corrida, id_comercio FROM ejecuciones")

    # ---- 4. anuncios: atributos = ultima vez visto; texto_original = primera vez ----
    anu <- base %>%
      dplyr::group_by(comercio, sku) %>%
      dplyr::summarise(
        nombre_original       = dplyr::last(nombres),
        presentacion_original = dplyr::last(presentacion),
        marca_original        = dplyr::last(marca),
        envase                = dplyr::last(envase),
        medida                = dplyr::last(medida),
        cantidad_unidad       = dplyr::last(cantidad_unidad),
        unidades              = dplyr::last(unidades),
        cantidad_total        = dplyr::last(cantidad_total),
        url_producto          = dplyr::last(url),
        texto_original        = dplyr::first(texto_original_anuncio),
        primera_consulta      = dplyr::first(fecha_consulta),
        ultima_consulta       = dplyr::last(fecha_consulta),
        .groups = "drop") %>%
      dplyr::mutate(marca_std        = estandarizar_marca(marca_original),
                    subcategoria_std = estandarizar_subcategoria(nombre_original)) %>%
      dplyr::left_join(cmap, by = "comercio")

    # los vinculos con el catalogo se rehacen siempre (por si cambia un SKU)
    DBI::dbExecute(con, "UPDATE anuncios SET id_producto = NULL WHERE id_producto IS NOT NULL")

    if (nrow(anu) > 0) {
      DBI::dbExecute(con,
        "INSERT INTO anuncios (id_comercio, sku, nombre_original, presentacion_original,
                               marca_original, marca_std, subcategoria_std, envase, medida,
                               cantidad_unidad, unidades, cantidad_total, url_producto,
                               texto_original, primera_consulta, ultima_consulta)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (id_comercio, sku) DO UPDATE SET
           nombre_original = excluded.nombre_original,
           presentacion_original = excluded.presentacion_original,
           marca_original = excluded.marca_original, marca_std = excluded.marca_std,
           subcategoria_std = excluded.subcategoria_std, envase = excluded.envase,
           medida = excluded.medida, cantidad_unidad = excluded.cantidad_unidad,
           unidades = excluded.unidades, cantidad_total = excluded.cantidad_total,
           url_producto = excluded.url_producto,
           primera_consulta = MIN(anuncios.primera_consulta, excluded.primera_consulta),
           ultima_consulta  = MAX(anuncios.ultima_consulta,  excluded.ultima_consulta)",
        params = unname(as.list(anu[, c("id_comercio", "sku", "nombre_original",
          "presentacion_original", "marca_original", "marca_std", "subcategoria_std",
          "envase", "medida", "cantidad_unidad", "unidades", "cantidad_total",
          "url_producto", "texto_original", "primera_consulta", "ultima_consulta")])))
    }

    # vinculo con el catalogo: marca y subcategoria de los comparables vienen de `productos`
    for (i in seq_len(nrow(catalogo_largo))) {
      DBI::dbExecute(con,
        "UPDATE anuncios
            SET id_producto      = :id,
                marca_std        = (SELECT marca_std        FROM productos WHERE id_producto = :id),
                subcategoria_std = (SELECT subcategoria_std FROM productos WHERE id_producto = :id)
          WHERE sku = :sku
            AND id_comercio = (SELECT id_comercio FROM comercios WHERE codigo = :cm)",
        params = list(id = as.integer(catalogo_largo$id_producto[i]),
                      sku = trimws(catalogo_largo$sku[i]),
                      cm  = catalogo_largo$comercio[i]))
    }

    # control: el SKU del catalogo debe tener el mismo contenido que el producto comun
    desajuste <- DBI::dbGetQuery(con,
      "SELECT c.codigo AS comercio, a.sku, a.nombre_original, p.nombre AS producto_catalogo,
              a.cantidad_total AS total_anuncio, p.cantidad_total AS total_catalogo
         FROM anuncios a JOIN productos p ON p.id_producto = a.id_producto
         JOIN comercios c ON c.id_comercio = a.id_comercio
        WHERE a.cantidad_total IS NULL OR a.cantidad_total <> p.cantidad_total")
    if (nrow(desajuste) > 0) {
      cat("!! REVISAR: el contenido del anuncio no coincide con el del producto comun (SKU mal asignado?)\n")
      print(desajuste)
    }

    # ---- 5. observaciones (ON CONFLICT: solo ignora la duplicada, no otros errores) ----
    amap <- DBI::dbGetQuery(con, "SELECT id_anuncio, id_comercio, sku FROM anuncios")
    obs <- base %>%
      dplyr::left_join(cmap, by = "comercio") %>%
      dplyr::left_join(amap, by = c("id_comercio", "sku")) %>%
      dplyr::mutate(codigo_corrida = id_ejecucion, id_ejecucion = NULL) %>%
      dplyr::left_join(emap, by = c("id_comercio", "codigo_corrida")) %>%
      dplyr::distinct(id_anuncio, fecha_consulta, .keep_all = TRUE)

    n_insertadas <- 0L
    if (nrow(obs) > 0) {
      n_insertadas <- DBI::dbExecute(con,
        "INSERT INTO observaciones (id_anuncio, id_comercio, id_ejecucion, fecha_hora_consulta,
                                    precio_cop, precio_lista_cop, es_promocion, url_extraccion,
                                    texto_original_anuncio, busqueda)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (id_anuncio, fecha_hora_consulta) DO NOTHING",
        params = unname(as.list(data.frame(
          obs$id_anuncio, obs$id_comercio, obs$id_ejecucion, obs$fecha_consulta,
          as.integer(obs$precio_real_cop), as.integer(obs$precio_lista_cop),
          as.integer(obs$oferta_general %in% 1L), obs$url_extraccion,
          obs$texto_original_anuncio, obs$busqueda,
          stringsAsFactors = FALSE))))
    }

    # ---- 6. cierre de cada ejecucion: n_registros y estado ----
    for (i in seq_len(nrow(runs))) {
      cm  <- runs$comercio[i];  cod <- runs$codigo_corrida[i]
      id_e <- emap$id_ejecucion[emap$codigo_corrida == cod & emap$id_comercio == runs$id_comercio[i]]
      n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM observaciones WHERE id_ejecucion = ?",
                           params = list(id_e))$n
      log_cm <- if (is.null(log)) data.frame(estado = character(), mensaje = character())
                else log[log$comercio == cm & log$id_ejecucion == cod, c("estado", "mensaje")]
      esperados <- trimws(catalogo_largo$sku[catalogo_largo$comercio == cm & catalogo_largo$id_producto %in% ids_conjunto])  # [Taller 2]
      vistos    <- base$sku[base$comercio == cm & base$id_ejecucion == cod]
      st <- calcular_estado(n, log_cm, length(setdiff(esperados, vistos)))
      DBI::dbExecute(con,
        "UPDATE ejecuciones SET n_registros = ?, estado = ?, mensaje = ? WHERE id_ejecucion = ?",
        params = list(as.integer(n), st$estado, st$mensaje, id_e))
    }

    list(n_filas = nrow(base), n_unicas = nrow(obs), n_insertadas = n_insertadas,
         n_descartadas = nrow(descartadas))
  })

  cat(sprintf("SQLite: %d fila(s) recibidas, %d nueva(s) insertadas, %d ya existian, %d descartadas por datos incompletos\n",
              res$n_filas, res$n_insertadas, res$n_unicas - res$n_insertadas, res$n_descartadas))
  print(DBI::dbGetQuery(con,
    "SELECT e.codigo_corrida, c.codigo AS comercio, e.n_registros, e.estado, e.mensaje
       FROM ejecuciones e JOIN comercios c USING (id_comercio)
      ORDER BY e.codigo_corrida DESC, c.codigo LIMIT 9"), row.names = FALSE)
  invisible(res)
}

# ---------------------------------------------------------------------
# Lo nuevo del Taller 2
# ---------------------------------------------------------------------
estado_base <- function(con) {
  list(max_ejecucion = DBI::dbGetQuery(con, "SELECT COALESCE(MAX(id_ejecucion), 0) AS m FROM ejecuciones")$m,
       observaciones = DBI::dbGetQuery(con, "SELECT c.codigo AS comercio, COUNT(*) AS n FROM observaciones o JOIN comercios c ON c.id_comercio = o.id_comercio GROUP BY c.codigo"),
       anuncios      = DBI::dbGetQuery(con, "SELECT c.codigo AS comercio, COUNT(*) AS n FROM anuncios a JOIN comercios c ON c.id_comercio = a.id_comercio GROUP BY c.codigo"))
}

# Resumen por comercio de lo que cambio en la base (A5)
resumen_actualizacion <- function(con, antes, base) {
  n_de <- function(df, cm) { v <- df$n[df$comercio == cm]; if (length(v)) v else 0L }
  despues <- estado_base(con)
  nuevas <- DBI::dbGetQuery(con,
    "SELECT c.codigo AS comercio, e.codigo_corrida, e.estado, e.n_registros
       FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
      WHERE e.id_ejecucion > ? ORDER BY c.codigo, e.codigo_corrida", params = list(antes$max_ejecucion))
  cambios <- DBI::dbGetQuery(con,
    "SELECT comercio, COUNT(*) AS n FROM v_cambios_precio WHERE id_ejecucion > ? AND variacion_cop <> 0 GROUP BY comercio",
    params = list(antes$max_ejecucion))
  no_obs <- DBI::dbGetQuery(con,
    "SELECT comercio, COUNT(*) AS n FROM v_no_observados WHERE id_ejecucion > ? GROUP BY comercio",
    params = list(antes$max_ejecucion))
  nombres <- c(exito = "\u00c9xito", farmatodo = "Farmatodo", larebaja = "La Rebaja")
  cms <- unique(base$comercio)
  nombre_de <- function(cm) unname(ifelse(cm %in% names(nombres), nombres[cm], cm))
  data.frame(
    comercio = nombre_de(cms),
    recolectados = vapply(cms, function(cm) sum(base$comercio == cm), numeric(1)),
    nuevas_observaciones = vapply(cms, function(cm) n_de(despues$observaciones, cm) - n_de(antes$observaciones, cm), numeric(1)),
    anuncios_nuevos = vapply(cms, function(cm) n_de(despues$anuncios, cm) - n_de(antes$anuncios, cm), numeric(1)),
    ejecuciones_nuevas = vapply(cms, function(cm) sum(nuevas$comercio == cm), numeric(1)),
    cambios_de_precio = vapply(cms, function(cm) n_de(cambios, nombre_de(cm)), numeric(1)),
    no_observados = vapply(cms, function(cm) n_de(no_obs, nombre_de(cm)), numeric(1)),
    row.names = NULL, check.names = FALSE)
}

# Punto de entrada de la app.
#   modo = "respaldo": lee raw/ y lo guarda (idempotente: lo ya guardado no se duplica).
#   modo = "scrape": scraping en linea; falla con mensaje claro si no hay navegador.
# Devuelve list(resumen, ejecuciones_nuevas, mensajes). Quien llama maneja los errores (tryCatch).
ejecutar_recoleccion <- function(con, modo = c("respaldo", "scrape"), dir_raw = "raw",
                                 comercios = c("exito", "farmatodo", "larebaja")) {
  modo <- match.arg(modo)
  if (modo == "scrape") {
    if (!requireNamespace("chromote", quietly = TRUE))
      stop("El scraping en l\u00ednea necesita Chrome o Brave y el paquete chromote, que no est\u00e1n disponibles en este entorno. Usa el modo sin conexi\u00f3n.", call. = FALSE)
    stop("El scraping en l\u00ednea a\u00fan no est\u00e1 integrado en esta versi\u00f3n. Usa el modo sin conexi\u00f3n.", call. = FALSE)
  }
  if (!dir.exists(dir_raw)) stop("No existe la carpeta de respaldos: ", dir_raw, call. = FALSE)
  antes <- estado_base(con)
  base  <- leer_respaldos(dir_raw, comercios)
  log   <- leer_log_csv(file.path(dir_raw, "log_consultas.csv"))
  mensajes <- utils::capture.output(res <- guardar_en_sqlite(con, base, log))
  list(resumen = resumen_actualizacion(con, antes, base),
       ejecuciones_nuevas = DBI::dbGetQuery(con,
         "SELECT c.nombre AS comercio, e.codigo_corrida, e.estado, e.n_registros, e.mensaje
            FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
           WHERE e.id_ejecucion > ? ORDER BY e.codigo_corrida, c.id_comercio", params = list(antes$max_ejecucion)),
       mensajes = mensajes)
}

