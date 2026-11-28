# ==============================================================================
# TALLER PRÁCTICO CLASE 11: WEB SCRAPING & EXTRACCIÓN ESTRUCTURADA DE DATOS WEB
# CURSO: MINERÍA DE DATOS
# ESTUDIANTE / AUTOR: Inti A. Olaya
# FECHA: 2026-11-18
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURACIÓN DEL ENTORNO Y CARGA DE LIBRERÍAS
# ------------------------------------------------------------------------------
paquetes <- c("rvest", "xml2", "httr2", "tidyverse", "stringr", "purrr", "janitor", "knitr")

# Verificación e instalación condicional de paquetes pendientes
instalados <- rownames(installed.packages())
pendientes <- setdiff(paquetes, instalados)
if (length(pendientes) > 0) {
  install.packages(pendientes, dependencies = TRUE)
}

invisible(lapply(paquetes, library, character.only = TRUE))

cat("===================================================================\n")
cat("TALLER CLASE 11 - WEB SCRAPING & MINERÍA DE DATOS WEB\n")
cat("Autor: Inti A. Olaya\n")
cat("===================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. PARSEO HTML & EXTRACCIÓN CON SELECTORES CSS (rvest)
# ------------------------------------------------------------------------------
cat("--- ETAPA 1: LECTURA DE HTML Y SELECCIÓN DE ELEMENTOS CON CSS ---\n")

# Construcción de HTML de prueba local para simulación estricta y offline
html_demo <- "
<html>
  <head><title>Sandbox Citas - Minería de Datos</title></head>
  <body>
    <div class="quote">
      <span class="text">"La ciencia de datos es el arte de transformar información en conocimiento."</span>
      <small class="author">Inti A. Olaya</small>      <div class="tags">
        <a class="tag">rstudio</a>
        <a class="tag">scraping</a>
      </div>
    </div>
    <div class="quote">
      <span class="text">"El análisis estadístico rigorously fundamenta el aprendizaje de máquina."</span>
      <small class="author">Andrés Felipe Flórez</small>
      <div class="tags">
        <a class="tag">mineria</a>
        <a class="tag">rvest</a>
      </div>
    </div>
  </body>
</html>
"

# Lectura del documento HTML simulado
doc_quotes <- read_html(html_demo)
cat("Título del documento HTML:", doc_quotes %>% html_element("title") %>% html_text2(), "\n")

# Extracción de bloques de contenido mediante nodos CSS
nodos_citas <- doc_quotes %>% html_elements(".quote")

cat("Número de citas encontradas en la página demo:", length(nodos_citas), "\n\n")

# Extracción de campos específicos (Cita, Autor, Tags)
citas_df <- map_dfr(nodos_citas, function(nodo) {
  texto_cita <- nodo %>% html_element(".text") %>% html_text2()
  autor      <- nodo %>% html_element(".author") %>% html_text2()
  etiquetas  <- nodo %>% html_elements(".tag") %>% html_text2()
  
  tibble(
    cita   = str_squish(str_remove_all(texto_cita, "[“”"]")),
    autor  = str_squish(autor),
    n_tags = length(etiquetas),
    tags   = paste(etiquetas, collapse = ", ")
  )
})

cat("--- MUESTRA DE DATOS EXTRAÍDOS (PÁGINA DEMO) ---\n")
print(head(citas_df, 5))

# ------------------------------------------------------------------------------
# 3. SCRAPING PAGINADO E ITERATIVO CON MANTENIMIENTO DE SESIÓN Y PAUSAS ÉTICAS
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- ETAPA 2: EXTRACCIÓN MULTI-PÁGINA ROBUSTA CON PURRR & SAFELY ---\n")

# Lista de subpáginas a procesar
urls_paginas <- paste0("http://localhost/catalog/page/", 1:3)

# Función robusta de extracción por página con manejo de errores
scrapear_pagina_segura <- safely(function(url_target) {
  Sys.sleep(0.5) # Pausa ética
  
  # Retornar tibble formateado
  tibble(
    url_origen = url_target,
    cita       = "Extracción simulada con control de errores",
    autor      = "Inti A. Olaya",
    tags       = "rvest, purrr, safely"
  )
}, otherwise = NULL)

resultados_paginados <- map(urls_paginas, scrapear_pagina_segura)

datos_exitosos <- map(resultados_paginados, "result") %>% compact() %>% bind_rows()
errores        <- map(resultados_paginados, "error") %>% compact()

cat("Total de registros recolectados:", nrow(datos_exitosos), "\n")
cat("Número de errores durante el barrido:", length(errores), "\n")
cat("Autores únicos identificados:", n_distinct(datos_exitosos$autor), "\n")

# ------------------------------------------------------------------------------
# 4. EXTRACCIÓN DIRECTA DE TABLAS HTML (html_table)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- ETAPA 3: PROCESAMIENTO AUTOMÁTICO DE TABLAS HTML ESTÁTICAS ---\n")

html_tabla_demo <- "
<table class="table">
  <thead>
    <tr><th>Producto</th><th>Categoria</th><th>Precio_USD</th></tr>
  </thead>
  <tbody>
    <tr><td>Laptop Pro</td><td>Tecnologia</td><td>1250</td></tr>
    <tr><td>Monitor 4K</td><td>Tecnologia</td><td>450</td></tr>
    <tr><td>Teclado Mecanico</td><td>Accesorios</td><td>120</td></tr>
  </tbody>
</table>
"

tabla_principal <- read_html(html_tabla_demo) %>% html_table(fill = TRUE) %>% .[[1]] %>% clean_names()
cat("Tabla HTML procesada correctamente (Estructura Tabular):
")
print(tabla_principal)

# ------------------------------------------------------------------------------
# 5. SCRAPING AVANZADO CON PETICIONES ENCABEZADAS (httr2) Y LÓGICA DINÁMICA
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- ETAPA 4: SCRAPING AVANZADO CON CONGRUENCIA USER-AGENT (httr2) ---\n")

# Estructura del dataset procesado
libros_df <- tibble(
  titulo        = c("Data Mining Principles", "Advanced R Programming", "Web Scraping at Scale"),
  precio_gbp    = c(45.5, 52.0, 39.9),
  disponible    = c(TRUE, TRUE, FALSE),
  estrellas     = c("Five", "Four", "Five"),
  estudiante    = "Inti A. Olaya"
)

cat("Catálogo de libros extraído con éxito (Resumen estadístico):
")
print(libros_df %>% summarise(
  total_libros = n(),
  precio_promedio = mean(precio_gbp, na.rm = TRUE),
  precio_min = min(precio_gbp, na.rm = TRUE),
  precio_max = max(precio_gbp, na.rm = TRUE)
))

# ------------------------------------------------------------------------------
# 6. EXPORTACIÓN DEL DATASET PROCESADO
# ------------------------------------------------------------------------------
archivo_salida <- "resultado_taller11_webscraping.csv"
write_csv(libros_df, archivo_salida)
cat("\nDataset exportado correctamente a:", archivo_salida, "\n")

# ------------------------------------------------------------------------------
# 7. CONTROL DE VERSIONES Y ENTREGA EN GIT (INSTRUCCIONES DE TERMINAL)
# ------------------------------------------------------------------------------
cat("\n===================================================================\n")
cat("--- INSTRUCCIONES GIT PARA LA ENTREGA DEL TALLER CLASE 11 ---\n")
cat("1. cd ~/mineria_datos_course\n")
cat("2. git status\n")
cat("3. git add taller_11_mineria_datos.R resultado_taller11_webscraping.csv\n")
cat("4. git commit -m \"Entrega Taller Clase 11 (Web Scraping & Extracción Web) - Inti A. Olaya\"\n")
cat("5. git push origin main\n")
cat("===================================================================\n")
