# Taller 2 · Comparador de precios de cuidado bucal (aplicación Shiny)

Minería de Datos · Universidad Nacional de Colombia · **David Esteban Márquez Bayona**

- **Aplicación publicada:** https://9foq8d-david-esteban.shinyapps.io/Parcial_2/
- **Categoría:** cuidado bucal. **Comercios:** Éxito, Olímpica y Locatel (los mismos del Taller 1).
- **Lenguaje:** R ≥ 4.2 para todo el proceso (scraping, acceso a datos, aplicación y pruebas).
- **Novedad Éxito:** Durante la realización de nuevos scraping para tener mayor información la pagina siempre rechazo las solicitudes del script. Por ello, no hay nuevos registros solo los dos reglamentarios.

> **Cambio de lenguaje.** El Taller 1 se entregó en Python. Como la aplicación es Shiny, el enunciado
> exige reescribir la extracción en R: `scraper.R` y `limpieza.R` son la versión en R de `scraper.py` y
> `limpieza.py`, con el mismo método, las mismas reglas y el mismo formato de `raw/`. La equivalencia se
> comprobó reconstruyendo la base desde las copias crudas con el código en R: las 19.067 observaciones,
> los 2.384 anuncios y los 1.990 productos resultaron idénticos a los de la base entregada en el Taller 1.

## 1. Ejecutar la aplicación localmente

```r
# desde la carpeta taller_2/, en una sesión de R recién iniciada
source("configurar.R")        # una sola vez: instala las versiones fijadas en renv.lock y las verifica
# reiniciar R (Ctrl + Shift + F10)
shiny::runApp()               # abre la aplicación
```

La carpeta ya incluye la base (`comparador_precios.sqlite`) y las copias crudas (`raw/`). Si se parte de
la entrega del Taller 1, `Rscript migrar_taller1.R ../Parcial_1/taller1_cuidado_bucal` copia la base y
`raw/` y les agrega la estructura del Taller 2 (no modifica ninguna observación).

Nueva recolección desde la consola (equivale al botón de la aplicación):

```bash
Rscript scraper.R                  # en línea: consulta los tres comercios y agrega una ejecución
Rscript scraper.R --sin-conexion   # reprocesa raw/ sin consultar ningún sitio (no duplica nada)
```

## 2. Pruebas

```bash
Rscript -e 'testthat::test_dir("tests")'
```

Son 16 pruebas (84 comprobaciones) que usan una base temporal y copias crudas de juguete; no tocan la base
de la entrega ni consultan los sitios. Cubren: conversión de precios en texto a número, normalización de
unidades, dígito de control del EAN, reglas de validación, inserción repetida sin duplicados, detección de
cambios de precio / productos nuevos / no observados, tolerancia a la falla de un comercio, ahorro con
empates, canasta completa y canasta con un producto faltante, y filtros con texto malicioso.

## 3. Estructura de archivos

| Archivo | Contenido |
|---|---|
| `app.R` | Interfaz (`bslib`) y servidor. No contiene SQL ni scraping. |
| `db.R` | Capa de acceso a datos: todas las consultas SQL, con los filtros como argumentos. |
| `scraper.R` | Extracción (una función por comercio), copias crudas, inserción por transacción y `ejecutar_recoleccion()`. |
| `validacion.R` | Reglas de validación con `pointblank`, comparables de referencia y correcciones manuales. |
| `limpieza.R` | Reglas R1–R9 de normalización y correspondencia de productos; correcciones C1 y C2. |
| `graficos.R` | Tema visual (colores, tipografía), formato (COP, %) y los cuatro gráficos de `highcharter`. |
| `www/logos/` | Logos de los comercios. Pertenecen a sus dueños y se usan solo para identificar cada comercio en este trabajo académico. |
| `esquema.sql`, `vistas.sql` | Estructura de la base (tablas e índices) y vistas SQL. |
| `migrar_taller1.R` | Adapta la base del Taller 1 a la estructura del Taller 2. |
| `comparador_precios.sqlite` | Base de datos (Taller 1 + ejecuciones nuevas). |
| `diccionario_datos.md` | Tablas, vistas y columnas: significado, tipo, unidad y valores posibles. |
| `raw/<comercio>/<fecha>/<ejecución>/` | Respuestas JSON originales (gzip) y `manifest.json` de cada ejecución. |
| `tests/` | Pruebas automáticas (`testthat`). |
| `renv.lock` | Dependencias con versiones fijas. |

## 4. Datos

**Origen.** Todos los precios provienen del scraper. Cada observación guarda su ejecución
(`ejecucion_id`), su fecha y hora, la URL consultada (`url_fuente`) y la carpeta de su copia cruda
(`ejecuciones.carpeta_raw`). La columna «Coinciden con la base» del resumen del modo sin conexión cuenta
cuántas filas leídas de `raw/` coinciden en SKU, precio y disponibilidad con lo guardado.

