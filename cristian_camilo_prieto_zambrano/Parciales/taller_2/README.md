# Taller 2 — Comparador de precios: Nutrición clínica

**Asignatura:** Minería de Datos (2016325), Universidad Nacional de Colombia.
**Autor:** Cristian Camilo Prieto Zambrano.
**Lenguaje:** R, con una aplicación Shiny.

**Aplicación publicada:** <https://capri7a-comparador-nutricion.share.connect.posit.cloud>
(Posit Connect Cloud; ver la sección 8).

El Taller 2 convierte el comparador del Taller 1 en una aplicación: la misma
categoría (Nutrición clínica), los mismos tres comercios (Locatel, Cruz Verde y
Farmatodo) y los mismos 10 productos comparables (P01–P10). La base conserva el
historial de todas las ejecuciones; la aplicación permite consultarla, actualizarla y
comparar precios.

---

## 1. Cómo ejecutar localmente

**Requisitos:** R 4.4 o superior, con codificación UTF-8 (en Windows es la opción
por defecto desde R 4.2; en Linux y macOS, una configuración regional UTF-8). Todas
las rutas son relativas: el directorio de trabajo debe ser esta carpeta.

1. **Dependencias.** Al abrir R en esta carpeta (por ejemplo, con el proyecto de
   RStudio), renv se activa solo por el archivo `.Rprofile`. Luego se instalan las
   versiones fijas de `renv.lock`:

   ```r
   renv::restore()
   ```

2. **Credencial (solo para recolectar Farmatodo en línea).** Copiar
   `.Renviron.example` con el nombre `.Renviron` y completar
   `FARMATODO_ALGOLIA_KEY`; el archivo explica cómo obtener la clave. Después,
   reiniciar R. `.Renviron` está en `.gitignore`. Sin la clave, la aplicación funciona
   igual; solo la recolección en línea de Farmatodo queda registrada como fallida.

3. **Aplicación:**

   ```r
   shiny::runApp()
   ```

### Actualizar los precios

Desde la pestaña **Datos** de la aplicación:

* **En línea:** consulta los tres sitios y agrega una corrida nueva. Tarda unos
  minutos por las pausas entre solicitudes y corre en otro proceso, así que la
  aplicación se puede seguir usando. Al terminar, todas las pestañas se actualizan
  sin reiniciar. Para no sobrecargar los sitios, entre dos actualizaciones en línea
  debe pasar al menos una hora (cuenta cualquier intento, también los fallidos), y
  solo corre una actualización a la vez; si no se puede, la aplicación dice por qué
  y desde qué hora se puede.
* **Sin conexión:** reprocesa una corrida guardada en `raw/`. Si esa corrida ya está
  en la base, solo verifica que las copias crudas coincidan con lo guardado y no
  duplica nada.

También desde la consola:

```r
source("scraper.R")
ejecutar_recoleccion()                                                # en línea
ejecutar_recoleccion(offline = TRUE, corrida = "20261010T213019")     # sin conexión
```

### Revisar la base

```r
source("verificar_base.R")
```

Muestra la estructura, las ejecuciones, los comparables por corrida, los rechazos,
las correcciones y la trazabilidad con `raw/`, y termina con 13 comprobaciones.

## 2. Pruebas

Desde esta carpeta, con un solo comando:

```
Rscript -e "testthat::test_dir('tests')"
```

