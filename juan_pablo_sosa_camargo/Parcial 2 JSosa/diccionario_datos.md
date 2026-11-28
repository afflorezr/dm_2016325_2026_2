# Diccionario de datos — `comparador_precios.sqlite`

Base del comparador de precios (Taller 1 corregido + Taller 2).
Categoría: **Cuidado del bebé / higiene** (jabón, champú, loción, aceite,
crema hidratante, colonia infantil). Comercios: **Farmatodo, Jumbo, Éxito**.
Moneda: **COP**. Zona horaria de `fecha_consulta`: **America/Bogota (UTC-05:00)**.

---

## Tablas

### `observaciones`
Una fila por anuncio observado en un comercio en una ejecución.
Restricción de unicidad: `UNIQUE (comercio, url, fecha_consulta)` — la misma
URL no se inserta dos veces en la misma ejecución.

| Columna | Tipo | Unidad / valores posibles | Significado |
|---|---|---|---|
| `id` | INTEGER PK | — | Identificador interno de la fila |
| `comercio` | TEXT | `Farmatodo`, `Jumbo`, `Éxito` | Comercio donde se observó el precio |
| `producto` | TEXT | — | Nombre del anuncio tal como aparece en el sitio |
| `texto_original` | TEXT | — | Texto completo del anuncio (nombre, marca, precio unitario, banda de oferta); sin limpiar |
| `marca` | TEXT | ej. `Johnson's`, `Dove` | Marca estandarizada (versión normalizada; el texto crudo queda en `texto_original`) |
| `subcategoria` | TEXT | `Jabón`, `Champú`, `Loción`, `Aceite`, `Crema hidratante`, `Colonia` | Subcategoría estandarizada; `NULL` = fuera de la categoría |
| `contenido_valor` | REAL | mL, g o unidades | Contenido total de la presentación (`NULL` si no se pudo leer) |
| `contenido_unidad` | TEXT | `ml`, `g`, `unidad` | Unidad del contenido; `NULL` si no aplica |
| `precio_cop` | REAL | COP | Precio observado; **> 0** (CHECK) |
| `precio_antes` | REAL | COP | Precio antes del descuento si el sitio lo muestra; `NULL` si no hay promo |
| `en_promocion` | INTEGER | `0`, `1` | 1 si el sitio marca precio promocional |
| `sku` | TEXT | — | Identificador interno del producto en el comercio; `NULL` si el sitio no lo expone |
| `disponibilidad` | TEXT | `disponible`, `agotado`, `NULL` | Estado según el sitio; `NULL` = no determinado. Un producto **no observado** no es `agotado`: simplemente no tiene fila en esta ejecución |
| `url` | TEXT | URL | Página de la que se extrajo el precio |
| `fecha_consulta` | TEXT | ISO 8601 con offset `-05:00` | Momento de la consulta; obligatoria |
| `id_ejecucion` | TEXT | `ejec_AAAAMMDDTHHMMSS` | Ejecución a la que pertenece la observación |
| `comparable` | INTEGER | `0`, `1` | 1 si pertenece a los productos comparables entre comercios |
| `id_comun` | TEXT | ej. `johnson-champu-400-ml-manzanilla` | Identificador común de la misma presentación en todos los comercios; `NULL` si no es comparable |

### `ejecuciones`
Una fila por ejecución × comercio. PK: `(id_ejecucion, comercio)`.

| Columna | Tipo | Valores posibles | Significado |
|---|---|---|---|
| `id_ejecucion` | TEXT | `ejec_…` | Identificador de la corrida |
| `comercio` | TEXT | `Farmatodo`, `Jumbo`, `Éxito` | Comercio de la fila |
| `modo` | TEXT | `online`, `offline` | Cómo se obtuvieron los datos |
| `estado` | TEXT | `exitosa`, `parcial`, `fallida` | Estado de ese comercio en la ejecución |
| `motivo` | TEXT | — | Detalle de parcialidad/falla; `NULL` si exitosa |
| `fecha_consulta` | TEXT | ISO 8601 | Hora de inicio de la ejecución |
| `origen_raw` | TEXT | `ejec_…` | Ejecución de origen de las copias crudas (offline) |
| `tarjetas_leidas` | INTEGER | ≥ 0 | Tarjetas de producto leídas en HTML |
| `recolectados` | INTEGER | ≥ 0 | Filas que superaron la validación |
| `insertados` | INTEGER | ≥ 0 | Filas nuevas insertadas |
| `rechazados` | INTEGER | ≥ 0 | Filas descartadas por validación |
| `nuevos` | INTEGER | ≥ 0 | URLs nunca vistas antes en ese comercio |
| `cambios_precio` | INTEGER | ≥ 0 | Anuncios con precio distinto al anterior |
| `no_observados` | INTEGER | ≥ 0 | URLs de la ejecución previa que no aparecieron |

