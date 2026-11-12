# =============================================================================
# Minería de Datos — Clase 9: Tablas, gráficos y distribuciones de frecuencia
# Ejercicios de práctica: pedidos de una tienda en línea colombiana
# Autor: David Márquez
# =============================================================================
#install.packages(c("tidyverse", "knitr", "highcharter"))
library(tidyverse)   # incluye lubridate (floor_date, month) desde tidyverse 2.0
library(lubridate)
library(knitr)

# -----------------------------------------------------------------------------
# Datos (código del slide)
# -----------------------------------------------------------------------------
set.seed(909); n <- 1500
dias <- seq(as.Date("2025-01-01"), as.Date("2025-12-31"), "day")
pedidos <- tibble(
  fecha        = sample(dias, n, replace = TRUE),
  canal        = sample(c("App", "Web", "Tienda"), n, TRUE,
                        prob = c(.45, .35, .20)),
  categoria    = sample(c("Tecnología", "Hogar", "Moda"),
                        n, replace = TRUE),
  valor        = round(rlnorm(n, 11.5 + 0.6 *
                   (categoria == "Tecnología"), 0.6), -2),
  dias_entrega = rpois(n, lambda = 3) + 1,
  calificacion = sample(1:5, n, TRUE, prob = c(1, 2, 3, 7, 7))
)

miles <- scales::label_number(big.mark = ".", decimal.mark = ",")

# Paleta cualitativa con nombres (Okabe-Ito, segura para daltonismo) -> Ej. 4
colores_canal <- c(App = "#0072B2", Web = "#E69F00", Tienda = "#009E73")

# =============================================================================
# EJERCICIO 1: tablas de frecuencia
# =============================================================================
frec_calif <- pedidos |>
  count(calificacion) |>
  mutate(pct = 100 * n / sum(n), acum = cumsum(pct))
frec_calif

# % con calificación de 4 o más
pct_4_mas <- 100 * mean(pedidos$calificacion >= 4)
cat(sprintf("Pedidos con calificación >= 4: %.1f%%\n", pct_4_mas))

# Valor por rangos (cortes del slide, desiguales)
pedidos |>
  mutate(rango = cut(valor, c(0, 1e5, 2e5, 4e5, Inf), right = FALSE)) |>
  count(rango) |>
  mutate(pct = round(100 * n / sum(n), 1))

# Cortes de igual ancho (8 intervalos entre el mínimo y el máximo)
cortes_iguales <- seq(min(pedidos$valor), max(pedidos$valor), length.out = 9)
frec_igual <- pedidos |>
  mutate(rango = cut(valor, cortes_iguales, include.lowest = TRUE,
                     dig.lab = 8)) |>
  count(rango, .drop = FALSE) |>
  mutate(pct = round(100 * n / sum(n), 1))
frec_igual
summary(pedidos$valor)

# =============================================================================
# EJERCICIO 2: elige el gráfico según la pregunta
# =============================================================================
ventas_mes <- pedidos |>
  mutate(mes = floor_date(fecha, "month")) |>
  group_by(mes, canal) |>
  summarise(ventas = sum(valor), .groups = "drop")

# 2.1 ¿Qué canal genera más pedidos? -> barras ordenadas (categórica, conteo)
pedidos |>
  count(canal) |>
  ggplot(aes(x = reorder(canal, n), y = n, fill = canal)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = n), hjust = -0.2) +
  scale_fill_manual(values = colores_canal) +
  coord_flip() +
  labs(title = "Pedidos por canal", x = NULL, y = "Pedidos") +
  theme_minimal()

# 2.2 ¿Cómo se distribuyen los días de entrega? -> barras (discreta, conteo)
ggplot(pedidos, aes(x = factor(dias_entrega))) +
  geom_bar(fill = "#006DAE") +
  labs(title = "Distribución de los días de entrega",
       x = "Días de entrega", y = "Pedidos") +
  theme_minimal()

