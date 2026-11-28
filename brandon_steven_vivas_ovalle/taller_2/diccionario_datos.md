# Diccionario de datos · Comparador de precios (Taller 2)

Base `comparador_precios.sqlite` (SQLite). **Moneda:** pesos colombianos (COP). **Fechas:** ISO 8601 con zona horaria de Colombia (UTC-5), p. ej. `2026-10-11T19:34:15-05:00`.
**Unidades normalizadas** (`unidad_base`): `unidad` (pañales, pañitos), `g` (gramos) o `ml` (mililitros). Nunca se comparan precios por unidad entre unidades base distintas.
**Datos ausentes:** un dato que el sitio no entrega queda `NULL`; nunca se reemplaza por un valor calculado.
Los textos originales de los anuncios (`nombre_original`, `descripcion_original`, `ficha_tecnica_original`) no se modifican; las versiones estandarizadas están en columnas `*_std`.

Relaciones: `comercios 1─n ejecuciones`, `comercios 1─n anuncios`, `anuncios 1─n observaciones`, `productos 1─n anuncios` (solo anuncios comparables), `ejecuciones 1─n observaciones`.

## tabla `comercios`
Comercios consultados (Éxito, Jumbo, Olímpica).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `comercio_id` | INTEGER | — | Identificador (llave primaria) | 1 Éxito, 2 Jumbo, 3 Olímpica |
| `clave` | TEXT | — | Clave corta usada por el scraper (única) | `exito`, `jumbo`, `olimpica` |
| `nombre` | TEXT | — | Nombre para mostrar | texto |
| `url_base` | TEXT | — | Dirección base del sitio consultado | URL |

## tabla `ejecuciones`
Una fila por ejecución del scraper y comercio. Una **ejecución** es una corrida (identificada por `run_AAAAMMDDTHHMMSS`) sobre uno o varios comercios.

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | — | Identificador de la ejecución (parte de la llave primaria) | `run_20261011T193258` |
| `comercio_id` | INTEGER | — | Comercio (parte de la llave primaria; FK a `comercios`) | 1, 2, 3 |
| `inicio` | TEXT | fecha-hora | Inicio de la recolección del comercio | ISO 8601 |
| `fin` | TEXT | fecha-hora | Fin de la recolección | ISO 8601 o NULL |
| `n_registros` | INTEGER | anuncios | Anuncios (SKU) recolectados antes de validar | ≥ 0 |
| `n_sitio_reportado` | INTEGER | productos | Total que el propio sitio informa para las categorías recorridas | entero o NULL |
| `estado` | TEXT | — | Resultado: `completa`; `parcial` (falló alguna consulta, se alcanzó el tope de peticiones o faltan productos comparables); `fallida` (sin datos) | completa, parcial, fallida |
| `modo` | TEXT | — | Cómo se obtuvo | `en_linea` (scraping), `sin_conexion` (reprocesado de `raw/`) |
| `modo_api` | TEXT | — | Servicio VTEX que respondió | `legacy`, `intelligent` o NULL |
| `notas` | TEXT | — | Motivo de fallas, rechazos o productos comparables ausentes | texto o NULL |
| `n_rechazadas` | INTEGER | observaciones | Observaciones que no superaron la validación (Taller 2) | ≥ 0 |

## tabla `productos`
Catálogo de **productos comparables**: presentaciones idénticas (misma marca, línea, talla/etapa y contenido) presentes en los tres comercios.

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `producto_id` | INTEGER | — | Identificador común entre comercios | entero |
| `clave` | TEXT | — | Clave de correspondencia: marca\|subcategoría\|variante\|etapa\|contenido+unidad (única) | texto |
| `grupo` | TEXT | — | La clave sin el contenido (misma línea y talla, distinto tamaño de paquete) | texto |
| `nombre_std` | TEXT | — | Nombre estandarizado legible | texto |
| `marca_std` | TEXT | — | Marca normalizada | Winny, Huggies… |
| `subcategoria_std` | TEXT | — | Subcategoría | pañal, pañitos húmedos, cambiador desechable, crema de barrera |
| `variante_std` | TEXT | — | Rasgos de la línea (p. ej. `gold`, `pants`, `ultratrim`) | texto o NULL |
| `etapa_std` | INTEGER | índice de talla | Talla normalizada: 0 RN, 1 P, 2 M, 3 G, 4 XG, 5 XXG, 6 XXXG | 0–6 o NULL |
| `contenido_total` | REAL | según `unidad_base` | Contenido total de la presentación | > 0 |
| `unidad_base` | TEXT | — | Unidad del contenido | unidad, g, ml |

