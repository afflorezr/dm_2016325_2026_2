# =============================================================================
# comparables.R · Correspondencia de productos entre comercios (Taller 1, 3.5)
# Uso: source("config.R"); source("scraper.R"); source("comparables.R"); asignar_comparables()
# =============================================================================
VARIANTE_SABORES <- list(
  NARANJA = "naranja", MANDARINA = "mandarina", LIMON = "limon", MORA = "mora", MANZANA = "manzana",
  TORONJA = "toronja", UVA = "uva", MANGO = "mango", FRESA = "fresa", DURAZNO = "durazno",
  PINA = "pina", GUAYABA = "guayaba", MARACUYA = "maracuya", LULO = "lulo", TAMARINDO = "tamarindo",
  ARANDANO = "arandano", FRUTOS_ROJOS = "frutos rojos", TROPICAL = "tropical", SURTIDO = "surtid[oa]s?",
  JENGIBRE = "ginger|jengibre", TONICA = "tonica", SODA = "soda", LYCHEE = "lychee", GRANADA = "granada",
  MANGOSTINO = "mangostino", CARAMBOLO = "carambolo", YUZU = "yuzu", COCO = "coco", PERA = "pera",
  SANDIA = "sandia", CEREZA = "cereza", CITRICO = "citrus|citricos", NEGRO = "negro", VERDE = "verde",
  BLANCO = "blanco", ROJO = "rojo", MIEL = "miel", COLADA = "colada"
)
clave_variante <- function(nombre) {
  vapply(nombre, function(x) {
    t <- str_replace_all(normalizar(x), "-", " ")
    p <- character()
    if (str_detect(t, "\\b(zero|cero|light|diet)\\b|\\bsin\\s*/?\\s*azu")) p <- c(p, "SIN_AZUCAR")
    if (str_detect(t, "\\s\\+\\s")) p <- c(p, "MIXTO")   # packs mixtos: "COCA COLA + SPRITE"
    if (str_detect(t, "\\bsin gas\\b")) p <- c(p, "SIN_GAS")
    else if (str_detect(t, "\\bcon gas\\b|\\bgasificad")) p <- c(p, "CON_GAS")
    for (k in names(VARIANTE_SABORES))
      if (str_detect(t, paste0("\\b(", VARIANTE_SABORES[[k]], ")\\b"))) p <- c(p, k)
    if (!length(p)) "BASE" else paste(sort(unique(p)), collapse = "+")
  }, character(1), USE.NAMES = FALSE)
}

asignar_comparables <- function(db_path = CFG$db_path, id_corrida = NULL, min_productos = 8, n_comercios = 3) {
  con <- db_conectar(db_path); on.exit(dbDisconnect(con), add = TRUE)
  dbExecute(con, "CREATE TABLE IF NOT EXISTS productos_comunes(
    id_corrida TEXT NOT NULL, id_producto_comun TEXT NOT NULL, clave_producto TEXT NOT NULL,
    marca TEXT, subcategoria TEXT, variante TEXT, contenido_total_ml REAL, unidades INTEGER,
    n_comercios INTEGER, lista_comercios TEXT, PRIMARY KEY(id_corrida, id_producto_comun))")
  if (is.null(id_corrida))
    id_corrida <- dbGetQuery(con, "SELECT MAX(id_corrida) m FROM ejecuciones WHERE n_registros > 0")$m
  obs <- dbGetQuery(con, "SELECT o.id_obs, o.comercio, o.sku_comercio, o.producto_raw, o.marca_estandarizada AS marca,
      o.subcategoria, o.contenido_total_ml, o.unidades
    FROM observaciones o JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion WHERE e.id_corrida = ?",
                    params = list(id_corrida))
  cat("Corrida:", id_corrida, "| observaciones:", nrow(obs), "\n")
  
  cand <- obs |>
    filter(!is.na(marca), subcategoria != "Sin categorizar", !is.na(contenido_total_ml), !is.na(unidades)) |>
    mutate(variante = clave_variante(producto_raw),
           clave = paste(marca, subcategoria, variante, round(contenido_total_ml), unidades, sep = "|"))
  comercios <- unique(cand$comercio)
  if (length(comercios) < n_comercios) stop("Hay menos de ", n_comercios, " comercios con datos.")
  
  trios <- combn(comercios, n_comercios, simplify = FALSE)
  comunes <- lapply(trios, function(tr) Reduce(intersect, lapply(tr, function(cm) cand$clave[cand$comercio == cm])))
  mejor <- which.max(lengths(comunes)); trio <- trios[[mejor]]; claves <- sort(comunes[[mejor]])
  cat("Trio elegido:", paste(trio, collapse = ", "), "| productos comunes:", length(claves), "\n")
  for (i in seq_along(trios)) cat("  ", paste(trios[[i]], collapse = " + "), "->", length(comunes[[i]]), "\n")
  if (length(claves) < min_productos)
    warning("Solo ", length(claves), " productos comunes (< ", min_productos, "). Revisa 'variante' o amplia la recoleccion.")
  
  ids <- setNames(sprintf("PROD_COM_%02d", seq_along(claves)), claves)
  rep_obs <- cand |> filter(clave %in% claves, comercio %in% trio) |>
    arrange(clave, comercio, sku_comercio) |> group_by(clave, comercio) |> slice(1) |> ungroup() |>
    mutate(id_producto_comun = unname(ids[clave]))
  info <- rep_obs |> group_by(id_producto_comun, clave) |>
    summarise(marca = first(marca), subcategoria = first(subcategoria), variante = first(variante),
              contenido_total_ml = first(contenido_total_ml), unidades = first(unidades),
              n_comercios = n_distinct(comercio), lista_comercios = paste(sort(comercio), collapse = " | "), .groups = "drop")
  
  dbBegin(con)
  tryCatch({
    dbExecute(con, "UPDATE observaciones SET comparable = 0, id_producto_comun = NULL
                    WHERE id_ejecucion IN (SELECT id_ejecucion FROM ejecuciones WHERE id_corrida = ?)", params = list(id_corrida))
    dbExecute(con, "UPDATE observaciones SET comparable = 1, id_producto_comun = ? WHERE id_obs = ?",
              params = list(rep_obs$id_producto_comun, rep_obs$id_obs))
    dbExecute(con, "DELETE FROM productos_comunes WHERE id_corrida = ?", params = list(id_corrida))
    dbAppendTable(con, "productos_comunes", data.frame(id_corrida = id_corrida, id_producto_comun = info$id_producto_comun,
                                                       clave_producto = info$clave, marca = info$marca, subcategoria = info$subcategoria, variante = info$variante,
                                                       contenido_total_ml = info$contenido_total_ml, unidades = info$unidades,
                                                       n_comercios = info$n_comercios, lista_comercios = info$lista_comercios))
    dbCommit(con)
  }, error = function(e) { dbRollback(con); stop(e) })
  cat("Observaciones comparables:", nrow(rep_obs), "(esperado >= 24)\n")
  print(as.data.frame(info[, c("id_producto_comun", "clave", "n_comercios")]), right = FALSE)
  invisible(info)
}