# Diccionario de datos: `comparador_precios.sqlite`

Base del comparador de precios de la categoría *Incontinencia y cuidado del adulto* en Éxito, La Rebaja y Olímpica. Contiene las recolecciones del Taller 1 y las del Taller 2 en la misma base.

**Convenciones**

- **Tipo**: el tipo declarado en SQLite (`INTEGER`, `REAL`, `TEXT`). Las columnas de las vistas toman el tipo de la columna de origen; las calculadas dicen el suyo.
- **Fechas**: texto ISO 8601 con hora de Colombia (UTC−5), por ejemplo `2026-11-07T19:26:18-05:00`. Los identificadores de recolección y ejecución usan la forma `2026-11-07T19-26-16` (guiones en vez de dos puntos, porque también son nombres de carpeta en `raw/`).
- **Indicadores 0/1**: `INTEGER`, 1 = sí, 0 = no.
- **Dinero**: pesos colombianos (COP), sin decimales en la práctica, tal como los publica cada tienda.
- **NULL**: un dato que la tienda no publicó queda como `NULL`. No se imputa ni se reemplaza.
- Las columnas marcadas con **(T2)** se agregaron en el Taller 2. Las demás vienen del Taller 1 y no cambiaron de significado.

## Cómo se relacionan

- Un comercio tiene muchas ejecuciones y muchos anuncios (`comercio_id`).
- Una ejecución tiene muchas observaciones (`ejecucion_id`), y un anuncio también (`anuncio_id`).
- Un anuncio comparable apunta a un producto (`anuncios.producto_id`), y `codigos_producto` guarda el código de cada EAN.

- Una **recolección** (`recoleccion_id`) es una corrida del scraper sobre las tres tiendas. Tiene una **ejecución** por tienda.
- Un **anuncio** es un producto tal como aparece en una tienda (un SKU). Una **observación** es el precio de un anuncio en una ejecución.
- Un **producto comparable** (`P01` a `P13`) es la misma presentación (mismo EAN) vendida por las tres tiendas.

---

## Tablas

### `comercios`

Una fila por tienda. 3 filas.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `comercio_id` | INTEGER | Llave primaria | 1, 2, 3 |
| `clave` | TEXT | Nombre corto que usa el código (único) | `exito`, `larebaja`, `olimpica` |
| `nombre` | TEXT | Nombre que se muestra (único) | `Exito`, `La Rebaja`, `Olimpica` (la app los muestra con tilde) |
| `url_base` | TEXT | Dominio de la tienda | URL |
| `seccion` | TEXT | Ruta de la sección tomada como la categoría | Texto, por ejemplo `Cuidado personal > Incontinencia` |
| `url_web` | TEXT | Página de la sección en el sitio | URL |

### `ejecuciones`

Una fila por tienda en cada recolección. Es la tabla que permite rastrear cada observación hasta su copia en `raw/`.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `ejecucion_id` | TEXT | Llave primaria: tienda y fecha y hora de inicio | `exito_2026-11-07T19-26-16` |
| `recoleccion_id` | TEXT | Agrupa las tres ejecuciones de una misma corrida | `2026-11-07T19-26-16` |
| `comercio_id` | INTEGER | Tienda (tabla `comercios`) | 1, 2, 3 |
| `fecha_hora_inicio` | TEXT | Inicio de la ejecución | ISO 8601 |
| `fecha_hora_fin` | TEXT | Fin de la ejecución | ISO 8601 |
| `total_servicio` | INTEGER | Productos que el servicio de la tienda dice tener en la sección | Conteo |
| `productos_unicos` | INTEGER | Productos distintos (`product_id`) que llegaron | Conteo |
| `registros` | INTEGER | Filas (SKU) obtenidas | Conteo |
| `estado` | TEXT | Resultado de la ejecución (con `CHECK`) | `completa`: llegaron todos los productos que informa el servicio y al menos 8 comparables con precio; `parcial`: faltaron productos o comparables (el motivo queda en `rechazos`); `fallida`: no llegó ningún producto |
| `carpeta_raw` | TEXT | Carpeta con las copias crudas de esa ejecución | Ruta relativa a la carpeta del taller, por ejemplo `raw\exito\2026-11-07T19-26-16`. Si llega una ruta completa, `db.preparar_base()` la deja relativa |
| `cargada_desde` | TEXT | Cómo se cargó | `en línea` (descarga de la tienda) o `raw (sin conexión)` (reproceso de `raw/`) |

### `anuncios`

