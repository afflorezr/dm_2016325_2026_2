# Taller 2 — Comparador de precios de protectores solares (Streamlit)

**Asignatura:** Minería de Datos (2016325) · **Lenguaje:** Python 3.13 (scraping, acceso a datos, aplicación y pruebas) · **Marco:** Streamlit

**Aplicación publicada:** https://comparador-solares.streamlit.app/

La aplicación convierte el comparador del Taller 1 en una herramienta web que consulta la base SQLite, la actualiza mediante el mismo web scraping y orienta al consumidor sobre dónde comprar un producto o una canasta de productos.

- **Categoría:** protectores solares faciales (con y sin color), corporales, labiales, infantiles y productos para después del sol.
- **Comercios (los mismos del Taller 1):** Bella Piel, Drogas La Rebaja y Locatel Colombia. Droguerías Colsubsidio y Medipiel siguen excluidas porque su `robots.txt` prohíbe las consultas a la API o con parámetros.
- **Origen de los datos:** API pública de catálogo VTEX que cada sitio usa para mostrar sus productos (`/api/catalog_system/pub/products/search`), identificada en el Taller 1 con las herramientas de desarrollador del navegador (pestaña *Red*). Cada observación se rastrea hasta su copia cruda en `raw/` (columna `ejecuciones.archivo_raw`) y su ejecución.

---

## 1. Ejecución local

```bash
# Desde la carpeta taller_2/
python -m venv venv
source venv/bin/activate          # Windows: .\venv\Scripts\activate
pip install -r requirements.txt

streamlit run app.py              # abre http://localhost:8501
```

Actualización por línea de comandos (equivalente al botón de la aplicación):

```bash
python actualizacion.py            # en línea: consulta los tres sitios y guarda copias en raw/
python actualizacion.py --offline  # sin conexión: reprocesa la copia más reciente de raw/
```

`python migracion_taller2.py` aplica el esquema del Taller 2 y las correcciones a la base del Taller 1. Ya está aplicado en la base entregada; si se vuelve a ejecutar, no repite nada.

## 2. Pruebas automáticas

```bash
pytest tests/
```

28 casos en `tests/test_comparador.py` (pytest). Usan una base SQLite temporal y datos pequeños; nunca la base de la entrega ni los sitios. Verifican: conversión de precios en texto a número, normalización de unidades, extracción del contenido, cálculo del ahorro con empates, que insertar dos veces la misma ejecución no duplica observaciones, detección de cambios de precio, que la canasta no se calcula cuando falta un producto, validación con motivo de rechazo, búsqueda con parámetros (sin inyección SQL), modo sin conexión y tolerancia a la falla de un comercio.

## 3. Estructura de archivos

```text
taller_2/
├── app.py                    # Entrada de Streamlit: configuración, filtros laterales y navegación multipágina
├── paginas/                  # Una página por sección (sin SQL)
│   ├── resumen.py            #   indicadores, distribución, mediana por subcategoría, gráfico de libre elección
│   ├── productos.py          #   tabla filtrada con descarga CSV
│   ├── comparables.py        #   evolución del precio, precio por unidad, dónde comprar cada comparable
│   ├── cambios.py            #   comparación entre dos ejecuciones
│   ├── canasta.py            #   canasta por comercio y compra óptima
│   ├── actualizar.py         #   botón de actualización (en línea y sin conexión) e historial
│   └── calidad.py            #   origen, disponibilidad, correcciones y rechazos
├── componentes.py            # Colores por comercio, formato COP/fechas, panel de filtros
├── datos_cache.py            # Caché (st.cache_data) sobre las funciones de db.py
├── db.py                     # Capa de acceso a datos: esquema, vistas, inserción transaccional y consultas
├── scraper.py                # Extracción (Taller 1 ajustado): recolectar_comercio() por comercio
├── validacion.py             # Reglas de validación con pandera
├── actualizacion.py          # Orquestación: scraper -> validación -> inserción, tolerante a fallas
├── migracion_taller2.py      # Migración y corrección documentada de la base del Taller 1
├── comparador_precios.sqlite # Base de datos
├── diccionario_datos.md      # Tablas, vistas y columnas: significado, tipo, unidad y valores posibles
├── raw/                      # Copias crudas .json.gz por comercio y fecha
├── tests/                    # Pruebas pytest
├── .streamlit/config.toml    # Tema y opciones de la interfaz (sin credenciales)
├── requirements.txt          # Dependencias con versiones fijas
└── README.md
```

