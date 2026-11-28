# =============================================================================
# Minería de Datos — Clase 7: Limpieza, transformación y normalización
# Ejercicios prácticos 1 a 6
# Autor: David Márquez
# =============================================================================
# Datos: carpeta data/ del curso (house_prices.csv, titanic.csv,
# mobile_data.csv, adult.csv, netflix_titles.csv).
# Las partes "(Python)" van al final de cada ejercicio como comentario.
# install.packages(c("tidyverse"))
library(tidyverse)

set.seed(2024)

# =============================================================================
# EJERCICIO 1: faltantes que no son faltantes (house_prices.csv)
# =============================================================================
precios <- read_csv("david_esteban_marquez_bayona/Taller_06/house_prices.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------------
# 1a. % de NA por columna y regla de > 50 %
# -----------------------------------------------------------------------------
pct_na <- precios |>
  map_dbl(~ mean(is.na(.x))) |>
  enframe(name = "columna", value = "pct_na") |>
  mutate(pct_na = round(100 * pct_na, 1)) |>
  arrange(desc(pct_na))
pct_na |> filter(pct_na > 0) |> print(n = Inf)

cols_perdidas <- pct_na |> filter(pct_na > 50) |> pull(columna)
cols_perdidas
precios_regla <- precios |> select(where(~ mean(is.na(.x)) <= 0.5))
stopifnot(ncol(precios_regla) == ncol(precios) - length(cols_perdidas))

# Qué se pierde con PoolQC: el NA significa "no tiene piscina"
count(precios, PoolQC)
count(precios, tiene_piscina = PoolArea > 0)
# Justificación: PoolQC tiene > 99 % de NA porque casi ninguna casa tiene
# piscina, no porque se haya perdido el dato. Eliminarla bota la calidad de la
# piscina de las pocas que sí tienen, y ese es justo el grupo de precios altos.

# -----------------------------------------------------------------------------
# 1b. ¿NA = "no tiene"? Cruce con el área
# -----------------------------------------------------------------------------
grupos <- list(
  garaje = list(cols = c("GarageType", "GarageFinish", "GarageQual", "GarageCond"),
                area = "GarageArea"),
  sotano = list(cols = c("BsmtQual", "BsmtCond", "BsmtExposure",
                         "BsmtFinType1", "BsmtFinType2"),
                area = "TotalBsmtSF"),
  piscina = list(cols = "PoolQC", area = "PoolArea")
)

# Faltante real: (NA y área > 0) o área NA, o (no NA y área == 0)
diagnostico_grupo <- function(df, cols, area) {
  a <- df[[area]]
  map_dfr(cols, function(cl) {
    x <- df[[cl]]
    tibble(columna = cl, area = area,
           na_estructural = sum(is.na(x) & !is.na(a) & a == 0),
           na_real        = sum(is.na(x) & (is.na(a) | a > 0)),
           dato_sin_area  = sum(!is.na(x) & !is.na(a) & a == 0))
  })
}
diag_1b <- map_dfr(grupos, ~ diagnostico_grupo(precios, .x$cols, .x$area),
                   .id = "grupo")
diag_1b
diag_1b |> group_by(grupo) |> summarise(faltantes_reales = sum(na_real))

# Filas donde falla la coincidencia (para revisarlas)
filas_falla <- imap(grupos, function(g, nm) {
  a <- precios[[g$area]]
  falla <- map(g$cols, ~ is.na(precios[[.x]]) & (is.na(a) | a > 0)) |>
    reduce(`|`)
  precios |> filter(falla) |> select(Id, all_of(g$area), all_of(g$cols))
})
filas_falla

# -----------------------------------------------------------------------------
# 1c. recodificar_ausencia(): solo NA estructurales -> "Ninguno"
# -----------------------------------------------------------------------------
recodificar_ausencia <- function(df, cols, area) {
  a <- df[[area]]
  estructural <- !is.na(a) & a == 0
  df |>
    mutate(across(all_of(cols) & where(is.character),
                  ~ if_else(is.na(.x) & estructural, "Ninguno", .x)))
}

precios_rec <- reduce(grupos, function(d, g) recodificar_ausencia(d, g$cols, g$area),
                      .init = precios)

# Comprobación: los NA que quedan son exactamente los faltantes reales
na_restantes <- map_int(unlist(map(grupos, "cols")), ~ sum(is.na(precios_rec[[.x]])))
stopifnot(sum(na_restantes) == sum(diag_1b$na_real))
tibble(columna = unlist(map(grupos, "cols")),
       na_antes = map_int(columna, ~ sum(is.na(precios[[.x]]))),
       na_despues = na_restantes)

# -----------------------------------------------------------------------------
# 1d. LotFrontage: mediana por barrio vs. mediana global
# -----------------------------------------------------------------------------
med_global <- median(precios$LotFrontage, na.rm = TRUE)
precios_rec <- precios_rec |>
  mutate(lf_global = coalesce(LotFrontage, med_global)) |>
  mutate(med_barrio = median(LotFrontage, na.rm = TRUE), .by = Neighborhood) |>
  mutate(lf_barrio = coalesce(LotFrontage, med_barrio, med_global))
stopifnot(!anyNA(precios_rec$lf_global), !anyNA(precios_rec$lf_barrio))

dif_barrio <- precios_rec |>
  summarise(n_na = sum(is.na(LotFrontage)),
            mediana_barrio = first(med_barrio), .by = Neighborhood) |>
  mutate(diferencia = mediana_barrio - med_global) |>
  arrange(desc(abs(diferencia)))
dif_barrio

ggplot(dif_barrio, aes(x = reorder(Neighborhood, diferencia), y = diferencia,
                       fill = diferencia > 0)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_fill_manual(values = c(`TRUE` = "#2166ac", `FALSE` = "#b2182b")) +
  labs(title = "LotFrontage: mediana del barrio - mediana global",
       x = NULL, y = "Diferencia (pies)") +
  theme_minimal()

# -----------------------------------------------------------------------------
# 1e. Edad de la vivienda y años imposibles
# -----------------------------------------------------------------------------
precios_rec <- precios_rec |> mutate(edad_vivienda = YrSold - YearBuilt)

imposibles <- precios_rec |>
  filter(edad_vivienda < 0 |
           (!is.na(GarageYrBlt) & GarageYrBlt > YrSold) |
           YearBuilt > 2010 | YearRemodAdd > 2010 |
           (!is.na(GarageYrBlt) & GarageYrBlt > 2010)) |>
  select(Id, YearBuilt, YearRemodAdd, GarageYrBlt, YrSold, edad_vivienda)
imposibles

# Decisiones:
# - GarageYrBlt > 2010 (p. ej. 2207): error de digitación evidente; se corrige
#   restando 200 si así queda entre YearBuilt y YrSold; si no, NA.
# - GarageYrBlt > YrSold (pero <= 2010): el garaje se registró como construido
#   después de la venta; no es verificable -> NA (no se borra la casa).
# - edad_vivienda < 0: venta sobre planos (se vendió antes de terminarla);
#   se corrige a 0 en vez de eliminar la fila.
precios_rec <- precios_rec |>
  mutate(
    garage_ok = case_when(
      is.na(GarageYrBlt) ~ NA_real_,
      GarageYrBlt > 2010 & between(GarageYrBlt - 200, YearBuilt, YrSold) ~
        GarageYrBlt - 200,
      GarageYrBlt > 2010 ~ NA_real_,
      GarageYrBlt > YrSold ~ NA_real_,
      TRUE ~ GarageYrBlt),
    dato_corregido = case_when(
      edad_vivienda < 0 ~ TRUE,
      !is.na(GarageYrBlt) & (GarageYrBlt > 2010 | GarageYrBlt > YrSold) ~ TRUE,
      TRUE ~ FALSE),
    edad_vivienda = case_when(edad_vivienda < 0 ~ 0, TRUE ~ edad_vivienda),
    GarageYrBlt = garage_ok
  ) |>
  select(-garage_ok)
count(precios_rec, dato_corregido)
stopifnot(all(precios_rec$edad_vivienda >= 0),
          all(precios_rec$GarageYrBlt <= precios_rec$YrSold, na.rm = TRUE))

# -----------------------------------------------------------------------------
# 1f. Cuartiles con cut() vs. ntile()
# -----------------------------------------------------------------------------
cortes <- quantile(precios_rec$edad_vivienda, probs = seq(0, 1, 0.25))
cortes
precios_rec <- precios_rec |>
  mutate(grupo_cut   = cut(edad_vivienda, breaks = unique(cortes),
                           include.lowest = TRUE),
         grupo_ntile = ntile(edad_vivienda, 4))
table(precios_rec$grupo_cut, precios_rec$grupo_ntile)

# Edades repartidas entre dos grupos de ntile (empates partidos)
precios_rec |>
  summarise(n_grupos = n_distinct(grupo_ntile), .by = edad_vivienda) |>
  filter(n_grupos > 1)

# SalePrice solo existe en las filas de entrenamiento (en test es NA)
precios_rec |>
  summarise(n = n(), mediana_precio = median(SalePrice, na.rm = TRUE),
            .by = grupo_cut) |> arrange(grupo_cut)
precios_rec |>
  summarise(n = n(), mediana_precio = median(SalePrice, na.rm = TRUE),
            .by = grupo_ntile) |> arrange(grupo_ntile)

# =============================================================================
# EJERCICIO 2: ¿qué es un outlier en fare? (titanic.csv)
# =============================================================================
titanic <- read_csv("david_esteban_marquez_bayona/Taller_06/titanic.csv", show_col_types = FALSE)

es_outlier_iqr <- function(x, k = 1.5) {
  q <- quantile(x, c(.25, .75), na.rm = TRUE); r <- q[[2]] - q[[1]]
  x < q[[1]] - k * r | x > q[[2]] + k * r
}

# 2a. IQR global con k = 1.5 y k = 3
tit <- titanic |>
  filter(!is.na(fare)) |>
  mutate(out_15 = es_outlier_iqr(fare, 1.5),
         out_3  = es_outlier_iqr(fare, 3))
tit |> summarise(pct_k15 = 100 * mean(out_15), pct_k3 = 100 * mean(out_3))

# 2b. IQR dentro de cada clase
tit <- tit |> mutate(out_clase = es_outlier_iqr(fare, 1.5), .by = pclass)
tit |> summarise(global = sum(out_15), por_clase = sum(out_clase), .by = pclass)
cat("Pasajeros de 1.ª clase que dejan de ser outliers:",
    sum(tit$out_15 & !tit$out_clase & tit$pclass == 1), "\n")

# 2c. Z-score robusto
tit <- tit |> mutate(z_rob = (fare - median(fare)) / mad(fare),
                     out_rob = abs(z_rob) > 3.5,
                     z_clas = (fare - mean(fare)) / sd(fare))
summarise(tit, out_robusto = sum(out_rob), out_z_clasico = sum(abs(z_clas) > 3))

# 2d. Cruce de los tres criterios
count(tit, out_15, out_clase, out_rob)
tit |> filter(out_rob & !out_15) |> select(name, pclass, fare)  # solo robusto
tit |> filter(out_clase & !out_15) |> select(name, pclass, fare) # solo por clase

# 2e. Tarifas en cero
cero <- titanic |> filter(fare == 0)
nrow(cero)
cero |> select(name, pclass, age, ticket, embarked, survived)
count(cero, pclass); count(cero, ticket, sort = TRUE)
# Propuesta: convertir a NA e imputar con la mediana de su clase (ver
# respuestas). Bandera para no perder la información:
titanic <- titanic |>
  mutate(fare_cero = !is.na(fare) & fare == 0,
         fare_lim  = if_else(fare_cero, NA_real_, fare)) |>
  mutate(fare_lim = coalesce(fare_lim, median(fare_lim, na.rm = TRUE)),
         .by = pclass)
stopifnot(!anyNA(titanic$fare_lim), all(titanic$fare_lim > 0))

# 2f. log1p y criterio IQR
tit <- tit |> mutate(out_log = es_outlier_iqr(log1p(fare), 1.5))
summarise(tit, out_original = sum(out_15), out_log = sum(out_log))
tit |> filter(out_log) |> select(name, pclass, fare)

# =============================================================================
# EJERCICIO 3: ¿qué estrategia de imputación se equivoca menos? (titanic.csv)
# =============================================================================
titanic <- titanic |>
  mutate(titulo_raw = str_trim(str_match(name, ",\\s*([^\\.]+)\\.")[, 2]),
         titulo = case_when(
           titulo_raw %in% c("Mr", "Mrs", "Miss", "Master") ~ titulo_raw,
           TRUE ~ "Otro"))
count(titanic, titulo)

con_edad <- titanic |> filter(!is.na(age))
stopifnot(nrow(con_edad) == 1046)

simular_imputacion <- function(semilla, datos = con_edad, prop = 0.2) {
  set.seed(semilla)
  ocultar <- sample(nrow(datos), round(prop * nrow(datos)))
  d <- datos |>
    mutate(age_real = age,
           oculto = row_number() %in% ocultar,
           age = if_else(oculto, NA_real_, age))
  # Medianas SOLO con las edades no ocultas (age ya es NA en las ocultas)
  med_g <- median(d$age, na.rm = TRUE)
  d <- d |>
    mutate(imp_global = coalesce(age, med_g)) |>
    mutate(imp_clase_sexo = coalesce(age, median(age, na.rm = TRUE)),
           .by = c(pclass, sex)) |>
    mutate(imp_titulo = coalesce(age, median(age, na.rm = TRUE)),
           .by = titulo) |>
    mutate(imp_titulo = coalesce(imp_titulo, med_g))
  d |>
    filter(oculto) |>
    pivot_longer(starts_with("imp_"), names_to = "estrategia",
                 values_to = "age_imp") |>
    summarise(MAE = mean(abs(age_imp - age_real)),
              RMSE = sqrt(mean((age_imp - age_real)^2)), .by = estrategia) |>
    mutate(semilla = semilla)
}

# 3a-3c con set.seed(2024)
res_2024 <- simular_imputacion(2024)
res_2024 |> arrange(MAE)

# 3d. 200 repeticiones
res_200 <- map(1:200, simular_imputacion) |> list_rbind()
res_200 |> summarise(MAE_medio = mean(MAE), RMSE_medio = mean(RMSE),
                     .by = estrategia)
ganador <- res_2024$estrategia[which.min(res_2024$MAE)]
pct_gana <- res_200 |>
  slice_min(MAE, n = 1, by = semilla, with_ties = FALSE) |>
  count(estrategia) |>
  mutate(pct = 100 * n / sum(n))
pct_gana
ggplot(res_200, aes(x = estrategia, y = MAE, fill = estrategia)) +
  geom_boxplot(show.legend = FALSE) +
  labs(title = "MAE de imputación de age en 200 simulaciones",
       x = NULL, y = "MAE (años)") +
  theme_minimal()

# 3e. Variabilidad tras imputar (con la semilla 2024)
set.seed(2024)
ocultar <- sample(nrow(con_edad), round(0.2 * nrow(con_edad)))
d_sd <- con_edad |>
  mutate(age_obs = if_else(row_number() %in% ocultar, NA_real_, age)) |>
  mutate(imp_global = coalesce(age_obs, median(age_obs, na.rm = TRUE))) |>
  mutate(imp_clase_sexo = coalesce(age_obs, median(age_obs, na.rm = TRUE)),
         .by = c(pclass, sex)) |>
  mutate(imp_titulo = coalesce(age_obs, median(age_obs, na.rm = TRUE)),
         .by = titulo)
d_sd |> summarise(across(c(age, imp_global, imp_clase_sexo, imp_titulo), sd))

# 3f. (Python) estrategia 2
# import pandas as pd, numpy as np
# tit = pd.read_csv("data/titanic.csv")
# d = tit[tit["age"].notna()].copy()            # mismas filas ocultas que en R:
# d["oculto"] = oculto_desde_R                   # exportar el vector desde R
# d["age_obs"] = d["age"].where(~d["oculto"])
# d["imp_clase_sexo"] = d["age_obs"].fillna(
#     d.groupby(["pclass", "sex"])["age_obs"].transform("median"))
# # Verificación: np.allclose(d["imp_clase_sexo"], valores_R)
# Para comparar, exporte desde R:
write_csv(d_sd |> select(name, age, age_obs, imp_clase_sexo),
          "david_esteban_marquez_bayona/Taller_06/imputacion_clase_sexo_R.csv")

# =============================================================================
# EJERCICIO 4: escalado, outliers y fuga de información (mobile_data.csv)
# =============================================================================
moviles <- read_csv("david_esteban_marquez_bayona/Taller_06/mobile_data.csv", show_col_types = FALSE)
vars_m <- c("ram", "battery_power", "int_memory", "px_height", "px_width")

# 4a. Función de escalado
escalar <- function(df, cols, metodo = c("minmax", "zscore", "robusto")) {
  metodo <- match.arg(metodo)
  f <- switch(metodo,
    minmax  = function(x) (x - min(x, na.rm = TRUE)) /
                          (max(x, na.rm = TRUE) - min(x, na.rm = TRUE)),
    zscore  = function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE),
    robusto = function(x) (x - median(x, na.rm = TRUE)) / IQR(x, na.rm = TRUE))
  df |> select(all_of(cols)) |> mutate(across(everything(), f))
}
stopifnot(all(range(escalar(moviles, vars_m, "minmax")) == c(0, 1)))

# 4b. Aporte de cada variable a la distancia euclidiana^2 entre filas 1 y 2
aporte_distancia <- function(df) {
  d2 <- (unlist(df[1, ]) - unlist(df[2, ]))^2
  round(100 * d2 / sum(d2), 1)
}
aportes <- tibble(
  variable   = vars_m,
  sin_escalar = aporte_distancia(moviles[, vars_m]),
  minmax     = aporte_distancia(escalar(moviles, vars_m, "minmax")),
  zscore     = aporte_distancia(escalar(moviles, vars_m, "zscore")),
  robusto    = aporte_distancia(escalar(moviles, vars_m, "robusto"))
)
aportes

# 4c. Un valor extremo en ram
mov_out <- moviles; mov_out$ram[1] <- 100000
sd_resto <- map_dbl(c("minmax", "zscore", "robusto"),
                    ~ sd(escalar(mov_out, "ram", .x)$ram[-1])) |>
  set_names(c("minmax", "zscore", "robusto"))
sd_resto
sd_resto_sin_out <- map_dbl(c("minmax", "zscore", "robusto"),
                            ~ sd(escalar(moviles, "ram", .x)$ram[-1]))
rbind(con_outlier = sd_resto, sin_outlier = sd_resto_sin_out)

# 4d. Fuga de información
set.seed(2024)
idx_tr <- sample(nrow(moviles), round(0.7 * nrow(moviles)))
train_m <- moviles[idx_tr, ]; test_m <- moviles[-idx_tr, ]
mins <- map_dbl(train_m[vars_m], min); maxs <- map_dbl(train_m[vars_m], max)
test_esc <- map2_dfc(test_m[vars_m], names(test_m[vars_m]),
                     ~ (.x - mins[[.y]]) / (maxs[[.y]] - mins[[.y]]))
fuera <- sum(test_esc < 0 | test_esc > 1)
cat("Valores de prueba fuera de [0, 1]:", fuera, "de", length(unlist(test_esc)),
    sprintf("(%.2f%%)\n", 100 * fuera / length(unlist(test_esc))))
map_int(test_esc, ~ sum(.x < 0 | .x > 1))
# Escalar todo junto (fuga): todos quedan en [0, 1] porque min/max se
# calcularon viendo la prueba
todo_esc <- escalar(moviles, vars_m, "minmax")
sum(todo_esc[-idx_tr, ] < 0 | todo_esc[-idx_tr, ] > 1)

# 4e. (Python)
# import pandas as pd
# from sklearn.model_selection import train_test_split
# from sklearn.preprocessing import MinMaxScaler
# mov = pd.read_csv("data/mobile_data.csv")
# cols = ["ram", "battery_power", "int_memory", "px_height", "px_width"]
# X_tr, X_te = train_test_split(mov[cols], test_size=0.3, random_state=2024)
# esc = MinMaxScaler().fit(X_tr)            # fit SOLO con entrenamiento
# X_te_esc = esc.transform(X_te)
# fuera = ((X_te_esc < 0) | (X_te_esc > 1)).mean() * 100
# print(f"% fuera de [0, 1]: {fuera:.2f}%")
# (La partición de Python no es la misma que la de R, así que el porcentaje
#  es parecido pero no idéntico.)

# =============================================================================
# EJERCICIO 5: pipeline funcional y reutilizable (adult.csv)
# =============================================================================
adult <- read_csv("david_esteban_marquez_bayona/Taller_06/adult.csv", show_col_types = FALSE)

# 5a. "?" -> NA y ¿el faltante de occupation es MCAR?
limpiar_signos <- function(df, ...) {
  df |> mutate(across(where(is.character), ~ na_if(str_trim(.x), "?")))
}
ad <- limpiar_signos(adult)
colSums(is.na(ad))
tab_occ <- ad |>
  mutate(occ_falta = is.na(occupation)) |>
  summarise(n = n(), ricos = sum(income == ">50K"),
            pct_mayor50k = 100 * mean(income == ">50K"), .by = occ_falta)
tab_occ
prop.test(x = tab_occ$ricos, n = tab_occ$n)

# 5b. Valor centinela en capital.gain
sum(ad$capital.gain == 99999)
sort(unique(ad$capital.gain), decreasing = TRUE)[1:3]
100 * mean(ad$capital.gain == 0)

# 5c. Una función por paso. Los pasos que dependen de los datos reciben
#     `p` (parámetros estimados en entrenamiento) -> 5e.
tratar_centinela <- function(df, ...) {
  df |> mutate(gain_centinela = as.integer(capital.gain == 99999),
               capital.gain = if_else(capital.gain == 99999, NA_real_,
                                      capital.gain))
}
agrupar_paises <- function(df, ...) {
  df |> mutate(native.country = case_when(
    is.na(native.country) ~ NA_character_,
    native.country == "United-States" ~ "Estados Unidos",
    TRUE ~ "Otro"))
}
imputar <- function(df, p) {
  df |>
    mutate(
      occupation = coalesce(occupation, "Desconocido"),   # no MCAR -> categoría
      workclass  = coalesce(workclass,  "Desconocido"),
      native.country = coalesce(native.country, p$moda_pais),
      capital.gain = coalesce(capital.gain, p$mediana_gain_pos))
}
transformar_log <- function(df, ...) {
  df |> mutate(capital.gain = log1p(capital.gain),
               capital.loss = log1p(capital.loss))
}
codificar <- function(df, p) {
  for (v in names(p$niveles)) {
    x <- factor(df[[v]], levels = p$niveles[[v]])        # niveles de train
    for (nv in p$niveles[[v]][-1]) {                     # sin la 1.ª (referencia)
      df[[paste0(v, "_", make.names(nv))]] <- as.integer(!is.na(x) & x == nv)
    }
    df[[v]] <- NULL
  }
  df |>
    mutate(income = as.integer(income == ">50K"),
           pais_otro = as.integer(native.country == "Otro")) |>
    select(-native.country, -education, -occupation, -relationship, -race)
}
estandarizar <- function(df, p) {
  for (v in names(p$medias)) df[[v]] <- (df[[v]] - p$medias[[v]]) / p$des[[v]]
  df
}

# 5e. Parámetros estimados SOLO con entrenamiento
vars_cod <- c("workclass", "marital.status", "sex")
vars_num <- c("age", "fnlwgt", "education.num", "capital.gain",
              "capital.loss", "hours.per.week")
ajustar_parametros <- function(train_raw) {
  t1 <- train_raw |> limpiar_signos() |> tratar_centinela() |> agrupar_paises()
  p <- list(
    moda_pais = names(which.max(table(t1$native.country))),
    mediana_gain_pos = median(t1$capital.gain[t1$capital.gain > 0], na.rm = TRUE)
  )
  t2 <- t1 |> imputar(p)
  p$niveles <- map(set_names(vars_cod), ~ sort(unique(t2[[.x]])))
  t3 <- t2 |> transformar_log()
  p$medias <- map(set_names(vars_num), ~ mean(t3[[.x]]))
  p$des    <- map(set_names(vars_num), ~ sd(t3[[.x]]))
  p
}

# 5d. Composición con reduce() y verificaciones
pasos <- list(limpiar_signos, tratar_centinela, agrupar_paises, imputar,
              transformar_log, codificar, estandarizar)
preprocesar_adult <- function(df, p = ajustar_parametros(df)) {
  salida <- reduce(pasos, function(d, f) f(d, p), .init = df)
  stopifnot(!anyNA(salida),
            all(map_lgl(salida, is.numeric)),
            nrow(salida) == nrow(df))
  salida
}

adult_listo <- preprocesar_adult(adult)
glimpse(adult_listo)

# Partición 70/30: parámetros con train, aplicados a test
set.seed(2024)
idx_a <- sample(nrow(adult), round(0.7 * nrow(adult)))
train_a <- adult[idx_a, ]; test_a <- adult[-idx_a, ]
params <- ajustar_parametros(train_a)
train_proc <- preprocesar_adult(train_a, params)
test_proc  <- preprocesar_adult(test_a,  params)
stopifnot(identical(names(train_proc), names(test_proc)))
round(colMeans(train_proc[vars_num]), 3)   # ~0 en train
round(colMeans(test_proc[vars_num]), 3)    # cerca de 0, no exactamente

# 5f. (Python)
# import pandas as pd, numpy as np
# from sklearn.model_selection import train_test_split
# from sklearn.pipeline import Pipeline
# from sklearn.compose import ColumnTransformer
# from sklearn.impute import SimpleImputer
# from sklearn.preprocessing import OneHotEncoder, StandardScaler
# ad = pd.read_csv("data/adult.csv")
# ad = ad.apply(lambda s: s.str.strip() if s.dtype == "object" else s).replace("?", np.nan)
# y = (ad.pop("income") == ">50K").astype(int)
# num = ["age", "fnlwgt", "education.num", "capital.gain", "capital.loss", "hours.per.week"]
# cat = ["workclass", "marital.status", "sex", "occupation", "native.country"]
# pre = ColumnTransformer([
#     ("num", Pipeline([("imp", SimpleImputer(strategy="median")),
#                       ("esc", StandardScaler())]), num),
#     ("cat", Pipeline([("imp", SimpleImputer(strategy="constant",
#                                             fill_value="Desconocido")),
#                       ("ohe", OneHotEncoder(handle_unknown="ignore"))]), cat)])
# X_tr, X_te, y_tr, y_te = train_test_split(ad, y, test_size=0.3, random_state=2024)
# pre.fit(X_tr)                    # medianas, medias, DE y categorías: solo train
# X_tr_p, X_te_p = pre.transform(X_tr), pre.transform(X_te)

# =============================================================================
# EJERCICIO 6 (reto opcional): netflix_titles.csv
# =============================================================================
netflix <- read_csv("david_esteban_marquez_bayona/Taller_06/netflix_titles.csv", show_col_types = FALSE)

# 6a. duration desplazada a rating
mal_ubicadas <- netflix |> filter(is.na(duration), str_detect(rating, "min$"))
mal_ubicadas |> select(show_id, title, rating, duration)
netflix <- netflix |>
  mutate(desplazado = is.na(duration) & str_detect(coalesce(rating, ""), "min$"),
         duration = if_else(desplazado, rating, duration),
         rating   = if_else(desplazado, NA_character_, rating))
stopifnot(sum(netflix$desplazado) == nrow(mal_ubicadas),
          !any(str_detect(netflix$rating, "min$"), na.rm = TRUE))

# 6b. Valor y unidad de la duración
netflix <- netflix |>
  mutate(duracion_valor  = as.numeric(str_extract(duration, "\\d+")),
         duracion_unidad = case_when(
           str_detect(duration, "min") ~ "min",
           str_detect(duration, "Season") ~ "temporadas"))
count(netflix, type, duracion_unidad)
netflix |> summarise(promedio = mean(duracion_valor, na.rm = TRUE),
                     .by = c(type, duracion_unidad))

# 6c. Fechas en inglés
netflix <- netflix |>
  mutate(fecha_agregado = parse_date(str_trim(date_added), "%B %d, %Y",
                                     locale = locale("en")),
         rezago = year(fecha_agregado) - release_year)
sum(is.na(netflix$fecha_agregado) & !is.na(netflix$date_added))  # fallos de parseo
summary(netflix$rezago)
netflix |> filter(rezago < 0) |>
  select(title, type, release_year, date_added, rezago)

# 6d. Géneros
generos <- netflix |>
  separate_longer_delim(listed_in, delim = ",") |>
  mutate(listed_in = str_trim(listed_in))
c(filas_antes = nrow(netflix), filas_despues = nrow(generos))
generos |> count(type, listed_in, sort = TRUE) |>
  slice_max(n, n = 10, by = type)

# 6e. Países
netflix <- netflix |>
  mutate(n_paises = if_else(is.na(country), NA_integer_,
                            str_count(country, ",") + 1L),
         coproduccion = n_paises > 1)
count(netflix, n_paises)
count(netflix, coproduccion)

# =============================================================================
# RESPUESTAS Y JUSTIFICACIONES
# =============================================================================
# Nota: no tuve los CSV del curso al resolver; las cifras exactas salen de la
# consola al correr el script. Lo que va aquí son las decisiones, el
# razonamiento y los valores conocidos de estos datasets públicos.
#
# EJERCICIO 1
# a. Con la regla de 50 % se pierden PoolQC, MiscFeature, Alley y Fence
#    (FireplaceQu queda justo por debajo, ~49 %). En todas el NA significa
#    "no tiene" (piscina, otro elemento, callejón, cerca). Al borrar PoolQC
#    se pierde la calidad de la piscina de las pocas casas que la tienen, que
#    suelen ser casas caras: es información, no ruido.
# b. Casi todos los NA de Garage*, Bsmt* y PoolQC coinciden con área = 0
#    (estructurales). Los que fallan son pocos: casas con garaje (área > 0)
#    pero sin GarageFinish/Qual/Cond, sótanos con área > 0 pero sin
#    BsmtExposure o BsmtFinType2, piscinas con área > 0 sin PoolQC, y filas
#    con el área en NA. La tabla diag_1b da el conteo por grupo.
# c. recodificar_ausencia() solo cambia a "Ninguno" donde el área es 0; los
#    faltantes reales siguen NA para imputarlos después (stopifnot lo verifica).
# d. La mediana por barrio difiere bastante de la global en barrios con lotes
#    grandes o muy pequeños (p. ej. barrios de townhouses con frentes cortos).
#    La mediana por barrio es mejor porque el frente del lote depende del
#    tipo de urbanización.
# e. Hay garajes con año 2207 (error evidente de 2007), casas con fecha de
#    remodelación o garaje posterior a la venta y ventas antes de terminar la
#    construcción (edad negativa). Se corrige lo evidente (2207 -> 2007),
#    se pone NA lo no verificable y la edad negativa se lleva a 0; no se
#    eliminan filas, y dato_corregido deja la traza.
# f. cut() y ntile() casi coinciden pero no del todo. ntile() reparte las
#    filas en 4 grupos del mismo tamaño ordenándolas, así que si muchas casas
#    tienen la misma edad justo en un corte, parte queda en un grupo y parte
#    en el siguiente. cut() usa los valores de corte: dos casas con la misma
#    edad siempre caen en el mismo intervalo (los grupos pueden quedar de
#    tamaños distintos). La mediana de SalePrice baja a medida que aumenta la
#    edad: las casas nuevas son las más caras.
#
# EJERCICIO 2
# a. k = 1,5 marca cerca de 13 % de los pasajeros; k = 3 marca bastante menos
#    (ver salida). La tarifa tiene cola derecha muy larga.
# b. Dentro de cada clase, muchos pasajeros de 1.ª clase dejan de ser
#    outliers: comparar su tarifa con la distribución global (dominada por
#    3.ª clase) es injusto, porque una tarifa alta es lo normal en 1.ª clase.
# c. El z-score robusto usa mediana y MAD, que no se mueven con los extremos.
#    El z-score clásico usa media y DE, que los propios extremos inflan, así
#    que un valor extremo "se esconde" (efecto de enmascaramiento).
# d. Ver count(tit, out_15, out_clase, out_rob): el robusto es el más
#    estricto con la cola derecha (la MAD de fare es pequeña); el criterio
#    por clase marca algunos pasajeros de 2.ª y 3.ª clase con tarifas altas
#    para su clase que el global no marca.
# e. Los 17 pasajeros con fare = 0 están en las tres clases y varios comparten
#    tiquete (tripulación/empleados de la naviera, invitados). No son outliers
#    estadísticos sino faltantes disfrazados: nadie pagó 0 por error de
#    medición. Decisión: bandera fare_cero y convertir a NA, imputando con la
#    mediana de su clase para modelos que usan fare como poder adquisitivo.
# f. Con log1p quedan muy pocos outliers. Transformar no elimina los
#    extremos: los acerca en la escala. Sirve para modelos sensibles a la
#    escala, pero no responde si el valor es correcto; eso hay que revisarlo.
#
# EJERCICIO 3
# c. La mediana por título suele ganar: el título resume edad y sexo (Master
#    = niño, Miss = soltera, a menudo joven), mejor que clase y sexo. La
#    mediana global es la peor.
# d. El ganador no gana en el 100 % de las repeticiones (ver pct_gana): en
#    algunas muestras la estrategia por clase y sexo queda por encima. Por eso
#    hay que repetir: una sola partición puede engañar.
# e. La DE baja tras imputar con una mediana: muchos valores idénticos
#    concentran la distribución. Un modelo vería menos variabilidad de la
#    real, subestimaría errores estándar y atenuaría el efecto de la edad.
#
# EJERCICIO 4
# b. Sin escalar domina ram (valores en miles, diferencias grandes) y aporta
#    casi toda la distancia. Tras escalar, el reparto entre variables queda
#    mucho más equilibrado.
# c. Min-max colapsa a las demás: el máximo pasa a 100000, así que las otras
#    2999 quedan apretadas cerca de 0 (DE diminuta). El z-score también se
#    ve afectado (la DE se infla). El robusto (mediana, IQR) casi no cambia.
# d. Con min/max de entrenamiento, algunos valores de prueba quedan fuera de
#    [0, 1] (los que superan el rango de train). Escalar todo junto usa
#    información de la prueba (su mínimo y máximo), aunque no se use
#    price_range: el modelo "ve" la distribución de datos que se supone
#    nuevos y la evaluación queda optimista.
#
# EJERCICIO 5
# a. La proporción de >50K es mucho menor cuando falta occupation, y
#    prop.test da p muy pequeño: no es MCAR. Imputar con la moda mezclaría a
#    esas personas con otra ocupación; es mejor la categoría "Desconocido",
#    que conserva la señal de la ausencia.
# b. 99999 es un tope/centinela: hay un salto grande respecto al siguiente
#    valor más alto, y > 90 % de las filas valen 0. Decisión: bandera
#    gain_centinela + convertir 99999 a NA e imputar con la mediana de los
#    positivos, y después log1p para la asimetría. La bandera conserva que
#    son personas de ingresos de capital muy altos.
# e. Se guardan: moda de native.country, mediana de capital.gain positiva,
#    niveles de los factores (para que las dummies de test sean las mismas
#    aunque falte o sobre una categoría) y medias/DE para estandarizar.
# f. fit solo con train porque si no, medianas, medias y categorías
#    incorporan la prueba (fuga). handle_unknown="ignore" evita que el
#    pipeline falle si en datos nuevos aparece una categoría no vista.
#
# EJERCICIO 6
# a. Las tres filas tienen la duración ("74 min", "84 min", "66 min") en
#    rating: se mueve a duration y rating queda NA.
# b. Las películas se miden en minutos y las series en temporadas: promediar
#    juntas mezcla unidades distintas. Se promedia por type.
# c. Hay rezagos negativos: títulos agregados antes del año de estreno
#    registrado (estrenos exclusivos de Netflix o un release_year que
#    corresponde a la última temporada en series).
# d. Una fila por género: el número de filas crece. No se puede sumar para
#    contar títulos porque un título con 3 géneros se contaría 3 veces.
# e. Para análisis por país dejaría NA (no inventar un país); para un
#    modelo, "Desconocido" + bandera, porque la ausencia puede ser
#    informativa. coproduccion queda NA donde no hay país.
