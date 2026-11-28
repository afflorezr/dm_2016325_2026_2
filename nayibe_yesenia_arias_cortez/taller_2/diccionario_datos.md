# Diccionario de datos · `comparador_precios.sqlite`

Taller 2 de Minería de Datos (UNAL). Categoría: cuidado capilar en La Rebaja, Locatel y Droguerías Cafam.

**Convenciones**
- Fechas y horas: texto ISO 8601 con la hora de Colombia, por ejemplo `2026-10-10T18:44:00-05:00`.
- `id_ejecucion`: texto `AAAAMMDDTHHMMSS`. Se puede ordenar como fecha.
- Precios: COP (pesos colombianos), con IVA, tal como los publica el sitio.
- Contenido: mL, g o unidad.
- Booleanos: `INTEGER` que vale 0 o 1.

**Cómo leer este documento**
- Las tablas de **1 a 7** vienen del Taller 1. Las columnas marcadas con 🆕 se agregaron en el Taller 2 (`db.migrar()`).
- Las tablas **8 y 9** y las vistas que empiezan por `v_`, excepto `v_observaciones`, son del Taller 2.
- La columna "Origen" dice de dónde sale cada dato:
  - **sitio**: el JSON o HTML del comercio, guardado en `raw/`;
  - **calc.**: se calcula a partir de datos del sitio;
  - **regla**: una regla documentada;
  - **SQLite**: columna calculada (`GENERATED`) que SQLite actualiza sola.

---

## Tablas

### 1. `comercios`: un registro por comercio
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| `id_comercio` (PK) | TEXT | Código corto del comercio | `larebaja`, `locatel`, `cafam` |
| `nombre` | TEXT | Nombre visible | `La Rebaja`, `Locatel`, `Droguerías Cafam` |
| `dominio` | TEXT | Dominio consultado | p. ej. `www.locatelcolombia.com` |
| `metodo_extraccion` | TEXT | Fuente usada: API de catálogo VTEX o HTML con `__STATE__` | texto |
| `paginas_consideradas` | TEXT | Ramas de categoría recorridas | texto, separado por `;` |

### 2. `anuncios`: el producto tal como aparece en un comercio (PK `id_comercio`, `sku_comercio`)
| Columna | Tipo | Unidad | Significado | Origen |
|---|---|---|---|---|
| `id_comercio` | TEXT | | Comercio (FK a `comercios`) | regla |
| `sku_comercio` | TEXT | | Código del SKU en el comercio (`itemId` de VTEX) | sitio |
| `product_id` | TEXT | | Código del producto en VTEX (puede agrupar varios SKU) | sitio |
| `ean`, `ean_norm` | TEXT | | EAN tal como viene; EAN normalizado a GTIN-13 (NULL si tiene menos de 8 dígitos) | sitio / calc. |
| `nombre_original` | TEXT | | Nombre del anuncio, sin modificar | sitio |
| `texto_original_anuncio` | TEXT | | Nombre, ficha técnica y descripción, sin modificar | sitio |
| `marca_original`, `marca_std` | TEXT | | Marca tal como viene; marca estandarizada (mayúsculas y alias unificados) | sitio / calc. |
| `subcategoria_original` | TEXT | | Ruta de categoría del comercio | sitio |
| `subcategoria_std` | TEXT | | Subcategoría estandarizada | `shampoo`, `acondicionador`, `mascarilla_tratamiento`, `peinado`, `coloracion`, `otro_capilar`, NULL si está excluido |
| `rama_origen` | TEXT | | Rama o ramas del comercio donde se encontró | sitio |
| `presentacion_ficha` | TEXT | | Contenido declarado en la ficha técnica (p. ej. `400 Mililitro`) | sitio |
| `tiene_descripcion` | INTEGER | 0/1 | 1 si el comercio publica una descripción con texto | calc. |
| `url` | TEXT | | Enlace al anuncio | sitio |
| `nombre_std` | TEXT | | Nombre estandarizado (mayúsculas, sin tildes) | calc. |
| `contenido_unitario` | REAL | mL o g | Contenido de una unidad del paquete | calc. |
| `unidad` | TEXT | | Unidad del Taller 1 | `ml`, `g`, `un`, NULL |
| `n_unidades` | INTEGER | unidades | Número de unidades del paquete (1 si es individual) | calc. |
| `contenido` | REAL | mL, g o unidad | **Contenido total** de la presentación (`n_unidades` × contenido unitario) | calc. |
| 🆕 `unidad_norm` | TEXT | | **Unidad normalizada** a partir de `unidad` | SQLite: `mL`, `g`, `unidad`, NULL |
| `incluido` | INTEGER | 0/1 | 1 si está dentro de la delimitación de la categoría | regla (`docs/delimitacion_categoria.md`) |
| `motivo_exclusion` | TEXT | | Por qué se excluyó | `medicamento`, `infantil`, `accesorio`, `fuera_de_categoria`, NULL |
| `comparable` | INTEGER | 0/1 | 1 si es uno de los 18 productos comparables | `comparables.py` |
| `id_producto_comun` | TEXT | | EAN del producto comparable (FK a `productos`) | `comparables.py` |
| `primera_ejecucion`, `ultima_ejecucion` | TEXT | | Primera y última ejecución en que se observó el anuncio | calc. |

