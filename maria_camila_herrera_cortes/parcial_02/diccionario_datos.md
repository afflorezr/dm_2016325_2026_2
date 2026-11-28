# Diccionario de datos — `comparador_precios.sqlite`

Base SQLite del comparador de precios (categoría **Cuidado y decoración de uñas**; comercios **Éxito, Jumbo y Olímpica**).
Todos los datos provienen del scraping (`scraper.R`) y cada observación se puede rastrear hasta su copia cruda en `raw/` y su ejecución en la tabla `ejecuciones`.

**Convenciones generales**

- Fechas y horas: texto ISO 8601 con zona horaria de Colombia, p. ej. `2026-11-09T12:58:18-05:00`.
- Moneda: pesos colombianos (COP), sin decimales en los datos originales.
- Booleanos: enteros `0` / `1` (`NULL` = el dato no se pudo extraer; **nunca se rellena**).
- Un dato ausente queda `NULL`: no se imputan ni calculan valores para reemplazarlo.
- Identificador de ejecución: `run_AAAAMMDD_HHMMSS` (fecha y hora de inicio de la ejecución, hora de Colombia).

---

## Tablas

### `comercios`
Los tres comercios consultados.

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `comercio_id` | INTEGER (PK) | Identificador interno | 1, 2, 3 |
| `nombre` | TEXT, único | Nombre corto del comercio | `exito`, `jumbo`, `olimpica` |

### `ejecuciones`
Una fila por **ejecución y comercio**: cada vez que se corre el scraper (o el botón de actualización) y qué tan bien salió en cada comercio. PK `(ejecucion_id, comercio_id)`.

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `ejecucion_id` | TEXT | Identificador de la ejecución | `run_AAAAMMDD_HHMMSS` |
| `comercio_id` | INTEGER (FK → `comercios`) | Comercio de esta fila | |
| `fecha_hora_inicio` | TEXT | Inicio de la ejecución | ISO 8601 |
| `n_registros` | INTEGER | Observaciones guardadas de ese comercio en la ejecución | ≥ 0 |
| `estado` | TEXT | Resultado de la ejecución en ese comercio | `completa` (se obtuvo todo lo que el sitio informó y están los 8 comparables), `parcial` (faltaron productos o páginas, o falta algún comparable), `fallida` (no se pudo consultar o guardar el comercio) |
| `motivo` | TEXT | Explicación cuando el estado no es `completa` (bloqueo del sitio, error de red, páginas omitidas, comparables faltantes…) | texto libre o `NULL` |

### `productos`
Correspondencia manual de los **productos comparables** (misma presentación en los tres comercios).

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `producto_id` | TEXT (PK) | Código del producto comparable | `P01` … `P10` |
| `ean` | TEXT | Código de barras (EAN-13) que identifica el producto en los comercios | 13 dígitos |
| `producto_estandar` | TEXT | Nombre estándar del producto | texto |
| `marca_estandar` | TEXT | Marca estandarizada | texto |
| `subcategoria` | TEXT | Subcategoría del producto | texto |
| `contenido` | REAL | Contenido total de la presentación | > 0 |
| `unidad` | TEXT | Unidad normalizada del contenido | `ml` (mililitros), `g` (gramos), `und` (unidades) |
| `principal` | INTEGER | 1 si es uno de los 8 productos comparables exigidos; 0 si es de reserva | 0, 1 |

### `anuncios`
Un anuncio = un producto publicado por un comercio (identificado por comercio + `product_id_comercio` + `sku`). Contiene los datos que **no** cambian entre ejecuciones. Restricción de unicidad: `(comercio_id, product_id_comercio, sku)`.

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `anuncio_id` | INTEGER (PK) | Identificador interno del anuncio | |
| `comercio_id` | INTEGER (FK) | Comercio que lo publica | |
| `product_id_comercio` | TEXT | Identificador del producto en el sitio del comercio | texto |
| `sku` | TEXT | SKU (variante) dentro del producto | texto |
| `ean` | TEXT | EAN del anuncio, si el sitio lo informa | 13 dígitos o `NULL` |
| `nombre_original` | TEXT | Nombre tal como aparece en el sitio | texto |
| `nombre_sku_original` | TEXT | Nombre de la variante (SKU) en el sitio | texto o `NULL` |
| `marca_original` | TEXT | Marca tal como aparece en el sitio | texto o `NULL` |
| `descripcion_original` | TEXT | Descripción del anuncio | texto o `NULL` |
| `ficha_tecnica_original` | TEXT | Ficha técnica del anuncio | texto o `NULL` |
| `categoria_api` | TEXT | Ruta de categoría que devuelve la API del comercio | texto |
| `categoria_consulta` | TEXT | Categoría consultada en el scraping | texto |
| `vendedor` | TEXT | Vendedor del anuncio (el comercio u otro proveedor del marketplace) | texto o `NULL` |
| `url` | TEXT | Enlace al anuncio | URL |
| `unidad_medida` | TEXT | Unidad de medida de venta que informa el sitio | p. ej. `un` |
| `multiplicador_unidad` | REAL | Multiplicador de la unidad de venta informado por el sitio | ≥ 0 |
| `marca_estandar` | TEXT | Marca estandarizada | texto o `NULL` |
| `subcategoria` | TEXT | Subcategoría asignada | Esmaltes, Removedores, Bases, tratamientos y brillos, Cortaúñas, Limas, Alicates y cortacutículas, Cuidado de cutículas, Uñas postizas, Otros |
| `contenido_valor` | REAL | Contenido total de la presentación, extraído del texto del anuncio | > 0 o `NULL` |
| `contenido_unidad` | TEXT | Unidad normalizada del contenido | `ml`, `g`, `und` o `NULL` |
| `producto_id` | TEXT (FK → `productos`) | Producto comparable al que corresponde (por EAN) | `P01`…`P10` o `NULL` |
| `incluido` | INTEGER | 1 si es un producto de la categoría de uñas; 0 si se excluyó | 0, 1 |
| `motivo_exclusion` | TEXT | Por qué se excluyó (solo si `incluido = 0`) | p. ej. «no es de uñas (filtro por palabras)», «exclusión manual», «lámparas/equipos de secado», «drills/pulidores eléctricos», «cuidado de pies» |

