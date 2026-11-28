# Taller 2 · Comparador de precios de perfumes

Aplicación web en Shiny (R) montada sobre el comparador del Taller 1. Consulta la base SQLite, la actualiza con el mismo scraper y ayuda a decidir dónde comprar un perfume, o una canasta de perfumes, entre La Riviera, Falabella y Farmatodo.

Aplicación publicada: https://ptt228-steven0david-alfonso0galindo.shinyapps.io/comparador-perfumes/

Todo está hecho en R (scraping, base de datos, aplicación y pruebas). La base tiene dos ejecuciones completas del scraper: la del 10/10/2026, que viene del Taller 1, y la del 10/11/2026.

## Cómo ejecutarla en otro computador

1. Abrir `app.R` en RStudio y fijar la carpeta de trabajo en `taller_2` con *Session → Set Working Directory → To Source File Location*.
2. Instalar las versiones exactas de los paquetes:
   ```r
   install.packages("renv")
   renv::restore()
   ```
3. Correr la aplicación:
   ```r
   shiny::runApp()
   ```

El botón **Actualizar precios** (pestaña *Actualizar*) tiene dos modos:

- En línea: consulta los tres sitios con `scraper.R` y agrega una ejecución nueva. Tarda unos 25 minutos y funciona en el computador local.
- Sin conexión: reprocesa las copias de `raw/` de la última ejecución, sin consultar los sitios.

La actualización corre en segundo plano (`ExtendedTask` con `future`), así que la aplicación se puede seguir usando mientras tanto.

## Pruebas

Desde la carpeta `taller_2`:

```r
Rscript -e 'testthat::test_dir("tests")'
```

Las pruebas usan datos pequeños y una base temporal, nunca la base de la entrega ni los sitios. Verifican la conversión de precios en texto a número, la normalización de unidades, el ahorro con empates, que insertar dos veces la misma ejecución no duplica observaciones, la detección de cambios de precio, que la canasta no se calcula cuando falta un producto, el rechazo de observaciones sin precio, que un rechazo no se anota dos veces, la búsqueda por nombre o marca y que una ejecución fallida no aparece en la aplicación.

## Estructura de archivos

| Archivo | Contenido |
|---|---|
| `app.R` | Interfaz (bslib) y servidor. No contiene SQL |
| `db.R` | Conexión y todas las consultas, con parámetros |
| `scraper.R` | Scraper del Taller 1. En el Taller 2 se agregó la disponibilidad de La Riviera y la validación antes de insertar |
| `validacion.R` | Reglas de pointblank y registro de rechazos |
| `procesamiento.R` | Estandarización, exclusiones y correspondencia con el catálogo (Taller 1, con las reglas corregidas) |
| `correcciones_t2.R`, `corregir_joyas.R`, `corregir_falabella.R`, `corregir_rechazos.R` | Scripts de corrección de la base. Cada uno deja registro en la tabla `correcciones` |
| `sql/esquema.sql` | Esquema del Taller 1 |
| `sql/migracion_t2.sql` | Tablas, columnas, índices y vistas del Taller 2 |
| `datos/catalogo_comparables.csv` | Catálogo de presentaciones comparables |
| `comparador_precios.sqlite` | Base de datos |
| `diccionario_datos.md` | Descripción de cada tabla, vista y columna |
| `raw/` | Copias crudas de cada consulta, por comercio y fecha, con su manifiesto |
| `tests/` | Pruebas con testthat |
| `renv.lock` | Versiones de los paquetes |

## Vistas SQL

| Vista | Para qué se usa |
|---|---|
| `v_ejecuciones` | Lista de ejecuciones con su fecha y cuántos comercios quedaron completos |
| `v_precios` | Observaciones válidas (sin excluidos ni descartados) con los campos de la tabla de la aplicación |
| `v_ultimo_precio` | Precios de la ejecución más reciente. Queda para consultas directas a la base; la aplicación filtra `v_precios` por la ejecución elegida |
| `v_comparables` | Presentaciones comparables con su precio por mL |
| `v_cambios_precio` | Cambio de precio de cada anuncio frente a la ejecución anterior, en COP y en % |
| `v_disponibilidad` | Disponible, agotado, sin dato o no observado, por anuncio y ejecución. Queda para consultas directas a la base; la aplicación no la consulta |

