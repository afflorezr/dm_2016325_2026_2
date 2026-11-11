# Diccionario de datos

Moneda: COP. Fechas: ISO 8601 con UTC−5 (Colombia). Los NULL representan información ausente, no cero. No se crean observaciones para productos ausentes. Los precios corresponden al instante de extracción.

Relaciones: observaciones y cobertura → ejecuciones (ejecucion, comercio); ejecuciones → comercios; observaciones.producto_comun → productos; correcciones.observacion_id → observaciones. Índices: idx_comparacion, idx_historial, idx_filtros, además de claves y unicidades.

## comercios

Tres fuentes públicas del estudio.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | TEXT | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| nombre | TEXT | Nombre legible de comercio o presentación canónica. |
| dominio | TEXT | Host público consultado; sin protocolo. |

## productos

Ocho correspondencias canónicas del Taller 1.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | TEXT | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| nombre | TEXT | Nombre legible de comercio o presentación canónica. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| variante | TEXT | Variante comercial y formulación del producto comparable. |
| presentacion | TEXT | Presentación canónica verificada (cantidad por empaque). |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| unidades_empaque | INTEGER | Cantidad de piezas dentro del empaque; entero positivo. |
| grupo_formulacion | TEXT | Grupo de formulación que evita comparar jabones o desodorantes de variantes distintas. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| evidencia | TEXT | Justificación textual de la correspondencia entre los tres anuncios y la presentación canónica. |

## ejecuciones

Una fila por captura global y comercio. Clave compuesta (id, comercio). Completa exige cobertura y correspondencias; las capturas parciales históricas se conservan.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | TEXT | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| inicio | TEXT | Inicio de la captura por comercio, ISO 8601 con UTC−5. |
| fin | TEXT | Fin de la captura por comercio, ISO 8601 con UTC−5; NULL si falló antes de completarse. |
| estado | TEXT | Estado de ejecución/cobertura: completa, parcial o fallida, según el contexto. |
| registros | INTEGER | Número de filas recolectadas antes de validar o depurar categoría. |
| incluidos | INTEGER | Número de filas recolectadas dentro de la delimitación de categoría antes de validar precio. |

## cobertura

Una fila por sección, ejecución y comercio. Permite contrastar productId esperados y recuperados.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| categoria | TEXT | Ruta/ID de sección VTEX solicitada al comercio; no es la subcategoría analítica. |
| esperados | INTEGER | Total de productos publicado por la API para la sección; NULL si no se obtuvo. |
| obtenidos | INTEGER | Número de productId distintos recuperados para la sección; no equivale al número de SKU. |
| estado | TEXT | Estado de ejecución/cobertura: completa, parcial o fallida, según el contexto. |
| error | TEXT | Detalle de fallo de red, cobertura, esquema o correspondencia; NULL si no hay error registrado. |

## observaciones

Historial íntegro del Taller 1 más nuevas filas validadas. Unicidad (comercio, SKU, fecha_hora) y (ejecución, comercio, SKU).

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |

## categoria

Vista original del Taller 1: incluido=1; puede contener precios NULL históricos. Se conserva por compatibilidad.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |

## comparables

Vista original del Taller 1: corresponde a producto canónico, incluido, precio no nulo y disponible=1. Se conserva por compatibilidad.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |
| producto | TEXT | Nombre canónico de productos.nombre; NULL en catálogo no comparable. |
| presentacion | TEXT | Presentación canónica verificada (cantidad por empaque). |
| grupo_formulacion | TEXT | Grupo de formulación que evita comparar jabones o desodorantes de variantes distintas. |
| unidades_empaque | INTEGER | Cantidad de piezas dentro del empaque; entero positivo. |

## migraciones

Control idempotente de cambios del esquema.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| version | TEXT | Identificador de migración aplicada una sola vez; t2-1. |
| fecha | TEXT | Fecha y hora de migración, corrección, rechazo o reprocesamiento; ISO 8601 UTC−5. |

## correcciones

Auditoría de cambios en campos estandarizados de filas históricas; no elimina observaciones.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| fecha | TEXT | Fecha y hora de migración, corrección, rechazo o reprocesamiento; ISO 8601 UTC−5. |
| observacion_id | INTEGER | Referencia a observaciones.id afectada por una corrección. |
| campo | TEXT | Nombre del campo estandarizado corregido, actualmente descartada. |
| valor_anterior | TEXT | Representación textual del valor anterior a la corrección. |
| valor_nuevo | TEXT | Representación textual del valor corregido. |
| motivo | TEXT | Justificación de la corrección, con reglas de validación que fallaron. |

