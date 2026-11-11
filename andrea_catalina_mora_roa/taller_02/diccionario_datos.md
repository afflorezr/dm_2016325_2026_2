# Diccionario de datos · `comparador_precios.sqlite`

Base SQLite del comparador de precios de **analgésicos, antipiréticos y antiinflamatorios** (categoría 29) en La Rebaja, Droguerías Cafam y Locatel Colombia.

Convenciones:
- Precios en **pesos colombianos (COP)**, tal como los publica el sitio en el momento de la consulta.
- Fechas y horas en **ISO 8601 con zona de Colombia**, por ejemplo `2026-11-05T23:50:20-05:00`.
- El id de una ejecución (`ejecucion_id`) es la hora de inicio en formato `AAAAMMDDTHHMMSS`, igual que la carpeta `raw/<comercio>/<ejecucion_id>/` que guarda sus copias crudas.
- Un dato que no se pudo extraer queda `NULL`: nunca se imputa.
- La estructura se crea con `preparar_base()` en `esquema.R`, que es idempotente.

---

## Tablas del Taller 1 (se conservan)

### `comercios`
Comercios consultados.

| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| `comercio` | TEXT (PK) | Código del comercio | `larebaja`, `cafam`, `locatel` |
| `nombre` | TEXT | Nombre para mostrar | La Rebaja, Droguerías Cafam, Locatel Colombia |
| `base_url` | TEXT | Dominio del sitio | URL |

### `ejecuciones`
Una fila por ejecución del scraper y comercio.

| Columna | Tipo | Significado | Unidad / valores |
|---|---|---|---|
| `ejecucion_id` | TEXT (PK) | Id de la ejecución | `AAAAMMDDTHHMMSS` |
| `comercio` | TEXT (PK, FK) | Comercio | ver `comercios` |
| `inicio`, `fin` | TEXT | Primera y última consulta al sitio | ISO 8601 |
| `modo` | TEXT | Cómo se capturó | `online` (consulta en línea; las copias de `raw/` lo respaldan) |
| `n_registros` | INTEGER | Filas que devolvió el scraper (SKU únicos) | conteo |
| `n_productos` | INTEGER | Productos (id del comercio) recolectados | conteo |
| `total_sitio` | INTEGER | Total que el sitio declara para la categoría | conteo |
| `estado` | TEXT | Resultado | `completa` (categoría completa y canasta de referencia presente), `parcial`, `fallida` |
| `notas` | TEXT | Detalle: totales por categoría, páginas, motivo de falla, validaciones | texto |

### `anuncios`
Un anuncio es un SKU de un comercio. Se inserta una sola vez y no se sobrescribe.

| Columna | Tipo | Significado |
|---|---|---|
| `anuncio_id` | INTEGER (PK) | Id interno |
| `comercio` | TEXT (FK) | Comercio |
| `producto_id` | TEXT | Id del producto en el sitio (VTEX `productId`) |
| `sku_comercio` | TEXT | SKU del comercio. Es único por comercio (`UNIQUE(comercio, sku_comercio)`) |
| `ean` | TEXT | Código de barras publicado (puede faltar) |
| `referencia` | TEXT | Referencia del sitio |
| `nombre_original`, `marca_original`, `descripcion_original` | TEXT | Texto tal como lo publica el sitio |
| `categoria_origen` | TEXT | Ruta de categorías del sitio |
| `categoria_consulta` | TEXT | Categoría consultada (ids VTEX, p. ej. `9/50`) |
| `url` | TEXT | Enlace al anuncio. Cafam lo publica relativo; las vistas lo completan con `base_url` |
| `texto_original` | TEXT | Nombre, descripción y ficha técnica unidos por ` \| ` (base para la búsqueda) |
| `primera_ejecucion` | TEXT | Ejecución en que apareció por primera vez |

### `observaciones`
Precio de un anuncio en una ejecución. Las nuevas observaciones se agregan; nunca se sobrescriben.