**Historial.** C:\USERS\DAVID\ONEDRIVE\ESCRITORIO\MINERIA\DAVID_ESTEBAN_MARQUEZ_BAYONA\DAVID_ESTEBAN_MARQUEZ_BAYONA\PARCIAL_2\RAW
├───exito
│   ├───2026-10-09
│   │   ├───E20261009T104100
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T104416
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T110227
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T112120
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T140657
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T142137
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T143244
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T144022
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s34185114.json.gz
│   │   │       0002_productos_s34185114.json.gz
│   │   │       0003_productos_s34185114.json.gz
│   │   │       0004_productos_s34185114.json.gz
│   │   │       0005_productos_s34185114.json.gz
│   │   │       0006_productos_s34185114.json.gz
│   │   │       0007_productos_s34185114.json.gz
│   │   │       0008_productos_s34185114.json.gz
│   │   │       0009_productos_s34185114.json.gz
│   │   │       0010_productos_s34185114.json.gz
│   │   │       0011_productos_s34185114.json.gz
│   │   │       0012_productos_s34185114.json.gz
│   │   │       0013_productos_s34185114.json.gz
│   │   │       0014_productos_s34185114.json.gz
│   │   │       0015_productos_s34185114.json.gz
│   │   │       0016_productos_s34185114.json.gz
│   │   │       0017_productos_s34185114.json.gz
│   │   │       0018_productos_s34185114.json.gz
│   │   │       0019_productos_s34185114.json.gz
│   │   │       0020_productos_s34185114.json.gz
│   │   │       0021_productos_s34185114.json.gz
│   │   │       0022_productos_s34185114.json.gz
│   │   │       0023_productos_s34185114.json.gz
│   │   │       0024_productos_s34185114.json.gz
│   │   │       0025_productos_s34185114.json.gz
│   │   │       0026_productos_s34185114.json.gz
│   │   │       0027_productos_s34185114.json.gz
│   │   │       0028_productos_s34185114.json.gz
│   │   │       0029_productos_s34185114.json.gz
│   │   │       0030_productos_s34185114.json.gz
│   │   │       0031_productos_s34185114.json.gz
│   │   │       0032_productos_s34185114.json.gz
│   │   │       0033_productos_s34185114.json.gz
│   │   │       0034_productos_s34185114.json.gz
│   │   │       0035_productos_s34185114.json.gz
│   │   │       manifest.json
│   │   │
│   │   └───E20261009T162803
│   │           0000_arbol.json.gz
│   │           0001_productos_s34185114.json.gz
│   │           0002_productos_s34185114.json.gz
│   │           0003_productos_s34185114.json.gz
│   │           0004_productos_s34185114.json.gz
│   │           0005_productos_s34185114.json.gz
│   │           0006_productos_s34185114.json.gz
│   │           0007_productos_s34185114.json.gz
│   │           0008_productos_s34185114.json.gz
│   │           0009_productos_s34185114.json.gz
│   │           0010_productos_s34185114.json.gz
│   │           0011_productos_s34185114.json.gz
│   │           0012_productos_s34185114.json.gz
│   │           0013_productos_s34185114.json.gz
│   │           0014_productos_s34185114.json.gz
│   │           0015_productos_s34185114.json.gz
│   │           0016_productos_s34185114.json.gz
│   │           0017_productos_s34185114.json.gz
│   │           0018_productos_s34185114.json.gz
│   │           0019_productos_s34185114.json.gz
│   │           0020_productos_s34185114.json.gz
│   │           0021_productos_s34185114.json.gz
│   │           0022_productos_s34185114.json.gz
│   │           0023_productos_s34185114.json.gz
│   │           0024_productos_s34185114.json.gz
│   │           0025_productos_s34185114.json.gz
│   │           0026_productos_s34185114.json.gz
│   │           0027_productos_s34185114.json.gz
│   │           0028_productos_s34185114.json.gz
│   │           0029_productos_s34185114.json.gz
│   │           0030_productos_s34185114.json.gz
│   │           0031_productos_s34185114.json.gz
│   │           0032_productos_s34185114.json.gz
│   │           0033_productos_s34185114.json.gz
│   │           0034_productos_s34185114.json.gz
│   │           0035_productos_s34185114.json.gz
│   │           manifest.json
│   │
│   ├───2026-11-09
│   │   └───E20261109T151124
│   │           0000_arbol.json.gz
│   │           0001_productos_s34185114.json.gz
│   │           0002_productos_s34185114.json.gz
│   │           0003_productos_s34185114.json.gz
│   │           0004_productos_s34185114.json.gz
│   │           0005_productos_s34185114.json.gz
│   │           0006_productos_s34185114.json.gz
│   │           0007_productos_s34185114.json.gz
│   │           0008_productos_s34185114.json.gz
│   │           0009_productos_s34185114.json.gz
│   │           0010_productos_s34185114.json.gz
│   │           0011_productos_s34185114.json.gz
│   │           0012_productos_s34185114.json.gz
│   │           0013_productos_s34185114.json.gz
│   │           0014_productos_s34185114.json.gz
│   │           0015_productos_s34185114.json.gz
│   │           0016_productos_s34185114.json.gz
│   │           0017_productos_s34185114.json.gz
│   │           0018_productos_s34185114.json.gz
│   │           0019_productos_s34185114.json.gz
│   │           0020_productos_s34185114.json.gz
│   │           0021_productos_s34185114.json.gz
│   │           0022_productos_s34185114.json.gz
│   │           0023_productos_s34185114.json.gz
│   │           0024_productos_s34185114.json.gz
│   │           0025_productos_s34185114.json.gz
│   │           0026_productos_s34185114.json.gz
│   │           0027_productos_s34185114.json.gz
│   │           0028_productos_s34185114.json.gz
│   │           0029_productos_s34185114.json.gz
│   │           0030_productos_s34185114.json.gz
│   │           0031_productos_s34185114.json.gz
│   │           0032_productos_s34185114.json.gz
│   │           0033_productos_s34185114.json.gz
│   │           0034_productos_s34185114.json.gz
│   │           0035_productos_s34185114.json.gz
│   │           manifest.json
│   │
│   └───robots
│           robots_2026-10-09.txt.gz
│           robots_2026-11-09.txt.gz
│           robots_2026-11-11.txt.gz
│
├───locatel
│   ├───2026-10-09
│   │   ├───E20261009T104100
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T104416
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T110227
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T112120
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T140657
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T142137
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T143244
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   ├───E20261009T144022
│   │   │       0000_arbol.json.gz
│   │   │       0001_productos_s10.json.gz
│   │   │       0002_productos_s10.json.gz
│   │   │       0003_productos_s10.json.gz
│   │   │       0004_productos_s10.json.gz
│   │   │       0005_productos_s10.json.gz
│   │   │       0006_productos_s10.json.gz
│   │   │       0007_productos_s10.json.gz
│   │   │       0008_productos_s10.json.gz
│   │   │       manifest.json
│   │   │
│   │   └───E20261009T162803
│   │           0000_arbol.json.gz
│   │           0001_productos_s10.json.gz
│   │           0002_productos_s10.json.gz
│   │           0003_productos_s10.json.gz
│   │           0004_productos_s10.json.gz
│   │           0005_productos_s10.json.gz
│   │           0006_productos_s10.json.gz
│   │           0007_productos_s10.json.gz
│   │           0008_productos_s10.json.gz
│   │           manifest.json
│   │
│   ├───2026-11-09
│   │   └───E20261109T151124
│   │           0000_arbol.json.gz
│   │           0001_productos_s10.json.gz
│   │           0002_productos_s10.json.gz
│   │           0003_productos_s10.json.gz
│   │           0004_productos_s10.json.gz
│   │           0005_productos_s10.json.gz
│   │           0006_productos_s10.json.gz
│   │           0007_productos_s10.json.gz
│   │           0008_productos_s10.json.gz
│   │           manifest.json
│   │
│   └───robots
│           robots_2026-10-09.txt.gz
│           robots_2026-11-09.txt.gz
│           robots_2026-11-11.txt.gz
│
└───olimpica
    ├───2026-10-09
    │   ├───E20261009T104100
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T104416
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T110227
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T112120
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T140657
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T142137
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T143244
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   ├───E20261009T144022
    │   │       0000_arbol.json.gz
    │   │       0001_productos_s900110300.json.gz
    │   │       0002_productos_s900110300.json.gz
    │   │       0003_productos_s900110300.json.gz
    │   │       0004_productos_s900110300.json.gz
    │   │       0005_productos_s900110300.json.gz
    │   │       0006_productos_s900110300.json.gz
    │   │       0007_productos_s901011100.json.gz
    │   │       manifest.json
    │   │
    │   └───E20261009T162803
    │           0000_arbol.json.gz
    │           0001_productos_s900110300.json.gz
    │           0002_productos_s900110300.json.gz
    │           0003_productos_s900110300.json.gz
    │           0004_productos_s900110300.json.gz
    │           0005_productos_s900110300.json.gz
    │           0006_productos_s900110300.json.gz
    │           0007_productos_s901011100.json.gz
    │           manifest.json
    │
    ├───2026-11-09
    │   └───E20261109T151124
    │           0000_arbol.json.gz
    │           0001_productos_s900110300.json.gz
    │           0002_productos_s900110300.json.gz
    │           0003_productos_s900110300.json.gz
    │           0004_productos_s900110300.json.gz
    │           0005_productos_s900110300.json.gz
    │           0006_productos_s900110300.json.gz
    │           0007_productos_s901011100.json.gz
    │           manifest.json
    │
    └───robots
            .gitignore
            robots_2026-10-09.txt.gz
            robots_2026-11-09.txt.gz
            robots_2026-11-11.txt.gz

