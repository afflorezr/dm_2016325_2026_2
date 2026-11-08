# Diccionario de datos

Describe cada tabla y vista de `comparador_precios.sqlite`. Se genera con `scripts/generar_diccionario.R` a partir del esquema real de la base.
Fechas en ISO 8601 con zona horaria de Colombia (`-05:00`). Precios en pesos colombianos (COP). Contenido en mL o g.
Un dato ausente se guarda como NULL: nunca se completa con valores calculados.
La columna *Valores* muestra el conjunto permitido cuando es cerrado; en los demás casos, lo observado en la base entregada.

## Tabla `agotados`

Tarjetas que el sitio muestra como no disponibles. No tienen precio ni SKU, por eso no son observaciones.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_agotado | INTEGER |  | Identificador interno. | 1, 2, 3 |
| id_ejecucion | INTEGER |  | Ejecución en la que el sitio mostró el producto como agotado. | 2, 5 |
| id_comercio | INTEGER |  | Comercio que lo mostró. | 2 |
| fecha_hora_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la consulta. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| nombre | TEXT |  | Nombre de la tarjeta. | texto libre |
| url | TEXT |  | Enlace al producto, si la tarjeta lo traía. | texto libre |
| texto_original | TEXT |  | Texto de la tarjeta, sin limpieza. | texto libre |

## Tabla `anuncios`

Producto tal como lo publica un comercio, identificado por su SKU. Se crea la primera vez que se observa.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_anuncio | INTEGER |  | Identificador interno del anuncio. | 1 a 239 |
| id_comercio | INTEGER |  | Comercio que publica el anuncio. | 1, 2, 3 |
| sku | TEXT |  | Código del producto en el comercio. Único por comercio. | texto libre |
| id_producto | INTEGER |  | Producto comparable al que corresponde el anuncio. NULL si el anuncio no es comparable. | 1 a 9 |
| nombre_original | TEXT |  | Nombre tal como lo publica el comercio. | texto libre |
| presentacion_original | TEXT |  | Presentación tal como se publicó. Puede faltar. | texto libre |
| marca_original | TEXT |  | Marca tal como se publicó. | texto libre |
| marca_std | TEXT |  | Marca estandarizada. | texto libre |
| subcategoria_std | TEXT |  | Subcategoría estandarizada. | aceite_corporal, crema_corporal, exfoliante_corporal, otros_corporal |
| envase | TEXT |  | Tipo de envase leído del anuncio. Puede faltar. | botella, caja, frasco, spray, tubo |
| medida | TEXT |  | Unidad del contenido. NULL si no se pudo leer; no se completa con valores calculados. | ml, g |
| cantidad_unidad | REAL | ml o g | Contenido de una unidad de venta. NULL si no se pudo leer. | mayor que 0 |
| unidades | REAL | unidades | Unidades por paquete. NULL si no se pudo leer. | mayor que 0 |
| cantidad_total | REAL | ml o g | Contenido total. NULL si no se pudo leer; en ese caso no hay precio por unidad. | mayor que 0 |
| url_producto | TEXT |  | Enlace a la página del producto en el comercio. | texto libre |
| texto_original | TEXT |  | Texto de la tarjeta la primera vez que se vio, sin limpieza. | texto libre |
| primera_consulta | TEXT | fecha ISO 8601 | Fecha y hora en que se observó por primera vez. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| ultima_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la última observación. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |

## Tabla `comercios`

Comercios de los que se recolectan precios.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_comercio | INTEGER |  | Identificador interno del comercio. | 1, 2, 3 |
| codigo | TEXT |  | Clave corta del comercio usada por el scraper. | exito, farmatodo, larebaja |
| nombre | TEXT |  | Nombre del comercio para mostrar. | Farmatodo, La Rebaja, Éxito |
| sitio_web | TEXT |  | Dirección del sitio web del comercio. | https://www.exito.com, https://www.farmatodo.com.co, https://www.larebajavirtual.com |

## Tabla `correcciones`

