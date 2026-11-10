# Taller 1 · Comparador de precios de bebidas en línea

**Asignatura:** Minería de Datos (2016325) · Universidad Nacional de Colombia, Departamento de Estadística
**Estudiante:** Laura Katherine Martínez Castiblanco
**Lenguaje:** R (scraping, limpieza, SQLite, consultas SQL, gráficos e informe)
**Categoría:** bebidas no alcohólicas (gaseosas, jugos, agua, té y café preparados, energizantes)

## 1. Qué hace el proyecto

Recolecta con web scraping la oferta de bebidas de **Éxito, Carulla, PriceSmart y Supermercado Comunal**, la guarda en SQLite, identifica presentaciones idénticas entre tres comercios y responde con SQL dónde conviene comprar cada producto y cuándo una presentación grande sale más barata por litro. El informe (`taller_1.Rmd` → `taller_1.html`) integra código, consultas, gráficos e interpretación.

## 2. Resultados de la corrida de entrega

Corrida `20261108-174507` (8 de noviembre de 2026, hora de Colombia, unas 4 h 15 min). Los cuatro comercios terminaron en estado `completa`.

| Comercio | Observaciones válidas | Descartadas |
|:--|--:|--:|
| Éxito | 511 | 567 |
| Carulla | 474 | 297 |
| Supermercado Comunal | 110 | 13 |
| PriceSmart | 69 | 150 |
| **Total** | **1.164** | **1.027** |

- **Comparables:** 36 presentaciones × 3 comercios (Éxito, Carulla y Comunal) = **108 observaciones**, por encima del mínimo de 24. La correspondencia usa marca + subcategoría + variante + contenido total (mL) + unidades y queda en la tabla `productos_comunes`. Una presentación (Coca-Cola "3000 ml", un multipack mal emparejado con una botella única) se excluyó y quedó registrada en `correcciones`. ⚠️ Si cambió el número de comparables al regenerar, actualice estas cifras.
- **PriceSmart** aporta datos a la descripción de la categoría, pero no tiene comparables: vende multipacks y formatos mayoristas sin equivalente exacto.
- **Verificación sin conexión:** reprocesar `raw/` reproduce los mismos 1.164 válidos (474 / 69 / 110 / 511). Los descartados bajan a 504 porque el descarte por URL ocurre antes de abrir la ficha y no deja copia cruda.
- **Hallazgo principal:** ningún comercio es el más barato en todas las presentaciones; el comercio ganador cambia según el producto y el tamaño. El informe detalla ahorro por producto, COP/L entre tamaños y el costo de la canasta.

## 3. Estructura de archivos

```text
taller_01/
├── README.md                     # esta guía
├── taller_01.Rproj               # proyecto de RStudio (abrir antes de ejecutar)
├── config.R                      # parámetros, términos de búsqueda y selectores por comercio
├── scraper.R                     # módulo de extracción (solo funciones): listado → ficha, validación, SQLite
├── run_scraper.R                 # punto de entrada: modo online/offline, comercios, corrida de prueba
├── comparables.R                 # correspondencia de productos entre comercios
├── revisar_comparables.R         # revisión y exclusión auditada de emparejamientos dudosos
├── preparar_taller1.R            # asigna comparables, genera el .rds y verifica los requisitos mínimos
├── helpers.R                     # funciones del informe (vistas temporales, tablas, gráficos)
├── consultas.sql                 # las 8 consultas SQL
├── taller_1.Rmd / taller_1.html  # informe reproducible y su versión autocontenida
├── comparador_precios.sqlite     # base de la corrida en línea
├── comparador_precios_reproc.sqlite  # base reconstruida desde raw/ (verificación sin conexión)
├── df_resultado_final.rds        # objetos precalculados que lee el informe
├── raw/                          # copias crudas (.html.gz) por comercio y corrida + manifest.csv
├── diagnostico/<corrida>/        # scraper.log, scraper_offline.log, robots.txt y pantallas
├── evidencias/                   # capturas para el informe
├── datos/staging/                # CSV intermedios (ignorado por Git)
├── renv.lock, renv/, .Rprofile   # dependencias con versiones fijas
├── style.css, scripts.js, header.html, UNAL_logo.png   # presentación del informe HTML
└── .gitignore
```

