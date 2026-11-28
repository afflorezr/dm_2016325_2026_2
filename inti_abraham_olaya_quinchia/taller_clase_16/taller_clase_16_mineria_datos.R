# Taller 16 R script
# ==============================================================================
# TALLER PRÁCTICO CLASE 16: EVALUACIÓN Y COMPARACIÓN INTEGRAL DE ENSAMBLES
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

library(tidyverse)
library(tidymodels)
library(rpart)
library(randomForest)
library(xgboost)
library(pROC)
library(stacks)
library(janitor)

cat("===================================================================\n")
cat("TALLER CLASE 16 - EVALUACIÓN DE ENSAMBLES, EARLY STOPPING & STACKING\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. SIMULACIÓN DE DATOS (MONITOREO AMBIENTAL DE CALIDAD DE AGUA)
# ------------------------------------------------------------------------------
set.seed(42)
n <- 600

datos_agua <- tibble(
  turbiedad   = rexp(n, rate = 0.1),
  pH          = rnorm(n, mean = 7.2, sd = 0.8),
  coliformes  = rpois(n, lambda = 80),
  DBO         = rexp(n, rate = 0.2),
  poblacion   = sample(5000:500000, n, replace = TRUE),
  altitud     = runif(n, 100, 3000)
) %>%
  mutate(
    score_riesgo = -3.5 + 0.05 * turbiedad + 1.2 * abs(pH - 7.0) + 
                   0.03 * coliformes + 0.15 * DBO - 0.0003 * altitud,
    prob_alerta  = 1 / (1 + exp(-score_riesgo)),
    alerta       = factor(if_else(prob_alerta > 0.45, "Alerta", "Normal"), 
                          levels = c("Normal", "Alerta"))
  ) %>%
  select(-score_riesgo, -prob_alerta)

cat("--- ESTRUCTURA DEL DATASET AMBIENTAL ---\n")
glimpse(datos_agua)
cat("\nDistribución de la variable objetivo (Alerta):\n")
print(table(datos_agua$alerta))

# ------------------------------------------------------------------------------
# 2. SEPARACIÓN EN TRAIN/TEST Y VALIDACIÓN CRUZADA DE 5 PLIEGUES (5-FOLD CV)
# ------------------------------------------------------------------------------
set.seed(2026)
split_datos <- initial_split(datos_agua, prop = 0.80, strata = alerta)
train_df    <- training(split_datos)
test_df     <- testing(split_datos)

folds <- vfold_cv(train_df, v = 5, strata = alerta)

# ------------------------------------------------------------------------------
# (a) ENTRENAMIENTO Y COMPARACIÓN CON CV DE 5 PLIEGUES (ÁRBOL, RF Y XGBOOST)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE (a): EVALUACIÓN DE MODELOS CON VALIDACIÓN CRUZADA 5-FOLD ---\n")

# 1. Especificación de Modelos
spec_arbol <- decision_tree(cost_complexity = 0.01, tree_depth = 5) %>%
  set_engine("rpart") %>%
  set_mode("classification")

spec_rf <- rand_forest(trees = 300, mtry = 3) %>%
  set_engine("randomForest") %>%
  set_mode("classification")

spec_xgb <- boost_tree(trees = 100, tree_depth = 4, learn_rate = 0.05) %>%
  set_engine("xgboost") %>%
  set_mode("classification")

# 2. Receta de Preprocesamiento
receta_base <- recipe(alerta ~ ., data = train_df) %>%
  step_normalize(all_numeric_predictors())

# 3. Workflows
wf_arbol <- workflow() %>% add_recipe(receta_base) %>% add_model(spec_arbol)
wf_rf    <- workflow() %>% add_recipe(receta_base) %>% add_model(spec_rf)
wf_xgb   <- workflow() %>% add_recipe(receta_base) %>% add_model(spec_xgb)

metrics_set <- metric_set(accuracy, f_meas, roc_auc)

res_arbol <- fit_resamples(wf_arbol, resamples = folds, metrics = metrics_set)
res_rf    <- fit_resamples(wf_rf,    resamples = folds, metrics = metrics_set)
res_xgb   <- fit_resamples(wf_xgb,   resamples = folds, metrics = metrics_set)

cat("\nMétricas en Validación Cruzada (Árbol de Decisión):\n")
print(collect_metrics(res_arbol))

cat("\nMétricas en Validación Cruzada (Random Forest):\n")
print(collect_metrics(res_rf))

cat("\nMétricas en Validación Cruzada (XGBoost):\n")
print(collect_metrics(res_xgb))

# ------------------------------------------------------------------------------
# (b) EARLY STOPPING EN XGBOOST CON 20 RONDAS DE PACIENCIA
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE (b): XGBOOST CON EARLY STOPPING (20 RONDAS DE PACIENCIA) ---\n")

X_train <- model.matrix(alerta ~ . - 1, data = train_df)
y_train <- as.numeric(train_df$alerta == "Alerta")

X_test  <- model.matrix(alerta ~ . - 1, data = test_df)
y_test  <- as.numeric(test_df$alerta == "Alerta")

dtrain <- xgb.DMatrix(data = X_train, label = y_train)
dtest  <- xgb.DMatrix(data = X_test,  label = y_test)

params_xgb <- list(
  booster          = "gbtree",
  objective        = "binary:logistic",
  eval_metric      = "auc",
  eta              = 0.05,
  max_depth        = 4,
  subsample        = 0.8
)

modelo_xgb_early <- xgb.train(
  params                = params_xgb,
  data                  = dtrain,
  nrounds               = 250,
  watchlist             = list(train = dtrain, eval = dtest),
  early_stopping_rounds = 20,
  verbose               = 0
)

cat("Número óptimo de árboles iterados (best_iteration):", modelo_xgb_early$best_iteration, "\n")
cat("Mejor AUC obtenido en validación:", modelo_xgb_early$best_score, "\n")

# ------------------------------------------------------------------------------
# (c) COMPARACIÓN DE IMPORTANCIA DE VARIABLES (RF IMPUREZA VS XGBOOST GAIN)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE (c): COMPARACIÓN DE IMPORTANCIA DE VARIABLES (RF vs XGBOOST) ---\n")

# Random Forest Impureza (Gini)
fit_rf_direct <- randomForest(alerta ~ ., data = train_df, importance = TRUE)
imp_rf <- importance(fit_rf_direct, type = 2) # MeanDecreaseGini
cat("\nImportancia de Variables en Random Forest (MeanDecreaseGini):\n")
print(sort(imp_rf[, 1], decreasing = TRUE))

# XGBoost Gain
imp_xgb <- xgb.importance(model = modelo_xgb_early)
cat("\nImportancia de Variables en XGBoost (Gain):\n")
print(imp_xgb)

# ------------------------------------------------------------------------------
# (d) MODELO DE STACKING CON PREDICCIONES OUT-OF-FOLD (OOF)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE (d): ENSAMBLE MULTINIVEL (STACKING) CON PREDICCIONES OOF ---\n")

ctrl_stack <- control_stack_resamples()

res_arbol_stack <- fit_resamples(wf_arbol, resamples = folds, control = ctrl_stack)
res_rf_stack    <- fit_resamples(wf_rf,    resamples = folds, control = ctrl_stack)

ensamble_stack <- stacks() %>%
  add_candidates(res_arbol_stack) %>%
  add_candidates(res_rf_stack) %>%
  blend_predictions(penalty = 10^seq(-3, -1, length.out = 20)) %>%
  fit_members()

cat("\nResumen del Modelo de Stacking Ajustado:\n")
print(ensamble_stack)

# Predicciones finales en el conjunto de prueba (Test)
pred_stack <- predict(ensamble_stack, test_df, type = "prob") %>%
  bind_cols(test_df)

roc_stack <- roc(pred_stack$alerta, pred_stack$.pred_Alerta, levels = c("Normal", "Alerta"))
cat("\nAUC del Modelo Stacking en el conjunto de Prueba:", auc(roc_stack), "\n")

# ------------------------------------------------------------------------------
# 3. VERSIONADO Y CONTROL DE CAMBIOS EN GIT (SUBMISIÓN EN RAMA TALLER_16)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- COMANDOS DE GIT PARA LA ENTREGA DEL TALLER CLASE 16 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git checkout -b taller_16\n")
cat("4. git add taller_16_mineria_datos.R\n")
cat("5. git commit -m \"Entrega Taller Clase 16 (Ensambles Comparativos & Stacking) - Inti A. Olaya\"\n")
cat("6. git push origin taller_16\n")
cat("===================================================================\n")