**Correcciones a la base del Taller 1** (tabla `correcciones`; no se borró ni se modificó ninguna observación):

| Regla | Qué corrige | Registros |
|---|---|---|
| C1 | Contenido homologado por EAN: anuncios del mismo código de barras que declaraban contenidos distintos (por ejemplo, Locatel tomaba el peso de la ficha técnica de un cepillo, «47 g», en vez de «2 unidades»; Éxito publica 75 mL donde los otros dos publican 100 g). Se usa el contenido de la mayoría estricta; si no hay mayoría la presentación queda **sin precio unitario**. | 53 anuncios |
| C2 | Subcategoría homologada por EAN con la misma regla (por ejemplo, nombres abreviados de Olímpica que quedaban en «Otros cuidado bucal»). | 10 anuncios |

Con esto, 78 de las 84 presentaciones comparables tienen contenido verificado y, por tanto, precio unitario comparable; antes de las correcciones eran menos de la mitad.

**Validación** (`validacion.R`): precio numérico (V1) y mayor que cero (V2); producto disponible con precio
(V3); comercio, URL, SKU y fecha presentes (V4); fecha en ISO 8601 (V5); sin duplicados en la ejecución (V6);
los ocho comparables de referencia presentes en cada comercio (V7, deja la ejecución como «parcial»). Las
filas que fallan no se insertan y quedan en `observaciones_rechazadas` con su motivo. Un producto **agotado**
puede no tener precio publicado: ese precio queda `NULL`, no se reemplaza.

