# Minería de Datos - Clase 7: limpieza, transformación y normalización
# 9. Ejercicios prácticos

paquetes   <- c("dplyr", "tidyr", "readr", "stringr", "purrr", "tibble",
                "ggplot2", "lubridate")
pendientes <- setdiff(paquetes, rownames(installed.packages()))
if (length(pendientes) > 0) install.packages(pendientes)

library(dplyr)
library(tidyr)
library(readr)
library(stringr)
library(purrr)
library(tibble)
library(ggplot2)
library(lubridate)

ruta_datos <- "C:/Users/Administrar/OneDrive/Escritorio/6 SEXTO SEMESTRE/Minería de Datos/DATOS"
leer <- function(archivo) read_csv(file.path(ruta_datos, archivo), show_col_types = FALSE)

house   <- leer("house_prices.csv")
titanic <- leer("titanic.csv")
mobile  <- leer("mobile_data.csv")
adult   <- leer("adult.csv")
netflix <- leer("netflix_titles.csv")


# =========================================================================
# Ejercicio 1: faltantes que no son faltantes (house_prices)
# =========================================================================

# a. porcentaje de NA por columna
pct_na <- house %>%
  summarise(across(everything(), ~ mean(is.na(.x)) * 100)) %>%
  pivot_longer(everything(), names_to = "columna", values_to = "pct_na") %>%
  filter(pct_na > 0) %>%
  arrange(desc(pct_na))
pct_na

cols_perdidas <- pct_na %>% filter(pct_na > 50) %>% pull(columna)
cols_perdidas

house %>% count(con_piscina = PoolArea > 0, PoolQC_na = is.na(PoolQC))

# b. NA estructurales frente a faltantes reales
grupos <- list(
  garage = list(cols = c("GarageType", "GarageFinish", "GarageQual", "GarageCond"),
                area = "GarageArea"),
  sotano = list(cols = c("BsmtQual", "BsmtCond", "BsmtExposure",
                         "BsmtFinType1", "BsmtFinType2"),
                area = "TotalBsmtSF"),
  piscina = list(cols = "PoolQC", area = "PoolArea")
)

revisar_grupo <- function(spec, nombre) {
  area <- house[[spec$area]]
  map_dfr(spec$cols, function(col) {
    x <- house[[col]]
    tibble(
      grupo        = nombre,
      columna      = col,
      na_total     = sum(is.na(x)),
      estructural  = sum(is.na(x) & !is.na(area) & area == 0),
      real         = sum(is.na(x) & (is.na(area) | area > 0)),
      area_na      = sum(is.na(area)),
      area0_sin_na = sum(!is.na(x) & !is.na(area) & area == 0)
    )
  })
}

coincidencia_na <- imap_dfr(grupos, revisar_grupo)
coincidencia_na

# filas con al menos un faltante real por grupo
filas_reales <- imap(grupos, function(spec, nombre) {
  area <- house[[spec$area]]
  falla <- house %>%
    select(all_of(spec$cols)) %>%
    mutate(across(everything(), ~ is.na(.x) & (is.na(area) | area > 0))) %>%
    rowSums() > 0
  house$Id[falla]
})
lengths(filas_reales)

# c. recodificar solo los NA estructurales
recodificar_ausencia <- function(df, cols, area) {
  sin_elemento <- !is.na(df[[area]]) & df[[area]] == 0
  cols_chr <- cols[map_lgl(df[cols], is.character)]
  df %>%
    mutate(across(all_of(cols_chr),
                  ~ if_else(is.na(.x) & sin_elemento, "Ninguno", .x)))
}

house_rec <- reduce(grupos, function(df, spec) recodificar_ausencia(df, spec$cols, spec$area),
                    .init = house)

# comprobación: los NA que quedan son exactamente los faltantes reales
na_restantes <- map_int(grupos, ~ sum(rowSums(is.na(house_rec[.x$cols])) > 0))
stopifnot(all(na_restantes == lengths(filas_reales)))
na_restantes

# d. imputación de LotFrontage
mediana_global <- median(house$LotFrontage, na.rm = TRUE)

