# Taller 1: comparador de precios

**Autor:** Juan Camilo Bonilla Rodríguez. **Lenguaje:** Python.

Categoría: termómetros, tensiómetros, glucómetros, tiras reactivas, lancetas y oxímetros. Se excluyen pruebas de embarazo y ovulación.

El informe se puede leer en **[taller_1.html](taller_1.html)**. Su fuente reproducible es **[taller_1.qmd](taller_1.qmd)**.

## Estructura de la entrega

El enunciado pide el documento, el scraper, SQLite, las respuestas originales, las dependencias y el README. Esos archivos quedan en la raíz; los auxiliares se agrupan por función.

```text
taller_01/
├── README.md
├── taller_1.qmd
├── taller_1.html
├── scraper.py
├── comparador_precios.sqlite
├── requirements.txt
├── raw/                         # Respuestas originales comprimidas y manifiestos
├── codigo/                      # Módulos que usan el scraper y el informe
│   ├── config.py                # Comercios, colores, rutas y zona horaria
│   ├── rawio.py                 # Lectura y escritura de respuestas originales
│   ├── limpieza.py              # Normalización y delimitación de la categoría
│   ├── validacion.py            # Reglas de calidad y disponibilidad
│   ├── db.py                    # Creación, carga y correspondencias en SQLite
│   ├── schema.sql               # Tablas y vistas de la base
│   ├── correspondencia.py       # Validación de identidades entre comercios
│   ├── consultas.py             # Las ocho preguntas SQL
│   ├── graficos.py              # Figuras del informe
│   ├── reproduccion.py          # Reconstrucción y comprobación sin conexión
│   └── __init__.py
├── datos/
│   ├── correspondencia.csv      # Mapeo actual: ocho presentaciones en tres tiendas
│   ├── familias_unidad.csv      # Grupos para comparar distintos tamaños
│   └── correspondencias/        # Mapeos usados en las capturas anteriores
├── documentacion/
│   ├── revision_correspondencia.md
│   ├── diccionario_datos.md
│   └── empaques/                # Fotografías utilizadas al revisar los kits
└── tests/                       # Pruebas del código entregado
```

`codigo/`, `datos/` y `documentacion/` son auxiliares de la entrega. No contienen precios preparados a mano: los CSV de `datos/` solo definen identidades y cantidades. Los precios se extraen con `scraper.py` y se guardan en SQLite. Las tablas y figuras del análisis están dentro del HTML; no hace falta entregar sus exportaciones por separado.

## Datos utilizados

Comercios: **Habib, Farmaprime y Farmaweb**. La captura completa `2026-11-16T143419384252` se realizó entre **14:34:21 y 14:35:48 del 16 de noviembre de 2026**, hora de Colombia.

Se obtuvieron ocho presentaciones con precio y disponibilidad en las tres tiendas: **24 observaciones sin duplicados**. Son el kit G30A con glucómetro, 50 tiras y 50 lancetas; G30A de 50 tiras; G30A de 150 tiras; G30A de 50 tiras con 50 lancetas; Glucoquick de 50 lancetas; Mediclas de 25 tiras; Mediclas de 50 tiras y Mediclas de 100 lancetas.

| Comercio | Anuncios recuperados / reportados | Productos incluidos | Precios válidos | Exclusiones | Rechazos |
|---|---:|---:|---:|---:|---:|
|Habib|102 / 102|64|64|38|0|
|Farmaprime|1109 / 1109|51|51|1058|0|
|Farmaweb|267 / 267|25|24|242|1|

Los conteos iniciales corresponden a secciones amplias, antes de excluir productos ajenos a la categoría. La base conserva **544 observaciones y 282 anuncios**, incluidos los antecedentes de Locatel, Cafam y La Rebaja. Sus 279 observaciones originales no se borraron. Los manifiestos de `raw/` enlazan cada captura con su mapeo histórico.

Las equivalencias se explican en [revision_correspondencia.md](documentacion/revision_correspondencia.md); las tablas y columnas, en [diccionario_datos.md](documentacion/diccionario_datos.md).

## Instalación