## tabla `anuncios`
Producto tal como aparece en un comercio (un SKU de un comercio).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `anuncio_id` | INTEGER | — | Identificador (llave primaria) | entero |
| `comercio_id` | INTEGER | — | Comercio (FK) | 1, 2, 3 |
| `sku` | TEXT | — | Código del SKU en el sitio (único por comercio) | texto |
| `product_id` | TEXT | — | Identificador de producto VTEX | texto o NULL |
| `ean` | TEXT | — | Código de barras | texto o NULL |
| `url` | TEXT | — | Enlace al anuncio | URL |
| `nombre_original` | TEXT | — | Nombre tal como lo publica el sitio | texto |
| `descripcion_original` | TEXT | — | Descripción original | texto o NULL |
| `ficha_tecnica_original` | TEXT | — | Ficha técnica original (JSON) | JSON o NULL |
| `marca_original` | TEXT | — | Marca tal como la publica el sitio | texto o NULL |
| `categoria_sitio` | TEXT | — | Ruta de categoría del sitio | texto o NULL |
| `via` | TEXT | — | Consulta(s) que encontraron el anuncio (categoría o búsqueda) | texto |
| `marca_std` | TEXT | — | Marca normalizada | texto o NULL |
| `subcategoria_std` | TEXT | — | Subcategoría asignada | pañal, pañitos húmedos, cambiador desechable, crema de barrera, NULL |
| `variante_std` | TEXT | — | Rasgos de la línea | texto o NULL |
| `etapa_std` | INTEGER | índice de talla | Talla normalizada (ver `productos.etapa_std`) | 0–6 o NULL |
| `contenido_total` | REAL | según `unidad_base` | Contenido total de la presentación (un multipaquete 3 x 80 = 240) | > 0 o NULL |
| `unidad_base` | TEXT | — | Unidad del contenido | unidad, g, ml o NULL |
| `unidades_por_paquete` | REAL | unidades | Unidades de un paquete (80 en 3 x 80) | > 0 o NULL |
| `incluido` | INTEGER | — | 1 si el anuncio pertenece a la categoría delimitada; 0 si se excluyó | 0, 1 |
| `motivo_descarte` | TEXT | — | Razón de la exclusión | texto o NULL |
| `inconsistencia_contenido` | INTEGER | — | 1 si el contenido del nombre difiere de la cantidad de la ficha técnica | 0, 1 |
| `clave` | TEXT | — | Clave de correspondencia calculada | texto o NULL |
| `producto_id` | INTEGER | — | Producto comparable al que corresponde (FK a `productos`) | entero o NULL |
| `comparable` | INTEGER | — | 1 si el anuncio es un comparable | 0, 1 |

