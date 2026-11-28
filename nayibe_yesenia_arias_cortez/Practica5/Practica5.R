# =============================================================================
# Minería de Datos — Clase 6: Tipos de Datos y Estructuras
# Taller (Ejercicios 1 a 5)
# =============================================================================
getwd()
setwd("/Users/nayibeyeseniaariascortez/Desktop/MineriaDatos/dm_2016325_2026_2/nayibe_yesenia_arias_cortez/Practica5")

# ---- Paquetes ---------------------------------------------------------------
paquetes <- c("jsonlite", "dplyr", "tibble", "tidyr", "ggplot2", "Matrix", "igraph")
faltantes <- paquetes[!paquetes %in% rownames(installed.packages())]
if (length(faltantes) > 0) install.packages(faltantes)

library(jsonlite)
library(dplyr)
library(tibble)
library(tidyr)
library(ggplot2)
library(Matrix)


ruta_titanic <- "titanic.csv"


# =============================================================================
# EJERCICIO 1: Clasificación de tipos de datos
# =============================================================================
# Respuestas en formato (a) tipo, (b) razón, (c) preprocesamiento mínimo.
#
# 1. Microdatos GEIH del DANE (.csv, 300.000 filas)
#    (a) Estructurado.
#    (b) Filas = personas/hogares, columnas con nombre y tipo fijo (esquema
#        explícito, documentado en el diccionario de datos del DANE).
#    (c) Leer con readr::read_csv() (o data.table::fread() por el tamaño),
#        fijar tipos de columna y recodificar códigos a factores con el
#        diccionario. Ej.:
#        geih <- readr::read_csv("geih.csv", show_col_types = FALSE)
#
# 2. Respuesta JSON de datos.gov.co (calidad del aire)
#    (a) Semi-estructurado.
#    (b) Tiene etiquetas (clave: valor) y jerarquía, pero no un esquema
#        tabular rígido: puede traer campos anidados o ausentes, y los
#        números suelen llegar como texto.
#    (c) Parsear con jsonlite::fromJSON(), aplanar (jsonlite::flatten() o
#        tidyr::unnest_wider()) y convertir tipos (as.numeric, as.Date).
#        Ej.:
#        aire <- fromJSON("https://www.datos.gov.co/resource/XXXX.json") |>
#                flatten() |> as_tibble()
#
# 3. Audios de audiencias judiciales (Rama Judicial)
#    (a) No estructurado.
#    (b) Señal de audio sin formato predefinido de variables; no hay filas
#        ni columnas.
#    (c) Feature engineering: transcripción (speech-to-text) y luego
#        representación del texto (DTM / TF-IDF), o extraer rasgos acústicos
#        (MFCC con tuneR/seewave). Cada audiencia queda como una fila del
#        tibble con sus rasgos numéricos y metadatos (fecha, despacho, duración).
#
# 4. Factura electrónica DIAN (XML)
#    (a) Semi-estructurado.
#    (b) Etiquetas jerárquicas (emisor, adquirente, ítems...) definidas por un
#        estándar (UBL 2.1), pero con estructura anidada y número variable de
#        ítems por factura.
#    (c) Parsear con xml2::read_xml(), extraer nodos con xml_find_all() +
#        xml_text() (XPath, ojo con los namespaces) y armar un tibble; una
#        fila por factura (encabezado) o por ítem (detalle). Ej.:
#        doc   <- xml2::read_xml("factura.xml")
#        items <- xml2::xml_find_all(doc, ".//cac:InvoiceLine")
#
# 5. Tabla HTML de Wikipedia scrapeada con rvest
#    (a) Semi-estructurado como fuente (HTML) → estructurado una vez extraída
#        la etiqueta <table>.
#    (b) El HTML mezcla marcado y contenido; la tabla sí tiene filas y
#        columnas, pero con notas al pie, celdas combinadas y números como texto.
#    (c) rvest::html_table() y limpieza: nombres de columna (janitor::clean_names),
#        quitar referencias "[1]", separadores de miles y convertir a numérico.
#        Ej.:
#        tabla <- rvest::read_html(url) |> rvest::html_element("table.wikitable") |>
#                 rvest::html_table()