house_rec <- house_rec %>%
  mutate(lot_global = coalesce(LotFrontage, mediana_global)) %>%
  mutate(lot_barrio = coalesce(LotFrontage, median(LotFrontage, na.rm = TRUE)),
         .by = Neighborhood)
stopifnot(!anyNA(house_rec$lot_global), !anyNA(house_rec$lot_barrio))

dif_barrio <- house %>%
  summarise(n_na = sum(is.na(LotFrontage)),
            mediana_barrio = median(LotFrontage, na.rm = TRUE),
            .by = Neighborhood) %>%
  mutate(diferencia = mediana_barrio - mediana_global) %>%
  arrange(desc(abs(diferencia)))
dif_barrio

grafico_lot <- ggplot(dif_barrio, aes(reorder(Neighborhood, diferencia), diferencia,
                                      fill = diferencia > 0)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "LotFrontage: mediana por barrio menos mediana global",
       x = NULL, y = "Diferencia (pies)") +
  theme_minimal()
grafico_lot
ggsave("ej1_lotfrontage_barrio.png", grafico_lot, width = 7, height = 6)

# e. edad de la vivienda y años imposibles
house_rec <- house_rec %>%
  mutate(edad_vivienda = YrSold - YearBuilt)

house_rec %>%
  filter(edad_vivienda < 0 | GarageYrBlt > YrSold |
           YearBuilt > 2010 | YearRemodAdd > 2010 | GarageYrBlt > 2010) %>%
  select(Id, YearBuilt, YearRemodAdd, GarageYrBlt, YrSold, SaleCondition)

house_rec <- house_rec %>%
  mutate(
    dato_corregido = edad_vivienda < 0 | coalesce(GarageYrBlt > YrSold, FALSE),
    # 2207 es un error de digitación de 2007 (la casa es de 2006)
    GarageYrBlt = case_when(GarageYrBlt > 2010 ~ GarageYrBlt - 200,
                            TRUE ~ GarageYrBlt),
    # venta "Partial" antes de terminar la obra: edad 0
    edad_vivienda = case_when(edad_vivienda < 0 ~ 0,
                              TRUE ~ edad_vivienda)
  )

stopifnot(all(house_rec$edad_vivienda >= 0),
          all(house_rec$GarageYrBlt <= 2010, na.rm = TRUE))
house_rec %>% filter(dato_corregido) %>%
  select(Id, YearBuilt, GarageYrBlt, YrSold, edad_vivienda)

# f. discretización por cuartiles
cortes <- quantile(house_rec$edad_vivienda, probs = seq(0, 1, 0.25))
cortes

house_rec <- house_rec %>%
  mutate(grupo_cut   = cut(edad_vivienda, breaks = cortes, include.lowest = TRUE),
         grupo_ntile = ntile(edad_vivienda, 4))

table(cut = as.integer(house_rec$grupo_cut), ntile = house_rec$grupo_ntile)
mean(as.integer(house_rec$grupo_cut) == house_rec$grupo_ntile)

# edades que ntile reparte en dos grupos distintos
house_rec %>%
  summarise(grupos_ntile = n_distinct(grupo_ntile), .by = edad_vivienda) %>%
  filter(grupos_ntile > 1)

house_rec %>%
  summarise(n = n(), mediana_precio = median(SalePrice), .by = grupo_cut) %>%
  arrange(grupo_cut)
house_rec %>%
  summarise(n = n(), mediana_precio = median(SalePrice), .by = grupo_ntile) %>%
  arrange(grupo_ntile)


# =========================================================================
# Ejercicio 2: ¿qué es un outlier en fare? (titanic)
# =========================================================================

marcar_iqr <- function(x, k = 1.5) {
  q <- quantile(x, c(0.25, 0.75), na.rm = TRUE)
  rango <- q[2] - q[1]
  x < q[1] - k * rango | x > q[2] + k * rango
}

tarifas <- titanic %>% filter(!is.na(fare))

# a
tarifas <- tarifas %>%
  mutate(out_k15 = marcar_iqr(fare, 1.5),
         out_k3  = marcar_iqr(fare, 3))
tarifas %>% summarise(pct_k15 = mean(out_k15) * 100, pct_k3 = mean(out_k3) * 100)

