# Taller 2 - prueba de la canasta sobre SQLite real, SOLO LECTURA.
stopifnot(file.exists("canasta.R"), file.exists("comparador_precios.sqlite"))
source("canasta.R", encoding = "UTF-8")

local({
  con <- DBI::dbConnect(
    RSQLite::SQLite(), "comparador_precios.sqlite",
    flags = RSQLite::SQLITE_RO
  )
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  cat("\n=== EJECUCIONES DISPONIBLES ===\n")
  ejecuciones <- listar_ejecuciones_canasta_db(con)
  print(ejecuciones)
  stopifnot(nrow(ejecuciones) > 0L)

  cat("\n=== PRODUCTOS HOMOLOGADOS ===\n")
  print(listar_productos_canasta_db(con))

  cat("\n=== PRUEBA: 1 P01 + 2 P02 ===\n")
  resultado <- calcular_canasta_db(
    con, ejecuciones$ejecucion_id[1L], c(P01 = 1L, P02 = 2L)
  )
  cat("Ejecucion utilizada:", resultado$ejecucion_id, "\n")
  print(resultado$por_comercio)
  cat("\n--- Recomendacion por producto ---\n")
  print(resultado$detalle_mixto)
  cat("\nMejor tienda completa:", resultado$mejor_comercio_completo, "\n")
  cat("Costo mejor tienda (COP):", resultado$mejor_total_cop, "\n")
  cat("Costo compra mixta (COP):", resultado$costo_mixto_cop, "\n")
  cat("Ahorro (COP):", resultado$ahorro_cop, "\n")
  cat("Ahorro (%):", round(resultado$ahorro_pct, 2), "\n")
  cat("Nota:", resultado$mensaje, "\n")
  cat(resultado$advertencia, "\n")

  stopifnot(
    length(resultado$por_comercio$comercio) == 3L,
    length(resultado$detalle_mixto$producto_comun_id) == 2L,
    all(resultado$detalle_mixto$cantidad == c(1, 2)),
    !is.na(resultado$costo_mixto_cop),
    all(is.na(resultado$por_comercio$costo_total_cop) |
        resultado$por_comercio$costo_total_cop >= resultado$costo_mixto_cop)
  )
  cat("\nPRUEBA SUPERADA: mismos precios de una ejecucion y totales coherentes.\n")
})
