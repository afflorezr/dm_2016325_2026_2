# Taller 2 — Comparador de precios: Salud visual y lentes de contacto

**Autor:** Daniel Santiago Guzmán Villanueva

**Aplicación publicada:** <https://j1mh8v-daniel0santiago-guzman0villanueva.shinyapps.io/comparador-salud-visual/>

**Lenguaje:** R (≥ 4.2). Todo el proceso (scraping, validación, acceso a datos, aplicación y pruebas) está en R. La aplicación usa Shiny + bslib, con gráficos en highcharter.

**Categoría:** Salud visual y lentes de contacto. Incluye lentes de lectura, lentes de contacto, estuches y soluciones para la limpieza y conservación de lentes. Excluye medicamentos y lágrimas artificiales.

**Comercios:** Locatel, Farmatodo y Droguerías Colsubsidio. Son los mismos del Taller 1 y no cambió ninguno. La forma en que se identificó cada servicio está documentada en el encabezado de `scraper.R`.

## Estructura

```         
taller_2/
├── app.R                      interfaz Shiny (sin SQL)
├── db.R                       capa de acceso a datos: todas las consultas, parametrizadas
├── scraper.R                  extracción del Taller 1, ampliada (validación, fallas, transacciones)
├── validacion.R               reglas de validación antes de insertar
├── migracion.R                corrige la base del Taller 1 y crea el esquema del Taller 2 (una vez)
├── comparador_precios.sqlite  base de datos
├── diccionario_datos.md       tablas, vistas y columnas
├── raw/<comercio>/<ejecución>/ respuestas originales (.json.gz) + totales.json
├── tests/                     pruebas con testthat
├── renv.lock                  dependencias con versiones fijas
└── README.md
```

## Ejecución local

Desde la carpeta `taller_2/` (por ejemplo, abriendo el proyecto en RStudio):

``` r
install.packages("renv")
renv::restore()          # instala las versiones de renv.lock
shiny::runApp()          # abre la aplicación
```

La base que se entrega ya está migrada. Si se parte de la base del Taller 1, primero se ejecuta `source("migracion.R")`. Repetirlo no cambia nada.

**Actualizar precios.** En la pestaña *Actualizar precios*:

- **En línea**: llama a `ejecutar_recoleccion()` de `scraper.R`, consulta los tres sitios y agrega una ejecución nueva.
- **Sin conexión**: reprocesa una corrida guardada en `raw/`. No duplica observaciones, porque `observaciones` tiene la restricción `UNIQUE(comercio, sku, fecha_hora_consulta)` y la hora de consulta se toma del nombre de cada copia cruda.

La tarea corre en segundo plano (`ExtendedTask` + `future`), así que la aplicación sigue respondiendo mientras tanto. Al terminar muestra un resumen por comercio: recolectados, nuevos, cambios de precio, no observados y rechazados. Los indicadores se actualizan sin reiniciar la aplicación.

También se puede actualizar sin la aplicación:

``` r
source("scraper.R")
ejecutar_recoleccion()                                        # en línea
ejecutar_recoleccion(offline = TRUE, corrida = "20261115T185400")
```

## Pruebas

``` r
Rscript -e 'testthat::test_dir("tests")'
```

Hay 13 pruebas en 5 archivos (45 verificaciones). Cubren:

- la conversión de precios en texto a número;
- la normalización de unidades;
- las reglas de validación y el registro de rechazos;
- el estado `parcial` cuando falta un comparable;
- que insertar dos veces la misma ejecución no duplica;
- el ahorro con empates;
- la detección de cambios de precio;
- que la canasta no da total cuando falta un producto;
- la validación de texto y el uso de parámetros en el SQL.

Todas usan datos pequeños y una base temporal; nunca tocan la base de la entrega ni los sitios.

## Datos y validación

