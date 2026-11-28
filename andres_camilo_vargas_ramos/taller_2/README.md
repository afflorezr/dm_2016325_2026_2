# Comparador de Precios - Salud Digestiva (Colombia)

Aplicacion web interactiva desarrollada en **R (Shiny + `bslib` + `highcharter`)** para comparar precios, precios por unidad normalizada y evolucion temporal de productos de salud digestiva (sueros de rehidratacion, sales, laxantes, antiacidos y productos para el mareo) en **Colsubsidio**, **Farmatodo** y **Cruz Verde**.

* **Aplicacion publicada:** https://h6cf08-camilo-vargas.shinyapps.io/comparador-salud-digestiva/
* **Lenguaje:** R (>= 4.3)

---

## 1. Estructura de archivos

```text
taller_2/
├── app.R                      # Interfaz bslib, graficos highcharter, ExtendedTask y logica reactiva
├── db.R                       # Capa de acceso a datos, consultas SQL parametrizadas y canasta
├── scraper.R                  # Modulo de web scraping reutilizado (Colsubsidio, Farmatodo, Cruz Verde)
├── validacion.R               # Migracion del esquema SQLite, vistas, indices y validacion pointblank
├── comparador_precios.sqlite  # Base de datos SQLite con historial de 4 ejecuciones
├── diccionario_datos.md       # Descripcion detallada de tablas, vistas y columnas
├── raw/                       # Copias crudas (.json.gz) de cada consulta por comercio y ejecucion
├── tests/
│   └── test_precios.R         # Suite de 7 pruebas automaticas con testthat
├── renv.lock                  # Dependencias con versiones fijas
└── README.md                  # Documentacion, hallazgos y declaracion de uso de IA
```

---

## 2. Ejecucion local y pruebas automaticas

### Requisitos previos
1. Clonar el repositorio y ubicarse en la carpeta `taller_2/`.
2. Restaurar las dependencias con versiones fijas desde R:
   ```r
   renv::restore()
   ```
3. Para el scraping en linea de Colsubsidio y Cruz Verde (renderizado dinamico), se requiere tener instalado **Google Chrome** o **Chromium** (utilizado por `chromote`).

### Ejecutar la aplicacion localmente
```r
shiny::runApp()
```

### Ejecutar las pruebas automaticas
Desde la carpeta `taller_2/`, ejecutar en terminal:
```bash
Rscript -e 'testthat::test_dir("tests")'
```
Todas las pruebas se ejecutan sobre bases SQLite temporales aisladas y validan conversion de precios, normalizacion de unidades, empates y ahorro en canasta, restriccion de unicidad, deteccion de cambios de precio, manejo de canastas incompletas y reglas de rechazo de `pointblank`.

### Nota sobre despliegue en la nube (`shinyapps.io`)
En entornos gratuitos como `shinyapps.io`, el servidor no dispone de navegador Chromium para renderizar sitios dinamicos (Colsubsidio/Cruz Verde) y los cambios en disco no persisten tras reiniciar el contenedor. Por ello, la aplicacion captura el error de red/navegador sin bloquearse e informa al usuario que puede utilizar el **Modo sin conexion (reprocesar `raw/`)** directamente desde el panel lateral. La recoleccion en linea funciona completamente en ejecucion local.

---

## 3. Vistas SQL y modelo de datos

El acceso a datos (`db.R`) opera mediante consultas SQL parametrizadas sobre cuatro vistas principales definidas en `validacion.R` (ver detalle completo en `diccionario_datos.md`):

* `v_ultimo_precio`: Devuelve la observacion valida (`descartada = 0`) mas reciente por cada par `(comercio, sku)`, enriquecida con `id_producto`, `contenido_total`, `unidad_norm` (`mL`, `g`, `unidad`) y `precio_unitario`.
* `v_comparables`: Filtra las observaciones vinculadas a las 12 presentaciones comparables estandarizadas (`P01`-`P12`) para comparar precios totales y precios por unidad sin mezclar unidades distintas.
* `v_cambios_precio`: Calcula mediante funciones de ventana (`LAG`) las variaciones absolutas (`cambio_cop`) y porcentuales (`cambio_pct`) entre ejecuciones consecutivas para un mismo anuncio y comercio.
* `v_no_observados`: Identifica anuncios presentes en ejecuciones anteriores pero ausentes en la ultima ejecucion de su comercio, diferenciandolos de los productos reportados explicitamente como `'agotado'`.

### Grafico de libre eleccion (Grafico 4)
El cuarto grafico (*Brecha de ahorro potencial (%) entre comercio mas caro y mas barato*) responde a la pregunta del consumidor: **¿en que productos comparables vale mas la pena comparar entre farmacias antes de comprar?** Ordena las 12 presentaciones por porcentaje de ahorro potencial (`100 * (Pmax - Pmin) / Pmax`) y colorea cada barra segun el comercio mas economico.

---

## 4. Hallazgos para el consumidor

Con base en las 4 ejecuciones registradas en `comparador_precios.sqlite` (desde `20261008T184604` hasta `20261113T113425`) se identifican tres conclusiones verificables en la aplicacion:

1. Dispersion significativa de precios en presentaciones identicas (hasta 18,5 % de diferencia): En la ultima ejecucion (`20261113T113425`), el mismo producto estandarizado presenta brechas importantes entre cadenas. Por ejemplo, *Dulcolax 5 mg x 10 grageas* (`P09`) registra un precio minimo de **$ 17.850 COP** en Farmatodo frente a **$ 21.902 COP** en Colsubsidio, generando un ahorro de **$ 4.052 COP (18,5 %)** por unidad sin cambiar de marca ni presentacion.
2. El ahorro por volumen no siempre favorece al empaque grande segun la farmacia:** Al normalizar por unidad (`COP / mL` y `COP / unidad` en el Grafico 2), se observa que *Electrolit 625 mL* (`P01`-`P03`) mantiene un costo por mililitro entre **$ 12,0 COP/mL** (Farmatodo) y **$ 13,8 COP/mL** (Colsubsidio), casi la mitad del costo por mL de presentaciones de 400 mL como *Hidraplus Zinc* (`P06`-`P07`, **$ 25,9 - $ 29,5 COP/mL**). Sin embargo, en laxantes (*Dulcolax*), la caja de 10 grageas en promocion en Farmatodo alcanza un precio por tableta competitivo frente a la caja de 20 grageas en cadenas sin descuento.
3. La compra dividida (canasta optima) supera a cualquier comercio unico, pero requiere verificar disponibilidad: Al armar una canasta mixta de sueros, laxantes y antiacidos (`P01`, `P04`, `P09`, `P12`) en la calculadora de canasta, ningun comercio lidera en todos los items simultaneamente. Comprar cada producto en el comercio mas economico reduce el gasto total frente a adquirir la canasta completa en la cadena mas costosa, sujeto a que cada tienda cuente con todos los items disponibles y considerando costos de envio.

---

## 5. Declaracion de uso de inteligencia artificial

* **Herramienta utilizada:** Gemini.
* **Partes del trabajo asistidas:** Estructuracion de la aplicacion Shiny con `bslib` y `highcharter`, implementacion del patron asincrono (`ExtendedTask` + `future_promise`).
* **Verificacion:** Todo el codigo generado fue ejecutado, depurado y verificado localmente sobre `comparador_precios.sqlite` y sobre bases temporales aisladas mediante `testthat::test_dir("tests")`, comprobando que cada indicador, grafico y calculo de canasta coincide con los datos crudos almacenados en `raw/`.
