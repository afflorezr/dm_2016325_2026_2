# =============================================================================
# Minería de Datos — Clase 8 - practica 7: Git, Valores Faltantes e Integración
# Taller: Ejercicios de práctica (valores faltantes)
# =============================================================================

# ---- Paquetes ---------------------------------------------------------------
paquetes <- c("dplyr", "tidyr", "ggplot2", "rpart", "tidymodels", "ipred", "naniar")
faltantes <- paquetes[!paquetes %in% rownames(installed.packages())]
if (length(faltantes) > 0) install.packages(faltantes)

library(dplyr)
library(tidyr)
library(ggplot2)


# =============================================================================
# EJERCICIO 1: Diagnóstico de valores faltantes
# =============================================================================

# ---- Datos del enunciado (copiados tal cual) --------------------------------
# Se guardan copias de ingreso y gasto ANTES de borrar valores. Copiar no
# consume números aleatorios, así que la secuencia de la semilla es idéntica
# a la del enunciado y 'datos' sale exactamente igual.
set.seed(2024); n <- 400
ciudad  <- sample(c("Bogotá", "Medellín", "Cali", "Barranquilla"),
                  n, TRUE, c(.35, .25, .25, .15))
edad    <- pmax(18, round(rnorm(n, 38, 12)))
ingreso <- rnorm(n, 2.5e6 + 4e4 * edad, 6e5)
gasto   <- ingreso * runif(n, 0.3, 0.7)
compra  <- rbinom(n, 1, plogis(scale(gasto)[, 1] * 0.8 - 0.5))
riesgo  <- ciudad == "Cali" & edad > 42

ingreso_real <- ingreso          # valores verdaderos (solo para 1.2 y 1.3)
gasto_real   <- gasto

ingreso[rbinom(n, 1, ifelse(riesgo, .55, .06)) == 1] <- NA
gasto[rbinom(n, 1, plogis(scale(gasto)[, 1] * 1.5 - 1)) == 1] <- NA
datos <- data.frame(ciudad, edad, ingreso, gasto, compra)

# ---- Diagnóstico general ----------------------------------------------------
colSums(is.na(datos))
round(colMeans(is.na(datos)) * 100, 1)       # % faltante por variable
sum(!complete.cases(datos))                  # filas con al menos un NA

if (requireNamespace("naniar", quietly = TRUE)) {
  print(naniar::gg_miss_var(datos))
  print(naniar::vis_miss(datos))
}


# -----------------------------------------------------------------------------
# 1.1 ¿Qué evidencia sustenta que la ausencia de ingreso es MAR y no MCAR?
# -----------------------------------------------------------------------------
# Si fuera MCAR, la probabilidad de que falte ingreso sería la MISMA en
# cualquier subgrupo definido por variables observadas. Lo comprobamos.

datos_diag <- datos |> mutate(ingreso_na = is.na(ingreso))

# (a) Tasa de faltantes por ciudad
datos_diag |>
  group_by(ciudad) |>
  summarise(n = n(), pct_na_ingreso = round(100 * mean(ingreso_na), 1)) |>
  arrange(desc(pct_na_ingreso))
chisq.test(table(datos_diag$ciudad, datos_diag$ingreso_na))

# (b) Edad según si falta o no el ingreso
datos_diag |>
  group_by(ingreso_na) |>
  summarise(n = n(), edad_media = mean(edad), edad_mediana = median(edad))
t.test(edad ~ ingreso_na, data = datos_diag)

# (c) Tasa de faltantes por ciudad y franja de edad
datos_diag |>
  mutate(franja_edad = cut(edad, c(-Inf, 30, 42, 55, Inf),
                           labels = c("18-30", "31-42", "43-55", "56+"))) |>
  group_by(ciudad, franja_edad) |>
  summarise(n = n(), pct_na = round(100 * mean(ingreso_na), 1), .groups = "drop") |>
  pivot_wider(names_from = franja_edad, values_from = c(pct_na, n))

ggplot(datos_diag, aes(edad, fill = ingreso_na)) +
  geom_histogram(binwidth = 4, position = "fill") +
  facet_wrap(~ ciudad) +
  labs(title = "Proporción de ingreso faltante por edad y ciudad",
       y = "Proporción", fill = "¿Ingreso NA?") +
  theme_minimal()

# (d) Modelo de la ausencia: regresión logística de is.na(ingreso)
mod_na <- glm(ingreso_na ~ ciudad * edad, data = datos_diag, family = binomial)
summary(mod_na)
# Comparación con un modelo sin la interacción
anova(glm(ingreso_na ~ ciudad + edad, data = datos_diag, family = binomial),
      mod_na, test = "Chisq")

