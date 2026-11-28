# Taller de SQL con R - Parte 2
# 7. Ejercicios de clase

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


# Ejercicio 1 -------------------------------------------------------------

# 1.1 cliente, empleado de soporte y jefe
clientes_soporte <- dbGetQuery(con, "
  SELECT   c.FirstName || ' ' || c.LastName                  AS cliente,
           e.FirstName || ' ' || e.LastName                  AS empleado_soporte,
           COALESCE(j.FirstName || ' ' || j.LastName, 'Sin jefe') AS jefe
  FROM     Customer c
  INNER JOIN Employee e ON c.SupportRepId = e.EmployeeId
  LEFT JOIN  Employee j ON e.ReportsTo    = j.EmployeeId
  ORDER BY empleado_soporte, cliente;
")
mostrar_tabla(clientes_soporte, n = 15, caption = "Cliente, soporte y jefe")

# 1.2 clientes que gastan más que el promedio de los demás clientes
#     de su mismo representante
sobre_promedio <- dbGetQuery(con, "
  WITH gasto AS (
    SELECT   c.CustomerId,
             c.FirstName || ' ' || c.LastName AS cliente,
             c.SupportRepId,
             SUM(i.Total)                     AS gasto_total
    FROM     Customer c
    JOIN     Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
  )
  SELECT   g.cliente,
           e.FirstName || ' ' || e.LastName AS empleado_soporte,
           ROUND(g.gasto_total, 2)          AS gasto_total,
           ROUND((SELECT AVG(g2.gasto_total)
                  FROM   gasto g2
                  WHERE  g2.SupportRepId = g.SupportRepId
                    AND  g2.CustomerId  <> g.CustomerId), 2) AS promedio_demas
  FROM     gasto g
  JOIN     Employee e ON g.SupportRepId = e.EmployeeId
  WHERE    g.gasto_total > (SELECT AVG(g2.gasto_total)
                            FROM   gasto g2
                            WHERE  g2.SupportRepId = g.SupportRepId
                              AND  g2.CustomerId  <> g.CustomerId)
  ORDER BY empleado_soporte, gasto_total DESC;
")
mostrar_tabla(sobre_promedio, caption = "Clientes sobre el promedio de su representante")

# 1.3 empleados que nunca han sido soporte
sin_clientes <- dbGetQuery(con, "
  SELECT e.EmployeeId,
         e.FirstName || ' ' || e.LastName AS empleado,
         e.Title                          AS cargo
  FROM   Employee e
  WHERE  e.EmployeeId IN (
           SELECT EmployeeId   FROM Employee
           EXCEPT
           SELECT SupportRepId FROM Customer
         )
  ORDER BY e.EmployeeId;
")
mostrar_tabla(sin_clientes, caption = "Empleados sin clientes asignados")

# 1.4 clientes e ingresos por empleado
clientes_empleado <- dbGetQuery(con, "
  WITH clientes AS (
    SELECT   SupportRepId, COUNT(*) AS n_clientes
    FROM     Customer
    GROUP BY SupportRepId
  ),
  ingresos AS (
    SELECT   c.SupportRepId, SUM(i.Total) AS ingreso_total
    FROM     Customer c
    JOIN     Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.SupportRepId
  )
  SELECT   e.FirstName || ' ' || e.LastName AS empleado,
           cl.n_clientes,
           ROUND(ing.ingreso_total, 2)      AS ingreso_total
  FROM     clientes cl
  JOIN     ingresos ing ON cl.SupportRepId = ing.SupportRepId
  JOIN     Employee e   ON cl.SupportRepId = e.EmployeeId
  ORDER BY ingreso_total DESC;
")
mostrar_tabla(clientes_empleado, caption = "Clientes e ingresos por empleado")


# Ejercicio 2 -------------------------------------------------------------

# 2.1 ventas por mes con LAG y LEAD
ventas_mes <- dbGetQuery(con, "
  WITH mensual AS (
    SELECT   SUBSTR(InvoiceDate, 1, 7) AS anio_mes,
             SUM(Total)                AS ventas
    FROM     Invoice
    GROUP BY anio_mes
  )
  SELECT anio_mes,
         ROUND(ventas, 2)                                  AS ventas,
         ROUND(LAG(ventas)  OVER (ORDER BY anio_mes), 2)   AS mes_anterior,
         ROUND(LEAD(ventas) OVER (ORDER BY anio_mes), 2)   AS mes_siguiente,
         ROUND(100.0 * (ventas - LAG(ventas) OVER (ORDER BY anio_mes))
               / LAG(ventas) OVER (ORDER BY anio_mes), 2)  AS variacion_pct
  FROM   mensual
  ORDER BY anio_mes;
")
mostrar_tabla(ventas_mes, n = 12, caption = "Ventas mensuales (primeros 12 meses)")

# 2.2 mes de mayor y menor venta por año
meses_extremos <- dbGetQuery(con, "
  WITH mensual AS (
    SELECT   SUBSTR(InvoiceDate, 1, 4) AS anio,
             SUBSTR(InvoiceDate, 6, 2) AS mes,
             SUM(Total)                AS ventas
    FROM     Invoice
    GROUP BY anio, mes
  ),
  rankings AS (
    SELECT anio, mes, ventas,
           RANK() OVER (PARTITION BY anio ORDER BY ventas DESC) AS rk_top,
           RANK() OVER (PARTITION BY anio ORDER BY ventas ASC)  AS rk_bajo
    FROM   mensual
  )
  SELECT   anio,
           GROUP_CONCAT(CASE WHEN rk_top  = 1 THEN mes END)          AS mes_top,
           ROUND(MAX(CASE WHEN rk_top  = 1 THEN ventas END), 2)      AS ventas_top,
           GROUP_CONCAT(CASE WHEN rk_bajo = 1 THEN mes END)          AS mes_bajo,
           ROUND(MAX(CASE WHEN rk_bajo = 1 THEN ventas END), 2)      AS ventas_bajo
  FROM     rankings
  GROUP BY anio
  ORDER BY anio;
")
mostrar_tabla(meses_extremos, caption = "Mes de mayor y menor venta por año")

# 2.3 género con más ingresos por año
genero_top <- dbGetQuery(con, "
  WITH ventas_genero AS (
    SELECT   SUBSTR(i.InvoiceDate, 1, 4)    AS anio,
             g.Name                          AS genero,
             SUM(il.UnitPrice * il.Quantity) AS ingresos
    FROM     Invoice i
    JOIN     InvoiceLine il ON i.InvoiceId = il.InvoiceId
    JOIN     Track t        ON il.TrackId  = t.TrackId
    JOIN     Genre g        ON t.GenreId   = g.GenreId
    GROUP BY anio, genero
  ),
  ranking_genero AS (
    SELECT anio, genero, ingresos,
           RANK() OVER (PARTITION BY anio ORDER BY ingresos DESC) AS posicion
    FROM   ventas_genero
  )
  SELECT   anio, genero, ROUND(ingresos, 2) AS ingresos
  FROM     ranking_genero
  WHERE    posicion = 1
  ORDER BY anio;
")
mostrar_tabla(genero_top, caption = "Género con más ingresos por año")

# 2.4 cuartiles de gasto por cliente
cuartiles <- dbGetQuery(con, "
  WITH gasto AS (
    SELECT   CustomerId, SUM(Total) AS gasto_total
    FROM     Invoice
    GROUP BY CustomerId
  ),
  con_cuartil AS (
    SELECT CustomerId, gasto_total,
           NTILE(4) OVER (ORDER BY gasto_total) AS cuartil
    FROM   gasto
  ),
  por_cuartil AS (
    SELECT   cuartil,
             COUNT(*)         AS n_clientes,
             SUM(gasto_total) AS ingreso
    FROM     con_cuartil
    GROUP BY cuartil
  )
  SELECT   CASE WHEN cuartil = 4 THEN 'Q4' ELSE 'Q1-Q3' END AS grupo,
           SUM(n_clientes)                                    AS n_clientes,
           ROUND(SUM(ingreso), 2)                             AS ingreso,
           ROUND(100.0 * SUM(ingreso) /
                 (SELECT SUM(ingreso) FROM por_cuartil), 2)   AS porcentaje
  FROM     por_cuartil
  GROUP BY grupo
  ORDER BY grupo DESC;
")
mostrar_tabla(cuartiles, caption = "Participación del cuartil superior")


# Ejercicio 3: clientes en riesgo de abandono ----------------------------

# 3.1 fecha de la última factura
fecha_max <- dbGetQuery(con, "SELECT MAX(InvoiceDate) AS fecha_maxima FROM Invoice;")
fecha_max

# 3.2 a 3.4
consulta_segmentos <- "
  WITH referencia AS (
    SELECT MAX(InvoiceDate) AS fecha_maxima FROM Invoice
  ),
  clientes AS (
    SELECT   c.CustomerId,
             c.FirstName || ' ' || c.LastName AS cliente,
             MAX(i.InvoiceDate)               AS ultima_compra,
             SUM(i.Total)                     AS gasto_historico
    FROM     Customer c
    JOIN     Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
  ),
  recencia AS (
    SELECT cl.*,
           (JULIANDAY(r.fecha_maxima) - JULIANDAY(cl.ultima_compra)) / 30 AS meses
    FROM   clientes cl
    CROSS JOIN referencia r
  ),
  segmentos AS (
    SELECT *,
           CASE WHEN meses <= 6  THEN 'activo'
                WHEN meses <= 12 THEN 'en riesgo'
                ELSE 'inactivo' END AS segmento
    FROM   recencia
  )
"

clientes_segmento <- dbGetQuery(con, paste(consulta_segmentos, "
  SELECT   cliente, DATE(ultima_compra) AS ultima_compra,
           ROUND(meses, 1) AS meses, segmento,
           ROUND(gasto_historico, 2) AS gasto_historico
  FROM     segmentos
  ORDER BY meses DESC;
"))
mostrar_tabla(clientes_segmento, n = 10, caption = "Recencia y segmento por cliente")

resumen_segmento <- dbGetQuery(con, paste(consulta_segmentos, "
  SELECT   segmento,
           COUNT(*)                       AS n_clientes,
           ROUND(AVG(gasto_historico), 2) AS gasto_promedio,
           ROUND(SUM(gasto_historico), 2) AS gasto_total
  FROM     segmentos
  GROUP BY segmento
  ORDER BY gasto_total DESC;
"))
mostrar_tabla(resumen_segmento, caption = "Resumen por segmento")

top_segmento <- dbGetQuery(con, paste(consulta_segmentos, ",
  ranking AS (
    SELECT segmento, cliente, gasto_historico, ROUND(meses, 1) AS meses,
           RANK() OVER (PARTITION BY segmento ORDER BY gasto_historico DESC) AS posicion
    FROM   segmentos
  )
  SELECT   segmento, posicion, cliente, ROUND(gasto_historico, 2) AS gasto_historico, meses
  FROM     ranking
  WHERE    posicion <= 3
  ORDER BY segmento, posicion;
"))
mostrar_tabla(top_segmento, caption = "Top 3 de gasto por segmento")

dbDisconnect(con)


# Respuestas --------------------------------------------------------------
#
# Ejercicio 1
# 1. Los 59 clientes quedan asignados a Jane Peacock, Margaret Park o Steve
#    Johnson; los tres reportan a Nancy Edwards. "Sin jefe" solo aplicaría a
#    Andrew Adams, que no atiende clientes.
# 2. 18 clientes gastan más que el promedio de los demás clientes de su
#    representante (6 de Jane Peacock, 6 de Margaret Park y 6 de Steve
#    Johnson). El que más se aleja es Helena Holý ($49,62 frente a $39,44).
# 3. Andrew Adams, Nancy Edwards, Michael Mitchell, Robert King y Laura
#    Callahan nunca han sido soporte; son cargos directivos o de TI.
# 4. Jane Peacock atiende más clientes (21) y genera más ingresos ($833,04),
#    seguida de Margaret Park (20; $775,40) y Steve Johnson (18; $720,16).
#    Sí coincide: el orden por clientes es el mismo que por ingresos, porque
#    el gasto por cliente es muy parecido entre representantes.
#
# Ejercicio 2
# 1. Las ventas mensuales son muy estables (casi siempre $37,62), por eso
#    la variación es 0 % en la mayoría de los meses; los cambios grandes
#    aparecen en meses puntuales, como diciembre de 2023 (+58,3 %) después
#    de la caída de noviembre de 2023 (-36,8 %).
# 2. Mes de mayor venta: 2022 enero, 2023 abril, 2024 agosto y 2025
#    noviembre. Mes de menor venta: 2021 enero, 2022 septiembre, 2023
#    noviembre y 2025 febrero. En 2021 (mes top) y 2024 (mes bajo) hay
#    empates entre varios meses con el mismo valor.
# 3. Rock es el género con más ingresos en todos los años (entre $155,43 y
#    $178,20).
# 4. El cuartil superior (14 clientes) concentra el 26,4 % del ingreso y los
#    otros tres cuartiles (45 clientes) el 73,6 %. El ingreso está poco
#    concentrado: el Q4 aporta apenas algo más que su peso en clientes.
#
# Ejercicio 3
# 1. La última factura es del 22 de diciembre de 2025.
# 2-3. 31 clientes son activos, 15 están en riesgo y 13 están inactivos.
# 4. Los activos suman el mayor gasto total ($1.226,22), pero el segmento
#    "en riesgo" tiene el gasto promedio más alto ($39,82) y $597,30 en
#    juego. Es el que debería priorizar la campaña, porque todavía es
#    recuperable, a diferencia de los inactivos. Sus clientes de mayor
#    gasto son Richard Cunningham ($47,62), Julia Barnett y Fynn
#    Zimmermann ($43,62 cada uno).