# =============================================================================
# EJERCICIO 2: JSON anidado a DataFrame
# =============================================================================
url <- "https://jsonplaceholder.typicode.com/users"
raw <- fromJSON(url)

# 2.1 Explorar la estructura
str(raw, max.level = 2)

# ¿Qué columnas son listas/data.frames anidados?
anidadas <- names(raw)[sapply(raw, function(col) is.list(col) || is.data.frame(col))]
anidadas
# -> "address" (que a su vez contiene "geo") y "company"

str(raw$address)   # street, suite, city, zipcode, geo (data.frame con lat, lng)
str(raw$company)   # name, catchPhrase, bs

# 2.2 Aplanar a un tibble con una fila por usuario
# Opción A: jsonlite::flatten() (pega los niveles con ".")
usuarios <- raw |>
  flatten() |>
  as_tibble() |>
  select(name, email, address.city, address.geo.lat, address.geo.lng, company.name) |>
  mutate(
    address.geo.lat = as.numeric(address.geo.lat),   # vienen como texto
    address.geo.lng = as.numeric(address.geo.lng)
  )
usuarios

# Opción B: extrayendo cada sub-campo a mano (equivalente)
usuarios_b <- tibble(
  name         = raw$name,
  email        = raw$email,
  city         = raw$address$city,
  lat          = as.numeric(raw$address$geo$lat),
  lng          = as.numeric(raw$address$geo$lng),
  company_name = raw$company$name
)
usuarios_b

# Verificación: una fila por usuario
nrow(usuarios) == nrow(raw)

# 2.3 Respuesta:
# Es una fuente SEMI-ESTRUCTURADA: tiene claves y jerarquía, pero no un esquema
# plano. fromJSON() respeta la jerarquía del JSON: cada objeto anidado
# ("address", "company") se convierte en un data.frame DENTRO de una columna
# (y "geo" en un data.frame dentro de "address"). El resultado es un
# data.frame de columnas-data.frame, no una tabla plana de vectores atómicos.
# Por eso hay que aplanar (flatten/unnest) explícitamente. Además, lat/lng
# llegan como texto y hay que convertirlas a numérico.


# =============================================================================
# EJERCICIO 3: Matriz de diseño
# =============================================================================
titanic <- read.csv(ruta_titanic, stringsAsFactors = FALSE)
names(titanic) <- tolower(names(titanic))   # por si viene con mayúsculas (Kaggle)

datos3 <- titanic |>
  select(age, fare, sibsp, parch) |>
  na.omit()

X <- as.matrix(datos3)

# 3.1 X centrada y escalada
X_scaled <- scale(X)
dim(X_scaled)
print(object.size(X_scaled), units = "Kb")
round(colMeans(X_scaled), 10)       # ~0
round(apply(X_scaled, 2, sd), 10)   # 1

# 3.2 X'X
XtX <- crossprod(X_scaled)          # = t(X_scaled) %*% X_scaled
round(XtX, 2)
n <- nrow(X_scaled)
diag(XtX)                           # cada valor = n - 1
n - 1
# Respuesta: con X estandarizada, la diagonal de X'X es la suma de cuadrados
# de cada variable = (n - 1) * varianza = n - 1. Fuera de la diagonal están
# (n - 1) * correlación; por eso X'X / (n - 1) es la MATRIZ DE CORRELACIONES:
round(XtX / (n - 1), 4)
round(cor(X), 4)                    # coincide

# 3.3 Versión dispersa
X_sparse        <- Matrix(X_scaled, sparse = TRUE)
X_sparse_orig   <- Matrix(X, sparse = TRUE)   # comparación: X sin escalar

tamanos <- tibble(
  version  = c("Densa escalada", "Dispersa escalada", "Densa original", "Dispersa original"),
  bytes    = c(object.size(X_scaled), object.size(X_sparse),
               object.size(X), object.size(X_sparse_orig)),
  pct_ceros = c(mean(X_scaled == 0), mean(X_scaled == 0), mean(X == 0), mean(X == 0)) * 100
)
tamanos
# Respuesta: NO tiene sentido. Tras centrar, casi ningún valor es exactamente 0
# (los ceros de sibsp/parch se vuelven negativos), así que la versión dispersa
# guarda todos los valores + sus índices y ocupa MÁS memoria que la densa.
# Incluso sin escalar, la proporción de ceros (sibsp, parch) no es lo bastante
# alta y la matriz es pequeña (4 columnas). El formato disperso compensa
# cuando la densidad es muy baja (p. ej. < 5-10% de no-ceros, como una DTM).

