# Diccionario de datos — `comparador_precios.sqlite`

## Convenciones

- **Fechas:** texto ISO 8601 con la hora de Colombia, por ejemplo `2026-11-15T18:54:37-05:00`.
- **`id_ejecucion`:** hora de inicio de la corrida, en formato `AAAAMMDDTHHMMSS` (por ejemplo `20261115T185400`). Ordenarlo como texto equivale a ordenarlo por fecha.
- **Precios:** en pesos colombianos (COP), por empaque. Un precio que el sitio no publica queda `NULL`, nunca 0.
- **Unidades normalizadas:** `mL`, `g` o `und` (artículos contables: gafas, estuches, lentes de contacto por unidad de la caja).
- **Claves de comercio:** `locatel`, `farmatodo` y `colsubsidio`.

## Tablas

### `comercios`
| Columna | Tipo | Significado |
|---|---|---|
| comercio | TEXT, PK | Clave del comercio |
| nombre | TEXT | Nombre para mostrar (Locatel, Farmatodo, Droguerías Colsubsidio) |
| url_categoria | TEXT | Página de la categoría en el sitio |

### `ejecuciones`
Una fila por corrida y comercio.

| Columna | Tipo | Significado / valores |
|---|---|---|
| id_ejecucion | TEXT, PK (con comercio) | Identificador de la corrida |
| comercio | TEXT, PK, FK → comercios | |
| inicio, fin | TEXT ISO 8601 | Inicio y fin de la consulta de ese comercio |
| modo | TEXT | `en_linea` (se consultó el sitio) o `sin_conexion` (se procesó desde `raw/` sin una consulta previa registrada) |
| n_registros | INTEGER | Anuncios válidos obtenidos (toda la sección del sitio) |
| total_sitio | INTEGER | Total de anuncios que informa el propio servicio del comercio |
| n_en_categoria | INTEGER | Anuncios dentro de la delimitación de la categoría |
| estado | TEXT | `completa`, `parcial` (faltan anuncios frente al total del sitio o falta un comparable) o `fallida` (sin datos) |
| detalle | TEXT | Motivo del estado: conteos, rechazos, comparables faltantes o error |
| reprocesada | TEXT ISO 8601 | Fecha y hora del último reproceso sin conexión de esa ejecución (`NULL` si nunca se reprocesó) |

### `anuncios`
Cada producto tal como aparece en un comercio. Guarda los atributos estandarizados más recientes.

| Columna | Tipo | Significado / valores |
|---|---|---|
| comercio, sku | TEXT, PK | Comercio e identificador interno del producto en ese sitio |
| ean | TEXT | Código de barras principal publicado |
| ean_alt | TEXT | Otros códigos publicados, separados por `\|` (Farmatodo) |
| nombre_original | TEXT | Nombre y presentación tal como los publica el sitio |
| marca_original | TEXT | Marca tal como la publica el sitio |
| subcategoria_sitio | TEXT | Categoría o subcategoría del sitio |
| nombre_std | TEXT | Nombre en minúsculas, sin tildes ni prefijos |
| marca_std | TEXT | Marca estandarizada (línea de producto cuando el nombre la identifica) |
| subcategoria_std | TEXT | `Lentes de lectura`, `Lentes de contacto`, `Solución para lentes de contacto`, `Estuches`, `Limpieza de gafas` o `NULL` si está fuera de la categoría |
| en_categoria | INTEGER | 1 = dentro de la delimitación de la planilla; 0 = excluido |
| motivo_exclusion | TEXT | Por qué se excluye (gotas lubricantes, gafas de sol, suplemento, etc.) |
| contenido | REAL | Contenido del empaque en la unidad normalizada |
| unidad | TEXT | `mL`, `g` o `und` |
| n_unidades | INTEGER | Unidades del empaque (por ejemplo, 6 lentes) |
| graduacion | REAL | Dioptrías de gafas y lentes (por ejemplo, 1.5) |
| tiene_descripcion | INTEGER | 1 si el anuncio trae una descripción de al menos 10 caracteres |
| id_producto | TEXT, FK → productos | Identificador común si el producto está en los tres comercios |
| comparable | INTEGER | 1 = presentación comparable entre los tres comercios |

### `productos`
Presentaciones idénticas presentes en los tres comercios.

| Columna | Tipo | Significado / valores |
|---|---|---|
| id_producto | TEXT, PK | `SV-<EAN normalizado>` |
| ean | TEXT | EAN común (sin ceros a la izquierda) |
| nombre_std | TEXT | Nombre común con su tamaño (por ejemplo, `ReNu multipropósito 355 mL`) |
| linea | TEXT | Mismo producto y formulación en distintos tamaños |
| marca_std, subcategoria_std | TEXT | Ver `anuncios` |
| contenido, unidad | REAL, TEXT | Contenido total y unidad normalizada de la presentación |
| n_unidades | INTEGER | Unidades del empaque |
| graduacion | REAL | Dioptrías (gafas) |
| regla_correspondencia | TEXT | `EAN idéntico` o `EAN + equivalencia manual` |

### `observaciones`
Un precio en un momento dado. Las ejecuciones nuevas se agregan sin sobrescribir.