# (e) Árbol de decisión: encuentra la regla que separa faltantes de observados
arbol_na <- rpart::rpart(ingreso_na ~ ciudad + edad, data = datos_diag,
                         method = "class", control = rpart::rpart.control(cp = 0.02))
print(arbol_na)

# (f) Test de Little (H0: MCAR) — opcional
if (requireNamespace("naniar", quietly = TRUE)) {
  print(naniar::mcar_test(datos |> select(edad, ingreso, gasto, compra)))
}

# RESPUESTA 1.1
# - La tasa de faltantes de ingreso NO es homogénea: en Cali es varias veces
#   mayor que en las demás ciudades (prueba chi-cuadrado significativa).
# - Quienes no reportan ingreso son en promedio MAYORES (prueba t significativa).
# - Al cruzar ambas variables, el faltante se concentra en Cali con edad
#   aproximadamente > 42 años (el árbol encuentra justo esa regla), mientras
#   que en el resto la tasa es baja y parecida entre grupos.
# - La regresión logística confirma que ciudad y edad (y su interacción)
#   predicen la ausencia; el test de Little rechaza MCAR.
# Conclusión: la ausencia depende de variables OBSERVADAS -> es MAR (respecto
# a ciudad y edad), no MCAR. Depende de la combinación ciudad = Cali y edad alta.
# (Con solo los datos no se puede descartar del todo MNAR, pero la evidencia
#  observable apunta a ciudad × edad.)


# -----------------------------------------------------------------------------
# 1.2 Media global vs. media condicional por ciudad y edad
# -----------------------------------------------------------------------------
# Subgrupo con más faltantes (según 1.1): Cali y edad > 42
datos_imp <- datos |>
  mutate(
    ingreso_real = ingreso_real,
    falta        = is.na(ingreso),
    subgrupo     = ciudad == "Cali" & edad > 42,
    franja_edad  = cut(edad, c(-Inf, 30, 42, 55, Inf))
  )

datos_imp |>
  group_by(subgrupo) |>
  summarise(n = n(), n_na = sum(falta), pct_na = round(100 * mean(falta), 1))

# (a) Imputación con la media global
media_global <- mean(datos$ingreso, na.rm = TRUE)

# (b) Imputación con la media condicional por ciudad × franja de edad
medias_cond <- datos_imp |>
  filter(!falta) |>
  group_by(ciudad, franja_edad) |>
  summarise(media_cond = mean(ingreso), n_obs = n(), .groups = "drop")
medias_cond

# (c) Variante: media condicional vía regresión ingreso ~ ciudad + edad
mod_ing <- lm(ingreso ~ ciudad + edad, data = datos_imp |> filter(!falta))

datos_imp <- datos_imp |>
  left_join(medias_cond |> select(ciudad, franja_edad, media_cond),
            by = c("ciudad", "franja_edad")) |>
  mutate(pred_lm = predict(mod_ing, newdata = pick(ciudad, edad))) |>
  mutate(
    imp_global = ifelse(falta, media_global, ingreso),
    imp_cond   = ifelse(falta, media_cond,   ingreso),
    imp_lm     = ifelse(falta, pred_lm,      ingreso)
  )

# Sesgo = promedio(valor imputado - valor real) en los NA del subgrupo
sesgo <- datos_imp |>
  filter(falta, subgrupo) |>
  summarise(
    n_imputados        = n(),
    ingreso_real_medio = mean(ingreso_real),
    sesgo_media_global = mean(imp_global - ingreso_real),
    sesgo_media_cond   = mean(imp_cond   - ingreso_real),
    sesgo_regresion    = mean(imp_lm     - ingreso_real)
  ) |>
  mutate(across(starts_with("sesgo"),
                list(pct = \(x) round(100 * x / ingreso_real_medio, 1))))
print(as.data.frame(sesgo))

# Efecto sobre la media del subgrupo completo (observados + imputados)
datos_imp |>
  filter(subgrupo) |>
  summarise(
    media_real          = mean(ingreso_real),
    media_casos_compl   = mean(ingreso, na.rm = TRUE),
    media_imp_global    = mean(imp_global),
    media_imp_cond      = mean(imp_cond),
    media_imp_regresion = mean(imp_lm)
  )