Todas las rutas son relativas a la carpeta del proyecto (`Path(__file__).parent`); no hay rutas absolutas.

## 4. Cómo responde a cada módulo

**Módulo 1 — Datos.**
- *Corrección del Taller 1:* `migracion_taller2.py` reprocesó las mismas copias crudas del 10/10/2026 con las reglas corregidas. Quedaron 469 correcciones en la tabla `correcciones`, con fecha, registro, valor anterior, valor nuevo y motivo. No se borró ninguna observación ni se modificó ningún precio; además se verificó que los 813 precios coinciden con su copia cruda. Errores corregidos:
  - 18 protectores mal excluidos: 11 como «kit», porque el «+» de «FPS 50+» se leía como combo; 6 como maquillaje («Ruboril» coincidía con «rubor»; «Protector Solar… Primer»); y 1 sérum solar con FPS 50;
  - 7 productos fuera de la categoría que estaban incluidos (acondicionador capilar, cremas faciales de tratamiento sin FPS, bálsamo labial sin FPS, estuche y combo);
  - contenidos mal extraídos (no se reconocía «Grs», la descripción tenía prioridad sobre el nombre, combos con un contenido único);
  - 373 códigos internos o vacíos guardados como EAN.

  Las 33 observaciones comparables (11 productos × 3 comercios) no cambiaron.
- *Historial:* la base contiene dos ejecuciones completas en línea: la del Taller 1 (ejecución 1, 10/10/2026, 813 observaciones) y la del Taller 2 (ejecución 2, 10/11/2026, 815 observaciones; los tres comercios completos y con los 11 comparables). Las nuevas ejecuciones se agregan sin sobrescribir y conservan su copia cruda, fecha y hora e identificador.
- *Validación:* `validacion.py` (pandera) exige precio numérico mayor que cero; comercio, URL y fecha presentes; ausencia de duplicados en la ejecución; unidad normalizada y disponibilidad válida. Las filas que no cumplen van a `observaciones_rechazadas` con el motivo. Si un comercio tiene menos de 8 comparables, la ejecución queda `parcial` y se listan los faltantes.
- *Disponibilidad:* `disponible` y `agotado` vienen de `commertialOffer.IsAvailable`; `no_observado` se deriva en la vista `v_disponibilidad` y no se interpreta como agotado ni retirado.
- *Estructura:* restricción `UNIQUE (comercio, id_producto_comercio, fecha_hora_consulta)`, 13 índices, disparadores de dominio, 7 vistas y `diccionario_datos.md`.

**Módulo 2 — Actualización.** El botón llama a `actualizacion.actualizar()`, que usa `scraper.recolectar_comercio()`: el scraper no se copia dentro de la aplicación. El avance por comercio se muestra con `st.status`. Cada comercio se inserta en una transacción (`with con:`); si falla, se revierte, la ejecución queda `fallida` con su motivo y se continúa con los demás. Al terminar se muestran, por comercio, productos recolectados, observaciones insertadas, productos nuevos, cambios de precio y no observados. Luego se invalida la caché y se recarga la página, sin reiniciar la aplicación. El modo sin conexión permite elegir la copia cruda de cada comercio.

**Módulo 3 — Consultas.** Todo el SQL está en `db.py`, en funciones que reciben los filtros como argumentos (`db.Filtros`) y devuelven tablas. Filtros, indicadores, medianas (funciones de ventana), ahorro, sobrecosto, cambios y canasta se calculan en SQLite; la aplicación nunca lee la tabla completa para filtrarla en memoria. La caché vive en `datos_cache.py` (`st.cache_data`) y se limpia al terminar una actualización. Cada consulta abre una conexión de solo lectura con un administrador de contexto que la cierra siempre.

