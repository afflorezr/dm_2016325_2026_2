# Clase 8: valores faltantes
# Ejercicios de práctica

paquetes <- c("dplyr", "tidyr", "recipes", "ipred", "lava")
tipo     <- if (.Platform$OS.type == "windows") "binary" else getOption("pkgType")

# instala lo que falte (o no cargue) con sus dependencias
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) install.packages(faltan, type = tipo, dependencies = TRUE)

library(dplyr)
library(tidyr)
library(recipes)


# Datos simulados -----------------------------------------------------------
# se guardan los valores reales antes de borrar, para medir el sesgo

set.seed(2024); n <- 400
ciudad <- sample(c("Bogotá","Medellín","Cali","Barranquilla"),
                 n, TRUE, c(.35,.25,.25,.15))
edad    <- pmax(18, round(rnorm(n, 38, 12)))
ingreso <- rnorm(n, 2.5e6 + 4e4*edad, 6e5)
gasto   <- ingreso * runif(n, 0.3, 0.7)
compra  <- rbinom(n, 1, plogis(scale(gasto)[,1]*0.8 - 0.5))

ingreso_real <- ingreso
gasto_real   <- gasto

riesgo <- ciudad == "Cali" & edad > 42
ingreso[rbinom(n, 1, ifelse(riesgo, .55, .06)) == 1] <- NA
gasto[rbinom(n, 1, plogis(scale(gasto)[,1]*1.5 - 1)) == 1] <- NA
datos <- data.frame(ciudad, edad, ingreso, gasto, compra)

colSums(is.na(datos))


# Ejercicio 1 ---------------------------------------------------------------

# 1.1 ¿de qué depende la ausencia de ingreso?
datos_na <- datos %>%
  mutate(ingreso_na = is.na(ingreso),
         tramo_edad = cut(edad, c(17, 30, 42, 55, Inf),
                          labels = c("18-30", "31-42", "43-55", "56+")))

datos_na %>%
  summarise(n = n(), pct_na = round(100 * mean(ingreso_na), 1), .by = ciudad) %>%
  arrange(desc(pct_na))

datos_na %>%
  summarise(n = n(), pct_na = round(100 * mean(ingreso_na), 1), .by = tramo_edad) %>%
  arrange(tramo_edad)

datos_na %>%
  summarise(pct_na = round(100 * mean(ingreso_na), 1), .by = c(ciudad, tramo_edad)) %>%
  pivot_wider(names_from = tramo_edad, values_from = pct_na)

chisq.test(table(datos_na$ciudad, datos_na$ingreso_na))
t.test(edad ~ ingreso_na, data = datos_na)

modelo_na <- glm(ingreso_na ~ ciudad * I(edad > 42), data = datos_na, family = binomial)
summary(modelo_na)

# gasto observado de quienes tienen y no tienen ingreso
datos_na %>% summarise(gasto_medio = mean(gasto, na.rm = TRUE), .by = ingreso_na)

# 1.2 media global frente a media condicional por ciudad y edad
media_global <- mean(datos$ingreso, na.rm = TRUE)
modelo_ing   <- lm(ingreso ~ ciudad + edad, data = datos)

imputado <- datos %>%
  mutate(ingreso_real = ingreso_real,
         falta = is.na(ingreso),
         grupo_riesgo = ciudad == "Cali" & edad > 42,
         imp_global = if_else(falta, media_global, ingreso),
         imp_condicional = if_else(falta, predict(modelo_ing, newdata = datos), ingreso))

sesgo <- imputado %>%
  filter(falta) %>%
  summarise(n = n(),
            real_medio = mean(ingreso_real),
            sesgo_global = mean(imp_global - ingreso_real),
            sesgo_condicional = mean(imp_condicional - ingreso_real),
            .by = grupo_riesgo)
sesgo

# efecto sobre la media del subgrupo completo
imputado %>%
  filter(grupo_riesgo) %>%
  summarise(media_real = mean(ingreso_real),
            media_global = mean(imp_global),
            media_condicional = mean(imp_condicional))

# 1.3 gasto falta más cuando su valor es alto
tibble(gasto_real, falta = is.na(gasto)) %>%
  summarise(n = n(), gasto_real_medio = mean(gasto_real), .by = falta)

c(media_real = mean(gasto_real),
  media_observada = mean(gasto, na.rm = TRUE))

# aun usando ingreso, que está muy correlacionado con gasto, la imputación
# condicional no recupera el nivel real de los faltantes
modelo_gasto <- lm(gasto ~ ingreso + edad + ciudad, data = datos)
con_gasto <- datos %>%
  mutate(gasto_real = gasto_real,
         falta = is.na(gasto),
         imp = if_else(falta, predict(modelo_gasto, newdata = datos), gasto)) %>%
  filter(falta, !is.na(imp))

con_gasto %>%
  summarise(n = n(), real = mean(gasto_real), imputado = mean(imp),
            sesgo = mean(imp - gasto_real))


# Ejercicio 2 ---------------------------------------------------------------

datos_modelo <- datos %>% mutate(compra = factor(compra))

# partición 80/20 estratificada por compra (equivale a initial_split() de
# rsample con strata = compra)
set.seed(7)
idx_train <- unlist(lapply(split(seq_len(nrow(datos_modelo)), datos_modelo$compra),
                           function(i) sample(i, round(0.8 * length(i)))))
train <- datos_modelo[sort(idx_train), ]
test  <- datos_modelo[-idx_train, ]

prop.table(table(train$compra)); prop.table(table(test$compra))

# 2.1 pipeline corregido:
#  - la receta se estima solo con train (antes usaba bind_rows(train, test))
#  - se imputa antes de crear las dummies
receta <- recipe(compra ~ ., data = train) |>
  step_impute_median(all_numeric_predictors()) |>
  step_impute_mode(all_nominal_predictors()) |>
  step_dummy(all_nominal_predictors()) |>
  prep()

