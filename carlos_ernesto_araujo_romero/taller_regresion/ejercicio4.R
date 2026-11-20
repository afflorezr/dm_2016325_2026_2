modelo_logit <- glm(promo ~ publicidad + precio, data = ventas, family = binomial)

summary(modelo_logit)

odds_ratios <- exp(coef(modelo_logit))
ic_or <- exp(confint(modelo_logit))

cbind(OR = odds_ratios, ic_or)
