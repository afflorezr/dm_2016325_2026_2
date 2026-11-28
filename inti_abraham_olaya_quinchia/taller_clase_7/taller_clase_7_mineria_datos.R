# ==============================================================================
# TALLER PRÁCTICO CLASE 7: MODELOS DE REGRESIÓN LINEAL, LOGÍSTICA Y PREPROCESAMIENTO
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# 1. CONFIGURACIÓN DEL ENTORNO Y LIBRERÍAS
# ------------------------------------------------------------------------------
librerias <- c("tidyverse", "car", "pROC", "tidymodels", "janitor", "knitr")
nuevas_librerias <- librerias[!(librerias %in% installed.packages()[, "Package"])]
if (length(nuevas_librerias) > 0) install.packages(nuevas_librerias)

library(tidyverse)
library(car)
library(pROC)
library(tidymodels)
library(janitor)
library(knitr)

cat("===================================================================\n")
cat("TALLER CLASE 7 - REGRESIÓN LINEAL, LOGÍSTICA & DIAGNÓSTICO DE MODELOS\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN Y SIMULACIÓN DEL DATASET REPRODUCIBLE
# ------------------------------------------------------------------------------
set.seed(2026)
n <- 400

# Simulación de variables explicativas
educacion <- runif(n, 5, 20)                        # Años de educación (5 a 20)
experiencia <- runif(n, 0, 30)                      # Años de experiencia (0 a 30)
genero <- factor(sample(c("Femenino", "Masculino"), n, replace = TRUE))
sector <- factor(sample(c("Publico", "Privado", "Independiente"), n, replace = TRUE))
puntaje_saber11 <- rnorm(n, 300, 50)                # Puntaje Saber 11

# Variable Respuesta Continua: Ingreso Mensual (COP)
ingreso <- 500000 + 380000 * educacion + 60000 * experiencia - 150000 * (genero == "Masculino") + rnorm(n, 0, 500000)

# Variable Respuesta Binaria: Deserción Laboral / Educativa (0 = No, 1 = Sí)
logit_desercion <- 2.5 - 0.015 * puntaje_saber11 - 0.08 * educacion + 0.5 * (sector == "Independiente")
prob_desercion <- 1 / (1 + exp(-logit_desercion))
desercion <- rbinom(n, 1, prob_desercion)

datos_clase7 <- tibble(
  ingreso = ingreso,
  desercion = desercion,
  educacion = educacion,
  experiencia = experiencia,
  genero = genero,
  sector = sector,
  puntaje_saber11 = puntaje_saber11
)

cat("--- VISTA PREVIA DEL DATASET GENERAL (Clase 7) ---\n")
print(head(datos_clase7, 5))

# ------------------------------------------------------------------------------
# 3. REGRESIÓN LINEAL MÚLTIPLE (MCO) Y DIAGNÓSTICO DE SUPUESTOS
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE 1: REGRESIÓN LINEAL MÚLTIPLE (MCO) ---\n")

mod_lineal <- lm(ingreso ~ educacion + experiencia + genero + sector, data = datos_clase7)

cat("\nResumen del Modelo Lineal:\n")
print(summary(mod_lineal))

cat("\n--- EVALUACIÓN DE MULTICOLINEALIDAD (VIF) ---\n")
vif_valores <- car::vif(mod_lineal)
print(round(vif_valores, 2))

# Diagnóstico de supuestos: Gráficos de diagnóstico
par(mfrow = c(2, 2))
plot(mod_lineal, main = "Diagnóstico MCO - Inti A. Olaya")
par(mfrow = c(1, 1))

# ------------------------------------------------------------------------------
# 4. REGRESIÓN LOGÍSTICA BINARIA (GLM) Y ODDS RATIOS
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE 2: REGRESIÓN LOGÍSTICA BINARIA (GLM BINOMIAL) ---\n")

mod_logistico <- glm(desercion ~ puntaje_saber11 + educacion + sector, 
                     data = datos_clase7, 
                     family = binomial(link = "logit"))

cat("\nResumen del Modelo Logístico:\n")
print(summary(mod_logistico))

cat("\n--- ESTIMACIÓN DE ODDS RATIOS (OR) E INTERVALOS DE CONFIANZA (95%) ---\n")
or_tabla <- exp(cbind(OR = coef(mod_logistico), confint(mod_logistico)))
print(round(or_tabla, 3))

# ------------------------------------------------------------------------------
# 5. EVALUACIÓN DE RENDIMIENTO Y CURVA ROC / AUC
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE 3: EVALUACIÓN DEL MODELO LOGÍSTICO (ROC Y MATRIZ DE CONFUSIÓN) ---\n")

datos_clase7$prob_pred <- predict(mod_logistico, type = "response")
datos_clase7$clase_pred <- ifelse(datos_clase7$prob_pred >= 0.5, 1, 0)

matriz_confusion <- table(Real = datos_clase7$desercion, Predicho = datos_clase7$clase_pred)
cat("\nMatriz de Confusión:\n")
print(matriz_confusion)

accuracy <- sum(diag(matriz_confusion)) / sum(matriz_confusion)
sensibilidad <- matriz_confusion[2, 2] / sum(matriz_confusion[2, ])
especificidad <- matriz_confusion[1, 1] / sum(matriz_confusion[1, ])

cat(sprintf("\nMétricas de Clasificación:\n- Accuracy: %.3f\n- Sensibilidad: %.3f\n- Especificidad: %.3f\n", 
            accuracy, sensibilidad, especificidad))

roc_obj <- pROC::roc(datos_clase7$desercion, datos_clase7$prob_pred, quiet = TRUE)
cat(sprintf("Área Bajo la Curva (AUC-ROC): %.3f\n", pROC::auc(roc_obj)))

plot(roc_obj, col = "#1b4d2e", lwd = 2, main = paste("Curva ROC (Clase 7) | AUC =", round(pROC::auc(roc_obj), 3)))
abline(a = 0, b = 1, lty = 2, col = "#94a3b8")

# ------------------------------------------------------------------------------
# 6. PIPELINES DE PREPROCESAMIENTO CON TIDYMODELS / RECIPES
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- PARTE 4: PIPELINES DE PREPROCESAMIENTO CON RECIPES ---\n")

set.seed(2026)
data_split <- initial_split(datos_clase7, prop = 0.8, strata = desercion)
train_data <- training(data_split)
test_data  <- testing(data_split)

receta_modelo <- recipe(desercion ~ puntaje_saber11 + educacion + experiencia + sector + genero, data = train_data) %>%
  step_impute_median(all_numeric_predictors()) %>%
  step_normalize(all_numeric_predictors()) %>%
  step_dummy(all_nominal_predictors()) %>%
  prep()

train_procesado <- bake(receta_modelo, new_data = NULL)
test_procesado  <- bake(receta_modelo, new_data = test_data)

cat("Dimensiones Dataset Procesado (Train):", dim(train_procesado), "\n")
cat("Variables codificadas en la receta:\n")
print(colnames(train_procesado))

# ------------------------------------------------------------------------------
# 7. CONTROL DE VERSIONES GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 7 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_07_mineria_datos.R\n")
cat("4. git commit -m \"Entrega Taller Clase 7 (Regresion y Preprocesamiento) - Inti A. Olaya\"\n")
cat("5. git push origin main\n")
cat("===================================================================\n")
