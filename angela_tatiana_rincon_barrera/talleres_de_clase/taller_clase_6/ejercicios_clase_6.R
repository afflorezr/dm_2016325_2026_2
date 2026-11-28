# Minería de Datos - Clase 6: Tipos de datos y estructuras
# Ejercicios 1 a 5

paquetes   <- c("jsonlite", "dplyr", "tibble", "readr", "tidyr",
                "ggplot2", "Matrix")
pendientes <- setdiff(paquetes, rownames(installed.packages()))
if (length(pendientes) > 0) install.packages(pendientes)

library(jsonlite)
library(dplyr)
library(tibble)
library(readr)
library(tidyr)
library(ggplot2)
library(Matrix)

# carpeta con las bases de datos del curso
ruta_datos <- "C:/Users/Administrar/OneDrive/Escritorio/6 SEXTO SEMESTRE/Minería de Datos/DATOS"
titanic <- read_csv(file.path(ruta_datos, "titanic.csv"), show_col_types = FALSE)


# Ejercicio 1: clasificación de tipos de datos ----------------------------
#
# 1. Microdatos GEIH del DANE (.csv de 300.000 filas)
#    (a) Estructurada.
#    (b) Filas = personas/hogares y columnas = variables con tipo fijo.
#    (c) read_csv() indicando separador y codificación, y revisar los tipos
#        de las columnas (códigos como factores o enteros).
#
# 2. JSON de la API de datos.gov.co (calidad del aire)
#    (a) Semi-estructurada.
#    (b) Tiene etiquetas clave-valor, pero admite anidamiento y campos que
#        no siempre aparecen en todos los registros.
#    (c) fromJSON() y aplanar los campos anidados (unnest / unnest_wider),
#        convirtiendo fechas y valores numéricos que llegan como texto.
#
# 3. Grabaciones de audio de audiencias judiciales
#    (a) No estructurada.
#    (b) Es una señal continua sin campos ni esquema predefinido.
#    (c) Transcribir el audio a texto (speech-to-text) y luego tokenizarlo,
#        o extraer características de la señal; cada audiencia queda como
#        una fila con sus metadatos (fecha, despacho, duración).
#
# 4. Factura electrónica DIAN (XML)
#    (a) Semi-estructurada.
#    (b) Usa etiquetas jerárquicas con un esquema (UBL), pero los datos
#        están anidados (emisor, receptor, ítems de la factura).
#    (c) read_xml() de xml2 y extraer los nodos con xml_find_all() y XPath;
#        los ítems se pasan a filas y los datos generales se repiten.
#
# 5. Tabla HTML de Wikipedia scrapeada con rvest
#    (a) Semi-estructurada en origen (HTML), con contenido tabular.
#    (b) La tabla tiene filas y columnas, pero viene mezclada con etiquetas,
#        notas al pie y formatos de texto.
#    (c) html_table() y limpiar: nombres de columnas, quitar referencias
#        tipo [1] y convertir números con separadores a numeric.


# Ejercicio 2: JSON anidado a data frame ----------------------------------

url <- "https://jsonplaceholder.typicode.com/users"
raw <- fromJSON(url)

# 2.1
str(raw, max.level = 2)

sapply(raw, class)

# 2.2
usuarios <- tibble(
  name         = raw$name,
  email        = raw$email,
  city         = raw$address$city,
  lat          = as.numeric(raw$address$geo$lat),
  lng          = as.numeric(raw$address$geo$lng),
  company_name = raw$company$name
)
usuarios

# misma tabla aplanando todo con flatten()
usuarios_flat <- as_tibble(flatten(raw))
names(usuarios_flat)

# 2.3 Es un dato semi-estructurado: fromJSON() devuelve un data.frame cuyas
# columnas address y company son a su vez data frames (y address$geo otro
# más), porque el JSON guarda objetos dentro de objetos. Un tibble plano
# exige una columna atómica por variable, así que hay que extraer o aplanar
# los niveles anidados; además lat y lng llegan como texto.


# Ejercicio 3: matriz de diseño --------------------------------------------

datos_x <- titanic %>%
  select(age, fare, sibsp, parch) %>%
  na.omit()

# 3.1
X <- scale(as.matrix(datos_x))
dim(X)
format(object.size(X), units = "Kb")