# 2.3 ¿El valor cambia según la categoría? -> boxplot (numérica vs. categórica)
ggplot(pedidos, aes(x = categoria, y = valor / 1000, fill = categoria)) +
  geom_boxplot(show.legend = FALSE) +
  scale_y_log10(labels = miles) +
  labs(title = "Valor del pedido por categoría",
       x = NULL, y = "Valor (miles COP, escala log)") +
  theme_minimal()

# 2.4 ¿Cómo evolucionaron las ventas mensuales por canal? -> líneas (tiempo)
ggplot(ventas_mes, aes(x = mes, y = ventas / 1e6, colour = canal)) +
  geom_line(linewidth = 1) + geom_point() +
  scale_colour_manual(values = colores_canal) +
  scale_x_date(date_labels = "%b", date_breaks = "1 month") +
  labs(title = "Ventas mensuales por canal, 2025",
       x = NULL, y = "Ventas (millones COP)", colour = "Canal") +
  theme_minimal()

# =============================================================================
# EJERCICIO 3: la forma del valor del pedido
# =============================================================================
hist_valor <- function(bins) {
  ggplot(pedidos, aes(x = valor / 1000)) +
    geom_histogram(bins = bins, fill = "#006DAE", color = "white") +
    geom_vline(xintercept = median(pedidos$valor) / 1000) +
    labs(title = paste("Valor del pedido —", bins, "bins"),
         x = "Valor del pedido (miles COP)", y = "Pedidos") +
    theme_minimal()
}
hist_valor(30)
hist_valor(8)
hist_valor(120)
hist_valor(30) + scale_x_log10(labels = miles) +
  labs(title = "Valor del pedido — escala logarítmica")

c(media = mean(pedidos$valor), mediana = median(pedidos$valor),
  asimetria = {x <- pedidos$valor; mean((x - mean(x))^3) / sd(x)^3})

# Por categoría
pedidos |>
  group_by(categoria) |>
  summarise(n = n(), media = mean(valor), mediana = median(valor))

ggplot(pedidos, aes(x = valor / 1000, fill = categoria)) +
  geom_histogram(bins = 30, color = "white", show.legend = FALSE) +
  scale_x_log10(labels = miles) +
  facet_wrap(~ categoria, ncol = 1) +
  labs(title = "Valor del pedido por categoría (escala log)",
       x = "Valor (miles COP)", y = "Pedidos") +
  theme_minimal()

# =============================================================================
# EJERCICIO 4: color con propósito
# =============================================================================
desvio_mes <- pedidos |>
  count(mes = month(fecha)) |>
  mutate(desvio = n - mean(n))
desvio_mes
ggplot(desvio_mes, aes(factor(mes), desvio, fill = desvio)) +
  geom_col() +
  geom_hline(yintercept = 0) +
  scale_fill_gradient2(low = "#b2182b", mid = "grey90",
                       high = "#2166ac", midpoint = 0) +
  labs(title = "Pedidos por mes: desviación frente al promedio mensual",
       x = "Mes", y = "Pedidos - promedio", fill = "Desvío") +
  theme_minimal()

# colores_canal (definido arriba) usado en dos gráficos distintos:
# gráfico 1: pedidos por canal (Ej. 2.1); gráfico 2: ventas mensuales (Ej. 2.4).
# Otro uso: calificación promedio por canal
pedidos |>
  group_by(canal) |>
  summarise(calif = mean(calificacion)) |>
  ggplot(aes(canal, calif, fill = canal)) +
  geom_col(show.legend = FALSE) +
  scale_fill_manual(values = colores_canal) +
  labs(title = "Calificación promedio por canal", x = NULL, y = "Calificación") +
  theme_minimal()

# =============================================================================
# EJERCICIO 5: tabla de contingencia y su gráfico
# =============================================================================
tabla <- table(pedidos$canal, pedidos$categoria)
tabla
pct_fila <- round(100 * prop.table(tabla, margin = 1), 1)   # % por fila
pct_fila

