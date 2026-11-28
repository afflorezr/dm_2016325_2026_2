# Diccionario de datos — `comparador_precios.sqlite`

Base del comparador de precios de **medicamentos antiinfecciosos de uso sistémico** en La Rebaja
Virtual, Locatel y Droguerías Cafam. El esquema completo (tablas, restricciones, índices y vistas)
está en [`esquema.sql`](esquema.sql). `scraper.conectar()` lo aplica cada vez que abre la base para
escribir, sin borrar datos.

**Convenciones**

- **Fechas:** texto ISO 8601 con la zona horaria de Colombia, por ejemplo
  `2026-11-08T11:03:10-05:00`.
- **Precios:** pesos colombianos (COP) con IVA, tal como los publica el sitio.
- **`NULL`:** el dato no existe o no se pudo extraer. Nunca se reemplaza por 0.
- **Identificador de ejecución:** `E` + fecha y hora de inicio, por ejemplo `E20261108T110310`.
  Es el mismo nombre de la carpeta de la copia cruda:
  `raw/<comercio>/<AAAA-MM-DD>/<id_ejecucion>/`.
- **Comercios (`id_comercio`):** `larebaja`, `locatel` y `cafam`. `colsubsidio` está registrado
  como respaldo, pero no se recolecta (`activo = 0`).
- Las columnas marcadas con **(T2)** son nuevas del Taller 2. Las demás vienen del Taller 1.

## Tablas

### `comercios`

Un comercio por fila.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_comercio` | TEXT, PK | Clave del comercio | `larebaja`, `locatel`, `cafam`, `colsubsidio` |
| `nombre` | TEXT | Nombre completo del comercio | p. ej. `La Rebaja Virtual` |
| `url_base` | TEXT | Dirección del sitio | URL |
| `plataforma` | TEXT | Plataforma del sitio y forma de lectura | `VTEX`, `VTEX IO (páginas HTML de categoría)` |
| `secciones` | TEXT | Secciones del sitio que se recorren | JSON |
| `robots` | TEXT | Resultado de la revisión de `robots.txt` | texto |
| `nombre_corto` (T2) | TEXT | Nombre que muestra la aplicación | `La Rebaja`, `Locatel`, `Cafam`, `Colsubsidio` |
| `activo` (T2) | INTEGER | Si el comercio se recolecta | `1` = sí, `0` = no |

### `ejecuciones`

Una fila por ejecución del scraper y por comercio. La clave primaria es
(`id_ejecucion`, `id_comercio`).

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_ejecucion` | TEXT | Identificador de la ejecución | `E` + `AAAAMMDDTHHMMSS` |
| `id_comercio` | TEXT, FK → `comercios` | Comercio recolectado | ver `comercios` |
| `inicio` | TEXT | Inicio de la recolección del comercio | ISO 8601 (-05:00) |
| `fin` | TEXT | Fin de la recolección del comercio | ISO 8601 (-05:00) |
| `modo` | TEXT | Cómo se obtuvieron los datos | `en_linea` (consulta al sitio), `sin_conexion` (reproceso de `raw/`) |
| `paginas` | INTEGER | Páginas o respuestas guardadas en `raw/` | número |
| `total_reportado_sitio` | INTEGER | Productos que el sitio dice tener en las secciones recorridas | productos |
| `productos_recorridos` | INTEGER | Productos distintos que se leyeron | productos |
| `registros_categoria` | INTEGER | SKU que quedaron dentro de la categoría (antiinfecciosos sistémicos) | SKU |
| `excluidos` | INTEGER | SKU recorridos que quedaron fuera de la categoría | SKU |
| `estado` | TEXT | Resultado de la ejecución en ese comercio | `completa` (se leyó todo lo que reporta el sitio), `parcial` (faltaron productos o hubo errores), `fallida` (no se obtuvo nada) |
| `detalle` | TEXT | Errores o motivo de la falla | JSON: `{"errores": [...]}` o `{"error": ..., "tipo": ...}` |

### `productos`