Entorno probado: Python **3.14.10**, SQLite **3.54.0** y Quarto **1.11.9**, Linux. Las versiones de paquetes están fijadas en `requirements.txt`. Quarto se instala aparte desde [su página oficial](https://quarto.org/docs/get-started/).

Desde la carpeta de esta entrega:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

En PowerShell, activar con `.venv\Scripts\Activate.ps1`. El entorno y las cachés que se crean al ejecutar son archivos locales y quedan excluidos de Git mediante `.gitignore`.

## Ejecutar el informe

```bash
quarto render taller_1.qmd
```

Por defecto, el documento procesa las respuestas de `raw/` sin consultar las tiendas. Conserva las fechas originales y no duplica precios. Para fijar el intérprete de Quarto en Linux se puede usar `QUARTO_PYTHON="$PWD/.venv/bin/python" quarto render taller_1.qmd`.

## Recolección en línea y modo sin conexión

```bash
python scraper.py
python scraper.py --offline
```

El primer comando crea una captura nueva de los tres comercios. El segundo reprocesa la última captura común guardada. No se debe reutilizar un identificador de captura en modo en línea.

Para reconstruir **todo el historial** desde las respuestas originales, en una base nueva:

```bash
python scraper.py --reconstruir reconstruida.sqlite
```

El destino debe ser inexistente. Para reconstruir únicamente la captura principal:

```bash
python scraper.py --offline --corrida-id 2026-11-16T143419384252 --db copia_completa.sqlite
```

También se puede recolectar desde el documento con `TALLER_ONLINE=1 quarto render taller_1.qmd`. En PowerShell, establecer `$env:TALLER_ONLINE="1"` antes de ejecutarlo y eliminar la variable después.

Todas las rutas son relativas a la carpeta de la entrega. Los cambios de precios se agregan al historial; no sobrescriben observaciones anteriores.

## Fuentes y método

Habib se consulta mediante su catálogo público VTEX, en Equipos de medición (`/51/176/`). Farmaprime usa WooCommerce Store, categoría 51085. Farmaweb usa las categorías 26968, 26887, 44978 y 27026, incluyendo termómetros y tensiómetros que estaban en secciones separadas. Las URLs exactas están en `scraper.py` y en cada copia cruda.

El código recorre la paginación completa, contrasta los totales del sitio y hace pausas de un segundo entre peticiones. Se fijaron un tiempo de espera de 30 segundos, tres intentos y un máximo de 60 páginas por sección. Los importes WooCommerce se convierten según `currency_minor_unit`.

Habib debe declarar una cantidad disponible positiva. Farmaprime y Farmaweb deben indicar producto en stock, compra habilitada y ausencia de pedido pendiente de reposición. Un producto agotado se conserva como tal. Los precios inválidos quedan en la tabla de rechazos, sin sustituirlos por cero.

## Comprobación de la entrega

```bash
python -m pytest tests/ -q
python scraper.py --verificar
```

Las **13 pruebas** verifican precios COP, unidades, reinserción, rechazos, fechas, multipaquetes, clasificación, disponibilidad, empates SQL, tamaños equivalentes, promociones históricas, escala WooCommerce y selección histórica de comparables. Usan bases temporales y no consultan las tiendas.

`--verificar` bloquea las peticiones HTTP, reconstruye las cuatro capturas en una base temporal y compara todo el historial y los resultados de las ocho consultas. Además, revisa integridad, claves foráneas, referencias a raw y las ocho presentaciones disponibles en tres tiendas.

La ejecución se comprobó localmente. No se ha probado en Colab, GitHub Actions ni en otro computador.

## Hallazgos

Resultados de la captura completa del 16 de noviembre de 2026:

- Mediclas de 25 tiras presentó la mayor diferencia relativa: 50.200 COP en Habib frente a 62.700 en Farmaweb, una diferencia de 12.500 COP (19,94 % del precio máximo).
- En Habib, las 150 tiras G30A costaron 1.310 COP por tira, frente a 2.094 en el empaque de 50. El paquete grande exigió pagar 196.500 COP en vez de 104.700.
- Farmaweb tuvo el kit G30A con glucómetro más económico, a 105.000 COP. Farmaprime tuvo el menor precio de las 100 lancetas Mediclas, a 49.800 COP.
- En Mediclas, el precio por tira en Habib bajó de 2.008 COP en el empaque de 25 a 1.970 en el de 50.

Los precios no incluyen envío, mínimos de compra ni otras condiciones de las promociones. Las existencias pueden cambiar después de la captura. Las comparaciones por contenido se limitan a la misma línea de producto.