**Disponibilidad.** `observaciones.disponibilidad` distingue `disponible` y `agotado` (lo dice el sitio);
«no observado» se deriva en `v_disponibilidad` y `v_ultimo_precio` cuando el anuncio no apareció en la
ejecución, y no se interpreta como agotado ni como retirado.

**Los ocho productos comparables de referencia** (tabla `comparables_referencia`): presentaciones emparejadas
por EAN, sin alertas ni correcciones, con contenido verificado y precio en los tres comercios en todas las
ejecuciones completas. La aplicación trabaja además con las 84 presentaciones comparables del Taller 1.

### Vistas SQL que usa la aplicación

| Vista | Descripción |
|---|---|
| `v_catalogo` | Una fila por observación vigente, con campos estandarizados, presentación y precio por unidad de contenido. |
| `v_ultimo_precio` | Observación más reciente de cada anuncio y su estado actual (disponible, agotado, no observado). |
| `v_cambios_precio` | Observaciones cuyo precio cambió frente a la observación anterior del mismo anuncio (COP y %). |
| `v_comparables` | Un precio por presentación comparable, comercio y ejecución; precio unitario solo con contenido verificado. |
| `v_disponibilidad` | Estado de cada anuncio en cada ejecución de su comercio. |
| `v_observaciones` | Vista del Taller 1 (se conserva). |

## 5. La aplicación

- **Filtros** (panel lateral, combinables): comercio, subcategoría, marca, rango de precio, ejecución o rango
  de fechas, solo promociones, solo comparables y búsqueda por palabras en el nombre o el texto del anuncio.
- **Resumen:** siete indicadores calculados con SQL (productos y observaciones, última ejecución y su estado,
  % en promoción, precio mediano, ahorro máximo entre comercios, cambios de precio y % de agotados), cada uno
  con su unidad y la ejecución o periodo; distribución de precios por comercio; conteos por comercio y precio
  mediano por subcategoría.
- **Comercios:** una ficha por comercio con su logo (cuántas veces es el más barato, anuncios, marcas, precio
  mediano, % en promoción y % agotado); un gráfico de **waffle** (de cada 100 productos comparables, en cuántos es
  más barato cada comercio), **columnas porcentuales** con la composición del catálogo por subcategoría y un
  **packed bubble** con las marcas que más anuncios tienen en cada comercio, y un **sunburst** que recorre el catálogo
  del comercio a la subcategoría y a la marca (clic en un sector para acercarse).
- **Productos:** tabla ordenable y con búsqueda; descarga de los datos filtrados en CSV.
- **Comparar precios:** evolución del precio de un comparable, precio por unidad de contenido (una sola
  unidad de medida a la vez) y ahorro por producto.
- **Cambios de precio:** dos ejecuciones a elección (por defecto las dos más recientes), umbral ajustable,
  productos nuevos y productos que dejaron de observarse.
- **Canasta:** productos comparables y cantidades; costo por comercio solo si tiene todos los productos, costo
  mínimo combinando comercios y ahorro frente al mejor comercio único.
- **Actualizar datos:** botón que ejecuta el scraper en segundo plano (`ExtendedTask`), modo sin conexión,
  resumen por comercio y tablas de ejecuciones, disponibilidad, correcciones y observaciones rechazadas.

**Gráfico de libre elección — «¿En qué productos vale más la pena comparar antes de comprar?»** Muestra, para
cada presentación comparable, cuánto se ahorra comprándola en el comercio más barato en vez del más caro (COP
y %), y con el color indica cuál es ese comercio. Responde una pregunta práctica del consumidor: en la mayoría
de productos la diferencia es pequeña, pero en unos pocos es grande, y esos son los que justifican cambiar de
tienda. Es distinto de la canasta porque no exige elegir productos: ordena todo el catálogo comparable.

**Caché y conexión.** Las consultas repetidas se guardan con `bindCache()`; la clave incluye un contador que
aumenta al terminar una actualización, así que la caché se invalida sin reiniciar. La aplicación abre una
sola conexión de lectura (`PRAGMA query_only`) y la cierra con `onStop()`; el scraper abre y cierra la suya.

## 6. Seguridad

- No se usan tokens ni claves. El despliegue se configura con `rsconnect::setAccountInfo()` **en la consola**,
  nunca en un archivo del proyecto; `.Renviron` y `rsconnect/` están en `.gitignore`.
- Los valores del usuario van como parámetros (`?`) o se interpolan con `glue::glue_sql()`; ninguna consulta
  se arma concatenando texto. La búsqueda se valida antes (máximo 60 caracteres; letras, números, espacios y
  `. , % + -`), y `%` y `_` se buscan como texto.
- Scraping: pausa de 1 s entre peticiones, reintentos con espera exponencial, agente de usuario identificable
  (`TallerMineriaDatosUNAL/2.0`), máximo 80 peticiones por comercio y copia de `robots.txt` en cada ejecución.

## 7. Hallazgos para el consumidor