### `correcciones`
Registro de correcciones sobre datos previos (Taller 1 → Taller 2). **No se
borran observaciones: se corrigen campos y se documenta aquí.**

| Columna | Tipo | Significado |
|---|---|---|
| `id` | INTEGER PK | — |
| `fecha` | TEXT ISO 8601 | Momento de la corrección |
| `tabla` | TEXT | Tabla afectada (p. ej. `observaciones`) |
| `registro` | TEXT | `id` de la fila afectada o `ESQUEMA` para cambios de estructura |
| `campo` | TEXT | Columna corregida |
| `valor_anterior` | TEXT | Valor previo |
| `valor_nuevo` | TEXT | Valor corregido (`NULL` escrito como texto `NULL`) |
| `motivo` | TEXT | Justificación de la corrección |

### `observaciones_rechazadas`
Toda fila que **no superó** la validación queda aquí con su motivo
(no se inserta en `observaciones`).

| Columna | Tipo | Significado |
|---|---|---|
| `id` | INTEGER PK | — |
| `id_ejecucion` | TEXT | Ejecución que intentó insertarla |
| `comercio`, `producto`, `url`, `fecha_consulta` | TEXT | Datos de la fila rechazada |
| `motivo` | TEXT | Regla(s) que fallaron (p. ej. `precio_positivo`) |
| `fecha_registro` | TEXT ISO 8601 | Momento del registro |
| `datos_json` | TEXT | Fila completa en JSON |

---

## Vistas (las usa la aplicación directamente)

### `v_ultimo_precio`
Última observación por `comercio × url` (ventana `ROW_NUMBER()`). Es la base
de filtros, indicadores y gráficos: un anuncio = una fila con el precio más
reciente.

*Columnas:* las mismas que `observaciones`.

### `v_cambios_precio`
Cada observación comparada con la **inmediatamente anterior** del mismo
`comercio × url` (`LAG`). Filas solo cuando hubo cambio.

| Columna | Significado |
|---|---|
| `variacion_cop` | `precio_actual − precio_anterior` |
| `variacion_pct` | Variación en porcentaje |
| `fecha_anterior`, `fecha_actual` | Ambas ejecuciones/consultas |
| `id_comun` | Comparable asociado (si lo es) |

### `v_comparables`
Observaciones con `comparable = 1` (vista de `v_ultimo_precio`), con
`precio_por_100` = `100 × precio / contenido` (no mezclar unidades: filtrar
por `contenido_unidad`).

---

## Índices

| Índice | Columnas | Uso |
|---|---|---|
| `ix_obs_url` | `comercio, url, fecha_consulta` | Última observación por anuncio; unicidad |
| `ix_obs_comercio_fecha` | `comercio, fecha_consulta` | Filtros por comercio y período |
| `ix_obs_fecha` | `fecha_consulta` | Rango de fechas |
| `ix_obs_subcategoria` | `subcategoria` | Filtro de subcategoría |
| `ix_obs_marca` | `marca` | Filtro de marca |
| `ix_obs_comparable` | `comparable, id_comun` | Comparables y canasta |
| `ix_obs_promo` | `en_promocion` | Filtro de promociones |
| `ix_ejec_fecha` | `fecha_consulta` (ejecuciones) | Última ejecución |

---

## Correspondencia de productos comparables

`comparable = 1` e `id_comun` se calculan con reglas documentadas
(`productos_comparables()` en `scraper.R`):

1. Misma **marca canónica**, **subcategoría**, **unidad** y **contenido**.
2. Similitud de Jaccard ≥ 0,25 sobre los tokens del nombre (sin marca,
   números ni palabras de categoría).
3. **Variante compatible**: los tokens de variante (p. ej. `original`,
   `manzanilla`, `avena`, `antes`, `dormir`) deben intersectar, salvo que una
   variante esté vacía. Evita emparejar productos distintos.
4. Emparejamiento 1 a 1 (mejor par) y grupos conexos; solo grupos presentes
   en los **3 comercios**.
5. `id_comun` = `marca-subcategoría-contenido-unidad-variante` (estable entre
   ejecuciones).
