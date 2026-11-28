# ==============================================================================
# TALLER PRÁCTICO CLASE 13: CLASIFICACIÓN NO LINEAL (K-NN Y SVM)
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y CARGA DE LIBRERÍAS
# ------------------------------------------------------------------------------
pkgs <- c("tidyverse", "tidymodels", "kknn", "e1071", "kernlab", "pROC", "janitor", "knitr")
instalados <- pkgs %in% installed.packages()[, "Package"]
if (any(!instalados)) {
  install.packages(pkgs[!instalados])
}

library(tidyverse)
library(tidymodels)
library(kknn)
library(e1071)
library(kernlab)
library(pROC)
library(janitor)
library(knitr)

cat("===================================================================\n")
cat("TALLER CLASE 13 - CLASIFICACIÓN NO LINEAL: K-NN & SUPPORT VECTOR MACHINES\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DE DATASET SIMULADO CON FRONTERA NO LINEAL
# ------------------------------------------------------------------------------
set.seed(2026)
n <- 800

# Simulación de datos con patrón circular no separable linealmente
r <- sqrt(runif(n, 0.2, 3.5))
theta <- runif(n, 0, 2 * pi)

x1 <- r * cos(theta) + rnorm(n, sd = 0.15)
x2 <- r * sin(theta) + rnorm(n, sd = 0.15)

# Definición de clases: Núcleo (Clase A) vs Anillo Exterior (Clase B)
clase <- ifelse(r < 1.8, "Grupo_A", "Grupo_B")

df_clasificacion <- tibble(
  predictor_1 = x1,
  predictor_2 = x2,
  clase_target = factor(clase, levels = c("Grupo_A", "Grupo_B"))
)

cat("--- VISTA PREVIA DEL DATASET SIMULADO ---\n")
print(head(df_clasificacion))

# Partición de datos en Entrenamiento (75%) y Prueba (25%)
set.seed(2026)
split_datos <- initial_split(df_clasificacion, prop = 0.75, strata = clase_target)
train_df <- training(split_datos)
test_df  <- testing(split_datos)

cat("\nDimensiones Entrenamiento:", nrow(train_df), "| Prueba:", nrow(test_df), "\n")

# ------------------------------------------------------------------------------
# 3. K-VECINOS MÁS CERCANOS (K-NN) CON RECETAS Y ESTANDARIZACIÓN Z-SCORE
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- MODELADO CON K-NEAREST NEIGHBORS (K-NN) ---\n")

# Definición de la Receta (Normalización indispensable para distancias)
receta_knn <- recipe(clase_target ~ ., data = train_df) %>%
  step_normalize(all_numeric_predictors())

# Especificación del Modelo k-NN
spec_knn <- nearest_neighbor(neighbors = 7, weight_func = "triangular") %>%
  set_engine("kknn") %>%
  set_mode("classification")

# Workflow de Tidymodels
wf_knn <- workflow() %>%
  add_recipe(receta_knn) %>%
  add_model(spec_knn)

# Ajuste del modelo
fit_knn <- wf_knn %>% fit(data = train_df)

# Predicciones en Test
pred_knn <- predict(fit_knn, test_df) %>%
  bind_cols(predict(fit_knn, test_df, type = "prob")) %>%
  bind_cols(test_df)

cat("Matriz de Confusión k-NN (k = 7):\n")
print(conf_mat(pred_knn, truth = clase_target, estimate = .pred_class))

cat("\nMétricas de Evaluación k-NN:\n")
metrics_knn <- metrics(pred_knn, truth = clase_target, estimate = .pred_class)
print(metrics_knn)

# ------------------------------------------------------------------------------
# 4. SUPPORT VECTOR MACHINES (SVM) - KERNEL RADIAL (RBF) & LINEAL
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- MODELADO CON SUPPORT VECTOR MACHINES (SVM) ---\n")

# SVM con Kernel Lineal (Línea base)
svm_lineal <- svm(
  clase_target ~ predictor_1 + predictor_2,
  data = train_df,
  kernel = "linear",
  cost = 1,
  scale = TRUE,
  probability = TRUE
)

# SVM con Kernel Gaussiando RBF (No lineal)
svm_rbf <- svm(
  clase_target ~ predictor_1 + predictor_2,
  data = train_df,
  kernel = "radial",
  cost = 10,
  gamma = 0.5,
  scale = TRUE,
  probability = TRUE
)

# Evaluación de SVM RBF en Prueba
pred_prob_svm <- predict(svm_rbf, test_df, probability = TRUE)
probs_svm <- attr(pred_prob_svm, "probabilities")[, "Grupo_A"]

pred_svm_df <- test_df %>%
  mutate(
    pred_clase = pred_prob_svm,
    prob_Grupo_A = probs_svm
  )

cat("Matriz de Confusión SVM Kernel Radial (RBF):\n")
print(confusionMatrix(pred_svm_df$pred_clase, test_df$clase_target))

# ------------------------------------------------------------------------------
# 5. COMPARACIÓN DE DESEMPEÑO ROC / AUC ENTRE K-NN Y SVM
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- COMPARACIÓN DE CAPACIDAD DISCRIMINATIVA (CURVAS ROC) ---\n")

roc_knn <- roc(test_df$clase_target, pred_knn$.pred_Grupo_A, levels = c("Grupo_B", "Grupo_A"))
roc_svm <- roc(test_df$clase_target, pred_svm_df$prob_Grupo_A, levels = c("Grupo_B", "Grupo_A"))

cat("AUC k-NN: ", round(auc(roc_knn), 4), "\n")
cat("AUC SVM (RBF):", round(auc(roc_svm), 4), "\n")

# ------------------------------------------------------------------------------
# 6. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 13 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_13_mineria_datos.R\n")
cat("4. git commit -m \"Entrega Taller Clase 13 (Clasificación No Lineal: k-NN y SVM) - Inti A. Olaya\"\n")
cat("5. git push origin main\n")
cat("===================================================================\n")