Las presentaciones comparables (P01 a P10), con su descripción verificada a mano.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_producto` | TEXT, PK | Identificador del comparable | `P01` … `P10` |
| `descripcion` | TEXT | Descripción legible | p. ej. `AMOXICILINA 875 MG TABLETA x20 (TECNOQUIMICAS)` |
| `principio_activo` | TEXT | Principio(s) activo(s), separados por ` + ` en orden alfabético | texto en mayúsculas |
| `concentracion` | TEXT | Concentración, en el mismo orden que `principio_activo` | p. ej. `875 MG`, `125/875 MG` |
| `forma` | TEXT | Forma farmacéutica | valores de `anuncios.forma_std` |
| `laboratorio` | TEXT | Laboratorio fabricante | texto en mayúsculas |
| `unidades` | INTEGER | Unidades por empaque (tabletas, cápsulas, sobres) | unidades |
| `contenido_ml` | REAL | Contenido del envase en líquidos (columna del Taller 1) | mL |
| `contenido_total` (T2) | REAL | Contenido total de la presentación, > 0 | en `unidad_normalizada` |
| `unidad_normalizada` (T2) | TEXT | Unidad de `contenido_total` | `mL`, `g`, `unidad` |

### `anuncios`

Un anuncio es un SKU de un comercio, con los campos tal como los publica el sitio (`*_original`) y
los estandarizados por `limpieza.py` (`*_std`). La clave primaria es (`id_comercio`, `sku_comercio`).

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_comercio` | TEXT, FK → `comercios` | Comercio del anuncio | ver `comercios` |
| `sku_comercio` | TEXT | Código del SKU en el comercio | texto |
| `id_producto_comercio` | TEXT | Código del producto en el comercio (un producto puede tener varios SKU) | texto |
| `ean` | TEXT | Código de barras publicado | texto; `NULL` si no lo publica |
| `ean_valido` | INTEGER | Si el EAN tiene dígito de control correcto (EAN-13/UPC-12) | `1` = válido, `0` = no (p. ej. códigos internos) |
| `nombre_original` | TEXT | Nombre del anuncio | texto publicado |
| `marca_original` | TEXT | Marca publicada | texto publicado |
| `laboratorio_original` | TEXT | Laboratorio publicado | texto publicado; Locatel no lo publica (`NULL`) |
| `principio_activo_original` | TEXT | Principio activo publicado | texto publicado |
| `presentacion_original` | TEXT | Presentación publicada | texto publicado |
| `via_original` | TEXT | Vía de administración publicada | p. ej. `ORAL`, `INTRAVENOSO`, `INTRAMUSCULAR`; `NULL` si no se publica |
| `requiere_formula` | TEXT | Si el sitio dice que requiere fórmula médica | `SI`/`Si`, `NO`/`No`, `NULL` |
| `categoria_comercio` | TEXT | Ruta de la categoría del anuncio en el sitio | p. ej. `/Drogueria/medicamentos/Antiinfecciosos/` |
| `url_producto` | TEXT | Enlace al anuncio | URL |
| `principio_activo_std` | TEXT | Principio activo estandarizado | texto en mayúsculas, sin tildes |
| `subcategoria` | TEXT | Grupo terapéutico (según el código ATC) | `Antibiótico`, `Antiviral`, `Antiparasitario`, `Antimicótico sistémico`, `Antimicótico sistémico / Antiparasitario` |
| `marca_std` | TEXT | Marca estandarizada | texto en mayúsculas |
| `laboratorio_std` | TEXT | Laboratorio estandarizado | texto en mayúsculas |
| `forma_std` | TEXT | Forma farmacéutica estandarizada | `TABLETA`, `CAPSULA`, `SUSPENSION ORAL`, `POLVO PARA SUSPENSION ORAL`, `SOLUCION ORAL`, `JARABE`, `SOBRE / POLVO ORAL`, `INYECTABLE`, `NULL` |
| `concentracion_std` | TEXT | Concentración estandarizada | p. ej. `500 MG`, `125 MG/5 ML` |
| `unidades` | INTEGER | Unidades por empaque | unidades |
| `contenido` | REAL | Contenido del envase (líquidos y polvos) | en `unidad_contenido` |
| `unidad_contenido` | TEXT | Unidad de `contenido` | `ML`, `G`, `NULL` |
| `fuente_cantidad` | TEXT | De dónde salieron `unidades` y `contenido` | `ficha` (campos del sitio), `nombre` (del nombre del anuncio), `nombre (la ficha decía …)` cuando no coincidían, `NULL` |
| `id_producto` | TEXT, FK → `productos` | Comparable al que corresponde | `P01` … `P10`; `NULL` si no es comparable |
| `comparable` | INTEGER | Si el anuncio es uno de los comparables | `1` = sí, `0` = no |
| `contenido_total` (T2) | REAL | Contenido total normalizado, > 0 | en `unidad_normalizada` |
| `unidad_normalizada` (T2) | TEXT | Unidad del contenido total | `mL`, `g`, `unidad`, `NULL` |

