# Diccionario de datos · `comparador_precios.sqlite`

Base SQLite del comparador de bebidas (Taller 1 → Taller 2). Describe cada tabla, vista y columna: significado, tipo, unidad y valores posibles.

## 1. Convenciones

| Tema | Convención |
|----|----|
| Moneda | COP (pesos colombianos), enteros o decimales, siempre `> 0` en `precio_cop` |
| Volumen | **mL** (contenido total del paquete); el precio por litro se expresa en COP/L |
| Fechas | ISO 8601 con zona `America/Bogota`: `2026-11-08T17:45:07-05:00` |
| Dato ausente | `NULL`. Nunca se calcula ni se imputa para reemplazar un dato no extraído |
| Corrida | `id_corrida`, formato `AAAAMMDD-HHMMSS`; es una recolección completa (varios comercios) |
| Ejecución | `id_ejecucion = <id_corrida>_<carpeta comercio>`; una por comercio y corrida. Los reprocesos offline terminan en `_reproc` |
| Booleanos | `INTEGER` 0/1 |

### Claves y su forma

| Clave | Ejemplo | Estabilidad |
|----|----|----|
| `id_corrida` | `20261110-141724` | Única por corrida |
| `id_ejecucion` | `20261110-141724_exito` | Única por comercio y corrida |
| `sku_comercio` | `EXI-1234567`, `CAR-…`, `PSM-…`, `SCO-…` | Estable dentro de un comercio (prefijo de comercio + id del anuncio) |
| `id_producto_comun` | `PROD_COM_07` | **Se reasigna en cada corrida**; no sirve para unir corridas |
| `clave_producto` | `COCA-COLA\|Gaseosas\|BASE\|6000\|2` | **Estable entre corridas**: `marca\|subcategoría\|variante\|mL totales\|unidades` |

**Valores de `variante`** (dentro de `clave_producto`): `BASE`, `SIN_AZUCAR`, `SIN_GAS`, `CON_GAS`, `MIXTO` (pack con sabores mezclados) o uno o varios sabores unidos con `+` (p. ej. `NARANJA`, `SANDIA+SODA`, `SIN_AZUCAR+UVA`).

## 2. Relaciones

``` text
ejecuciones (id_ejecucion) 1 ──< N observaciones (id_ejecucion)
ejecuciones (id_ejecucion) 1 ──< N descartes
ejecuciones (id_ejecucion) 1 ──< N cobertura_sitio
observaciones (id_obs)     1 ──< 1 obs_descartadas        (opcional, marca a posteriori)
observaciones (id_obs)     1 ──< N correcciones           (id_registro, sin FK declarada)
productos_comunes (id_corrida, id_producto_comun) 1 ──< N observaciones
        (vía observaciones.id_producto_comun y la corrida de su ejecución)
validaciones (id_ejecucion = id_corrida) N ── 1 corrida
```

## 3. Tablas

### 3.1 `ejecuciones` · auditoría por comercio y corrida

| Columna | Tipo | Significado / valores |
|----|----|----|
| `id_ejecucion` | TEXT (PK) | `<id_corrida>_<carpeta comercio>`; reprocesos offline: `…_reproc` |
| `id_corrida` | TEXT | Identificador de la corrida completa |
| `comercio` | TEXT | Éxito, Carulla, PriceSmart, Supermercado Comunal |
| `fecha_inicio`, `fecha_fin` | TEXT | Inicio y fin de la extracción de ese comercio |
| `modo` | TEXT | `online` (scraping real) · `offline` (reproceso de `raw/`) |
| `n_registros` | INTEGER | Observaciones válidas insertadas |
| `n_descartados` | INTEGER | Observaciones rechazadas |
| `estado` | TEXT | `en_curso`, `completa`, `parcial` (hubo errores), `fallida` |
| `detalle` | TEXT | Errores resumidos (hasta 10, separados por `\|\|`); NULL si no hubo |

### 3.2 `observaciones` · un precio de un anuncio en un momento (núcleo)

