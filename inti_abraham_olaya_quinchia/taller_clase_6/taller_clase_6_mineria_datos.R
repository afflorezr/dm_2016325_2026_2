# Taller 06 R script
# ==============================================================================
# TALLER PRÁCTICO CLASE 6: ANÁLISIS ESTADÍSTICO DE TABLAS DE CONTINGENCIA
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-11
# ==============================================================================

library(tidyverse)
library(janitor)
library(vcd)
library(knitr)

cat("===================================================================
")
cat("TALLER CLASE 6 - TABLAS DE CONTINGENCIA & PRUEBAS DE INDEPENDENCIA
")
cat("Autor: Inti A. Olaya
")
cat("===================================================================

")

# ------------------------------------------------------------------------------
# 2. PRUEBA DE CHI-CUADRADO DE PEARSON & RESIDUOS ESTANDARIZADOS
# ------------------------------------------------------------------------------
tab_educ_internet <- matrix(
  c(180, 40,
    210, 95,
    60,  150),
  nrow = 3, byrow = TRUE,
  dimnames = list(
    Educacion = c("Sin bachillerato", "Bachillerato", "Superior"),
    Internet  = c("Sin acceso", "Con acceso")
  )
)

cat("--- TABLA DE CONTINGENCIA: EDUCACIÓN VS ACCESO A INTERNET ---
")
print(tab_educ_internet)

prueba_chi <- chisq.test(tab_educ_internet, correct = FALSE)
cat("
--- RESULTADOS PRUEBA CHI-CUADRADO DE PEARSON ---
")
print(prueba_chi)

cat("
--- FRECUENCIAS ESPERADAS ---
")
print(round(prueba_chi$expected, 1))

cat("
--- RESIDUOS ESTANDARIZADOS (stdres) ---
")
print(round(prueba_chi$stdres, 2))

# ------------------------------------------------------------------------------
# 3. DATOS EMPAREJADOS Y PRUEBA DE MCNEMAR (TABLAS 2x2 CUADRADAS)
# ------------------------------------------------------------------------------
antes_despues <- matrix(
  c(55, 18,
    7,  40),
  nrow = 2, byrow = TRUE,
  dimnames = list(
    Antes   = c("En desacuerdo", "De acuerdo"),
    Despues = c("En desacuerdo", "De acuerdo")
  )
)

cat("
===================================================================
")
cat("--- PRUEBA DE MCNEMAR PARA DATOS EMPAREJADOS (ANTES VS DESPUÉS) ---
")
print(antes_despues)

prueba_mcnemar <- mcnemar.test(antes_despues, correct = FALSE)
cat("
--- RESULTADOS PRUEBA DE MCNEMAR ---
")
print(prueba_mcnemar)

# ------------------------------------------------------------------------------
# 4. TABLAS MULTIWAY Y PARADOJA DE SIMPSON
# ------------------------------------------------------------------------------
exito_3way <- array(
  c(90, 110,  45, 155,
    20,  80,   5,  95),
  dim = c(2, 2, 2),
  dimnames = list(
    Resultado     = c("Exito", "Fracaso"),
    Procedimiento = c("Procedimiento A", "Procedimiento B"),
    Estado        = c("Buen estado", "Mal estado")
  )
)

cat("
===================================================================
")
cat("--- DEMOSTRACIÓN DE LA PARADOJA DE SIMPSON ---
")

cat("
1. Proporciones en Pacientes en BUEN ESTADO:
")
print(prop.table(exito_3way[,,1], margin = 2))

cat("
2. Proporciones en Pacientes en MAL ESTADO:
")
print(prop.table(exito_3way[,,2], margin = 2))

tabla_marginal <- margin.table(exito_3way, c(1, 2))
cat("
3. Tabla Marginal Colapsada (Ignorando Estado del Paciente):
")
print(tabla_marginal)
cat("
Proporciones Marginales Colapsadas:
")
print(prop.table(tabla_marginal, margin = 2))

# ------------------------------------------------------------------------------
# 5. CASO DE CUASI-INDEPENDENCIA Y EXCLUSIÓN DE DIAGONAL (MOVILIDAD SOCIAL)
# ------------------------------------------------------------------------------
movilidad <- matrix(
  c(320, 48, 12,
    65, 280, 55,
    18,  70, 260),
  nrow = 3, byrow = TRUE,
  dimnames = list(
    Padre = c("Baja", "Media", "Alta"),
    Hijo  = c("Baja", "Media", "Alta")
  )
)

cat("
===================================================================
")
cat("--- TABLA DE MOVILIDAD SOCIAL SOCIOECONÓMICA ---
")
print(movilidad)

movilidad_sin_diag <- movilidad
diag(movilidad_sin_diag) <- 0

cat("
--- CHI-CUADRADO EXCLUYENDO LA DIAGONAL (CUASI-INDEPENDENCIA) ---
")
prueba_cuasi <- chisq.test(movilidad_sin_diag, simulate.p.value = TRUE, B = 2000)
print(prueba_cuasi)

# ------------------------------------------------------------------------------
# 6. VERSIONADO Y CONTROL DE CAMBIOS GIT (INSTRUCCIONES TERMINAL)
# ------------------------------------------------------------------------------
cat("
===================================================================
")
cat("--- COMANDOS DE GIT PARA ENTREGA DE TALLER CLASE 6 ---
")
cat("1. cd ~/mineria_datos_course
")
cat("2. git status
")
cat("3. git add taller_06_mineria_datos.R
")
cat("4. git commit -m \"Entrega Taller Clase 6 (Tablas Contingencia) - Inti A. Olaya\"
")
cat("5. git push origin main
")
cat("===================================================================
")
