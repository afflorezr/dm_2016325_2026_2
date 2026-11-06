# Comparador de precios de confitería — Taller Parcial 1

**Curso:** Minería de Datos  
**Estudiante:** Carlos Ernesto Araujo Romero  
**Universidad Nacional de Colombia — Sede Bogotá**  
**Lenguaje:** R 4.6.2  
**Categoría:** Confitería (chocolates, caramelos, gomitas, chicles y mentas)  
**Comercios:** Éxito, Carulla y Jumbo (`www.jumbocolombia.com`)  
**Documento:** [`taller_1.html`](taller_1.html) (versión compilada) y [`taller_1.Rmd`](taller_1.Rmd) (fuente reproducible)

---

## 1. Qué resuelve este taller

El taller compara el precio de **13 presentaciones idénticas** de confitería en tres
comercios con venta en línea en Colombia, a partir de una extracción completa de
la categoría mediante scraping. La pregunta que guía el análisis es doble:

1. **¿Dónde conviene comprar cada producto?**
2. **¿Cuándo una presentación más grande ofrece un mejor precio por unidad?**

El informe compilado es una **presentación para el consumidor**: parte de una
portada visual, responde ocho preguntas con tablas y gráficos y cierra con una
guía de compra, limitaciones y reproducibilidad. No muestra código. El detalle
técnico queda en `scraper.R`, `consultas.sql`, `docs/categorias.md` y este README.

### Resultados principales

* **13 presentaciones comparables**, cada una con precio en los tres comercios:
  **39 observaciones comparables** en una misma ejecución.
* **No hay un comercio ganador único.** En la ejecución de análisis, Jumbo aparece
  como el más barato en 6 presentaciones (incluyendo un empate), Carulla en 4 y
  Éxito en 4.
* **La canasta completa en un solo almacén** cuesta entre **$187.410** y
  **$192.924**. Comprando cada producto donde está más barato, el costo baja a
  **$178.904**: un ahorro de **$14.020 (7,3%)** frente a la canasta más costosa.
* **La presentación grande no siempre es más barata por gramo.** En Corona
  tradicional, la barra de 200 g de Éxito es la más eficiente por 100 g; la de
  450 g no mejora ese indicador en Éxito ni en Carulla. En Millows original, la
  bolsa de 300 g sí es más eficiente que la de 75 g en los tres comercios.
* **Dos ejecuciones completas** conservadas en la base, con identificadores y horas
  distintas, para demostrar que el scraper no sobrescribe observaciones.

> Los precios son una fotografía del momento de la consulta. No incluyen
> domicilio, mínimos de compra, cupones, fidelización ni precios de tienda física.

---

## 2. Inicio rápido

### 2.1. Ver el informe (sin conexión)

La base `comparador_precios.sqlite` y las copias crudas `raw/` ya están incluidas.
Desde R, en la carpeta del proyecto:

```r
rmarkdown::render("taller_1.Rmd")
```

O abra directamente [`taller_1.html`](taller_1.html).

### 2.2. Reproducir la recolección sin internet

```r
source("scraper.R")
verificar_offline(id_ejecucion = "EJEC_20261105_223427")
```

Esto lee únicamente `raw/`, crea `verificacion_offline.sqlite` y compara conteos,
suma de precios y disponibilidad contra la base principal. El resultado de la
prueba está en [`verificacion_offline.txt`](verificacion_offline.txt).

### 2.3. Hacer una recolección nueva (con internet)

```r
source("scraper.R")
ejecutar_recoleccion(offline = FALSE, ruta_db = "comparador_precios.sqlite")
```

Cada corrida crea un `id_ejecucion` nuevo, guarda sus propias copias crudas y
**no sobrescribe** las ejecuciones anteriores. Si un sitio cambia o bloquea el
acceso, la entrega se puede evaluar con el modo offline.

### 2.4. Dependencias

```r
source("dependencias.R")
# o, con renv:
renv::restore()
```

Las versiones exactas están en [`renv.lock`](renv.lock) (R 4.6.2, 66 paquetes).

---

## 3. Estructura de archivos

```text
Taller_Parcial1/
├── taller_1.Rmd                  # documento reproducible (fuente)
├── taller_1.html                 # presentación compilada, autocontenida
├── styles.css                    # estilos visuales del informe
├── consultas.sql                 # las 8 consultas SQL para revisión técnica
├── scraper.R                     # módulo de extracción, SQLite y offline
├── comparador_precios.sqlite     # base de datos con las ejecuciones
├── mapeo_productos.csv           # correspondencia manual SKU ↔ producto canónico
├── db/
│   └── schema.sql                # esquema SQLite con restricciones y vistas
├── raw/
│   ├── exito/YYYY-MM-DD/{id_ejecucion}/{rama}/pagina_NNN.json.gz
│   ├── carulla/...
│   └── jumbo/...
├── docs/
│   ├── categorias.md             # delimitación y equivalencias por comercio
│   └── robots/                   # robots.txt descargados (auditoría)
├── verificacion_offline.R        # prueba de reprocesamiento sin red
├── verificacion_offline.txt      # resultado de la prueba
├── dependencias.R                # instalación de paquetes
├── renv.lock                     # versiones fijas
└── README.md
```

