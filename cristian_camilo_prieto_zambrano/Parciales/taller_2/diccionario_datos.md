# Diccionario de datos — `comparador_precios.sqlite`

Comparador de precios de **nutrición clínica** en Locatel, Cruz Verde y Farmatodo.
Taller 2, Minería de Datos (UNAL). Esquema en la versión 3 (`PRAGMA user_version = 3`).

## Convenciones

| Aspecto | Convención |
|-|-|
| Fechas y horas | Texto ISO 8601 con zona horaria de Colombia, p. ej. `2026-11-10T15:32:20-05:00`. Las columnas `fecha` son `AAAA-MM-DD`. |
| Corrida | Identificador `AAAAMMDDTHHMMSS` (hora de Colombia en que se inició). Es también el nombre de la carpeta en `raw/<comercio>/<corrida>/`. |
| Moneda | Pesos colombianos (COP), sin decimales en los precios publicados. |
| Contenido | Normalizado a gramos (`g`) o mililitros (`mL`): 1 kg = 1000 g, 1 L = 1000 mL, 1 lb = 453,592 g, 1 oz = 28,3495 g. |
| Valores lógicos | Enteros `0` (no) y `1` (sí). |
| Datos ausentes | `NULL`. Un dato que el sitio no publica nunca se completa ni se reemplaza por 0. |
| Columnas generadas | Marcadas *(generada)*: SQLite las calcula a partir de otras columnas y no se escriben directamente. |

**Archivos relacionados.** `raw/` guarda la copia cruda (`.json.gz`) de cada respuesta de los sitios, con la hora de consulta en el nombre del archivo, y `totales.csv` con el total que informa cada sitio. `correspondencia.csv` asigna el identificador común de cada producto comparable (P01–P10) al SKU de cada comercio.

---

## Tablas

### `comercios`

| Columna | Tipo | Significado y valores |
|-|-|-|
| `id_comercio` | TEXT, clave primaria | `locatel`, `cruzverde`, `farmatodo` |
| `nombre` | TEXT | Nombre para mostrar: Locatel, Cruz Verde, Farmatodo |
| `url_base` | TEXT | Dirección del sitio del comercio |

### `productos`

Productos comparables: la misma presentación vendida en los tres comercios. Se carga desde `correspondencia.csv`.

| Columna | Tipo | Unidad | Significado y valores |
|-|-|-|-|
| `id_producto` | TEXT, clave primaria | — | `P01` a `P10` |
| `nombre_std` | TEXT | — | Nombre estandarizado de la presentación |
| `marca_std` | TEXT | — | Marca estandarizada |
| `subcategoria_std` | TEXT | — | Subcategoría estandarizada (valores en `anuncios.subcategoria_std`) |
| `variante` | TEXT | — | Sabor o variante (Vainilla) |
| `contenido` | REAL | g o mL | Contenido de una unidad |
| `unidad` | TEXT | — | `g` o `mL` |
| `n_unidades` | INTEGER | unidades | Unidades por empaque (1 en todos) |
| `contenido_total` | REAL *(generada)* | g, mL o unidad | `contenido × n_unidades` |
| `unidad_norm` | TEXT *(generada)* | — | `g`, `mL` o `unidad` |

### `ejecuciones`

Una fila por comercio en cada corrida del scraper.