# b
tarifas <- tarifas %>%
  mutate(out_clase = marcar_iqr(fare, 1.5), .by = pclass)

tarifas %>%
  summarise(global = sum(out_k15), por_clase = sum(out_clase),
            dejan_de_serlo = sum(out_k15 & !out_clase), .by = pclass) %>%
  arrange(pclass)

# c. z-score robusto
tarifas <- tarifas %>%
  mutate(z_robusto = (fare - median(fare)) / mad(fare),
         out_robusto = abs(z_robusto) > 3.5,
         z_clasico = (fare - mean(fare)) / sd(fare),
         out_clasico = abs(z_clasico) > 3.5)
tarifas %>% summarise(robusto = sum(out_robusto), clasico = sum(out_clasico))

# d. cruce de criterios
tarifas %>% count(out_k15, out_clase, out_robusto)

tarifas %>%
  filter(out_robusto & !out_k15) %>%
  count(pclass, name = "solo_robusto")
tarifas %>%
  filter(out_clase & !out_k15) %>%
  select(name, pclass, fare)

# e. tarifas en cero
tarifas %>%
  filter(fare == 0) %>%
  select(name, pclass, ticket, age, survived)

tarifas <- tarifas %>%
  mutate(tarifa_cero = fare == 0,
         fare_limpia = if_else(fare == 0, NA_real_, fare))
stopifnot(sum(is.na(tarifas$fare_limpia)) == 17)

# f. transformación logarítmica
tarifas <- tarifas %>% mutate(out_log = marcar_iqr(log1p(fare), 1.5))
tarifas %>% summarise(sin_log = sum(out_k15), con_log = sum(out_log))
tarifas %>% filter(out_log) %>% count(pclass, alto = fare > median(fare))


# =========================================================================
# Ejercicio 3: ¿qué estrategia de imputación se equivoca menos? (titanic)
# =========================================================================

titanic_edad <- titanic %>%
  filter(!is.na(age)) %>%
  mutate(titulo = str_extract(name, "(?<=, )[A-Za-z]+(?=\\.)"),
         titulo = if_else(titulo %in% c("Mr", "Mrs", "Miss", "Master"), titulo, "Otro"))
stopifnot(nrow(titanic_edad) == 1046)

imputar_mediana <- function(edad, oculta, grupo = NULL) {
  base <- tibble(edad, oculta, grupo = if (is.null(grupo)) "todos" else grupo)
  base %>%
    mutate(med = median(edad[!oculta]), .by = grupo) %>%
    mutate(med = coalesce(med, median(edad[!oculta])),
           imp = if_else(oculta, med, edad)) %>%
    pull(imp)
}

simular_imputacion <- function(semilla, datos = titanic_edad, devolver_datos = FALSE) {
  set.seed(semilla)
  ocultas <- sample(nrow(datos), round(0.2 * nrow(datos)))

  d <- datos %>%
    mutate(oculta = row_number() %in% ocultas,
           age_real = age,
           age_obs = if_else(oculta, NA_real_, age),
           imp_global = imputar_mediana(age, oculta),
           imp_clase_sexo = imputar_mediana(age, oculta, paste(pclass, sex)),
           imp_titulo = imputar_mediana(age, oculta, titulo))

  if (devolver_datos) return(d)

  d %>%
    filter(oculta) %>%
    pivot_longer(starts_with("imp_"), names_to = "estrategia", values_to = "imputada") %>%
    summarise(mae = mean(abs(imputada - age_real)),
              rmse = sqrt(mean((imputada - age_real)^2)),
              .by = estrategia) %>%
    mutate(semilla = semilla)
}

# a a c
datos_2024 <- simular_imputacion(2024, devolver_datos = TRUE)
stopifnot(sum(datos_2024$oculta) == 209)
resultado_2024 <- simular_imputacion(2024)
resultado_2024 %>% arrange(mae)

# d. 200 repeticiones
simulaciones <- map_dfr(1:200, simular_imputacion)

ganadores <- simulaciones %>%
  slice_min(mae, n = 1, by = semilla, with_ties = FALSE) %>%
  count(estrategia) %>%
  mutate(pct = n / 2)
ganadores

