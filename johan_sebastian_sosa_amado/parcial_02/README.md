# Taller 2: comparador de precios en Streamlit (incontinencia y cuidado del adulto)

- **Estudiante:** Johan Sebastian Sosa Amado
- **Taller:** 02, Minería de Datos (2016325), Universidad Nacional de Colombia, sede Bogotá
- **Lenguaje:** Python en todo el proceso (scraping, acceso a datos, aplicación y pruebas), igual que en el Taller 1.
- **Aplicación publicada:** https://comparador-precios-jsosaa.streamlit.app

## Descripción

Aplicación web que convierte el comparador de precios del Taller 1 en una herramienta para el consumidor. Compara la categoría *Incontinencia y cuidado del adulto* en Éxito, La Rebaja y Olímpica, con los mismos 13 productos comparables del Taller 1.

- Consulta la base `comparador_precios.sqlite`, que conserva las recolecciones del Taller 1 y agrega las nuevas.
- Actualiza los precios con un botón que llama a las funciones de `scraper.py` (el mismo módulo del Taller 1, ampliado), en línea o sin conexión desde `raw/`.
- Muestra indicadores, cuatro gráficos interactivos, una tabla descargable, la comparación entre dos recolecciones, una canasta de compra y un catálogo con la foto de cada producto comparable.

La base tiene cinco recolecciones completas de las tres tiendas y una parcial (hora de Colombia):

| Recolección | Fecha | Origen |
|---|---|---|
| `2026-10-09T05-01-44` | 9 oct 2026, 05:01 | Taller 1 |
| `2026-10-10T04-22-07` | 10 oct 2026, 04:22 | Taller 1 |
| `2026-11-07T19-26-16` | 7 nov 2026, 19:26 | Taller 2, `python scraper.py` en línea |
| `2026-11-07T21-24-49` | 7 nov 2026, 21:24 | Taller 2, botón "Actualizar precios" de la aplicación, en línea |
| `2026-11-10T14-02-54` | 10 nov 2026, 14:02 | Taller 2, `python scraper.py` en línea |
| `2026-11-14T04-13-42` | 14 nov 2026, 04:13 | Taller 2, botón "Actualizar precios" de la aplicación, en línea. Parcial: La Rebaja y Olímpica completas; Éxito fallida (el sitio respondió con el código 403) |

## Archivos

```
parcial_02/
  app.py                     configuración, panel de filtros y navegación (st.navigation)
  paginas/                   una página por sección de la aplicación
    resumen.py               indicadores, distribución de precios y promociones
    comparar.py              evolución de un producto, precio por unidad y ahorro
    cambios.py               cambios de precio entre dos recolecciones
    canasta.py               costo de una canasta en cada comercio
    datos.py                 tabla de productos filtrados y descarga CSV
    actualizar.py            botón de actualización y calidad de los datos
    catalogo.py              foto de referencia de cada producto comparable
  ui.py                      caché, colores por comercio, formato y filtros (sin SQL)
  db.py                      capa de acceso a datos: estructura de la base y todas las consultas
  scraper.py                 extracción, limpieza y carga (Taller 1, ampliado)
  validacion.py              reglas que debe cumplir una observación antes de entrar (pandera)
  correcciones.py            correcciones de la base del Taller 1
  comparador_precios.sqlite  base de datos
  diccionario_datos.md       cada tabla, vista y columna de la base
  raw/                       copias crudas de cada ejecución: raw/<tienda>/<fecha-hora>/*.json.gz
  imagenes/                  fotos del catálogo, una por producto comparable (P01.jpg a P13.jpg)
  tests/                     pruebas automáticas (pytest)
  .streamlit/config.toml     tema de la aplicación (no tiene credenciales)
  requirements.txt           dependencias con versiones fijas
  .gitignore
  README.md
```

La interfaz no contiene SQL: las páginas solo llaman funciones de `db.py`, y `db.py` no importa Streamlit.