| Columna | Tipo | Unidad | Significado y valores |
|-|-|-|-|
| `id_ejecucion` | INTEGER, clave primaria | — | Identificador |
| `corrida` | TEXT | — | Corrida a la que pertenece; nombre de la carpeta en `raw/` |
| `id_comercio` | TEXT → `comercios` | — | Comercio |
| `inicio`, `fin` | TEXT | fecha y hora | Inicio y fin del procesamiento. En una carga sin conexión, la hora de la carga |
| `n_registros` | INTEGER | anuncios | Anuncios obtenidos, sin SKU repetidos entre secciones y antes de la validación |
| `total_sitio` | INTEGER | anuncios | Total que informa el propio sitio para las secciones recolectadas |
| `estado` | TEXT | — | `completa`; `parcial` (se obtuvieron menos anuncios que `total_sitio`, o hay menos de 8 comparables con precio); `fallida` (ningún registro) |
| `modo` | TEXT | — | Cómo se cargó: `en_linea` (consulta a los sitios) o `sin_conexion` (reprocesando `raw/`) |
| `captura_inicio`, `captura_fin` | TEXT | fecha y hora | Primera y última hora de consulta a los sitios (tomadas de los nombres de las copias crudas). Es el momento al que corresponden los precios |
| `motivo` | TEXT | — | Explicación del estado: anuncios faltantes, comparables faltantes, observaciones rechazadas. `NULL` si no hay nada que señalar |

### `anuncios`

Cada producto tal como aparece en un comercio. Hay un solo registro por comercio y SKU; los datos descriptivos son los de la consulta más reciente.

| Columna | Tipo | Unidad | Significado y valores |
|-|-|-|-|
| `id_anuncio` | INTEGER, clave primaria | — | Identificador |
| `id_comercio` | TEXT → `comercios` | — | Comercio |
| `sku` | TEXT | — | Identificador interno del comercio (Cruz Verde: `COCV_…`) |
| `seccion` | TEXT | — | Sección del sitio de donde salió: `suplementos` y `cereales_regulares` (Locatel), `nutricion` (Cruz Verde, Farmatodo) |
| `ean` | TEXT | — | Código de barras. `NULL` en Cruz Verde, que no lo publica |
| `nombre` | TEXT | — | Nombre publicado por el sitio |
| `marca` | TEXT | — | Marca publicada por el sitio |
| `subcategoria` | TEXT | — | Categoría publicada por el sitio |
| `texto_original` | TEXT | — | Texto del anuncio sin limpiar: `nombre | descripción` (en Cruz Verde, además `| precio por unidad publicado`) |
| `url` | TEXT | — | Página del producto en el sitio |
| `contenido` | REAL | g o mL | Contenido de una unidad, extraído del nombre (presentación más reciente) |
| `unidad` | TEXT | — | `g`, `mL` o `NULL` si el nombre no trae el tamaño |
| `n_unidades` | INTEGER | unidades | Unidades del empaque ("Caja x 6 Und" → 6); 1 si no se indica |
| `marca_std` | TEXT | — | Marca estandarizada: marca conocida encontrada en el nombre o, si no hay, la del sitio |
| `subcategoria_std` | TEXT | — | `Espesante / módulo de carbohidrato`, `Fórmula pediátrica`, `Fórmula para diabetes`, `Fórmula renal`, `Fórmula especializada (otra patología)`, `Fórmula completa adulto`, `Módulo de proteína`, `Otro (revisar)` |
| `es_paquete` | INTEGER | — | 1 si es un paquete u oferta compuesta ("x 6", "850 g + 400 g", "kit", "lleve"…) |
| `excluido` | INTEGER | — | 1 si no pertenece a la categoría nutrición clínica. Se recolecta igual, para verificar la completitud |
| `motivo_exclusion` | TEXT | — | `NULL` si pertenece a la categoría. Si no: dispositivo médico; nutrición deportiva; vitaminas o suplemento dietario; medicamento o producto de cuidado personal; leche o fórmula infantil de consumo general; cereal o alimento regular; otro alimento fuera de la delimitación |
| `id_producto` | TEXT → `productos` | — | Producto comparable al que corresponde; `NULL` si no es comparable |
| `comparable` | INTEGER | — | 1 si está en `correspondencia.csv` |
| `contenido_total` | REAL *(generada)* | g, mL o unidad | `contenido × n_unidades`; si no hay contenido pero sí varias unidades, el número de unidades; si no, `NULL` |
| `unidad_norm` | TEXT *(generada)* | — | `g`, `mL`, `unidad` o `NULL` |

