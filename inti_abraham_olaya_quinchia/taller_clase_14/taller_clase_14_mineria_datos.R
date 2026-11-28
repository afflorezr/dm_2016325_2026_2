# ==============================================================================
# TALLER PRÁCTICO CLASE 14: AGRUPAMIENTO NO SUPERVISADO (K-MEANS Y HCLUST)
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# 1. CONFIGURACIÓN DEL ENTORNO Y LIBRERÍAS
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(tidyverse)
  library(cluster)
  library(factoextra)
  library(janitor)
  library(knitr)
})

cat("===================================================================
")
cat("TALLER CLASE 14 - CLUSTERING NO SUPERVISADO: K-MEANS Y HCLUST
")
cat("Autor: Inti A. Olaya
")
cat("===================================================================

")

# 2. GENERACIÓN Y PREPARACIÓN DEL DATASET (FASE KDD)
# ------------------------------------------------------------------------------
# Simulación de perfilamiento de clientes / municipios (Acueducto, Alcantarillado, IRCA, Ingreso)
set.seed(140)
n <- 400

df_raw <- tibble(
  id = 1:n,
  cobertura_acueducto = pmin(100, pmax(10, rnorm(n, mean = 70, sd = 20))),
  cobertura_alcantarillado = pmin(100, pmax(5, rnorm(n, mean = 55, sd = 25))),
  irca_agua = pmin(100, pmax(0, rnorm(n, mean = 35, sd = 18))),
  poblacion_k = rlnorm(n, meanlog = 2.5, sdlog = 0.8),
  # Variable objetivo apartada (Nivel de Riesgo Real)
  target_riesgo = factor(sample(c("Bajo", "Medio", "Alto"), n, replace = TRUE, prob = c(0.4, 0.35, 0.25)))
)

cat("--- PRIMERAS FILAS DEL DATASET CRUDO ---
")
print(head(df_raw))

# Regla KDD: APARTAR la variable respuesta antes de agrupar
X_features <- df_raw %>%
  select(cobertura_acueducto, cobertura_alcantarillado, irca_agua, poblacion_k)

y_apartada <- df_raw$target_riesgo

# 3. ESCALAMIENTO Y ESTANDARIZACIÓN Z-SCORE
# ------------------------------------------------------------------------------
# Es obligatorio escalar variables para evitar que magnitudes dominen las distancias
X_scaled <- scale(X_features)

cat("
--- VERIFICACIÓN DE ESCALAMIENTO (Media = 0, Desv.Est = 1) ---
")
print(colMeans(X_scaled))
print(apply(X_scaled, 2, sd))

# 4. DETERMINACIÓN DEL NÚMERO ÓPTIMO DE CLUSTERS (K)
# ------------------------------------------------------------------------------
# a) Método del Codo (Inercia / WSS)
p_codo <- fviz_nbclust(X_scaled, kmeans, method = "wss") +
  labs(title = "Método del Codo (Inercia WSS)",
       subtitle = "Autor: Inti A. Olaya - Clase 14",
       x = "Número de Clusters (K)", y = "Suma de Cuadrados Intra-Cluster") +
  theme_minimal()

# b) Coeficiente de Silueta Promedio
p_silueta <- fviz_nbclust(X_scaled, kmeans, method = "silhouette") +
  labs(title = "Método de la Silueta Promedio",
       subtitle = "Autor: Inti A. Olaya - Clase 14",
       x = "Número de Clusters (K)", y = "Ancho de Silueta Promedio") +
  theme_minimal()

cat("
--- EVALUACIÓN DE SILUETA PARA K = 2 A 6 ---
")
for (k in 2:6) {
  km_tmp <- kmeans(X_scaled, centers = k, nstart = 25)
  sil_tmp <- silhouette(km_tmp$cluster, dist(X_scaled))
  cat(sprintf("K = %d | Inercia WSS: %.2f | Silueta Promedio: %.4f
",
              k, km_tmp$tot.withinss, mean(sil_tmp[, 3])))
}

# 5. AJUSTE DE K-MEANS CON K ÓPTIMO
# ------------------------------------------------------------------------------
K_optimo <- 3
km_final <- kmeans(X_scaled, centers = K_optimo, nstart = 50, iter.max = 100)

cat("
--- RESULTADOS K-MEANS (K = 3) ---
")
cat("Inercia Total Intra-Cluster (tot.withinss):", round(km_final$tot.withinss, 2), "
")
cat("Tamaño de los clusters:", km_final$size, "
")

# 6. CLUSTERING JERÁRQUICO AGLOMERATIVO (HCLUST)
# ------------------------------------------------------------------------------
mat_dist <- dist(X_scaled, method = "euclidean")
hc_ward <- hclust(mat_dist, method = "ward.D2")

# Correlación cofenética
cor_cofenetica <- cor(mat_dist, cophenetic(hc_ward))
cat("
Correlación Cofenética (HClust Ward):", round(cor_cofenetica, 4), "
")

# Asignación de grupos cortando el árbol
clusters_hc <- cutree(hc_ward, k = K_optimo)

# 7. PERFILAMIENTO Y CARACTERIZACIÓN DE CLUSTERS
# ------------------------------------------------------------------------------
df_analisis <- df_raw %>%
  mutate(
    cluster_kmeans = factor(km_final$cluster),
    cluster_hclust = factor(clusters_hc)
  )

perfil_kmeans <- df_analisis %>%
  group_by(cluster_kmeans) %>%
  summarise(
    n_municipios = n(),
    acueducto_prom = round(mean(cobertura_acueducto), 1),
    alcantarillado_prom = round(mean(cobertura_alcantarillado), 1),
    irca_prom = round(mean(irca_agua), 1),
    poblacion_prom = round(mean(poblacion_k), 1)
  ) %>%
  mutate(
    nombre_perfil = case_when(
      irca_prom > 40 ~ "Alto Riesgo / Baja Cobertura",
      acueducto_prom > 75 & irca_prom < 30 ~ "Cobertura Consolidada",
      TRUE ~ "Cobertura Intermedia"
    )
  )

cat("
--- TABLA DE PERFILEMAMIENTO K-MEANS ---
")
print(kable(perfil_kmeans))

# 8. CRUCE CON VARIABLE OBJETIVO APARTADA
# ------------------------------------------------------------------------------
cat("
--- TABLA DE CONTINGENCIA: CLUSTER K-MEANS VS RIESGO APARTADO ---
")
tab_contingencia <- table(Cluster = df_analisis$cluster_kmeans, Riesgo_Real = y_apartada)
print(tab_contingencia)

chi_test <- chisq.test(tab_contingencia)
cat("
Prueba Chi-Cuadrado de Asociación:
")
print(chi_test)

# 9. CONTROL DE VERSIONES Y ENTREGA GIT
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("COMANDOS GIT PARA LA ENTREGA DEL TALLER CLASE 14:
")
cat("1. git checkout -b taller_14
")
cat("2. git add taller_14_mineria_datos.R
")
cat("3. git commit -m "Entrega Taller Clase 14 (K-Means y HClust) - Inti A. Olaya"
")
cat("4. git push origin taller_14
")
cat("===================================================================
")
