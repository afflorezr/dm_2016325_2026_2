# Diccionario de Datos — `comparador_precios.sqlite`

Base de datos SQLite del comparador de precios de medicamentos y productos de salud digestiva en Colombia (**Colsubsidio**, **Farmatodo** y **Cruz Verde**). Todos los valores monetarios están expresados en **pesos colombianos (COP)**.

---

## 1. Tablas

### `ejecuciones`
Registro de auditoría de cada corrida del módulo de extracción (`scraper.R`) por comercio.
* **Clave primaria:** `(id_ejecucion, comercio)`

| Columna | Tipo | Unidad / Formato | Valores posibles / Descripción |
| :--- | :--- | :--- | :--- |
| `id_ejecucion` | `TEXT` | `YYYYMMDDTHHMMSS` | Identificador único de la corrida en hora de Colombia (`America/Bogota`). |
| `comercio` | `TEXT` | Texto | `'Colsubsidio'`, `'Farmatodo'`, `'Cruz Verde'`. |
| `inicio` | `TEXT` | ISO 8601 | Fecha y hora de inicio de la extracción del comercio. |
| `fin` | `TEXT` | ISO 8601 | Fecha y hora de finalización de la extracción del comercio. |
| `modo` | `TEXT` | Texto | `'en_linea'` (scraping web) o `'sin_conexion'` (reprocesado desde `raw/`). |
| `n_registros` | `INTEGER` | Conteo | Número de observaciones válidas insertadas/procesadas en esa corrida. |
| `n_esperado` | `INTEGER` | Conteo | Total de productos reportado por la API del sitio (`NULL` si el sitio no lo expone). |
| `estado` | `TEXT` | Texto | `'completa'`, `'parcial'`, `'fallida'`. |
| `detalle` | `TEXT` | Texto | Mensaje de error o advertencias de validación (`NULL` si no hubo incidencias). |

### `observaciones`
Registros individuales de productos recolectados en cada ejecución.
* **Clave primaria:** `id_obs`
* **Restricción de unicidad:** `UNIQUE (comercio, sku, fecha_hora_consulta)`

| Columna | Tipo | Unidad / Formato | Valores posibles / Descripción |
| :--- | :--- | :--- | :--- |
| `id_obs` | `INTEGER` | Autoincremental | Identificador interno de la observación. |
| `id_ejecucion` | `TEXT` | `YYYYMMDDTHHMMSS` | Referencia a `ejecuciones.id_ejecucion`. |
| `comercio` | `TEXT` | Texto | Nombre del comercio (`'Colsubsidio'`, `'Farmatodo'`, `'Cruz Verde'`). |
| `sku` | `TEXT` | Texto | Código único del producto dentro del comercio. |
| `nombre_original` | `TEXT` | Texto | Nombre del producto tal como aparece publicado en el sitio web. |
| `marca` | `TEXT` | Texto | Marca o laboratorio reportado por el sitio. |
| `subcategoria` | `TEXT` | Texto | Subcategoría reportada por el comercio (`NULL` si no la expone en listado). |
| `descripcion_original` | `TEXT` | Texto | Texto descriptivo completo capturado de la API o tarjeta HTML. |
| `precio` | `REAL` | `COP` | Precio vigente de venta al público (`> 0`). |
| `precio_antes` | `REAL` | `COP` | Precio regular tachado cuando el producto está en promoción (`NULL` si no aplica). |
| `promocion` | `INTEGER` | Booleano (`0`/`1`) | `1` si `precio_antes > precio`, `0` en caso contrario. |
| `disponible` | `INTEGER` | Booleano (`0`/`1`) | `1` disponible, `0` agotado, `NULL` cuando el listado no reporta inventario. |
| `estado_disponibilidad` | `TEXT` | Texto | `'disponible'`, `'agotado'` o `NULL` (sin dato en el sitio). El estado "no observado" se deriva en `v_no_observados`. |
| `descartada` | `INTEGER` | Booleano (`0`/`1`) | `0` observación activa; `1` marcada como descartada por auditoría sin borrar el registro. |
| `url` | `TEXT` | URL | Enlace directo al producto o categoría consultada. |
| `fecha_hora_consulta` | `TEXT` | ISO 8601 | Marca temporal exacta de la consulta (`America/Bogota`). |