### `observaciones`

Cada precio observado: un anuncio en una ejecución.

| Columna | Tipo | Unidad | Significado y valores |
|-|-|-|-|
| `id_obs` | INTEGER, clave primaria | — | Identificador |
| `id_anuncio` | INTEGER → `anuncios` | — | Anuncio |
| `id_ejecucion` | INTEGER → `ejecuciones` | — | Ejecución en que se observó |
| `precio` | REAL | COP | Precio de venta abierto a todos: el de oferta si existe y, si no, el de lista. `NULL` si el sitio no publica precio |
| `precio_lista` | REAL | COP | Precio antes del descuento |
| `precio_club` | REAL | COP | Solo Cruz Verde: precio para afiliados al club. No se usa en las comparaciones |
| `promocion` | INTEGER | — | 1 si el precio de venta es menor que el de lista |
| `disponible` | INTEGER | — | Disponibilidad según el sitio, 1 o 0. Locatel: `IsAvailable` del vendedor principal. Cruz Verde: `stock` mayor que 0. Farmatodo: al menos una tienda con existencias (`stores_with_stock`); verificado en el sitio el 2026-11-14, incluidos los productos de vendedores externos |
| `disponibilidad` | TEXT *(generada)* | — | `disponible` o `agotado` |
| `fecha_hora_consulta` | TEXT | fecha y hora | Momento de la consulta, tomado del nombre de la copia cruda |
| `descartada` | INTEGER | — | 1 si la observación se marcó como inválida después de cargarse; no se borra |
| `motivo_descarte` | TEXT | — | Por qué se descartó (la regla de validación que no cumple) |
| `contenido` | REAL | g o mL | Contenido de una unidad, tal como se leyó en esta consulta |
| `unidad` | TEXT | — | `g`, `mL` o `NULL`, en esta consulta |
| `n_unidades` | INTEGER | unidades | Unidades del empaque, en esta consulta |
| `contenido_total` | REAL *(generada)* | g, mL o unidad | Igual que en `anuncios`, con la presentación de esta consulta |
| `unidad_norm` | TEXT *(generada)* | — | `g`, `mL`, `unidad` o `NULL` |

La presentación se guarda en cada observación porque un comercio puede reutilizar el SKU con otro tamaño (Locatel, SKU 27148: 400 g en octubre y 900 g en noviembre). Así cada precio conserva la presentación a la que corresponde.

### `correcciones`

Registro de todo cambio a un dato ya insertado (sección 3.2 del enunciado).

| Columna | Tipo | Significado y valores |
|-|-|-|
| `id_correccion` | INTEGER, clave primaria | Identificador |
| `fecha` | TEXT | Fecha y hora de la corrección |
| `tabla` | TEXT | `anuncios`, `observaciones` o `ejecuciones` |
| `id_registro` | INTEGER | Llave primaria del registro corregido en esa tabla |
| `campo` | TEXT | Columna corregida |
| `valor_anterior`, `valor_nuevo` | TEXT | Valores antes y después, como texto |
| `motivo` | TEXT | Por qué se corrigió, con la evidencia. Los cambios automáticos al recargar un anuncio empiezan por "Recalculado al cargar la ejecución N" |

### `rechazos`

Observaciones que no superaron la validación y por eso no se insertaron (sección 3.4). Una fila por observación y regla incumplida.

| Columna | Tipo | Significado y valores |
|-|-|-|
| `id_rechazo` | INTEGER, clave primaria | Identificador |
| `id_ejecucion` | INTEGER → `ejecuciones` | Ejecución en la que se rechazó |
| `id_comercio` | TEXT → `comercios` | Comercio |
| `sku` | TEXT | SKU del anuncio rechazado |
| `regla` | TEXT | `precio_valido`, `precio_lista_valido`, `campos_obligatorios`, `fecha_iso`, `disponible_valido`, `contenido_valido`, `sin_duplicados` (definidas en `validacion.R`) |
| `detalle` | TEXT | Valor que incumple la regla, p. ej. `faltan: url` |
| `fecha_hora_consulta` | TEXT | Hora de consulta de la fila rechazada |
| `registro` | TEXT (JSON) | La fila rechazada completa |