Una fila por producto de una tienda (SKU). Única por (`comercio_id`, `sku`). Guarda el texto original y los campos limpios.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `anuncio_id` | INTEGER | Llave primaria | — |
| `comercio_id` | INTEGER | Tienda (tabla `comercios`) | 1, 2, 3 |
| `sku` | TEXT | Identificador interno del artículo en la tienda (VTEX `itemId`) | Texto |
| `product_id` | TEXT | Identificador del producto en la tienda (VTEX `productId`); un producto puede tener varios SKU | Texto |
| `ean` | TEXT | Código de barras publicado por la tienda | 13 dígitos; `''` si la tienda no lo da. Éxito usa a veces códigos internos (`22…`, `IZ…`) |
| `marca` | TEXT | Marca tal como la publica la tienda | Texto original |
| `subcategoria` | TEXT | Ruta de categorías de la tienda | Texto original, por ejemplo `/Cuidado personal/Higiene íntima/…/` |
| `nombre_original` | TEXT | Nombre visible del anuncio, sin limpiar | Texto original |
| `descripcion_original` | TEXT | Descripción del anuncio (puede traer HTML) | Texto original |
| `presentacion_original` | TEXT | Ficha de presentación de la tienda, si la publica | Texto original o `''` |
| `url` | TEXT | Página del producto | URL |
| `en_categoria` | INTEGER | 1 si el anuncio es de la categoría; 0 si la tienda lo puso en la sección pero no lo es | 0/1 |
| `motivo_exclusion` | TEXT | Por qué se excluyó (solo si `en_categoria` = 0) | Por ejemplo `higiene menstrual`, `papel higiénico`; `''` si está en la categoría |
| `marca_estandar` | TEXT | Marca estandarizada | Por ejemplo `TENA`, `PLENITUD` |
| `subcategoria_estandar` | TEXT | Subcategoría estandarizada | `Pañal`, `Ropa interior absorbente`, `Toalla o protector`, `Toallitas húmedas`, `Cuidado de la piel`, `Protector de cama`, `Otro` |
| `contenido` | REAL | Cantidad del empaque extraída del texto | Número (ver `unidad`); NULL si no se pudo leer |
| `unidad` | TEXT | Unidad de `contenido` como la extrae la limpieza | `und`, `mL`, `g` o NULL |
| `talla` | TEXT | Talla del pañal o pants | `S`, `M`, `L`, `XL`, `P/M`, `G/XG`… o NULL si no aplica |
| `producto_id` | TEXT | Producto comparable al que corresponde (tabla `productos`) | `P01` a `P13`; NULL si no es comparable |
| `comparable` | INTEGER | 1 si el anuncio es uno de los productos comparables | 0/1 |
| `variante` **(T2)** | TEXT | Línea del producto, leída del nombre | `clasico`, `comfort`, `ultra`, `nocturno`, `discreet`, `basic` o NULL. Sirve para no emparejar dos líneas distintas con el mismo nombre comercial |
| `contenido_total` **(T2)** | REAL | Cantidad total del empaque, ya corregida | Pañales, toallas: unidades; líquidos: mL; cremas: g |
| `unidad_normalizada` **(T2)** | TEXT | Unidad de `contenido_total` | `unidad`, `mL`, `g` o NULL |

### `observaciones`

Una fila por anuncio en cada ejecución: el precio en un momento. Nunca se borra una fila.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `observacion_id` | INTEGER | Llave primaria | — |
| `anuncio_id` | INTEGER | Anuncio (tabla `anuncios`) | — |
| `ejecucion_id` | TEXT | Ejecución en que se observó (tabla `ejecuciones`) | `exito_2026-11-07T19-26-16` |
| `precio` | REAL | Precio de venta que muestra la tienda | COP, mayor que 0; NULL si el producto está agotado y la tienda no muestra precio |
| `precio_antes` | REAL | Precio de lista antes del descuento | COP; NULL si está agotado |
| `promocion` | INTEGER | 1 si `precio_antes` es mayor que `precio` | 0/1 |
| `disponible` | INTEGER | Lo que dice la tienda sobre la existencia | 1 = disponible, 0 = agotado |
| `vendedor` | TEXT | Vendedor que muestra la tienda por defecto | Texto, por ejemplo `exito`, `Olimpica` o un vendedor externo |
| `pagina` | INTEGER | Página de resultados donde apareció | Desde 1 |
| `fecha_hora_consulta` | TEXT | Momento de la consulta | ISO 8601 |
| `estado_disponibilidad` **(T2)** | TEXT | Estado según el sitio | `disponible` o `agotado`. El tercer estado, `no observado`, no es una fila: sale de la vista `v_disponibilidad` |
| `descartada` **(T2)** | INTEGER | 1 si la observación no se usa en el análisis (el motivo va en `correcciones`) | 0/1; por defecto 0 |

