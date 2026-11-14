# Observatorio de precios de medicamentos dermatológicos — Taller 2

**Minería de Datos 2016325 · Universidad Nacional de Colombia**

## Aplicación publicada

**URL pública:** [Abrir el observatorio](https://6mqo1q-sebastian0orlando-olarte0rincon.shinyapps.io/observatorio-precios-dermatologicos/)

> Despliegue realizado en shinyapps.io. La disponibilidad y las funciones deben comprobarse en producción.

## Objetivo y procedencia

Se comparan precios obtenidos por el scraper R del Taller 1, para tres comercios: **Cruz Verde, Droguerías Cafam y La Rebaja**. Las observaciones proceden exclusivamente de capturas HTML/JSON conservadas en `raw/`, vinculadas con `ejecuciones` y `observaciones` en `comparador_precios.sqlite`. No se imputan precios ni se interpretan ausencias como agotamiento.

Se reutilizan **8 presentaciones homologadas** entre las tres droguerías, en dos capturas de fechas diferentes: **10 de octubre** y **13 de noviembre de 2026**. En la base examinada durante el desarrollo había **5.621 observaciones**, 24 comparables vigentes y 27 rechazos documentados. Verificar los conteos de la versión definitiva usando `verificar_entrega.R`.

## Puesta en marcha (RStudio)

1. Abrir la carpeta `taller_2` como directorio de trabajo (sin llamar a `setwd()` dentro del código entregado).
2. Tener instalados R y los paquetes según `renv.lock`. Para restaurar paquetes: `install.packages('renv')` y `renv::restore(prompt = FALSE)`.
3. Si faltan paquetes usados por el Taller 2, ejecutar `source('actualizar_dependencias.R')` y revisar el `renv.lock` actualizado antes del despliegue.
4. Arrancar: `shiny::runApp('.', launch.browser = TRUE)`.
5. Para ejecutar las **pruebas automatizadas sin visitar sitios ni modificar SQLite**: `source('ejecutar_pruebas.R', encoding = 'UTF-8')`.
6. Para comprobar la estructura antes de entregar: `source('verificar_entrega.R', encoding = 'UTF-8')`.

La aplicación muestra Panorama, Análisis, Cambios de precio, Catálogo, Canasta de compras y Actualización. Los filtros generales se procesan mediante consultas SQL parametrizadas; la búsqueda del catálogo y la exportación CSV comparten esos filtros. El CSV utiliza coma y UTF-8; para abrirlo correctamente en Excel en español, importar desde **Datos → Desde texto/CSV** con delimitador coma y codificación UTF-8.

### Capturas y actualización

El botón **Actualización** ofrece dos modos separados:

- **En línea:** reutiliza funciones de `scraper.R` y la validación de `validacion.R`; guarda nuevas copias RAW e inserta registros válidos en transacciones por comercio. Si falla un sitio, la aplicación debe informar la incidencia y continuar con los restantes.
- **Sin conexión:** reproduce las capturas originales de `raw/` y muestra un resumen **sin** crear una ejecución nueva ni cambiar SQLite.

La tarea Shiny utiliza `ExtendedTask` y `future_promise` para no bloquear la interfaz. Se invalidan los valores de la caché al terminar una captura en línea.

### Comparación de ejecuciones

La pestaña «Cambios de precio» permite elegir dos ejecuciones reales y un umbral porcentual. Compara el **mismo ID de anuncio dentro del mismo comercio** y distingue **Aumento**, **Disminución**, **Sin cambio**, **Nuevo**, **No observado** y **Sin precio válido**. Un anuncio no observado no significa que esté agotado. Las diferencias monetarias y porcentuales se calculan exclusivamente cuando existen precios válidos en ambas ejecuciones.

### Canasta de compras

Elegir una ejecución, varios productos homologados y cantidad entera de envases. La canasta total por tienda solo se muestra cuando **todos los productos están presentes** en esa ejecución; una ausencia genera estado **Incompleta**, sin total ficticio. La recomendación mixta elige el menor precio por producto, informa empates y compara su costo con la mejor tienda completa. No contempla envíos, mínimos, promociones condicionadas ni disponibilidad garantizada.

## Hallazgos verificables para el consumidor

Estos hallazgos se basan en las capturas conservadas, no en precios actuales del sitio.

1. **Captura del 10/10/2026:** una canasta con un Clotrimazol AG/Lafrancol crema 40 g (P06) y un Caladryl loción 100 ml (P08) cuesta **$29.080 COP** comprando el primero en Cafam ($11.080) y el segundo en La Rebaja ($18.000). La mejor tienda completa es La Rebaja ($31.300); el ahorro de dividir compras es **$2.220 COP, 7,09 %**. Se reproduce en «Canasta de compras».
2. **Captura del 13/11/2026:** Cruz Verde tuvo el menor precio de las **8 presentaciones comparables** (P01–P08), entre los tres comercios observados. Por tanto, para cualquier canasta formada por estas ocho presentaciones y cantidades positivas, la compra mixta no mejora el costo de Cruz Verde en esa captura. Se comprueba en `v_comparables` y «Canasta».
3. **Diferencias entre fechas:** el menor precio de P01 en Cruz Verde fue $18.657 COP en la captura del 10/10 y $15.224 COP en la del 13/11. La diferencia de esos **mínimos por producto y comercio** es de **−$3.433 COP** (aproximadamente −18,4 %). Para afirmar variaciones del **mismo anuncio**, usar la pestaña «Cambios de precio», que empareja los identificadores individuales.

## Estructura de archivos y vistas

- `app.R`: interfaz Shiny, gráficos, indicadores y pestañas.
- `db.R`: acceso SQLite, filtros parametrizados, KPI, catálogo y agregaciones.
- `scraper.R`: extracción y normalización del Taller 1; respetar el archivo original.
- `validacion.R`: conversión de precio y reglas de calidad previas a la inserción.
- `actualizacion_t2.R`, `previsualizacion_t2.R`, `paso23_disponibilidad_t2.R`: actualización/ausencias y modo sin conexión.
- `canasta.R`: cálculo por comercio, ahorro, faltantes y empates.
- `comparacion_ejecuciones.R`: comparación entre dos ejecuciones elegidas.
- `comparador_precios.sqlite`: base histórica real; **no es un archivo de ejemplo**.
- `raw/`: respuestas y evidencias crudas del scraping.
- `diccionario_datos.md`: tipos, campos, tablas y vistas.
- `tests/testthat/test_taller2.R`: pruebas con SQLite **en memoria**, sin consultar comercios.
- `renv.lock`: dependencias fijadas; revisar que cubra los paquetes realmente usados por esta versión.

Las vistas SQL principales son `v_ultimo_precio` (última observación válida por anuncio y comercio), `v_cambios_precio` (precios válidos observados en ejecuciones sucesivas) y `v_comparables` (ocho productos homologados y precio normalizado por g/mL/unidad). Las tablas de rechazos y correcciones conservan la trazabilidad de incidentes.

### Seguridad y límites

- Tokens de despliegue exclusivamente en `.Renviron` local (excluido mediante `.gitignore`) o en los ajustes de la plataforma. **Nunca** poner `rsconnect::setAccountInfo()` en código compartido.
- Los filtros usan marcadores SQL `?` y límites de longitud/valores; no concatenan texto del usuario.
- El scraping respeta pausas y límites de solicitudes. Verificar política de acceso y agente de usuario identificable en la versión final del scraper.
- En las plataformas gratuitas puede perderse lo escrito en SQLite al reiniciar la aplicación; **las actualizaciones en línea se verifican localmente** y se ofrece modo sin conexión en producción.

## Publicar y entregar

1. Instalar `rsconnect` si es necesario y ejecutar en consola su configuración de cuenta conforme a la documentación de shinyapps.io. Las credenciales **no** van en archivos del proyecto.
2. Ejecutar `rsconnect::deployApp(appDir='.', appName='observatorio-precios-dermatologicos', forceUpdate=TRUE)` desde `taller_2`, después de verificar los archivos e identificar dependencias. Revisar que se desplieguen `raw/`, SQLite y las funciones requeridas (sin incluir `backups/`, `.Renviron` ni bibliotecas locales).
3. Abrir la URL resultante y probar las seis pestañas, los filtros, la comparación, la canasta y el modo offline.
4. Sustituir la URL de marcador en este README por el enlace real que funcione.
5. Confirmar que `git status` no incluye credenciales, respaldos, archivos personales ni versiones del Taller 1; agregar únicamente `taller_2/`, hacer commit y crear Pull Request hacia el repositorio del curso desde tu rama. El PR no modifica archivos ajenos.
6. La plataforma debe seguir funcionando durante la semana siguiente a la entrega.

## Declaración de uso de inteligencia artificial

Se utilizó ChatGPT para asistir en el desarrollo de módulos Shiny, consultas SQL, visualizaciones, validación, diseño de canasta, comparación histórica y documentación. Las extracciones proceden del scraper ejecutado sobre los comercios y sus copias RAW, no de IA. El autor verificó los datos frente a SQLite y las capturas, ejecutó pruebas locales y revisó los cambios antes de entregar. **Actualizar esta declaración según las verificaciones realmente realizadas y los resultados de los tests**.
