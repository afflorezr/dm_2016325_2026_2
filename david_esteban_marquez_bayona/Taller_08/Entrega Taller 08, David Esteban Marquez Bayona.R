# =============================================================================
# Minería de Datos — Clase 8: Git, valores faltantes e integración
# Ejercicios de práctica: valores faltantes
# Autor: David Márquez
# =============================================================================
#install.packages(c("tidyverse", "tidymodels", "ipred"))
# (tidymodels incluye rsample y recipes; ipred lo usa step_impute_bag)
library(tidyverse)
library(rsample)
library(recipes)

# =============================================================================
# EJERCICIO 1: diagnóstico de valores faltantes
# =============================================================================
set.seed(2024); n <- 400
ciudad  <- sample(c("Bogotá","Medellín","Cali","Barranquilla"),
                   n, TRUE, c(.35,.25,.25,.15))
edad    <- pmax(18, round(rnorm(n, 38, 12)))
ingreso <- rnorm(n, 2.5e6 + 4e4*edad, 6e5)
gasto   <- ingreso * runif(n, 0.3, 0.7)
compra  <- rbinom(n, 1, plogis(scale(gasto)[,1]*0.8 - 0.5))
ingreso_real <- ingreso                      # se guarda antes de borrar (verdad)
gasto_real   <- gasto
riesgo  <- ciudad == "Cali" & edad > 42
ingreso[rbinom(n, 1, ifelse(riesgo, .55, .06)) == 1] <- NA
gasto[rbinom(n, 1, plogis(scale(gasto)[,1]*1.5 - 1)) == 1] <- NA
datos <- data.frame(ciudad, edad, ingreso, gasto, compra)

# --- Panorama de faltantes ---------------------------------------------------
colSums(is.na(datos))
round(100 * colMeans(is.na(datos)), 1)

# -----------------------------------------------------------------------------
# 1a. Evidencia de que la ausencia de ingreso es MAR (y no MCAR)
# -----------------------------------------------------------------------------
datos$falta_ing <- is.na(datos$ingreso)

# Tasa de faltantes por ciudad
tab_ciudad <- datos |>
  group_by(ciudad) |>
  summarise(n = n(), pct_falta = round(100 * mean(falta_ing), 1))
tab_ciudad
chisq.test(table(datos$ciudad, datos$falta_ing))

# Edad de quienes tienen / no tienen ingreso
datos |> group_by(falta_ing) |>
  summarise(n = n(), edad_media = mean(edad), edad_mediana = median(edad))
t.test(edad ~ falta_ing, data = datos)

# Interacción ciudad x edad (> 42 años)
tab_cruce <- datos |>
  mutate(edad_grupo = if_else(edad > 42, "> 42", "<= 42")) |>
  group_by(ciudad, edad_grupo) |>
  summarise(n = n(), pct_falta = round(100 * mean(falta_ing), 1),
            .groups = "drop")
tab_cruce

# Modelo logístico de la indicadora de ausencia
modelo_na <- glm(falta_ing ~ ciudad * I(edad > 42), data = datos,
                 family = binomial)
summary(modelo_na)

ggplot(datos, aes(x = edad, y = as.numeric(falta_ing), colour = ciudad == "Cali")) +
  geom_jitter(height = 0.05, alpha = 0.4) +
  geom_smooth(method = "glm", method.args = list(family = binomial), se = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "firebrick", `FALSE` = "grey50"),
                      labels = c("Otras ciudades", "Cali")) +
  labs(title = "Probabilidad de que falte ingreso según edad",
       y = "Falta ingreso (1 = sí)", colour = NULL) +
  theme_minimal()

# -----------------------------------------------------------------------------
# 1b. Media global vs. media condicional (ciudad y edad)
# -----------------------------------------------------------------------------
# Imputación 1: media global
imp_global <- ifelse(is.na(datos$ingreso), mean(datos$ingreso, na.rm = TRUE),
                     datos$ingreso)