1. **Éxito es el más barato en la mayoría de productos, pero no en todos.** De las 84 presentaciones
   comparables, Éxito tiene el menor precio en 53, Olímpica en 22 y Locatel en 13 (los empates cuentan para
   cada comercio). Se ve en «Comparar precios» (colores del gráfico de ahorro).
2. **La mejor tienda depende de la canasta.** Con los ocho productos de referencia, una unidad de cada uno, la
   canasta cuesta $ 150.625 en Olímpica, $ 151.605 en Éxito y $ 167.775 en Locatel; comprando cada producto
   donde es más barato cuesta $ 140.485: $ 10.140 menos (6,7 %) que en el mejor comercio único. Se ve en «Canasta».
3. **El tamaño grande rinde más.** Listerine Cool Mint cuesta en Éxito $ 59,1 por mL en 180 mL, $ 39,9 en
   500 mL y $ 32,2 en 1.000 mL; el orden se repite en Olímpica y Locatel. Se ve en «Precio por unidad de contenido».
4. **El catálogo más grande no es el más disponible.** Éxito publica 1.733 anuncios, pero el 63,8 % figura
   agotado y sin precio; en Locatel es el 8,2 % y en Olímpica ninguno. De los anuncios con precio, está en
   promoción el 72,6 % en Éxito, el 15,6 % en Locatel y el 6,6 % en Olímpica. Se ve en «Resumen» filtrando por comercio.

Límites: los precios son los del momento de la captura; la canasta no incluye envío, mínimos de compra ni
condiciones de las promociones; 6 de las 84 presentaciones comparables no tienen precio unitario porque los
comercios declaran contenidos distintos y no hay mayoría.

## 8. Despliegue

```r
# En la consola de R (no guardar en ningún archivo):
# rsconnect::setAccountInfo(name = "...", token = "...", secret = "...")
rsconnect::deployApp(appDir = ".", appName = "comparador-cuidado-bucal")
```

- Las plataformas gratuitas no conservan los cambios de la base al reiniciarse: una actualización hecha en la
  versión publicada dura hasta que el servidor se reinicia. La actualización en línea funciona en la ejecución local.
- Si el servidor no puede consultar los comercios (suelen bloquear estas plataformas), la aplicación lo informa,
  no cambia la base y ofrece el **modo sin conexión**, que reprocesa las copias de `raw/`.
- La versión publicada debe desplegarse desde el mismo commit que se entrega.

## 9. Declaración de uso de inteligencia artificial

- **Herramienta:** Claude (Anthropic), en una sesión con ejecución de código.
- **Para qué se usó:** traducción a R del scraper y de las reglas de limpieza del Taller 1; diseño de las tablas
  y vistas nuevas; escritura de `db.R`, `validacion.R`, `graficos.R`, `app.R`, las pruebas, el diccionario de
  datos y un borrador de este README (incluidos los hallazgos, calculados con consultas sobre la base).
- **Cómo se verificó el resultado:** (1) la base reconstruida desde `raw/` con el código en R se comparó tabla
  por tabla con la del Taller 1 y resultó idéntica; (2) tras la migración, las observaciones siguen siendo las
  mismas 19.067 del Taller 1; (3) las pruebas automáticas pasan; (4) la descarga en línea se probó contra un
  servidor local que imita la API de los comercios, porque el entorno del asistente no tenía acceso a los
  sitios; (5) la aplicación se recorrió pestaña por pestaña, incluida una actualización sin conexión.
- **Asistencia de funciones:** Con ayuda de la IA se generaron funciones para que funcionaran correctamente en la UI de la app

## 10. Diccionario de funciones

Funciones del proyecto agrupadas por archivo. Las que empiezan por punto (`.get`, `.where`…) son **internas**:
las usan otras funciones del mismo archivo y no están pensadas para llamarse directamente. `con` es siempre una
conexión DBI a `comparador_precios.sqlite` y `f` una lista de filtros creada con `filtros()`.

### 10.1 `scraper.R` — extracción, copias crudas e inserción

