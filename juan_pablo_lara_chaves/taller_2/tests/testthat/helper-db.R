
library(DBI); library(RSQLite)
source("../../db.R")

con_prueba <- function() {
  con <- dbConnect(SQLite(), ":memory:")
  crear_esquema(con)
  dbExecute(con, "INSERT INTO comercios (comercio) VALUES ('A'), ('B'), ('C')")
  dbExecute(con, "INSERT INTO productos (producto_id, contenido, unidad)
                  VALUES ('P1', 1, 'unidad'), ('P2', 1, 'unidad'), ('P3', 1, 'unidad')")
  for (e in c("e1", "e2")) for (cm in c("A", "B", "C"))
    dbExecute(con, "INSERT INTO ejecuciones (ejecucion_id, comercio, fecha_inicio, estado)
                    VALUES (?, ?, '2026-11-01', 'completa')", params = list(e, cm))
  con
}

obs <- function(con, ejec, cm, prod, precio,
                fecha = paste0("2026-11-0", substr(ejec, 2, 2), "T10:00:00")) {
  dbExecute(con, "INSERT INTO observaciones
    (ejecucion_id, comercio, nombre, producto_comercio, precio, fecha_hora, producto_id, comparable)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1)",
    params = list(ejec, cm, paste(prod, cm), paste(prod, cm), precio, fecha, prod))
}

