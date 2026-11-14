ventas$region <- as.factor(ventas$region)

modelo_region <- lm(ventas ~ publicidad + precio + region, data = ventas)

summary(modelo_region)

anova(modelo_region)
