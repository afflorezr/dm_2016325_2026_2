# Comparador de precios — Cuidado del bebé (Taller 2)

Aplicación **Shiny (R)** que consulta `comparador_precios.sqlite`, se actualiza
mediante web scraping de Farmatodo, Jumbo y Éxito, y orienta al consumidor
sobre dónde comprar más barato.

| | |
|---|---|
| Asignatura | Minería de Datos (2016325) — Taller 2 |
| Lenguaje | **R** (Shiny + bslib + highcharter + SQLite) |
| Categoría | Cuidado del bebé / higiene (jabón, champú, loción, aceite, crema hidratante, colonia infantil) |
| Comercios | Farmatodo, Jumbo, Éxito (Colombia) |
| Moneda | COP · Hora de los datos: America/Bogota (UTC-05:00) |

> **Enlace de la aplicación publicada:**
> **https://connect.posit.cloud/juan-sosa-10/content/01a1dcdf-17b3-6f25-fce7-249745e5396d**
> (enlace directo: https://01a1dcdf-17b3-6f25-fce7-249745e5396d.share.connect.posit.cloud/)
>
> (Posit Connect Cloud · cuenta `juan-sosa-10` · contenido
> `comparador-precios-bebe`)

---

## 1. Instalación y ejecución local

Guía completa para replicar y correr la aplicación en cualquier computador
a partir de la carpeta `taller_2/` (clonada del repositorio o descomprimida).

### 1.1. Requisitos

| Requisito | Detalle |
|---|---|
| **R ≥ 4.4** | Se probó con R 4.6.2 (el `renv.lock` fija `Matrix 1.7-6`, que requiere R ≥ 4.4). Descarga: https://cran.r-project.org |
| **Conexión a internet** | Solo para instalar dependencias (1ª vez) y para el scraping en línea |
| **Chrome o Chromium** | *Opcional*: solo necesario para “Actualizar precios” en modo **En línea**. El modo **Sin conexión** no lo necesita |

No se requiere RStudio (recomendado pero opcional). Se recomienda evitar
rutas con espacios para la carpeta del proyecto.

### 1.2. Instalar dependencias (solo la primera vez)

Abre **R** (o RStudio) con el *working directory* dentro de `taller_2/`
(el `.Rprofile` del proyecto activa **renv** automáticamente):

```r
renv::restore()
```

`renv::restore()` lee `renv.lock` e instala exactamente las versiones
registradas (128 paquetes: shiny, bslib, highcharter, rvest, chromote,
testthat, etc.) dentro de `renv/library/` del proyecto. Tarda unos minutos.

> **Nota:** si R no encuentra `renv` (p. ej. en Mac/Linux, donde la librería
> incluida es la de Windows), instálalo una vez con
> `install.packages("renv")` y vuelve a `renv::restore()`.

### 1.3. Correr la aplicación

```r
# Working directory = carpeta taller_2/
shiny::runApp(".")
```

En terminal, desde la raíz del proyecto:

```bash
Rscript -e "shiny::runApp('.')"
```

**Qué puede hacer la app:**

- **Filtros**: comercio, subcategoría, marca, precio, ejecución, fechas,
  solo promociones, solo comparables, búsqueda de texto.
- **Pestañas**: Resumen (indicadores + gráficos + tabla), Comparables
  (precio unitario y evolución), Cambios de precio (dos ejecuciones),
  Canasta (costo por comercio y compra mínima).
- **Actualizar precios**:
  - *En línea*: hace scraping real de Farmatodo/Jumbo/Éxito (requiere
    Chrome; puede tardar 10–20 min y los sitios pueden mostrar captcha — la
    app lo reporta y continúa con los demás).
  - *Sin conexión*: en el panel lateral elija “Sin conexión (reprocesa
    copias de raw/)” y pulse *Actualizar precios*; la app relee las copias
    crudas sin consultar los sitios (funciona sin Chrome ni internet).
- **Descargar CSV** de la tabla filtrada.

### 1.4. Verificar la base de datos

```r
source("db.R")
con <- abrir_conexion()

DBI::dbGetQuery(con, "SELECT comercio, COUNT(*) FROM observaciones GROUP BY 1")
DBI::dbGetQuery(con, "SELECT * FROM ejecuciones ORDER BY fecha_consulta")
DBI::dbGetQuery(con, "SELECT COUNT(*) FROM v_comparables")

cerrar_conexion(con)
```

También puede abrirse `comparador_precios.sqlite` con cualquier visor de
SQLite (DB Browser for SQLite, etc.). Estructura completa en
[`diccionario_datos.md`](diccionario_datos.md).

### 1.5. Solución de problemas

| Problema | Solución |
|---|---|
| `there is no package called 'shiny'` | Ejecuta `renv::restore()` con el working directory en la carpeta |
| `renv` pregunta de proyecto / activación | Acepta; o ejecuta `renv::activate()` una vez |
| La app abre pero los filtros no cargan | Revisa que `comparador_precios.sqlite` esté en la misma carpeta que `global.R` |
| “Actualizar precios” en línea falla | Normal desde algunas redes: los sitios bloquean. Usa **Sin conexión** (reprocesa `raw/`) |
| Falta Chrome para scraping en línea | Instala Google Chrome o usa solo el modo sin conexión |
| `testthat` no encuentra los archivos | Verifica que el working directory sea la carpeta `taller_2/` (donde está `tests/`) |

### 1.6. Flujo completo desde cero

```r
# 0) Una vez por maquina
install.packages("renv")

# 1) Dentro de taller_2/
renv::restore()                    # dependencias fijadas

# 2) Pruebas
testthat::test_dir("tests")        # 64/64

# 3) App local
shiny::runApp(".")

# 4) (Opcional) scraping en linea — requiere Chrome
source("scraper.R")
res <- ejecutar_scraper(modo = "online")
print(res$resumen)

# 5) (Opcional) modo sin conexion — no requiere internet ni Chrome
source("scraper.R")
res <- ejecutar_scraper(modo = "offline")
print(res$resumen)
```

---

## 2. Cómo correr las pruebas

```bash
# desde la raíz del proyecto (taller_2/)
Rscript -e "testthat::test_dir('tests')"
```

(o, dentro de R con el working directory en `taller_2/`:
`testthat::test_dir("tests")`). Salida esperada:

```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 64 ]
```

Son 17 pruebas `testthat` (actualmente 64 aserciones) que cubren: conversión
de precios, normalización de unidades, ahorro máximo entre comercios (con
empates), no-duplicado al reinsertar una ejecución, detección de cambios de
precio, canasta en SQL (por comercio, mínima y detalle, incluido el caso
incompleto) y reglas de validación. Usan datos pequeños o una base
**temporal**, nunca la base de la entrega ni los sitios.

---

## 3. Estructura de archivos

```
taller_2/
├── ui.R / server.R / global.R         # aplicación Shiny (bslib)
├── db.R                                 # capa de acceso: TODO el SQL (Modulo 3)
├── scraper.R                            # extracción: 1 función por comercio + general
├── validacion.R                         # reglas pointblank/por fila (Modulo 1)
├── comparador_precios.sqlite            # base SQLite (observaciones, ejecuciones, correcciones…)
├── diccionario_datos.md                 # tablas, vistas y columnas
├── www/custom.css                       # estilos de la interfaz
├── raw/                                 # copias crudas HTML por comercio y fecha
│   ├── farmatodo/2026-11-10/ 2026-11-12/*.html
│   ├── jumbo/2026-11-10/ 2026-11-12/*.html
│   └── exito/2026-11-10/ 2026-11-12/*.html
├── tests/
│   ├── helper-fixtures.R               # datos pequeños y base temporal
│   ├── test-precios.R
│   ├── test-validacion.R
│   └── test-base.R
├── renv.lock  .Rprofile  renv/          # dependencias con versiones fijas
├── rsconnect/                           # metadatos del despliegue (sin credenciales)
├── .gitignore                           # ignora .Renviron, renv/ local, etc.
└── README.md                            # este archivo (incluye el manual de instalación)
```

Reglas de organización: la interfaz no contiene SQL (todo está en `db.R`), la
extracción está separada (`scraper.R`), la validación también (`validacion.R`)
y ningún archivo concentra toda la aplicación.

**Reproducibilidad:**

- **Rutas relativas** en todo el código (sin `setwd()` ni rutas absolutas).
- **Dependencias con versiones fijas** en `renv.lock`.
- **Datos rastreables**: cada observación se vincula a una copia cruda en
  `raw/` y a una fila de `ejecuciones`.
- **Modo sin conexión** que verifica la extracción sin consultar los sitios
  (protege el trabajo ante cambios o bloqueos futuros).
- **64 aserciones automatizadas** ejecutables con un solo comando.

---

## 4. Cómo funciona la actualización (Módulo 2)

1. El botón **Actualizar precios** lanza `ejecutar_scraper()` de `scraper.R`
   como `ExtendedTask` en segundo plano (**no bloquea** la app).
2. Cada comercio se procesa en su propia transacción: si uno falla (captcha,
   red, cambio de estructura) los demás continúan y la fila queda como
   `fallida`/`parcial` con el motivo visible en el resumen.
3. Se valida cada fila (`validacion.R`); lo rechazado se registra en
   `observaciones_rechazadas` y **no** entra a `observaciones`.
4. Los resultados se agregan **sin sobrescribir** observaciones anteriores
   (unicidad `comercio + url + fecha_consulta`).
5. Al terminar se recalcula `comparable`/`id_comun` y se invalida la caché de
   indicadores, gráficos y tablas.
6. Modo **sin conexión**: reprocesa las copias de `raw/` sin salir de la app.

---

## 5. Consultas y vistas SQL

La aplicación usa directamente tres vistas (definidas en `scraper.R`,
documentadas en `diccionario_datos.md`):

| Vista | Uso en la app |
|---|---|
| `v_ultimo_precio` | Filtros, indicadores, tabla y distribución de precios (última observación por anuncio) |
| `v_cambios_precio` | Indicador de subidas/bajas entre ejecuciones consecutivas |
| `v_comparables` | Precio unitario, evolución, brecha y canasta |

Todos los filtros y agregados se calculan en SQL con **parámetros `?`**
(nunca concatenando valores del usuario). La conexión se abre una vez por
sesión y se cierra al finalizar (`abrir_conexion` / `cerrar_conexion`).

**Indicadores (≥6, con unidad y período):** observaciones y anuncios por
comercio; comparables (productos × comercios); % de anuncios en promoción;
ahorros máximo (COP y %); cambios de precio (subidas/bajas/total); fecha y
estado de la última ejecución; mediana del precio por subcategoría.

**Gráficos (4, interactivos con highcharter):**
1. evolución del precio de un comparable elegido (una serie por comercio);
2. precio por unidad de contenido entre comercios (sin mezclar mL/g/unidades);
3. distribución de precios de la categoría por comercio (boxplot);
4. *libre*: mayor brecha de precio entre comercios del mismo producto —
   responde **¿qué producto tiene la diferencia más grande entre el más caro y
   el más barato?** (justificación: es la pregunta de ahorro más directa para
   quien compra una presentación concreta).

**Tabla:** productos filtrados con comercio, nombre, marca, presentación,
precio, precio unitario, promoción, disponibilidad, fecha y enlace; ordenable,
buscable y descargable en CSV.

---

## 6. Correspondencia de los comparables (Taller 1, §2.4)

Reglas documentadas en `productos_comparables()` (`scraper.R`) y en
`diccionario_datos.md`: misma marca canónica + subcategoría + contenido +
unidad, similitud de nombres ≥ 0,25 y **variante compatible** (los tokens de
variante —original, manzanilla, avena, antes de dormir…— deben intersectar).
Se exige presencia en los **3 comercios**; `id_comun` es estable entre
ejecuciones (ej. `johnson-champu-400-ml-manzanilla`).

---

## 7. Hallazgos para el consumidor

_Período: ejecuciones `ejec_20261110T095913` (10-11-2026) y
`ejec_20261112T101944` (12-11-2026); 31 productos comparables presentes en
los 3 comercios. Verificable en las pestañas **Comparables** y **Resumen**._

1. **Farmatodo es el más barato en la mayoría de las presentaciones
   comparables** (26 de 31 productos comparables; Éxito 5; Jumbo 0). En la
   pestaña Comparables, con el filtro “solo comparables”, Farmatodo lidera
   casi todas las filas de precio. *No implica que sea más barato en todo:
   la comparación es por presentación idéntica.*

2. **Las brechas de precio entre comercios llegan al ~28 %** en productos
   puntuales: la crema hidratante Johnson's 800 mL varió $16.040 (28,3 %) y
   el aceite 300 mL $11.472 (24,2 %) entre el más caro y el más barato
   (gráfico “Mayores brechas de precio”, Resumen). Elegir bien el comercio
   ahorra hasta casi un tercio del precio en esas presentaciones.

3. **El precio absoluto no siempre indica la mejor compra por unidad**: en
   la crema hidratante 800 mL, Éxito ($40.650) fue más barata en precio de
   escaparate que Farmatodo ($46.198) y que Jumbo ($56.690), invirtiendo el
   patrón de las presentaciones chicas (pestaña Comparables → “Precio por
   unidad”). Para tamaños grandes conviene mirar siempre el COP/mL, no solo
   el ticket.

4. **La mediana de precios favorece a Éxito ($27.900) y Jumbo ($27.950)
   frente a Farmatodo ($30.788)**, pero Farmatodo marca promociones en el
   87,8 % de sus anuncios frente al 0 % de Jumbo y 15,8 % de Éxito: el
   ahorro real depende de los descuentos del día, no del precio de lista
   (indicadores de Resumen; última observación de cada anuncio).

---

## 8. Módulo de extracción (Taller 1)

- **Páginas consultadas:** búsquedas por término de la categoría en cada
  comercio (10 términos: jabón/champú/loción/aceite/crema/colonia de bebé,
  Johnson's, Mustela, jabón líquido, shampoo bebé), recorriendo la paginación
  de Jumbo y Éxito (3 páginas por término) y el desplazamiento de Farmatodo.
  *Equivalencia categoría↔sitio:* cada término se filtró además con las
  reglas `RX_BEBE`/`RX_SUBCAT`/`RX_EXCLUIR` (excluye pañales, protector solar,
  kits, detergente, etc., según la delimitación de la planilla).
- **Librerías:** `rvest`/`xml2` sobre HTML renderizado con `chromote`
  (Chrome real, porque las tiendas cargan producto con JavaScript); pausas de
  3–6 s entre peticiones, agente de usuario identificable y límite de
  páginas por ejecución (buenas prácticas de scraping).
- **Selectores:** Farmatodo `app-product-card-handler`; Jumbo
  `h3[class*='ProductCardstyles']`; Éxito `div[class*='productCard_contentInfo']`
  (VTEX). Cada respuesta se guarda en `raw/<comercio>/<fecha>/` y el modo
  sin conexión la reprocesa.
- **Cobertura:** los conteos por comercio se registran en la tabla
  `ejecuciones` (`tarjetas_leidas`, `recolectados`, `insertados`,
  `rechazados`) y se pueden comparar con los listados de cada sitio.

---

## 9. Despliegue (Módulo 8)

**Plataforma utilizada: Posit Connect Cloud** (aceptada en el enunciado:
“Shiny: shinyapps.io o Posit Connect Cloud”).

- **Enlace publicado:** https://connect.posit.cloud/juan-sosa-10/content/01a1dcdf-17b3-6f25-fce7-249745e5396d
- **Cuenta:** `juan-sosa-10` (connect.posit.cloud)
- **Nombre del contenido:** `comparador-precios-bebe`

### Reproducir el despliegue

1. Autenticar la cuenta (abre el navegador con un código a confirmar):

   ```r
   install.packages("rsconnect")
   rsconnect::connectCloudUser()   # confirma el codigo en el navegador
   ```

2. Publicar / actualizar:

   ```r
   rsconnect::deployApp(
     appDir  = ".",
     appName = "comparador-precios-bebe",
     account = "juan-sosa-10",
     server  = "connect.posit.cloud"
   )
   ```

**Credenciales:** el token OAuth queda en el perfil del usuario
(`~/.config/rsconnect`), **fuera del repositorio**; nada de secretos en el
código (`.gitignore` incluye `.Renviron`). Si se filtrara una credencial,
revocarla en la plataforma (borrar el archivo no basta: queda en Git).

**Notas de producción:**
- Los comercios suelen bloquear el scraping desde servidores; si el botón
  “Actualizar precios” falla en línea, la app lo informa y permite el **modo
  sin conexión** con las copias de `raw/`.
- Las plataformas gratuitas **no conservan cambios** en la base al
  reiniciarse; la app funciona con la base incluida en el despliegue y la
  actualización en línea aplica en la ejecución local.

---

## 10. Correcciones sobre el Taller 1 (Módulo 1)

Todas quedan registradas en la tabla `correcciones` (fecha, registro, campo,
valor anterior, valor nuevo, motivo); no se borraron observaciones:

1. Migración de esquema: +`texto_original`, `precio_antes`, `sku`,
   `disponibilidad`, `comparable`, `id_comun`; unicidad pasó de
   `comercio+producto+fecha` a `comercio+url+fecha`.
2. ~88 filas de Éxito tenían el precio unitario (“(Ml a $ 53,16)”) en el
   campo `marca`; se derivó la marca del nombre del anuncio.
3. 4 productos de limpieza (detergente/ropa) estaban clasificados como
   “Colonia” por la regla “fragancia”; se marcaron fuera de categoría
   (`subcategoria = NULL`).
4. `texto_original` de las filas previas se rellena con `producto` (las copias
   crudas de esa ejecución no guardaban descripción adicional).

### 10.1. Ejecución del Taller 1 y cambio de comercio (Cruz Verde → Jumbo)

**La base entregada no contiene la ejecución original del Taller 1.** Se
reemplazó, como permite el enunciado (§3.3: “Si la ejecución del Taller 1 no
es válida, se reemplaza por otra nueva, también en una fecha distinta”).

En el Taller 1 los comercios eran **Farmatodo, Cruz Verde y Éxito**. Las
ejecuciones del 09-11-2026 en esa base mostraron que **Cruz Verde dejó de
permitir la extracción**:

| Ejecución | Farmatodo | Cruz Verde | Éxito |
|---|---|---|---|
| `ejec_20261109T163535` | parcial · 64 | **fallida · 0** | parcial · 100 |
| `ejec_20261109T170649` | parcial · 96 | parcial · 12 | parcial · 100 |
| `ejec_20261109T235237` | parcial · 96 | parcial · 12 | parcial · 100 |

_(estado · productos recolectados, tomados de la tabla `ejecuciones` de la
base del Taller 1)._ En Cruz Verde casi todos los términos de búsqueda
devolvían “0 tarjetas de producto: posible cambio de estructura o contenido
no renderizado”. Con 12 productos no era posible garantizar los **ocho
productos comparables en los tres comercios**, por lo que esas ejecuciones
no eran válidas para el Taller 2.

Por eso, según el §2 del enunciado (“Si un comercio dejó de permitir la
extracción, puede reemplazarse por otro, documentando el cambio y
garantizando de nuevo los ocho productos comparables en los tres
comercios”):

- **Cruz Verde se reemplazó por Jumbo** (`scraper.R`, función de Jumbo,
  selector `h3[class*='ProductCardstyles']`). Se mantuvieron la categoría,
  los términos de búsqueda, Farmatodo y Éxito.
- Se recolectó de nuevo en los tres comercios. Las ejecuciones válidas de la
  base son `ejec_20261110T095913` (10-11-2026, reemplaza a la del Taller 1)
  y `ejec_20261112T101944` (12-11-2026, nueva del Taller 2): fechas
  distintas y ≥ 8 comparables en los tres comercios en ambas.
- Las copias crudas de cada ejecución están en `raw/farmatodo/`,
  `raw/jumbo/` y `raw/exito/`.

---

## 11. Declaración de uso de inteligencia artificial


Se utilizó además **Claude Code (Anthropic, modelo Claude Opus 5.5)** para:

- **Despliegue:** diagnosticar por qué el enlace mostraba una versión vieja
  (la publicación se hacía en otra cuenta), corregir el error de
  `rsconnect::deployApp()` al leer `renv.lock` (se debe ejecutar con renv
  activo) y volver a publicar en Posit Connect Cloud.
- **Capa de datos:** mover a `db.R` las consultas SQL que estaban escritas en
  `server.R` y `global.R` (`lista_comparables`, `rango_fechas_observadas`,
  `precio_maximo_observado`, `contar_comparables`,
  `contar_observaciones_comparables`), para que la interfaz no contenga SQL.
- **Creacion de las pruebas:** Correr pruebas para cumplir con los requisitos
- **Estructura del proyecto:** Organizacion las carpetas y la aplicacion.  