No se versionan `.Rproj.user/`, `.Rhistory`, `.RData`, `renv/library/` ni `datos/staging/`.

## 4. Cómo ejecutarlo

Abra `taller_01.Rproj` (la carpeta de trabajo debe ser `taller_01/`; no se usa `setwd()`) y restaure el entorno:

```r
renv::restore()
```

### 4.1 Recolección en línea

Requiere Google Chrome. Edite las opciones de `run_scraper.R` y ejecútelo:

```r
# MODO <- "online"; VISIBLE <- TRUE/FALSE; PRUEBA <- TRUE (corrida corta) / FALSE (completa)
source("run_scraper.R")
```

Una corrida completa tarda varias horas. Cada comercio se inserta en una transacción; las copias crudas quedan en `raw/` y el registro en `diagnostico/<corrida>/scraper.log`.

### 4.2 Reprocesar sin conexión (verificación)

Reconstruye la base desde `raw/` sin consultar los sitios (el identificador está en `raw/manifest.csv`):

```r
source("config.R"); source("scraper.R")
ejecutar_corrida(modo = "offline", id_corrida = "20261108-174507")
```

Escribe en `comparador_precios_reproc.sqlite`.

### 4.3 Comparables y objetos del informe

```r
source("preparar_taller1.R")            # asigna comparables, genera df_resultado_final.rds y verifica
source("config.R"); source("scraper.R"); source("revisar_comparables.R")
revisar_comparables()                    # emparejamientos con brecha > 25 %
# excluir_comparables("PROD_COM_xx", "motivo")   # luego REASIGNAR <- FALSE en preparar_taller1.R
```

### 4.4 Informe

```r
rmarkdown::render("taller_1.Rmd")       # genera taller_1.html; no hace scraping
```

## 5. Base de datos

`ejecuciones` (corrida, comercio, fechas ISO 8601, estado), `observaciones` (28 campos, con texto original sin limpiar y archivo crudo), `descartes`, `cobertura_sitio`, `productos_comunes` y `correcciones`, más las vistas `v_ultimo_precio`, `v_cambios_precio` y `v_comparables`. Restricciones: `precio_cop > 0`, `UNIQUE(comercio, sku_comercio, fecha_hora_consulta)` y `UNIQUE(id_ejecucion, sku_comercio)` para evitar duplicados, claves foráneas e índices.

## 6. Limitaciones

- **Una sola fecha:** no se observan cambios de precio en el tiempo.
- **Cobertura parcial:** depende de los términos de búsqueda, el máximo de páginas y el tope de fichas por comercio. El total que muestra cada sitio incluye productos ajenos a la categoría y no sirve como referencia.
- **Correspondencia heurística:** inferida del nombre del producto; se revisó manualmente, pero pueden quedar errores.
- **Condiciones de compra:** no se fijó ciudad ni sede y no se incluyen envíos ni mínimos de compra. En Éxito se usa el precio general, no el de tarjeta.

## 7. Cumplimiento de la entrega

- [x] Los datos provienen del código de scraping; cada observación se rastrea hasta su copia en `raw/`.
- [x] Fecha y hora de consulta en todas las observaciones; dependencias fijadas en `renv.lock`.
- [X] Sin contraseñas ni tokens en el repositorio.
- [X] Ningún archivo supera 100 MB (`raw/` pesa unos 45 MB; `diagnostico/*/pantallas/` pesa unos 71.6 MB).

**Uso de herramientas de IA** (complete o ajuste según corresponda): se usó un asistente de IA para apoyar la depuración del scraper, la redacción de consultas SQL y la estructura del informe. El código se probó en el equipo local y los resultados se verificaron contra la base y las copias crudas.