# Imputación 2: media condicional por ciudad y edad
# (regresión lineal del ingreso observado sobre ciudad y edad)
mod_cond <- lm(ingreso ~ ciudad + edad, data = datos)
imp_cond <- ifelse(is.na(datos$ingreso),
                   predict(mod_cond, newdata = datos), datos$ingreso)

# Sesgo en el subgrupo con más faltantes: Cali y edad > 42
sub   <- datos$ciudad == "Cali" & datos$edad > 42
falt  <- sub & is.na(datos$ingreso)
cat("Subgrupo Cali > 42:", sum(sub), "personas,", sum(falt), "con ingreso faltante\n")

sesgo <- tibble(
  metodo = c("Media global", "Media condicional (ciudad + edad)"),
  # sesgo promedio en los valores imputados (imputado - real)
  sesgo_imputados = c(mean(imp_global[falt] - ingreso_real[falt]),
                      mean(imp_cond[falt]   - ingreso_real[falt])),
  # sesgo de la media del subgrupo completo después de imputar
  media_sub_imputada = c(mean(imp_global[sub]), mean(imp_cond[sub])),
  media_sub_real     = mean(ingreso_real[sub])
) |>
  mutate(sesgo_media_sub = media_sub_imputada - media_sub_real,
         sesgo_pct = round(100 * sesgo_media_sub / media_sub_real, 1))
print(sesgo, width = Inf)

# -----------------------------------------------------------------------------
# 1c. gasto es MNAR: falta más cuando su propio valor es alto
# -----------------------------------------------------------------------------
falta_gasto <- is.na(datos$gasto)
c(gasto_real_observados = mean(gasto_real[!falta_gasto]),
  gasto_real_faltantes  = mean(gasto_real[falta_gasto]))

# Aun imputando con el ingreso (variable muy relacionada), el sesgo persiste:
mod_gasto <- lm(gasto ~ ingreso + edad + ciudad, data = datos)
imp_gasto <- predict(mod_gasto, newdata = datos)
ok <- falta_gasto & !is.na(imp_gasto)
c(media_real_faltantes    = mean(gasto_real[ok]),
  media_imputada_faltantes = mean(imp_gasto[ok]),
  sesgo = mean(imp_gasto[ok] - gasto_real[ok]))

# =============================================================================
# EJERCICIO 2: depurar el pipeline con recipes
# =============================================================================
datos_mod <- datos |> select(ciudad, edad, ingreso, gasto, compra)
# compra como factor (clasificación)
datos_mod$compra <- factor(datos_mod$compra, levels = c(0, 1))

set.seed(7)
split <- initial_split(datos_mod, prop = 0.8, strata = compra)
train <- training(split)
test  <- testing(split)

# --- Pipeline ORIGINAL con errores (comentado) -------------------------------
# receta <- recipe(compra ~ ., data = bind_rows(train, test)) |>   # ERROR 1
#   step_dummy(all_nominal_predictors()) |>                         # ERROR 2
#   step_impute_median(all_numeric_predictors()) |>
#   step_impute_mode(all_nominal_predictors()) |>
#   prep()
#
# ERROR 1 (fuga de información): recipe() se construye con train + test, así
#   que prep() estima las medianas y la moda usando el conjunto de prueba.
#   La receta debe estimarse SOLO con train.
# ERROR 2 (orden): step_dummy() va antes de imputar. Las nominales ya se
#   convirtieron en dummies, así que step_impute_mode() no encuentra
#   nominales que imputar (un NA en ciudad produciría dummies con NA que la
#   mediana "imputaría" como 0/1 sin sentido). Hay que imputar primero y
#   crear dummies al final.

# --- Pipeline CORREGIDO -----------------------------------------------------
receta <- recipe(compra ~ ., data = train) |>
  step_impute_median(all_numeric_predictors()) |>
  step_impute_mode(all_nominal_predictors()) |>
  step_dummy(all_nominal_predictors()) |>
  prep()
