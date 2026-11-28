# Diccionario de datos

Base `comparador_precios.sqlite`. Categoría: perfumes (Parfum, EDP, EDT y EDC) en La Riviera, Falabella y Farmatodo. Los precios están en pesos colombianos (COP) e incluyen IVA, como los muestra el sitio. Las fechas y horas están en formato ISO 8601 con la zona de Colombia (`-05:00`). Un dato que el sitio no muestra queda en `NULL`.

## Tablas

### comercios
Un registro por comercio.

| Columna | Tipo | Descripción |
|---|---|---|
| comercio_id | INTEGER | Llave. 1 La Riviera, 2 Falabella, 3 Farmatodo |
| nombre | TEXT | Nombre que se muestra en la aplicación |
| clave | TEXT | Nombre corto usado en las carpetas de `raw/` |
| sitio_web | TEXT | Dirección del sitio |
| url_categoria | TEXT | Página de la categoría de perfumes |
| metodo_extraccion | TEXT | Cómo se obtienen los datos (HTML, JSON o servicio interno) |

### ejecuciones
Una fila por ejecución del scraper y comercio.

| Columna | Tipo | Descripción |
|---|---|---|
| id_ejecucion | TEXT | Identificador de la ejecución, `AAAAMMDDTHHMMSS` (hora de inicio) |
| comercio_id | INTEGER | Comercio (llave foránea a `comercios`) |
| fecha_hora_inicio | TEXT | Inicio de la recolección del comercio |
| fecha_hora_fin | TEXT | Fin de la recolección |
| modo | TEXT | `en_linea` (consulta los sitios) o `sin_conexion` (reprocesa `raw/`) |
| n_registros | INTEGER | Productos distintos obtenidos |
| n_total_sitio | INTEGER | Total que muestra el sitio, si lo muestra |
| estado | TEXT | `completa`, `parcial` o `fallida` |
| detalle | TEXT | Explicación del estado, o el motivo de la falla |

### productos
Catálogo de las presentaciones comparables (`datos/catalogo_comparables.csv`).

| Columna | Tipo | Descripción |
|---|---|---|
| producto_id | TEXT | Llave, p. ej. `VERSACE-EROS-EDT-100` |
| familia | TEXT | Mismo perfume en distintos tamaños |
| marca, linea | TEXT | Marca y línea del perfume |
| concentracion | TEXT | `Extrait`, `Parfum`, `EDP`, `EDT` o `EDC` |
| contenido | REAL | Contenido de la presentación |
| unidad | TEXT | Siempre `ml` |
| unidades | INTEGER | Frascos por presentación (1) |
| genero | TEXT | `Hombre`, `Mujer` o `Unisex` |
| subcategoria | TEXT | `Perfume de hombre`, `Perfume de mujer` o `Perfume unisex` |
| descripcion | TEXT | Nombre legible |

### anuncios
Un producto publicado por un comercio. Se conserva entre ejecuciones.

| Columna | Tipo | Descripción |
|---|---|---|
| anuncio_id | INTEGER | Llave |
| comercio_id | INTEGER | Comercio |
| id_producto_comercio | TEXT | Identificador del producto en el sitio. Único por comercio |
| sku, ean | TEXT | Código del comercio y código de barras, si el sitio los muestra |
| url_producto | TEXT | Enlace al anuncio |
| marca_std, linea_std, concentracion_std, genero_std | TEXT | Campos estandarizados por `procesamiento.R` |
| contenido_ml | REAL | Contenido de un frasco, en mL |
| unidades | INTEGER | Frascos en el anuncio |
| subcategoria_std | TEXT | Subcategoría estándar (igual a `productos.subcategoria`) |
| excluido | INTEGER | 1 si no es un perfume de la categoría, 0 si lo es |
| motivo_exclusion | TEXT | Regla de exclusión que aplicó |
| producto_id | TEXT | Presentación comparable a la que corresponde, o NULL |
| regla_correspondencia | TEXT | Cómo se asignó la presentación |
| contenido_total | REAL | **Nuevo.** `contenido_ml × unidades` |
| unidad_norm | TEXT | **Nuevo.** Unidad del contenido total: `mL`, `g` o `unidad` (en perfumes, `mL`) |

### observaciones
Precio de un anuncio en una ejecución. Nunca se sobrescribe.