ggplot(pedidos, aes(x = canal, fill = categoria)) +
  geom_bar(position = "fill") +
  scale_y_continuous(labels = scales::percent) +
  labs(y = "Proporción dentro del canal", x = NULL, fill = "Categoría") +
  theme_minimal()

# Gráfico que sí muestra el tamaño de cada canal: barras apiladas en conteos
# (o un mosaico, donde el ancho de cada barra es proporcional al canal)
ggplot(pedidos, aes(x = canal, fill = categoria)) +
  geom_bar() +
  labs(y = "Pedidos", x = NULL, fill = "Categoría",
       title = "Pedidos por canal y categoría (conteos)") +
  theme_minimal()
mosaicplot(tabla, main = "Mosaico canal x categoría", color = TRUE)

kable(as.data.frame.matrix(pct_fila),
      caption = "Porcentaje de pedidos por categoría dentro de cada canal")

# =============================================================================
# EJERCICIO 6: interactividad con criterio
# =============================================================================
conteo <- pedidos |> count(categoria, canal)

# Versión highcharter en español, con separador de miles
if (requireNamespace("highcharter", quietly = TRUE)) {
  library(highcharter)
  hcoptslang <- getOption("highcharter.lang")
  hcoptslang$thousandsSep <- "."
  hcoptslang$decimalPoint <- ","
  options(highcharter.lang = hcoptslang)

  conteo |>
    hchart("column", hcaes(x = categoria, y = n, group = canal)) |>
    hc_colors(unname(colores_canal[sort(unique(conteo$canal))])) |>
    hc_tooltip(shared = TRUE,
               headerFormat = "<b>{point.key}</b><br>",
               pointFormat = "{series.name}: {point.y:,.0f} pedidos<br>") |>
    hc_xAxis(title = list(text = "Categoría")) |>
    hc_yAxis(title = list(text = "Número de pedidos"),
             labels = list(format = "{value:,.0f}")) |>
    hc_legend(title = list(text = "Canal")) |>
    hc_title(text = "Pedidos por categoría y canal")
}

# Versión ggplot2
ggplot(conteo, aes(x = categoria, y = n, fill = canal)) +
  geom_col(position = "dodge") +
  geom_text(aes(label = n), position = position_dodge(0.9), vjust = -0.3,
            size = 3) +
  scale_fill_manual(values = colores_canal) +
  scale_y_continuous(labels = miles) +
  labs(title = "Pedidos por categoría y canal",
       x = "Categoría", y = "Número de pedidos", fill = "Canal") +
  theme_minimal()

