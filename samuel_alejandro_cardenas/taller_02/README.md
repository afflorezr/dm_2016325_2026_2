# Taller 2 - Comparador de precios de salud sexual

Minería de Datos (2016325) · R, Shiny y SQLite

**Aplicación:** https://samuelcardenas.shinyapps.io/comparador-salud-sexual/

## Proyecto

Continuación del Taller 1 con información de Cafam, Locatel y Cruz Verde. La aplicación permite buscar productos, comparar ocho presentaciones entre comercios, revisar precios por unidad y cambios entre fechas, y calcular el costo de una canasta. Incluye indicadores, gráficos y descarga del catálogo.

Los precios corresponden al momento de cada consulta, no necesariamente a los precios actuales de las tiendas.

## Datos

Se utilizan registros obtenidos por scraping y almacenados en SQLite, con sus respuestas originales en `raw/`. Las principales capturas para comparar fechas son:

| Fecha | Ejecución | Comercios |
| --- | --- | --- |
| 10/10/2026 | `20261010_084111` | Cafam, Locatel y Cruz Verde |
| 11/11/2026 | `20261111_144528` | Cafam, Locatel y Cruz Verde |

Los registros sin información de precio o disponibilidad no se completan artificialmente. La base conserva también ejecuciones parciales del 9 de octubre.

## Archivos

- `app.R`: interfaz, gráficos y canasta.
- `db.R`: consultas a SQLite.
- `scraper.R`: extracción de información de los comercios.
- `validacion.R` y `actualizacion_taller2.R`: validación, almacenamiento y actualización.
- `comparador_precios_taller2.sqlite`: base utilizada por la aplicación.
- `config/`: equivalencias entre los ocho productos comparables.
- `raw/`: respuestas originales de las consultas.
- `tests/`: pruebas automáticas.
- `diccionario_datos.md`: tablas, campos, tipos y unidades.
- `renv.lock`: dependencias de R.

## Ejecución

Desde la carpeta del proyecto, en RStudio:

```r
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::restore(prompt = FALSE)
shiny::runApp()
```

Para ejecutar las pruebas:

```r
testthat::test_dir("tests", reporter = "summary")
```

Se ejecutaron siete pruebas sin errores en RStudio y se revisó el estado de dependencias con `renv::status()`.

## Resultados y consideraciones

Las comparaciones usan capturas de fechas identificadas. En la canasta solo se muestra un total comprable cuando está confirmada la disponibilidad de todos los productos elegidos. La aplicación también permite consultar la procedencia de los registros.

Las ejecuciones registran las rutas consultadas; esto no equivale por sí solo a certificar la cobertura completa de la categoría. En shinyapps.io los cambios en SQLite pueden perderse al reiniciar la instancia, por lo que las actualizaciones permanentes se manejan en el entorno local.

## Uso de IA

Se utilizó ChatGPT como apoyo en el desarrollo y revisión de código R y SQL, las pruebas y la documentación. Se revisaron los resultados en RStudio y se contrastaron con los registros de SQLite y las capturas del scraper.