### 3. `observaciones`: precio de un anuncio en una ejecución
Restricciones de unicidad:
- `UNIQUE(id_comercio, sku_comercio, fecha_hora_consulta)`, del Taller 1;
- 🆕 `UNIQUE(id_ejecucion, id_comercio, sku_comercio)`, índice `ux_obs_ejecucion_anuncio`.

| Columna | Tipo | Unidad | Significado | Valores |
|---|---|---|---|---|
| `id_observacion` (PK) | INTEGER | | Consecutivo | |
| `id_ejecucion` | TEXT | | Ejecución que la recolectó (enlaza con `ejecuciones` y con `raw/<comercio>/<fecha>/<id_ejecucion>/`) | |
| `id_comercio`, `sku_comercio` | TEXT | | Anuncio observado (FK a `anuncios`) | |
| `fecha_hora_consulta` | TEXT | ISO 8601 | Momento de la petición que trajo el dato (está en `manifiesto.json`) | |
| `precio` | REAL | COP | Precio de venta del vendedor con existencias. Si el sitio no lo publica, queda NULL; nunca se inventa | > 0 o NULL |
| `precio_antes_descuento` | REAL | COP | `ListPrice` cuando es mayor que el precio | NULL si no hay descuento |
| `es_promocion` | INTEGER | 0/1 | 1 si hay precio antes del descuento | |
| `promocion_texto` | TEXT | | Nombre de la promoción publicada (p. ej. `2x1`) | NULL si no hay |
| `disponible` | INTEGER | 0/1 | 1 si algún vendedor tiene existencias (`AvailableQuantity > 0`) | |
| 🆕 `estado_disponibilidad` | TEXT | | Calculada por SQLite a partir de `disponible` | `disponible`, `agotado` |
| `vendedor` | TEXT | | Vendedor de la oferta elegida | |
| `url` | TEXT | | Enlace al anuncio en ese momento | |
| `comparable`, `id_producto_comun` | INTEGER, TEXT | | Copia de la marca de comparable del anuncio | |
| 🆕 `descartada` | INTEGER | 0/1 | 1 si se descartó por una corrección (ver `correcciones`). No se borra | por defecto 0 |
| 🆕 `motivo_descarte` | TEXT | | Motivo del descarte | `precio_ausente`, NULL |