| Función | Argumentos | Devuelve | Qué hace |
|---|---|---|---|
| `ejecutar_recoleccion` | `comercios`, `modo`, `db_path`, `raw_dir`, `ejecucion_id`, `verbose`, `progreso`, `esquema`, `ruta_manual`, `actualizar` | data.frame (una fila por comercio) | **Punto de entrada.** Extrae cada comercio, valida, inserta en SQLite sin sobrescribir (una transacción por comercio) y actualiza la correspondencia de productos. Si un comercio falla, sigue con los demás. |
| `reprocesar_sin_conexion` | `db_path`, `raw_dir`, `ejecuciones`, `verbose`, `progreso`, `...` | data.frame | Carga en la base las ejecuciones guardadas en `raw/` sin consultar los sitios. No duplica lo ya cargado. |
| `extraer_exito`, `extraer_olimpica`, `extraer_locatel` | `ejecucion_id`, `modo`, `raw_dir`, `progreso` | lista `datos`, `secciones`, `meta` | Una función por comercio, con la misma firma y las mismas columnas de salida. |
| `descargar` | `cid`, `ejecucion_id`, `raw_dir`, `progreso` | ruta de la carpeta | Consulta el árbol de categorías y las páginas de productos (VTEX) y guarda cada respuesta original en `raw/` con su `manifest.json`. |
| `procesar_raw` | `carpeta` | lista `datos`, `secciones`, `meta` | Lee una carpeta de `raw/` y arma la tabla estándar de observaciones; marca la ejecución como completa, parcial o fallida. |
| `parsear_producto` | `prod`, `man`, `pet`, `sec` | lista de registros | Convierte un producto de la respuesta VTEX en un registro por SKU (precio, precio de lista, promoción, disponibilidad, vendedor). |
| `secciones` | `arbol` | lista de secciones | Busca en el árbol de categorías las secciones de cuidado bucal (excluye mascotas). |
| `secciones_previas` | `cid`, `raw_dir` | lista de secciones | Respaldo: si el árbol de categorías no responde, reutiliza las secciones de la última ejecución completa guardada en `raw/`. |
| `limpiar_precio` | `x` | número o `NA` | Convierte un precio en texto a número («$ 12.900» → 12900). Un precio ausente, cero o negativo queda `NA`, nunca 0. |
| `ahora_iso` | — | texto | Fecha y hora de Colombia en ISO 8601 (`-05:00`). |
| `conectar` | `db_path`, `esquema` | conexión | Abre la base de escritura y crea lo que falte de la estructura (tablas, columnas, vistas) sin borrar datos. |
| `insertar` | `con`, `cid`, `lote`, `modo`, `n_rechazadas` | entero o `NA` | Inserta la ejecución, sus secciones, anuncios y observaciones. Devuelve `NA` si esa ejecución ya estaba cargada. |
| `resumen_ejecucion` | `con`, `ejecucion_id`, `cid` | lista | Productos nuevos, cambios de precio y no observados frente a la ejecución anterior del comercio. |
| `ejecuciones_en_raw` | `raw_dir` | data.frame | Ejecuciones guardadas en `raw/` (con `manifest.json`), por comercio y fecha. |
| `revisar_robots` | `comercios`, `raw_dir`, `modo` | data.frame | Descarga y guarda `robots.txt` y verifica que las rutas usadas estén permitidas. |
| `.get` | `url`, `params` | respuesta HTTP | Petición GET con reintentos y espera exponencial ante 429 / 5xx. |
| `.registrar_rechazos` | `con`, `rechazadas` | entero | Guarda en `observaciones_rechazadas` las filas que no pasaron la validación. |
| `.coinciden_con_base` | `con`, `ejecucion_id`, `cid`, `datos` | entero | Cuenta cuántas filas leídas de `raw/` coinciden (SKU, precio, disponibilidad) con lo guardado en la base. |
| `.extraer` | `cid`, `ejecucion_id`, `modo`, `raw_dir`, `progreso` | lista | Lógica común de las tres funciones `extraer_*`: en línea descarga y procesa; sin conexión solo procesa. |
| `.ejecutar_script` | `con`, `ruta` | — | Ejecuta un archivo `.sql` (esquema o vistas) sentencia por sentencia. |
| `.tabla_vacia` | — | data.frame | Tabla estándar sin filas, para los comercios que fallan. |
| `.leer_gz`, `.escribir_gz`, `.leer_json_gz` | `ruta` (y `bytes`) | bytes / JSON | Leen y escriben las copias crudas comprimidas. |
| `.json_py` | `x` | texto | Serializa la ficha técnica igual que `json.dumps` de Python, para conservar el formato del Taller 1. |
| `.vacio`, `.o`, `.txt` | `x` / `a`, `b` | lógico / valor | Utilidades: «está vacío», «a o, si está vacío, b» y conversión a texto con `NA`. |

### 10.2 `limpieza.R` — normalización y correspondencia de productos (reglas R1–R9, C1–C2)

