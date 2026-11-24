library(tidyverse)
library(dbscan)
library(arules)
library(solitude)

# --- Simulación de los datos (no contamos con los datos reales) ---
set.seed(123)
n <- 300
municipios <- tibble(
  cobertura_acueducto = c(rnorm(n / 2, 85, 6),     rnorm(n / 2, 45, 8)),
  alcantarillado      = c(rnorm(n / 2, 78, 7),     rnorm(n / 2, 38, 9)),
  irca                = c(rnorm(n / 2, 14, 5),     rnorm(n / 2, 56, 8)),
  poblacion           = c(rlnorm(n / 2, 10.6, 0.6), rlnorm(n / 2, 9.0, 0.7)),
  altitud             = c(rnorm(n / 2, 1200, 400),  rnorm(n / 2, 600, 300))
)
datos_esc <- scale(municipios)
municipios$cluster_kmeans <- kmeans(datos_esc, centers = 3, nstart = 25)$cluster

# Transacciones simuladas de una cooperativa de compras agrícolas
items <- c("semilla", "fertilizante", "fungicida", "abono", "guantes", "manguera")
set.seed(456)
transacciones_lista <- lapply(1:200, function(i) {
  canasta <- sample(items, sample(1:3, 1))
  if ("semilla" %in% canasta) canasta <- union(canasta, "fertilizante")
  unique(canasta)
})
trans <- as(transacciones_lista, "transactions")

# A partir de aquí: datos_esc, municipios y trans son su punto de partida.

# =====================================================================
# TAREA 1. Dendrograma (Ward) vs. K-means
# =====================================================================
# Nota: datos_esc ya está estandarizado con scale(); se usa tal cual.
d  <- dist(datos_esc, method = "euclidean")
hc <- hclust(d, method = "ward.D2")

plot(hc, labels = FALSE, hang = -1,
     main = "Dendrograma (Ward.D2) - municipios",
     xlab = "", sub = "")
rect.hclust(hc, k = 3, border = 2:4)

municipios$cluster_ward <- cutree(hc, k = 3)

# Tabla de contingencia: filas = K-means, columnas = Ward
tab1 <- table(kmeans = municipios$cluster_kmeans,
              ward   = municipios$cluster_ward)
print(tab1)

# Índice de Rand ajustado (ARI) calculado a mano: 1 = coinciden, ~0 = azar
ari <- function(x, y) {
  tab <- table(x, y)
  choose2 <- function(v) v * (v - 1) / 2
  sum_ij <- sum(choose2(tab))
  sum_i  <- sum(choose2(rowSums(tab)))
  sum_j  <- sum(choose2(colSums(tab)))
  esperado <- sum_i * sum_j / choose2(sum(tab))
  (sum_ij - esperado) / (0.5 * (sum_i + sum_j) - esperado)
}
cat("\nARI (K-means vs Ward):",
    round(ari(municipios$cluster_kmeans, municipios$cluster_ward), 3), "\n")

# Perfil de los grupos (medias en escala original) para interpretar
municipios %>%
  group_by(cluster_ward) %>%
  summarise(across(cobertura_acueducto:altitud, mean), n = n())

# =====================================================================
# TAREA 2. DBSCAN con gráfico de k-distancias
# =====================================================================
# Regla práctica: minPts >= 2 * dimensiones = 10; el gráfico usa k = minPts
minPts <- 10
kNNdistplot(datos_esc, k = minPts)
# Elija eps en el "codo" de la curva y dibújelo con abline():
eps <- 1.2            # <-- AJUSTAR según el codo observado en el gráfico
abline(h = eps, lty = 2, col = "red")

db <- dbscan(datos_esc, eps = eps, minPts = minPts)
print(db)

municipios$cluster_dbscan <- db$cluster      # 0 = ruido
n_ruido <- sum(db$cluster == 0)
cat("\nMunicipios marcados como ruido:", n_ruido,
    sprintf("(%.1f%%)\n", 100 * n_ruido / nrow(municipios)))

# Sensibilidad: ruido según distintos valores de eps
sapply(c(0.8, 1.0, 1.2, 1.5, 2.0), function(e) {
  r <- dbscan(datos_esc, eps = e, minPts = minPts)
  c(eps = e, grupos = max(r$cluster), ruido = sum(r$cluster == 0))
}) %>% t() %>% print()

# =====================================================================
# TAREA 3. Reglas de asociación (Apriori)
# =====================================================================
reglas <- apriori(trans,
                  parameter = list(supp = 0.05, conf = 0.5,
                                   minlen = 2, target = "rules"))

cat("\nReglas encontradas:", length(reglas), "\n")

top5 <- head(sort(reglas, by = "lift", decreasing = TRUE), 5)
inspect(top5)

# (Opcional) versión sin reglas redundantes
reglas_nr <- reglas[!is.redundant(reglas)]
inspect(head(sort(reglas_nr, by = "lift", decreasing = TRUE), 5))

# =====================================================================
# TAREA 4. Isolation Forest vs. ruido de DBSCAN
# =====================================================================
set.seed(123)
iso <- isolationForest$new(num_trees = 500)
iso$fit(as.data.frame(datos_esc))

puntajes <- iso$predict(as.data.frame(datos_esc))
# predict() puede reordenar filas: se alinea por id
puntajes <- puntajes[order(puntajes$id), ]
municipios$anomaly_score <- puntajes$anomaly_score

# Los n_ruido municipios con mayor puntaje de anomalía
top_iso <- order(municipios$anomaly_score, decreasing = TRUE)[seq_len(n_ruido)]
ruido_db <- which(municipios$cluster_dbscan == 0)

cat("\nRuido DBSCAN:", length(ruido_db),
    "| Top-IF:", length(top_iso),
    "| Coinciden:", length(intersect(ruido_db, top_iso)), "\n")
cat("Jaccard:",
    round(length(intersect(ruido_db, top_iso)) /
            length(union(ruido_db, top_iso)), 3), "\n")

# Comparación de puntajes: ruido vs. no ruido
municipios %>%
  mutate(es_ruido = cluster_dbscan == 0) %>%
  group_by(es_ruido) %>%
  summarise(media_score = mean(anomaly_score),
            max_score   = max(anomaly_score),
            n = n())

boxplot(anomaly_score ~ I(cluster_dbscan == 0), data = municipios,
        names = c("No ruido", "Ruido DBSCAN"),
        ylab = "Puntaje de anomalía", col = c("grey85", "tomato"))

# Municipios más anómalos y si DBSCAN también los marcó
municipios %>%
  mutate(id = row_number(), ruido_dbscan = cluster_dbscan == 0) %>%
  arrange(desc(anomaly_score)) %>%
  select(id, anomaly_score, ruido_dbscan, poblacion, altitud, irca) %>%
  head(15)