- **Origen.** Todos los datos salen de `scraper.R`. Cada observación tiene su `id_ejecucion` y su `fecha_hora_consulta`, que coincide con el nombre de su copia cruda en `raw/<comercio>/<id_ejecucion>/`.

- **Historial.** La base tiene dos ejecuciones completas en fechas distintas: `20261011T205340` (Taller 1) y `20261115T185400` (Taller 2).

- **Validación (`validacion.R`).** Las reglas están escritas de forma explícita en `REGLAS_VALIDACION`:

  - el precio debe ser numérico y mayor que cero;
  - deben estar presentes el comercio, el sku, la URL y la fecha ISO 8601;
  - no puede haber duplicados en la misma ejecución;
  - deben estar los productos comparables de cada comercio.

  Lo que no pasa la validación no se inserta y queda en `observaciones_rechazadas` con su motivo. Si falta un comparable, la ejecución de ese comercio queda `parcial`.

  Un precio ausente solo se acepta cuando el sitio marca el producto como agotado (Colsubsidio publica los agotados sin precio), y en ese caso queda `NULL`.

  Se usaron reglas propias en R en lugar de `pointblank` porque este depende de `gt` y `V8`, que complican el despliegue. Las reglas son las mismas que pide el enunciado.

- **Disponibilidad.** Se distinguen tres estados: `disponible` y `agotado` (según el sitio) en cada observación, y `no observado` en la vista `v_disponibilidad`. Un producto no observado no se interpreta como agotado.

- **Correcciones del Taller 1.** Están en la tabla `correcciones` y se ven en la pestaña *Calidad de los datos*:

  - el modo, inicio y fin de las ejecuciones del 11 de octubre, que el reproceso sin conexión había sobrescrito;
  - el contenido de un estuche y un kit de limpieza, que no tenía unidad;
  - una marca faltante (`Foster Gran`).

  No se borró ninguna observación. La retroalimentación del docente sobre el Taller 1 fue que faltaba `renv.lock`, que se agregó.

## Vistas SQL

| Vista | Qué devuelve | Uso en la app |
|------------------------|------------------------|------------------------|
| `v_observaciones` | Cada observación válida con su anuncio, producto común, disponibilidad y precio por unidad | Filtros, tabla, indicadores, distribución |
| `v_ultimo_precio` | El último precio de cada anuncio; `vigente = 1` si apareció en la última ejecución de su comercio | Consulta rápida del precio actual |
| `v_cambios_precio` | Cada observación frente a la anterior del mismo anuncio (`LAG`): cambio en COP, % y dirección | Indicador de cambios, resumen de actualización |
| `v_comparables` | Las presentaciones comparables (mismo `id_producto` en los tres comercios) con precio por mL, g o und | Evolución, precio unitario, ahorro, canasta |
| `v_disponibilidad` | Por ejecución y anuncio: disponible, agotado o no observado | Control de disponibilidad |

Hay índices sobre las columnas que usan los filtros: ejecución, fecha, precio, promoción, subcategoría, marca y comparable. El detalle de cada columna está en `diccionario_datos.md`.

## Gráfico de libre elección

**¿Cuánto me ahorro comprando cada presentación en el comercio más barato?** Es una barra por presentación comparable con el ahorro en COP frente al precio más alto. El color de la barra indica el comercio más barato (gris si hay empate) y la etiqueta muestra el porcentaje. Responde de un vistazo dónde comprar cada producto y si vale la pena cambiar de comercio por él.

## Seguridad

- No hay credenciales en el repositorio. La cuenta de shinyapps.io se configura en la consola con `rsconnect::setAccountInfo()`, nunca en un archivo del proyecto. `.Renviron` está en `.gitignore`.
- La clave de Algolia de `scraper.R` es la clave pública de solo búsqueda que Farmatodo entrega a cualquier visitante en su JavaScript; no es una credencial privada.
- Todas las consultas de `db.R` son parametrizadas. En el texto SQL solo se insertan marcadores `?`.
- La búsqueda admite como máximo 60 caracteres, y solo letras, números, espacios y `. , + - / & ( )`. Los valores de las listas se contrastan con los que existen en la base.
- La aplicación abre la base en modo de solo lectura. Solo la tarea de actualización escribe.
- Buenas prácticas de scraping: pausa de 1,5 s entre peticiones, agente de usuario que identifica el proyecto y un tope de 60 peticiones por comercio en cada ejecución (el uso normal es de unas 25 en total).

