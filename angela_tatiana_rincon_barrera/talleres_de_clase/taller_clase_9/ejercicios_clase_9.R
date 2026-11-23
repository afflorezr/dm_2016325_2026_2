# Clase 9: tablas, gráficos y distribuciones de frecuencia
# Parte 7: ejercicios de práctica

paquetes <- c("dplyr", "tidyr", "ggplot2", "lubridate", "scales", "knitr",
              "highcharter", "htmlwidgets")
tipo     <- if (.Platform$OS.type == "windows") "binary" else getOption("pkgType")
faltan   <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) install.packages(faltan, type = tipo, dependencies = TRUE)

library(dplyr)
library(tidyr)
library(ggplot2)
library(lubridate)
library(scales)
library(knitr)

miles <- label_number(big.mark = ".", decimal.mark = ",")


# Datos ---------------------------------------------------------------------

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

# colores por canal (paleta Okabe-Ito, apta para daltonismo); se usan en
# los ejercicios 2 y 4
colores_canal     <- c(App = "#0072B2", Web = "#E69F00", Tienda = "#009E73")
colores_categoria <- c(Hogar = "#56B4E9", Moda = "#CC79A7", "Tecnología" = "#D55E00")


# Ejercicio 1: tablas de frecuencia ----------------------------------------

frec_calif <- pedidos |>
  count(calificacion) |>
  mutate(pct = 100 * n / sum(n), acum = cumsum(pct))
frec_calif

# 1.1
frec_calif |> filter(calificacion >= 4) |> summarise(pct_4_o_mas = sum(pct))

# cortes de la clase
pedidos |>
  mutate(rango = cut(valor, c(0, 1e5, 2e5, 4e5, Inf), right = FALSE)) |>
  count(rango) |>
  mutate(pct = round(100 * n / sum(n), 1))

# 1.3 cortes de igual ancho
cortes_iguales <- seq(0, max(pedidos$valor), length.out = 9)
frec_valor <- pedidos |>
  mutate(rango = cut(valor, cortes_iguales, include.lowest = TRUE, dig.lab = 8)) |>
  count(rango, .drop = FALSE) |>
  mutate(pct = round(100 * n / sum(n), 1))
frec_valor

summary(pedidos$valor)


# Ejercicio 2: elige el gráfico según la pregunta ---------------------------

# 2.1 comparar categorías: barras
g2_1 <- pedidos |>
  count(canal) |>
  ggplot(aes(reorder(canal, -n), n, fill = canal)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = n), vjust = -0.4) +
  scale_fill_manual(values = colores_canal) +
  labs(title = "Pedidos por canal", x = NULL, y = "Pedidos") +
  theme_minimal()
g2_1

# 2.2 variable discreta: barras por valor (no histograma)
g2_2 <- ggplot(pedidos, aes(dias_entrega)) +
  geom_bar(fill = "#006DAE") +
  scale_x_continuous(breaks = 1:max(pedidos$dias_entrega)) +
  labs(title = "Distribución de los días de entrega",
       x = "Días de entrega", y = "Pedidos") +
  theme_minimal()
g2_2

# 2.3 numérica por grupos: boxplot (escala log por la asimetría)
g2_3 <- ggplot(pedidos, aes(categoria, valor)) +
  geom_boxplot(fill = "grey85", outlier.alpha = 0.4) +
  scale_y_log10(labels = miles) +
  labs(title = "Valor del pedido por categoría",
       x = NULL, y = "Valor del pedido (COP, escala log)") +
  theme_minimal()
g2_3

# 2.4 tendencia: líneas
ventas_mes <- pedidos |>
  mutate(mes = floor_date(fecha, "month")) |>
  group_by(mes, canal) |>
  summarise(ventas = sum(valor), .groups = "drop")

g2_4 <- ggplot(ventas_mes, aes(mes, ventas / 1e6, colour = canal)) +
  geom_line(linewidth = 1) +
  geom_point() +
  scale_colour_manual(values = colores_canal) +
  scale_x_date(date_labels = "%b", date_breaks = "1 month") +
  labs(title = "Ventas mensuales por canal, 2025",
       x = NULL, y = "Ventas (millones COP)", colour = "Canal") +
  theme_minimal()
g2_4

ggsave("ej2_1_pedidos_canal.png", g2_1, width = 6, height = 4)
ggsave("ej2_2_dias_entrega.png", g2_2, width = 6, height = 4)
ggsave("ej2_3_valor_categoria.png", g2_3, width = 6, height = 4)
ggsave("ej2_4_ventas_mes_canal.png", g2_4, width = 8, height = 4)


