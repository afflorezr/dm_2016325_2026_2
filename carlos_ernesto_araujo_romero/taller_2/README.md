# Comparador de precios de confitería — Taller 2

**Curso:** Minería de Datos (2016325) — Universidad Nacional de Colombia, sede Bogotá  
**Estudiante:** Carlos Ernesto Araujo Romero  
**Lenguaje:** R 4.3.3  
**Categoría:** confitería (chocolates, chocolate de mesa, caramelos, gomitas, chicles y mentas)  
**Comercios activos:** Carulla, Jumbo y Olímpica  
**Aplicación publicada:** <https://01a1d0a7-6ccf-190d-8d9e-288697a8dfdc.share.connect.posit.cloud/> (Posit Connect Cloud)  
**Base:** `comparador_precios.sqlite`  
**Documento del Taller 1:** `../Taller_Parcial1/Taller_Parcial1/taller_1.html`

---

## 1. Qué hace la aplicación

Convierte el comparador del Taller 1 en una aplicación web que:

* consulta la base SQLite y muestra la oferta de la categoría con filtros
  combinables (comercio, subcategoría, marca, precio, promoción, comparables y
  búsqueda por texto);
* calcula ocho indicadores con SQL (presentaciones comparables, observaciones,
  comercios, proporción en promoción, precio mediano, ahorro máximo, cambios de
  precio y fecha y estado de la última ejecución);
* presenta cuatro gráficos interactivos con **highcharter**: evolución del
  precio de una presentación por comercio, precio por unidad de contenido,
  distribución de precios por comercio y ahorro potencial por presentación;
* permite ordenar, buscar y descargar en CSV la tabla filtrada;
* compara dos ejecuciones y lista los productos que subieron, bajaron,
  aparecieron o dejaron de observarse, con un umbral ajustable;
* arma una canasta con cantidades, calcula el costo por comercio solo cuando hay
  cobertura completa y compara con la compra óptima producto por producto;
* actualiza los precios desde la propia aplicación, sin bloquear la interfaz,
  reutilizando `scraper.R`, validando antes de insertar y tolerando fallas por
  comercio;
* ofrece un modo sin conexión que reprocesa las copias de `raw/`.

Todos los precios están en pesos colombianos (COP) y corresponden al momento de
la consulta. La aplicación muestra siempre la fecha de la ejecución.

---

## 2. Inicio rápido

### 2.1. Dependencias

```r
renv::restore()          # versiones exactas de renv.lock (R 4.3.3, 104 paquetes)
```

Si prefiere instalarlas a mano:

```r
source("dependencias.R")
```

### 2.2. Ejecutar la aplicación

Desde la carpeta `taller_2/`:

```r
shiny::runApp(".")
```

La base y las copias crudas ya están incluidas: la aplicación abre con la
última ejecución completa y no necesita internet para funcionar.

### 2.3. Pruebas

```r
Rscript -e 'testthat::test_dir("tests")'
```

Dieciséis pruebas en siete archivos; todas usan bases temporales o funciones puras,
nunca la base de la entrega ni los sitios.

### 2.4. Actualizar precios

Desde la aplicación: pestaña **Actualizar** → *Actualizar precios (en línea)*.
Desde R:

```r
source("scraper.R")
ejecutar_recoleccion(offline = FALSE)
```

### 2.5. Modo sin conexión

En la aplicación: **Actualizar** → *Reprocesar copias locales*. Desde R:

```r
source("scraper.R")
ejecutar_recoleccion(offline = TRUE, id_ejecucion = "EJEC_..._OFF",
                     id_origen = "EJEC_20261111_231458")
```

El reprocesamiento usa las copias de `raw/` del identificador de origen y crea
una ejecución nueva con las fechas de consulta originales.

---

## 3. Estructura de archivos

```text
taller_2/
├── app.R                     # interfaz y servidor Shiny
├── db.R                      # capa de acceso a datos y consultas parametrizadas
├── scraper.R                 # extracción, copias crudas, SQLite y modo offline
├── validacion.R              # reglas de validación y conversión de precios
├── comparador_precios.sqlite # base con las ejecuciones y las vistas
├── diccionario_datos.md      # significado, tipo y unidad de cada campo
├── mapeo_productos.csv       # correspondencia SKU ↔ presentación canónica
├── db/
│   ├── schema.sql                  # tablas, restricciones e índices
│   ├── vistas.sql                  # vistas SQL de la aplicación
│   └── migracion_observaciones.sql # retiro del UNIQUE heredado del Taller 1
├── raw/                      # copias crudas comprimidas por comercio y fecha
├── tests/                    # pruebas testthat + helper con base temporal
├── renv.lock                 # versiones fijas
├── dependencias.R            # lista de paquetes
├── deploy.R                  # publicación en shinyapps.io
└── README.md
```

