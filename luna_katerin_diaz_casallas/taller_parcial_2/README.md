# Taller 2 – Comparador de precios de vitaminas en Shiny

**Asignatura:** Minería de Datos (2016325) – Universidad Nacional de Colombia
**Autora:** Luna Katerin Diaz
**Lenguaje:** R (probado con R 4.6.1)
**Aplicación publicada:** https://ldiazca.shinyapps.io/comparador-vitaminas/

Aplicación web en Shiny construida sobre el comparador de precios del Taller 1. Trabaja con la misma categoría (**vitaminas**), los mismos tres comercios y las mismas 10 presentaciones comparables (8 productos):

- **Cafam** (drogueriascafam.com.co)
- **La Rebaja Virtual** (larebajavirtual.com)
- **La Alemana** (tudrogueriavirtual.com)

La aplicación consulta la base SQLite del Taller 1. La actualiza con el mismo módulo de *web scraping* y muestra dónde conviene comprar un producto o una canasta.

Todo el proceso está en R: extracción, acceso a datos, aplicación y pruebas.

## Estructura de archivos

```
taller_2/
├── app.R                      # Aplicación Shiny: interfaz, gráficos y actualización en segundo plano
├── db.R                       # Acceso a datos: esquema, correcciones, vistas y consultas
├── scraper.R                  # Módulo de extracción del Taller 1 (secciones 1 a 6) + validación y tolerancia a fallas (sección 7)
├── validacion.R               # Reglas de validación, disponibilidad, ahorro, cambios de precio y canasta
├── comparador_precios.sqlite  # Base de datos
├── diccionario_datos.md       # Descripción de tablas, vistas y columnas
├── renv.lock                  # Dependencias con versiones fijas
├── README.md                  # Este archivo
├── tests/
│   └── test_precios.R         # Pruebas automáticas (testthat)
└── raw/                       # Copias crudas
    ├── cafam_vitaminas_resultados.csv     # Primera ejecución (11-oct-2026), productos ya extraídos
    ├── rebaja_vitaminas_resultados.csv
    ├── alemana_vitaminas_resultados.csv
    └── <comercio>/<id_ejecucion>/         # Ejecuciones siguientes
        ├── paginas.csv                    # Página, URL y fecha-hora de consulta
        └── pagina_NN.html.gz              # HTML original de cada página
```

## Requisitos

- **R 4.2 o superior** (el `renv.lock` registra R 4.6.1).
- **Google Chrome o Chromium**, solo para la actualización en línea: `chromote` controla un Chrome sin interfaz.

Para instalar las versiones exactas de los paquetes, abre R en esta carpeta y ejecuta:

```r
install.packages("renv")
renv::restore()
```

Los paquetes principales son `shiny`, `bslib`, `highcharter`, `DT`, `future`, `promises`, `pointblank`, `glue`, `rvest`, `chromote`, `dplyr`, `stringr`, `DBI`, `RSQLite` y `testthat`.

## Cómo ejecutarlo

```r
shiny::runApp()
```

Al iniciar, la aplicación aplica a la base el esquema y las correcciones pendientes (no se repiten si ya están) y reconstruye `anuncios`, `productos_comparables` y las vistas.

### Actualizar precios

La pestaña **Actualizar** tiene dos modos:

- **En línea:** llama a `ejecutar_recoleccion_completa(modo_offline = FALSE)` de `scraper.R`. Crea una ejecución nueva con identificador `AAAAMMDD_HHMMSS` (hora de Colombia), recorre la categoría completa en los tres sitios y guarda el HTML de cada página en `raw/<comercio>/<id_ejecucion>/`. Toma unos 35 minutos.
- **Sin conexión:** llama a la misma función con `modo_offline = TRUE`. Vuelve a extraer los productos de las copias de `raw/` sin consultar los sitios.

La actualización corre en segundo plano (`ExtendedTask` con `future`), así que la aplicación sigue respondiendo mientras tanto. Cada comercio se procesa así:

1. Se registra la ejecución.
2. Se validan las observaciones.
3. Se insertan solo las válidas que no existían.

Esos tres pasos se hacen dentro de una transacción. Si un comercio falla, se registra como `parcial` o `fallida` con el motivo y se sigue con los demás. Al terminar, la aplicación muestra un resumen por comercio y actualiza indicadores, gráficos y tablas sin reiniciarse. El resumen incluye productos recolectados, nuevos, con cambio de precio, no observados y rechazados.

La recolección también se puede ejecutar sin la aplicación:

```r
source("scraper.R")
ejecutar_recoleccion_completa(modo_offline = FALSE)
```

## Pruebas

Desde esta carpeta:

