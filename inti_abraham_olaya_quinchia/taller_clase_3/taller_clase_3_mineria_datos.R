# ==============================================================================
# TALLER PRÁCTICO CLASE 3: PREPROCESAMIENTO, DATOS FALTANTES E IMPUTACIÓN EN R
# Asignatura: Minería de Datos
# Herramientas: RStudio, Tidyverse, Naniar, Visdat, Tidymodels (Recipes)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. INSTALACIÓN Y CARGA DE LIBRERÍAS
# ------------------------------------------------------------------------------
paquetes <- c("tidyverse", "naniar", "visdat", "tidymodels", "recipes", "janitor", "knitr")
paquetes_faltantes <- paquetes[!(paquetes %in% installed.packages()[, "Package"])]

if(length(paquetes_faltantes) > 0) {
  install.packages(paquetes_faltantes)
}

library(tidyverse)
library(naniar)
library(visdat)
library(tidymodels)
library(recipes)
library(janitor)
library(knitr)

cat("=== LIBRERÍAS CARGADAS EXITOSAMENTE ===\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DE DATASET SIMULADO CON PATRONES DE DATOS FALTANTES
# ------------------------------------------------------------------------------
set.seed(2024)
n <- 500

datos_raw <- tibble(
  id_cliente = paste0("CLI-", sprintf("%03d", 1:n)),
  ciudad = sample(c("Bogotá", "Medellín", "Cali", "Barranquilla"), n, replace = TRUE, prob = c(0.35, 0.25, 0.25, 0.15)),
  edad = pmax(18, round(rnorm(n, mean = 38, sd = 12))),
  ingreso_mensual = rnorm(n, mean = 2500000 + 40000 * edad, sd = 600000),
  gasto_total = ingreso_mensual * runif(n, 0.3, 0.7),
  categoria_cliente = sample(c("Estándar", "Premium", "VIP"), n, replace = TRUE, prob = c(0.6, 0.3, 0.1)),
  reclamaciones = rpois(n, lambda = 1.2),
  churn = rbinom(n, size = 1, prob = 0.2)
)

# Inducir valores faltantes (NA) simulando distintos mecanismos (MAR / MCAR)
datos_incompletos <- datos_raw

# NA en edad (MCAR - al azar)
idx_edad_na <- sample(1:n, size = round(n * 0.10))
datos_incompletos$edad[idx_edad_na] <- NA

# NA en ingreso_mensual (MAR - dependiente de ciudad y edad)
riesgo_na_ingreso <- datos_incompletos$ciudad == "Cali" & (is.na(datos_incompletos$edad) | datos_incompletos$edad > 40)
datos_incompletos$ingreso_mensual[rbinom(n, 1, ifelse(riesgo_na_ingreso, 0.50, 0.08)) == 1] <- NA

# NA en gasto_total (dependiente del ingreso)
datos_incompletos$gasto_total[is.na(datos_incompletos$ingreso_mensual) | rbinom(n, 1, 0.05) == 1] <- NA

# NA en categoría_cliente (categórico)
idx_cat_na <- sample(1:n, size = round(n * 0.07))
datos_incompletos$categoria_cliente[idx_cat_na] <- NA

cat("\nDataset simulado creado con dimensión:", dim(datos_incompletos), "\n")

# ------------------------------------------------------------------------------
# 3. DIAGNÓSTICO Y VISUALIZACIÓN DE DATOS FALTANTES (Naniar & Visdat)
# ------------------------------------------------------------------------------
cat("\n=== DIAGNÓSTICO DE DATOS FALTANTES ===\n")

# Resumen numérico de missingness por variable
resumen_na <- miss_var_summary(datos_incompletos)
print(resumen_na)

# Mapa de calor de missingness en la tabla entera
# vis_miss(datos_incompletos)

# Gráfico de barras de valores ausentes por variable
# gg_miss_var(datos_incompletos)

# Crear matriz de sombra (Shadow Matrix) para evaluar correlaciones entre datos faltantes
datos_shadow <- bind_shadow(datos_incompletos)
head(datos_shadow)

# Evaluando si el faltante en ingreso se relaciona con la ciudad
tabla_cruzada_na <- datos_shadow %>%
  count(ciudad, ingreso_mensual_NA) %>%
  group_by(ciudad) %>%
  mutate(prop_missing = n / sum(n))

print(tabla_cruzada_na)

# ------------------------------------------------------------------------------
# 4. IMPUTACIÓN DE DATOS FALTANTES MEDIANTE PIPELINES CON RECIPES (TIDYMODELS)
# ------------------------------------------------------------------------------
cat("\n=== PIPELINE DE IMPUTACIÓN Y TRANSFORMACIÓN CON RECIPES ===\n")

# Divisón Train / Test para evitar Data Leakage (Fuga de Información)
set.seed(123)
split_datos <- initial_split(datos_incompletos, prop = 0.80, strata = churn)
datos_train <- training(split_datos)
datos_test  <- testing(split_datos)

# Definición de la receta de preprocesamiento (Recipe)
receta_imputacion <- recipe(churn ~ ., data = datos_train) %>%
  # 1. Eliminar identificadores no analíticos
  step_rm(id_cliente) %>%
  # 2. Crear indicadores booleanos de missingness antes de imputar
  step_indicate_na(ingreso_mensual, gasto_total) %>%
  # 3. Imputar variables numéricas continuas con la mediana
  step_impute_median(all_numeric_predictors()) %>%
  # 4. Imputar variables categóricas con la moda (most_frequent)
  step_impute_mode(all_nominal_predictors()) %>%
  # 5. Normalizar predictores numéricos (Z-Score)
  step_normalize(all_numeric_predictors()) %>%
  # 6. Codificación One-Hot para variables cualitativas
  step_dummy(all_nominal_predictors())

# Entrenar la receta sobre los datos de entrenamiento (Prep)
receta_preparada <- prep(receta_imputacion, training = datos_train)

# Aplicar la receta sobre Train y Test (Bake)
train_procesado <- bake(receta_preparada, new_data = NULL)
test_procesado  <- bake(receta_preparada, new_data = datos_test)

cat("Verificación de NAs en Train Procesado:", sum(!complete.cases(train_procesado)), "\n")
cat("Verificación de NAs en Test Procesado:", sum(!complete.cases(test_procesado)), "\n")
cat("Dimensiones finales de Train:", dim(train_procesado), "\n")

# ------------------------------------------------------------------------------
# 5. CONTROL DE VERSIONES CON GIT & GITHUB
# ------------------------------------------------------------------------------
# Ejecute la siguiente secuencia en la Terminal de RStudio / Bash:
# git status
# git add taller_03_mineria_datos.R
# git commit -m "Feat: Agregar script del Taller Clase 3 sobre Diagnóstico e Imputación de NAs"
# git push origin main
