# Taller 19 - jerarquico y DBSCAN (accidentes)

library(dbscan)

set.seed(2026)
t <- runif(120, 0, pi)
avenida  <- data.frame(x = 5 + 4 * cos(t) + rnorm(120, 0, 0.25),
                       y = 1 + 4 * sin(t) + rnorm(120, 0, 0.25))
cruce    <- data.frame(x = rnorm(60, 5, 0.35),
                       y = rnorm(60, 1.8, 0.35))
aislados <- data.frame(x = runif(15, 0, 10), y = runif(15, 0, 8))
acc <- rbind(avenida, cruce, aislados)
acc$zona <- rep(c("avenida", "cruce", "aislado"), c(120, 60, 15))

zona <- acc$zona
X <- acc[, c("x", "y")]   # x,y ya estan en la misma escala, no escalo

# 1. mapa sin la zona
plot(X, pch = 19, cex = .7, main = "accidentes")
# se ve un arco grande y una nube compacta en el centro abajo, mas unos puntos sueltos

# 2. jerarquico
d <- dist(X)
k_salto <- function(hc) {
  h <- rev(hc$height)
  which.max(-diff(h)) + 1
}

hw <- hclust(d, method = "ward.D2")
hs <- hclust(d, method = "single")
k_salto(hw); k_salto(hs)

par(mfrow = c(1, 2))
plot(hw, labels = FALSE, main = "ward"); plot(hs, labels = FALSE, main = "simple")

gw <- cutree(hw, k_salto(hw))
gs <- cutree(hs, 3)   # con el salto mayor solo separa un punto suelto, pruebo 3
plot(X, col = gw, pch = 19, cex = .7, main = "ward")
plot(X, col = gs, pch = 19, cex = .7, main = "simple, K=3")
# ward mezcla el cruce con parte del arco, lo corta en pedazos redondos
# simple con K=3 si respeta el arco, aunque se le pegan los aislados

# 3. DBSCAN
par(mfrow = c(1, 1))
kNNdistplot(X, k = 4)
abline(h = 0.8, lty = 2)   # el codo queda mas o menos entre 0.7 y 1
db <- dbscan(X, eps = 0.8, minPts = 5)
db
plot(X, col = db$cluster + 1, pch = ifelse(db$cluster == 0, 4, 19), cex = .7,
     main = "dbscan eps=0.8")   # x = ruido

# 4. eps a la mitad y al doble
db_m <- dbscan(X, eps = 0.4, minPts = 5)
db_d <- dbscan(X, eps = 1.6, minPts = 5)
db_m; db_d
par(mfrow = c(1, 2))
plot(X, col = db_m$cluster + 1, pch = ifelse(db_m$cluster == 0, 4, 19), cex = .7, main = "eps=0.4")
plot(X, col = db_d$cluster + 1, pch = ifelse(db_d$cluster == 0, 4, 19), cex = .7, main = "eps=1.6")
# con 0.4 el arco se parte en muchos grupos y sube mucho el ruido
# con 1.6 quedan los 2 grupos pero casi no hay ruido, los aislados se pegan a las zonas

# 5. cruce con zona
table(ward = gw, zona)
table(simple = gs, zona)
table(dbscan = db$cluster, zona)
# dbscan con eps=0.8 recupera avenida y cruce casi perfectos y deja como ruido
# los accidentes sueltos (algunos aislados caen sobre el arco, normal que no salgan)
# para la Secretaria: usar dbscan. identifica el corredor de la avenida y el cruce
# como dos puntos criticos distintos, y aparte los accidentes sueltos, que no son
# zona critica pero igual toca revisarlos caso a caso.
# ward/kmeans no sirven aca porque fuerzan grupos redondos y parten la avenida.
