# ==============================================================================
# TALLER PRÁCTICO CLASE 18: ANÁLISIS NO SUPERVISADO & CLUSTERING K-MEANS
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y LIBRERÍAS
# ------------------------------------------------------------------------------
# Carga de paquetes para manipulación de datos, clustering y métricas de silueta
suppressPackageStartupMessages({
  library(tidyverse)
  library(cluster)
  library(janitor)
  library(knitr)
})

cat("===================================================================\n")
cat("TALLER CLASE 18 - APRENDIZAJE NO SUPERVISADO Y CLUSTERING K-MEANS\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DEL DATASET Y SEPARACIÓN DE LA VARIABLE RESPUESTA (KDD FASE 1-2)
# ------------------------------------------------------------------------------
# Simulación del caso de estudio (Segmentación de Clientes / Perfomance)
# Regla fundamental: La variable objetivo (y) se APARTA antes de agrupar.
set.seed(2026)
n <- 400

df_raw <- tibble(
  id = 1:n,
  ingreso_k = round(rnorm(n, mean = 50, sd = 15), 1),       # Escala en miles
  gasto_score = round(runif(n, min = 1, max = 100), 1),    # Escala 1-100
  recencia_dias = round(rpois(n, lambda = 30), 0),          # Escala días
  frecuencia_compras = round(rpois(n, lambda = 12), 0),     # Escala número de compras
  target_categoria = factor(sample(c("Bajo RIESGO", "Alto RIESGO"), n, replace = TRUE, prob = c(0.7, 0.3)))
)

cat("--- DATASET ORIGINAL (Incluyendo la variable objetivo) ---\n")
print(head(df_raw, 5))

# Apartar la variable respuesta 'target_categoria'
y_apartada <- df_raw$target_categoria
X_cuanti <- df_raw %>% select(-id, -target_categoria)

cat("\n--- VARIABLES CUANTITATIVAS SELECCIONADAS PARA K-MEANS ---\n")
print(head(X_cuanti, 5))

# ------------------------------------------------------------------------------
# 3. NORMALIZACIÓN / ESTANDARIZACIÓN Z-SCORE (OBLIGATORIA EN DISTANCIAS)
# ------------------------------------------------------------------------------
# Justificación: Al medir distancias euclidianas, variables con mayor magnitud/varianza
# (ej. recencia_dias vs frecuencia) dominarían el cálculo si no se estandarizan.
X_scaled <- scale(X_cuanti)

cat("\n--- RESUMEN DE VARIABLES ESTANDARIZADAS (Media=0, SD=1) ---\n")
print(summary(X_scaled))

# ------------------------------------------------------------------------------
# 4. EVALUACIÓN DE HIPERPARÁMETRO K: INERCIA (WSS) Y COEFICIENTE DE SILUETA
# ------------------------------------------------------------------------------
# Bucle para evaluar K de 2 a 8 centroides
k_valores <- 2:8
resultados_k <- tibble(
  K = k_valores,
  inercia_wss = numeric(length(k_valores)),
  silueta_promedio = numeric(length(k_valores))
)

matriz_distancias <- dist(X_scaled)

for (i in seq_along(k_valores)) {
  k <- k_valores[i]
  set.seed(2026)
  km_temp <- kmeans(X_scaled, centers = k, nstart = 25)
  sil <- silhouette(km_temp$cluster, matriz_distancias)
  
  resultados_k$inercia_wss[i] <- km_temp$tot.withinss
  resultados_k$silueta_promedio[i] <- mean(sil[, 3])
}

cat("\n===================================================================\n")
cat("--- EVALUACIÓN DE K (INERCIA WSS Y ANÁLISIS DE SILUETA) ---\n")
print(kable(resultados_k, digits = 3))

# Selección del K óptimo (mayor coeficiente de silueta)
k_optimo <- resultados_k %>% filter(silueta_promedio == max(silueta_promedio)) %>% pull(K)
cat("\n--> K ÓPTIMO SELECCIONADO:", k_optimo, "(Basado en el máximo coeficiente de silueta)\n")

# ------------------------------------------------------------------------------
# 5. AJUSTE DE MODELO K-MEANS DEFINITIVO CON NSTART ALTO & PERFILAMIENTO
# ------------------------------------------------------------------------------
set.seed(2026)
km_final <- kmeans(X_scaled, centers = k_optimo, nstart = 50)

# Asignar clusters al dataset original
df_clustered <- df_raw %>% 
  mutate(cluster = factor(km_final$cluster, labels = paste0("Cluster_", 1:k_optimo)))

cat("\n===================================================================\n")
cat("--- CONVERGENCIA Y TAMAÑO DE LOS CLUSTERS ---\n")
print(table(df_clustered$cluster))

# Perfilamiento estadístico por grupo (Promedios en escala original)
perfil_grupos <- df_clustered %>% 
  group_by(cluster) %>% 
  summarise(
    n_casos = n(),
    ingreso_medio = round(mean(ingreso_k), 2),
    gasto_medio = round(mean(gasto_score), 2),
    recencia_media = round(mean(recencia_dias), 2),
    frecuencia_media = round(mean(frecuencia_compras), 2)
  )

cat("\n--- PERFILAMIENTO ESTADÍSTICO DE LOS CLUSTERS (MEDIAS EN ESCALA ORIGINAL) ---\n")
print(kable(perfil_grupos))

# ------------------------------------------------------------------------------
# 6. CRUCE CON LA VARIABLE OBJETIVO APARTADA (TABLA DE CONTINGENCIA)
# ------------------------------------------------------------------------------
# Evaluar si los grupos descubiertos sin supervisión corresponden a la etiqueta real
cat("\n===================================================================\n")
cat("--- CRUCE K-MEANS VS VARIABLE OBJETIVO APARTADA ---\n")
tabla_cruce <- table(Cluster = df_clustered$cluster, Objetivo = df_clustered$target_categoria)
print(tabla_cruce)

# Prueba Chi-cuadrado para evaluar asociación estocástica entre clusters y target
prueba_asoc <- chisq.test(tabla_cruce)
cat("\n--- ASOCIACIÓN CHI-CUADRADO DE PEARSON ---\n")
cat("p-valor:", format.pval(prueba_asoc$p.value), "\n")

# ------------------------------------------------------------------------------
# 7. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES DE TERMINAL)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- INSTRUCCIONES DE GIT PARA ENTREGA DE TALLER CLASE 18 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git checkout -b taller_18b\n")
cat("3. git status\n")
cat("4. git add taller_18_mineria_datos.R\n")
cat("5. git commit -m \"Entrega Taller Clase 18 (K-means y No Supervisado) - Inti A. Olaya\"\n")
cat("6. git push origin taller_18b\n")
cat("===================================================================\n")
