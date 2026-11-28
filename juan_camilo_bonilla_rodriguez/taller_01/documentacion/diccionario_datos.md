# Diccionario de datos

Motor SQLite. Importes en pesos colombianos (COP), nunca centavos. Fechas ISO 8601 con hora de Colombia. NULL significa ausente; un cero no reemplaza ausencias. Tipos declarados según PRAGMA table_info; en vistas derivadas un tipo vacío se documenta como derivado.

Relaciones: anuncios → comercios y productos; observaciones → anuncios y ejecuciones; ejecuciones → comercios. Unicidad: comercio+sku; corrida+comercio; anuncio+fecha; anuncio+ejecución.

## anuncios (table)

Todos los productos incluidos en la categoría, con atributos originales y estandarizados.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| anuncio_id | INTEGER; PK | Clave interna del anuncio de un comercio. |
| comercio_id | INTEGER; NOT NULL | Clave del comercio; referencia a comercios. |
| sku | TEXT; NOT NULL | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| descripcion_original | TEXT | Descripción literal de origen, puede contener HTML o ser vacía; NULL si ausente. |
| marca_original | TEXT | Marca literal proporcionada por el comercio; puede ser proveedor en lugar de marca comercial. |
| categoria_sitio | TEXT | Categorías literales del catálogo separadas por |. |
| texto_original | TEXT | Título y descripción originales unidos por salto de línea; los campos componentes también se conservan. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |
| producto_id | INTEGER | Identidad común de una presentación; NULL para anuncios no emparejados. |
| comparable | INTEGER; NOT NULL | 1 si se seleccionó como comparable en alguna captura; la cohorte por corrida define el conjunto vigente, 0 en el resto. |
| ean | TEXT | Código publicado por el comercio; se conserva como texto, incluso cuando no tiene forma de GTIN válido. |
| ficha_original_json | TEXT | Objeto JSON con nombres y valores originales de las especificaciones. No sustituye la descripción. |
| presentacion_original | TEXT | Texto de presentación estructurada cuando existe; NULL en los sitios que no la exponen así. |

## cohortes_comparables (table)

Identidades seleccionadas en cada corrida; preserva cohortes históricas al cambiar de comercios.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| corrida_id | TEXT; PK; NOT NULL | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |
| producto_id | INTEGER; PK; NOT NULL | Identidad común de una presentación; NULL para anuncios no emparejados. |

## comercios (table)

Tres comercios seleccionados.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| comercio_id | INTEGER; PK | Clave del comercio; referencia a comercios. |
| slug | TEXT; NOT NULL | Identificador estable del comercio: comercio1–3 históricos; comercio4–6 actuales. |
| nombre | TEXT; NOT NULL | Nombre visible de cada comercio, incluidos los retirados del análisis actual. |

## correcciones (table)

Historial de cambios a atributos estandarizados, identidades o estado de ejecución.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| correccion_id | INTEGER; PK | Clave del evento de auditoría. |
| fecha | TEXT; NOT NULL | Fecha y hora del evento en Colombia, ISO 8601. |
| tabla | TEXT; NOT NULL | Tabla afectada por la revisión. |
| registro_id | INTEGER; NOT NULL | Identificador del registro en la tabla afectada. |
| campo | TEXT; NOT NULL | Nombre del atributo revisado. |
| valor_anterior | TEXT | Representación textual del valor antes de corregir; puede ser NULL. |
| valor_nuevo | TEXT | Representación textual del valor corregido; puede ser NULL. |
| motivo | TEXT; NOT NULL | Explicación del descarte, rechazo o corrección; obligatoria. |

## descartes (table)

Exclusiones de categoría; los descartes de una clasificación preliminar se conservan como auditoría y pueden coexistir con una reclasificación posterior.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| descarte_id | INTEGER; PK | Clave del descarte de categoría. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| comercio_id | INTEGER | Clave del comercio; referencia a comercios. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| motivo | TEXT; NOT NULL | Explicación del descarte, rechazo o corrección; obligatoria. |

## ejecuciones (table)

Una fila por corrida y comercio. Conserva también corridas parciales y fallidas.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| ejecucion_id | INTEGER; PK | Clave de una recolección de un comercio. |
| corrida_id | TEXT; NOT NULL | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |
| comercio_id | INTEGER; NOT NULL | Clave del comercio; referencia a comercios. |
| inicio | TEXT; NOT NULL | Inicio registrado en ISO 8601 con zona -05:00. |
| n_registros | INTEGER | Cantidad única extraída de secciones antes de excluir productos o rechazar precios. |
| n_reportado_sitio | INTEGER | Suma de totales de las secciones consultadas; puede incluir productos ajenos o duplicados. |
| estado | TEXT; NOT NULL | completa, parcial o fallida; describe cada comercio, no toda la campaña. |
| notas | TEXT | Cobertura por URL y explicación de fallas o alcance. |

