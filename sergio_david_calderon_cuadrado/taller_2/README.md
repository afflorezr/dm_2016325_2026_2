# Comparador de precios de cremas corporales (Taller 2)

Aplicación Shiny (R) que consulta una base SQLite con precios de cremas corporales de tres comercios colombianos (Éxito, Farmatodo y La Rebaja) y ayuda a decidir dónde comprar un producto o una canasta.

**Aplicación publicada:** https://n9qpo3-dave.shinyapps.io/comparador-cremas/

> Los datos son de dos ejecuciones completas: **17-oct-2026** y **6-nov-2026**. Todos los precios están en pesos colombianos (COP).

## Qué hace

| Pestaña | Contenido |
|---|---|
| Resumen | 6 indicadores con su periodo y unidad: productos y observaciones por comercio, última ejecución y su estado, % de productos en promoción, mediana de precio por subcategoría, ahorro máximo entre comercios y cambios de precio en la última ejecución |
| Gráficos | Evolución del precio de un producto por comercio, mediana del precio por mL o g (sin mezclar unidades), distribución de precios por comercio y porcentaje de productos en promoción por comercio |
| Tabla | Productos filtrados con comercio, marca, presentación, precio, precio por unidad, promoción, disponibilidad, fecha y enlace al anuncio; descarga en CSV |
| Cambios | Comparación entre dos ejecuciones elegidas: sube, baja, igual, nuevos y no observados, con un umbral de variación (%) |
| Canasta | Costo por comercio (solo si tiene todos los productos), mínimo combinado, ahorro frente a comprar todo en un comercio y advertencia de envío y mínimos de compra |

Filtros del panel lateral: comercio, subcategoría, marca, rango de precio, periodo (último precio, una ejecución o un rango de fechas), solo promociones, solo comparables y búsqueda de texto.

## Ejecutar en local

1. Abrir el proyecto en RStudio (carpeta `taller_2/`).
2. Restaurar las dependencias con versiones fijas:
   ```r
   renv::restore()
   ```
3. Iniciar la app:
   ```r
   shiny::runApp()
   ```

## Pruebas

Desde la raíz del proyecto:

```r
testthat::test_dir("tests/testthat")
```

Las pruebas usan una base **temporal** con datos inventados y respuestas calculadas a mano. No tocan `comparador_precios.sqlite` ni los sitios web. Cubren filtros, indicadores en SQL, cambios de precio, ahorro con empates, canasta incompleta, validación de textos, consultas parametrizadas, insertar dos veces sin duplicar y `validacion.R`.

Además, `scripts/verificar_f2.R` y `scripts/verificar_f4.R` comparan las consultas de `db.R` con un cálculo independiente en R sobre las tablas base:

```r
source("scripts/verificar_f2.R", encoding = "UTF-8")
source("scripts/verificar_f4.R", encoding = "UTF-8")
```

## Estructura

```
taller_2/
├── global.R, ui.R, server.R   # app Shiny
├── db.R                       # conexión y consultas parametrizadas
├── validacion.R               # reglas de validación y detección de agotados
├── scraper.R                  # recolección (ver "Limitaciones")
├── comparador_precios.sqlite  # base de datos
├── diccionario_datos.md       # diccionario de datos
├── raw/                       # respaldos de las ejecuciones
├── sql/                       # esquema y migraciones
├── scripts/                   # verificaciones contra cálculo independiente
├── tests/                     # pruebas testthat
├── renv.lock                  # versiones de paquetes
└── README.md
```

## Vistas de la base

| Vista | Qué contiene | Filas |
|---|---|---|
| `v_precios` | Todas las observaciones con comercio, producto, presentación y precio por unidad. Base de las demás | 462 |
| `v_ultimo_precio` | Último precio de cada anuncio | 239 |
| `v_comparables` | Observaciones de los 8 productos comparables | 48 |
| `v_cambios_precio` | Variación de cada observación frente a la anterior del mismo anuncio | 223 |
| `v_no_observados` | Anuncios vistos antes que no aparecen en una ejecución | 3 |