Bitácora de correcciones hechas sobre la entrega del Taller 1. No se borran observaciones: se corrige o se documenta aquí.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_correccion | INTEGER |  | Identificador de la corrección. | 1, 2, 3 |
| fecha | TEXT | fecha ISO 8601 | Fecha y hora en que se registró la corrección. | 2026-11-07T10:45:17-05:00 |
| tabla | TEXT |  | Tabla afectada. | ejecuciones, productos |
| registro | TEXT |  | Registro afectado, con su identificador (por ejemplo id_producto=9). | id_ejecucion=1, id_ejecucion=4, id_producto=9 |
| campo | TEXT |  | Campo corregido. | en_conjunto, estado |
| valor_anterior | TEXT |  | Valor antes de la corrección. NULL si no había. | parcial |
| valor_nuevo | TEXT |  | Valor después de la corrección. | 0, completa |
| motivo | TEXT |  | Razón de la corrección. | texto libre |

## Tabla `ejecuciones`

Una fila por comercio y por corrida del scraper. Registra cuándo se corrió y cómo terminó.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_ejecucion | INTEGER |  | Identificador interno de la ejecución de un comercio. | 1, 2, 3, 4, 5, 6 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Código de la corrida del scraper. Es la columna id_ejecucion de los CSV de raw/ y enlaza cada observación con su copia cruda. | 20261017230148, 20261106221640 |
| id_comercio | INTEGER |  | Comercio recolectado en esta ejecución. | 1, 2, 3 |
| fecha_hora_inicio | TEXT | fecha ISO 8601 | Inicio de la ejecución, con zona horaria de Colombia (-05:00). | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| n_registros | INTEGER | observaciones | Cantidad de registros recolectados. | 0 o más |
| estado | TEXT |  | Resultado de la ejecución. | completa, parcial, fallida |
| mensaje | TEXT |  | Motivo cuando la ejecución no fue completa. NULL si fue completa. | sin datos |

## Tabla `observaciones`

Precio de un anuncio en un momento dado. Es la tabla central: nunca se sobrescribe, solo se agregan filas.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_observacion | INTEGER |  | Identificador interno de la observación. | 1 a 462 |
| id_anuncio | INTEGER |  | Anuncio observado. | 1 a 239 |
| id_comercio | INTEGER |  | Comercio del anuncio. | 1, 2, 3 |
| id_ejecucion | INTEGER |  | Ejecución en la que se obtuvo la observación. | 1, 2, 3, 4, 5, 6 |
| fecha_hora_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la consulta del precio, con zona horaria de Colombia (-05:00). | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| precio_cop | INTEGER | COP | Precio que paga cualquier cliente, ya con el descuento general si lo hay. | mayor que 0 |
| precio_lista_cop | INTEGER | COP | Precio sin descuento. Nunca es menor que precio_cop. | mayor que 0 |
| es_promocion | INTEGER |  | 1 si precio_cop es menor que precio_lista_cop. | 0, 1 |
| url_extraccion | TEXT |  | Página de la que se extrajo el precio. | texto libre |
| texto_original_anuncio | TEXT |  | Texto de la tarjeta en el momento de la consulta, sin limpieza. Junto con comercio, sku y código de corrida enlaza con la fila cruda de raw/. | texto libre |
| busqueda | TEXT |  | Primera búsqueda en la que apareció el anuncio. Informativo. | aceite corporal, crema corporal, crema hidratante corporal, estrías, exfoliante |
| disponibilidad | TEXT |  | Estado según el sitio. agotado solo si la tarjeta con precio lo indica. El estado no observado no se guarda: se deriva en v_no_observados. | disponible, agotado |

## Tabla `productos`

Catálogo de productos comparables del Taller 1. El conjunto comparable en los tres comercios son los de en_conjunto = 1.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_producto | INTEGER |  | Identificador del producto comparable (el del catálogo del Taller 1). | 1 a 9 |
| nombre | TEXT |  | Nombre estándar del producto, con su contenido. | texto libre |
| linea | TEXT |  | Nombre del producto sin el contenido, por ejemplo «Lubriderm humectación diaria». | Lubriderm FPS 15, Lubriderm humectación delicada, Lubriderm humectación diaria, Lubriderm reparación intensiva, Nivea hidratación express |
| marca_std | TEXT |  | Marca estandarizada. | LUBRIDERM, NIVEA |
| subcategoria_std | TEXT |  | Subcategoría estandarizada. | crema_corporal |
| presentacion | TEXT |  | Contenido legible, por ejemplo «400 ml» o «3 x 200 ml». | 1000 ml, 120 ml, 200 ml, 400 ml, 946 ml |
| medida | TEXT |  | Unidad en que se mide el contenido. | ml, g |
| cantidad_unidad | REAL | ml o g | Contenido de una unidad de venta. | mayor que 0 |
| unidades | REAL | unidades | Número de unidades por paquete. | mayor que 0 |
| cantidad_total | REAL | ml o g | Contenido total (cantidad_unidad por unidades). Es el divisor del precio por unidad. | mayor que 0 |
| en_conjunto | INTEGER |  | 1 si el producto pertenece al conjunto de ocho comparables presentes en los tres comercios. | 0, 1 |

