# Diccionario de datos — `comparador_precios.sqlite`

Base SQLite del comparador de precios de protectores solares (Taller 2). Moneda: pesos colombianos (COP). Fechas: texto ISO 8601 con zona horaria de Colombia (`-05:00`). Un dato que no se pudo extraer queda como `NULL`; nunca se reemplaza por un valor calculado.

**Terminología.** Una *corrida* (tabla `corridas`) es una ejecución completa del scraper sobre los tres comercios; en la aplicación se muestra como **«Ejecución»**. Cada corrida tiene una *ejecución por comercio* (tabla `ejecuciones`).

---

## Tablas

### `corridas`
Una fila por ejecución completa (los tres comercios).

| Columna | Tipo | Unidad | Significado | Valores posibles |
|---|---|---|---|---|
| `id_corrida` | INTEGER PK | — | Identificador de la ejecución completa | autoincremental |
| `fecha_hora_inicio` | TEXT | ISO 8601 | Inicio de la corrida | — |
| `fecha_hora_fin` | TEXT | ISO 8601 | Fin de la corrida | NULL si no terminó |
| `n_total_observaciones` | INTEGER | observaciones | Observaciones insertadas en la corrida | ≥ 0 |
| `estado` | TEXT | — | Estado global | `completa` (todas las ejecuciones completas), `parcial`, `fallida` (todas fallaron) |
| `modo` | TEXT | — | Origen de los datos (Taller 2) | `en_linea`, `sin_conexion` (reprocesa `raw/`) |
| `fecha_datos` | TEXT | ISO 8601 | Fecha de consulta más reciente de sus observaciones; ordena las corridas en el tiempo (Taller 2) | NULL si no insertó observaciones |
| `motivo` | TEXT | — | Observaciones generales (Taller 2) | texto libre |

### `ejecuciones`
Una fila por comercio dentro de cada corrida.

| Columna | Tipo | Unidad | Significado | Valores posibles |
|---|---|---|---|---|
| `id_ejecucion` | INTEGER PK | — | Identificador | autoincremental |
| `id_corrida` | INTEGER FK | — | Corrida a la que pertenece | `corridas.id_corrida` |
| `fecha_hora_inicio`, `fecha_hora_fin` | TEXT | ISO 8601 | Inicio y fin de la ejecución del comercio | — |
| `comercio` | TEXT | — | Comercio | `Bella Piel`, `La Rebaja`, `Locatel` |
| `total_reportado_sitio` | INTEGER | productos | Total de la categoría informado por el sitio (encabezado `resources` de la API VTEX) | NULL si el sitio no lo informó |
| `total_obtenido` | INTEGER | productos | Productos (SKU) recolectados, válidos + rechazados | ≥ 0 |
| `n_registros` | INTEGER | observaciones | Observaciones insertadas (las ya existentes no se duplican) | ≥ 0 |
| `estado` | TEXT | — | Estado de la ejecución | `completa` (sin fallas, total obtenido ≥ total reportado y ≥ 8 comparables), `parcial`, `fallida` (ninguna observación válida o inserción revertida) |
| `modo` | TEXT | — | Origen (Taller 2) | `en_linea`, `sin_conexion` |
| `archivo_raw` | TEXT | ruta relativa | Copia cruda de origen en `raw/<comercio>/<fecha>/` (Taller 2) | NULL si no se obtuvo ninguna página |
| `n_rechazadas` | INTEGER | observaciones | Rechazadas por la validación (Taller 2) | ≥ 0 |
| `n_productos_nuevos` | INTEGER | anuncios | Anuncios observados por primera vez en ese comercio (Taller 2) | ≥ 0 |
| `n_cambios_precio` | INTEGER | anuncios | Anuncios cuyo precio cambió frente a su observación previa (Taller 2) | ≥ 0 |
| `n_no_observados` | INTEGER | anuncios | Anuncios de la consulta previa del comercio que no aparecieron en esta (Taller 2) | ≥ 0 |
| `comparables_encontrados` | INTEGER | productos | Productos comparables distintos encontrados (Taller 2) | 0 a 11 |
| `motivo` | TEXT | — | Motivo de falla o estado parcial (error de red, bloqueo, cambio de estructura, faltantes) (Taller 2) | texto libre |

### `productos_comparables`
Catálogo de las 11 presentaciones idénticas presentes en los tres comercios.

