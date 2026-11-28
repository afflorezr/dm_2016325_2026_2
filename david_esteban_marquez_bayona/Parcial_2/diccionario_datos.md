# Diccionario de datos · `comparador_precios.sqlite`

Taller 2 · Minería de Datos (2016325) · cuidado bucal. Moneda: pesos colombianos (COP). Fechas y horas en ISO 8601 con hora de Colombia (`-05:00`). Un dato que el sitio no publicó queda como `NULL`.

Relaciones: `observaciones` → `anuncios` (`anuncio_id`) → `productos` (`producto_id`); `observaciones` → `ejecuciones` (`ejecucion_id`, `comercio_id`) → `comercios`. Unicidad: una observación por (`comercio_id`, `sku_comercio`, `fecha_hora_consulta`) y por (`ejecucion_id`, `comercio_id`, `sku_comercio`); un anuncio por (`comercio_id`, `sku_comercio`).

## `comercios`

Comercios consultados (uno por fila).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `nombre` | TEXT | Nombre del comercio | — | Éxito, Olímpica, Locatel |
| `tipo` | TEXT | Tipo de comercio | — | texto |
| `url_base` | TEXT | Dirección del sitio | — | URL |
| `plataforma` | TEXT | Plataforma de comercio electrónico | — | `VTEX` |

## `ejecuciones`

Una fila por ejecución del scraper y comercio. Todas las observaciones remiten a una fila de esta tabla.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `inicio` | TEXT | Inicio de la ejecución en ese comercio | ISO 8601, -05:00 | fecha y hora |
| `fin` | TEXT | Fin de la ejecución en ese comercio | ISO 8601, -05:00 | fecha y hora |
| `modo_carga` | TEXT | Cómo se cargó la ejecución | — | `en_linea`, `sin_conexion` |
| `n_registros` | INTEGER | Filas (SKU) leídas del sitio | anuncios | entero ≥ 0 |
| `n_productos` | INTEGER | Productos distintos del sitio | productos | entero ≥ 0 |
| `total_reportado_sitio` | INTEGER | Total de productos que reporta el sitio para la categoría | productos | entero o NULL |
| `estado` | TEXT | Resultado de la ejecución | — | `completa`, `parcial`, `fallida` |
| `mensaje` | TEXT | Motivo de la falla, secciones incompletas, comparables faltantes o rechazos | — | texto o NULL |
| `carpeta_raw` | TEXT | Carpeta de las copias crudas de esa ejecución | — | ruta relativa `raw/<comercio>/<fecha>/<ejecución>` |
| `n_rechazadas` | INTEGER | Observaciones rechazadas por la validación (Taller 2) | observaciones | entero ≥ 0 |

## `secciones`

Secciones del sitio que se recorrieron como «cuidado bucal» en cada ejecución, con el total que reporta el sitio (verificación de categoría completa).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `seccion_id` | TEXT | Identificador de la sección en el sitio | — | texto |
| `nombre` | TEXT | Nombre de la sección | — | texto |
| `ruta_nombres` | TEXT | Ruta de la sección en el árbol de categorías | — | texto |
| `filtro` | TEXT | Filtro de categoría usado en la consulta | — | p. ej. `/34185083/34185114/` |
| `url` | TEXT | URL de la sección | — | URL o NULL |
| `api` | TEXT | Servicio consultado | — | `catalogo` |
| `total_reportado` | INTEGER | Productos que reporta el sitio en la sección | productos | entero o NULL |
| `n_obtenidos` | INTEGER | Productos obtenidos de la sección | productos | entero |
| `error` | TEXT | Error al recorrer la sección | — | texto o NULL |

## `anuncios`