## Tabla `rechazos`

Observaciones que no superaron la validación y por eso no se insertaron, con la regla incumplida.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_rechazo | INTEGER |  | Identificador del rechazo. | 1 a 13 |
| fecha_hora_registro | TEXT | fecha ISO 8601 | Cuándo se registró el rechazo. | 2026-11-07T11:32:19-05:00 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Corrida en que se obtuvo la observación rechazada. | 20261017230148, 20261106221640 |
| comercio | TEXT |  | Código del comercio, como lo entrega el scraper. | exito, farmatodo |
| sku | TEXT |  | SKU de la observación rechazada. NULL si la tarjeta no lo tenía. | 100612, 102561952, 1046969, 104881722, 226150255, 422552 |
| nombre | TEXT |  | Nombre de la tarjeta rechazada. | texto libre |
| precio_texto | TEXT | COP | Precio de la observación rechazada, tal como llegó. Puede estar vacío. | texto libre |
| regla | TEXT |  | Regla de validación incumplida. | precio_real_positivo, precio_lista_positivo, precio_real_le_lista, comercio_presente, sku_presente, url_presente, fecha_presente, fecha_formato_iso, no_duplicada |
| motivo | TEXT |  | Explicación de la regla incumplida. | texto libre |

## Vista `v_cambios_precio`

Cada observación comparada con la inmediatamente anterior del mismo anuncio (mismo anuncio, mismo comercio).

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_observacion | INTEGER |  | Observación actual (la más reciente de la pareja comparada). | 227 a 462 |
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja, Éxito |
| id_anuncio | INTEGER |  | Anuncio comparado consigo mismo en el tiempo. | 1 a 226 |
| sku | TEXT |  | Código del producto en el comercio. | texto libre |
| nombre | TEXT |  | Nombre del anuncio. | texto libre |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si no es comparable. | 1 a 9 |
| id_ejecucion_anterior | INTEGER |  | Ejecución de la observación anterior. | 1, 2, 3 |
| id_ejecucion | INTEGER |  | Ejecución de la observación actual. | 4, 5, 6 |
| fecha_anterior | TEXT | fecha ISO 8601 | Fecha de la observación anterior. | 2026-10-17T23:01:48-05:00 |
| fecha_actual | TEXT | fecha ISO 8601 | Fecha de la observación actual. | 2026-11-06T22:16:40-05:00 |
| precio_anterior | INTEGER | COP | Precio en la observación anterior. | 9990 a 244990 |
| precio_actual | INTEGER | COP | Precio en la observación actual. | 9990 a 244990 |
| variacion_cop | INTEGER | COP | Precio actual menos precio anterior. Positivo si subió. | -13725 a 38381 |
| variacion_pct | REAL | % | Variación porcentual respecto al precio anterior, con un decimal. | -30 a 64.8 |

## Vista `v_comparables`