| Columna | Tipo | Descripción |
|---|---|---|
| observacion_id | INTEGER | Llave |
| anuncio_id | INTEGER | Anuncio observado |
| comercio_id | INTEGER | Comercio |
| id_ejecucion | TEXT | Ejecución en que se observó |
| fecha_hora_consulta | TEXT | Hora en que se descargó la página |
| nombre_original, marca_original, subcategoria_original, presentacion_original | TEXT | Textos tal como los muestra el sitio |
| contenido_original | REAL | Contenido que muestra el sitio |
| unidad_original | TEXT | Unidad que muestra el sitio |
| texto_original | TEXT | Texto completo del anuncio, sin limpiar |
| precio | REAL | Precio a pagar, en COP. Mayor que 0 |
| precio_antes | REAL | Precio tachado (antes del descuento), en COP |
| promocion | INTEGER | 1 si hay precio tachado o etiqueta de descuento, 0 si no |
| etiqueta_promocion | TEXT | Texto de la etiqueta (p. ej. `30% OFF`) |
| precio_condicionado | REAL | Precio con condición (p. ej. tarjeta CMR), en COP |
| condicion_precio | TEXT | Condición de ese precio |
| vendedor | TEXT | Vendedor, en los marketplaces |
| disponible | INTEGER | 1 disponible, 0 agotado según el sitio, NULL si el sitio no lo dice |
| url_extraccion | TEXT | Dirección que se consultó |
| archivo_raw | TEXT | Copia cruda en `raw/` de la que sale la observación |
| comparable | INTEGER | 1 si la presentación tiene precio en los tres comercios en esa ejecución |
| descartada | INTEGER | **Nuevo.** 1 si la observación no se usa: por un error o por ser una variante repetida del mismo producto en Falabella. Se registra en `correcciones` |

Restricciones: `UNIQUE (comercio_id, anuncio_id, fecha_hora_consulta)` y `UNIQUE (anuncio_id, id_ejecucion)`, que impide insertar dos veces la misma observación.

### correcciones (nueva)
Cada cambio a un dato ya guardado.

| Columna | Tipo | Descripción |
|---|---|---|
| correccion_id | INTEGER | Llave |
| fecha | TEXT | Cuándo se hizo |
| tabla | TEXT | Tabla afectada |
| registro_id | TEXT | Llave del registro (`anuncio_id` u `observacion_id`) |
| campo | TEXT | Columna cambiada |
| valor_anterior, valor_nuevo | TEXT | Valores antes y después |
| motivo | TEXT | Por qué se corrigió |

### rechazos (nueva)
Observaciones que no pasaron la validación de `validacion.R` y no se insertaron.

| Columna | Tipo | Descripción |
|---|---|---|
| rechazo_id | INTEGER | Llave |
| id_ejecucion, comercio_id | TEXT, INTEGER | Ejecución y comercio |
| id_producto_comercio, nombre_original | TEXT | Producto rechazado |
| precio | REAL | Precio leído (puede ser NULL) |
| regla | TEXT | Regla que no cumplió |
| fecha_hora_registro | TEXT | Cuándo se rechazó |

### controles_completitud (nueva)
Indicadores para verificar que cada ejecución trajo la categoría completa.

| Columna | Tipo | Descripción |
|---|---|---|
| id_ejecucion, comercio_id | TEXT, INTEGER | Ejecución y comercio |
| indicador | TEXT | Nombre del indicador. Falabella: `productos_obtenidos`, `total_sitio`, `cobertura_pct` (cuentan productos, no variantes). Farmatodo: `consultas_en_tope`, `tramos_finales` |
| valor | REAL | Valor |
| descripcion | TEXT | Qué mide |

## Vistas

| Vista | Qué devuelve | La usa |
|---|---|---|
| v_observaciones | Observaciones con comercio, anuncio y presentación (del Taller 1) | Consultas de revisión |
| v_ejecuciones | Una fila por ejecución: fecha, inicio, fin y comercios completos | Filtro de ejecución, indicador de la última ejecución |
| v_precios | Observaciones válidas (no excluidas, no descartadas, con precio) con los campos de la tabla de la app; `disponibilidad` en texto | Tabla, filtros, indicadores |
| v_ultimo_precio | `v_precios` de la ejecución más reciente | Resumen |
| v_comparables | Presentaciones comparables con `presentacion` y `precio_por_ml` (COP por mL) | Gráficos de evolución y precio por mL, canasta |
| v_cambios_precio | Cada observación con el precio del mismo anuncio en la ejecución anterior: `cambio_cop` y `cambio_pct` | Indicador de cambios, resumen de actualización |
| v_disponibilidad | Por anuncio y ejecución: `disponible`, `agotado`, `sin dato` o `no observado` | Disponibilidad |

## Índices

`idx_obs_ejecucion`, `idx_obs_precio`, `idx_obs_fecha`, `idx_obs_comparable`, `idx_anuncios_producto`, `idx_anuncios_subcat` e `idx_anuncios_marca`, sobre las columnas que usan los filtros.