| Columna | Tipo | Significado | Unidad / valores |
|---|---|---|---|
| `obs_id` | INTEGER (PK) | Id interno | |
| `ejecucion_id`, `comercio` | TEXT (FK) | Ejecución y comercio | |
| `anuncio_id` | INTEGER (FK) | Anuncio observado | |
| `fecha_hora` | TEXT | Hora de la consulta de la página que contenía el anuncio (de `raw/.../indice.csv`) | ISO 8601 |
| `precio` | REAL | Precio de venta | COP |
| `precio_lista` | REAL | Precio antes de descuento | COP |
| `en_promocion` | INTEGER | 1 si `precio < precio_lista` | 0, 1, NULL |
| `disponible` | INTEGER | Existencias según el sitio (`AvailableQuantity > 0`) | 0, 1, NULL |
| `estado_disponibilidad` | TEXT | **(Taller 2)** Disponibilidad legible | `disponible`, `agotado` (según el sitio), `sin dato` |
| `moneda` | TEXT | Moneda | `COP` |
| `url` | TEXT | URL consultada (API o página) | |
| `descartada` | INTEGER | **(Taller 2)** 1 si la observación no cumple las reglas y se excluye (no se borra) | 0, 1 |
| `motivo_descarte` | TEXT | **(Taller 2)** Por qué se descartó | texto |

Restricciones: `UNIQUE(comercio, anuncio_id, fecha_hora)` y el índice único **`ux_obs_ejecucion_anuncio (ejecucion_id, anuncio_id)`**, que impide insertar dos veces la misma observación de una ejecución.

### `clasificacion`
Limpieza y estandarización por anuncio (`limpieza.R`). El texto original no se modifica.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| `anuncio_id` | INTEGER (PK, FK) | Anuncio | |
| `en_categoria` | INTEGER | Pertenece a la categoría según el principio activo | 1 sí, 0 no, NULL revisar |
| `motivo_categoria` | TEXT | Regla aplicada | texto |
| `confianza_categoria` | TEXT | Origen de la clasificación | `declarado`, `heredado por EAN` |
| `principio_activo_std` | TEXT | Principios activos detectados | p. ej. `IBUPROFENO+CAFEINA` |
| `forma` | TEXT | Forma farmacéutica | `solido oral`, `liquido oral`, `topico (gel/crema/spray)`, `parche`, NULL |
| `venta` | TEXT | Condición de venta | `OTC`, `Con formula medica`, `No informado` |
| `es_paquete_promo` | INTEGER | Kit, combo, "pague X lleve Y" | 0, 1 |
| `pediatrico` | INTEGER | Presentación pediátrica | 0, 1 |
| `ean_norm` | TEXT | EAN solo con dígitos, sin ceros a la izquierda | |
| `marca_std` | TEXT | Marca estandarizada | mayúsculas, sin tildes |
| `subcategoria_std` | TEXT | Subcategoría por uso y vía | `Acetaminofen oral`, `AINE oral u otro analgesico oral`, `Acido acetilsalicilico oral`, `Combinacion analgesica oral`, `Analgesico/antiinflamatorio topico`, `Opioide oral (con formula)` |
| `concentracion` | TEXT | Concentración | p. ej. `500 mg`, `1 %` |
| `contenido_valor` | REAL | Contenido de la presentación | número |
| `contenido_unidad` | TEXT | Unidad del contenido | `un`, `ml`, `g` |
| `n_dup_en_comercio` | INTEGER | Anuncios del mismo producto en el comercio | conteo |
| `dup_conflicto` | INTEGER | Duplicados con precios distintos | 0, 1 |

### `productos`
Presentación estandarizada: mismo EAN y mismo contenido.