Observaciones de los ocho productos comparables en los tres comercios. Mismas columnas que v_precios.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_observacion | INTEGER |  | Identificador de la observación. | 1 a 442 |
| id_anuncio | INTEGER |  | Identificador del anuncio. | 42 a 226 |
| id_ejecucion | INTEGER |  | Identificador de la ejecución. | 1, 2, 3, 4, 5, 6 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Código de la corrida del scraper. | 20261017230148, 20261106221640 |
| estado_ejecucion | TEXT |  | Estado de la ejecución del comercio. | completa, parcial, fallida |
| fecha_hora_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la consulta. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| id_comercio | INTEGER |  | Identificador del comercio. | 1, 2, 3 |
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja, Éxito |
| sku | TEXT |  | Código del producto en el comercio. | texto libre |
| nombre | TEXT |  | Nombre del anuncio tal como lo publica el comercio. | texto libre |
| marca | TEXT |  | Marca estandarizada. | LUBRIDERM |
| subcategoria | TEXT |  | Subcategoría estandarizada. | crema_corporal |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si el anuncio no es comparable. | 1 a 8 |
| producto | TEXT |  | Nombre estándar del producto comparable. NULL si no es comparable. | texto libre |
| es_comparable | INTEGER |  | 1 si el anuncio corresponde a un producto del catálogo. | 0, 1 |
| en_conjunto | INTEGER |  | 1 si el producto es uno de los ocho comparables en los tres comercios. | 0, 1 |
| medida | TEXT |  | Unidad del contenido. NULL si no se pudo leer. | ml, g |
| cantidad_unidad | REAL | ml o g | Contenido de una unidad de venta. | 120, 200, 400, 946 |
| unidades | REAL | unidades | Unidades por paquete. | 1 |
| cantidad_total | REAL | ml o g | Contenido total. | 120, 200, 400, 946 |
| presentacion | TEXT |  | Contenido legible, por ejemplo «400 ml» o «3 x 200 ml». NULL si no hay contenido. | 120 ml, 200 ml, 400 ml, 946 ml |
| precio | INTEGER | COP | Precio que paga cualquier cliente. | 19600 a 81150 |
| precio_lista | INTEGER | COP | Precio sin descuento. | 19600 a 81150 |
| es_promocion | INTEGER |  | 1 si precio es menor que precio_lista. | 0, 1 |
| disponibilidad | TEXT |  | Estado según el sitio. | disponible, agotado |
| precio_por_medida | REAL | COP por ml o g | Precio dividido entre cantidad_total. NULL si no hay contenido. Solo es comparable entre anuncios con la misma medida. | 46.59 a 174.5 |
| url_extraccion | TEXT |  | Página de la que se extrajo el precio. | texto libre |
| url_producto | TEXT |  | Enlace al producto. | texto libre |
| texto_original_anuncio | TEXT |  | Texto de la tarjeta en el momento de la consulta. | texto libre |

## Vista `v_no_observados`

Anuncios vistos antes que no aparecieron en una ejecución completa. situacion indica si el sitio los mostró como agotados.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_ejecucion | INTEGER |  | Ejecución en que el anuncio no apareció. | 5, 6 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Código de la corrida. | 20261106221640 |
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja |
| id_anuncio | INTEGER |  | Anuncio que no apareció. | 158, 211, 222 |
| sku | TEXT |  | Código del producto en el comercio. | 445, 500016316, 73395 |
| nombre | TEXT |  | Nombre del anuncio. | texto libre |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si no es comparable. | sin datos |
| situacion | TEXT |  | agotado_segun_sitio si el sitio mostró el producto como no disponible en esa ejecución; no_observado si simplemente no apareció (no se interpreta como agotado ni retirado). | agotado_segun_sitio, no_observado |

## Vista `v_observaciones`

Vista heredada del Taller 1: una fila por observación. Se conserva por compatibilidad con el scraper; la aplicación usa v_precios.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_observacion | INTEGER |  | Identificador de la observación. | 1 a 462 |
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja, Éxito |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si el anuncio no es comparable. | 1 a 9 |
| producto | TEXT |  | Nombre estándar del producto comparable. NULL si no es comparable. | texto libre |
| linea | TEXT |  | Nombre del producto sin el contenido, por ejemplo «Lubriderm humectación diaria». | Lubriderm FPS 15, Lubriderm humectación delicada, Lubriderm humectación diaria, Lubriderm reparación intensiva, Nivea hidratación express |
| es_comparable | INTEGER |  | 1 si el anuncio corresponde a un producto del catálogo. | 0, 1 |
| sku | TEXT |  | Código del producto en el comercio. | texto libre |
| nombre_original | TEXT |  | Nombre tal como lo publica el comercio. | texto libre |
| marca_std | TEXT |  | Marca estandarizada. | texto libre |
| subcategoria_std | TEXT |  | Subcategoría estandarizada. | aceite_corporal, crema_corporal, exfoliante_corporal, otros_corporal |
| medida | TEXT |  | Unidad del contenido. NULL si no se pudo leer. | ml, g |
| cantidad_unidad | REAL | ml o g | Contenido de una unidad de venta. | 10 a 1000 |
| unidades | REAL | unidades | Unidades por paquete. | 1, 2, 3, 4, 5 |
| cantidad_total | REAL | ml o g | Contenido total. | 10 a 1000 |
| precio_cop | INTEGER | COP | Precio que paga cualquier cliente, ya con el descuento general si lo hay. | mayor que 0 |
| precio_lista_cop | INTEGER | COP | Precio sin descuento. Nunca es menor que precio_cop. | mayor que 0 |
| es_promocion | INTEGER |  | 1 si precio es menor que precio_lista. | 0, 1 |
| precio_por_medida | REAL | COP por ml o g | Precio dividido entre cantidad_total. NULL si no hay contenido. Solo es comparable entre anuncios con la misma medida. | 9.99 a 11490 |
| fecha_hora_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la consulta. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Código de la corrida del scraper. | 20261017230148, 20261106221640 |
| estado_ejecucion | TEXT |  | Estado de la ejecución del comercio. | completa, parcial, fallida |
| url_extraccion | TEXT |  | Página de la que se extrajo el precio. | texto libre |
| url_producto | TEXT |  | Enlace al producto. | texto libre |
| texto_original_anuncio | TEXT |  | Texto de la tarjeta en el momento de la consulta. | texto libre |

