library(DBI)
library(RSQLite)

# Abre una conexión
con <- dbConnect(RSQLite::SQLite(), "C:/Users/thetr/Desktop/Minería/dm_2016325_2026_2/daniel_mauricio_vanegas_oliveros/parcial_1/raw/consultas.db")

# Verifica la tabla
dbListTables(con)
dbListFields(con, "productos")

# Selección de productos



# 1: Manís La Especial Arándanos 450g

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%especial%'
  AND    titulo LIKE '%arándanos%'
  AND    titulo LIKE '%450%'
  ORDER  BY pagina, precio;
")


# 2: CEREAL ZUCARITAS 610G

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%zucaritas%'
  AND    titulo LIKE '%610%'
  ORDER  BY pagina, precio;
")

# 3: CEREAL CHOCO KRISPIS 570G

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%choco%'
  AND    titulo LIKE '%krispis%'
  AND    titulo LIKE '%570%'
  ORDER  BY pagina, precio;
")

# 4: hojuelas conr flakes kellogs 410g

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%kelloggs%'
  AND    titulo LIKE '%410%'
  ORDER  BY pagina, precio;
")

# 5: Frot loops 450g

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%froot%'
  AND    titulo LIKE '%450%'
  ORDER  BY pagina, precio;
")

# 6: flips 400g chocolate

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%flips%'
  AND    titulo LIKE '%400%'
  and    titulo LIKE '%choco%'
  ORDER  BY pagina, precio;
")

# 7: oreo 432 

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%oreo%'
  AND    titulo LIKE '%432%'
  AND    precio < 16000
  ORDER  BY pagina, precio;
")

# 8: gansito 6 unidades (no zombie)

dbGetQuery(con, "
  SELECT titulo, precio, pagina
  FROM   productos
  WHERE  titulo LIKE '%gansito%'
  AND    titulo LIKE '%6und%'   
  AND    titulo NOT LIKE '%zombie%'
  ORDER  BY pagina, precio;
")

