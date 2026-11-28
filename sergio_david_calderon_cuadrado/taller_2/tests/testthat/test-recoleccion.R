# Modo sin conexion: reprocesar respaldos CSV (raw/) hacia la base. Todo temporal e inventado.
skip_if_not_installed("dplyr"); skip_if_not_installed("tidyr")
source(file.path(raiz(), "scraper.R"), encoding = "UTF-8")

crear_base_vacia <- function() {
  con <- conectar(tempfile(fileext = ".sqlite"))
  aplicar_sql(con, test_path("fixtures", "esquema.sql"))
  asegurar_comercios(con, names(NOMBRES_COMERCIO))
  cat_p <- CATALOGO_COMPARABLES
  for (i in seq_len(nrow(cat_p))) DBI::dbExecute(con,
    "INSERT INTO productos (id_producto,nombre,linea,marca_std,subcategoria_std,presentacion,medida,cantidad_unidad,unidades,cantidad_total)
     VALUES (?,?,'x','LUBRIDERM','crema_corporal','x','ml',100,1,100)", params = list(cat_p$id_producto[i], cat_p$producto_comparable[i]))
  DBI::dbExecute(con, "UPDATE productos SET en_conjunto = 1 WHERE id_producto BETWEEN 1 AND 8")
  con
}

# Respaldos con el esquema final (COLUMNAS_FINALES): un registro por SKU del catalogo y comercio.
# Exito NO trae el SKU del producto 9 (como en la realidad).
crear_raw <- function(corridas, precio = function(cm, p, k) 10000 + 1000 * p + 100 * cm) {
  dir <- file.path(tempfile("raw")); dir.create(dir)
  filas <- list(); logs <- list()
  for (cm in c("exito", "farmatodo", "larebaja")) for (k in seq_along(corridas)) {
    cod <- corridas[k]; ts <- iso_desde_codigo(cod)
    cat_cm <- catalogo_largo[catalogo_largo$comercio == cm & !(cm == "exito" & catalogo_largo$id_producto == 9), ]
    for (i in seq_len(nrow(cat_cm))) {
      pr <- precio(match(cm, c("exito", "farmatodo", "larebaja")), cat_cm$id_producto[i], k)
      filas[[length(filas) + 1]] <- data.frame(comercio = cm, busqueda = "crema", id_ejecucion = cod, fecha_consulta = ts,
        sku = cat_cm$sku[i], nombres = cat_cm$producto_comparable[i], marca = "Lubriderm", presentacion = "200 ml", envase = "frasco",
        medida = "ml", cantidad_unidad = 200, unidades = 1, cantidad_total = 200, precio_lista_cop = pr, precio_real_cop = pr,
        oferta_general = 0, precio_medida = pr / 200, url = paste0("https://prueba/", cat_cm$sku[i]), texto_original_anuncio = "tarjeta")
    }
    logs[[length(logs) + 1]] <- data.frame(comercio = cm, id_ejecucion = cod, estado = "ok", mensaje = NA_character_)
  }
  for (cm in c("exito", "farmatodo", "larebaja")) {
    d <- do.call(rbind, Filter(function(f) f$comercio[1] == cm, filas))
    utils::write.csv(d, file.path(dir, paste0("resultado_seguro_", cm, ".csv")), row.names = FALSE, fileEncoding = "UTF-8")
  }
  utils::write.csv(do.call(rbind, logs), file.path(dir, "log_consultas.csv"), row.names = FALSE)
  dir
}

test_that("reprocesar respaldos carga las ejecuciones y deja Exito completa (no parcial) sin el producto 9", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- crear_raw(c("20261101100000", "20261102100000"))
  r <- ejecutar_recoleccion(con, "respaldo", raw)
  expect_equal(nrow(r$ejecuciones_nuevas), 6)
  expect_true(all(r$ejecuciones_nuevas$estado == "completa"))
  expect_equal(cantidad_filas(con, "ejecuciones"), 6)
  expect_equal(sum(r$resumen$nuevas_observaciones), cantidad_filas(con, "observaciones"))
})

test_that("reprocesar dos veces no duplica nada (idempotente)", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- crear_raw(c("20261101100000", "20261102100000"))
  ejecutar_recoleccion(con, "respaldo", raw)
  n1 <- c(cantidad_filas(con, "observaciones"), cantidad_filas(con, "anuncios"), cantidad_filas(con, "ejecuciones"))
  r2 <- ejecutar_recoleccion(con, "respaldo", raw)
  expect_equal(c(cantidad_filas(con, "observaciones"), cantidad_filas(con, "anuncios"), cantidad_filas(con, "ejecuciones")), n1)
  expect_equal(sum(r2$resumen$nuevas_observaciones), 0)
  expect_equal(nrow(r2$ejecuciones_nuevas), 0)
})