Las vistas heredadas del Taller 1 (`v_observaciones`, `v_variacion_precio`) se conservan en la base entregada.

## Hallazgos

Cada hallazgo se puede reproducir con la app o con la función indicada (`source("db.R"); con <- conectar()`).

1. **Éxito tiene muchas más promociones que La Rebaja.** Con el último precio de cada anuncio: Éxito 45,5 % de sus productos en promoción (35 de 77), Farmatodo 23,1 % (28 de 121) y La Rebaja 2,4 % (1 de 41). Descuento mediano: 20 % en Éxito, 17,5 % en Farmatodo y 50 % en La Rebaja, este último sobre un solo producto. Reproducir: `promociones_por_comercio(con)`.
2. **Entre el 17-oct y el 6-nov cambiaron 6 de los 8 productos comparables por comercio, todos en Éxito y Farmatodo.** Cuatro en Éxito y dos en Farmatodo, ninguno en La Rebaja. Los saltos de Éxito (de +15 % a +54 %) corresponden a promociones que terminaron: los productos 2, 3 y 8 pasaron de `es_promocion = 1` a `0`. Reproducir: `cambios_entre(con)` filtrando `id_producto <= 8`.
3. **El mayor ahorro posible entre comercios es de $ 30.300 en un solo producto.** Se da en Lubriderm reparación intensiva 946 ml, más barato en Éxito que en Farmatodo, en la ejecución del 6-nov. Reproducir: `indicadores(con)$ahorro_maximo`.
4. **En la Lubriderm humectación diaria de 120 ml, los tres comercios cobran casi lo mismo.** Éxito y La Rebaja $ 19.600, Farmatodo $ 19.650 en las dos ejecuciones. Reproducir: `serie_precio(con, <id del producto>)`.

## Limitaciones

- **Solo hay dos ejecuciones completas** (17-oct y 6-nov), así que las comparaciones en el tiempo son de un único intervalo.
- **Éxito: 67 anuncios en la ejecución del 17-oct frente a 77 en la del 6-nov.** Los 10 que faltan pueden indicar una categoría incompleta el 17-oct, así que sus cambios entre ejecuciones deben leerse con cuidado.
- **Precio por unidad con pocos datos:** en gramos, Éxito tiene 3 anuncios y La Rebaja 5, y hay valores extremos (por eso se usa la mediana y no el promedio).
- **La base no persiste en shinyapps.io (plan gratuito):** cualquier cambio hecho en la app publicada se pierde al reiniciarse. Para conservar datos nuevos hay que actualizar la base en local y volver a publicar.
- **Búsqueda de texto:** SQLite ignora mayúsculas solo en ASCII; "humectación" no encuentra "HUMECTACIÓN".
- **La canasta no incluye envío, mínimos de compra ni condiciones de las promociones.**
- **Actualización de datos desde la app:** [COMPLETAR según lo que quede implementado: botón de actualizar, modo sin conexión o ninguno].

## Declaración de uso de IA

Se usó **Claude (Anthropic)** como asistente durante el taller.

- **Qué hizo la IA:** ayuda en `db.R` (consultas parametrizadas, validación de entradas), las pruebas `testthat`, los scripts de verificación y README; explicó conceptos de Shiny y revisó el código de la interfaz.
- **Qué hace el autor:** escribír `global.R`, `ui.R` y `server.R` (filtros, indicadores, gráficos, tabla, cambios y canasta) a partir de ejemplos y esqueletos con huecos, correger los errores que aparecieron al ejecutar la app, y publicar la aplicación. 
- **Cómo se verificó:** las funciones de `db.R` se compararon con un cálculo independiente en R sobre las tablas base (`scripts/`), con las cifras ya verificadas de los datos (239 anuncios, 226 y 236 observaciones por ejecución, 6 cambios en los comparables), y con pruebas automáticas. La interfaz se revisó ejecutando la app.
