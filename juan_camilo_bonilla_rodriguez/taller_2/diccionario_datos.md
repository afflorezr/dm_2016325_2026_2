# Diccionario de datos

La base conserva el historial del Taller 1. Los precios están en COP y las fechas en hora de Colombia (UTC−5). NULL significa dato ausente. Los nombres de columnas de las vistas heredan el significado de sus tablas de origen.

Los kits con glucómetro, tiras y lancetas se cuentan como un kit (unidad), sin sumar componentes heterogéneos. Las tiras en tres cajas de 50 tienen contenido total de 150 unidades. No se mezclan unidades en un mismo ranking.

## anuncios

Oferta identificada por comercio y SKU.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `marca_original` | TEXT | Marca extraída del sitio antes de normalizar | Texto o NULL |
| `categoria_sitio` | TEXT | Categorías del catálogo del comercio | Texto original; puede contener varias secciones |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `ean` | TEXT | Código de barras extraído de la ficha | Texto o NULL |
| `ficha_original_json` | TEXT | Metadatos originales de la ficha técnica | JSON; incluye evidencias de disponibilidad y escala monetaria |
| `presentacion_original` | TEXT | Presentación publicada en la ficha del sitio | Texto o NULL |

## cohortes_comparables

Presentaciones seleccionadas en cada corrida.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |

## comercios

Fuentes activas e históricas.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `slug` | TEXT | Clave estable del comercio en el scraper | comercio1…comercio6; activos: comercio4, comercio5, comercio6 |
| `nombre` | TEXT | Nombre público del comercio | Texto |

## correcciones

Registro de modificaciones con valor anterior, nuevo y motivo.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `correccion_id` | INTEGER | Identificador del cambio auditado | Entero; clave primaria |
| `fecha` | TEXT | Momento de registrar la corrección | ISO 8601, hora de Colombia |
| `tabla` | TEXT | Tabla donde se encuentra el registro corregido | anuncios, productos, observaciones o ejecuciones |
| `registro_id` | INTEGER | Clave primaria del registro afectado | Entero |
| `campo` | TEXT | Columna corregida | Nombre de columna de la tabla afectada |
| `valor_anterior` | TEXT | Valor antes de la corrección | Texto serializado o NULL |
| `valor_nuevo` | TEXT | Valor después de la corrección | Texto serializado o NULL |
| `motivo` | TEXT | Razón de rechazo, exclusión o corrección | Texto obligatorio |

## descartes

Productos excluidos por no pertenecer a la categoría.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `descarte_id` | INTEGER | Identificador de exclusión por categoría | Entero; clave primaria |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `motivo` | TEXT | Razón de rechazo, exclusión o corrección | Texto obligatorio |

## ejecuciones

Una consulta por comercio; tres consultas comparten corrida_id.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `inicio` | TEXT | Inicio de la consulta del comercio | ISO 8601, Colombia UTC−5 |
| `n_registros` | INTEGER | Anuncios recuperados antes de delimitar la categoría | Conteo; puede incluir exclusiones |
| `n_reportado_sitio` | INTEGER | Total declarado por el sitio para las secciones consultadas | Conteo; NULL si el sitio no lo informa |
| `estado` | TEXT | Resultado de extracción y cobertura de las ocho presentaciones | completa, parcial, fallida |
| `notas` | TEXT | Cobertura por sección, incidencias o motivo del estado | Texto/JSON; no contiene precios inventados |

## familias_unidad

Equivalencias justificadas para comparar contenido.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `familia` | TEXT | Agrupación justificada para comparar tamaños equivalentes | Texto; no mezcla marcas ni kits heterogéneos |
| `justificacion` | TEXT | Motivo documentado de equivalencia de formulación | Texto |

## observaciones