Las copias crudas se guardan comprimidas (`.json.gz`). Cada archivo pesa mucho
menos que el HTML renderizado y conserva la respuesta original completa. Ningún
archivo de la entrega supera los 100 MB.

---

## 4. Fuentes y método

### 4.1. Comercios y ramas

| Comercio | Grupo | Ramas equivalentes |
|---|---|---|
| **Éxito** | Grupo Éxito | `Mercado > Dulces y chocolatería` (Chocolatería, Confitería, Chicles, Masmelos y gomitas) + chocolate de mesa de `Café, chocolate y cremas no lácteas` |
| **Carulla** | Grupo Éxito | `Bebidas, snacks y dulces > Dulces y chocolates` (Chocolates, Confitería, Chicles, Gomitas y masmelos) + `Despensa > Chocolate, té e infusiones > Chocolate` |
| **Jumbo** | Cencosud | `Supermercado > Dulces y postres` (Confitería, Chocolatería) + `Supermercado > Despensa > Chocolate de mesa` |

La delimitación completa, los productos excluidos y la justificación de cada
equivalencia están en [`docs/categorias.md`](docs/categorias.md).

### 4.2. Scraping

* **API pública de catálogo VTEX** (`/api/catalog_system/pub/products/search/...`),
  la misma que alimenta la vitrina. Devuelve JSON con producto, marca, precio,
  disponibilidad, URL y categoría.
* Paginación de 50 productos, una petición cada ~0,25 s, hasta tres reintentos.
* `User-Agent` identificable y `robots.txt` revisados y archivados.
* Sin Selenium ni Playwright: la recolección es más rápida, estable y
  reproducible.
* Cada página se guarda en `raw/` con un `metadata.json` (URL, hora, total
  reportado y hash SHA-256).

### 4.3. Cobertura

| Comercio | Productos reportados por las ramas | Extraídos | Incluidos en la categoría | Con precio |
|---|---:|---:|---:|---:|
| Éxito | 4.624 | 4.624 | 3.024 | 714 |
| Carulla | 2.466 | 2.466 | 2.342 | 525 |
| Jumbo | 541 | 541 | 509 | 509 |

La diferencia entre “extraídos” e “incluidos” corresponde a exclusiones
documentadas: café y cremas de la rama mixta de Éxito, cocoa en polvo, galletas,
Halls, suplementos y artículos de fiesta. La diferencia entre “incluidos” y “con
precio” corresponde a productos agotados o sin precio en línea. **No se imputó
ningún precio ni contenido:** los valores ausentes quedan `NULL`.

### 4.4. Correspondencia

La canasta se construyó manualmente con una regla estricta: misma marca, misma
variante, mismo contenido y misma unidad. Los 39 SKUs (13 productos × 3
comercios) están en `mapeo_productos.csv`, con el texto original de cada sitio y
la justificación. La tabla del informe muestra, lado a lado, cómo se llama la
misma presentación en Éxito, Carulla y Jumbo.

---

## 5. Base de datos

El esquema completo está en [`db/schema.sql`](db/schema.sql). Tablas:

| Tabla | Contenido |
|---|---|
| `comercios` | Los tres comercios y su categoría equivalente. |
| `ejecuciones` | Una fila por corrida: fecha, modo (online/offline), estado y totales. |
| `ejecuciones_comercio` | Detalle por comercio: páginas, reportados, extraídos, incluidos, con precio. |
| `ejecuciones_categoria` | Detalle por rama consultada, para conciliar con el sitio. |
| `productos_comparables` | Las 13 presentaciones canónicas. |
| `observaciones` | Cada producto de cada comercio en cada ejecución. |
| `mapeo_productos` | Correspondencia SKU ↔ producto canónico, con regla y confianza. |
| `descartes` | Excluidos y duplicados, con motivo y texto original. |

Restricciones principales:

* `UNIQUE (id_comercio, sku_comercio, fecha_consulta)`.
* Índice único parcial `(id_ejecucion, id_comercio, id_producto_comun)` para
  comparables: una sola observación por comercio y producto en cada ejecución.
* Claves foráneas a ejecuciones, comercios y productos.
* `precio_cop` y `contenido_valor` admiten `NULL`; los `CHECK` impiden valores
  negativos o cero cuando hay dato.

---

## 6. Documento y consultas

El documento [`taller_1.Rmd`](taller_1.Rmd) genera una presentación visual para el
consumidor. No muestra código: las consultas SQL y el scraping quedan en el
código fuente y en los archivos auxiliares.

* **Portada y resumen:** hero, indicadores clave, tres hallazgos y guía de compra.
* **Ocho preguntas, ocho respuestas:** cada pregunta tiene una respuesta corta,
  una tabla o un gráfico y una interpretación.
* **Ocho gráficos:** mapa de calor de precios, podio de comercios, ahorro
  porcentual, precio por 100 g, ahorro absoluto vs. relativo, faltantes,
  disponibilidad y costo de la canasta.