| Columna | Tipo | Significado / valores |
|---|---|---|
| id_observacion | INTEGER, PK | Autonumérico |
| id_ejecucion | TEXT, FK → ejecuciones | Corrida que la produjo |
| comercio, sku | TEXT, FK → anuncios | |
| seccion | TEXT | Sección del sitio consultada |
| precio | REAL | Precio de venta en COP (de oferta si existe); `NULL` si el sitio no lo publica |
| precio_lista | REAL | Precio antes del descuento |
| promocion | INTEGER | 1 si precio_lista > precio |
| disponible | INTEGER | 1 = disponible; 0 = agotado según el sitio |
| url | TEXT | Enlace al anuncio |
| texto_original | TEXT | Nombre, presentación y descripción sin limpiar, separados por `\|` |
| fecha_hora_consulta | TEXT ISO 8601 | Hora de la consulta (coincide con el nombre de la copia cruda) |
| descartada | INTEGER | 1 = marcada como errónea en `correcciones` (no se borra; las vistas la excluyen) |

Restricción: `UNIQUE(comercio, sku, fecha_hora_consulta)`.

### `observaciones_rechazadas`
Observaciones que no superaron `validacion.R`. No entran a `observaciones`.

| Columna | Tipo | Significado / valores |
|---|---|---|
| id_rechazo | INTEGER, PK | |
| id_ejecucion, comercio, sku | TEXT | Origen de la observación |
| regla | TEXT | `precio_numerico`, `precio_positivo`, `precio_presente_disponible`, `comercio_presente`, `sku_presente`, `url_presente`, `fecha_presente` o `sin_duplicados` |
| motivo | TEXT | Descripción de la regla incumplida |
| precio, url, fecha_hora_consulta, texto_original | | Valores tal como llegaron |
| fecha_registro | TEXT ISO 8601 | Cuándo se rechazó |

Restricción: `UNIQUE(id_ejecucion, comercio, sku, regla)`.

### `correcciones`
Cambios hechos a la base del Taller 1 (sección 3.2).

| Columna | Tipo | Significado |
|---|---|---|
| id_correccion | INTEGER, PK | |
| fecha | TEXT ISO 8601 | Cuándo se aplicó |
| tabla | TEXT | Tabla afectada |
| registro | TEXT | Clave del registro (`id_ejecucion/comercio` o `comercio/sku`) |
| campo | TEXT | Columna corregida |
| valor_anterior, valor_nuevo | TEXT | |
| motivo | TEXT | Justificación |

Restricción: `UNIQUE(tabla, registro, campo)`.

## Vistas

### `v_observaciones`
Observaciones no descartadas, unidas a `anuncios` y `productos`.

- Columnas: `id_observacion`, `id_ejecucion`, `comercio`, `sku`, `id_producto`, `comparable`, `en_categoria`, `motivo_exclusion`, `producto`, `nombre_original`, `marca_std`, `subcategoria_std`, `contenido`, `unidad`, `n_unidades`, `graduacion`, `precio`, `precio_lista`, `promocion`, `disponible`, `url`, `texto_original` y `fecha_hora_consulta`.
- `producto`: el nombre común si el anuncio es comparable; si no, el nombre estandarizado.
- `disponibilidad`: `disponible` o `agotado`.
- `precio_por_unidad`: precio / contenido, en COP por mL, g o und.

### `v_ultimo_precio`
Última observación de cada anuncio, con las columnas principales de `v_observaciones`. `vigente` vale 1 si esa observación pertenece a la ejecución no fallida más reciente de su comercio.

### `v_cambios_precio`
Cada observación comparada con la anterior del mismo anuncio (`LAG` por comercio y sku, ordenado por fecha).

- `ejecucion_anterior`, `precio_anterior`, `fecha_anterior`: datos de la observación anterior.
- `cambio_cop`: diferencia en COP.
- `cambio_pct`: variación en %.
- `direccion`: `subió`, `bajó`, `igual` o `sin precio`.

### `v_comparables`
Observaciones de presentaciones comparables con los datos de `productos`: `nombre_std`, `linea`, `contenido`, `unidad` y `precio_unitario`, que es el precio / contenido en COP por mL, g o und.

### `v_disponibilidad`
Para cada ejecución no fallida de un comercio y cada anuncio ya visto en ese comercio, da `disponibilidad` con tres valores:

- `disponible`;
- `agotado`, cuando el sitio lo indica;
- `no observado`, cuando el anuncio no apareció en esa ejecución. No implica que esté agotado ni retirado.

## Índices

| Índice | Columnas |
|---|---|
| `idx_obs_ejecucion` | observaciones(id_ejecucion, comercio) |
| `idx_obs_fecha` | observaciones(fecha_hora_consulta) |
| `idx_obs_precio` | observaciones(precio) |
| `idx_obs_promocion` | observaciones(promocion) |
| `idx_anu_subcat` | anuncios(subcategoria_std) |
| `idx_anu_marca` | anuncios(marca_std) |
| `idx_anu_comparable` | anuncios(comparable, id_producto) |
| `idx_anu_categoria` | anuncios(en_categoria) |
