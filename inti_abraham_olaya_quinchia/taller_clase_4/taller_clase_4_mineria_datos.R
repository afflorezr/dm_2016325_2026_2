# ==============================================================================
# TALLER DE MINERÍA DE DATOS - CLASE 4: VISUALIZACIÓN EXPLORATORIA & AVANZADA
# Autor: Inti A. Olaya
# Curso: Minería de Datos
# Herramientas: RStudio, ggplot2, plotly, highcharter, patchwork, knitr
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. INSTALACIÓN Y CARGA DE LIBRERÍAS REQUERIDAS
# ------------------------------------------------------------------------------
paquetes <- c("tidyverse", "patchwork", "plotly", "highcharter", "knitr", "kableExtra", "janitor")
instalados <- rownames(installed.packages())
pendientes <- setdiff(paquetes, instalados)

if (length(pendientes) > 0) {
  install.packages(pendientes)
}

invisible(lapply(paquetes, library, character.only = TRUE))

cat("=== Taller Clase 4 iniciado por Autor: Inti A. Olaya ===\n\n")

# ------------------------------------------------------------------------------
# 2. GENERACIÓN DE DATASET DE EJEMPLO (EMPLEADOS Y SALARIOS)
# ------------------------------------------------------------------------------
set.seed(2026)

n <- 250
empleados <- tibble(
  id = 1:n,
  nombre = paste("Empleado", 1:n),
  ciudad = sample(c("Bogotá", "Medellín", "Cali", "Barranquilla", "Bucaramanga"), n, replace = TRUE, prob = c(0.35, 0.25, 0.15, 0.15, 0.10)),
  sexo = sample(c("Femenino", "Masculino"), n, replace = TRUE),
  edad = round(rnorm(n, mean = 35, sd = 8)),
  experiencia = pmax(0, round(edad - 22 + rnorm(n, mean = 0, sd = 2))),
  salario = round(rnorm(n, mean = 4500000, sd = 1200000) + experiencia * 150000)
)

# ------------------------------------------------------------------------------
# 3. VISUALIZACIÓN ESTÁTICA Y COMPOSICIÓN CON GGPLOT2 Y PATCHWORK
# ------------------------------------------------------------------------------
# 3.1 Histograma con línea vertical de media salarial
p1 <- ggplot(empleados, aes(x = salario / 1e6)) +
  geom_histogram(bins = 25, fill = "#006DAE", color = "white", alpha = 0.85) +
  geom_vline(xintercept = mean(empleados$salario) / 1e6, color = "#b91c1c", linetype = "dashed", linewidth = 1) +
  labs(
    title = "Distribución Salarial",
    subtitle = "Línea punteada indica salario medio",
    x = "Salario (Millones COP)",
    y = "Frecuencia"
  ) +
  theme_minimal(base_size = 12)

# 3.2 Boxplot por Ciudad y Sexo
p2 <- ggplot(empleados, aes(x = reorder(ciudad, -salario, FUN = median), y = salario / 1e6, fill = sexo)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.7) +
  geom_jitter(position = position_jitterdodge(jitter.width = 0.15), alpha = 0.4, size = 1.2) +
  scale_fill_manual(values = c("Femenino" = "#e0245e", "Masculino" = "#1da1f2")) +
  labs(
    title = "Salarios por Ciudad y Sexo",
    x = "Ciudad",
    y = "Salario (Millones COP)",
    fill = "Sexo"
  ) +
  theme_minimal(base_size = 12)

# 3.3 Composición de gráficos usando Patchwork (Apilado y Lado a Lado)
panel_completo <- (p1 + p2) + 
  plot_annotation(
    title = "Panel de Exploración Salarial - Taller Clase 4",
    subtitle = "Autor: Inti A. Olaya",
    theme = theme(plot.title = element_text(size = 16, face = "bold"))
  )

print(panel_completo)

# ------------------------------------------------------------------------------
# 4. EXPLORACIÓN INTERACTIVA CON PLOTLY (GGPLOTLY)
# ------------------------------------------------------------------------------
# 4.1 Creación de Tooltip personalizado
empleados_plotly <- empleados %>%
  mutate(info_tooltip = paste0(
    "<b>", nombre, "</b><br>",
    "Ciudad: ", ciudad, "<br>",
    "Edad: ", edad, " años<br>",
    "Experiencia: ", experiencia, " años<br>",
    "Salario: $", format(salario, big.mark = ".")
  ))

p_scatter <- ggplot(empleados_plotly, aes(x = edad, y = salario / 1e6, color = ciudad, text = info_tooltip)) +
  geom_point(alpha = 0.7, size = 2.5) +
  scale_color_brewer(palette = "Set2") +
  labs(
    title = "Relación Edad vs. Salario por Ciudad",
    x = "Edad (Años)",
    y = "Salario (Millones COP)",
    color = "Ciudad"
  ) +
  theme_minimal(base_size = 12)

# Convertir a gráfico interactivo Plotly
g_interactivo <- ggplotly(p_scatter, tooltip = "text")

# ------------------------------------------------------------------------------
# 5. GRÁFICOS WEB PULIDOS CON HIGHCHARTER
# ------------------------------------------------------------------------------
# 5.1 Gráfico de Líneas de Ventas Mensuales (Series de Tiempo)
set.seed(42)
ventas_mes <- tibble(
  mes = seq(as.Date("2024-01-01"), by = "month", length.out = 12),
  ventas = round(rnorm(12, mean = 850, sd = 120))
)

hc_ventas <- hchart(ventas_mes, "line", hcaes(x = mes, y = ventas), name = "Ventas (COP)") %>%
  hc_title(text = "Evolución de Ventas Mensuales 2024") %>%
  hc_subtitle(text = "Taller Clase 4 - Highcharter Demo | Autor: Inti A. Olaya") %>%
  hc_xAxis(type = "datetime") %>%
  hc_yAxis(title = list(text = "Ventas (Millones COP)")) %>%
  hc_tooltip(pointFormat = "{point.x:%B %Y}: <b>${point.y}M COP</b>")

# ------------------------------------------------------------------------------
# 6. TABLAS RESUMEN EN FORMATO PUBLICACIÓN (KNITR / KABLE)
# ------------------------------------------------------------------------------
resumen_ciudad <- empleados %>%
  group_by(Ciudad = ciudad) %>%
  summarise(
    n = n(),
    `Media Salario` = mean(salario),
    `Mediana Salario` = median(salario),
    `Desv. Est.` = sd(salario),
    `CV (%)` = (sd(salario) / mean(salario)) * 100
  ) %>%
  arrange(desc(`Mediana Salario`))

print(knitr::kable(
  resumen_ciudad,
  digits = 1,
  caption = "Resumen Estadístico por Ciudad - Elaborado por Inti A. Olaya",
  format.args = list(big.mark = ".")
))

# ------------------------------------------------------------------------------
# 7. INSTRUCCIONES DE CONTROL DE VERSIONES (GIT EN RSTUDIO)
# ------------------------------------------------------------------------------
# Secuencia de comandos en la terminal de RStudio:
#
# git status
# git add taller_04_mineria_datos.R
# git commit -m "Entrega Taller Clase 4 - Inti A. Olaya"
# git push origin main
#
# ==============================================================================
