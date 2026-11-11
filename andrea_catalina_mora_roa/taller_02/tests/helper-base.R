# Carga los módulos del proyecto (sin tocar la base de la entrega ni los sitios) y crea bases
# temporales pequeñas para las pruebas. testthat::test_dir("tests") ejecuta este archivo primero.
withr::with_dir("..", {
  source("actualizacion.R", local = TRUE, encoding = "UTF-8")   # scraper, limpieza, validacion, esquema
  source("db.R", local = TRUE, encoding = "UTF-8")
})

# Base temporal con la estructura completa y datos mínimos:
#   2 ejecuciones (E1, E2), 3 comercios, productos P1 y P2 (comparables) con contenido en unidades.
crear_base_prueba <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- dbConnect(SQLite(), ruta)
  preparar_base(con)
  ej <- expand.grid(ejecucion_id = c("20260101T100000", "20260201T100000"),
                    comercio = c("larebaja", "cafam", "locatel"), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(ej)))
    dbExecute(con, "INSERT INTO ejecuciones (ejecucion_id, comercio, inicio, modo, estado) VALUES (?,?,?, 'online', 'completa')",
              params = list(ej$ejecucion_id[i], ej$comercio[i],
                            sprintf("%s-%s-%sT10:00:00-05:00", substr(ej$ejecucion_id[i], 1, 4),
                                    substr(ej$ejecucion_id[i], 5, 6), substr(ej$ejecucion_id[i], 7, 8))))
  dbExecute(con, "INSERT INTO productos (producto_id, descripcion, contenido_valor, contenido_unidad, comparable)
                  VALUES ('P1', 'Producto uno x 10', 10, 'un', 1), ('P2', 'Producto dos 100 ml', 100, 'ml', 1)")
  completar_derivados(con)
  con
}

# Agrega un anuncio con su observación (y lo marca comparable en su ejecución)
agregar_obs <- function(con, comercio, sku, producto, ejecucion, precio, comparable = 1L) {
  dbExecute(con, "INSERT OR IGNORE INTO anuncios (comercio, sku_comercio, nombre_original, url, primera_ejecucion)
                  VALUES (?,?,?,?,?)", params = list(comercio, sku, paste("Anuncio", sku), paste0("/p/", sku), ejecucion))
  id <- dbGetQuery(con, "SELECT anuncio_id FROM anuncios WHERE comercio = ? AND sku_comercio = ?",
                   params = list(comercio, sku))$anuncio_id
  cont <- dbGetQuery(con, "SELECT contenido_valor, contenido_unidad FROM productos WHERE producto_id = ?",
                     params = list(producto))
  dbExecute(con, "INSERT OR REPLACE INTO clasificacion (anuncio_id, en_categoria, contenido_valor, contenido_unidad, es_paquete_promo)
                  VALUES (?, 1, ?, ?, 0)", params = list(id, cont$contenido_valor, cont$contenido_unidad))
  dbExecute(con, "INSERT OR REPLACE INTO correspondencia (anuncio_id, producto_id, comparable) VALUES (?,?,?)",
            params = list(id, producto, comparable))
  fh <- sprintf("%s-%s-%sT10:00:00-05:00", substr(ejecucion, 1, 4), substr(ejecucion, 5, 6), substr(ejecucion, 7, 8))
  dbExecute(con, "INSERT INTO observaciones (ejecucion_id, comercio, anuncio_id, fecha_hora, precio, en_promocion,
                  disponible, estado_disponibilidad) VALUES (?,?,?,?,?,0,1,'disponible')",
            params = list(ejecucion, comercio, id, fh, precio))
  oid <- dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
  dbExecute(con, "INSERT INTO obs_comparable (obs_id, ejecucion_id, comparable) VALUES (?,?,?)",
            params = list(oid, ejecucion, comparable))
  invisible(id)
}

# Lote como el que entrega scraper.R (columnas COLS) para probar validación e inserción
lote_scraper <- function(n = 3, comercio = "cafam", fecha = "2026-11-05T23:51:08-05:00") {
  data.frame(comercio = comercio, producto_id = paste0("pid", seq_len(n)), sku_comercio = paste0("sku", seq_len(n)),
             ean = NA_character_, referencia = NA_character_, nombre_original = paste("Producto", seq_len(n)),
             marca_original = "MARCA", descripcion_original = NA_character_, categoria_origen = NA_character_,
             categoria_consulta = "1/10", url = paste0("/producto-", seq_len(n), "/p"),
             precio = 1000 * seq_len(n), precio_lista = 1000 * seq_len(n), en_promocion = 0L, disponible = 1L,
             moneda = "COP", texto_original = paste("Producto", seq_len(n)), fecha_hora = fecha,
             stringsAsFactors = FALSE)
}
