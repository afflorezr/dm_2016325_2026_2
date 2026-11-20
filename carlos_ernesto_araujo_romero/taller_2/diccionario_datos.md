# Diccionario de datos

**Base:** `comparador_precios.sqlite`  
**Motor:** SQLite 3 (RSQLite)  
**Aplicación:** Shiny, `app.R`  
**Moneda:** pesos colombianos (COP), salvo que se indique otra unidad.  
**Fechas:** texto ISO 8601 con hora de Colombia (`AAAA-MM-DDThh:mm:ss-05:00`).

La base reúne la entrega del Taller 1 y los objetos del Taller 2. Las tablas
`comercios`, `ejecuciones`, `ejecuciones_comercio`, `ejecuciones_categoria`,
`productos_comparables`, `observaciones`, `mapeo_productos` y `descartes`
provienen del Taller 1; las columnas y tablas nuevas se marcan con **(T2)**.

---

## 1. Tablas

### 1.1. `comercios`

Catálogo de comercios y delimitación de la categoría en cada sitio.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_comercio` | TEXT (PK) | `carulla`, `jumbo`, `olimpica`, `exito` | Identificador corto. |
| `nombre` | TEXT | — | Nombre comercial. |
| `url_base` | TEXT | URL | Dominio del comercio. |
| `grupo` | TEXT | — | Grupo empresarial. |
| `categoria_equivalente` | TEXT | — | Ramas del sitio que equivalen a la categoría registrada. |
| `robots_url` | TEXT | URL | Dirección del `robots.txt` revisado. |
| `activo` **(T2)** | INTEGER | 0 / 1 | 1 si el comercio participa en las ejecuciones nuevas. |
| `motivo_estado` **(T2)** | TEXT | — | Razón por la que un comercio está inactivo. |
| `notas` | TEXT | — | Estrategia de extracción. |

`exito` quedó inactivo el 2026-11-11 porque Cloudflare bloqueó su dominio con
HTTP 403. Sus observaciones históricas se conservan.

### 1.2. `ejecuciones`

Una fila por corrida del scraper (en línea o sin conexión).

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_ejecucion` | TEXT (PK) | `EJEC_AAAAMMDD_hhmmss` | Identificador de la corrida. |
| `fecha_inicio` | TEXT | ISO 8601 | Inicio de la ejecución. |
| `fecha_fin` | TEXT | ISO 8601 o NULL | Cierre de la ejecución. |
| `modo` | TEXT | `online`, `offline` | Origen de los datos. |
| `estado` | TEXT | `en_curso`, `completa`, `parcial`, `fallida` | Resultado global. |
| `n_registros` | INTEGER | observaciones | Filas insertadas. |
| `n_obs_comparables` | INTEGER | observaciones | Filas con `es_comparable = 1`. |
| `n_productos_comparables` | INTEGER | productos | Presentaciones comparables distintas. |
| `n_comercios` | INTEGER | comercios | Comercios con datos. |
| `notas` | TEXT | — | Comercios y, si aplica, ejecución de origen del reprocesamiento. |

### 1.3. `ejecuciones_comercio`

Detalle y estado de cada comercio dentro de una ejecución.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_ejecucion` | TEXT (PK) | — | Ejecución. |
| `id_comercio` | TEXT (PK) | — | Comercio. |
| `fecha_inicio` | TEXT | ISO 8601 | Inicio de la extracción del comercio. |
| `fecha_fin` | TEXT | ISO 8601 o NULL | Fin de la extracción. |
| `n_paginas` | INTEGER | páginas | Páginas descargadas. |
| `n_reportado_sitio` | INTEGER | productos | Total que reportó el sitio. |
| `n_extraido` | INTEGER | productos | Productos descargados antes de excluir. |
| `n_incluido` | INTEGER | productos | Productos que pertenecen a la categoría. |
| `n_excluido` | INTEGER | productos | Excluidos por la delimitación. |
| `n_con_precio` | INTEGER | productos | Productos con precio disponible. |
| `estado` | TEXT | `en_curso`, `completa`, `parcial`, `fallida` | Estado del comercio. |
| `url_categoria` | TEXT | URLs separadas por ` | ` | Ramas consultadas. |
| `mensaje` | TEXT | — | Detalle o motivo de la falla. |

### 1.4. `ejecuciones_categoria`

Detalle por rama consultada, para conciliar con el total del sitio.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_ejecucion` | TEXT (PK) | — | Ejecución. |
| `id_comercio` | TEXT (PK) | — | Comercio. |
| `rama` | TEXT (PK) | — | Nombre de la rama del sitio. |
| `url_categoria` | TEXT | URL | Endpoint consultado. |
| `n_reportado` | INTEGER | productos | Total reportado por la API. |
| `n_extraido` | INTEGER | productos | Productos descargados. |
| `n_incluido` | INTEGER | productos | Incluidos en la categoría. |
| `n_excluido` | INTEGER | productos | Excluidos. |
| `n_paginas` | INTEGER | páginas | Páginas descargadas. |
| `estado` | TEXT | `completa`, `parcial`, `fallida` | Estado de la rama. |

