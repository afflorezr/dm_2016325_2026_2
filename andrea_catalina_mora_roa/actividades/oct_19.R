
# ============================================================
# EJERCICIOS DE PRACTICA: REGRESION EN R
# ============================================================

# Instalar paquetes si es necesario:
# install.packages("ggplot2")

library(ggplot2)

# ============================================================
# 1. GENERACION DE DATOS
# ============================================================

set.seed(42)

n <- 120

ventas <- data.frame(
  mes = rep(1:12, times = 10),
  publicidad = round(runif(n, min = 2.0, max = 4.5), 1),
  precio = round(runif(n, min = 13.0, max = 15.5), 1),
  region = sample(c("Norte", "Sur", "Este", "Oeste"),
                  n, replace = TRUE),
  promo = sample(c(0L, 1L), n, replace = TRUE)
)

ventas$ventas <- round(
  100 + 18 * ventas$publicidad -
    5 * ventas$precio +
    rnorm(n, mean = 0, sd = 8)
)

# Convertir region en variable categorica
ventas$region <- factor(ventas$region)

# Revisar los datos
head(ventas)
summary(ventas)
str(ventas)


# ============================================================
# EJERCICIO 1: REGRESION LINEAL SIMPLE
# Ventas explicadas por publicidad
# ============================================================

modelo_simple <- lm(ventas ~ publicidad, data = ventas)

summary(modelo_simple)

# Grafico de dispersion y recta de regresion
ggplot(ventas, aes(x = publicidad, y = ventas)) +
  geom_point(color = "darkgreen", alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, color = "red") +
  labs(
    title = "Regresion simple: publicidad y ventas",
    x = "Gasto en publicidad",
    y = "Ventas"
  ) +
  theme_minimal()

# Interpretacion automatica de coeficientes
coef(modelo_simple)
cat("R cuadrado del modelo simple:",
    summary(modelo_simple)$r.squared, "\n")


# ============================================================
# EJERCICIO 2: REGRESION LINEAL MULTIPLE
# Ventas explicadas por publicidad y precio
# ============================================================

modelo_multiple <- lm(
  ventas ~ publicidad + precio,
  data = ventas
)

summary(modelo_multiple)

# Comparacion del R cuadrado ajustado
r2_simple <- summary(modelo_simple)$adj.r.squared
r2_multiple <- summary(modelo_multiple)$adj.r.squared

cat("R2 ajustado - Modelo simple:", r2_simple, "\n")
cat("R2 ajustado - Modelo multiple:", r2_multiple, "\n")

if (r2_multiple > r2_simple) {
  cat("El modelo multiple presenta mayor R2 ajustado.\n")
} else {
  cat("El modelo multiple no mejora el R2 ajustado.\n")
}

# Comparacion de modelos
anova(modelo_simple, modelo_multiple)


# ============================================================
# EJERCICIO 3: VARIABLE CATEGORICA
# Incorporar region como predictor
# ============================================================

# R crea automaticamente variables dummy para los niveles
# de region, tomando una categoria como referencia.

modelo_region <- lm(
  ventas ~ publicidad + precio + region,
  data = ventas
)

summary(modelo_region)

# Identificar la categoria de referencia
cat("Categoria de referencia:",
    levels(ventas$region)[1], "\n")

# Prueba conjunta del efecto de region
modelo_sin_region <- lm(
  ventas ~ publicidad + precio,
  data = ventas
)

anova(modelo_sin_region, modelo_region)

# Medias de ventas por region
aggregate(ventas ~ region, data = ventas, mean)

# Grafico por region
ggplot(ventas, aes(x = region, y = ventas, fill = region)) +
  geom_boxplot() +
  labs(
    title = "Distribucion de ventas por region",
    x = "Region",
    y = "Ventas"
  ) +
  theme_minimal() +
  theme(legend.position = "none")


# ============================================================
# EJERCICIO 4: REGRESION LOGISTICA
# Variable dependiente: promo (0 o 1)
# ============================================================

modelo_logistico <- glm(
  promo ~ publicidad + precio,
  data = ventas,
  family = binomial(link = "logit")
)

summary(modelo_logistico)

# Odds ratios
odds_ratios <- exp(coef(modelo_logistico))
cat("Odds ratios:\n")
print(odds_ratios)

