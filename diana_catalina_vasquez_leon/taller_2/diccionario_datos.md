# Diccionario de datos

Generado automáticamente desde el esquema de `comparador_precios.sqlite` (`migrar_taller2.py`).

Convenciones: precios en pesos colombianos (COP); fechas en ISO 8601 con hora de Colombia (-05:00); un dato no disponible se guarda como `NULL`, nunca como 0.

## Vista `v_cambios_precio`

Variación de precio de cada anuncio entre sus dos últimas observaciones válidas.

| Columna | Tipo | Descripción |
|---|---|---|
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `titulo_original` | TEXT | Nombre del anuncio tal como se publicó (sin limpiar). |
| `marca_estandar` | TEXT | Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados). |
| `ejecucion_anterior` | TEXT | Ejecución de la observación previa. |
| `ejecucion_nueva` | TEXT | Ejecución de la observación más reciente. |
| `fecha_anterior` | TEXT | Fecha de consulta del precio anterior. |
| `fecha_nueva` | TEXT | Fecha de consulta del precio nuevo. |
| `precio_anterior` | REAL | Precio en la observación previa (COP). |
| `precio_nuevo` | REAL | Precio en la observación más reciente (COP). |
| `variacion_cop` | — | precio_nuevo - precio_anterior (COP). |
| `variacion_pct` | — | Variación porcentual respecto al precio anterior. |
| `url` | TEXT | Página de la que se extrajo el precio. |

## Vista `v_comparables`

Observaciones de los productos comparables en las ejecuciones válidas.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `id_producto_comun` | TEXT | Identificador P01..P10 del producto comparable; NULL si no es comparable. |
| `marca_estandar` | TEXT | Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados). |
| `nombre_estandar` | TEXT | Nombre estandarizado del producto comparable. |
| `contenido_num` | REAL | Contenido total de la presentación, en la unidad normalizada. |
| `unidad` | TEXT | Unidad normalizada: 'mL', 'g' o 'und' (el mg se convierte a g). |
| `precio_lista` | REAL | Precio antes del descuento (COP); igual al vigente si no hay promoción. |
| `precio_vigente` | REAL | Precio que se paga en el momento de la consulta (COP). |
| `promocion` | INTEGER | 1 si el precio vigente es promocional; 0 si no. |
| `disponible` | INTEGER | 1 = disponible; 0 = agotado según el sitio; NULL = el sitio no lo informa. |
| `precio_unitario` | — | Precio por unidad de contenido (COP por mL, g o unidad, según 'unidad'). |
| `url` | TEXT | Página de la que se extrajo el precio. |
| `titulo_original` | TEXT | Nombre del anuncio tal como se publicó (sin limpiar). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `fecha_consulta` | TEXT | Momento en que se observó el precio, ISO 8601 con -05:00. |

## Vista `v_disponibilidad`

Estado de cada anuncio por ejecución: disponible, agotado o no observado.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `estado_disponibilidad` | — | 'disponible', 'agotado', 'no_observado' o 'sin_dato'. |

## Vista `v_observaciones`

