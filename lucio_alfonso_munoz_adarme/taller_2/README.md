# Taller 2: aplicación comparador de precios de nutrición deportiva

Aplicación web que consulta la base del Taller 1, la actualiza con el scraper y ayuda a decidir dónde comprar productos de nutrición deportiva (proteínas, creatina, aminoácidos, preentrenos, geles, barras y bebidas deportivas) en Éxito, Farmatodo y Locatel, con precios de Bogotá.

- **Lenguaje:** Python, con Streamlit para la aplicación. Todo el proceso (scraping, acceso a datos, aplicación y pruebas) está en Python.
- **Aplicación publicada:** https://comparador-nutricion-lmunozad.streamlit.app/

## Ejecutar localmente

Desde la carpeta `taller_2/`:

```
pip install -r requirements.txt
streamlit run app.py

```

La aplicación abre en `http://localhost:8501`. No necesita credenciales ni archivos de configuración. Todas las rutas se arman desde la carpeta del proyecto

Para recolectar sin abrir la aplicación:

```
python -c "import scraper; print(scraper.ejecutar_recoleccion(online=True).to_string())"
```

Con `online=False` se reprocesan las copias de `raw/` sin conectarse a internet.

## Pruebas

```
pytest tests/
```

Son 8 pruebas que usan datos pequeños y una base temporal: conversión del precio en texto a número, normalización de unidades, ahorro con empates, que insertar dos veces la misma ejecución no duplica observaciones, detección de cambios de precio, que la canasta no se calcula si falta un producto, rechazo de observaciones inválidas y validación del texto de búsqueda.

## Estructura

```
app.py                      navegación entre páginas (st.navigation)
paginas/                    resumen, productos, comparar precios, cambios de precio, canasta y actualizar
comun.py                    colores de los comercios, formato de números y filtros del panel lateral
db.py                       consultas SQL con parámetros; la interfaz no tiene SQL
scraper.py                  extracción, limpieza y carga en SQLite (el del Taller 1 con los cambios de abajo)
validacion.py               reglas de validación con pandera y validación del texto de búsqueda
corregir_taller1.py         crea esta base a partir de la del Taller 1 y registra las correcciones
comparador_precios.sqlite   base con todas las ejecuciones
diccionario_datos.md        tablas, vistas y columnas de la base
raw/                        respuestas originales comprimidas: raw/<comercio>/<fecha>/<id_ejecucion>/
tests/                      pruebas con pytest
requirements.txt            dependencias con versiones fijas
```

## Datos

Todos los datos vienen del scraper ejecutado sobre los servicios JSON que usan los propios sitios (VTEX en Éxito y Locatel, Algolia en Farmatodo), identificados en el Taller 1. Cada observación tiene su `id_ejecucion` y su fecha y hora de consulta, y su copia cruda está en `raw/` en la carpeta que indica `ejecuciones.carpeta_raw`.

### Historial de ejecuciones

| Ejecución | Fecha | Éxito | Farmatodo | Locatel |
|---|---|---|---|---|
| 20261011T112336 | 11/10/2026 11:23 | completa | parcial | completa |
| 20261011T114310 | 11/10/2026 11:43 | completa | parcial | completa |
| 20261114T194451 | 14/11/2026 19:44 | fallida (HTTP 403) | completa | completa |

**Éxito.** Desde noviembre de 2026 Éxito tiene una verificación de Cloudflare que responde HTTP 403 a todas las  consultas automátics, también con el agente de navegador que usaba el Taller 1, y su robots.txt. La ejecución nueva de Éxito queda como fallida, dado que no fue posible realizar la consulta, por lo que Éxito conserva sus dos ejecuciones completas de octubre. Por eso la comparación de los tres comercios se hace con los datos de octubre, y la de noviembre solo entre Farmatodo y Locatel.

**Farmatodo.** En el Taller 1 cada búsqueda traía solo la primera página (24 productos), así que 16 búsquedas quedaron cortadas y la ejecución quedó parcial. Ahora cada búsqueda se recorre página por página: en la ejecución del 14 de noviembre se descargaron 84 páginas, con 826 productos, 269 de ellos de la categoría. En noviembre se rechazaron 108 productos de Farmatodo porque el sitio no publica su URL.