| Columna | Tipo | Unidad | Significado / valores |
|----|----|----|----|
| `id_obs` | INTEGER (PK) | – | Autoincremental |
| `id_ejecucion` | TEXT (FK) | – | Ejecución que la produjo → trazabilidad |
| `comercio` | TEXT | – | Comercio |
| `fecha_hora_consulta` | TEXT | ISO 8601 | Momento exacto de la captura |
| `sku_comercio` | TEXT | – | Identificador del anuncio en el comercio |
| `sku_origen` | TEXT | – | De dónde salió el SKU: `atributo`, `url`, `hash_nombre` |
| `producto_raw` | TEXT | – | Nombre tal como lo muestra el sitio |
| `texto_original_anuncio` | TEXT | – | Texto completo (nombre + descripción + ficha), hasta 3.000 caracteres |
| `marca_raw` | TEXT | – | Marca del sitio; NULL si no es confiable |
| `marca_estandarizada` | TEXT | – | Marca normalizada (p. ej. `COCA-COLA`, `POSTOBON`); NULL si no se identificó |
| `subcategoria` | TEXT | – | Gaseosas, Jugos, Agua, Té preparado, Café preparado, Energizantes, Sin categorizar |
| `presentacion_raw` | TEXT | – | `NxVml`: unidades × mL por unidad (p. ej. `2x3000ml`) |
| `unidades` | INTEGER | und | Unidades del paquete |
| `volumen_unit_ml` | REAL | mL | mL por unidad |
| `contenido_total_ml` | REAL | mL | Contenido total del paquete |
| `unidad_medida` | TEXT | – | Unidad normalizada (`ml`) |
| `precio_cop` | REAL | COP | Precio pagado, `> 0` (CHECK) |
| `precio_lista_cop` | REAL | COP | Precio tachado; NULL si no hay descuento (no se inventa) |
| `es_promocion` | INTEGER | 0/1 | 1 si hay precio de lista mayor al precio pagado |
| `disponibilidad` | TEXT | – | `disponible` · `agotado` (el sitio lo indica) · `no_observado` (sin evidencia; **no** equivale a agotado) |
| `precio_por_litro` | REAL | COP/L | Calculado en la extracción: `precio_cop / (contenido_total_ml / 1000)` |
| `url_extraccion` | TEXT | – | Página consultada |
| `url_producto` | TEXT | – | Enlace del anuncio |
| `url_imagen` | TEXT | – | Imagen del producto; NULL si no hay |
| `archivo_raw` | TEXT | – | Copia cruda `.html.gz` en `raw/` que originó la fila |
| `termino_busqueda` | TEXT | – | Término que llevó al anuncio |
| `comparable` | INTEGER | 0/1 | 1 si es la observación representativa de un producto comparable |
| `id_producto_comun` | TEXT | – | `PROD_COM_nn`; NULL si no es comparable |

**Restricciones:** `UNIQUE(comercio, sku_comercio, fecha_hora_consulta)` y `UNIQUE(id_ejecucion, sku_comercio)` impiden insertar dos veces la misma observación. `precio_cop > 0`. `disponibilidad` solo admite los tres valores indicados.

### 3.3 `productos_comunes` · catálogo de productos comparables por corrida

| Columna | Tipo | Unidad | Significado |
|----|----|----|----|
| `id_corrida` | TEXT (PK) | – | Corrida a la que pertenece |
| `id_producto_comun` | TEXT (PK) | – | `PROD_COM_nn` dentro de esa corrida |
| `clave_producto` | TEXT | – | `marca\|subcategoría\|variante\|mL\|unidades`; estable entre corridas |
| `marca` | TEXT | – | Marca estandarizada |
| `subcategoria` | TEXT | – | Subcategoría |
| `variante` | TEXT | – | Ver valores en §1 |
| `contenido_total_ml` | REAL | mL | Contenido total |
| `unidades` | INTEGER | und | Unidades del paquete |
| `n_comercios` | INTEGER | – | Comercios del trío donde se encontró |
| `lista_comercios` | TEXT | – | Comercios separados por `\|` |

### 3.4 `descartes` · observaciones rechazadas (nunca entran a `observaciones`)

| Columna | Tipo | Significado |
|----|----|----|
| `id_descarte` | INTEGER (PK) | Autoincremental |
| `id_ejecucion` | TEXT (FK) | Ejecución |
| `comercio`, `fecha_hora_consulta`, `producto_raw` | TEXT | Identificación de lo rechazado |
| `motivo` | TEXT | Ver tabla de motivos |
| `detalle` | TEXT | Dato que explica el rechazo (precio, ppl, fuente del parseo) |
| `archivo_raw` | TEXT | Copia cruda de origen |

