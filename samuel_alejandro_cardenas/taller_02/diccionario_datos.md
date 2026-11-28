# Diccionario de datos — Taller 2 de Minería de Datos

**Proyecto:** comparador de precios de salud sexual no farmacológica.  
**Comercios:** Cafam, Locatel y Cruz Verde.  
**Motor:** SQLite. **Moneda:** pesos colombianos (COP).  
**Fuente:** scraping ejecutado en los sitios de los comercios; cada observación debe conservar un origen `raw/` verificable.

## Reglas de interpretación

- La clave del anuncio es el par `(comercio, sku)`. La observación histórica es única por `(id_ejecucion, comercio, sku)`.
- `id_comun` une presentaciones equivalentes entre comercios, sin perder la identidad del anuncio original.
- `precio` es el valor capturado en COP y debe ser estrictamente positivo. Una ausencia se representa mediante `NULL`, nunca cero.
- `disponibilidad = NULL` significa **no informado**, no implica agotamiento. `agotado` requiere evidencia del sitio. La condición `no_observado` se registra separadamente cuando una ejecución completa permite establecer la ausencia del anuncio.
- `contenido_total` se expresa únicamente en `g`, `mL` o `unidad`, indicada en `unidad_normalizada`; el precio unitario nunca debe compararse entre unidades incompatibles.
- `cobertura.estado = ruta_recorrida` indica recorrido de páginas, pero **no demuestra** cobertura total certificada de la categoría.
- Las marcas de tiempo son textos ISO 8601 con zona horaria cuando están disponibles. No deben sustituirse las fechas históricas por la de procesamiento.
- La tabla `productos` almacena los metadatos por anuncio; `observaciones` conserva todas las capturas y permite analizar cambios en el tiempo.

## Tabla: `cobertura`

Estado del recorrido de páginas o secciones para cada comercio y ejecución.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `seccion` | `TEXT` | Nombre de sección, categoría o segmento del recorrido. |
| `esperados` | `INTEGER` | Total reportado o esperado para el recorrido; puede provenir de la fuente o del lote recuperado. |
| `capturados` | `INTEGER` | Número de anuncios clasificados y conservados en la sección. |
| `paginas` | `INTEGER` | Número de páginas consultadas de la sección. |
| `estado` | `TEXT` | Estado de captura o recorrido; su dominio depende de la tabla. **Dominio:** Según tabla: historica_parcial, ruta_recorrida, pendiente_verificar_cobertura, parcial o fallida. |
| `detalle` | `TEXT` | Detalle narrativo del estado, incluidos errores o advertencias. |

## Tabla: `correcciones`

Auditoría inmutable de cambios justificados sobre datos estandarizados.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id_correccion` | `INTEGER` | Clave interna del registro de corrección. |
| `fecha_hora` | `TEXT` | Momento en que se documentó la corrección. |
| `tabla_afectada` | `TEXT` | Tabla sobre la cual se efectuó la corrección. |
| `registro_id` | `TEXT` | Identificador de la fila modificada. |
| `campo` | `TEXT` | Campo específico cuya representación se corrigió. |
| `valor_anterior` | `TEXT` | Valor almacenado antes del ajuste documentado. |
| `valor_nuevo` | `TEXT` | Valor almacenado después del ajuste documentado. |
| `motivo` | `TEXT` | Motivo verificable de una corrección o rechazo. |

## Tabla: `ejecuciones`

Bitácora de intentos de captura por comercio y ejecución.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `inicio` | `TEXT` | Fecha y hora de inicio de consulta del comercio. |
| `registros` | `INTEGER` | Número de observaciones insertadas por la ejecución en este comercio. |
| `estado` | `TEXT` | Estado de captura o recorrido; su dominio depende de la tabla. **Dominio:** Según tabla: historica_parcial, ruta_recorrida, pendiente_verificar_cobertura, parcial o fallida. |
| `detalle` | `TEXT` | Detalle narrativo del estado, incluidos errores o advertencias. |

## Tabla: `observaciones`

Historial verificable de precios capturados; una fila por anuncio, comercio y ejecución.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id` | `INTEGER` | Identificador interno de observación. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `sku` | `TEXT` | SKU del comercio. |
| `producto_original` | `TEXT` | Nombre original del anuncio. |
| `descripcion_original` | `TEXT` | Descripción original del anuncio. |
| `marca` | `TEXT` | Marca. |
| `subcategoria` | `TEXT` | Subcategoría. |
| `precio` | `REAL` | Precio observado en COP (> 0), o NULL si no se informó. |
| `precio_anterior` | `REAL` | Precio anterior mostrado por el sitio, si existe, en COP. |
| `promocion` | `INTEGER` | Indicador de oferta/promoción detectado en la fuente. **Dominio:** 0 = no; 1 = sí; NULL = no informado. |
| `url` | `TEXT` | Enlace original del producto. |
| `fecha_consulta` | `TEXT` | Momento de la consulta. |
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `cantidad` | `REAL` | Contenido numérico extraído del nombre del producto, sin normalizar. |
| `unidad` | `TEXT` | Unidad cruda detectada, por ejemplo g, mg, mL o unidad. |
| `id_comun` | `TEXT` | Identificador de presentación comparable; NULL para otros productos. |
| `comparable` | `INTEGER` | Comparable: 0 = no; 1 = sí. |
| `precio_club` | `REAL` | Precio especial condicionado a membresía, cuando la página lo informa (COP). |
| `seccion_fuente` | `TEXT` | Categoría o sección de origen en el comercio. |
| `origen_raw` | `TEXT` | Ruta de la respuesta original en `raw/`. |
| `contenido_total` | `REAL` | Contenido normalizado (> 0) o NULL. |
| `unidad_normalizada` | `TEXT` | Unidad normalizada: g, mL, unidad o NULL. |
| `disponibilidad` | `TEXT` | Estado informado: disponible, agotado o NULL. |