Precios históricos. Unicidad por anuncio y ejecución, y por anuncio y fecha.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `obs_id` | INTEGER | Identificador de la observación de precio | Entero; clave primaria |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `raw_ref` | TEXT | Ruta a la respuesta original que contiene la observación | Ruta relativa dentro de raw/; archivo JSON comprimido gzip |
| `disponibilidad` | TEXT | Disponibilidad informada por el sitio | disponible, agotado, desconocida; no observado solo en vistas/comparaciones |
| `texto_original_captura` | TEXT | Título y descripción originales en esa captura | Texto inmutable por observación; respaldo en raw |
| `descartada` | INTEGER | Marca de observación excluida del análisis sin borrarla | 0 vigente; 1 descartada; todo cambio se audita en correcciones |

## productos

Identidades comunes revisadas; no contienen precios.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |

## rechazos

Filas que no superaron las reglas de validación.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `rechazo_id` | INTEGER | Identificador de fila rechazada | Entero; clave primaria |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `motivo` | TEXT | Razón de rechazo, exclusión o corrección | Texto obligatorio |
| `datos_json` | TEXT | Fila rechazada para revisar su origen y motivo | JSON; el precio inválido no se inserta en observaciones |

## v_cambios_precio

Precio anterior del mismo anuncio y diferencias. Usada para el resumen de cambios.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `contenido_total` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido multiplicado por número de componentes homogéneos | contenido × n_unidades; unidad indicada por unidad |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `precio_por_unidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio del empaque dividido por su contenido total | COP/mL, COP/g, COP/mg o COP/unidad; NULL si contenido no identificable |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `disponibilidad` | TEXT | Disponibilidad informada por el sitio | disponible, agotado, desconocida; no observado solo en vistas/comparaciones |
| `raw_ref` | TEXT | Ruta a la respuesta original que contiene la observación | Ruta relativa dentro de raw/; archivo JSON comprimido gzip |
| `descartada` | INTEGER | Marca de observación excluida del análisis sin borrarla | 0 vigente; 1 descartada; todo cambio se audita en correcciones |
| `texto_capturado` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Texto original conservado en la observación | Respalda las búsquedas históricas; usa el anuncio si no hay instantánea |
| `producto_nombre` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Nombre común para identificar una presentación | Nombre canónico o nombre del anuncio si no tiene correspondencia |
| `producto_marca` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Marca canónica de la presentación | Texto normalizado o NULL |
| `presentacion` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido total y unidad para lectura humana | Texto; Sin identificar cuando no hay cantidad fiable |
| `familia` | TEXT | Agrupación justificada para comparar tamaños equivalentes | Texto; no mezcla marcas ni kits heterogéneos |
| `precio_anterior` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio de la observación anterior del mismo anuncio | COP; NULL en la primera observación |
| `corrida_anterior` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Corrida de la observación anterior del mismo anuncio | Identificador o NULL |
| `cambio_cop` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Diferencia respecto al precio anterior | COP; positivo subió, negativo bajó, cero sin cambio |
| `cambio_pct` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Variación respecto al precio anterior | 100 × cambio_cop / precio_anterior; porcentaje o NULL |

## v_catalogo

Consulta principal: observaciones vigentes, disponibilidad y texto de cada captura. Usada por filtros y tabla.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `contenido_total` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido multiplicado por número de componentes homogéneos | contenido × n_unidades; unidad indicada por unidad |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `precio_por_unidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio del empaque dividido por su contenido total | COP/mL, COP/g, COP/mg o COP/unidad; NULL si contenido no identificable |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `disponibilidad` | TEXT | Disponibilidad informada por el sitio | disponible, agotado, desconocida; no observado solo en vistas/comparaciones |
| `raw_ref` | TEXT | Ruta a la respuesta original que contiene la observación | Ruta relativa dentro de raw/; archivo JSON comprimido gzip |
| `descartada` | INTEGER | Marca de observación excluida del análisis sin borrarla | 0 vigente; 1 descartada; todo cambio se audita en correcciones |
| `texto_capturado` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Texto original conservado en la observación | Respalda las búsquedas históricas; usa el anuncio si no hay instantánea |
| `producto_nombre` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Nombre común para identificar una presentación | Nombre canónico o nombre del anuncio si no tiene correspondencia |
| `producto_marca` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Marca canónica de la presentación | Texto normalizado o NULL |
| `presentacion` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido total y unidad para lectura humana | Texto; Sin identificar cuando no hay cantidad fiable |
| `familia` | TEXT | Agrupación justificada para comparar tamaños equivalentes | Texto; no mezcla marcas ni kits heterogéneos |

