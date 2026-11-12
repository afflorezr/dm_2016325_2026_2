# =============================================================================
# Minería de Datos — Clase 15: Random Forest y métodos ensemble
# Práctica: mora en una cooperativa de Robledo (Medellín)
# Autor: David Márquez
# =============================================================================
# Paquetes: randomForest, rpart, pROC
#install.packages(c("randomForest", "rpart", "pROC"))

library(randomForest)
library(rpart)
library(pROC)

# -----------------------------------------------------------------------------
# 0. Datos reproducibles (código del slide)
# -----------------------------------------------------------------------------
dir.create("data", showWarnings = FALSE)

set.seed(2026)
n <- 1000
historial <- sample(c("bueno", "regular", "malo"), n,
                    replace = TRUE, prob = c(.55, .30, .15))
empleo  <- sample(c("formal", "informal"), n,
                  replace = TRUE, prob = c(.60, .40))
estrato <- sample(1:6, n, replace = TRUE,
                  prob = c(.18, .32, .28, .13, .06, .03))
ingreso <- round(exp(rnorm(n, log(1.2 + 0.5 * estrato), 0.35)), 2)
monto   <- round(runif(n, 1, 25), 1)
edad    <- sample(20:70, n, replace = TRUE)
antiguedad <- pmin(edad - 18, rpois(n, 6))
cod_asesor <- sample(1:60, n, replace = TRUE)

carga <- monto / (12 * ingreso)  # crédito vs. ingreso anual
z <- -3.0 + 2.2 * (historial == "malo") +
     1.0 * (historial == "regular") +
     1.0 * (empleo == "informal") + 3.0 * (carga > 0.5) +
     0.8 * (edad < 26) - 0.10 * antiguedad
mora <- ifelse(runif(n) < plogis(z), "Si", "No")
cooperativa <- data.frame(ingreso, monto, edad, antiguedad,
                          estrato, empleo, historial,
                          cod_asesor, mora)
write.csv(cooperativa, "data/cooperativa.csv", row.names = FALSE)

# Lectura y tipos: randomForest necesita factores para clasificación
datos <- read.csv("data/cooperativa.csv")
datos$empleo    <- factor(datos$empleo)
datos$historial <- factor(datos$historial, levels = c("bueno", "regular", "malo"))
datos$mora      <- factor(datos$mora, levels = c("No", "Si"))
str(datos)

# Funciones auxiliares
exactitud <- function(pred, real) mean(pred == real)
auc_val   <- function(prob, real) as.numeric(auc(roc(real, prob,
                                  levels = c("No", "Si"), direction = "<",
                                  quiet = TRUE)))

# =============================================================================
# AJUSTE Y COMPARACIÓN
# =============================================================================

# -----------------------------------------------------------------------------
# a. Tasa de mora y exactitud del clasificador trivial ("siempre No")
# -----------------------------------------------------------------------------
table(datos$mora)
tasa_mora <- mean(datos$mora == "Si")
cat(sprintf("Tasa de mora: %.1f%%\n", 100 * tasa_mora))
cat(sprintf("Exactitud de predecir siempre 'No' (total): %.1f%%\n",
            100 * (1 - tasa_mora)))

# -----------------------------------------------------------------------------
# b. Partición 70/30 y comparación: árbol sin restricciones, árbol podado, RF
# -----------------------------------------------------------------------------
set.seed(2026)
idx   <- sample(n, 0.7 * n)
train <- datos[idx, ]
test  <- datos[-idx, ]

cat(sprintf("Prueba: %d casos, %d en mora; 'siempre No' = %.1f%%\n",
            nrow(test), sum(test$mora == "Si"),
            100 * mean(test$mora == "No")))

# b.1 Árbol sin restricciones (crece hasta memorizar)
set.seed(2026)
arbol_full <- rpart(mora ~ ., data = train, method = "class",
                    control = rpart.control(cp = 0, minsplit = 2,
                                            minbucket = 1, xval = 10))
hojas_full <- sum(arbol_full$frame$var == "<leaf>")