| Columna | Tipo | Significado | Unidad / valores |
|---|---|---|---|
| `producto_id` | TEXT (PK) | `EAN<ean>-<contenido><unidad>`, p. ej. `EAN7707172688939-10.0un` | |
| `descripcion` | TEXT | Nombre más completo entre los anuncios | |
| `marca_std` | TEXT | Marca de consenso (la más frecuente) | |
| `subcategoria_std` | TEXT | Subcategoría de consenso entre comercios (**corregida en el Taller 2**) | ver `clasificacion` |
| `principio_activo_std` | TEXT | Unión de los principios activos declarados | |
| `contenido_valor`, `contenido_unidad` | REAL, TEXT | Contenido en la notación del Taller 1 | `un`, `ml`, `g` |
| `contenido_total` | REAL | **(Taller 2)** Contenido total de la presentación | número de `unidad_norm` |
| `unidad_norm` | TEXT | **(Taller 2)** Unidad normalizada | `mL`, `g`, `unidad` |
| `unidades_empaque` | INTEGER | Unidades por empaque (sólidos) | conteo |
| `concentracion` | TEXT | Concentración | |
| `comparable` | INTEGER | Comparable en la última ejecución procesada | 0, 1 |

### `correspondencia`
Relación entre cada anuncio y su producto estandarizado.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| `anuncio_id` | INTEGER (PK) | Anuncio | |
| `producto_id` | TEXT (FK) | Producto | |
| `comparable` | INTEGER | Comparable en la última ejecución procesada | 0, 1 |
| `regla` | TEXT | Regla de emparejamiento | `R1: mismo EAN y mismo contenido`, `R2: sin EAN; coincide marca+activos+concentracion+contenido…` |

### `obs_comparable`
Comparabilidad de cada observación **dentro de su ejecución**: el producto está en los tres comercios, pertenece a la categoría, tiene precio y contenido, no es un paquete promocional y no tiene duplicados con precios contradictorios.

| Columna | Tipo | Valores |
|---|---|---|
| `obs_id` | INTEGER (PK, FK) | |
| `ejecucion_id` | TEXT | |
| `comparable` | INTEGER | 0, 1 |

### `familias`
Productos comparables agrupados en familias: el mismo producto en distintos tamaños.

| Columna | Tipo | Significado |
|---|---|---|
| `producto_id` | TEXT (PK) | Producto |
| `familia` | TEXT | Marca + activos + concentración + línea + `[unidad]` |
| `n_tamanos` | INTEGER | Tamaños distintos de la familia |

---

## Tablas nuevas del Taller 2

### `correcciones`
Cada cambio a datos ya existentes, con su valor anterior.

| Columna | Tipo | Significado |
|---|---|---|
| `correccion_id` | INTEGER (PK) | Id |
| `fecha` | TEXT | Cuándo se corrigió |
| `tabla` | TEXT | Tabla afectada |
| `registro` | TEXT | Registro afectado, p. ej. `obs_id=241` |
| `campo` | TEXT | Columna corregida |
| `valor_anterior`, `valor_nuevo` | TEXT | Valores antes y después |
| `motivo` | TEXT | Justificación |

### `rechazos`
Observaciones que **no superaron la validación** y por eso no se insertaron en `observaciones`.

| Columna | Tipo | Significado |
|---|---|---|
| `rechazo_id` | INTEGER (PK) | Id |
| `ejecucion_id`, `comercio`, `sku_comercio` | TEXT | Identificación (son trazables a `raw/`) |
| `nombre_original`, `url`, `fecha_hora`, `precio` | | Datos de la fila rechazada |
| `regla` | TEXT | `precio_positivo`, `campos_presentes`, `fecha_iso`, `moneda_cop`, `sin_duplicados` |
| `motivo` | TEXT | Motivo legible |
| `registrado` | TEXT | Cuándo se registró |

### `validaciones`
Resultado de cada regla por ejecución y comercio. Clave primaria: `ejecucion_id`, `comercio`, `regla`.

| Columna | Tipo | Valores |
|---|---|---|
| `regla` | TEXT | Las cinco anteriores más `canasta_referencia` (los 8 productos de referencia presentes) |
| `evaluadas`, `fallas` | INTEGER | conteos |
| `resultado` | TEXT | `cumple`, `no cumple` |
| `detalle` | TEXT | Descripción o productos faltantes |
| `registrado` | TEXT | ISO 8601 |

