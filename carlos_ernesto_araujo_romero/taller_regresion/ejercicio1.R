# 1. Generación de los datos
set.seed(42)
n <- 120
ventas <- data.frame(
  mes        = rep(1:12, times = 10),
  publicidad = round(runif(n, min = 2.0, max = 4.5), 1),
  precio     = round(runif(n, min = 13.0, max = 15.5), 1),
  region     = sample(c("Norte", "Sur", "Este", "Oeste"), n, replace = TRUE),
  promo      = sample(c(0L, 1L), n, replace = TRUE)
)
ventas$ventas <- round(
  100 + 18 * ventas$publicidad - 5 * ventas$precio +
    rnorm(n, mean = 0, sd = 8)
)

# 2. Ajuste del modelo de regresión lineal simple
modelo <- lm(ventas ~ publicidad, data = ventas)

# 3. Resumen del modelo
summary(modelo)