Las fotos del catálogo son de referencia: se tomaron de las páginas de los productos en las tiendas y no se actualizan con el scraper. Si falta la foto de un producto, su tarjeta dice "Sin foto".

## Ejecución local

Requisitos: Python 3.13. Todos los comandos se corren **desde la carpeta `parcial_02`**; las rutas del código son relativas a esa carpeta.

```powershell
# Windows (PowerShell)
py -3.13 -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

```bash
# macOS o Linux
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**La aplicación:**

```bash
streamlit run app.py
```

Se abre en `http://localhost:8501`. En la página **Actualizar y calidad**, el botón "Actualizar precios" tiene dos modos:

- **En línea:** descarga las tres tiendas, guarda las copias en `raw/` y agrega una recolección nueva. Muestra el avance por comercio (`st.status`) y al final un resumen por comercio con los productos de la categoría, los nuevos, los cambios de precio y los no observados. Si una tienda no responde, ese comercio queda `fallida` con el motivo (por ejemplo, "no hubo conexión con el sitio") y los demás siguen.
- **Sin conexión:** reprocesa la copia completa más reciente de `raw/` de cada tienda. Se salta las carpetas de un intento en línea que falló (sin páginas, con la respuesta de un bloqueo o con páginas faltantes). Si esa copia ya está en la base, no se duplica nada (la columna "Filas guardadas" queda en 0).

**El scraper desde la terminal** (como en el Taller 1):

```bash
python scraper.py                  # en línea, las tres tiendas
python scraper.py --sin-conexion   # reprocesa la última copia completa de raw/
python scraper.py --limpiar        # solo limpieza y emparejamiento
python correcciones.py             # registra y aplica las correcciones del Taller 1 (se puede repetir)
```

## Pruebas

```bash
pytest tests/
```

Hay 13 pruebas en `tests/test_comparador.py`. Usan datos pequeños y una base temporal creada en cada prueba; nunca tocan `comparador_precios.sqlite` ni los sitios de las tiendas. Verifican:

1. conversión de precios en texto a número (`limpiar_precio("$ 12.900") == 12900`);
2. normalización de unidades (`21 und` y `X9 Unds` quedan en unidad, `100 ml` en mL);
3. lectura de la variante de TENA Pants (clásico frente a comfort);
4. ahorro entre comercios con empates (dos tiendas con el mismo precio mínimo);
5. insertar dos veces la misma ejecución no duplica observaciones ni rechazos;
6. detección de cambios de precio entre dos recolecciones (subió, bajó, nuevo, dejó de observarse), con los conteos en SQL y el indicador del resumen;
7. el modo sin conexión toma la última copia completa de `raw/` y se salta las de un intento fallido;
8. una tienda sin conexión queda `fallida`, con un motivo claro y sin insertar nada;
9. la carpeta de `raw/` se guarda como ruta relativa, no con la ruta del equipo;
10. la canasta no da total en un comercio al que le falta un producto;
11. validación: precio no positivo y duplicados se rechazan;
12. validación: URL o fecha vacías se rechazan, y un producto agotado sin precio se acepta;
13. la búsqueda del usuario rechaza texto demasiado largo o con caracteres no permitidos.

## Base de datos

El detalle de cada tabla, vista y columna está en [`diccionario_datos.md`](diccionario_datos.md). Frente al Taller 1, la base agrega:

- tablas `correcciones` y `rechazos`, y `codigos_producto` para que los códigos P01 a P13 no cambien entre corridas;
- `observaciones.estado_disponibilidad` y `observaciones.descartada`; `anuncios.variante`, `anuncios.contenido_total` y `anuncios.unidad_normalizada`;
- un índice único sobre (`anuncio_id`, `ejecucion_id`): la misma observación no puede entrar dos veces en una ejecución;
- índices sobre las columnas de los filtros (comercio, subcategoría, marca, precio, promoción, recolección, producto).

