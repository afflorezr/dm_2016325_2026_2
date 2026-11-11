# Taller 2 · Comparador de precios de analgésicos y antiinflamatorios

**Asignatura:** Minería de Datos 
**Estudiante:** Andrea Catalina Mora Roa
**Lenguaje:** R. Scraping, acceso a datos, aplicación y pruebas están todos en R; la aplicación usa Shiny con bslib y highcharter.

**Aplicación publicada:** <https://01a1af59-29e3-011c-2c7e-a1e716dc5e37.share.connect.posit.cloud/> (Posit Connect Cloud)

La aplicación convierte el comparador del Taller 1 en una herramienta para el consumidor. Muestra dónde comprar un medicamento para el dolor o la inflamación, o una canasta de varios, en **La Rebaja**, **Droguerías Cafam** y **Locatel Colombia**. 
---

## Ejecutar localmente

Requisitos: R 4.3 o superior. La versión de cada paquete está fijada en `renv.lock`.

```r
# en R, con el directorio de trabajo en la carpeta taller_02
renv::restore()
shiny::runApp()
```

En la pestaña **Actualizar**, el botón *Actualizar precios* consulta los sitios (modo en línea) o reprocesa las copias de `raw/` (modo sin conexión). También se puede actualizar desde la consola:

```r
source("actualizacion.R")
actualizar_precios()                                         # en línea, los tres comercios
actualizar_precios(modo = "offline", ejecucion_raw = "20261105T235015")
```

## Pruebas

Desde la carpeta `taller_02`, con un solo comando:

```
Rscript -e 'testthat::test_dir("tests")'
```

Son 8 pruebas (45 verificaciones) y usan bases temporales y datos pequeños, nunca la base de la entrega ni los sitios. Cubren:

1. la conversión de precios en texto a número;
2. la normalización de contenido y unidades;
3. el cálculo del ahorro con empates;
4. que insertar dos veces la misma ejecución no duplica observaciones;
5. la detección de cambios de precio;
6. que la canasta no se calcula cuando falta un producto;
7. las reglas de validación;
8. la validación del texto de búsqueda y las consultas parametrizadas.

## Estructura de archivos

```
taller_02/
├── app.R                  interfaz y servidor Shiny (sin SQL)
├── graficos.R             gráficos highcharter y formato (COP, fechas, colores por comercio)
├── db.R                   capa de acceso a datos: consultas parametrizadas, filtros, indicadores, canasta
├── actualizacion.R        actualización: llama al scraper, valida, inserta por transacción, resume
├── scraper.R              extracción del Taller 1 (La Rebaja y Locatel por API VTEX; Cafam por HTML)
├── validacion.R           reglas de validación antes de insertar
├── limpieza.R             limpieza, clasificación y correspondencia del Taller 1 (con correcciones)
├── esquema.R              tablas, columnas, índices y vistas (idempotente)
├── migracion_taller2.R    paso único que llevó la base del Taller 1 a la estructura del Taller 2
├── comparador_precios.sqlite
├── diccionario_datos.md   significado, tipo, unidad y valores de cada tabla, vista y columna
├── raw/<comercio>/<ejecucion>/   copias crudas (.json.gz / .html.gz) e indice.csv con URL, hora y estado HTTP
├── tests/                 helper-base.R y test_precios.R (testthat)
├── renv.lock
└── README.md
```

Ningún archivo concentra la aplicación: la interfaz no contiene SQL, el scraper no escribe en la base y la validación está en un módulo propio. Todas las rutas son relativas y no se usa `setwd()`.

---

## Datos

### Origen
Todos los datos provienen del scraper entregado en el Taller 1 (`scraper.R`), ejecutado sobre los sitios de los comercios.
- **La Rebaja y Locatel:** la API pública de catálogo que usa el propio sitio (`/api/catalog_system/pub/products/search`).
- **Cafam:** el HTML de la categoría, del que se leen el estado `__STATE__` de VTEX IO y, como respaldo, el bloque `ld+json`.

Cada observación es trazable a su copia cruda en `raw/<comercio>/<ejecucion_id>/`. El archivo `indice.csv` de esa carpeta guarda la URL, la fecha y hora de la consulta y el estado HTTP.

### Ejecuciones en la base

| Ejecución | Fecha de captura | La Rebaja | Cafam | Locatel | Estado |
|---|---|---|---|---|---|
| `20261008T123757` | 8 oct 2026, 12:38–14:11 | 290 / 290 | 143 / 143 | 739 / 739 | completa |
| `20261105T235015` | 5 nov 2026, 23:50–23:54 | 288 / 288 | 196 / 196 | 724 / 724 | completa |
| `20261111T160714` | 11 nov 2026, 16:07–16:11 | 287 / 287 | 196 / 196 | 724 / 724 | completa |