| Motivo | Significado |
|----|----|
| `fuera_de_categoria`, `fuera_de_categoria_url`, `fuera_de_seccion_bebida` | No es bebida no alcohólica (nombre, URL o breadcrumb) |
| `sin_volumen_liquido` | No se pudo determinar el contenido en mL |
| `sin_precio`, `sin_nombre` | Falta el dato esencial |
| `precio_fuera_de_rango` | Precio fuera de 100–3.000.000 COP |
| `precio_por_litro_implausible` | Precio por litro fuera de 300–80.000 COP/L |
| `validacion_precio`, `validacion_comercio`, `validacion_url`, `validacion_fecha`, `validacion_sku`, `validacion_duplicado`, `validacion_disponibilidad` | Reglas de validación previas a la inserción |

### 3.5 `cobertura_sitio` · lo que reporta el sitio vs. lo extraído

| Columna | Tipo | Significado |
|----|----|----|
| `id_cobertura` | INTEGER (PK) | Autoincremental |
| `id_ejecucion` | TEXT (FK) | Ejecución |
| `comercio`, `termino` | TEXT | Comercio y término de búsqueda o sección |
| `tipo` | TEXT | `listado` (página de resultados) · `producto` (ficha) |
| `url`, `fecha_hora`, `archivo_raw` | TEXT | Origen y copia cruda |
| `total_sitio` | INTEGER | Total de resultados que muestra el sitio; NULL si no lo muestra |
| `n_tarjetas` | INTEGER | Enlaces de producto detectados |
| `n_validos`, `n_descartes` | INTEGER | Resultado del procesamiento de la ficha |

### 3.6 `correcciones` · auditoría de cambios a la entrega del Taller 1

| Columna | Tipo | Significado |
|----|----|----|
| `id_correccion` | INTEGER (PK) | Autoincremental |
| `fecha` | TEXT | Fecha y hora de la corrección (ISO 8601 con `-05:00`) |
| `tabla` | TEXT | Tabla afectada (`observaciones`) |
| `id_registro` | TEXT | `id_obs` afectado |
| `campo` | TEXT | Campo corregido (`comparable`), o `descartada` si se marcó como descartada |
| `valor_anterior`, `valor_nuevo` | TEXT | Antes y después |
| `motivo` | TEXT | Por qué se corrigió |

**Correcciones registradas del emparejamiento erróneo** (multipack de Comunal emparejado con una botella única de 3 L):

| Corrida           | `id_obs`         | Campo        | Anterior → nuevo |
|-------------------|------------------|--------------|------------------|
| `20261108-174507` | 33, 528, 1116    | `comparable` | 1 → 0            |
| `20261110-141724` | 1197, 1667, 2257 | `comparable` | 1 → 0            |

### 3.7 `obs_descartadas` · observaciones descartadas a posteriori

| Columna  | Tipo         | Significado            |
|----------|--------------|------------------------|
| `id_obs` | INTEGER (PK) | Observación descartada |
| `fecha`  | TEXT         | Cuándo se descartó     |
| `motivo` | TEXT         | Por qué                |

La observación **permanece** en `observaciones`; las vistas la excluyen.

### 3.8 `validaciones` · reglas de lote tras cada actualización

| Columna | Tipo | Significado |
|----|----|----|
| `id_validacion` | INTEGER (PK) | Autoincremental |
| `id_ejecucion` | TEXT | Aquí guarda el **`id_corrida`** (la validación es de la corrida completa) |
| `fecha_hora` | TEXT | Cuándo se evaluó |
| `regla` | TEXT | Precio \> 0, campos presentes, sin duplicados, ≥ 8 comparables por comercio del trío |
| `n_evaluadas`, `n_fallidas` | INTEGER | Filas evaluadas y fallidas |
| `resultado` | TEXT | `ok` · `falla` · `omitida` |
| `detalle` | TEXT | Explicación de la falla u omisión |

### 3.9 `meta_app` · metadatos

| Columna | Tipo      | Significado                        |
|---------|-----------|------------------------------------|
| `clave` | TEXT (PK) | Nombre del metadato                |
| `valor` | TEXT      | Valor (p. ej. versión del esquema) |

## 4. Vistas (las usa la aplicación directamente)