### `observaciones`
Una fila por **anuncio y ejecución**: el precio y la disponibilidad en el momento de la consulta. Es la tabla de hechos.
Restricciones de unicidad: `(anuncio_id, fecha_hora_consulta)` y `(anuncio_id, ejecucion_id)` (índice `ux_obs_anuncio_ejecucion`): la misma observación no se puede insertar dos veces.

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `observacion_id` | INTEGER (PK) | Identificador interno | |
| `anuncio_id` | INTEGER (FK → `anuncios`) | Anuncio observado | |
| `ejecucion_id` | TEXT | Ejecución a la que pertenece | `run_AAAAMMDD_HHMMSS` |
| `fecha_hora_consulta` | TEXT | Momento exacto de la consulta | ISO 8601 |
| `precio_cop` | REAL | Precio de venta vigente (COP) | > 0, o `NULL` si el producto está agotado o el sitio no informó precio |
| `precio_lista_cop` | REAL | Precio de lista (sin descuento) | > 0 o `NULL` |
| `en_promocion` | INTEGER | 1 si `precio_cop < precio_lista_cop` | 0, 1 o `NULL` (sin precios) |
| `disponible` | INTEGER | 1 si el sitio informa existencias (cantidad disponible > 0) | 0, 1 |
| `comparable` | INTEGER | 1 si es un producto incluido, con producto comparable asignado y con precio | 0, 1 |
| `estado_disponibilidad` | TEXT | Disponibilidad según el sitio | `disponible`, `agotado` (ver nota) |
| `descartada` | INTEGER | 1 si la observación se descartó por un error documentado en `correcciones` (nunca se borran filas) | 0, 1 |

> **Disponibilidad:** la base distingue tres situaciones. `disponible` y `agotado` se guardan en `estado_disponibilidad`. **«No observado»** no se guarda: es la *ausencia* de una observación de un anuncio que ya se había visto en una ejecución anterior; se calcula en la vista `v_disponibilidad`. Un producto no observado **no** se interpreta como agotado ni como retirado sin evidencia.

### `observaciones_rechazadas`
Observaciones que **no superaron la validación** y por eso no se insertaron en `observaciones` (precio no numérico o ≤ 0 en un producto disponible, comercio/URL/fecha ausentes, duplicado en la misma ejecución).

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `rechazo_id` | INTEGER (PK) | Identificador interno | |
| `ejecucion_id` | TEXT | Ejecución en la que se intentó insertar | |
| `comercio` | TEXT | Comercio | `exito`, `jumbo`, `olimpica` |
| `product_id_comercio` | TEXT | Identificador del producto en el sitio | |
| `sku` | TEXT | SKU | |
| `url` | TEXT | Enlace del anuncio | |
| `fecha_hora_consulta` | TEXT | Momento de la consulta | ISO 8601 |
| `precio_cop` | REAL | Precio recibido (puede ser inválido) | |
| `motivo_rechazo` | TEXT | Regla(s) que incumplió, separadas por «;» | texto |
| `fecha_registro` | TEXT | Cuándo se registró el rechazo | ISO 8601 |

### `correcciones`
Registro de cada corrección hecha después de la entrega del Taller 1. **No se borran observaciones**: se corrigen campos estandarizados o se marca la observación como descartada.

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `correccion_id` | INTEGER (PK) | Identificador interno | |
| `fecha` | TEXT | Cuándo se hizo la corrección | fecha y hora |
| `tabla` | TEXT | Tabla afectada | texto |
| `registro_id` | TEXT | Registro afectado (su identificador) | texto |
| `campo` | TEXT | Campo corregido | texto |
| `valor_anterior` | TEXT | Valor antes de la corrección | texto |
| `valor_nuevo` | TEXT | Valor después de la corrección | texto |
| `motivo` | TEXT | Por qué se corrigió | texto |