## Tabla: `observaciones_rechazadas`

Datos descartados por validación previa a INSERT, con su motivo.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id_rechazo` | `INTEGER` | Clave interna del rechazo. |
| `fecha_rechazo` | `TEXT` | Fecha y hora de rechazo del dato en la validación. |
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `sku` | `TEXT` | SKU del comercio. |
| `precio_texto` | `TEXT` | Representación textual del precio rechazado. |
| `url` | `TEXT` | Enlace original del producto. |
| `origen_raw` | `TEXT` | Ruta de la respuesta original en `raw/`. |
| `motivo` | `TEXT` | Motivo verificable de una corrección o rechazo. |
| `registro_original` | `TEXT` | Registro rechazado serializado a JSON para su auditoría. |

## Tabla: `productos`

Catálogo normalizado de anuncios sin repetir precios históricos.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `sku` | `TEXT` | SKU del comercio. |
| `nombre` | `TEXT` | Nombre del producto utilizado en el catálogo. |
| `marca` | `TEXT` | Marca. |
| `subcategoria` | `TEXT` | Subcategoría. |
| `url` | `TEXT` | Enlace original del producto. |
| `id_comun` | `TEXT` | Identificador de presentación comparable; NULL para otros productos. |
| `comparable` | `INTEGER` | Comparable: 0 = no; 1 = sí. |
| `contenido_total` | `REAL` | Contenido normalizado (> 0) o NULL. |
| `unidad_normalizada` | `TEXT` | Unidad normalizada: g, mL, unidad o NULL. |
| `ultima_fecha_consulta` | `TEXT` | Campo auxiliar derivado de datos registrados. |

## Tabla: `validaciones_comparables`

Revisión documental de las ocho equivalencias de productos.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `id_comun` | `TEXT` | Identificador de presentación comparable; NULL para otros productos. |
| `metodo` | `TEXT` | Técnica usada para validar una equivalencia. |
| `justificacion` | `TEXT` | Razonamiento y evidencia de la equivalencia. |
| `fecha_revision` | `TEXT` | Fecha en que se validó la equivalencia. |

## Vista: `v_ultimo_precio`

Una observación más reciente por anuncio `(comercio, sku)` mediante ROW_NUMBER.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id` | `INTEGER` | Identificador interno de observación. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `sku` | `TEXT` | SKU del comercio. |
| `producto_original` | `TEXT` | Nombre original del anuncio. |
| `descripcion_original` | `TEXT` | Descripción original del anuncio. |
| `marca` | `TEXT` | Marca. |
| `subcategoria` | `TEXT` | Subcategoría. |
| `precio` | `REAL` | Precio observado en COP (> 0), o NULL si no se informó. |
| `precio_anterior` | `REAL` | Precio anterior mostrado por el sitio, si existe, en COP. |
| `promocion` | `INTEGER` | Indicador de oferta/promoción detectado en la fuente. **Dominio:** 0 = no; 1 = sí; NULL = no informado. |
| `url` | `TEXT` | Enlace original del producto. |
| `fecha_consulta` | `TEXT` | Momento de la consulta. |
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `cantidad` | `REAL` | Contenido numérico extraído del nombre del producto, sin normalizar. |
| `unidad` | `TEXT` | Unidad cruda detectada, por ejemplo g, mg, mL o unidad. |
| `id_comun` | `TEXT` | Identificador de presentación comparable; NULL para otros productos. |
| `comparable` | `INTEGER` | Comparable: 0 = no; 1 = sí. |
| `precio_club` | `REAL` | Precio especial condicionado a membresía, cuando la página lo informa (COP). |
| `seccion_fuente` | `TEXT` | Categoría o sección de origen en el comercio. |
| `origen_raw` | `TEXT` | Ruta de la respuesta original en `raw/`. |
| `contenido_total` | `REAL` | Contenido normalizado (> 0) o NULL. |
| `unidad_normalizada` | `TEXT` | Unidad normalizada: g, mL, unidad o NULL. |
| `disponibilidad` | `TEXT` | Estado informado: disponible, agotado o NULL. |