### `productos`
Catálogo maestro de las 12 presentaciones comparables estandarizadas (`P01`–`P12`).

| Columna | Tipo | Unidad / Formato | Valores posibles / Descripción |
| :--- | :--- | :--- | :--- |
| `id_producto` | `TEXT` | Código (`P01`–`P12`) | Clave primaria del producto estandarizado. |
| `nombre_std` | `TEXT` | Texto | Nombre homogéneo de la presentación comparable. |
| `marca_std` | `TEXT` | Texto | Marca estandarizada. |
| `subcategoria_std` | `TEXT` | Texto | Subcategoría terapéutica homogénea. |
| `contenido` | `REAL` | Numérico | Cantidad nominal de la presentación original. |
| `unidad` | `TEXT` | Texto | Unidad específica de la presentación (`'ml'`, `'g'`, `'gragea'`, `'tableta'`, `'sachet'`). |
| `n_unidades` | `INTEGER` | Conteo | Número de unidades por empaque. |
| `contenido_total` | `REAL` | Numérico | Contenido total normalizado para el cálculo de precio unitario. |
| `unidad_norm` | `TEXT` | Texto | Unidad normalizada estricta: `'mL'`, `'g'` o `'unidad'`. |

### `correspondencia`
Tabla puente que vincula cada SKU de cada comercio con su `id_producto` comparable.
* **Clave primaria:** `(comercio, sku)`

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_producto` | `TEXT` | Clave foránea hacia `productos.id_producto`. |
| `comercio` | `TEXT` | Comercio al que pertenece el SKU. |
| `sku` | `TEXT` | Identificador del producto en el comercio. |
| `verificado` | `INTEGER` | `1` si la equivalencia de presentación y principio activo fue verificada manualmente. |
| `nota` | `TEXT` | Observaciones de verificación (EAN, gramaje o presentación en web). |

### `correcciones`
Bitácora de auditoría sobre ajustes manuales realizados a registros históricos (Módulo 1.2).

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_correccion` | `INTEGER` | Clave primaria autoincremental. |
| `fecha` | `TEXT` | Fecha y hora ISO 8601 de la corrección. |
| `tabla` | `TEXT` | Nombre de la tabla afectada. |
| `registro` | `TEXT` | Identificador del registro modificado. |
| `campo` | `TEXT` | Nombre de la columna ajustada. |
| `valor_anterior` | `TEXT` | Valor previo al ajuste. |
| `valor_nuevo` | `TEXT` | Valor asignado tras la corrección. |
| `motivo` | `TEXT` | Justificación documentada del cambio. |

### `observaciones_rechazadas`
Registro de filas descartadas por las reglas de validación (`validacion.R`) antes de entrar a `observaciones`.

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_rechazo` | `INTEGER` | Clave primaria autoincremental. |
| `id_ejecucion` | `TEXT` | Identificador de la ejecución donde ocurrió el rechazo. |
| `comercio` | `TEXT` | Comercio origen del registro. |
| `sku` | `TEXT` | SKU del registro rechazado (si existía). |
| `motivo` | `TEXT` | Regla incumplida (precio $\le 0$, URL nula, duplicado, etc.). |
| `datos_json` | `TEXT` | Objeto JSON con todos los campos crudos de la fila rechazada. |
| `fecha` | `TEXT` | Fecha y hora ISO 8601 del rechazo. |

---

## 2. Vistas SQL

1. **`v_ultimo_precio`**: Devuelve la observación activa (`descartada = 0`) más reciente por cada par `(comercio, sku)`, enriquecida con `id_producto`, `comparable`, `contenido_total`, `unidad_norm` y `precio_unitario` (`COP / unidad_norm`).
2. **`v_cambios_precio`**: Calcula mediante funciones de ventana (`LAG`) el precio anterior, la ejecución anterior, la diferencia absoluta (`cambio_cop`) y la variación porcentual (`cambio_pct`) para cada observación consecutiva de un mismo comercio y SKU.
3. **`v_comparables`**: Filtra exclusivamente las observaciones vinculadas a los 12 productos estandarizados (`P01`–`P12`), calculando `precio_unitario = ROUND(precio / contenido_total, 2)`.
4. **`v_no_observados`**: Identifica anuncios (`comercio`, `sku`, `nombre_original`) que fueron capturados en ejecuciones anteriores pero estuvieron ausentes en la última ejecución registrada de su comercio.