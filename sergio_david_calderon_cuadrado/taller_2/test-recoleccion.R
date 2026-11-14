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

test_that("modo en linea sin navegador falla con un mensaje claro", {
  con <- crear_base_vacia(); on.exit(DBI::dbDisconnect(con))
  expect_error(ejecutar_recoleccion(con, "scrape"), "modo sin conexi")
  expect_error(ejecutar_recoleccion(con, "respaldo", file.path(tempdir(), "no_existe")), "No existe la carpeta")
})