Cada producto tal como lo publica un comercio (un SKU). Guarda el texto original sin modificar y los campos estandarizados por `limpieza.R`.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `sku_comercio` | TEXT | SKU del producto en el comercio | — | texto |
| `product_id_comercio` | TEXT | Identificador de producto del comercio | — | texto |
| `ean` | TEXT | Código de barras | — | en `anuncios`: el publicado por el comercio; en `productos` y vistas: GTIN-14 válido; NULL |
| `referencia` | TEXT | Referencia interna del comercio | — | texto o NULL |
| `nombre_original` | TEXT | Nombre del producto tal como lo publica el comercio | — | texto |
| `nombre_item_original` | TEXT | Nombre del SKU tal como lo publica el comercio | — | texto |
| `marca_original` | TEXT | Marca publicada por el comercio | — | texto |
| `categoria_original` | TEXT | Ruta de categoría publicada por el comercio | — | texto |
| `descripcion_original` | TEXT | Descripción publicada | — | texto o NULL |
| `ficha_tecnica_original` | TEXT | Ficha técnica publicada | — | JSON en texto o NULL |
| `texto_original` | TEXT | Texto original completo del anuncio (nombre, descripción y ficha) | — | texto |
| `url_producto` | TEXT | Enlace al anuncio | — | URL |
| `seccion_origen` | TEXT | Sección del sitio donde apareció | — | texto |
| `primera_consulta` | TEXT | Primera vez que se observó el anuncio | ISO 8601, -05:00 | fecha y hora |
| `ultima_consulta` | TEXT | Última vez que se observó el anuncio | ISO 8601, -05:00 | fecha y hora |
| `nombre_std` | TEXT | Nombre estandarizado del anuncio | — | texto |
| `marca_std` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria_std` | TEXT | Subcategoría estandarizada (R3, C2) | — | ver `subcategoria`; NULL si el anuncio se excluye |
| `contenido_unitario` | REAL | Contenido de una unidad del empaque | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `n_unidades` | INTEGER | Número de unidades del empaque | unidades | entero ≥ 1 |
| `contenido_total` | REAL | Contenido total = unitario × unidades | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `unidad` | TEXT | Unidad normalizada del contenido | — | en tablas: `ml`, `g`, `m`, `und`; en vistas: `mL`, `g`, `m`, `unidad`; NULL si no se pudo determinar |
| `concentracion` | TEXT | Concentración de flúor o principio activo (R6) | ppm o % | p. ej. `1450 ppm`, o NULL |
| `familia` | TEXT | Clave de familia: subcategoría, marca y nombre sin tamaño (R7) | — | texto |
| `ean_valido` | TEXT | GTIN-14 si el dígito de control es válido | — | 14 dígitos o NULL |
| `incluido` | INTEGER | El anuncio pertenece a cuidado bucal (R4) | — | 0, 1 |
| `motivo_exclusion` | TEXT | Motivo de la exclusión | — | texto o NULL |
| `alerta_limpieza` | TEXT | Alerta al extraer el contenido | — | texto o NULL |
| `metodo_correspondencia` | TEXT | Cómo se emparejó | — | `EAN`, `EAN + unidades`, `clave normalizada`, `clave normalizada (unida a EAN)`, `manual` |
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |

## `observaciones`

Precio y disponibilidad de un anuncio en una ejecución. Nunca se sobrescriben ni se borran.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `observacion_id` | INTEGER | Identificador de la observación | — | entero |
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `sku_comercio` | TEXT | SKU del producto en el comercio | — | texto |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `precio` | REAL | Precio de venta en el momento de la consulta | COP | número > 0; NULL si el sitio no lo publicó (nunca 0) |
| `precio_lista` | REAL | Precio sin descuento | COP | número > 0 o NULL |
| `es_promocion` | INTEGER | El precio de venta es menor que el de lista | — | 0, 1 |
| `texto_promocion` | TEXT | Texto de la promoción publicado por el sitio | — | texto o NULL |
| `disponible` | INTEGER | Disponibilidad según el sitio (campo del Taller 1) | — | 1, 0 o NULL |
| `vendedor` | TEXT | Vendedor que ofrece el precio | — | texto |
| `url_fuente` | TEXT | URL de la respuesta de la que se extrajo el dato | — | URL |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |
| `disponibilidad` | TEXT | Estado de disponibilidad de la observación (Taller 2) | — | `disponible`, `agotado` (según el sitio) o NULL (sin dato). «No observado» no se guarda: se deriva en `v_disponibilidad` |
| `descartada` | INTEGER | Observación descartada por una corrección (Taller 2) | — | 0, 1 |
| `motivo_descarte` | TEXT | Motivo del descarte | — | texto o NULL |

## `productos`

Presentación común entre comercios (correspondencia R8). Se recalcula en cada actualización.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `nombre_estandar` | TEXT | Nombre estándar de la presentación | — | texto |
| `marca` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria` | TEXT | Subcategoría estandarizada (R3, C2) | — | Crema dental, Cepillo dental, Enjuague bucal, Seda e hilo dental, … |
| `familia` | TEXT | Clave de familia: subcategoría, marca y nombre sin tamaño (R7) | — | texto |
| `contenido_unitario` | REAL | Contenido de una unidad del empaque | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `n_unidades` | INTEGER | Número de unidades del empaque | unidades | entero ≥ 1 |
| `contenido_total` | REAL | Contenido total = unitario × unidades | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `unidad` | TEXT | Unidad normalizada del contenido | — | en tablas: `ml`, `g`, `m`, `und`; en vistas: `mL`, `g`, `m`, `unidad`; NULL si no se pudo determinar |
| `concentracion` | TEXT | Concentración de flúor o principio activo (R6) | ppm o % | p. ej. `1450 ppm`, o NULL |
| `ean` | TEXT | Código de barras | — | en `anuncios`: el publicado por el comercio; en `productos` y vistas: GTIN-14 válido; NULL |
| `metodo_correspondencia` | TEXT | Cómo se emparejó | — | `EAN`, `EAN + unidades`, `clave normalizada`, `clave normalizada (unida a EAN)`, `manual` |
| `n_comercios` | INTEGER | Comercios en los que aparece la presentación | comercios | 1 a 3 |
| `alerta` | TEXT | Alertas de la correspondencia (contenidos, marcas o subcategorías distintas en el grupo) | — | texto o NULL |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |
| `contenido_verificado` | INTEGER | Todos los anuncios de la presentación declaran el mismo contenido y unidad; condición para calcular precio unitario (Taller 2) | — | 0, 1 |