## tabla `observaciones`
Una fila por anuncio y ejecución: el precio visto en ese momento. **Restricciones de unicidad:** `(anuncio_id, fecha_hora_consulta)` y `(ejecucion_id, anuncio_id)`; no se puede insertar dos veces la misma observación.

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `obs_id` | INTEGER | — | Identificador (llave primaria) | entero |
| `ejecucion_id` | TEXT | — | Ejecución a la que pertenece | `run_…` |
| `comercio_id` | INTEGER | — | Comercio (con `ejecucion_id` referencia a `ejecuciones`) | 1, 2, 3 |
| `anuncio_id` | INTEGER | — | Anuncio observado (FK) | entero |
| `fecha_hora_consulta` | TEXT | fecha-hora | Momento exacto de la consulta | ISO 8601 |
| `fecha_consulta` | TEXT | fecha | Solo la fecha de la consulta | AAAA-MM-DD |
| `precio` | REAL | COP | Precio de venta vigente; NULL si el sitio no lo informa (típicamente agotado) | > 0 o NULL |
| `precio_lista` | REAL | COP | Precio de lista antes del descuento | > 0 o NULL |
| `es_promocion` | INTEGER | — | 1 si `precio` < `precio_lista` | 0, 1 |
| `disponible` | INTEGER | — | 1 si el sitio informa existencias (compatibilidad con el Taller 1) | 0, 1 |
| `estado_disponibilidad` | TEXT | — | `disponible` o `agotado` según el sitio. El tercer estado, `no_observado`, no es una fila: lo calcula la vista `v_disponibilidad` | disponible, agotado |
| `raw_archivo` | TEXT | ruta | Copia cruda (JSON comprimido en `raw/`) de donde se extrajo la observación | ruta relativa o NULL |

## tabla `observaciones_rechazadas`
Observaciones que **no superaron la validación** y por eso no se insertaron.

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `rechazo_id` | INTEGER | — | Identificador | entero |
| `ejecucion_id` | TEXT | — | Ejecución en la que se detectó | `run_…` |
| `comercio_id` | INTEGER | — | Comercio (FK) | 1, 2, 3 |
| `sku` | TEXT | — | SKU del anuncio | texto o NULL |
| `url` | TEXT | — | Enlace del anuncio | texto o NULL |
| `fecha_hora_consulta` | TEXT | fecha-hora | Momento de la consulta | texto o NULL |
| `precio` | REAL | COP | Precio recibido | número o NULL |
| `disponible` | INTEGER | — | Disponibilidad recibida | 0, 1 o NULL |
| `motivo` | TEXT | — | Regla(s) incumplida(s), separadas por `;` | `precio_numerico_positivo`, `url_presente`, `fecha_hora_valida`, `sin_duplicados_en_ejecucion`… |
| `datos_json` | TEXT | — | Registro rechazado completo (JSON) para auditarlo | JSON |
| `fecha_rechazo` | TEXT | fecha-hora | Cuándo se rechazó | ISO 8601 |

## tabla `correcciones`
Registro de correcciones hechas a la base del Taller 1 (nunca se borran observaciones).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `correccion_id` | INTEGER | — | Identificador | entero |
| `fecha` | TEXT | fecha-hora | Cuándo se corrigió | ISO 8601 |
| `tabla` | TEXT | — | Tabla del registro afectado | texto |
| `registro_id` | TEXT | — | Llave del registro afectado | texto |
| `campo` | TEXT | — | Campo corregido | texto |
| `valor_anterior` | TEXT | — | Valor antes de la corrección | texto o NULL |
| `valor_nuevo` | TEXT | — | Valor después de la corrección | texto o NULL |
| `motivo` | TEXT | — | Por qué se corrigió | texto |
| `autor` | TEXT | — | Quién o qué script la aplicó | texto |

## vista `v_ejecuciones_resumen`
Una fila por ejecución (agrega los comercios). Base del selector de ejecuciones y de «última ejecución».

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | — | Ejecución | `run_…` |
| `inicio` | TEXT | fecha-hora | Menor inicio entre los comercios | ISO 8601 |
| `fin` | TEXT | fecha-hora | Mayor fin entre los comercios | ISO 8601 |
| `fecha` | TEXT | fecha | Fecha de inicio | AAAA-MM-DD |
| `n_comercios` | INTEGER | comercios | Comercios con fila en la ejecución | ≥ 1 |
| `n_completas` | INTEGER | comercios | Comercios con estado `completa` | ≥ 0 |
| `n_parciales` | INTEGER | comercios | Comercios con estado `parcial` | ≥ 0 |
| `n_fallidas` | INTEGER | comercios | Comercios con estado `fallida` | ≥ 0 |
| `n_registros` | INTEGER | anuncios | Suma de registros recolectados | ≥ 0 |
| `es_completa` | INTEGER | — | 1 si todos los comercios de la base quedaron `completa` | 0, 1 |
| `estado` | TEXT | — | `completa`, `parcial` o `fallida` para toda la ejecución | texto |
| `modo` | TEXT | — | Modo(s) de obtención | en_linea, sin_conexion |

