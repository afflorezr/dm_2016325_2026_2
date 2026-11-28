# Diccionario de Datos — Comparador de Precios (Taller 2)

**Asignatura:** Minería de Datos (2016325) — Universidad Nacional de Colombia  
**Estudiante:** Sebastián Sepúlveda Valenzuela  
**Categoría:** Cuidado y Limpieza del Hogar  
**Comercios:** Olímpica, Jumbo, Éxito  
**Motor de Base de Datos:** SQLite 3  

---

## 1. Tablas del Sistema

### 1.1. `comercios`
Almacena los establecimientos comerciales evaluados en el sistema comparador.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `comercio_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador único interno del comercio. |
| `nombre` | `TEXT` | N/A | `UNIQUE NOT NULL` ('Éxito', 'Olímpica', 'Jumbo') | Nombre comercial oficial del establecimiento. |
| `plataforma` | `TEXT` | N/A | 'VTEX', 'VTEX FastStore' | Plataforma de comercio electrónico subyacente. |
| `url_base` | `TEXT` | N/A | URLs válidas ('https://...') | Dominio base para consultas y enlaces web. |

---

### 1.2. `ejecuciones`
Auditoría y trazabilidad de cada sesión de recolección (web scraping en vivo o modo sin conexión).

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `ejecucion_id` | `TEXT` | N/A | `PRIMARY KEY` (ej. `EXEC_20261028_...`) | Identificador único alfanumérico de la ejecución. |
| `comercio_id` | `INTEGER` | N/A | `FOREIGN KEY (comercio_id) REFERENCES comercios` | Comercio sobre el cual se ejecutó la recolección. |
| `fecha_hora_inicio` | `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Marca de tiempo exacta del inicio de la recolección. |
| `fecha_hora_fin` | `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Marca de tiempo exacta de finalización de la recolección. |
| `registros_obtenidos`| `INTEGER` | Conteos | $\ge 0$ | Cantidad de observaciones válidas procesadas. |
| `registros_con_precio`| `INTEGER` | Conteos | $\ge 0$ | Cantidad de observaciones válidas con precio $>0$. |
| `total_sitio` | `INTEGER` | Conteos | $\ge 0$ | Total de productos reportados por la cabecera `resources`. |
| `estado` | `TEXT` | N/A | `'completa'`, `'parcial'`, `'fallida'` | Estado de integridad de la captura del comercio. |
| `nota` | `TEXT` | N/A | Texto descriptivo | Justificación metodológica o causa de fallo. |

---

### 1.3. `productos`
Catálogo maestro de productos normalizados y homologados entre comercios.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `producto_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador único del producto normalizado. |
| `ean` | `TEXT` | N/A | `UNIQUE`, dígitos de 8 a 14 caracteres | Código de barras estándar internacional (GTIN/EAN). |
| `nombre_estandar` | `TEXT` | N/A | `NOT NULL`, texto | Nombre representativo estandarizado del producto. |
| `marca_estandar` | `TEXT` | N/A | Texto | Marca comercial homologada (ej. 'Ariel', 'Axion'). |
| `subcategoria_estandar`| `TEXT` | N/A | Subcategorías homologadas | Subcategoría estándar en la taxonomía unificada. |
| `variante` | `TEXT` | N/A | Texto / NULL | Fragancia o variante específica (ej. 'Limón', 'Floral'). |
| `contenido_total` | `REAL` | Cantidad | $> 0$ / NULL | Magnitud numérica del contenido neto total. |
| `unidad_base` | `TEXT` | N/A | 'ml', 'g', 'und' / NULL | Unidad base original extraída en Taller 1. |
| `unidad_normalizada` | `TEXT` | N/A | `'mL'`, `'g'`, `'unidad'` / NULL | Unidad estandarizada oficial del Taller 2. |
| `unidades_por_paquete`| `INTEGER` | Conteos | $\ge 1$ (default 1) | Número de piezas o empaques contenidos en la oferta. |
| `concentracion` | `TEXT` | N/A | Texto / NULL | Concentración química cuando aplica. |
| `es_comparable` | `INTEGER` | Booleano | `0`, `1` | 1 si el producto se homologó entre los 3 comercios. |
| `es_canasta_8` | `INTEGER` | Booleano | `0`, `1` | 1 si pertenece al grupo canónico de los 8 comparables. |

---