# b.2 Árbol podado con el cp de mínimo xerror (validación cruzada interna)
cp_tab  <- arbol_full$cptable
cp_opt  <- cp_tab[which.min(cp_tab[, "xerror"]), "CP"]
arbol_pod  <- prune(arbol_full, cp = cp_opt)
hojas_pod  <- sum(arbol_pod$frame$var == "<leaf>")
print(arbol_pod)   # revisar si usa cod_asesor en alguna partición

# b.3 Random Forest de 500 árboles (mtry por defecto = floor(sqrt(8)) = 2)
set.seed(2026)
rf <- randomForest(mora ~ ., data = train, ntree = 500, importance = TRUE)
print(rf)

# Evaluación en prueba
eval_modelo <- function(nombre, pred_tr, pred_te, prob_te, hojas = NA) {
  data.frame(modelo = nombre, hojas = hojas,
             exact_train = round(100 * exactitud(pred_tr, train$mora), 1),
             exact_test  = round(100 * exactitud(pred_te, test$mora), 1),
             AUC_test    = round(auc_val(prob_te, test$mora), 3))
}

comparacion <- rbind(
  eval_modelo("Árbol sin restricciones",
              predict(arbol_full, train, type = "class"),
              predict(arbol_full, test,  type = "class"),
              predict(arbol_full, test,  type = "prob")[, "Si"], hojas_full),
  eval_modelo("Árbol podado",
              predict(arbol_pod, train, type = "class"),
              predict(arbol_pod, test,  type = "class"),
              predict(arbol_pod, test,  type = "prob")[, "Si"], hojas_pod),
  eval_modelo("Random Forest (500)",
              predict(rf, train),          # ojo: en entrenamiento RF ~100%
              predict(rf, test),
              predict(rf, test, type = "prob")[, "Si"])
)
print(comparacion, row.names = FALSE)
cat(sprintf("Error OOB del bosque: %.1f%%\n", 100 * rf$err.rate[500, "OOB"]))

# Curvas ROC en prueba
roc_full <- roc(test$mora, predict(arbol_full, test, type = "prob")[, "Si"],
                levels = c("No", "Si"), direction = "<", quiet = TRUE)
roc_pod  <- roc(test$mora, predict(arbol_pod, test, type = "prob")[, "Si"],
                levels = c("No", "Si"), direction = "<", quiet = TRUE)
roc_rf   <- roc(test$mora, predict(rf, test, type = "prob")[, "Si"],
                levels = c("No", "Si"), direction = "<", quiet = TRUE)
plot(roc_rf, col = "darkgreen", lwd = 2, main = "Curvas ROC en prueba")
plot(roc_pod,  col = "steelblue", lwd = 2, add = TRUE)
plot(roc_full, col = "firebrick", lwd = 2, add = TRUE)
legend("bottomright", lwd = 2, col = c("darkgreen", "steelblue", "firebrick"),
       legend = sprintf("%s (AUC = %.2f)",
                        c("Random Forest", "Árbol podado", "Árbol sin restricciones"),
                        c(auc(roc_rf), auc(roc_pod), auc(roc_full))))

# -----------------------------------------------------------------------------
# c. Error OOB vs. número de árboles
# -----------------------------------------------------------------------------
oob <- rf$err.rate[, "OOB"]
plot(1:500, 100 * oob, type = "l", lwd = 2, col = "darkgreen",
     xlab = "Número de árboles", ylab = "Error OOB (%)",
     main = "Error OOB vs. número de árboles")
abline(v = 100, lty = 2, col = "grey40")
round(100 * oob[c(10, 25, 50, 100, 200, 300, 500)], 1)
cat(sprintf("Rango del OOB entre 100 y 500 árboles: %.1f%% – %.1f%%\n",
            100 * min(oob[100:500]), 100 * max(oob[100:500])))

# -----------------------------------------------------------------------------
# d. mtry de 1 a 8 (mtry = 8 es Bagging)
# -----------------------------------------------------------------------------
res_mtry <- t(sapply(1:8, function(m) {
  set.seed(2026)
  f <- randomForest(mora ~ ., data = train, ntree = 500, mtry = m)
  c(mtry = m,
    OOB  = round(100 * unname(f$err.rate[500, "OOB"]), 1),
    exact_test = round(100 * exactitud(predict(f, test), test$mora), 1),
    AUC_test   = round(auc_val(predict(f, test, type = "prob")[, "Si"],
                               test$mora), 3))
}))
print(res_mtry)
plot(res_mtry[, "mtry"], res_mtry[, "OOB"], type = "b", pch = 19,
     xlab = "mtry", ylab = "Error OOB (%)", main = "Error OOB según mtry")

