# =============================================================================
# Minería de Datos - Clase 13: Regresión Lineal, Múltiple y Logística
# Taller: Ejercicios de práctica
# =============================================================================

# Paquetes (instalar una sola vez si no los tiene):
# install.packages(c("car", "pROC"))
library(car)    # VIF
library(pROC)   # Curva ROC / AUC (opcional, ejercicio 4)

# -----------------------------------------------------------------------------
# Datos del taller (tal como vienen en la clase)
# -----------------------------------------------------------------------------
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

str(ventas)
summary(ventas)


# =============================================================================
# Ejercicio 1: Regresión lineal simple  (ventas ~ publicidad)
# =============================================================================
mod1 <- lm(ventas ~ publicidad, data = ventas)
summary(mod1)

coef(mod1)
cat("R² modelo simple:", round(summary(mod1)$r.squared, 3), "\n")

# Gráfico de dispersión con la recta ajustada
plot(ventas$publicidad, ventas$ventas,
     pch = 19, col = "grey40",
     xlab = "Gasto en publicidad", ylab = "Ventas",
     main = "Ventas vs. publicidad")
abline(mod1, col = "#1b4d2e", lwd = 2)

# Interpretación (completar con sus resultados):
# - Coeficiente de publicidad: por cada unidad adicional de gasto en
#   publicidad, las ventas aumentan en promedio 18.66774 unidades.
# - R²: proporción de la variabilidad de las ventas explicada por publicidad 0.737.
#   Un R² moderado indica que publicidad explica parte, pero no toda, la
#   variación (el precio y el ruido también influyen).


# =============================================================================
# Ejercicio 2: Regresión lineal múltiple  (ventas ~ publicidad + precio)
# =============================================================================
mod2 <- lm(ventas ~ publicidad + precio, data = ventas)
summary(mod2)

# Comparación de R² ajustado
r2adj <- c(
  simple   = summary(mod1)$adj.r.squared,
  multiple = summary(mod2)$adj.r.squared
)
round(r2adj, 3)

# Multicolinealidad
round(vif(mod2), 2)

# ¿Qué variable aporta más? Comparar coeficientes estandarizados
mod2_std <- lm(scale(ventas) ~ scale(publicidad) + scale(precio), data = ventas)
round(coef(mod2_std), 3)

# Alternativa: prueba F de cada variable (ANOVA tipo II)
Anova(mod2, type = 2)

# Interpretación:
#Publicidad (18.63): casi no cambia frente al modelo simple. Eso cuadra con el VIF = 1: publicidad y precio no están correlacionados, así que agregar el precio no altera el efecto de la publicidad.
#Precio (−4.90, p ≈ 2e-06): por cada unidad que sube el precio, las ventas bajan en promedio 4.9 unidades, con la publicidad constante. Es significativo.
#R² ajustado: sube de 0.735 a 0.780. Incluir el precio mejora el modelo aun penalizando por tener un predictor más, y el error residual baja de 8.36 a 7.62.
#¿Cuál aporta más? La publicidad, con diferencia. Su coeficiente estandarizado es 0.857 frente a −0.215 del precio, y su F es 397 frente a 25. Una desviación estándar más de publicidad mueve las ventas unas 0.86 DE, mientras que el precio las mueve unas 0.21 DE.


# =============================================================================
# Ejercicio 3: Variable categórica (region como dummy)
# =============================================================================
ventas$region <- factor(ventas$region)
levels(ventas$region)   # la primera en orden alfabético ("Este") es la referencia

# Opcional: cambiar la categoría de referencia, por ejemplo a "Norte"
# ventas$region <- relevel(ventas$region, ref = "Norte")

mod3 <- lm(ventas ~ publicidad + precio + region, data = ventas)
summary(mod3)

# Ver las dummies que R construye (k - 1 = 3 columnas)
head(model.matrix(mod3))

# ¿Hay diferencia significativa entre regiones en conjunto?
# Prueba F parcial: modelo sin región vs. con región
anova(mod2, mod3)

# Interpretación:
#Codificación dummy: region tiene 4 niveles, así que R creó k − 1 = 3 dummies (regionNorte, regionOeste, regionSur). La categoría de referencia es Este, la primera en orden alfabético. En la model.matrix se ve: la fila 2 tiene las tres dummies en 0, así que esa observación es de Este.

#Coeficientes de región: cada uno es la diferencia promedio de ventas frente a Este, con la publicidad y el precio constantes.

#Norte (−1.49, p = 0.43): vende en promedio 1.5 unidades menos que Este. No es significativo.
#Oeste (−4.01, p = 0.056): vende unas 4 unidades menos que Este. Es marginal: no alcanza el 5 %, solo el 10 %.
#Sur (−1.82, p = 0.36): vende 1.8 unidades menos que Este. No es significativo.

