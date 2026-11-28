# Taller 2 · Comparador de precios de medicamentos respiratorios (Shiny)

Minería de Datos, Universidad Nacional de Colombia. Roger González Sánchez.

- **Lenguaje:** R. El scraping, el acceso a datos, la aplicación (Shiny + bslib) y las pruebas (testthat) están en R.
- **Categoría:** medicamentos para alergias y síntomas respiratorios (sin antiinfecciosos).
- **Comercios:** Farmatodo, Cruz Verde y La Rebaja, los mismos del Taller 1.

## Aplicación publicada

**https://ndb7gu-roger-gonzalez0sanchez.shinyapps.io/comparador_precios/**

La plataforma gratuita no conserva los cambios en la base cuando reinicia la aplicación: una actualización hecha en línea se pierde al reiniciar y la app vuelve a la base del repositorio. Además, los comercios pueden bloquear las peticiones que vienen de estos servidores; por eso, en la versión publicada el modo sin conexión viene activado. La actualización en línea funciona en la ejecución local.

## Qué se reutiliza del Taller 1

| Taller 1 | Uso en el Taller 2 |
|---|---|
| `scraper.R` y `R/00` a `R/07` | El botón *Actualizar precios* llama a `FUNCIONES_SCRAPE` (R/03), `filtrar_categoria_respiratorios()` (R/02), `crear_esquema()`, `registrar_ejecucion()` y `marcar_productos_comparables()` (R/06), y `candidatos_comparables()` (R/04). No se copiaron ni reescribieron dentro de la app. |
| `comparador_precios.sqlite` | Fuente de datos. Las tablas y columnas del Taller 1 se conservan; las corridas nuevas se agregan a la misma base. |
| `raw/` y modo sin conexión | El modo sin conexión de la app usa `cargar_raw_offline()` del Taller 1: relee los `manifiesto.jsonl` y conserva el id y la hora de la captura original. |
| Correspondencia de los 8 comparables | `productos_comunes` y el marcado `comparable` / `id_producto_comun`. |

Cambios frente al Taller 1:
- `R/00_configuracion.R`: se quitó una línea con un punto suelto (`.`) después de `REGEX_SUBCATEGORIA`, que hacía fallar `source("scraper.R")` con *object '.' not found*.
- La base gana dos tablas (`correcciones`, `observaciones_rechazadas`), la columna `observaciones.descartada`, contadores en `ejecuciones`, índices y seis vistas. Ver `diccionario_datos.md`.
- Correcciones de la retroalimentación: no corregí datos de la base. La única corrección fue de código: la línea con el punto suelto en `R/00_configuracion.R`, descrita arriba. Por eso la tabla `correcciones` existe pero está vacía.
## Estructura de archivos

```
taller_2/
├── global.R              carga paquetes, abre la conexión, prepara la base
├── ui.R                  interfaz (bslib), sin SQL
├── server.R              lógica reactiva, sin SQL
├── db.R                  capa de acceso a datos: todas las consultas de la app
├── actualizacion.R       botón de actualizar: llama al scraper, valida e inserta por comercio
├── validacion.R          reglas de validación (y pointblank) y validación de entradas
├── analisis.R            cálculo de la canasta
├── presentacion.R        formatos, colores por comercio y gráficos highcharter
├── scraper.R             scraper del Taller 1 (carga R/)
├── R/                    módulos del scraper del Taller 1 (Shiny no los carga solo: R/_disable_autoload.R)
├── sql/esquema_taller2.sql   tablas, índices y vistas del Taller 2
├── comparador_precios.sqlite
├── diccionario_datos.md
├── raw/                  copias crudas: raw/{farmatodo|cruzverde|larebaja}/{fecha}/ + manifiesto.jsonl
├── tests/                pruebas con testthat
├── renv.lock             versiones fijas de los paquetes
└── README.md
```

## Ejecutar localmente

Requisitos: R 4.4 o superior y RStudio.

1. Abrir `taller_2.Rproj` en RStudio (el directorio de trabajo queda en la carpeta del taller; no se usa `setwd()`).
2. Instalar los paquetes con las versiones del proyecto:
   ```r
   install.packages("renv")
   renv::restore()
   ```
3. Abrir `server.R` y pulsar **Run App**, o en la consola: `shiny::runApp()`.

## Pruebas

Desde la carpeta `taller_2/`:

```
Rscript -e 'testthat::test_dir("tests")'
```

Usan una base temporal creada con `crear_esquema()` y datos pequeños; no tocan `comparador_precios.sqlite` ni consultan los sitios (el scraper se reemplaza por una función que devuelve datos fijos).

| Archivo | Qué prueba |
|---|---|
| test_precios.R | precio en texto a número (`limpiar_precio`, `num1`); normalización del contenido (`extraer_contenido`) y de la unidad a mL, g o unidad (`v_observaciones`) |
| test_validacion.R | rechazo de precio ≤ 0, URL vacía, duplicados y filas sin copia cruda, con su motivo; columnas obligatorias; comparables faltantes; validación de la búsqueda |
| test_base.R | insertar dos veces la misma ejecución no duplica; detección de subidas, bajadas, nuevos y no observados; un comercio que falla no detiene a los demás; consultas parametrizadas |
| test_canasta.R | la canasta no se calcula si falta un producto (o está agotado); ahorro con empates |