train_proc <- bake(receta, new_data = NULL)
test_proc  <- bake(receta, new_data = test)

stopifnot(!anyNA(train_proc), !anyNA(test_proc))
head(train_proc)

# 2.2 indicador de ausencia + imputación por bagging
receta_bag <- recipe(compra ~ ., data = train) |>
  step_indicate_na(ingreso) |>
  step_impute_bag(ingreso, gasto,
                  impute_with = imp_vars(ciudad, edad, ingreso, gasto)) |>
  step_impute_mode(all_nominal_predictors()) |>
  step_dummy(all_nominal_predictors()) |>
  prep()

train_bag <- bake(receta_bag, new_data = NULL)
test_bag  <- bake(receta_bag, new_data = test)

stopifnot(!anyNA(train_bag), !anyNA(test_bag))
names(train_bag)
train_bag %>% count(na_ind_ingreso)


# Respuestas ----------------------------------------------------------------
#
# Ejercicio 1
# 1. El faltante de ingreso no es parejo: en Cali falta el 22 % frente a
#    menos del 8 % en las demás ciudades (chi cuadrado, p < 0,001), y
#    quienes no reportan ingreso son mayores (44 frente a 38 años,
#    p = 0,003). Al cruzar ciudad y edad aparece el patrón: en Cali entre
#    48 % y 62 % de los mayores de 42 años no tiene ingreso, mientras en el
#    resto de grupos falta menos del 13 %. Si fuera MCAR la proporción sería
#    similar en todos los grupos. Depende de variables observadas (ciudad y
#    edad, en particular Cali con más de 42 años), así que es MAR.
#
# 2. En el subgrupo con más faltantes (Cali, mayores de 42), la media
#    global subestima el ingreso de los imputados en $337.921 en promedio,
#    porque usa el ingreso de toda la muestra, que es más joven. La media
#    condicional (regresión por ciudad y edad) reduce el sesgo a $139.500,
#    aunque lo sobrestima un poco porque el modelo no tiene la interacción
#    ciudad-edad. Sobre la media del subgrupo, la real es $4.473.781, con
#    la global queda en $4.299.993 y con la condicional en $4.545.523.
#
# 3. Quienes no tienen gasto gastan en realidad $2.504.693 en promedio,
#    frente a $1.779.017 de quienes sí lo reportan. Cualquier imputación se
#    estima con los datos observados, que son justamente los de gasto bajo,
#    así que reproduce ese sesgo: incluso imputando con ingreso, que está
#    muy relacionado con el gasto, los imputados quedan $513.575 por debajo
#    de su valor real. La ausencia depende del valor que no se ve (MNAR) y
#    los datos no tienen información para corregirla. En su lugar haría un
#    análisis de sensibilidad (por ejemplo, sumar un ajuste delta a los
#    imputados y ver cómo cambian los resultados), dejaría un indicador de
#    ausencia en el modelo y buscaría información externa o una submuestra
#    de seguimiento para conocer el gasto real de quienes no responden.
#
# Ejercicio 2
# 1. Primer error: recipe() se construía con bind_rows(train, test), y
#    prep() calcula medianas y modas con esos datos; la información de
#    prueba entra al entrenamiento (fuga). Debe usarse solo train. Segundo
#    error: step_dummy() iba antes de imputar; las dummies se crean con los
#    NA de las categóricas y step_impute_mode() ya no encuentra columnas
#    nominales que imputar, además de que la mediana se aplicaría sobre las
#    dummies. Se imputa primero y luego se crean las dummies.
#
# 2. El orden final es: step_indicate_na(ingreso), step_impute_bag(),
#    step_impute_mode() y step_dummy(). El indicador va primero porque
#    después de imputar ya no se sabe qué filas faltaban, y como el
#    faltante es MAR esa bandera puede ser informativa. step_impute_bag()
#    va antes de las dummies porque usa ciudad (como factor) y edad para
#    predecir ingreso y gasto. Las dummies van al final, cuando ya no quedan
#    NA. La receta se estima solo con train y deja 27 filas marcadas con
#    na_ind_ingreso.
#
# Ejercicio 3
# 1. Es más consistente con MAR: la ausencia se asocia con una
#    variable observada (estrato, correlación de 0,52), así que no ocurre
#    al azar, y la diferencia de incumplimiento (31 % frente a 9 %) muestra
#    que quienes no reportan son distintos. No se puede descartar MNAR
#    porque nunca vemos el ingreso que falta: es posible que, aun dentro de
#    un mismo estrato, falte más cuando el ingreso es bajo, y eso no se
#    puede comprobar con los datos observados.
#
# 2. La mediana global le asigna a todos los que no reportan un
#    ingreso "típico", que probablemente es más alto que el real. El modelo
#    verá a ese grupo como menos riesgoso de lo que es y terminará aprobando
#    créditos a solicitantes con alta probabilidad de incumplimiento (31 %),
#    mientras se pierde la señal de que no reportar el ingreso ya es una
#    alerta. Además, el efecto se concentra en ciertos estratos, lo que
#    puede generar decisiones sesgadas por grupo.
#
# 3. (1) Crear un indicador de ausencia de ingreso_reportado y
#    dejarlo como variable del modelo. (2) Imputar condicionalmente con
#    estrato y otras variables observadas (por ejemplo, imputación múltiple
#    con mice), ajustando todo solo con entrenamiento. (3) Hacer un análisis
#    de sensibilidad: reducir los ingresos imputados en distintos
#    porcentajes y revisar cuánto cambian las tasas de aprobación y de
#    incumplimiento; si cambian mucho, establecer una política
#    conservadora para quienes no reportan.