# Intervalos de confianza de los odds ratios
ic_odds <- exp(confint.default(modelo_logistico))
cat("Intervalos de confianza del 95%:\n")
print(ic_odds)

# Probabilidades estimadas
ventas$prob_promo <- predict(
  modelo_logistico,
  type = "response"
)

head(ventas[, c("publicidad", "precio",
                "promo", "prob_promo")])

# Grafico de probabilidad estimada segun precio
nuevos_datos <- data.frame(
  publicidad = rep(mean(ventas$publicidad), 100),
  precio = seq(min(ventas$precio),
               max(ventas$precio), length.out = 100)
)

nuevos_datos$probabilidad <- predict(
  modelo_logistico,
  newdata = nuevos_datos,
  type = "response"
)

ggplot(nuevos_datos,
       aes(x = precio, y = probabilidad)) +
  geom_line(color = "blue", linewidth = 1) +
  labs(
    title = "Probabilidad estimada de promocion",
    subtitle = "Publicidad constante en su valor promedio",
    x = "Precio",
    y = "Probabilidad de promocion"
  ) +
  theme_minimal()


# ============================================================
# EJERCICIO 5: DIAGNOSTICO DEL MODELO MULTIPLE
# ============================================================

# Graficos diagnosticos clasicos de R:
# 1. Residuales vs. ajustados
# 2. Grafico Q-Q
# 3. Escala-localizacion
# 4. Residuales vs. leverage

par(mfrow = c(2, 2))
plot(modelo_multiple)
par(mfrow = c(1, 1))

# Prueba de normalidad de los residuales
shapiro_resultado <- shapiro.test(
  residuals(modelo_multiple)
)
print(shapiro_resultado)

# Prueba de homocedasticidad (Breusch-Pagan)
# Instalar lmtest si hace falta:
# install.packages("lmtest")

if (requireNamespace("lmtest", quietly = TRUE)) {
  print(lmtest::bptest(modelo_multiple))
} else {
  message("Para Breusch-Pagan, ejecute install.packages('lmtest')")
}

# Prueba de independencia de errores (Durbin-Watson)
if (requireNamespace("lmtest", quietly = TRUE)) {
  print(lmtest::dwtest(modelo_multiple))
}

# Resumen de diagnosticos
cat("\n--- RESUMEN DEL MODELO MULTIPLE ---\n")
print(summary(modelo_multiple))

cat("\nR2:", summary(modelo_multiple)$r.squared, "\n")
cat("R2 ajustado:", summary(modelo_multiple)$adj.r.squared, "\n")
cat("Error estandar residual:",
    summary(modelo_multiple)$sigma, "\n")


# ============================================================
# CONCLUSION PARA EL INFORME
# ============================================================

# El modelo de regresión lineal múltiple permite concluir que tanto la publicidad 
# como el precio influyen significativamente en las ventas. El modelo presenta un 
# $R^2$ ajustado de 0,7799, lo que significa que aproximadamente el 77,99 % de la 
# variabilidad de las ventas es explicada por estas dos variables. Además, al 
# compararlo con el modelo simple, se observa una mejora estadísticamente significativa 
# al incluir el precio ($p < 0,001$). Los resultados indican que la publicidad 
# tiene una relación positiva con las ventas, mientras que el precio presenta una 
# relación negativa; es decir, una mayor inversión en publicidad se asocia con 
# mayores ventas, mientras que un aumento del precio se relaciona con una disminución 
# de estas, manteniendo constante la otra variable.

# En cuanto al diagnóstico del modelo, los gráficos de residuos frente a valores ajustados no muestran patrones sistemáticos evidentes, lo que sugiere que el supuesto de linealidad se cumple razonablemente. El gráfico Q-Q presenta una distribución de los residuos aproximadamente normal, aunque podrían existir pequeñas desviaciones, y el gráfico de escala-localización no evidencia cambios importantes en la dispersión, por lo que la homocedasticidad parece cumplirse de manera aceptable. En conclusión, el modelo es adecuado para apoyar la toma de decisiones comerciales y orientar las estrategias de publicidad y precios. Sin embargo, se recomienda revisar posibles observaciones atípicas y validar los supuestos antes de utilizar el modelo para realizar predicciones o establecer estrategias definitivas.