* **Guía de compra:** dónde comprar cada producto y cuánto se ahorra.
* **Cómo se hizo:** categoría, cobertura, correspondencia manual y exclusiones.
* **Limitaciones y reproducibilidad:** sin anexo técnico ni bloques de código.
* **Consultas SQL:** las ocho consultas están en [`consultas.sql`](consultas.sql)
  y en los chunks ocultos del `.Rmd`; el informe compilado muestra solo sus
  resultados.

---

## 7. Cumplimiento de la rúbrica

| Criterio | Peso | Evidencia |
|---|---:|---|
| **Selección de fuentes y scraping** | 50% | `scraper.R` con una función por comercio y una función general; 3 comercios; categoría completa (4.624 + 2.466 + 541 productos extraídos); 13 productos × 3 comercios = 39 observaciones comparables en una misma ejecución; `raw/` comprimido; modo offline probado; `robots.txt` y User-Agent documentados; dos ejecuciones conservadas. |
| **Construcción de la base SQLite** | 10% | `db/schema.sql`; tablas `ejecuciones`, `ejecuciones_comercio`, `ejecuciones_categoria`, `observaciones`, `productos_comparables`, `mapeo_productos`, `descartes`; `UNIQUE` de observaciones; índice único de comparables; campos obligatorios; correspondencia manual documentada. |
| **Consultas SQL** | 15% | [`consultas.sql`](consultas.sql) y chunks ocultos del `.Rmd`: 8 preguntas, filtro por ejecución, empates con `RANK()` y `GROUP_CONCAT`, faltantes y calidad por comercio. El informe muestra las respuestas, no el código. |
| **Documento** | 25% | Presentación visual: resumen para el consumidor, guía de compra, 8 gráficos con interpretación, 8 preguntas respondidas, limitaciones y reproducibilidad. |
| **Requisitos mínimos** | — | 3 comercios; 13 presentaciones (mínimo 8); 39 observaciones (mínimo 24); categoría completa; fecha y hora ISO 8601 en todas las observaciones; `renv.lock`; base SQLite; `raw/`. |

---

## 8. Reproducibilidad y verificación

### 8.1. Modo offline

`verificar_offline()` lee los `.json.gz` y `metadata.json` de `raw/`, aplica el
mismo parser y la misma correspondencia, y crea una base de verificación. No
llama a `curl`. La comparación por comercio (conteos, suma de precios y
disponibilidad) debe coincidir exactamente con la base original. El resultado
está en [`verificacion_offline.txt`](verificacion_offline.txt).

Además se probó una **reconstrucción desde cero en una carpeta limpia**, sin la
base original: `ejecutar_recoleccion(offline = TRUE)` produjo 5.875
observaciones, 39 observaciones comparables y 13 productos, idénticos a la base
incluida. Esa prueba confirma que la entrega no depende de la base ya construida
ni de una conexión a internet.

### 8.2. Modo online

`ejecutar_recoleccion(offline = FALSE)` consulta las APIs, guarda las copias
crudas de la nueva ejecución e inserta las observaciones en la base. La función
registra el inicio y el fin, el número de páginas, el total reportado por el
sitio, los incluidos, los excluidos y los que tienen precio. Si un comercio falla,
la ejecución queda `parcial` y el error se registra.

### 8.3. Entorno

* R 4.6.2.
* Paquetes: `curl`, `jsonlite`, `DBI`, `RSQLite`, `dplyr`, `tidyr`, `stringr`,
  `purrr`, `tibble`, `readr`, `ggplot2`, `scales`, `digest`, `knitr`,
  `rmarkdown`.
* Versiones exactas en `renv.lock`.

---

## 9. Limitaciones

* Los precios son una fotografía; las promociones pueden cambiar el ranking.
* No se incluyen domicilio, mínimos de compra, cupones, fidelización ni tienda
  física.
* La disponibilidad cambia: un producto publicado puede estar agotado.
* La equivalencia de categorías es una decisión documentada; cada sitio organiza
  la confitería a su manera.
* La correspondencia de productos es manual y auditada; dos nombres comerciales
  pueden referirse a empaques ligeramente distintos.
* Las dos ejecuciones se hicieron el mismo día en horarios distintos. La
  estructura permite repetir en otras fechas para observar cambios.
* El informe no es una recomendación nutricional ni terapéutica.

---

## 10. Notas para la revisión

* El informe compilado es [`taller_1.html`](taller_1.html); se puede abrir sin
  conexión y contiene los gráficos embebidos.
* La base se puede inspeccionar con `sqlite3 comparador_precios.sqlite` o con
  `DBI`/`RSQLite`.
* La ejecución de análisis se elige automáticamente como la última ejecución
  `completa` con al menos 8 productos comparables. Para forzar otra:
  `rmarkdown::render("taller_1.Rmd", params = list(id_ejecucion = "EJEC_..."))`.
* No se incluyen contraseñas, tokens ni claves de acceso.
* Las copias crudas y la base están dentro de la carpeta individual del
  estudiante; no se modifican archivos de otros estudiantes.