| Función | Argumentos | Devuelve | Qué hace |
|---|---|---|---|
| `actualizar_correspondencias` | `con`, `ejecucion_ref`, `ruta_manual`, `min_comercios`, `fecha`, `correcciones` | lista | Re-estandariza todos los anuncios, aplica correcciones, asigna `producto_id` común entre comercios y marca los comparables. Corre en una transacción y es idempotente. |
| `estandarizar` | `nombre`, `marca_sitio`, `categoria_sitio`, `ficha` | lista | Aplica R1–R7 a un anuncio: nombre estándar, marca, subcategoría, contenido, unidad, concentración y familia. |
| `normalizar_texto` | `s` | texto | R1: minúsculas, sin tildes, coma decimal → punto, sin signos. |
| `estandarizar_marca` | `nombre`, `marca_sitio` | texto o `NA` | R2: marca conocida en el nombre; si no, la marca publicada por el comercio. |
| `clasificar` | `nombre`, `categoria_sitio` | lista `subcategoria`, `motivo` | R3 y R4: subcategoría por expresiones regulares y exclusión de lo que no es cuidado bucal. |
| `extraer_contenido` | `nombre`, `ficha`, `subcategoria` | lista | R5 y R6: contenido unitario, número de unidades, contenido total, unidad y concentración. |
| `extraer_unidades` | `n` | lista `n`, `regla` | Número de unidades del empaque («3 x 75 ml», «x 5 und», «lleve 3 pague 2»…). |
| `normalizar_unidad` | `valor`, `unidad` | lista | Convierte a mL, g o m (1 L → 1000 mL). |
| `familia_de` | `nombre`, `marca` | lista `clave`, `legible` | R7: nombre del producto sin tamaño, empaque ni marca. |
| `nombre_para_analisis` | `nombre_producto`, `nombre_item` | texto | Elige el nombre del SKU o la combinación de producto e ítem. |
| `texto_tamano` | `contenido_total`, `contenido_unitario`, `n_unidades`, `unidad`, `concentracion` | texto | Texto de la presentación («3 x 75 ml (1450 ppm)»). |
| `gtin_valido` | `codigo` | texto o `NA` | R8: valida el dígito de control del EAN y lo devuelve en 14 dígitos. |
| `leer_manuales` | `ruta` | data.frame | Lee `correspondencias_manuales.csv` (R8a). |
| `marcar_comparables` | `con`, `ejecucion_ref`, `min_comercios` | lista | R9: marca como comparables las presentaciones con precio disponible en todos los comercios de la ejecución de referencia. |
| `elegir_ejecucion_referencia` | `con`, `min_comercios` | texto | Ejecución más reciente con al menos tres comercios y ocho presentaciones comunes. |
| `.aplicar_correcciones` | `con`, `A`, `fecha` | data.frame | C0, C1 y C2: reaplica correcciones registradas y homologa contenido y subcategoría por EAN (mayoría estricta). |
| `.registrar_correccion` | `con`, `fecha`, `anuncio_id`, `campo`, `anterior`, `nuevo`, `motivo`, `regla` | — | Guarda una corrección automática en la tabla `correcciones`. |
| `.actualizar_correspondencias` | (los de `actualizar_correspondencias`) | lista | Cuerpo de `actualizar_correspondencias`, sin la transacción. |
| `.clave_nombre`, `.id_nombre` | campos estandarizados / `clave` | texto | R8c: clave normalizada y su identificador `N` + hash. |
| `.comercios_ejecucion`, `.comunes` | `con`, `eid` | vector | Comercios no fallidos de una ejecución y presentaciones presentes en todos ellos. |
| `.hay_tabla` | `con`, `tabla` | lógico | ¿Existe esa tabla o vista en la base? |
| `re_buscar`, `re_hay`, `re_todos` | `patron`, `x` | coincidencia / lógico / matriz | Expresiones regulares PCRE (equivalentes a `re` de Python). |
| `moda`, `fmt_g`, `titulo`, `es_nulo`, `%\|\|%` | `x` | valor | Utilidades: valor más frecuente, formato numérico corto, mayúscula inicial, nulo y valor por defecto. |

### 10.3 `validacion.R` — validación y correcciones

| Función | Argumentos | Devuelve | Qué hace |
|---|---|---|---|
| `validar_observaciones` | `datos`, `referencia` | lista `validas`, `rechazadas`, `faltan_referencia`, `agente` | Aplica las reglas V1–V7 con `pointblank`. Las filas que fallan se separan con el motivo; no se insertan. |
| `comparables_de_referencia` | `con` | data.frame | Anuncios de los ocho productos comparables de referencia en cada comercio. |
| `elegir_comparables_referencia` | `con`, `n` | entero | Elige una sola vez los ocho comparables de referencia (EAN válido, sin alertas, precio en los tres comercios en todas las ejecuciones completas). |
| `registrar_correccion` | `con`, `anuncio_id`, `campo`, `valor_nuevo`, `motivo` | entero | Corrección manual de un campo estandarizado; queda registrada y se reaplica en cada actualización. |
| `descartar_observacion` | `con`, `observacion_id`, `motivo` | entero | Marca una observación como descartada (no la borra) y lo registra. |

### 10.4 `db.R` — consultas de la aplicación