## Despliegue

La aplicación está publicada en shinyapps.io (enlace al inicio). Las plataformas gratuitas no conservan los cambios en la base cuando se reinician, así que una actualización hecha en la versión publicada se pierde en el siguiente reinicio.

Los comercios suelen bloquear las peticiones desde estos servidores. Si la actualización en línea falla en los tres comercios, la aplicación lo informa y ofrece el modo sin conexión. La actualización en línea funciona en la ejecución local.

## Hallazgos

Se basan en las ejecuciones `20261011T205340` (11 de octubre de 2026) y `20261115T185400` (15 de noviembre de 2026). Todo se puede verificar en la aplicación.

1.  **Droguerías Colsubsidio es el comercio más barato en 9 de las 10 presentaciones comparables** en la ejecución del 15 de noviembre. La excepción es Opti-Free PureMoist 90 mL, más barato en Locatel. En octubre ganaba en 6, con un empate triple en Opti-Free 120 mL. *Dónde verlo:* Resumen → gráfico de ahorro, eligiendo la ejecución en el panel lateral.
2.  **Los mayores ahorros están en ReNu 355 mL y en las gafas Foster Grant +1,50.** Comprar ReNu 355 mL en Colsubsidio (\$48.400) en lugar de Locatel o Farmatodo (\$61.350) ahorra \$12.950 (21,1 %). En las gafas el ahorro es de \$10.000 (25,1 %). *Dónde verlo:* indicador «Ahorro máximo entre comercios» y la canasta.
3.  **Entre octubre y noviembre cambió el precio de 11 de las 30 observaciones comparables.** Colsubsidio bajó 5 (por ejemplo, Opti-Free 120 mL bajó 8,2 %), mientras que Farmatodo subió Multi Solution Oxi 120 mL 10,7 % y Locatel la subió 10,1 %. Fuera de los comparables, Farmatodo subió 117 precios de la categoría, sobre todo gafas de lectura (+25 %). *Dónde verlo:* pestaña Cambios de precio (comparar 11-oct contra 15-nov, umbral 10 %).
4.  **El frasco grande no siempre es el más barato por mL.** En Colsubsidio, Opti-Free 300 mL cuesta \$344 por mL y el de 120 mL \$324 por mL, así que el frasco grande cuesta más por mL. En cambio, ReNu 355 mL (\$136/mL) sí es mucho más barato por mL que los de 120 mL (\$206/mL) y 60 mL (\$255/mL). *Dónde verlo:* Resumen → «Precio por unidad de contenido», unidad mL.

Los precios son los del momento de la consulta. No incluyen envío ni pedidos mínimos, y las promociones pueden haber cambiado desde entonces.

## Declaración de uso de inteligencia artificial

- **Herramienta:** Claude (Anthropic). De manera transversal e intensiva. Como la mayor guía en todo este proceso.
- **Para qué se usó:**
  - proponer la estructura de archivos;
  - redactar el código de `validacion.R`, `db.R`, `app.R`, `migracion.R` y las pruebas;
  - ampliar `scraper.R` (validación, tolerancia a fallas, límite de peticiones);
  - redactar el diccionario de datos y este README.
- **Cómo se verificó:**
  - se ejecutaron las pruebas (`testthat::test_dir("tests")`) y la aplicación localmente;
  - se compararon los indicadores con consultas directas a la base;
  - se revisaron las correcciones contra las copias crudas de `raw/`;
  - se probó la actualización en línea y sin conexión.