# 3.2
XtX <- crossprod(X)
round(XtX, 2)
round(diag(XtX))   # n - 1

# 3.3
X_sparse <- Matrix(X, sparse = TRUE)
format(object.size(X_sparse), units = "Kb")
mean(X == 0)       # proporción de ceros en X escalada
mean(as.matrix(datos_x) == 0)   # proporción de ceros antes de escalar

# 3.4 ver respuestas al final


# Ejercicio 4: concentración de distancias --------------------------------

set.seed(42)
dimensiones <- c(1, 2, 5, 10, 50, 100, 500, 1000, 5000)

dist_coseno <- function(a, b) 1 - sum(a * b) / (sqrt(sum(a^2)) * sqrt(sum(b^2)))

resumen_dist <- lapply(dimensiones, function(p) {
  puntos <- matrix(runif(500 * p), nrow = 500, ncol = p)
  euc <- sapply(1:200, function(i) sqrt(sum((puntos[i, ] - puntos[i + 200, ])^2)))
  cos <- sapply(1:200, function(i) dist_coseno(puntos[i, ], puntos[i + 200, ]))
  tibble(p = p,
         media_euclid = mean(euc), cv_euclid = 100 * sd(euc) / mean(euc),
         media_coseno = mean(cos), cv_coseno = 100 * sd(cos) / mean(cos))
}) %>%
  bind_rows()

# 4.1 y 4.4
resumen_dist %>% mutate(across(-p, ~ round(.x, 4)))

# 4.2
grafico_dist <- resumen_dist %>%
  select(p, `Distancia media` = media_euclid, `CV (%)` = cv_euclid) %>%
  pivot_longer(-p, names_to = "medida", values_to = "valor") %>%
  ggplot(aes(p, valor)) +
  geom_line() +
  geom_point() +
  scale_x_log10(breaks = dimensiones) +
  facet_wrap(~ medida, scales = "free_y") +
  labs(title = "Concentración de distancias euclidianas",
       x = "Dimensión p (escala log)", y = NULL) +
  theme_minimal()
grafico_dist
ggsave("concentracion_distancias.png", grafico_dist, width = 8, height = 4)

# 4.3
resumen_dist %>% filter(cv_euclid < 5) %>% slice_min(p)

# comparación del CV euclidiano y coseno
grafico_cv <- resumen_dist %>%
  select(p, Euclidiana = cv_euclid, Coseno = cv_coseno) %>%
  pivot_longer(-p, names_to = "distancia", values_to = "cv") %>%
  filter(is.finite(cv)) %>%   # en p = 1 la distancia coseno siempre es 0
  ggplot(aes(p, cv, colour = distancia)) +
  geom_line() +
  geom_point() +
  geom_hline(yintercept = 5, linetype = "dashed") +
  scale_x_log10(breaks = dimensiones) +
  labs(title = "CV de las distancias según la dimensión",
       x = "Dimensión p (escala log)", y = "CV (%)", colour = NULL) +
  theme_minimal()
grafico_cv
ggsave("cv_euclidiana_coseno.png", grafico_cv, width = 7, height = 4)


# Ejercicio 5: PCA ----------------------------------------------------------

datos_pca <- titanic %>%
  select(survived, age, fare, sibsp, parch, pclass) %>%
  na.omit()

X5 <- datos_pca %>% select(-survived) %>% as.matrix()

# 5.1
pca <- prcomp(X5, scale. = TRUE)
summary(pca)

varianza <- tibble(
  componente = seq_along(pca$sdev),
  prop       = pca$sdev^2 / sum(pca$sdev^2),
  acumulada  = cumsum(prop)
)
varianza

min(which(varianza$acumulada >= 0.80))
min(which(varianza$acumulada >= 0.95))

# 5.2
grafico_scree <- ggplot(varianza, aes(componente, acumulada)) +
  geom_line() +
  geom_point() +
  geom_hline(yintercept = c(0.80, 0.95), linetype = "dashed", colour = "grey40") +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  labs(title = "Scree plot: varianza acumulada",
       x = "Componente principal", y = "Varianza acumulada") +
  theme_minimal()
grafico_scree
ggsave("scree_plot_titanic.png", grafico_scree, width = 6, height = 4)

# 5.3
round(pca$rotation[, 1:2], 3)