## v_comparables

Aplica la cohorte histórica. Usada por ahorro, precio unitario, evolución y canasta.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `contenido_total` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido multiplicado por número de componentes homogéneos | contenido × n_unidades; unidad indicada por unidad |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `precio_por_unidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio del empaque dividido por su contenido total | COP/mL, COP/g, COP/mg o COP/unidad; NULL si contenido no identificable |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `disponibilidad` | TEXT | Disponibilidad informada por el sitio | disponible, agotado, desconocida; no observado solo en vistas/comparaciones |
| `raw_ref` | TEXT | Ruta a la respuesta original que contiene la observación | Ruta relativa dentro de raw/; archivo JSON comprimido gzip |
| `descartada` | INTEGER | Marca de observación excluida del análisis sin borrarla | 0 vigente; 1 descartada; todo cambio se audita en correcciones |
| `texto_capturado` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Texto original conservado en la observación | Respalda las búsquedas históricas; usa el anuncio si no hay instantánea |
| `producto_nombre` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Nombre común para identificar una presentación | Nombre canónico o nombre del anuncio si no tiene correspondencia |
| `producto_marca` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Marca canónica de la presentación | Texto normalizado o NULL |
| `presentacion` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido total y unidad para lectura humana | Texto; Sin identificar cuando no hay cantidad fiable |
| `familia` | TEXT | Agrupación justificada para comparar tamaños equivalentes | Texto; no mezcla marcas ni kits heterogéneos |

## v_disponibilidad

Distingue disponible, agotado, desconocida y no observado por ejecución; no crea precios artificiales.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `disponibilidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Disponibilidad informada por el sitio | disponible, agotado, desconocida; no observado solo en vistas/comparaciones |
| `estado` | TEXT | Resultado de extracción y cobertura de las ocho presentaciones | completa, parcial, fallida |

## v_observaciones

Une observaciones, anuncios, comercios y ejecuciones.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `contenido_total` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido multiplicado por número de componentes homogéneos | contenido × n_unidades; unidad indicada por unidad |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `precio_por_unidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio del empaque dividido por su contenido total | COP/mL, COP/g, COP/mg o COP/unidad; NULL si contenido no identificable |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |

## v_promociones

Distingue descuentos verificables y promociones anunciadas.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `contenido_total` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido multiplicado por número de componentes homogéneos | contenido × n_unidades; unidad indicada por unidad |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `precio_por_unidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio del empaque dividido por su contenido total | COP/mL, COP/g, COP/mg o COP/unidad; NULL si contenido no identificable |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `descuento_verificable` | INTEGER | Indicador de descuento con evidencia en precios | 0 o 1 |
| `promocion_anunciada` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Promoción indicada en precio o título de la captura | 0 o 1; incluye ofertas de contenido |

## v_ultimo_precio

Último precio observado de cada anuncio. Usada para opciones de filtros; no declara stock actual.

