# =============================================================================
#  Minería de Datos — Clase 14
# =============================================================================

library(rpart)
tiene_rpart_plot <- requireNamespace("rpart.plot", quietly = TRUE)
if (tiene_rpart_plot) library(rpart.plot)

# -----------------------------------------------------------------------------
# 0. Datos
# -----------------------------------------------------------------------------
ruta <- "data/desercion.csv"

if (file.exists(ruta)) {
  desercion <- read.csv(ruta)
} else {
  set.seed(2026)
  n <- 1200
  estrato <- sample(1:6, n, replace = TRUE,
                    prob = c(.20, .32, .28, .12, .05, .03))
  papa    <- round(pmin(5, pmax(2, rnorm(n, 3.7, 0.45))), 1)
  creditos_perdidos <- rpois(n, lambda = pmax(0.2, 3 * (4.2 - papa)))
  horas_trabajo <- ifelse(runif(n) < ifelse(estrato <= 2, 0.45, 0.15),
                          sample(seq(8, 48, 4), n, replace = TRUE), 0)
  distancia_km <- round(rgamma(n, shape = 2, rate = 0.25), 1)
  semestre     <- sample(1:10, n, replace = TRUE)

  p <- ifelse(papa < 3.3 & creditos_perdidos >= 3, 0.75,
       ifelse(papa < 3.3, 0.40,
       ifelse(horas_trabajo >= 24 & estrato <= 2, 0.50, 0.06)))
  deserta <- ifelse(runif(n) < p, "Sí", "No")
  retiro_registrado <- ifelse(deserta == "Sí",
                              ifelse(runif(n) < 0.9,  "Sí", "No"),
                              ifelse(runif(n) < 0.02, "Sí", "No"))

  desercion <- data.frame(papa, creditos_perdidos, estrato,
                          horas_trabajo, distancia_km, semestre,
                          retiro_registrado, deserta)
  dir.create("data", showWarnings = FALSE)
  write.csv(desercion, ruta, row.names = FALSE)
}

# Factores con niveles fijos (robusto a problemas de codificación de la tilde)
a_factor <- function(x) factor(ifelse(grepl("^S", x), "Sí", "No"),
                               levels = c("No", "Sí"))
desercion$deserta           <- a_factor(desercion$deserta)
desercion$retiro_registrado <- a_factor(desercion$retiro_registrado)
str(desercion)

# Funciones auxiliares ---------------------------------------------------------
n_hojas   <- function(arbol) sum(arbol$frame$var == "<leaf>")
exactitud <- function(arbol, datos)
  mean(predict(arbol, datos, type = "class") == datos$deserta)
sensibilidad <- function(pred, real) mean(pred[real == "Sí"] == "Sí")

# Reglas de las hojas con cobertura (equivalente a rpart.rules(cover = TRUE),
# pero solo con rpart)
reglas_hojas <- function(arbol) {
  fr    <- arbol$frame
  hoja  <- fr$var == "<leaf>"
  nodos <- as.integer(rownames(fr)[hoja])
  caminos <- path.rpart(arbol, nodes = nodos, print.it = FALSE)
  data.frame(
    regla       = sapply(caminos, function(x) paste(x[-1], collapse = "  Y  ")),
    prediccion  = attr(arbol, "ylevels")[fr$yval[hoja]],
    P_si        = round(fr$yval2[hoja, 5], 2),
    n           = fr$n[hoja],
    cobertura   = paste0(round(100 * fr$n[hoja] / fr$n[1], 1), "%"),
    row.names   = NULL
  )
}

# -----------------------------------------------------------------------------
# a. Tasa de deserción y exactitud de predecir siempre "No"
# -----------------------------------------------------------------------------
cat("\n========== a. Tasa de deserción ==========\n")
print(table(desercion$deserta))
tasa <- mean(desercion$deserta == "Sí")
cat(sprintf("Tasa de deserción: %.1f%%\n", 100 * tasa))
cat(sprintf("Exactitud de predecir siempre 'No' (1.200 casos): %.1f%%\n",
            100 * (1 - tasa)))