**Disponibilidad: tres situaciones (§3.5)**
- `disponible` y `agotado` salen de `estado_disponibilidad`.
- `no_observado` no es una observación. Se deduce en la vista `v_disponibilidad`: el anuncio ya existía y no apareció en esa ejecución. No significa agotado ni retirado.
- Cafam no informa agotados: su `AvailableQuantity` es siempre 10000 en las copias crudas. Por eso todas sus observaciones salen como `disponible`.

### 4. `ejecuciones`: una fila por ejecución y comercio (PK `id_ejecucion`, `id_comercio`)
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| `fecha_hora_inicio`, `fecha_hora_fin` | TEXT | Inicio y fin de la recolección de ese comercio | ISO 8601 |
| `n_registros` | INTEGER | SKU obtenidos (sin repetidos entre ramas) | |
| `n_productos` | INTEGER | Productos distintos (`product_id`) | |
| `total_sitio` | INTEGER | Total de productos que el sitio dice tener en las ramas | |
| `n_incluidos` | INTEGER | SKU dentro de la delimitación | |
| `estado` | TEXT | `completa` si obtuvo todo lo que reporta el sitio y tiene al menos 8 de los 18 comparables (los que falten quedan en `nota`); `parcial` si faltó parte de la categoría, hubo un error o quedaron menos de 8 comparables; `fallida` si no obtuvo nada | `completa`, `parcial`, `fallida` |
| `detalle_ramas` | TEXT | Obtenidos sobre el total por rama | |
| `nota` | TEXT | Errores, límites de la plataforma, comparables faltantes | |

### 5. `productos`: un registro por producto comparable (18)
| Columna | Tipo | Significado |
|---|---|---|
| `id_producto_comun` (PK) | TEXT | EAN/GTIN-13 normalizado: identificador común entre comercios |
| `marca_std`, `nombre_std`, `subcategoria_std` | TEXT | Marca, nombre de referencia y subcategoría estandarizados |
| `contenido` | REAL | Contenido total verificado igual en los tres comercios (mL o g) |
| `unidad` / 🆕 `unidad_norm` | TEXT | Unidad del Taller 1 (`ml`, `g`) / unidad normalizada (`mL`, `g`, `unidad`) |
| `n_unidades` | INTEGER | Unidades por paquete |
| `linea` | TEXT | Agrupa tamaños de un mismo producto (tabla `lineas`) |
| `regla_correspondencia`, `id_ejecucion_verificacion` | TEXT | Regla aplicada y ejecución en que se verificó (`20261010T184400`) |

### 6. `correspondencia`: qué SKU de cada comercio corresponde a cada producto común (54 = 18 × 3)
Columnas: `id_producto_comun`, `id_comercio`, `sku_comercio`, `id_ejecucion` (PK compuesta); `nombre_original`, `marca_std`, `contenido`, `unidad`, `n_unidades`, `precio` (COP, en la ejecución de verificación), `regla` y `verificacion` (`ok` o notas). Los 18 comparables quedan **fijos** en el Taller 2: `comparables.py` no se vuelve a ejecutar.

### 7. `lineas`: tamaños distintos de un mismo producto
`linea` (nombre de la línea), `id_producto_comun` (EAN de cada tamaño) y `nota` (tamaño, p. ej. `415 mL`). PK compuesta (`linea`, `id_producto_comun`). Un tamaño puede no ser comparable.

### 8. 🆕 `correcciones`: registro de correcciones a la base del Taller 1 (§3.2)
| Columna | Tipo | Significado |
|---|---|---|
| `id_correccion` (PK) | INTEGER | Consecutivo |
| `fecha_correccion` | TEXT | Cuándo se corrigió (ISO 8601) |
| `tabla`, `registro`, `campo` | TEXT | Qué se corrigió: tabla, clave del registro y columna. `UNIQUE(tabla, registro, campo)` |
| `valor_anterior`, `valor_nuevo` | TEXT | Valores antes y después |
| `motivo` | TEXT | Por qué |