## familias_unidad (table)

Agrupaciones explícitas para comparar tamaños del mismo producto.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| producto_id | INTEGER; PK | Identidad común de una presentación; NULL para anuncios no emparejados. |
| familia | TEXT; NOT NULL | Grupo de mismo producto y formulación que permite comparar tamaños; nunca agrupa marcas incompatibles. |
| justificacion | TEXT; NOT NULL | Evidencia y regla de la equivalencia de contenido. |

## observaciones (table)

Historial acumulativo de precios validados y evidencia cruda.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| obs_id | INTEGER; PK | Clave interna de la observación. |
| anuncio_id | INTEGER; NOT NULL | Clave interna del anuncio de un comercio. |
| ejecucion_id | INTEGER; NOT NULL | Clave de una recolección de un comercio. |
| precio | REAL | Precio actual extraído, en COP; se inserta solo si es numérico y positivo. |
| precio_antes | REAL | Precio de lista anterior al descuento, en COP; NULL cuando no se publica. |
| promocion | INTEGER; NOT NULL | 1 cuando precio_antes > precio; 0 cuando no se constata ese descuento. Regalos o campañas de nombre quedan en el original. |
| fecha_hora | TEXT; NOT NULL | Momento de la captura original ISO 8601 en Colombia (-05:00); nunca la fecha del reprocesamiento. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| raw_ref | TEXT | Ruta relativa al gzip de la respuesta original que sustenta la observación. |
| disponibilidad | TEXT; NOT NULL | disponible, agotado o desconocida según la respuesta. No observado se calcula por ausencia entre corridas, no equivale a agotado. |
| texto_original_captura | TEXT | Copia del texto original junto a la observación; preserva el texto histórico aunque el anuncio cambie. |

## productos (table)

Identidades comunes históricas y actuales; ocho se seleccionan en la corrida vigente.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| producto_id | INTEGER; PK | Identidad común de una presentación; NULL para anuncios no emparejados. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |

## rechazos (table)

Observaciones que no superaron la validación; no se insertaron en observaciones.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| rechazo_id | INTEGER; PK | Clave del rechazo de una observación. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| motivo | TEXT; NOT NULL | Explicación del descarte, rechazo o corrección; obligatoria. |
| datos_json | TEXT; NOT NULL | Registro completo rechazado como JSON; precios ausentes siguen siendo null. |

## v_cambios_precio (view)

LAG del mismo anuncio para calcular variación histórica. Las dos corridas seleccionadas arbitrariamente se comparan con consumidor.cambios_precio.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| comercio | TEXT | Nombre visible del comercio. |
| comercio_id | INTEGER | Clave del comercio; referencia a comercios. |
| anuncio_id | INTEGER | Clave interna del anuncio de un comercio. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| texto_original | TEXT | Título y descripción originales unidos por salto de línea; los campos componentes también se conservan. |
| descripcion_original | TEXT | Descripción literal de origen, puede contener HTML o ser vacía; NULL si ausente. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| contenido_total | derivado | contenido × n_unidades; cantidad total en unidad base. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |
| producto_id | INTEGER | Identidad común de una presentación; NULL para anuncios no emparejados. |
| comparable | INTEGER | 1 si se seleccionó como comparable en alguna captura; la cohorte por corrida define el conjunto vigente, 0 en el resto. |
| precio | REAL | Precio actual extraído, en COP; se inserta solo si es numérico y positivo. |
| precio_antes | REAL | Precio de lista anterior al descuento, en COP; NULL cuando no se publica. |
| promocion | INTEGER | 1 cuando precio_antes > precio; 0 cuando no se constata ese descuento. Regalos o campañas de nombre quedan en el original. |
| precio_por_unidad | derivado | precio / contenido_total, COP por unidad; NULL si no hay contenido válido. Comparar solo la misma familia y unidad. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| fecha_hora | TEXT | Momento de la captura original ISO 8601 en Colombia (-05:00); nunca la fecha del reprocesamiento. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| corrida_id | TEXT | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |
| precio_anterior | derivado | Precio observado inmediatamente antes para el mismo anuncio, COP; NULL en la primera captura. |
| cambio_cop | derivado | Precio actual menos precio observado antes, COP. |
| cambio_pct | derivado | 100 × cambio_cop / precio_anterior; NULL si no existe referencia positiva. |

