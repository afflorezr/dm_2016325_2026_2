# scripts/verificar_f4.R -- Verifica promociones_por_comercio() (grafico 4).
# Ejecutar en la CONSOLA de RStudio, desde la raiz del proyecto:  source("scripts/verificar_f4.R", encoding = "UTF-8")
source("db.R", encoding = "UTF-8")
con <- conectar()
raw <- DBI::dbGetQuery(con, "
  SELECT o.id_anuncio, c.nombre AS comercio, o.fecha_hora_consulta, o.precio_cop, o.precio_lista_cop, o.es_promocion,
         e.codigo_corrida, COALESCE(p.en_conjunto, 0) AS en_conjunto
    FROM observaciones o JOIN anuncios a ON a.id_anuncio = o.id_anuncio
    JOIN comercios c ON c.id_comercio = o.id_comercio JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion
    LEFT JOIN productos p ON p.id_producto = a.id_producto")
ord <- raw[order(raw$id_anuncio, raw$fecha_hora_consulta), ]
ultimo <- ord[!duplicated(ord$id_anuncio, fromLast = TRUE), ]
ult <- sort(unique(raw$codigo_corrida), decreasing = TRUE)[1]
casos <- list(list(f = list(), d = ultimo),
              list(f = list(solo_comparables = TRUE), d = ultimo[ultimo$en_conjunto == 1, ]),
              list(f = list(corrida = ult), d = raw[raw$codigo_corrida == ult, ]))
ok <- logical()
for (k in seq_along(casos)) {
  r <- promociones_por_comercio(con, casos[[k]]$f); d <- casos[[k]]$d
  ok[k] <- setequal(r$comercio, unique(d$comercio)) && all(sapply(seq_len(nrow(r)), function(i) {
    x <- d[d$comercio == r$comercio[i], ]; pr <- x[x$es_promocion == 1, ]
    dsc <- if (nrow(pr)) round(median(100 * (pr$precio_lista_cop - pr$precio_cop) / pr$precio_lista_cop), 1) else NA
    r$productos[i] == length(unique(x$id_anuncio)) && r$en_promocion[i] == length(unique(pr$id_anuncio)) &&
      isTRUE(all.equal(r$pct_promocion[i], round(100 * length(unique(pr$id_anuncio)) / length(unique(x$id_anuncio)), 1))) &&
      ((is.na(dsc) && is.na(r$descuento_mediano_pct[i])) || isTRUE(all.equal(r$descuento_mediano_pct[i], dsc, tolerance = 0.11)))
  }))
}
cat(sprintf("%-60s %s\n", c("promociones: sin filtros (ultimo precio)", "promociones: solo comparables", "promociones: una ejecucion"), ifelse(ok, "OK", "FALLA")), sep = "")
print(promociones_por_comercio(con))
DBI::dbDisconnect(con)
cat(sprintf("\n%d de %d pruebas OK.\n", sum(ok), length(ok)))
