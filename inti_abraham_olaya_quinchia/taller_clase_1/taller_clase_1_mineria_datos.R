# ==============================================================================
# CURSO DE MINERÍA DE DATOS
# TALLER CLASE 1: INTRODUCCIÓN A LA MINERÍA DE DATOS, KDD Y ENTORNO RSTUDIO
# ==============================================================================
# Descripción: Script de RStudio estructurado para el Taller 01 de Minería de Datos.
# Cubre el flujo de trabajo KDD/CRISP-DM, importación de datos, preprocesamiento
# inicial y la preparación del entorno para control de versiones con Git/GitHub.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. VERIFICACIÓN Y CARGA DE PAQUETES
# ------------------------------------------------------------------------------
paquetes <- c("tidyverse", "readr", "readxl", "janitor", "skimr", "knitr")

instalados <- rownames(installed.packages())
pendientes <- setdiff(paquetes, instalados)

if (length(pendientes) > 0) {
  message("Instalando paquetes pendientes: ", paste(pendientes, collapse = ", "))
  install.packages(pendientes)
}

invisible(lapply(paquetes, library, character.only = TRUE))
message("Entorno RStudio cargado exitosamente.")

# ------------------------------------------------------------------------------
# 2. FASE 1 Y 2 KDD: SELECCIÓN Y RECOLECCIÓN DE DATOS
# ------------------------------------------------------------------------------
# Creación/Simulación de conjunto de datos para la práctica de importación y exploración
set.seed(2026)
n_obs <- 500

datos_ejemplo <- tibble(
  id_estudiante = 1:n_obs,
  departamento = sample(c("Bogotá", "Antioquia", "Valle del Cauca", "Boya", "Chocó"), n_obs, replace = TRUE),
  estrato = sample(1:6, n_obs, replace = TRUE, prob = c(0.20, 0.30, 0.25, 0.15, 0.06, 0.04)),
  horas_estudio = round(pmax(0, rnorm(n_obs, mean = 10, sd = 3)), 1),
  edad = sample(17:30, n_obs, replace = TRUE),
  puntaje_evaluacion = round(pmin(500, pmax(0, rnorm(n_obs, mean = 280, sd = 45))))
)

# Introducción de valores faltantes intencionales
datos_ejemplo$horas_estudio[sample(1:n_obs, 25)] <- NA

# Guardar y volver a cargar usando readr para practicar lectura
dir.create("data", showWarnings = FALSE)
write_csv(datos_ejemplo, "data/estudiantes_taller1.csv")

# Lectura formal con readr
estudiantes <- read_csv("data/estudiantes_taller1.csv", show_col_types = FALSE)

# ------------------------------------------------------------------------------
# 3. COMPRENSIÓN Y EXPLORACIÓN INICIAL DE DATOS (CRISP-DM / EDA)
# ------------------------------------------------------------------------------
# Inspección de la estructura de la tabla
glimpse(estudiantes)

# Resumen estadístico básico
summary(estudiantes)

# Diagnóstico completo de calidad de datos usando skimr
skim(estudiantes)

# ------------------------------------------------------------------------------
# 4. FASE 3 KDD: PREPROCESAMIENTO Y LIMPIEZA DE DATOS
# ------------------------------------------------------------------------------
# Limpieza de nombres de columnas
estudiantes_limpio <- estudiantes %>%
  clean_names()

# Detección y conteo de valores faltantes (is.na)
colSums(is.na(estudiantes_limpio))

# Filtrado y selección con dplyr
estudiantes_filtrados <- estudiantes_limpio %>%
  filter(!is.na(horas_estudio)) %>%
  filter(estrato %in% c(1, 2, 3)) %>%
  select(id_estudiante, departamento, estrato, horas_estudio, puntaje_evaluacion)

# ------------------------------------------------------------------------------
# 5. FASE 4 KDD: TRANSFORMACIÓN Y EXTRACCIÓN DE PATRONES
# ------------------------------------------------------------------------------
# Agrupamiento y agregación con group_by() y summarise()
resumen_departamento <- estudiantes_filtrados %>%
  group_by(departamento) %>%
  summarise(
    n_estudiantes = n(),
    promedio_horas = mean(horas_estudio, na.rm = TRUE),
    promedio_puntaje = mean(puntaje_evaluacion, na.rm = TRUE),
    desviacion_puntaje = sd(puntaje_evaluacion, na.rm = TRUE)
  ) %>%
  arrange(desc(promedio_puntaje))

print("Resumen exploratorio por departamento:")
print(resumen_departamento)

# ------------------------------------------------------------------------------
# 6. INSTRUCCIONES DE CONTROL DE VERSIONES (GIT EN RSTUDIO)
# ------------------------------------------------------------------------------
# Flujo de trabajo en la terminal de RStudio para la entrega del Taller 1:
# 1. git status
# 2. git add .
# 3. git commit -m "Entrega taller_01 de Minería de Datos"
# 4. git push origin main
# ==============================================================================