# Ejercicio 3: la forma del valor del pedido -------------------------------

pedidos |>
  summarise(media = mean(valor), mediana = median(valor),
            p25 = quantile(valor, .25), p75 = quantile(valor, .75),
            p95 = quantile(valor, .95), maximo = max(valor),
            asimetria = mean((valor - mean(valor))^3) / sd(valor)^3)

histograma <- function(bins, log = FALSE) {
  g <- ggplot(pedidos, aes(x = valor / 1000)) +
    geom_histogram(bins = bins, fill = "#006DAE", color = "white") +
    geom_vline(xintercept = median(pedidos$valor) / 1000) +
    labs(title = paste("Valor del pedido,", bins, "bins"),
         x = "Valor del pedido (miles COP)", y = "Pedidos") +
    theme_minimal()
  if (log) g <- g + scale_x_log10(labels = miles) +
    labs(title = paste("Valor del pedido,", bins, "bins, escala log"))
  g
}

h8   <- histograma(8)
h30  <- histograma(30)
h120 <- histograma(120)
hlog <- histograma(30, log = TRUE)
h8; h30; h120; hlog

ggsave("ej3_hist_8.png", h8, width = 6, height = 4)
ggsave("ej3_hist_30.png", h30, width = 6, height = 4)
ggsave("ej3_hist_120.png", h120, width = 6, height = 4)
ggsave("ej3_hist_log.png", hlog, width = 6, height = 4)

# 3.4 por categoría
medianas_cat <- pedidos |>
  summarise(media = mean(valor), mediana = median(valor), .by = categoria)
medianas_cat

h_cat <- ggplot(pedidos, aes(x = valor / 1000, fill = categoria)) +
  geom_histogram(bins = 30, color = "white", show.legend = FALSE) +
  geom_vline(data = medianas_cat, aes(xintercept = mediana / 1000)) +
  scale_x_log10(labels = miles) +
  scale_fill_manual(values = colores_categoria) +
  facet_wrap(~ categoria, ncol = 1) +
  labs(title = "Valor del pedido por categoría (escala log)",
       x = "Valor del pedido (miles COP)", y = "Pedidos") +
  theme_minimal()
h_cat
ggsave("ej3_hist_categoria.png", h_cat, width = 6, height = 6)


# Ejercicio 4: color con propósito -----------------------------------------

desvio_mes <- pedidos |>
  count(mes = month(fecha)) |>
  mutate(desvio = n - mean(n))
desvio_mes

g4_1 <- ggplot(desvio_mes, aes(factor(mes), desvio, fill = desvio)) +
  geom_col() +
  geom_hline(yintercept = 0) +
  scale_fill_gradient2(low = "#b2182b", mid = "grey90",
                       high = "#2166ac", midpoint = 0) +
  labs(title = "Pedidos por mes frente al promedio mensual",
       x = "Mes", y = "Diferencia con el promedio", fill = "Desvío") +
  theme_minimal()
g4_1
ggsave("ej4_desvio_mes.png", g4_1, width = 7, height = 4)

# 4.2 colores_canal en dos gráficos distintos: g2_1 y g2_4 (ejercicio 2)
# y este de valor por canal
g4_2 <- ggplot(pedidos, aes(canal, valor, fill = canal)) +
  geom_boxplot(show.legend = FALSE, outlier.alpha = 0.4) +
  scale_fill_manual(values = colores_canal) +
  scale_y_log10(labels = miles) +
  labs(title = "Valor del pedido por canal",
       x = NULL, y = "Valor del pedido (COP, escala log)") +
  theme_minimal()
g4_2
ggsave("ej4_valor_canal.png", g4_2, width = 6, height = 4)


# Ejercicio 5: tabla de contingencia y su gráfico --------------------------

tabla <- table(pedidos$canal, pedidos$categoria)
tabla
round(100 * prop.table(tabla, margin = 1), 1)   # % por fila

g5_1 <- ggplot(pedidos, aes(x = canal, fill = categoria)) +
  geom_bar(position = "fill") +
  scale_fill_manual(values = colores_categoria) +
  scale_y_continuous(labels = percent) +
  labs(title = "Mezcla de categorías dentro de cada canal",
       x = NULL, y = "Proporción dentro del canal", fill = "Categoría") +
  theme_minimal()
g5_1
ggsave("ej5_barras_100.png", g5_1, width = 6, height = 4)

