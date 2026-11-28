# Taller 2 — Comparador de precios (pañales, pañitos, cambiadores desechables y cremas de barrera)

**Asignatura:** Minería de Datos (2016325) · Universidad Nacional de Colombia
**Lenguaje:** Python (>= 3.11) · **Aplicación:** Streamlit · **Comercios (VTEX):** Éxito, Jumbo, Olímpica

> 🔗 **Aplicación publicada:** https://dm201632520262-gcjcmotappitr4gvkzryqn7.streamlit.app/
>
> Nota de despliegue: las plataformas gratuitas **no conservan los cambios en la base al reiniciarse** y los comercios suelen **bloquear el scraping desde servidores en la nube**. En la versión publicada la actualización en línea puede fallar (la aplicación lo informa con claridad y ofrece el modo sin conexión); la actualización en línea está pensada para ejecutarse en el computador local.

## ¿Qué responde la aplicación?

*¿Dónde me conviene comprar un producto o una canasta de productos de cuidado del bebé?* Siete páginas:

| Página | Contenido |
|---|---|
| **Resumen** | 8 indicadores calculados con SQL (productos y observaciones por comercio, fecha/estado de la última ejecución, % en promoción, precio mediano y mediana por subcategoría, ahorro máximo entre comercios, cambios de precio y no observados en la última ejecución), cada uno con su unidad y periodo |
| **Productos** | Tabla filtrable, ordenable y con búsqueda; descarga en CSV; enlace a cada anuncio |
| **Gráficos** | 4 gráficos interactivos (plotly): evolución del precio por comercio, precio por unidad (sin mezclar unidades), distribución por comercio y mapa de sobreprecio |
| **Cambios de precio** | Compara dos ejecuciones (por defecto las dos completas más recientes): subieron/bajaron (COP y %), nuevos, dejaron de observarse; umbral ajustable |
| **Canasta** | Costo por comercio (solo si tiene todos los productos), costo mínimo comprando cada producto donde es más barato y ahorro |
| **Actualizar datos** | Botón que llama al scraper (con avance por comercio), resumen por comercio y modo sin conexión |
| **Origen de los datos** | Ejecuciones, observaciones rechazadas, correcciones y trazabilidad hasta `raw/` |

Panel lateral con filtros combinables: comercio, subcategoría, marca, rango de precio, ejecución, rango de fechas, solo promociones, solo comparables y búsqueda de texto. Cada comercio conserva su color en toda la aplicación (Éxito amarillo, Jumbo verde, Olímpica rojo).

### Gráfico de libre elección (justificación)
**«¿Cuánto pago de más frente al comercio más barato?»** (mapa de calor producto × comercio). Un consumidor rara vez compra un solo producto: quiere saber si un comercio es sistemáticamente más caro y en qué productos la diferencia importa. El mapa muestra, para cada presentación idéntica, el sobreprecio porcentual de cada comercio frente al mínimo, y el pie del gráfico resume el sobreprecio promedio por comercio.

## Ejecución local

```bash
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
streamlit run app.py
```

### Pruebas automáticas (un solo comando, desde `taller_2/`)
```bash
pytest tests/
```
Usan **datos sintéticos** y una **base temporal** (nunca la base de la entrega ni los sitios). Cubren: conversión de precios en texto a número, normalización de unidades, ahorro con empates, que insertar dos veces la misma ejecución no duplica observaciones, detección de cambios de precio, que la canasta no se calcula cuando falta un producto, validación antes de insertar, transacciones (rollback), tres estados de disponibilidad, consultas parametrizadas (inyección SQL), modo sin conexión, esquema/índices/vistas, diccionario de datos y ausencia de credenciales.

### Actualizar los precios
* **Desde la aplicación:** página *Actualizar datos* → *Actualizar precios (en línea)*. O por consola: `python scraper.py run` (también `probe` y `diagnose` para diagnosticar bloqueos).
* **Modo sin conexión (usa `raw/`, no consulta sitios):** botón en la misma página o `python scraper.py offline`. No pisa ejecuciones ya cargadas.
* **Enlazar y verificar las observaciones antiguas con `raw/`:** `python migrar_taller2.py --raw raw` (llena `observaciones.raw_archivo` y comprueba que cada precio coincida con la respuesta original).

Cada actualización **agrega** observaciones (nunca sobrescribe). La base contiene las ejecuciones completas del 11 de octubre y del 9 de noviembre de 2026.