o, en la consola de R, `testthat::test_dir("tests")`. Resultado esperado:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 78 ]`.

Las pruebas no usan `comparador_precios.sqlite` ni consultan los sitios.
`tests/helper-base.R` crea una base temporal pequeña (3 comercios, 2 corridas, 3
comparables y algunos productos más) con las mismas funciones que usa la
actualización (`limpiar()`, `validar_observaciones()`, `guardar_ejecucion()`,
`aplicar_correspondencia()`), para que las pruebas recorran el código real de
escritura.

| Archivo | Qué verifica |
|-|-|
| `test-01-precios.R` | Conversión del precio de la respuesta a número: un precio 0, negativo, vacío o no numérico queda `NA`, nunca 0. |
| `test-02-unidades.R` | Normalización de unidades: kg, L, lb y oz a g o mL; punto de miles ("1.000 g"); nombres sin contenido; unidades por empaque. |
| `test-03-ahorro-empates.R` | Dos comercios empatados en el precio mínimo: ambos son el más barato, sin sobrecosto, y el ahorro se mide contra el más caro. |
| `test-04-sin-duplicados.R` | Insertar dos veces la misma ejecución no duplica observaciones ni rechazos; una corrida ya cargada se reconoce. |
| `test-05-cambios.R` | Cambios entre dos ejecuciones: subió, bajó, igual, nuevo, no observado y cambio de presentación (que no cuenta como cambio de precio); el umbral resalta solo lo que lo alcanza. |
| `test-06-canasta.R` | Un comercio al que le falta un producto no tiene total y se indica qué le falta; compra combinada; cantidades y códigos inválidos. |
| `test-07-seguridad.R` | La búsqueda rechaza caracteres no permitidos; un filtro con comillas se trata como texto, no como SQL. |
| `test-08-validacion.R` | La validación rechaza un precio negativo y una fila duplicada antes de insertar. |
| `test-09-limite-actualizacion.R` | Dentro de la hora siguiente a una actualización en línea no se consultan los sitios y se explica por qué; solo corre una actualización a la vez. |

**Sobre la prueba de precios.** Las APIs de los tres comercios entregan los precios
como números, no como texto con "$" y separadores. Por eso `limpiar_precio()` no
convierte texto: aplica la regla que sí se usa en los tres parsers (un precio 0 o
ausente significa "sin precio publicado" y queda `NA`), y la prueba verifica esa
regla.

## 3. Estructura de archivos

| Archivo o carpeta | Contenido |
|-|-|
| `app.R` | Interfaz y lógica reactiva de la aplicación. No contiene SQL. |
| `db.R` | Acceso a datos: estructura y migración de la base, escritura en transacciones, vistas y todas las consultas de la aplicación (parametrizadas). |
| `scraper.R` | Extracción de los tres comercios, limpieza y `ejecutar_recoleccion()`. La actualización de la aplicación reutiliza estas funciones. |
| `validacion.R` | Reglas de validación (pointblank) que se aplican antes de insertar. |
| `modulo_actualizacion.R` | Módulo Shiny del botón de actualización (tarea en segundo plano). |
| `tema.R`, `graficos.R`, `componentes.R` | Estética y formatos, los cuatro gráficos (highcharter) y las piezas HTML de la interfaz. |
| `correcciones_t1.R` | Corrección de la base del Taller 1, con cada cambio registrado en la tabla `correcciones`. |
| `verificar_base.R` | Informe de revisión de la base. |
| `comparador_precios.sqlite` | Base con el historial de ejecuciones. |
| `correspondencia.csv` | Asignación de P01–P10 al SKU de cada comercio. |
| `diccionario_datos.md` | Tablas, columnas, restricciones y vistas de la base. |
| `raw/<comercio>/<corrida>/` | Copias crudas de las respuestas (`.json.gz`) y totales de cada sitio (`totales.csv`). |
| `tests/` | Pruebas automáticas (sección 2). |
| `renv.lock`, `.Rprofile`, `renv/` | Dependencias con versiones fijas. |
| `manifest.json` | Archivos y paquetes de la aplicación publicada (sección 8). |
| `.Renviron.example` | Plantilla de la credencial. |

## 4. Base de datos

El detalle de cada tabla y columna está en `diccionario_datos.md`. En resumen:

* **Tablas del Taller 1:** `comercios`, `productos`, `anuncios`, `observaciones` y
  `ejecuciones`.
* **Tablas nuevas:** `correcciones` (cada cambio a un dato ya insertado, con valor
  anterior, valor nuevo y motivo) y `rechazos` (lo que no pasó la validación, con la
  regla y la fila completa).
* **Historial:** cada ejecución agrega observaciones y no sobrescribe las anteriores.
  `UNIQUE(id_anuncio, id_ejecucion)` impide duplicados.
* **Versión de la estructura** en `PRAGMA user_version` (versión 3). Al abrir una
  base anterior, `crear_base()` la migra.

### Vistas SQL

Se recrean cada vez que se abre la base, así siempre corresponden al código. Todas
usan solo observaciones válidas de anuncios de la categoría.

| Vista | Qué contiene | Dónde se usa |
|-|-|-|
| `v_ejecuciones` | Cada ejecución con su comercio, estado, modo, fecha, registros, total del sitio, observaciones válidas, rechazos y su orden. Marca la **vigente**: la más reciente de cada comercio que no falló. | Pestaña Datos, fecha de los datos, indicadores. |
| `v_observaciones` | Una fila por observación válida, con el anuncio, la presentación de esa consulta y el **precio unitario** (COP por g, mL o unidad, sin mezclar unidades). Base de las demás vistas. | Tabla de productos, distribución, indicadores. |
| `v_ultimo_precio` | El dato de la ejecución vigente de cada comercio. | Consulta directa del último precio de cada anuncio. La aplicación filtra la vigente sobre `v_observaciones`. |
| `v_comparables` | Precio de cada comparable en cada comercio y corrida, frente a los demás: mínimo, máximo, si es el más barato (los empates cuentan para todos), sobrecosto y ahorro máximo. `coincide = 0` si el comercio publicó otra presentación. | Tarjetas, cuadrícula, evolución, canasta, mayor ahorro. |
| `v_cambios_precio` | Cambios entre ejecuciones consecutivas del mismo comercio, sobre el mismo anuncio: subió, bajó, igual, nuevo, no observado o cambio de presentación, con la diferencia en COP y en %. | Indicador «Cambios de precio» del Resumen y resumen que muestra cada actualización. La pestaña Cambios de precio compara dos ejecuciones cualesquiera con las mismas reglas. |
| `v_disponibilidad` | Por ejecución, cada anuncio ya visto en ese comercio: disponible, agotado o no observado. Un producto no observado no se interpreta como agotado: se conserva su último precio y la fecha en que se vio. | Consulta de la disponibilidad en el tiempo. La aplicación muestra la disponibilidad de cada observación y los no observados en Cambios de precio. |

## 5. La aplicación

* **Filtros** (panel izquierdo): búsqueda por nombre, ejecución, comercios,
  subcategoría, marca, rango de precio, solo promociones y solo comparables.
* **Resumen:** siete indicadores (cada uno con su periodo o ejecución), tarjetas de
  comparación de los comparables, cuadrícula de precio por unidad y sobrecosto,
  distribución de precios por comercio y "¿Conviene comprar la presentación grande?".
* **Productos:** tabla filtrada, ordenable, con descarga en CSV.
* **Evolución:** precio de un comparable en el tiempo, una línea por comercio.
* **Cambios de precio:** dos ejecuciones elegidas (por defecto, las dos más
  recientes), con un umbral que resalta las variaciones grandes.
* **Canasta:** productos y cantidades; total por comercio solo si el comercio tiene
  todos, compra combinada y ahorro. No incluye envío, mínimos de compra ni condiciones
  de las promociones.
* **Datos:** actualización y registro de ejecuciones.

**Seguridad.** La credencial se lee de `.Renviron` (`Sys.getenv`), nunca del código.
Todas las consultas con datos del usuario son parametrizadas (`?`). La búsqueda solo
admite letras, números, espacios y `. + -`, con un largo máximo; las cantidades, las
ejecuciones y los códigos de producto se validan antes de consultar. El scraper se
identifica con un user-agent con dato de contacto, espera 1,5 s entre solicitudes, usa
un tiempo máximo de 30 s y hasta 3 reintentos. Desde la aplicación, que es pública, se
permite una actualización en línea por hora y una sola a la vez.

**Validación antes de insertar** (`validacion.R`): precio y precio de lista mayores que
cero o vacíos, campos obligatorios, fecha en ISO 8601, disponibilidad válida,
contenido positivo y sin duplicados por anuncio. Lo que no cumple va a `rechazos`.

## 6. Correcciones a la base del Taller 1

Ningún dato se borró: cada cambio quedó en la tabla `correcciones` con su motivo
(`correcciones_t1.R`).

* **Subcategoría de 10 anuncios.** Productos de la categoría que quedaban en "Otro
  (revisar)" o mal clasificados (Ketocal, Monogen, Glutament, Argiment, NutriAdvance,
  Renament, Proklein NET). Se agregaron sus reglas y se reclasificaron.
* **4 observaciones descartadas.** Entraron en el Taller 1 sin URL, antes de que
  existiera la validación. Se marcan como descartadas, no se borran.
* **Presentación por observación.** Un comercio puede reutilizar el SKU para otra
  presentación: en Locatel, el SKU 27148 era "Prowhey Renal Crónico X 400G" en octubre
  y "X 900G" en noviembre. Desde la versión 3, el contenido se guarda en cada
  observación, y el precio unitario y los cambios de precio usan el de esa consulta.

## 7. Hallazgos para el consumidor

Se basan en los 10 productos comparables (P01–P10) y en las tres corridas completas:
**10 oct 2026, 21:30** (ejecuciones 1–3), **10 nov 2026, 15:32** (ejecuciones 4–6) y
**14 nov 2026, 23:44** (ejecuciones 10–12). La corrida del 14 nov a las 21:17
(ejecuciones 7–9) no se usa porque Locatel quedó parcial. Salvo que se indique otra
cosa, las cifras son de la corrida del 14 nov, 23:44.

**1. Locatel tiene el precio más bajo en la mayoría de los productos, y eso se mantiene.**
Fue el más barato en 7 de los 10 comparables el 10 oct y en 8 de 10 el 10 nov y el
14 nov. Cruz Verde gana siempre en ProWhey DM líquido 200 mL. En ProWhey DM polvo
850 g, el más barato pasó de Cruz Verde a Farmatodo.
*Cómo verificarlo:* Resumen → «¿En qué comercio conviene cada producto?», eligiendo
cada corrida en el filtro **Ejecución** y contando las celdas «Mejor precio» de cada
comercio.

**2. Las diferencias grandes entre comercios vienen de las promociones.**
Las tres mayores diferencias son de productos en promoción en algún comercio:

* Diben Drink 200 mL: Cruz Verde cobra 53,9 % más que Locatel, que lo tiene en
  promoción.
* ProWhey DM polvo 850 g: Locatel cobra 24,8 % más que Farmatodo. Farmatodo y Cruz
  Verde lo tienen en promoción.
* ProWhey DM líquido 200 mL: 21,0 % de diferencia, con promoción en Cruz Verde.

En los otros siete, la diferencia entre el más caro y el más barato no pasa de 9,9 %,
y en cinco de ellos es menor de 6,5 %. Con los tamaños pasa lo mismo: comprar 850 g en
vez de 400 g ahorra entre 5,9 % y 7,9 % por gramo, salvo en ProWhey DM de Cruz Verde y
de Farmatodo (30,4 % y 28,9 %), donde el tamaño grande está en promoción.
*Cómo verificarlo:* Resumen → la cuadrícula, las tarjetas de comparación (píldora
«Promoción») y «¿Conviene comprar la presentación grande?».

**3. Comprar todo en el comercio que más veces gana no es lo más barato.**
Una canasta con una unidad de cada comparable cuesta $753.830 en Farmatodo, $771.950
en Cruz Verde y $776.155 en Locatel. Locatel, el más barato en 8 de los 10 productos,
tiene la canasta más cara. La razón es que el producto de mayor precio (ProWhey DM
polvo 850 g, $191.000 en Locatel) está en promoción en los otros dos. Comprando cada
producto donde es más barato, la canasta cuesta $735.485, $18.345 menos que en
Farmatodo. El 10 oct y el 10 nov la canasta más barata fue la de Cruz Verde, también
por sus promociones. En los productos de mayor precio conviene revisar las promociones
antes de elegir el comercio.
*Cómo verificarlo:* Canasta, con los 10 comparables en cantidad 1 y la corrida elegida
en el filtro **Ejecución**.

**4. Locatel y Farmatodo casi no cambian sus precios; lo que cambia son las
promociones.**
Entre el 10 oct y el 14 nov, Locatel mantuvo el precio de 91 de sus 117 productos y
Farmatodo el de 75 de 87. Cruz Verde, en cambio, modificó 43 de sus 46 productos.
Entre el 10 y el 14 nov ningún producto subió de precio y 24 bajaron (18 en Locatel,
4 en Farmatodo y 2 en Cruz Verde). Entre el 10 oct y el 14 nov hubo 4 subidas de
exactamente 42,9 % en Locatel y 3 de 25,0 % en Farmatodo: es lo que ocurre cuando
termina un descuento del 30 % (1/0,7 = 1,429) o del 20 % (1/0,8 = 1,25). Un precio
bajo por promoción puede desaparecer de una semana a otra.
*Cómo verificarlo:* Cambios de precio, comparando «10 nov 2026, 15:32» con
«14 nov 2026, 23:44», y luego «10 oct 2026, 21:30» con «14 nov 2026, 23:44».

**Alcance.** Los precios son los publicados en el momento de cada consulta. No incluyen
el precio Club de Cruz Verde para afiliados, los costos de envío, las compras mínimas
ni las condiciones de las promociones. Con tres corridas en cinco semanas, estos
hallazgos describen lo observado; no son tendencias.

## 8. Despliegue

**Enlace:** <https://capri7a-comparador-nutricion.share.connect.posit.cloud>

* **Plataforma:** Posit Connect Cloud, plan gratuito. Se eligió en lugar de
  shinyapps.io porque Posit está integrando shinyapps.io en Connect Cloud y porque el
  plan gratuito de Connect Cloud tiene variables secretas para la credencial.
* **Publicación desde el repositorio.** La aplicación se publica desde GitHub (rama
  `entrega-parcial-02`, archivo `cristian_camilo_prieto_zambrano/Parciales/taller_2/app.R`)
  con *Automatically publish on push*: cada push republica la aplicación, así que la
  versión publicada es la del repositorio. `manifest.json` lista los archivos y las
  versiones de los paquetes (tomadas de `renv.lock`); se genera con:

  ```r
  archivos <- rsconnect::listDeploymentFiles(".")
  archivos <- archivos[!grepl("^(\\.Renviron$|respaldo_|prueba_|renv/|tests/|\\.Rproj\\.user/)", archivos)]
  rsconnect::writeManifest(appFiles = archivos)
  ```

  y se vuelve a generar cada vez que cambia un archivo de la aplicación.
* **Credencial.** `FARMATODO_ALGOLIA_KEY` está configurada como variable secreta en
  la plataforma (*Settings → Variables*). No está en el código ni en el repositorio, y
  `.Renviron` no se publica.
* **Scraping desde el servidor.** En la prueba del 15 nov 2026 el servidor sí pudo
  consultar los tres sitios: la actualización en línea quedó completa en los tres
  comercios. Si en algún momento los comercios bloquean el servidor, la aplicación lo
  informa ("No fue posible consultar los sitios de los comercios desde este
  servidor…"), registra los intentos como ejecuciones fallidas con su motivo y remite
  al modo sin conexión, que funciona con las copias de `raw/` incluidas en la
  publicación.
* **La base no persiste.** El plan gratuito no conserva los cambios en la base al
  reiniciarse: una actualización hecha en la versión publicada se pierde en el
  siguiente reinicio, y la aplicación vuelve a la base del repositorio. La
  actualización en línea con datos que se conservan se hace en la ejecución local.
* **Arranque.** Si nadie la ha usado en un tiempo, la aplicación se suspende y tarda
  unos segundos en volver a cargar.

## 9. Limitaciones

* **Momento y lugar.** Los precios corresponden al momento de cada consulta y, en Cruz
  Verde, a la zona de inventario `COCV_zona64`.
* **Precios condicionados.** No se comparan el precio Club, los descuentos por
  cantidad ni el costo de envío.
* **Paginación de Locatel.** En la corrida del 14 nov a las 21:17, Locatel entregó 395
  de 398 productos: el catálogo cambió de orden mientras se recorrían las páginas y 3
  productos se repitieron en lugar de aparecer. La ejecución quedó como parcial, con
  ese motivo. Desde entonces las consultas piden un orden estable (`OrderByNameASC`), y
  la corrida siguiente quedó completa (398 de 398).
* **Clave de Farmatodo.** Es la clave pública de solo búsqueda que el sitio entrega a
  todos sus visitantes, no una credencial privada. Desde el Taller 2 se lee de
  `.Renviron`, pero en el Taller 1 estaba escrita en el código y sigue en el historial
  de git de esa entrega. No se puede revocar porque no es nuestra.
* **Delimitación de la categoría.** Se hace por reglas sobre el nombre; un nombre poco
  informativo puede quedar mal clasificado. Los 30 anuncios comparables se verificaron
  uno a uno.
* **Comparación.** Solo se compara cada presentación consigo misma. Un menor precio no
  indica que una fórmula pueda reemplazar a otra.
* **Pocas corridas.** Tres corridas completas en cinco semanas: los cambios de precio
  describen lo observado, no tendencias.

## 10. Declaración de uso de inteligencia artificial

En este taller se usó **Claude** (Anthropic), un asistente de inteligencia artificial.
No se usaron otras herramientas de IA.

**Para qué se usó:**

* escribir el código de los módulos nuevos: `db.R` (capa de acceso, vistas y
  migración), `validacion.R`, `modulo_actualizacion.R`, `app.R`, `tema.R`,
  `graficos.R`, `componentes.R`, `correcciones_t1.R`, `verificar_base.R` y las pruebas
  de `tests/`;
* los cambios a `scraper.R`: la lectura de la clave desde `.Renviron`, el orden estable
  de Locatel y `limpiar_precio()`;
* calcular las cifras de los hallazgos a partir de la base;
* redactar este README y el diccionario de datos;
* depurar errores.

**Decisiones del estudiante.** Claude propuso alternativas y el estudiante decidió:

* el alcance y el orden de trabajo de cada módulo;
* la estética de la aplicación: la referencia visual, los colores de cada comercio, el
  tema claro y la escala del mapa de calor;
* qué gráficos incluir;
* cómo corregir los datos del Taller 1;
* qué hallazgos incluir.

Del Taller 1 se conservan, sin IA, la elección de la categoría y de los comercios, las
secciones equivalentes de cada sitio y la selección de los productos comparables.

**Verificación.** El estudiante revisó todo lo que produjo Claude:

* el código, para entenderlo;
* la aplicación, pestaña por pestaña, con la base real. Reportó los errores que
  encontró y verificó su corrección;
* los resultados contra los sitios de los comercios;
* las cifras de los hallazgos en la aplicación;
* `verificar_base.R` (13 de 13 comprobaciones) y las pruebas automáticas (78 de 78);
* una actualización en línea real, en la ejecución local y en la versión publicada.
