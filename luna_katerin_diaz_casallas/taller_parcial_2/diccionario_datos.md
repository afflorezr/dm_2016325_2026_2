# Diccionario de datos

Base `comparador_precios.sqlite`. Precios en pesos colombianos (COP), del momento de cada captura. No incluyen envío ni descuentos por afiliación o medio de pago.

La disponibilidad distingue tres situaciones:

- `disponible`: el sitio publicó un precio mayor que cero.
- `agotado`: el sitio publicó un precio de $0 o un texto de agotado.
- no observado: el anuncio no aparece en esa ejecución. No es una fila. Se calcula al comparar dos ejecuciones.

## ejecuciones

Una fila por corrida y comercio.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_ejecucion | TEXT | Identificador `AAAAMMDD_HHMMSS`, hora de Colombia. Clave con `comercio`. | |
| comercio | TEXT | Comercio consultado. | `CAFAM`, `LA REBAJA`, `LA ALEMANA` |
| fecha_inicio | TEXT | Inicio de la consulta, ISO 8601 con `-05:00`. | |
| fecha_fin | TEXT | Fin de la consulta. | |
| modo | TEXT | Cómo se obtuvo. | `en_linea`, `copias_crudas`, `prueba` |
| paginas_consultadas | INTEGER | Páginas recorridas. | |
| paginas_sin_datos | INTEGER | Páginas del recorrido que no trajeron productos. | |
| n_registros | INTEGER | Filas leídas antes de validar. | |
| productos_unicos | INTEGER | Enlaces distintos que apuntan a un producto (`/p`). | |
| total_sitio | INTEGER | Total que muestra el buscador. NULL si el sitio no lo publica. | |
| estado | TEXT | Resultado de la corrida. | `completa`, `parcial`, `fallida` |
| motivo | TEXT | Por qué quedó parcial o fallida. NULL si no aplica. | |

## historico_productos

Una fila por observación de precio. No se sobrescribe: una ejecución nueva agrega filas.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| id_observacion | INTEGER | Identificador interno. | |
| id_ejecucion | TEXT | Ejecución en la que se leyó. | |
| comercio | TEXT | Comercio del anuncio. | |
| n_producto | TEXT | Nombre tal como lo publicó el sitio. | |
| enlace | TEXT | URL del anuncio. | |
| precio | TEXT | Precio de venta, texto original. | |
| marca | TEXT | Marca publicada por el sitio. | |
| contenido | TEXT | Presentación publicada por el sitio, si la trae. | |
| precio_sin_promo | TEXT | Precio de lista, texto original. | |
| pagina | INTEGER | Página del listado. | |
| consulta | TEXT | Término usado. | `vitaminas` |
| fecha_extraccion | TEXT | Fecha y hora de la lectura, ISO 8601, `-05:00`. | |
| precio_num | REAL | Precio de venta en COP. NULL si el texto no es un precio mayor que cero. | COP |
| precio_sin_promo_num | REAL | Precio de lista en COP. | COP |
| promocion | INTEGER | 1 si el precio de lista es mayor que el de venta. | 0, 1 |
| disponibilidad | TEXT | Estado informado por el sitio. | `disponible`, `agotado`, NULL |

Restricción de unicidad: `(comercio, enlace, fecha_extraccion)`.

## anuncios

Un anuncio por comercio y enlace. Se reconstruye desde `historico_productos`. El texto original no se modifica.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| comercio | TEXT | Comercio. Clave con `enlace`. | |
| enlace | TEXT | URL del anuncio. | |
| codigo_producto | TEXT | Número final de la URL, si el sitio lo incluye. | |
| n_producto | TEXT | Nombre original de la lectura más reciente. | |
| marca | TEXT | Marca original. | |
| nombre_std | TEXT | Nombre en mayúsculas, sin tildes. | |
| marca_std | TEXT | Marca en mayúsculas, sin tildes. | |
| subcategoria | TEXT | Clasificación por palabras del nombre. | Ver reglas en `db.R` |
| cantidad | REAL | Contenido del empaque. NULL si no se identificó. | |
| unidad | TEXT | Unidad del contenido. | `mL`, `g`, `und`, NULL |
| n_observaciones | INTEGER | Lecturas acumuladas de ese anuncio. | |
| motivo_descarte | TEXT | Por qué no entra en la categoría. NULL si se conserva. | `enlace_no_es_producto`, `enlace_ambiguo`, `anuncio_sin_nombre`, `fuera_de_categoria` |
| id_producto | TEXT | Presentación comparable, si corresponde. | `P01`–`P10` |
| comparable | INTEGER | 1 si tiene `id_producto`. | 0, 1 |

## productos_comparables

Las 10 presentaciones de los 8 productos que están en los tres comercios.

