# Taller 2 — Comparador de precios (Cuidado y decoración de uñas)

**Minería de Datos 2026-2 · Universidad Nacional de Colombia · María Camila Herrera Cortés**

**Aplicación publicada:** <https://u05knv-maria0camila-herrera0cortes.shinyapps.io/parcial_02/>

Aplicación web en **Shiny (R)** construida sobre el comparador de precios del Taller 1. Consulta una base SQLite con precios de **Éxito, Jumbo y Olímpica**, la actualiza con web scraping y orienta al consumidor sobre dónde comprar un producto o una canasta de productos. Todo el proceso (scraping, acceso a datos, aplicación y pruebas) está en **R**.

**Nota sobre la versión publicada.** Las plataformas gratuitas no conservan los cambios en la base al reiniciarse la aplicación y los comercios suelen bloquear las consultas desde sus servidores. Por eso, en línea, el botón *Actualizar precios* informa el bloqueo y se usa el **modo sin conexión** (reprocesa las copias de `raw/`; la versión publicada incluye solo las dos ejecuciones más recientes de `raw/` por tamaño). La actualización en línea funciona al ejecutar la aplicación en un computador.

## Cómo ejecutarla localmente

Abrir la carpeta `parcial_02/` como proyecto de RStudio (o con ese directorio de trabajo) y ejecutar:

```r
renv::restore()      # instala las versiones fijas de renv.lock
shiny::runApp()      # abre la aplicación
```

## Cómo correr las pruebas

Desde `parcial_02/` (debe terminar en `FAIL 0`; son 108 verificaciones):

```r
Rscript -e 'testthat::test_dir("tests")'
```

Las pruebas usan datos pequeños o una base temporal; nunca la base entregada ni los sitios.

## Estructura de archivos

| Archivo | Contenido |
|---|---|
| `app.R` | Interfaz (bslib) y servidor de la aplicación. No contiene SQL. |
| `db.R` | Capa de acceso a datos: consultas parametrizadas, filtros, indicadores, canasta y comparación de ejecuciones, todo calculado en SQL. |
| `scraper.R` | Extracción (Taller 1) con tope de peticiones, pausas y agente de usuario identificable. |
| `limpieza_sqlite.R` | Limpieza, estandarización y carga a SQLite (una transacción por comercio). |
| `validacion.R` | Reglas que debe cumplir toda observación antes de insertarse. |
| `esquema_taller2.R` | Migración idempotente de la base: tablas, índices y vistas del Taller 2. |
| `actualizacion.R`, `mod_actualizar.R` | Botón de actualización en segundo plano (`ExtendedTask`), tolerancia a fallas, modo sin conexión y verificación del origen de los datos. |
| `graficos.R`, `colores.R` | Gráficos (highcharter) y colores de la aplicación. |
| `comparador_precios.sqlite` | Base de datos. |
| `diccionario_datos.md` | Descripción de cada tabla, vista y columna. |
| `raw/` | Copias crudas (JSON comprimido) de cada respuesta del scraping, por comercio y fecha. |
| `tests/` | Pruebas con `testthat`. |
| `renv.lock` | Dependencias con versiones fijas. |

## Datos y trazabilidad

Todos los datos provienen del scraping de las respuestas JSON que usan los propios sitios para mostrar sus productos. Cada observación se rastrea hasta su copia cruda en `raw/` y su ejecución en la tabla `ejecuciones`; la función `verificar_origen()` reprocesa una ejecución desde `raw/` y la compara con la base (**las 6 ejecuciones dieron coincidencia total**). Un dato ausente queda `NULL`.

| Ejecución | Fecha (Colombia) | Estado | Observaciones |
|---|---|---|---|
| `run_20261009_012911` | 9-oct-2026 01:29 | completa | 6.520 |
| `run_20261009_182726` | 9-oct-2026 18:27 | completa | 6.523 |
| `run_20261010_090740` | 10-oct-2026 09:07 | completa | 6.519 |
| `run_20261105_231034` | 5-nov-2026 23:10 | parcial (Éxito: 1 producto menos de los informados; Olímpica sin el comparable P06) | 6.523 |
| `run_20261105_234722` | 5-nov-2026 23:47 | completa | 6.524 |
| `run_20261109_125818` | 9-nov-2026 12:58 | completa (hecha con el botón de la aplicación) | 6.537 |