```
Rscript -e "testthat::test_dir('tests')"
```

Las pruebas usan datos pequeños y una base temporal; no consultan los sitios ni modifican la base de la entrega. Verifican:

- la conversión del precio en texto a número;
- la normalización de unidades a mL, g o unidad;
- el ahorro cuando hay empate en el menor precio;
- que cargar dos veces la misma ejecución no duplica observaciones;
- la detección de subidas, bajadas, productos nuevos y no observados;
- que un enlace descartado no genera cambios de precio;
- que la canasta no se calcula en un comercio al que le falta un producto.

## Organización del código

**`scraper.R`** conserva sin cambios las secciones 1 a 6 del Taller 1. La sección 7 agrega:

- el agente de usuario;
- la validación antes de insertar;
- la transacción por comercio;
- la tolerancia a fallas (`recolectar_en_linea()`, `recolectar_copias()` y `cerrar_con_resumen()`).

**`validacion.R`** contiene las reglas que no dependen de la base: limpieza de contenido y unidades, disponibilidad, validación con `pointblank`, ahorro, cambios de precio y costo de la canasta.

**`db.R`** contiene:

- el esquema que se agrega a la base del Taller 1;
- la limpieza y correspondencia de productos;
- las vistas;
- las correcciones;
- las consultas que usa la aplicación.

Cada consulta recibe los filtros como argumentos y los pasa como parámetros.

**`app.R`** solo llama a funciones de `db.R` y `scraper.R`; no contiene SQL.

## Base de datos (`comparador_precios.sqlite`)

| Objeto | Contenido |
|---|---|
| `ejecuciones` | Una fila por corrida y comercio: identificador, fecha y hora de inicio y fin, modo, páginas, registros, productos distintos, total que muestra el sitio, estado y motivo |
| `historico_productos` | Una fila por observación de precio, con su disponibilidad. Restricción de unicidad sobre `(comercio, enlace, fecha_extraccion)` |
| `anuncios` | Una fila por producto de cada comercio, con campos estandarizados, motivo de descarte, `id_producto` y `comparable` |
| `productos_comparables` | Las 10 presentaciones comparables con su contenido total y unidad normalizada (mL, g o und) |
| `correcciones` | Cambios hechos sobre la base del Taller 1: fecha, registro, valor anterior, valor nuevo y motivo |
| `observaciones_rechazadas` | Observaciones que no pasaron la validación, con el motivo |

El detalle de cada columna está en `diccionario_datos.md`.

### Vistas

| Vista | Contenido y uso |
|---|---|
| `v_observaciones` | Cada observación con su anuncio estandarizado. Filtros, indicadores, distribución de precios y catálogo |
| `v_precios_comparables` | Una observación por ejecución, comercio y presentación comparable, con precio por unidad |
| `v_comparables` | La vista anterior más `es_mas_barato` (1 en todos los comercios empatados). Ahorro, evolución, precio unitario y canasta |
| `v_ultimo_precio` | La observación más reciente de cada anuncio, con precio unitario y disponibilidad |
| `v_cambios_precio` | Diferencia de cada anuncio frente a su observación de la ejecución anterior. Indicador de cambios y resumen de actualización |

### Ejecuciones

| Ejecución | Fecha | Origen | Estado |
|---|---|---|---|
| `20261011_195616` | 11-oct-2026 | Taller 1; en `raw/` solo el CSV con los productos extraídos | Cafam `parcial`; La Rebaja y La Alemana `completa` |
| `20261013_191617` | 13-oct-2026 | Taller 1; HTML de cada página | `completa` en los tres |
| `20261114_124642` | 14-nov-2026 | Taller 2, en línea; HTML de cada página | `completa` en los tres |

Las ejecuciones del 13 de octubre y del 14 de noviembre son completas y tienen los 8 productos comparables en los tres comercios.

El 14 de noviembre se obtuvieron:

- **Cafam:** 401 productos, igual al total del sitio;
- **La Rebaja:** 368 productos, frente a 367 que muestra el sitio;
- **La Alemana:** 760 productos (el sitio no muestra un total).

Ese día La Rebaja no listó la presentación P08 (Kola Tarrito Rojo fresa 135 g): su SKU 153179 no aparece en ninguna de las 24 páginas guardadas en `raw/rebaja/20261114_124642/`. El producto sigue cubierto por P07 (380 g). La ausencia queda registrada como `presentacion_no_observada`.

### Validación antes de insertar

Antes de insertar, las observaciones se separan en válidas y rechazadas, y las válidas se confirman con un agente de `pointblank`. Las reglas son:

