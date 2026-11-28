# Diccionario de datos

Este documento describe la estructura de la base de datos `comparador_precios.sqlite`,
incluyendo tablas, vistas y el significado de cada columna.

## Tablas Base

### 1. Tabla `observaciones`
Registra cada producto capturado en cada ejecución de scraping. Es la tabla principal del sistema.

| Columna | Tipo | Descripción | Valores posibles |
| :--- | :--- | :--- | :--- |
| `id_obs` | INTEGER | Identificador único de la observación. | Autoincremental (1, 2, 3...) |
| `id_ejecucion` | TEXT | Identificador de la ejecución (fecha y hora). | Formato `YYYYMMDDTHHMMSS` |
| `comercio` | TEXT | Nombre del comercio. | `D1`, `Carulla`, `Olímpica`, `Éxito` |
| `sku` | TEXT | Identificador interno del producto en el comercio. | Texto numérico o alfanumérico |
| `ean` | TEXT | Código de barras internacional. | Texto numérico (13 dígitos) o NULL |
| `nombre_original` | TEXT | Nombre del producto tal como aparece en el sitio. | Texto libre |
| `marca` | TEXT | Marca del producto. | Texto libre |
| `subcategoria` | TEXT | Categoría del producto. | Texto libre |
| `descripcion_original`| TEXT | Descripción larga del producto. | Texto libre o NULL |
| `precio` | REAL | Precio capturado en COP. | Número mayor a 0 o NULL |
| `precio_antes` | REAL | Precio anterior si está en promoción. | Número mayor a 0 o NULL |
| `promocion` | INTEGER | Indica si el producto está en promoción. | `1` (Sí) o `0` (No) |
| `disponible` | INTEGER | Indica si el producto está disponible. | `1` (Sí) o `0` (No) |
| `url` | TEXT | Enlace directo al producto en el sitio. | URL válida |
| `fecha_hora_consulta` | TEXT | Fecha y hora exacta de la consulta. | Formato ISO 8601 |
| `descartada` | INTEGER | Indica si la observación fue descartada (ej. datos de Éxito). | `1` (Sí) o `0` (No) |

### 2. Tabla `ejecuciones`
Registra el historial de cada vez que se corre el scraper.

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_ejecucion` | TEXT | Identificador único de la ejecución. |
| `comercio` | TEXT | Comercio al que pertenece la ejecución. |
| `inicio` | TEXT | Fecha y hora de inicio. |
| `fin` | TEXT | Fecha y hora de finalización. |
| `modo` | TEXT | Indica si fue `en_linea` o `sin_conexion`. |
| `n_registros` | INTEGER | Cantidad de registros capturados. |
| `n_esperado` | INTEGER | Cantidad de registros esperados según el sitio. |
| `estado` | TEXT | Estado de la ejecución: `completa`, `parcial` o `fallida`. |
| `detalle` | TEXT | Mensaje de error si la ejecución falló. |

### 3. Tabla `productos`
Define los productos comparables (canasta) con su información estandarizada.

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_producto` | TEXT | Identificador único del producto comparable (ej. `P01`). |
| `ean` | TEXT | Código de barras del producto. |
| `nombre_std` | TEXT | Nombre estandarizado para mostrar en la app. |
| `marca_std` | TEXT | Marca estandarizada. |
| `subcategoria_std` | TEXT | Subcategoría estandarizada. |
| `contenido` | REAL | Cantidad total del empaque (ej. 128 metros). |
| `unidad` | TEXT | Unidad de medida (`m`, `servilleta`, `hoja`, `vaso`, etc.). |
| `n_unidades` | INTEGER | Número de unidades del empaque (ej. 4 rollos). |

### 4. Tabla `correspondencia`
Une los productos estandarizados con los SKUs reales de cada comercio.

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_producto` | TEXT | Identificador del producto comparable (FK a `productos`). |
| `comercio` | TEXT | Nombre del comercio. |
| `sku` | TEXT | SKU del producto en ese comercio específico. |
| `verificado` | INTEGER | Indica si la correspondencia fue verificada manualmente. |
| `nota` | TEXT | Nota explicativa (ej. si el producto es un equivalente). |

### 5. Tabla `correcciones`
Registra los cambios y correcciones realizadas en la base de datos.

| Columna | Tipo | Descripción |
| :--- | :--- | :--- |
| `id_correccion` | INTEGER | Identificador único de la corrección. |
| `fecha` | TEXT | Fecha y hora en que se realizó la corrección. |
| `registro` | TEXT | Registro afectado (ej. \"Comercio\"). |
| `valor_anterior` | TEXT | Valor que tenía antes de la corrección. |
| `valor_nuevo` | TEXT | Valor nuevo asignado. |
| `motivo` | TEXT | Explicación del porqué de la corrección. |