Restricciones de unicidad: (`anuncio_id`, `fecha_hora_consulta`), del Taller 1, y el índice único `ux_obs_anuncio_ejecucion` sobre (`anuncio_id`, `ejecucion_id`), del Taller 2: el mismo anuncio no entra dos veces en una ejecución.

### `productos`

Una fila por producto comparable: la misma presentación (mismo EAN) en las tres tiendas. 13 filas. La limpieza la rehace en cada corrida.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `producto_id` | TEXT | Llave primaria; código estable (ver `codigos_producto`) | `P01` a `P13` |
| `descripcion` | TEXT | Nombre estandarizado | Texto, por ejemplo `Pañales TENA pants clásicos talla L (8 und)` |
| `marca` | TEXT | Marca estandarizada | `TENA` |
| `subcategoria` | TEXT | Subcategoría estandarizada | Como `anuncios.subcategoria_estandar` |
| `contenido` | REAL | Cantidad del empaque | Número |
| `unidad` | TEXT | Unidad de `contenido` | `und`, `mL`, `g` |
| `ean` | TEXT | Código de barras común a las tres tiendas | 13 dígitos |
| `talla` | TEXT | Talla | `M`, `L` o NULL |

### `codigos_producto` (T2)

Guarda el código de cada producto comparable para que no cambie entre corridas aunque un producto falte en alguna ejecución.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `ean` | TEXT | Llave primaria: código de barras | 13 dígitos |
| `producto_id` | TEXT | Código asignado (único) | `P01`, `P02`, etc. |

### `correcciones` (T2)

Una fila por corrección hecha sobre la base del Taller 1. La carpeta del Taller 1 no se modifica; `db.aplicar_correcciones()` vuelve a aplicar estas filas después de cada limpieza.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `correccion_id` | INTEGER | Llave primaria | — |
| `fecha` | TEXT | Cuándo se registró | ISO 8601 |
| `tabla` | TEXT | Tabla corregida | `anuncios` u `observaciones` |
| `registro_id` | INTEGER | Fila corregida (`anuncio_id` u `observacion_id`) | — |
| `referencia` | TEXT | La misma fila en palabras | Por ejemplo `larebaja SKU 9659` |
| `campo` | TEXT | Columna corregida | Solo las permitidas en `db.registrar_correccion()`: `variante`, `contenido`, `contenido_total`, `producto_id`, `comparable`, `talla`, `descartada`, `precio` |
| `valor_anterior` | TEXT | Valor antes de corregir | Texto |
| `valor_nuevo` | TEXT | Valor corregido | Texto |
| `motivo` | TEXT | Explicación con la evidencia (copias de `raw/`) | Texto |

Única por (`tabla`, `registro_id`, `campo`, `valor_nuevo`): registrar dos veces la misma corrección no la duplica.

### `rechazos` (T2)

Lo que no superó la validación de `validacion.py`. Las filas rechazadas no entran a `observaciones`.

| Columna | Tipo | Significado | Unidad / valores posibles |
|---|---|---|---|
| `rechazo_id` | INTEGER | Llave primaria | — |
| `ejecucion_id` | TEXT | Ejecución en que llegó la fila | Como en `ejecuciones` |
| `comercio` | TEXT | Tienda | `Exito`, `La Rebaja`, `Olimpica` |
| `sku` | TEXT | SKU de la fila rechazada | Texto; NULL si el rechazo es de toda la ejecución |
| `url` | TEXT | Página del producto | URL o NULL |
| `fecha_hora_consulta` | TEXT | Momento de la consulta | ISO 8601 |
| `regla` | TEXT | Regla que falló; si fallan varias, se unen con ` \| ` | `precio: precio no mayor que cero`, `sin precio aunque el sitio lo muestra disponible`, `observación duplicada en la ejecución`, `comercio: comercio vacío`, `url: URL vacía`, `fecha_hora_consulta: fecha vacía`, `<columna>: dato faltante` (nulo en comercio, URL, fecha o SKU), `ejecución` (regla de toda la ejecución: menos de 8 comparables con precio o productos faltantes) |
| `detalle` | TEXT | Valor que causó el rechazo o motivo de la ejecución | Texto, por ejemplo `precio=0.0` |

---

## Vistas

Las vistas se borran y se vuelven a crear en `db.preparar_base()`, así que siempre tienen la definición de `db.py`. La aplicación las consulta directamente.

### `v_observaciones`

Una fila por observación válida: solo anuncios de la categoría (`en_categoria` = 1) y observaciones no descartadas (`descartada` = 0). Une `observaciones`, `anuncios`, `comercios` y `ejecuciones`. Es la base de las demás vistas y de la tabla de la aplicación.

