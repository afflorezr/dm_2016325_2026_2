# Taller 2 · Comparador de precios (Shiny)

**Daniel Mauricio Vanegas Oliveros** · Minería de Datos (2016325) · Universidad Nacional de Colombia

Aplicación web en **Shiny (R)** que consulta una base SQLite, la actualiza con el scraper del Taller 1 y orienta al consumidor sobre dónde comprar una presentación o una canasta de **alimentos y snacks** (categoría *Galletas, cereales, frutos secos, barras convencionales, conservas y otros alimentos*) en **Carulla, Éxito y Jumbo**. Se comparan las mismas 8 presentaciones en los 3 comercios.

**Aplicación publicada:** *https://h6zgrw-daniel0mauricio-vanegas0oliveros.shinyapps.io/parcial_2/*

## 1. Cómo ejecutarla

Todo se corre **desde la carpeta `taller_2/`** (las rutas son relativas; no se usa `setwd()`). Requiere R ≥ 4.3, shiny ≥ 1.8.1 y bslib ≥ 0.7 (por `ExtendedTask` y `input_task_button`).

``` r
# 1. Dependencias (versiones fijas en renv.lock)
install.packages("renv"); renv::restore()
#    Si todavía no existe renv.lock: renv::init() y, con todo instalado, renv::snapshot()

# 2. Aplicación
shiny::runApp()
```

Paquetes: shiny, bslib, DT, highcharter, DBI, RSQLite, dplyr, tibble, stringr, readr, promises, future, rvest, xml2, chromote (solo para el scraping en línea) y testthat (pruebas).

### Datos

`productos.sqlite` (que cumple la función de `comparador_precios.sqlite`) ya viene construida. Para regenerarla o agregar una lectura nueva:

``` bash
Rscript scraper.R       # descarga las páginas a raw/ con el sufijo SUFIJO_EJECUCION ("2" para hoy)
Rscript sql_consult.R   # valida e inserta en productos.sqlite todo lo que esté en raw/ y no esté en la base
```

- Las copias del 10 de octubre (`raw/<Comercio>_<consulta>.html`) deben estar en `raw/`.
- La lectura del Taller 1 se importa de `consultas_iniciales.db` (copiada en esta carpeta).
- Las lecturas nuevas se guardan como `raw/Carulla_cereales2.html`, `…3.html`, etc., y `raw/manifiesto.csv` guarda la hora real de cada descarga.
- El scraper necesita **Google Chrome** y el paquete `chromote`.

### Pruebas

``` bash
Rscript -e 'testthat::test_dir("tests")'
```

13 pruebas (usan datos pequeños y una base temporal; no tocan `productos.sqlite` ni los sitios).

## 2. Estructura de archivos

```         
taller_2/
├── app.R                  Principal: solo llama a global.R, app_ui.R y app_server.R
├── global.R               Paquetes, colores por comercio y carga de módulos
├── app_ui.R               Interfaz (bslib: page_navbar + sidebar de filtros + tarjetas)
├── app_server.R           Lógica reactiva (sin SQL)
├── db.R                   Capa de acceso a datos: consultas parametrizadas
├── scraper.R              Descarga las páginas y extrae los datos (reutilizado del Taller 1)
├── sql_consult.R          Valida e inserta en SQLite, marca comparables, ejecuciones y vistas
├── validacion.R           Reglas de validación y limpieza del texto del usuario
├── graficos.R             Series de tiempo y distribución con highcharter; formato COP
├── productos.sqlite       Base de datos
├── consultas_iniciales.db Base del Taller 1 (origen de la ejecución #1)
├── diccionario_datos.md   Tablas, vistas y columnas
├── raw/                   Copias crudas de las páginas + manifiesto.csv
├── tests/                 Pruebas con testthat
├── renv.lock              Dependencias con versión fija (generar con renv::snapshot(), ver §1)
└── README.md
```

## 3. Cómo funciona

1.  **Ejecuciones.** Cada lectura del scraper es una fila de `ejecuciones` (fecha, modo, estado). Las observaciones nuevas se **agregan** sin tocar las anteriores y conservan su copia cruda (`archivo_raw`), su fecha y hora y el id de la ejecución.
2.  **Validación antes de insertar.** Precio numérico y \> 0; comercio, URL y fecha/hora presentes; sin duplicados en la ejecución; y los 8 comparables presentes en cada comercio. Lo que no pasa va a `rechazados` con su motivo; si faltan comparables, el comercio queda `parcial`.
3.  **Botón «Actualizar precios».** Corre en segundo plano (`ExtendedTask` + `future_promise`), llama a las funciones de `scraper.R`, valida, inserta **dentro de una transacción por comercio** y muestra un resumen por comercio (recolectados, nuevos, cambios de precio, no observados). Si un comercio falla, continúa con los demás.
4.  **Modo sin conexión.** «Reprocesar raw/» relee las copias crudas. Cada ejecución se identifica por su clave (`raw:2`…): reprocesar lo mismo **no duplica** nada.
5.  **Seguridad.** Sin credenciales en el repositorio (`.gitignore`); todo valor del usuario va como parámetro `?`; los textos se limitan a 60 caracteres y a un conjunto de caracteres; el scraper usa pausas (10 s), reintentos limitados, tope de 40 peticiones y un agente de usuario identificable (`options(taller2.user_agent = NULL)` lo desactiva si un comercio lo bloquea).

