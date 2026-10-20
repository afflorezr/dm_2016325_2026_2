# =============================================================================
# Minería de Datos — Clase 9: Tablas, Gráficos y Distribuciones de Frecuencia
# Ejercicios de práctica (Parte 7) — dataset: pedidos en línea
# =============================================================================

# ---- Paquetes ---------------------------------------------------------------
paquetes <- c("tidyverse", "knitr", "highcharter", "colorspace", "scales")
faltantes <- paquetes[!paquetes %in% rownames(installed.packages())]
if (length(faltantes) > 0) install.packages(faltantes)

library(tidyverse)   # dplyr, ggplot2, tidyr, lubridate (floor_date, month)...
library(knitr)       # kable()
library(scales)      # formatos de ejes con separador de miles

# ---- Dataset (copiado del enunciado) ----------------------------------------
set.seed(909); n <- 1500
dias <- seq(as.Date("2025-01-01"), as.Date("2025-12-31"), "day")
pedidos <- tibble(
  fecha     = sample(dias, n, replace = TRUE),
  canal     = sample(c("App", "Web", "Tienda"), n, TRUE,
                     prob = c(.45, .35, .20)),
  categoria = sample(c("Tecnología", "Hogar", "Moda"),
                     n, replace = TRUE),
  valor     = round(rlnorm(n, 11.5 + 0.6 *
                             (categoria == "Tecnología"), 0.6), -2),
  dias_entrega = rpois(n, lambda = 3) + 1,
  calificacion = sample(1:5, n, TRUE, prob = c(1, 2, 3, 7, 7))
)
glimpse(pedidos)

# Formato colombiano: punto de miles, coma decimal
miles <- label_number(big.mark = ".", decimal.mark = ",")
pesos <- label_number(prefix = "$", big.mark = ".", decimal.mark = ",")

# Paleta fija por canal (se define aquí y se reutiliza en todo el taller; ver Ej. 4)
# Colores Okabe-Ito: distinguibles con daltonismo
colores_canal <- c(App = "#0072B2", Web = "#E69F00", Tienda = "#009E73")
colores_cat   <- c(Tecnología = "#CC79A7", Hogar = "#56B4E9", Moda = "#D55E00")


# =============================================================================
# EJERCICIO 1: Tablas de frecuencia
# =============================================================================

# Distribución de frecuencias de la calificación
frec_calif <- pedidos |>
  count(calificacion) |>
  mutate(pct = 100 * n / sum(n), acum = cumsum(pct))
frec_calif

# Distribución de frecuencias del valor (cortes del enunciado, ancho desigual)
frec_valor <- pedidos |>
  mutate(rango = cut(valor, c(0, 1e5, 2e5, 4e5, Inf), right = FALSE)) |>
  count(rango) |>
  mutate(pct = 100 * n / sum(n), acum = cumsum(pct))
frec_valor

# 1.1 ¿Qué porcentaje de pedidos tiene calificación de 4 o más?
pct_4_o_mas <- pedidos |> summarise(pct = 100 * mean(calificacion >= 4)) |> pull(pct)
pct_4_o_mas
# Equivale a 100 - acumulada hasta 3:
100 - frec_calif$acum[frec_calif$calificacion == 3]
# RESPUESTA: aprox. 70% (las probabilidades del muestreo dan 14/20 = 70%; la
# cifra exacta sale arriba).

# 1.2 ¿Por qué la acumulada tiene sentido para calificacion y no para canal?
pedidos |> count(canal) |> mutate(pct = 100 * n / sum(n))
# RESPUESTA: la calificación es una variable ORDINAL (1 < 2 < ... < 5), así que
# "acumular" responde una pregunta real: ¿qué % calificó 3 o menos?
# El canal es NOMINAL: App, Web y Tienda no tienen orden, y la acumulada
# dependería de un orden arbitrario (alfabético, por ejemplo), así que
# "App o menos" no significa nada.

# 1.3 Cortes de igual ancho
rango_valor <- range(pedidos$valor)
rango_valor

frec_igual <- pedidos |>
  mutate(rango = cut(valor, breaks = 6, dig.lab = 7)) |>   # 6 intervalos de igual ancho
  count(rango, .drop = FALSE) |>
  mutate(pct = round(100 * n / sum(n), 1))