- **Corrección de la base del Taller 1** (tabla `correcciones`): Olímpica retiró el esmalte **P06** (Vitú gel tono 10 blanco 8 ml): la consulta por su EAN no devuelve resultados, no aparece en `raw/` desde el 5-nov y lo confirmé a mano en el sitio. P06 pasó a producto de reserva y **P09** (lima curva Freestyle, presente en los tres comercios en todas las ejecuciones) pasó a ser el octavo comparable principal.
- Dos ejecuciones quedaron incompletas (5-nov 23:53 y 9-nov 19:18; solo 1 y 8 de ~120 respuestas): **no entraron a la base** y sus copias no se incluyen en `raw/`.
- **Validación antes de insertar** (`validacion.R`): precio numérico y mayor que cero en productos disponibles (un agotado sin precio queda `NULL`), comercio, URL y fecha presentes, sin duplicados en la misma ejecución y presencia de los ocho comparables. Lo rechazado se registra con su motivo en `observaciones_rechazadas` (ninguna observación fue rechazada).

## Vistas SQL (las usa la aplicación directamente)

- `v_precios`: todas las observaciones vigentes con datos del anuncio, precio unitario y unidad normalizada (mL, g, unidad).
- `v_ultima_ejecucion`: por comercio, su ejecución completa más reciente.
- `v_ultimo_precio`: los precios de esa última ejecución (tabla de productos e indicadores por defecto).
- `v_cambios_precio`: cada observación frente a la anterior del mismo anuncio (variación en COP y %).
- `v_comparables`: los productos comparables con su precio unitario.
- `v_disponibilidad`: estado de cada anuncio en cada ejecución: *disponible*, *agotado según el sitio* o *no observado* (no se interpreta como agotado ni retirado).

## Scraping y modos de funcionamiento

La aplicación contempla tres modalidades de trabajo:

- **Actualización en línea:** consulta directamente los comercios Éxito, Jumbo y Olímpica mediante solicitudes HTTP a sus servicios de productos. Esta modalidad depende de que los comercios permitan las consultas desde el equipo o servidor que ejecuta la aplicación. Los sitios pueden restringir o bloquear las solicitudes automatizadas, por lo que no se garantiza que todas las actualizaciones sean exitosas.

- **Modo sin conexión:** permite reprocesar los archivos originales disponibles en `raw/` y cargar los resultados en una base de datos temporal, sin depender de nuevas consultas a los comercios. Es especialmente útil cuando las plataformas bloquean las solicitudes desde el servidor de publicación.

**Limitación de la aplicación publicada:** Shinyapps.io ejecuta la aplicación desde sus propios servidores, y los comercios pueden bloquear las solicitudes provenientes de estas plataformas. Cuando esto ocurre, la aplicación debe informar claramente que no fue posible realizar la actualización en línea, identificar el comercio y mostrar el motivo disponible, sin registrar precios no verificados. El usuario puede recurrir al modo sin conexión para consultar los datos previamente recolectados.

El modo sin conexión depende de que los archivos necesarios estén disponibles en `raw/`. Por tanto, no representa una actualización de precios en tiempo real.

## Gráfico de libre elección

**«Sobrecosto frente al comercio más barato»** (sección *Comparar comercios*). Responde la pregunta más práctica del consumidor: *¿en qué comercio conviene comprar cada producto y cuánto más caro es en los otros?* Para cada producto comparable muestra, en porcentaje, cuánto cuesta de más cada comercio frente al más barato (0 % = el más barato), lo que permite decidir de un vistazo sin comparar precios en pesos de productos muy distintos.

## Hallazgos

Periodo: 9-oct a 9-nov-2026. Ejecución de referencia: `run_20261109_125818` (9-nov, la última completa en los tres comercios). Todo se puede verificar en la aplicación.