---

## 4. Datos

### 4.1. Origen y categoría

Los datos provienen del código de `scraper.R`, que consulta la API pública de
catálogo (VTEX) que alimenta la vitrina de cada comercio. No hay precios
digitados ni archivos preparados a mano; cada observación se puede rastrear
hasta su copia comprimida en `raw/<comercio>/<fecha>/<ejecución>/<rama>/` y
hasta su fila en `ejecuciones`.

| Comercio | Ramas equivalentes | Productos reportados |
|---|---|---:|
| Carulla | Chocolates, Confitería, Chicles, Gomitas y masmelos + Chocolate de mesa | 2.468 |
| Jumbo | Confitería, Chocolatería + Chocolate de mesa | 541 |
| Olímpica | Confitería + Chocolates de mesa | 416 |

La delimitación de la categoría y las exclusiones (suplementos, pastillas
medicinales, panadería, café, cocoa en polvo, artículos de fiesta) están en el
informe del Taller 1 y resumidas en la tabla `descartes`.

### 4.2. Reemplazo de Éxito por Olímpica

El 11 de noviembre de 2026 Cloudflare bloqueó todo el dominio `www.exito.com`
con HTTP 403, tanto la página principal como la API de catálogo (se probó con
`curl` y con un navegador; `robots.txt` sí respondía). El enunciado permite
reemplazar un comercio que dejó de permitir la extracción. La decisión quedó
registrada en la tabla `correcciones`:

* Éxito queda `activo = 0`; sus 17.629 observaciones históricas se conservan y
  no se borraron.
* Olímpica entra como tercer comercio activo. Su categoría equivalente es
  `Supermercado > Pasabocas y helados > Confitería` más
  `Supermercado > Desayuno > Chocolates de mesa`.
* Se revalidó la correspondencia contra el texto original de los tres
  comercios: 14 presentaciones están en Carulla, Jumbo y Olímpica.

Éxito y Carulla comparten catálogo y SKU (pertenecen al mismo grupo), lo que
confirmó la correspondencia de las cinco presentaciones del Taller 1 que también
existen en Olímpica. Las otras ocho no se encontraron en Olímpica y dejan de ser
comparables vigentes, aunque sus observaciones históricas se conservan.

### 4.3. Historial de ejecuciones

| Ejecución | Fecha | Comercios | Observaciones | Comparables |
|---|---|---|---:|---:|
| `EJEC_20261105_222937` | 2026-11-05 | Éxito, Carulla, Jumbo | 5.875 | 39 |
| `EJEC_20261105_223427` | 2026-11-05 | Éxito, Carulla, Jumbo | 5.875 | 39 |
| `EJEC_20261106_193851` | 2026-11-06 | Éxito, Carulla, Jumbo | 5.879 | 39 |
| `EJEC_20261111_231458` | 2026-11-11 | Carulla, Jumbo, Olímpica | 3.247 | 42 |
| `EJEC_20261112_000010` | 2026-11-12 | Carulla, Jumbo, Olímpica | 3.251 | 42 |

La ejecución `EJEC_20261111_230924` quedó `fallida`: fue el primer intento del
11 de noviembre y abortó por un error de programación en la tabla de motivos de
validación, antes de insertar observaciones. Se conserva como evidencia y no se
borró; el detalle está en `correcciones`.

Las ejecuciones del Taller 1 se conservan intactas. Las dos ejecuciones nuevas
comparten los mismos tres comercios y las mismas 14 presentaciones, de modo que
la comparación entre fechas es válida.

---

## 5. Base de datos

El esquema completo está en `db/schema.sql` y las vistas en `db/vistas.sql`.
El diccionario de cada tabla, vista y columna está en
[`diccionario_datos.md`](diccionario_datos.md).

### 5.1. Tablas