## Actualización de precios

Página **Actualizar datos**, botón *Actualizar precios* (`actualizacion.R`):

1. Por cada comercio llama al scraper del Taller 1 y a su filtro de la categoría.
2. Corre en otro proceso de R (`ExtendedTask` + `future`); la app sigue respondiendo. Una corrida en línea tarda unos 4 minutos.
3. Registra la corrida en `ejecuciones`, valida cada observación e inserta solo las que no existen (`ON CONFLICT ... DO NOTHING` sobre la restricción única del Taller 1). Las rechazadas quedan en `observaciones_rechazadas`.
4. Si un comercio falla (error de red, bloqueo, cambio de estructura), sigue con los demás y lo deja `FALLIDA` o `PARCIAL` con el motivo. Lo de cada comercio se guarda en una sola transacción.
5. Marca los 8 comparables con el motor del Taller 1 y deja `PARCIAL` el comercio al que le falte alguno.
6. Muestra un resumen por comercio: recolectados, válidos, rechazados, insertados, nuevos, cambios de precio y no observados.
7. **Modo sin conexión:** reprocesa la última carpeta de `raw/` de cada comercio. Se registra como `RP_...`; las observaciones conservan la corrida original y, si ya estaban, no se duplican.
8. Al terminar se refrescan indicadores, gráficos y tablas sin reiniciar la app.

Buenas prácticas de scraping: agente de usuario identificable (`USER_AGENT` en R/00), pausa de 1,2 s entre peticiones y 3 s entre comercios, hasta 3 reintentos con espera, máximo 30 páginas por categoría (unas 40-45 peticiones por comercio), una sola actualización a la vez y mínimo 10 minutos entre actualizaciones en línea.

## Vistas SQL

| Vista | Para qué |
|---|---|
| `v_observaciones` | observaciones no descartadas con contenido y unidad normalizados, precio unitario y disponibilidad |
| `v_ultimo_precio` | último precio conocido de cada producto en cada comercio |
| `v_cambios_precio` | cambios de precio frente a la observación anterior del mismo producto |
| `v_comparables` | los 8 comparables en cada comercio y corrida, con estado `disponible`, `agotado`, `sin_dato` o `no_observado` |
| `v_disponibilidad` | estado de todos los productos conocidos en cada corrida |
| `v_ejecuciones` | una fila por corrida con su estado general |

## Seguridad

- No hay credenciales en el repositorio. `.Renviron` y `rsconnect/` están en `.gitignore`; la cuenta de shinyapps.io se configuró con `rsconnect::setAccountInfo()` en la consola.
- Toda consulta con valores del usuario usa marcadores `?` y `params`; para listas (`IN`) se generan solo los marcadores.
- La búsqueda se valida (máximo 60 caracteres; letras, números, espacios y `. , + & % ' / -`) y las opciones elegidas se comparan con las que existen en la base.
- Los enlaces de la tabla solo se muestran si empiezan por `http(s)` y se escapan.

## Gráfico de libre elección

**Pregunta:** ¿en qué farmacia está más barato cada uno de los 8 productos comparables?
**Por qué:** quien necesita un solo medicamento quiere saber a qué farmacia ir primero. El gráfico cuenta, en la corrida elegida, en cuántos comparables cada comercio tiene el precio más bajo; los empates cuentan para todos los empatados y los agotados no cuentan.

## Hallazgos

Comparo la ejecución del 14/11/2026 a las 22:51 (`EJ_20261114T225133`, hecha para este taller) con la del 11/10/2026 a las 02:42 (`EJ_20261011T024216`, del Taller 1). Las dos están completas en los tres comercios y con los 8 comparables. La app muestra por defecto la del 14/11, y la página *Cambios de precio* compara por defecto estas dos. Los precios son los del momento de la captura y no incluyen envío ni mínimos de compra.

1. **Cruz Verde pasó a ser la más barata en más productos.** El 14/11 tiene el precio más bajo en 4 de los 8 comparables (Afrin, Allegra, loratadina y Pax Noche), Farmatodo en 3 (Abrilar, Dolex Gripa y Fluimucil) y La Rebaja en 1 (Avamys). El 11/10 el reparto era La Rebaja 3, Farmatodo 3 y Cruz Verde 2. El cambio más grande fue el Allegra 120 mg x 10 en Cruz Verde: bajó de $72.000 a $48.420 (32,8 % menos) y pasó de ser el más caro de los tres comercios a ser el más barato. *Dónde verlo:* Gráficos → ¿Dónde conviene comprar?