## vista `v_ultima_ejecucion_comercio`
Última ejecución **no fallida** de cada comercio.

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `comercio_id` | INTEGER | — | Comercio | 1, 2, 3 |
| `ejecucion_id` | TEXT | — | Su última ejecución con datos | `run_…` |
| `inicio` | TEXT | fecha-hora | Inicio de esa ejecución | ISO 8601 |
| `estado` | TEXT | — | Estado de esa ejecución | completa, parcial |

## vista `v_observaciones`
Observación + anuncio + comercio, solo anuncios dentro de la categoría (`incluido = 1`). Base de la tabla, los filtros y varios gráficos.

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `obs_id`, `ejecucion_id`, `comercio_id`, `anuncio_id`, `sku` | — | — | Identificadores (ver `observaciones` y `anuncios`) | — |
| `comercio_clave` | TEXT | — | Clave del comercio | exito, jumbo, olimpica |
| `comercio` | TEXT | — | Nombre del comercio | Éxito, Jumbo, Olímpica |
| `nombre_original`, `descripcion_original`, `marca_original`, `url`, `categoria_sitio` | TEXT | — | Textos originales del anuncio | — |
| `marca` | TEXT | — | `marca_std` o, si falta, `marca_original` | texto |
| `subcategoria` | TEXT | — | `subcategoria_std` del anuncio | texto |
| `variante_std`, `etapa_std`, `contenido_total`, `unidad_base` | — | — | Atributos estandarizados (ver `anuncios`) | — |
| `presentacion` | TEXT | — | Contenido y unidad legibles, p. ej. `80 unidad` | texto o NULL |
| `incluido`, `comparable`, `producto_id` | INTEGER | — | Ver `anuncios` | — |
| `producto_comparable` | TEXT | — | `nombre_std` del producto comparable | texto o NULL |
| `fecha_hora_consulta`, `fecha_consulta`, `precio`, `precio_lista`, `es_promocion`, `raw_archivo` | — | — | Ver `observaciones` | — |
| `estado_disponibilidad` | TEXT | — | disponible o agotado | disponible, agotado |
| `precio_unitario` | REAL | COP por `unidad_base` | `precio / contenido_total` | > 0 o NULL |

## vista `v_ultimo_precio`
Observación más reciente de cada anuncio **dentro de la última ejecución de su comercio** (los anuncios que no aparecieron en ella no están). Tiene exactamente las columnas de `v_observaciones`:
`obs_id`, `ejecucion_id`, `comercio_id`, `comercio_clave`, `comercio`, `anuncio_id`, `sku`, `nombre_original`, `descripcion_original`, `marca_original`, `marca`, `subcategoria`, `variante_std`, `etapa_std`, `contenido_total`, `unidad_base`, `presentacion`, `incluido`, `comparable`, `producto_id`, `producto_comparable`, `url`, `categoria_sitio`, `fecha_hora_consulta`, `fecha_consulta`, `precio`, `precio_lista`, `es_promocion`, `estado_disponibilidad`, `precio_unitario`, `raw_archivo` (significado, tipo y unidad como en `v_observaciones`).