# Pérdida de varianza: la media global "aplana" la distribución
datos_imp |>
  summarise(sd_real = sd(ingreso_real), sd_imp_global = sd(imp_global),
            sd_imp_cond = sd(imp_cond))

# RESPUESTA 1.2
# El ingreso crece con la edad (4e4 por año), y el subgrupo con más faltantes
# (Cali, > 42 años) es MAYOR que el promedio. La media global se calcula con
# observados que están sobrerrepresentados por personas más jóvenes, así que
# SUBESTIMA sistemáticamente el ingreso de esos faltantes (sesgo negativo
# grande: revise 'sesgo_media_global' y su %). La media condicional por ciudad
# y edad usa personas parecidas (misma ciudad, misma franja de edad), y como
# la ausencia es MAR dado ciudad y edad, su sesgo es cercano a cero; la
# regresión (que usa la edad exacta) suele ser aún mejor. Además, la media
# global reduce artificialmente la desviación estándar.


# -----------------------------------------------------------------------------
# 1.3 gasto falta más cuando su valor real es alto (MNAR)
# -----------------------------------------------------------------------------
datos_gasto <- datos |>
  mutate(gasto_real = gasto_real, gasto_na = is.na(gasto))

# Con los valores reales (que en la práctica NO tendríamos): los que faltan
# tienen gasto mucho mayor
datos_gasto |>
  group_by(gasto_na) |>
  summarise(n = n(), gasto_real_medio = mean(gasto_real))

# Lo que SÍ se observa: la media de los observados subestima la real
c(media_real = mean(gasto_real), media_observada = mean(datos$gasto, na.rm = TRUE))

# Ni siquiera una imputación condicional bien especificada corrige el sesgo:
# modelo gasto ~ ingreso + edad + ciudad sobre casos completos
completos <- datos_gasto |> filter(!gasto_na, !is.na(ingreso))
mod_gasto <- lm(gasto ~ ingreso + edad + ciudad, data = completos)

a_imputar <- datos_gasto |> filter(gasto_na, !is.na(ingreso))
a_imputar$gasto_pred <- predict(mod_gasto, newdata = a_imputar)
a_imputar |>
  summarise(n = n(),
            sesgo_regresion = mean(gasto_pred - gasto_real),
            sesgo_pct = round(100 * mean(gasto_pred - gasto_real) / mean(gasto_real), 1))

# Señal indirecta observable: los NA de gasto se asocian con compra y con
# ingreso alto (variables correlacionadas con el gasto)
datos_gasto |>
  group_by(gasto_na) |>
  summarise(tasa_compra = mean(compra), ingreso_medio = mean(ingreso, na.rm = TRUE))

# Análisis de sensibilidad (delta-adjustment): imputar y luego desplazar los
# imputados en +delta% para ver cuánto cambian las conclusiones
deltas <- c(0, 0.10, 0.20, 0.30, 0.40)
sensibilidad <- sapply(deltas, function(d) {
  g <- datos_gasto$gasto
  idx <- which(datos_gasto$gasto_na & !is.na(datos_gasto$ingreso))
  g[idx] <- predict(mod_gasto, newdata = datos_gasto[idx, ]) * (1 + d)
  mean(g, na.rm = TRUE)
})
data.frame(delta_pct = deltas * 100, media_gasto = round(sensibilidad),
           media_real = round(mean(gasto_real)))

# RESPUESTA 1.3
# Todo método de imputación (media, mediana, KNN, regresión, MICE, missForest)
# aprende de los valores OBSERVADOS y supone que, dadas las demás variables,
# los faltantes se parecen a los observados (supuesto MAR). Aquí falla: aun
# entre personas con el mismo ingreso, edad y ciudad, los que no reportan
# gasto son justamente los de gasto alto. Los observados son una muestra
# truncada hacia abajo, así que cualquier imputación hereda ese sesgo y
# SUBESTIMA el gasto. Además, desde los datos no se puede verificar: la
# información que delataría el sesgo es justo la que falta.
# Qué hacer en su lugar:
#  1. Crear un indicador gasto_na y usarlo como predictor (la ausencia en sí
#     es informativa: se asocia con gasto alto y con compra).
#  2. Imputar (con ingreso como variable auxiliar, que está muy correlacionada)
#     y hacer ANÁLISIS DE SENSIBILIDAD: desplazar los imputados (+10%, +20%...)
#     y ver si las conclusiones cambian (punto de quiebre o "tipping point").
#  3. Modelos que representan explícitamente el mecanismo MNAR: modelos de
#     selección (Heckman) o pattern-mixture.
#  4. Conseguir información externa: seguimiento a una submuestra de no
#     respondentes, datos administrativos (p. ej., transacciones), o rediseñar
#     la captura (rangos en vez de valor exacto).
#  5. Documentar el supuesto y reportar resultados bajo varios escenarios.