2. **Cruz Verde está en temporada de promociones.** El 14/11 tiene en promoción 106 de sus 171 productos (62 %); el 11/10 tenía 40 de 169 (23,7 %). Entre las dos fechas le bajó el precio a 126 productos y se lo subió a 32. Farmatodo también subió sus promociones, de 7,1 % a 17,9 %, mientras que La Rebaja casi no se movió (de 4,6 % a 5,9 %) y dejó igual el precio de 293 de sus productos. En total, entre las dos fechas subieron 92 precios, bajaron 181, aparecieron 19 productos nuevos y 8 dejaron de verse. *Dónde verlo:* Cambios de precio (umbral 10 %) y la tarjeta "En promoción" del Resumen filtrando por comercio.

3. **Un genérico puede subir mucho de una medición a otra.** El aumento más fuerte fue el de la fexofenadina 120 mg x 10 genérica de Cruz Verde: pasó de $13.050 a $34.640 (165 % más). En cambio, Farmatodo bajó el Fluimucil 600 mg x 10 sobres de $32.950 a $24.713 (25 % menos) y quedó como la opción más barata de ese producto. Antes de comprar conviene mirar el precio del día y no el de la semana anterior. *Dónde verlo:* Cambios de precio, ordenando por la columna Variación.

4. **La canasta salió más barata que en octubre, y repartir la compra ahorra poco.** Con una unidad de cada uno de los 8 comparables, el 14/11 cuesta $217.660 en Farmatodo y $218.737 en Cruz Verde, apenas $1.077 de diferencia. En La Rebaja no se puede calcular porque el Fluimucil aparece agotado, igual que en las ejecuciones de octubre. Comprando cada producto donde es más barato se gastan $207.972, o sea $9.688 menos (4,5 %) que comprando todo en Farmatodo. Frente al 11/10, la canasta bajó $11.080 en Farmatodo (de $228.740) y $31.844 en Cruz Verde (de $250.581). Hay que tener en cuenta que Cruz Verde no informa si un producto está disponible y la app lo toma como disponible. *Dónde verlo:* Canasta, ejecución del 14/11, los 8 productos con cantidad 1.

### Cómo comprobar estos números con SQL

```sql
-- 1. En cuántos comparables es más barato cada comercio (14/11)
WITH d AS (SELECT id_producto_comun, comercio, precio_cop FROM v_comparables
           WHERE id_ejecucion = 'EJ_20261114T225133' AND precio_cop IS NOT NULL AND estado <> 'agotado'),
     m AS (SELECT id_producto_comun, MIN(precio_cop) AS minimo FROM d
           GROUP BY id_producto_comun HAVING COUNT(*) >= 2)
SELECT d.comercio, COUNT(*) AS veces
FROM d JOIN m ON m.id_producto_comun = d.id_producto_comun AND d.precio_cop = m.minimo
GROUP BY d.comercio;

-- 2. Productos en promoción por comercio en cada ejecución
SELECT id_ejecucion, comercio, COUNT(*) AS productos, SUM(es_promocion) AS en_promocion,
       ROUND(100.0 * AVG(es_promocion), 1) AS pct
FROM v_observaciones
WHERE id_ejecucion IN ('EJ_20261011T024216', 'EJ_20261114T225133')
GROUP BY id_ejecucion, comercio;

-- 2 y 3. Subidas y bajadas por comercio entre el 11/10 y el 14/11 (mismo producto)
SELECT b.comercio, SUM(b.precio_cop > a.precio_cop) AS suben, SUM(b.precio_cop < a.precio_cop) AS bajan
FROM v_observaciones b
JOIN v_observaciones a ON a.comercio = b.comercio AND a.sku_comercio = b.sku_comercio
                      AND a.id_ejecucion = 'EJ_20261011T024216'
WHERE b.id_ejecucion = 'EJ_20261114T225133'
GROUP BY b.comercio;

-- 4. Canasta: total por comercio y costo combinando (14/11, sin agotados)
SELECT comercio, SUM(precio_cop) AS total, SUM(estado = 'agotado') AS agotados
FROM v_comparables WHERE id_ejecucion = 'EJ_20261114T225133' GROUP BY comercio;

SELECT SUM(minimo) AS costo_minimo_combinando
FROM (SELECT MIN(precio_cop) AS minimo FROM v_comparables
      WHERE id_ejecucion = 'EJ_20261114T225133' AND precio_cop IS NOT NULL AND estado <> 'agotado'
      GROUP BY id_producto_comun);
```

## Declaración de uso de inteligencia artificial

- **Herramienta:** Claude (modelo de Anthropic).
- **Para qué la usé:** me ayudó a rectificar la aplicación Shiny, a conectar y corregir las consultas de `db.R` y las vistas SQL y validación del código en general.
- **Qué es mío:**, el botón de actualizar conectado con mi scraper del Taller 1, la canasta, los gráficos y las pruebas. el cálculo con SQL de los datos de los hallazgos, el diccionario de datos. La mayor parte del código de la aplicación.
- **Cómo verifiqué:** corrí las pruebas automáticas (`testthat::test_dir("tests")`, todas pasan), comparé los números de los hallazgos con consultas SQL directas sobre la base (las de arriba) y con lo que muestra la app publicada, y comprobé que cada observación tiene su copia en `raw/` y que la actualización funciona en línea y sin conexión.
