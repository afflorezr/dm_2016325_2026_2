# Taller 2 — Comparador de precios: Primeros auxilios y curación

**Autor:** Johan Steven Avilan Peñaloza  
**Curso:** Minería de Datos (2016325)  
**Lenguaje:** R (Shiny). Todo el proceso —scraping, acceso a datos, aplicación y pruebas— está en R.

## Aplicación publicada

**https://1bat7z-johan-avilan.shinyapps.io/comparador-precios/**

La aplicación está en shinyapps.io. Dos advertencias sobre el entorno publicado:

- Las plataformas gratuitas **no conservan los cambios en la base** al reiniciarse la aplicación.
- Los comercios suelen **bloquear los servidores de despliegue**, y Farmatodo requiere un navegador automatizado (Chrome) que el servidor no tiene. Por eso la actualización en línea **funciona al ejecutar la aplicación localmente**; en el servidor la aplicación lo informa con un aviso y ofrece el **modo sin conexión**, que reprocesa las copias de `raw/`.

## Qué hace

Convierte el comparador del Taller 1 en una aplicación web que consulta la base SQLite, la actualiza mediante el scraper del Taller 1 y orienta al consumidor sobre dónde comprar un producto o una canasta en Farmatodo, La Rebaja y Locatel.

- **Resumen:** filtros combinables (comercio, subcategoría, marca, rango de precio, captura, solo promociones, solo comparables, búsqueda por palabras), seis indicadores calculados con SQL, cuatro gráficos interactivos (highcharter) y una tabla con descarga en CSV.
- **Cambios de precio:** compara dos capturas (por defecto las dos más recientes) con un umbral ajustable. Muestra productos que subieron, bajaron, nuevos y que dejaron de observarse.
- **Canasta:** costo de la canasta en cada comercio (solo si tiene todos los productos), costo mínimo comprando cada producto donde es más barato y ahorro frente a comprar todo en un solo comercio. No incluye envío, mínimos de compra ni condiciones de las promociones.
- **Actualización:** botón que ejecuta el scraper en segundo plano (`ExtendedTask`), valida e inserta por comercio con transacciones, tolera fallas y muestra un resumen por comercio. Modo sin conexión sobre `raw/`.

## Cómo ejecutarla localmente

Requiere R 4.1 o superior y, solo para la captura en línea de Farmatodo, Google Chrome.

1. Descomprima la carpeta `parcial_02` y ábrala como directorio de trabajo en RStudio (**Session → Set Working Directory → Choose Directory...**).
2. Restaure las dependencias con versiones fijas. Si `renv` indica que el proyecto no está activado, elija la opción 1 (*Activate the project and use the project library*):

   ```r
   renv::restore()
   ```

3. Inicie la aplicación:

   ```r
   shiny::runApp()
   ```

## Cómo correr las pruebas

Desde la carpeta `parcial_02/`, con un solo comando en la terminal:

```
Rscript -e "testthat::test_dir('tests')"
```

o, dentro de R: `testthat::test_dir("tests")`. Las pruebas usan datos pequeños y una base temporal; nunca la base de la entrega ni los sitios. Hay 16 pruebas (51 verificaciones) que cubren, entre otras, la conversión de precios a número, la normalización de unidades, el ahorro con empates, que insertar dos veces la misma ejecución no duplica observaciones, la detección de cambios de precio y que la canasta no se calcula cuando falta un producto.

## Estructura de archivos

```text
parcial_02/
├── app.R                       # Interfaz Shiny (bslib). No contiene SQL
├── db.R                        # Capa de acceso a datos: consultas parametrizadas, canasta, cambios
├── scraper.R                   # Extracción (Taller 1), validación previa, transacciones, resumen por comercio
├── validacion.R                # Reglas de validación antes de insertar
├── esquema.R                   # Migración del esquema: contenido normalizado, índices y vistas
├── comparador_precios.sqlite   # Base de datos
├── diccionario_datos.md        # Tablas, vistas y columnas
├── comparables.csv             # Correspondencia de los 8 productos (auditoría, Taller 1)
├── raw/                        # Copias crudas por comercio y captura
├── tests/                      # Pruebas testthat
├── renv.lock                   # Dependencias con versiones fijas
└── README.md
```

## Origen de los datos y trazabilidad