| Tabla | Contenido |
|---|---|
| `comercios` | Comercios, categoría equivalente y estado (activo/inactivo). |
| `ejecuciones` | Una fila por corrida: fechas, modo, estado y totales. |
| `ejecuciones_comercio` | Detalle por comercio y estado de la extracción. |
| `ejecuciones_categoria` | Detalle por rama consultada. |
| `productos_comparables` | Catálogo canónico, contenido normalizado y vigencia. |
| `observaciones` | Cada anuncio de cada comercio en cada ejecución. |
| `mapeo_productos` | Correspondencia SKU ↔ presentación, con regla y confianza. |
| `descartes` | Excluidos y duplicados con su motivo. |
| `correcciones` | Bitácora de cambios sobre la entrega anterior. |
| `observaciones_rechazadas` | Filas que no pasaron la validación, con el motivo. |

### 5.2. Vistas

| Vista | Para qué |
|---|---|
| `v_ultimo_precio` | Última observación de cada anuncio. |
| `v_cambios_precio` | Cambios entre dos ejecuciones del mismo anuncio. |
| `v_comparables` | Catálogo canónico y cobertura de correspondencia. |
| `v_disponibilidad` | Disponible, agotado o no observado. |
| `v_ahorro_presentacion` | Mínimo, máximo, promedio, ahorro y empates. |
| `v_precio_unitario` | Precio por g, mL o unidad. |
| `v_resumen_ejecucion` | Totales por ejecución. |
| `v_observaciones` | Observaciones con nombres legibles. |

### 5.3. Validación antes de insertar

`validacion.R` aplica nueve reglas antes de cada inserción: precio positivo en
disponibles, campos obligatorios, URL válida, fecha ISO 8601 con hora de
Colombia, estado de disponibilidad válido, ausencia de duplicados en la
ejecución, coherencia del precio de lista, contenido positivo y unidad
normalizada. Las filas rechazadas se guardan en `observaciones_rechazadas` con
el motivo y no entran a `observaciones`.

### 5.4. Correcciones registradas

| Fecha | Tabla | Cambio |
|---|---|---|
| 2026-11-11 | `comercios` | Éxito pasa a inactivo por el bloqueo 403. |
| 2026-11-11 | `comercios` | Olímpica entra como comercio activo. |
| 2026-11-11 | `observaciones` | Se agrega `estado_disponibilidad` y se deriva de `disponible` y `precio_cop`. |
| 2026-11-11 | `productos_comparables` | Se agregan `contenido_total` y `unidad_normalizada`. |
| 2026-11-11 | `productos_comparables` | 8 presentaciones del Taller 1 dejan de ser vigentes; 9 nuevas se incorporan. |
| 2026-11-11 | `mapeo_productos` | 39 → 71 filas de correspondencia. |
| 2026-11-11 | `ejecuciones` | El primer intento del 11/11 queda como `fallida`. |
| 2026-11-11 | `observaciones` | Se retira el `UNIQUE (comercio, sku, fecha)` heredado para que el modo sin conexión pueda reprocesar `raw/`; la unicidad por ejecución se mantiene. |
| 2026-11-11 | `descartes` | Se retira la regla `^pasta`, que excluía por error «Pasta de Caramelo Mechas Locas» (confitería agotada). El producto entra desde la ejecución del 12/11. |
| 2026-11-11 | `descartes` | Se excluyen tres «Harina Pan» (harina de maíz) que el Taller 1 tenía dentro de confitería por un error de clasificación del sitio; no son confitería y no tenían precio. |

---

## 6. Funcionalidades por módulo

### Módulo 1. Datos

* Origen verificable: toda observación tiene `id_ejecucion` y una copia cruda en
  `raw/`; el identificador de la ejecución y el SHA-256 de cada página están en
  `metadata.json`.
* La base distingue `disponible`, `agotado` y `no_observado` (vista
  `v_disponibilidad`).
* Contenido total y unidad normalizada (`g`, `mL`, `unidad`) en el catálogo y en
  cada observación.
* Restricción de unicidad `(id_ejecucion, id_comercio, sku_comercio)` e índices
  para los filtros de la aplicación.
* Ocho vistas SQL; la aplicación usa directamente `v_cambios_precio`,
  `v_comparables`, `v_ahorro_presentacion`, `v_precio_unitario` y
  `v_observaciones`.

