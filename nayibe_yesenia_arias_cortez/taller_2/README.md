# Taller 2 · Comparador de precios de cuidado capilar

**Minería de Datos (2016325) · Universidad Nacional de Colombia · Nayibe Yesenia Arias Cortez**

Aplicación web en **Streamlit (Python 3.12)** que consulta la base SQLite del Taller 1, la actualiza con el scraper
del Taller 1 y orienta al consumidor sobre dónde comprar un producto o una canasta de productos.
La categoría es **cuidado capilar** y los comercios son **La Rebaja**, **Locatel** y **Droguerías Cafam**.

- **Aplicación publicada:** _(enlace pendiente: se agrega en el Módulo 8, despliegue)_
- **Lenguaje:** todo el proceso (scraping, acceso a datos, aplicación y pruebas) está en **Python 3.12**.

---

## 1. Ejecutar localmente

Desde la carpeta `taller_2/`:

```bash
python3.12 -m venv .venv
source .venv/bin/activate          # en Windows: .venv\Scripts\activate
pip install -r requirements.txt
streamlit run app.py
```

La aplicación abre en `http://localhost:8501`. Usa `comparador_precios.sqlite` y `raw/`, que vienen en esta
carpeta; no necesita credenciales.

**Actualizar precios sin abrir la app** (opcional):

```bash
python actualizacion.py                      # ejecución nueva EN LÍNEA (consulta los 3 sitios, ~3 min)
python actualizacion.py --offline            # reprocesa la última ejecución guardada en raw/
```

## 2. Ejecutar las pruebas

```bash
pytest
```

Son 9 pruebas en `tests/` y deben pasar todas. Usan una **base temporal** con datos ficticios pequeños: nunca usan
la base de la entrega ni consultan los sitios (la red queda bloqueada durante las pruebas). Cubren:
- la conversión de un precio en texto a número;
- la normalización de unidades;
- la validación antes de insertar;
- que insertar dos veces la misma ejecución no duplica datos;
- la detección de cambios de precio;
- el ahorro con empates;
- que la canasta no se calcula cuando falta un producto;
- las entradas maliciosas (inyección SQL);
- el tope de peticiones del scraper.

## 3. Estructura de archivos

```
taller_2/
├── app.py                 # entrada de Streamlit: navegación (st.navigation), filtros laterales, fecha de los datos
├── paginas/
│   ├── resumen.py         # indicadores en tarjetas, distribución de precios, tabla filtrada + CSV
│   ├── comparar.py        # evolución del precio, precio por mL/g, gráfico libre
│   ├── cambios.py         # comparación de dos ejecuciones con umbral ajustable
│   ├── canasta.py         # canasta por comercio, costo mínimo y ahorro
│   └── actualizar.py      # botón de actualización (en línea / sin conexión) con st.status
├── componentes.py         # caché (st.cache_data), colores por comercio, formatos, filtros, mensajes
├── db.py                  # TODO el SQL: conexión controlada, migración, vistas, consultas parametrizadas
├── validacion.py          # reglas de pandera antes de insertar
├── actualizacion.py       # recolectar → validar → guardar, un comercio por transacción
├── scraper.py             # scraper del Taller 1 (cambios del Taller 2 marcados con [CAMBIO])
├── comparables.py         # correspondencia por EAN del Taller 1 (los 18 comparables quedan fijos)
├── comparador_precios.sqlite
├── diccionario_datos.md   # cada tabla, vista y columna: significado, tipo, unidad y valores
├── raw/                   # copias crudas de cada respuesta: raw/<comercio>/<fecha>/<id_ejecucion>/ + manifiesto.json
├── docs/                  # enunciado, fuentes de scraping y delimitación de la categoría
├── tests/                 # pruebas con pytest (conftest.py arma la base temporal)
├── pytest.ini
└── requirements.txt       # dependencias con versiones fijas
```

La interfaz (`app.py`, `componentes.py`, `paginas/`) **no contiene SQL**: pide los datos a `db.py` a través de
`componentes.consultar()`, que guarda los resultados en caché. La caché se limpia al terminar una actualización.