---

## Restricciones e índices

| Objeto | Definición | Propósito |
|-|-|-|
| `UNIQUE (id_comercio, sku)` en `anuncios` | Un anuncio por comercio y SKU | No duplicar anuncios |
| `UNIQUE (id_anuncio, fecha_hora_consulta)` en `observaciones` | — | No insertar dos veces la misma consulta |
| `uq_obs_anuncio_ejecucion` | Índice único `(id_anuncio, id_ejecucion)` | Una observación por anuncio y ejecución |
| `CHECK` en `ejecuciones` | `estado` y `modo` con valores permitidos | — |
| Índices `ix_*` | `observaciones (id_ejecucion)`, `observaciones (fecha_hora_consulta)`, `anuncios (id_comercio)`, `anuncios (id_producto)`, `anuncios (subcategoria_std)`, `anuncios (marca_std)`, `anuncios (excluido, comparable)`, `ejecuciones (corrida, id_comercio)`, `rechazos (id_ejecucion)` | Columnas que usan los filtros y las uniones de la aplicación |

---

## Vistas

Todas excluyen las observaciones descartadas y los anuncios fuera de la categoría (`excluido = 1`). La **ejecución vigente** de un comercio es la más reciente que no sea `fallida`. El **precio unitario** es `precio / contenido_total`, en COP por g, por mL o por unidad según `unidad_norm`; nunca se mezclan unidades.

### `v_ejecuciones`

Columnas de `ejecuciones` (`id_ejecucion`, `corrida`, `id_comercio`, `estado`, `modo`, `captura_inicio`, `captura_fin`, `n_registros`, `total_sitio`, `motivo`), más:

| Columna | Significado |
|-|-|
| `comercio` | Nombre del comercio |
| `fecha` | Fecha de la captura (`AAAA-MM-DD`) |
| `n_observaciones` | Observaciones válidas de la ejecución, incluidas las de anuncios excluidos |
| `n_rechazos` | Filas en `rechazos` |
| `orden` | Posición de la ejecución dentro del comercio (1 = la más antigua); `NULL` si es fallida |
| `vigente` | 1 si es la ejecución vigente del comercio |

### `v_observaciones`

Una fila por observación válida de la categoría. Es la base de las demás vistas y de la tabla de la aplicación.

| Columna | Unidad | Significado |
|-|-|-|
| `id_obs`, `id_ejecucion`, `corrida`, `id_anuncio`, `id_comercio`, `sku`, `url`, `texto_original` | — | Como en las tablas |
| `orden_ejecucion`, `vigente` | — | De `v_ejecuciones` |
| `comercio` | — | Nombre del comercio |
| `nombre` | — | Nombre del anuncio (el más reciente) |
| `marca`, `subcategoria` | — | `marca_std` y `subcategoria_std` |
| `comparable`, `id_producto`, `es_paquete` | — | Como en `anuncios` |
| `contenido_total`, `unidad_norm` | g, mL o unidad | Presentación de la observación |
| `precio`, `precio_lista` | COP | Como en `observaciones` |
| `promocion`, `disponibilidad` | — | Como en `observaciones` |
| `precio_unitario` | COP por g, mL o unidad | `precio / contenido_total`; `NULL` sin precio o sin contenido |
| `fecha_hora_consulta`, `fecha` | — | Momento de la consulta |

### `v_ultimo_precio`

Mismas columnas que `v_observaciones`, limitadas a la ejecución vigente de cada comercio. Es el dato más reciente de cada anuncio.