**Módulo 4 — Seguridad.**
- La aplicación no usa credenciales. `.streamlit/secrets.toml` y `.env` están en `.gitignore`.
- Todo valor del usuario viaja como parámetro `?`; en el texto SQL solo se insertan marcadores generados por el código.
- La búsqueda se valida con un máximo de 60 caracteres y una lista de caracteres permitidos, y escapa los comodines de `LIKE`.
- El scraping usa un agente de usuario identificable, una pausa de 1 s entre peticiones y un máximo de 20 peticiones por comercio.

**Módulo 5 — Presentación.**
- Navegación multipágina (`st.navigation`) con indicadores en tarjetas y colores fijos por comercio: Bella Piel magenta, La Rebaja azul y Locatel verde.
- COP, unidades y fecha de los datos visibles en todas las páginas, con formato colombiano ($ 123.456).
- Mensajes en español cuando un filtro no devuelve datos o cuando ocurre un error.
- Filtros laterales combinables: comercio (múltiple), subcategoría, marca, rango de precio, ejecución o rango de fechas, solo promociones, solo comparables y búsqueda en el nombre o el texto del anuncio.
- 7 indicadores en tarjetas (más tablas por comercio y por subcategoría), 4 gráficos exigidos más 2 complementarios (plotly) y una tabla que se puede ordenar, buscar y descargar en CSV.

**Módulo 6 — Análisis para el consumidor.**
- Precio por mL y por g en pestañas separadas, para no mezclar unidades.
- Comparación de dos ejecuciones elegidas (por defecto, las dos más recientes), con umbral ajustable que resalta las variaciones grandes.
- Canasta con cantidades: el total solo aparece si el comercio tiene todos los productos; si no, se indica qué falta. Incluye la compra óptima (empates listados) y el ahorro frente al mejor comercio único, con la advertencia sobre envío, mínimos y promociones.

**Módulos 7 y 8 — Calidad y despliegue.** Ver secciones 1 a 3 y 7.

## 5. Vistas SQL

| Vista | Descripción |
|---|---|
| `v_corridas` | Ejecuciones con datos, fecha de los datos y orden cronológico |
| `v_observaciones` | Observaciones no descartadas con la fecha y el orden de su ejecución (base de filtros y tabla) |
| `v_ultimo_precio` | Último precio observado de cada anuncio, por comercio |
| `v_comparables` | Precios de los comparables con mínimo por producto y ejecución, diferencia frente al mínimo y marca de «más barato» (empates incluidos) |
| `v_cambios_precio` | Precio de cada anuncio frente a su observación anterior, en COP y %, con dirección |
| `v_disponibilidad` | Disponible, agotado, sin información o no observado, por anuncio y ejecución |
| `v_resumen_ejecuciones` | Resumen por ejecución de comercio (estado, conteos, copia cruda y motivo) |

## 6. Gráficos

1. **Evolución del precio** de un comparable elegido, con una serie por comercio.
2. **Precio por unidad** (COP/mL o COP/g) de los comparables, sin mezclar unidades.
3. **Distribución de precios** de la categoría por comercio (diagrama de caja).
4. **Gráfico de libre elección — «¿En qué comercio conviene comprar los productos comparables?».** Muestra, por comercio, el sobrecosto promedio (%) frente al comercio más barato de cada comparable disponible, con el número de veces que es el más barato. Responde la duda práctica de quien no quiere revisar producto por producto: en qué tienda suele pagar menos y cuánto más pagaría en las otras. Los agotados se excluyen porque no se pueden comprar.

Complementarios: precio mediano por subcategoría (Resumen) y estado de disponibilidad por comercio (Origen y calidad).

## 7. Despliegue

Publicada en Streamlit Community Cloud desde el repositorio del curso: archivo principal `taller_2/app.py` y Python 3.13 en *Advanced settings*. La aplicación no necesita secretos; si en el futuro se requieren, se configuran en *Settings › Secrets* de la plataforma, nunca en el código.

- Los comercios suelen bloquear las peticiones desde servidores en la nube. En ese caso, la página *Actualizar datos* lo informa con claridad y ofrece el **modo sin conexión**, que reprocesa `raw/`.
- La plataforma gratuita no conserva los cambios en la base cuando reinicia la aplicación: vuelve a la versión del repositorio. La actualización en línea con persistencia se hace en la ejecución local.

