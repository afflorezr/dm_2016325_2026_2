# Diccionario de datos — `comparador_precios.sqlite`

Categoría: *Primeros auxilios y curación*. Comercios: Farmatodo, La Rebaja y Locatel.
Moneda: pesos colombianos (COP). Fechas y horas en formato ISO 8601 con hora de
Colombia (`-05:00`). Todos los datos provienen del scraping; cada observación se
rastrea hasta `raw/<comercio>/<captura>/` mediante `ejecuciones.ruta_raw`.

Un dato que el sitio no entrega queda `NULL`; nunca se completa ni se calcula.

## Tablas

### `comercios`
| Columna | Tipo | Significado |
|---|---|---|
| id_comercio | INTEGER (PK) | Identificador del comercio. |
| nombre | TEXT, único | `Farmatodo`, `La Rebaja` o `Locatel`. |

### `productos_comparables`
Los ocho productos idénticos en los tres comercios.
| Columna | Tipo | Significado |
|---|---|---|
| id_comparable | INTEGER (PK) | Identificador del producto comparable (1 a 8). |
| nombre_comun | TEXT | Nombre común del producto. |
| marca_comun | TEXT | Marca. |
| contenido_valor | REAL | Contenido de la presentación. |
| contenido_unidad | TEXT | Unidad del contenido: `mL`, `m`, `unidad` o `sobre`. |
| regla_correspondencia | TEXT | Regla con que se identificó el producto en cada comercio (EAN o expresión regular). |

### `anuncios`
Cada producto tal como aparece en un comercio. Único por `(id_comercio, sku)`.
| Columna | Tipo | Significado |
|---|---|---|
| id_anuncio | INTEGER (PK) | Identificador del anuncio. |
| id_comercio | INTEGER (FK) | Comercio que lo publica. |
| sku | TEXT | Código del producto en el comercio. |
| ean | TEXT | Código de barras (solo La Rebaja y Locatel; Farmatodo no lo publica). |
| nombre_original | TEXT | Nombre tal como lo muestra el sitio. |
| descripcion_original | TEXT | Descripción del sitio (solo La Rebaja y Locatel). |
| marca_original | TEXT | Marca tal como la muestra el sitio. |
| presentacion_texto_origen | TEXT | Texto de presentación publicado por el sitio. |
| contenido_origen, contenido_unidad_origen | TEXT | Contenido y unidad que publica el sitio (no siempre es el contenido real). |
| subcategoria_origen | TEXT | Subcategoría del sitio. |
| url | TEXT | Enlace al anuncio. |
| contenido_valor | REAL | Contenido verificado, solo para comparables. |
| contenido_unidad | TEXT | Unidad verificada: `mL`, `m`, `unidad`, `sobre`. Solo comparables. |
| contenido_total | REAL | Contenido total normalizado de la presentación comparable (copia de `contenido_valor`). `NULL` si no es comparable. |
| unidad_normalizada | TEXT | `mL`, `g`, `unidad` o `m` (metros de cinta). `sobre` se normaliza a `unidad`. `NULL` si no es comparable. |
| comparable | INTEGER | 1 si es uno de los ocho comparables, 0 si no. |
| id_comparable | INTEGER (FK) | Producto comparable al que corresponde. |
| incluido | INTEGER | 1 si pertenece a la categoría; 0 si se excluyó por regla explícita. |
| motivo_exclusion | TEXT | Regla que lo excluyó. |
| nombre_estandar | TEXT | Nombre en minúsculas, sin tildes ni signos. |
| marca | TEXT | Marca estandarizada (mayúsculas, sin tildes ni espacios). |
| subcategoria | TEXT | Subcategoría común a los tres comercios, asignada por reglas. |

### `ejecuciones`
Una fila por corrida y comercio.
| Columna | Tipo | Significado |
|---|---|---|
| id_ejecucion | TEXT (PK) | `comercio_AAAA-MM-DD` (históricas) o `comercio_AAAA-MM-DD_HHMMSS`. |
| id_comercio | INTEGER (FK) | Comercio consultado. |
| fecha_hora_inicio | TEXT | Hora de la captura. |
| registros | INTEGER | Filas recolectadas (una por SKU). |
| productos | INTEGER | Productos distintos recolectados. |
| total_sitio | INTEGER | Total de productos que declara el sitio (`NULL` en Farmatodo). |
| estado | TEXT | `completa`, `parcial` o `fallida`. |
| modo | TEXT | `online` u `offline` (modo con que se realizó la captura). |
| mensaje | TEXT | Motivo cuando no es completa (errores del sitio, comparables ausentes, fallo de inserción). |
| rechazadas | INTEGER | Observaciones que no superaron la validación. |
| ruta_raw | TEXT | Carpeta con las copias crudas de la captura. |