### `correspondencia`

Relación verificada a mano entre cada comparable y su anuncio en cada comercio (viene de
`correspondencia.csv`). Solo lleva identificadores, nunca precios.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_producto` | TEXT, FK → `productos` | Comparable | `P01` … `P10` |
| `id_comercio` | TEXT | Comercio | ver `comercios` |
| `sku_comercio` | TEXT | SKU del comparable en ese comercio | FK (`id_comercio`, `sku_comercio`) → `anuncios` |
| `regla` | TEXT | Criterio con que se eligió la correspondencia | texto |

### `observaciones`

Una observación es el precio de un SKU en una ejecución. Cada fila se puede rastrear hasta su copia
cruda con `id_ejecucion`, `id_comercio` y `url_extraccion`.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_observacion` | INTEGER, PK | Identificador de la observación | autoincremental |
| `id_ejecucion` | TEXT | Ejecución en que se observó | FK (`id_ejecucion`, `id_comercio`) → `ejecuciones` |
| `id_comercio` | TEXT | Comercio | ver `comercios` |
| `sku_comercio` | TEXT | SKU observado | FK (`id_comercio`, `sku_comercio`) → `anuncios` |
| `fecha_consulta` | TEXT | Fecha y hora en que se consultó la página o respuesta | ISO 8601 (-05:00) |
| `precio` | REAL | Precio de venta publicado; si existe, es > 0 | COP; `NULL` = sin precio (solo si está agotado; un agotado casi siempre conserva el precio publicado) |
| `precio_lista` | REAL | Precio antes del descuento; si existe, es > 0 | COP; `NULL` si no se publica |
| `promocion` | INTEGER | Si el precio es menor que el precio de lista | `1` = sí, `0` = no, `NULL` = no se puede saber |
| `disponible` | INTEGER | Si el sitio lo muestra disponible | `1` = disponible, `0` = agotado |
| `url_extraccion` | TEXT | Dirección exacta de la página o respuesta leída | URL |
| `texto_original` | TEXT | Texto del anuncio tal como se publicó (nombre, nombre del SKU, descripción y ficha) | JSON |
| `disponibilidad` (T2) | TEXT | Situación según el sitio | `disponible`, `agotado` (el "no observado" está en la vista `v_disponibilidad`) |
| `descartada` (T2) | INTEGER | Si la observación se marcó como descartada en vez de borrarla | `0` = vigente, `1` = descartada |
| `motivo_descarte` (T2) | TEXT | Por qué se descartó | texto; obligatorio si `descartada = 1` |

Restricciones:

- `UNIQUE (id_comercio, sku_comercio, fecha_consulta)`, del Taller 1.
- `UNIQUE (id_ejecucion, id_comercio, sku_comercio)`: la misma observación no puede insertarse dos
  veces.
- `disponible` y `disponibilidad` deben coincidir, y un producto disponible siempre tiene precio.

### `excluidos`

