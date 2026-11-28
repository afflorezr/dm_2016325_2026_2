# Utilidades para las pruebas: base temporal pequeña (nunca la base de la entrega ni los sitios)
for (f in c("scraper.R", "esquema_taller2.R", "validacion.R", "limpieza_sqlite.R", "db.R", "colores.R", "graficos.R", "actualizacion.R"))
  source(file.path("..", f), encoding = "UTF-8")

crear_base_prueba <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- dbConnect(SQLite(), ruta); on.exit(dbDisconnect(con))
  crear_esquema(con)
  dbExecute(con, "INSERT INTO comercios (nombre) VALUES ('exito'), ('jumbo')")
  dbExecute(con, "INSERT INTO productos VALUES ('P01','111','Removedor X 100 ml','Lander','Removedores',100,'ml',1)")
  # anuncios: 1 y 2 = P01 en éxito y jumbo; 3 = solo éxito, sin producto comparable
  for (i in 1:3) dbExecute(con,
    "INSERT INTO anuncios (comercio_id, product_id_comercio, sku, nombre_original, marca_estandar,
       subcategoria, contenido_valor, contenido_unidad, producto_id, incluido, url)
     VALUES (?,?,?,?,?,?,?,?,?,1,?)",
    params = list(c(1, 2, 1)[i], as.character(i), "1", c("Removedor X", "Removedor X", "Lima Y")[i],
                  c("Lander", "Lander", "Genérico")[i], c("Removedores", "Removedores", "Limas")[i],
                  c(100, 100, 1)[i], c("ml", "ml", "und")[i], c("P01", "P01", NA)[i],
                  paste0("https://t/", i)))
  for (e in c("run_A", "run_B")) for (cm in 1:2) dbExecute(con,
    "INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, n_registros, estado) VALUES (?,?,?,?,'completa')",
    params = list(e, cm, if (e == "run_A") "2026-11-01T10:00:00-05:00" else "2026-11-05T10:00:00-05:00", 2L))
  obs <- data.frame(
    anuncio = c(1, 2, 3, 1, 2),                 # el anuncio 3 NO aparece en run_B
    ejec    = c("run_A", "run_A", "run_A", "run_B", "run_B"),
    ts      = c("2026-11-01T10:00:01-05:00", "2026-11-01T10:00:02-05:00", "2026-11-01T10:00:03-05:00",
                "2026-11-05T10:00:01-05:00", "2026-11-05T10:00:02-05:00"),
    precio  = c(10000, 12000, 5000, 11000, 12000),
    disp    = c(1, 1, 0, 1, 1))
  for (k in seq_len(nrow(obs))) dbExecute(con,
    "INSERT INTO observaciones (anuncio_id, ejecucion_id, fecha_hora_consulta, precio_cop,
       precio_lista_cop, en_promocion, disponible, comparable, estado_disponibilidad)
     VALUES (?,?,?,?,?,0,?,?,?)",
    params = list(obs$anuncio[k], obs$ejec[k], obs$ts[k], obs$precio[k], obs$precio[k], obs$disp[k],
                  as.integer(obs$anuncio[k] %in% 1:2),
                  if (obs$disp[k] == 1) "disponible" else "agotado"))
  ruta
}


# ---- datos falsos con la forma de la salida del scraper (los 8 comparables principales) ----
datos_falsos <- function(comercio, ejecucion = "run_20261106_100000", ts = "2026-11-06T10:00:00-05:00",
                         precio = 5000) {
  p <- CORRESPONDENCIA[CORRESPONDENCIA$principal == 1, ]
  data.frame(comercio = comercio, ejecucion_id = ejecucion, fecha_hora_consulta = ts,
             product_id = paste0("pid", seq_len(nrow(p))), sku = paste0("sku", seq_len(nrow(p))),
             ean = p$ean_n, nombre_original = p$producto_estandar, nombre_sku_original = p$producto_estandar,
             marca_original = p$marca_estandar, descripcion_original = NA_character_,
             ficha_tecnica_original = NA_character_,
             categoria_api = "/Belleza/Maquillaje y cosméticos/Uñas/Esmaltes y removedores/",
             categoria_consulta = "Belleza > Maquillaje y cosméticos > Uñas > Esmaltes y removedores",
             precio_cop = precio, precio_lista_cop = precio, en_promocion = FALSE, disponible = TRUE,
             vendedor = comercio, unidad_medida = "un", multiplicador_unidad = 1,
             url = paste0("https://", comercio, ".test/", seq_len(nrow(p))), stringsAsFactors = FALSE)
}
resumen_falso <- function(comercio, ejecucion = "run_20261106_100000", n = 8)
  data.frame(comercio = comercio, ejecucion_id = ejecucion, categoria = "Esmaltes y removedores",
             total_sitio = n, n_productos = n, n_omitidos = 0L, stringsAsFactors = FALSE)

# Recolector falso: éxito falla con error, jumbo devuelve datos, olímpica devuelve datos con un resumen
# defectuoso que hace fallar la carga DESPUÉS de insertar observaciones (prueba de la transacción)
recolector_falso <- function(comercio, ejecucion) {
  if (comercio == "exito") stop("HTTP 500 simulado")
  d <- datos_falsos(comercio, ejecucion, ts = inicio_iso(ejecucion))
  r <- resumen_falso(comercio, ejecucion)
  if (comercio == "olimpica") r$total_sitio <- "no-numerico"
  list(datos = d, resumen = r)
}

# Base con 3 comercios y 2 productos comparables en una ejecución, para ahorro y canasta
crear_base_canasta <- function(precios) {   # precios: data.frame(comercio, producto_id, precio_cop)
  ruta <- tempfile(fileext = ".sqlite")
  con <- dbConnect(SQLite(), ruta); on.exit(dbDisconnect(con))
  crear_esquema(con)
  cms <- unique(precios$comercio)
  for (cm in cms) dbExecute(con, "INSERT INTO comercios (nombre) VALUES (?)", params = list(cm))
  dbExecute(con, "INSERT INTO productos VALUES ('P01','1','Producto uno','M','S',100,'ml',1),
                                               ('P02','2','Producto dos','M','S',50,'g',1)")
  for (k in seq_len(nrow(precios))) {
    cid <- match(precios$comercio[k], cms)
    dbExecute(con, "INSERT INTO anuncios (comercio_id, product_id_comercio, sku, nombre_original, producto_id, incluido, url)
                    VALUES (?,?,?,?,?,1,'u')", params = list(cid, as.character(k), "1", "x", precios$producto_id[k]))
    dbExecute(con, "INSERT OR IGNORE INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, n_registros, estado)
                    VALUES ('R1', ?, '2026-11-06T10:00:00-05:00', 1, 'completa')", params = list(cid))
    dbExecute(con, "INSERT INTO observaciones (anuncio_id, ejecucion_id, fecha_hora_consulta, precio_cop, disponible,
                      comparable, estado_disponibilidad) VALUES (?, 'R1', '2026-11-06T10:00:01-05:00', ?, 1, 1, 'disponible')",
              params = list(k, precios$precio_cop[k]))
  }
  ruta
}