# 5.4 K-Means con k = 2
set.seed(42)
X5_esc <- scale(X5)
km_x   <- kmeans(X5_esc, centers = 2, nstart = 25)
km_pc  <- kmeans(pca$x[, 1:2], centers = 2, nstart = 25)

# coincidencia con survived (se toma la mejor asignación de etiquetas)
coincidencia <- function(grupo, y) {
  tabla <- table(grupo, y)
  max(sum(diag(tabla)), sum(tabla) - sum(diag(tabla))) / sum(tabla)
}

table(grupo = km_x$cluster,  survived = datos_pca$survived)
table(grupo = km_pc$cluster, survived = datos_pca$survived)

tibble(
  representacion = c("X escalada (5 variables)", "PC1 y PC2"),
  coincidencia   = c(coincidencia(km_x$cluster,  datos_pca$survived),
                     coincidencia(km_pc$cluster, datos_pca$survived))
)


# Respuestas ----------------------------------------------------------------
#
# Ejercicio 2
# 1. address y company son data frames anidados, y dentro de address la
#    columna geo es otro data frame (lat, lng).
# 2. Ver el tibble usuarios: una fila por usuario con name, email, city,
#    lat, lng y company_name (lat y lng convertidos a numéricos).
# 3. Respondida en el comentario del punto 2.3.
#
# Ejercicio 3
# 1. X tiene 1.045 filas y 4 columnas y ocupa unos 34,5 Kb.
# 2. Como X está centrada y escalada, la diagonal de X'X vale n - 1 = 1.044
#    en cada variable: es la suma de cuadrados de una variable con varianza
#    1. Fuera de la diagonal están las covarianzas por (n - 1), es decir,
#    X'X / (n - 1) es la matriz de correlaciones.
# 3. La versión dispersa ocupa más (unos 50,8 Kb frente a 34,5 Kb). No
#    tiene sentido: al centrar, ningún valor queda en cero (0 % de ceros),
#    y el formato disperso solo ahorra memoria cuando la mayoría de los
#    valores son cero. Antes de escalar había 35 % de ceros (sibsp, parch),
#    que tampoco es suficiente.
# 4. Un grafo (por ejemplo con igraph): cada pasajero es un nodo y cada
#    relación familiar una arista. sibsp y parch solo cuentan familiares, no
#    dicen quiénes son, así que las aristas se tendrían que construir
#    uniendo pasajeros por ticket o apellido. Con el grafo se pueden
#    estudiar los grupos familiares como componentes conectados.
#
# Ejercicio 4
# 1. La distancia media crece con p (de 0,34 en p = 1 a 28,9 en p = 5.000),
#    mientras el CV cae de 69,4 % a 0,75 %.
# 3. El CV queda por debajo del 5 % desde p = 500 (2,48 %). Desde ahí todas
#    las distancias son casi iguales, así que para K-NN el vecino "más
#    cercano" y uno cualquiera están prácticamente a la misma distancia y
#    los vecinos dejan de ser informativos; se necesita reducir la
#    dimensión o seleccionar variables antes.
# 4. La distancia coseno también se concentra (su media tiende a 0,25),
#    pero un poco más despacio: su CV baja del 5 % recién en p = 1.000
#    (3,84 %; en p = 500 todavía es 5,44 %). En p = 1 no se puede calcular
#    porque todos los puntos son positivos y el coseno siempre es 0.
#
# Ejercicio 5
# 1. Con 3 componentes se retiene el 80,6 % de la varianza; para llegar al
#    95 % se necesitan los 5 (con 4 se llega al 92,8 %).
# 3. PC1 está dominado por pclass (+0,66), fare (-0,56) y age (-0,49): mide
#    el nivel socioeconómico; valores altos son pasajeros de tercera clase,
#    jóvenes y con tarifas bajas. PC2 está dominado por sibsp (-0,63) y
#    parch (-0,63): mide el tamaño del grupo familiar con el que se viajaba.
# 4. Con X escalada los grupos coinciden con survived en el 59,6 % de los
#    casos y con los 2 primeros PCs en el 59,5 %. La diferencia es mínima:
#    los dos primeros PCs conservan casi la misma información para separar
#    los grupos, pero ninguna representación reproduce bien la
#    supervivencia, porque faltan variables clave como el sexo.
#    (Se usó X escalada porque sin escalar fare dominaría las distancias.)
