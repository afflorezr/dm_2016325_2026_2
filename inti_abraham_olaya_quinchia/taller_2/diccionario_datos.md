# Diccionario de datos — `comparador_precios.sqlite`

Precios en **pesos colombianos (COP)**. Fechas en **ISO 8601 con hora de Colombia (−05:00)**. Un valor no disponible queda como `NULL`; nunca se reemplaza por 0. Los textos originales del anuncio no se modifican: la versión estandarizada vive en campos propios.

## Tablas

### `comercios`
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id | INTEGER | Identificador del comercio | clave primaria |
| nombre | TEXT | Nombre del comercio | La Rebaja, Locatel, Éxito, Olímpica, Jumbo, Carulla |
| url_base | TEXT | Dirección base del sitio | URL |

### `ejecuciones`
Una fila por comercio en cada corrida del scraper.
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id | INTEGER | Identificador de la ejecución | clave primaria |
| corrida_id | TEXT | Identificador de la corrida | `run-AAAAMMDDThhmmss` o `raw-<fecha>` (modo sin conexión) |
| inicio | TEXT | Fecha y hora de la consulta | ISO 8601 |
| comercio | TEXT | Comercio consultado | ver `comercios.nombre` |
| modo | TEXT | Modo de ejecución | `online`, `offline` |
| n_registros | INTEGER | Registros obtenidos | ≥ 0 |
| n_productos | INTEGER | Productos distintos obtenidos | ≥ 0 |
| n_esperado_sitio | INTEGER | Total que informa el sitio (encabezado `resources`) | ≥ 0 o NULL |
| estado | TEXT | Resultado | `completa`, `parcial`, `fallida` |
| detalle | TEXT | Motivo si no fue completa | texto o NULL |

Restricción: `UNIQUE (corrida_id, comercio)`.

### `categorias_sitio`
| Columna | Tipo | Significado |
|---|---|---|
| corrida_id, comercio | TEXT | Ejecución a la que pertenece |
| categoria_id | TEXT | Identificador de la categoría en el sitio |
| nombre | TEXT | Nombre de la categoría equivalente a «Afeitado y depilación» |
| ruta | TEXT | Ruta de identificadores en el árbol del sitio |
| total_sitio | INTEGER | Total de productos que informa el sitio (para verificar completitud) |

### `productos`
Identificador común de una misma presentación entre comercios (se reconstruye en cada corrida).
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id | INTEGER | Identificador del producto común | clave primaria |
| clave_comun | TEXT | Regla de correspondencia | `EAN:<código>` o `TXT:<marca>|<nombre base>|<contenido>|<unidad>` |
| marca | TEXT | Marca estandarizada | texto |
| nombre_estandar | TEXT | Nombre normalizado | minúsculas, sin tildes |
| subcategoria | TEXT | Subcategoría | Cuchillas y repuestos, Máquinas de afeitar, Rastrillos desechables, Espumas de afeitar, Geles de afeitar, Depilación, Después del afeitado, Otros afeitado/depilación |
| contenido_total | REAL | Contenido total de la presentación | número |
| unidad_base | TEXT | Unidad del contenido | `mL`, `g`, `mg`, `unidad` |
| n_comercios | INTEGER | Comercios en los que aparece | ≥ 1 |
| comparable | INTEGER | 1 si tiene precio en los tres comercios del análisis en la misma ejecución | 0, 1 |

### `anuncios`
Producto tal como aparece en un comercio.
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id | INTEGER | Identificador del anuncio | clave primaria |
| comercio_id | INTEGER | Comercio | → `comercios.id` |
| sku | TEXT | Identificador interno en el comercio | texto |
| ean | TEXT | Código de barras | texto o NULL |
| product_id | TEXT | Identificador del producto en el sitio | texto |
| url | TEXT | Página de origen del precio | URL |
| nombre_original, descripcion_original, texto_original | TEXT | Texto del anuncio **sin limpiar** | texto |
| marca_original | TEXT | Marca como la publica el sitio | texto o NULL |
| categoria_sitio | TEXT | Categoría del sitio de la que se extrajo | texto |
| marca_estandar, nombre_estandar, nombre_base | TEXT | Versiones estandarizadas | texto |
| subcategoria | TEXT | Subcategoría asignada por reglas | ver `productos.subcategoria` |
| contenido_total | REAL | Contenido extraído del nombre/descripción | número o NULL |
| unidad_base | TEXT | Unidad extraída | `mL`, `g`, `mg`, `unidad` o NULL |
| unidades_paquete | INTEGER | Número de envases del paquete | ≥ 1 |
| excluido | INTEGER | 1 si no pertenece a la categoría | 0, 1 |
| motivo_exclusion | TEXT | Motivo de la exclusión | texto o NULL |
| producto_id | INTEGER | Producto común asignado | → `productos.id` o NULL |
| unidad_normalizada | TEXT | Unidad para comparar (mg se convierte a g) | `mL`, `g`, `unidad` o NULL |
| contenido_normalizado | REAL | Contenido expresado en `unidad_normalizada` | número o NULL |

