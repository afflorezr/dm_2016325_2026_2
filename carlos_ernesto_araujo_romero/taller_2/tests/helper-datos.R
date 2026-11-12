# Utilidades compartidas por las pruebas. Buscan la raíz del proyecto sin
# rutas absolutas ni setwd(), y crean una base temporal con el esquema real.

raiz <- getwd()
while (!file.exists(file.path(raiz, "db.R")) && dirname(raiz) != raiz) {
  raiz <- dirname(raiz)
}

RUTA_ESQUEMA <- file.path(raiz, "db", "schema.sql")
RUTA_VISTAS <- file.path(raiz, "db", "vistas.sql")
source(file.path(raiz, "scraper.R"))
assign("RUTA_ESQUEMA", RUTA_ESQUEMA, envir = globalenv())
assign("RUTA_VISTAS", RUTA_VISTAS, envir = globalenv())
source(file.path(raiz, "validacion.R"))
source(file.path(raiz, "db.R"))

nueva_base <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ruta)
  crear_esquema(con)
  DBI::dbExecute(con, "INSERT INTO comercios
    (id_comercio, nombre, url_base, activo)
    VALUES ('carulla', 'Carulla', 'https://carulla.test', 1),
           ('jumbo', 'Jumbo', 'https://jumbo.test', 1)")
  DBI::dbExecute(con, "INSERT INTO productos_comparables
    (id_producto_comun, nombre_canonico, marca, variante, contenido_total,
     unidad_normalizada, subcategoria, vigente)
    VALUES ('P1', 'Producto uno 100 g', 'Marca', 'clásico', 100, 'g', 'Chocolates', 1),
           ('P2', 'Producto dos 200 g', 'Marca', 'clásico', 200, 'g', 'Chocolates', 1)")
  list(con = con, ruta = ruta)
}

nueva_ejecucion <- function(con, id, fecha) {
  DBI::dbExecute(con, "INSERT INTO ejecuciones
    (id_ejecucion, fecha_inicio, modo, estado, n_registros)
    VALUES (?, ?, 'online', 'completa', 0)", params = list(id, fecha))
}

nueva_observacion <- function(con, ejecucion, comercio, sku, precio, fecha,
                              producto = NA_character_, comparable = 0L,
                              estado = "disponible") {
  DBI::dbExecute(con, "INSERT INTO observaciones
    (id_ejecucion, id_comercio, sku_comercio, texto_original, marca, subcategoria,
     contenido_total, unidad_normalizada, precio_cop, disponible,
     estado_disponibilidad, fecha_consulta, id_producto_comun, es_comparable,
     url_producto)
    VALUES (?, ?, ?, ?, 'Marca', 'Chocolates', 100, 'g', ?, ?,
            ?, ?, ?, ?, ?)",
    params = list(ejecucion, comercio, sku, paste("Producto", sku), precio,
                  as.integer(estado == "disponible"), estado, fecha,
                  producto, as.integer(comparable),
                  paste0("https://", comercio, ".test/", sku)))
}