**Locatel.** Las tres secciones se descargaron completas (387, 12 y 24 productos). Tres productos están en dos secciones, por eso hay 420 productos únicos y no 423. El scraper marcaba esto como parcial; se corrigió la regla y el estado de esa ejecución (queda registrado en `correcciones`).

### Cambios al scraper del Taller 1

- Agente de usuario identificable, pausa de 1 segundo entre peticiones y tope de 300 peticiones por ejecución.
- Paginación completa de las búsquedas de Farmatodo.
- Disponibilidad: en Farmatodo con `outofstore` y `stores_with_stock` (el campo `hasStock` que usaba el Taller 1 siempre llega en `False`); en Éxito y Locatel con la cantidad disponible.
- `limpiar_precio` convierte precios en número o en texto (`"$ 12.900"`) a número.
- Rutas relativas a la carpeta del proyecto.
- Validación con pandera antes de insertar. Lo que no pasa queda en la tabla `rechazos` con el motivo.
- `recolectar_comercio` recolecta un comercio y lo guarda en una sola transacción. Si falla, registra la ejecución como fallida con el motivo y sigue con los demás.


### Correcciones del Taller 1

La base se creó con `corregir_taller1.py` a partir de la base entregada en el Taller 1. Cada cambio está en la tabla `correcciones` con la fecha, el registro, el valor anterior, el valor nuevo y el motivo. No se borró ninguna observación: las que no cumplen la validación quedan con `descartada = 1` y el motivo.

| Corrección | Registros |
|---|---|
| Disponibilidad de Farmatodo: todo quedaba como agotado porque `hasStock` siempre es `False` | 752 observaciones |
| Precio ausente (Éxito publica en 0 los productos sin oferta): observación descartada | 145 observaciones |
| URL ausente en Farmatodo: observación descartada | 70 observaciones |
| URL de Farmatodo armada con `urlCanonical` | 12 anuncios |
| Contenido no reconocido en nombres como "Caja x 12" o "60 Tab" | 47 anuncios |
| Sabor faltante en productos comparables, tomado del mismo EAN en otro comercio | 6 anuncios y 3 productos |

Además se corrigió el estado de Locatel en la ejecución del 14 de noviembre (de parcial a completa).


## Vistas SQL

| Vista | Qué contiene | Dónde se usa |
|---|---|---|
| `v_observaciones` | Observaciones no descartadas con los datos del anuncio y el precio por unidad de contenido | filtros, tabla de productos, indicadores, distribución de precios, cambios de precio |
| `v_ultimo_precio` | La observación más reciente de cada anuncio | consulta de apoyo |
| `v_cambios_precio` | Anuncios cuyo precio cambió frente a su observación anterior | indicador de cambios de precio |
| `v_comparables` | Precios de los productos comparables en cada ejecución | evolución, precio por unidad, ahorro y canasta |
| `v_disponibilidad` | Cada comparable en cada ejecución de su comercio: disponible, agotado o no observado | disponibilidad de los comparables |
| `v_ejecuciones` | Resumen de cada ejecución | selección de ejecuciones |

El detalle de cada columna está en `diccionario_datos.md`.

## Aplicación

- **Resumen:** seis indicadores en tarjetas, productos y observaciones por comercio, mediana del precio por subcategoría y distribución de precios por comercio. Los filtros del panel lateral (ejecución, comercio, subcategoría, marca, rango de precio, solo promociones, solo comparables y búsqueda por palabras) se aplican aquí y en Productos.
- **Productos:** tabla filtrada con comercio, nombre, marca, presentación, precio, precio por unidad, promoción, disponibilidad, fecha de consulta y enlace. Se puede ordenar con clic en cada columna, y buscar y descargar en CSV con los botones de la esquina de la tabla.
- **Comparar precios:** evolución del precio de un producto comparable, precio por unidad de contenido (una unidad a la vez) y el gráfico de libre elección.
- **Cambios de precio:** compara dos ejecuciones (por defecto las dos más recientes) y muestra lo que subió, bajó, apareció o dejó de observarse, con un umbral para resaltar las variaciones grandes. Los comercios cuya ejecución falló no se comparan, para no confundir "no observado" con "agotado".
- **Canasta:** costo por comercio solo si tiene todos los productos, costo mínimo comprando cada producto donde es más barato y ahorro frente a comprar todo en un solo comercio.
- **Actualizar precios:** botón en línea, que llama a `scraper.recolectar_comercio` y muestra el avance por comercio con `st.status`, y botón sin conexión, que reprocesa `raw/`. Al terminar muestra el resumen por comercio y limpia la caché, así que todo se actualiza sin reiniciar.