## Estructura de archivos

| Archivo | Descripción |
|---|---|
| `app.py`, `paginas/` | Aplicación: navegación multipágina y una página por módulo funcional (sin SQL) |
| `ui.py`, `ui_filtros.py`, `graficos.py` | Piezas de interfaz, panel de filtros y figuras plotly |
| `servicios.py` | Caché (`st.cache_data`) de las consultas; se invalida tras cada actualización |
| `db.py` | **Capa de acceso a datos**: esquema, vistas, índices y todas las consultas SQL parametrizadas |
| `scraper.py` | Extracción (módulo del Taller 1 reutilizado): `recolectar_comercio()`, `ejecutar_recoleccion()`, `reprocesar_raw()` |
| `limpieza.py` | Delimitación de la categoría, estandarización y correspondencia de productos (Taller 1) |
| `validacion.py` | Reglas de validación de observaciones y de entradas del usuario |
| `analisis.py` | Cálculos para el consumidor (ahorro con empates, canasta, variaciones) y formatos COP |
| `migrar_taller2.py` | Lleva la base del Taller 1 al esquema del Taller 2 y registra las correcciones |
| `hallazgos.py` | Reproduce con SQL las cifras de la sección de hallazgos |
| `comparador_precios.sqlite` | Base de datos (Taller 1 + esquema del Taller 2; las nuevas ejecuciones se agregan aquí) |
| `diccionario_datos.md` | Diccionario de tablas, vistas y columnas |
| `raw/` | Copias crudas (JSON comprimido) por comercio y fecha |
| `tests/` | Pruebas con pytest |
| `.streamlit/`, `.gitignore` | Configuración; los secretos van en `.streamlit/secrets.toml` (ignorado) o en la plataforma |

## Cómo se cumple cada módulo

**Datos.** Todo precio proviene del scraper (`raw/` guarda la respuesta original de cada petición; `observaciones.raw_archivo` enlaza cada observación con su copia y `ejecuciones` con su ejecución). Un dato ausente queda `NULL`. Antes de insertar se validan reglas explícitas (`validacion.py`): precio numérico > 0 (un producto *agotado* sin precio queda `NULL` y se registra como agotado), comercio, URL, SKU, nombre y fecha-hora presentes y válidas, sin duplicados en la misma ejecución, y presencia de los productos comparables en cada comercio (si falta alguno, la ejecución de ese comercio queda `parcial` con el motivo). Lo que no pasa la validación **no se inserta** y queda en `observaciones_rechazadas` con su motivo. Las reglas se implementaron con pandas puro (sin dependencia extra) y equivalen a un esquema de pandera.
**Corrección del Taller 1.** `migrar_taller2.py` aplica y registra en `correcciones` (fecha, registro, valor anterior, valor nuevo, motivo): (1) la URL base de Jumbo, que apuntaba al dominio antiguo `tiendasjumbo.co`; (2) un anuncio de un vendedor externo («Otros vendedores») que estaba marcado como comparable del producto 11. No se borró ninguna observación.
**Disponibilidad.** `disponible` / `agotado` (lo informa el sitio, columna `estado_disponibilidad`) y `no_observado` (vista `v_disponibilidad`: el anuncio no apareció en la ejecución; no se interpreta como agotado ni retirado).
**Actualización.** El botón llama a `scraper.recolectar_comercio` comercio por comercio con `st.status`; cada comercio se inserta en una transacción (todo o nada); si uno falla (red, bloqueo) los demás continúan y la falla queda registrada con su motivo; al terminar se muestra el resumen (recolectados, nuevos, cambios de precio, no observados) y se invalida el caché para que todo se actualice sin reiniciar.
**Seguridad.** Consultas parametrizadas (`?`); solo se insertan marcadores y nombres de vistas/columnas de listas blancas; la búsqueda se valida (máx. 60 caracteres, caracteres permitidos) y los `%`/`_` se escapan; sin credenciales en el repositorio (`.gitignore`, `st.secrets`); scraping con agente de usuario identificable, pausa mínima de 1 s y tope de peticiones por comercio.

