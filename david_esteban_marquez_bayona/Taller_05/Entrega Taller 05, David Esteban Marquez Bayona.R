# =============================================================================
# Minería de Datos — Taller práctico de SQL, Parte 2 (Chinook)
# Ejercicios de clase 1, 2 y 3
# Autor: David Márquez
# =============================================================================
library(DBI)
library(RSQLite)
library(dplyr)

con <- dbConnect(RSQLite::SQLite(), "C:/Users/Estudiante/Documents/david_esteban_marquez_bayona/david_esteban_marquez_bayona/Taller_05/chinook.db")   # ajuste la ruta
q <- function(sql) dbGetQuery(con, sql)

# =============================================================================
# EJERCICIO 1: JOINs avanzados, subconsultas correlacionadas y conjuntos
# =============================================================================

# 1.1 Cliente -> empleado de soporte -> jefe (SELF JOIN + COALESCE)
ej1_1 <- q("
SELECT c.FirstName || ' ' || c.LastName                    AS cliente,
       e.FirstName || ' ' || e.LastName                    AS soporte,
       COALESCE(j.FirstName || ' ' || j.LastName, 'Sin jefe') AS jefe
FROM Customer c
INNER JOIN Employee e ON c.SupportRepId = e.EmployeeId
LEFT  JOIN Employee j ON e.ReportsTo   = j.EmployeeId
ORDER BY soporte, cliente;
")
head(ej1_1, 10); nrow(ej1_1)
count(ej1_1, soporte, jefe)
# Nota: con LEFT JOIN en el jefe, un empleado sin jefe no se pierde y
# COALESCE muestra 'Sin jefe'. (Con INNER JOIN esas filas desaparecerían.)

# 1.2 Clientes que gastan más que el promedio de los DEMÁS clientes de su
#     mismo representante (subconsulta correlacionada)
ej1_2 <- q("
WITH gasto AS (
  SELECT c.CustomerId, c.FirstName || ' ' || c.LastName AS cliente,
         c.SupportRepId, SUM(i.Total) AS gasto_total
  FROM Customer c
  JOIN Invoice i ON i.CustomerId = c.CustomerId
  GROUP BY c.CustomerId
)
SELECT g.cliente, g.SupportRepId, ROUND(g.gasto_total, 2) AS gasto_total,
       ROUND((SELECT AVG(g2.gasto_total)
              FROM gasto g2
              WHERE g2.SupportRepId = g.SupportRepId
                AND g2.CustomerId  <> g.CustomerId), 2) AS promedio_otros_mismo_rep
FROM gasto g
WHERE g.gasto_total > (SELECT AVG(g2.gasto_total)
                       FROM gasto g2
                       WHERE g2.SupportRepId = g.SupportRepId     -- correlación
                         AND g2.CustomerId  <> g.CustomerId)      -- los demás
ORDER BY g.SupportRepId, g.gasto_total DESC;
")
ej1_2; nrow(ej1_2)

# 1.3 Empleados que nunca han sido soporte (EXCEPT)
ej1_3 <- q("
SELECT EmployeeId FROM Employee
EXCEPT
SELECT SupportRepId FROM Customer WHERE SupportRepId IS NOT NULL;
")
q(paste0("SELECT EmployeeId, FirstName || ' ' || LastName AS empleado, Title
          FROM Employee WHERE EmployeeId IN (",
         paste(ej1_3$EmployeeId, collapse = ","), ")"))

# 1.4 Clientes e ingresos por empleado (CTE)
ej1_4 <- q("
WITH clientes_rep AS (
  SELECT SupportRepId, COUNT(*) AS n_clientes
  FROM Customer GROUP BY SupportRepId
),
ingresos_rep AS (
  SELECT c.SupportRepId, SUM(i.Total) AS ingreso_total
  FROM Customer c JOIN Invoice i ON i.CustomerId = c.CustomerId
  GROUP BY c.SupportRepId
)
SELECT e.FirstName || ' ' || e.LastName AS empleado, cr.n_clientes,
       ROUND(ir.ingreso_total, 2) AS ingreso_total,
       ROUND(ir.ingreso_total / cr.n_clientes, 2) AS ingreso_por_cliente
FROM clientes_rep cr
JOIN ingresos_rep ir ON ir.SupportRepId = cr.SupportRepId
JOIN Employee e      ON e.EmployeeId    = cr.SupportRepId
ORDER BY ingreso_total DESC;
")
ej1_4

# =============================================================================
# EJERCICIO 2: funciones de ventana y CTEs encadenadas
# =============================================================================

# 2.1 Ventas por mes con LAG y LEAD y variación porcentual
ej2_1 <- q("
WITH ventas_mes AS (
  SELECT SUBSTR(InvoiceDate, 1, 7) AS anio_mes, SUM(Total) AS ventas
  FROM Invoice GROUP BY anio_mes
)
SELECT anio_mes, ROUND(ventas, 2) AS ventas,
       ROUND(LAG(ventas)  OVER (ORDER BY anio_mes), 2) AS ventas_mes_anterior,
       ROUND(LEAD(ventas) OVER (ORDER BY anio_mes), 2) AS ventas_mes_siguiente,
       ROUND(100.0 * (ventas - LAG(ventas) OVER (ORDER BY anio_mes))
             / LAG(ventas) OVER (ORDER BY anio_mes), 2) AS variacion_pct
FROM ventas_mes
ORDER BY anio_mes;
")
head(ej2_1, 12); nrow(ej2_1)
summary(ej2_1$variacion_pct)

# 2.2 Mes de mayor y menor venta por año (dos RANK)
ej2_2 <- q("
WITH ventas_mes AS (
  SELECT SUBSTR(InvoiceDate, 1, 4) AS anio, SUBSTR(InvoiceDate, 6, 2) AS mes,
         SUM(Total) AS ventas
  FROM Invoice GROUP BY anio, mes
),
rankings AS (
  SELECT anio, mes, ventas,
         RANK() OVER (PARTITION BY anio ORDER BY ventas DESC) AS rk_top,
         RANK() OVER (PARTITION BY anio ORDER BY ventas ASC)  AS rk_bajo
  FROM ventas_mes
)
SELECT t.anio,
       GROUP_CONCAT(DISTINCT t.mes)  AS mes_top,   ROUND(MAX(t.ventas), 2) AS ventas_top,
       GROUP_CONCAT(DISTINCT b.mes)  AS mes_bajo,  ROUND(MIN(b.ventas), 2) AS ventas_bajo
FROM (SELECT * FROM rankings WHERE rk_top  = 1) t
JOIN (SELECT * FROM rankings WHERE rk_bajo = 1) b ON b.anio = t.anio
GROUP BY t.anio
ORDER BY t.anio;
")
ej2_2
# (GROUP_CONCAT muestra todos los meses si hay empate en el rango 1.)

# 2.3 Género con mayores ingresos por año (CTE encadenada + RANK + WHERE)
ej2_3 <- q("
WITH ingresos_genero AS (
  SELECT SUBSTR(i.InvoiceDate, 1, 4) AS anio, g.Name AS genero,
         SUM(il.UnitPrice * il.Quantity) AS ingresos
  FROM Invoice i
  JOIN InvoiceLine il ON il.InvoiceId = i.InvoiceId
  JOIN Track t        ON t.TrackId    = il.TrackId
  JOIN Genre g        ON g.GenreId    = t.GenreId
  GROUP BY anio, genero
),
ranking_genero AS (
  SELECT anio, genero, ingresos,
         RANK() OVER (PARTITION BY anio ORDER BY ingresos DESC) AS rk
  FROM ingresos_genero
)
SELECT anio, genero, ROUND(ingresos, 2) AS ingresos
FROM ranking_genero
WHERE rk = 1
ORDER BY anio;
")
ej2_3

# 2.4 Cuartiles de gasto (NTILE) y peso de Q4
ej2_4 <- q("
WITH gasto AS (
  SELECT CustomerId, SUM(Total) AS gasto_total
  FROM Invoice GROUP BY CustomerId
),
cuartiles AS (
  SELECT CustomerId, gasto_total,
         NTILE(4) OVER (ORDER BY gasto_total) AS cuartil
  FROM gasto
),
por_cuartil AS (
  SELECT cuartil, COUNT(*) AS n_clientes, SUM(gasto_total) AS ingreso
  FROM cuartiles GROUP BY cuartil
)
SELECT cuartil, n_clientes, ROUND(ingreso, 2) AS ingreso,
       ROUND(100.0 * ingreso / (SELECT SUM(ingreso) FROM por_cuartil), 2) AS pct_ingreso
FROM por_cuartil
ORDER BY cuartil;
")
ej2_4
ej2_4_resumen <- q("
WITH gasto AS (
  SELECT CustomerId, SUM(Total) AS gasto_total FROM Invoice GROUP BY CustomerId
),
cuartiles AS (
  SELECT gasto_total, NTILE(4) OVER (ORDER BY gasto_total) AS cuartil FROM gasto
)
SELECT CASE WHEN cuartil = 4 THEN 'Q4 (superior)' ELSE 'Q1-Q3' END AS grupo,
       ROUND(SUM(gasto_total), 2) AS ingreso,
       ROUND(100.0 * SUM(gasto_total) / (SELECT SUM(gasto_total) FROM gasto), 2) AS pct
FROM cuartiles
GROUP BY grupo;
")
ej2_4_resumen

# =============================================================================
# EJERCICIO 3 (reto): clientes en riesgo de abandono
# =============================================================================

# 3.1 Fecha de la última factura (el "presente")
q("SELECT MAX(InvoiceDate) AS fecha_maxima FROM Invoice;")

# 3.2 y 3.3 Última compra, meses sin comprar y segmento
segmentos_sql <- "
WITH fecha_max AS (
  SELECT MAX(InvoiceDate) AS fecha_maxima FROM Invoice
),
clientes AS (
  SELECT c.CustomerId, c.FirstName || ' ' || c.LastName AS cliente, c.Country,
         MAX(i.InvoiceDate) AS ultima_compra,
         SUM(i.Total)       AS gasto_historico
  FROM Customer c JOIN Invoice i ON i.CustomerId = c.CustomerId
  GROUP BY c.CustomerId
),
recencia AS (
  SELECT cl.*,
         ROUND((JULIANDAY(f.fecha_maxima) - JULIANDAY(cl.ultima_compra)) / 30, 1)
           AS meses_sin_comprar
  FROM clientes cl CROSS JOIN fecha_max f
),
segmentados AS (
  SELECT *,
         CASE WHEN meses_sin_comprar <= 6  THEN 'activo'
              WHEN meses_sin_comprar <= 12 THEN 'en riesgo'
              ELSE 'inactivo' END AS segmento
  FROM recencia
)
"
ej3_clientes <- q(paste0(segmentos_sql, "
SELECT cliente, Country, ultima_compra, meses_sin_comprar,
       ROUND(gasto_historico, 2) AS gasto_historico, segmento
FROM segmentados ORDER BY meses_sin_comprar DESC;"))
head(ej3_clientes, 10)
summary(ej3_clientes$meses_sin_comprar)

# 3.4 Resumen por segmento
ej3_resumen <- q(paste0(segmentos_sql, "
SELECT segmento, COUNT(*) AS n_clientes,
       ROUND(AVG(gasto_historico), 2) AS gasto_promedio,
       ROUND(SUM(gasto_historico), 2) AS gasto_total
FROM segmentados GROUP BY segmento
ORDER BY CASE segmento WHEN 'activo' THEN 1 WHEN 'en riesgo' THEN 2 ELSE 3 END;"))
ej3_resumen

# Top 3 de gasto dentro de cada segmento
ej3_top3 <- q(paste0(segmentos_sql, ",
ranking AS (
  SELECT segmento, cliente, Country, meses_sin_comprar, gasto_historico,
         RANK() OVER (PARTITION BY segmento ORDER BY gasto_historico DESC) AS rk
  FROM segmentados
)
SELECT segmento, rk, cliente, Country, meses_sin_comprar,
       ROUND(gasto_historico, 2) AS gasto_historico
FROM ranking WHERE rk <= 3
ORDER BY segmento, rk;"))
ej3_top3

dbDisconnect(con)

# =============================================================================
# RESPUESTAS
# =============================================================================
# (Resultados con chinook.db del curso: facturas de 2021-01 a 2025-12.)
#
# EJERCICIO 1
# 1. 59 clientes. Todos tienen soporte asignado entre Jane Peacock (21),
#    Margaret Park (20) y Steve Johnson (18), y los tres reportan a Nancy
#    Edwards; por eso 'Sin jefe' no aparece en esta consulta. Aparecería si un
#    representante no tuviera jefe (p. ej. Andrew Adams, el gerente general,
#    tiene ReportsTo NULL). Se usa LEFT JOIN en el segundo JOIN para que esas
#    filas no se pierdan y COALESCE las rotule.
# 2. 18 clientes gastan más que el promedio de los demás clientes de su mismo
#    representante: 6 de Jane Peacock (id 3), 6 de Margaret Park (id 4) y 6 de
#    Steve Johnson (id 5). Los de mayor gasto: Helena Holý (49,62), Richard
#    Cunningham (47,62) y Luis Rojas (46,62). La subconsulta se recalcula para
#    cada cliente (correlación por SupportRepId) y excluye al propio cliente.
# 3. Nunca han sido soporte: Andrew Adams (General Manager), Nancy Edwards
#    (Sales Manager), Michael Mitchell (IT Manager), Robert King y Laura
#    Callahan (IT Staff): son gerentes y personal de TI, no agentes de ventas.
# 4. Jane Peacock: 21 clientes, 833,04; Margaret Park: 20, 775,40; Steve
#    Johnson: 18, 720,16. Sí, quien atiende más clientes genera más ingresos,
#    pero por volumen, no por cliente: el ingreso por cliente es casi igual
#    (38,77 a 40,01) y el mayor es el de Steve Johnson (40,01), que tiene
#    menos clientes. La diferencia la explica el número de clientes asignados.
#
# EJERCICIO 2
# 1. 60 meses. Las ventas son muy estables (casi siempre 37,62): la variación
#    porcentual es 0 % en la mayoría de los meses, con picos entre -36,8 % y
#    +58,3 %. El primer mes no tiene anterior (NA) y el último no tiene
#    siguiente.
# 2. Mes top y mes más bajo por año:
#      2021: top feb-dic (empate, 37,62)         bajo: ene (35,64)
#      2022: top ene (52,62)                     bajo: sep (36,63)
#      2023: top abr (51,62)                     bajo: nov (23,76)
#      2024: top ago (47,62)                     bajo: varios meses (37,62)
#      2025: top nov (49,62)                     bajo: feb (27,72)
#    RANK() asigna el mismo puesto a los empates, por eso en 2021 y 2024 hay
#    varios meses en el puesto 1.
# 3. Rock es el género con mayores ingresos en los 5 años (entre 155,43 y
#    178,20 por año).
# 4. Con NTILE(4) sobre 59 clientes los cuartiles quedan de 15, 15, 15 y 14.
#    Q4 aporta el 26,4 % del ingreso total (614,68) frente al 73,6 % de
#    Q1-Q3 (1.713,92). Cada cuartil aporta entre 24 % y 26 %: el gasto está
#    muy repartido, no hay un grupo pequeño de clientes que concentre las
#    ventas (no se cumple un 80/20).
#
# EJERCICIO 3
# 1. Fecha máxima: 2025-12-22.
# 2-3. Meses sin comprar: de 0 a 19 (mediana 5,6). Segmentos:
#      activo (<= 6 meses): 31 clientes, gasto promedio 39,56, total 1.226,22
#      en riesgo (6-12):    15 clientes, gasto promedio 39,82, total   597,30
#      inactivo (> 12):     13 clientes, gasto promedio 38,85, total   505,08
# 4. Top 3 por segmento:
#      activo:    Helena Holý (49,62); Ladislav Kovács y Hugh O'Reilly (45,62)
#      en riesgo: Richard Cunningham (47,62); Julia Barnett y Fynn
#                 Zimmermann (43,62)
#      inactivo:  Luis Rojas (46,62); Jack Smith y João Fernandes (39,62)
#    Interpretación: la campaña de retención debe priorizar el segmento
#    "en riesgo": son 15 clientes con el gasto promedio más alto (39,82) y
#    597,30 de valor histórico, y todavía es posible recuperarlos (6 a 12
#    meses sin comprar). Empezaría por Richard Cunningham, Julia Barnett y
#    Fynn Zimmermann. Los inactivos (> 12 meses) son más difíciles y
#    costosos de recuperar; solo vale una acción puntual para los de mayor
#    valor, como Luis Rojas.