# 5.2 Marimekko: ancho = peso del canal, alto = mezcla de categorías
mosaico <- pedidos |>
  count(canal, categoria) |>
  mutate(total_canal = sum(n), alto = n / total_canal, .by = canal) |>
  mutate(ancho = total_canal / sum(n))

columnas <- mosaico |>
  distinct(canal, ancho) |>
  arrange(desc(ancho)) |>
  mutate(xmax = cumsum(ancho), xmin = xmax - ancho)

mosaico <- mosaico |>
  left_join(columnas, by = c("canal", "ancho")) |>
  arrange(canal, categoria) |>
  mutate(ymax = cumsum(alto), ymin = ymax - alto, .by = canal)

g5_2 <- ggplot(mosaico) +
  geom_rect(aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = categoria),
            colour = "white") +
  geom_text(aes((xmin + xmax) / 2, (ymin + ymax) / 2, label = n), size = 3.5) +
  scale_fill_manual(values = colores_categoria) +
  scale_x_continuous(breaks = (columnas$xmin + columnas$xmax) / 2,
                     labels = paste0(columnas$canal, "\n(", percent(columnas$ancho, 1), ")")) +
  scale_y_continuous(labels = percent) +
  labs(title = "Pedidos por canal y categoría (Marimekko)",
       subtitle = "Ancho: peso del canal en los pedidos; alto: mezcla de categorías",
       x = NULL, y = "Proporción dentro del canal", fill = "Categoría") +
  theme_minimal()
g5_2
ggsave("ej5_marimekko.png", g5_2, width = 7, height = 5)

# 5.3
tabla_pct <- as.data.frame.matrix(round(100 * prop.table(tabla, margin = 1), 1))
tabla_pct$Pedidos <- as.vector(rowSums(tabla))
kable(tabla_pct, caption = "Distribución de categorías por canal (% por fila)",
      format.args = list(big.mark = ".", decimal.mark = ","))
chisq.test(tabla)


# Ejercicio 6: interactividad con criterio ---------------------------------

library(highcharter)

# 6.1 idioma y separadores en español
idioma <- getOption("highcharter.lang")
idioma$thousandsSep <- "."
idioma$decimalPoint <- ","
options(highcharter.lang = idioma)

grafico_hc <- pedidos |>
  count(categoria, canal) |>
  hchart("column", hcaes(x = categoria, y = n, group = canal)) |>
  hc_colors(unname(colores_canal[c("App", "Tienda", "Web")])) |>
  hc_tooltip(shared = TRUE,
             headerFormat = "<b>{point.key}</b><br>",
             pointFormat = "{series.name}: {point.y:,.0f} pedidos<br>") |>
  hc_xAxis(title = list(text = "Categoría")) |>
  hc_yAxis(title = list(text = "Número de pedidos"),
           labels = list(format = "{value:,.0f}")) |>
  hc_title(text = "Pedidos por categoría y canal")
grafico_hc

# selfcontained necesita pandoc (viene con RStudio); si no está, se guarda
# con una carpeta de archivos auxiliares
tryCatch(
  htmlwidgets::saveWidget(grafico_hc, "ej6_highcharter.html", selfcontained = TRUE),
  error = function(e) htmlwidgets::saveWidget(grafico_hc, "ej6_highcharter.html",
                                              selfcontained = FALSE)
)