El detalle de cada columna está en `diccionario_datos.md`.

## Cambios frente al Taller 1

- **Retroalimentación del docente.** Se agregó `renv.lock`. Para verificar que Falabella y Farmatodo se recorrieron completos, la tabla `controles_completitud` guarda una comprobación calculada desde `raw/`. En Falabella se cuentan los productos distintos que suman los dos recorridos y se comparan con el total que informa el sitio: 2.999 de 3.000 el 10/10 (99,97 %) y 2.957 de 2.957 el 10/11 (100 %). En Farmatodo, que no informa un total, se comprueba que ningún tramo final de la búsqueda llega al tope de 80 resultados.
- **Correcciones.** Se corrigieron reglas de exclusión (accesorios, body mist, cremas, varias unidades, el "+" en nombres como "Musk+ Instinct" y Cherry Baby) y se leyó la disponibilidad de La Riviera desde las copias crudas. Al revisar la aplicación se encontraron además 24 joyas de Falabella (collares, dijes y charms) dentro de la categoría, que se excluyeron con `corregir_joyas.R`. Cada cambio quedó en la tabla `correcciones` con su motivo. No se borró ninguna observación.
- **Variantes repetidas en Falabella.** Falabella identifica cada anuncio por su variante, y el listado muestra una variante u otra del mismo producto según el orden del recorrido. Por eso había productos dos veces en la misma ejecución (101 el 10/10 y 105 el 10/11), y una primera versión del control de completitud, que contaba variantes, daba más productos que los que informa el sitio. `corregir_falabella.R` marca la observación repetida como descartada, sin borrarla, y recalcula el control contando productos. El scraper no se modificó, así que después de una ejecución nueva hay que volver a correr ese script.
- **Disponibilidad.** La Riviera indica si un producto está agotado (7 anuncios el 10/11). Esos anuncios no muestran precio, así que quedan guardados en la base pero no aparecen en la aplicación, que solo lista productos con precio. En Farmatodo la consulta trae únicamente los productos que el sitio tiene visibles, y todos quedan como "disponible". Falabella no lo indica en el listado, así que sus productos quedan como "sin dato". Un producto que no aparece en una ejecución no se marca como agotado: en la base queda como "no observado" (vista `v_disponibilidad`) y en la pestaña *Cambios de precio* aparece como "Dejó de observarse".

## Despliegue

La aplicación está publicada en shinyapps.io. Las credenciales se configuraron en la consola con `rsconnect::setAccountInfo()` y no están en ningún archivo del proyecto.

En la plataforma gratuita los cambios en la base no se conservan cuando el servidor se reinicia, y los comercios suelen bloquear las consultas desde servidores en la nube. Por eso, en la versión publicada, la actualización en línea puede fallar: la aplicación lo informa y ofrece el modo sin conexión. La actualización en línea funciona en la ejecución local.

## Gráfico de libre elección

Pregunta: ¿en qué comercio está el menor precio más veces?

Los otros gráficos muestran un perfume a la vez. Este sirve para algo anterior: si uno solo va a mirar un sitio, saber por cuál empezar. Está en la pestaña *Resumen*.

Se calcula con las presentaciones comparables de la ejecución elegida (mismo perfume, misma concentración y mismo tamaño, con precio en los tres comercios). Para cada una se busca el precio más bajo y se anota qué comercio lo tiene; la barra de cada comercio es ese conteo. Si dos comercios empatan, la presentación cuenta para ambos, y por eso las barras pueden sumar más que el total de presentaciones. Si un comercio tiene varios anuncios de la misma presentación se usa el más barato.

Solo cambia con la ejecución, no con los demás filtros, y usa las comparables (21 el 10/11/2026), no toda la categoría.

## Hallazgos

Datos de dos ejecuciones completas en los tres comercios: 10/10/2026 (`20261010T210722`) y 10/11/2026 (`20261110T180740`). Precios en pesos colombianos. Las comparaciones entre comercios se hacen con las presentaciones comparables, que fueron 24 en octubre y 21 en noviembre.

**1. Falabella es el más barato casi siempre.** En noviembre tuvo el menor precio, solo o empatado, en 17 de las 21 presentaciones; Farmatodo en 6 y La Riviera en 5. En octubre fue igual de claro: 20 de 24, contra 10 y 6. Se ve en el gráfico de libre elección del *Resumen*, cambiando la ejecución.