- precio numérico y mayor que cero, salvo que el sitio informe agotado;
- comercio, URL y fecha y hora de consulta presentes;
- sin observaciones duplicadas de comercio, URL y fecha y hora en la misma ejecución;
- los 8 productos comparables presentes en cada comercio.

Si falta uno de los 8 productos, la ejecución de ese comercio queda `parcial`. Si solo falta una de las dos presentaciones de un producto (Kola Tarrito Rojo 380 g y 135 g; Centrum Silver Women x30 y x60), se registra como `presentacion_no_observada` y la ejecución no cambia de estado. Las observaciones rechazadas no se insertan: quedan en `observaciones_rechazadas` con el motivo.

### Disponibilidad

`historico_productos.disponibilidad` vale `disponible` (precio mayor que cero) o `agotado` (el sitio publica $0 o un texto de agotado). La tercera situación, **no observado**, es la ausencia del anuncio en una ejecución. Se calcula al comparar dos ejecuciones y no se interpreta como agotado.

### Correcciones de la base del Taller 1

Están en la tabla `correcciones` y las aplica `aplicar_correcciones()` de `db.R`. No se borró ninguna observación.

1. **Categoría incompleta.** La ejecución de Cafam del 11 de octubre figuraba como `completa`. Sin embargo, solo leyó 283 productos en 24 páginas, y el 13 de octubre el sitio mostraba 400 en 34. Pasa a `parcial`.
2. **Anuncio sin datos.** Un enlace publicitario de La Alemana (Pedialyte, con parámetros `gclid`) no tenía nombre ni precio. Queda descartado con el motivo `anuncio_sin_nombre`.
3. **Unidad normalizada.** La unidad de las presentaciones comparables era `cápsula` o `tableta`. Pasa a `und`; la forma farmacéutica sigue en `presentacion`.
4. **Cobertura de La Rebaja (14-nov).** La ejecución quedó `parcial` con una regla que exigía las 10 presentaciones. Con la regla de los 8 productos pasa a `completa`.

Además, dos enlaces del Taller 1 recibían un producto distinto en cada página: la página de inicio de Cafam y un enlace con `?idsku=12084` en La Alemana. Ya estaban descartados en `anuncios`, pero el cálculo de cambios de precio no los excluía y mostraba variaciones de hasta 1.700 %. Ahora `v_cambios_precio` y la comparación de ejecuciones solo usan anuncios no descartados.

## Aplicación

- **Resumen:** la fecha de la ejecución elegida y seis indicadores con su unidad: productos, observaciones, % en promoción, precio mediano, ahorro máximo y cambios de precio. Debajo, la distribución de precios por comercio y la diferencia de precio entre comercios para cada presentación comparable.
- **Comparar:** evolución del precio de una presentación comparable, con una serie por comercio, y precio por unidad de contenido entre tamaños del mismo producto, sin mezclar unidades.
- **Cambios:** compara dos ejecuciones (por defecto, las dos más recientes) sobre el mismo anuncio y comercio. Una tabla muestra, según se elija, los productos que cambiaron de precio (en COP y en %), los nuevos o los que ya no aparecen. Las variaciones que superan el umbral elegido quedan resaltadas.
- **Canasta:** el usuario elige presentaciones comparables y cantidades, y se usan precios de una misma ejecución. Muestra:
  - el costo en cada comercio, solo si tiene todos los productos;
  - el costo mínimo comprando cada producto donde es más barato;
  - el ahorro frente a comprar todo en un solo comercio.
- **Catálogo:** tabla con comercio, nombre, marca, presentación, precio, precio unitario, promoción, disponibilidad, fecha de consulta y enlace. Se puede ordenar, buscar y descargar en CSV.

Los filtros del panel lateral se pueden combinar:

- ejecución;
- comercio (selección múltiple);
- subcategoría;
- marca;
- rango de precio;
- solo promociones;
- solo comparables;
- búsqueda por palabras en el nombre o en el texto original.

Cada comercio conserva su color en toda la aplicación: Cafam azul, La Alemana naranja y La Rebaja verde.

**Gráfico de libre elección.** El gráfico "Diferencia de precio entre comercios" responde: ¿en qué productos vale la pena comparar antes de comprar? Para cada presentación comparable muestra la diferencia en COP entre el precio más alto y el más bajo de una misma ejecución. Así se ve en qué productos elegir bien el comercio cambia el valor de la compra y en cuáles la diferencia es pequeña.

## Seguridad