# RESPUESTA a:
# 259 de 1.200 estudiantes desertan (21,6%). Un "modelo" que siempre dice "No"
# acierta el 78,4% de las veces y no detecta a ningún desertor. Esa es la
# línea base que cualquier árbol tiene que superar. En la partición de prueba
# (sección c) esa línea base es 76,7%.

# -----------------------------------------------------------------------------
# b. Variable no disponible al momento de predecir (fuga de información)
# -----------------------------------------------------------------------------
cat("\n========== b. Fuga de información ==========\n")
print(table(Retiro = desercion$retiro_registrado, Deserta = desercion$deserta))

# RESPUESTA b:
# retiro_registrado (retiro registrado en el SIA) se produce DESPUÉS o al mismo
# tiempo que la deserción: es una consecuencia de Y, no una causa. Cuando
# Bienestar quiere llamar al estudiante para ofrecerle tutoría, ese registro
# todavía no existe. Si se incluye, el árbol la toma como raíz y la exactitud
# en prueba sube a 95,6% (sensibilidad 84,5%), un resultado irreal que no se
# reproduciría en producción. Se excluye. (Se muestra abajo, después de la
# partición, solo como evidencia.)

# -----------------------------------------------------------------------------
# c. Partición 70/30, árbol sin restricciones vs. árbol podado con VC
# -----------------------------------------------------------------------------
cat("\n========== c. Partición y ajuste ==========\n")
set.seed(2026)
idx   <- sample(nrow(desercion), 0.7 * nrow(desercion))
train <- desercion[idx, ]    # 840 estudiantes
test  <- desercion[-idx, ]   # 360 estudiantes
cat(sprintf("Entrenamiento: %d | Prueba: %d\n", nrow(train), nrow(test)))
base_test <- mean(test$deserta == "No")
cat(sprintf("Línea base en prueba (siempre 'No'): %.1f%%\n", 100 * base_test))

# Evidencia de la fuga (b): árbol CON retiro_registrado
arbol_fuga <- rpart(deserta ~ ., data = train, method = "class")
pred_fuga  <- predict(arbol_fuga, test, type = "class")
cat(sprintf("Con retiro_registrado -> raíz: %s | exactitud prueba: %.1f%% | sensibilidad: %.1f%%\n",
            arbol_fuga$frame$var[1],
            100 * mean(pred_fuga == test$deserta),
            100 * sensibilidad(pred_fuga, test$deserta)))

# Fórmula sin la variable con fuga
formula_ok <- deserta ~ papa + creditos_perdidos + estrato + horas_trabajo +
                        distancia_km + semestre

# Árbol sin restricciones (crece hasta hojas puras). La validación cruzada
# interna de rpart (xval = 10) usa la semilla, por eso se fija otra vez.
set.seed(2026)
arbol_full <- rpart(formula_ok, data = train, method = "class",
                    control = rpart.control(cp = 0, minsplit = 2, minbucket = 1))

# Árbol con los valores por defecto (cp = 0,01), como referencia
arbol_def <- rpart(formula_ok, data = train, method = "class")

# Poda por costo-complejidad: cp con el menor xerror
printcp(arbol_full)
plotcp(arbol_full)
tabla_cp <- arbol_full$cptable
cp_opt   <- tabla_cp[which.min(tabla_cp[, "xerror"]), "CP"]
cat(sprintf("cp óptimo (xerror mínimo): %.4f\n", cp_opt))
arbol_podado <- prune(arbol_full, cp = cp_opt)

comparacion <- data.frame(
  modelo = c("Siempre 'No'", "Sin restricciones (cp = 0)",
             "Por defecto (cp = 0,01)", sprintf("Podado VC (cp = %.4f)", cp_opt)),
  hojas  = c(1, n_hojas(arbol_full), n_hojas(arbol_def), n_hojas(arbol_podado)),
  exact_train = round(100 * c(mean(train$deserta == "No"),
                              exactitud(arbol_full, train),
                              exactitud(arbol_def, train),
                              exactitud(arbol_podado, train)), 1),
  exact_test  = round(100 * c(base_test,
                              exactitud(arbol_full, test),
                              exactitud(arbol_def, test),
                              exactitud(arbol_podado, test)), 1)
)
comparacion$brecha <- comparacion$exact_train - comparacion$exact_test
print(comparacion, row.names = FALSE)