## `familias`

Nombre legible de cada familia de productos (mismo producto en distintos tamaños).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `familia` | TEXT | Clave de familia: subcategoría, marca y nombre sin tamaño (R7) | — | texto |
| `nombre_familia` | TEXT | Nombre legible de la familia | — | texto |

## `parametros`

Parámetros de la correspondencia: ejecución de referencia y sus comercios.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `clave` | TEXT | Nombre del parámetro | — | `ejecucion_referencia`, `comercios_referencia` |
| `valor` | TEXT | Valor del parámetro | — | texto |

## `correcciones`

Correcciones a campos estandarizados o descartes de observaciones (Taller 2). No se borra nada: se reaplican en cada actualización.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `correccion_id` | INTEGER | Identificador de la corrección | — | entero |
| `fecha` | TEXT | Fecha y hora de la corrección | ISO 8601, -05:00 | fecha y hora |
| `tabla` | TEXT | Tabla del registro afectado | — | `anuncios`, `observaciones` |
| `registro_id` | TEXT | Identificador del registro afectado (`anuncio_id` u `observacion_id`) | — | texto |
| `campo` | TEXT | Campo corregido | — | `contenido_total`, `contenido_unitario`, `unidad`, `nombre_std`, `subcategoria_std`, `marca_std`, `n_unidades`, `incluido`, `descartada` |
| `valor_anterior` | TEXT | Valor antes de la corrección | — | texto o NULL |
| `valor_nuevo` | TEXT | Valor corregido | — | texto |
| `motivo` | TEXT | Motivo de la corrección o del rechazo | — | texto |
| `regla` | TEXT | Regla que originó la corrección | — | `C1`, `C2`, `manual` |
| `activa` | INTEGER | La corrección se aplica | — | 1, 0 |

