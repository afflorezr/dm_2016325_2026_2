
# Comparador de precios: Ortopedia y rehabilitación (Taller 2)

Juan Pablo Lara Chaves · Minería de Datos (2016325) · UNAL

**App publicada:** https://zmo6al-juan0pablo-lara0chaves.shinyapps.io/comparador-ortopedia/

App Shiny sobre `comparador_precios.sqlite` que compara 8 productos equivalentes entre Farmatodo, Locatel y Ortopédicos Futuro. Incluye filtros, 7 indicadores calculados en SQL, 4 gráficos, tabla con descarga CSV, comparación de dos ejecuciones, canasta y botón de actualización por scraping.

## Ejecución local

```r
renv::restore()                 # instala las versiones de renv.lock
shiny::runApp()                 # desde taller_2/
```

Para reconstruir la base desde cero (reiniciar R, cerrar conexiones):

```r
file.remove("comparador_precios.sqlite")
source("preparar_base.R")
```

## Pruebas

```r
testthat::test_dir("tests/testthat")
```

7 pruebas: ahorro con empates, referencia con varias variantes, no duplicar ejecución, precio no positivo, cambios de precio con umbral, canasta incompleta y canasta vacía.

## Estructura

| Archivo | Contenido |
|---|---|
| `app.R` | App Shiny (bslib, highcharter, ExtendedTask, bindCache) |
| `scraper.R` | Recolección por plataforma, HTML crudo y modo sin conexión (`reprocesar_raw()`) |
| `procesamiento.R` | Limpieza, reglas y asignación de los 8 comparables |
| `db.R` | Esquema, vistas, inserción idempotente y consultas parametrizadas |
| `validacion.R` | Validación con pointblank (rechazos registrados por regla) |
| `preparar_base.R` | Arma la base desde cero |
| `raw/` | HTML crudo y CSV por comercio y fecha |
| `tests/` | Pruebas testthat |
| `diccionario_datos.md` | Tablas, columnas y vistas |

## Vistas

- `v_ultimo_precio`: último precio no descartado de cada anuncio.
- `v_cambios_precio`: variación de cada anuncio respecto a la observación anterior.
- `v_comparables`: observaciones de los 8 comparables con su ficha y precio unitario.
- `v_referencia`: una fila por comparable, comercio y ejecución; el precio es el máximo de las variantes (en Farmatodo, la más cara).

## Hallazgos (ejecución del 18-nov-2026)

1. **El Rhizo Forte de Locatel cuesta 142.150, 56 % más que en Farmatodo y Ortopédicos Futuro (91.050 en ambos).** Es la mayor brecha entre los 8 comparables.
2. **Farmatodo es el más barato en 5 de los 8 comparables** (uno empatado con Ortopédicos Futuro), aun tomando su variante más cara; Locatel lo es en 3 y Ortopédicos Futuro solo empata en uno.
3. **Ortopédicos Futuro es el más caro en las medias y pantimedias de compresión 8-15 y 15-20** (hasta 27 % sobre el más barato en la media de hombre 8-15). En la media de mujer 8-15 y la de hombre 20-30 los tres comercios difieren menos del 2 %.
4. **Entre el 17 y el 18-nov, cuatro productos maternos Anne Shantel de Locatel bajaron exactamente 30 %**, lo que sugiere una promoción de marca.

## Limitaciones

- Farmatodo se recolecta de forma parcial a propósito: se excluyó la categoría de muletas porque su `robots.txt` no lo permite.
- Ortopédicos Futuro quedó parcial el 16-nov por fallas de red (499 productos frente a 535 el 17-nov).
- Locatel no indica el sexo en la media de mujer 8-15; el diamante de Farmatodo es grande y el de Ortopédicos Futuro pequeño. Las equivalencias se verificaron página a página.
- En Farmatodo un mismo comparable tiene varias variantes (talla y color) con precios distintos; se usa la más cara como referencia.
- `n_registros` cuenta lo recolectado y `observaciones` solo lo que pasó la validación (el 18-nov: 2.072 recolectadas, 1.822 válidas, 250 rechazadas).
- Rechazos principales: precio ausente (Locatel: productos agotados; Ortopédicos Futuro y Farmatodo: filas sin precio publicado), anuncios repetidos dentro de la misma categoría y 23 fajas sin URL de Ortopédicos Futuro el 17-nov.
- La ejecución del 9-oct (Taller 1) no tiene copia cruda: se conserva con `con_raw = 0` y sus observaciones quedan descartadas (registrado en `correcciones`).

## Plataformas gratuitas

Los servidores gratuitos (por ejemplo shinyapps.io) no pueden hacer scraping de forma fiable: bloquean el navegador automatizado y limitan memoria y tiempo. En el despliegue se usa el **modo sin conexión**, que reprocesa el HTML guardado en `raw/`. El modo en línea solo funciona al ejecutar la app localmente.

## Declaración de uso de IA

Usé Claude (Anthropic) como asistente para escribir y depurar código en R (app Shiny, consultas SQL, pruebas) y redactar documentación. Las decisiones de diseño, la selección de los 8 comparables, la revisión de cada página de los comercios y la verificación de los resultados son mías. [Ajusta esta declaración a lo que pide el curso.]