frec_igual

# Mismo resultado con cortes explícitos de igual ancho (más legibles)
ancho <- 250000
pedidos |>
  mutate(rango = cut(valor, breaks = seq(0, ceiling(max(valor) / ancho) * ancho, ancho),
                     right = FALSE, dig.lab = 8)) |>
  count(rango, .drop = FALSE) |>
  mutate(pct = round(100 * n / sum(n), 1))

# RESPUESTA: los intervalos ALTOS (los de la derecha) quedan casi vacíos. El
# valor tiene distribución log-normal, asimétrica a la derecha: la mayoría de
# pedidos está entre ~50 y 300 mil pesos y unos pocos pedidos muy grandes
# (sobre todo de Tecnología) estiran el máximo. Como los cortes de igual ancho
# se reparten entre el mínimo y ese máximo extremo, casi todos los pedidos
# caen en los primeros 1-2 intervalos y los últimos solo tienen unos pocos
# casos. Por eso, en variables sesgadas conviene usar cortes de ancho
# desigual (como los del enunciado), cuantiles o una escala logarítmica.


# =============================================================================
# EJERCICIO 2: Elige el gráfico según la pregunta
# =============================================================================
ventas_mes <- pedidos |>
  mutate(mes = floor_date(fecha, "month")) |>
  group_by(mes, canal) |>
  summarise(ventas = sum(valor), .groups = "drop")

# 2.1 ¿Qué canal genera más pedidos?  ->  1 variable categórica: BARRAS ordenadas
pedidos |>
  count(canal) |>
  mutate(canal = fct_reorder(canal, n, .desc = TRUE)) |>
  ggplot(aes(canal, n, fill = canal)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = miles(n)), vjust = -0.4) +
  scale_fill_manual(values = colores_canal) +
  labs(title = "App concentra la mayor cantidad de pedidos",
       x = "Canal", y = "Número de pedidos") +
  theme_minimal()
# Justificación: es una variable categórica y la pregunta es comparar
# cantidades; las barras ordenadas con base común se comparan mejor que una torta.

# 2.2 ¿Cómo se distribuyen los días de entrega?  ->  1 numérica DISCRETA: barras
pedidos |>
  count(dias_entrega) |>
  ggplot(aes(factor(dias_entrega), n)) +
  geom_col(fill = "#006DAE") +
  geom_text(aes(label = n), vjust = -0.4, size = 3) +
  labs(title = "La mayoría de pedidos se entrega entre 3 y 5 días",
       x = "Días de entrega", y = "Número de pedidos") +
  theme_minimal()
# Justificación: es numérica pero entera con pocos valores (conteo de días);
# un gráfico de barras por valor (equivalente a un histograma con bins de
# ancho 1) muestra la forma sin depender de la elección de bins.

# 2.3 ¿El valor del pedido cambia según la categoría?  ->  categórica + numérica: BOXPLOT
ggplot(pedidos, aes(fct_reorder(categoria, valor, median), valor, fill = categoria)) +
  geom_boxplot(show.legend = FALSE, outlier.alpha = 0.4) +
  scale_y_log10(labels = pesos) +
  scale_fill_manual(values = colores_cat) +
  labs(title = "Los pedidos de Tecnología tienen un valor típico mayor",
       x = "Categoría", y = "Valor del pedido (COP, escala log)") +
  theme_minimal()
# Justificación: el boxplot por grupo compara medianas, dispersión y atípicos
# entre categorías; la escala log evita que la cola derecha aplaste las cajas.