*(productos recolectados / total que declara el sitio para la categoría; algunos productos tienen varios SKU, por eso hay más observaciones que productos)*

La segunda ejecución se capturó en línea con `scraper.R` en el computador de la estudiante. Luego se insertó desde sus copias de `raw/` con el flujo del Taller 2, de modo que cada fila pasó por la validación antes de entrar a la base. La tercera se hizo con el botón **Actualizar precios** de la aplicación, en modo en línea, también en el computador de la estudiante. Las tres ejecuciones incluyen los 8 productos de la canasta de referencia en los tres comercios. Hay 43 productos comparables en la primera, 44 en la segunda y 44 en la tercera.


### Validación antes de insertar (`validacion.R`)
Las reglas se escribieron de forma explícita, en base R:

| Regla | Qué verifica |
|---|---|
| `precio_positivo` | precio numérico y mayor que cero |
| `campos_presentes` | comercio, SKU, URL y fecha y hora presentes |
| `fecha_iso` | fecha y hora en ISO 8601 con zona |
| `moneda_cop` | moneda COP |
| `sin_duplicados` | un anuncio por ejecución |
| `canasta_referencia` | los 8 productos de referencia presentes con precio en el comercio |

Lo que no pasa no se inserta: queda en `rechazos` con el motivo, y el resultado de cada regla queda en `validaciones`. Además, el índice único `(ejecucion_id, anuncio_id)` impide insertar dos veces la misma observación.

### Disponibilidad
`observaciones.estado_disponibilidad` distingue `disponible` de `agotado` (según el sitio) y deja `sin dato` cuando el sitio no informa. La vista `v_disponibilidad` agrega `no observado` para los anuncios conocidos que no aparecieron en una ejecución, sin interpretarlos como agotados ni retirados.

### Vistas SQL que usa la aplicación
- **`v_observaciones`:** una fila por observación válida, con todo lo estandarizado y el precio por unidad. Sobre ella se calculan los filtros, la tabla, los indicadores y la distribución.
- **`v_ultimo_precio`:** la observación más reciente de cada anuncio.
- **`v_cambios_precio`:** precio de cada anuncio frente a su ejecución anterior, con el cambio en COP, el cambio en % y la dirección.
- **`v_comparables`:** productos comparables por comercio y ejecución, con contenido total, unidad normalizada y precio por unidad. Alimenta la evolución, el precio unitario, el ahorro y la canasta.
- **`v_disponibilidad`:** disponible, agotado, sin dato o no observado, por ejecución.
- **`v_resumen_ejecuciones`:** estado, total del sitio, observaciones válidas y rechazadas por ejecución y comercio.

El detalle de cada columna está en `diccionario_datos.md`.

---

## La aplicación

- **Filtros** (panel lateral, combinables):
  - comercio (selección múltiple);
  - ejecución o rango de fechas;
  - subcategoría y marca;
  - rango de precio;
  - solo promociones, solo comparables y solo productos de la categoría;
  - búsqueda en el nombre o en el texto original del anuncio.
- **Indicadores**, calculados en SQL; cada uno indica su unidad y su periodo o ejecución:
  1. productos y observaciones;
  2. fecha y estado de la última ejecución;
  3. porcentaje de observaciones en promoción;
  4. precio mediano, total y por subcategoría;
  5. ahorro máximo entre comercios para un mismo producto, con los empates;
  6. número de cambios de precio frente a la ejecución anterior.

  Una tabla adicional muestra los productos, la promoción y los agotados por comercio.
- **Gráficos interactivos** (highcharter). Cada comercio mantiene su color en toda la aplicación: La Rebaja naranja, Cafam azul, Locatel verde.
  1. Evolución del precio del producto comparable que elija el usuario, con una serie por comercio.
  2. Precio por unidad de contenido entre comercios. El usuario elige la unidad (unidad, mL o g) y nunca se mezclan unidades.
  3. Distribución de precios de la categoría por comercio. El mínimo, los cuartiles, la mediana y el máximo se calculan en SQL.
  4. **Gráfico libre:** *"¿Cuánto cuesta una tableta del mismo medicamento según la marca?"*, justificado abajo.
