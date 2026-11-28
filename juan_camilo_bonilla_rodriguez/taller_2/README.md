# Taller 2 · Precios de salud

Juan Camilo Bonilla Rodríguez · Python y Streamlit.

Esta aplicación compara precios de termómetros, tensiómetros, glucómetros, tiras reactivas, lancetas y oxímetros en **Habib, Farmaprime y Farmaweb**. Se excluyen pruebas de embarazo y ovulación. Reutiliza el scraper, SQLite, las correspondencias y las respuestas originales de la [entrega del Taller 1](https://github.com/afflorezr/dm_2016325_2026_2/pull/139).

**Aplicación:** [Precios de salud](https://dm201632520262-ytvjx9dnyzxbacfkksc6cm.streamlit.app/)

## Ejecutar localmente

Se probó en Linux con Python 3.14.10, Streamlit 1.67.0 y Plotly 7.1.0. Usar Python 3.14 y las versiones de `requirements.txt`.

Desde `juan_camilo_bonilla_rodriguez/taller_2/`:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m streamlit run app.py
```

En Windows, activar el entorno con `.venv\Scripts\Activate.ps1`. Abrir la dirección que indica Streamlit, normalmente `http://localhost:8501`. La aplicación consulta la base entregada al iniciar; no necesita consultar las tiendas para mostrar sus resultados.

## Estructura

```text
taller_2/
├── app.py                       # Entrada y navegación
├── db.py                        # SQL, filtros, indicadores, cambios y canasta
├── scraper.py                   # Extractores reutilizados y coordinación de la actualización
├── validacion.py                # Validación de lotes y entradas de búsqueda
├── interfaz.py                  # Filtros, caché y componentes compartidos
├── comparador_precios.sqlite
├── diccionario_datos.md
├── requirements.txt
├── README.md
├── auditoria.py                 # Contrasta precios con raw, sin usar la red
├── paginas/
│   ├── resumen.py               # Indicadores, cuatro gráficos y tabla
│   ├── cambios.py               # Comparación de ejecuciones
│   ├── canasta.py               # Cantidades y cobertura de la canasta
│   └── datos.py                 # Estado, historial y actualización
├── codigo/                     # Limpieza, persistencia y lectores del Taller 1
├── datos/                      # Correspondencias; no contiene precios digitados
├── raw/                        # JSON/HTML originales comprimidos, por comercio y captura
├── tests/                      # Pruebas con bases temporales
└── .streamlit/config.toml       # Apariencia y configuración local
```

`codigo/` contiene los módulos reutilizados del Taller 1. El botón de actualización llama a `scraper.run_all`. Las rutas se resuelven desde la carpeta del proyecto.

## Qué permite consultar

- **Comparar precios:** filtros combinables por comercio, marca, subcategoría, precio, ejecución, fechas, promoción, comparables y palabras del nombre o del anuncio. Se muestran seis indicadores SQL, oferta por comercio, evolución, precio unitario, distribución de precios y ahorro entre comercios. La tabla permite ordenar, buscar y descargar el resultado filtrado.
- **Cambios entre fechas:** selecciona dos ejecuciones, compara el mismo anuncio en el mismo comercio y muestra subidas, bajadas, productos nuevos y no observados, con umbral ajustable. Por defecto se eligen las dos ejecuciones más recientes, aunque puedan pertenecer al mismo día.
- **Mi canasta:** usa presentaciones y cantidades iguales en una sola ejecución. El total de una tienda queda ausente si falta cualquier producto o está agotado. Incluye mínimo combinado y ahorro frente a cada canasta completa.
- **Datos y actualización:** muestra estados y cobertura; permite consultar las tiendas o reprocesar las copias originales.

Los filtros laterales delimitan la oferta de la primera página. La evolución utiliza todo el historial del producto y los comercios elegidos. Las páginas de cambios y canasta tienen sus propios selectores de ejecución y productos.

El cuarto gráfico responde: **¿en qué presentación se ahorra más al cambiar de tienda?** Ordena las diferencias porcentuales de presentaciones idénticas con cobertura de los tres comercios. El gráfico de distribución describe surtidos diferentes; no se usa para afirmar que una tienda sea globalmente más barata.

## Datos y fechas

La base conserva **822 observaciones**, incluidas las **544 heredadas** del Taller 1. Tiene tres capturas completas de los comercios activos, en dos fechas distintas:

| Corrida | Fecha de Colombia | Presentaciones comunes | Observaciones comparables |
|---|---|---:|---:|
| `2026-11-16T143419384252` | 2026-11-16 | 8 | 24 |
| `2026-11-17T064831740696` | 2026-11-17 | 8 | 24 |
| `2026-11-17T065026871905` | 2026-11-17 | 8 | 24 |

En cada una se recorrieron las categorías completas: Habib, 102 anuncios; Farmaprime, 1109; Farmaweb, 267. Después de aplicar la delimitación, se conservaron 64, 51 y 24 observaciones de precio válidas respectivamente. En Farmaweb se rechazó un precio no válido y quedó registrado con su motivo. Los totales amplios incluyen productos que se excluyen por pertenecer a otras categorías.

Las ocho identidades siguen siendo: kit G30A con glucómetro, 50 tiras y 50 lancetas; G30A 50 tiras; G30A tres cajas de 50 tiras; G30A 50 tiras con 50 lancetas; Glucoquick 50 lancetas; Mediclas 25 tiras; Mediclas 50 tiras; Mediclas 100 lancetas. El archivo de correspondencias relaciona la marca, la presentación, la cantidad y el SKU de cada tienda mediante un identificador común. Un kit heterogéneo cuenta como un kit; no se divide su precio por la suma de tiras, lancetas y glucómetro.

Al revisar el PR del Taller 1 el 17 de noviembre no había comentarios de retroalimentación. La primera captura de este taller guardó las respuestas, pero el procesamiento de dos tiendas falló porque faltaba `lxml`. Tras instalarlo, se reprocesaron esas respuestas con sus fechas originales. El cambio de estado quedó en `correcciones`. Después se realizó otra captura completa en línea.

La disponibilidad puede ser **disponible**, **agotado según el sitio** o **desconocida**. **No observado** indica que un anuncio no tuvo una observación válida en esa ejecución; puede deberse a una captura parcial y no demuestra agotamiento ni retiro.

## Actualización en línea y sin conexión

En la página **Datos y actualización**, pulsar **Consultar los tres comercios**. El progreso se muestra por tienda con `st.status`. Una falla no impide continuar con las demás. Cada comercio se inserta mediante una transacción independiente; se preservan los datos anteriores. El resumen indica anuncios recuperados, observaciones nuevas y duplicadas, productos nuevos, cambios de precio, rechazos y no observados.

Para trabajar sin conexión, activar **Reprocesar copias sin conexión** y pulsar el botón. Se vuelve a ejecutar la extracción sobre `raw/`: no es una actualización de precios y conserva la hora original. Los resultados repetidos no se insertan otra vez.

También se puede ejecutar desde terminal:

```bash
python scraper.py
python scraper.py --offline
python scraper.py --offline --corrida-id 2026-11-17T065026871905
```

Las nuevas capturas se agregan a la misma base. Nunca reutilizar un identificador de captura en modo en línea. El historial se relaciona con los manifiestos de `raw/manifiestos/` y con los mapeos de `datos/correspondencias/`. El scraper hace pausas, identifica su agente de usuario, limita páginas e intentos y no elude bloqueos.

Las reglas previas a insertar comprueban precio numérico, finito y positivo; comercio, SKU, URL HTTPS y fecha ISO con UTC−5; duplicados dentro del lote; y cobertura de los ocho SKU esperados por tienda. Los registros inválidos se guardan en `rechazos`; no se sustituyen por cero. La falta de cobertura impide marcar la ejecución como completa, aunque se conserven las observaciones válidas del resto de la categoría.

## Consultas y vistas

Toda consulta de la interfaz está en `db.py`. Los filtros, conteos, medianas, ahorro, cambios y totales de canasta se calculan en SQLite. Los valores se pasan mediante parámetros. La búsqueda limita longitud y caracteres y trata los comodines como texto. Las conexiones se cierran mediante un administrador de contexto.

Vistas utilizadas directamente por la aplicación:

| Vista | Uso |
|---|---|
| `v_catalogo` | Tabla filtrada, indicadores y surtido; excluye observaciones marcadas como descartadas. |
| `v_comparables` | Comparación, evolución, precio unitario y canasta; respeta la cohorte de cada corrida. |
| `v_ultimo_precio` | Opciones de filtros a partir del último precio observado por anuncio. No implica disponibilidad actual. |
| `v_cambios_precio` | Diferencias respecto a la observación anterior del mismo anuncio. |
| `v_disponibilidad` | Estado observado o ausencia de observación por anuncio y ejecución. |

`st.cache_data` conserva consultas repetidas. Su clave incluye la versión del archivo SQLite y la caché se limpia al terminar una actualización. Un bloqueo compartido impide que dos sesiones de la aplicación inicien actualizaciones simultáneas. Los índices cubren corrida, anuncio, fecha, producto, precio y atributos de filtrado. El [diccionario](diccionario_datos.md) detalla todas las tablas, vistas y columnas.

## Pruebas y auditoría

```bash
python -m pytest tests/ -q
python scraper.py --verificar
```

Las **25 pruebas** usan datos pequeños y bases temporales; no consultan tiendas ni usan la base de la entrega. Cubren conversión COP, unidades, ahorro con empates, inserción idempotente, cambios del mismo anuncio, canasta incompleta y productos agotados. También comprueban validación, búsqueda, fallas por comercio y la interfaz de Streamlit.

La auditoría se ejecuta por separado sobre los datos reales: bloquea las peticiones HTTP, reprocesa las respuestas originales y verifica precio, precio anterior, fecha, URL, referencia cruda, integridad, claves foráneas, unicidad y ocho productos disponibles por comercio en dos fechas distintas.

## Hallazgos

En las corridas completas del **16 y 17 de noviembre de 2026**, los precios de las ocho presentaciones comunes se mantuvieron iguales. Los siguientes resultados se pueden reproducir seleccionando `2026-11-17T065026871905`:

1. **Mediclas de 25 tiras** tuvo la mayor diferencia relativa: 50.200 COP en Habib y 62.700 COP en Farmaweb. Elegir Habib reduce el pago en 12.500 COP, equivalente al 19,94 % del precio máximo.
2. En **G30A sin accesorios**, Habib ofreció las 150 tiras por 196.500 COP: 1.310 COP por tira, frente a 2.094 COP por tira en el empaque de 50. El tamaño grande ahorra por unidad, pero exige pagar 91.800 COP más por el empaque.
3. El **kit G30A con glucómetro** costó menos en Farmaweb, a 105.000 COP. Las **100 lancetas Mediclas** costaron menos en Farmaprime, a 49.800 COP. Conviene comparar cada presentación.
4. Una canasta con **una unidad de cada una de las ocho presentaciones** costó 734.700 COP en Habib, 759.100 en Farmaprime y 762.200 en Farmaweb. Comprar cada producto donde estaba más barato sumó 725.700 COP: 9.000 COP menos que la canasta completa más económica en una sola tienda.

Estos valores no incluyen envío, mínimos de compra ni condiciones de promociones. El ahorro de comprar en varias tiendas puede desaparecer al sumar esos costos. Los precios y existencias describen el momento de captura y no garantizan la oferta posterior. Un menor precio no es una recomendación de sustitución médica.

## Despliegue

La aplicación está publicada en [Streamlit Community Cloud](https://dm201632520262-ytvjx9dnyzxbacfkksc6cm.streamlit.app/) desde el fork `jbonillaro-lgtm/dm_2016325_2026_2`, rama `entrega-taller-02`. El archivo de entrada es `juan_camilo_bonilla_rodriguez/taller_2/app.py`.

Para volver a desplegarla, usar esa rama y ruta y seleccionar Python 3.14 en **Advanced settings**, siguiendo la [guía de Streamlit](https://docs.streamlit.io/deploy/streamlit-community-cloud/deploy-your-app/deploy). Las correcciones se agregan al [PR del Taller 2](https://github.com/afflorezr/dm_2016325_2026_2/pull/140).

La consulta de los catálogos no requiere credenciales. Los secretos de despliegue, si se necesitan, se configuran en la plataforma o en `.streamlit/secrets.toml`, que está excluido de Git.

El servidor puede bloquear las consultas a alguna tienda. En ese caso, la aplicación muestra el estado por comercio y permite reprocesar las copias de `raw/`. En el alojamiento gratuito, las actualizaciones de SQLite y los archivos guardados en el servidor pueden perderse al reiniciar; la copia incluida en el repositorio se conserva.

## Uso de IA

Se utilizó OpenAI Codex como apoyo para desarrollar y revisar el código, las consultas SQL, las pruebas y la documentación, reutilizando el trabajo del Taller 1.

Las instrucciones principales, resumidas de esta conversación y del enunciado, fueron:

- Reutilizar el scraper, SQLite y las copias originales del Taller 1.
- Revisar los requisitos y conservar las ocho presentaciones comparables en los tres comercios.
- Agregar una captura de otra fecha y validar los datos antes de insertarlos.
- Separar la interfaz, las consultas, la extracción y la validación.
- Comparación de fechas y canasta.
- Comprobar el funcionamiento con pruebas y documentar la ejecución local y sin conexión.

Se verificaron las 822 observaciones contra las respuestas originales, se ejecutaron 25 pruebas automáticas y se comprobó la instalación en un entorno virtual nuevo.