## `observaciones_rechazadas`

Filas del scraper que no pasaron la validación y por eso no entraron a `observaciones` (Taller 2).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `rechazo_id` | INTEGER | Identificador del rechazo | — | entero |
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `sku_comercio` | TEXT | SKU del producto en el comercio | — | texto |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `precio` | TEXT | Precio tal como llegó (puede no ser numérico) | COP | texto o NULL |
| `url_fuente` | TEXT | URL de la respuesta de la que se extrajo el dato | — | URL |
| `nombre_original` | TEXT | Nombre del producto tal como lo publica el comercio | — | texto |
| `motivo` | TEXT | Motivo de la corrección o del rechazo | — | texto |
| `fecha_registro` | TEXT | Fecha y hora del rechazo | ISO 8601, -05:00 | fecha y hora |

## `comparables_referencia`

Los ocho productos comparables que debe traer cada ejecución en cada comercio (Taller 2).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `orden` | INTEGER | Orden del comparable de referencia | — | 1 a 8 |
| `criterio` | TEXT | Criterio con el que se eligió | — | texto |
| `fecha_seleccion` | TEXT | Fecha y hora de la selección | ISO 8601, -05:00 | fecha y hora |

## `v_catalogo`

Vista. Una fila por observación vigente (anuncio incluido y observación no descartada). Base de filtros, tabla e indicadores.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `observacion_id` | INTEGER | Identificador de la observación | — | entero |
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `comercio` | TEXT | Nombre del comercio | — | Éxito, Olímpica, Locatel |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `sku_comercio` | TEXT | SKU del producto en el comercio | — | texto |
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `nombre` | TEXT | Nombre estandarizado del anuncio (o el original si no hay) | — | texto |
| `nombre_original` | TEXT | Nombre del producto tal como lo publica el comercio | — | texto |
| `texto_original` | TEXT | Texto original completo del anuncio (nombre, descripción y ficha) | — | texto |
| `marca` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria` | TEXT | Subcategoría estandarizada (R3, C2) | — | Crema dental, Cepillo dental, Enjuague bucal, Seda e hilo dental, … |
| `contenido_total` | REAL | Contenido total = unitario × unidades | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `n_unidades` | INTEGER | Número de unidades del empaque | unidades | entero ≥ 1 |
| `unidad` | TEXT | Unidad normalizada del contenido | — | en tablas: `ml`, `g`, `m`, `und`; en vistas: `mL`, `g`, `m`, `unidad`; NULL si no se pudo determinar |
| `presentacion` | TEXT | Presentación legible | — | p. ej. `3 x 75 mL`, `150 mL`, `2 unidades`; NULL |
| `precio` | REAL | Precio de venta en el momento de la consulta | COP | número > 0; NULL si el sitio no lo publicó (nunca 0) |
| `precio_lista` | REAL | Precio sin descuento | COP | número > 0 o NULL |
| `precio_unitario` | REAL | Precio por unidad de contenido = precio / contenido total | COP por mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `es_promocion` | INTEGER | El precio de venta es menor que el de lista | — | 0, 1 |
| `texto_promocion` | TEXT | Texto de la promoción publicado por el sitio | — | texto o NULL |
| `disponibilidad` | TEXT | Estado de disponibilidad de la observación (Taller 2) | — | `disponible`, `agotado` (según el sitio) o NULL (sin dato). «No observado» no se guarda: se deriva en `v_disponibilidad` |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `fecha` | TEXT | Fecha de la consulta | AAAA-MM-DD | fecha |
| `url_producto` | TEXT | Enlace al anuncio | — | URL |
| `url_fuente` | TEXT | URL de la respuesta de la que se extrajo el dato | — | URL |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |
| `carpeta_raw` | TEXT | Carpeta de las copias crudas de esa ejecución | — | ruta relativa `raw/<comercio>/<fecha>/<ejecución>` |

## `v_ultimo_precio`

Vista. Observación más reciente de cada anuncio (columnas de `v_catalogo` más las indicadas).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `observacion_id` | INTEGER | Identificador de la observación | — | entero |
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `comercio` | TEXT | Nombre del comercio | — | Éxito, Olímpica, Locatel |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `sku_comercio` | TEXT | SKU del producto en el comercio | — | texto |
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `nombre` | TEXT | Nombre estandarizado del anuncio (o el original si no hay) | — | texto |
| `nombre_original` | TEXT | Nombre del producto tal como lo publica el comercio | — | texto |
| `texto_original` | TEXT | Texto original completo del anuncio (nombre, descripción y ficha) | — | texto |
| `marca` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria` | TEXT | Subcategoría estandarizada (R3, C2) | — | Crema dental, Cepillo dental, Enjuague bucal, Seda e hilo dental, … |
| `contenido_total` | REAL | Contenido total = unitario × unidades | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `n_unidades` | INTEGER | Número de unidades del empaque | unidades | entero ≥ 1 |
| `unidad` | TEXT | Unidad normalizada del contenido | — | en tablas: `ml`, `g`, `m`, `und`; en vistas: `mL`, `g`, `m`, `unidad`; NULL si no se pudo determinar |
| `presentacion` | TEXT | Presentación legible | — | p. ej. `3 x 75 mL`, `150 mL`, `2 unidades`; NULL |
| `precio` | REAL | Precio de venta en el momento de la consulta | COP | número > 0; NULL si el sitio no lo publicó (nunca 0) |
| `precio_lista` | REAL | Precio sin descuento | COP | número > 0 o NULL |
| `precio_unitario` | REAL | Precio por unidad de contenido = precio / contenido total | COP por mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `es_promocion` | INTEGER | El precio de venta es menor que el de lista | — | 0, 1 |
| `texto_promocion` | TEXT | Texto de la promoción publicado por el sitio | — | texto o NULL |
| `disponibilidad` | TEXT | Estado de disponibilidad de la observación (Taller 2) | — | `disponible`, `agotado` (según el sitio) o NULL (sin dato). «No observado» no se guarda: se deriva en `v_disponibilidad` |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `fecha` | TEXT | Fecha de la consulta | AAAA-MM-DD | fecha |
| `url_producto` | TEXT | Enlace al anuncio | — | URL |
| `url_fuente` | TEXT | URL de la respuesta de la que se extrajo el dato | — | URL |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |
| `carpeta_raw` | TEXT | Carpeta de las copias crudas de esa ejecución | — | ruta relativa `raw/<comercio>/<fecha>/<ejecución>` |
| `ultima_ejecucion` | TEXT | Última ejecución no fallida del comercio | — | ver `ejecucion_id` |
| `estado_actual` | TEXT | Estado del anuncio frente a la última ejecución de su comercio | — | `disponible`, `agotado`, `no observado`, `sin dato` |

