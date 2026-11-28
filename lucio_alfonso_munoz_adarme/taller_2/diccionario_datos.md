# Diccionario de datos

Base: `comparador_precios.sqlite`. Las fechas están en ISO 8601 con la hora de Colombia (`AAAA-MM-DDTHH:MM:SS-05:00`) y los precios en pesos colombianos (COP). Las unidades de contenido son `g` (gramos), `ml` (mililitros) y `und` (unidades).

## Tablas

### comercios
Una fila por comercio.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_comercio | INTEGER | Identificador | 1, 2, 3 |
| nombre | TEXT | Nombre del comercio | Exito, Farmatodo, Locatel |
| url_categoria | TEXT | Página de la categoría en el sitio | URL |

### ejecuciones
Una fila por comercio en cada ejecución del scraper.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_ejecucion | TEXT | Identificador de la ejecución (fecha y hora de inicio) | AAAAMMDDTHHMMSS |
| comercio | TEXT | Comercio | Exito, Farmatodo, Locatel |
| inicio, fin | TEXT | Fecha y hora de inicio y fin de la consulta al comercio | ISO 8601 |
| registros | INTEGER | Filas descargadas (presentaciones) | 0 o más |
| en_categoria | INTEGER | Filas que cumplen la delimitación de la categoría | 0 o más |
| total_sitio | INTEGER | Total de productos que reporta el sitio | NULL si no lo reporta |
| estado | TEXT | Resultado de la ejecución | completa, parcial, fallida |
| carpeta_raw | TEXT | Carpeta de las copias crudas | raw/comercio/fecha/id_ejecucion |
| insertadas | INTEGER | Observaciones insertadas | 0 o más |
| rechazadas | INTEGER | Observaciones que no pasaron la validación | 0 o más |
| comparables | INTEGER | Productos comparables observados con datos válidos | 0 a 11 |
| motivo | TEXT | Por qué la ejecución es parcial o fallida | texto o NULL |

### productos
Una fila por presentación común a los tres comercios (los productos comparables).

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_producto_comun | TEXT | Identificador de la presentación común | marca_nombre_sabor_contenido |
| nombre_comun | TEXT | Nombre para mostrar | texto |
| marca_std | TEXT | Marca estandarizada | texto |
| subcategoria_std | TEXT | Subcategoría | proteína, creatina, aminoácidos, preentreno, ganador de peso, gel, barra, bebida deportiva |
| nombre_std | TEXT | Nombre sin marca, sabor ni contenido | texto |
| variante | TEXT | Sabor | texto o NULL |
| contenido | REAL | Contenido total de la presentación | número, en la unidad |
| unidad | TEXT | Unidad del contenido | g, ml, und |
| unidades_empaque | INTEGER | Unidades dentro del empaque | 1 o más |
| regla | TEXT | Cómo se formó el grupo | EAN, manual |

### anuncios
Una fila por presentación publicada por un comercio. Guarda el texto original y los campos estandarizados.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_anuncio | INTEGER | Identificador | entero |
| comercio | TEXT | Comercio | Exito, Farmatodo, Locatel |
| id_producto_comercio | TEXT | Identificador del producto en el sitio | texto |
| sku | TEXT | Identificador de la presentación en el sitio | texto |
| ean | TEXT | Código de barras | texto o NULL |
| nombre | TEXT | Nombre como lo publica el sitio | texto |
| texto_original | TEXT | Nombre, nombre de la presentación y descripción del anuncio | texto |
| categoria_sitio | TEXT | Categoría que le da el sitio | texto |
| marca_sitio | TEXT | Marca que publica el sitio | texto o NULL |
| marca_std | TEXT | Marca estandarizada | texto o NULL |
| subcategoria_std | TEXT | Subcategoría (ver productos) | texto o NULL |
| nombre_std | TEXT | Nombre estandarizado | texto o NULL |
| variante | TEXT | Sabor | texto o NULL |
| contenido | REAL | Contenido total de la presentación | número o NULL |
| unidad | TEXT | Unidad del contenido | g, ml, und o NULL |
| unidades_empaque | INTEGER | Unidades dentro del empaque | 1 o más, o NULL |
| con_descripcion | INTEGER | El anuncio tiene descripción | 0, 1 |
| en_categoria | INTEGER | Cumple la delimitación de nutrición deportiva | 0, 1 |
| motivo_exclusion | TEXT | Por qué no cumple la delimitación | texto o NULL |
| url | TEXT | Enlace al anuncio | URL o NULL |
| id_producto_comun | TEXT | Presentación común a la que pertenece | id de productos o NULL |
| comparable | INTEGER | Pertenece a una presentación común | 0, 1 |