| Columna | Tipo | Unidad | Significado | Valores posibles |
|---|---|---|---|---|
| `id_producto_comun` | TEXT PK | — | Código del producto comparable | p. ej. `ANTHELIOS_UVMUNE_400_50ML` |
| `nombre_estandar` | TEXT | — | Nombre estandarizado | — |
| `marca_estandar` | TEXT | — | Marca | — |
| `categoria_estandar` | TEXT | — | Tipo de protector | `Protector Facial`, `Protector Infantil` |
| `presentacion_estandar` | TEXT | — | Presentación | p. ej. `Frasco 50 ml` |
| `contenido_valor` | REAL | mL o g | Contenido total de la presentación | > 0 |
| `contenido_unidad` | TEXT | — | Unidad normalizada | `mL`, `g` |
| `ean` | TEXT | — | Código EAN-13 | 13 dígitos |

### `observaciones`
Una fila por anuncio (SKU) de un comercio en una consulta. Restricción de unicidad `uq_comercio_prod_fecha (comercio, id_producto_comercio, fecha_hora_consulta)`: impide insertar dos veces la misma observación. Disparadores `trg_obs_dominios_ins/upd` rechazan valores fuera de dominio en disponibilidad, unidad y precio.

| Columna | Tipo | Unidad | Significado | Valores posibles |
|---|---|---|---|---|
| `id_observacion` | INTEGER PK | — | Identificador | autoincremental |
| `id_corrida` | INTEGER FK | — | Corrida | `corridas.id_corrida` |
| `id_ejecucion` | INTEGER FK | — | Ejecución del comercio (lleva a `archivo_raw`) | `ejecuciones.id_ejecucion` |
| `comercio` | TEXT | — | Comercio | `Bella Piel`, `La Rebaja`, `Locatel` |
| `id_producto_comercio` | TEXT | — | SKU del anuncio en el comercio (`items[].itemId`) | — |
| `nombre_original` | TEXT | — | Nombre del anuncio tal como lo publica el sitio (`productName`) | — |
| `presentacion_original` | TEXT | — | Nombre del SKU (`items[].name`) | — |
| `descripcion_original` | TEXT | — | Descripción del anuncio (HTML original) | — |
| `marca_original` | TEXT | — | Marca según el sitio (`brand`) | — |
| `subcategoria_original` | TEXT | — | Última categoría del sitio | — |
| `precio_actual` | REAL | COP | Precio de venta (`commertialOffer.Price`) | > 0 o NULL |
| `precio_lista` | REAL | COP | Precio de lista (`ListPrice`) | > 0 o NULL |
| `es_promocion` | INTEGER | — | 1 si el precio de lista es mayor que el precio actual | 0, 1 |
| `url` | TEXT | — | Enlace al anuncio | URL http(s) |
| `pum_original` | TEXT | — | Precio por unidad publicado por el sitio (no lo publican estos comercios) | NULL |
| `fecha_hora_consulta` | TEXT | ISO 8601 | Momento de la consulta (igual al `timestamp` de la copia cruda) | — |
| `comparable` | INTEGER | — | 1 si corresponde a un producto del catálogo comparable | 0, 1 |
| `id_producto_comun` | TEXT FK | — | Producto comparable | `productos_comparables.id_producto_comun` o NULL |
| `contenido_valor` | REAL | mL, g o unidad | Contenido total normalizado de la presentación | > 0 o NULL (combos o sin contenido) |
| `contenido_unidad` | TEXT | — | Unidad normalizada | `mL`, `g`, `unidad`, NULL |
| `precio_por_unidad` | REAL | COP/mL, COP/g o COP/unidad | `precio_actual / contenido_valor` | NULL si falta alguno |
| `en_categoria` | INTEGER | — | 1 si pertenece a la categoría (protectores faciales, corporales, labiales, infantiles y después del sol) | 0, 1 |
| `motivo_exclusion` | TEXT | — | Regla de exclusión aplicada | p. ej. `Kit o combo que mezcla productos distintos`; NULL si `en_categoria = 1` |
| `ean` | TEXT | — | EAN/GTIN válido (8, 12, 13 o 14 dígitos) | NULL si el sitio no da un EAN válido |
| `estado_disponibilidad` | TEXT | — | Disponibilidad informada por el sitio (`commertialOffer.IsAvailable`) (Taller 2) | `disponible`, `agotado`, NULL (el sitio no informa). El estado `no_observado` no se guarda aquí: se deriva en `v_disponibilidad` |
| `subcategoria_estandar` | TEXT | — | Subcategoría estandarizada por reglas sobre el nombre (Taller 2) | `Facial`, `Facial con color`, `Corporal`, `Infantil`, `Labial`, `Después del sol`, `Bronceador`, `Fuera de la categoría` |
| `marca_estandar` | TEXT | — | Marca con mayúsculas y alias unificados (Taller 2) | p. ej. `La Roche Posay` |
| `ean_original` | TEXT | — | Valor original del campo `ean` del sitio, aunque no sea un EAN (Taller 2) | texto |
| `descartada` | INTEGER | — | 1 si la observación se descarta del análisis por un error documentado (no se borra) (Taller 2) | 0, 1 |
| `motivo_descarte` | TEXT | — | Motivo del descarte (Taller 2) | texto o NULL |