test_that("una corrida nueva suma solo lo nuevo y cuenta los cambios de precio", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw1 <- crear_raw(c("20261101100000", "20261102100000"))
  ejecutar_recoleccion(con, "respaldo", raw1)
  # tercera corrida: el producto 1 sube en Farmatodo (1 cambio); el resto igual
  raw2 <- crear_raw(c("20261101100000", "20261102100000", "20261103100000"),
                    precio = function(cm, p, k) 10000 + 1000 * p + 100 * cm + if (k == 3 && cm == 2 && p == 1) 500 else 0)
  r <- ejecutar_recoleccion(con, "respaldo", raw2)
  expect_equal(nrow(r$ejecuciones_nuevas), 3)                       # una por comercio
  expect_equal(r$resumen$cambios_de_precio[r$resumen$comercio == "Farmatodo"], 1)
  expect_equal(sum(r$resumen$cambios_de_precio), 1)
})

# ---- Scraping en linea con comercios SIMULADOS (nunca se abre un navegador ni se consulta un sitio) ----
ficha_falsa <- function(nombre, filas_fn, falla = FALSE) {
  list(nombre = nombre,
       catalogo = list(crema = list(termino = "crema", filtros = list(list(etiqueta = "todo", regla = NULL)))),
       url_del_filtro = function(cfg, f) "https://prueba.invalid/busqueda",
       scrapear_pagina = function(url, pausa, ts) {
         if (falla) stop("bloqueado por el sitio (prueba)")
         filas_fn(ts)
       })
}
filas_crudas <- function(nm, precios_extra = 0, solo = NULL) {
  force(nm); force(precios_extra)
  function(ts) {
    cat_cm <- catalogo_largo[catalogo_largo$comercio == nm & !(nm == "exito" & catalogo_largo$id_producto == 9), ]
    if (!is.null(solo)) cat_cm <- cat_cm[solo, ]
    tibble::tibble(id_ejecucion = ts$id_ejecucion, fecha_consulta = ts$fecha_consulta,
                   nombres = paste(cat_cm$producto_comparable, "200 ml"), presentacion = "200 ml", marca = "Lubriderm",
                   precio_cop = format(10000 + 1000 * cat_cm$id_producto + precios_extra, scientific = FALSE, trim = TRUE),
                   precio_oferta = NA_character_, condicion_promocion = NA_character_,
                   url = paste0("https://prueba.invalid/", cat_cm$sku), sku = cat_cm$sku, texto_original_anuncio = "tarjeta")
  }
}
fichas_prueba <- function(falla_en = character()) {
  setNames(lapply(c("exito", "farmatodo", "larebaja"), function(nm)
    ficha_falsa(nm, filas_crudas(nm), falla = nm %in% falla_en)), c("exito", "farmatodo", "larebaja"))
}
correr_en_linea <- function(con, dir_raw, fichas, ...) {
  suppressMessages(ejecutar_recoleccion(con, "scrape", dir_raw = dir_raw, fichas = fichas, usar_navegador = FALSE, pausa = 0, ...))
}

test_that("scraping en linea (simulado): registra una ejecucion por comercio y guarda lo recolectado", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- tempfile("raw"); dir.create(raw)
  r <- correr_en_linea(con, raw, fichas_prueba())
  expect_equal(r$modo, "scrape")
  expect_equal(nrow(r$fallos), 0)
  expect_equal(nrow(r$ejecuciones_nuevas), 3)
  expect_true(all(r$ejecuciones_nuevas$estado %in% c("completa", "parcial")))
  expect_gt(sum(r$resumen$nuevas_observaciones), 0)
  expect_equal(sum(r$resumen$recolectados), sum(r$resumen$nuevas_observaciones))
  expect_true(all(file.exists(file.path(raw, paste0("resultado_seguro_", c("exito", "farmatodo", "larebaja"), ".csv")))))
})

test_that("si un comercio falla, los demas se guardan y el fallo queda registrado con su motivo", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- tempfile("raw"); dir.create(raw)
  r <- correr_en_linea(con, raw, fichas_prueba(falla_en = "farmatodo"))
  expect_equal(r$fallos$comercio, "farmatodo")
  expect_match(r$fallos$motivo, "sin producto|ning|bloque")
  fa <- r$ejecuciones_nuevas[r$ejecuciones_nuevas$comercio == "Farmatodo", ]
  expect_equal(fa$estado, "fallida")
  expect_equal(fa$n_registros, 0)
  expect_gt(r$resumen$nuevas_observaciones[r$resumen$comercio == "\u00c9xito"], 0)
  expect_gt(r$resumen$nuevas_observaciones[r$resumen$comercio == "La Rebaja"], 0)
  expect_equal(r$resumen$nuevas_observaciones[r$resumen$comercio == "Farmatodo"], 0)
  expect_equal(r$resumen$recolectados[r$resumen$comercio == "Farmatodo"], 0)
})