Restricción de unicidad: `(comercio, id_producto_comercio, sku)`.

### observaciones
Una fila por precio de un anuncio en una ejecución.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_observacion | INTEGER | Identificador | entero |
| id_anuncio | INTEGER | Anuncio observado | id de anuncios |
| id_ejecucion | TEXT | Ejecución | id de ejecuciones |
| precio | REAL | Precio de venta (COP) | mayor que 0; NULL solo en observaciones descartadas del Taller 1 |
| precio_antes | REAL | Precio antes del descuento (COP) | número o NULL |
| promocion | INTEGER | El precio es menor que el precio antes | 0, 1 |
| disponibilidad | TEXT | Disponibilidad según el sitio | disponible, agotado |
| vendedor | TEXT | Vendedor (en Éxito puede ser un tercero) | texto |
| fecha_consulta | TEXT | Fecha y hora de la consulta | ISO 8601 |
| descartada | INTEGER | La observación no cumple la validación | 0, 1 |
| motivo_descarte | TEXT | Motivo del descarte | texto o NULL |

Restricción de unicidad: `(id_anuncio, id_ejecucion)`, que impide insertar dos veces la misma observación. El tercer estado de disponibilidad, "no observado", no se guarda como fila: es un anuncio sin observación en la ejecución (ver `v_disponibilidad`).

### rechazos
Observaciones que no pasaron la validación y no se insertaron.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_rechazo | INTEGER | Identificador | entero |
| id_ejecucion, comercio | TEXT | Ejecución y comercio | ver ejecuciones |
| id_producto_comercio, sku, nombre | TEXT | Datos del anuncio rechazado | texto |
| precio | REAL | Precio recibido (COP) | número o NULL |
| url | TEXT | Enlace recibido | URL o NULL |
| fecha_consulta | TEXT | Fecha y hora de la consulta | ISO 8601 |
| motivo | TEXT | Regla que no cumple | precio ausente, precio no mayor que cero, URL ausente, URL no válida, comercio ausente, fecha y hora de consulta ausente, observación duplicada en la ejecución |

### correcciones
Cambios hechos a la base del Taller 1 y al estado de una ejecución.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_correccion | INTEGER | Identificador | entero |
| fecha | TEXT | Fecha de la corrección | ISO 8601 |
| tabla | TEXT | Tabla corregida | anuncios, observaciones, productos, ejecuciones |
| id_registro | INTEGER | id_anuncio, id_observacion, o rowid en productos y ejecuciones | entero |
| campo | TEXT | Columna corregida | texto |
| valor_anterior, valor_nuevo | TEXT | Valor antes y después | texto o NULL |
| motivo | TEXT | Razón de la corrección | texto |

## Índices

| Índice | Columnas | Uso |
|---|---|---|
| idx_observaciones_ejecucion | observaciones (id_ejecucion) | filtro por ejecución |
| idx_observaciones_anuncio | observaciones (id_anuncio) | historial de un anuncio |
| idx_observaciones_precio | observaciones (precio) | rango de precio |
| idx_anuncios_filtros | anuncios (comercio, en_categoria, subcategoria_std, marca_std) | filtros del panel lateral |
| idx_anuncios_comun | anuncios (comparable, id_producto_comun) | comparables y canasta |

## Vistas

| Vista | Una fila por | Columnas principales |
|---|---|---|
| v_observaciones | observación no descartada | datos del anuncio y de la observación, y `precio_unidad` = precio / contenido (COP por g, ml o und) |
| v_ultimo_precio | anuncio | su observación más reciente |
| v_cambios_precio | observación cuyo precio cambió frente a la anterior del mismo anuncio | precio, precio_anterior, id_ejecucion, id_ejecucion_anterior |
| v_comparables | precio de una presentación comparable en una ejecución | producto, comercio, precio, precio_unidad, disponibilidad |
| v_disponibilidad | comparable de un comercio en cada ejecución de ese comercio | disponibilidad: disponible, agotado o no observado |
| v_ejecuciones | ejecución | inicio, número de comercios completos, parciales y fallidos, insertadas y rechazadas |
