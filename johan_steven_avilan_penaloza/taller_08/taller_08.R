library(tidyverse)
library(lubridate)
library(knitr)
library(scales)

# Datos
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

colores_canal <- c(App = "#0072B2", Web = "#E69F00", Tienda = "#CC79A7")

tema <- theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"))
fmt_miles <- label_number(big.mark = ".", decimal.mark = ",")

# Ejercicio 1
tab_calif <- pedidos |>
  count(calificacion) |>
  mutate(pct = 100 * n / sum(n), acum = cumsum(pct))
print(tab_calif)

pct_4_mas <- pedidos |> summarise(pct = 100 * mean(calificacion >= 4))
print(pct_4_mas)

pedidos |>
  mutate(rango = cut(valor, c(0, 1e5, 2e5, 4e5, Inf), right = FALSE)) |>
  count(rango) |>
  mutate(pct = round(100 * n / sum(n), 1))

tab_ancho <- pedidos |>
  mutate(rango = cut_width(valor, width = 2e5, boundary = 0)) |>
  count(rango) |>
  mutate(pct = round(100 * n / sum(n), 2))
print(tab_ancho)

# Ejercicio 2
ventas_mes <- pedidos |>
  mutate(mes = floor_date(fecha, "month")) |>
  group_by(mes, canal) |>
  summarise(ventas = sum(valor), .groups = "drop")

g2a <- pedidos |>
  count(canal) |>
  mutate(canal = fct_reorder(canal, n, .desc = TRUE)) |>
  ggplot(aes(canal, n, fill = canal)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = n), vjust = -0.4) +
  scale_fill_manual(values = colores_canal) +
  labs(title = "Pedidos por canal", x = NULL, y = "Pedidos") + tema
print(g2a)

g2b <- ggplot(pedidos, aes(dias_entrega)) +
  geom_bar(fill = "#0072B2") +
  scale_x_continuous(breaks = scales::breaks_width(1)) +
  labs(title = "Distribución de días de entrega",
       x = "Días de entrega", y = "Pedidos") + tema
print(g2b)

g2c <- ggplot(pedidos, aes(categoria, valor / 1000, fill = categoria)) +
  geom_boxplot(show.legend = FALSE, alpha = .7) +
  scale_y_log10(labels = fmt_miles) +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "Valor del pedido por categoría",
       x = NULL, y = "Valor (miles COP, escala log)") + tema
print(g2c)

g2d <- ggplot(ventas_mes, aes(mes, ventas / 1e6, color = canal)) +
  geom_line(linewidth = 1) +
  geom_point() +
  scale_color_manual(values = colores_canal) +
  scale_x_date(date_labels = "%b", date_breaks = "1 month") +
  labs(title = "Ventas mensuales por canal",
       x = NULL, y = "Ventas (millones COP)", color = "Canal") + tema
print(g2d)

# Ejercicio 3
hist_valor <- function(bins, log = FALSE) {
  g <- ggplot(pedidos, aes(x = valor / 1000)) +
    geom_histogram(bins = bins, fill = "#006DAE", color = "white") +
    geom_vline(xintercept = median(pedidos$valor) / 1000) +
    labs(x = "Valor del pedido (miles COP)", y = "Pedidos",
         title = paste0("bins = ", bins, if (log) " (escala log)" else "")) + tema
  if (log) g <- g + scale_x_log10(labels = fmt_miles)
  g
}
hist_valor(30)
hist_valor(8)
hist_valor(120)
hist_valor(30, log = TRUE)

pedidos |>
  summarise(media = mean(valor), mediana = median(valor),
            q95 = quantile(valor, .95), maximo = max(valor),
            media_geom = exp(mean(log(valor))))

g3d <- ggplot(pedidos, aes(valor / 1000, fill = categoria)) +
  geom_histogram(bins = 30, color = "white", show.legend = FALSE) +
  scale_x_log10(labels = fmt_miles) +
  facet_wrap(~ categoria, ncol = 1) +
  scale_fill_brewer(palette = "Set2") +
  labs(x = "Valor del pedido (miles COP, escala log)", y = "Pedidos") + tema
print(g3d)

# Ejercicio 4
desvio_mes <- pedidos |>
  count(mes = month(fecha)) |>
  mutate(desvio = n - mean(n))

g4 <- ggplot(desvio_mes, aes(factor(mes), desvio, fill = desvio)) +
  geom_col() +
  scale_fill_gradient2(low = "#b2182b", mid = "grey90",
                       high = "#2166ac", midpoint = 0) +
  labs(x = "Mes", y = "Desvío frente al promedio mensual",
       fill = "Desvío") + tema