### `v_comparables`

Una fila por producto comparable, comercio y ejecución. Los comercios se comparan dentro de una misma **corrida**.

| Columna | Unidad | Significado |
|-|-|-|
| `id_producto`, `producto` | — | Producto comparable y su nombre estandarizado |
| `id_comercio`, `comercio`, `id_ejecucion`, `corrida`, `fecha`, `vigente`, `id_anuncio`, `sku`, `url` | — | Dónde y cuándo se observó |
| `precio`, `precio_unitario` | COP; COP por g o mL | Precio observado |
| `contenido_total`, `unidad_norm` | g o mL | Presentación observada |
| `promocion`, `disponibilidad` | — | Como en `observaciones` |
| `coincide` | — | 1 si la presentación observada es la del producto. Si es 0, el comercio cambió la presentación y la fila no entra en la comparación |
| `precio_min`, `precio_max` | COP | Menor y mayor precio del producto en la corrida, entre los comercios con precio y `coincide = 1` |
| `comercios_con_precio` | comercios | Comercios que entran en la comparación |
| `es_mas_barato` | — | 1 si el precio es el mínimo (en un empate, todos los empatados tienen 1); 0 si no; `NULL` si no entra en la comparación |
| `n_mas_baratos` | comercios | Comercios con el precio mínimo (más de 1 indica empate) |
| `sobrecosto` | COP | Precio menos el precio mínimo |
| `ahorro_maximo` | COP | `precio_max − precio_min`: lo que se ahorra comprando en el más barato y no en el más caro (0 si solo hay un comercio) |

### `v_cambios_precio`

Una fila por anuncio en cada par de ejecuciones consecutivas (no fallidas) del mismo comercio. Se compara el mismo anuncio en el mismo comercio.

| Columna | Unidad | Significado |
|-|-|-|
| `id_comercio`, `comercio` | — | Comercio |
| `id_ejecucion_anterior`, `corrida_anterior`, `fecha_anterior` | — | Ejecución anterior |
| `id_ejecucion_actual`, `corrida_actual`, `fecha_actual`, `vigente` | — | Ejecución actual (`vigente` = 1 si es la vigente) |
| `id_anuncio`, `sku`, `nombre`, `marca`, `subcategoria`, `comparable`, `id_producto` | — | Anuncio |
| `precio_anterior`, `precio_actual` | COP | Precio en cada ejecución |
| `contenido_anterior`, `contenido_actual`, `unidad_norm` | g, mL o unidad | Presentación en cada ejecución |
| `tipo_cambio` | — | `subió`, `bajó`, `igual`; `cambió la presentación` (no se cuenta como cambio de precio); `sin precio` (falta el precio en una de las dos); `nuevo` (no estaba en la anterior); `no observado` (no aparece en la actual) |
| `diferencia` | COP | `precio_actual − precio_anterior`, solo con la misma presentación |
| `variacion_pct` | % | `100 × diferencia / precio_anterior`, con dos decimales |

### `v_disponibilidad`

Una fila por ejecución y por anuncio ya visto en ese comercio hasta esa ejecución.

| Columna | Unidad | Significado |
|-|-|-|
| `id_ejecucion`, `corrida`, `id_comercio`, `comercio`, `fecha`, `vigente` | — | Ejecución |
| `estado_ejecucion` | — | `completa` o `parcial` |
| `id_anuncio`, `sku`, `nombre`, `subcategoria`, `comparable`, `id_producto` | — | Anuncio |
| `estado` | — | `disponible` o `agotado` (según el sitio); `no_observado` (el anuncio no apareció en la ejecución: no se interpreta como agotado ni retirado); `sin_informacion` (observado sin dato de disponibilidad) |
| `ultimo_precio` | COP | Último precio conocido hasta esa ejecución |
| `fecha_ultimo_precio` | — | Fecha de ese precio |