train_proc <- bake(receta, new_data = NULL)
test_proc  <- bake(receta, new_data = test)
colSums(is.na(train_proc)); colSums(is.na(test_proc))
tidy(receta, number = 1)       # medianas estimadas solo con train

# --- Pipeline EXTENDIDO: indicador de ausencia + imputación por bagging -----
receta_ext <- recipe(compra ~ ., data = train) |>
  step_indicate_na(ingreso) |>                       # 1. bandera na_ind_ingreso
  step_impute_bag(ingreso, gasto,                    # 2. bagging de árboles
                  impute_with = imp_vars(ciudad, edad, ingreso, gasto)) |>
  step_impute_mode(all_nominal_predictors()) |>      # 3. nominales (si hubiera NA)
  step_dummy(all_nominal_predictors()) |>            # 4. dummies al final
  prep()
train_ext <- bake(receta_ext, new_data = NULL)
test_ext  <- bake(receta_ext, new_data = test)
head(train_ext)
colSums(is.na(train_ext)); colSums(is.na(test_ext))
mean(train_ext$na_ind_ingreso)

# Justificación del orden:
# 1. step_indicate_na() va PRIMERO: después de imputar ya no quedan NA y la
#    bandera saldría toda en cero. La bandera conserva la información de que
#    el dato faltaba (útil porque aquí la ausencia es MAR y se asocia con un
#    perfil: Cali, > 42 años).
# 2. step_impute_bag() imputa con un modelo de árboles que usa ciudad y edad
#    como predictores, así que recupera la dependencia MAR (media condicional)
#    en vez de un valor global. Va antes de step_dummy() porque los árboles
#    usan ciudad como factor directamente.
# 3. step_impute_mode() cubre posibles NA en nominales antes de crear dummies.
# 4. step_dummy() al final, cuando ya no hay NA.
# Todo se estima con prep() sobre train y se aplica a test con bake(): sin fuga.