| Vista | Qué devuelve | Columnas destacadas |
|----|----|----|
| `v_corridas` | Una fila por corrida en línea (excluye reprocesos) | `id_corrida`, `fecha_hora`, `fecha`, `n_comercios`, `n_obs`, `estado` (`completa`/`parcial`/`fallida`) |
| `v_ejecuciones_resumen` | Auditoría: registrado vs. guardado | `registros_registrados`, `observaciones_reales` |
| `v_obs_validas` | Observaciones vigentes (sin las descartadas) + derivados | Todas las de `observaciones` + `id_corrida`, `volumen_ml` (mL), `unidad_base` (`mL`), `precio_por_ml` (COP/mL), `precio_por_l` (COP/L) |
| `v_ultimo_precio` | Último precio de cada anuncio | `en_ultima_corrida` (1/0), `rn` |
| `v_precios_actuales` | Foto de la corrida más reciente | Igual a `v_obs_validas` filtrada |
| `v_cambios_precio` | Cambio frente a la observación anterior del mismo anuncio | `precio_anterior`, `delta_cop`, `delta_pct`, `sentido` (`nuevo`/`sube`/`baja`/`igual`) |
| `v_productos_comparables` | Catálogo de comparables con etiqueta legible | `clave_producto`, `etiqueta` |
| `v_comparables` | Observaciones comparables (compatible con el Taller 1) | `clave_producto`, `etiqueta`, `variante` |
| `v_historial_precios` | Serie por producto comparable y comercio | `clave_producto`, `fecha`, `precio_cop`, `precio_por_l` |
| `v_canasta_supermercado` | Base de la canasta: precio por producto y comercio + mínimo | `precio_minimo`, `es_minimo` (empates = varios 1), `n_comercios_con_precio` |

**Diferencia entre `precio_por_litro` y `precio_por_l`:** la primera columna se calcula una vez en el scraper y se guarda en `observaciones`; la segunda se deriva en la vista `v_obs_validas` a partir de `precio_cop` y `volumen_ml`, y es la que usan los indicadores y gráficos.

**`etiqueta`** (en `v_productos_comparables` y `v_comparables`): texto legible del producto, p. ej. `COCA-COLA base · 6000 mL (2 und)`.

## 5. Índices

| Índice | Columnas | Para qué |
|----|----|----|
| `idx_comercio_sku` | `comercio, sku_comercio, fecha_hora_consulta` | Historial por anuncio |
| `idx_ejecucion` | `id_ejecucion, comercio` | Filtro por corrida |
| `idx_obs_precio`, `idx_obs_promo`, `idx_obs_marca`, `idx_obs_subcat` | Columnas de los filtros de la app | Filtros del panel lateral |
| `idx_pc_clave` | `productos_comunes(clave_producto)` | Unión entre corridas |
| `idx_valid_ejec` | `validaciones(id_ejecucion)` | Consulta de validaciones |
| `idx_obs_comparable`, `idx_obs_fecha`, `idx_obs_filtros`, `idx_ejec_corrida` | – | Creados por el scraper |

## 6. Valores de referencia de la entrega

| Corrida           | Fecha      | Origen   | Obs. válidas | Comparables (trío) |
|-------------------|------------|----------|-------------:|-------------------:|
| `20261108-174507` | 2026-11-08 | Taller 1 |        1.164 |                 36 |
| `20261110-141724` | 2026-11-10 | Taller 2 |        1.141 |                 34 |

| Comercio             | Corrida 1 | Corrida 2 |
|----------------------|----------:|----------:|
| Éxito                |       511 |       486 |
| Carulla              |       474 |       475 |
| Supermercado Comunal |       110 |       110 |
| PriceSmart           |        69 |        70 |

## 7. Reglas de calidad

-   Un dato que no se pudo extraer queda **NULL**; nunca se calcula para reemplazarlo.
-   `precio_cop > 0`; comercio, URL y fecha presentes; sin duplicados `(comercio, sku)` dentro de una ejecución.
-   `precio_por_litro` solo se acepta entre 300 y 80.000 COP/L.
-   Disponibilidad con tres estados; `no_observado` no se interpreta como agotado ni retirado.
-   Ninguna observación se borra: los errores se corrigen en `correcciones` o se marcan en `obs_descartadas`.
-   Toda observación se rastrea hasta `ejecuciones` (`id_ejecucion`) y su copia cruda en `raw/` (`archivo_raw`, `raw/manifest.csv`).

## 8. Cómo verificar este diccionario contra la base

``` sql
-- Tablas y vistas
SELECT type, name FROM sqlite_master WHERE type IN ('table','view') ORDER BY type, name;

-- Columnas y tipos de una tabla
PRAGMA table_info(observaciones);

-- Índices de una tabla
PRAGMA index_list(observaciones);

-- Integridad referencial
PRAGMA foreign_key_check;
```