- **Tabla de productos filtrados**: comercio, nombre, marca, presentación, precio, precio unitario, promoción, disponibilidad, fecha de consulta y enlace. Se puede ordenar y buscar, y se descarga en CSV.
- **Cambios de precio.** Compara dos ejecuciones cualesquiera (por defecto las dos más recientes) sobre el mismo anuncio en el mismo comercio. Muestra:
  - lo que subió y lo que bajó, en COP y en %;
  - los productos nuevos y los que dejaron de observarse;
  - un umbral ajustable que resalta las variaciones grandes.
- **Canasta.** El usuario elige productos comparables y la cantidad de cada uno, con precios de una misma ejecución.
  - Calcula el total en cada comercio solo si el comercio tiene todos los productos; si falta alguno, lo indica.
  - Calcula el costo mínimo comprando cada producto donde es más barato y el ahorro frente al mejor comercio único.
  - Advierte que no incluye envío, mínimos de compra ni condiciones de las promociones.
- **Actualizar** (ver abajo), la lista de ejecuciones y la validación de cada una.
- La fecha de la última ejecución se muestra siempre en la barra superior. Los precios están en COP y las etiquetas en español. Cuando un filtro no devuelve datos aparece un mensaje claro en lugar de un gráfico vacío.

### Justificación del gráfico libre
Quien compra un analgésico suele elegir entre la marca conocida y un genérico sin saber cuánto cambia el precio. El gráfico toma un **mismo principio activo y una misma concentración** (por ejemplo, acetaminofén 500 mg). Muestra el **precio mínimo por tableta, cápsula o sobre de cada marca en cada comercio**, ordenado de la marca más barata a la más cara. Así responde de forma directa cuánto se paga de más por la marca y en qué comercio conviene. Usa todas las presentaciones sólidas de la categoría, no solo las comparables, porque los genéricos casi nunca están en los tres comercios con el mismo EAN.

### Actualización desde la aplicación
1. **Reutiliza el scraper del Taller 1.** El botón llama a `actualizar_precios()` (`actualizacion.R`), que llama a `recolectar_comercio()` de `scraper.R`. No lee archivos locales ni la base para presentarlos como una actualización.
2. **No bloquea la aplicación.** Corre como `ExtendedTask` en otro proceso (`future` y `promises`), con `input_task_button`. La aplicación consulta `log_actualizaciones` cada 2 s y muestra el avance por comercio.
3. **Registra la ejecución.** Crea una ejecución nueva, valida cada observación e inserta solo lo que no existe (`INSERT OR IGNORE` más el índice único).
4. **Tolera fallas.** Antes de recolectar prueba la conexión con el sitio. Si un comercio falla (red, bloqueo o cambio de estructura), registra esa ejecución como `fallida` o `parcial` con el motivo y continúa con los demás. Cada comercio se inserta en **una transacción**, de modo que una falla no deja la base a medias.
5. **Muestra un resumen por comercio:** productos recolectados, productos nuevos, observaciones insertadas, rechazadas, cambios de precio y no observados.
6. **Modo sin conexión.** Reprocesa las copias de `raw/` de la ejecución que se elija.
7. **Refresca la aplicación.** Al terminar, sube un contador de versión que invalida la caché (`bindCache`), y los indicadores, gráficos y tablas se actualizan sin reiniciar.

## Seguridad
- **Sin credenciales en el repositorio.** La cuenta de Posit Connect Cloud se vincula desde la consola con `rsconnect::connectCloudUser()`, que guarda el token en la configuración del usuario, fuera del proyecto. `.Renviron`, `.Rhistory`, `.RData` y `rsconnect/` están en `.gitignore`.
- **Consultas parametrizadas.** Todo valor del usuario va como parámetro `?`. En el texto SQL solo se insertan marcadores, incluidos los de las listas `IN (?, ?, …)` y los de la canasta `VALUES (?, ?)`. La búsqueda usa `LIKE ? ESCAPE '\'`.
- **Validación del texto de búsqueda.** Máximo 60 caracteres, y solo letras, números, espacios y `. , % / + -`. Si el texto no cumple, se muestra un aviso y se ignora.
- **Buenas prácticas de scraping.** El scraper cumple:
  - pausa de 3 s entre peticiones;
  - agente de usuario identificable (`TallerMineriaDatos-UNAL/1.0 (uso academico)`);
  - respeto del `robots.txt`;
  - reintentos con espera exponencial, sin reintentar los 4xx (no se eluden bloqueos);
  - tope de 120 peticiones por comercio y ejecución (la categoría completa usa unas 40).
- **Errores sin detalles técnicos:** `shiny.sanitize.errors = TRUE`.