## `v_cambios_precio`

Vista. Observaciones cuyo precio difiere del de la observación anterior del mismo anuncio.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `ejecucion_anterior` | TEXT | Ejecución de la observación anterior del anuncio | — | ver `ejecucion_id` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `comercio` | TEXT | Nombre del comercio | — | Éxito, Olímpica, Locatel |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `nombre` | TEXT | Nombre estandarizado del anuncio (o el original si no hay) | — | texto |
| `marca` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria` | TEXT | Subcategoría estandarizada (R3, C2) | — | Crema dental, Cepillo dental, Enjuague bucal, Seda e hilo dental, … |
| `presentacion` | TEXT | Presentación legible | — | p. ej. `3 x 75 mL`, `150 mL`, `2 unidades`; NULL |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |
| `precio_anterior` | REAL | Precio en la observación anterior | COP | número > 0 |
| `precio` | REAL | Precio de venta en el momento de la consulta | COP | número > 0; NULL si el sitio no lo publicó (nunca 0) |
| `cambio_cop` | REAL | Cambio de precio | COP | número distinto de 0 |
| `cambio_pct` | REAL | Cambio de precio relativo al precio anterior | % | número distinto de 0 |
| `tipo_cambio` | TEXT | Sentido del cambio | — | `subió`, `bajó` |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `url_producto` | TEXT | Enlace al anuncio | — | URL |

## `v_comparables`

Vista. Un precio por presentación comparable, comercio y ejecución (el anuncio disponible más barato).

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `producto` | TEXT | Nombre estándar de la presentación | — | texto |
| `marca` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria` | TEXT | Subcategoría estandarizada (R3, C2) | — | Crema dental, Cepillo dental, Enjuague bucal, Seda e hilo dental, … |
| `contenido_total` | REAL | Contenido total = unitario × unidades | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `unidad` | TEXT | Unidad normalizada del contenido | — | en tablas: `ml`, `g`, `m`, `und`; en vistas: `mL`, `g`, `m`, `unidad`; NULL si no se pudo determinar |
| `presentacion` | TEXT | Presentación legible | — | p. ej. `3 x 75 mL`, `150 mL`, `2 unidades`; NULL |
| `contenido_verificado` | INTEGER | Todos los anuncios de la presentación declaran el mismo contenido y unidad; condición para calcular precio unitario (Taller 2) | — | 0, 1 |
| `orden_referencia` | INTEGER | Orden si es uno de los ocho comparables de referencia | — | 1 a 8 o NULL |
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `comercio` | TEXT | Nombre del comercio | — | Éxito, Olímpica, Locatel |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `precio` | REAL | Precio de venta en el momento de la consulta | COP | número > 0; NULL si el sitio no lo publicó (nunca 0) |
| `precio_lista` | REAL | Precio sin descuento | COP | número > 0 o NULL |
| `precio_unitario` | REAL | Precio por unidad de contenido = precio / contenido total | COP por mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `es_promocion` | INTEGER | El precio de venta es menor que el de lista | — | 0, 1 |
| `disponibilidad` | TEXT | Estado de disponibilidad de la observación (Taller 2) | — | `disponible`, `agotado` (según el sitio) o NULL (sin dato). «No observado» no se guarda: se deriva en `v_disponibilidad` |
| `comprable` | INTEGER | Tiene precio y está disponible en ese comercio y ejecución | — | 0, 1 |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `fecha` | TEXT | Fecha de la consulta | AAAA-MM-DD | fecha |
| `url_producto` | TEXT | Enlace al anuncio | — | URL |