### Vistas SQL (usadas directamente por la aplicación)
| Vista | Qué contiene |
|---|---|
| `v_ejecuciones_resumen` | Una fila por ejecución con estado global y conteo de comercios |
| `v_ultima_ejecucion_comercio` | Última ejecución no fallida de cada comercio |
| `v_observaciones` | Observación + anuncio + comercio (categoría delimitada), con precio unitario |
| `v_ultimo_precio` | Precio más reciente de cada anuncio (última ejecución de su comercio) |
| `v_comparables` | Mejor precio disponible por ejecución × comercio × producto comparable |
| `v_cambios_precio` | Cambios de precio del mismo anuncio entre observaciones consecutivas |
| `v_disponibilidad` | Disponible / agotado / no observado por anuncio y ejecución |
| `v_precios_comparables` | Vista del Taller 1 (se conserva) |

## Hallazgos para el consumidor

Base: ejecución completa `run_20261109T163247` (9 de noviembre de 2026, desde las 16:32; Éxito, Jumbo y Olímpica; 18 productos comparables). Para los cambios de precio se compara con la ejecución completa `run_20261011T193258` (11 de octubre de 2026). Reproducibles con `python hallazgos.py`.

1. **Éxito fue el comercio más barato en la mitad de los comparables.** Fue el más barato en 9 de 18 productos (Olímpica en 6 y Jumbo en 3). Su sobreprecio promedio frente al mínimo fue de 2,1 %, frente a 9,0 % en Olímpica y 11,0 % en Jumbo. En algunos productos la diferencia llega al 104 % (*Gráficos → ¿Dónde pago de más?*).
2. **En unos pocos productos la diferencia entre comercios es enorme.** El pañito Huggies manitos y carita x 80 cuesta $4.845 en Éxito y $9.890 en el comercio más caro (51 % menos). El pañal Winny ultratrim XG x 50 cuesta $74.100 en Éxito y $85.290 en el más caro ($11.190 de ahorro), y el Winny pants XG x 30 cuesta $41.220 en Éxito frente a $51.990 en el más caro ($10.770 de ahorro). Comprar cada producto donde es más barato ahorra dinero frente a un solo comercio (*Canasta*).
3. **Comprar el tamaño grande no siempre sale más barato por unidad.** En la crema Almipro el frasco de 125 g es entre 8 % y 15 % más barato por gramo que el de 60 g en los tres comercios. En los pañales Winny no hay una regla: en Éxito el paquete ultratrim de 50 cuesta $1.482 por unidad frente a $1.595 el de 30, pero en Olímpica ocurre lo contrario ($1.612 el de 30 frente a $1.706 el de 50) y en Jumbo el gold de 30 sale más barato ($1.866 frente a $1.938 el de 50) (*Gráficos → Precio por unidad*).
4. **Los precios cambiaron bastante en un mes.** Entre el 11 de octubre y el 9 de noviembre cambió el precio de 112 productos en Éxito, 52 en Jumbo y 24 en Olímpica. El cambio promedio fue de +13,2 % en Éxito y +12,8 % en Jumbo, y de −4,0 % en Olímpica (promedio de subidas y bajadas de todos los productos con cambio). Además, 4 de los 18 comparables estaban en promoción en Éxito y ninguno en Jumbo ni en Olímpica (*Cambios de precio*).

## Declaración de uso de inteligencia artificial

* **Herramienta:** Claude (Anthropic).
* **Para qué se usó:** la mayor parte del código de la aplicación fue generada con Claude: la arquitectura (separación app/db/scraper/validación), el módulo `db.py` (esquema, vistas e índices SQL), la validación de datos, la aplicación Streamlit, las pruebas con pytest, el diccionario de datos, el script de migración y la redacción de este README. El scraper, la limpieza y la correspondencia de productos son los del Taller 1 (de mi autoría), con las extensiones descritas arriba. También se usó para interpretar los resultados y los mensajes de error durante la ejecución.
* **Cómo se verificó:** ejecuté todo en mi computador y comprobé los resultados: la aplicación abre y todas sus páginas y gráficos funcionan; las 76 pruebas automáticas pasan (`pytest tests/`); la migración enlazó 18.984 de 18.984 observaciones con sus copias en `raw/` sin diferencias de precio; la nueva recolección del 9 de noviembre terminó completa en los tres comercios; y las cifras de los hallazgos se obtuvieron con consultas SQL sobre la base (`hallazgos.py`).

## Limitaciones
* Los precios son los del momento de captura; no incluyen envío, mínimos de compra ni descuentos por tarjeta.
* El historial se basa en dos ejecuciones completas (11 de octubre y 9 de noviembre de 2026); entre ambas hay un mes de diferencia, no un seguimiento diario.
* La base de la plataforma gratuita es efímera (se reinicia con cada despliegue).