`db.preparar_base()` hace estos cambios sobre la base existente. Se puede correr muchas veces: solo crea lo que falta y nunca borra observaciones.

### Vistas SQL

| Vista | Qué devuelve | Dónde la usa la aplicación |
|---|---|---|
| `v_observaciones` | Una fila por observación de la categoría, no descartada, con comercio, recolección, campos limpios y `precio_unitario` (COP por unidad, mL o g) | Tabla de productos, filtros, indicadores, distribución, promociones |
| `v_ultimo_precio` | Lo mismo, solo para la ejecución más reciente (no fallida) de cada comercio | Ninguna página; sirve para consultar a mano el precio vigente en cada comercio |
| `v_cambios_precio` | Cada cambio de precio de un anuncio frente a su observación anterior (`LAG`), en COP y %, con las columnas de los filtros | Resumen: indicador "Cambios de precio" frente a la recolección anterior |
| `v_comparables` | Precio de cada producto comparable por recolección y comercio, con su puesto (`RANK`, empates incluidos) | Comparar comercios, ahorro, canasta |
| `v_disponibilidad` | Para cada anuncio y cada ejecución de su comercio: `disponible`, `agotado` (según el sitio) o `no observado` (`LEFT JOIN`) | Actualizar y calidad > Disponibilidad |

### Origen de los datos

Todos los precios salen del scraping del servicio JSON que usa la página de cada tienda (plataforma VTEX), como se documentó en el Taller 1. Cada observación lleva su `ejecucion_id`; la tabla `ejecuciones` da la carpeta de `raw/` con la copia cruda de esa ejecución (ruta relativa a `parcial_02/`, por ejemplo `raw\exito\2026-11-07T19-26-16`). Un precio que la tienda no muestra (producto agotado) queda como `NULL`: no se imputa.

## Correcciones del Taller 1

Retroalimentación: *"Algunas variantes por revisar (Tena Pants «clásicos» frente a «comfort»)"*.

**Revisión.** En La Rebaja, los pants de 8 unidades talla M y L (P07 y P06) se llaman "PANTS COMFORT", mientras Éxito y Olímpica los llaman "clásicos". Se revisaron las copias crudas de La Rebaja (`raw/larebaja/2026-10-10T04-22-21`): en la misma respuesta JSON, la URL dice `pants-clasico`, el campo `ML_Titulo` dice "PANTS CLASICO" y la foto se llama "PANTS-CLASICO". El EAN, la talla y las unidades coinciden con los de las otras dos tiendas, y la ficha del paquete de 16 explica el nombre: "TENA Pants Clásico […] con sistema Confort Care". **Es el mismo producto: el emparejamiento era correcto**, pero el nombre visible de La Rebaja confunde la variante.

En la misma revisión apareció otro error: Éxito publica los pants clásicos de 16 unidades como "(1 und)", aunque la URL y la foto del anuncio dicen "16-unidad" y La Rebaja publica el mismo EAN como "PAQUETE X 16 UND". El contenido se había extraído como 1.

**Qué se cambió.** No se modificó la carpeta del Taller 1 ni se borró ninguna observación. Cada cambio es una fila de la tabla `correcciones` (fecha, registro, valor anterior, valor nuevo y motivo con la evidencia):

| Registro | Campo | Antes | Después |
|---|---|---|---|
| La Rebaja SKU 9659 (P07), 9660 (P06), 14514 y 14513 | `variante` | `comfort` | `clasico` |
| Éxito SKU 1783610 y 1783475 | `contenido` | 1 | 16 |

Además, la limpieza ahora lee la variante del nombre (`clasico`, `comfort`, `ultra`, `nocturno`, `discreet`, `basic`) y no empareja dos anuncios con el mismo EAN si sus variantes no coinciden; esos casos quedan "por revisar". `db.aplicar_correcciones()` vuelve a aplicar las correcciones después de cada limpieza, para que una actualización no las deshaga. Las correcciones se ven en la aplicación, en **Actualizar y calidad > Correcciones**.

