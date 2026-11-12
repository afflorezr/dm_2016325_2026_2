# =============================================================================
# Minería de Datos — Clase 16: Gradient Boosting, XGBoost y Stacking
# Ejercicio: calidad del agua en Colombia (apta / no apta)
# Autor: David Márquez
# =============================================================================
# Paquetes: rpart, randomForest, xgboost, pROC
#install.packages(c("rpart", "randomForest", "xgboost", "pROC"))
# El código funciona con xgboost 1.7.x y 3.x (CRAN).

library(rpart)
library(randomForest)
library(xgboost)
library(pROC)

# -----------------------------------------------------------------------------
# 0. Datos simulados (código del slide)
# -----------------------------------------------------------------------------
set.seed(42); n <- 600
df <- data.frame(
  turbiedad  = rexp(n, 0.1),
  pH         = rnorm(n, 7.2, 0.8),
  coliformes = rpois(n, 80),
  DBO        = rexp(n, 0.2),
  poblacion  = sample(5000:500000, n, replace = TRUE),
  altitud    = runif(n, 100, 3000)
)
df$apta <- as.integer(
  df$turbiedad < 5 & df$pH > 6.5 & df$pH < 8.5 &
  df$coliformes < 100 & df$DBO < 5
)

vars <- c("turbiedad", "pH", "coliformes", "DBO", "poblacion", "altitud")
table(df$apta)
cat(sprintf("Proporción de municipios con agua apta: %.1f%%\n",
            100 * mean(df$apta)))
# La clase positiva (apta) es minoritaria (~20%): la exactitud sola engaña,
# por eso se reportan también F1 y AUC.

# Versión factor de la respuesta para rpart / randomForest
df$apta_f <- factor(ifelse(df$apta == 1, "apta", "no_apta"),
                    levels = c("no_apta", "apta"))

# -----------------------------------------------------------------------------
# Funciones auxiliares
# -----------------------------------------------------------------------------
# Pliegues estratificados (misma proporción de "apta" en cada pliegue)
pliegues_estrat <- function(y, k, semilla) {
  set.seed(semilla)
  f <- integer(length(y))
  for (cl in unique(y)) {
    id <- which(y == cl)
    f[id] <- sample(rep(1:k, length.out = length(id)))
  }
  f
}

metricas <- function(prob, y, umbral = 0.5) {
  pred <- as.integer(prob >= umbral)
  tp <- sum(pred == 1 & y == 1); fp <- sum(pred == 1 & y == 0)
  fn <- sum(pred == 0 & y == 1)
  prec <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
  rec  <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
  c(accuracy = mean(pred == y),
    F1  = ifelse(prec + rec == 0, 0, 2 * prec * rec / (prec + rec)),
    AUC = as.numeric(auc(roc(y, prob, levels = c(0, 1), direction = "<",
                             quiet = TRUE))))
}

# Mejor iteración de early stopping (el nombre cambió entre versiones)
mejor_iter <- function(obj) {
  if (!is.null(obj$best_iteration)) return(obj$best_iteration)
  if (!is.null(obj$early_stop$best_iteration)) return(obj$early_stop$best_iteration)
  attr(obj, "early_stop")$best_iteration
}

# Hiperparámetros de XGBoost (los de la clase)
params_xgb <- list(
  objective        = "binary:logistic",
  eval_metric      = "logloss",
  max_depth        = 4,
  eta              = 0.05,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  gamma            = 1,
  lambda           = 2,
  nthread          = 1        # reproducibilidad
)

# Ajuste y predicción de cada modelo base
ajustar_arbol <- function(train) {
  rpart(apta_f ~ turbiedad + pH + coliformes + DBO + poblacion + altitud,
        data = train, method = "class")      # árbol CART con poda por defecto
}
ajustar_rf <- function(train) {
  randomForest(apta_f ~ turbiedad + pH + coliformes + DBO + poblacion + altitud,
               data = train, ntree = 500)
}
ajustar_xgb <- function(train, nrounds) {
  dtr <- xgb.DMatrix(as.matrix(train[, vars]), label = train$apta)
  xgb.train(params = params_xgb, data = dtr, nrounds = nrounds, verbose = 0)
}
prob_arbol <- function(m, nuevo) predict(m, nuevo, type = "prob")[, "apta"]
prob_rf    <- function(m, nuevo) predict(m, nuevo, type = "prob")[, "apta"]
prob_xgb   <- function(m, nuevo) predict(m, xgb.DMatrix(as.matrix(nuevo[, vars])))