simulaciones %>%
  summarise(mae_medio = mean(mae), rmse_medio = mean(rmse), .by = estrategia)

grafico_mae <- ggplot(simulaciones, aes(estrategia, mae, fill = estrategia)) +
  geom_boxplot(show.legend = FALSE) +
  labs(title = "MAE de 200 simulaciones por estrategia de imputación",
       x = NULL, y = "MAE (años)") +
  theme_minimal()
grafico_mae
ggsave("ej3_mae_imputacion.png", grafico_mae, width = 7, height = 4)

# e. variabilidad después de imputar
datos_2024 %>%
  summarise(sd_real = sd(age_real),
            sd_global = sd(imp_global),
            sd_clase_sexo = sd(imp_clase_sexo),
            sd_titulo = sd(imp_titulo))

# archivo para comparar con Python (punto f)
datos_2024 %>%
  select(id, pclass, sex, oculta, age_obs, imp_clase_sexo) %>%
  write_csv("ej3_imputacion_r.csv")


# =========================================================================
# Ejercicio 4: escalado, outliers y fuga de información (mobile_data)
# =========================================================================

# a
escalar <- function(df, cols, metodo = c("minmax", "zscore", "robusto")) {
  metodo <- match.arg(metodo)
  f <- switch(metodo,
              minmax  = function(x) (x - min(x)) / (max(x) - min(x)),
              zscore  = function(x) (x - mean(x)) / sd(x),
              robusto = function(x) (x - median(x)) / IQR(x))
  df %>% select(all_of(cols)) %>% mutate(across(everything(), f))
}

vars4 <- c("ram", "battery_power", "int_memory", "px_height", "px_width")

# b. aporte de cada variable a la distancia entre los teléfonos 1 y 2
aporte_distancia <- function(df) {
  d2 <- (unlist(df[1, ]) - unlist(df[2, ]))^2
  round(100 * d2 / sum(d2), 2)
}

metodos <- c("minmax", "zscore", "robusto")
aportes <- map_dfr(c("sin escalar", metodos), function(m) {
  datos <- if (m == "sin escalar") select(mobile, all_of(vars4)) else escalar(mobile, vars4, m)
  as_tibble_row(c(metodo = m, as.list(aporte_distancia(datos))))
})
aportes

# c. un outlier extremo en ram
mobile_out <- mobile
mobile_out$ram[1] <- 100000

map_dfr(metodos, function(m) {
  tibble(metodo = m,
         sd_ram_resto = sd(escalar(mobile_out, "ram", m)$ram[-1]),
         rango_resto = diff(range(escalar(mobile_out, "ram", m)$ram[-1])))
})

# d. fuga de información
predictoras <- setdiff(names(mobile), "price_range")

set.seed(2024)
idx_train <- sample(nrow(mobile), round(0.7 * nrow(mobile)))
train <- mobile[idx_train, ]
test  <- mobile[-idx_train, ]

minimos <- map_dbl(train[predictoras], min)
maximos <- map_dbl(train[predictoras], max)

test_esc <- map(predictoras, ~ (test[[.x]] - minimos[.x]) / (maximos[.x] - minimos[.x])) %>%
  set_names(predictoras) %>%
  as_tibble()

fuera <- sum(test_esc < 0 | test_esc > 1)
c(valores_fuera = fuera,
  pct_fuera = round(100 * fuera / (nrow(test_esc) * ncol(test_esc)), 3))
colSums(test_esc < 0 | test_esc > 1)[colSums(test_esc < 0 | test_esc > 1) > 0]

# escalado con todo el dataset (incorrecto)
todo_esc <- escalar(mobile, predictoras, "minmax")
sum(todo_esc[-idx_train, ] < 0 | todo_esc[-idx_train, ] > 1)

write_csv(mobile %>% mutate(fila = row_number(), en_train = fila %in% idx_train),
          "ej4_particion_r.csv")


# =========================================================================
# Ejercicio 5: pipeline funcional y reutilizable (adult)
# =========================================================================

# a. "?" como faltante
adult_na <- adult %>%
  mutate(across(where(is.character), ~ na_if(str_trim(.x), "?")))
colSums(is.na(adult_na))[colSums(is.na(adult_na)) > 0]