| Columna | Tipo | Significado | Unidad |
|---|---|---|---|
| id_producto | TEXT | Identificador. | `P01`–`P10` |
| producto | TEXT | Nombre del producto. | |
| nombre_corto | TEXT | Etiqueta usada en la aplicación. | |
| marca | TEXT | Marca comercial común. | |
| subcategoria | TEXT | Subcategoría del producto. | |
| presentacion | TEXT | Tamaño del empaque, en texto. | |
| contenido | REAL | Contenido total del empaque. | número |
| unidad | TEXT | Unidad normalizada del contenido. La forma (cápsula, tableta) queda en `presentacion`. | `mL`, `g`, `und` |
| familia | TEXT | Agrupa los tamaños del mismo producto. | |

## correcciones

Cambios sobre campos ya guardados. No se usa para borrar una observación.

| Columna | Tipo | Significado |
|---|---|---|
| id_correccion | INTEGER | Identificador. |
| fecha | TEXT | Cuándo se corrigió, ISO 8601. |
| tabla | TEXT | Tabla afectada. |
| registro | TEXT | Identificador del registro. |
| campo | TEXT | Campo corregido. |
| valor_anterior | TEXT | Valor antes de la corrección. |
| valor_nuevo | TEXT | Valor después. |
| motivo | TEXT | Por qué se cambió. |

`registro` identifica la fila: `id_ejecucion|comercio` en `ejecuciones`, `comercio|enlace` en `anuncios` e `id_producto` en `productos_comparables`. La función `aplicar_correcciones()` de `db.R` aplica cada corrección una sola vez. Correcciones de esta entrega:

- `ejecuciones`, `20261011_195616|CAFAM`: `estado` pasa de `completa` a `parcial`. Esa corrida leyó 283 productos en 24 páginas y el sitio tenía 400 en 34 páginas.
- `anuncios`: un enlace publicitario de La Alemana sin nombre ni precio pasa a `motivo_descarte = anuncio_sin_nombre`.
- `productos_comparables`, `P01`, `P02`, `P05`, `P06`, `P09` y `P10`: `unidad` pasa de `cápsula` o `tableta` a `und`.
- `ejecuciones`, `20261114_124642|LA REBAJA`: `estado` pasa de `parcial` a `completa`. La regla de cobertura exige los 8 productos, y solo faltaba P08, cubierto por P07.

La disponibilidad de las observaciones anteriores se calculó a partir del precio guardado y no lo reemplaza.

## observaciones_rechazadas

Lecturas que no entraron a `historico_productos`, o un aviso de cobertura.

| Columna | Tipo | Significado |
|---|---|---|
| id_rechazo | INTEGER | Identificador. |
| id_ejecucion | TEXT | Ejecución. |
| comercio | TEXT | Comercio. |
| enlace | TEXT | URL, si se conocía. |
| fecha_extraccion | TEXT | Fecha de la lectura rechazada. |
| motivo | TEXT | Regla que falló. |
| detalle | TEXT | Nombre u otra nota. |
| fecha_registro | TEXT | Cuándo se anotó el rechazo. |

Motivos de fila: `dato_obligatorio_ausente`, `duplicado_en_ejecucion`, `precio_invalido`, `pointblank`. Motivos de la corrida (sin `enlace`):

- `cobertura_comparables`: falta uno de los 8 productos comparables. Deja el comercio en estado `parcial`.
- `presentacion_no_observada`: falta una presentación de un producto que sigue cubierto por otra (por ejemplo, P08 cuando está P07). Es informativo y no cambia el estado.

Ninguno de los dos borra las lecturas válidas.

## Vistas

La aplicación consulta estas vistas con los filtros en SQL.

### v_observaciones

Cada lectura de `historico_productos` con su anuncio: nombre estandarizado, subcategoría, contenido, descarte, `id_producto` y `comparable`.

### v_precios_comparables

Una lectura por ejecución, comercio y presentación comparable. Incluye el precio en COP y el precio por unidad de contenido (`precio / contenido`).

### v_ultimo_precio

La lectura más reciente de cada anuncio, con precio, precio unitario, promoción, disponibilidad y la presentación comparable si la tiene. Sirve para ver el precio vigente.

### v_cambios_precio

Para cada anuncio, la diferencia contra su lectura de la ejecución anterior: `precio_anterior`, `delta_cop`, `delta_pct` y `tipo` (`subio`, `bajo`, `igual`, `sin_precio`). Toma una lectura por anuncio y ejecución, excluye los anuncios con `motivo_descarte` (por ejemplo, la página de inicio de Cafam, que recibe un producto distinto en cada página) y solo incluye anuncios que ya tenían una lectura previa.

### v_comparables

Lo mismo que `v_precios_comparables`, más `es_mas_barato`. Vale 1 en todos los comercios empatados en el menor precio de esa presentación y ejecución.

## Índices

`idx_hist_comercio_enlace`, `idx_hist_ejecucion`, `idx_hist_fecha`, `idx_anuncios_producto`, `idx_anuncios_subcategoria`, `idx_anuncios_marca`, `idx_rechazo_ejecucion`. Cubren los filtros de comercio, ejecución, fecha, producto, subcategoría y marca.