## Validación antes de insertar

`validacion.py` define las reglas con pandera. Lo que no las cumple no entra a `observaciones` y queda en la tabla `rechazos` con la regla que falló:

1. precio numérico y mayor que cero; un producto sin precio solo se acepta si el sitio lo marca agotado;
2. comercio, URL y fecha y hora de consulta presentes;
3. sin observaciones duplicadas (mismo comercio y SKU) en la misma ejecución;
4. al menos 8 productos comparables con precio en cada comercio; si no, la ejecución queda `parcial` y el motivo se registra.

Cada comercio se guarda en una transacción: si algo falla, no queda nada a medias de ese comercio y se sigue con los demás.

## Seguridad

- **Credenciales:** la aplicación no usa ninguna. `.streamlit/secrets.toml` está en `.gitignore` por si se necesitara; `.streamlit/config.toml` solo tiene el tema.
- **Consultas parametrizadas:** todo valor del usuario (comercio, marca, precios, búsqueda, cantidades de la canasta) va como parámetro `?`. En el texto de la consulta solo se insertan marcadores.
- **Entradas validadas:** la búsqueda acepta máximo 60 caracteres y solo letras, números, espacios y `. , ( ) / % + -`.
- **Lectura:** las consultas de la aplicación abren la base en modo de solo lectura y cierran la conexión al terminar.
- **Scraping:** se revisa el `robots.txt` de cada tienda, hay una pausa de 2 segundos entre páginas, un tope de 100 páginas por tienda y un agente de usuario identificable (`ComparadorPreciosUNAL/2.0 (Mineria de Datos 2016325; uso academico)`).

## Despliegue

La aplicación está publicada en Streamlit Community Cloud desde la rama `entrega-taller-02` del fork, con archivo principal `johan_sebastian_sosa_amado/parcial_02/app.py` y Python 3.13.

- **La plataforma gratuita no conserva los cambios en la base al reiniciarse.** Una actualización hecha en la aplicación publicada dura hasta que el servidor se reinicia; la base del repositorio no cambia.
- Las tiendas suelen bloquear las direcciones de estas plataformas. Si el botón en línea no obtiene datos, la aplicación marca cada comercio como `fallida`, muestra el motivo y recomienda el modo **Sin conexión**, que reprocesa la última copia completa de `raw/`. La actualización en línea funciona en la ejecución local.

## Hallazgos para el consumidor

Basados en las recolecciones `2026-10-10T04-22-07` (10 oct 2026, 04:22), `2026-11-07T19-26-16` (7 nov 2026, 19:26) y `2026-11-10T14-02-54` (10 nov 2026, 14:02), con los 13 productos comparables. Precios en COP con las promociones de cada día.

1. **Ninguna tienda es la más barata en todo, y comprar repartido ahorra.** Una canasta con una unidad de cada producto comparable costaba el 10 nov 616.060 en La Rebaja, 671.170 en Olímpica y 712.802 en Éxito. Comprando cada producto donde es más barato cuesta 575.930: 40.130 menos que en La Rebaja y 136.872 menos que en Éxito. Ese día La Rebaja era la más barata en 6 productos, Olímpica en 5 y Éxito en 2. *Verificar en: Canasta (recolección del 10 nov, cantidad 1 en los 13 productos).*

2. **El comercio más barato cambia de un mes a otro: hay que mirar la fecha.** Los TENA Pants Ultra de 20 unidades (P08 talla L y P09 talla M) eran más baratos en Éxito el 10 oct (75.240 y 68.508). El 10 nov Éxito los vendía a 114.000 y 103.800 (51,5 % más) y era el más caro; el más barato era Olímpica (79.170 y 70.770). Entre esas dos fechas Éxito subió el precio de 9 de sus 13 comparables y bajó 4, Olímpica subió 9 y bajó 3 (entre ellos P08 y P09), y La Rebaja dejó 9 iguales y bajó 4. *Verificar en: Comparar comercios > Evolución del precio (P08, P09) y Cambios de precio (10 oct frente a 10 nov, ordenando por la columna Comparable).*