# =============================================================================
# EJERCICIO 2: Depurar un pipeline con recipes
# =============================================================================
library(tidymodels)

# compra se pasa a factor: es la variable de clase y así se puede usar en un
# modelo de clasificación (y con strata en initial_split)
datos2 <- datos |> mutate(compra = factor(compra, levels = c(0, 1)))

set.seed(7)
split <- initial_split(datos2, prop = 0.8, strata = compra)
train <- training(split)
test  <- testing(split)

# ---- Pipeline ORIGINAL (con errores) — no ejecutar --------------------------
# receta <- recipe(compra ~ ., data = bind_rows(train, test)) |>   # ERROR 1
#   step_dummy(all_nominal_predictors()) |>                       # ERROR 2
#   step_impute_median(all_numeric_predictors()) |>
#   step_impute_mode(all_nominal_predictors()) |>
#   prep()

# ERROR 1 — data = bind_rows(train, test): prep() estima las medianas y modas
#   con TODO el conjunto, incluido test. Hay FUGA DE INFORMACIÓN (data
#   leakage): el preprocesamiento "conoce" el conjunto de prueba y la
#   evaluación sale optimista. Debe ser data = train.
#
# ERROR 2 — step_dummy() va ANTES de imputar:
#   - Si una categórica tiene NA, sus dummies quedan en NA.
#   - Después, step_impute_mode(all_nominal_predictors()) ya no encuentra
#     variables nominales (se volvieron dummies numéricas), así que no imputa
#     nada; y step_impute_median imputaría las dummies con la mediana (0/1),
#     que no es una moda bien definida de la categoría.
#   Se debe imputar primero y crear dummies al final.

# ---- Pipeline CORREGIDO -----------------------------------------------------
receta <- recipe(compra ~ ., data = train) |>
  step_impute_mode(all_nominal_predictors()) |>
  step_impute_median(all_numeric_predictors()) |>
  step_dummy(all_nominal_predictors()) |>
  prep()

train_proc <- bake(receta, new_data = NULL)
test_proc  <- bake(receta, new_data = test)

colSums(is.na(train_proc))   # todo en 0
colSums(is.na(test_proc))    # todo en 0
tidy(receta, number = 2)     # medianas aprendidas SOLO con train

# ---- Pipeline EXTENDIDO ----------------------------------------------------
receta_ext <- recipe(compra ~ ., data = train) |>
  step_indicate_na(ingreso) |>                          # 1. indicador (antes de imputar)
  step_impute_mode(all_nominal_predictors()) |>         # 2. categóricas
  step_impute_bag(ingreso,                              # 3. ingreso con bagged trees
                  impute_with = imp_vars(ciudad, edad, gasto),
                  trees = 25) |>
  step_impute_median(all_numeric_predictors()) |>       # 4. lo que queda (gasto)
  step_dummy(all_nominal_predictors())                  # 5. dummies al final

receta_ext_prep <- prep(receta_ext)
train_ext <- bake(receta_ext_prep, new_data = NULL)
test_ext  <- bake(receta_ext_prep, new_data = test)

glimpse(train_ext)                     # aparece la columna na_ind_ingreso
colSums(is.na(train_ext))
table(train_ext$na_ind_ingreso)

# Justificación del orden final:
# 1. step_indicate_na() va PRIMERO: si se ejecuta después de imputar, ya no
#    hay NA y el indicador sería todo ceros. Así se conserva la información de
#    que el dato faltaba (útil porque la ausencia es MAR y puede ser predictiva).
# 2. step_impute_mode() antes de step_impute_bag(): deja completas las
#    categóricas que el modelo de imputación usa como predictoras.
# 3. step_impute_bag() antes de las dummies: los árboles manejan 'ciudad' como
#    factor directamente y capturan la interacción ciudad × edad que explica el
#    ingreso; además toleran NA en sus predictoras (gasto). Se restringe
#    impute_with a ciudad, edad y gasto: no se usa la respuesta 'compra' (no es
#    predictora en la receta) ni el propio indicador.
# 4. step_impute_median() para el resto (gasto), después de que ingreso ya está
#    imputado con un método mejor (si fuera antes, imputaría ingreso con la
#    mediana y step_impute_bag no tendría nada que hacer).
# 5. step_dummy() al final: todas las variables ya están completas.
# Todo se estima con train (prep) y se aplica igual a test (bake).
# Mejora posible: agregar también step_indicate_na(gasto), dado su mecanismo MNAR.

