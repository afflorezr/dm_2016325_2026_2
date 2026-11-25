# Taller 18b - K-means

library(cluster)
library(dplyr)

heart <- read.csv("heart.csv")
vars <- c("age", "trestbps", "chol", "thalach", "oldpeak")

y <- heart$target          # se aparta, no entra al kmeans
X <- heart[, vars]

# 1. escalado
sapply(X, range)
# chol va hasta ~560 y oldpeak no pasa de ~6, sin escalar chol y trestbps
# dominarian la distancia y oldpeak casi no pesaria
Xs <- scale(X)

# 2. inercia y silueta
set.seed(123)
d <- dist(Xs)
res <- data.frame(k = 2:8, inercia = NA, silueta = NA)
for (i in 1:nrow(res)) {
  km <- kmeans(Xs, centers = res$k[i], nstart = 25)
  res$inercia[i] <- km$tot.withinss
  res$silueta[i] <- mean(silhouette(km$cluster, d)[, 3])
}
res

par(mfrow = c(1, 2))
plot(res$k, res$inercia, type = "b", xlab = "K", ylab = "inercia")
plot(res$k, res$silueta, type = "b", xlab = "K", ylab = "silueta")
# el codo no es muy claro pero la silueta es mayor en K = 2, me quedo con 2

# 3. modelo final y perfiles
km2 <- kmeans(Xs, centers = 2, nstart = 50)
heart$grupo <- km2$cluster

heart %>%
  group_by(grupo) %>%
  summarise(n = n(), across(all_of(vars), mean))
# un grupo sale mayor, con thalach mas bajo y oldpeak mas alto -> "mayores / menor capacidad cardiaca"
# el otro mas joven, thalach alto y oldpeak bajo -> "jovenes / buena respuesta al esfuerzo"
# (revisar cual numero quedo con cual, cambia segun la corrida)

# 4. cruce con target
tab <- table(grupo = heart$grupo, target = y)
tab
prop.table(tab, 1)
# los grupos se parecen bastante a target (~70% en cada uno) pero no es lo mismo:
# kmeans separa sobre todo por edad y respuesta al ejercicio, no por enfermedad.
# chol y trestbps casi no diferencian los grupos. agrupar no es clasificar.