# 3.4 Respuesta (estructura para relaciones familiares):
# Un GRAFO no dirigido G = (V, E): nodos = pasajeros, aristas = vínculo
# familiar (hermano/cónyuge → sibsp; padre/hijo → parch), con atributo de
# tipo de relación. sibsp y parch son solo el GRADO de cada nodo (cuántos
# familiares tiene a bordo), pero no dicen CON QUIÉN; una tabla plana pierde
# esa topología. Permite encontrar familias como componentes conexas,
# y estudiar si la supervivencia se agrupa por familia.
#
# Ilustración: aproximamos las aristas uniendo pasajeros que comparten
# tiquete y tienen familiares a bordo (si la columna 'ticket' existe).
if ("ticket" %in% names(titanic) && requireNamespace("igraph", quietly = TRUE)) {
  fam <- titanic |>
    mutate(id = row_number()) |>
    filter(sibsp + parch > 0)
  aristas <- fam |>
    select(id, ticket) |>
    inner_join(fam |> select(id, ticket), by = "ticket",
               suffix = c("_from", "_to"), relationship = "many-to-many") |>
    filter(id_from < id_to) |>
    select(from = id_from, to = id_to)
  G_fam <- igraph::graph_from_data_frame(aristas, directed = FALSE,
                                         vertices = fam |> select(id, survived))
  comp <- igraph::components(G_fam)
  cat("Pasajeros con familia:", igraph::vcount(G_fam),
      "| Vínculos:", igraph::ecount(G_fam),
      "| Grupos familiares (componentes):", comp$no, "\n")
}


# =============================================================================
# EJERCICIO 4: Concentración de distancias
# =============================================================================
set.seed(42)
dimensiones <- c(1, 2, 5, 10, 50, 100, 500, 1000, 5000)

dist_euclid <- function(x, y) sqrt(sum((x - y)^2))
dist_coseno <- function(x, y) 1 - sum(x * y) / (sqrt(sum(x^2)) * sqrt(sum(y^2)))

simular <- function(p) {
  puntos <- matrix(runif(500 * p), nrow = 500, ncol = p)
  # 200 pares: (1, 201), (2, 202), ..., (200, 400) — igual que en clase
  d_euc <- sapply(1:200, function(i) dist_euclid(puntos[i, ], puntos[i + 200, ]))
  d_cos <- sapply(1:200, function(i) dist_coseno(puntos[i, ], puntos[i + 200, ]))
  tibble(
    p = p,
    metrica = c("Euclidiana", "Coseno"),
    dist_media = c(mean(d_euc), mean(d_cos)),
    cv_pct = c(sd(d_euc) / mean(d_euc), sd(d_cos) / mean(d_cos)) * 100
  )
}

resultados <- bind_rows(lapply(dimensiones, simular))

# 4.1 Tabla euclidiana
tabla_euc <- resultados |> filter(metrica == "Euclidiana") |>
  mutate(across(c(dist_media, cv_pct), \(x) round(x, 4)))
tabla_euc

# 4.2 Gráfico: distancia media y CV vs p (escala log en x)
resultados |>
  filter(metrica == "Euclidiana") |>
  pivot_longer(c(dist_media, cv_pct), names_to = "medida", values_to = "valor") |>
  mutate(medida = recode(medida, dist_media = "Distancia media",
                         cv_pct = "Coeficiente de variación (%)")) |>
  ggplot(aes(p, valor)) +
  geom_line(color = "steelblue") +
  geom_point(color = "steelblue", size = 2) +
  geom_hline(data = tibble(medida = "Coeficiente de variación (%)", y = 5),
             aes(yintercept = y), linetype = "dashed", color = "firebrick") +
  scale_x_log10(breaks = dimensiones) +
  facet_wrap(~ medida, scales = "free_y") +
  labs(title = "Concentración de distancias euclidianas en [0,1]^p",
       x = "Dimensión p (escala log)", y = NULL) +
  theme_minimal()