## 4. Datos

- **Origen.** Todos los precios vienen del scraper (`scraper.py`), ejecutado sobre los sitios:
  - La Rebaja y Locatel: API pública de catálogo VTEX;
  - Cafam: el HTML de la categoría con su JSON `__STATE__`, porque su `robots.txt` prohíbe `/api/`.
  
  El detalle está en `docs/fuentes_scraping.md`. Cada observación se puede rastrear hasta su copia cruda en
  `raw/` y su ejecución en la tabla `ejecuciones`.
- **Ejecuciones.** Hay 4, todas `completa`, en **3 fechas**:
  - Taller 1: 09/10/2026 (dos ejecuciones) y 10/10/2026;
  - Taller 2: **08/11/2026** (`20261108T163807`).
  
  En total hay 5.804 observaciones.
- **Validación (pandera, `validacion.py`).** Ninguna observación entra sin cumplir estas reglas:
  - precio numérico y mayor que 0;
  - comercio, URL, fecha y hora presentes;
  - sin duplicados en la misma ejecución;
  - al menos 8 de los 18 comparables por comercio.
  
  Las observaciones rechazadas quedan en la tabla `rechazos` con su motivo. Hoy son 4 de Locatel sin precio.
- **Correcciones (tabla `correcciones`, 13 filas).** No se borró ninguna observación:
  - 12 observaciones del Taller 1 con precio NULL se marcaron como `descartada = 1`;
  - el estado de La Rebaja en la ejecución del 08/11/2026 pasó de `parcial` a `completa` (ver la decisión 3).
- **Disponibilidad.** Se distinguen tres situaciones: `disponible`, `agotado` (según el sitio) y `no_observado`
  (el anuncio no apareció en esa ejecución). Cafam no informa agotados: publica siempre 10.000 unidades.
- **Diccionario de datos:** `diccionario_datos.md`.

### Decisiones documentadas
1. **Un precio ausente se rechaza; no se inventa.** Queda en `rechazos` (§3.1, §3.4).
2. **Los 18 comparables del Taller 1 quedan fijos** (los mismos SKU), para que la historia sea comparable entre
   fechas. `comparables.py` no se vuelve a ejecutar.
3. **Una ejecución es `completa`** si obtuvo toda la categoría que reporta el sitio y tiene al menos los **8**
   comparables que exige el §3.3. Si falta algún comparable, queda anotado. El 08/11/2026 La Rebaja dejó de
   publicar 2 comparables (SKU 18052 y 54769): su ejecución es completa (387/387 productos, 16 comparables), con
   esa nota.
4. **La canasta usa solo productos disponibles.** Un producto agotado cuenta como faltante.
5. **Tope de 60 peticiones por comercio en cada ejecución**, con 1 s de pausa entre peticiones, un agente de
   usuario identificable y reintentos con espera creciente (§6).

## 5. Vistas SQL que usa la aplicación

| Vista | Qué contiene | Dónde se usa |
|---|---|---|
| `v_precios` | Todas las observaciones válidas (sin descartadas y dentro de la categoría), con precio por unidad de contenido (COP/mL, COP/g o COP/unidad) | Tabla filtrada, distribución de precios, filtros por ejecución o fechas, comparación de dos ejecuciones |
| `v_ultimo_precio` | Las de `v_precios` de la última ejecución no fallida de cada comercio | Indicadores y tabla por defecto |
| `v_cambios_precio` | El mismo anuncio en el mismo comercio entre ejecuciones consecutivas: precio anterior, actual, diferencia (COP), variación (%) y tipo (`subió`, `bajó`, `sin cambio`) | Indicador «cambios de precio», resumen de la actualización |
| `v_comparables` | Los 18 comparables por ejecución y comercio, con precio por mL o g | Evolución del precio, precio por unidad, ahorro, canasta, gráfico libre |
| `v_disponibilidad` | Por ejecución y anuncio: `disponible`, `agotado` o `no_observado` | Indicador de agotados, resumen de la actualización |

