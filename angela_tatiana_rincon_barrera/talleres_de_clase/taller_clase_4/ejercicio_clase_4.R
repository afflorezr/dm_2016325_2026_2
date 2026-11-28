# Taller de SQL con R
# 11. Ejercicios de clase

paquetes   <- c("DBI", "RSQLite", "dplyr", "knitr")
pendientes <- setdiff(paquetes, rownames(installed.packages()))
if (length(pendientes) > 0) install.packages(pendientes)

library(DBI)
library(RSQLite)
library(dplyr)

url_chinook <- "https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
ruta_db     <- "chinook.db"

if (!file.exists(ruta_db)) download.file(url_chinook, destfile = ruta_db, mode = "wb")

con <- dbConnect(RSQLite::SQLite(), ruta_db)

mostrar_tabla <- function(df, n = nrow(df), caption = NULL) {
  print(knitr::kable(head(df, n), caption = caption))
}


# Ejercicio 1: colección musical ------------------------------------------

# 1.1
total_pistas <- dbGetQuery(con, "
  SELECT COUNT(*) AS total_pistas
  FROM   Track;
")
mostrar_tabla(total_pistas, caption = "Total de pistas")

# 1.2
total_generos <- dbGetQuery(con, "
  SELECT COUNT(DISTINCT GenreId) AS total_generos
  FROM   Genre;
")
mostrar_tabla(total_generos, caption = "Géneros distintos")

# 1.3
pistas_genero <- dbGetQuery(con, "
  SELECT   g.Name                                  AS genero,
           COUNT(t.TrackId)                        AS n_pistas,
           ROUND(AVG(t.Milliseconds) / 60000.0, 2) AS duracion_media_min
  FROM     Track t
  JOIN     Genre g ON t.GenreId = g.GenreId
  GROUP BY g.Name
  ORDER BY n_pistas DESC;
")
mostrar_tabla(pistas_genero, caption = "Pistas y duración media por género")

# 1.4
pistas_largas <- dbGetQuery(con, "
  SELECT   t.Name                             AS pista,
           a.Title                            AS album,
           ROUND(t.Milliseconds / 60000.0, 2) AS duracion_min
  FROM     Track t
  JOIN     Album a ON t.AlbumId = a.AlbumId
  ORDER BY t.Milliseconds DESC
  LIMIT    5;
")
mostrar_tabla(pistas_largas, caption = "Las 5 pistas más largas")

# 1.5
precio_mayor <- dbGetQuery(con, "
  SELECT SUM(CASE WHEN UnitPrice > 0.99 THEN 1 ELSE 0 END) AS pistas_mayor_099,
         COUNT(*)                                          AS total_pistas,
         ROUND(100.0 * SUM(CASE WHEN UnitPrice > 0.99 THEN 1 ELSE 0 END)
               / COUNT(*), 2)                              AS porcentaje
  FROM   Track;
")
mostrar_tabla(precio_mayor, caption = "Pistas con precio mayor a $0.99")

# 1.6
resumen_duracion <- dbGetQuery(con, "
  SELECT ROUND(AVG(Milliseconds), 2) AS media_ms,
         MIN(Milliseconds)           AS min_ms,
         MAX(Milliseconds)           AS max_ms,
         ROUND(AVG(Milliseconds * Milliseconds) -
               AVG(Milliseconds) * AVG(Milliseconds), 2) AS varianza_ms
  FROM   Track;
")
mostrar_tabla(resumen_duracion, caption = "Duración de las pistas (ms)")


# Ejercicio 2: ventas -----------------------------------------------------

# 2.1
ingresos <- dbGetQuery(con, "
  SELECT ROUND(SUM(Total), 2) AS ingreso_total,
         ROUND(AVG(Total), 2) AS promedio_factura,
         COUNT(*)             AS n_facturas
  FROM   Invoice;
")
mostrar_tabla(ingresos, caption = "Ingresos totales y promedio por factura")

# comprobación con el detalle de InvoiceLine
dbGetQuery(con, "
  SELECT ROUND(SUM(UnitPrice * Quantity), 2) AS ingreso_total_lineas
  FROM   InvoiceLine;
")

# 2.2
facturas_anio <- dbGetQuery(con, "
  SELECT   strftime('%Y', InvoiceDate) AS anio,
           COUNT(*)                    AS n_facturas
  FROM     Invoice
  GROUP BY anio
  ORDER BY anio;
")
mostrar_tabla(facturas_anio, caption = "Facturas por año")

# 2.3
top_paises <- dbGetQuery(con, "
  SELECT   BillingCountry       AS pais,
           COUNT(*)             AS n_facturas,
           ROUND(SUM(Total), 2) AS ingreso_total,
           ROUND(AVG(Total), 2) AS promedio_factura
  FROM     Invoice
  GROUP BY BillingCountry
  ORDER BY ingreso_total DESC
  LIMIT    5;
")
mostrar_tabla(top_paises, caption = "Los 5 países con más ingresos")

# 2.4
varianza_total <- dbGetQuery(con, "
  SELECT AVG(Total * Total) - AVG(Total) * AVG(Total) AS varianza
  FROM   Invoice;
")
desv_estandar <- sqrt(varianza_total$varianza)

cat("Varianza del total por factura:", round(varianza_total$varianza, 4), "\n")
cat("Desviación estándar:", round(desv_estandar, 4), "\n")

# 2.5
ingreso_mes <- dbGetQuery(con, "
  SELECT   strftime('%m', InvoiceDate) AS mes,
           COUNT(*)                    AS n_facturas,
           ROUND(AVG(Total), 4)        AS ingreso_promedio
  FROM     Invoice
  GROUP BY mes
  ORDER BY ingreso_promedio DESC;
")
mostrar_tabla(ingreso_mes, caption = "Ingreso promedio por mes")

ingreso_mes %>% slice_max(ingreso_promedio, n = 1)
ingreso_mes %>% slice_min(ingreso_promedio, n = 1)

dbDisconnect(con)


# Respuestas --------------------------------------------------------------
#
# Ejercicio 1
# 1. Hay 3.503 pistas.
# 2. Hay 25 géneros.
# 3. Rock es el género con más pistas (1.297; 4,73 min en promedio), seguido
#    de Latin (579) y Metal (374). Los géneros de series y películas (TV
#    Shows, Drama, Sci Fi & Fantasy, Science Fiction) tienen las duraciones
#    promedio más altas, entre 35 y 49 min.
# 4. Las 5 más largas son episodios de series: "Occupation / Precipice"
#    (88,12 min) y "Through a Looking Glass" (84,81 min), seguidas de tres
#    episodios de Battlestar Galactica (Classic) de unos 49 min.
# 5. 213 pistas cuestan más de $0.99, el 6,08 % del total.
# 6. Duración media: 393.599 ms (6,6 min); mínima: 1.071 ms; máxima:
#    5.286.953 ms; varianza: 286.149.105.505 ms².
#
# Ejercicio 2
# 1. Ingreso total: $2.328,60, en 412 facturas; promedio por factura: $5,65.
#    La suma de InvoiceLine da el mismo valor.
# 2. 83 facturas por año entre 2021 y 2024, y 80 en 2025.
# 3. Estados Unidos (91 facturas, $523,06, $5,75 por factura), Canadá
#    (56, $303,96, $5,43), Francia (35, $195,10, $5,57), Brasil (35,
#    $190,10, $5,43) y Alemania (28, $156,48, $5,59).
# 4. Varianza: 22,46; desviación estándar: 4,74.
# 5. Abril tiene el mayor ingreso promedio por factura ($6,00) y diciembre
#    el menor ($5,40).