### 1.5. `productos_comparables`

Catálogo canónico de presentaciones comparables.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_producto_comun` | TEXT (PK) | `CONF_...` | Identificador común entre comercios. |
| `nombre_canonico` | TEXT | — | Nombre normalizado de la presentación. |
| `marca` | TEXT | — | Marca estandarizada. |
| `variante` | TEXT | — | Variante (sabor, formulación, línea). |
| `contenido_valor` | REAL | g, mL o unidades | Contenido de la presentación. |
| `contenido_unidad` | TEXT | `g`, `ml`, `unidad` | Unidad tal como se registró. |
| `contenido_total` **(T2)** | REAL | g, mL o unidades | Contenido total normalizado. |
| `unidad_normalizada` **(T2)** | TEXT | `g`, `mL`, `unidad` | Unidad base para el precio unitario. |
| `subcategoria` | TEXT | `Chocolates`, `Caramelos`, `Gomitas y masmelos`, `Mentas`, `Chicles` | Clasificación propia. |
| `unidad_base` | TEXT | — | Unidad usada en la comparación. |
| `justificacion` | TEXT | — | Regla de correspondencia. |
| `fecha_creacion` | TEXT | ISO 8601 | Fecha de alta. |
| `vigente` **(T2)** | INTEGER | 0 / 1 | 1 si tiene correspondencia en todos los comercios activos. |

### 1.6. `observaciones`

Cada producto de cada comercio en cada ejecución. Es la tabla central.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_observacion` | INTEGER (PK) | — | Consecutivo interno. |
| `id_ejecucion` | TEXT (FK) | — | Ejecución a la que pertenece. |
| `id_comercio` | TEXT (FK) | — | Comercio. |
| `id_producto_comercio` | TEXT | — | Identificador del producto en el sitio. |
| `sku_comercio` | TEXT | — | SKU del anuncio. |
| `texto_original` | TEXT | — | Nombre del anuncio tal como se publicó. **No se limpia.** |
| `descripcion_original` | TEXT | — | Descripción o ficha del sitio. |
| `especificaciones_json` | TEXT | JSON | Especificaciones originales del sitio. |
| `marca` | TEXT | — | Marca tal como la reporta el sitio (puede tener errores de origen). |
| `categoria_sitio` | TEXT | — | Ruta de categoría del sitio. |
| `subcategoria` | TEXT | ver catálogo | Clasificación estandarizada. |
| `contenido_valor` | REAL | g, ml o unidades | Contenido detectado en el texto. |
| `contenido_unidad` | TEXT | `g`, `ml`, `unidad` | Unidad detectada. |
| `contenido_total` **(T2)** | REAL | g, mL o unidades | Contenido normalizado. |
| `unidad_normalizada` **(T2)** | TEXT | `g`, `mL`, `unidad` | Unidad base. |
| `contenido_origen` | TEXT | `nombre`, `nombre_multipack`, `nombre_unidades`, `nombre_sku` | De dónde salió el contenido. |
| `unidades_por_paquete` | INTEGER | unidades | Multiplicador del ítem en el sitio. |
| `empaque_mencionado` | INTEGER | unidades | Número de empaques mencionado en el nombre. |
| `precio_cop` | REAL | COP | Precio observado. `NULL` si no hay precio o el producto está agotado. |
| `precio_lista_cop` | REAL | COP | Precio antes del descuento, si el sitio lo muestra. |
| `es_promocion` | INTEGER | 0 / 1 | 1 si `precio_lista_cop > precio_cop`. |
| `descuento_pct` | REAL | % | Descuento calculado. |
| `disponible` | INTEGER | 0 / 1 | Indicador heredado del Taller 1. |
| `estado_disponibilidad` **(T2)** | TEXT | `disponible`, `agotado`, `no_observado` | Estado informado por el sitio. |
| `precio_por_unidad` | REAL | COP / unidad | Precio dividido por el contenido. |
| `unidad_precio` | TEXT | `COP/g`, `COP/ml`, `COP/unidad` | Unidad del indicador anterior. |
| `url_producto` | TEXT | URL | Página del anuncio. |
| `fecha_consulta` | TEXT | ISO 8601 | Momento de la consulta. Obligatorio. |
| `id_producto_comun` | TEXT (FK) | — | Presentación canónica, si es comparable. |
| `es_comparable` | INTEGER | 0 / 1 | 1 si pertenece al catálogo comparable. |