Contenido actual: 13 filas. La retroalimentación del Taller 1 no señaló errores.
- **12 filas:** las observaciones de Locatel con precio NULL (4 SKU en cada una de las 3 ejecuciones del Taller 1), marcadas `descartada = 1`.
- **1 fila:** el estado de la ejecución `20261108T163807` de La Rebaja pasó de `parcial` a `completa`. La Rebaja dejó de publicar 2 de los 18 comparables, pero se obtuvo toda su categoría (387/387) y quedan 16 comparables, más que los 8 exigidos.

### 9. 🆕 `rechazos`: observaciones que no superaron la validación y no se insertaron (§3.4)
| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| `id_rechazo` (PK) | INTEGER | Consecutivo | |
| `id_ejecucion`, `id_comercio`, `sku_comercio` | TEXT | Observación rechazada | |
| `fecha_hora_consulta`, `url` | TEXT | Tal como venían (pueden ser NULL si ese fue el motivo) | |
| `precio` | REAL (COP) | Precio tal como venía | puede ser NULL |
| `regla` | TEXT | Regla incumplida (`validacion.py`) | `precio_mayor_que_cero`, `campo_obligatorio`, `formato_invalido`, `duplicado_en_ejecucion` |
| `motivo` | TEXT | Explicación en español | |
| `fecha_registro` | TEXT | Cuándo se registró el rechazo | ISO 8601 |

`UNIQUE(id_ejecucion, id_comercio, sku_comercio, regla)`: reprocesar la misma ejecución sin conexión no duplica rechazos.

`sqlite_sequence` es una tabla interna de SQLite (contadores de `AUTOINCREMENT`).

---

## Vistas
Todas, excepto `v_observaciones`, excluyen las observaciones con `descartada = 1` y los anuncios con `incluido = 0`.

| Vista | Para qué la usa la app | Columnas principales |
|---|---|---|
| `v_observaciones` | Vista del Taller 1 (se conserva; la recrea `scraper.conectar`) | campos mínimos del Taller 1 |
| `v_precios` | Tabla filtrada, filtros por ejecución o fechas, distribución de precios | `id_ejecucion`, `comercio`, `nombre_original`, `marca`, `subcategoria`, `contenido`, `unidad_norm`, `precio` (COP), `precio_unitario` (COP por mL, g o unidad; NULL sin contenido), `es_promocion`, `estado_disponibilidad`, `comparable`, `url`, `fecha_hora_consulta` |
| `v_ultimo_precio` | Indicadores y tabla con los precios vigentes | igual que `v_precios`, solo la última ejecución no fallida de cada comercio |
| `v_cambios_precio` | Cambios de precio entre ejecuciones consecutivas del mismo comercio (mismo anuncio) | `id_ejecucion_anterior`, `id_ejecucion`, `precio_anterior`, `precio_actual`, `diferencia` (COP), `variacion_pct` (%), `tipo_cambio` (`subió`, `bajó`, `sin cambio`) |
| `v_comparables` | Evolución del precio, precio por unidad y canasta de los 18 comparables | `id_ejecucion`, `comercio`, `id_producto_comun`, `producto`, `contenido`, `unidad_norm`, `precio` (COP), `precio_unitario` (COP/mL o COP/g), `es_promocion`, `estado_disponibilidad` |
| `v_disponibilidad` | Las tres situaciones de disponibilidad por ejecución | `id_ejecucion`, `id_comercio`, `sku_comercio`, `estado_disponibilidad` (`disponible`, `agotado`, `no_observado`) |

## Índices
- **Del Taller 1:**
  - `ix_obs_ejec` (`id_ejecucion`, `id_comercio`);
  - `ix_obs_prod` (`id_producto_comun`).
- 🆕 **Del Taller 2, para los filtros de la app:**
  - `ux_obs_ejecucion_anuncio` (único);
  - `ix_obs_precio`, `ix_obs_fecha`, `ix_obs_promocion`;
  - `ix_anuncios_subcat`, `ix_anuncios_marca`;
  - `ix_anuncios_compar`.
