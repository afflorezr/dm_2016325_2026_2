source("db.R")
corrida <- "20261110-141724" # id_corrida para consulta de indicadores
clave   <- db_q("SELECT clave_producto FROM v_comparables WHERE id_corrida = ? LIMIT 1",
                list(corrida))$clave_producto      # para la consulta G1

con <- db_abrir(); on.exit(dbDisconnect(con))
lin <- readLines("sql/04_consultas_indicadores.sql", encoding = "UTF-8")
txt <- paste(lin[!grepl("^\\s*--", lin)], collapse = "\n")
qs  <- trimws(strsplit(txt, ";", fixed = TRUE)[[1]]); qs <- qs[nzchar(qs)]

for (q in qs) {
  nombres <- unique(sub(":", "", regmatches(q, gregexpr(":[a-z_]+", q))[[1]]))
  pars <- c(corrida = corrida, clave = clave)[nombres]
  cat("\n---", substr(gsub("\\s+", " ", q), 1, 70), "...\n")
  print(if (length(pars)) dbGetQuery(con, q, params = as.list(pars)) else dbGetQuery(con, q))
}