# RESPUESTA c:
#  Modelo                       Hojas  Entrenamiento  Prueba
#  Siempre "No"                     1      79,2%       76,7%
#  Sin restricciones (cp = 0)     136     100,0%       76,4%
#  Por defecto (cp = 0,01)         13      88,8%       81,4%
#  Podado con VC (cp = 0,0171)      3      85,7%       80,3%
#
# El árbol sin restricciones memoriza: 100% en entrenamiento y 76,4% en
# prueba, PEOR que predecir siempre "No" (brecha de 23,6 puntos). En la tabla
# cp, el xerror es mínimo con 2 divisiones (0,686) y luego sube hasta 0,954
# con el árbol completo: más hojas = más ruido. El árbol podado tiene solo
# 3 hojas, una brecha de 5 puntos y pierde apenas 1,1 puntos frente al árbol
# por defecto de 13 hojas: casi igual de preciso y mucho más simple.

# -----------------------------------------------------------------------------
# d. Reglas del árbol podado con su cobertura
# -----------------------------------------------------------------------------
cat("\n========== d. Reglas del árbol podado ==========\n")
print(arbol_podado)
reglas_podado <- reglas_hojas(arbol_podado)
print(reglas_podado, row.names = FALSE)

if (tiene_rpart_plot) {
  rpart.plot(arbol_podado, extra = 106, main = "Árbol podado (VC)")
  print(rpart.rules(arbol_podado, cover = TRUE))
} else {
  plot(arbol_podado, margin = 0.1); text(arbol_podado, use.n = TRUE)
}

imp <- arbol_podado$variable.importance
cat("Importancia (suma de mejoras):\n");  print(round(imp, 1))
cat("Importancia (%):\n");                print(round(100 * imp / sum(imp), 1))

# RESPUESTA d:
#  R1. SI papa >= 3,25                            -> No  P(Sí) = 0,12  cobertura 83%
#  R2. SI papa <  3,25 Y créditos perdidos < 2,5  -> No  P(Sí) = 0,33  cobertura  5%
#  R3. SI papa <  3,25 Y créditos perdidos >= 2,5 -> Sí  P(Sí) = 0,79  cobertura 11%
# Importancia: papa 63,4 y créditos perdidos 21,3 (74,8% y 25,2% del total).
# Solo la regla R3 dispara la alerta. R2 predice "No", pero un 33% de riesgo es
# casi el triple de la tasa en R1: es un grupo para vigilar.

# -----------------------------------------------------------------------------
# e. ¿Recupera las tres reglas de la simulación?
# -----------------------------------------------------------------------------
cat("\n========== e. Reglas de la simulación vs. árbol ==========\n")
# Reglas que generaron los datos:
#  S1. papa < 3,3 y créditos >= 3                     -> P(Sí) = 0,75
#  S2. papa < 3,3 y créditos < 3                      -> P(Sí) = 0,40
#  S3. papa >= 3,3, horas >= 24 y estrato <= 2        -> P(Sí) = 0,50
#  Resto                                              -> P(Sí) = 0,06
grupo_sim <- with(train, ifelse(papa < 3.3 & creditos_perdidos >= 3, "S1",
                         ifelse(papa < 3.3, "S2",
                         ifelse(horas_trabajo >= 24 & estrato <= 2, "S3", "Resto"))))
resumen_sim <- aggregate(deserta ~ grupo_sim,
                         data = data.frame(grupo_sim, deserta = train$deserta == "Sí"),
                         FUN = function(x) c(n = length(x), tasa = round(mean(x), 2)))
print(do.call(data.frame, resumen_sim))