SKU que se recorrieron pero quedaron fuera de la categoría, con el motivo (sirve para revisar la
delimitación de `categoria.py`).

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_ejecucion` | TEXT | Ejecución | ver `ejecuciones` |
| `id_comercio` | TEXT | Comercio | ver `comercios` |
| `sku_comercio` | TEXT | SKU excluido | texto |
| `nombre_original` | TEXT | Nombre publicado | texto |
| `principio_activo` | TEXT | Principio activo reconocido | texto |
| `categoria_comercio` | TEXT | Categoría del sitio | ruta de categoría |
| `motivo` | TEXT | Por qué quedó fuera | p. ej. `vía declarada por el comercio: TOPICA`, `antiinfeccioso de acción local o intestinal (no sistémico)`, `uso local (piel): 'crema'` |

### `correcciones` (T2)

Cada cambio a un dato que ya estaba en la base. Nunca se borra nada.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_correccion` | INTEGER, PK | Identificador | autoincremental |
| `fecha` | TEXT | Cuándo se hizo el cambio | ISO 8601 (-05:00) |
| `tabla` | TEXT | Tabla corregida | `anuncios`, `productos`, `observaciones` |
| `registro` | TEXT | Clave del registro corregido | p. ej. `locatel/14177`, `P02`, `id_observacion=123` |
| `campo` | TEXT | Columna corregida | nombre de columna |
| `valor_anterior` | TEXT | Valor antes del cambio | texto; `NULL` = estaba vacío |
| `valor_nuevo` | TEXT | Valor después del cambio | texto; `NULL` = queda vacío |
| `motivo` | TEXT | Por qué se corrigió | texto |
| `origen` | TEXT | Archivo y función que hizo el cambio | `preparar_base.py`, `scraper._guardar_anuncios`, `scraper._descartar_existentes` |

### `rechazos` (T2)