## Vista: `v_cambios_precio`

Variaciones absolutas y porcentuales contra la observación anterior del mismo anuncio, mediante LAG.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id` | `INTEGER` | Identificador interno de observación. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `sku` | `TEXT` | SKU del comercio. |
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `fecha_consulta` | `TEXT` | Momento de la consulta. |
| `precio` | `REAL` | Precio observado en COP (> 0), o NULL si no se informó. |
| `precio_previo` | `derivado` | Precio capturado inmediatamente antes para el mismo comercio y SKU (COP). |
| `cambio_cop` | `derivado` | Variación `precio - precio_previo` en COP. |
| `cambio_porcentaje` | `derivado` | Variación porcentual respecto al precio previo. |

## Vista: `v_comparables`

Solo productos con `comparable = 1` e `id_comun`; calcula precio por unidad cuando existe contenido verificable.

| Columna | Tipo SQLite | Descripción, unidad y dominio |
|---|---|---|
| `id` | `INTEGER` | Identificador interno de observación. |
| `id_ejecucion` | `TEXT` | Identificador de la ejecución. |
| `fecha_consulta` | `TEXT` | Momento de la consulta. |
| `comercio` | `TEXT` | Comercio: Cafam, Locatel o Cruz Verde. |
| `sku` | `TEXT` | SKU del comercio. |
| `id_comun` | `TEXT` | Identificador de presentación comparable; NULL para otros productos. |
| `producto_original` | `TEXT` | Nombre original del anuncio. |
| `marca` | `TEXT` | Marca. |
| `subcategoria` | `TEXT` | Subcategoría. |
| `precio` | `REAL` | Precio observado en COP (> 0), o NULL si no se informó. |
| `promocion` | `INTEGER` | Indicador de oferta/promoción detectado en la fuente. **Dominio:** 0 = no; 1 = sí; NULL = no informado. |
| `url` | `TEXT` | Enlace original del producto. |
| `disponibilidad` | `TEXT` | Estado informado: disponible, agotado o NULL. |
| `contenido_calculable` | `derivado` | Contenido elegido para calcular un precio unitario verificable. |
| `unidad_calculable` | `derivado` | Unidad compatible para calcular el precio unitario. |
| `precio_unitario` | `derivado` | Precio capturado dividido entre contenido calculable (COP por g, mL o unidad). **Dominio:** COP por unidad_calculable; NULL si no verificable. |

## Integridad y claves

- `observaciones`: restricción `UNIQUE(id_ejecucion, comercio, sku)` para impedir duplicaciones en una captura.
- `productos`: clave primaria compuesta `(comercio, sku)`.
- `ejecuciones`: clave primaria compuesta `(id_ejecucion, comercio)`.
- `cobertura`: clave primaria compuesta `(id_ejecucion, comercio, seccion)`.
- `correcciones` y `observaciones_rechazadas`: identificadores autoincrementales y conservación del motivo.
- Las vistas no almacenan nuevas observaciones; derivan la información de `observaciones` mediante SQL.
- Entre los índices del proyecto están los de fecha y comercio, producto comparable y ejecución, subcategoría y marca, promoción y precio, y comercio/SKU/fecha.

## Objetos creados durante la actualización

La función de actualización crea `estados_no_observados` si no existe. Solo debe poblarse cuando la cobertura de la ejecución permita establecer que un anuncio no se observó. Sus campos son: `id_ejecucion` (TEXT), `comercio` (TEXT), `sku` (TEXT), `fecha_deteccion` (TEXT), `estado` (TEXT, siempre `no_observado`) y `motivo` (TEXT). La clave primaria es `(id_ejecucion, comercio, sku)`.

## Limitaciones

- Las existencias históricas no informadas permanecen como `NULL`; no se infiere disponibilidad por el mero hecho de haber un precio.
- La cobertura registrada antes de incorporar metadatos externos no debe interpretarse como recuento certificado de la categoría.
- Precios y promociones son observaciones temporales, no una oferta garantizada al momento de consultar la aplicación.
