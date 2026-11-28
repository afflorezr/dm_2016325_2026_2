# ==============================================================================
# TALLER PRÁCTICO CLASE 15: APRENDIZAJE NO SUPERVISADO Y CLUSTERING AVANZADO
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# INSTITUCIÓN: UNIVERSIDAD NACIONAL DE COLOMBIA
# ==============================================================================

library(tidyverse)
library(cluster)
library(factoextra)
library(dbscan)
library(knitr)
library(janitor)

cat("===================================================================\n")
cat("TALLER CLASE 15 - CLUSTERING NO SUPERVISADO (K-MEANS, HCLUST, DBSCAN)\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# 1. GENERACIÓN Y PREPROCESAMIENTO DE DATOS MULTIVARIADOS
set.seed(2026)
n_obs <- 300

c1 <- data.frame(ingreso = rnorm(100, mean = 2500, sd = 400), gasto = rnorm(100, mean = 800, sd = 150), recencia = rnorm(100, 15, 3))
c2 <- data.frame(ingreso = rnorm(100, mean = 6500, sd = 800), gasto = rnorm(100, mean = 2800, sd = 300), recencia = rnorm(100, 45, 8))
c3 <- data.frame(ingreso = rnorm(100, mean = 4000, sd = 600), gasto = rnorm(100, mean = 1200, sd = 200), recencia = rnorm(100, 80, 12))

datos_raw <- rbind(c1, c2, c3)
datos_escalados <- scale(datos_raw)

cat("--- PRIMERAS FILAS DE LOS DATOS ESCALADOS ---\n")
print(head(datos_escalados, 5))

# 2. DETERMINACIÓN DEL NÚMERO ÓPTIMO DE CLUSTERS (K)
p_elbow <- fviz_nbclust(datos_escalados, kmeans, method = "wss") +
  labs(title = "Método del Codo (WSS) - Inti A. Olaya", x = "Número de Clusters (k)", y = "Suma Total de Cuadrados Intra-Cluster") +
  theme_minimal()

p_silhouette <- fviz_nbclust(datos_escalados, kmeans, method = "silhouette") +
  labs(title = "Método de la Silueta - Inti A. Olaya", x = "Número de Clusters (k)", y = "Coeficiente de Silueta Promedio") +
  theme_minimal()

# 3. CLUSTERING PARTICIONAL: K-MEANS
set.seed(2026)
k_optimo <- 3
modelo_kmeans <- kmeans(datos_escalados, centers = k_optimo, nstart = 25)

cat("\n--- RESULTADOS K-MEANS (K = 3) ---\n")
print(modelo_kmeans$size)

p_km_viz <- fviz_cluster(modelo_kmeans, data = datos_escalados,
                         ellipse.type = "convex",
                         palette = "jco",
                         ggtheme = theme_minimal(),
                         main = "Clustering K-Means (PCA 2D) - Inti A. Olaya")

# 4. CLUSTERING JERÁRQUICO AGLOMERATIVO (HCLUST & DENDROGRAMA)
matriz_distancia <- dist(datos_escalados, method = "euclidean")
hc_ward <- hclust(matriz_distancia, method = "ward.D2")

cor_cofenetica <- cor(matriz_distancia, cophenetic(hc_ward))
cat(sprintf("\nCorrelación Cofenética del Dendrograma: %.4f\n", cor_cofenetica))

p_dendro <- fviz_dend(hc_ward, k = k_optimo,
                      cex = 0.5,
                      k_colors = c("#2E9FDF", "#E7B800", "#FC4E07"),
                      color_labels_by_k = TRUE,
                      rect = TRUE,
                      main = "Dendrograma Jerárquico (Ward.D2) - Inti A. Olaya")

grupos_hclust <- cutree(hc_ward, k = k_optimo)

# 5. CLUSTERING BASADO EN DENSIDAD: DBSCAN
modelo_dbscan <- dbscan(datos_escalados, eps = 0.6, minPts = 5)

p_dbscan <- fviz_cluster(modelo_dbscan, data = datos_escalados, stand = FALSE,
                         ellipse = FALSE, show.clust.cent = FALSE,
                         ggtheme = theme_minimal(),
                         main = "Clustering DBSCAN - Inti A. Olaya")

# 6. COMPARACIÓN DE EVALUACIÓN NO SUPERVISADA
sil_km <- silhouette(modelo_kmeans$cluster, matriz_distancia)
sil_hc <- silhouette(grupos_hclust, matriz_distancia)

resumen_silueta <- data.frame(
  Algoritmo = c("K-Means", "HClust (Ward.D2)"),
  Silueta_Promedio = c(mean(sil_km[, 3]), mean(sil_hc[, 3]))
)

cat("\n===================================================================\n")
cat("--- COMPARACIÓN DE COEFICIENTES DE SILUETA PROMEDIO ---\n")
print(kable(resumen_silueta, digits = 4, caption = "Evaluación de Calidad de Clustering - Inti A. Olaya"))
cat("===================================================================\n\n")

# 7. CONTROL DE VERSIONES CON GIT
cat("--- CONTROL DE VERSIONES DE GIT ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_15_mineria_datos.R\n")
cat("4. git commit -m 'Entrega Taller Clase 15 - Inti A. Olaya'\n")
cat("5. git push origin main\n")