Todos los datos provienen del código de web scraping (`scraper.R`) ejecutado sobre los sitios de los comercios: Farmatodo con Chrome automatizado (`rvest::read_html_live`) y La Rebaja y Locatel con el servicio JSON de VTEX que usan sus propias páginas. Cada observación se rastrea hasta su copia cruda mediante `ejecuciones.ruta_raw` y su ejecución en la tabla `ejecuciones`. Un dato ausente queda `NULL`; no se digita, copia ni calcula ningún precio.

| Ejecución | Estado | Registros |
|---|---|---|
| `farmatodo_2026-10-10`, `larebaja_2026-10-10`, `locatel_2026-10-10` | completa | 161 / 168 / 375 |
| `farmatodo_2026-11-09`, `larebaja_2026-11-09`, `locatel_2026-11-09` | completa | 159 / 162 / 377 |
| `farmatodo_2026-11-12_113552` | **parcial** (no se capturó la subcategoría *curitas, algodones, adhesivos y botiquín*) | 80 |
| `larebaja_2026-11-12_113552`, `locatel_2026-11-12_113552` | completa | 161 / 377 |

Hay dos ejecuciones completas en los tres comercios, en fechas distintas (10 de octubre y 9 de noviembre de 2026), cada una con los ocho productos comparables en los tres comercios. **Las ejecuciones parciales o fallidas quedan registradas, pero no se usan para el estado actual ni para comparar precios.**

## Validación y correcciones

Antes de insertar, `validacion.R` comprueba: comercio, SKU, nombre, URL y fecha-hora presentes; precio numérico y mayor que cero (un precio ausente solo se acepta si el sitio marca el producto como agotado); y ausencia de duplicados en la ejecución. Lo que no supera la validación no se inserta y queda en la tabla `rechazadas` con su motivo. La presencia de los ocho comparables en cada comercio se verifica por ejecución; si falta alguno, la ejecución queda `parcial`.

La tabla `correcciones` registra los cambios sobre lo ya entregado, sin modificar en silencio el Taller 1: restitución de la hora de captura de las tres ejecuciones del 10 de octubre, el campo `modo` de las seis ejecuciones históricas, y la corrección del informe del Taller 1, que mencionaba ejecuciones del 7 y 9 de octubre que no existen (solo hay datos del 10 de octubre).

## Vistas SQL

| Vista | Uso |
|---|---|
| `v_ultimo_precio` | Estado actual: cada anuncio con su observación de la última ejecución completa de su comercio. Alimenta filtros, indicadores, gráficos y tabla. |
| `v_cambios_precio` | Compara las dos últimas ejecuciones completas de cada comercio (mismo anuncio, mismo comercio): subió, bajó, igual, nuevo, no observado. |
| `v_comparables` | Los ocho productos comparables con precio y precio por unidad normalizada. Alimenta evolución, precio por unidad y canasta. |
| `v_disponibilidad` | Disponible, agotado según el sitio o no observado, en la última ejecución completa. |
| `v_precios` | Histórico de observaciones; permite filtrar por captura. |
| `v_ejecuciones_orden`, `v_referencia` | Auxiliares: orden de las ejecuciones por comercio y fecha de referencia. |

El detalle de cada tabla, vista y columna está en `diccionario_datos.md`.

## Gráfico de libre elección

**¿En qué comercio es más probable encontrar el producto disponible?** Un precio bajo no sirve si el producto está agotado. El gráfico apila, por comercio, los anuncios disponibles, agotados según el sitio y no observados en la última ejecución completa.

## Hallazgos

Los hallazgos usan los precios publicados en los sitios al momento de cada captura y pueden verificarse en la aplicación.