Todas las observaciones de ejecuciones válidas, con precio unitario.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_observacion` | INTEGER | Identificador interno de la observación. |
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `codigo_barras` | TEXT | EAN del producto, si el comercio lo publica. |
| `id_producto_comun` | TEXT | Identificador P01..P10 del producto comparable; NULL si no es comparable. |
| `titulo_original` | TEXT | Nombre del anuncio tal como se publicó (sin limpiar). |
| `marca_estandar` | TEXT | Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados). |
| `subcategoria` | TEXT | Subcategoría de origen del comercio. |
| `en_alcance` | INTEGER | 1 si pertenece a la categoría de la planilla; 0 si se excluyó. |
| `comparable` | INTEGER | 1 si la observación es de un producto comparable en una ejecución con precio; 0 si no. |
| `precio_lista` | REAL | Precio antes del descuento (COP); igual al vigente si no hay promoción. |
| `precio` | REAL | Precio vigente (COP). |
| `promocion` | INTEGER | 1 si el precio vigente es promocional; 0 si no. |
| `disponible` | INTEGER | 1 = disponible; 0 = agotado según el sitio; NULL = el sitio no lo informa. |
| `contenido_num` | REAL | Contenido total de la presentación, en la unidad normalizada. |
| `unidad` | TEXT | Unidad normalizada: 'mL', 'g' o 'und' (el mg se convierte a g). |
| `precio_unitario` | — | Precio por unidad de contenido (COP por mL, g o unidad, según 'unidad'). |
| `url` | TEXT | Página de la que se extrajo el precio. |
| `texto_original` | TEXT | Nombre, ficha y descripción del anuncio sin limpiar. |
| `fecha_consulta` | TEXT | Momento en que se observó el precio, ISO 8601 con -05:00. |

## Vista `v_ultimo_precio`

Última observación válida de cada anuncio, con precio unitario y la marca `vigente` (observado en la última ejecución).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_observacion` | INTEGER | Identificador interno de la observación. |
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `codigo_barras` | TEXT | EAN del producto, si el comercio lo publica. |
| `id_producto_comun` | TEXT | Identificador P01..P10 del producto comparable; NULL si no es comparable. |
| `titulo_original` | TEXT | Nombre del anuncio tal como se publicó (sin limpiar). |
| `marca_estandar` | TEXT | Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados). |
| `subcategoria` | TEXT | Subcategoría de origen del comercio. |
| `en_alcance` | INTEGER | 1 si pertenece a la categoría de la planilla; 0 si se excluyó. |
| `comparable` | INTEGER | 1 si la observación es de un producto comparable en una ejecución con precio; 0 si no. |
| `precio_lista` | REAL | Precio antes del descuento (COP); igual al vigente si no hay promoción. |
| `precio` | REAL | Precio vigente (COP). |
| `promocion` | INTEGER | 1 si el precio vigente es promocional; 0 si no. |
| `disponible` | INTEGER | 1 = disponible; 0 = agotado según el sitio; NULL = el sitio no lo informa. |
| `contenido_num` | REAL | Contenido total de la presentación, en la unidad normalizada. |
| `unidad` | TEXT | Unidad normalizada: 'mL', 'g' o 'und' (el mg se convierte a g). |
| `precio_unitario` | — | Precio por unidad de contenido (COP por mL, g o unidad, según 'unidad'). |
| `url` | TEXT | Página de la que se extrajo el precio. |
| `texto_original` | TEXT | Nombre, ficha y descripción del anuncio sin limpiar. |
| `fecha_consulta` | TEXT | Momento en que se observó el precio, ISO 8601 con -05:00. |
| `vigente` | — | 1 si el anuncio se observó en la última ejecución válida de su comercio; 0 si solo se conoce su último precio de una ejecución anterior. |

## Tabla `comercios`

Comercios de los que se extrae información.

| Columna | Tipo | Descripción |
|---|---|---|
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sitio_web` | TEXT | URL base del comercio. |

## Tabla `correcciones`

Registro de cada corrección hecha sobre datos ya cargados (fecha, registro, valor anterior y nuevo, motivo).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_correccion` | INTEGER | Identificador de la corrección. |
| `fecha` | TEXT | Momento en que se registró la corrección. |
| `tabla` | TEXT | Tabla afectada. |
| `registro` | TEXT | Clave del registro afectado. |
| `campo` | TEXT | Campo modificado. |
| `valor_anterior` | TEXT | Valor antes de la corrección. |
| `valor_nuevo` | TEXT | Valor después de la corrección. |
| `motivo` | TEXT | Por qué se corrigió o rechazó. |

## Tabla `ejecuciones`

Una fila por corrida del scraper y comercio.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `fecha_inicio` | TEXT | Inicio de la ejecución, ISO 8601 con hora de Colombia (-05:00). |
| `fecha_fin` | TEXT | Fin de la ejecución, ISO 8601. |
| `modo` | TEXT | 'en_linea' (consultó el sitio) u 'offline' (reprocesó raw/). |
| `registros_obtenidos` | INTEGER | Anuncios extraídos del comercio en esa ejecución. |
| `registros_insertados` | INTEGER | Anuncios nuevos que entraron a la base. |
| `registros_declarados_sitio` | INTEGER | Cifra que el sitio muestra para la categoría, si está disponible. |
| `estado` | TEXT | 'completa', 'parcial' o 'fallida'. |
| `detalle` | TEXT | Notas del scraper sobre la ejecución. |
| `valida` | INTEGER | 1 = se usa en el análisis; 0 = descartada (motivo en motivo_invalidez). |
| `motivo_invalidez` | TEXT | Razón por la que la ejecución se descartó. |
| `ruta_raw` | TEXT | Carpeta con las copias crudas (HTML/JSON) de esa ejecución y comercio; NULL si no existe. |

