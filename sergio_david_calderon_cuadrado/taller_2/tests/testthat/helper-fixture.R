# Base TEMPORAL y pequena para las pruebas. Nunca se toca comparador_precios.sqlite ni los sitios web.
# Los datos son inventados a proposito, con respuestas conocidas (ver tabla en cada prueba).
raiz <- function() normalizePath(test_path("..", ".."))
source(file.path(raiz(), "db.R"), encoding = "UTF-8")

COM_EXITO <- "\u00c9xito"
A <- "20260101100000"; B <- "20260201100000"; C <- "20260301100000"

# Precios (COP). Cada fila: anuncio, comercio, corrida, precio, precio_lista
#  A: Exito p1 10000, p2 20000 (lista 22000, promo), p3 30000 | Farmatodo 10000, 20000, 30000 | La Rebaja 12000, 20000, 30000 y un anuncio extra de 5000
#  B: Exito p1 10000, p2 25000, p3 27000 (lista 30000, promo), anuncio nuevo de 5000 | Farmatodo p1 10000, p2 20000 (sin p3) | La Rebaja 12000, 20000, 30000
#  C: corrida con Exito `parcial` (sin observaciones): no cuenta como completa
crear_base_prueba <- function() {
  ruta <- tempfile(fileext = ".sqlite")
  con <- conectar(ruta)
  aplicar_sql(con, test_path("fixtures", "esquema.sql"))
  DBI::dbExecute(con, "INSERT INTO comercios VALUES (1,'exito',?, 'x'),(2,'farmatodo','Farmatodo','x'),(3,'larebaja','La Rebaja','x')",
                 params = list(COM_EXITO))
  prod <- data.frame(id = 1:3, nombre = paste("Crema", c("Alfa", "Beta", "Gamma"), c(100, 200, 400), "ml"), ml = c(100, 200, 400))
  for (k in 1:3) DBI::dbExecute(con,
    "INSERT INTO productos (id_producto,nombre,linea,marca_std,subcategoria_std,presentacion,medida,cantidad_unidad,unidades,cantidad_total)
     VALUES (?,?,'x','LUBRIDERM','crema_corporal',?,'ml',?,1,?)",
    params = list(prod$id[k], prod$nombre[k], paste(prod$ml[k], "ml"), prod$ml[k], prod$ml[k]))
  DBI::dbExecute(con, "UPDATE productos SET en_conjunto = 1")
  anuncio <- function(id, cm, sku, p, nombre, marca = "LUBRIDERM", ml = NA_real_) {
    DBI::dbExecute(con,
      "INSERT INTO anuncios (id_anuncio,id_comercio,sku,id_producto,nombre_original,marca_std,subcategoria_std,medida,cantidad_unidad,unidades,cantidad_total,url_producto,primera_consulta,ultima_consulta)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      params = list(id, cm, sku, p, nombre, marca, "crema_corporal", if (is.na(ml)) NA_character_ else "ml", ml,
                    if (is.na(ml)) NA_real_ else 1, ml, paste0("https://prueba/", sku), "2026-01-01T10:00:00-05:00", "2026-02-01T10:00:00-05:00"))
  }
  for (cm in 1:3) for (p in 1:3)
    anuncio((cm - 1) * 3 + p, cm, paste0("S", cm, p), p, paste("Crema", c("Alfa", "Beta", "Gamma")[p], "100 ml"), ml = prod$ml[p])
  anuncio(10, 1, "NUEVO", NA, "Crema Nuevo", marca = "NIVEA")
  anuncio(11, 3, "SOLOA", NA, "Crema Solo A", marca = "NIVEA")

  fch <- c(A = "2026-01-01T10:00:00-05:00", B = "2026-02-01T10:00:00-05:00", C = "2026-03-01T10:00:00-05:00")
  ids <- 0
  for (co in c(A, B, C)) for (cm in 1:3) {
    ids <- ids + 1
    estado <- if (co == C && cm == 1) "parcial" else "completa"
    DBI::dbExecute(con, "INSERT INTO ejecuciones VALUES (?,?,?,?,0,?,NULL)",
                   params = list(ids, co, cm, fch[[match(co, c(A, B, C))]], estado))
  }
  ej <- function(co, cm) (match(co, c(A, B, C)) - 1) * 3 + cm
  obs <- function(an, cm, co, precio, lista = precio, disp = "disponible") {
    DBI::dbExecute(con,
      "INSERT INTO observaciones (id_anuncio,id_comercio,id_ejecucion,fecha_hora_consulta,precio_cop,precio_lista_cop,es_promocion,url_extraccion,texto_original_anuncio,busqueda,disponibilidad)
       VALUES (?,?,?,?,?,?,?,?,?,?,?)",
      params = list(an, cm, ej(co, cm), fch[[match(co, c(A, B, C))]], precio, lista, as.integer(precio < lista), "https://prueba/b", "tarjeta", "crema", disp))
  }
  a_idx <- function(cm, p) (cm - 1) * 3 + p
  pa <- list(c(10000, 10000), c(20000, 22000), c(30000, 30000))
  for (p in 1:3) { obs(a_idx(1, p), 1, A, pa[[p]][1], pa[[p]][2]); obs(a_idx(2, p), 2, A, pa[[p]][1]); obs(a_idx(3, p), 3, A, if (p == 1) 12000 else pa[[p]][1]) }
  obs(11, 3, A, 5000)
  obs(a_idx(1, 1), 1, B, 10000); obs(a_idx(1, 2), 1, B, 25000); obs(a_idx(1, 3), 1, B, 27000, 30000); obs(10, 1, B, 5000)
  obs(a_idx(2, 1), 2, B, 10000); obs(a_idx(2, 2), 2, B, 20000)
  obs(a_idx(3, 1), 3, B, 12000); obs(a_idx(3, 2), 3, B, 20000); obs(a_idx(3, 3), 3, B, 30000)
  # Farmatodo p3 aparece como "agotado segun el sitio" en la corrida B
  registrar_agotados(con, data.frame(fecha_consulta = fch[["B"]], nombres = "Crema Gamma 100 ml", url = "https://prueba/S23",
                                     texto_original_anuncio = "Av\u00edsame cuando est\u00e9 disponible", id_ejecucion = B, comercio = "farmatodo"))
  con
}

cantidad_filas <- function(con, tabla) DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", tabla))$n