print(g4)

g4b1 <- pedidos |>
  count(canal) |>
  ggplot(aes(canal, n, fill = canal)) +
  geom_col(show.legend = FALSE) +
  scale_fill_manual(values = colores_canal) +
  labs(title = "Pedidos por canal", x = NULL, y = "Pedidos") + tema

g4b2 <- ventas_mes |>
  ggplot(aes(mes, ventas / 1e6, color = canal)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = colores_canal) +
  labs(title = "Ventas mensuales por canal",
       x = NULL, y = "Ventas (millones COP)", color = "Canal") + tema
print(g4b1); print(g4b2)

library(colorspace)
par(mfrow = c(1, 3))
scales::show_col(colores_canal,         labels = FALSE)
scales::show_col(deutan(colores_canal), labels = FALSE)
scales::show_col(protan(colores_canal), labels = FALSE)
par(mfrow = c(1, 1))

# Ejercicio 5
tabla <- table(pedidos$canal, pedidos$categoria)
tabla
round(100 * prop.table(tabla, margin = 1), 1)

g5 <- ggplot(pedidos, aes(x = canal, fill = categoria)) +
  geom_bar(position = "fill") +
  scale_y_continuous(labels = percent) +
  scale_fill_brewer(palette = "Set2") +
  labs(y = "Proporción dentro del canal", x = NULL, fill = "Categoría") + tema
print(g5)

marimekko <- pedidos |>
  count(canal, categoria) |>
  group_by(canal) |>
  mutate(ancho = sum(n), prop = n / ancho) |>
  ungroup() |>
  arrange(desc(ancho), canal, categoria) |>
  mutate(canal = fct_inorder(canal))

anchos <- marimekko |> distinct(canal, ancho) |>
  mutate(xmax = cumsum(ancho) / sum(ancho),
         xmin = xmax - ancho / sum(ancho))

g5b <- marimekko |>
  left_join(anchos, by = c("canal", "ancho")) |>
  group_by(canal) |>
  mutate(ymax = cumsum(prop), ymin = ymax - prop) |>
  ungroup() |>
  ggplot() +
  geom_rect(aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
                fill = categoria), color = "white") +
  geom_text(aes(x = (xmin + xmax) / 2, y = (ymin + ymax) / 2,
                label = n), color = "black", size = 3) +
  scale_x_continuous(breaks = (anchos$xmin + anchos$xmax) / 2,
                     labels = paste0(anchos$canal, "\n(n = ", anchos$ancho, ")")) +
  scale_y_continuous(labels = percent) +
  scale_fill_brewer(palette = "Set2") +
  labs(x = NULL, y = "Proporción dentro del canal", fill = "Categoría",
       title = "Marimekko: canal (ancho) x categoría (alto)") + tema
print(g5b)

tabla_pct <- round(100 * prop.table(tabla, margin = 1), 1)
kable(tabla_pct, caption = "Distribución de categorías por canal (% por fila)",
      col.names = colnames(tabla_pct))
chisq.test(tabla)

# Ejercicio 6
library(highcharter)

lang <- getOption("highcharter.lang")
lang$thousandsSep <- "."
lang$decimalPoint <- ","
options(highcharter.lang = lang)

hc <- pedidos |>
  count(categoria, canal) |>
  hchart("column", hcaes(x = categoria, y = n, group = canal)) |>
  hc_colors(unname(colores_canal[c("App", "Tienda", "Web")])) |>
  hc_tooltip(shared = TRUE,
             headerFormat = "<b>Categoría: {point.key}</b><br/>",
             pointFormat  = paste0('<span style="color:{point.color}">\u25CF</span> ',
                                   "{series.name}: <b>{point.y:,.0f}</b> pedidos<br/>")) |>
  hc_xAxis(title = list(text = "Categoría")) |>
  hc_yAxis(title = list(text = "Número de pedidos"),
           labels = list(format = "{value:,.0f}")) |>
  hc_legend(title = list(text = "Canal")) |>
  hc_title(text = "Pedidos por categoría y canal")
hc

g6 <- pedidos |>
  count(categoria, canal) |>
  ggplot(aes(categoria, n, fill = canal)) +
  geom_col(position = "dodge") +
  geom_text(aes(label = fmt_miles(n)),
            position = position_dodge(width = .9), vjust = -0.3, size = 3) +
  scale_fill_manual(values = colores_canal) +
  scale_y_continuous(labels = fmt_miles, expand = expansion(mult = c(0, .1))) +
  labs(title = "Pedidos por categoría y canal",
       x = "Categoría", y = "Número de pedidos", fill = "Canal") + tema
print(g6)