# =============================================================================
# b. Early stopping en XGBoost (20 rondas de paciencia)
#    (se resuelve antes que (a) porque el número óptimo de árboles se usa
#     después en la validación cruzada de XGBoost)
# =============================================================================
dtodo <- xgb.DMatrix(as.matrix(df[, vars]), label = df$apta)
set.seed(42)
cv_xgb <- xgb.cv(
  params  = params_xgb,
  data    = dtodo,
  nrounds = 2000,
  nfold   = 5,
  stratified = TRUE,
  early_stopping_rounds = 20,      # paciencia de 20 rondas
  verbose = 0
)
n_opt <- mejor_iter(cv_xgb)
cat("Número óptimo de árboles (early stopping, VC 5 pliegues):", n_opt, "\n")

# Curva de log-loss de entrenamiento y validación
ev <- as.data.frame(cv_xgb$evaluation_log)
plot(ev$iter, ev$test_logloss_mean, type = "l", lwd = 2, col = "firebrick",
     ylim = range(c(ev$train_logloss_mean, ev$test_logloss_mean)),
     xlab = "Número de árboles", ylab = "Log-loss",
     main = "XGBoost: early stopping (paciencia = 20)")
lines(ev$iter, ev$train_logloss_mean, lwd = 2, col = "steelblue")
abline(v = n_opt, lty = 2)
legend("topright", lwd = 2, col = c("steelblue", "firebrick"),
       legend = c("Entrenamiento", "Validación"))

# Alternativa con conjunto de validación 80/20 (como en la clase)
set.seed(42)
idx_val <- sample(n, 0.2 * n)
dtr_es  <- xgb.DMatrix(as.matrix(df[-idx_val, vars]), label = df$apta[-idx_val])
dval_es <- xgb.DMatrix(as.matrix(df[ idx_val, vars]), label = df$apta[ idx_val])
lista_eval <- list(train = dtr_es, val = dval_es)
args_es <- list(params = params_xgb, data = dtr_es, nrounds = 2000,
                early_stopping_rounds = 20, verbose = 0)
# xgboost >= 3 usa 'evals'; versiones anteriores usan 'watchlist'
if ("evals" %in% names(formals(xgb.train))) args_es$evals <- lista_eval else
  args_es$watchlist <- lista_eval
mod_es <- do.call(xgb.train, args_es)
cat("Número óptimo de árboles (validación 80/20):", mejor_iter(mod_es), "\n")

# =============================================================================
# a. Árbol vs. Random Forest vs. XGBoost con VC de 5 pliegues
# =============================================================================
k <- 5
fold <- pliegues_estrat(df$apta, k, semilla = 42)

res_cv <- list()
for (i in 1:k) {
  tr <- df[fold != i, ]; te <- df[fold == i, ]
  set.seed(42); m_arbol <- ajustar_arbol(tr)
  set.seed(42); m_rf    <- ajustar_rf(tr)
  set.seed(42); m_xgb   <- ajustar_xgb(tr, n_opt)
  res_cv[[i]] <- rbind(
    data.frame(pliegue = i, modelo = "Árbol",
               t(metricas(prob_arbol(m_arbol, te), te$apta))),
    data.frame(pliegue = i, modelo = "Random Forest",
               t(metricas(prob_rf(m_rf, te), te$apta))),
    data.frame(pliegue = i, modelo = "XGBoost",
               t(metricas(prob_xgb(m_xgb, te), te$apta)))
  )
}
res_cv <- do.call(rbind, res_cv)

resumen_a <- aggregate(cbind(accuracy, F1, AUC) ~ modelo, data = res_cv,
                       FUN = function(x) round(mean(x), 3))
de_a <- aggregate(cbind(accuracy, F1, AUC) ~ modelo, data = res_cv,
                  FUN = function(x) round(sd(x), 3))
cat("\nVC 5 pliegues — promedio:\n"); print(resumen_a, row.names = FALSE)
cat("\nVC 5 pliegues — desviación estándar:\n"); print(de_a, row.names = FALSE)