Observaciones que no pasaron la validación (`validacion.py`). No se insertan en `observaciones`:
se guardan aquí con el motivo.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_rechazo` | INTEGER, PK | Identificador | autoincremental |
| `id_ejecucion` | TEXT | Ejecución | ver `ejecuciones` |
| `id_comercio` | TEXT | Comercio | ver `comercios` |
| `sku_comercio` | TEXT | SKU rechazado | texto |
| `fecha_consulta` | TEXT | Fecha de la consulta | ISO 8601 (-05:00) |
| `url_extraccion` | TEXT | Página o respuesta leída | URL |
| `precio` | REAL | Precio leído, si era numérico | COP |
| `motivo` | TEXT | Regla que no se cumplió | texto |
| `registro` | TEXT | La fila rechazada completa | JSON |
| `fecha_registro` | TEXT | Cuándo se registró el rechazo | ISO 8601 (-05:00) |

### `validaciones` (T2)

Resultado de cada regla de validación por ejecución y comercio. La clave primaria es
(`id_ejecucion`, `id_comercio`, `regla`).

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `id_ejecucion` | TEXT | Ejecución | ver `ejecuciones` |
| `id_comercio` | TEXT | Comercio | ver `comercios` |
| `regla` | TEXT | Regla revisada | `precio_numerico_mayor_que_cero`, `disponible_con_precio`, `campos_obligatorios`, `sin_duplicados`, `comparables_presentes` |
| `n_revisadas` | INTEGER | Filas revisadas | filas |
| `n_fallas` | INTEGER | Filas que no cumplieron | filas |
| `aprobada` | INTEGER | Si la regla se cumplió | `1` = sí, `0` = no |
| `detalle` | TEXT | Explicación del resultado | texto |
| `fecha` | TEXT | Cuándo se validó | ISO 8601 (-05:00) |

## Índices

Además de los índices que crean las claves primarias y los `UNIQUE`, hay índices sobre las columnas
que usan los filtros de la aplicación:

| Índice | Tabla (columnas) |
|---|---|
| `idx_observaciones_fecha` | `observaciones (fecha_consulta)` |
| `idx_observaciones_precio` | `observaciones (precio)` |
| `idx_observaciones_promocion` | `observaciones (promocion)` |
| `idx_anuncios_subcategoria` | `anuncios (subcategoria)` |
| `idx_anuncios_marca` | `anuncios (marca_std)` |
| `idx_anuncios_comparable` | `anuncios (comparable, id_producto)` |
| `idx_ejecuciones_estado` | `ejecuciones (estado)` |

## Vistas

La aplicación consulta estas vistas directamente desde `db.py`, menos `v_ultimo_precio`, que queda
para consultas independientes sobre la base.

### `v_observaciones`

Una fila por observación, unida con su anuncio, su comercio y su comparable (si lo es). Es la base
de los filtros, los indicadores y la tabla de productos. Tiene las columnas de `observaciones` y
estas otras:

| Columna | Origen | Significado |
|---|---|---|
| `comercio`, `nombre_corto` | `comercios.nombre`, `comercios.nombre_corto` | Nombre del comercio |
| `id_producto`, `producto` | `anuncios.id_producto`, `productos.descripcion` | Comparable (o `NULL`) |
| `ean`, `nombre_original`, `subcategoria`, `url_producto`, `comparable` | `anuncios` | Ver `anuncios` |
| `marca`, `laboratorio`, `principio_activo`, `concentracion`, `forma` | `anuncios.*_std` | Campos estandarizados |
| `unidades`, `contenido`, `unidad_contenido`, `contenido_total`, `unidad_normalizada` | `anuncios` | Contenido de la presentación |
| `precio_unitario` | `precio / anuncios.contenido_total` | COP por mL, g o unidad (según `unidad_normalizada`) |

### `v_ultimo_precio`

La observación más reciente, no descartada, de cada anuncio. Tiene las mismas columnas de
`v_observaciones` más `orden` (siempre 1), que sale de `ROW_NUMBER()`.

### `v_cambios_precio`

Cambios de precio del mismo anuncio entre observaciones consecutivas (`LAG` por comercio y SKU, en
orden de fecha). No se tienen en cuenta las ejecuciones fallidas ni las observaciones descartadas, y
solo aparecen las filas en que el precio cambió.

| Columna | Significado | Unidad / valores posibles |
|---|---|---|
| `id_ejecucion`, `id_comercio`, `comercio`, `sku_comercio` | Observación posterior | — |
| `nombre_original`, `id_producto`, `subcategoria` | Datos del anuncio | — |
| `id_ejecucion_anterior`, `fecha_anterior`, `precio_anterior` | Observación anterior del mismo anuncio | precio en COP |
| `fecha_consulta`, `precio` | Observación posterior | precio en COP |
| `cambio_cop` | `precio - precio_anterior` | COP (negativo = bajó) |
| `cambio_pct` | Cambio frente al precio anterior | %, 2 decimales |
| `direccion` | Sentido del cambio | `subió`, `bajó` |

### `v_comparables`

Observaciones no descartadas de las presentaciones comparables, con su precio por unidad de
contenido. El contenido sale de `productos`, que se verificó a mano.

| Columna | Significado | Unidad / valores posibles |
|---|---|---|
| `id_observacion`, `id_ejecucion`, `fecha_consulta`, `id_comercio`, `comercio` | Observación | — |
| `id_producto`, `producto`, `principio_activo` | Comparable | `P01` … `P10` |
| `sku_comercio`, `nombre_original`, `url_producto` | Anuncio | — |
| `contenido_total`, `unidad_normalizada` | Contenido del comparable | `mL`, `g`, `unidad` |
| `precio`, `precio_lista`, `promocion`, `disponibilidad` | Ver `observaciones` | COP |
| `precio_unitario` | `precio / contenido_total` | COP por mL, g o unidad |

### `v_ejecuciones_completas`

Ejecuciones en que **todos** los comercios activos quedaron `completa`.

| Columna | Significado | Unidad / valores posibles |
|---|---|---|
| `id_ejecucion` | Ejecución | — |
| `inicio`, `fin` | Primer inicio y último fin entre los comercios | ISO 8601 (-05:00) |
| `fecha` | Fecha del inicio | `AAAA-MM-DD` |

### `v_disponibilidad`

Situación de cada anuncio en cada ejecución.

| Columna | Significado | Unidad / valores posibles |
|---|---|---|
| `id_ejecucion`, `id_comercio`, `sku_comercio` | Anuncio en una ejecución | — |
| `situacion` | Qué pasó con el anuncio | `disponible` y `agotado` (lo dice el sitio); `no observado` (el anuncio ya se había visto en ese comercio, pero no apareció en esta ejecución, que no falló). **No observado no significa agotado.** |

### `v_resumen_ejecucion`

Resumen de cada ejecución y comercio. Es lo que muestra la aplicación al terminar una actualización.

| Columna | Significado | Unidad / valores posibles |
|---|---|---|
| `id_ejecucion`, `id_comercio`, `comercio`, `modo`, `estado`, `inicio`, `fin`, `detalle` | Ver `ejecuciones` | — |
| `recolectados` | Observaciones no descartadas de esa ejecución | anuncios |
| `nuevos` | Anuncios que se observaron por primera vez | anuncios |
| `cambios_precio` | Anuncios cuyo precio cambió frente a su observación anterior | anuncios |
| `no_observados` | Anuncios conocidos que no aparecieron | anuncios |
| `rechazados` | Observaciones rechazadas por la validación | filas |