## v_comparables (view)

Filtra comparable=1 y añade nombres canónicos. No elimina precios NULL por su cuenta.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| comercio | TEXT | Nombre visible del comercio. |
| comercio_id | INTEGER | Clave del comercio; referencia a comercios. |
| anuncio_id | INTEGER | Clave interna del anuncio de un comercio. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| texto_original | TEXT | Título y descripción originales unidos por salto de línea; los campos componentes también se conservan. |
| descripcion_original | TEXT | Descripción literal de origen, puede contener HTML o ser vacía; NULL si ausente. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| contenido_total | derivado | contenido × n_unidades; cantidad total en unidad base. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |
| producto_id | INTEGER | Identidad común de una presentación; NULL para anuncios no emparejados. |
| comparable | INTEGER | 1 si se seleccionó como comparable en alguna captura; la cohorte por corrida define el conjunto vigente, 0 en el resto. |
| precio | REAL | Precio actual extraído, en COP; se inserta solo si es numérico y positivo. |
| precio_antes | REAL | Precio de lista anterior al descuento, en COP; NULL cuando no se publica. |
| promocion | INTEGER | 1 cuando precio_antes > precio; 0 cuando no se constata ese descuento. Regalos o campañas de nombre quedan en el original. |
| precio_por_unidad | derivado | precio / contenido_total, COP por unidad; NULL si no hay contenido válido. Comparar solo la misma familia y unidad. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| fecha_hora | TEXT | Momento de la captura original ISO 8601 en Colombia (-05:00); nunca la fecha del reprocesamiento. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| corrida_id | TEXT | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |
| producto_nombre | TEXT | Rótulo canónico de la presentación comparable, tomado de productos. |
| producto_marca | TEXT | Marca canónica tomada de productos. |

## v_observaciones (view)

Une comercios, anuncios, observaciones y ejecuciones; calcula contenido y precio unitario.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| comercio | TEXT | Nombre visible del comercio. |
| comercio_id | INTEGER | Clave del comercio; referencia a comercios. |
| anuncio_id | INTEGER | Clave interna del anuncio de un comercio. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| texto_original | TEXT | Título y descripción originales unidos por salto de línea; los campos componentes también se conservan. |
| descripcion_original | TEXT | Descripción literal de origen, puede contener HTML o ser vacía; NULL si ausente. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| contenido_total | derivado | contenido × n_unidades; cantidad total en unidad base. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |
| producto_id | INTEGER | Identidad común de una presentación; NULL para anuncios no emparejados. |
| comparable | INTEGER | 1 si se seleccionó como comparable en alguna captura; la cohorte por corrida define el conjunto vigente, 0 en el resto. |
| precio | REAL | Precio actual extraído, en COP; se inserta solo si es numérico y positivo. |
| precio_antes | REAL | Precio de lista anterior al descuento, en COP; NULL cuando no se publica. |
| promocion | INTEGER | 1 cuando precio_antes > precio; 0 cuando no se constata ese descuento. Regalos o campañas de nombre quedan en el original. |
| precio_por_unidad | derivado | precio / contenido_total, COP por unidad; NULL si no hay contenido válido. Comparar solo la misma familia y unidad. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| fecha_hora | TEXT | Momento de la captura original ISO 8601 en Colombia (-05:00); nunca la fecha del reprocesamiento. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| corrida_id | TEXT | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |

## v_promociones (view)

