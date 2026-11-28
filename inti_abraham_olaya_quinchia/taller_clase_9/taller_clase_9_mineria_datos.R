# ==============================================================================
# TALLER PRÁCTICO CLASE 9: ENSAMBLES DE APRENDIZAJE (BAGGING, RANDOM FOREST & GRADIENT BOOSTING)
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CARGA DE LIBRERÍAS Y CONFIGURACIÓN DEL ENTORNO
# ------------------------------------------------------------------------------
paquetes <- c("tidyverse", "randomForest", "xgboost", "vip", "pROC", "tidymodels", "janitor", "knitr")
nuevos_paquetes <- paquetes[!(paquetes %in% installed.packages()[,"Package"])]
if(length(nuevos_paquetes)) install.packages(nuevos_paquetes)

library(tidyverse)
library(randomForest)
library(xgboost)
library(vip)
library(pROC)
library(tidymodels)
library(janitor)
library(knitr)

set.seed(2026)

cat("===================================================================\n")
cat("TALLER CLASE 9 - ENSAMBLES DE APRENDIZAJE: RANDOM FOREST & BOOSTING\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN Y PREPARACIÓN DE DATOS (PREDICCIÓN DE CHURN FINANCIERO)
# ------------------------------------------------------------------------------
n <- 1200
df_churn <- tibble(
  id_cliente       = 1001:(1000 + n),
  score_credito    = round(rnorm(n, mean = 650, sd = 70)),
  edad             = round(rnorm(n, mean = 40, sd = 10)),
  saldo_cuenta     = round(runif(n, 500, 150000), 2),
  num_productos    = sample(1:4, n, replace = TRUE, prob = c(0.4, 0.4, 0.15, 0.05)),
  es_miembro_activo= sample(c(0, 1), n, replace = TRUE, prob = c(0.45, 0.55)),
  salario_estimado = round(runif(n, 15000, 120000), 2),
  pais             = sample(c("Colombia", "México", "Chile"), n, replace = TRUE)
) %>%
  mutate(
    prob_churn = plogis(-1.5 - 0.005*(score_credito - 650) + 0.04*(edad - 40) - 
                        0.6*es_miembro_activo + 0.5*(num_productos == 1)),
    churn = factor(ifelse(rbinom(n, 1, prob_churn) == 1, "Si", "No"), levels = c("No", "Si"))
  ) %>%
  select(-prob_churn)

# Eliminación de ID para evitar Data Leakage
df_modelo <- df_churn %>% select(-id_cliente)

# División en Entrenamiento (80%) y Prueba (20%)
set.seed(2026)
split_datos <- initial_split(df_modelo, prop = 0.80, strata = churn)
train_data  <- training(split_datos)
test_data   <- testing(split_datos)

cat("--- TAMAÑO DE LOS CONJUNTOS DE DATOS ---\n")
cat("Entrenamiento:", nrow(train_data), "registros | Prueba:", nrow(test_data), "registros\n\n")

# ------------------------------------------------------------------------------
# 3. RANDOM FOREST & ESTIMACIÓN DE ERROR OUT-OF-BAG (OOB)
# ------------------------------------------------------------------------------
cat("===================================================================\n")
cat("--- MODELADO CON RANDOM FOREST & ERROR OUT-OF-BAG (OOB) ---\n")

# Modelo Random Forest
rf_model <- randomForest(
  churn ~ .,
  data = train_data,
  ntree = 500,
  mtry = 2,
  importance = TRUE,
  proximity = TRUE
)

print(rf_model)

cat("\n--- ERROR OUT-OF-BAG (OOB) FINAL ---\n")
cat("Error OOB estimado:", round(rf_model$err.rate[500, "OOB"] * 100, 2), "%\n")

# Visualización de Importancia de Variables (Gini & Permutación)
cat("\n--- IMPORTANCIA DE VARIABLES (RANDOM FOREST) ---\n")
print(round(importance(rf_model), 2))

# ------------------------------------------------------------------------------
# 4. GRADIENT BOOSTING CON XGBOOST
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- MODELADO CON GRADIENT BOOSTING (XGBOOST) ---\n")

# Preparación de Matrices DMatrix para XGBoost
train_matrix_x <- model.matrix(churn ~ . - 1, data = train_data)
train_label_y  <- ifelse(train_data$churn == "Si", 1, 0)

test_matrix_x  <- model.matrix(churn ~ . - 1, data = test_data)
test_label_y   <- ifelse(test_data$churn == "Si", 1, 0)

dtrain <- xgb.DMatrix(data = train_matrix_x, label = train_label_y)
dtest  <- xgb.DMatrix(data = test_matrix_x, label = test_label_y)

# Parámetros de XGBoost
params_xgb <- list(
  booster          = "gbtree",
  objective        = "binary:logistic",
  eval_metric      = "auc",
  eta              = 0.05,
  max_depth        = 4,
  subsample        = 0.8,
  colsample_bytree = 0.8
)

# Entrenamiento del Modelo Boosting
set.seed(2026)
xgb_model <- xgb.train(
  params    = params_xgb,
  data      = dtrain,
  nrounds   = 150,
  watchlist = list(train = dtrain, eval = dtest),
  verbose   = 0
)

cat("Modelo XGBoost entrenado exitosamente con 150 iteraciones boosting.\n")

# ------------------------------------------------------------------------------
# 5. EVALUACIÓN COMPARATIVA Y CURVAS ROC / AUC
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- EVALUACIÓN COMPARATIVA DE MODELOS EN CONJUNTO DE PRUEBA ---\n")

# Predicciones de Probabilidad
pred_prob_rf  <- predict(rf_model, newdata = test_data, type = "prob")[, "Si"]
pred_prob_xgb <- predict(xgb_model, newdata = dtest)

# Cálculo de ROC / AUC
roc_rf  <- roc(test_data$churn, pred_prob_rf, levels = c("No", "Si"))
roc_xgb <- roc(test_data$churn, pred_prob_xgb, levels = c("No", "Si"))

cat("AUC Random Forest :", round(auc(roc_rf), 4), "\n")
cat("AUC XGBoost       :", round(auc(roc_xgb), 4), "\n")

# Matriz de Confusión XGBoost (Corte 0.5)
pred_clase_xgb <- factor(ifelse(pred_prob_xgb > 0.5, "Si", "No"), levels = c("No", "Si"))
mat_conf_xgb   <- confusionMatrix(pred_clase_xgb, test_data$churn, positive = "Si")

cat("\n--- MATRIZ DE CONFUSIÓN (XGBOOST EN TEST) ---\n")
print(mat_conf_xgb$table)
cat("Accuracy    :", round(mat_conf_xgb$overall["Accuracy"], 4), "\n")
cat("Sensibilidad:", round(mat_conf_xgb$byClass["Sensitivity"], 4), "\n")
cat("Especificidad:", round(mat_conf_xgb$byClass["Specificity"], 4), "\n")

# ------------------------------------------------------------------------------
# 6. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 9 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_09_mineria_datos.R\n")
cat("4. git commit -m \"Entrega Taller Clase 9 (Ensambles & Boosting) - Inti A. Olaya\"\n")
cat("5. git push origin main\n")
cat("===================================================================\n")