# =============================================================================
# INTERPRETACIÓN
# =============================================================================

# -----------------------------------------------------------------------------
# e. Importancia Gini vs. permutación; ¿dónde queda cod_asesor?
# -----------------------------------------------------------------------------
imp <- importance(rf)
imp_gini <- sort(imp[, "MeanDecreaseGini"], decreasing = TRUE)
imp_perm <- sort(imp[, "MeanDecreaseAccuracy"], decreasing = TRUE)
round(imp_gini, 1)
round(imp_perm, 1)
cat("Puesto de cod_asesor — Gini:", which(names(imp_gini) == "cod_asesor"),
    "| Permutación:", which(names(imp_perm) == "cod_asesor"), "\n")
varImpPlot(rf, main = "Importancia de variables (Random Forest)")

# Comprobación: bosque sin cod_asesor
set.seed(2026)
rf_sin <- randomForest(mora ~ . - cod_asesor, data = train, ntree = 500)
cat(sprintf("OOB sin cod_asesor: %.1f%% (con cod_asesor: %.1f%%)\n",
            100 * rf_sin$err.rate[500, "OOB"], 100 * rf$err.rate[500, "OOB"]))

# -----------------------------------------------------------------------------
# f. ¿Recupera el bosque las variables de la regla?
# -----------------------------------------------------------------------------
# Regla real: historial, empleo, carga = monto/(12*ingreso), edad < 26, antiguedad.
# Dependencia parcial de las variables clave
par(mfrow = c(2, 2))
partialPlot(rf, train, x.var = "ingreso", which.class = "Si",
            main = "Dependencia parcial: ingreso")
partialPlot(rf, train, x.var = "monto", which.class = "Si",
            main = "Dependencia parcial: monto")
partialPlot(rf, train, x.var = "historial", which.class = "Si",
            main = "Dependencia parcial: historial")
partialPlot(rf, train, x.var = "empleo", which.class = "Si",
            main = "Dependencia parcial: empleo")
par(mfrow = c(1, 1))

# -----------------------------------------------------------------------------
# g. Umbral de decisión: sensibilidad, especificidad y alertas
# -----------------------------------------------------------------------------
prob_rf <- predict(rf, test, type = "prob")[, "Si"]
metricas_umbral <- function(u) {
  pred <- ifelse(prob_rf >= u, "Si", "No")
  c(umbral = u,
    sensibilidad  = round(100 * mean(pred[test$mora == "Si"] == "Si"), 1),
    especificidad = round(100 * mean(pred[test$mora == "No"] == "No"), 1),
    exactitud     = round(100 * mean(pred == test$mora), 1),
    alertas       = sum(pred == "Si"))
}
tabla_umbral <- t(sapply(c(0.5, 0.4, 0.35, 0.3, 0.25), metricas_umbral))
print(tabla_umbral)

# Matriz de confusión con umbral 0.5 y con el umbral propuesto (0.3)
table(Predicho = ifelse(prob_rf >= 0.5, "Si", "No"), Real = test$mora)
table(Predicho = ifelse(prob_rf >= 0.3, "Si", "No"), Real = test$mora)