# 4.3 ¿A partir de qué p el CV < 5%?
p_cv5 <- tabla_euc |> filter(cv_pct < 5) |> slice_min(p) |> pull(p)
p_cv5
# Respuesta: con set.seed(42) el CV cae por debajo de 5% alrededor de p = 500
# (entre 100 y 500; verifique con su salida). Implicación para K-NN: las
# distancias al vecino más cercano y al más lejano son casi iguales, así que
# "los k más cercanos" son prácticamente una selección arbitraria; el
# clasificador pierde poder discriminativo y es muy sensible al ruido. Hay que
# reducir dimensión (PCA), seleccionar variables o usar otra métrica.

# 4.4 Repetir con distancia coseno
tabla_cos <- resultados |> filter(metrica == "Coseno") |>
  mutate(across(c(dist_media, cv_pct), \(x) round(x, 4)))
tabla_cos

# Comparación del CV de ambas métricas
resultados |>
  ggplot(aes(p, cv_pct, color = metrica)) +
  geom_line() + geom_point(size = 2) +
  geom_hline(yintercept = 5, linetype = "dashed") +
  scale_x_log10(breaks = dimensiones) +
  labs(title = "CV de las distancias: euclidiana vs coseno",
       x = "Dimensión p (escala log)", y = "CV (%)", color = "Métrica") +
  theme_minimal()

# Respuesta: también se concentra. Con datos uniformes en [0,1]^p (todas las
# coordenadas positivas) los vectores apuntan casi en la misma dirección que
# (1,1,...,1): la distancia coseno media tiende a 1 - 3/4 = 0.25 y su
# dispersión cae aproximadamente como 1/sqrt(p). Para p pequeño el CV del
# coseno es incluso mayor que el euclidiano, pero en p grande ambas se
# concentran; el coseno no resuelve la maldición de la dimensionalidad para
# datos densos. Su ventaja aparece con datos DISPERSOS (texto), donde ignora
# los ceros compartidos y la longitud del documento.


# =============================================================================
# EJERCICIO 5: PCA y reducción de dimensionalidad
# =============================================================================
datos5 <- titanic |>
  select(survived, age, fare, sibsp, parch, pclass) |>
  na.omit()

y5 <- datos5$survived
X5 <- datos5 |> select(-survived) |> as.matrix()

# 5.1 PCA
pca <- prcomp(X5, scale. = TRUE)
summary(pca)

var_expl  <- pca$sdev^2 / sum(pca$sdev^2)
var_acum  <- cumsum(var_expl)
tabla_pca <- tibble(componente = seq_along(var_expl),
                    var_expl = round(var_expl * 100, 2),
                    var_acum = round(var_acum * 100, 2))
tabla_pca

k80 <- which(var_acum >= 0.80)[1]
k95 <- which(var_acum >= 0.95)[1]
cat("Componentes para >= 80% de varianza:", k80, "\n")
cat("Componentes para >= 95% de varianza:", k95, "\n")
# Con 5 variables poco correlacionadas, la reducción es modesta: se necesitan
# varios componentes (típicamente 3-4 para el 80% y 4-5 para el 95%).

# 5.2 Scree plot (varianza individual y acumulada)
ggplot(tabla_pca, aes(componente)) +
  geom_col(aes(y = var_expl), fill = "grey75") +
  geom_line(aes(y = var_acum), color = "steelblue") +
  geom_point(aes(y = var_acum), color = "steelblue", size = 2.5) +
  geom_hline(yintercept = c(80, 95), linetype = "dashed",
             color = c("darkorange", "firebrick")) +
  scale_x_continuous(breaks = tabla_pca$componente,
                     labels = paste0("PC", tabla_pca$componente)) +
  labs(title = "Scree plot — PCA Titanic",
       subtitle = "Barras: varianza explicada; línea: varianza acumulada",
       x = NULL, y = "Varianza (%)") +
  theme_minimal()

# 5.3 Loadings de PC1 y PC2
loadings <- round(pca$rotation[, 1:2], 3)
loadings