**2. Comparar vale la pena en unas marcas y en otras no.** En Versace y Tommy Hilfiger los tres comercios cobran prácticamente lo mismo: en las siete presentaciones de noviembre la diferencia máxima es de $40.000, y en cuatro no llega a $100. En cambio, en las marcas árabes (Armaf, Afnan, Ahmed Al Maghribi, Swiss Arabian, French Avenue, Rayhaan) 9 de las 11 presentaciones tienen más de $90.000 de diferencia. El caso extremo es Armaf Club de Nuit Iconic EDP 105 mL, que costaba $324.350 en Falabella y $655.000 en La Riviera. Todo esto está en la tabla "Diferencia de precio entre comercios" de la pestaña *Comparar*.

**3. Los precios se mueven sobre todo en Falabella.** Entre las dos fechas cambió el precio de 607 de los 3.202 anuncios que aparecen en ambas (325 bajaron, 282 subieron). De esos cambios, 507 son de Falabella, que movió el 24 % de sus anuncios; La Riviera movió el 13 % (97) y Farmatodo casi nada (3). En las comparables solo hubo cinco cambios, todos bajas. La mayor fue Afnan Kiaana Angel EDP 100 mL en La Riviera, de $599.900 a $280.000, que dejó a La Riviera como la más barata en esa presentación. Pestaña *Cambios de precio*, filtrando por comercio o marcando "Solo comparables".

**4. Las promociones también se concentran en Falabella.** En noviembre estaba en promoción el 31,2 % de la categoría (28,6 % en octubre), pero el reparto es muy desigual: 41,5 % en Falabella (960 de 2.311 productos), 16,1 % en La Riviera (120 de 746) y cero en Farmatodo, cuyo listado no mostró precios de oferta en ninguna de las dos fechas. El total está en el indicador del *Resumen*; por comercio se ve en *Productos* con "Solo promociones".

Hay que leer esto con dos límites. Son solo dos fechas, así que describen un mes, no una tendencia. Y las comparables son 21 de 3.458 productos, elegidas porque están en los tres comercios, así que no representan toda la categoría. Los precios no incluyen envío ni las condiciones de cada promoción.

## Uso de IA

En este taller se usó Claude (Anthropic) durante todo el trabajo.

**Para qué se usó**

- Revisión y retroalimentación de la planeación del taller.
- Retroalimentación del Taller 1 y los archivos de clase.
- Escribir la mayor parte del código nuevo.
- Encontrar y corregir errores que aparecieron al correr la aplicación: el argumento de pointblank que no existía en la versión instalada, los gráficos que no se veían bien, el filtro de precio que no se aplicaba en Cambios de precio y las reglas de exclusión.
- Diseñar la verificación de completitud de Falabella y Farmatodo, que responde a la retroalimentación dada en el taller 1.
- Redactar el diccionario de datos.
- Mejorar la redacción y corregir la ortografía de los textos, incluido este documento.
- Revisar el proyecto terminado contra la base y las copias de `raw/`.

**Qué hice yo**

- Planeación del taller.
- Correr el scraper y todos los scripts en mi computador, y revisar cada resultado antes de seguir.
- Recorrer la aplicación pestaña por pestaña y reportar lo que estaba mal. Así se encontraron, por ejemplo, las joyas de Falabella dentro de la categoría de perfumes y los problemas de los gráficos.
- Decidir qué se corregía y cómo se presentaba la aplicación.
- Hacer ajustes puntuales en el código durante el desarrollo.
- Comprobé en la aplicación cada cifra de los hallazgos antes de dejarla en el README.
- Hice la revisión final del README.

**Cómo se verificó**

- Las 12 pruebas de `tests/` pasan.
- Las dos ejecuciones se cargaron y se reprocesaron desde `raw/`. En Falabella el número de productos se comparó con el total que informa el sitio; en Farmatodo, que no informa un total, se comprobó que ningún tramo de la búsqueda llegara al tope de resultados.
- Las correcciones a la base quedaron en la tabla `correcciones`, y no se borró ninguna observación.
- Las cifras de los hallazgos se comprobaron en la aplicación y en la base.
