# =============================================================================
# Minería de Datos — Clase 10: Medidas estadísticas y comunicación de resultados
# Taller 10: arriendos en Bogotá, Medellín y Cali
# Autor: David Márquez
# =============================================================================
# Ejercicio 1 completo en R (análisis del informe) + las reglas del Ejercicio 2
# aplicadas en R para responder sus preguntas (la app en sí va en app.py).
#install.packages(c("tidyverse", "kableExtra", "corrplot"))

library(tidyverse)
library(kableExtra)
library(corrplot)

# -----------------------------------------------------------------------------
# 0. Datos (código del slide)
# -----------------------------------------------------------------------------
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

datos <- read_csv("arriendos.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------------
# Funciones auxiliares
# -----------------------------------------------------------------------------
asimetria <- function(x) {               # coeficiente de asimetría (momentos)
  m <- mean(x); mean((x - m)^3) / mean((x - m)^2)^1.5
}
cv <- function(x) sd(x) / mean(x)
limites_iqr <- function(x) {
  q <- unname(quantile(x, c(.25, .75))); r <- q[2] - q[1]
  c(inf = q[1] - 1.5 * r, sup = q[2] + 1.5 * r)
}
es_atipico <- function(x) { l <- limites_iqr(x); x < l["inf"] | x > l["sup"] }
pesos <- function(x) formatC(round(x), format = "d", big.mark = ".", decimal.mark = ",")

# =============================================================================
# EJERCICIO 1
# =============================================================================

# -----------------------------------------------------------------------------
# P1. ¿Cuánto cuesta un arriendo típico? (media, mediana, asimetría)
# -----------------------------------------------------------------------------
cat("Media:    ", pesos(mean(datos$arriendo)), "\n")
cat("Mediana:  ", pesos(median(datos$arriendo)), "\n")
cat("Asimetría:", round(asimetria(datos$arriendo), 2), "\n")

ggplot(datos, aes(arriendo)) +
  geom_density(fill = "grey85") +
  geom_vline(aes(xintercept = mean(arriendo),   colour = "Media"),   linewidth = 1) +
  geom_vline(aes(xintercept = median(arriendo), colour = "Mediana"), linewidth = 1) +
  scale_x_log10(labels = scales::label_dollar(prefix = "$", big.mark = ".")) +
  scale_colour_manual(values = c(Media = "firebrick", Mediana = "steelblue")) +
  labs(title = "Distribución del arriendo (escala log)", x = "Arriendo (COP)",
       y = "Densidad", colour = NULL) +
  theme_minimal()

# -----------------------------------------------------------------------------
# P2. ¿En qué ciudad los precios son más dispersos? (DE, CV, IQR)
# -----------------------------------------------------------------------------
tabla_ciudad <- function(d) {
  d |>
    group_by(ciudad) |>
    summarise(n = n(), media = mean(arriendo), mediana = median(arriendo),
              DE = sd(arriendo), CV = cv(arriendo), IQR = IQR(arriendo),
              IQR_mediana = IQR(arriendo) / median(arriendo), .groups = "drop")
}
por_ciudad <- tabla_ciudad(datos)
por_ciudad |>
  mutate(across(c(media, mediana, DE, IQR), pesos),
         across(c(CV, IQR_mediana), ~ scales::percent(.x, 0.1))) |>
  kbl(caption = "Arriendo por ciudad (con errores)") |>
  kable_styling(bootstrap_options = c("striped", "hover"))
print(por_ciudad)

# -----------------------------------------------------------------------------
# P3. ¿Qué registros son sospechosos? (regla del IQR)
# -----------------------------------------------------------------------------
lim <- limites_iqr(datos$arriendo)
cat("Límites IQR:", pesos(lim["inf"]), "a", pesos(lim["sup"]), "\n")

atipicos <- datos |>
  mutate(fila = row_number(),
         precio_m2 = arriendo / area_m2,
         # Un error de digitación (x10) deja un arriendo > 10 millones con un
         # precio por m2 imposible para su estrato/área
         diagnostico = if_else(arriendo > 1e7, "Error de digitación",
                               "Arriendo alto legítimo")) |>
  filter(es_atipico(datos$arriendo)) |>
  arrange(desc(arriendo))
cat("Atípicos por la regla del IQR:", nrow(atipicos), "\n")
print(count(atipicos, diagnostico))
atipicos |>
  mutate(across(c(arriendo, precio_m2), pesos)) |>
  kbl(caption = "Atípicos: ¿error o arriendo alto?") |>
  kable_styling(bootstrap_options = c("striped", "condensed"))

# Verificación: los detectados como error son exactamente los 6 introducidos
errores <- which(datos$arriendo > 1e7)
cat("Filas con error detectadas:", errores, "\n")
cat("¿Coinciden con los errores simulados?", setequal(errores, err), "\n")

# -----------------------------------------------------------------------------
# P4. ¿Qué variables se asocian con el arriendo? (Pearson, Spearman)
# -----------------------------------------------------------------------------
num <- datos |> select(arriendo, area_m2, estrato, antiguedad)
cor_p <- cor(num, method = "pearson")
cor_s <- cor(num, method = "spearman")
round(cor_p[, "arriendo"], 2)
round(cor_s[, "arriendo"], 2)
corrplot(cor_s, method = "color", type = "upper", addCoef.col = "black",
         tl.col = "black", title = "Correlograma de Spearman", mar = c(0, 0, 2, 0))

# -----------------------------------------------------------------------------
# ¿Qué cambia al depurar? (corrigiendo los 6 errores: dividir por 10)
# -----------------------------------------------------------------------------
limpios <- datos |> mutate(arriendo = if_else(arriendo > 1e7, arriendo / 10, arriendo))

resumen <- function(d) {
  cvs <- tabla_ciudad(d)$CV
  c(Media     = pesos(mean(d$arriendo)),
    Mediana   = pesos(median(d$arriendo)),
    Asimetría = format(round(asimetria(d$arriendo), 2), decimal.mark = ","),
    `CV por ciudad` = paste0(round(100 * min(cvs)), "% a ", round(100 * max(cvs)), "%"),
    `Pearson / Spearman con el área` =
      paste(format(round(cor(d$arriendo, d$area_m2), 2), decimal.mark = ","),
            format(round(cor(d$arriendo, d$area_m2, method = "spearman"), 2),
                   decimal.mark = ","), sep = " / "))
}
antes_despues <- tibble(
  Medida = names(resumen(datos)),
  `Con errores` = resumen(datos),
  `Sin los 6 errores` = resumen(limpios),
  `¿Cambió mucho?` = c("Sí (sensible)", "No (robusta)", "Sí, muchísimo",
                       "Sí, y desaparece la diferencia entre ciudades",
                       "Pearson sí; Spearman no")
)
antes_despues |> kbl(caption = "Antes y después de depurar") |>
  kable_styling(bootstrap_options = c("striped", "hover"))
print(antes_despues)

print(tabla_ciudad(limpios))                      # CV por ciudad sin errores
cat("Atípicos IQR sin errores:", sum(es_atipico(limpios$arriendo)), "\n")

# =============================================================================
# EJERCICIO 2 — reglas de la app aplicadas en R (para responder sus preguntas)
# =============================================================================
reglas_app <- function(d, ciudades = unique(d$ciudad), estratos = 1:6,
                       umbral_asim = 0.5) {
  g <- d |> filter(ciudad %in% ciudades, estrato %in% estratos)
  x <- g$arriendo; a <- asimetria(x)
  usar_mediana <- abs(a) > umbral_asim
  at <- es_atipico(x)
  list(
    n = nrow(g),
    asimetria = round(a, 2),
    centro = if (usar_mediana)
      sprintf("Mediana %s (IQR %s): |asimetría| > %.1f", pesos(median(x)),
              pesos(IQR(x)), umbral_asim)
      else sprintf("Media %s (DE %s): distribución aprox. simétrica",
                   pesos(mean(x)), pesos(sd(x))),
    CV = scales::percent(cv(x), 0.1),
    heterogeneo = cv(x) > 0.30,
    atipicos = sum(at),
    errores_entre_atipicos = sum(at & x > 1e7)
  )
}

# 1. Solo Bogotá, estratos 1 a 3
str(reglas_app(datos, "Bogotá", 1:3))
# 2. Solo estrato 6
str(reglas_app(datos, estratos = 6))
# 3. Sin filtros (comparar con el informe)
str(reglas_app(datos))
# 4. Sin los errores
str(reglas_app(limpios))

# =============================================================================
# RESPUESTAS
# ======================================================================
#
# EJERCICIO 1
# P1. Media 1.978.789 vs. mediana 1.740.000; asimetría ≈ 10,1. Con un sesgo
#     tan fuerte la media está inflada: el arriendo típico se reporta con la
#     MEDIANA (1.740.000). Sin los 6 errores la asimetría baja a ≈ 1,26: los
#     errores explican casi todo el sesgo, pero los precios siguen sesgados a
#     la derecha, así que la mediana sigue siendo la elección correcta.
#
# P2. Con errores el CV va de 75% (Bogotá) a 95% (Medellín) y parecería que
#     Medellín y Cali son mucho más dispersas. Pero con medidas robustas
#     (IQR/mediana: 55% a 60%) o con el CV sin errores (41% a 42%) las tres
#     ciudades son casi iguales. La "diferencia" era un artefacto de los
#     errores. Ninguna ciudad es claramente más dispersa (Cali tiene el
#     IQR/mediana un poco mayor, 60%).
#
# P3. La regla del IQR (límites -175.000 a 3.785.000) marca 26 atípicos, pero
#     solo 6 son errores de digitación (arriendos > 10 millones en estratos 2
#     a 5, filas 201, 486, 563, 617, 624 y 652). Los otros 20 son arriendos
#     altos legítimos (estratos altos, áreas grandes). Atípico ≠ error.
#
# P4. Arriendo vs. área: Pearson 0,29 y Spearman 0,61 con errores; sin
#     errores, Pearson 0,63 y Spearman 0,62. La brecha entre ambos era la
#     huella de los errores. Estrato: Spearman 0,62 (es ordinal: se usa
#     Spearman). Antigüedad: correlación ≈ 0 (no se asocia).
#
# Tabla antes / después:
#   Medida            Con errores   Sin errores   ¿Cambió?
#   Media             1.978.789     1.865.889     Sí
#   Mediana           1.740.000     1.740.000     No
#   Asimetría         10,12         1,26          Muchísimo
#   CV por ciudad     75% a 95%     41% a 42%     Sí; desaparece la diferencia
#   Pearson / Spear.  0,29 / 0,61   0,63 / 0,62   Pearson sí, Spearman no
#
# Pregunta de cierre: son robustas las medidas basadas en el ORDEN (mediana,
# IQR, cuantiles, Spearman): seis valores extremos entre 900 no mueven las
# posiciones centrales ni los rangos. No son robustas las basadas en MOMENTOS
# (media, DE, CV, asimetría, Pearson): usan la magnitud de cada valor, y la
# DE eleva al cuadrado y la asimetría al cubo las desviaciones, así que unos
# pocos extremos las dominan.
#
# EJERCICIO 2 (reglas de la app aplicadas con reglas_app())
# 1. Bogotá, estratos 1 a 3 (289 registros): 10 atípicos y solo 1 es error de
#    digitación. La regla depende del grupo: un arriendo normal de estrato 5
#    puede ser atípico dentro de estratos 1 a 3.
# 2. Estrato 6 (58 registros): asimetría ≈ 0,92 > 0,5, así que la app sigue
#    reportando la mediana (3.045.000). CV ≈ 30,4%: justo en el límite, la
#    app advierte que el grupo es heterogéneo.
# 3. Sí: sin filtros la app y el informe dan la misma mediana, 1.740.000.
# 4. Sin errores cambian la media, el CV (84,7% -> 41,7%), la asimetría
#    (10,1 -> 1,26) y el número de atípicos (26 -> 22). La mediana no cambia.
#

