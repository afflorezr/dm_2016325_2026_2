# Comparador de Precios - Taller 2

**Asignatura:** Minería de Datos (2016325)  
**Estudiante:** Sergio Martínez Vallejo 
**Repositorio:**  
**Aplicación publicada:** https://kw1lyb-sergio-martinez.shinyapps.io/app_precios_parcial12/

## Descripción del Proyecto
Aplicación web desarrollada en R Shiny que permite comparar precios de una canasta de productos de aseo
y desechables en tres comercios: **D1, Carulla y Olímpica**.
La aplicación consume una base de datos SQLite alimentada por un scraper propio, 
permite filtrar los productos, ver la evolución de precios, analizar cambios entre ejecuciones y 
calcular el costo de una canasta de 8 productos comparables.

## Nota importante sobre el cambio de comercio
Originalmente, el Taller 1 se realizó con los comercios Éxito, Carulla y Olímpica. 
Sin embargo, al momento de realizar el Taller 2, el sitio web de Éxito contuvo problemas a la hora de 
hacer el scraping por lo que no se pudo hacer la extracción de datos. Siguiendo los lineamientos de 
la sección 2 del taller, se reemplazó Éxito por D1, 
garantizando de nuevo los ocho productos comparables en los tres comercios. 
Este cambio está documentado en la tabla `correcciones` de la base de datos.


## Instrucciones para ejecutar localmente
1. Clona este repositorio.
2. Abrir el proyecto en RStudio.
3. Restaura las dependencias fijas:
 ```r
 renv::restore()
 ``` 
4. Ejecutar la aplicación
 ```r
 shiny::runApp("app.R")
 ``` 
5. Para correr las pruebas
 ```r
 testthat::test_dir("tests")
 ``` 

## Estructura de archivos

| Archivo / carpeta | Contenido |
|---|---|
| `app.R` | Interfaz de usuario y servidor de la aplicación Shiny (bslib, highcharter, DT). |
| `db.R` | Capa de acceso a datos: funciones que consultan SQLite (sin SQL en la interfaz). |
| `scraper.R` | Módulo de extracción: una función por comercio y `ejecutar_recoleccion()`, que ejecuta la recolección completa, registra la ejecución e inserta en SQLite sin sobrescribir. |
| `comparador_precios.sqlite` | Base de datos: tablas `ejecuciones`, `observaciones`, `productos`, `correspondencia`, `correcciones` y vistas `v_observaciones`, `v_ultimo_precio`, `v_cambios_precio`. |
| `raw/` | Copias crudas comprimidas de las respuestas, organizadas como `raw/<comercio>/<id_ejecucion>/`. |
| `tests/` | Pruebas automáticas con `testthat` (`test_precios.R`). |
| `renv.lock` | Dependencias con versiones fijas. |
| `diccionario_datos.md` | Descripción de las tablas, vistas y columnas de la base de datos. |
| `README.md` | Este documento. |

## Requisitos

- R ≥ 4.1.
- Conexión a internet solo para la recolección en línea. No se necesita navegador: los tres comercios (plataforma VTEX) se consultan con peticiones HTTP directas.
- Para correr la aplicación: `shiny`, `bslib`, `highcharter`, `DT`, `promises`, `future`.

## Instalación
Abrir la carpeta como proyecto de RStudio (o fijar el directorio de trabajo en ella) y restaurar las dependencias:
 ```r
  install.packages("renv")
  renv::restore()
 ``` 
 
## Ejecución

### Recolección en línea

```r
source("scraper.R", encoding = "UTF-8")
resumen <- ejecutar_recoleccion()   # las tres tiendas en una misma ejecución
resumen
source("correspondencia.R", encoding = "UTF-8")
```

Cada ejecución recibe un identificador (por ejemplo `20261116T180941`), guarda las copias crudas en `raw/` y agrega las observaciones a la base sin borrar las anteriores. Para revisar las rutas de categoría de una tienda: `listar_categorias_vtex("exito")`.

### Modo sin conexión

Reprocesa las copias de `raw/` sin consultar los sitios:

```r
source("scraper.R", encoding = "UTF-8")
ejecutar_recoleccion(offline = TRUE, id_ejecucion = "20261116T180941")
```

Las observaciones ya existentes no se duplican (restricción de unicidad sobre comercio, SKU y fecha y hora de consulta). Para revisar el resultado sin escribir en la base: `scrape_olimpica("20261011T101202", offline = TRUE)`.

## Descripción de las vistas SQL

La aplicación se apoya en las siguientes vistas para calcular los indicadores y gráficos:

### v_observaciones: 
Une las observaciones con su correspondencia de producto y filtra los datos descartados.

### v_ultimo_precio: 
Obtiene el precio más reciente de cada SKU por comercio.

### v_cambios_precio: 
Compara el precio actual con el anterior para detectar subidas o bajadas.


## Hallazgos para el consumidor

D1 es consistentemente más económico en productos de aseo básico, 
pero tiene un catálogo más reducido de marcas tradicionales (Familia, Rosal).

Carulla y Olímpica comparten una mayor cantidad de productos idénticos (mismos EAN),
lo que permite una comparación directa más justa.

El ahorro máximo comprando en diferentes comercios puede superar el 20% frente a 
comprar todo en un solo lugar, especialmente cuando se aprovechan las promociones de Olímpica.

## Declaración del uso de IA

* La corrección de errores en el código del scraper, para poder cambiar el comercio de Exitó a D1.

* La estructuración de las consultas SQL y las vistas.

* La optimización y aclaración en cada función usada para crear la app.

* Ayuda en errores que se encontraban realizando la app.


 