tabla_occ <- adult_na %>%
  mutate(occ_faltante = is.na(occupation)) %>%
  summarise(n = n(), mayor_50k = sum(income == ">50K"),
            prop = mean(income == ">50K"),
            .by = occ_faltante)
tabla_occ
prop.test(tabla_occ$mayor_50k, tabla_occ$n)

# b. valor centinela en capital.gain
adult %>% count(capital.gain == 99999)
adult %>% filter(capital.gain < 99999) %>% summarise(siguiente = max(capital.gain))
mean(adult$capital.gain == 0)

# c. un paso por función (versión que recalcula los parámetros)
limpiar_signos <- function(df) {
  df %>% mutate(across(where(is.character), ~ na_if(str_trim(.x), "?")))
}

tratar_centinela <- function(df, tope = 41310) {
  df %>%
    mutate(ganancia_centinela = as.integer(capital.gain == 99999),
           capital.gain = if_else(capital.gain == 99999, tope, capital.gain))
}

agrupar_paises <- function(df) {
  df %>%
    mutate(native.country = if_else(native.country == "United-States",
                                    "Estados Unidos", "Otro"))
}

imputar <- function(df, params = NULL) {
  if (is.null(params)) params <- list(
    medianas = map(select(df, where(is.numeric)), median, na.rm = TRUE),
    moda_pais = names(which.max(table(df$native.country)))
  )
  df %>%
    mutate(across(c(workclass, occupation), ~ coalesce(.x, "Desconocido")),
           native.country = coalesce(native.country, params$moda_pais),
           across(where(is.numeric), ~ coalesce(.x, params$medianas[[cur_column()]])))
}

transformar_log <- function(df) {
  df %>% mutate(across(c(capital.gain, capital.loss), log1p))
}

cols_onehot <- c("workclass", "marital.status", "sex",
                 "occupation", "relationship", "race")

codificar <- function(df, niveles = NULL) {
  if (is.null(niveles)) niveles <- map(df[cols_onehot], ~ sort(unique(.x)))
  dummies <- imap(niveles, function(lv, col) {
    map(lv[-1], ~ as.integer(df[[col]] == .x)) %>%
      set_names(make.names(paste0(col, "_", lv[-1])))
  }) %>%
    unname() %>%
    unlist(recursive = FALSE) %>%
    as_tibble()
  df %>%
    mutate(income = as.integer(income == ">50K"),
           pais_eeuu = as.integer(native.country == "Estados Unidos")) %>%
    select(-all_of(cols_onehot), -native.country, -education) %>%
    bind_cols(dummies)
}

cols_continuas <- c("age", "fnlwgt", "education.num", "capital.gain",
                    "capital.loss", "hours.per.week")

estandarizar <- function(df, params = NULL) {
  if (is.null(params)) params <- list(
    medias = map(df[cols_continuas], mean),
    sds    = map(df[cols_continuas], sd)
  )
  df %>%
    mutate(across(all_of(cols_continuas),
                  ~ (.x - params$medias[[cur_column()]]) / params$sds[[cur_column()]]))
}

# d. composición con reduce()
pasos <- list(limpiar_signos, tratar_centinela, imputar, agrupar_paises,
              transformar_log, codificar, estandarizar)

preprocesar_adult <- function(df) {
  salida <- reduce(pasos, function(datos, paso) paso(datos), .init = df)
  stopifnot(!anyNA(salida),
            all(map_lgl(salida, is.numeric)),
            nrow(salida) == nrow(df))
  salida
}

adult_listo <- preprocesar_adult(adult)
dim(adult_listo)
round(colMeans(adult_listo[cols_continuas]), 4)

# e. parámetros aprendidos solo con entrenamiento
ajustar_parametros <- function(train) {
  base <- train %>% limpiar_signos() %>% tratar_centinela()
  p_imp <- list(medianas = map(select(base, where(is.numeric)), median, na.rm = TRUE),
                moda_pais = names(which.max(table(base$native.country))))
  base <- base %>% imputar(p_imp) %>% agrupar_paises() %>% transformar_log()
  niveles <- map(base[cols_onehot], ~ sort(unique(.x)))
  base <- codificar(base, niveles)
  list(imputar = p_imp, niveles = niveles,
       escala = list(medias = map(base[cols_continuas], mean),
                     sds    = map(base[cols_continuas], sd)))
}