`v_observaciones` es la vista del Taller 1 y se conserva sin cambios.

## 6. La aplicación

| Página | Contenido |
|---|---|
| **Resumen** | 8 indicadores, cada uno con su unidad y periodo: productos, observaciones, % en promoción, precio promedio, fecha y estado de la última ejecución, ahorro máximo entre comercios, cambios de precio, agotados. También: tablas por comercio y mediana por subcategoría, **gráfico 3** (distribución de precios por comercio) y la tabla filtrada (ordenar, buscar y descargar CSV) |
| **Productos comparables** | **Gráfico 1** (evolución del precio de un comparable, una serie por comercio), **gráfico 2** (precio por mL o g, sin mezclar unidades), **gráfico 4** (libre) y la tabla de ahorro por producto |
| **Cambios de precio** | Dos ejecuciones a elección (por defecto, las dos más recientes): qué subió y qué bajó (COP y %), qué es nuevo y qué dejó de observarse, con un umbral ajustable que resalta las variaciones grandes |
| **Canasta** | Productos y cantidades: total por comercio (o «incompleta: falta X»), costo mínimo comprando cada producto donde es más barato y ahorro frente al mejor comercio único. Advierte que no incluye envío, mínimos de compra ni condiciones de las promociones |
| **Actualizar precios** | Botón en línea o sin conexión (reprocesa `raw/`), avance por comercio con `st.status` y resumen: recolectados, nuevos, cambios y no observados |

Cada comercio tiene el mismo color en toda la app: La Rebaja rojo, Locatel verde y Cafam azul. Los filtros del panel
lateral son comercio, subcategoría, marca, rango de precio, ejecución o rango de fechas, solo promociones, solo
comparables y búsqueda por palabras. Se aplican en SQL con parámetros `?`.

**Gráfico 4 (libre): ¿en qué comercio conviene comprar?** Responde la pregunta del consumidor que solo va a una
tienda: *«¿cuál tiene el precio más bajo en más productos?»*.
- Para cada uno de los 18 productos comparables disponibles (mismo EAN y contenido en los tres comercios) cuenta en
  cuántos cada comercio tiene el precio mínimo. En un empate, cuenta para todos los empatados.
- Se usan solo comparables porque comparar el precio promedio de toda la categoría mezclaría productos distintos.
- Contar victorias, en lugar de sumar pesos, evita que un solo producto caro decida el resultado.

## 7. Hallazgos para el consumidor

Se basan en la ejecución `20261010T184400` (10/10/2026, Taller 1) y en la `20261108T163807` (08/11/2026,
Taller 2). Todos se pueden verificar en la aplicación.

1. **El comercio más conveniente cambió en un mes: de Cafam a Locatel.**
   - El 10/10/2026, Cafam tenía el precio más bajo en 7 de los 18 comparables, y la canasta de los 18 (una unidad
     de cada uno) costaba **$582.630 en Cafam**, frente a $602.720 en La Rebaja y $606.188 en Locatel.
   - El 08/11/2026, Locatel es el más barato en 7 de 18, y la canasta cuesta **$605.926 en Locatel** frente a
     $631.700 en Cafam. En La Rebaja no se puede calcular: solo tiene 15 de los 18 disponibles.
   - *Dónde verlo:* Productos comparables → gráfico 3; Canasta con los 18 productos y cada ejecución.
2. **Terminaron muchas promociones en La Rebaja y Cafam; Locatel bajó precios.**
   - Entre las dos ejecuciones, la proporción de observaciones en promoción cayó en La Rebaja de 19,9 % a 2,5 % y en
     Cafam de 31,3 % a 15,8 %. En Locatel subió de 15,2 % a 22,0 %.
   - En los mismos anuncios, La Rebaja subió 66 precios y bajó 3, y Cafam subió 63 y bajó 19. Locatel bajó 79 y
     subió 70.
   - Ejemplo: el acondicionador Tío Nacho Henna Egipcia 415 mL en Cafam pasó de $26.950 (promoción) a $38.500
     (+42,9 %).
   - *Dónde verlo:* Cambios de precio (A = 10/10/2026, B = 08/11/2026); Resumen con el filtro de ejecución.
