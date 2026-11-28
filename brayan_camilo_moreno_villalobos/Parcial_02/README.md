# Comparador de Precios - Alimentos para Mascotas (Colombia)

Aplicación web interactiva desarrollada en **R Shiny** para monitorear, homologar y comparar precios de alimentos para mascotas (perros y gatos) en tres grandes cadenas de retail en Colombia: **Éxito, Jumbo y Olímpica**.
🔗 **Aplicación en vivo (enlace):** [http://16h44d-bcmorenov.shinyapps.io/Comparador_de_Precios_Alimentos_para_Mascotas](http://16h44d-bcmorenov.shinyapps.io/Comparador_de_Precios_Alimentos_para_Mascotas)

---

## 1. Estructura del Proyecto

* `ui.R`: Interfaz de usuario construida con `bslib` (Bootstrap 5) y `highcharter`.
* `server.R`: Lógica reactiva, ejecución asíncrona del scraper (`promises` + `future`), cálculo de canasta óptima y renderizado de visualizaciones.
* `db.R`: Capa de acceso a datos SQLite, creación de vistas optimizadas, registro de auditoría (`correcciones`) y consultas SQL parametrizadas.
* `scraper.R`: Motor de extracción web con soporte para ejecución en vivo y modo sin conexión (`offline`).
* `comparador_precios.sqlite`: Base de datos relacional con el histórico de precios, productos homologados y ejecuciones.
* `tests/test_comparador.R`: Suite de pruebas unitarias automatizadas con `testthat`.
* `renv.lock`: Archivo de control de versiones de paquetes de R para reproducibilidad.

---

## 2. Arquitectura de Datos y Vistas SQL

El modelo relacional se apoya en tres vistas SQL principales definidas en `db.R` para garantizar rendimiento y trazabilidad:

1. **`v_comparables`**: Filtra exclusivamente los productos homologados (excluyendo marcas genéricas o sin identificar) que tienen presencia simultánea en los 3 supermercados (`HAVING COUNT(DISTINCT id_comercio) = 3`), asegurando comparaciones justas.
2. **`v_ultimo_precio`**: Extrae mediante una CTE (`UltimaEjecucion`) el precio de etiqueta y el precio por unidad (`precio_x_und`) más reciente de cada anuncio, eliminando cuellos de botella en consultas de visualización.
3. **`v_cambios_precio`**: Cruza la última ejecución contra la penúltima para calcular variaciones absolutas y porcentuales (`Subió`, `Bajó`, `Sin cambio`).

---

## 3. Justificación de Visualizaciones (Módulo 6)

* **Gráfico 1 (Evolución Temporal - Líneas)**: Permite rastrear la volatilidad histórica de un producto específico en cada supermercado.
* **Gráfico 2 (Precio Unitario - Barras)**: Normaliza el costo por gramo/unidad para identificar el verdadero ahorro independientemente del tamaño del empaque.
* **Gráfico 3 (Distribución de Categoría - Boxplot)**: Muestra mediana, cuartiles y valores extremos por supermercado para evaluar el posicionamiento de precios general.
* **Gráfico 4 (Participación de Marcas - Dona)**: Se seleccionó un gráfico de dona porque permite visualizar de manera inmediata la concentración del catálogo homologado por fabricante, complementando los análisis de precio con una perspectiva de oferta y surtido.

---

## 4. Tres Hallazgos Clave para el Consumidor

1. **Ahorro significativo mediante compra fragmentada (Canasta Óptima)**: Al combinar productos entre supermercados en lugar de comprar todo en un solo establecimiento, el consumidor logra un ahorro promedio cercano al **32.8%** entre el precio máximo y mínimo registrado.
2. **Dispersión de precios por presentación**: Las presentaciones de mayor gramaje (ej. 1.500 g a 4.000 g) presentan un costo unitario por gramo sustancialmente menor frente a sobres individuales (85 g - 100 g), aunque su precio de etiqueta incremente la dispersión superior en el diagrama de cajas.
3. **Diferencias de posicionamiento por cadena**: Aunque existen empates puntuales en referencias líderes (como Cat Chow y Dog Chow), **Jumbo** y **Olímpica** suelen alternar los precios mínimos en presentaciones medianas, mientras que **Éxito** presenta mayor amplitud entre su precio mínimo y máximo.

---

## 5. Pruebas Automatizadas y Reproducibilidad

Para ejecutar las pruebas unitarias localmente:
```r
testthat::test_dir("tests")
```
## 6. Declaración de Uso de Inteligencia Artificial

En cumplimiento con los lineamientos de transparencia académica, se declara el uso de un asistente de Inteligencia Artificial Generativa (**Gemini**) como herramienta de apoyo técnico, depuración y verificación durante el desarrollo de esta aplicación. 

El diseño de la arquitectura relacional, las reglas de homologación de productos, la lógica de negocio y la interpretación de los resultados fueron concebidos e implementados por el autor, empleando la IA específicamente como copiloto en las siguientes tareas puntuales:

* **Optimización y depuración de consultas SQL (`db.R`)**: Verificación de sintaxis en SQLite para la construcción de expresiones de tabla comunes (CTEs) y funciones de ventana (`ROW_NUMBER`), asegurando el cálculo eficiente de variaciones entre ejecuciones y evitando cuellos de botella en las vistas (`v_ultimo_precio`).
* **Soporte en renderizado y reactividad (`server.R` / `ui.R`)**: Resolución de conflictos de tipos de datos y estandarización de nombres de columnas en el renderizado dinámico de tablas (`DT`) y gráficos interactivos (`highcharter`), así como la estructuración de tareas asíncronas (`ExtendedTask` / `future`) para evitar el bloqueo de la interfaz.
* **Diagnóstico de despliegue en la nube (`shinyapps.io`)**: Análisis de registros del servidor (*logs*) para gestionar las restricciones de memoria y tiempos de espera de la capa gratuita, implementando controles preventivos y manejo de notificaciones en la interfaz.
* **Aseguramiento de calidad (`tests/`)**: Validación de casos borde y estructuración de pruebas unitarias automatizadas con `testthat`.

**Validación y dominio técnico:** Cada bloque de código sugerido o depurado fue auditado, adaptado e integrado manualmente por el autor, verificando su comportamiento real sobre la base de datos `comparador_precios.sqlite` y garantizando la capacidad plena para sustentar y explicar cada componente del sistema.