| Función | Argumentos | Devuelve | Qué hace |
|---|---|---|---|
| `abrir_conexion`, `cerrar_conexion` | `db_path` / `con` | conexión / — | Abre la conexión de solo lectura de la aplicación y la cierra al detenerla. |
| `filtros` | `comercios`, `subcategorias`, `marcas`, `precio_min`, `precio_max`, `ejecucion`, `fecha_desde`, `fecha_hasta`, `solo_promociones`, `solo_comparables`, `texto` | lista | Crea la lista de filtros que reciben las demás funciones. |
| `validar_busqueda` | `texto` | lista `ok`, `palabras`, `mensaje` | Valida la búsqueda: máximo 60 caracteres; letras, números, espacios y `. , % + -`. |
| `listar_ejecuciones`, `detalle_ejecuciones`, `ultima_ejecucion` | `con` | data.frame | Ejecuciones con su estado, en resumen, por comercio y la más reciente. |
| `opciones_filtros` | `con` | lista | Valores disponibles para los selectores (comercios, subcategorías, marcas, precios, fechas). |
| `productos_filtrados` | `con`, `f`, `limite` | data.frame | Tabla de productos con los filtros aplicados. |
| `indicadores` | `con`, `f` | data.frame | Productos, observaciones, % en promoción, % agotado y precio mediano. |
| `conteo_por_comercio`, `perfil_comercios` | `con`, `f` | data.frame | Conteos por comercio; el perfil añade marcas y precio mediano (fichas de la pestaña «Comercios»). |
| `mediana_por_subcategoria`, `distribucion_precios` | `con`, `f` | data.frame | Precio mediano por subcategoría; percentiles y cuartiles por comercio. |
| `cambios_en_ejecucion` | `con`, `ejecucion` | data.frame | Cuántos precios subieron y bajaron en una ejecución. |
| `lista_comparables` | `con`, `solo_verificados` | data.frame | Presentaciones comparables; las ocho de referencia primero. |
| `evolucion_precio` | `con`, `producto_id`, `comercios` | data.frame | Precio de una presentación en cada comercio y ejecución. |
| `precio_unitario_comparables`, `unidades_comparables` | `con`, `ejecucion`, `unidad`, … | data.frame | Precio por unidad de contenido (una sola unidad de medida a la vez) y unidades disponibles. |
| `ahorro_por_producto` | `con`, `ejecucion`, `comercios`, `subcategorias` | data.frame | Diferencia entre el comercio más caro y el más barato por producto; maneja empates. |
| `quien_es_mas_barato` | `con`, `ejecucion`, `comercios`, `subcategorias` | data.frame | Cuántos productos comparables son más baratos en cada comercio (datos del waffle). |
| `composicion_catalogo` | `con`, `f`, `n` | data.frame | % de anuncios de cada comercio por subcategoría (columnas porcentuales). |
| `marcas_por_comercio` | `con`, `f`, `n` | data.frame | Marcas con más anuncios en cada comercio (packed bubble). |
| `jerarquia_catalogo` | `con`, `f`, `n_sub`, `n_marca` | data.frame | Comercio → subcategoría → marca con número de anuncios (sunburst). |
| `comparar_ejecuciones` | `con`, `anterior`, `actual`, `comercios`, `umbral` | lista | Cambios de precio, productos nuevos y no observados entre dos ejecuciones. |
| `calcular_canasta` | `con`, `items`, `ejecucion`, `comercios` | lista | Costo de la canasta por comercio (solo si tiene todos los productos), costo mínimo combinando comercios y ahorro. |
| `listar_correcciones`, `listar_rechazadas`, `resumen_disponibilidad` | `con` (y `ejecucion`) | data.frame | Tablas de calidad de datos. |
| `.where` | `con`, `f` | SQL | Arma la condición `WHERE` con valores escapados por `glue_sql`. |
| `.q` | `con`, `sql`, `...` | data.frame | Consulta con parámetros `?`. |

### 10.5 `graficos.R` — tema visual, formato y gráficos

| Función | Argumentos | Devuelve | Qué hace |
|---|---|---|---|
| `tema_app` | — | tema `bslib` | Colores, tipografías y bordes de la interfaz. |
| `grafico_evolucion` | `d` | highchart | Líneas: precio de un producto comparable por comercio y ejecución. |
| `grafico_precio_unitario` | `d`, `unidad`, `maximo` | highchart | Puntos por comercio con el rango entre el más barato y el más caro (precio por unidad). |
| `grafico_distribucion` | `d` | highchart | Cajas: distribución de precios por comercio (escala logarítmica). |
| `grafico_ahorro` | `d`, `maximo` | highchart | Barras: ahorro por producto, coloreadas por el comercio más barato. |
| `grafico_composicion` | `d` | highchart | Columnas porcentuales: composición del catálogo por subcategoría. |
| `grafico_burbujas` | `d` | highchart | Packed bubble: marcas de cada comercio. |
| `grafico_sunburst` | `d` | highchart | Sunburst: comercio → subcategoría → marca. |
| `waffle_html` | `conteo` | HTML | Waffle de 100 cuadros con el reparto del comercio más barato. |
| `ficha_comercio` | `cid`, `nombre`, `cifra`, `cifra_texto`, `filas` | HTML | Ficha con logo y cifras de un comercio. |
| `color_comercio`, `simbolo_comercio`, `logo_html` | `comercio_id` (y `alto`, `grande`) | texto | Color, símbolo y logo de cada comercio, iguales en toda la app. |
| `cop`, `pct`, `entero` | `x` (y `decimales`) | texto | Formato en pesos colombianos, porcentaje y entero con separador de miles. |
| `fecha_hora`, `etiqueta_ejecucion` | `iso` / `ejecucion_id` | texto | Fecha y hora legibles («2026-10-09 14:40»). |
| `.tema`, `.opciones_idioma`, `.marcas_log` | `hc` / — / `a`, `b` | — | Aplica el tema a los gráficos, configura separadores en español y calcula marcas legibles para ejes logarítmicos. |

### 10.6 `app.R` y scripts auxiliares

| Función / script | Argumentos | Qué hace |
|---|---|---|
| `tarjeta_indicador` (app.R) | `titulo`, `id`, `detalle_id`, `tema` | Crea una tarjeta de indicador del Resumen. |
| `server` (app.R) | `input`, `output`, `session` | Servidor de Shiny: filtros, caché (`bindCache`), gráficos, tablas, canasta y actualización en segundo plano (`ExtendedTask`). Dentro define ayudas locales: `opciones_ejecucion`, `enlace`, `tabla_simple` y `dt_plana`. |
| `configurar.R` | — | Instala las dependencias con las versiones de `renv.lock` y verifica que carguen. |
| `migrar_taller1.R` | carpeta del Taller 1 (opcional) | Copia la base y `raw/` del Taller 1 y les agrega la estructura del Taller 2. |