1. **Farmatodo fue el más barato en los ocho productos comparables.** Periodo: captura del 9 de noviembre de 2026 (`farmatodo_2026-11-09`, `larebaja_2026-11-09`, `locatel_2026-11-09`). Comprar una unidad de cada uno cuesta COP 115.600 en Farmatodo, 142.000 en Locatel y 150.700 en La Rebaja: Farmatodo es 18,6 % más barato que Locatel y 23,3 % que La Rebaja. Como Farmatodo es el más barato en cada producto, repartir la compra entre comercios no ahorra nada frente a comprarla toda allí (antes de envío). *Verificación:* pestaña **Canasta**, los ocho productos, captura 2026-11-09.
2. **La mayor diferencia entre comercios está en las cintas de fijación y las curas Cure Band.** Misma captura. La cinta Fixo Roll Cure Band 10 cm × 2 m cuesta COP 33.560 en Farmatodo y 44.300 en La Rebaja (COP 10.740, 24,2 %; COP 16.780 contra 22.150 por metro). En porcentaje, la mayor brecha es la caja de curas Cure Band Standard × 10: COP 1.960 contra 3.500 (44,0 %). *Verificación:* **Resumen**, indicador «Ahorro máximo entre comercios» y gráfico de precio por unidad.
3. **La Rebaja tiene muchos más productos agotados.** Periodo: última ejecución completa de cada comercio (`larebaja_2026-11-12_113552`, `locatel_2026-11-12_113552` y `farmatodo_2026-11-09`). En La Rebaja 60 de 160 productos observados figuran agotados (37,5 %), en Locatel 19 de 304 (6,3 %) y en Farmatodo ninguno, aunque este sitio solo indica agotado cuando no publica precio y puede estar ocultando esos productos. *Verificación:* gráfico de disponibilidad en **Resumen**.
4. **Locatel bajó precios entre el 9 y el 12 de noviembre.** 131 de 304 productos bajaron y ninguno subió (`locatel_2026-11-09` frente a `locatel_2026-11-12_113552`). En Farmatodo, entre el 10 de octubre y el 9 de noviembre, 44 productos subieron y 2 bajaron. Parte de estos cambios puede deberse a campañas temporales de descuento y no al precio regular. *Verificación:* pestaña **Cambios de precio**, desmarcando los comercios que no interesen.

## Limitaciones

- Los precios son los del momento de cada captura y cambian con frecuencia; solo hay tres fechas, insuficientes para hablar de tendencias.
- La captura del 12 de noviembre de Farmatodo es parcial, por lo que la fecha de referencia de los comparables es el 9 de noviembre.
- Solo se comparan ocho productos idénticos en los tres comercios, seis de ellos de dos marcas (Cure Band y Nexcare). Las conclusiones valen para esos productos.
- Seis comparables son cintas vendidas por metros; se usa `m` como unidad normalizada, además de `mL` y `unidad`.
- Farmatodo no publica código de barras ni declara el total de productos; la equivalencia con los otros comercios se basa en marca, producto y medida del nombre.
- Los sitios se consultaron desde Bogotá; los precios pueden variar según la ciudad y entre el canal en línea y las tiendas físicas.
- Los resultados de la canasta no incluyen envío, mínimos de compra ni condiciones de las promociones.
- El indicador «Cambios de precio» agrega los cambios de la última comparación de cada comercio, que no cubren el mismo periodo (ver `v_cambios_precio`).

## Seguridad y buenas prácticas

- No hay credenciales en el repositorio; `.gitignore` excluye `.Renviron`, `rsconnect/` y archivos de sesión. El token de shinyapps.io se configuró en la consola con `rsconnect::setAccountInfo()`.
- Todas las consultas con valores del usuario son parametrizadas; los campos de texto se limpian (longitud máxima y caracteres permitidos) antes de usarse.
- El scraping respeta pausas entre peticiones, un agente de usuario identificable y un máximo de peticiones por ejecución.
- Rutas relativas; no se usa `setwd()` dentro del código.

## Declaración de uso de inteligencia artificial

Usé **Claude (Anthropic)** como asistente de programación durante todo el taller: para planear el trabajo por módulos, escribir y refactorizar el código R (scraper con ids únicos, validación y transacciones; migración del esquema con índices y vistas; capa de acceso `db.R`; aplicación Shiny con botón de actualización en segundo plano; pruebas `testthat`) y para redactar el diccionario de datos y este README.

Verifiqué el resultado ejecutando todo localmente: reproceso de `raw/` en modo sin conexión (sin duplicar observaciones), captura en línea, consulta de las vistas desde la consola, las 51 verificaciones de las pruebas automáticas, la aplicación en local y la aplicación publicada. Los errores que aparecieron al ejecutar (copia anidada de carpetas, sesión de R con una versión antigua del esquema, captura parcial de Farmatodo) los diagnostiqué y corregí.
