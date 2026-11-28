# ==============================================================================
# TALLER PRÁCTICO CLASE 12: BASES DE DATOS RELACIONALES & SQL AVANZADO EN RSTUDIO
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# PAQUETES: DBI, RSQLite, dplyr, dbplyr, janitor, knitr
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y CONEXIÓN DBI / RSQLITE
# ------------------------------------------------------------------------------
cat("===================================================================
")
cat("TALLER CLASE 12 - SQL AVANZADO, WINDOW FUNCTIONS & DBPYLR EN RSTUDIO
")
cat("Autor: Inti A. Olaya
")
cat("===================================================================

")

paquetes <- c("DBI", "RSQLite", "dplyr", "dbplyr", "janitor", "knitr")
instalados <- rownames(installed.packages())
pendientes <- setdiff(paquetes, instalados)
if (length(pendientes) > 0) install.packages(pendientes)

invisible(lapply(paquetes, library, character.only = TRUE))

# Crear/Conectar base de datos SQLite relacional en memoria
con <- dbConnect(RSQLite::SQLite(), ":memory:")

cat("-> Conexión a la base de datos relacional SQLite en memoria establecida.

")

# Recrear esquema relacional para el Taller (Modelado Chinook Simplificado)
dbExecute(con, "
CREATE TABLE Artist (
  ArtistId INTEGER PRIMARY KEY,
  Name TEXT NOT NULL
);
")

dbExecute(con, "
CREATE TABLE Album (
  AlbumId INTEGER PRIMARY KEY,
  Title TEXT NOT NULL,
  ArtistId INTEGER,
  FOREIGN KEY (ArtistId) REFERENCES Artist(ArtistId)
);
")

dbExecute(con, "
CREATE TABLE Genre (
  GenreId INTEGER PRIMARY KEY,
  Name TEXT NOT NULL
);
")

dbExecute(con, "
CREATE TABLE Track (
  TrackId INTEGER PRIMARY KEY,
  Name TEXT NOT NULL,
  AlbumId INTEGER,
  GenreId INTEGER,
  Milliseconds INTEGER,
  UnitPrice REAL,
  FOREIGN KEY (AlbumId) REFERENCES Album(AlbumId),
  FOREIGN KEY (GenreId) REFERENCES Genre(GenreId)
);
")

dbExecute(con, "
CREATE TABLE Customer (
  CustomerId INTEGER PRIMARY KEY,
  FirstName TEXT NOT NULL,
  LastName TEXT NOT NULL,
  Country TEXT NOT NULL,
  SupportRepId INTEGER
);
")

dbExecute(con, "
CREATE TABLE Invoice (
  InvoiceId INTEGER PRIMARY KEY,
  CustomerId INTEGER,
  InvoiceDate TEXT NOT NULL,
  Total REAL,
  FOREIGN KEY (CustomerId) REFERENCES Customer(CustomerId)
);
")

dbExecute(con, "
CREATE TABLE Employee (
  EmployeeId INTEGER PRIMARY KEY,
  FirstName TEXT NOT NULL,
  LastName TEXT NOT NULL,
  Title TEXT NOT NULL,
  ReportsTo INTEGER
);
")

# Poblar tablas relacionales
dbExecute(con, "INSERT INTO Artist VALUES (1, 'AC/DC'), (2, 'Accept'), (3, 'Metallica'), (4, 'Iron Maiden'), (5, 'Nirvana');")
dbExecute(con, "INSERT INTO Album VALUES (1, 'For Those About to Rock', 1), (2, 'Balls to the Wall', 2), (3, 'Master of Puppets', 3), (4, 'The Number of the Beast', 4), (5, 'Nevermind', 5);")
dbExecute(con, "INSERT INTO Genre VALUES (1, 'Rock'), (2, 'Heavy Metal'), (3, 'Thrash Metal'), (4, 'Grunge');")

dbExecute(con, "
INSERT INTO Track VALUES 
(1, 'For Those About To Rock', 1, 1, 343719, 0.99),
(2, 'Put The Finger On You', 1, 1, 205662, 0.99),
(3, 'Balls to the Wall', 2, 2, 342562, 0.99),
(4, 'Fast As a Shark', 2, 2, 230619, 0.99),
(5, 'Battery', 3, 3, 312411, 1.29),
(6, 'Master of Puppets', 3, 3, 515200, 1.29),
(7, 'Run to the Hills', 4, 2, 233117, 0.99),
(8, 'Hallowed Be Thy Name', 4, 2, 431000, 1.29),
(9, 'Smells Like Teen Spirit', 5, 4, 301000, 0.99),
(10, 'Come As You Are', 5, 4, 219000, 0.99);
")

dbExecute(con, "
INSERT INTO Customer VALUES 
(1, 'Helena', 'Holý', 'Czech Republic', 3),
(2, 'Richard', 'Cunningham', 'USA', 3),
(3, 'Luis', 'Rojas', 'Chile', 5),
(4, 'Astrid', 'Gruber', 'Austria', 5),
(5, 'Eduardo', 'Martins', 'Brazil', 3);
")

dbExecute(con, "
INSERT INTO Invoice VALUES 
(101, 1, '2026-01-15', 49.62),
(102, 2, '2026-01-20', 47.62),
(103, 3, '2026-02-01', 46.62),
(104, 4, '2026-02-10', 42.62),
(105, 5, '2026-02-15', 37.62),
(106, 1, '2026-03-01', 15.50),
(107, 2, '2026-03-05', 12.00);
")

dbExecute(con, "
INSERT INTO Employee VALUES 
(1, 'Andrew', 'Adams', 'General Manager', NULL),
(2, 'Nancy', 'Edwards', 'Sales Manager', 1),
(3, 'Jane', 'Peacock', 'Sales Support Agent', 2),
(4, 'Margaret', 'Park', 'Sales Support Agent', 2),
(5, 'Steve', 'Johnson', 'Sales Support Agent', 2);
")

cat("-> Tablas en la base de datos relacional:
")
print(dbListTables(con))

# ------------------------------------------------------------------------------
# 2. CONSULTAS DE JOINS Y RELACIONES COMPLEJAS (INNER, LEFT & SELF JOIN)
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- 2. CONSULTAS CON JOINS MULTITABLA & SELF-JOIN DE EMPLEADOS ---
")
cat("===================================================================
")

# Self-Join: Estructura Jerárquica de Empleados y sus Supervisores
query_self_join <- "
SELECT 
  e.FirstName || ' ' || e.LastName AS empleado,
  e.Title AS cargo,
  COALESCE(s.FirstName || ' ' || s.LastName, 'Sin Supervisor') AS supervisor
FROM Employee e
LEFT JOIN Employee s ON e.ReportsTo = s.EmployeeId
ORDER BY e.EmployeeId;
"
res_self_join <- dbGetQuery(con, query_self_join)
cat("
1. Jerarquía Organizacional (Self-Join):
")
print(kable(res_self_join))

# Inner Join Multitabla: Pistas, Álbumes, Artistas y Géneros
query_multijoin <- "
SELECT 
  t.Name AS pista,
  al.Title AS album,
  ar.Name AS artista,
  g.Name AS genero,
  ROUND(t.Milliseconds / 60000.0, 2) AS duracion_min
FROM Track t
INNER JOIN Album al ON t.AlbumId = al.AlbumId
INNER JOIN Artist ar ON al.ArtistId = ar.ArtistId
INNER JOIN Genre g ON t.GenreId = g.GenreId
ORDER BY duracion_min DESC;
"
res_multijoin <- dbGetQuery(con, query_multijoin)
cat("
2. Pistas con Detalle Multitabla (Joins Enlazados):
")
print(kable(head(res_multijoin, 6)))

# ------------------------------------------------------------------------------
# 3. EXPRESIONES DE TABLA COMÚN (CTEs) Y OPERACIONES DE CONJUNTOS
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- 3. CTEs (WITH) Y CONJUNTOS (UNION, INTERSECT, EXCEPT) ---
")
cat("===================================================================
")

# CTE para categorizar ventas por país comparadas con el promedio global
query_cte <- "
WITH VentasPorCliente AS (
  SELECT 
    c.CustomerId,
    c.FirstName || ' ' || c.LastName AS cliente,
    c.Country AS pais,
    SUM(i.Total) AS gasto_total
  FROM Customer c
  JOIN Invoice i ON c.CustomerId = i.CustomerId
  GROUP BY c.CustomerId
),
PromedioGlobal AS (
  SELECT AVG(gasto_total) AS media_gasto FROM VentasPorCliente
)
SELECT 
  v.cliente,
  v.pais,
  v.gasto_total,
  ROUND(p.media_gasto, 2) AS media_global,
  CASE 
    WHEN v.gasto_total >= p.media_gasto THEN 'Alto Valor'
    ELSE 'Estándar'
  END AS segmento
FROM VentasPorCliente v, PromedioGlobal p
ORDER BY v.gasto_total DESC;
"
res_cte <- dbGetQuery(con, query_cte)
cat("
1. Clasificación por CTEs y Promedios Globales:
")
print(kable(res_cte))

# ------------------------------------------------------------------------------
# 4. FUNCIONES DE VENTANA (WINDOW FUNCTIONS: ROW_NUMBER, RANK, LAG, LEAD)
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- 4. FUNCIONES DE VENTANA (OVER, PARTITION BY, RANK & LAG) ---
")
cat("===================================================================
")

query_window <- "
SELECT 
  g.Name AS genero,
  t.Name AS pista,
  t.Milliseconds / 1000 AS duracion_seg,
  ROW_NUMBER() OVER(PARTITION BY t.GenreId ORDER BY t.Milliseconds DESC) AS num_fila,
  RANK() OVER(PARTITION BY t.GenreId ORDER BY t.Milliseconds DESC) AS ranking_duracion,
  LAG(t.Name, 1) OVER(PARTITION BY t.GenreId ORDER BY t.Milliseconds DESC) AS pista_anterior
FROM Track t
JOIN Genre g ON t.GenreId = g.GenreId
ORDER BY genero, ranking_duracion;
"
res_window <- dbGetQuery(con, query_window)
cat("
1. Rankings y Análisis de Secuencia con Window Functions:
")
print(kable(res_window))

# ------------------------------------------------------------------------------
# 5. INTEGRACIÓN TRADUCTORA DBPYLR (SQL <-> RSTUDIO TIDYVERSE)
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- 5. INTERFAZ DBPYLR Y GENERACIÓN AUTOMÁTICA DE SQL ---
")
cat("===================================================================
")

# Mapear tabla SQLite directamente como referencia dbplyr
tbl_track <- tbl(con, "Track")
tbl_genre <- tbl(con, "Genre")

# Construir flujo analítico en Tidyverse sobre base de datos remota
consulta_dbplyr <- tbl_track %>%
  inner_join(tbl_genre, by = "GenreId", suffix = c("_track", "_genre")) %>%
  group_by(Name_genre) %>%
  summarise(
    total_pistas = n(),
    duracion_promedio_ms = mean(Milliseconds, na.rm = TRUE),
    precio_maximo = max(UnitPrice, na.rm = TRUE)
  ) %>%
  filter(total_pistas >= 1) %>%
  arrange(desc(total_pistas))

cat("
1. Código SQL Autogenerado por dbplyr (show_query):
")
show_query(consulta_dbplyr)

cat("
2. Ejecución y Recolección a Tibble Local (collect):
")
res_dbplyr <- collect(consulta_dbplyr)
print(kable(res_dbplyr))

# Desconectar base de datos limpia al finalizar
dbDisconnect(con)
cat("
-> Conexión a la base de datos cerrada exitosamente.
")

# ------------------------------------------------------------------------------
# 6. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 12 ---
")
cat("1. cd ~/mineria_datos_course
")
cat("2. git status
")
cat("3. git add taller_12_mineria_datos.R
")
cat("4. git commit -m "Entrega Taller Clase 12 (SQL Avanzado & DBI) - Inti A. Olaya"
")
cat("5. git push origin main
")
cat("===================================================================
")