## Vista `v_precios`

Una fila por observación con todos los datos unidos (comercio, anuncio, producto, ejecución). Base de las demás vistas.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_observacion | INTEGER |  | Identificador de la observación. | 1 a 462 |
| id_anuncio | INTEGER |  | Identificador del anuncio. | 1 a 239 |
| id_ejecucion | INTEGER |  | Identificador de la ejecución. | 1, 2, 3, 4, 5, 6 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Código de la corrida del scraper. | 20261017230148, 20261106221640 |
| estado_ejecucion | TEXT |  | Estado de la ejecución del comercio. | completa, parcial, fallida |
| fecha_hora_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la consulta. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| id_comercio | INTEGER |  | Identificador del comercio. | 1, 2, 3 |
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja, Éxito |
| sku | TEXT |  | Código del producto en el comercio. | texto libre |
| nombre | TEXT |  | Nombre del anuncio tal como lo publica el comercio. | texto libre |
| marca | TEXT |  | Marca estandarizada. | texto libre |
| subcategoria | TEXT |  | Subcategoría estandarizada. | aceite_corporal, crema_corporal, exfoliante_corporal, otros_corporal |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si el anuncio no es comparable. | 1 a 9 |
| producto | TEXT |  | Nombre estándar del producto comparable. NULL si no es comparable. | texto libre |
| es_comparable | INTEGER |  | 1 si el anuncio corresponde a un producto del catálogo. | 0, 1 |
| en_conjunto | INTEGER |  | 1 si el producto es uno de los ocho comparables en los tres comercios. | 0, 1 |
| medida | TEXT |  | Unidad del contenido. NULL si no se pudo leer. | ml, g |
| cantidad_unidad | REAL | ml o g | Contenido de una unidad de venta. | 10 a 1000 |
| unidades | REAL | unidades | Unidades por paquete. | 1, 2, 3, 4, 5 |
| cantidad_total | REAL | ml o g | Contenido total. | 10 a 1000 |
| presentacion | TEXT |  | Contenido legible, por ejemplo «400 ml» o «3 x 200 ml». NULL si no hay contenido. | texto libre |
| precio | INTEGER | COP | Precio que paga cualquier cliente. | 9990 a 244990 |
| precio_lista | INTEGER | COP | Precio sin descuento. | 9990 a 244990 |
| es_promocion | INTEGER |  | 1 si precio es menor que precio_lista. | 0, 1 |
| disponibilidad | TEXT |  | Estado según el sitio. | disponible, agotado |
| precio_por_medida | REAL | COP por ml o g | Precio dividido entre cantidad_total. NULL si no hay contenido. Solo es comparable entre anuncios con la misma medida. | 9.99 a 11490 |
| url_extraccion | TEXT |  | Página de la que se extrajo el precio. | texto libre |
| url_producto | TEXT |  | Enlace al producto. | texto libre |
| texto_original_anuncio | TEXT |  | Texto de la tarjeta en el momento de la consulta. | texto libre |

## Vista `v_ultimo_precio`

