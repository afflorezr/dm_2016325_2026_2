# Clase 10: generación de los datos de arriendos
# El CSV que produce es la entrada del informe (R/Quarto) y de la app (Python)

library(tidyverse)

set.seed(1010); n <- 900
arriendos <- tibble(
  ciudad  = sample(c("Bogotá", "Medellín", "Cali"), n, TRUE,
                   prob = c(.5, .3, .2)),
  estrato = sample(1:6, n, TRUE,
                   prob = c(.08, .22, .32, .20, .11, .07)),
  area_m2 = round(rlnorm(n, log(45) + 0.12 * estrato, 0.35)),
  antiguedad = round(runif(n, 0, 40)),
  arriendo = round(exp(11.8 + 0.15 * estrato + 0.5 * log(area_m2)
             - 0.12 * (ciudad == "Cali") + rnorm(n, 0, 0.25)), -4))
err <- sample(n, 6)                      # errores de digitación
arriendos$arriendo[err] <- arriendos$arriendo[err] * 10
write_csv(arriendos, "arriendos.csv")