Restricción: `UNIQUE (comercio_id, sku)`.

### `observaciones`
Precio de un anuncio en un momento dado. Nunca se sobrescriben.
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id | INTEGER | Identificador | clave primaria |
| anuncio_id | INTEGER | Anuncio observado | → `anuncios.id` |
| ejecucion_id | INTEGER | Ejecución que la produjo | → `ejecuciones.id` |
| precio_cop | REAL | Precio vigente en COP | > 0 o NULL (agotado / no extraído) |
| precio_regular_cop | REAL | Precio antes del descuento, si el sitio lo muestra | > 0 o NULL |
| en_promocion | INTEGER | 1 si el precio es menor al regular | 0, 1 |
| disponible | INTEGER | Disponibilidad según el sitio (Taller 1) | 0, 1 |
| fecha_consulta | TEXT | Fecha y hora de la observación | ISO 8601 |
| disponibilidad | TEXT | Estado de disponibilidad | `disponible`, `agotado`, `no observado`* |
| comercio_id | INTEGER | Comercio (copiado del anuncio, para la unicidad) | → `comercios.id` |

\* `no observado` no se guarda por observación (no hay fila si el anuncio no apareció); `v_ultimo_precio` lo calcula. No significa agotado ni retirado.

Restricciones: `UNIQUE (anuncio_id, fecha_consulta)` y índice único `(comercio_id, anuncio_id, fecha_consulta)`.

### `seleccion`
| Columna | Significado |
|---|---|
| comercio_id | Comercios usados en el análisis (tres, de grupos empresariales distintos) |

### `correcciones`
Registro de correcciones a la base del Taller 1 (no se borran observaciones).
| Columna | Tipo | Significado |
|---|---|---|
| id | INTEGER | Identificador |
| fecha | TEXT | Fecha de la corrección (ISO 8601) |
| id_registro | INTEGER | Registro afectado |
| valor_anterior, valor_nuevo | TEXT | Valores antes y después |
| motivo | TEXT | Razón de la corrección |

### `observaciones_rechazadas`
Observaciones que no superaron la validación (pandera); no se insertan en `observaciones`.
| Columna | Tipo | Significado |
|---|---|---|
| id | INTEGER | Identificador |
| fecha_rechazo | TEXT | Cuándo se rechazó |
| corrida_id, comercio, sku, fecha_consulta, precio_cop | — | Datos de la fila rechazada |
| motivo | TEXT | Regla incumplida (por ejemplo, `precio <= 0`) |
| fila_json | TEXT | Fila completa tal como llegó del scraper |

## Vistas

### `v_obs` (Taller 1)
Observaciones unidas a ejecución, comercio, anuncio y producto, con la bandera `comparable` (1 si el producto es comparable y el comercio está en `seleccion`).

### `v_ultimo_precio`
Última observación de cada anuncio no excluido.
Columnas: `comercio`, `anuncio_id`, `sku`, `url`, `texto_original`, `nombre_estandar`, `marca`, `subcategoria`, `contenido_normalizado`, `unidad_normalizada`, `precio` (COP), `precio_regular_cop` (COP), `en_promocion` (0/1), `disponibilidad` (`disponible`/`agotado`/`no observado`), `fecha_consulta`, `corrida_id`, `precio_unitario` (COP por mL, g o unidad; NULL si falta precio o contenido), `producto_id`, `comparable` (0/1).

### `v_cambios_precio`
Cambio entre observaciones consecutivas del mismo anuncio en el mismo comercio.
Columnas: `comercio`, `anuncio_id`, `sku`, `url`, `texto_original`, `marca`, `subcategoria`, `corrida_anterior`, `corrida_id`, `fecha_anterior`, `fecha_consulta`, `precio_anterior` (COP), `precio_nuevo` (COP), `variacion_cop`, `variacion_pct` (%), `sentido` (`subio`/`bajo`/`igual`).

### `v_comparables`
Observaciones de los productos comparables en los comercios de `seleccion`.
Columnas: `corrida_id`, `producto_id`, `clave_comun`, `marca`, `producto`, `comercio`, `anuncio_id`, `sku`, `url`, `texto_original`, `fecha_consulta`, `precio` (COP), `en_promocion`, `disponibilidad`, `contenido_normalizado`, `unidad_normalizada`, `precio_unitario` (COP por unidad normalizada), `precio_min_corrida` y `precio_max_corrida` (COP, por producto y ejecución), `es_precio_minimo` (1 también en empates).