## Tabla `familias_tamano`

Mismo producto en distintos tamaños, para el precio por unidad de contenido.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_familia` | TEXT | Identificador de la familia de tamaños (F01...). |
| `nombre_familia` | TEXT | Nombre de la familia de tamaños. |
| `codigo_barras` | TEXT | EAN del producto, si el comercio lo publica. |

## Tabla `observaciones`

Una fila por anuncio (SKU) observado en una ejecución, con su precio en ese momento.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_observacion` | INTEGER | Identificador interno de la observación. |
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `codigo_barras` | TEXT | EAN del producto, si el comercio lo publica. |
| `id_producto_comercio` | TEXT | Identificador interno del producto en el comercio. |
| `url` | TEXT | Página de la que se extrajo el precio. |
| `titulo_original` | TEXT | Nombre del anuncio tal como se publicó (sin limpiar). |
| `marca_original` | TEXT | Marca tal como se publicó. |
| `presentacion_original` | TEXT | Presentación/variante tal como se publicó. |
| `texto_original` | TEXT | Nombre, ficha y descripción del anuncio sin limpiar. |
| `categoria_origen` | TEXT | Subcategoría de origen según el comercio. |
| `categorias_origen` | TEXT | Todas las colecciones/categorías del comercio a las que pertenece. |
| `en_alcance` | INTEGER | 1 si pertenece a la categoría de la planilla; 0 si se excluyó. |
| `motivo_exclusion` | TEXT | Razón de la exclusión cuando en_alcance = 0. |
| `precio_lista` | REAL | Precio antes del descuento (COP); igual al vigente si no hay promoción. |
| `precio_vigente` | REAL | Precio que se paga en el momento de la consulta (COP). |
| `precio_prime` | REAL | Precio para clientes con programa de fidelización, si existe (COP). |
| `promocion` | INTEGER | 1 si el precio vigente es promocional; 0 si no. |
| `precio_promocional` | REAL | Precio promocional (COP) cuando promocion = 1. |
| `tiendas_con_oferta` | INTEGER | Número de tiendas con oferta (Farmatodo). |
| `disponible` | INTEGER | 1 = disponible; 0 = agotado según el sitio; NULL = el sitio no lo informa. |
| `es_marketplace` | INTEGER | 1 si lo vende un tercero en el marketplace del comercio. |
| `contenido_num` | REAL | Contenido total de la presentación, en la unidad normalizada. |
| `unidad` | TEXT | Unidad normalizada: 'mL', 'g' o 'und' (el mg se convierte a g). |
| `nota_calidad` | TEXT | Advertencias de calidad del dato (por ejemplo contenido inferido). |
| `fecha_consulta` | TEXT | Momento en que se observó el precio, ISO 8601 con -05:00. |
| `marca_estandar` | TEXT | Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados). |
| `id_producto_comun` | TEXT | Identificador P01..P10 del producto comparable; NULL si no es comparable. |
| `comparable` | INTEGER | 1 si la observación es de un producto comparable en una ejecución con precio; 0 si no. |

## Tabla `observaciones_rechazadas`

Observaciones que no superaron la validación y por eso no se insertaron.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_rechazo` | INTEGER | Identificador del rechazo. |
| `id_ejecucion` | TEXT | Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS. |
| `comercio` | TEXT | Nombre del comercio (La Rebaja, Dermatodo, Farmatodo). |
| `sku_comercio` | TEXT | SKU o código del anuncio en el comercio. |
| `fecha_rechazo` | TEXT | Momento del rechazo. |
| `motivo` | TEXT | Por qué se corrigió o rechazó. |
| `datos_json` | TEXT | Observación rechazada, serializada en JSON. |

## Tabla `productos`

Los productos comparables entre comercios (identificador común, correspondencia verificada a mano).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_producto_comun` | TEXT | Identificador P01..P10 del producto comparable; NULL si no es comparable. |
| `codigo_barras` | TEXT | EAN del producto, si el comercio lo publica. |
| `marca_estandar` | TEXT | Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados). |
| `nombre_estandar` | TEXT | Nombre estandarizado del producto comparable. |
| `contenido_num` | REAL | Contenido total de la presentación, en la unidad normalizada. |
| `unidad` | TEXT | Unidad normalizada: 'mL', 'g' o 'und' (el mg se convierte a g). |
