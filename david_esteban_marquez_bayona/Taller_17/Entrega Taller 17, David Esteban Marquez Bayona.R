# =============================================================================
# Minería de Datos — Clase 17: Máquinas de soporte vectorial y KNN
# Taller 17: Ejercicio 1 (calidad del agua, a mano) y Ejercicio 2 (deserción)
# Autor: David Márquez
# =============================================================================
# install.packages("e1071")
library(e1071)

# =============================================================================
# EJERCICIO 1: calidad del agua (SVM y KNN "a mano")
# =============================================================================
agua <- data.frame(
  municipio = c("M1", "M2", "M3", "M4"),
  pH        = c(7.2, 6.1, 7.5, 5.8),
  turbiedad = c(1.2, 8.5, 0.8, 12.0),
  y         = c(1, -1, 1, -1)
)
nuevo <- c(pH = 6.8, turbiedad = 3.5)

# -----------------------------------------------------------------------------
# a. SVM a mano
# -----------------------------------------------------------------------------
X  <- as.matrix(agua[, c("pH", "turbiedad")])
mu <- colMeans(X); de <- apply(X, 2, sd)      # sd con n - 1
mu; round(de, 3)
Z  <- scale(X, center = mu, scale = de)
rownames(Z) <- agua$municipio
round(Z, 3)

# Par más cercano de clases opuestas (en z)
pos <- which(agua$y == 1); neg <- which(agua$y == -1)
pares <- expand.grid(i = pos, j = neg)
pares$dist <- apply(pares, 1, function(r) sqrt(sum((Z[r[1], ] - Z[r[2], ])^2)))
pares$par <- paste(agua$municipio[pares$i], agua$municipio[pares$j], sep = "-")
pares[order(pares$dist), c("par", "dist")]
mas_cercano <- pares[which.min(pares$dist), ]
zp <- Z[mas_cercano$i, ]; zn <- Z[mas_cercano$j, ]

# Mediatriz: w paralelo a (zp - zn), escalado para que f(zp) = 1 y f(zn) = -1
w <- 2 * (zp - zn) / sum((zp - zn)^2)
b <- -sum(w * (zp + zn) / 2)
f <- function(z) as.numeric(z %*% w + b)
round(w, 3); round(b, 3)
ancho <- 2 / sqrt(sum(w^2))
cat("Ancho de la carretera 2/||w|| =", round(ancho, 3), "\n")

# Certificado: y_i f(z_i) >= 1 para todos
cert <- data.frame(municipio = agua$municipio, y = agua$y,
                   f = round(f(Z), 3), y_f = round(agua$y * f(Z), 3))
cert
stopifnot(all(agua$y * f(Z) >= 1 - 1e-9))

# Comprobación con e1071 (margen duro: C muy grande, sin re-escalar)
svm_agua <- svm(x = Z, y = factor(agua$y, levels = c(1, -1)),
                kernel = "linear", cost = 1e5, scale = FALSE)
w_e1071 <- drop(t(svm_agua$coefs) %*% svm_agua$SV)
round(c(w_e1071, b = -svm_agua$rho), 3)       # debe coincidir con w, b
rownames(Z)[svm_agua$index]                    # vectores de soporte

# -----------------------------------------------------------------------------
# b. Predicción del municipio nuevo
# -----------------------------------------------------------------------------
z_nuevo <- (nuevo - mu) / de
round(z_nuevo, 3)
f_nuevo <- f(z_nuevo)
cat("f(nuevo) =", round(f_nuevo, 3), "-> clase", ifelse(f_nuevo > 0, "+1 (apta)", "-1 (no apta)"),
    "| dentro de la carretera:", abs(f_nuevo) < 1, "\n")

# -----------------------------------------------------------------------------
# c. KNN con K = 3, sin escalar y con z
# -----------------------------------------------------------------------------
d_crudo <- sqrt(colSums((t(X) - nuevo)^2))
d_z     <- sqrt(colSums((t(Z) - z_nuevo)^2))
names(d_crudo) <- names(d_z) <- agua$municipio
knn_tabla <- data.frame(
  sin_escalar = round(sort(d_crudo), 2), orden_crudo = names(sort(d_crudo)),
  con_z = round(sort(d_z), 2), orden_z = names(sort(d_z)), row.names = NULL)