- **Credenciales:** no hay ninguna en el repositorio. Las de shinyapps.io se configuran en la consola con `rsconnect::setAccountInfo()`. `.Renviron` está en `.gitignore`.
- **Consultas parametrizadas:** los valores del usuario van siempre como parámetros (`?` o `glue::glue_sql`, también para los valores de `IN`).
- **Validación de entradas:** la búsqueda admite como máximo 80 caracteres: letras, números, espacios y `. , + -`. Los demás filtros solo aceptan valores de listas cargadas desde la base.
- **Buenas prácticas de scraping:**
  - agente de usuario identificable (`ComparadorVitaminasUNAL/2.0`);
  - una página a la vez, con pausas entre páginas;
  - máximo 60 páginas por comercio y ejecución;
  - en La Alemana se usa la paginación `vitaminas?page=N`, que es la que permite su `robots.txt`.

## Despliegue

La aplicación se publica en shinyapps.io desde la consola de R:

```r
install.packages("rsconnect")
rsconnect::setAccountInfo(name = "<cuenta>", token = "<token>", secret = "<secreto>")
rsconnect::deployApp(
  appFiles = c("app.R", "db.R", "scraper.R", "validacion.R",
               "comparador_precios.sqlite", "raw"),
  appName = "comparador-vitaminas"
)
# No incluir renv.lock en el despliegue: shinyapps resuelve paquetes solo.
# El renv.lock sí va en el Pull Request del curso (reproducibilidad local).
```

- shinyapps.io no tiene Chrome, y los tres sitios cargan los productos con JavaScript, así que en el servidor no se puede hacer *scraping*. La aplicación lo informa en la pestaña Actualizar y permite el modo sin conexión. La actualización en línea funciona en la ejecución local.
- La plataforma gratuita no conserva los cambios en la base al reiniciarse. Después de un reinicio, la base vuelve a ser la del repositorio.

## Hallazgos

Se basan en la ejecución `20261114_124642` (14-nov-2026) y en su comparación con `20261013_191617` (13-oct-2026). Precios en COP, sin envío.

1. **La Alemana es la más barata en 7 de las 10 presentaciones comparables.** Cafam es más barata en Aquasol E y en ácido fólico Ecar, y La Rebaja en Complejo B Genfar. Una canasta con una unidad de cada presentación cuesta:
   - $448.300 en La Alemana;
   - $486.575 en Cafam;
   - en La Rebaja no se puede armar, porque ese día no tenía la kola de 135 g.

   Comprando cada producto donde es más barato, cuesta $439.595: solo $8.705 menos que todo en La Alemana. Se verifica en la pestaña **Canasta**.
2. **El empaque grande tiene menor precio por unidad, pero exige un desembolso mayor.**
   - Centrum Silver Women en La Alemana: el de 60 tabletas cuesta $1.562 por tableta y el de 30, $1.800 (13 % menos en el grande). El de 60 cuesta $93.700 y el de 30, $54.000.
   - Kola Tarrito Rojo fresa: $78 por gramo en el tarro de 380 g y $96 en el de 135 g.

   Se verifica en la pestaña **Comparar**, gráfico de precio por unidad.
3. **Las diferencias entre comercios no son iguales en todos los productos.** Las mayores son:
   - Centrum Silver Women x60: $12.200 (11,5 %);
   - Vitacerebrina caramelo: $9.800 (15,6 %);
   - Cebion gotas fresa: $7.000 (22,8 %, la mayor en porcentaje).

   En Aquasol E la diferencia es de solo $1.500 (1,9 %). Se verifica en el **Resumen**, gráfico de diferencia de precio entre comercios.
4. **Cafam es el comercio con más cambios de precio y más promociones.** Entre el 13 de octubre y el 14 de noviembre, en Cafam bajaron 136 productos y subieron 74; en La Rebaja, 20 y 13. Cafam tiene el 39,8 % de sus productos en promoción, contra 20,0 % en La Alemana y 10,9 % en La Rebaja. Por ejemplo, en Cafam:
   - Complejo B Genfar pasó de $65.300 a $59.625;
   - Centrum Silver Women x60 pasó de $95.310 a $105.900.

   Se verifica en la pestaña **Cambios** y en el indicador de promoción filtrando por comercio.

## Uso de inteligencia artificial

Se usó **Gemini** como un asistente de IA para:

- corregir la primera versión de `validacion.R` y  `app.R`;
- revisar la base del Taller 1 en busca de errores;
- corregir la redacción de este README y el diccionario de datos.
- por último, para corregir errores a la hora de conectar y ejecutar todo.

## Notas

- Los precios corresponden al momento de cada captura y no incluyen envío, mínimos de compra ni descuentos por afiliación o medio de pago.
- La primera ejecución (11-oct-2026) solo conserva en `raw/` el CSV con los productos ya extraídos. Desde la segunda se guarda el HTML original de cada página.