| Columna | Origen / significado |
|---|---|
| `observacion_id`, `ejecucion_id`, `precio`, `precio_antes`, `promocion`, `estado_disponibilidad`, `fecha_hora_consulta` | `observaciones` |
| `recoleccion_id` | `ejecuciones` |
| `comercio_clave`, `comercio` | `comercios.clave`, `comercios.nombre` |
| `anuncio_id`, `sku`, `ean`, `nombre_original`, `variante`, `talla`, `presentacion_original`, `contenido_total`, `unidad_normalizada`, `producto_id`, `comparable`, `url` | `anuncios` |
| `marca` | `anuncios.marca_estandar` |
| `subcategoria` | `anuncios.subcategoria_estandar` |
| `precio_unitario` | REAL, calculado: `precio / contenido_total` redondeado a 1 decimal. COP por unidad, por mL o por g según `unidad_normalizada`. NULL si falta el precio o el contenido |

### `v_ultimo_precio`

Mismas columnas que `v_observaciones`, solo para la ejecución más reciente que no sea `fallida` de cada tienda. Sirve para consultar a mano el precio vigente en cada tienda; ninguna página la usa.

### `v_cambios_precio`

Una fila por cada vez que el precio de un anuncio cambió frente a su observación anterior (mismo anuncio, misma tienda; `LAG` ordenado por fecha y hora de consulta). Solo entran pares con los dos precios presentes y distintos. La usa el indicador "Cambios de precio" del resumen, con los filtros del panel.

| Columna | Tipo | Significado |
|---|---|---|
| `recoleccion_id` | TEXT | Recolección del precio nuevo |
| `recoleccion_anterior` | TEXT | Recolección del precio anterior |
| `comercio`, `anuncio_id`, `nombre_original`, `presentacion_original`, `marca`, `subcategoria`, `producto_id`, `promocion` | — | Como en `v_observaciones` (de la observación nueva) |
| `precio_anterior` | REAL | COP |
| `precio` | REAL | COP |
| `cambio_cop` | REAL | `precio − precio_anterior`, COP (negativo = bajó) |
| `cambio_pct` | REAL | Cambio en porcentaje del precio anterior, 1 decimal |

### `v_comparables`

Una fila por producto comparable, recolección y tienda con precio, con el puesto de la tienda en ese producto y esa recolección.

| Columna | Tipo | Significado |
|---|---|---|
| `producto_id`, `descripcion`, `talla`, `ean` | — | `productos` |
| `recoleccion_id`, `comercio`, `precio`, `precio_unitario`, `contenido_total`, `unidad_normalizada`, `promocion`, `estado_disponibilidad`, `fecha_hora_consulta`, `url` | — | `v_observaciones` |
| `puesto` | INTEGER | `RANK()` por precio dentro del producto y la recolección: 1 = más barato. Dos tiendas con el mismo precio comparten puesto (empate) |

### `v_disponibilidad`

Los tres estados de disponibilidad. Una fila por cada anuncio de la categoría y cada ejecución no fallida de su tienda (`LEFT JOIN`).

| Columna | Tipo | Significado / valores |
|---|---|---|
| `ejecucion_id`, `recoleccion_id` | TEXT | Ejecución |
| `comercio`, `anuncio_id`, `nombre_original`, `producto_id` | — | Anuncio |
| `estado` | TEXT | `disponible` o `agotado` según el sitio; `no observado` si el anuncio no apareció en esa ejecución. Un anuncio no observado no se interpreta como agotado ni como retirado |

---

## Índices

| Índice | Columnas | Para qué |
|---|---|---|
| `ux_obs_anuncio_ejecucion` (único) | `observaciones (anuncio_id, ejecucion_id)` | Impide insertar dos veces la misma observación en una ejecución |
| `ix_obs_ejecucion` | `observaciones (ejecucion_id)` | Filtro por recolección |
| `ix_obs_precio` | `observaciones (precio)` | Filtro por rango de precio |
| `ix_obs_promocion` | `observaciones (promocion)` | Filtro "solo promociones" |
| `ix_anu_comercio` | `anuncios (comercio_id)` | Filtro por comercio |
| `ix_anu_producto` | `anuncios (producto_id)` | Filtro "solo comparables", canasta |
| `ix_anu_subcat` | `anuncios (subcategoria_estandar)` | Filtro por subcategoría |
| `ix_anu_marca` | `anuncios (marca_estandar)` | Filtro por marca |
| `ix_eje_recoleccion` | `ejecuciones (recoleccion_id)` | Elegir recolección |
| `ix_eje_comercio` | `ejecuciones (comercio_id, fecha_hora_inicio)` | Última ejecución de cada tienda |
