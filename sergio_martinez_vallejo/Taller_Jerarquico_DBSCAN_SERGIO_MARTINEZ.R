
# Base de datos
set.seed(1031610377)
t <- runif(120, 0, pi)
avenida  <- data.frame(x = 5 + 4 * cos(t) + rnorm(120, 0, 0.25),
                       y = 1 + 4 * sin(t) + rnorm(120, 0, 0.25))
cruce    <- data.frame(x = rnorm(60, 5, 0.35),
                       y = rnorm(60, 1.8, 0.35))
aislados <- data.frame(x = runif(15, 0, 10), y = runif(15, 0, 8))
acc <- rbind(avenida, cruce, aislados)

acc$zona <- rep(c("avenida", "cruce", "aislado"), c(120, 60, 15))



# Guardamos la verdad simulada aparte y creamos el dataset solo con coordenadas
zona_real <- acc$zona
datos <- acc[, c("x", "y")]

# Graficamos el mapa sin etiquetas
plot(datos, pch = 19, col = "darkgray", 
     main = "Mapa de accidentes (sin etiquetas)",
     xlab = "Coordenada X", ylab = "Coordenada Y", asp = 1)



#### 2.) Jerárquico con Ward y con enlace simple: dendrograma, K según el salto más grande y mapa coloreado. ¿Cuál respeta el arco?
# Matriz de distancias euclidianas
d <- dist(datos)

# Modelos jerárquicos
hc_ward   <- hclust(d, method = "ward.D2")
hc_simple <- hclust(d, method = "single")

# 2.1 Dendrogramas
par(mfrow = c(1, 2))
plot(hc_ward, labels = FALSE, main = "Dendrograma - Ward", xlab = "", sub = "")
plot(hc_simple, labels = FALSE, main = "Dendrograma - Enlace Simple", xlab = "", sub = "")

# 2.2 Cálculo del salto más grande en las alturas de fusión (para elegir K)

tail(diff(hc_ward$height), 10)
tail(diff(hc_simple$height), 10)

# Usemos K = 3 para comparar cómo separan las estructuras 
k_ward   <- cutree(hc_ward, k = 3)
k_simple <- cutree(hc_simple, k = 3)

# 2.3 Mapas coloreados
plot(datos, col = k_ward, pch = 19, main = "Jerárquico: Ward (K=3)", asp = 1)
plot(datos, col = k_simple, pch = 19, main = "Jerárquico: Enlace Simple (K=3)", asp = 1)
par(mfrow = c(1, 1))


#### 3.) DBSCAN con minPts =5 : elija ε con el gráfico de k -distancias. ¿Cuántos grupos y cuántos puntos de ruido obtiene?
# Gráfico de k-distancias (con k = minPts = 5)
kNNdistplot(datos, k = 5)
abline(h = 0.65, col = "red", lty = 2) 

# Ajustamos DBSCAN con el epsilon
eps_optimo <- 0.65
db_optimo <- dbscan(datos, eps = eps_optimo, minPts = 5)

# Resultados
print(db_optimo)
plot(datos, col = db_optimo$cluster + 1, pch = 19, 
     main = paste("DBSCAN (eps =", eps_optimo, ", minPts = 5)"), asp = 1)
legend("topright", legend = c("Ruido (0)", "Grupo 1", "Grupo 2"), 
       col = 1:3, pch = 19)



#### 4.) Repita DBSCAN con ε a la mitad y al doble. ¿Qué les pasa a los grupos y al ruido?

db_mitad <- dbscan(datos, eps = eps_optimo / 2, minPts = 5) # eps = 0.325
db_doble <- dbscan(datos, eps = eps_optimo * 2, minPts = 5) # eps = 1.30

par(mfrow = c(1, 2))
plot(datos, col = db_mitad$cluster + 1, pch = 19, 
     main = paste("DBSCAN Mitad (eps =", eps_optimo/2, ")"), asp = 1)
plot(datos, col = db_doble$cluster + 1, pch = 19, 
     main = paste("DBSCAN Doble (eps =", eps_optimo*2, ")"), asp = 1)
par(mfrow = c(1, 1))

print(db_mitad)
print(db_doble)


### 5.) Ahora sí, cruce cada resultado con zona. ¿Qué método le recomendaría a la Secretaría?

cat("--- Tabla Jerárquico Ward (K=3) ---\n")
table(Real = zona_real, Ward = k_ward)

cat("\n--- Tabla Jerárquico Enlace Simple (K=3) ---\n")
table(Real = zona_real, Simple = k_simple)

cat("\n--- Tabla DBSCAN Óptimo (eps = 0.65) ---\n")
table(Real = zona_real, DBSCAN = db_optimo$cluster)