test_that("una corrida en linea posterior con un precio distinto cuenta el cambio e inserta solo lo nuevo", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- tempfile("raw"); dir.create(raw)
  correr_en_linea(con, raw, fichas_prueba())
  Sys.sleep(1.1)                                    # el id de ejecucion es la hora (segundos)
  f2 <- fichas_prueba(); f2$farmatodo <- ficha_falsa("farmatodo", filas_crudas("farmatodo", precios_extra = 500, solo = 1))
  r <- correr_en_linea(con, raw, f2)
  expect_equal(r$resumen$cambios_de_precio[r$resumen$comercio == "Farmatodo"], 1)
  n1 <- cantidad_filas(con, "observaciones")
  expect_equal(cantidad_filas(con, "ejecuciones"), 6)
  expect_equal(sum(r$resumen$nuevas_observaciones), n1 - (n1 - sum(r$resumen$nuevas_observaciones)))
})

test_that("el avance por comercio se escribe en un archivo que la app puede leer", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- tempfile("raw"); dir.create(raw); ruta <- tempfile(fileext = ".csv")
  suppressMessages(ejecutar_recoleccion(con, "scrape", dir_raw = raw, fichas = fichas_prueba(falla_en = "larebaja"),
                                        usar_navegador = FALSE, pausa = 0, progreso = crear_progreso(ruta)))
  p <- leer_progreso(ruta)
  expect_equal(sort(p$comercio), c("exito", "farmatodo", "larebaja"))
  expect_equal(p$estado[p$comercio == "exito"], "listo")
  expect_equal(p$estado[p$comercio == "larebaja"], "fallo")
  expect_null(leer_progreso(tempfile()))
})

test_that("sin navegador, la actualizacion en linea falla con un mensaje claro (y no scrapea)", {
  skip_if_not_installed("chromote")
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  testthat::local_mocked_bindings(find_chrome = function(...) NULL, .package = "chromote")
  withr::local_envvar(CHROMOTE_CHROME = "")
  expect_error(ejecutar_recoleccion(con, "scrape"), "modo sin conexi")
  expect_equal(cantidad_filas(con, "ejecuciones"), 0)
})

test_that("el modo sin conexion falla claro si no existe la carpeta de respaldos", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  expect_error(ejecutar_recoleccion(con, "respaldo", file.path(tempdir(), "no_existe")), "No existe la carpeta")
})

test_that("si un comercio revienta por completo (error inesperado), no tumba la corrida", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  raw <- tempfile("raw"); dir.create(raw)
  original <- get("ejecutar_busquedas", envir = globalenv())
  assign("ejecutar_busquedas", function(cm, ...) if (cm$nombre == "larebaja") stop("estructura del sitio cambio (prueba)") else original(cm, ...),
         envir = globalenv())
  on.exit(assign("ejecutar_busquedas", original, envir = globalenv()), add = TRUE)
  r <- correr_en_linea(con, raw, fichas_prueba())
  expect_equal(r$fallos$comercio, "larebaja")
  expect_match(r$fallos$motivo, "estructura del sitio")
  expect_equal(r$ejecuciones_nuevas$estado[r$ejecuciones_nuevas$comercio == "La Rebaja"], "fallida")
  expect_gt(r$resumen$nuevas_observaciones[r$resumen$comercio == "Éxito"], 0)
})

test_that("las paginas se abren con un agente de usuario identificable, fijado antes de pedir la pagina real", {
  skip_if_not_installed("chromote")
  withr::local_envvar(TALLER_CONTACTO = "")
  ua <- agente_usuario()
  expect_equal(ua, "ComparadorPreciosT2")
  expect_false(grepl("Chrome|Mozilla", ua))                       # no se hace pasar por un navegador comun
  eventos <- character()
  sesion_falsa <- list(session = list(
    Network = list(setUserAgentOverride = function(userAgent) eventos <<- c(eventos, paste("ua:", userAgent))),
    Page = list(loadEventFired = function(...) "promesa", navigate = function(url, ...) eventos <<- c(eventos, paste("ir:", url))),
    wait_for = function(p) invisible(NULL)))
  local_mocked_bindings(read_html_live = function(url) { eventos <<- c(eventos, paste("abrir:", url)); sesion_falsa }, .package = "rvest")
  abrir_pagina_live("https://prueba.invalid/x")
  expect_equal(eventos, c("abrir: about:blank", paste("ua:", ua), "ir: https://prueba.invalid/x"))
  withr::local_envvar(TALLER_CONTACTO = "estudiante@ejemplo.edu")
  expect_equal(agente_usuario(), "ComparadorPreciosT2 (contacto: estudiante@ejemplo.edu)")
})