# =============================================================================
# c. Importancia: RF (impureza, MeanDecreaseGini) vs. XGBoost (Gain)
# =============================================================================
set.seed(42); rf_todo  <- ajustar_rf(df)
set.seed(42); xgb_todo <- ajustar_xgb(df, n_opt)

imp_rf <- importance(rf_todo)[, "MeanDecreaseGini"]
imp_rf <- sort(imp_rf / sum(imp_rf), decreasing = TRUE)   # normalizada a 1

imp_xgb <- xgb.importance(model = xgb_todo)
gain    <- setNames(imp_xgb$Gain, imp_xgb$Feature)
gain    <- gain[vars]; gain[is.na(gain)] <- 0              # variables no usadas
gain    <- sort(gain, decreasing = TRUE)

comp_imp <- data.frame(
  variable    = vars,
  RF_Gini     = round(imp_rf[vars], 3),
  rank_RF     = match(vars, names(imp_rf)),
  XGB_Gain    = round(gain[vars], 3),
  rank_XGB    = match(vars, names(gain))
)
print(comp_imp[order(comp_imp$rank_XGB), ], row.names = FALSE)
cat("Correlación de Spearman entre rankings:",
    round(cor(comp_imp$rank_RF, comp_imp$rank_XGB), 2), "\n")

par(mfrow = c(1, 2), mar = c(4, 7, 3, 1))
barplot(rev(imp_rf), horiz = TRUE, las = 1, col = "darkgreen",
        main = "RF: impureza (Gini)", xlab = "Importancia relativa")
barplot(rev(gain), horiz = TRUE, las = 1, col = "steelblue",
        main = "XGBoost: Gain", xlab = "Importancia relativa")
par(mfrow = c(1, 1), mar = c(5, 4, 4, 2) + 0.1)

# =============================================================================
# d. Stacking: árbol + RF como base, logística como meta-modelo (con OOF)
# =============================================================================
# Evaluación honesta (anidada): en cada pliegue externo,
#  1) dentro del entrenamiento se generan predicciones OOF (VC interna de 5
#     pliegues) del árbol y del RF -> columnas Z;
#  2) la logística se entrena sobre Z (nunca sobre predicciones dentro de
#     muestra, que producirían leakage);
#  3) los modelos base se reentrenan con todo el entrenamiento, predicen el
#     pliegue externo y el meta-modelo combina esas predicciones.
res_stack <- list()
pesos_meta <- list()
for (i in 1:k) {
  tr <- df[fold != i, ]; te <- df[fold == i, ]

  # 1) OOF internas
  f_in <- pliegues_estrat(tr$apta, k, semilla = 100 + i)
  Z <- data.frame(arbol = numeric(nrow(tr)), rf = numeric(nrow(tr)))
  for (j in 1:k) {
    a <- tr[f_in != j, ]; b <- tr[f_in == j, ]
    set.seed(42); Z$arbol[f_in == j] <- prob_arbol(ajustar_arbol(a), b)
    set.seed(42); Z$rf[f_in == j]    <- prob_rf(ajustar_rf(a), b)
  }
  Z$apta <- tr$apta

  # 2) meta-modelo logístico sobre las OOF
  meta <- glm(apta ~ arbol + rf, data = Z, family = binomial)
  pesos_meta[[i]] <- coef(meta)

  # 3) modelos base con todo el entrenamiento -> predicciones del pliegue externo
  set.seed(42); m_arbol <- ajustar_arbol(tr)
  set.seed(42); m_rf    <- ajustar_rf(tr)
  Z_te <- data.frame(arbol = prob_arbol(m_arbol, te), rf = prob_rf(m_rf, te))
  p_stack <- predict(meta, newdata = Z_te, type = "response")

  res_stack[[i]] <- data.frame(pliegue = i, modelo = "Stacking (árbol + RF)",
                               t(metricas(p_stack, te$apta)))
}
res_stack <- do.call(rbind, res_stack)
cat("\nCoeficientes del meta-modelo por pliegue:\n")
print(round(do.call(rbind, pesos_meta), 2))

res_todo <- rbind(res_cv, res_stack)
resumen_d <- aggregate(cbind(accuracy, F1, AUC) ~ modelo, data = res_todo,
                       FUN = function(x) round(mean(x), 3))
cat("\nComparación final (VC 5 pliegues, mismos pliegues):\n")
print(resumen_d[order(-resumen_d$AUC), ], row.names = FALSE)

