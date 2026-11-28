# ==============================================================================
# TALLER PRÁCTICO CLASE 17: MINERÍA DE REGLAS DE ASOCIACIÓN Y ALGORITMO APRIORI
# CURSO: MINERÍA DE DATOS
# AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y PAQUETES NECESARIOS
# ------------------------------------------------------------------------------
paquetes_requeridos <- c("tidyverse", "arules", "arulesViz", "knitr")
paquetes_faltantes <- paquetes_requeridos[!(paquetes_requeridos %in% installed.packages()[, "Package"])]
if (length(paquetes_faltantes) > 0) {
  install.packages(paquetes_faltantes, dependencies = TRUE)
}

library(tidyverse)
library(arules)
library(arulesViz)
library(knitr)

cat("===================================================================
")
cat("TALLER CLASE 17 - MINERÍA DE REGLAS DE ASOCIACIÓN (MARKET BASKET ANALYSIS)
")
cat("Autor / Estudiante: Inti A. Olaya
")
cat("===================================================================

")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN Y STRUCTURACIÓN DE DATOS DE TRANSACCIONES (SUPERMERCADO)
# ------------------------------------------------------------------------------
set.seed(2026)
n_transacciones <- 1200

productos <- c("Pan", "Leche", "Mantequilla", "Café", "Azúcar", 
               "Queso", "Huevos", "Jamón", "Cerveza", "Snacks", 
               "Pañales", "Gaseosa", "Frutas", "Yogurt")

# Generar transacciones sintéticas con patrones de compra reales
lista_transacciones <- vector("list", n_transacciones)
for (i in 1:n_transacciones) {
  # Patrones probabilísticos asociados
  r <- runif(1)
  if (r < 0.35) {
    # Patrón Desayuno: Pan + Leche + Mantequilla/Café
    items <- sample(c("Pan", "Leche", "Mantequilla", "Café", "Azúcar", "Queso"), 
                    size = sample(2:4, 1), prob = c(0.8, 0.7, 0.6, 0.5, 0.4, 0.4))
  } else if (r < 0.65) {
    # Patrón Fin de Semana: Cerveza + Snacks + Pañales/Gaseosa
    items <- sample(c("Cerveza", "Snacks", "Pañales", "Gaseosa", "Queso"), 
                    size = sample(2:4, 1), prob = c(0.75, 0.7, 0.65, 0.5, 0.3))
  } else {
    # Compras Generales variadas
    items <- sample(productos, size = sample(1:5, 1))
  }
  lista_transacciones[[i]] <- unique(items)
}

# Convertir la lista a objeto tipo 'transactions' del paquete arules
transacciones <- as(lista_transacciones, "transactions")

cat("--- RESUMEN DEL DATASET DE TRANSACCIONES ---
")
summary(transacciones)

cat("
--- PRIMERAS 5 TRANSACCIONES REGISTRADAS ---
")
inspect(transacciones[1:5])

# Visualizar la frecuencia relativa de los 10 ítems más vendidos
itemFrequencyPlot(transacciones, topN = 10, type = "relative", 
                  main = "Frecuencia Relativa de Ítems (Inti A. Olaya)",
                  col = "steelblue")

# ------------------------------------------------------------------------------
# 3. EJECUCIÓN DEL ALGORITMO APRIORI
# ------------------------------------------------------------------------------
# Definición de umbrales: Soporte mínimo = 3%, Confianza mínima = 50%
reglas <- apriori(transacciones,
                  parameter = list(supp = 0.03, conf = 0.50, minlen = 2, maxlen = 5))

cat("
===================================================================
")
cat("--- RESULTADOS DEL ALGORITMO APRIORI ---
")
cat("Total de reglas descubiertas:", length(reglas), "

")

# Inspeccionar las 10 reglas principales ordenadas por Lift
reglas_ordenadas_lift <- sort(reglas, by = "lift", decreasing = TRUE)
cat("--- TOP 10 REGLAS CON MAYOR LIFT ---
")
inspect(head(reglas_ordenadas_lift, 10))

# ------------------------------------------------------------------------------
# 4. PODA DE REGLAS REDUNDANTES Y FILTRADO ESPECÍFICO
# ------------------------------------------------------------------------------
# Identificar y remover reglas que no aportan información adicional (redundantes)
es_redundante <- is.redundant(reglas_ordenadas_lift)
reglas_limpias <- reglas_ordenadas_lift[!es_redundante]

cat("
--- REGLAS LUEGO DE ELIMINAR REDUNDANCIAS ---
")
cat("Reglas no redundantes restantes:", length(reglas_limpias), "
")

# Filtrar reglas dirigidas a un consecuente específico (ej. Consecuente = Cerveza o Café)
reglas_cerveza <- subset(reglas_limpias, rhs %in% "Cerveza")
cat("
--- REGLAS QUE LLEVAN A LA COMPRA DE 'Cerveza' ---
")
inspect(head(reglas_cerveza, 5))

reglas_cafe <- subset(reglas_limpias, rhs %in% "Café")
cat("
--- REGLAS QUE LLEVAN A LA COMPRA DE 'Café' ---
")
inspect(head(reglas_cafe, 5))

# ------------------------------------------------------------------------------
# 5. VISUALIZACIÓN DE REGLAS DE ASOCIACIÓN (arulesViz)
# ------------------------------------------------------------------------------
# Scatter plot de Soporte vs Confianza coloreado por Lift
plot(reglas_limpias, method = "scatterplot", 
     main = "Distribución de Reglas: Soporte vs Confianza (Inti A. Olaya)")

# Gráfico de red de las 15 principales reglas por Lift
plot(head(reglas_limpias, 15), method = "graph", 
     control = list(verbose = FALSE),
     main = "Red de Asociación de Ítems (Top 15 Reglas - Inti A. Olaya)")

# Matriz agrupada de reglas
plot(head(reglas_limpias, 10), method = "grouped",
     main = "Matriz Agrupada de Reglas de Asociación")

# ------------------------------------------------------------------------------
# 6. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- COMANDOS DE TERMINAL GIT PARA LA ENTREGA DEL TALLER 17 ---
")
cat("1. git checkout -b taller_17
")
cat("2. git status
")
cat("3. git add taller_17_mineria_datos.R
")
cat("4. git commit -m "Entrega Taller Clase 17 (Reglas de Asociación & Apriori) - Inti A. Olaya"
")
cat("5. git push origin taller_17
")
cat("===================================================================
")