# Variables dominantes (mayor |loading|)
sort(abs(pca$rotation[, 1]), decreasing = TRUE)
sort(abs(pca$rotation[, 2]), decreasing = TRUE)

# Gráfico de loadings
as_tibble(pca$rotation[, 1:2], rownames = "variable") |>
  ggplot(aes(PC1, PC2, label = variable)) +
  geom_segment(aes(x = 0, y = 0, xend = PC1, yend = PC2),
               arrow = arrow(length = unit(0.2, "cm")), color = "steelblue") +
  geom_text(vjust = -0.6) +
  coord_equal() +
  labs(title = "Loadings de PC1 y PC2") +
  theme_minimal()

# Interpretación (revise los signos en su salida; el signo de un PC es arbitrario):
# - Típicamente un componente lo dominan sibsp y parch (mismo signo):
#   "tamaño del grupo familiar a bordo".
# - El otro lo dominan pclass y fare (signos opuestos) junto con age:
#   "nivel socioeconómico" — primera clase = tarifa alta y pasajeros
#   mayores; tercera clase = tarifa baja y pasajeros más jóvenes.
# Así PC1 y PC2 resumen dos ejes: familia vs. clase/riqueza.

# 5.4 Reto: K-Means (k = 2) sobre X y sobre los 2 primeros PCs
# Se usa X escalada: sin escalar, 'fare' (rango 0-512) dominaría la distancia.
X5_scaled <- scale(X5)
pcs2      <- pca$x[, 1:2]

set.seed(42)
km_X   <- kmeans(X5_scaled, centers = 2, nstart = 25)
km_PC  <- kmeans(pcs2,      centers = 2, nstart = 25)

# Tablas de contingencia contra la supervivencia
table(cluster = km_X$cluster,  survived = y5)
table(cluster = km_PC$cluster, survived = y5)

# Coincidencia: las etiquetas de cluster (1/2) son arbitrarias, así que se
# toma la mejor de las dos asignaciones posibles.
coincidencia <- function(cl, y) {
  a <- mean((cl == 2) == (y == 1))
  max(a, 1 - a)
}

# Índice de Rand ajustado (0 = azar, 1 = acuerdo perfecto)
ari <- function(a, b) {
  tab <- table(a, b)
  comb2 <- function(x) sum(choose(x, 2))
  s_ij <- comb2(tab); s_a <- comb2(rowSums(tab)); s_b <- comb2(colSums(tab))
  esperado <- s_a * s_b / choose(sum(tab), 2)
  (s_ij - esperado) / ((s_a + s_b) / 2 - esperado)
}

comparacion <- tibble(
  representacion = c("X escalada (5 variables)", "2 primeros PCs"),
  coincidencia_pct = round(100 * c(coincidencia(km_X$cluster, y5),
                                   coincidencia(km_PC$cluster, y5)), 1),
  ARI = round(c(ari(km_X$cluster, y5), ari(km_PC$cluster, y5)), 3),
  tasa_base_pct = round(100 * max(mean(y5), 1 - mean(y5)), 1)
)
comparacion

# Visualización de los clusters en el plano PC1-PC2
tibble(PC1 = pcs2[, 1], PC2 = pcs2[, 2],
       cluster = factor(km_PC$cluster),
       survived = factor(y5, labels = c("No", "Sí"))) |>
  ggplot(aes(PC1, PC2, color = cluster, shape = survived)) +
  geom_point(alpha = 0.6) +
  labs(title = "K-Means (k = 2) sobre los 2 primeros PCs",
       color = "Cluster", shape = "Sobrevivió") +
  theme_minimal()

# Interpretación: compare 'coincidencia_pct' con 'tasa_base_pct' (lo que se
# obtendría prediciendo siempre la clase mayoritaria). K-Means no usa
# 'survived'; agrupa por similitud en las variables. Los grupos suelen
# separar clase/tarifa o tamaño de familia, que se relacionan solo
# parcialmente con la supervivencia (falta 'sex', el predictor más fuerte).
# La representación con mejor coincidencia (y ARI más alto) responde la
# pregunta; en los 2 PCs se pierde la varianza de los demás componentes,
# pero también se elimina ruido, así que el resultado puede ir en cualquier
# sentido: reporte lo que obtenga.