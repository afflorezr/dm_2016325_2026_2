# Taller 2 · Comparador de precios de bebidas (Shiny + SQLite)

|  |  |
|------------------------------------|------------------------------------|
| **Asignatura** | Minería de Datos (2016325) · Universidad Nacional de Colombia |
| **Estudiante** | Laura Katherine Martínez Castiblanco |
| **Lenguaje** | R (scraping, datos, aplicación y pruebas) |
| **Categoría** | Bebidas no alcohólicas |
| **Comercios** | Éxito, Carulla y Supermercado Comunal (trío comparable). PriceSmart se recolecta pero no entra al trío. |
| **Aplicación publicada** | <https://c2d31m-laura-mart0nez.shinyapps.io/comparador-precios-bebidas/> (verificada desde un segundo dispositivo) |

> **Nota sobre el despliegue.** Las plataformas gratuitas no conservan los cambios de la base al reiniciarse: lo que se actualice en línea se pierde. La actualización con scraping funciona en la ejecución local. En el servidor (sin Chrome, y con comercios que bloquean servidores) la app lo informa y ofrece el **modo sin conexión**.

## Contenido

1.  [Ejecución local](#1-ejecución-local)
2.  [Pruebas](#2-pruebas)
3.  [Datos en la base](#3-datos-en-la-base)
4.  [Estructura del proyecto](#4-estructura-del-proyecto)
5.  [Vistas SQL](#5-vistas-sql)
6.  [Corrección de la retroalimentación del Taller 1](#6-corrección-de-la-retroalimentación-del-taller-1)
7.  [Decisiones de diseño](#7-decisiones-de-diseño)
8.  [Hallazgos para el consumidor](#8-hallazgos-para-el-consumidor)
9.  [Verificación de indicadores](#9-verificación-de-indicadores)
10. [Verificación del modo sin conexión](#10-verificación-del-modo-sin-conexión)
11. [Limitaciones](#11-limitaciones)
12. [Declaración de uso de inteligencia artificial](#12-declaración-de-uso-de-inteligencia-artificial)
13. [Notas de mantenimiento](#13-notas-de-mantenimiento)

------------------------------------------------------------------------

## 1. Ejecución local

``` r
# Desde la carpeta taller_2/ (rutas relativas; no se usa setwd())
renv::restore()     # reproduce las versiones fijadas en renv.lock
shiny::runApp()     # abre el comparador
```

**Requisitos:** shiny ≥ 1.8.1 (`ExtendedTask`) y Google Chrome para el scraping en línea. `copiar_desde_taller1.R` trae `config.R`, `scraper.R`, `comparables.R`, la base y `raw/` del Taller 1.

**Nueva corrida completa** (tarda varias horas):

``` bash
Rscript actualizar_desde_consola.R
```

También se puede lanzar desde la pestaña **Actualizar** de la app. La «corrida de prueba» de la app trabaja sobre una **copia temporal**: no modifica la base ni `raw/`.

## 2. Pruebas

``` bash
Rscript -e 'testthat::test_dir("tests")'
```

**Resultado:** `FAIL 0 | WARN 0 | SKIP 0 | PASS 59`, con 15 pruebas en `tests/test_validacion.R` y `tests/test_db.R`. Usan datos mínimos y una base temporal, nunca la base de la entrega ni los sitios.

| Área | Qué verifican |
|------------------------------------|------------------------------------|
| Precios | Conversión de texto a número |
| Unidades | Normalización de unidades |
| Ahorro | Cálculo con empates |
| Cambios | Detección de cambios de precio |
| Canasta | No se calcula si falta un producto; compra dividida |
| Inserción | Insertar dos veces la misma ejecución no duplica |
| Seguridad | Intentos de inyección SQL |
| Auditoría | Correcciones registradas, vistas e historial por `clave_producto` |
| Validación | Reglas de validación de lote |

## 3. Datos en la base

| Corrida | Fecha | Origen | Estado | Obs. válidas | Comparables (trío) |
|------------|------------|------------|------------|-----------:|-----------:|
| `20261108-174507` | 08-11-2026 | Taller 1 | completa (4 comercios) | 1.164 | 36 |
| `20261110-141724` | 10-11-2026 | Taller 2 | completa (4 comercios) | 1.141 | 34 |

**Observaciones válidas por comercio**

| Comercio             | Corrida 1 (08-11) | Corrida 2 (10-11) |
|----------------------|------------------:|------------------:|
| Éxito                |               511 |               486 |
| Carulla              |               474 |               475 |
| Supermercado Comunal |               110 |               110 |
| PriceSmart           |                69 |                70 |
| **Total**            |         **1.164** |         **1.141** |

-   Las validaciones de lote (pestaña *Datos y auditoría*) pasan en ambas corridas: precio \> 0, comercio/URL/fecha presentes, sin duplicados y ≥ 8 comparables en cada comercio del trío.
-   El historial cumple el mínimo de **dos ejecuciones completas en fechas distintas**.
-   Cada observación se rastrea hasta su ejecución (`id_ejecucion`) y su copia cruda en `raw/` (`archivo_raw`, más `raw/manifest.csv`).
-   `raw/` pesa 84 MB; ningún archivo supera 100 MB.

## 4. Estructura del proyecto

``` text
taller_2/
├── app.R                           UI (bslib, claro/oscuro) y servidor; une los módulos
├── db.R                            Todo el SQL: consultas parametrizadas, migración, correcciones, caché
├── validacion.R                    Funciones puras: precios, unidades, cambios, ahorro, canasta, validación
├── actualizacion.R                 Lo que invoca el botón (segundo plano): scraper → validación → comparables → resumen
├── scraper.R  config.R             Taller 1 (reutilizados, no reescritos)
├── comparables.R                   Taller 1 (correspondencia de productos)
├── utils_ui.R  www/estilos.css     Utilidades de interfaz y estilos
├── modulos/                        Una pestaña por archivo
├── sql/                            01 esquema · 02 índices · 03 vistas · 04 consultas de indicadores
├── tests/                          testthat
├── raw/                            Copias crudas (.html.gz) + manifest.csv
├── comparador_precios.sqlite       Base de datos
├── diccionario_datos.md  renv.lock  README.md  .gitignore  .Renviron.example
│
├── actualizar_desde_consola.R      Misma actualización sin interfaz
├── copiar_desde_taller1.R          Trae los archivos del Taller 1
├── correcciones_taller1.R          Correcciones auditadas (tabla `correcciones`)
├── reconstruir_productos_comunes.R Deja `productos_comunes` coherente con `observaciones.comparable`
├── limpiar_corrida_prueba.R        Elimina una corrida de prueba guardada por error (con respaldo)
├── verificar_indicadores.R         Reproduce los indicadores con sql/04_consultas_indicadores.sql
├── instalar_dependencias.R         Instalación de dependencias
└── desplegar.R                     Despliegue en shinyapps.io (credenciales fuera del código)
```

## 5. Vistas SQL

| Vista | Uso |
|------------------------------------|------------------------------------|
| `v_corridas` | Fechas, estado y tamaño de cada corrida |
| `v_obs_validas` | Base de filtros, KPIs, distribución y tabla (excluye descartadas; añade COP/L) |
| `v_ultimo_precio`, `v_precios_actuales` | Último precio por anuncio / foto de la corrida más reciente |
| `v_cambios_precio` | Subidas y bajadas por anuncio (`LAG`) |
| `v_comparables`, `v_productos_comparables` | Comparador, canasta y selectores |
| `v_historial_precios` | Evolución por producto y comercio (une corridas por `clave_producto`) |
| `v_canasta_supermercado` | Mínimos y empates por producto para la canasta |
| `v_ejecuciones_resumen` | Auditoría: registrado vs. guardado |

Cada indicador se reproduce con una consulta independiente en `sql/04_consultas_indicadores.sql`. Las columnas están descritas en `diccionario_datos.md`.

## 6. Corrección de la retroalimentación del Taller 1

| Observación del docente | Qué se hizo |
|------------------------------------|------------------------------------|
| La correspondencia no es válida: un producto común agrupaba productos distintos (p. ej. `PROD_COM_03` con Brisa, Cristal y San Pellegrino) | Se reescribió `scraper.R` (extracción por ficha individual: JSON-LD \> `__NEXT_DATA__` \> DOM), se creó `config.R` y `run_scraper.R`, y `comparables.R` pasó a una clave `marca\|subcategoría\|variante\|mL\|unidades` que separa sabor, sin azúcar, con/sin gas y packs mixtos. Se auditó con `revisar_comparables.R`. |
| Precios de Carulla/Éxito (\~\$142–\$293 por agua de 1,5 L) no comparables | Se lee el precio general de la ficha, se descartan precios por unidad y se rechaza todo precio por litro fuera de 300–80.000 COP/L (`precio_por_litro_implausible`). |
| La tabla `ejecuciones` no correspondía a las observaciones, el id era un número epoch y no había unicidad | La crea el scraper: `id_corrida` (AAAAMMDD-HHMMSS), una ejecución por comercio consultado, clave foránea desde `observaciones`, y `UNIQUE(comercio, sku_comercio, fecha_hora_consulta)` y `UNIQUE(id_ejecucion, sku_comercio)`. |
| El documento no llamaba al módulo; `raw/` pesaba 421 MB | La app y el botón llaman a `ejecutar_corrida()` de `scraper.R`. Las copias crudas se guardan reducidas (sin estilos ni scripts, salvo JSON-LD) y comprimidas (`.html.gz`). |

**Correcciones manuales** (tabla `correcciones`, pestaña *Datos y auditoría*). El mismo emparejamiento erróneo apareció en las dos corridas: un multipack de botellas pequeñas de Comunal (\$9.990, 3000 mL en total) se había emparejado con una botella única de 3 L (\~\$24.500) de Éxito y Carulla.

| Corrida           | Observaciones desmarcadas | Cambio             |
|-------------------|---------------------------|--------------------|
| `20261108-174507` | 33, 528, 1116             | `comparable` 1 → 0 |
| `20261110-141724` | 1197, 1667, 2257          | `comparable` 1 → 0 |

Después se reconstruyó `productos_comunes` (`reconstruir_productos_comunes.R`), que además recuperó los comparables de Coca-Cola Zero 3 L que un borrado inicial había dejado sin catálogo. Ninguna observación se borra: queda el valor anterior, el nuevo y el motivo.

## 7. Decisiones de diseño

| Tema | Decisión |
|------------------------------------|------------------------------------|
| Trazabilidad | Cada fila → `id_ejecucion` → copia cruda `archivo_raw` en `raw/`. Un dato ausente queda `NULL`. |
| Identidad del producto | `id_producto_comun` (`PROD_COM_nn`) se reasigna por corrida; la serie histórica y la canasta se unen por `clave_producto`. |
| Catálogo coherente | `v_comparables` une `observaciones` con `productos_comunes`; al corregir `comparable` se reconstruye el catálogo. |
| Tolerancia a fallas | Cada comercio se guarda en una transacción (`dbBegin/dbCommit/dbRollback`). Un comercio que falla queda `parcial`/`fallida` y los demás continúan. |
| Modo sin conexión | Reprocesa `raw/` en una base temporal, compara con lo guardado y solo registra lo que falte (`INSERT OR IGNORE`). |
| Corrida de prueba | Corre sobre una copia temporal; no contamina el historial. |
| Corrida por defecto | Comparador y Canasta usan la última ejecución con comparables; la Canasta tiene su propio selector. |
| Seguridad | Valores del usuario siempre como parámetros `?`; texto libre saneado y comodines `LIKE` escapados; sin credenciales en el repositorio; pausas, agente de usuario identificable y tope de fichas. |
| Gráfico de libre elección | «¿Cuánto me ahorro por elegir el comercio correcto?»: muestra en qué productos importa dónde comprar (ahorro % entre el comercio más barato y el más caro). |

## 8. Hallazgos para el consumidor

Basados en las corridas del 08-11 y del 10-11 de 2026 (dos días de diferencia), precios en COP. Se verifican en la app y con `sql/04_consultas_indicadores.sql`.

### 8.1 Dónde comprar importa en algunos productos

Corrida del 10-11 (pestaña *Comparador*, gráfico de ahorro). Mayores diferencias entre el comercio más barato y el más caro:

| Producto                    | Precio mínimo | Precio máximo | Ahorro |
|-----------------------------|--------------:|--------------:|-------:|
| Schweppes ginger ale 300 mL |       \$2.080 |       \$3.290 | 36,8 % |
| Manantial con gas 600 mL    |       \$2.990 |       \$4.000 | 25,3 % |
| Del Valle 2.500 mL          |       \$5.490 |       \$7.300 | 24,8 % |
| Sprite 3.000 mL             |       \$7.890 |       \$9.900 | 20,3 % |
| Canada Dry 1.500 mL         |       \$4.290 |       \$5.363 | 20,0 % |

### 8.2 Supermercado Comunal fue el más barato más veces, pero ningún comercio gana en todo

De 34 productos comparables (corrida 10-11, pestaña *Canasta*; los empates cuentan para cada comercio empatado):

| Comercio             | Productos donde tuvo el menor precio |
|----------------------|-------------------------------------:|
| Supermercado Comunal |                                   17 |
| Éxito                |                                   15 |
| Carulla              |                                   11 |

Dividir la compra no siempre compensa: en una canasta de prueba de seis productos el ahorro fue de apenas 0,1 % frente a comprar todo en Comunal.

### 8.3 Éxito subió y Carulla bajó entre ambas corridas

Pestaña *Cambios de precio* (todos los anuncios, no solo comparables):

| Comercio             | Subieron | Variación media | Bajaron | Variación media |
|----------------------|---------:|----------------:|--------:|----------------:|
| Éxito                |       41 |         +17,6 % |      16 |          −9,1 % |
| Carulla              |       24 |          +7,9 % |      41 |         −19,2 % |
| PriceSmart           |        7 |          +4,4 % |       – |               – |
| Supermercado Comunal |        0 |               – |       0 |               – |

Con solo dos días de diferencia, parte del movimiento puede deberse a promociones temporales y no a una tendencia.

## 9. Verificación de indicadores

El script `verificar_indicadores.R` garantiza que cada indicador de la app se puede reproducir con una consulta SQL independiente (requisito 14 del enunciado). Qué hace:

1.  Abre la base con la misma capa de acceso de la app (`db.R`).
2.  Toma la corrida indicada (`20261110-141724`) y una `clave_producto` de `v_comparables`.
3.  Lee `sql/04_consultas_indicadores.sql`, descarta comentarios y separa las consultas por `;`.
4.  Inyecta `:corrida` y `:clave` mediante `params`, sin concatenar texto.
5.  Imprime cada consulta con su resultado. Solo lee; no modifica la base.

``` r
source("verificar_indicadores.R")   # o: Rscript verificar_indicadores.R
```

**Resultados sobre la corrida 10-11-2026**

| Id | Indicador | Resultado |
|------------------------|------------------------|------------------------|
| K1 | Última corrida | `20261110-141724` · 2026-11-10T14:17:25-05:00 · completa · 1.141 obs. |
| K5 | Mayor ahorro en COP | COCA-COLA base · 6000 mL (2 und): \$19.990 vs \$22.500 → \$2.510 (11,16 %) |
| K6 | Cambios de precio | 72 suben · 57 bajan |

> K5 ordena por ahorro en **COP**, no en %. Por eso difiere del producto con mayor ahorro porcentual de §8.1.

**K2. Productos y observaciones por comercio**

| Comercio             | Productos | Observaciones |
|----------------------|----------:|--------------:|
| Carulla              |       475 |           475 |
| PriceSmart           |        70 |            70 |
| Supermercado Comunal |       110 |           110 |
| Éxito                |       486 |           486 |

**K3. Proporción de productos en promoción**

| Comercio             | \% en promoción |
|----------------------|----------------:|
| Carulla              |            38,1 |
| Éxito                |            30,7 |
| PriceSmart           |             0,0 |
| Supermercado Comunal |             0,0 |

**K4. Mediana del precio por litro por subcategoría**

| Subcategoría    |  COP/L |
|-----------------|-------:|
| Agua            |  5.210 |
| Gaseosas        |  5.274 |
| Jugos           |  7.275 |
| Té preparado    | 10.420 |
| Sin categorizar | 11.800 |
| Energizantes    | 19.027 |
| Café preparado  | 21.964 |

**G1. Serie histórica de un producto comparable (ejemplo)**

| Fecha      | Carulla | Supermercado Comunal | Éxito |
|------------|--------:|---------------------:|------:|
| 2026-11-08 |   5.437 |                4.290 | 4.916 |
| 2026-11-10 |   5.363 |                4.290 | 4.916 |

Comunal y Éxito mantuvieron el precio; Carulla bajó 1,4 %.

**G2. Precio promedio por litro (solo productos en mL)**

| Comercio             |  COP/L |
|----------------------|-------:|
| Supermercado Comunal |  6.819 |
| PriceSmart           |  9.245 |
| Éxito                | 11.593 |
| Carulla              | 12.149 |

**C1. Canasta.** La consulta devuelve 102 filas (34 productos comparables × 3 comercios del trío) con la columna `es_minimo`. El conteo de mínimos por comercio coincide con §8.2 (17 / 15 / 11). El costo final de la canasta lo calcula `validacion.R::calcular_canasta()` sobre esta vista.

## 10. Verificación del modo sin conexión

En la pestaña **Actualizar** se eligió *Sin conexión* y se reprocesaron las copias de `raw/` de la corrida `20261108-174507`. La app informó que no encontró Chrome en el equipo (lo habitual en servidores de despliegue) y ejecutó el reprocesamiento correctamente. La verificación muestra que lo reprocesado coincide con lo guardado:

| Comercio | Reprocesadas desde `raw/` | Presentes en la base | ¿Coincide? |
|-----------------|----------------:|----------------:|:------------------:|
| Carulla | 474 | 474 | ✔ |
| Éxito | 511 | 511 | ✔ |
| PriceSmart | 69 | 69 | ✔ |
| Supermercado Comunal | 110 | 110 | ✔ |

Esto confirma que el modo sin conexión (a) no consulta los sitios, (b) reproduce exactamente las observaciones guardadas, y (c) no duplica datos gracias a `INSERT OR IGNORE` y `UNIQUE(comercio, sku_comercio, fecha_hora_consulta)`. Los tres primeros totales suman 1.164 observaciones, igual que la corrida 1 de §3.

## 11. Limitaciones

-   Los precios son los del momento de la captura y no incluyen envío, mínimos de compra ni condiciones de las promociones.
-   «No observado» no significa agotado (Éxito: 28 productos de la corrida 1 no aparecieron en la 2).
-   La correspondencia de productos se hizo con reglas automáticas y auditoría manual; puede quedar algún emparejamiento dudoso. Un caso se detectó en ambas corridas y se corrigió de forma auditada (§6).
-   Los cambios de precio se calculan sobre todos los anuncios, no solo sobre los comparables.
-   En el servidor gratuito los cambios de la base no persisten y el scraping en línea puede no estar disponible.

## 12. Declaración de uso de inteligencia artificial

Se usó **Claude (Anthropic)** como asistente para estructurar el proyecto; escribir el esqueleto de `db.R`, `validacion.R`, `actualizacion.R`, la interfaz Shiny, las vistas SQL y las pruebas; y depurar errores. El módulo de extracción (`scraper.R`, `config.R`, `run_scraper.R`, `comparables.R`) y los datos provienen del Taller 1, ejecutados sobre los sitios reales.

**Cómo se verificó el resultado:**

1.  Las 15 pruebas `testthat` pasan (59 verificaciones).
2.  La app se ejecutó localmente y se revisó cada pestaña.
3.  Se lanzó la corrida 2 completa en línea y se revisó su resumen por comercio y las validaciones de lote.
4.  La correspondencia se auditó con `revisar_comparables.R`; se revisaron a ojo los emparejamientos con brecha ≥ 25 % y se corrigió una reincidencia en la corrida 2.
5.  Se consultó la base directamente para confirmar los hallazgos y que no hay observaciones comparables sin fila en `productos_comunes`.
6.  Se reprodujeron los indicadores con `verificar_indicadores.R` (§9).
7.  Se probó el modo sin conexión (§10).
8.  Se verificó la app publicada desde otro dispositivo.

Soy responsable de todo el código entregado.