### Módulo 2. Actualización

* Botón que llama a `ejecutar_recoleccion()` de `scraper.R`; no reimplementa el
  scraping ni lee archivos locales.
* `ExtendedTask` + `future` + `promises`: la recolección corre en un proceso
  aparte y la interfaz sigue respondiendo. El avance por comercio se consulta
  con `reactivePoll`.
* Cada comercio se inserta dentro de una transacción; si falla, se revierte y la
  ejecución de ese comercio queda `parcial` o `fallida` con el motivo, sin
  afectar a los demás.
* Al terminar se muestra un resumen por comercio: recolectados, nuevos, cambios
  de precio y no observados.
* Modo sin conexión que reprocesa `raw/` y crea una ejecución nueva.

### Módulo 3. Consultas y acceso a datos

* `db.R` concentra el SQL; la interfaz no contiene consultas.
* Filtros, indicadores y agregaciones se calculan en SQLite (incluida la
  mediana con `ROW_NUMBER`), no filtrando la tabla completa en R.
* Una conexión por sesión, abierta al iniciar y cerrada en `onStop`.
* Resultados repetidos en caché con `bindCache`; la caché se invalida al subir
  la versión de datos después de una actualización.

### Módulo 4. Seguridad

* Sin credenciales en el repositorio; `.Renviron` está en `.gitignore`.
* Todas las consultas usan marcadores `?` y `params`; los `IN (...)` se generan
  con marcadores, nunca concatenando valores.
* El texto de búsqueda se valida (máximo 60 caracteres, caracteres permitidos) y
  se neutralizan `%` y `_` antes del `LIKE`.
* El scraping usa un agente identificable, pausas de 0,25 s y un número acotado
  de peticiones por ejecución.

### Módulo 5. Presentación

* `page_sidebar` + `navset_card_tab` de `bslib`, con indicadores en tarjetas.
* Paleta fija por comercio en todos los gráficos y tablas.
* Filtros del panel lateral combinables; mensajes claros cuando no hay datos.
* Cuatro gráficos highcharter y una tabla DT con orden, búsqueda y descarga CSV.
* Moneda, unidades y fecha visibles en todos los indicadores.

### Módulo 6. Análisis para el consumidor

* Precio por unidad sin mezclar unidades (g, mL, unidad).
* Comparación de dos ejecuciones con umbral ajustable.
* Canasta con cantidades, validación de cobertura y advertencia de condiciones.
* Hallazgos verificables en la sección 8.

### Módulo 7. Calidad y reproducibilidad

* Cuatro archivos separados (`app.R`, `db.R`, `scraper.R`, `validacion.R`).
* Dieciséis pruebas con `testthat` en `tests/`.
* `renv.lock` con R 4.3.3 y 104 paquetes.
* Rutas relativas; no hay `setwd()` ni rutas absolutas.

### Módulo 8. Despliegue

Ver la sección 10.

---

## 7. Cómo se actualiza la base

1. La aplicación genera un `id_ejecucion` nuevo y lo pasa a `ejecutar_recoleccion()`.
2. El scraper descarga la categoría completa de cada comercio y guarda las
   respuestas en `raw/`.
3. Cada lote se valida (`validacion.R`); las filas rechazadas van a
   `observaciones_rechazadas`.
4. La inserción de cada comercio ocurre en una transacción; si falla, se revierte.
5. Se aplica la correspondencia de `mapeo_productos.csv` y se marcan los
   comparables vigentes.
6. Se cierra la ejecución con su estado (`completa`, `parcial` o `fallida`).
7. La aplicación incrementa la versión de datos, invalida la caché y actualiza
   indicadores, gráficos y tablas sin reiniciarse.

---

## 8. Hallazgos para el consumidor

Los siguientes resultados corresponden a las ejecuciones `EJEC_20261111_231458`
(11 de noviembre) y `EJEC_20261112_000010` (12 de noviembre), con 14
presentaciones presentes en Carulla, Jumbo y Olímpica. Se pueden reproducir en
la aplicación eligiendo esas ejecuciones.

1. **No hay un comercio más barato para todo.** De las 14 presentaciones, el
   precio mínimo está en Carulla en 5, en Olímpica en 4, en Jumbo en 2 y hay
   empate en 3 (Tic Tac menta, Milka 80 g y Jet burbuja Dubai). La mayor
   diferencia es Luker azúcar morena 400 g: $9.400 en Carulla frente a $12.990
   en Jumbo y Olímpica (27,6 %).