aplicar_pipeline <- function(df, params) {
  salida <- df %>%
    limpiar_signos() %>%
    tratar_centinela() %>%
    imputar(params$imputar) %>%
    agrupar_paises() %>%
    transformar_log() %>%
    codificar(params$niveles) %>%
    estandarizar(params$escala)
  stopifnot(!anyNA(salida), all(map_lgl(salida, is.numeric)), nrow(salida) == nrow(df))
  salida
}

set.seed(2024)
idx <- sample(nrow(adult), round(0.7 * nrow(adult)))
params_train <- ajustar_parametros(adult[idx, ])

adult_train <- aplicar_pipeline(adult[idx, ], params_train)
adult_test  <- aplicar_pipeline(adult[-idx, ], params_train)

stopifnot(identical(names(adult_train), names(adult_test)))
dim(adult_train); dim(adult_test)
round(colMeans(adult_test[cols_continuas]), 3)


# =========================================================================
# Ejercicio 6 (reto): texto, fechas y columnas anidadas (netflix)
# =========================================================================

# a. duración guardada en rating
netflix %>%
  filter(is.na(duration), str_detect(rating, "min")) %>%
  select(show_id, title, rating, duration)

netflix_l <- netflix %>%
  mutate(desplazado = is.na(duration) & str_detect(coalesce(rating, ""), "^\\d+ min$"),
         duration = if_else(desplazado, rating, duration),
         rating = if_else(desplazado, NA_character_, rating))
stopifnot(sum(netflix_l$desplazado) == 3, !anyNA(netflix_l$duration))

# b. valor y unidad de la duración
netflix_l <- netflix_l %>%
  mutate(duracion_valor = as.numeric(str_extract(duration, "\\d+")),
         duracion_unidad = if_else(str_detect(duration, "min"), "min", "temporadas"))

netflix_l %>% count(type, duracion_unidad)
netflix_l %>% summarise(promedio = mean(duracion_valor), .by = c(type, duracion_unidad))

# c. fechas
netflix_l <- netflix_l %>%
  mutate(fecha_agregado = parse_date(str_trim(date_added), "%B %d, %Y",
                                     locale = locale("en")),
         rezago = year(fecha_agregado) - release_year)

sum(is.na(netflix_l$fecha_agregado)); sum(is.na(netflix_l$date_added))
summary(netflix_l$rezago)
netflix_l %>% filter(rezago < 0) %>%
  select(title, type, release_year, fecha_agregado, rezago) %>%
  arrange(rezago)
sum(netflix_l$rezago < 0, na.rm = TRUE)

# d. géneros
generos <- netflix_l %>%
  select(show_id, type, listed_in) %>%
  separate_longer_delim(listed_in, delim = ", ")

c(filas_antes = nrow(netflix_l), filas_despues = nrow(generos))

generos %>%
  count(type, listed_in, sort = TRUE) %>%
  slice_max(n, n = 10, by = type)

# e. países
netflix_l <- netflix_l %>%
  mutate(n_paises = map_int(str_split(country, ","),
                            ~ if (all(is.na(.x))) NA_integer_ else sum(str_trim(.x) != "")),
         coproduccion = n_paises > 1)

netflix_l %>% count(coproduccion)
netflix_l %>% count(n_paises) %>% head(6)


