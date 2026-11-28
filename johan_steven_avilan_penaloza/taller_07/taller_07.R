library(tidymodels)
library(tidyverse)
library(naniar)

# Datos
set.seed(2024); n <- 400
ciudad  <- sample(c("Bogotá","Medellín","Cali","Barranquilla"),
                  n, TRUE, c(.35,.25,.25,.15))
edad    <- pmax(18, round(rnorm(n, 38, 12)))
ingreso <- rnorm(n, 2.5e6 + 4e4*edad, 6e5)
gasto   <- ingreso * runif(n, 0.3, 0.7)
compra  <- rbinom(n, 1, plogis(scale(gasto)[,1]*0.8 - 0.5))
riesgo  <- ciudad == "Cali" & edad > 42

ingreso_real <- ingreso
gasto_real   <- gasto

ingreso[rbinom(n, 1, ifelse(riesgo, .55, .06)) == 1] <- NA
gasto[rbinom(n, 1, plogis(scale(gasto)[,1]*1.5 - 1)) == 1] <- NA

datos <- data.frame(ciudad, edad, ingreso, gasto, compra)
verdad <- data.frame(ingreso_real, gasto_real, riesgo)

# Ejercicio 1
colMeans(is.na(datos))
gg_miss_var(datos)

datos <- datos |>
  mutate(ing_na   = is.na(ingreso),
         edad_cat = cut(edad, c(0, 30, 42, Inf),
                        labels = c("<=30", "31-42", ">42")))

datos |> group_by(ciudad)   |> summarise(pct_na = mean(ing_na), n = n())
datos |> group_by(edad_cat) |> summarise(pct_na = mean(ing_na), n = n())

datos |>
  group_by(ciudad, edad_cat) |>
  summarise(pct_na = round(mean(ing_na), 2), n = n(), .groups = "drop") |>
  arrange(desc(pct_na))

mod_na <- glm(ing_na ~ ciudad * I(edad > 42) + compra,
              data = datos, family = binomial)
summary(mod_na)

chisq.test(table(datos$ciudad, datos$ing_na))
t.test(edad ~ ing_na, data = datos)

idx_sub <- verdad$riesgo
cat("Faltantes en el subgrupo:", sum(is.na(datos$ingreso[idx_sub])),
    "de", sum(idx_sub), "\n")

media_global <- mean(datos$ingreso, na.rm = TRUE)
ing_imp_global <- ifelse(is.na(datos$ingreso), media_global, datos$ingreso)

mod_ing <- lm(ingreso ~ ciudad + edad, data = datos)
pred    <- predict(mod_ing, newdata = datos)
ing_imp_cond <- ifelse(is.na(datos$ingreso), pred, datos$ingreso)

sesgo <- function(imp) {
  c(media_real    = mean(verdad$ingreso_real[idx_sub]),
    media_imputada = mean(imp[idx_sub]),
    sesgo_abs      = mean(imp[idx_sub]) - mean(verdad$ingreso_real[idx_sub]),
    sesgo_pct      = 100 * (mean(imp[idx_sub]) / mean(verdad$ingreso_real[idx_sub]) - 1))
}
resultado_sesgo <- rbind(global      = sesgo(ing_imp_global),
                         condicional = sesgo(ing_imp_cond))
print(round(resultado_sesgo, 1))

na_sub <- idx_sub & is.na(datos$ingreso)
data.frame(
  metodo = c("global", "condicional"),
  sesgo_medio = c(mean(ing_imp_global[na_sub] - verdad$ingreso_real[na_sub]),
                  mean(ing_imp_cond[na_sub]   - verdad$ingreso_real[na_sub])),
  RMSE = c(sqrt(mean((ing_imp_global[na_sub] - verdad$ingreso_real[na_sub])^2)),
           sqrt(mean((ing_imp_cond[na_sub]   - verdad$ingreso_real[na_sub])^2)))
)

cat("Media gasto observada:", mean(datos$gasto, na.rm = TRUE), "\n")
cat("Media gasto real     :", mean(verdad$gasto_real), "\n")
tibble(gasto_real = verdad$gasto_real, falta = is.na(datos$gasto)) |>
  ggplot(aes(gasto_real, fill = falta)) +
  geom_density(alpha = .5) +
  labs(title = "gasto: los valores altos son los que faltan (MNAR)")

library(mice)
imp0 <- mice(datos[, c("ciudad", "edad", "ingreso", "gasto", "compra")],
             m = 5, method = "pmm", seed = 123, printFlag = FALSE)

media_gasto_delta <- function(delta_pct) {
  sapply(1:5, function(k) {
    d <- complete(imp0, k)
    na <- is.na(datos$gasto)
    d$gasto[na] <- d$gasto[na] * (1 + delta_pct / 100)
    mean(d$gasto)
  }) |> mean()
}
sens <- tibble(delta_pct = c(0, 10, 20, 30, 40)) |>
  mutate(media_gasto = map_dbl(delta_pct, media_gasto_delta))
print(sens)
cat("Media real de gasto:", mean(verdad$gasto_real), "\n")

# Ejercicio 2
set.seed(7)
split <- initial_split(datos |> select(ciudad, edad, ingreso, gasto, compra),
                       prop = 0.8, strata = compra)
train <- training(split)
test  <- testing(split)

train <- train |> mutate(compra = factor(compra))
test  <- test  |> mutate(compra = factor(compra))

receta_ok <- recipe(compra ~ ., data = train) |>
  step_impute_median(all_numeric_predictors()) |>
  step_impute_mode(all_nominal_predictors()) |>
  step_dummy(all_nominal_predictors()) |>
  prep(training = train)

train_proc <- bake(receta_ok, new_data = NULL)
test_proc  <- bake(receta_ok, new_data = test)

stopifnot(sum(is.na(train_proc)) == 0, sum(is.na(test_proc)) == 0)

receta_ext <- recipe(compra ~ ., data = train) |>
  step_indicate_na(ingreso) |>
  step_impute_bag(ingreso, gasto,
                  impute_with = imp_vars(all_predictors()),
                  trees = 25, seed_val = 123) |>
  step_dummy(all_nominal_predictors()) |>
  step_zv(all_predictors()) |>
  step_normalize(all_numeric_predictors())

wf_ext <- workflow() |>
  add_recipe(receta_ext) |>
  add_model(logistic_reg())

fit_ext <- fit(wf_ext, data = train)

pred_ext <- augment(fit_ext, test)
roc_auc(pred_ext, truth = compra, .pred_0)
conf_mat(pred_ext, truth = compra, estimate = .pred_class)

wf_base <- workflow() |>
  add_recipe(recipe(compra ~ ., data = train) |>
               step_impute_median(all_numeric_predictors()) |>
               step_impute_mode(all_nominal_predictors()) |>
               step_dummy(all_nominal_predictors())) |>
  add_model(logistic_reg())
fit_base <- fit(wf_base, data = train)
roc_auc(augment(fit_base, test), truth = compra, .pred_0)