**Gráfico de libre elección.** "¿En qué comercio conviene comprar cada presentación?": para cada producto comparable muestra cuánto se ahorra al comprarlo en el comercio más barato frente al más caro, en porcentaje y en pesos, con el color del comercio que conviene. Es la pregunta que se hace un consumidor antes de comprar, y el gráfico permite ver de un vistazo dónde está la diferencia grande y dónde casi da igual.


## Despliegue

La aplicación está publicada en Streamlit Community Cloud desde este repositorio (`lucio_alfonso_munoz_adarme/taller_2/app.py`). Como nos paso con Exito, en los otros comercios se puede generar algun bloqueo por cambios en las restricicones, así que si la actualización en línea falla, se puede usar el modo sin conexión. La plataforma no conserva los cambios de la base al reiniciarse, así que la versión publicada siempre vuelve a la base del repositorio. La actualización en línea funciona en la ejecución local.

## Hallazgos

Los valores se pueden revisar con los datros de la aplicación:

1. **En octubre Éxito era el más barato.** En la ejecución 20261011T114310 (11 de octubre), la única con los tres comercios, Éxito tenía el menor precio en 8 de los 11 comparables, Farmatodo en 2 (bebida Going de uva y proteína Going de vainilla) y Locatel en 1 (Benet Whey, en promoción). La mayor diferencia era la proteína Going de chocolate de 600 g: $135.800 en Éxito y $187.650 en Locatel, 27,6 % menos. (Comparar precios, gráfico de ahorro, ejecución 20261011T114310.)

2. **Entre Farmatodo y Locatel casi da igual dónde comprar.** En la ejecución 20261114T194451 (14 de noviembre), con 10 comparables con precio en los dos, Farmatodo es más barato en 6, Locatel en 3 y en la Crea Stack cuestan lo mismo. Ninguna diferencia pasa de 4,4 %. La canasta con esos 10 productos (una unidad de cada uno) cuesta $980.340 en Farmatodo y $998.050 en Locatel; comprando cada uno donde es más barato, $978.890. En octubre la misma canasta costaba $902.522 en Éxito, así que perder a Éxito como opción le cuesta al consumidor cerca de $76.000 en estos productos. (Canasta.)

3. **Los precios de los comparables casi no cambiaron, pero la promoción de Benet terminó.** Entre el 11 de octubre y el 14 de noviembre ningún comparable cambió de precio en Farmatodo, y en Locatel solo la Benet Whey de 595 g, que pasó de $122.320 a $152.900 (25 % más) porque terminó su promoción. Ahora es más barata en Farmatodo ($148.350). (Comparar precios, evolución del precio de Benet Whey; Cambios de precio.)

4. **En la categoría completa los precios subieron.** Comparando las mismas presentaciones de Farmatodo y Locatel entre 20261011T114310 y 20261114T194451, 24 subieron de precio y solo 1 bajó (el gel Going de granada en Locatel, 30 % menos). Las subidas grandes son de proteínas: la Isolate Gourmet de 2.270 g en Locatel subió 32,2 % y las proteínas Sascha Fitness en Farmatodo 11,9 %. (Cambios de precio, umbral de 10 %.)

## Declaración de uso de IA

Como mecanismo de apoyo use la IA Claude, principalmente para:

- Resolver dudas tecncias respecto a las correciones del scraper, el manejo a darle a la base de datos y como ayuda para la construcción de la pagina web, dado que la experiencia al respecto no era la suficiente;
- Como ayuda para la identificacion de los errores arrojados en el desarrollo del taller.
- Dado el error de bloqueo de Exito, se utilizó para determinar la causa y posibles alternativas, avanzando finalmente sin este comercio para las utlimas recolecciones.