### 1.4. `anuncios`
Catálogo de ofertas o publicaciones individuales por comercio (nivel SKU).

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `anuncio_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador único interno del anuncio. |
| `comercio_id` | `INTEGER` | N/A | `FOREIGN KEY REFERENCES comercios` | Comercio que publica el anuncio. |
| `sku` | `TEXT` | N/A | `NOT NULL`, alfanumérico | Identificador del artículo/SKU en la tienda. |
| `ean` | `TEXT` | N/A | Dígitos GTIN / NULL | Código EAN asociado a este SKU. |
| `product_id_comercio`| `TEXT` | N/A | Numérico | ID de producto del catálogo VTEX. |
| `url` | `TEXT` | N/A | URL web completa | Enlace directo a la publicación en la tienda. |
| `nombre_original` | `TEXT` | N/A | `NOT NULL`, texto crudo | Título del producto tal como figura en el sitio. |
| `descripcion_original`| `TEXT` | N/A | Texto / NULL | Descripción cruda del producto. |
| `ficha_tecnica_original`| `TEXT` | N/A | JSON en texto / NULL | Atributos y especificaciones técnicas crudas. |
| `marca_original` | `TEXT` | N/A | Texto crudo / NULL | Marca original declarada por el comercio. |
| `categoria_original`| `TEXT` | N/A | Texto crudo | Ruta de navegación o categoría cruda del sitio. |
| `contenido_texto_original`| `TEXT` | N/A | Texto crudo | Fragmento de texto donde se detectó el contenido. |
| `nombre_estandar` | `TEXT` | N/A | Texto limpio | Nombre normalizado a nivel de anuncio. |
| `marca_estandar` | `TEXT` | N/A | Texto limpio | Marca homologada a nivel de anuncio. |
| `subcategoria_estandar`| `TEXT`| N/A | Texto limpio | Subcategoría unificada. |
| `contenido_total` | `REAL` | Cantidad | $> 0$ / NULL | Magnitud numérica de contenido calculada. |
| `unidad_base` | `TEXT` | N/A | 'ml', 'g', 'und' / NULL | Unidad base histórica. |
| `unidad_normalizada` | `TEXT` | N/A | `'mL'`, `'g'`, `'unidad'` / NULL | Unidad normalizada estándar. |
| `unidades_por_paquete`| `INTEGER` | Conteos | $\ge 1$ | Unidades de empaque. |
| `producto_id` | `INTEGER` | N/A | `FOREIGN KEY REFERENCES productos` | Vínculo al catálogo maestro normalizado. |
| `comparable` | `INTEGER` | Booleano | `0`, `1` | Indicador de comparabilidad del anuncio. |

*Restricción de unicidad:* `UNIQUE(comercio_id, sku)`.

---

### 1.5. `observaciones`
Registro temporal de precios, disponibilidad y promociones capturados por anuncio y ejecución.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `observacion_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador único de la observación. |
| `anuncio_id` | `INTEGER` | N/A | `FOREIGN KEY REFERENCES anuncios` | Anuncio observado. |
| `ejecucion_id` | `TEXT` | N/A | `FOREIGN KEY REFERENCES ejecuciones` | Ejecución en la que se recolectó. |
| `precio_actual` | `REAL` | COP | $> 0$ (o NULL únicamente si `disponibilidad = 'agotado'`) | Precio de venta vigente al consumidor. El precio solo puede ser NULL si el producto está reportado como `'agotado'` (sin oferta comercial activa en tienda). Si el producto está disponible o el precio es $\le 0$, se rechaza. |
| `precio_antes` | `REAL` | COP | $\ge 0$ / NULL | Precio de lista previo a descuentos. |
| `es_promocion` | `INTEGER` | Booleano | `0`, `1`, NULL | 1 si `precio_actual < precio_antes`. |
| `disponibilidad` | `TEXT` | N/A | `'disponible'`, `'agotado'` | Estado de inventario según el sitio web. |
| `fecha_hora_consulta`| `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Marca de tiempo exacta de la petición HTTP. |
| `descartada` | `INTEGER` | Booleano | `0`, `1` (default 0) | 1 si la observación fue excluida por auditoría. |
| `motivo_descarte`| `TEXT` | N/A | Texto explicativo / NULL | Razón de la exclusión si `descartada = 1`. |

*Restricciones de unicidad:*
- `UNIQUE(anuncio_id, fecha_hora_consulta)`
- `UNIQUE(anuncio_id, ejecucion_id)` (vía índice único `uidx_obs_anuncio_ejecucion`).

---

### 1.6. `descartados`
Registro de productos excluidos del alcance de la categoría durante la recolección.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `descarte_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador único del descarte. |
| `comercio` | `TEXT` | N/A | 'Éxito', 'Olímpica', 'Jumbo' | Comercio de origen. |
| `ejecucion_id` | `TEXT` | N/A | Alfanumérico | Ejecución donde se detectó el descarte. |
| `sku` | `TEXT` | N/A | Alfanumérico | SKU del producto descartado. |
| `nombre` | `TEXT` | N/A | Texto crudo | Nombre del producto descartado. |
| `categoria_original`| `TEXT` | N/A | Texto crudo | Categoría cruda de origen. |
| `motivo` | `TEXT` | N/A | Texto descriptivo | Regla de exclusión aplicada (ej. papel higiénico). |
| `fecha_descarte`| `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Fecha del descarte. |

---

### 1.7. `correspondencia_rechazada`
Auditoría de candidatos a producto comparable rechazados por inconsistencias entre comercios.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `rechazo_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador del rechazo de correspondencia. |
| `ean` | `TEXT` | N/A | GTIN analizado | Código de barras que no superó los criterios. |
| `nombre_referencia`| `TEXT` | N/A | Texto | Nombre de referencia en los anuncios. |
| `marca_referencia` | `TEXT` | N/A | Texto | Marca de referencia. |
| `motivo` | `TEXT` | N/A | Texto explicativo | Razón de rechazo (contenido dispar, marcas disímiles). |
| `fecha_rechazo` | `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Fecha de evaluación. |

---

### 1.8. `correcciones`
Registro auditable de modificaciones a datos existentes (correcciones del Taller 1).

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `correccion_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador de la corrección. |
| `fecha` | `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Fecha de aplicación de la corrección. |
| `tabla` | `TEXT` | N/A | Nombre de la tabla ('productos', etc.) | Tabla afectada. |
| `registro_id` | `TEXT` | N/A | Identificador del registro | ID de la fila modificada. |
| `campo` | `TEXT` | N/A | Nombre de la columna | Campo corregido. |
| `valor_anterior`| `TEXT` | N/A | Valor previo / NULL | Estado antes del cambio. |
| `valor_nuevo` | `TEXT` | N/A | Valor nuevo | Estado después del cambio. |
| `motivo` | `TEXT` | N/A | Justificación técnica | Causa o fundamento de la corrección. |

---

### 1.9. `rechazos`
Registro de registros individuales que no superan las validaciones de calidad de Pandera antes de su inserción.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `rechazo_id` | `INTEGER` | N/A | `PRIMARY KEY AUTOINCREMENT` | Identificador del rechazo. |
| `ejecucion_id` | `TEXT` | N/A | Alfanumérico | Ejecución en la que se presentó el rechazo. |
| `comercio` | `TEXT` | N/A | 'Éxito', 'Olímpica', 'Jumbo' | Comercio asociado. |
| `sku` | `TEXT` | N/A | SKU del artículo | Identificador en la tienda. |
| `datos_json` | `TEXT` | JSON | Estructura de la fila | Datos crudos del registro rechazado. |
| `regla` | `TEXT` | N/A | 'precio_no_positivo', 'precio_nulo_no_agotado', 'pandera_schema_error', 'duplicado_ejecucion', etc. | Nombre de la regla violada. |
| `motivo` | `TEXT` | N/A | Explicación detallada | Razón por la cual se bloqueó la inserción. |
| `fecha` | `TEXT` | ISO 8601 | YYYY-MM-DDTHH:MM:SS-05:00 | Momento de la validación. |

---

### 1.10. `comparables_8`
Catálogo estricto y documentado de los 8 productos de consumo masivo presentes en los tres comercios.

| Columna | Tipo SQLite | Unidad | Valores Posibles / Restricciones | Significado / Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `producto_id` | `INTEGER` | N/A | `PRIMARY KEY REFERENCES productos` | Identificador del producto en el catálogo maestro. |
| `ean` | `TEXT` | N/A | `UNIQUE NOT NULL` | Código de barras EAN exacto. |
| `nombre_referencia`| `TEXT` | N/A | Texto | Nombre unificado para presentación. |
| `marca` | `TEXT` | N/A | Texto | Marca oficial. |
| `subcategoria` | `TEXT` | N/A | Texto | Subcategoría asignada. |
| `contenido_total` | `REAL` | Cantidad | $> 0$ | Contenido neto estandarizado. |
| `unidad_normalizada`| `TEXT` | N/A | `'mL'`, `'g'`, `'unidad'` | Unidad para cálculo de precios unitarios. |

---

## 2. Vistas SQL

### 2.1. `v_observaciones`
Join plano desnormalizado de todas las observaciones con metadatos de producto, comercio y precios unitarios.
- **Columnas:** `observacion_id`, `ejecucion_id`, `comercio_id`, `comercio`, `anuncio_id`, `sku`, `ean`, `url`, `nombre_original`, `nombre`, `marca`, `subcategoria`, `contenido_total`, `unidad_normalizada`, `unidades_por_paquete`, `producto_id`, `es_comparable`, `es_canasta_8`, `precio_actual`, `precio_antes`, `es_promocion`, `disponibilidad`, `fecha_hora_consulta`, `descartada`, `motivo_descarte`, `precio_unitario`.

### 2.2. `v_ultimo_precio`
Presenta exclusivamente la observación más reciente de cada anuncio activo (`descartada = 0`), resolviendo empates por `observacion_id DESC`.
- **Columnas:** `observacion_id`, `ejecucion_id`, `comercio_id`, `comercio`, `anuncio_id`, `sku`, `ean`, `url`, `nombre`, `marca`, `subcategoria`, `contenido_total`, `unidad_normalizada`, `unidades_por_paquete`, `producto_id`, `es_comparable`, `es_canasta_8`, `precio_actual`, `precio_antes`, `es_promocion`, `disponibilidad`, `fecha_hora_consulta`, `precio_unitario`.

### 2.3. `v_comparables`
Vista enfocada en los 8 productos comparables presentes en los tres comercios, calculando el precio unitario exacto por `mL`, `g` o `unidad`.
- **Columnas:** `observacion_id`, `ejecucion_id`, `comercio_id`, `comercio`, `producto_id`, `ean`, `nombre`, `marca`, `subcategoria`, `contenido_total`, `unidad_normalizada`, `anuncio_id`, `sku`, `url`, `precio_actual`, `precio_antes`, `es_promocion`, `disponibilidad`, `fecha_hora_consulta`, `precio_unitario`.

### 2.4. `v_cambios_precio`
Calcula la evolución y variaciones de precio (en COP y porcentaje) para el mismo anuncio en el mismo comercio a través de funciones de ventana `LAG()`.
- **Columnas:** `observacion_id`, `anuncio_id`, `comercio_id`, `comercio`, `sku`, `ean`, `url`, `nombre`, `marca`, `subcategoria`, `contenido_total`, `unidad_normalizada`, `es_comparable`, `es_canasta_8`, `ejecucion_anterior_id`, `ejecucion_actual_id`, `precio_anterior`, `precio_actual`, `cambio_cop`, `cambio_porcentaje`, `tipo_cambio` ('subida', 'bajada', 'sin_cambio', 'nuevo'), `fecha_anterior`, `fecha_actual`, `descartada`.

### 2.5. `v_disponibilidad`
Cruza el producto cartesiano de los 8 productos comparables contra todas las ejecuciones y comercios. Si un producto no fue capturado en una ejecución dada, deriva el estado `'no_observado'` sin insertar filas artificiales en la base de datos.
- **Columnas:** `ejecucion_id`, `comercio_id`, `comercio`, `fecha_hora_inicio`, `producto_id`, `ean`, `nombre`, `marca`, `observacion_id`, `precio_actual`, `estado_disponibilidad` ('disponible', 'agotado', 'no_observado').

### 2.6. `v_ejecuciones_resumen`
Resumen de control por ejecución: total capturado, registros con precio, tamaño oficial del catálogo y cobertura de los 8 comparables.
- **Columnas:** `ejecucion_id`, `comercio_id`, `comercio`, `fecha_hora_inicio`, `fecha_hora_fin`, `registros_obtenidos`, `registros_con_precio`, `total_sitio`, `estado`, `nota`, `anuncios_observados`, `comparables_8_observados`.