3. **En pocos días los precios casi no cambian, pero un solo cambio mueve la canasta.** Del 7 al 10 nov solo cambió un comparable: La Rebaja bajó las toallas TENA Discreet súper (P10) de 61.600 a 49.280 (20 % menos), el mismo precio que tenía el 10 oct. Con eso pasó a ser la más barata en ese producto y su canasta bajó de 628.380 a 616.060. *Verificar en: Cambios de precio (7 nov frente a 10 nov) y Comparar comercios > Evolución del precio (P10).*

4. **Más promociones no es más ahorro.** El 10 nov Éxito tenía en promoción el 43,9 % de sus productos con precio, frente al 22,7 % de La Rebaja y el 11,1 % de Olímpica, pero su descuento mediano era 15 %, frente a 20 % y 25 %. De los 6 comparables de Éxito en promoción, solo 2 eran los más baratos de las tres tiendas. *Verificar en: Resumen > "¿Dónde hay más promociones y cuánto descuentan de verdad?" con la recolección del 10 nov.*

5. **El paquete grande no siempre sale más barato por pañal.** El 10 nov, TENA Slip Comfort talla L en paquete de 21 (P01) costaba 2.400 por pañal en La Rebaja, frente a 3.600 en su paquete de 9 (P02). En Éxito y Olímpica pasaba lo contrario: el de 21 costaba 3.724 y 3.469 por pañal, y el de 9, 3.178 y 2.888. Conviene mirar el precio por unidad antes de elegir el paquete. *Verificar en: Comparar comercios > Precio por unidad (recolección del 10 nov).*

### Gráfico de libre elección

**Pregunta:** *¿En qué tienda hay más productos en promoción y cuánto descuentan de verdad?* (página Resumen). Muchas personas eligen tienda por la cantidad de ofertas que ve. El gráfico muestra, por comercio, la proporción de productos en promoción y, debajo, el descuento mediano (precio antes frente a precio actual). Así se ve que la tienda con más ofertas no es la que más descuenta (hallazgo 4). Las barras empiezan en cero y cada comercio conserva su color.

## Herramientas

Python 3.13 con requests (descarga), pandas y numpy (limpieza), sqlite3 (base de datos), pandera (validación), Streamlit (aplicación), plotly (gráficos) y pytest (pruebas). Las versiones exactas están en `requirements.txt`.

## Declaración de uso de IA

- **Herramienta:** Claude (Anthropic), como asistente de programación y redacción.
- **Para qué:** plan del taller a partir del enunciado y de las clases; revisión de la variante de TENA Pants en las copias de `raw/`; código de `db.py`, `validacion.py`, `correcciones.py`, la aplicación (`app.py`, `ui.py`, `paginas/`) y las pruebas; ampliación de `scraper.py`; borradores del diccionario de datos y de este README. 
- **Cómo se verificó:** ejecuté el scraper en línea y sin conexión en mi equipo y revisé el resumen de cada comercio; corrí `correcciones.py` y revisé la tabla resultante; recorrí todas las páginas de la aplicación con filtros distintos; corrí `pytest tests/` (todas pasan); comparé los indicadores y los hallazgos con consultas directas a la base; revisé contra las copias de `raw/` la evidencia de la corrección de TENA Pants.

## Limitaciones

- Los precios son los que mostraba cada tienda en el momento de la consulta, con las promociones de ese día. La canasta no incluye envío, mínimos de compra ni condiciones de las promociones.
- Un producto "no observado" en una ejecución no se interpreta como agotado ni como retirado.
- El texto original de cada anuncio se guarda la primera vez que aparece; si la tienda lo cambia después, el texto nuevo queda en `raw/`, no en la base.