#¿Hay diferencia significativa entre regiones? No. La prueba F parcial (anova(mod2, mod3)) evalúa las tres dummies a la vez y da F = 1.26, p = 0.29. No hay evidencia de que la región ayude a explicar las ventas una vez que se controla por publicidad y precio. Esta prueba conjunta es la que responde la pregunta. Los p-valores individuales solo comparan cada región contra Este.
#Comparación de ajuste: el R² sube un poco (0.784 → 0.791), pero el R² ajustado baja (0.780 → 0.781 es prácticamente igual frente a la penalización de 3 parámetros extra). Agregar la región no mejora el modelo de forma relevante. Los coeficientes de publicidad (18.6) y precio (−5.1) casi no cambian.
#Conclusión: conviene quedarse con el modelo del ejercicio 2, que es más sencillo. Este resultado tiene sentido: en la simulación la región se asignó al azar y no entra en la fórmula de las ventas. El −4 de Oeste es ruido muestral.

# =============================================================================
# Ejercicio 4: Regresión logística  (promo ~ publicidad + precio)
# =============================================================================
mod4 <- glm(promo ~ publicidad + precio, data = ventas, family = binomial)
summary(mod4)

# Odds ratios con intervalos de confianza al 95%
round(exp(cbind(OR = coef(mod4), confint(mod4))), 3)

# Efecto marginal del precio evaluado en la probabilidad media
p_media <- mean(predict(mod4, type = "response"))
efecto_marginal_precio <- coef(mod4)["precio"] * p_media * (1 - p_media)
round(efecto_marginal_precio, 4)

# Evaluación: curva ROC y AUC
prob_pred <- predict(mod4, type = "response")
roc_obj   <- roc(ventas$promo, prob_pred, quiet = TRUE)
plot(roc_obj, col = "#1b4d2e", lwd = 2,
     main = paste("Curva ROC | AUC =", round(auc(roc_obj), 3)))

# Matriz de confusión con umbral 0.5
pred_clase <- ifelse(prob_pred > 0.5, 1, 0)
table(Observado = ventas$promo, Predicho = pred_clase)

# - Precio: OR = 0.677 (IC 95%: 0.40 - 1.12; p = 0.135). Por cada unidad que sube
#   el precio, los odds de aplicar una promoción se multiplican por 0.68
#   (reducción de ~32%). PERO el IC incluye el 1: el efecto NO es
#   significativo. No hay evidencia de que el precio influya en la
#   probabilidad de promoción.
# - Publicidad: OR = 1.057 (IC 95%: 0.65 - 1.72; p = 0.82). Efecto
#   prácticamente nulo y no significativo.
# - Intercepto (OR = 215.9): sin interpretación útil (precio = 0 y
#   publicidad = 0 están fuera del rango de los datos); por eso su IC es enorme.
# - Efecto marginal del precio = -0.0975: evaluado en la probabilidad media
#   (~0.5), una unidad más de precio bajaría la probabilidad de promoción en
#   ~9.8 puntos porcentuales. Como no es significativo, no es confiable.
# - Devianza: de 166.36 (nulo) a 164.03, una caída de solo 2.3 con 2 gl. El modelo
#   casi no mejora frente a no usar predictores.
# - Matriz de confusión (umbral 0.5):
#     Accuracy      = (35 + 34) / 120 = 57.5%
#     Sensibilidad  = 34 / 60 = 56.7%
#     Especificidad = 35 / 60 = 58.3%
#   Con clases balanceadas (60/60), el azar daría ~50%: el modelo apenas lo
#   supera. El AUC (ver título del gráfico ROC) indica discriminación pobre.
# - Conclusión: ni el precio ni la publicidad explican si se aplica una
#   promoción. Es lo esperado, porque en la simulación "promo" se generó al
#   azar. El 57.5% de accuracy se debe a ruido y a evaluar el modelo con los
#   mismos datos con que se ajustó.


# =============================================================================
# Ejercicio 5: Diagnóstico del modelo múltiple (mod2) y comunicación
# =============================================================================
par(mfrow = c(2, 2))
plot(mod2)          # 1) Residuos vs ajustados  2) Q-Q  3) Escala-localización  4) Residuos vs leverage (Cook)
par(mfrow = c(1, 1))

# Pruebas formales de apoyo
shapiro.test(residuals(mod2))   # Normalidad   (H0: residuos normales)
ncvTest(mod2)                   # Homocedasticidad (H0: varianza constante)
durbinWatsonTest(mod2)          # Independencia (H0: no autocorrelación)

# Observaciones influyentes (Distancia de Cook > 4/n)
cook <- cooks.distance(mod2)
which(cook > 4 / n)