## `v_disponibilidad`

Vista. Estado de cada anuncio en cada ejecución no fallida de su comercio posterior a su primera aparición.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `estado` | TEXT | Estado del anuncio en la ejecución | — | `disponible`, `agotado`, `sin_dato`, `no_observado` |

## `v_observaciones`

Vista del Taller 1 (se conserva sin cambios): observaciones con los campos del anuncio y del producto.

| Columna | Tipo | Significado | Unidad | Valores posibles |
|---|---|---|---|---|
| `observacion_id` | INTEGER | Identificador de la observación | — | entero |
| `ejecucion_id` | TEXT | Identificador de la ejecución: `E` + fecha y hora de inicio (hora de Colombia) | — | p. ej. `E20261009T144022` |
| `comercio_id` | TEXT | Identificador del comercio | — | `exito`, `olimpica`, `locatel` |
| `comercio` | TEXT | Nombre del comercio | — | Éxito, Olímpica, Locatel |
| `anuncio_id` | INTEGER | Identificador interno del anuncio | — | entero |
| `sku_comercio` | TEXT | SKU del producto en el comercio | — | texto |
| `ean` | TEXT | Código de barras | — | en `anuncios`: el publicado por el comercio; en `productos` y vistas: GTIN-14 válido; NULL |
| `producto_id` | TEXT | Identificador común de la presentación | — | `G`+GTIN-14 (EAN), `G…-xN` (EAN con otro número de unidades) o `N`+hash (clave normalizada) |
| `nombre_estandar` | TEXT | Nombre estándar de la presentación | — | texto |
| `marca` | TEXT | Marca estandarizada (R2) | — | texto o NULL |
| `subcategoria` | TEXT | Subcategoría estandarizada (R3, C2) | — | Crema dental, Cepillo dental, Enjuague bucal, Seda e hilo dental, … |
| `contenido_unitario` | REAL | Contenido de una unidad del empaque | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `n_unidades` | INTEGER | Número de unidades del empaque | unidades | entero ≥ 1 |
| `contenido_total` | REAL | Contenido total = unitario × unidades | mL, g, m o unidad (ver `unidad`) | número > 0 o NULL |
| `unidad` | TEXT | Unidad normalizada del contenido | — | en tablas: `ml`, `g`, `m`, `und`; en vistas: `mL`, `g`, `m`, `unidad`; NULL si no se pudo determinar |
| `familia` | TEXT | Clave de familia: subcategoría, marca y nombre sin tamaño (R7) | — | texto |
| `precio` | REAL | Precio de venta en el momento de la consulta | COP | número > 0; NULL si el sitio no lo publicó (nunca 0) |
| `precio_lista` | REAL | Precio sin descuento | COP | número > 0 o NULL |
| `es_promocion` | INTEGER | El precio de venta es menor que el de lista | — | 0, 1 |
| `texto_promocion` | TEXT | Texto de la promoción publicado por el sitio | — | texto o NULL |
| `disponible` | INTEGER | Disponibilidad según el sitio (campo del Taller 1) | — | 1, 0 o NULL |
| `fecha_hora_consulta` | TEXT | Fecha y hora en que se consultó el sitio | ISO 8601, -05:00 | p. ej. `2026-10-09T14:41:03-05:00` |
| `url_fuente` | TEXT | URL de la respuesta de la que se extrajo el dato | — | URL |
| `url_producto` | TEXT | Enlace al anuncio | — | URL |
| `comparable` | INTEGER | Presentación con precio disponible en todos los comercios de la ejecución de referencia (R9) | — | 0, 1 |
| `incluido` | INTEGER | El anuncio pertenece a cuidado bucal (R4) | — | 0, 1 |
| `nombre_original` | TEXT | Nombre del producto tal como lo publica el comercio | — | texto |
| `texto_original` | TEXT | Texto original completo del anuncio (nombre, descripción y ficha) | — | texto |

## Índices

| Índice | Tabla y columnas | Uso |
|---|---|---|
| `ix_anuncios_comercio` | `anuncios` (comercio_id) | filtro por comercio |
| `ix_anuncios_comparable` | `anuncios` (comparable) | filtro «solo comparables» |
| `ix_anuncios_marca` | `anuncios` (marca_std) | filtro por marca |
| `ix_anuncios_producto` | `anuncios` (producto_id) | correspondencia y comparables |
| `ix_anuncios_subcategoria` | `anuncios` (subcategoria_std) | filtro por subcategoría |
| `ix_obs_anuncio_ejecucion` | `observaciones` (anuncio_id, ejecucion_id) | historial de un anuncio y cambios de precio |
| `ix_obs_ejecucion` | `observaciones` (ejecucion_id, comercio_id) | filtro por ejecución |
| `ix_obs_fecha` | `observaciones` (fecha_hora_consulta) | filtro por rango de fechas |
| `ix_obs_precio` | `observaciones` (precio) | filtro por rango de precio |
| `ix_obs_promocion` | `observaciones` (es_promocion) | filtro «solo promociones» |
| `ix_rechazadas_ejecucion` | `observaciones_rechazadas` (ejecucion_id, comercio_id) | rechazos de una ejecución |