## Consultas y acceso a datos
- `db.R` es independiente de la interfaz. Sus funciones reciben los filtros como argumentos y devuelven tablas.
- Filtros, indicadores, medianas, cuartiles, ahorros, cambios y canasta se calculan con SQL. La tabla completa nunca se lee para filtrarla en memoria.
- Los resultados se guardan en caché con `bindCache`, con los filtros y la versión de los datos como clave, y se invalidan al terminar una actualización.
- Cada proceso abre una sola conexión de lectura, que se cierra con `onStop`. La actualización abre la suya en el proceso de segundo plano y la cierra con `on.exit`.

## Despliegue
La aplicación está publicada en **Posit Connect Cloud** (enlace al inicio).
- Las plataformas gratuitas no conservan los cambios en la base al reiniciarse. Si la carpeta de la aplicación no admite escritura, la aplicación trabaja sobre una copia temporal de la base.
- Los comercios suelen bloquear las consultas desde servidores en la nube. Si el servidor no puede consultar los sitios, la aplicación lo informa con claridad, no modifica los datos y ofrece el modo sin conexión. En la prueba del 6 de noviembre de 2026, el servidor de Connect Cloud sí pudo consultar Cafam en línea (196 productos, ejecución completa); esa ejecución vive solo en el servidor hasta que este se reinicia.
- La actualización en línea funciona en la ejecución local.

---

## Hallazgos para el consumidor
*Se basan en las ejecuciones `20261008T123757` (8 oct 2026), `20261105T235015` (5 nov 2026) y `20261111T160714` (11 nov 2026). Todos se pueden verificar en la aplicación.*

1. **El comercio más barato depende del día: el 11 de noviembre Cafam lanzó una promoción en casi toda la categoría.**
   - El 98,8 % de sus observaciones de la categoría estaban en promoción, frente al 11,0 % del 5 de noviembre.
   - Bajó el precio de 143 anuncios, con una mediana de −10 %.
   - Con eso pasó del segundo al primer lugar. La canasta de los 44 productos comparables (una unidad de cada uno) costaba el 11 de noviembre:
     - Cafam: **$1.067.803**;
     - Locatel: $1.125.050;
     - La Rebaja: $1.178.950.
   - Cafam tiene el precio más bajo, o empata en él, en **29 de los 44** productos.
   - El 5 de noviembre el más barato era Locatel ($1.135.790).

   *(Pestañas Canasta y Cambios de precio, 05/11 → 11/11.)*
2. **Repartir la compra entre comercios ahorra poco.** Comprando cada producto donde es más barato, la canasta del 11 de noviembre baja a $1.046.765, apenas un 2,0 % menos que comprarlo todo en Cafam. *(Pestaña Canasta.)*
3. **En el último mes Locatel subió precios y La Rebaja fue la más estable.** Del 8 de octubre al 11 de noviembre, entre los anuncios de la categoría observados en ambas fechas:
   - Locatel: **94 subieron** y 19 bajaron, con una mediana de +3,9 %;
   - La Rebaja: **208 sin cambio**, 12 alzas y 7 bajas.

   *(Pestaña Cambios de precio, solo categoría.)*
4. **El genérico cuesta una fracción de la marca.** En acetaminofén 500 mg (11 nov):
   - la tableta más barata cuesta **$121,5** (genérico Best en Cafam);
   - la de Dolex cuesta **$722,25** en su mejor precio (Cafam), unas **6 veces más**;
   - la de Dolofen llega a $1.002,5 en Locatel.

   *(Pestaña ¿Marca o genérico?)*

Los precios son los del momento de la captura y no incluyen envío ni condiciones de las promociones.

---

## Declaración de uso de IA

**Herramienta:** Claude (Anthropic), usado como asistente conversacional con acceso a los archivos del proyecto.

**Para qué se usó:**
- Leer el enunciado y la entrega del Taller 1, y proponer un plan de trabajo.
- Revisión en código y visualización: Corrección de warning y cambio en el diseño base de la app, haciendola amigable.
- Redactar `diccionario_datos.md` y este README. Los hallazgos se calcularon con consultas a la base.

**Cómo se verificó el resultado:**
- Las 8 pruebas de `tests/` (45 verificaciones) pasan en mi computador.
- El reproceso sin conexión de `raw/` reproduce la ejecución del Taller 1 sin insertar observaciones nuevas, lo que confirma que los datos provienen de las copias crudas.
- Las cifras de los indicadores y de los hallazgos se compararon con consultas SQL independientes sobre la base.
- La aplicación publicada se probó en una ventana de incógnito: carga sin iniciar sesión y la actualización en línea de Cafam funcionó en el servidor.