# =============================================================================
# RESPUESTAS
# =============================================================================
# (Valores con set.seed(909).)
#
# EJERCICIO 1
# - Calificación >= 4: 69,7% de los pedidos (34,0% con 4 y 35,7% con 5).
# - La acumulada tiene sentido para calificacion porque es ORDINAL: "30,3%
#   tiene 3 o menos" significa algo. canal es NOMINAL (App, Web, Tienda no
#   tienen orden), así que acumular dependería de un orden arbitrario.
# - Con 8 cortes de igual ancho (17.000 a 1.271.100) el 71% de los pedidos cae
#   en el primer intervalo y los intervalos (800 mil a 957 mil) y (957 mil a
#   1,11 millones) quedan VACÍOS; el último solo tiene 2 pedidos. El valor
#   tiene cola larga a la derecha (lognormal): unos pocos pedidos muy caros
#   estiran el rango y la mayoría queda apretada al inicio. Por eso los
#   cortes desiguales del slide (0-100 mil, 100-200 mil, ...) informan mejor.
#
# EJERCICIO 2
# - ¿Qué canal genera más pedidos? Barras horizontales ordenadas: compara
#   conteos de una variable categórica. App (709) > Web (517) > Tienda (274).
# - Días de entrega: gráfico de barras, porque es una variable discreta
#   (conteo); un histograma partiría valores enteros. Moda en 3-4 días,
#   cola a la derecha hasta 13 días.
# - Valor según categoría: boxplot (numérica vs. categórica) en escala log;
#   Tecnología tiene valores claramente mayores que Hogar y Moda.
# - Evolución mensual por canal: gráfico de líneas, porque el eje x es el
#   tiempo. App siempre lidera (6-11 millones/mes), luego Web y Tienda; no
#   hay una tendencia clara, solo fluctuaciones.
#
# EJERCICIO 3
# - Forma: asimétrica a la derecha (asimetría ≈ 2,7), unimodal. Centro:
#   mediana 119.300. Cola: larga, hasta 1,27 millones. Sí, la media (151.927)
#   es mayor que la mediana: la cola la jala hacia arriba.
# - bins = 8 es demasiado grueso (todo en 2-3 barras, se pierde la forma);
#   bins = 120 es demasiado fino (ruido, barras vacías). 30 bins muestra
#   bien la forma: pico a la izquierda y cola larga.
# - Con scale_x_log10() la distribución se ve casi simétrica (el valor es
#   lognormal): la cola se comprime y se aprecia el centro. A gerencia le
#   reportaría la MEDIANA (≈ 119 mil), que no se infla con los pedidos caros.
# - Por categoría aparece lo que el global ocultaba: Tecnología está corrida
#   a la derecha (mediana 189.600 vs. ≈ 94-100 mil de Hogar y Moda). El
#   histograma global es una MEZCLA de dos niveles de precio, lo que también
#   alarga la cola.
#
# EJERCICIO 4
# - La paleta divergente conviene porque el dato tiene un punto de referencia
#   con significado: el promedio mensual (125 pedidos), que corresponde a
#   desvío = 0 (gris). Azul = meses por encima (marzo +15, septiembre +7);
#   rojo = por debajo (junio -13, febrero y julio -7). El color codifica
#   dirección e intensidad del desvío.
# - colores_canal se definió con nombres (App, Web, Tienda) y se usa en el
#   gráfico de pedidos por canal, en el de ventas mensuales y en el de
#   calificación: el mismo canal tiene siempre el mismo color.
# - Se usa la paleta Okabe-Ito (azul, naranja, verde azulado), diseñada para
#   daltonismo, así que no depende de distinguir rojo de verde; la divergente
#   rojo-azul también es segura. Verificar subiendo las imágenes a Coblis.
#
# EJERCICIO 5
# - Tecnología pesa más en App (34,3%), seguida de Web (31,1%) y Tienda
#   (28,1%). Sí coincide con las barras al 100%: el segmento de Tecnología es
#   el más alto en App. Las diferencias son pequeñas: las categorías se
#   asignaron al azar, así que no hay asociación real entre canal y categoría.
# - Las barras al 100% ocultan que App tiene 709 pedidos y Tienda solo 274.
#   Lo resuelven las barras apiladas en conteos o el gráfico de mosaico
#   (ancho proporcional al tamaño de cada canal).
# - Interpretación de la tabla: (1) En los tres canales la mezcla de
#   categorías es parecida, cerca de un tercio cada una. (2) La mayor
#   diferencia está en Tienda, donde Moda llega al 40,5% y Tecnología baja
#   al 28,1%; sin embargo, con solo 274 pedidos en Tienda puede ser variación
#   aleatoria.
#
# EJERCICIO 6
# - highcharter: tooltip compartido, ejes y leyenda en español, separador de
#   miles "." (opciones lang thousandsSep / decimalPoint).
# - ggplot2 gana: reproducible, se exporta a PDF/Word, control total del
#   diseño, se puede rotular cada valor. Pierde: no hay tooltip, zoom ni
#   ocultar series. highcharter gana interacción (tooltip, filtrar canales
#   desde la leyenda); pierde: necesita HTML/JavaScript, no sirve en PDF.
# - En un informe PDF para gerencia usaría ggplot2 (estático, con los valores
#   rotulados). En un dashboard usaría highcharter, porque el usuario explora
#   y la interacción aporta.
