# Taller 2 — Comparador de precios de antiinfecciosos (aplicación Streamlit)

**Lenguaje: Python** (probado con Python 3.15.2). Todo el proceso está en Python: la extracción
(`scraper.py`), la validación (`validacion.py`), el acceso a datos (`db.py`), la aplicación
(Streamlit) y las pruebas (`pytest`).

**Categoría:** medicamentos antiinfecciosos de uso sistémico (antibióticos, antivirales,
antimicóticos sistémicos y antiparasitarios), la misma del Taller 1.

**Comercios:** La Rebaja Virtual · Locatel Colombia · Droguerías Cafam, los mismos del Taller 1.

## Aplicación publicada

**Enlace:** https://marlonjimenezvalencia-7qyng7cxsviahpst75gmnp.streamlit.app

- La plataforma gratuita no conserva los cambios en la base cuando la aplicación se reinicia. Una
  actualización hecha en la versión publicada se pierde al reiniciar; la base del repositorio es la
  que se carga cada vez.
- Los comercios suelen bloquear las peticiones que vienen de servidores en la nube. Si la
  actualización en línea falla allí, la página **Actualizar precios** lo dice y ofrece el modo sin
  conexión, que reprocesa las copias de `raw/`. La actualización en línea funciona en la ejecución
  local.
- La aplicación no usa credenciales. Si en algún momento las necesita, van en
  `.streamlit/secrets.toml` (está en `.gitignore`) o en la configuración de la plataforma.

## Qué hace la aplicación

| Página | Qué muestra |
|---|---|
| **Resumen** | 8 indicadores calculados con SQL (con su unidad y su periodo) y 4 gráficos interactivos: evolución del precio de un comparable, precio por unidad de contenido, distribución de precios y "¿Dónde es más barato?" |
| **Productos** | Tabla de los productos filtrados: comercio, marca, nombre, presentación, precio, precio unitario, promoción, disponibilidad, fecha de consulta y enlace al anuncio. Se puede ordenar, buscar y descargar en CSV |
| **Cambios de precio** | Compara dos ejecuciones (por defecto, las dos completas más recientes): qué subió o bajó (en COP y en %), qué es nuevo y qué dejó de observarse, con un umbral que resalta las variaciones grandes |
| **Canasta** | Costo de una canasta de comparables en cada comercio (En caso de que el comercio tiene todos los productos), costo mínimo combinando comercios y ahorro |
| **Actualizar precios** | Botón que llama a `scraper.py` (en línea o sin conexión), muestra el avance por comercio con `st.status` y al final un resumen por comercio |
| **Calidad de los datos** | Ejecuciones, disponibilidad, resultado de las validaciones, rechazos, correcciones y copias crudas |

Los filtros de la barra lateral (en Resumen y Productos) se pueden combinar: comercio, ejecución o
rango de fechas, subcategoría, marca, rango de precio, solo promociones, solo comparables y búsqueda
por palabras en el nombre o en el texto original del anuncio. Cada comercio tiene siempre el mismo
color, y cada gráfico tiene una tabla con sus respectivos datos ("Ver los datos del gráfico").

## Cómo se puede ejecutar localmente

Desde la carpeta `taller_2`:

```bash
python -m venv .venv
# Windows (PowerShell): .venv\Scripts\Activate.ps1   Git Bash: source .venv/Scripts/activate
# macOS / Linux:        source .venv/bin/activate
pip install -r requirements.txt
streamlit run app.py
```

La aplicación abre en `http://localhost:8501`. Lee `comparador_precios.sqlite`, que ya viene con
los datos, así que no hay que recolectar nada para usarla.

## Cómo correr las pruebas

Desde la carpeta `taller_2`, con el entorno activado:

```bash
pytest tests/
```

Son 30 casos en 13 funciones de prueba, que cubren todo lo que pide el enunciado:

| Lo que se prueba | Archivo |
|---|---|
| Conversión de precios en texto a número (`"$ 12.900"` → 12900; un precio ausente queda vacío, nunca 0) | `tests/test_precios.py` |
| Normalización de unidades (mL, g o unidad) | `tests/test_precios.py` |
| Cálculo del ahorro con empates | `tests/test_consultas.py` |
| Un producto agotado no cuenta como el más barato aunque conserve su precio (ahorro, canasta y precio por unidad) | `tests/test_consultas.py` |
| Insertar dos veces la misma ejecución no duplica observaciones | `tests/test_insertar.py` |
| Detección de cambios de precio (función `db.cambios_entre` y vista `v_cambios_precio`) | `tests/test_consultas.py` |
| La canasta no se calcula cuando falta un producto | `tests/test_consultas.py` |
| La búsqueda rechaza texto no permitido y trata `%` como texto | `tests/test_consultas.py` |

Las pruebas no usan la base de la entrega ni consultan los sitios:

- `tests/base_prueba.py` arma una base pequeña en una carpeta temporal.
- `tests/datos/raw/` es una copia mínima de `raw/` (4 productos reales de La Rebaja del 8 de
  noviembre) para probar la inserción completa: lectura, limpieza, validación y guardado.

## Cómo actualizar los datos

- **Desde la aplicación:** página **Actualizar precios**.
  - *En línea* consulta los tres sitios.
  - *Sin conexión* reprocesa una ejecución guardada en `raw/`.
- **Desde la terminal:**

  ```bash
  python scraper.py                                         # en línea, unos 25 minutos
  python scraper.py --comercios locatel                     # un solo comercio
  python scraper.py --sin-conexion --id-ejecucion E20261108T110310   # reprocesa raw/
  ```

Cada actualización:

1. Registra una ejecución nueva.
2. Valida las observaciones con `validacion.py` (pandera).
3. Inserta unicamente las que no existen, en una transacción por comercio.

Si un comercio falla, continua con los demás y deja ese comercio como `parcial` o `fallida` para mejor comprension, con el
motivo.

## Estructura de archivos

```
taller_2/
├── app.py                     entrada de la aplicación: configuración, navegación y filtros
├── .streamlit/config.toml     estilo de la aplicación (colores, letras, barra lateral); no
│                              lleva credenciales
├── paginas/                   una página por archivo (resumen, productos, cambios, canasta,
│                              actualizar, datos)
├── interfaz.py                piezas visuales compartidas: formatos (COP, fechas), colores,
│                              filtros, gráficos, tablas y mensajes de error (sin SQL)
├── db.py                      capa de acceso a datos: todas las consultas SQL, parametrizadas
│                              y con caché (st.cache_data); abre la base en solo lectura
├── scraper.py                 extracción (del Taller 1, ampliada): recolecta, valida y guarda
├── validacion.py              reglas de validación con pandera
├── categoria.py               delimitación de la categoría (principio activo y vía)
├── limpieza.py                estandarización (marca, laboratorio, forma, unidades, contenido)
├── esquema.sql                tablas, restricciones, índices y vistas de la base
├── preparar_base.py           construyó esta base a partir de la del Taller 1 (se corrió una vez)
├── correspondencia.csv        comparables P01–P10 y su SKU en cada comercio (sin precios)
├── comparador_precios.sqlite  base de datos
├── diccionario_datos.md       significado, tipo, unidad y valores de cada tabla, vista y columna
├── raw/                       copias crudas: raw/<comercio>/<AAAA-MM-DD>/<id_ejecucion>/
├── tests/                     pruebas automáticas (pytest)
├── pytest.ini                 configuración de pytest
├── requirements.txt           dependencias con versiones fijas
└── README.md
```

Todas las rutas son relativas a la carpeta del archivo que las usa (`Path(__file__)`), así que la
aplicación funciona desde un computador cualquiera, independientemente.

## Base de datos

### Ejecuciones

La base tiene **3 ejecuciones completas en los tres comercios**, en fechas diferentes:

| Ejecución | Fecha | Origen | Observaciones |
|---|---|---|---|
| `E20261004T182736` | 4 oct 2026 | Taller 1 | 898 |
| `E20261009T235057` | 9 oct 2026 | Taller 1 (ejecución de referencia de esa entrega) | 897 |
| `E20261108T110310` | 8 nov 2026 | Taller 2 | 954 |

Las ejecuciones parciales y fallidas tambien se  conservan (ejemplo, `E20261108T094725`, en la
que Cafam quedó `parcial`). Así queda el historial completo de lo que pasó; la página **Calidad de
los datos** las muestra todas. En total hay 5.932 observaciones de 972 anuncios.

**Cambio en Cafam (noviembre de 2026):** desde noviembre, Cafam también lista los productos
agotados.

- La subcategoría "Medicamentos RX" tiene más de 600 productos, el máximo que el sitio muestra en un
  listado. Antes se partía por rango de precio (`?priceRange=`), pero ese filtro deja por fuera los
  agotados.
- Ahora se parte por grupos de marcas (`/medicamentos-rx/mk/genfar?map=marca,marca`), lo que
  `robots.txt` permite.
- Con eso, la ejecución `E20261108T110310` recorrió los 4.157 productos que reporta el sitio.

### Vistas SQL

La aplicación consulta seis de estas vistas directamente, desde `db.py`. El detalle de cada
columna se localiza en [`diccionario_datos.md`](diccionario_datos.md).

| Vista | Qué devuelve? | Dónde se usa? (función de `db.py`) |
|---|---|---|
| `v_observaciones` | Cada observación unida con su anuncio, comercio y comparable, más el precio unitario | Filtros, indicadores, tabla de productos y gráficos (`_consulta_filtrada`) |
| `v_cambios_precio` | Cambios de precio entre observaciones consecutivas del mismo anuncio (`LAG`) | Indicador "Cambios de precio" del Resumen (`cambios_en_ejecucion`) |
| `v_comparables` | Observaciones de los comparables P01–P10 con su precio por mL, g o unidad | Gráfico de evolución del precio (`evolucion_precio`) y canasta (`canasta`) |
| `v_ejecuciones_completas` | Ejecuciones en que los tres comercios quedaron `completa` | Ejecución por defecto y selectores de ejecución (`ejecuciones`) |
| `v_disponibilidad` | Disponible, agotado o **no observado** en cada ejecución (no observado ≠ agotado) | Página Calidad de los datos (`disponibilidad`) |
| `v_resumen_ejecucion` | Recolectados, nuevos, cambios de precio, no observados y rechazados por ejecución y comercio | Resumen al terminar una actualización (`scraper.py`) y página Calidad de los datos (`resumen_ejecuciones`) |
| `v_ultimo_precio` | La observación más reciente de cada anuncio (`ROW_NUMBER`) | No la usa la aplicación (los filtros necesitan elegir la última observación *dentro* del periodo filtrado). Sirve para consultas independientes sobre la base |

### Corrección de la base del Taller 1

`preparar_base.py` copió todas las filas de la base del Taller 1 sin modificar el archivo original, estuvo todo en orden.
Luego corrigió los campos y reprocesó las copias de `raw/` con las reglas actuales. Cada cambio
quedó en la tabla `correcciones`, con fecha, registro, valor anterior, valor nuevo y motivo:

- **`productos`:**
  - laboratorio de P02 (CLAVULIN es la marca; el laboratorio es GSK);
  - orden de la concentración de P02 y P08;
  - contenido total y unidad normalizada de los 10 comparables.
- **`anuncios`:** laboratorio, forma farmacéutica y unidades estandarizados de nuevo con las reglas
  corregidas de `limpieza.py` (320 cambios).

No se borró ninguna observación.

## Origen y verificación de los datos

Todos los precios salen de `scraper.py`, que lee las mismas respuestas que usa cada sitio para
mostrar sus productos:

- **La Rebaja y Locatel:** el servicio de catálogo de VTEX (`/api/catalog_system/pub/products/search`),
  que su `robots.txt` permite.
- **Cafam:** su `robots.txt` prohíbe `/api/`, así que se leen sus páginas de categoría en HTML
  (`?page=N`). Cada una trae sus productos en un bloque JSON (`__STATE__`).

Cada respuesta se guarda comprimida en `raw/<comercio>/<AAAA-MM-DD>/<id_ejecucion>/`, junto con un
`manifest.json` de la ejecución. Cada observación tiene `id_ejecucion` y `url_extraccion`, así que
se es posible rastrearlo hasta su copia cruda. El modo sin conexión reconstruye los datos unicamente desde
`raw/`.

**Buenas prácticas de scraping:**

- pausa de 1 segundo entre peticiones;
- agente de usuario identificable (`TallerMineriaDatosUNAL/1.0`);
- tope de 1.000 peticiones por comercio y ejecución;
- solo páginas públicas, sin credenciales;
- se respeta `robots.txt`.

**Seguridad:**

- Todas las consultas usan parámetros `?`; el texto del usuario nunca se pega dentro del SQL.
- La búsqueda admite máximo 60 caracteres y solo letras, números, espacios y `. , / + - % ( )`.
- La aplicación abre la base en modo de solo lectura. Solo el botón de actualización escribe, a
  través de `scraper.py`.

## Gráfico de libre elección: "¿Dónde es más barato?"

**Pregunta:** si busco exactamente el mismo producto (mismo código de barras) en los comercios
elegidos, ¿dónde suele estar más barato?

**Cómo se calcula** (`db.mas_barato_mismo_ean`):

1. Se toman los productos disponibles con el mismo EAN válido y con precio en todos los comercios
   elegidos. Los agotados no cuentan a pesar de que el sitio conserve su precio, porque no se pueden
   comprar (el mismo criterio de la canasta, del ahorro máximo y del precio por unidad).
2. Para cada producto se busca el comercio con el menor precio.
3. Se cuenta cuántas veces gana cada comercio. Si hay empate en el mínimo, el producto cuenta como
   "Empate".

A diferencia del gráfico de precio por unidad, que usa solo los 10 comparables, este gráfico compara
todos los productos idénticos que venden los tres comercios.

**Por qué responde una pregunta del consumidor:** ayuda a tomar la decision de en qué droguería buscar de manera primaria
cuando ya se sabe exactamente qué producto se necesita, por ejemplo cuando la fórmula médica indica
una marca y una presentación. El código de barras (EAN) identifica un producto exacto (mismo
laboratorio, concentración, forma y cantidad), así que se comparan productos idénticos y no nombres
parecidos que podrían ser presentaciones distintas. Solo cuentan los productos que esten disponibles, porque
un producto agotado no se puede comprar aunque el sitio arroge su precio.

El gráfico tiene algunos límites: cuenta cuántas veces gana cada comercio, pero no cuánto se ahorra (para
eso están el indicador de ahorro máximo, el precio por unidad y la canasta); deja por fuera los
productos que vende un solo comercio; y muestra una sola ejecución, es decir, los precios de una
fecha.

## Hallazgos

**Periodo:** de octubre 4 al noviembre 8  del 2026. **Ejecuciones completas en los tres
comercios:** `E20261004T182736` (4 de octubre), `E20261009T235057` (9 de octubre) y
`E20261108T110310` (8 de noviembre). Precios en COP con IVA. Cuando se dice "más barato" solo
cuentan productos disponibles.


1. **Para un mismo producto, Locatel suele ser el más barato.** El 8 de noviembre, de los 67
   productos con el mismo código de barras disponibles en los tres comercios, Locatel tiene el
   precio más bajo en 42 (63 %),  La Rebaja en 20 y Cafam en 5. El 9 de octubre Locatel también
   ganaba, pero por menos: 27 de 64, frente a 24 de Cafam y 13 de La Rebaja.
   *Verificar:* Resumen → "¿Dónde es más barato?", eligiendo cada ejecución en la barra lateral.