Restricciones: `ux_observaciones_ejecucion_anuncio (id_ejecucion, id_comercio,
sku_comercio)` y `CHECK (precio_cop IS NULL OR precio_cop > 0)`. La restricción
`UNIQUE (id_comercio, sku_comercio, fecha_consulta)` del Taller 1 se retiró en la
migración del Taller 2 porque impedía reprocesar una copia cruda en una
ejecución nueva con la misma hora de consulta; el detalle está en
`correcciones`.

### 1.7. `mapeo_productos`

Correspondencia manual entre SKU y presentación canónica.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_producto_comun` | TEXT (PK/FK) | — | Presentación canónica. |
| `id_comercio` | TEXT (PK/FK) | — | Comercio. |
| `sku_comercio` | TEXT (PK) | — | SKU del anuncio. |
| `nombre_comercio` | TEXT | — | Nombre original en ese comercio. |
| `regla` | TEXT | — | Regla aplicada y verificación. |
| `confianza` | TEXT | `alta`, `media`, `baja` | Certeza de la correspondencia. |
| `validado_por` | TEXT | — | Responsable de la validación. |
| `fecha_validacion` | TEXT | ISO 8601 | Fecha de validación. |

### 1.8. `descartes`

Productos excluidos de la categoría o duplicados entre ramas.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_descarte` | INTEGER (PK) | — | Consecutivo. |
| `id_ejecucion` | TEXT (FK) | — | Ejecución. |
| `id_comercio` | TEXT | — | Comercio. |
| `sku_comercio` | TEXT | — | SKU descartado. |
| `texto_original` | TEXT | — | Nombre original. |
| `motivo` | TEXT | `suplemento`, `medicinal_garganta`, `no_confiteria`, `otra_categoria`, `duplicado_categoria`, `cobertura_incompleta`, `bebida_o_polvo`, `no_es_chocolate` | Razón. |
| `detalle` | TEXT | — | Contexto (rama, categoría del sitio). |
| `fecha_registro` | TEXT | ISO 8601 | Fecha del descarte. |

### 1.9. `correcciones` **(T2)**