## rechazos

Filas nuevas inválidas registradas fuera de observaciones, deduplicadas por SHA-256.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| fecha | TEXT | Fecha y hora de migración, corrección, rechazo o reprocesamiento; ISO 8601 UTC−5. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| motivos | TEXT | Lista textual de causas de rechazo antes de insertar. |
| datos_originales | TEXT | JSON de la fila parseada rechazada, incluyendo ruta raw; mantiene NULL, no imputa precios. |
| huella | TEXT | SHA-256 de fila más motivos; evita duplicar el mismo rechazo en reprocesamiento. |

## actualizaciones

Bitácora por intento y comercio, incluso reprocesamientos offline y fallas.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| fecha | TEXT | Fecha y hora de migración, corrección, rechazo o reprocesamiento; ISO 8601 UTC−5. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| modo | TEXT | online: petición a sitios; offline: reprocesamiento de respuestas originales. |
| estado | TEXT | Estado de ejecución/cobertura: completa, parcial o fallida, según el contexto. |
| recolectados | INTEGER | Cantidad de filas parseadas antes de validación, por intento y comercio. |
| insertados | INTEGER | Cantidad de observaciones nuevas efectivamente insertadas; 0 al repetir una ejecución ya cargada. |
| rechazados | INTEGER | Cantidad de filas que no superaron las reglas en ese intento; los rechazos únicos están en rechazos. |
| error | TEXT | Detalle de fallo de red, cobertura, esquema o correspondencia; NULL si no hay error registrado. |

## v_catalogo

Vista usada en catálogo e indicadores: incluido=1, descartada=0, precio>0; enriquece con nombre de tienda, presentación y precio unitario.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |
| comercio_nombre | TEXT | Nombre legible del comercio asociado a comercio. |
| producto | TEXT | Nombre canónico de productos.nombre; NULL en catálogo no comparable. |
| presentacion | TEXT | Presentación canónica verificada (cantidad por empaque). |
| grupo_formulacion | TEXT | Grupo de formulación que evita comparar jabones o desodorantes de variantes distintas. |
| precio_unitario | Derivado numérico / NULL | Precio / contenido_total: COP/g, COP/mL o COP/unidad. NULL si contenido no confiable; comparar solo misma formulación. |

## v_comparables

Vista usada por ahorros y canasta: v_catalogo con comparable=1 y disponibilidad=disponible.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |
| comercio_nombre | TEXT | Nombre legible del comercio asociado a comercio. |
| producto | TEXT | Nombre canónico de productos.nombre; NULL en catálogo no comparable. |
| presentacion | TEXT | Presentación canónica verificada (cantidad por empaque). |
| grupo_formulacion | TEXT | Grupo de formulación que evita comparar jabones o desodorantes de variantes distintas. |
| precio_unitario | Derivado numérico / NULL | Precio / contenido_total: COP/g, COP/mL o COP/unidad. NULL si contenido no confiable; comparar solo misma formulación. |

## v_ultimo_precio

Vista usada en Calidad: última observación válida conocida por comercio/SKU; puede ser antigua y no significa presencia en la última captura.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |
| comercio_nombre | TEXT | Nombre legible del comercio asociado a comercio. |
| producto | TEXT | Nombre canónico de productos.nombre; NULL en catálogo no comparable. |
| presentacion | TEXT | Presentación canónica verificada (cantidad por empaque). |
| grupo_formulacion | TEXT | Grupo de formulación que evita comparar jabones o desodorantes de variantes distintas. |
| precio_unitario | Derivado numérico / NULL | Precio / contenido_total: COP/g, COP/mL o COP/unidad. NULL si contenido no confiable; comparar solo misma formulación. |
| posicion | Derivado numérico / NULL | Orden descendente de fecha e ID dentro de comercio y SKU; v_ultimo_precio conserva únicamente 1. |

## v_cambios_precio

Vista usada por indicador de cambios: LAG sobre comercio/SKU ordenado por fecha e ID, diferencias absolutas y porcentuales.