knn_tabla
pred_knn <- function(d, k = 3) {
  vecinos <- names(sort(d))[1:k]
  sign(sum(agua$y[match(vecinos, agua$municipio)]))
}
c(knn_sin_escalar = pred_knn(d_crudo), knn_z = pred_knn(d_z))

# =============================================================================
# EJERCICIO 2: SVM con datos simulados (deserción)
# =============================================================================
set.seed(2026)
n <- 800
puntaje   <- round(rnorm(n, 650, 90))          # admisión
trabajo   <- round(pmax(0, rnorm(n, 12, 10)))  # h/semana
distancia <- round(runif(n, 1, 35), 1)         # km
nota_c1   <- round(pmin(5, pmax(1, rnorm(n, 3.4, 0.6))), 1)
riesgo <- -3.4 - 0.010*(puntaje - 650) - 1*(nota_c1 > 4) +
  5*(trabajo > 20 & nota_c1 < 3.2) + 2.5*(nota_c1 < 2.8)
deserta <- ifelse(runif(n) < plogis(riesgo), 1, -1)
datos <- data.frame(puntaje, trabajo, distancia, nota_c1,
                    deserta)
write.csv(datos, "desercion.csv", row.names = FALSE)

datos <- read.csv("desercion.csv")
datos$deserta <- factor(datos$deserta, levels = c(1, -1))   # 1 = positiva
vars <- c("puntaje", "trabajo", "distancia", "nota_c1")

# Métricas (positiva = deserta = 1)
metricas <- function(pred, real) {
  pred <- as.character(pred); real <- as.character(real)
  sens <- mean(pred[real == "1"] == "1")
  esp  <- mean(pred[real == "-1"] == "-1")
  c(exactitud = mean(pred == real), sensibilidad = sens,
    especificidad = esp, exact_balanceada = (sens + esp) / 2)
}

# -----------------------------------------------------------------------------
# a. Explorar
# -----------------------------------------------------------------------------
table(datos$deserta)
cat(sprintf("Proporción de desertores: %.1f%%\n", 100 * mean(datos$deserta == "1")))
sapply(datos[vars], function(x) c(min = min(x), media = mean(x), max = max(x), de = sd(x)))

# -----------------------------------------------------------------------------
# b. División 75/25 estratificada con semilla fija
# -----------------------------------------------------------------------------
set.seed(17)
idx_tr <- unlist(lapply(split(seq_len(nrow(datos)), datos$deserta),
                        function(id) sample(id, round(0.75 * length(id)))))
train <- datos[idx_tr, ]; test <- datos[-idx_tr, ]
c(n_train = nrow(train), n_test = nrow(test),
  pct_des_train = mean(train$deserta == "1"), pct_des_test = mean(test$deserta == "1"))

# Modelo trivial: "continúa" para todos
metricas(rep("-1", nrow(test)), test$deserta)

# Escalado SOLO con entrenamiento (equivale al pipeline de sklearn):
# svm(scale = TRUE) guarda medias/DE de train y las aplica a los datos nuevos.
# Para la validación cruzada se reajusta en cada pliegue (sin fuga).

# Pesos por clase "balanced": n / (2 * n_clase)
pesos_bal <- function(y) {
  tb <- table(y); setNames(as.numeric(length(y) / (2 * tb)), names(tb))
}

# Validación cruzada estratificada de 5 pliegues con exactitud balanceada
pliegues <- function(y, k = 5, semilla = 17) {
  set.seed(semilla); f <- integer(length(y))
  for (cl in levels(y)) { id <- which(y == cl); f[id] <- sample(rep(1:k, length.out = length(id))) }
  f
}
fold <- pliegues(train$deserta)

cv_svm <- function(datos_tr, cols, kernel, cost, gamma = NULL, pesos = FALSE,
                   escalar = TRUE) {
  ba <- sapply(1:5, function(i) {
    tr <- datos_tr[fold != i, ]; va <- datos_tr[fold == i, ]
    args <- list(x = as.matrix(tr[, cols]), y = tr$deserta, kernel = kernel,
                 cost = cost, scale = escalar)
    if (!is.null(gamma)) args$gamma <- gamma
    if (pesos) args$class.weights <- pesos_bal(tr$deserta)
    m <- do.call(svm, args)
    metricas(predict(m, as.matrix(va[, cols])), va$deserta)["exact_balanceada"]
  })
  mean(ba)
}