1. **La promoción de octubre de Jumbo terminó y sus precios subieron.** El 10-oct (`run_20261010_090740`) el 53,3 % de los productos de Jumbo estaba en promoción; el 9-nov (`run_20261109_125818`) solo el 1,6 %. En 158 productos el precio de noviembre es exactamente 1,4286 veces el de octubre (el precio de octubre era el 70 % del de lista), incluidos cuatro comparables (P03, P04, P05 y P07, +42,9 %). *Dónde verlo:* **Cambios de precio** (anterior `run_20261010_090740` vs. actual `run_20261109_125818`) y **Resumen → promoción por comercio** (filtro «Una ejecución»).
2. **Ningún comercio gana en todo.** El 9-nov Jumbo es el más barato en 4 de los 10 productos comparables, Éxito en 3 y Olímpica en 3. *Dónde verlo:* **Comparar comercios → «Productos comparables en los que cada comercio es el más barato»**.
3. **Repartir la compra ahorra.** Para una unidad de cada uno de los 8 comparables principales la canasta cuesta $93.280 en Éxito, $90.220 en Jumbo y $92.500 en Olímpica; comprando cada producto donde es más barato cuesta **$85.100**, un ahorro de $5.120 (5,7 %) frente al mejor comercio único. *Dónde verlo:* **Canasta** (P01, P02, P03, P04, P05, P07, P08 y P09, ejecución `run_20261109_125818`).
4. **Las mayores diferencias:** el cortaúñas grande Freestyle (P08) cuesta $2.550 menos en Olímpica que en Éxito (19,9 %), y los tres removedores son más baratos en Jumbo: en el P03 (aloe vera, 60 ml) Éxito cobra ~30 % más por mL ($183,3 vs. $141,5). *Dónde verlo:* **Comparar comercios → ahorro por producto** y **precio por unidad (mL)**.
5. **Más anuncios no es más oferta disponible.** Éxito lista 3.005 anuncios pero solo 687 (23 %) figuran disponibles; el resto está agotado según el sitio. En Jumbo están disponibles 319 de 319 anuncios y en Olímpica 401 de 402. Además, Olímpica ya no vende P06. *Dónde verlo:* **Resumen → disponibilidad por comercio** y **Canasta** (elegir P06: Olímpica aparece «incompleta»).

Limitaciones: los precios son los del momento de la captura y no incluyen envío, mínimos de compra ni condiciones de las promociones. Los gráficos usan Highcharts (licencia gratuita para uso no comercial y educativo).

## Declaración de uso de inteligencia artificial

**Herramienta:** Claude, como asistente de programación y análisis, durante el taller.

**Para qué partes:** diseño y escritura del código R de la migración de la base (`esquema_taller2.R`), la validación (`validacion.R`), la capa de acceso a datos (`db.R`), la actualización en segundo plano y el modo sin conexión (`actualizacion.R`, `mod_actualizar.R`), la interfaz y los gráficos (`app.R`, `graficos.R`), las pruebas (`tests/`). 

**Mi trabajo:** El scraper y la limpieza vienen de mi Taller 1; solo se ajustaron (tope de peticiones, conversión de precios, filtro de copias crudas). Para este taller 2, ejecuté todo en mi computador comprobando posible errores e incovenientes presentados, realicé las nuevas ejecuciones del scraper, comprobé a mano en el sitio que Olímpica retiró P06 y decidí el reemplazo por P09, probé los botones y todas las secciones de la aplicación, y definí cambios de diseño (colores, filtros, tamaño de los gráficos, gráficos adicionales), realicé el diccionario de datos y la redacción de este README.

**Cómo se verificó el resultado:** 108 pruebas automáticas con `testthat`; `verificar_origen()` sobre las 6 ejecuciones (coinciden con `raw/`); comparación de indicadores, filtros, canasta y cambios de precio con consultas SQL independientes; revisión manual de la aplicación local y publicada. Soy responsable de todo el código entregado y puedo explicarlo.
