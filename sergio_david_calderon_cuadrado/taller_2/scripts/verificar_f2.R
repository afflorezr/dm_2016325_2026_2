# scripts/verificar_f2.R -- Verificacion agrupada de F2.
# Ejecutar en la CONSOLA de RStudio, desde la raiz del proyecto:  source("scripts/verificar_f2.R", encoding = "UTF-8")
# Compara cada funcion de db.R con un calculo independiente hecho en R sobre las tablas base
# (observaciones, anuncios, ejecuciones...), sin usar las vistas ni las funciones de db.R.
# Solo lee la base: no escribe nada.
source("db.R", encoding = "UTF-8")
con <- conectar()
res <- data.frame(bloque = character(), prueba = character(), ok = logical(), detalle = character())
chk <- function(bloque, prueba, ok, detalle = "") {
  res[nrow(res) + 1, ] <<- list(bloque, prueba, isTRUE(ok), if (isTRUE(ok)) "" else as.character(detalle))
}
iguales <- function(a, b, tol = 1e-6) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol))
rechaza <- function(expr) inherits(try(expr, silent = TRUE), "try-error")

# ---- Oraculo: datos base leidos de las tablas (solo para verificar) ----
raw <- DBI::dbGetQuery(con, "
  SELECT o.id_observacion, o.id_anuncio, c.nombre AS comercio, o.fecha_hora_consulta, o.precio_cop,
         o.es_promocion, o.disponibilidad, o.texto_original_anuncio, e.codigo_corrida,
         a.nombre_original, a.marca_std, a.subcategoria_std, a.id_producto, a.medida, a.cantidad_total,
         COALESCE(p.en_conjunto, 0) AS en_conjunto
    FROM observaciones o
    JOIN anuncios a ON a.id_anuncio = o.id_anuncio
    JOIN comercios c ON c.id_comercio = o.id_comercio
    JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
    LEFT JOIN productos p ON p.id_producto = a.id_producto")
raw$ppm <- ifelse(is.na(raw$cantidad_total), NA, round(raw$precio_cop / raw$cantidad_total, 2))
ord    <- raw[order(raw$id_anuncio, raw$fecha_hora_consulta), ]
ultimo <- ord[!duplicated(ord$id_anuncio, fromLast = TRUE), ]
ej     <- DBI::dbGetQuery(con, "SELECT codigo_corrida, estado, fecha_hora_inicio FROM ejecuciones")
ini    <- tapply(ej$fecha_hora_inicio, ej$codigo_corrida, min)
todas  <- names(sort(ini, decreasing = TRUE))
compl  <- todas[sapply(todas, function(k) all(ej$estado[ej$codigo_corrida == k] == "completa"))]
ult    <- todas[1]

orac <- function(corrida = NULL, fechas = NULL, comercios = NULL, subcat = NULL, marcas = NULL,
                 precio = NULL, promo = FALSE, comp = FALSE, palabras = NULL) {
  d <- if (!is.null(corrida)) raw[raw$codigo_corrida == corrida, ]
       else if (!is.null(fechas)) raw[substr(raw$fecha_hora_consulta, 1, 10) >= fechas[1] &
                                      substr(raw$fecha_hora_consulta, 1, 10) <= fechas[2], ]
       else ultimo
  if (!is.null(comercios)) d <- d[d$comercio %in% comercios, ]
  if (!is.null(subcat))    d <- d[d$subcategoria_std %in% subcat, ]
  if (!is.null(marcas))    d <- d[d$marca_std %in% marcas, ]
  if (!is.null(precio))    d <- d[d$precio_cop >= precio[1] & d$precio_cop <= precio[2], ]
  if (promo) d <- d[d$es_promocion == 1, ]
  if (comp)  d <- d[d$en_conjunto == 1, ]
  # LIKE de SQLite ignora mayusculas solo en ASCII: el oraculo hace lo mismo
  min_ascii <- function(x) chartr(paste(LETTERS, collapse = ""), paste(letters, collapse = ""), x)
  for (p in palabras) d <- d[grepl(min_ascii(p), min_ascii(d$nombre_original), fixed = TRUE) |
                             grepl(min_ascii(p), min_ascii(d$texto_original_anuncio), fixed = TRUE), ]
  d
}
ids <- function(d) sort(d$id_observacion)

op   <- opciones_filtros(con)
com2 <- op$comercios[2:3]

# ---- 1. opciones_filtros ----
chk("opciones", "comercios = tabla comercios", setequal(op$comercios, DBI::dbGetQuery(con, "SELECT nombre FROM comercios")$nombre))
chk("opciones", "rango de precio", iguales(op$precio, range(raw$precio_cop)))
chk("opciones", "rango de fechas", identical(unname(op$fechas), c(min(substr(raw$fecha_hora_consulta, 1, 10)), max(substr(raw$fecha_hora_consulta, 1, 10)))))
chk("opciones", "ejecuciones = corridas distintas", setequal(op$ejecuciones$codigo_corrida, todas))
chk("opciones", "productos = conjunto comparable", setequal(op$productos$id_producto, DBI::dbGetQuery(con, "SELECT id_producto FROM productos WHERE en_conjunto = 1")$id_producto))

# ---- 2. filtrar_precios ----
chk("filtrar", "sin filtros = ultimo precio de cada anuncio", identical(sort(filtrar_precios(con)$id_observacion), ids(ultimo)))
casos <- list(
  list(f = list(corrida = ult),                                  o = orac(corrida = ult)),
  list(f = list(corrida = todas[length(todas)], solo_comparables = TRUE), o = orac(corrida = todas[length(todas)], comp = TRUE)),
  list(f = list(fechas = c(op$fechas[["desde"]], op$fechas[["desde"]])), o = orac(fechas = rep(op$fechas[["desde"]], 2))),
  list(f = list(comercios = com2, precio = c(20000, 80000)),     o = orac(comercios = com2, precio = c(20000, 80000))),
  list(f = list(solo_promociones = TRUE),                        o = orac(promo = TRUE)),
  list(f = list(subcategorias = op$subcategorias[1], marcas = op$marcas[1:2]), o = orac(subcat = op$subcategorias[1], marcas = op$marcas[1:2])),
  list(f = list(texto = "lubriderm"),                            o = orac(palabras = "lubriderm")),
  list(f = list(texto = "lubriderm diaria", comercios = com2, solo_comparables = TRUE, precio = c(0, 60000)),
       o = orac(palabras = c("lubriderm", "diaria"), comercios = com2, comp = TRUE, precio = c(0, 60000))))
for (i in seq_along(casos)) {
  r <- filtrar_precios(con, casos[[i]]$f)
  chk("filtrar", paste("filtros combinados, caso", i), identical(sort(r$id_observacion), ids(casos[[i]]$o)),
      sprintf("funcion %d filas, oraculo %d", nrow(r), nrow(casos[[i]]$o)))
}
chk("filtrar", "filtro sin resultados devuelve tabla vacia con columnas", {r <- filtrar_precios(con, list(texto = "zzzzqqq")); nrow(r) == 0 && ncol(r) > 10})

# ---- 3. indicadores ----
for (k in 1:2) {
  f <- list(list(), list(solo_comparables = TRUE, corrida = ult))[[k]]
  o <- if (k == 1) orac() else orac(corrida = ult, comp = TRUE)
  ind <- indicadores(con, f)
  pc  <- ind$por_comercio
  chk("indicadores", paste0("por_comercio (caso ", k, ")"),
      all(sapply(pc$comercio, function(cm) { x <- o[o$comercio == cm, ]
        pc$productos[pc$comercio == cm] == length(unique(x$id_anuncio)) && pc$observaciones[pc$comercio == cm] == nrow(x) })) &&
      setequal(pc$comercio, unique(o$comercio)))
  chk("indicadores", paste0("resumen y % promocion (caso ", k, ")"),
      ind$resumen$productos == length(unique(o$id_anuncio)) && ind$resumen$observaciones == nrow(o) &&
      iguales(ind$resumen$pct_promocion, round(100 * length(unique(o$id_anuncio[o$es_promocion == 1])) / length(unique(o$id_anuncio)), 1)))
  chk("indicadores", paste0("mediana general (caso ", k, ")"), iguales(ind$resumen$mediana_precio, median(o$precio_cop)))
  ms <- ind$mediana_subcategoria
  chk("indicadores", paste0("mediana por subcategoria (caso ", k, ")"),
      all(sapply(seq_len(nrow(ms)), function(j) { x <- o$precio_cop[ifelse(is.na(o$subcategoria_std), "sin dato", o$subcategoria_std) == ms$subcategoria[j]]
        iguales(ms$mediana[j], median(x)) && ms$n[j] == length(x) })))
}
ind <- indicadores(con)
ue  <- ej[ej$codigo_corrida == ult, ]
chk("indicadores", "ultima ejecucion: corrida, estados y fecha", setequal(ind$ultima_ejecucion$estado, ue$estado) &&
      all(ind$ultima_ejecucion$codigo_corrida == ult) && nrow(ind$ultima_ejecucion) == nrow(ue))
# ahorro maximo (oraculo en R)
cc <- compl[1]; d <- raw[raw$codigo_corrida == cc & raw$en_conjunto == 1 & raw$disponibilidad == "disponible", ]
pp <- aggregate(precio_cop ~ id_producto + comercio, d, min)
sp <- do.call(rbind, lapply(split(pp, pp$id_producto), function(x) if (nrow(x) >= 2) data.frame(id_producto = x$id_producto[1], dif = max(x$precio_cop) - min(x$precio_cop), pmin = min(x$precio_cop), pmax = max(x$precio_cop))))
mx <- sp[which.max(sp$dif), ]
chk("indicadores", "ahorro maximo entre comercios", nrow(ind$ahorro_maximo) == 1 && iguales(ind$ahorro_maximo$ahorro_cop, mx$dif) &&
      iguales(ind$ahorro_maximo$precio_min, mx$pmin) && iguales(ind$ahorro_maximo$precio_max, mx$pmax) && ind$ahorro_maximo$codigo_corrida == cc,
    paste("funcion:", ind$ahorro_maximo$ahorro_cop, "oraculo:", mx$dif))
# cambios en la ultima corrida (oraculo en R)
du <- raw[raw$codigo_corrida == ult, ]
var <- vapply(seq_len(nrow(du)), function(i) { prev <- raw[raw$id_anuncio == du$id_anuncio[i] & raw$fecha_hora_consulta < du$fecha_hora_consulta[i], ]
  if (nrow(prev) == 0) NA_real_ else du$precio_cop[i] - prev$precio_cop[order(prev$fecha_hora_consulta)][nrow(prev)] }, numeric(1))
cu <- ind$cambios_ultima
chk("indicadores", "cambios de precio en la ultima ejecucion",
    cu$comparados == sum(!is.na(var)) && cu$suben == sum(var > 0, na.rm = TRUE) && cu$bajan == sum(var < 0, na.rm = TRUE) &&
    cu$sin_cambio == sum(var == 0, na.rm = TRUE) && cu$cambios_conjunto == sum(var != 0 & du$en_conjunto == 1, na.rm = TRUE),
    paste(unlist(cu), collapse = " "))

# ---- 4. graficos ----
okserie <- all(sapply(op$productos$id_producto, function(p) { s <- serie_precio(con, p); o <- raw[raw$id_producto %in% p, ]
  nrow(s) == nrow(o) && iguales(sort(s$precio), sort(o$precio_cop)) }))
chk("graficos", "serie_precio de cada producto comparable", okserie)
pu <- precio_unitario(con); o <- orac(); o <- o[!is.na(o$ppm) & !is.na(o$medida), ]
chk("graficos", "precio_unitario por comercio y unidad, sin mezclar", all(sapply(seq_len(nrow(pu)), function(j) {
  x <- o$ppm[o$comercio == pu$comercio[j] & o$medida == pu$medida[j]]
  length(x) == pu$n[j] && iguales(pu$mediana[j], median(x), 1e-6) && iguales(pu$minimo[j], min(x)) && iguales(pu$maximo[j], max(x)) })) &&
  nrow(pu) == nrow(unique(o[, c("comercio", "medida")])))
dp <- distribucion_precios(con); o <- orac()
chk("graficos", "distribucion: min, q1, mediana, q3, max", all(sapply(seq_len(nrow(dp)), function(j) {
  x <- o$precio_cop[o$comercio == dp$comercio[j]]; q <- quantile(x, c(0, .25, .5, .75, 1), type = 7)
  iguales(unlist(dp[j, c("minimo", "q1", "mediana", "q3", "maximo")]), q) && dp$n[j] == length(x) })))

# ---- 5. cambios_entre ----
if (length(compl) >= 2) {
  b <- compl[1]; a <- compl[2]
  da <- raw[raw$codigo_corrida == a, ]; db <- raw[raw$codigo_corrida == b, ]
  ce <- cambios_entre(con, umbral = 10)
  both <- merge(da[, c("id_anuncio", "precio_cop")], db[, c("id_anuncio", "precio_cop")], by = "id_anuncio", suffixes = c("_a", "_b"))
  ce_ab <- ce[ce$situacion %in% c("sube", "baja", "igual"), ]
  chk("cambios", "por defecto = dos ultimas completas (a anterior, b reciente)", nrow(ce_ab) == nrow(both) &&
        iguales(ce_ab$variacion_cop[order(ce_ab$id_anuncio)], (both$precio_cop_b - both$precio_cop_a)[order(both$id_anuncio)]))
  chk("cambios", "sube / baja / igual", sum(ce$situacion == "sube") == sum(both$precio_cop_b > both$precio_cop_a) &&
        sum(ce$situacion == "baja") == sum(both$precio_cop_b < both$precio_cop_a) && sum(ce$situacion == "igual") == sum(both$precio_cop_b == both$precio_cop_a))
  chk("cambios", "nuevos y no observados", sum(ce$situacion == "nuevo") == length(setdiff(db$id_anuncio, da$id_anuncio)) &&
        sum(ce$situacion %in% c("no_observado", "agotado_segun_sitio")) == length(setdiff(da$id_anuncio, db$id_anuncio)))
  pct <- 100 * (both$precio_cop_b - both$precio_cop_a) / both$precio_cop_a
  chk("cambios", "umbral resalta |variacion %| >= umbral", sum(ce$supera_umbral == 1) == sum(abs(pct) >= 10) &&
        sum(cambios_entre(con, umbral = 0)$supera_umbral == 1) == nrow(both))
  chk("cambios", "mismo anuncio, mismo comercio (sin filas duplicadas)", !anyDuplicated(ce$id_anuncio))
  chk("cambios", "ejecuciones explicitas = por defecto", identical(cambios_entre(con, a, b, 10), ce))
  chk("cambios", "misma ejecucion dos veces se rechaza", rechaza(cambios_entre(con, a, a)))
  chk("cambios", "ejecucion inexistente se rechaza", rechaza(cambios_entre(con, a, "99999999999999")))
}

# ---- 6. canasta ----
if (length(compl) >= 1) {
  its <- data.frame(id_producto = c(1, 3, 6), cantidad = c(1, 2, 1))
  cb  <- canasta(con, its)
  d   <- raw[raw$codigo_corrida == compl[1] & raw$en_conjunto == 1 & raw$disponibilidad == "disponible", ]
  pm  <- aggregate(precio_cop ~ id_producto + comercio, d, min)
  tot <- sapply(unique(raw$comercio), function(cm) { x <- pm[pm$comercio == cm & pm$id_producto %in% its$id_producto, ]
    if (nrow(x) == nrow(its)) sum(x$precio_cop * its$cantidad[match(x$id_producto, its$id_producto)]) else NA })
  chk("canasta", "costo por comercio solo si tiene todos los productos", all(sapply(cb$totales$comercio, function(cm) {
    a <- cb$totales$costo[cb$totales$comercio == cm]; b <- tot[[cm]]; (is.na(a) && is.na(b)) || iguales(a, b) })))
  mini <- sum(sapply(its$id_producto, function(p) min(pm$precio_cop[pm$id_producto == p]) * its$cantidad[its$id_producto == p]))
  chk("canasta", "minimo combinado y ahorro", iguales(cb$resumen$costo_minimo_combinado, mini) &&
        (is.na(cb$resumen$ahorro_cop) || iguales(cb$resumen$ahorro_cop, min(tot, na.rm = TRUE) - mini)))
  chk("canasta", "advertencia de envio y minimos presente", grepl("env", cb$advertencia))
  chk("canasta", "producto fuera del conjunto se rechaza", rechaza(canasta(con, data.frame(id_producto = 9, cantidad = 1))))
  chk("canasta", "cantidades invalidas se rechazan", rechaza(canasta(con, data.frame(id_producto = 1, cantidad = 0))) &&
        rechaza(canasta(con, data.frame(id_producto = 1, cantidad = 2.5))) && rechaza(canasta(con, data.frame(id_producto = 1, cantidad = 100))))
}

# ---- 7. seguridad (S2, S3) ----
antes <- DBI::dbGetQuery(con, "SELECT (SELECT COUNT(*) FROM observaciones) o, (SELECT COUNT(*) FROM anuncios) a")
malos <- c("'; DROP TABLE observaciones; --", "x' OR '1'='1", "100%", "a_b", strrep("a", 61), "uno dos tres cuatro cinco seis", "<script>")
chk("seguridad", "textos peligrosos o fuera de formato se rechazan", all(sapply(malos, function(t) rechaza(filtrar_precios(con, list(texto = t))))))
chk("seguridad", "texto con tilde y apostrofe es valido", !rechaza(filtrar_precios(con, list(texto = "humectaci\u00f3n"))) && !rechaza(filtrar_precios(con, list(texto = "l'oreal"))))
chk("seguridad", "valores raros en filtros se rechazan", rechaza(filtrar_precios(con, list(precio = c("a", "b")))) &&
      rechaza(filtrar_precios(con, list(corrida = "1; DROP"))) && rechaza(filtrar_precios(con, list(fechas = c("hoy", "ayer")))))
chk("seguridad", "listas con comillas se tratan como texto (parametros)", nrow(filtrar_precios(con, list(comercios = "x'); DROP TABLE anuncios;--"))) == 0)
despues <- DBI::dbGetQuery(con, "SELECT (SELECT COUNT(*) FROM observaciones) o, (SELECT COUNT(*) FROM anuncios) a")
chk("seguridad", "las tablas siguen intactas", identical(antes, despues))
chk("seguridad", "escapar_like neutraliza % _ \\", identical(escapar_like("a%b_c\\d"), "a\\%b\\_c\\\\d"))

# ---- 8. integridad ----
chk("integridad", "a lo sumo 1 observacion por anuncio y ejecucion", DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM (SELECT 1 FROM observaciones GROUP BY id_anuncio, id_ejecucion HAVING COUNT(*) > 1)")$n == 0)

# ---- 9. cifras ya verificadas en el traspaso (solo si esta la base real de las 2 corridas) ----
if (all(c("20261017230148", "20261106221640") %in% todas)) {
  chk("traspaso", "239 anuncios (ultimo precio), 24 comparables", nrow(filtrar_precios(con)) == 239 && nrow(filtrar_precios(con, list(solo_comparables = TRUE))) == 24)
  chk("traspaso", "corrida 17-oct: 226 observaciones; corrida 6-nov: 236", nrow(filtrar_precios(con, list(corrida = "20261017230148"))) == 226 &&
        nrow(filtrar_precios(con, list(corrida = "20261106221640"))) == 236)
  ce <- cambios_entre(con, "20261017230148", "20261106221640", 10)
  cm <- ce[ce$situacion %in% c("sube", "baja") & !is.na(ce$id_producto) & ce$id_producto <= 8, ]
  chk("traspaso", "6 cambios en los comparables (4 Exito, 2 Farmatodo, 0 La Rebaja)", nrow(cm) == 6 && sum(cm$comercio == op$comercios[1]) == 4 &&
        sum(cm$comercio == "Farmatodo") == 2, paste(table(cm$comercio), collapse = "/"))
  chk("traspaso", "13 nuevos y 3 no observados", sum(ce$situacion == "nuevo") == 13 && sum(ce$situacion %in% c("no_observado", "agotado_segun_sitio")) == 3,
      paste(table(ce$situacion), collapse = "/"))
}

DBI::dbDisconnect(con)
cat(sprintf("%-12s %-64s %-5s %s\n", res$bloque, res$prueba, ifelse(res$ok, "OK", "FALLA"), res$detalle), sep = "")
cat(sprintf("\n%d de %d pruebas OK.%s\n", sum(res$ok), nrow(res), if (all(res$ok)) " F2 verificada." else " Revisa las filas FALLA."))
