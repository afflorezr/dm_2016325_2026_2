modelo_multiple <- lm(ventas ~ publicidad + precio, data = ventas)

par(mfrow = c(1, 3))

plot(modelo_multiple, which = 1)
plot(modelo_multiple, which = 2)
plot(modelo_multiple, which = 3)

par(mfrow = c(1, 1))

shapiro.test(residuals(modelo_multiple))