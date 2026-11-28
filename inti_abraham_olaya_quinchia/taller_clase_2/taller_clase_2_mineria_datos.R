# ==============================================================================
# TALLER PRÁCTICO - CLASE 2: TIPOS, ESTRUCTURAS Y ALTA DIMENSIONALIDAD
# Curso: Minería de Datos - Universidad Nacional de Colombia
# Script para RStudio: taller_02_mineria_datos.R
# ==============================================================================
#
# OBJETIVOS DEL TALLER:
# 1. Parsear y aplanar datos semiestructurados (JSON) provenientes de APIs.
# 2. Trabajar con matrices densas y dispersas (Matrix::sparseMatrix) evaluando
#    la eficiencia en memoria.
# 3. Construir e inspeccionar tensores/arreglos multidimensionales (array 3D).
# 4. Aplicar escalado y Análisis de Componentes Principales (PCA) para
#    reducción de dimensionalidad sobre matrices de diseño.
# 5. Flujo de entrega con Git/GitHub.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y CARGA DE LIBRERÍAS
# ------------------------------------------------------------------------------

paquetes <- c("tidyverse", "jsonlite", "Matrix", "janitor", "skimr", "knitr")

# Instalación condicional de paquetes faltantes
pendientes <- setdiff(paquetes, rownames(installed.packages()))
if (length(pendientes) > 0) {
  install.packages(pendientes)
}

# Carga de paquetes en el entorno
library(tidyverse)
library(jsonlite)
library(Matrix)
library(janitor)
library(skimr)
library(knitr)

message("Entorno configurado correctamente para la Clase 2.")

# ------------------------------------------------------------------------------
# 2. PARSEO Y APLANADO DE DATOS SEMIESTRUCTURADOS (JSON)
# ------------------------------------------------------------------------------
# En minería de datos, la información proveniente de APIs suele llegar en JSON.

json_datos <- '
[
  {"municipio": "Bogotá", "año": 2023, "indicadores": {"desempleo": 10.5, "pobreza": 31.2}},
  {"municipio": "Medellín", "año": 2023, "indicadores": {"desempleo": 8.9, "pobreza": 27.5}},
  {"municipio": "Cali", "año": 2023, "indicadores": {"desempleo": 12.1, "pobreza": 35.8}},
  {"municipio": "Barranquilla", "año": 2023, "indicadores": {"desempleo": 9.4, "pobreza": 29.1}}
]
'

# 2.1 Parsear la cadena JSON a estructura de R
datos_raw <- jsonlite::fromJSON(json_datos)
print(str(datos_raw))

# 2.2 Aplanado (Flattening) a Tibble
datos_tbl <- as_tibble(datos_raw) %>%
  mutate(
    desempleo = indicadores$desempleo,
    pobreza = indicadores$pobreza
  ) %>%
  select(-indicadores)

cat("\n--- TABLA RESULTANTE DEL PARSEO DE JSON ---\n")
print(datos_tbl)

# ------------------------------------------------------------------------------
# 3. MATRICES DENSAS VS. DISPERSAS (SPARSITY Y USO DE MEMORIA)
# ------------------------------------------------------------------------------
# Simulación de una matriz Documento-Término (DTM) típica en minería de texto.

set.seed(2026)
n_docs <- 1000
n_terminos <- 5000

# Matriz densa (~99.9% ceros)
dtm_densa <- matrix(rpois(n_docs * n_terminos, lambda = 0.001), nrow = n_docs)

# Matriz dispersa (Compressed Sparse Column - dgCMatrix)
dtm_sparse <- Matrix::Matrix(dtm_densa, sparse = TRUE)

# Comparación de almacenamiento en memoria
tamano_densa <- object.size(dtm_densa)
tamano_sparse <- object.size(dtm_sparse)

cat("\n--- COMPARACIÓN DE EFICIENCIA EN MEMORIA ---\n")
cat("Tamaño Matriz Densa:   ", format(tamano_densa, units = "Mb"), "\n")
cat("Tamaño Matriz Dispersa:", format(tamano_sparse, units = "Mb"), "\n")
cat("Factor de Ahorro:       ", round(as.numeric(tamano_densa) / as.numeric(tamano_sparse), 1), "x\n")

# Inspect de la estructura interna
print(str(dtm_sparse))

# ------------------------------------------------------------------------------
# 4. ARREGLOS MULTIDIMENSIONALES (TENSORES)
# ------------------------------------------------------------------------------
# Representación de un panel tridimensional: 32 Ciudades x 12 Meses x 5 Indicadores

n_ciudades <- 32L
n_meses <- 12L
n_indicadores <- 5L

panel_tensor <- array(
  rnorm(n_ciudades * n_meses * n_indicadores, mean = 50, sd = 10),
  dim = c(n_ciudades, n_meses, n_indicadores),
  dimnames = list(
    Ciudad = paste0("C", sprintf("%02d", seq_len(n_ciudades))),
    Mes = month.abb,
    Indicador = c("PIB", "Desempleo", "Inflacion", "Exportaciones", "Pobreza")
  )
)

cat("\n--- ESTRUCTURA DEL TENSOR MULTIDIMENSIONAL ---\n")
cat("Dimensiones:", dim(panel_tensor), "\n")
cat("Muestra de datos (C01 - C03, Meses Ene-Jun, Indicador PIB):\n")
print(panel_tensor[1:3, 1:6, "PIB"])

# ------------------------------------------------------------------------------
# 5. REDUCCIÓN DE DIMENSIONALIDAD (PCA SOBRE MATRIZ DE DISEÑO)
# ------------------------------------------------------------------------------
# Mitigación de la "Maldición de la Dimensionalidad" usando prcomp.

# Matriz de predicores numéricos
data(iris)
X_matriz <- as.matrix(iris[, 1:4])

# 5.1 Centrado y Escalado previo a PCA (scale)
X_scaled <- scale(X_matriz)

# 5.2 Análisis de Componentes Principales
pca_out <- prcomp(X_matriz, scale. = TRUE)

# Cálculo de Varianza Explicada por cada Componente
var_explicada <- (pca_out$sdev^2) / sum(pca_out$sdev^2)
var_acumulada <- cumsum(var_explicada)

resumen_pca <- tibble(
  Componente = paste0("PC", 1:length(var_explicada)),
  Varianza_Explicada = round(var_explicada, 4),
  Varianza_Acumulada = round(var_acumulada, 4)
)

cat("\n--- RESULTADOS DEL PCA ---\n")
print(resumen_pca)

# ------------------------------------------------------------------------------
# 6. FLUJO DE TRABAJO CON GIT Y GITHUB (PASOS PARA LA ENTREGA)
# ------------------------------------------------------------------------------
# Comandos a ejecutar en el Terminal de RStudio para publicar la tarea:
#
# 1. Estado y actualización:
#    git status
#    git pull origin main
#
# 2. Confirmación de cambios:
#    git add taller_02_mineria_datos.R
#    git commit -m "Entrega Taller Clase 2: Estructuras, Sparsity y PCA"
#
# 3. Publicación en GitHub:
#    git push origin main
# ==============================================================================