| Columna | Tipo SQLite | Significado, unidad y valores |
|---|---|---|
| id | INTEGER | Identificador; en observaciones/correcciones/rechazos/actualizaciones es entero autoincremental; en comercios/productos es clave de texto y en ejecuciones es el ID global de captura. |
| ejecucion | TEXT | Identificador global de captura YYYYMMDDTHHMMSS_aleatorio; enlaza ejecuciones.id junto con comercio. |
| comercio | TEXT | Clave del comercio: colsubsidio, cafam o larebaja; referencia a comercios.id. |
| sku | TEXT | Identificador de la variante/anuncio dentro de un comercio; texto. |
| producto_sitio | TEXT | productId del sitio que puede reunir uno o varios SKU. |
| ean | TEXT | Código de barras como texto, preserva ceros iniciales; NULL si no se publica en el anuncio. |
| producto_comun | TEXT | Clave canónica de una de las ocho presentaciones; NULL para otros productos de categoría. |
| nombre_original | TEXT | Nombre publicado por el comercio, sin reescritura. |
| nombre_limpio | TEXT | Nombre en minúsculas sin acentos ni HTML y con espacios normalizados; se usa en búsqueda. |
| marca | TEXT | Marca estandarizada; en observaciones puede ser NULL si el sitio no la informa. |
| subcategoria | TEXT | Jabones y geles de ducha; Desodorantes y antitranspirantes; Talcos; o NULL si excluido. |
| presentacion_original | TEXT | Campo de presentación tal como aparece en la respuesta del sitio; puede ser NULL o discrepar del empaque verificado. |
| descripcion_original | TEXT | Descripción original del anuncio; puede incluir HTML. |
| descripcion_adicional | TEXT | Información adicional de contenido publicada por el sitio; puede estar ausente. |
| texto_original | TEXT | JSON textual con nombre, nombre de SKU, descripción y ficha originales; no sustituye la copia raw. |
| precio | REAL | Precio de venta publicado en COP por empaque; positivo. NULL históricos se conservan descartados. |
| precio_lista | REAL | Precio de lista publicado, COP por empaque; NULL si no hay referencia positiva. |
| promocion | INTEGER | 1 si precio < precio_lista; 0 si no; NULL si no se puede determinar. No aplica descuentos condicionados. |
| disponible | INTEGER | Indicador original 1/0 del scraper legado; el 0 puede incluir falta de información, por eso se usa disponibilidad. |
| url | TEXT | URL pública del anuncio, http o https. |
| url_extraccion | TEXT | URL de la petición HTTP que produjo la respuesta raw. |
| fecha_hora | TEXT | Fecha y hora real de la respuesta archivada, ISO 8601 con UTC−5; no se actualiza al reprocesar offline. |
| contenido_total | REAL | Contenido de todo el empaque, positivo; g, mL o unidad según unidad. NULL cuando no puede determinarse. |
| unidad | TEXT | Unidad normalizada del contenido: g, mL o unidad para comparables. El legado de otros productos puede conservar mg o NULL. |
| comparable | INTEGER | 1 si SKU y EAN coinciden con una de las ocho presentaciones; 0 en otro caso. |
| incluido | INTEGER | 1 si pertenece a higiene corporal según reglas documentadas; 0 si está fuera de delimitación. |
| motivo_exclusion | TEXT | Razón textual de exclusión de categoría; NULL para productos incluidos. |
| incidencia | TEXT | Advertencia de correspondencia o presentación, conservada del scraper original; NULL cuando no aplica. |
| archivo_raw | TEXT | Ruta relativa desde taller_2 a la respuesta comprimida original .json.gz. |
| descartada | INTEGER | 1 para una observación histórica inválida; se conserva pero no alimenta las vistas analíticas. 0 para válida. |
| disponibilidad | TEXT | disponible (evidencia positiva), agotado (IsAvailable=false explícito), desconocida (sin evidencia suficiente). No observado se deriva entre ejecuciones, no es una fila inventada. |
| comercio_nombre | TEXT | Nombre legible del comercio asociado a comercio. |
| producto | TEXT | Nombre canónico de productos.nombre; NULL en catálogo no comparable. |
| presentacion | TEXT | Presentación canónica verificada (cantidad por empaque). |
| grupo_formulacion | TEXT | Grupo de formulación que evita comparar jabones o desodorantes de variantes distintas. |
| precio_unitario | Derivado numérico / NULL | Precio / contenido_total: COP/g, COP/mL o COP/unidad. NULL si contenido no confiable; comparar solo misma formulación. |
| precio_anterior | Derivado numérico / NULL | Precio COP de la observación válida anterior del mismo comercio/SKU; NULL si no hay anterior. |
| cambio_cop | Derivado numérico / NULL | precio − precio_anterior, COP; NULL si no hay dato anterior. |
| cambio_pct | Derivado numérico / NULL | 100 × (precio − precio_anterior)/precio_anterior, porcentaje; NULL sin anterior. |