Conserva observaciones y distingue descuento numérico de promoción anunciada; usa el título histórico de cada observación.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| comercio | TEXT | Nombre visible del comercio. |
| comercio_id | INTEGER | Clave del comercio; referencia a comercios. |
| anuncio_id | INTEGER | Clave interna del anuncio de un comercio. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| texto_original | TEXT | Título y descripción originales unidos por salto de línea; los campos componentes también se conservan. |
| descripcion_original | TEXT | Descripción literal de origen, puede contener HTML o ser vacía; NULL si ausente. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| contenido_total | derivado | contenido × n_unidades; cantidad total en unidad base. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |
| producto_id | INTEGER | Identidad común de una presentación; NULL para anuncios no emparejados. |
| comparable | INTEGER | 1 si se seleccionó como comparable en alguna captura; la cohorte por corrida define el conjunto vigente, 0 en el resto. |
| precio | REAL | Precio actual extraído, en COP; se inserta solo si es numérico y positivo. |
| precio_antes | REAL | Precio de lista anterior al descuento, en COP; NULL cuando no se publica. |
| promocion | INTEGER | 1 cuando precio_antes > precio; 0 cuando no se constata ese descuento. Regalos o campañas de nombre quedan en el original. |
| precio_por_unidad | derivado | precio / contenido_total, COP por unidad; NULL si no hay contenido válido. Comparar solo la misma familia y unidad. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| fecha_hora | TEXT | Momento de la captura original ISO 8601 en Colombia (-05:00); nunca la fecha del reprocesamiento. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| corrida_id | TEXT | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |
| descuento_verificable | INTEGER | 1 si precio de lista es mayor que precio actual; conserva el indicador promocion de la observación. |
| promocion_anunciada | derivado | 1 si hay descuento verificable o el título original de esa captura contiene oferta, gratis, pague o lleve; 0 sin esa evidencia. No atribuye porcentaje a regalos. |

## v_ultimo_precio (view)

Última observación por anuncio. Puede pertenecer a una corrida vieja si no se volvió a observar: comprobar fecha antes de usarla en una canasta.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| comercio | TEXT | Nombre visible del comercio. |
| comercio_id | INTEGER | Clave del comercio; referencia a comercios. |
| anuncio_id | INTEGER | Clave interna del anuncio de un comercio. |
| sku | TEXT | Identificador productId de VTEX como texto; no es necesariamente el código EAN ni el itemId. |
| titulo_original | TEXT | productName literal publicado por el comercio, sin limpieza. |
| texto_original | TEXT | Título y descripción originales unidos por salto de línea; los campos componentes también se conservan. |
| descripcion_original | TEXT | Descripción literal de origen, puede contener HTML o ser vacía; NULL si ausente. |
| nombre_std | TEXT | Nombre estandarizado; en productos incluye un rótulo legible de la presentación. |
| marca_std | TEXT | Marca comercial normalizada; NULL si no identificada. |
| subcategoria_std | TEXT | termometro, tensiometro, glucometro, tiras_reactivas, lancetas u oximetro. |
| contenido | REAL | Cantidad por empaque unitario; para kit heterogéneo identificado equivale a 1 kit. |
| unidad | TEXT | Unidad base: mL, g, mg o unidad; en esta captura se usa unidad. Interpretar unidad según presentación (tira, lanceta, dispositivo o kit). |
| n_unidades | INTEGER | Número de empaques homogéneos; contenido total = contenido × n_unidades. |
| contenido_total | derivado | contenido × n_unidades; cantidad total en unidad base. |
| concentracion | TEXT | Concentración cuando aplique; NULL en dispositivos sin concentración. |
| producto_id | INTEGER | Identidad común de una presentación; NULL para anuncios no emparejados. |
| comparable | INTEGER | 1 si se seleccionó como comparable en alguna captura; la cohorte por corrida define el conjunto vigente, 0 en el resto. |
| precio | REAL | Precio actual extraído, en COP; se inserta solo si es numérico y positivo. |
| precio_antes | REAL | Precio de lista anterior al descuento, en COP; NULL cuando no se publica. |
| promocion | INTEGER | 1 cuando precio_antes > precio; 0 cuando no se constata ese descuento. Regalos o campañas de nombre quedan en el original. |
| precio_por_unidad | derivado | precio / contenido_total, COP por unidad; NULL si no hay contenido válido. Comparar solo la misma familia y unidad. |
| url | TEXT | URL pública del producto correspondiente al precio. |
| fecha_hora | TEXT | Momento de la captura original ISO 8601 en Colombia (-05:00); nunca la fecha del reprocesamiento. |
| ejecucion_id | INTEGER | Clave de una recolección de un comercio. |
| corrida_id | TEXT | Identificador común de la campaña en los tres comercios; texto fecha/hora con microsegundos. |

## Índices y parámetros

Índices en observaciones por ejecución/anuncio y fecha; anuncios por comercio/subcategoría/marca/comparable; unicidad adicional por anuncio/ejecución. Las consultas parametrizan corrida y selección de productos; nunca interpolan valores del consumidor.

Los precios, URL, texto y fecha históricos se verifican en raw_ref. La ficha del anuncio puede actualizarse; la ficha exacta de cada fecha siempre está en la copia cruda correspondiente.
