# ==============================================================================
# TALLER PRÁCTICO CLASE 8: ÁRBOLES DE DECISIÓN, PODA Y PREVENCIÓN DE OVERFITTING
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y LIBRERÍAS
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(tidyverse)
  library(rpart)
  library(rpart.plot)
  library(tidymodels)
  library(pROC)
  library(knitr)
})

set.seed(2026)

cat("===================================================================\n")
cat("TALLER CLASE 8 - ÁRBOLES DE DECISIÓN & PODAS (CART)\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DEL DATASET: DESERCIÓN ESTUDIANTIL
# ------------------------------------------------------------------------------
# Caso de negocio: Predicción de deserción académica (Bienestar Universitario)
n <- 1200
datos_desercion <- tibble(
  id_estudiante = 1:n,
  papa = round(rnorm(n, mean = 3.4, sd = 0.5), 2) %>% pmin(5.0) %>% pmax(0.0),
  creditos_perdidos = rpois(n, lambda = 3),
  estrato = sample(1:6, n, replace = TRUE, prob = c(0.25, 0.30, 0.25, 0.10, 0.06, 0.04)),
  horas_trabajo = rpois(n, lambda = 12),
  distancia_km = round(runif(n, 1, 45), 1),
  semestre = sample(1:10, n, replace = TRUE),
  retiro_registrado = sample(c("Sí", "No"), n, replace = TRUE, prob = c(0.15, 0.85)) # Variable fuga de datos
) %>%
  mutate(
    # Generación de la variable objetivo 'deserta' basada en riesgo no lineal
    prob_deserta = 1 / (1 + exp(-(-1.5 - 1.2 * papa + 0.35 * creditos_perdidos + 0.08 * horas_trabajo - 0.2 * estrato))),
    deserta = factor(if_else(runif(n) < prob_deserta, "Sí", "No"), levels = c("No", "Sí"))
  ) %>%
  select(-prob_deserta)

cat("--- ESTRUCTURA DEL DATASET DE DESERCIÓN ---\n")
glimpse(datos_desercion)
cat("\nBalance de clases en variable objetivo (deserta):\n")
print(table(datos_desercion$deserta))

# ------------------------------------------------------------------------------
# 3. DIVISIÓN HONESTA DE DATOS Y MANEJO DE FUGA DE INFORMACIÓN (DATA LEAKAGE)
# ------------------------------------------------------------------------------
# Separación de datos en entrenamiento (70%) y prueba (30%)
split_datos <- initial_split(datos_desercion, prop = 0.70, strata = deserta)
train_df <- training(split_datos)
test_df  <- testing(split_datos)

# Exclusión explícita de identificadores e indicadores del futuro (Data Leakage)
# 'id_estudiante' memoriza la tabla; 'retiro_registrado' es consecuencia directa de la deserción.
train_clean <- train_df %>% select(-id_estudiante, -retiro_registrado)
test_clean  <- test_df  %>% select(-id_estudiante, -retiro_registrado)

cat("\n===================================================================\n")
cat("--- PREVENCIÓN DE DATA LEAKAGE Y PARTISIÓN HONESTA ---\n")
cat("Muestra de entrenamiento (70%):", nrow(train_clean), "registros\n")
cat("Muestra de prueba (30%):       ", nrow(test_clean), "registros\n")

# ------------------------------------------------------------------------------
# 4. CONSTRUCCIÓN Y VISUALIZACIÓN DEL ÁRBOL INICIAL (rpart)
# ------------------------------------------------------------------------------
arbol_base <- rpart(
  formula = deserta ~ .,
  data = train_clean,
  method = "class",
  control = rpart.control(cp = 0.01, minsplit = 20, maxdepth = 30)
)

cat("\n===================================================================\n")
cat("--- REGLAS EXTRAÍDAS DEL ÁRBOL INICIAL ---\n")
print(rpart.rules(arbol_base, cover = TRUE))

cat("\n--- IMPORTANCIA DE VARIABLES (REDUCCIÓN DE IMPUREZA GINI) ---\n")
imp_var <- round(100 * arbol_base$variable.importance / sum(arbol_base$variable.importance), 2)
print(imp_var)

# ------------------------------------------------------------------------------
# 5. DIAGNÓSTICO DE OVERFITTING Y PODA DEL ÁRBOL (PRUNING CON COMPLEXITY PARAMETER)
# ------------------------------------------------------------------------------
# Forzar crecimiento completo (cp = 0) para evaluar el sobreajuste
arbol_profundo <- rpart(
  formula = deserta ~ .,
  data = train_clean,
  method = "class",
  control = rpart.control(cp = 0, minsplit = 2, minbucket = 1)
)

# Evaluación de la exactitud en entrenamiento vs prueba (Árbol Profundo)
pred_train_prof <- predict(arbol_profundo, train_clean, type = "class")
pred_test_prof  <- predict(arbol_profundo, test_clean, type = "class")

acc_train_prof <- mean(pred_train_prof == train_clean$deserta)
acc_test_prof  <- mean(pred_test_prof == test_clean$deserta)

cat("\n===================================================================\n")
cat("--- DIAGNÓSTICO DE SOBREAJUSTE (ÁRBOL SIN PODAR) ---\n")
cat("Exactitud en entrenamiento:", round(acc_train_prof * 100, 2), "%\n")
cat("Exactitud en prueba (test):", round(acc_test_prof * 100, 2), "%\n")
cat("Brecha de sobreajuste:     ", round((acc_train_prof - acc_test_prof) * 100, 2), "puntos %\n")

# Selección del parámetro cp óptimo según el error de validación cruzada (xerror)
tabla_cp <- arbol_profundo$cptable
cp_opt <- tabla_cp[which.min(tabla_cp[, "xerror"]), "CP"]
cat("\nCP óptimo seleccionado por validación cruzada:", round(cp_opt, 5), "\n")

# Poda del árbol con el cp óptimo
arbol_podado <- prune(arbol_profundo, cp = cp_opt)

pred_test_podado <- predict(arbol_podado, test_clean, type = "class")
acc_test_podado  <- mean(pred_test_podado == test_clean$deserta)

cat("Exactitud en prueba (Árbol Podado):", round(acc_test_podado * 100, 2), "%\n")

# ------------------------------------------------------------------------------
# 6. EVALUACIÓN DE DESEMPEÑO Y MATRIZ DE CONFUSIÓN
# ------------------------------------------------------------------------------
matriz_conf <- table(Real = test_clean$deserta, Predicho = pred_test_podado)
cat("\n===================================================================\n")
cat("--- MATRIZ DE CONFUSIÓN (ÁRBOL PODADO EN TEST) ---\n")
print(matriz_conf)

sensibilidad <- matriz_conf["Sí", "Sí"] / sum(matriz_conf["Sí", ])
especificidad <- matriz_conf["No", "No"] / sum(matriz_conf["No", ])

cat("\n--- MÉTRICAS DE CLASIFICACIÓN ---\n")
cat("Sensibilidad (Recall Sí):", round(sensibilidad * 100, 2), "%\n")
cat("Especificidad (Recall No):", round(especificidad * 100, 2), "%\n")

# Cálculo de probabilidades y curva ROC
prob_test_podado <- predict(arbol_podado, test_clean, type = "prob")[, "Sí"]
roc_obj <- roc(test_clean$deserta, prob_test_podado, levels = c("No", "Sí"), quiet = TRUE)
cat("Área bajo la curva ROC (AUC-ROC):", round(auc(roc_obj), 4), "\n")

# ------------------------------------------------------------------------------
# 7. TUNING CON PIPELINES DE TIDYMODELS
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- OPTIMIZACIÓN REPRODUCIBLE CON TIDYMODELS ---\n")

tree_spec <- decision_tree(
  cost_complexity = tune(),
  tree_depth = tune(),
  min_n = tune()
) %>%
  set_engine("rpart") %>%
  set_mode("classification")

tree_wf <- workflow() %>%
  add_recipe(recipe(deserta ~ ., data = train_clean)) %>%
  add_model(tree_spec)

folds <- vfold_cv(train_clean, v = 5, strata = deserta)

tree_res <- tune_grid(
  tree_wf,
  resamples = folds,
  grid = 10,
  metrics = metric_set(accuracy, roc_auc)
)

best_tree <- select_best(tree_res, metric = "roc_auc")
cat("Mejores hiperparámetros encontrados:\n")
print(best_tree)

final_wf <- finalize_workflow(tree_wf, best_tree)
final_fit <- fit(final_wf, data = train_clean)

# ------------------------------------------------------------------------------
# 8. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 8 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_08_mineria_datos.R\n")
cat("4. git commit -m \"Entrega Taller Clase 8 (Arboles de Decision) - Inti A. Olaya\"\n")
cat("5. git push origin main\n")
cat("===================================================================\n")