3. **Comparar sigue valiendo la pena, pero dividir la compra ahorra poco.**
   - El 08/11/2026, el mismo shampoo Babaria Cebolla 700 mL cuesta $20.588 en Locatel y $29.900 en el más caro:
     $9.312 de diferencia (31,1 %).
   - La diferencia promedio entre el comercio más barato y el más caro para un mismo comparable bajó de 16,9 % (10/10)
     a 8,5 % (08/11).
   - Comprar cada uno de los 18 comparables donde es más barato cuesta $599.726, solo **$6.200 menos** que comprar
     todo en Locatel. El 10/10/2026 esa diferencia era de $34.842.
   - *Dónde verlo:* tarjeta «Ahorro máximo entre comercios» y la tabla de ahorro (Productos comparables);
     Canasta.

*Advertencia:* los precios son los del momento de cada captura e incluyen IVA. La canasta no incluye envío, mínimos
de compra ni condiciones de las promociones.

## 8. Seguridad y buenas prácticas

- **Ninguna credencial en el repositorio.** La app no necesita claves. `.streamlit/secrets.toml` está en
  `.gitignore` por si alguna vez se usa.
- **Consultas parametrizadas.** Todo valor del usuario va como parámetro `?`; en el texto del SQL solo hay
  marcadores. Las consultas de la app abren la base en **solo lectura**.
- **Entradas validadas antes de consultar.** La búsqueda acepta máximo 60 caracteres (letras, números, espacios y
  `. , & + -`). Los comercios, ejecuciones, fechas, subcategorías y cantidades se validan contra su formato.
- **Scraping responsable:** pausas de 1 s, agente de usuario identificable, reintentos con espera creciente, tope de
  peticiones por ejecución, y se respeta `robots.txt` (ver `docs/fuentes_scraping.md`).

## 9. Despliegue

_(Se completa en el Módulo 8.)_ Las plataformas gratuitas **no conservan los cambios en la base al reiniciarse**:
una actualización hecha en la app publicada se pierde cuando el servidor se reinicia. Además, los comercios suelen
bloquear las consultas desde servidores en la nube. En ese caso la página de actualización lo informa y ofrece el
modo sin conexión. La actualización en línea funciona en la ejecución local.

## 10. Declaración de uso de inteligencia artificial

- **Herramienta:** Claude Code (Anthropic), con el modelo Claude Opus 5.5, usado como asistente de programación
  dentro de la carpeta del proyecto, con reglas de trabajo escritas en `CLAUDE.md`. Entre esas reglas: no ejecutar
  git, no hacer scraping en línea sin mi permiso, no inventar datos y trabajar un módulo a la vez.
- **Para qué la usé:**
  - leer el enunciado y proponer el plan y la arquitectura;
  - escribir el código de `db.py`, `validacion.py`, `actualizacion.py`, `componentes.py`, `app.py`, `paginas/` y
    `tests/`;
  - hacer los cambios marcados con `[CAMBIO]` en `scraper.py`;
  - redactar el borrador de `diccionario_datos.md` y de este README.
  
  Las decisiones las tomé yo con base en las opciones que me presentaba: qué hacer con los precios ausentes, fijar
  los comparables, la regla de 8 comparables, la canasta solo con productos disponibles y las páginas de la app.
  También autoricé la ejecución en línea del 08/11/2026.
- **Cómo se verificó:**
  - cada módulo se ejecutó y se revisó su salida real antes de seguir;
  - la migración se probó primero en una copia de la base;
  - las cifras de la app se contrastaron con consultas SQL independientes y con las copias crudas de `raw/`;
  - las páginas se probaron con `streamlit.testing` (AppTest) y en el navegador;
  - las 9 pruebas de `pytest` pasan, y se comprobó que fallan cuando se introduce un error a propósito.
  
  Revisé el código, hice los commits a mano y soy responsable de todo lo entregado.