2. **Los precios de Cafam dependen mucho de la fecha: su promoción de octubre terminó.** El 9 de
   octubre, 122 de los 228 productos de Cafam (53,5 %) estaban en promoción; el 8 de noviembre,
   solo 13 de 294 (4,4 %). Entre esas dos ejecuciones subieron 164 precios de Cafam y no bajó
   ninguno, lo que coincide con que Cafam pasara de ser el más barato en 24 productos a serlo en 5.
   Para quien compra: un precio bajo puede ser una promoción temporal, así que conviene fijarse en
   la fecha de la consulta.
   *Verificar:* Cambios de precio (anterior `E20261009T235057`, posterior `E20261108T110310`) y el
   indicador "Productos en promoción" del Resumen en cada ejecución.

3. **En las presentaciones comparables la diferencia entre comercios es pequeña, y combinar
   comercios ahorra poco.** El 8 de noviembre, la mayor diferencia entre las diez presentaciones
   comparables es de $7.300 (levofloxacina 750 mg x5: $128.200 en Locatel frente a $135.500 en La
   Rebaja, 5,4 %), y en seis de las diez es menor de $2.000. Una canasta con una unidad de P01, P02
   y P05 cuesta $209.800 en La Rebaja y $213.200 en Cafam; Locatel no tiene total porque P02 está
   agotado. Comprando cada producto donde es más barato se pagan $204.800: $5.000 menos (2,4 %) que
   en La Rebaja, sin contar el envío de un segundo pedido.
   *Verificar:* Resumen (indicador "Ahorro máximo") y Canasta (P01, P02 y P05, ejecución del 8 de
   noviembre).

4. **La marca pesa mucho más que el comercio.** El 8 de noviembre, la ciprofloxacina de 500 mg en
   tableta cuesta desde $905 por tableta (Procatec, en Locatel) hasta $23.220 (Cipro, en La Rebaja):
   unas 25 veces más por el mismo principio activo, la misma concentración y la misma forma. Antes
   de cambiar de marca hay que consultar al médico o al farmacéutico.
   *Verificar:* Productos → buscar "ciprofloxacin" → ordenar por precio unitario (filas de 500 mg
   disponibles).

## Declaración de uso de inteligencia artificial

**Herramienta:** Claude Code (modelo Claude Opus 5.5, de Anthropic), en la aplicación de escritorio
de Claude, trabajando sobre los archivos de mi computador en la funcion de cowork. El módulo de extracción viene del Taller
1, el cual tuvo apoyo de code.
**Para qué partes:** Fue util para la escritura y depuración del código (scraper, capa de datos, interfaz,
páginas, validación, vistas SQL y pruebas) y asi evitar errores, ejecución de las recolecciones, ayudo a trabajar el estilo visual de la
aplicación y en la parte de redacción de la documentación tediosa(incluido este README y el diccionario
de datos).

**Cómo se verificó:**

- 30 pruebas automáticas con pytest sobre una base temporal (nunca la base de la entrega). Se
  comprobó que las pruebas fallan cuando se quita la corrección que vigilan.
- Prueba de las seis páginas con `streamlit.testing` (AppTest), sin errores.
- Los números de los hallazgos se compararon con consultas SQL independientes sobre la base, escritas
  aparte de `db.py`.
- Cada ejecución con observaciones tiene su copia cruda en `raw/`.
- Los colores se revisaron con un validador de daltonismo y contraste.
- Revisión de la aplicación en el navegador.

Esa revisión encontró dos errores que se corrigieron antes de entregar: Cafam quedaba parcial
porque el filtro por precio dejaba por fuera los agotados, y los productos agotados contaban como
"más barato" aunque no se pudieran comprar.

Soy responsable de todo el código entregado, en completas capacidades de explicarlo y presentar una explicacion oral de la utilidad de esta apliacion, asi como de como fue confeccionado usando herramientas del curso.