# 2.4 ¿Cómo evolucionaron las ventas mensuales por canal?  ->  tiempo: LÍNEAS
ggplot(ventas_mes, aes(mes, ventas / 1e6, color = canal)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_color_manual(values = colores_canal) +
  scale_x_date(date_labels = "%b", date_breaks = "1 month") +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  labs(title = "Ventas mensuales por canal, 2025",
       x = "Mes", y = "Ventas (millones COP)", color = "Canal") +
  theme_minimal()
# Justificación: la variable está ordenada en el tiempo; las líneas muestran
# tendencia y estacionalidad y permiten comparar los canales mes a mes.


# =============================================================================
# EJERCICIO 3: La forma del valor del pedido
# =============================================================================
hist_valor <- function(bins, log = FALSE) {
  p <- ggplot(pedidos, aes(x = valor / 1000)) +
    geom_histogram(bins = bins, fill = "#006DAE", color = "white") +
    geom_vline(xintercept = median(pedidos$valor) / 1000, linewidth = 0.8) +
    geom_vline(xintercept = mean(pedidos$valor) / 1000,
               linewidth = 0.8, linetype = "dashed", color = "firebrick") +
    labs(title = paste0("Valor del pedido — bins = ", bins, if (log) " (escala log)"),
         subtitle = "Línea continua: mediana · Línea roja punteada: media",
         x = "Valor del pedido (miles COP)", y = "Pedidos") +
    theme_minimal()
  if (log) p <- p + scale_x_log10(labels = miles)
  p
}

print(hist_valor(30))
print(hist_valor(8))
print(hist_valor(120))
print(hist_valor(30, log = TRUE))

# Resumen numérico para apoyar la descripción
pedidos |>
  summarise(minimo = min(valor), q1 = quantile(valor, .25), mediana = median(valor),
            media = mean(valor), q3 = quantile(valor, .75), maximo = max(valor)) |>
  mutate(across(everything(), pesos))

# Regla de partida de la clase: bins ≈ sqrt(n)
sqrt(nrow(pedidos))

# 3.1 RESPUESTA (forma, centro y cola):
# - Forma: unimodal y ASIMÉTRICA A LA DERECHA (sesgo positivo).
# - Centro: la mayoría de pedidos se concentra entre ~60 y ~250 mil pesos;
#   la mediana está alrededor de 120-130 mil (ver tabla).
# - Cola: larga hacia la derecha, con pocos pedidos muy grandes (> 500 mil).
# - Sí: la MEDIA es mayor que la MEDIANA, porque los valores extremos de la
#   cola derecha jalan el promedio hacia arriba.
#
# 3.2 ¿Qué número de bins muestra mejor la forma?
# - bins = 8: demasiado gruesos; se pierde el detalle del pico y de la cola.
# - bins = 120: demasiado finos; barras irregulares (ruido muestral) y
#   muchos huecos en la cola.
# - bins = 30 (cercano a sqrt(1500) ≈ 39): equilibrio entre detalle y ruido;
#   muestra claramente el pico y la cola derecha. Es la mejor opción.
#
# 3.3 ¿Qué cambia con scale_x_log10()?
# La distribución se vuelve aproximadamente SIMÉTRICA (forma de campana),
# como corresponde a una variable log-normal: la escala log convierte
# diferencias multiplicativas en aditivas y "estira" la zona donde están
# la mayoría de pedidos. Media y mediana quedan más cerca.
# A gerencia le reportaría la MEDIANA (valor típico de un pedido), porque no
# se deja arrastrar por los pocos pedidos grandes; si interesa el total de
# ingresos, la media también sirve (media × número de pedidos = ventas).

# 3.4 Repetir por categoría
ggplot(pedidos, aes(x = valor / 1000, fill = categoria)) +
  geom_histogram(bins = 30, color = "white", show.legend = FALSE) +
  geom_vline(data = pedidos |> group_by(categoria) |> summarise(med = median(valor) / 1000),
             aes(xintercept = med)) +
  facet_wrap(~ categoria, ncol = 1) +
  scale_x_log10(labels = miles) +
  scale_fill_manual(values = colores_cat) +
  labs(title = "Valor del pedido por categoría (escala log)",
       subtitle = "Línea: mediana de cada categoría",
       x = "Valor del pedido (miles COP)", y = "Pedidos") +
  theme_minimal()

# Densidades superpuestas: otra forma de comparar
ggplot(pedidos, aes(x = valor / 1000, color = categoria)) +
  geom_density(linewidth = 1) +
  scale_x_log10(labels = miles) +
  scale_color_manual(values = colores_cat) +
  labs(x = "Valor del pedido (miles COP, escala log)", y = "Densidad", color = "Categoría") +
  theme_minimal()

pedidos |>
  group_by(categoria) |>
  summarise(n = n(), mediana = median(valor), media = mean(valor)) |>
  mutate(across(c(mediana, media), pesos))

# RESPUESTA: el histograma global mezcla DOS poblaciones. Hogar y Moda tienen
# prácticamente la misma distribución, pero Tecnología está desplazada a la
# derecha (su mediana es ~1,8 veces mayor: exp(0,6) ≈ 1,82). El histograma
# global lo oculta: parece una sola distribución sesgada, y buena parte de la
# cola derecha son en realidad pedidos de Tecnología. Para modelar el valor,
# la categoría es una variable clave.


# =============================================================================
# EJERCICIO 4: Color con propósito
# =============================================================================
desvio_mes <- pedidos |>
  count(mes = month(fecha)) |>
  mutate(desvio = n - mean(n))

mean(count(pedidos, mes = month(fecha))$n)   # referencia: promedio mensual

ggplot(desvio_mes, aes(factor(mes, labels = month.abb), desvio, fill = desvio)) +
  geom_col() +
  geom_hline(yintercept = 0, color = "grey40") +
  scale_fill_gradient2(low = "#b2182b", mid = "grey90",
                       high = "#2166ac", midpoint = 0) +
  labs(title = "Pedidos por mes: desviación frente al promedio mensual",
       x = "Mes", y = "Pedidos por encima / debajo del promedio", fill = "Desvío") +
  theme_minimal()

# 4.1 ¿Por qué una paleta divergente? ¿Cuál es la referencia?
# RESPUESTA: porque el dato es una DESVIACIÓN respecto a un punto medio con
# significado: el promedio mensual de pedidos (≈ 1500/12 = 125). Hay dos
# direcciones que interpretar (por encima / por debajo) y la paleta divergente
# las separa con dos tonos que se alejan de un gris neutro en el 0. Una paleta
# secuencial no mostraría dónde se cruza el promedio.

# 4.2 colores_canal con nombres, usado en dos gráficos distintos
colores_canal   # definido al inicio: App, Web, Tienda

# Gráfico A: participación de pedidos por canal
g_canal_a <- pedidos |>
  count(canal) |>
  ggplot(aes(fct_reorder(canal, n), n, fill = canal)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_fill_manual(values = colores_canal) +
  labs(title = "Pedidos por canal", x = NULL, y = "Pedidos") +
  theme_minimal()

# Gráfico B: valor del pedido por canal (otro orden de niveles y otro geom)
g_canal_b <- pedidos |>
  filter(canal != "App") |>                 # aunque falte un nivel...
  ggplot(aes(valor / 1000, fill = canal)) +
  geom_density(alpha = 0.6) +
  scale_x_log10(labels = miles) +
  scale_fill_manual(values = colores_canal) + # ...cada canal conserva su color
  labs(title = "Valor del pedido: Web vs. Tienda",
       x = "Valor (miles COP, escala log)", y = "Densidad", fill = "Canal") +
  theme_minimal()

print(g_canal_a)
print(g_canal_b)
# El gráfico de líneas del Ej. 2.4 también usa colores_canal: el mismo canal
# tiene siempre el mismo color en todo el informe. Con un vector con nombre,
# el color no depende del orden ni de qué niveles aparezcan.

# 4.3 ¿Se entiende sin distinguir rojo y verde?
# Coblis (https://www.color-blindness.com/coblis-color-blindness-simulator/):
# guardar los gráficos y subirlos. También se puede simular en R:
if (requireNamespace("colorspace", quietly = TRUE)) {
  print(colorspace::deutan(colores_canal))        # deuteranopía (verde)
  print(colorspace::protan(colores_canal))        # protanopía (rojo)
  colorspace::swatchplot(
    "Original"    = colores_canal,
    "Deuteranopía" = colorspace::deutan(colores_canal),
    "Protanopía"   = colorspace::protan(colores_canal)
  )
  # Simula el gráfico completo (requiere el paquete colorblindr, opcional):
  # colorblindr::cvd_grid(g_canal_a)
}
# RESPUESTA: sí. La paleta Okabe-Ito (azul, naranja, verde azulado) está
# diseñada para seguir siendo distinguible con deuteranopía y protanopía, y
# los gráficos no dependen solo del color: los ejes y etiquetas nombran cada
# canal (señal redundante). La paleta divergente usa rojo-azul, no
# rojo-verde, y la línea en 0 marca la referencia.


# =============================================================================
# EJERCICIO 5: Tabla de contingencia y su gráfico
# =============================================================================
tabla <- table(pedidos$canal, pedidos$categoria)
tabla
round(100 * prop.table(tabla, margin = 1), 1)   # % por fila

ggplot(pedidos, aes(x = canal, fill = categoria)) +
  geom_bar(position = "fill") +
  scale_fill_manual(values = colores_cat) +
  scale_y_continuous(labels = label_percent()) +
  labs(y = "Proporción dentro del canal", x = "Canal", fill = "Categoría") +
  theme_minimal()

# 5.1 ¿En qué canal pesa más Tecnología?
pct_fila <- round(100 * prop.table(tabla, margin = 1), 1)
pct_fila[, "Tecnología"]
names(which.max(pct_fila[, "Tecnología"]))
# RESPUESTA: el canal con mayor % de Tecnología es el que imprime la línea
# anterior. Sí coincide con las barras al 100%: la altura de cada segmento
# es exactamente el % por fila. Pero las diferencias entre canales son de
# pocos puntos porcentuales; como la categoría se asignó sin depender del
# canal, son ruido muestral. La prueba chi-cuadrado lo confirma:
chisq.test(tabla)

# 5.2 Las barras al 100% ocultan cuántos pedidos tiene cada canal:
# RESPUESTA: el gráfico de MARIMEKKO (mosaico) de los retos lo resuelve:
# el ANCHO de cada columna es la proporción de pedidos del canal y la ALTURA
# es la proporción de la categoría dentro del canal; así el área = proporción
# conjunta.
marimekko <- pedidos |>
  count(canal, categoria) |>
  group_by(canal) |>
  mutate(n_canal = sum(n), alto = n / n_canal,
         ymax = cumsum(alto), ymin = ymax - alto) |>
  ungroup() |>
  mutate(ancho = n_canal / sum(n))

anchos <- marimekko |>
  distinct(canal, ancho) |>
  arrange(desc(ancho)) |>
  mutate(xmax = cumsum(ancho), xmin = xmax - ancho)

marimekko <- marimekko |> left_join(anchos, by = c("canal", "ancho"))

ggplot(marimekko) +
  geom_rect(aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = categoria),
            color = "white") +
  geom_text(aes(x = (xmin + xmax) / 2, y = (ymin + ymax) / 2,
                label = paste0(round(100 * alto), "%")), size = 3.5) +
  geom_text(data = anchos,
            aes(x = (xmin + xmax) / 2, y = 1.04,
                label = paste0(canal, " (", round(100 * ancho), "%)")), size = 3.5) +
  scale_fill_manual(values = colores_cat) +
  scale_x_continuous(labels = label_percent()) +
  scale_y_continuous(labels = label_percent()) +
  labs(title = "Marimekko: canal × categoría",
       subtitle = "Ancho = % de pedidos del canal · Alto = % de la categoría dentro del canal",
       x = "Proporción de pedidos (canal)", y = "Proporción dentro del canal",
       fill = "Categoría") +
  theme_minimal()

# Alternativa en R base:
mosaicplot(tabla, color = colores_cat[colnames(tabla)],
           main = "Mosaico canal × categoría", xlab = "Canal", ylab = "Categoría")

# 5.3 Tabla con kable() y dos frases de interpretación
tabla_kable <- as.data.frame.matrix(tabla) |>
  rownames_to_column("Canal") |>
  mutate(Total = Hogar + Moda + Tecnología) |>
  mutate(across(c(Hogar, Moda, Tecnología),
                \(x) paste0(x, " (", round(100 * x / Total, 1), "%)")))

kable(tabla_kable,
      caption = "Pedidos por canal y categoría (entre paréntesis: % dentro del canal)",
      align = "lrrrr",
      format.args = list(big.mark = "."))

# Interpretación (ajuste las cifras a su salida):
# 1. App es el canal con más pedidos (cerca del 45% del total), seguido de Web
#    y Tienda, pero la mezcla de categorías es muy parecida en los tres:
#    cada categoría pesa alrededor de un tercio dentro de cada canal.
# 2. Las diferencias de pocos puntos entre canales (p. ej., en Tecnología) no
#    son significativas (chi-cuadrado con p alto), así que no hay evidencia de
#    que un canal se especialice en alguna categoría.


# =============================================================================
# EJERCICIO 6: Interactividad con criterio
# =============================================================================
library(highcharter)

# Configuración en español: separador de miles "." y decimal ","
lang <- getOption("highcharter.lang")
lang$thousandsSep <- "."
lang$decimalPoint <- ","
lang$months      <- c("Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
                      "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre")
lang$shortMonths <- c("Ene", "Feb", "Mar", "Abr", "May", "Jun",
                      "Jul", "Ago", "Sep", "Oct", "Nov", "Dic")
lang$weekdays    <- c("Domingo", "Lunes", "Martes", "Miércoles",
                      "Jueves", "Viernes", "Sábado")
lang$downloadPNG <- "Descargar PNG"
lang$downloadCSV <- "Descargar CSV"
lang$printChart  <- "Imprimir gráfico"
options(highcharter.lang = lang)

# 6.1 Gráfico original con tooltip y ejes en español
conteo <- pedidos |> count(categoria, canal)

hc1 <- conteo |>
  hchart("column", hcaes(x = categoria, y = n, group = canal)) |>
  hc_colors(unname(colores_canal[sort(unique(conteo$canal))])) |>
  hc_tooltip(
    shared = TRUE,
    headerFormat = "<b>Categoría: {point.key}</b><br/>",
    pointFormat  = "<span style='color:{point.color}'>●</span> {series.name}: <b>{point.y:,.0f}</b> pedidos<br/>"
  ) |>
  hc_title(text = "Pedidos por categoría y canal") |>
  hc_xAxis(title = list(text = "Categoría")) |>
  hc_yAxis(title = list(text = "Número de pedidos"),
           labels = list(format = "{value:,.0f}")) |>
  hc_legend(title = list(text = "Canal"))
hc1

# Con ventas en pesos el separador de miles sí se nota:
ventas_cat <- pedidos |>
  group_by(categoria, canal) |>
  summarise(ventas = sum(valor), .groups = "drop")

hc2 <- ventas_cat |>
  hchart("column", hcaes(x = categoria, y = ventas, group = canal)) |>
  hc_colors(unname(colores_canal[sort(unique(ventas_cat$canal))])) |>
  hc_tooltip(shared = TRUE,
             headerFormat = "<b>{point.key}</b><br/>",
             pointFormat  = "{series.name}: <b>${point.y:,.0f}</b><br/>") |>
  hc_title(text = "Ventas por categoría y canal (COP)") |>
  hc_xAxis(title = list(text = "Categoría")) |>
  hc_yAxis(title = list(text = "Ventas (COP)"),
           labels = list(format = "${value:,.0f}"))
hc2

# 6.2 Versión en ggplot2
g6 <- ggplot(conteo, aes(categoria, n, fill = canal)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(aes(label = miles(n)), position = position_dodge(width = 0.8),
            vjust = -0.4, size = 3.2) +
  scale_fill_manual(values = colores_canal) +
  scale_y_continuous(labels = miles, expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Pedidos por categoría y canal",
       x = "Categoría", y = "Número de pedidos", fill = "Canal") +
  theme_minimal()
g6

# (Opcional) puente: el mismo ggplot convertido en interactivo
# plotly::ggplotly(g6)

# ¿Qué gana y qué pierde cada una?
# highcharter
#   + Tooltip con valores exactos, ocultar/mostrar canales desde la leyenda,
#     zoom, exportar a PNG/CSV. Ideal para explorar.
#   - Requiere navegador/HTML: no se imprime bien, depende de JavaScript, y su
#     personalización usa sintaxis de Highcharts (no la gramática de ggplot).
#     Licencia comercial de Highcharts para uso empresarial.
# ggplot2
#   + Estático, reproducible y con calidad de publicación; se exporta a PDF,
#     PNG o Word sin perder nada; gramática por capas coherente con el resto
#     del informe; etiquetas con el valor ya visibles.
#   - Sin interacción: el lector no puede consultar valores que no se
#     rotularon ni filtrar canales.
#
# 6.3 ¿Cuál en un PDF para gerencia y cuál en un dashboard?
# - Informe PDF para gerencia: ggplot2. Un PDF es estático (la interacción
#   se pierde); conviene un gráfico limpio, con los números clave rotulados y
#   un título que diga la conclusión.
# - Dashboard: highcharter. El usuario explora por su cuenta, filtra canales
#   y consulta valores con el tooltip; la interacción sí aporta valor.