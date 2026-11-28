# Diccionario de datos: `comparador_precios.sqlite`

Categoría: medicamentos para alergias y síntomas respiratorios. Comercios: Farmatodo, Cruz Verde y La Rebaja.

- Fechas y horas: texto ISO 8601 con la hora de Colombia, por ejemplo `2026-10-11T02:42:19-05:00`.
- Precios: pesos colombianos (COP).
- `NULL` significa que el dato no se pudo extraer; nunca se rellena.
- Tablas del Taller 1: las crea `crear_esquema()` (`R/06_base_datos.R`). Lo que agrega el Taller 2 lo crea `db_inicializar()` (`db.R`) con `sql/esquema_taller2.sql`.

## Tablas

### `comercios` (Taller 1)
| Columna | Tipo | Significado | Valores posibles |
|---|---|---|---|
| comercio | TEXT (PK) | Nombre del comercio | Farmatodo, Cruz Verde, La Rebaja; Farmacias Pasteur y Éxito (respaldo, sin datos) |
| clave | TEXT (único) | Clave usada en el código y en `raw/` | farmatodo, cruzverde, larebaja, pasteur, exito |
| plataforma | TEXT | Servicio JSON del sitio | Algolia, Salesforce Commerce Cloud, VTEX |
| url_base | TEXT | Sitio del comercio | |

### `ejecuciones` (Taller 1, con columnas nuevas del Taller 2)
Una fila por comercio en cada corrida del scraper. PK: (`id_ejecucion`, `comercio`).

| Columna | Tipo | Unidad | Significado | Valores posibles |
|---|---|---|---|---|
| id_ejecucion | TEXT | | Identificador de la corrida | `EJ_AAAAMMDDTHHMMSS` (captura); `RP_...` (reprocesamiento sin conexión) |
| fecha_inicio | TEXT | fecha y hora | Inicio de la corrida en ese comercio | |
| comercio | TEXT (FK) | | Comercio | |
| registros_obtenidos | INTEGER | productos | Productos que pasaron el filtro (y la validación, en el Taller 2) | ≥ 0 |
| estado | TEXT | | Resultado | `EN_CURSO`, `COMPLETA`, `PARCIAL` (peticiones fallidas o faltan comparables), `FALLIDA` |
| modo | TEXT | | Cómo se obtuvo | `online`, `offline`, `test` |
| detalle | TEXT | | Conteos y motivo de la falla | |
| entorno | TEXT | | Versión de R y sistema operativo | |
| n_validas | INTEGER | productos | Pasaron la validación (Taller 2) | NULL en corridas del Taller 1 |
| n_rechazadas | INTEGER | productos | Rechazadas (ver `observaciones_rechazadas`) | |
| n_insertadas | INTEGER | productos | Entraron a la base (no existían) | |
| n_nuevos | INTEGER | productos | Nunca se habían visto en ese comercio | |
| n_cambios | INTEGER | productos | Precio distinto al último conocido | |
| n_no_observados | INTEGER | productos | Estaban en la corrida anterior del comercio y no aparecieron | |

### `productos_comunes` (Taller 1)
Los 8 productos comparables.

| Columna | Tipo | Unidad | Significado |
|---|---|---|---|
| id_producto_comun | TEXT (PK) | | `COMP_DOLEX_GRIPA`, `COMP_PAX_NOCHE`, `COMP_FLUIMUCIL_600`, `COMP_ABRILAR_JARABE`, `COMP_AFRIN_ADULTOS`, `COMP_LORATADINA_10MG`, `COMP_ALLEGRA_120`, `COMP_AVAMYS_SPRAY` |
| descripcion | TEXT | | Nombre del producto comparable |
| alternativa_elegida | TEXT | | Presentación que se encontró en los 3 comercios |
| marca_estandarizada | TEXT | | Marca (o laboratorio) común |
| contenido_num | REAL | según unidad | Contenido de la presentación |
| unidad_medida | TEXT | | `unidad`, `sobres`, `mL`, `dosis` |

### `observaciones` (Taller 1, con una columna nueva)
Precio de un producto en una corrida. Único: (`comercio`, `sku_comercio`, `fecha_hora_consulta`).