# ---- Bonus: el pipeline dentro de un workflow con un modelo -----------------
wf <- workflow() |>
  add_recipe(receta_ext) |>
  add_model(logistic_reg() |> set_engine("glm"))

fit_wf <- fit(wf, data = train)
tidy(fit_wf)

predict(fit_wf, test, type = "prob") |>
  bind_cols(test |> select(compra)) |>
  roc_auc(truth = compra, .pred_1, event_level = "second")


# =============================================================================
# EJERCICIO 3: Razonamiento conceptual (crédito, 22% de ingreso faltante)
# =============================================================================
# 3.1 ¿MAR o MCAR? ¿Por qué no se puede descartar MNAR?
#
# Más consistente con MAR que con MCAR. Bajo MCAR, quienes tienen el dato
# faltante serían una submuestra aleatoria: la ausencia no se relacionaría con
# ninguna variable. Pero:
#   - la ausencia se asocia con estrato (≈ 0.52), una variable observada;
#   - quienes no reportan ingreso incumplen 31% vs. 9%: son un grupo distinto.
# La débil relación con edad (≈ 0.03) solo dice que la edad no es la que
# explica la ausencia; no hace falta que todas las variables se asocien.
#
# No se puede descartar MNAR porque:
#   - El estrato está correlacionado con el ingreso. La asociación
#     ausencia–estrato es compatible con que la ausencia dependa del PROPIO
#     ingreso (p. ej., ingresos bajos, informales o difíciles de demostrar no se
#     reportan) y el estrato solo actúe como sustituto.
#   - La brecha 31% vs. 9% en incumplimiento puede persistir dentro de cada
#     estrato, lo que indicaría algo más que el estrato detrás de la ausencia.
#   - En general, MAR vs. MNAR no se puede probar con los datos: la
#     información necesaria para distinguirlos es justo el valor no observado.
#
# 3.2 Consecuencia práctica de imputar con la mediana global
#
# A todo el 22% que no reportó se le asigna el mismo ingreso "típico". Esos
# solicitantes son de más riesgo (31% de incumplimiento) y probablemente de
# menor ingreso o de estratos específicos. Consecuencias:
#   - El modelo los ve como clientes promedio: SUBESTIMA su riesgo y tiende a
#     APROBAR créditos a personas que incumplen mucho más (más pérdidas,
#     condiciones de tasa o monto mal asignadas).
#   - Se pierde la señal "no reportó ingreso", que por sí sola es muy
#     predictiva. Además, un pico artificial en la mediana distorsiona (atenúa)
#     el efecto estimado del ingreso, y eso afecta también las decisiones sobre
#     quienes sí reportaron.
#   - Como la ausencia está ligada al estrato, los errores no se reparten al
#     azar: se clasifica mal sistemáticamente a ciertos estratos. Riesgo de
#     trato injusto, aprobaciones y rechazos inconsistentes, y problemas
#     regulatorios o de explicabilidad ante el comité o el supervisor.
#   - Un AUC global aceptable puede ocultar que el modelo está mal calibrado
#     justo en el segmento de no reportantes.
#
# 3.3 Estrategia en 3 pasos (sin eliminar el 22%)
#
# Paso 1 — Indicador + imputación condicional dentro del pipeline:
#   Crear ingreso_faltante (0/1) y usarlo como predictor; imputar el ingreso
#   con un modelo que use estrato y otras variables auxiliares (buró, productos,
#   transacciones) mediante múltiple imputación (mice) o step_impute_bag.
#   Todo ajustado SOLO con train, dentro de recipes o workflow.
#
# Paso 2 — Sensibilidad al supuesto MNAR:
#   Repetir el modelo desplazando los ingresos imputados (−10%, −20%, −30%) y
#   comparar tasas de aprobación, incumplimiento esperado, AUC y calibración por
#   segmento (faltante vs. no faltante, por estrato). Si las decisiones son
#   estables, la estrategia es defendible; si no, reportar el punto de quiebre.
#
# Paso 3 — Validación, gobierno y política:
#   Validación fuera de tiempo, monitoreo de la tasa de faltantes y del
#   desempeño en ese segmento, y documentación de los supuestos. Como política
#   operativa, para no reportantes cerca del umbral pedir soporte de ingresos o
#   limitar montos, y mejorar la captura del dato a futuro.