# ¿Por qué se pierde S3? Dentro de la hoja papa >= 3,25 (700 estudiantes),
# partir por horas_trabajo y estrato NO cambia la clase predicha de ninguna
# hija (todas siguen prediciendo "No"), así que el error de clasificación no
# baja: la poda por costo-complejidad mide el error de clasificación y elimina
# esa división.
hoja_r1 <- train[train$papa >= 3.25, ]
s3 <- hoja_r1$horas_trabajo >= 22 & hoja_r1$estrato <= 2
cat(sprintf("Subgrupo S3 dentro de papa >= 3,25: n = %d (%.1f%% de train), P(Sí) = %.2f\n",
            sum(s3), 100 * sum(s3) / nrow(train), mean(hoja_r1$deserta[s3] == "Sí")))
cat(sprintf("Resto de la hoja: n = %d, P(Sí) = %.2f\n",
            sum(!s3), mean(hoja_r1$deserta[!s3] == "Sí")))
cat(sprintf("Errores de la hoja sin partir: %d | partida por S3 (ambas predicen 'No'): %d\n",
            sum(hoja_r1$deserta == "Sí"),
            sum(hoja_r1$deserta[s3] == "Sí") + sum(hoja_r1$deserta[!s3] == "Sí")))
cat("Variables del árbol por defecto:",
    setdiff(unique(as.character(arbol_def$frame$var)), "<leaf>"), "\n")

# RESPUESTA e:
#  - S1 SÍ se recupera: papa < 3,25 y créditos >= 2,5 -> P(Sí) = 0,79 (simulado
#    0,75). Los umbrales 3,25 y 2,5 son los puntos medios entre valores
#    observados (papa tiene un decimal; créditos es entero), equivalentes a
#    "< 3,3" y ">= 3".
#  - S2 se recupera EN PARTE: papa < 3,25 y créditos < 2,5 -> P(Sí) = 0,33
#    (simulado 0,40); como su clase mayoritaria es "No", la regla no genera
#    alerta, solo queda como hoja de riesgo intermedio.
#  - S3 NO se recupera en el podado. Esos estudiantes (unos 107 en train, 13%)
#    tienen P(Sí) ≈ 0,49: es una moneda al aire, la clase mayoritaria sigue
#    siendo "No" y separar el grupo no reduce ni un error de clasificación
#    (85 errores antes y después). Como cp mide la mejora en error de
#    clasificación, la poda la descarta. El árbol por defecto sí la encuentra
#    (horas_trabajo < 22 y estrato >= 2,5, P(Sí) = 0,49) y el árbol con
#    costos (sección g) la convierte en alerta.

# -----------------------------------------------------------------------------
# f. ¿Aparece distancia_km en algún árbol?
# -----------------------------------------------------------------------------
cat("\n========== f. distancia_km ==========\n")
cuenta_var <- function(arbol, v) sum(arbol$frame$var == v)
cat(sprintf("Divisiones con distancia_km -> sin restricciones: %d de %d | por defecto: %d de %d | podado: %d de %d\n",
            cuenta_var(arbol_full, "distancia_km"),   sum(arbol_full$frame$var != "<leaf>"),
            cuenta_var(arbol_def, "distancia_km"),    sum(arbol_def$frame$var != "<leaf>"),
            cuenta_var(arbol_podado, "distancia_km"), sum(arbol_podado$frame$var != "<leaf>")))
cat("Importancia (%) árbol sin restricciones:\n")
print(round(100 * arbol_full$variable.importance / sum(arbol_full$variable.importance), 1))

# RESPUESTA f:
# distancia_km no participa en la regla que generó los datos: es ruido puro.
# Aun así, el árbol sin restricciones la usa en 50 de sus 135 divisiones y le
# asigna 24% de la importancia (la segunda variable más importante). También
# aparece en ramas profundas del árbol por defecto (nodos con 9 a 34
# estudiantes). En el árbol podado no aparece. Significa que el árbol grande
# memorizó casualidades de la muestra: una variable continua con muchos
# valores distintos ofrece muchísimos cortes posibles y siempre alguno separa
# por azar unos pocos casos. Importancia ≠ relevancia real; la poda con
# validación cruzada elimina esas divisiones.

