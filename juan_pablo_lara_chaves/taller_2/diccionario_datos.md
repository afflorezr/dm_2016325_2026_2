
# Diccionario de datos

Base: `comparador_precios.sqlite` (SQLite).

## Tablas

### comercios
| Columna | Descripción |
|---|---|
| comercio (PK) | Identificador: `farmatodo`, `locatel`, `ortopedicos_futuro` |
| nombre_comercial | Nombre para mostrar |
| url_base | Dominio del comercio |
| plataforma | Plataforma de la tienda (Angular, VTEX) |

### productos
| Columna | Descripción |
|---|---|
| producto_id (PK) | Identificador del comparable (ej. `NOVARIX_MEDIA_HOMBRE_15-20`) |
| marca, tipo, presentacion | Ficha del producto equivalente |
| contenido, unidad | Cantidad y unidad (`mL`, `g`, `unidad`); aquí 1 `unidad` |

### ejecuciones
| Columna | Descripción |
|---|---|
| ejecucion_id, comercio (PK) | Corrida (`ejec_AAAAMMDD`) y comercio |
| fecha_inicio, fecha_fin | Ventana de la recolección |
| n_registros | Registros recolectados, antes de validar |
| estado | `completa`, `parcial` o `fallida` |
| nota | Motivo de una ejecución parcial o fallida |
| con_raw | 1 si existe copia cruda (HTML) en `raw/`; 0 si no |

### observaciones
| Columna | Descripción |
|---|---|
| obs_id (PK) | Identificador autoincremental |
| ejecucion_id, comercio | Ejecución y comercio de origen |
| categoria_sitio, subcategoria_std | Categoría en el sitio y subcategoría estandarizada |
| nombre, nombre_norm | Nombre original y normalizado |
| marca_std, sku, id_anuncio | Marca estandarizada, SKU (solo Farmatodo) e id del anuncio |
| n_unidades | Unidades por presentación |
| producto_comercio | Clave del anuncio dentro del comercio |
| precio, precio_lista | Precio vigente (> 0) y precio de lista, en COP |
| descuento | Texto del descuento (ej. `15%`) |
| en_promocion | 1 si hay promoción |
| disponibilidad | `disponible` o `agotado` |
| url, url_origen | Página del producto y del listado donde apareció |
| fecha_hora | Momento de la consulta (ISO 8601, hora de Bogotá) |
| producto_id | Comparable asignado (FK a `productos`) |
| comparable | 1 si pertenece a los 8 comparables |
| descartada | 1 si la observación se excluye (ej. 9-oct sin copia cruda) |

Restricción única: (`comercio`, `producto_comercio`, `fecha_hora`). Insertar con `INSERT OR IGNORE` evita duplicados al repetir una ejecución.

### correcciones
Registro de cambios sobre los datos: `fecha`, `tabla`, `registro_id`, `campo`, `valor_anterior`, `valor_nuevo`, `motivo`.

### rechazos
Filas que no pasaron la validación: `fecha` (hora de registro), `ejecucion_id`, `comercio`, `fila_json` (fila original), `regla` y `motivo`.
Reglas: `precio_positivo`, `campos_obligatorios`, `duplicado_en_ejecucion`.

### reglas_emparejamiento
Reglas usadas para asignar cada anuncio a un comparable (confianza alta en los 8).

## Vistas

| Vista | Qué devuelve |
|---|---|
| v_ultimo_precio | Observación más reciente de cada anuncio (no descartada) |
| v_cambios_precio | Precio actual, anterior, `delta` y `delta_pct` por anuncio |
| v_comparables | Observaciones comparables con ficha y `precio_unitario` |
| v_referencia | Por comparable, comercio y ejecución: `precio` (máximo de las variantes), `precio_min`, `n_anuncios` |