ajustar_final <- function(cols, kernel, cost, gamma = NULL, pesos = TRUE, escalar = TRUE) {
  args <- list(x = as.matrix(train[, cols]), y = train$deserta, kernel = kernel,
               cost = cost, scale = escalar)
  if (!is.null(gamma)) args$gamma <- gamma
  if (pesos) args$class.weights <- pesos_bal(train$deserta)
  do.call(svm, args)
}

# -----------------------------------------------------------------------------
# c. SVM lineal: rejilla de C, sin y con pesos
# -----------------------------------------------------------------------------
Cs <- c(0.01, 0.1, 1, 10, 100)
grid_lin <- expand.grid(C = Cs, pesos = c(FALSE, TRUE))
grid_lin$cv_bal <- mapply(function(C, p) cv_svm(train, vars, "linear", C, pesos = p),
                          grid_lin$C, grid_lin$pesos)
grid_lin

mejor_sin <- grid_lin[!grid_lin$pesos, ][which.max(grid_lin$cv_bal[!grid_lin$pesos]), ]
mejor_con <- grid_lin[ grid_lin$pesos, ][which.max(grid_lin$cv_bal[ grid_lin$pesos]), ]
lin_sin <- ajustar_final(vars, "linear", mejor_sin$C, pesos = FALSE)
lin_con <- ajustar_final(vars, "linear", mejor_con$C, pesos = TRUE)

# w en escala z (los SV de e1071 ya están escalados con medias/DE de train)
w_z <- function(m) {
  w <- drop(t(m$coefs) %*% m$SV)
  # e1071: decisión > 0 -> primer nivel ("1" = deserta), así que w apunta a desertar
  round(w, 3)
}
w_z(lin_con)

# -----------------------------------------------------------------------------
# d. SVM con kernel RBF: rejilla C x gamma con pesos
# -----------------------------------------------------------------------------
gammas <- c(0.01, 0.1, 1, 10)
grid_rbf <- expand.grid(C = Cs, gamma = gammas)
grid_rbf$cv_bal <- mapply(function(C, g) cv_svm(train, vars, "radial", C, g, pesos = TRUE),
                          grid_rbf$C, grid_rbf$gamma)
grid_rbf[order(-grid_rbf$cv_bal), ][1:5, ]
mejor_rbf <- grid_rbf[which.max(grid_rbf$cv_bal), ]
rbf_con <- ajustar_final(vars, "radial", mejor_rbf$C, mejor_rbf$gamma, pesos = TRUE)

# -----------------------------------------------------------------------------
# e. Mejor modelo sin escalar y sin distancia
# -----------------------------------------------------------------------------
rbf_sin_esc <- ajustar_final(vars, "radial", mejor_rbf$C, mejor_rbf$gamma,
                             pesos = TRUE, escalar = FALSE)
vars_sd <- setdiff(vars, "distancia")
rbf_sin_dist <- ajustar_final(vars_sd, "radial", mejor_rbf$C, mejor_rbf$gamma, pesos = TRUE)
cv_sin_dist <- cv_svm(train, vars_sd, "radial", mejor_rbf$C, mejor_rbf$gamma, pesos = TRUE)

# --- Evaluación en prueba: UNA sola vez, al final ---------------------------
evaluar <- function(m, cols) metricas(predict(m, as.matrix(test[, cols])), test$deserta)
resultados <- rbind(
  "Trivial (continúa)"               = metricas(rep("-1", nrow(test)), test$deserta),
  "Lineal sin pesos"                 = evaluar(lin_sin, vars),
  "Lineal con pesos"                 = evaluar(lin_con, vars),
  "RBF con pesos"                    = evaluar(rbf_con, vars),
  "RBF con pesos, sin escalar"       = evaluar(rbf_sin_esc, vars),
  "RBF con pesos, sin distancia"     = evaluar(rbf_sin_dist, vars_sd)
)
resultados <- cbind(round(resultados, 3),
  n_SV = c(NA, lin_sin$tot.nSV, lin_con$tot.nSV, rbf_con$tot.nSV,
           rbf_sin_esc$tot.nSV, rbf_sin_dist$tot.nSV))
resultados
cat("Mejor C lineal sin pesos:", mejor_sin$C, "| con pesos:", mejor_con$C,
    "| RBF: C =", mejor_rbf$C, "gamma =", mejor_rbf$gamma,
    "| CV RBF sin distancia:", round(cv_sin_dist, 3), "\n")