# -----------------------------------------------------------------------------
# g. Sensibilidad para "Sí" y mejora con matriz de pérdida
# -----------------------------------------------------------------------------
cat("\n========== g. Sensibilidad y costos ==========\n")
pred_podado <- predict(arbol_podado, test, type = "class")
cm_podado   <- table(Real = test$deserta, Predicho = pred_podado)
print(cm_podado)

# Matriz de pérdida de rpart: filas = clase real, columnas = clase predicha.
#                Pred No  Pred Sí
#   Real No         0        1     (falsa alarma: cuesta 1)
#   Real Sí         3        0     (no detectar a un desertor: cuesta 3)
perdida <- matrix(c(0, 3, 1, 0), nrow = 2)
arbol_costos <- rpart(formula_ok, data = train, method = "class",
                      parms   = list(loss = perdida),
                      control = rpart.control(cp = cp_opt))
print(arbol_costos)
print(reglas_hojas(arbol_costos), row.names = FALSE)
if (tiene_rpart_plot) rpart.plot(arbol_costos, extra = 106,
                                 main = "Árbol con costos (FN cuesta 3)")

pred_costos <- predict(arbol_costos, test, type = "class")
cm_costos   <- table(Real = test$deserta, Predicho = pred_costos)
print(cm_costos)

metricas <- function(cm) c(
  exactitud     = sum(diag(cm)) / sum(cm),
  sensibilidad  = cm["Sí", "Sí"] / sum(cm["Sí", ]),
  especificidad = cm["No", "No"] / sum(cm["No", ]),
  precision     = cm["Sí", "Sí"] / sum(cm[, "Sí"]),
  falsas_alarmas = cm["No", "Sí"],
  desertores_no_detectados = cm["Sí", "No"]
)
tabla_g <- rbind(podado = metricas(cm_podado), costos = metricas(cm_costos))
tabla_g[, 1:4] <- round(100 * tabla_g[, 1:4], 1)
print(cbind(hojas = c(n_hojas(arbol_podado), n_hojas(arbol_costos)), tabla_g))

# RESPUESTA g:
#                      Podado   Con costos
#  Hojas                    3        4
#  Exactitud            80,3%    81,1%
#  Sensibilidad (Sí)    28,6%    72,6%
#  Especificidad        96,0%    83,7%
#  Precisión (Sí)       68,6%    57,5%
#  Falsas alarmas          11       45
#  Desertores perdidos     60       23
#
# El árbol podado detecta solo 24 de los 84 desertores de prueba (28,6%): su
# 80% de exactitud esconde que deja pasar a 7 de cada 10. Al hacer que no
# detectar a un desertor cueste 3 veces más que una falsa alarma, el árbol
# cambia: ahora cualquier estudiante con papa < 3,25 recibe alerta, y aparece
# la regla de trabajo y estrato (papa >= 3,25, horas >= 22, estrato <= 2 ->
# alerta). La sensibilidad sube a 72,6% (61 de 84).
# ¿Qué se pierde? Precisión y especificidad: las falsas alarmas pasan de 11 a
# 45 (estudiantes citados sin necesidad) y solo el 57,5% de las alertas
# corresponde a un desertor real, frente al 68,6% antes. En esta muestra la
# exactitud global no cae (sube 0,8 puntos), pero eso no es lo usual; el costo
# real es tiempo de tutores y citas que no hacían falta. También cambia la
# lectura del árbol: las reglas S1 y S2 se fusionan en una sola alerta.

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Le recomendaría a Bienestar el árbol con costos: en una alerta temprana el
# error grave es no llamar a quien va a desertar, y este árbol detecta 61 de
# 84 desertores (frente a 24 del podado) a cambio de 34 citas adicionales de
# tutoría, un costo bajo comparado con perder a un estudiante; además sigue
# siendo legible (4 reglas) y recupera el grupo de riesgo de estudiantes que
# trabajan y son de estratos 1 y 2.
