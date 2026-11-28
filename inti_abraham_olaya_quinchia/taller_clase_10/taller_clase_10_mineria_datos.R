# ==============================================================================
# TALLER PRÁCTICO CLASE 10: ENSAMBLES AVANZADOS (STACKING) Y CLASIFICACIÓN DESBALANCEADA
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y LIBRERÍAS
# ------------------------------------------------------------------------------
librerias <- c("tidyverse", "tidymodels", "stacks", "randomForest", 
               "xgboost", "ROSE", "pROC", "janitor", "knitr")

nuevas_librerias <- librerias[!(librerias %in% installed.packages()[,"Package"])]
if(length(nuevas_librerias) > 0) install.packages(nuevas_librerias)

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidymodels)
  library(stacks)
  library(randomForest)
  library(xgboost)
  library(ROSE)
  library(pROC)
  library(janitor)
  library(knitr)
})

cat("===================================================================\n")
cat("TALLER CLASE 10 - STACKING ENSEMBLES & CLASIFICACIÓN DESBALANCEADA\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DE DATASET SIMULADO (RIESGO DE FRAUDE FINANCIERO)
# ------------------------------------------------------------------------------
set.seed(2026)
n <- 2500

datos_fraude <- tibble(
  id_cliente = paste0("CLI_", 1000:(1000 + n - 1)),
  monto_transaccion = exp(rnorm(n, mean = 4.5, sd = 1.2)),
  frecuencia_uso_diario = rpois(n, lambda = 3),
  antiguedad_meses = sample(1:120, n, replace = TRUE),
  puntaje_credito = round(rnorm(n, mean = 650, sd = 70)),
  dispositivo_nuevo = sample(c("Sí", "No"), n, replace = TRUE, prob = c(0.25, 0.75)),
  tipo_tarjeta = sample(c("Clásica", "Gold", "Platinum"), n, replace = TRUE, prob = c(0.6, 0.3, 0.1))
) %>%
  mutate(
    logit_p = -3.5 + 
      0.002 * monto_transaccion + 
      -0.015 * puntaje_credito + 
      1.2 * (dispositivo_nuevo == "Sí") + 
      -0.02 * antiguedad_meses,
    prob_fraude = 1 / (1 + exp(-logit_p)),
    fraude = factor(ifelse(runif(n) < prob_fraude, "Fraude", "Normal"), levels = c("Fraude", "Normal"))
  ) %>%
  select(-logit_p, -prob_fraude)

cat("--- DISTRIBUCIÓN INICIAL DE LA VARIABLE OBJETIVO (DESBALANCE) ---\n")
print(table(datos_fraude$fraude))
cat("\nProporción de clase minoritaria (Fraude):", round(mean(datos_fraude$fraude == "Fraude") * 100, 2), "%\n\n")

# ------------------------------------------------------------------------------
# 3. DIVISIÓN DE DATOS Y ESTRATEGIA OUT-OF-FOLD (CV) PARA EVITAR LEAKAGE
# ------------------------------------------------------------------------------
set.seed(2026)
split_datos <- initial_split(datos_fraude, prop = 0.80, strata = fraude)
train_df <- training(split_datos)
test_df  <- testing(split_datos)

set.seed(2026)
folds_cv <- vfold_cv(train_df, v = 5, strata = fraude)

cat("--- CONFIGURACIÓN DE MUESTREO ---\n")
cat("Entrenamiento:", nrow(train_df), "registros\n")
cat("Prueba:", nrow(test_df), "registros\n")
cat("Folds de Validación Cruzada:", length(folds_cv$splits), "folds\n\n")

# ------------------------------------------------------------------------------
# 4. PREPROCESAMIENTO Y MODELOS BASE (CANDIDATOS)
# ------------------------------------------------------------------------------
receta_base <- recipe(fraude ~ ., data = train_df) %>%
  update_role(id_cliente, new_role = "ID") %>%
  step_dummy(all_nominal_predictors()) %>%
  step_zv(all_predictors()) %>%
  step_normalize(all_numeric_predictors())

mod_log <- logistic_reg() %>% 
  set_engine("glm")

mod_rf <- rand_forest(trees = 300) %>% 
  set_engine("randomForest") %>% 
  set_mode("classification")

mod_xgb <- boost_tree(trees = 200, tree_depth = 4, learn_rate = 0.05) %>% 
  set_engine("xgboost") %>% 
  set_mode("classification")

ctrl_stack <- control_stack_resamples()

# ------------------------------------------------------------------------------
# 5. ENTRENAMIENTO DE MODELOS BASE CON PREDICCIONES OOF
# ------------------------------------------------------------------------------
cat("--- ENTRENANDO MODELOS BASE CON PREDICCIONES OUT-OF-FOLD ---\n")

wf_log <- workflow() %>% add_recipe(receta_base) %>% add_model(mod_log)
res_log <- fit_resamples(wf_log, resamples = folds_cv, control = ctrl_stack)

wf_rf <- workflow() %>% add_recipe(receta_base) %>% add_model(mod_rf)
res_rf <- fit_resamples(wf_rf, resamples = folds_cv, control = ctrl_stack)

wf_xgb <- workflow() %>% add_recipe(receta_base) %>% add_model(mod_xgb)
res_xgb <- fit_resamples(wf_xgb, resamples = folds_cv, control = ctrl_stack)

cat("Modelos candidatos (Regresión Logística, Random Forest, XGBoost) entrenados exitosamente.\n\n")

# ------------------------------------------------------------------------------
# 6. CONSTRUCCIÓN Y AJUSTE DEL META-MODELO (STACKING ENSEMBLE)
# ------------------------------------------------------------------------------
cat("--- ENSAMBLANDO META-MODELO (STACKING) CON PAQUETE STACKS ---\n")

modelo_stacking <- stacks() %>%
  add_candidates(res_log) %>%
  add_candidates(res_rf) %>%
  add_candidates(res_xgb) %>%
  blend_predictions(penalty = 10^seq(-3, -1, length.out = 30)) %>%
  fit_members()

cat("\n--- PONDERACIONES OPTIMIZADAS DEL META-MODELO ---\n")
print(modelo_stacking)

# ------------------------------------------------------------------------------
# 7. EVALUACIÓN Y COMPARACIÓN EN EL CONJUNTO DE PRUEBA INDEPENDIENTE
# ------------------------------------------------------------------------------
cat("\n--- EVALUACIÓN EN CONJUNTO DE PRUEBA (TEST SET) ---\n")

pred_stack <- predict(modelo_stacking, test_df, type = "prob") %>%
  bind_cols(test_df %>% select(fraude))

roc_stack <- roc(test_df$fraude, pred_stack$.pred_Fraude, levels = c("Normal", "Fraude"))

cat("AUC-ROC del Ensamble Stacking:", round(auc(roc_stack), 4), "\n\n")

# ------------------------------------------------------------------------------
# 8. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("===================================================================\n")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 10 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_10_mineria_datos.R\n")
cat("4. git commit -m \"Entrega Taller Clase 10 (Stacking & Desbalance) - Inti A. Olaya\"\n")
cat("5. git push origin main\n")
cat("===================================================================\n")