# =============================================================================
# RESPUESTAS
# =============================================================================
# EJERCICIO 1 (coincide con la clave)
# a. Medias (6,65; 5,625), DE (0,827; 5,531). En z, el par más cercano de
#    clases opuestas es M1-M2 (1,874). Vectores de soporte: M1 y M2.
#    w = (0,758; -0,751), b = -0,105, ancho de la carretera 2/||w|| = 1,874.
#    Certificado y·f(z): M1 = 1, M2 = 1, M3 = 1,33, M4 = 1,75 (todos >= 1).
#    e1071 con margen duro da los mismos w y b.
# b. z del nuevo = (0,181; -0,384), f = +0,32 -> apta (+1), pero |f| < 1:
#    queda DENTRO de la carretera, es un caso dudoso. A la secretaría le diría
#    que no lo clasifique con este modelo: repetir el muestreo. Además, con la
#    norma real (turbiedad máx. 2 UNT) ese agua (3,5 UNT) NO es apta: el
#    modelo aprendió de solo 4 municipios y no conoce la norma.
# c. Sin escalar: M1 2,33; M3 2,79; M2 5,05; M4 8,56. Con z: M1 0,64;
#    M3 0,98; M2 1,24; M4 1,96. El orden no cambia y con K = 3 (M1, M3, M2)
#    la predicción es apta (+1) en ambos casos, igual que la SVM. Recomendaría
#    la SVM porque además de la clase da la distancia a la frontera (avisa
#    que el caso es dudoso); con 4 datos ninguno es confiable y lo correcto
#    es aplicar la norma.
#
# EJERCICIO 2 (división 75/25 estratificada con set.seed(17) en R; la clave
# usa sklearn con random_state = 17, así que las cifras difieren algo. La
# prueba tiene solo 26 desertores: 1 desertor = 3,8 puntos de sensibilidad.)
# a. 104 de 800 desertan (13,0 %). Predecir "continúa" para todos da 87 % de
#    exactitud en prueba, pero sensibilidad 0 (no detecta a nadie) y
#    exactitud balanceada 0,50. Por eso hay que usar exactitud balanceada o
#    sensibilidad. Escalas muy distintas: puntaje ~416-933, trabajo 0-46,
#    distancia 1-35, nota 1,2-5.
# b. 600 de entrenamiento y 200 de prueba, ambos con 13 % de desertores. El
#    escalado lo hace svm(scale = TRUE) con medias/DE de entrenamiento
#    (también dentro de cada pliegue de la VC).
# c. Sin pesos (mejor C = 10): exactitud 89,5 % pero sensibilidad 0,27 y
#    exactitud balanceada 0,63: casi ignora a los desertores. Con pesos
#    balanceados (mejor C = 0,1 en VC, 0,791): exactitud balanceada en prueba
#    0,73, sensibilidad 0,65, especificidad 0,81.
#    w en z: puntaje -0,67, trabajo +0,59, distancia -0,20, nota_c1 -0,84.
#    Los signos coinciden con el mecanismo (puntaje y nota bajos y trabajo
#    alto aumentan el riesgo). distancia tiene el |w| más pequeño: es la
#    variable que no importa (su peso no nulo es ruido muestral).
# d. RBF con pesos: mejor C = 10, gamma = 0,01 (VC 0,811 vs. 0,791 del
#    lineal). En prueba: exactitud balanceada 0,75 (lineal 0,73), sensibilidad
#    0,65 (igual), especificidad 0,85 (lineal 0,81), 297 vectores de soporte
#    de 600 (lineal 312). RBF gana un poco porque el efecto trabajo x nota es
#    una interacción no lineal; con 26 desertores en prueba la diferencia es
#    pequeña (empate práctico), pero la VC también favorece a RBF. ~50 % de
#    vectores de soporte indica mucho traslape entre clases.
# e. Sin escalar, RBF cae a 0,55 de exactitud balanceada (sensibilidad 0,27):
#    puntaje (cientos) domina la distancia del kernel y las demás variables
#    casi no cuentan. Sin distancia: 0,74 en prueba y 0,82 en VC (mejor que
#    con ella): quitar la variable de ruido no empeora y simplifica.
#    Recomendación para Bienestar: SVM RBF con pesos por clase, variables
#    escaladas y sin distancia, priorizando la sensibilidad (se podría bajar
#    el umbral para detectar más), porque perder a un desertor cuesta mucho
#    más que ofrecer una tutoría de más.