### `observaciones`
Precio de un anuncio en una captura. Único por `(id_anuncio, fecha_hora_consulta)`.
| Columna | Tipo | Significado |
|---|---|---|
| id_observacion | INTEGER (PK) | Identificador. |
| id_anuncio | INTEGER (FK) | Anuncio observado. |
| id_ejecucion | TEXT (FK) | Ejecución a la que pertenece. |
| fecha_hora_consulta | TEXT | Momento de la consulta. |
| precio | REAL | Precio vigente en COP. `NULL` si el sitio no lo publica (agotado). Nunca 0. |
| precio_antes | REAL | Precio anterior o de lista, si hay promoción. |
| es_promocion | INTEGER | 1 si el sitio muestra un precio anterior mayor al vigente. |
| disponible | INTEGER | 1 disponible; 0 agotado según el sitio. |
| vendedor | TEXT | Vendedor indicado por el sitio. |

La disponibilidad tiene **tres estados**: *disponible* (`disponible = 1`), *agotado
según el sitio* (`disponible = 0`) y *no observado* (el anuncio no aparece en la
ejecución; no significa agotado ni retirado). El tercero se deriva en `v_disponibilidad`.

### `rechazadas`
Observaciones que no superaron la validación y no se insertaron.
| Columna | Tipo | Significado |
|---|---|---|
| id_rechazo | INTEGER (PK) | Identificador. |
| id_ejecucion | TEXT (FK) | Ejecución en que se rechazó. |
| comercio, sku, nombre_original, url, precio, fecha_hora_consulta | TEXT/REAL | Datos de la fila rechazada. |
| motivo | TEXT | Regla incumplida (por ejemplo, `Precio menor o igual a cero`). |
| fecha_registro | TEXT | Cuándo se registró. |

### `correcciones`
Cambios sobre datos ya guardados. No se borran observaciones.
| Columna | Tipo | Significado |
|---|---|---|
| id_correccion | INTEGER (PK) | Identificador. |
| fecha | TEXT | Fecha y hora de la corrección. |
| tabla | TEXT | Tabla (o documento) afectado. |
| registro | TEXT | Registro afectado. |
| campo | TEXT | Campo corregido. |
| valor_anterior, valor_nuevo | TEXT | Valores antes y después. |
| motivo | TEXT | Razón de la corrección. |

## Vistas

| Vista | Qué devuelve |
|---|---|
| `v_ejecuciones_orden` | Ejecuciones `completa` o `parcial` numeradas por comercio (`orden` 1 = la más reciente). |
| `v_ultimo_precio` | Estado actual: cada anuncio incluido con su observación de la última ejecución de su comercio. Columnas: `comercio`, `nombre`, `marca`, `subcategoria`, `url`, `precio` (COP), `precio_antes`, `es_promocion`, `disponibilidad` (`disponible`/`agotado`), `precio_unitario` (COP por `unidad_normalizada`, solo comparables) y `fecha`. |
| `v_precios` | Histórico: todas las observaciones de anuncios incluidos, con las mismas columnas que `v_ultimo_precio`. Permite consultar una captura anterior. |
| `v_disponibilidad` | Disponibilidad de cada anuncio incluido en la última ejecución: `disponible`, `agotado` o `no observado`. |
| `v_cambios_precio` | Compara las dos últimas ejecuciones de cada comercio para el mismo anuncio. `tipo`: `subió`, `bajó`, `igual`, `nuevo`, `no observado` o `sin comparación`. `cambio_cop` en COP y `cambio_pct` en %. |
| `v_comparables` | Observaciones de los ocho comparables con precio, una por anuncio y día. Incluye `precio_unitario` (COP por unidad normalizada) y `unidad_normalizada`. |
| `v_referencia` | Fecha más reciente que contiene los ocho comparables en los tres comercios. |

## Índices
`anuncios`: `id_comercio`, `subcategoria`, `marca`, `id_comparable`, `incluido`, `ean`.
`observaciones`: `id_ejecucion`, `precio`, `es_promocion`. `ejecuciones`:
`(id_comercio, fecha_hora_inicio)`. `rechazadas`: `id_ejecucion`. Además de las
restricciones de unicidad de `anuncios` y `observaciones`.