# =========================================================================
# Respuestas y justificaciones
# =========================================================================
#
# Ejercicio 1
# a. Con la regla del 50 % se perderían PoolQC (99,7 %), MiscFeature
#    (96,4 %), Alley (93,2 %) y Fence (80,4 %). En PoolQC el NA significa
#    casi siempre "no tiene piscina", así que al borrarla se pierde la
#    calidad de las 13 piscinas que sí existen. La regla trata como
#    faltante algo que en realidad es información.
# b. Los NA coinciden con área 0 en casi todos los casos. Faltantes reales:
#    2 filas en garaje (incluida una con GarageArea en NA), 10 en sótano
#    (una con TotalBsmtSF en NA) y 3 en piscina (casas con PoolArea > 0 sin
#    PoolQC). No hay casos con área 0 y categoría registrada.
# c. recodificar_ausencia() solo cambia a "Ninguno" los NA con área 0 y la
#    comprobación confirma que los NA restantes son los faltantes reales.
#    Así no se inventa una categoría para datos que sí se perdieron.
# d. La mediana global es 68 pies. Las mayores diferencias están en
#    MeadowV y BrDale (-47), NPkVill y Blueste (-44) y Blmngtn (-25), y por
#    encima en NridgHt (+24) y NoRidge (+21). Se prefiere la mediana por
#    barrio porque el frente del lote depende del tipo de urbanización; la
#    global sobrestima mucho en barrios de lotes angostos.
# e. Hay dos registros. La casa 2550 se vendió (2007) antes de terminarse
#    (2008), con venta "Partial": no es un error, así que la edad se deja
#    en 0. La casa 2593 tiene GarageYrBlt = 2207, un error de digitación de
#    2007 (la casa es de 2006), y se corrige. No se elimina ninguna fila y
#    ambas quedan marcadas en dato_corregido.
# f. Los cortes son 0, 7, 35 y 54,5 años. cut() y ntile() coinciden en el
#    98,7 % de las viviendas; las diferencias están en las edades 7, 35 y
#    55, que ntile() reparte en dos grupos para que todos tengan el mismo
#    tamaño, mientras cut() asigna por valor. La mediana de SalePrice baja
#    con la edad: $274.950, $230.130, $172.000 y $163.000 con cut().
#
# Ejercicio 2
# a. Con k = 1,5 se marca el 13,1 % de los pasajeros y con k = 3 el 6,4 %.
# b. En primera clase se pasa de 153 outliers a 25: 128 dejan de serlo. En
#    segunda y tercera aumentan (de 7 a 12 y de 11 a 65). Comparar con la
#    distribución global es injusto porque la tarifa depende de la clase;
#    un pasaje caro de primera es normal dentro de su grupo.
# c. El z-score robusto marca 240 pasajeros y el clásico 29. La mediana y
#    la MAD no se mueven con los valores extremos, mientras que la media y
#    la desviación estándar se inflan con las tarifas de $512 y terminan
#    ocultando los outliers (efecto de enmascaramiento).
# d. 43 pasajeros son outliers con los tres criterios y 1.022 con ninguno.
#    128 de primera clase son outliers global y robusto pero no por clase;
#    46 solo lo son por clase (sobre todo familias de tercera con tarifas
#    de grupo) y 56 solo con el z-score robusto.
# e. Los 17 casos con tarifa 0 son empleados de Harland & Wolff, de la
#    White Star (Ismay) y de la American Line (tiquete "LINE"): viajaron
#    por cortesía. No son outliers ni errores, sino faltantes disfrazados:
#    se pasan a NA con la bandera tarifa_cero, y si un modelo lo exige se
#    imputan con la mediana de su clase.
# f. Con log1p(fare) quedan 42 outliers (antes 171). La transformación
#    reduce la asimetría y mejora los modelos sensibles a la escala, pero
#    no elimina los valores extremos: solo los acerca. Las tarifas siguen
#    siendo las mismas, por eso hay que decidir igual qué hacer con ellas.
#
# Ejercicio 3
# a-c. Con la semilla 2024 gana la mediana por título (MAE 9,70; RMSE 12,6),
#    luego la de clase y sexo (10,3; 13,3) y la global (11,0; 14,4). Las
#    medianas se calculan solo con las edades no ocultas.
# d. En 200 repeticiones el título gana el 86 % de las veces y clase-sexo
#    el 14 %; la global nunca gana. El título funciona mejor porque Master y
#    Miss identifican niños y mujeres jóvenes.
# e. La desviación estándar baja de 14,4 a 13,0 con la mediana global y a
#    13,3 con las otras dos. Imputar con una mediana concentra los valores
#    en el centro: el modelo verá menos variabilidad de la real y puede
#    subestimar errores estándar o la relación de la edad con la respuesta.
# f. En Python, groupby().transform("median") da exactamente los mismos
#    valores que en R (ver ejercicios_clase_7.py).
#
# Ejercicio 4
# b. Sin escalar, px_width (64,8 %) y px_height (33,4 %) dominan la
#    distancia entre los teléfonos 1 y 2. Al escalar el reparto se
#    equilibra: int_memory pasa de 0,09 % a entre 31,7 % y 38,1 %, y px_width
#    baja a entre 39,4 % y 46,8 %, según el método.
# c. Min-max colapsa a las demás observaciones: con ram = 100.000 el resto
#    queda en un rango de 0,04 (sd 0,011), porque el máximo define toda la
#    escala. El z-score también se afecta (sd 0,52) y el robusto es el que
#    menos (sd 0,59), porque la mediana y el IQR no dependen del extremo.
# d. Con mínimo y máximo de entrenamiento, solo 2 de 18.000 valores de
#    prueba quedan fuera de [0, 1] (0,011 %). Si se escala todo junto no
#    queda ninguno fuera, porque los mínimos y máximos ya incluyen la
#    prueba: el escalado usa información que en la práctica no se tendría,
#    aunque nunca se toque price_range.
# e. En Python, con otra partición aleatoria, quedan 18 valores fuera
#    (0,1 %). El porcentaje es bajo en ambos casos; la diferencia se debe a
#    qué filas caen en cada partición.
#
# Ejercicio 5
# a. Hay 1.836 NA en workclass, 1.843 en occupation y 583 en
#    native.country. Entre quienes no tienen ocupación, el 10,4 % gana más
#    de 50K frente al 24,9 % del resto (p < 2,2e-16). El faltante no es
#    aleatorio, así que conviene la categoría "Desconocido": imputar con la
#    moda borraría un patrón que sí se relaciona con el ingreso.
# b. 159 filas tienen 99999 y el siguiente valor es 41.310, y el 91,7 % de
#    las filas vale 0. El 99999 parece un tope de registro, no un error: se
#    crea la bandera ganancia_centinela, se reemplaza por 41.310 y luego se
#    aplica log1p. Pasarlo a NA perdería que son personas de alto ingreso.
# c-d. preprocesar_adult() compone los siete pasos con reduce() y pasa las
#    verificaciones: 32.561 filas, 47 columnas numéricas y sin NA. Además de
#    workclass, marital.status y sex se codifican occupation, relationship y
#    race, y se quita education (repite education.num), porque si no
#    quedarían columnas de texto.
# e. Hay que guardar las medianas numéricas, la moda del país, los niveles
#    de cada factor y las medias y desviaciones de las variables continuas.
#    Con la partición 70/30 se aprenden en entrenamiento y se aplican a
#    prueba: ambas quedan con las mismas 47 columnas y las medias de prueba
#    son cercanas a 0 pero no exactamente 0, como es esperable.
# f. En Python, fit solo con entrenamiento evita la fuga de información, y
#    handle_unknown = "ignore" evita un error si en prueba aparece una
#    categoría que no estaba en entrenamiento (queda con ceros en todas sus
#    columnas).
#
# Ejercicio 6
# a. Las tres filas son especiales de Louis C.K. con la duración en rating;
#    se pasan a duration y rating queda en NA.
# b. Las películas se miden en minutos y las series en temporadas, así que
#    un promedio de todo el catálogo mezcla unidades. Por tipo: 99,6 min en
#    películas y 1,76 temporadas en series.
# c. Hay 10 fechas faltantes. 14 títulos tienen rezago negativo (de -1 a
#    -3), casi todos series: release_year suele corresponder a la última
#    temporada, o el título se agregó antes de su estreno oficial.
# d. Al separar los géneros se pasa de 8.807 a 19.323 filas. No se puede
#    sumar para contar títulos porque un mismo título aparece en varios
#    géneros. Los más frecuentes son International Movies y Dramas en
#    películas, e International TV Shows y TV Dramas en series.
# e. 1.315 títulos son coproducciones y 831 no tienen país. Para contar
#    títulos por país o coproducciones conviene dejar NA, porque
#    "Desconocido" crearía un país falso; para un modelo que no acepta NA
#    sí sirve "Desconocido" como categoría aparte.