2. **La canasta completa no coincide con la compra óptima.** Comprar las 14
   presentaciones en un solo comercio cuesta $148.250 en Carulla, $150.800 en
   Olímpica y $154.260 en Jumbo. Comprando cada producto donde está más barato,
   el costo baja a $141.490: $6.760 menos (4,6 %) que el mejor comercio único y
   $12.770 menos (8,3 %) que el más costoso.
3. **La presentación grande puede ser más eficiente por gramo.** Corona
   tradicional: la barra de 200 g cuesta $3.760 por 100 g en Carulla, mientras
   que la de 450 g cuesta $3.711 en Carulla, $3.642 en Jumbo y $3.611 en
   Olímpica. La diferencia por gramo es pequeña, pero el desembolso de la barra
   grande es más del doble; conviene distinguir ahorro unitario de desembolso.
4. **Los precios de las presentaciones comparables se movieron poco entre el 6
   y el 12 de noviembre.** La mayor variación fue de 3,3 % (Corona tradicional
   200 g en Carulla, de $7.280 a $7.520); con el umbral de 5 % de la aplicación
   no aparece ninguna variación. Entre el 11 y el 12 de noviembre no hubo
   cambios en las 14 presentaciones. Los cambios de mayor magnitud de la sección
   **Cambios** corresponden a productos del resto de la categoría y a la entrada
   de Olímpica.

> Los precios son una fotografía del momento de la consulta. No incluyen
> domicilio, mínimos de compra, cupones, fidelización ni precios de tienda
> física. La comparación de la canasta supone que el comercio tiene todos los
> productos y no modela sustituciones.

---

## 9. Pruebas

```r
Rscript -e 'testthat::test_dir("tests")'
```

| Archivo | Qué verifica |
|---|---|
| `test-precios.R` | Conversión de precios en texto a número; rechazo de precios no positivos; campos obligatorios. |
| `test-contenido.R` | Normalización de kg/g y mL; paquetes múltiples; unidades contables; contenido ausente. |
| `test-ahorro.R` | Ahorro con empates y con precios ausentes. |
| `test-unicidad.R` | La restricción impide duplicar una observación; la validación detecta duplicados en el lote. |
| `test-cambios.R` | Subidas, bajadas, productos nuevos, no observados y umbral. |
| `test-canasta.R` | La canasta no se calcula si falta un producto; totales, óptimo y ahorro; producto agotado. |
| `test-filtros.R` | Validación del texto de búsqueda y filtros parametrizados. |

Las pruebas construyen una base temporal con `db/schema.sql` y `db/vistas.sql`,
y no consultan los sitios ni la base de la entrega.

---

## 10. Despliegue

**Aplicación publicada:** <https://01a1d0a7-6ccf-190d-8d9e-288697a8dfdc.share.connect.posit.cloud/>

Plataforma: **Posit Connect Cloud**, cuenta `carl0sarauj0`.
Acceso público: cualquier persona con el enlace puede verla.

### Cómo se publicó

```r
install.packages("rsconnect")
rsconnect::connectCloudUser()   # autorización interactiva; registra la cuenta
source("deploy.R")
```

También se puede autenticar sin navegador con un client ID y un secret creados
en <https://login.posit.cloud/identity/credentials>:

```r
rsconnect::connectCloudClientCredentials(
  clientId = "<CLIENT_ID>", clientSecret = "<CLIENT_SECRET>",
  accountName = "carl0sarauj0"
)
```

`deploy.R` publica con `account = "carl0sarauj0"` y `appVisibility = "public"`.
Las credenciales se administran en la plataforma; el repositorio no contiene
tokens ni secretos.

### Notas del servidor

- En el enlace publicado funcionan los filtros, los indicadores, los cuatro
  gráficos, la tabla con descarga, la canasta y la comparación de ejecuciones.
- Connect Cloud no permite hacer scraping desde su red. El botón de
  actualización en línea informa el error por comercio y conserva la base; el
  modo sin conexión reprocesa `raw/`. Si el sistema de archivos del servidor es
  de solo lectura, la aplicación muestra el motivo en lugar de dejar la base
  inconsistente.