## 8. Hallazgos para el consumidor

Basados en la **ejecución 1 (10/10/2026, 02:53)** y la **ejecución 2 (10/11/2026, 23:20)**, ambas completas. Se pueden verificar en las páginas *Cambios de precio* (ejecución anterior 1, posterior 2), *Comparables y precio unitario*, *Canasta* y *Resumen*.

1. **En un mes predominaron las subidas, explicadas sobre todo por el fin de promociones.** De los anuncios observados en ambas ejecuciones, 164 cambiaron de precio: 121 subieron y 43 bajaron (Bella Piel 70 y 19; La Rebaja 19 y 9; Locatel 32 y 15). En 76 de las 121 subidas el producto estaba en promoción en octubre y ya no lo estaba en noviembre; por eso la proporción de productos en promoción cayó en los tres comercios (Bella Piel, de 32,9 % a 26,9 %; La Rebaja, de 24,0 % a 17,2 %; Locatel, de 15,5 % a 10,8 %). La mayor subida en un mismo anuncio fue la de Anthelios Family Spray SPF 50 de 300 ml en Bella Piel: de $ 176.962 a $ 235.950 (+$ 58.988; +33,3 %). La mayor bajada fue la de Eucerin Sérum + Protector Solar UV FPS 50 de 30 ml en Locatel: de $ 153.800 a $ 107.660 (−$ 46.140; −30,0 %).
2. **La canasta de los 11 comparables se encareció, pero la compra repartida sigue ahorrando cerca de $ 280.000.** Con una unidad de cada producto, la canasta pasó de $ 1.570.440 a $ 1.621.584 en Bella Piel y de $ 1.592.725 a $ 1.626.860 en Locatel; la diferencia entre ambos se redujo a $ 5.276. Comprando cada producto donde es más barato cuesta $ 1.339.994 en noviembre ($ 1.277.395 en octubre), es decir, $ 281.590 menos que en el mejor comercio único. De los 33 precios comparables, cambiaron 13: los dos Umbrella bajaron 20 % en Locatel (Urban, de $ 145.200 a $ 116.160; Acqua, de $ 124.750 a $ 99.800), mientras que los dos Cetaphil subieron 33,3 % en Locatel y los cuatro Eucerin de La Rebaja subieron 6,7 %.
3. **La Rebaja sigue siendo la más barata en lo que tiene disponible, pero sigue sin poder completar la canasta.** En noviembre es el comercio más barato en sus 5 comparables disponibles; los mismos 6 comparables de octubre aparecen como agotados según el sitio, al igual que el 46 % de su catálogo de la categoría (58 de 126 anuncios). La mayor diferencia entre comercios se mantuvo idéntica en ambas ejecuciones: Sunaid Evolution Protector Solar Gel FPS 50+ de 40 g cuesta $ 77.850 en La Rebaja y $ 173.100 en Bella Piel ($ 95.250; 55 %).
4. **Entre Bella Piel y Locatel no hay un ganador fijo: depende de la marca.** En noviembre, Bella Piel es más barato en los dos La Roche-Posay y en Eucerin Pigment Control; Locatel, en Umbrella, Cetaphil, Sunaid y Eucerin Oil Control (por $ 50); en Eucerin Hydro Fluid y Photoaging Control empatan. El sobrecosto promedio frente al más barato de los dos es de 7,3 % en Bella Piel y 8,2 % en Locatel.

## 9. Declaración de uso de inteligencia artificial

Se utilizó Claude (Anthropic) como asistente de programación y redacción para el desarrollo de la aplicación, la capa de acceso a datos, la validación, las pruebas, el diccionario de datos y el README, así como para auditar la base del Taller 1. Antigravity (Google) se usó para instalar el entorno local, ejecutar la recolección en línea del 10/11/2026 y revisar las páginas de la aplicación en el navegador.

El alcance se definió a partir del enunciado del taller. La nueva recolección, las correcciones aplicadas a la base y los resultados se revisaron mediante las pruebas automáticas, consultas independientes sobre la base y el recorrido de todas las páginas. Todo el código y los textos entregados fueron revisados y pueden explicarse en su totalidad.