## vista `v_comparables`
Una fila por ejecución × comercio × producto comparable: el anuncio **disponible de menor precio** (si el comercio tiene varios SKU del mismo producto).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `ejecucion_id`, `comercio_id`, `comercio`, `producto_id` | — | — | Ejecución, comercio y producto | — |
| `nombre_std` | TEXT | — | Nombre del producto comparable | texto |
| `subcategoria` | TEXT | — | Subcategoría | texto |
| `contenido_total` | REAL | según `unidad_base` | Contenido de la presentación | > 0 |
| `unidad_base` | TEXT | — | Unidad del contenido | unidad, g, ml |
| `anuncio_id` | INTEGER | — | Anuncio con el menor precio | entero |
| `precio` | REAL | COP | Precio de venta mínimo disponible | > 0 |
| `precio_regular` | REAL | COP | Precio de lista (o el precio si no hay lista) | > 0 |
| `precio_unitario` | REAL | COP por `unidad_base` | Precio por unidad de contenido | > 0 |
| `en_promocion` | INTEGER | — | 1 si ese anuncio está en promoción | 0, 1 |
| `fecha_hora_consulta`, `fecha_consulta` | TEXT | fecha-hora / fecha | Momento de la consulta | ISO 8601 |
| `url` | TEXT | — | Enlace al anuncio | URL |
| `n_anuncios` | INTEGER | anuncios | SKU del mismo producto con precio disponible en el comercio | ≥ 1 |

## vista `v_cambios_precio`
Cambios de precio del **mismo anuncio** entre observaciones consecutivas (solo con precio y disponible en ambas; variación > 0,5 COP).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `ejecucion_id` | TEXT | — | Ejecución en la que se observa el precio nuevo | `run_…` |
| `comercio_id`, `comercio`, `anuncio_id`, `sku` | — | — | Comercio y anuncio | — |
| `nombre_original` | TEXT | — | Nombre original del anuncio | texto |
| `marca`, `subcategoria`, `producto_id`, `comparable` | — | — | Atributos del anuncio (ver `v_observaciones`) | — |
| `ejecucion_anterior` | TEXT | — | Ejecución de la observación previa | `run_…` |
| `fecha_anterior` | TEXT | fecha-hora | Momento de la observación previa | ISO 8601 |
| `precio_anterior` | REAL | COP | Precio previo | > 0 |
| `precio_nuevo` | REAL | COP | Precio nuevo | > 0 |
| `fecha_hora_consulta` | TEXT | fecha-hora | Momento de la observación nueva | ISO 8601 |
| `variacion_cop` | REAL | COP | `precio_nuevo - precio_anterior` | ≠ 0 |
| `variacion_pct` | REAL | % | Variación relativa al precio anterior | ≠ 0 |

## vista `v_disponibilidad`
Tres estados por anuncio y ejecución (solo ejecuciones no fallidas y anuncios ya vistos en o antes de esa ejecución).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `ejecucion_id`, `comercio_id`, `anuncio_id`, `producto_id`, `comparable` | — | — | Identificadores y marca de comparable | — |
| `estado` | TEXT | — | `disponible`; `agotado` (el sitio lo informó); `no_observado` (el anuncio no apareció en la ejecución: **no** significa agotado ni retirado) | disponible, agotado, no_observado |

## vista `v_precios_comparables`
Vista del Taller 1 (una fila por ejecución × comercio × producto comparable; se conserva para reproducir el Taller 1).

| columna | tipo | unidad | significado | valores |
|---|---|---|---|---|
| `ejecucion_id`, `comercio`, `producto_id`, `nombre_std`, `grupo` | — | — | Identificación del producto y comercio | — |
| `contenido_total`, `unidad_base` | — | — | Presentación | — |
| `precio` | REAL | COP | Mínimo precio disponible | > 0 |
| `precio_regular` | REAL | COP | Mínimo precio de lista | > 0 |
| `n_observaciones` | INTEGER | observaciones | Observaciones agregadas | ≥ 1 |
| `alguna_promocion` | INTEGER | — | 1 si alguna observación estaba en promoción | 0, 1 |

## Índices
`ux_obs_ejec_anuncio` (único), `ix_obs_ejec`, `ix_obs_anuncio_fecha`, `ix_obs_fecha`, `ix_obs_precio`, `ix_anu_filtros` (comercio, incluido, subcategoría, marca), `ix_anu_producto`, `ix_anu_comparable`, `ix_anu_clave`, `ix_ejec_comercio`, `ix_rech_ejec`, `ix_corr_registro`: cubren las columnas usadas por los filtros de la aplicación (comercio, subcategoría, marca, precio, ejecución, fecha, comparables).