### `log_actualizaciones`
Una fila por comercio cada vez que se ejecuta una actualización, desde la aplicación o desde la consola. La aplicación la consulta para mostrar el avance.

| Columna | Tipo | Significado | Valores |
|---|---|---|---|
| `log_id` | INTEGER (PK) | Id | |
| `actualizacion_id` | TEXT | Id de la pulsación del botón | |
| `ejecucion_id`, `comercio`, `modo` | TEXT | | `online`, `offline` |
| `inicio`, `fin` | TEXT | ISO 8601 | |
| `estado` | TEXT | | `en curso`, `completa`, `parcial`, `fallida` |
| `recolectados` | INTEGER | Filas devueltas por el scraper | conteo |
| `nuevos` | INTEGER | Anuncios que no existían | conteo |
| `insertadas` | INTEGER | Observaciones insertadas (las existentes se ignoran) | conteo |
| `rechazadas` | INTEGER | Filas rechazadas por la validación | conteo |
| `cambios_precio` | INTEGER | Anuncios con precio distinto al de la ejecución anterior | conteo |
| `no_observados` | INTEGER | Anuncios de la ejecución anterior que no aparecieron | conteo |
| `motivo` | TEXT | Falla o advertencia | texto |

### `canasta_referencia`
Los **8 productos comparables** cuya presencia se exige en cada comercio y ejecución.

| Columna | Tipo | Significado |
|---|---|---|
| `producto_id` | TEXT (PK, FK) | Producto |
| `orden` | INTEGER | 1 a 8 |
| `motivo` | TEXT | Por qué se eligió: cubre las subcategorías y las tres unidades |

---

## Vistas

| Vista | Para qué la usa la aplicación | Contenido |
|---|---|---|
| `v_observaciones` | Filtros, tabla, indicadores, distribución, gráfico por marca | Una fila por observación **no descartada**, con todo lo estandarizado: `fecha` (AAAA-MM-DD), `comercio_nombre`, `url_anuncio` absoluta, `estado_disponibilidad`, subcategoría y marca de consenso, `unidad_norm`, `producto_id`, `comparable` (en su ejecución) y `precio_por_unidad` (COP por mL, g o unidad) |
| `v_ultimo_precio` | Consulta del precio vigente | La observación más reciente de cada anuncio |
| `v_cambios_precio` | Indicador "cambios de precio" | Para cada anuncio, su precio frente al de la ejecución anterior en que se observó: `cambio_cop`, `cambio_pct` y `direccion` (`subió`, `bajó`, `igual`) |
| `v_comparables` | Evolución, precio por unidad, ahorro y canasta | Una fila por producto comparable, comercio y ejecución: precio (el mínimo si hay dos anuncios con el mismo precio), `contenido_total`, `unidad_norm` y `precio_por_unidad` |
| `v_disponibilidad` | Disponibilidad por ejecución | Para cada anuncio ya conocido en cada ejecución no fallida: `disponible`, `agotado` (según el sitio), `sin dato` o `no observado` (no apareció en esa ejecución; **no** se interpreta como agotado) |
| `v_resumen_ejecuciones` | Pestaña Actualizar | Cada ejecución y comercio con su estado, el total del sitio, las observaciones válidas y las rechazadas |

## Índices
`ux_obs_ejecucion_anuncio` (único), `ix_obs_ejecucion_comercio`, `ix_obs_anuncio`, `ix_obs_fecha`, `ix_obs_precio`, `ix_obscomp_ejecucion`, `ix_corresp_producto`, `ix_clasif_subcat`, `ix_clasif_marca`, `ix_clasif_categoria`, `ix_anuncios_comercio`, `ix_rechazos_ejecucion` e `ix_log_actualizacion`. Cubren las columnas que filtra la aplicación: ejecución, comercio, fecha, precio, subcategoría, marca, categoría y producto.