- Las plataformas gratuitas no conservan los cambios de la base al reiniciarse;
  la actualización en línea funciona en la ejecución local.

---

## 11. Declaración de uso de inteligencia artificial

**Herramientas:** DeepSeek Harness (asistente de codificación) y Claude Code
(revisión y depuración).

**Uso estimado: 60 % del código y de la documentación.** El desglose es:

| Parte | Asistencia de IA | Verificación del estudiante |
|---|---|---|
| `scraper.R` (Taller 1, ampliado) | 50 % | Ejecución en línea, revisión de `raw/`, modo offline y comparación de conteos. |
| `validacion.R` | 80 % | Revisión de las nueve reglas y de las filas rechazadas. |
| `db.R` | 75 % | Cada consulta se contrastó con consultas independientes en `sqlite3`. |
| `app.R` | 70 % | Prueba de los siete paneles, filtros, canasta y botón de actualización. |
| Pruebas `tests/` | 85 % | Ejecución local y revisión de los casos límite. |
| `diccionario_datos.md` y `README.md` | 80 % | Verificación de tablas, vistas y cifras contra la base. |
| Correspondencia de productos | 20 % | Validación manual contra el texto original de los tres comercios. |
| Conclusiones para el consumidor | 40 % | Cálculo y revisión de los resultados en la aplicación. |

El estudiante es responsable de todo el código entregado, lo ejecutó, revisó y
puede explicarlo. El historial de Git del repositorio conserva los cambios. Se
usó IA como apoyo, no como sustituto de la verificación de los datos.

---

## 12. Limitaciones

* Los precios son una fotografía; las promociones y la disponibilidad cambian.
* La correspondencia de presentaciones es manual. Las diferencias de nombre
  entre comercios (por ejemplo, «aros surtidos» y «aros frutal») están
  documentadas en `mapeo_productos.csv`.
* La canasta no incluye envío, mínimos de compra ni condiciones de promoción.
* La base conserva las ejecuciones del Taller 1 con Éxito; la aplicación las
  muestra como historial, pero no se comparan contra las ejecuciones nuevas
  porque no comparten comercios.
* En un servidor público el scraping puede estar bloqueado; el modo sin conexión
  reprocesa `raw/` y mantiene la aplicación demostrable.
* Las plataformas gratuitas no conservan los cambios de la base al reiniciarse;
  la actualización en línea funciona en la ejecución local.

---

## 13. Auditoría del Taller 1

Antes de construir el Taller 2 se revisó la entrega anterior contra su
enunciado:

| Requisito del Taller 1 | Estado |
|---|---|
| Tres comercios con datos | Cumple (Éxito, Carulla, Jumbo). |
| Categoría completa y paginación | Cumple: 4.626 + 2.468 + 541 productos; el total reportado por el sitio coincide con lo extraído. |
| Ocho productos comparables en una misma ejecución | Cumple: 13 presentaciones, 39 observaciones. |
| Módulo `scraper.R` separado y función general | Cumple. |
| Copias crudas en `raw/` y modo offline | Cumple; `verificar_offline()` reproduce la ejecución. |
| Campos obligatorios y fecha ISO 8601 | Cumple. |
| Base SQLite con tabla de ejecuciones y unicidad | Cumple. |
| Ocho consultas SQL con interpretación | Cumple (`consultas.sql`, informe). |
| Informe con gráficos y conclusiones | Cumple (`taller_1.html`). |
| `renv.lock` | Existe, pero declara R 4.6.2 y versiones que no coinciden con este equipo (R 4.3.3). Es la única debilidad encontrada; el `renv.lock` del Taller 2 sí se generó con el entorno usado. |

No se encontraron precios mal extraídos ni correspondencias incorrectas en las
39 observaciones comparables; se conservaron sin cambios. Las correcciones del
Taller 2 son de estructura (campos y vistas nuevos), de disponibilidad y del
reemplazo de Éxito, y están todas en la tabla `correcciones`.

Al reprocesar las copias crudas del Taller 1 con el validador del Taller 2 se
excluyen tres «Harina Pan» que el sitio tenía dentro de confitería. No tenían
precio ni participaban de la comparación; las observaciones históricas se
conservan. Es la única diferencia entre la base histórica y su
reprocesamiento.