### Vistas SQL (las usa la aplicación directamente)

| Vista | Qué entrega |
|----|----|
| `v_productos` | Todas las observaciones con la fecha de su ejecución, marca normalizada y precio unitario. Base de los filtros, la tabla y los indicadores. |
| `v_ultimo_precio` | El precio más reciente de cada anuncio (comercio + título). |
| `v_comparables` | Las presentaciones comparables con precio por g y por unidad del empaque. Alimenta las series, el ahorro y la canasta. |
| `v_cambios_precio` | Anuncios cuyo precio cambió frente a su observación anterior. Alimenta el indicador de cambios. |

## 4. Hallazgos para el consumidor

> Basados en la **ejecución #1 (10 de octubre de 2026)**. Cada cifra se puede reproducir en la aplicación (pestaña *Canasta*, *Resumen* y *Series de precio*, eligiendo esa ejecución).

1.  **La canasta de las 8 presentaciones cuesta casi lo mismo en Éxito (COP 145.250) y Carulla (COP 145.370); Jumbo es 11,0 % más cara (COP 161.183).** Comprar cada producto donde es más barato costaría COP 142.213: COP 3.037 (2,1 %) menos que la canasta de Éxito, a cambio de ir a varios comercios.
2.  **El ahorro se concentra en dos productos:** Maní La Especial con arándanos (hasta COP 8.270, 33,1 %) y Cereal Zucaritas 610 g (hasta COP 8.910, 30,8 %); en ambos Jumbo es el más caro. Corn Flakes 410 g y Froot Loops 450 g cuestan lo mismo en los tres comercios, así que da igual dónde comprarlos.
3.  **Carulla tiene 5 de las 8 presentaciones en promoción, Jumbo 1 y Éxito ninguna.** Las promociones de Carulla explican sus precios más bajos en maní, Zucaritas y Flips; son precios promocionales que pueden no mantenerse.
4.  *(Completar tras la ejecución #2 del 11 de noviembre: qué productos subieron o bajaron, cuáles comercios cambiaron más precios, y si el orden de las canastas se mantiene. Pestaña Cambios de precio* y gráfico *¿Dónde sale más barata la canasta?*.)

**Límites.** Los precios son de un momento y una sola ciudad/sede no registrada; no incluyen envío, mínimos de compra ni condiciones de las promociones.

## 5. Gráfico de libre elección

*¿Dónde sale más barata la canasta de 8 productos y eso cambia con el tiempo?* Es una serie de tiempo con el costo total de la canasta por comercio en cada ejecución. Responde la pregunta que más le importa a quien hace mercado: no cuánto cuesta un producto, sino en qué comercio le sale mejor la compra completa. Solo se grafican comercios que tienen los 8 productos en esa ejecución.

## 6. Limitaciones conocidas

- La tienda Jumbo no permitió realizar una segunda revisión, ya que recibió un bloqueo de agents (notificado a la página por el `scraper.r`).
- La lectura es la **primera página de 8 búsquedas** (≈ 330 productos), no la categoría completa.
- El scraper **no captura el aviso de «agotado»**: `disponibilidad` queda `NULL` (sin dato). «No observado» se calcula comparando ejecuciones y no significa agotado.
- El «enlace al anuncio» de la tabla lleva a la **búsqueda** del comercio, porque el scraper no guarda la URL de cada producto.
- La base se llama `productos.sqlite` (no `comparador_precios.sqlite`).
- En shinyapps.io / Posit Connect Cloud **los cambios hechos a la base se pierden al reiniciar la aplicación**, y los comercios suelen bloquear el scraping desde esos servidores: allí la app avisa y ofrece el modo sin conexión. La actualización en línea funciona al ejecutarla en el computador local.
- No se usó `pointblank`: las reglas de validación están en `validacion.R` con dplyr porque se necesita el motivo de rechazo fila por fila.

## 7. Declaración de uso de IA

Se usó **Claude (Sonnet 5.5, Anthropic)** a la fecha del 11/11/2026 para:

- Proponer la estructura de módulos.
- Reescribir, reestructurar y depurar el código de `sql_consult.R`, `scraper.R` y `graficos.R` con base a código replicado de las diapositivas de clase.
- Escribir y depurar el código de `db.R`,`validacion.R`, `app_ui.R` y `app_server.R` con base a código replicado de las diapositivas de clase.
- Escribir las pruebas de `tests/` y redactar `diccionario_datos.md`.

Verificación: se ejecutaron las 13 pruebas de testthat; se comprobó que `productos.sqlite` reproduce la ejecución del Taller 1 (330 observaciones, 24 comparables y los mismos precios y totales de canasta); y se probó el server con filtros, indicadores, cambios de precio y canasta. Los gráficos de highcharter, el scraping en línea y el despliegue se verifican manualmente antes de la entrega. Soy responsable de todo el código entregado y puedo explicarlo.