| Columna | Tipo | Unidad | Significado | Valores posibles |
|---|---|---|---|---|
| id_observacion | INTEGER (PK) | | Identificador | |
| id_ejecucion | TEXT (FK) | | Corrida en la que se obtuvo (la misma del manifiesto de `raw/`) | |
| comercio | TEXT | | Comercio | |
| sku_comercio | TEXT | | Identificador del producto en el sitio | |
| producto_nombre_original | TEXT | | Nombre tal como lo publica el sitio | |
| marca_estandarizada | TEXT | | Marca o laboratorio estandarizado | |
| subcategoria_estandar | TEXT | | Subcategoría | `Antihistamínicos`, `Antigripales / Descongestionantes`, `Antitusivos / Expectorantes`, `Enfermedades Respiratorias` |
| contenido_num | REAL | según unidad | Contenido del envase | > 0 o NULL |
| unidad_medida | TEXT | | Unidad del contenido | `mL`, `g`, `mg`, `unidad`, `sobres`, `dosis`, NULL |
| precio_cop | REAL | COP | Precio que paga el comprador (oferta si la hay) | > 0 |
| precio_regular_cop | REAL | COP | Precio sin descuento | ≥ precio_cop |
| es_promocion | INTEGER | | precio_cop < precio_regular_cop | 0, 1 |
| url_producto | TEXT | | Enlace al producto | |
| fecha_hora_consulta | TEXT | fecha y hora | Momento de la petición | |
| comparable | INTEGER | | 1 si es la presentación elegida de un comparable en esa corrida | 0, 1 |
| id_producto_comun | TEXT (FK) | | Comparable al que corresponde | NULL si no es comparable |
| familia_producto | TEXT | | Todas las presentaciones del mismo producto y marca | `FAM_...` |
| presentacion_original, descripcion_original, ficha_tecnica_original, categoria_origen | TEXT | | Texto original del sitio | |
| url_consulta | TEXT | | URL del servicio JSON consultado | |
| archivo_raw | TEXT | | Archivo de la copia cruda, en `raw/{clave}/{AAAA-MM-DD}/` y listado en el `manifiesto.jsonl` de esa carpeta | |
| disponible | INTEGER | | Lo que dice el sitio | 1 disponible, 0 agotado, NULL el sitio no lo indica (Cruz Verde) |
| descartada | INTEGER | | 1 si se descartó por una corrección (Taller 2; no se borra) | 0, 1 |

Un producto **no observado** en una corrida no tiene fila en esta tabla. Las vistas `v_comparables` y `v_disponibilidad` lo muestran como `no_observado`, que es distinto de `agotado`.

### `observaciones_rechazadas` (Taller 2)
Filas que entregó el scraper y no pasaron la validación (`validacion.R`). No entran a `observaciones`.

| Columna | Tipo | Significado |
|---|---|---|
| id_rechazo | INTEGER (PK) | Identificador |
| id_ejecucion | TEXT | Corrida |
| comercio, sku_comercio, producto_nombre_original, url_producto, fecha_hora_consulta, archivo_raw | TEXT | Lo que llegó del scraper (puede ser NULL) |
| precio_cop | REAL (COP) | Precio que llegó (puede ser inválido) |
| motivo | TEXT | Reglas que no cumplió, separadas por `;` |
| fecha_registro | TEXT | Cuándo se rechazó |

### `correcciones` (Taller 2)
| Columna | Tipo | Significado |
|---|---|---|
| id_correccion | INTEGER (PK) | Identificador |
| fecha | TEXT | Cuándo se corrigió |
| tabla | TEXT | Tabla afectada (`observaciones`) |
| id_registro | TEXT | `id_observacion` afectado |
| campo | TEXT | Columna corregida |
| valor_anterior, valor_nuevo | TEXT | Valores antes y después |
| motivo | TEXT | Por qué (obligatorio) |

## Índices

Del Taller 1: `ix_obs_ejecucion`, `ix_obs_comparable`. Del Taller 2, para los filtros de la app: `ix_obs_comercio` (comercio, id_ejecucion), `ix_obs_subcategoria`, `ix_obs_marca`, `ix_obs_precio`, `ix_obs_fecha`, `ix_rech_ejecucion`.

## Vistas (Taller 2)

| Vista | Qué devuelve | Dónde la usa la app |
|---|---|---|
| `v_observaciones` | Observaciones no descartadas. Agrega `contenido_total` y `unidad_normalizada` (mL; g, con mg/1000; unidad para tabletas, sobres y dosis), `precio_unitario` (COP por mL, g o unidad) y `estado_disponibilidad` | Indicadores, tabla de productos, distribución, comparación de ejecuciones |
| `v_ultimo_precio` | Última observación de cada producto en cada comercio (`orden` = 1) | Al actualizar: productos nuevos y cambios de precio |
| `v_cambios_precio` | Productos con precio distinto a su observación anterior: `precio_anterior`, `precio_actual`, `diferencia` (COP), `variacion_pct` (%) | Indicador de cambios de precio |
| `v_comparables` | Los 8 comparables en cada comercio y corrida, aunque no se hayan observado. `estado`: `disponible`, `agotado`, `sin_dato`, `no_observado` | Evolución del precio, precio por unidad, ahorro máximo, dónde es más barato, canasta |
| `v_disponibilidad` | Estado de cada producto ya conocido de un comercio en cada corrida | Indicador de agotados y no observados |
| `v_ejecuciones` | Una fila por corrida: estado general, comercios y observaciones | Selectores de ejecución e historial |

Las corridas `offline` que no agregaron observaciones (porque las copias de `raw/` ya estaban en la base) no se cuentan en `v_comparables` ni en `v_disponibilidad`.