La observación más reciente de cada anuncio. Mismas columnas que v_precios.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| id_observacion | INTEGER |  | Identificador de la observación. | 176 a 462 |
| id_anuncio | INTEGER |  | Identificador del anuncio. | 1 a 239 |
| id_ejecucion | INTEGER |  | Identificador de la ejecución. | 2, 3, 4, 5, 6 |
| codigo_corrida | TEXT | AAAAMMDDhhmmss | Código de la corrida del scraper. | 20261017230148, 20261106221640 |
| estado_ejecucion | TEXT |  | Estado de la ejecución del comercio. | completa, parcial, fallida |
| fecha_hora_consulta | TEXT | fecha ISO 8601 | Fecha y hora de la consulta. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| id_comercio | INTEGER |  | Identificador del comercio. | 1, 2, 3 |
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja, Éxito |
| sku | TEXT |  | Código del producto en el comercio. | texto libre |
| nombre | TEXT |  | Nombre del anuncio tal como lo publica el comercio. | texto libre |
| marca | TEXT |  | Marca estandarizada. | texto libre |
| subcategoria | TEXT |  | Subcategoría estandarizada. | aceite_corporal, crema_corporal, exfoliante_corporal, otros_corporal |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si el anuncio no es comparable. | 1 a 9 |
| producto | TEXT |  | Nombre estándar del producto comparable. NULL si no es comparable. | texto libre |
| es_comparable | INTEGER |  | 1 si el anuncio corresponde a un producto del catálogo. | 0, 1 |
| en_conjunto | INTEGER |  | 1 si el producto es uno de los ocho comparables en los tres comercios. | 0, 1 |
| medida | TEXT |  | Unidad del contenido. NULL si no se pudo leer. | ml, g |
| cantidad_unidad | REAL | ml o g | Contenido de una unidad de venta. | 10 a 1000 |
| unidades | REAL | unidades | Unidades por paquete. | 1, 2, 3, 4, 5 |
| cantidad_total | REAL | ml o g | Contenido total. | 10 a 1000 |
| presentacion | TEXT |  | Contenido legible, por ejemplo «400 ml» o «3 x 200 ml». NULL si no hay contenido. | texto libre |
| precio | INTEGER | COP | Precio que paga cualquier cliente. | 9990 a 244990 |
| precio_lista | INTEGER | COP | Precio sin descuento. | 9990 a 244990 |
| es_promocion | INTEGER |  | 1 si precio es menor que precio_lista. | 0, 1 |
| disponibilidad | TEXT |  | Estado según el sitio. | disponible, agotado |
| precio_por_medida | REAL | COP por ml o g | Precio dividido entre cantidad_total. NULL si no hay contenido. Solo es comparable entre anuncios con la misma medida. | 9.99 a 11490 |
| url_extraccion | TEXT |  | Página de la que se extrajo el precio. | texto libre |
| url_producto | TEXT |  | Enlace al producto. | texto libre |
| texto_original_anuncio | TEXT |  | Texto de la tarjeta en el momento de la consulta. | texto libre |

## Vista `v_variacion_precio`

Vista heredada del Taller 1: última observación de cada anuncio frente a la anterior. La aplicación usa v_cambios_precio.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| comercio | TEXT |  | Nombre del comercio. | Farmatodo, La Rebaja, Éxito |
| id_producto | INTEGER |  | Producto comparable correspondiente. NULL si el anuncio no es comparable. | 1 a 9 |
| producto | TEXT |  | Nombre estándar del producto comparable. NULL si no es comparable. | texto libre |
| linea | TEXT |  | Nombre del producto sin el contenido, por ejemplo «Lubriderm humectación diaria». | Lubriderm FPS 15, Lubriderm humectación delicada, Lubriderm humectación diaria, Lubriderm reparación intensiva, Nivea hidratación express |
| sku | TEXT |  | Código del producto en el comercio. | texto libre |
| nombre_original | TEXT |  | Nombre tal como lo publica el comercio. | texto libre |
| fecha_actual | TEXT | fecha ISO 8601 | Fecha de la observación actual. | 2026-10-17T23:01:48-05:00, 2026-11-06T22:16:40-05:00 |
| precio_actual | INTEGER | COP | Precio en la observación actual. | 9990 a 244990 |
| precio_por_medida_actual | REAL | COP por ml o g | Precio actual dividido entre cantidad_total. | 9.99 a 11490 |
| fecha_anterior | TEXT | fecha ISO 8601 | Fecha de la observación anterior. | 2026-10-17T23:01:48-05:00 |
| precio_anterior | INTEGER | COP | Precio en la observación anterior. | 9990 a 244990 |
| variacion_cop | INTEGER | COP | Precio actual menos precio anterior. Positivo si subió. | -13725 a 38381 |
| variacion_pct | REAL | % | Variación porcentual respecto al precio anterior, con un decimal. | -30 a 64.8 |