| Columna | Tipo SQLite | Significado | Unidad o valores |
|---|---|---|---|
| `comercio` | TEXT | Nombre del comercio para presentación y filtros | Habib, Farmaprime y Farmaweb; conserva tres fuentes históricas |
| `comercio_id` | INTEGER | Identificador del comercio | Identificador entero; clave foránea cuando corresponde |
| `anuncio_id` | INTEGER | Identificador del producto en un comercio | Entero; estable entre fechas |
| `sku` | TEXT | Código interno del producto en el comercio | Texto; único junto con comercio_id |
| `titulo_original` | TEXT | Nombre del producto tal como lo devuelve el sitio | Texto original; última versión del anuncio |
| `texto_original` | TEXT | Título y descripción originales del anuncio | Texto con salto de línea; última versión; para historia usar texto_original_captura |
| `descripcion_original` | TEXT | Descripción o ficha disponible en el sitio | HTML o texto sin reemplazar por texto normalizado; NULL si ausente |
| `nombre_std` | TEXT | Nombre estandarizado del producto | Texto; distinto del anuncio original |
| `marca_std` | TEXT | Marca estandarizada | Texto normalizado o NULL |
| `subcategoria_std` | TEXT | Clase del producto dentro de la delimitación | termometro, tensiometro, glucometro, tiras_reactivas, lancetas, oximetro |
| `contenido` | REAL | Contenido de cada componente homogéneo del empaque | Número positivo o NULL; expresado en unidad |
| `unidad` | TEXT | Unidad normalizada de contenido | mL, g, mg o unidad; las comparaciones activas usan unidad |
| `n_unidades` | INTEGER | Número de componentes homogéneos del multipaquete | Entero positivo; 1 en empaque simple |
| `contenido_total` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido multiplicado por número de componentes homogéneos | contenido × n_unidades; unidad indicada por unidad |
| `concentracion` | TEXT | Concentración o formulación cuando aplica | Texto o NULL; no aplica a los ocho dispositivos y consumibles |
| `producto_id` | INTEGER | Identificador común de una presentación entre comercios | Entero; NULL para anuncios sin correspondencia |
| `comparable` | INTEGER | Anuncio con identidad común revisada | 0 o 1; la cohorte define las presentaciones seleccionadas en cada corrida |
| `precio` | REAL | Precio observado del empaque | COP; positivo para nuevas inserciones; NULL nunca se reemplaza por cero |
| `precio_antes` | REAL | Precio anterior o de lista informado por el sitio | COP; NULL si no está disponible |
| `promocion` | INTEGER | Precio promocional indicado por la fuente o descuento verificable | 0 o 1 |
| `precio_por_unidad` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Precio del empaque dividido por su contenido total | COP/mL, COP/g, COP/mg o COP/unidad; NULL si contenido no identificable |
| `url` | TEXT | URL de la oferta de donde procede el precio | URL HTTPS; no es una búsqueda manual |
| `fecha_hora` | TEXT | Momento real en que se obtuvo la respuesta | ISO 8601 con hora de Colombia y desfase −05:00 |
| `ejecucion_id` | INTEGER | Identificador de la consulta de un comercio | Entero; una fila por comercio y corrida |
| `corrida_id` | TEXT | Identificador común de la recolección | Texto con fecha y hora; agrupa los tres comercios |
| `disponibilidad` | TEXT | Disponibilidad informada por el sitio | disponible, agotado, desconocida; no observado solo en vistas/comparaciones |
| `raw_ref` | TEXT | Ruta a la respuesta original que contiene la observación | Ruta relativa dentro de raw/; archivo JSON comprimido gzip |
| `descartada` | INTEGER | Marca de observación excluida del análisis sin borrarla | 0 vigente; 1 descartada; todo cambio se audita en correcciones |
| `texto_capturado` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Texto original conservado en la observación | Respalda las búsquedas históricas; usa el anuncio si no hay instantánea |
| `producto_nombre` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Nombre común para identificar una presentación | Nombre canónico o nombre del anuncio si no tiene correspondencia |
| `producto_marca` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Marca canónica de la presentación | Texto normalizado o NULL |
| `presentacion` | Derivado (REAL si es cálculo numérico; TEXT si es etiqueta) | Contenido total y unidad para lectura humana | Texto; Sin identificar cuando no hay cantidad fiable |
| `familia` | TEXT | Agrupación justificada para comparar tamaños equivalentes | Texto; no mezcla marcas ni kits heterogéneos |