# 6.2 versión en ggplot2
g6 <- pedidos |>
  count(categoria, canal) |>
  ggplot(aes(categoria, n, fill = canal)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(aes(label = miles(n)), position = position_dodge(width = 0.8),
            vjust = -0.4, size = 3.2) +
  scale_fill_manual(values = colores_canal) +
  scale_y_continuous(labels = miles) +
  labs(title = "Pedidos por categoría y canal",
       x = "Categoría", y = "Número de pedidos", fill = "Canal") +
  theme_minimal()
g6
ggsave("ej6_ggplot.png", g6, width = 7, height = 4)


# Respuestas ----------------------------------------------------------------
#
# Ejercicio 1
# 1. El 69,7 % de los pedidos tiene calificación de 4 o 5.
# 2. calificacion es ordinal: tiene sentido decir "el 30,3 % calificó 3 o
#    menos". canal es nominal (App, Web, Tienda no tienen orden), así que
#    acumular depende del orden en que se listen y no significa nada.
# 3. Con 8 intervalos de igual ancho (unos $158.900 cada uno), los de
#    $794.000 a $1.112.000 quedan vacíos y el de $635.000 a $794.000 tiene
#    el 0,8 %. El valor es muy asimétrico a la derecha: el 66,9 % está en el
#    primer intervalo y dos pedidos de más de $1,1 millones estiran el rango.
#
# Ejercicio 2
# 1. Barras, porque se comparan conteos entre categorías: App genera más
#    pedidos (709, 47 %), seguida de Web (517) y Tienda (274).
# 2. Barras por valor, porque los días de entrega son discretos: la mayoría
#    tarda 3 o 4 días (promedio 4,0) y la cola llega hasta 13.
# 3. Boxplot, porque compara la distribución de una numérica entre grupos
#    (en escala log por la asimetría): Tecnología tiene pedidos más caros
#    (mediana $189.600) que Moda ($100.300) y Hogar ($93.950).
# 4. Líneas, porque muestran la evolución en el tiempo: App lidera casi
#    todos los meses (entre $6,2 y $11,3 millones), salvo abril, cuando Web
#    la supera; Tienda se mantiene entre $2,1 y $4,6 millones. No hay una
#    tendencia clara, solo variaciones de un mes a otro.
#
# Ejercicio 3
# 1. Asimetría positiva (2,66): la mayoría de pedidos está entre $75.000 y
#    $187.000 (p25 y p75), con una cola larga a la derecha hasta $1,27
#    millones. La media ($151.927) es mayor que la mediana ($119.300)
#    porque la cola la arrastra hacia arriba.
# 2. 30 bins: con 8 se pierde la forma (casi todo queda en dos barras) y
#    con 120 aparece ruido y barras vacías que no dicen nada.
# 3. En escala log la distribución se ve casi simétrica (el valor es
#    aproximadamente lognormal) y la cola deja de dominar el gráfico. A
#    gerencia le reportaría la mediana, que representa el pedido típico sin
#    que la afecten los pedidos muy grandes.
# 4. Sí: Tecnología está claramente desplazada a la derecha (mediana
#    $189.600 frente a cerca de $100.000 en Hogar y Moda). El histograma
#    global mezcla dos niveles de precio y oculta que buena parte de la
#    cola derecha corresponde a Tecnología.
#
# Ejercicio 4
# 1. Porque se muestra una desviación respecto a una referencia, el
#    promedio mensual (125 pedidos): importa el signo, no solo la magnitud.
#    Azul indica meses por encima (marzo, +15) y rojo por debajo (junio,
#    -13); el gris marca el promedio.
# 2. colores_canal se usa en g2_1 (pedidos por canal), g2_4 (ventas
#    mensuales), g4_2 (valor por canal) y g6, así cada canal conserva su
#    color en todos los gráficos.
# 3. Se usó la paleta Okabe-Ito, pensada para daltonismo, y la divergente
#    es azul-rojo, no rojo-verde. También se cambiaron los colores por
#    defecto de las categorías, que mezclaban rojo y verde. Falta subir los
#    PNG a Coblis para comprobarlo.
#
# Ejercicio 5
# 1. Tecnología pesa más en App (34,3 % de sus pedidos, frente a 31,1 % en
#    Web y 28,1 % en Tienda). Coincide con las barras al 100 %, que muestran
#    justamente los porcentajes por fila.
# 2. El gráfico de Marimekko: el ancho de cada columna muestra el peso del
#    canal (App 47 %, Web 34 %, Tienda 18 %) y el alto, la mezcla de
#    categorías.
# 3. App concentra casi la mitad de los pedidos y reparte su demanda casi
#    por igual entre las tres categorías; Tienda tiene más peso de Moda
#    (40,5 %). Sin embargo, las diferencias entre canales son pequeñas y no
#    son estadísticamente significativas (chi cuadrado, p = 0,15).
#
# Ejercicio 6
# 1. Se cambiaron el título de los ejes, el tooltip ("pedidos") y los
#    separadores con options(highcharter.lang): punto para miles y coma
#    para decimales.
# 2. highcharter gana interactividad (tooltip, ocultar canales desde la
#    leyenda, ver el valor exacto al pasar el mouse) pero necesita un
#    navegador. ggplot2 gana como imagen estática: se exporta a PDF o Word,
#    muestra las cifras en las etiquetas y se reproduce igual en cualquier
#    parte, pero pierde la interacción.
# 3. En el informe PDF para gerencia usaría ggplot2, porque el documento es
#    estático y las cifras deben verse sin interactuar. En un dashboard
#    usaría highcharter, porque el usuario explora y filtra los datos.