Bitácora de cambios sobre la entrega anterior o sobre la base. Ningún cambio se
hace en silencio.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_correccion` | INTEGER (PK) | — | Consecutivo. |
| `fecha` | TEXT | ISO 8601 | Momento de la corrección. |
| `tabla` | TEXT | — | Tabla afectada. |
| `campo` | TEXT | — | Campo o conjunto de campos. |
| `id_registro` | TEXT | — | Registro(s) afectado(s). |
| `valor_anterior` | TEXT | — | Valor previo. |
| `valor_nuevo` | TEXT | — | Valor nuevo. |
| `motivo` | TEXT | — | Justificación. |
| `id_ejecucion` | TEXT | — | Ejecución asociada, si aplica. |
| `autor` | TEXT | — | Responsable. |

### 1.10. `observaciones_rechazadas` **(T2)**

Observaciones que no pasaron la validación y no entraron a `observaciones`.

| Columna | Tipo | Unidad / valores | Significado |
|---|---|---|---|
| `id_rechazo` | INTEGER (PK) | — | Consecutivo. |
| `fecha` | TEXT | ISO 8601 | Momento del rechazo. |
| `id_ejecucion` | TEXT | — | Ejecución en curso. |
| `id_comercio` | TEXT | — | Comercio. |
| `sku_comercio` | TEXT | — | SKU. |
| `texto_original` | TEXT | — | Nombre original. |
| `precio_cop` | REAL | COP | Precio que traía. |
| `motivo` | TEXT | ver `validacion.R` | Regla incumplida. |
| `detalle` | TEXT | — | Explicación. |

---

## 2. Vistas

| Vista | Grano | Uso en la aplicación |
|---|---|---|
| `v_observaciones` | Una fila por observación, con nombre de comercio y producto canónico. | Series de precio y tabla base. |
| `v_comparables` | Una fila por presentación canónica, con cobertura de correspondencia. | Catálogo de productos comparables. |
| `v_ultimo_precio` | Última observación de cada anuncio (comercio + SKU). | Precio vigente por anuncio. |
| `v_cambios_precio` | Un par de ejecuciones por anuncio con precio en ambas. | Página de cambios de precio. |
| `v_disponibilidad` | Ejecución × comercio × presentación comparable. | Estados disponible / agotado / no observado. |
| `v_ahorro_presentacion` | Ejecución × presentación comparable. | Mínimo, máximo, promedio, ahorro y empates. |
| `v_precio_unitario` | Ejecución × comercio × presentación comparable. | Precio por g, mL o unidad. |
| `v_resumen_ejecucion` | Una fila por ejecución. | Indicadores y fecha de la última ejecución. |

Columnas de `v_ultimo_precio`: `id_observacion`, `id_ejecucion`, `id_comercio`,
`comercio`, `sku_comercio`, `id_producto_comun`, `nombre_canonico`,
`texto_original`, `marca`, `subcategoria`, `contenido_total`,
`unidad_normalizada`, `precio_cop`, `precio_lista_cop`, `es_promocion`,
`descuento_pct`, `disponible`, `estado_disponibilidad`, `precio_por_unidad`,
`unidad_precio`, `url_producto`, `fecha_consulta`, `es_comparable`.

Columnas de `v_cambios_precio`: `ejecucion_anterior`, `ejecucion_actual`,
`id_comercio`, `comercio`, `sku_comercio`, `id_producto_comun`,
`nombre_canonico`, `texto_original`, `precio_anterior`, `precio_actual`,
`cambio_cop`, `cambio_pct`, `fecha_anterior`, `fecha_actual`.

Columnas de `v_ahorro_presentacion`: `id_ejecucion`, `id_producto_comun`,
`nombre_canonico`, `marca`, `subcategoria`, `contenido_total`,
`unidad_normalizada`, `n_comercios`, `precio_min`, `precio_max`,
`precio_promedio`, `ahorro_cop`, `ahorro_pct`, `comercios_min`,
`comercios_max`.

---

## 3. Índices y restricciones

* `ux_observaciones_ejecucion_anuncio`: unicidad de `(id_ejecucion, id_comercio, sku_comercio)`.
* `ux_observaciones_comparable`: una sola fila comparable por producto y comercio en cada ejecución.
* Índices para los filtros de la aplicación: `id_ejecucion`, `id_comercio`,
  `subcategoria`, `marca`, `precio_cop`, `es_promocion`, `fecha_consulta`,
  `id_producto_comun`.
* Claves foráneas a `comercios`, `ejecuciones` y `productos_comparables`.

---

## 4. Reglas de validación

Definidas en `validacion.R` y aplicadas antes de cada inserción:

| Regla | Condición |
|---|---|
| `precio_positivo` | Si el producto está disponible, `precio_cop > 0`. |
| `campos_obligatorios` | Comercio, SKU, texto original, URL y fecha presentes. |
| `url_valida` | La URL empieza por `http://` o `https://`. |
| `fecha_iso` | `AAAA-MM-DDThh:mm:ss-05:00`. |
| `disponibilidad_valida` | `disponible`, `agotado` o `no_observado`. |
| `duplicado_ejecucion` | Sin dos filas del mismo anuncio en la ejecución. |
| `precio_lista_coherente` | El precio de lista no es menor que el precio pagado. |
| `contenido_positivo` | `contenido_total > 0` cuando existe. |
| `unidad_normalizada` | `g`, `mL` o `unidad`. |

Las filas que incumplen una regla se registran en `observaciones_rechazadas` con
el motivo y no se insertan.