---

## Vistas SQL (las usa la aplicación directamente)

Todas excluyen las observaciones descartadas (`descartada = 1`) y los anuncios no incluidos (`incluido = 0`), salvo indicación.

### `v_precios`
Base de las demás vistas: cada observación vigente con los datos del anuncio y del comercio.

| Columna | Significado |
|---|---|
| `observacion_id`, `anuncio_id`, `ejecucion_id`, `fecha_hora_consulta` | Identificadores y momento de la consulta |
| `comercio` | Nombre del comercio |
| `product_id_comercio`, `sku` | Identificadores en el sitio |
| `nombre`, `marca`, `marca_original`, `subcategoria` | Nombre original, marca estandarizada y original, subcategoría |
| `contenido_valor`, `contenido_unidad` | Contenido total y unidad (`ml`, `g`, `und`) |
| `producto_id` | Producto comparable (`P01`…`P10`) o `NULL` |
| `url`, `vendedor` | Enlace y vendedor |
| `texto_anuncio` | Nombre + descripción, usado por la búsqueda por palabras |
| `precio_cop`, `precio_lista_cop`, `en_promocion`, `disponible`, `estado_disponibilidad`, `comparable` | Como en `observaciones` |
| `precio_unitario` | Precio por unidad de contenido: `precio_cop / contenido_valor` (COP por mL, por g o por unidad); `NULL` si falta precio o contenido |
| `unidad_norm` | Unidad del precio unitario: `mL`, `g` o `unidad` |

### `v_ultima_ejecucion`
Por comercio, su ejecución **completa** más reciente (solo si el comercio nunca tuvo una completa, la más reciente parcial). Columnas: `comercio_id`, `comercio`, `ejecucion_id`, `fecha_hora_inicio`, `estado`.

### `v_ultimo_precio`
Las observaciones de `v_precios` que pertenecen a la última ejecución de cada comercio (`v_ultima_ejecucion`). Mismas columnas que `v_precios`. Es la fuente de la tabla de productos y de los indicadores por defecto.

### `v_cambios_precio`
Compara cada observación con la **anterior del mismo anuncio** y deja solo los casos con precio distinto y ambos precios presentes.

| Columna | Significado |
|---|---|
| `anuncio_id`, `comercio`, `producto_id`, `nombre`, `marca` | Identificación del anuncio |
| `ejecucion_anterior`, `fecha_anterior` | Ejecución y fecha de la observación anterior |
| `ejecucion_actual`, `fecha_actual` | Ejecución y fecha de la observación actual |
| `precio_anterior`, `precio_actual` | Precios (COP) |
| `variacion_cop` | `precio_actual − precio_anterior` (COP; positivo = subió) |
| `variacion_pct` | Variación porcentual respecto al precio anterior |

### `v_comparables`
Observaciones de los productos comparables (`comparable = 1`) con su precio unitario.

| Columna | Significado |
|---|---|
| `ejecucion_id`, `fecha_hora_consulta`, `comercio` | Ejecución, momento y comercio |
| `producto_id`, `producto_estandar`, `marca_estandar`, `subcategoria` | Producto comparable (de la tabla `productos`) |
| `contenido`, `unidad` | Contenido y unidad (`ml`, `g`, `und`) del producto comparable |
| `precio_cop`, `precio_lista_cop`, `en_promocion` | Como en `observaciones` |
| `vendedor`, `url`, `nombre_original` | Datos del anuncio |
| `estado_disponibilidad` | `disponible` o `agotado` |
| `precio_unitario`, `unidad_norm` | Precio por unidad de contenido y su unidad (`mL`, `g`, `unidad`) |
| `principal` | 1 si es de los 8 comparables exigidos |

### `v_disponibilidad`
Para cada anuncio incluido y cada ejecución completa o parcial **desde la primera vez que se observó el anuncio**, su estado en esa ejecución.

| Columna | Significado | Valores |
|---|---|---|
| `anuncio_id`, `comercio`, `nombre`, `producto_id` | Anuncio | |
| `ejecucion_id`, `fecha_hora_inicio` | Ejecución evaluada | |
| `estado` | Situación del anuncio en esa ejecución | `disponible`, `agotado`, `no_observado` |

---

## Índices
`ux_obs_anuncio_ejecucion` (único), `idx_obs_comparable_ejec`, `idx_obs_precio`, `idx_obs_fecha`, `idx_obs_promocion`, `idx_anuncios_comercio`, `idx_anuncios_marca`, `idx_anuncios_subcat`, `idx_ejec_estado`: sobre las columnas que usan los filtros de la aplicación (comercio, subcategoría, marca, precio, ejecución/fecha, promoción, comparables).