### `observaciones_rechazadas` (Taller 2)
Observaciones que no superaron la validación y por tanto no se insertaron.

| Columna | Tipo | Unidad | Significado |
|---|---|---|---|
| `id_rechazo` | INTEGER PK | — | Identificador |
| `id_corrida`, `id_ejecucion` | INTEGER FK | — | Corrida y ejecución en que se recolectó |
| `comercio`, `id_producto_comercio`, `nombre_original`, `url`, `fecha_hora_consulta` | TEXT | — | Datos del anuncio rechazado |
| `precio_actual` | REAL | COP | Precio recolectado (puede ser NULL) |
| `motivo` | TEXT | — | Reglas incumplidas: R1 precio, R2 campos obligatorios, R3 duplicado, R4 URL, R5 unidad, R6 disponibilidad |
| `fecha_registro` | TEXT | ISO 8601 | Momento del rechazo |

### `correcciones` (Taller 2)
Registro de cada corrección hecha sobre los datos del Taller 1.

| Columna | Tipo | Significado |
|---|---|---|
| `id_correccion` | INTEGER PK | Identificador |
| `fecha_correccion` | TEXT | Fecha y hora de la corrección |
| `tabla` | TEXT | Tabla afectada (`observaciones`, `ejecuciones`) |
| `id_registro` | INTEGER | Clave primaria del registro afectado |
| `campo` | TEXT | Columna corregida |
| `valor_anterior`, `valor_nuevo` | TEXT | Valores antes y después |
| `motivo` | TEXT | Razón de la corrección |

---

## Vistas (las usa la aplicación directamente)

| Vista | Qué devuelve | Uso en la aplicación |
|---|---|---|
| `v_corridas` | Corridas que tienen observaciones, con `fecha_datos`, número de observaciones y comercios, y `orden` cronológico (1 = la más antigua) | Selector de ejecución, «última ejecución» |
| `v_observaciones` | Observaciones no descartadas con `fecha_corrida` y `orden_corrida` | Base de filtros, tabla, indicadores y distribución |
| `v_ultimo_precio` | Para cada comercio, las observaciones de su corrida más reciente con datos | Consulta del último precio publicado |
| `v_comparables` | Observaciones comparables con precio, unidos al catálogo, con `precio_minimo_corrida`, `diferencia_vs_minimo`, `es_mas_barato` (empates = 1 en todos) y `n_comercios_con_precio` por corrida y producto | Precio unitario, evolución, ahorro, sobrecosto y canasta |
| `v_cambios_precio` | Para cada anuncio, el precio frente a su observación anterior: `cambio_cop`, `cambio_pct` y `direccion` (`subió`, `bajó`, `sin cambio`) | Verificación de cambios entre corridas consecutivas |
| `v_disponibilidad` | Estado de cada anuncio en cada corrida, desde la primera vez que se vio: `disponible`, `agotado`, `sin_informacion` o `no_observado` | Gráfico de disponibilidad |
| `v_resumen_ejecuciones` | Resumen por ejecución de comercio: modo, estado, recolectados, insertados, rechazados, nuevos, cambios, no observados, copia cruda y motivo | Historial y página de calidad |

## Índices
`idx_obs_corrida`, `idx_obs_comun`, `idx_obs_comercio`, `idx_obs_ejecucion`, `idx_obs_en_cat`, `idx_obs_subcat`, `idx_obs_marca`, `idx_obs_precio`, `idx_obs_promo`, `idx_obs_fecha`, `idx_obs_comercio_anuncio (comercio, id_producto_comercio, id_corrida)`, `idx_rech_ejecucion`, `idx_corr_registro`. Cubren las columnas de los filtros de la aplicación (comercio, subcategoría, marca, precio, promoción, ejecución, fechas, comparables) y las uniones de la comparación entre corridas.