# =============================================================================
# RESPUESTAS
# =============================================================================
# (Valores de referencia con set.seed(42). Pueden variar un poco según la
#  versión de R y de los paquetes (en especial xgboost 1.7 vs. 3.x); lo
#  importante son los órdenes de magnitud y las conclusiones.)
#
# Datos: 106 de 600 municipios con agua apta (17,7%). Predecir siempre
# "no apta" daría 82,3% de exactitud y F1 = 0, así que la exactitud sola no
# sirve para comparar; F1 y AUC son las métricas relevantes.
#
# a. VC estratificada de 5 pliegues (promedio ± d.e.):
#      Modelo          Accuracy        F1             AUC
#      Árbol (rpart)   0,982 ± 0,014   0,948 ± 0,038  0,984 ± 0,016
#      Random Forest   0,982 ± 0,015   0,950 ± 0,040  0,998 ± 0,003
#      XGBoost         ~0,983 ± 0,016  ~0,954 ± 0,042 ~0,994 ± 0,006
#    Los tres modelos son prácticamente equivalentes en accuracy y F1: las
#    diferencias (< 1 punto) son mucho menores que la desviación entre
#    pliegues. La razón es que la regla real es un conjunto de umbrales
#    paralelos a los ejes (turbiedad < 5, 6,5 < pH < 8,5, DBO < 5,
#    coliformes < 100) que un solo árbol ya puede representar casi exacto,
#    y no hay ruido en la respuesta. Donde sí se nota el ensamble es en el
#    AUC: RF y XGBoost ordenan mejor las probabilidades (0,99–1,00) que el
#    árbol (0,98), y son más estables entre pliegues.
#
# b. Early stopping (paciencia de 20 rondas, eta = 0,05, max_depth = 4):
#    con xgb.cv de 5 pliegues el número óptimo de árboles queda del orden de
#    150–300 (≈ 290 con la semilla 42; cambia con la partición porque la
#    curva de log-loss de validación es muy plana cerca del mínimo). Con una
#    sola partición 80/20 se detiene antes (≈ 130). El log-loss de validación
#    baja hasta ≈ 0,06 mientras el de entrenamiento sigue bajando (≈ 0,03):
#    pasado el óptimo, más árboles solo memorizan. Reporte el valor que le
#    dé n_opt en su ejecución.
#
# c. Importancia (normalizada a 1):
#      Variable     RF (Gini)   XGBoost (Gain)
#      turbiedad      0,51         ~0,50
#      DBO            0,23         ~0,26
#      pH             0,16         ~0,21
#      altitud        0,04         ~0,01
#      coliformes     0,03         ~0,02
#      poblacion      0,03         ~0,01
#    Sí coinciden en lo esencial: ambos ponen turbiedad, DBO y pH arriba y
#    en el mismo orden; son justamente las restricciones que más municipios
#    incumplen (turbiedad < 5 solo se cumple en ~39%, DBO < 5 en ~63%,
#    pH en rango en ~79%). Coliformes está en la regla pero casi nunca
#    restringe (con Poisson(80), P(coliformes < 100) ≈ 98%), por eso ambos
#    la ven poco importante. La diferencia: el Gini de RF le da algo de
#    importancia a población y altitud (ruido puro), porque son continuas
#    con muchos puntos de corte y el sorteo de variables (mtry) obliga a
#    usarlas a veces; XGBoost con gamma = 1 casi no las usa (Gain ≈ 0), ya
#    que solo acepta divisiones que reduzcan la pérdida lo suficiente.
#
# d. Stacking (árbol + RF, meta-modelo logístico sobre OOF, evaluación anidada):
#      accuracy 0,978   F1 0,941   AUC 0,997
#    NO supera a los individuales: queda igual o ligeramente por debajo del
#    Random Forest (0,982 / 0,950 / 0,998). Los coeficientes del meta-modelo
#    lo explican: el peso del RF es grande y positivo (≈ 11 a 22) y el del
#    árbol es pequeño o negativo, es decir, el meta-modelo básicamente se
#    queda con el RF. El stacking gana cuando los modelos base cometen errores
#    distintos; aquí el árbol y el RF se equivocan en los mismos municipios
#    (los que están justo en los umbrales), así que no hay nada que combinar,
#    y el paso extra solo agrega varianza.
#