# =============================================================================
# RESPUESTAS
# =============================================================================
# (Valores con set.seed(2024) y set.seed(7).)
#
# EJERCICIO 1
# 1a. ingreso falta en 37 de 400 registros (9,2%). Si fuera MCAR, la tasa de
#     ausencia sería parecida en todos los grupos, pero no lo es:
#     - Por ciudad: Cali 22,0% vs. Bogotá 7,4%, Barranquilla 7,6% y
#       Medellín 1,9% (chi-cuadrado p ≈ 0,00001).
#     - Por edad: quienes no reportan ingreso tienen 44 años en promedio vs.
#       38 de quienes sí (t de Welch, p ≈ 0,003).
#     - En el cruce está la clave: en Cali con más de 42 años falta el 51,4%,
#       mientras que en los demás grupos va de 0% a 12,5% (Cali <= 42: 3,6%).
#     La ausencia depende de variables OBSERVADAS (ciudad y edad, en
#     interacción), lo que es consistente con MAR. Con los datos no se puede
#     probar que no dependa también del propio ingreso (eso sería MNAR).
#
# 1b. Subgrupo con más faltantes: Cali y > 42 años (35 personas, 18 sin
#     ingreso). Ingreso real promedio del subgrupo: 4.473.781.
#                        Sesgo en imputados   Media del subgrupo   Sesgo
#     Media global          -337.921            4.299.993           -3,9%
#     Media condicional     +139.500            4.545.523           +1,6%
#     La media global SUBESTIMA a los imputados en ~338 mil pesos, porque el
#     ingreso crece con la edad y los faltantes son mayores que el promedio.
#     La media condicional (regresión sobre ciudad y edad) reduce el sesgo a
#     menos de la mitad (~140 mil) y lo deja en 1,6% sobre la media del
#     subgrupo. Bajo MAR, condicionar en las variables de las que depende la
#     ausencia corrige gran parte del sesgo.
#
# 1c. gasto falta el 31,5% de las veces y la ausencia depende de su propio
#     valor (MNAR): el gasto real de los faltantes promedia 2.504.693 vs.
#     1.779.017 de los observados. Cualquier imputación aprende la relación
#     a partir de los OBSERVADOS, que son sistemáticamente los de gasto bajo;
#     ninguna variable observada contiene la información de "este valor era
#     alto". Incluso imputando con el ingreso (muy correlacionado), los
#     valores imputados quedan ~514 mil pesos por debajo del real. Qué haría:
#     (1) agregar un indicador de ausencia como predictor; (2) análisis de
#     sensibilidad (p. ej., delta-adjustment: imputar y sumar un desplazamiento
#     delta, ver cómo cambian las conclusiones); (3) modelos de selección o
#     patrón-mezcla; y, sobre todo, (4) recuperar el dato en la fuente
#     (re-encuestar una submuestra de no respondientes) y documentar el
#     supuesto.
#
# EJERCICIO 2
# Error 1: recipe(..., data = bind_rows(train, test)) -> fuga de información:
#   las medianas/modas se estiman con el conjunto de prueba. Corrección:
#   recipe(compra ~ ., data = train).
# Error 2: step_dummy() antes de imputar -> las nominales ya no existen
#   cuando llega step_impute_mode() y los NA de ciudad pasarían a las dummies.
#   Corrección: imputar primero, step_dummy() al final.
# Pipeline extendido: step_indicate_na(ingreso) -> step_impute_bag() ->
#   step_impute_mode() -> step_dummy(). La bandera va primero porque después
#   de imputar no quedarían NA que marcar; el bagging usa ciudad y edad, que
#   explican la ausencia (MAR); las dummies al final. 8,5% de train tiene
#   na_ind_ingreso = 1 y no quedan NA ni en train ni en test.
#
# EJERCICIO 3 (conceptual)
# 1. Más consistente con MAR que con MCAR: bajo MCAR la ausencia no se
#    asociaría con nada, pero se asocia con estrato (≈ 0,52) y con el
#    resultado (incumplimiento 31% vs. 9%). Sin embargo, no se puede
#    descartar un componente MNAR: quien tiene ingreso bajo (o irregular)
#    tiene motivos para no reportarlo, y el estrato es solo un proxy parcial
#    del ingreso. La diferencia tan grande en incumplimiento sugiere que la
#    ausencia lleva información que quizá el estrato no explica del todo. Por
#    definición, MNAR depende del valor no observado, así que los datos
#    observados no permiten probarlo ni descartarlo.
# 2. Imputar con la mediana global le asigna a todos los que no reportaron un
#    ingreso "típico", más alto que el que probablemente tienen (están
#    concentrados en estratos bajos). El modelo los ve como solicitantes de
#    riesgo medio: subestima su riesgo y aprueba créditos que deberían
#    rechazarse o evaluarse aparte, lo que aumenta la cartera vencida. Además
#    se pierde la señal de que "no reportar" es en sí un predictor fuerte de
#    incumplimiento (31% vs. 9%), y el efecto recae de forma desigual por
#    estrato (problema de equidad y de explicabilidad ante el supervisor).
# 3. Estrategia en 3 pasos:
#    (1) Crear un indicador de ausencia (ingreso_faltante) y usarlo como
#        predictor: conserva la señal de riesgo.
#    (2) Imputación múltiple condicional (MICE o bagging) con estrato y demás
#        variables observadas, estimada solo con datos de entrenamiento dentro
#        del pipeline (sin fuga), para no perder el 22% de las filas.
#    (3) Análisis de sensibilidad MNAR (delta-adjustment) y validación del
#        desempeño por separado en el grupo con dato faltante; documentar el
#        supuesto y, en paralelo, mejorar la captura del ingreso (p. ej.
#        validación con centrales de riesgo) para reducir el faltante.