# =============================================================================
# RESPUESTAS
# =============================================================================
#
# a. 298 de 1.000 créditos en mora: tasa de 29,8%. Quien predice siempre "No"
#    acierta 70,2% en el total y 74,0% en la prueba (300 casos, 78 en mora).
#    Cualquier modelo debe superar ese 74% para aportar algo.
#
# b. Comparación en prueba:
#      Modelo                    Hojas  Exact. train  Exact. test   AUC
#      Árbol sin restricciones    139      100,0%        69,0%      0,62
#      Árbol podado (xerror min)   10       81,7%        75,3%      0,72
#      Random Forest (500, mtry=2)  -          -          81,0%      0,83
#    El árbol sin restricciones memoriza (100% en entrenamiento) y en prueba
#    queda POR DEBAJO de la regla trivial (69% < 74%). El árbol podado apenas
#    supera la regla trivial y además usa cod_asesor en una partición (ruido
#    memorizado). El bosque (OOB 22,3%) logra 81% de exactitud y AUC 0,83:
#    +11 puntos de AUC frente al árbol podado.
#
# c. Error OOB: 28,4% con 10 árboles, 26,1% con 25, 24,9% con 50, 24,0% con
#    100, 23,4% con 200 y 22,3% con 500. Entre 100 y 500 árboles oscila en
#    21,9%–24,1%. Se estabiliza hacia los 100–200 árboles; más árboles no
#    sobreajustan, solo dejan de mejorar.
#
# d. mtry de 1 a 8: OOB entre 21,3% y 23,7%, AUC de prueba entre 0,81 y 0,83
#    (Bagging, mtry = 8: OOB 21,4%, AUC 0,81). No hay un valor claramente
#    mejor: las diferencias (2–3 puntos) son del orden del ruido. mtry = 1 es
#    algo peor en OOB y mtry altos bajan un poco el AUC. La ganancia grande es
#    pasar de un árbol a un bosque, no afinar mtry. Con pocas variables útiles,
#    mtry importa poco aquí.
#
# Interpretación
# e. Gini (MeanDecreaseGini): monto 77,9; ingreso 63,3; edad 38,0;
#    cod_asesor 36,6; historial 25,5; antiguedad 24,4; estrato 21,0; empleo 8,0.
#    Permutación (MeanDecreaseAccuracy): monto 40,9; ingreso 30,7;
#    historial 23,7; estrato 9,0; empleo 1,8; edad 1,7; cod_asesor -1,1;
#    antiguedad -1,9.
#    cod_asesor queda 4.º en Gini y penúltimo (≈0, negativo) en permutación.
#    Es ruido puro, pero tiene 60 valores distintos: ofrece muchísimos puntos
#    de corte y los árboles lo usan para separar ruido en nodos pequeños, lo
#    que infla la reducción de impureza (sesgo de Gini hacia variables con
#    muchos valores/continuas). Al barajarlo, el error no cambia, porque no
#    tiene relación real con la mora. Confirmación: sin cod_asesor el OOB baja
#    de 22,3% a 21,0%. Conclusión: preferir la importancia por permutación.
#
# f. Sí recupera lo esencial: monto e ingreso (juntos forman la carga
#    monto/(12·ingreso), el efecto más fuerte de la regla) e historial
#    aparecen arriba en ambas medidas. Le cuesta más EMPLEO: tiene efecto
#    moderado (+1 en el logit) pero es binaria, así que Gini la castiga y en
#    permutación queda casi en cero. Edad (< 26) y antigüedad tienen efectos
#    pequeños y casi no aparecen en permutación (la edad sale alta en Gini por
#    ser continua). Estrato aparece aunque no está en la regla porque está
#    correlacionado con el ingreso (proxy).
#
# g. Umbral 0,5: sensibilidad 60,3% (47 de 78 morosos detectados),
#    especificidad 88,3%, exactitud 81,0%, 73 alertas.
#      Umbral  Sensib.  Especif.  Exactitud  Alertas
#       0,50    60,3%    88,3%     81,0%       73
#       0,40    75,6%    80,6%     79,3%      102
#       0,35    76,9%    74,3%     75,0%      117
#       0,30    83,3%    71,2%     74,3%      129
#       0,25    87,2%    62,2%     68,7%      152
#    Propuesta: umbral 0,3 (o 0,4 si la capacidad de revisión es limitada).
#    Con 0,3 se detectan 83% de los morosos (65 de 78, frente a 47 con 0,5),
#    a cambio de revisar 129 solicitudes en vez de 73 y marcar 64 socios
#    cumplidos (vs. 26). La exactitud baja, pero para la cooperativa un
#    crédito en mora (pérdida de capital) suele costar mucho más que una
#    revisión adicional, así que conviene priorizar la sensibilidad. La
#    decisión final depende del costo de una mora frente al costo de revisar.
#
