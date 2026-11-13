# Taller 2 — Comparador de precios: Afeitado y depilación (aplicación Streamlit)

**Asignatura:** Minería de Datos (2016325) · Universidad Nacional de Colombia
**Estudiante:** Inti Abraham Olaya Quinchia
**Lenguaje:** Python (scraping, acceso a datos, aplicación y pruebas). Aplicación en **Streamlit**.

## Aplicación publicada

**Enlace:** PENDIENTE — pegar aquí la URL de Streamlit Community Cloud una vez desplegada.

Notas de la versión publicada:
- Las plataformas gratuitas **no conservan los cambios en la base** al reiniciarse la aplicación: lo que se actualice desde el botón se pierde al reiniciar. La actualización persistente funciona en la ejecución local.
- Los comercios suelen bloquear las IP de estas plataformas (Éxito ya respondió `HTTP 403` desde un computador personal). Si el servidor no puede hacer scraping, la aplicación lo informa por comercio como «fallida», con el motivo, y se puede usar el **modo sin conexión**, que reprocesa las copias de `raw/`.
- No hay credenciales en el repositorio ni en el código; la aplicación no las necesita.

## Ejecución local

```bash
pip install -r requirements.txt
streamlit run app.py
```

- **Actualizar precios (en línea):** botón «Actualizar precios» de la barra lateral. Llama a las funciones de `scraper.py`, valida con `pandera`, inserta cada comercio dentro de una transacción y muestra un resumen por comercio.
- **Sin conexión:** activar «Modo sin conexión (usa raw/)» antes de pulsar el botón; reprocesa la copia cruda más reciente de `raw/`.
- Por línea de comandos: `python scraper.py` (todos los candidatos), `python scraper.py --comercios "Jumbo" "Locatel" "Carulla"` o `python scraper.py --modo offline`.
- `python migrar_db.py comparador_precios.sqlite` aplica el esquema del Taller 2 a una base del Taller 1 (idempotente). La base entregada ya está migrada.

## Pruebas automáticas

Desde `taller_2/`:

```bash
pytest tests/
```

Seis pruebas (`tests/test_app.py`) con una base SQLite en memoria y datos simulados: conversión de precios, normalización de unidades, ahorro con empates, unicidad al insertar, detección de cambios y canasta incompleta.

## Estructura

```text
taller_2/
├── app.py                    # punto de entrada: st.navigation + botón de actualización
├── paginas/
│   ├── resumen.py            # filtros, 6 indicadores, 4 gráficos (plotly), tabla y CSV
│   ├── cambios.py            # comparación de dos ejecuciones
│   └── canasta.py            # costo por comercio y canasta ideal
├── db.py                     # capa de acceso a datos (SQL parametrizado, st.cache_data)
├── actualizacion.py          # scraping -> validación -> inserción transaccional
├── scraper.py                # módulo de extracción del Taller 1 (VTEX, sin navegador)
├── validacion.py             # reglas pandera y registro de rechazadas
├── analisis.py               # cálculos de canasta y ahorro (sin SQL ni Streamlit)
├── migrar_db.py              # migración del esquema (correcciones, vistas, índices)
├── comparador_precios.sqlite # base con 2 ejecuciones completas (24-oct y 13-nov-2026)
├── diccionario_datos.md      # tablas, vistas y columnas
├── raw/<comercio>/<fecha>/   # copias crudas (.json.gz) + meta.json.gz
├── tests/test_app.py
└── requirements.txt
```

## Comercios y cambios respecto al Taller 1

En el Taller 1 el análisis usó **Jumbo, Locatel y Éxito**. En la ejecución del 13 de noviembre de 2026 **Éxito bloqueó la extracción** (`HTTP 403` en el árbol de categorías), por lo que se **reemplazó por Carulla**, también del Grupo Éxito, con catálogo casi idéntico. Se garantizó de nuevo la cobertura: la base marca 41 productos comparables con observación en los tres comercios en ambas ejecuciones. Carulla salió **parcial** (2.596 de 3.026 productos en «Afeitadoras»), igual que en el Taller 1; el sitio no devolvió el resto aun dividiendo la consulta por rangos de precio (VTEX no pagina más de 2.500 resultados por consulta). El alcance queda registrado en la tabla `ejecuciones` (`detalle`).

## Vistas SQL

La aplicación consulta directamente tres vistas (además de `v_obs` del Taller 1):

- `v_ultimo_precio`: última observación de cada anuncio, con precio unitario, disponibilidad (`disponible`, `agotado` o `no observado`: no apareció en la última ejecución de su comercio; no significa agotado ni retirado) y bandera `comparable`.
- `v_cambios_precio`: variación en COP y % entre observaciones consecutivas del mismo anuncio en el mismo comercio.
- `v_comparables`: observaciones de los productos comparables en los comercios del análisis, con precio unitario, mínimo y máximo por ejecución y `es_precio_minimo` (también marca los empates).

## Gráficos

1. Evolución del precio de un producto comparable (una línea por comercio).
2. Precio por unidad de contenido (barras; mL, g y unidad se eligen por separado y nunca se mezclan).
3. Distribución de precios por comercio (boxplot).
4. **Libre elección — proporción de productos con y sin promoción (dona).** Responde: *¿puedo confiar en que el precio que veo es el habitual?* Un comercio con muchos productos en promoción muestra precios que pueden ser temporales; esto matiza cualquier conclusión sobre «dónde es más barato».

## Hallazgos

Base: 36 productos comparables con contenido consistente en los tres comercios (Locatel, Jumbo y Carulla). Se excluyen cinco que la base marca como comparables pero cuyo contenido o unidad difiere entre comercios (por ejemplo, espuma Gillette Sensitive: 150 g en dos comercios y 155 mL en Jumbo). Ejecuciones: `run-20261113T174237` (13-nov-2026) y `run-20261024T221730` (24-oct-2026). Precios en COP al momento de la captura.

1. **Ninguno es el más barato en todas las fechas.** El 13 de noviembre, Locatel tuvo el menor precio en 26 de los 36 productos (Carulla en 9 y Jumbo en 3, contando empates); el 24 de octubre el orden fue otro: Jumbo en 17, Locatel en 14 y Carulla en 4. Comprar los 36 productos solo en Locatel costaba $1.117.033 el 13-nov, frente a $1.274.045 en Carulla y $1.338.210 en Jumbo; el 24-oct (35 productos con precio en los tres) Jumbo era el más barato con $1.257.450, frente a $1.330.100 en Locatel y $1.381.190 en Carulla.
2. **La ventaja de Locatel coincide con sus promociones.** El 13-nov, 28 de los 36 productos estaban en promoción en Locatel, frente a 4 en Carulla y 0 en Jumbo. Entre ambas ejecuciones, 28 de los 36 precios de Locatel bajaron (−22,4 % en promedio), mientras en Jumbo 12 subieron (+22 % en promedio) y 7 bajaron. Son precios de la captura, no permanentes.
3. **Elegir bien un producto ahorra mucho; armar la canasta ahorra poco.** En el 13-nov, el ahorro mediano de comprar cada producto en el comercio más barato frente al más caro fue 23,4 % ($7.588). Casos extremos: Gillette Prestobarba Sense Care x2 entre $15.150 (Locatel) y $23.850 (36,5 %), y repuestos Venus Breeze x2 entre $25.970 (Carulla) y $39.590 (34,4 %). En cambio, la canasta ideal (cada producto donde es más barato) cuesta $1.075.222, solo $41.811 (3,7 %) menos que comprar todo en Locatel. Estas cifras no incluyen envío, mínimos de compra ni condiciones de las promociones.

## Limitaciones de los datos

- 11.794 de 15.064 observaciones no tienen precio (producto agotado según el sitio); se guardan como ausentes, nunca como 0.
- 7.964 de 9.789 anuncios no tienen contenido identificable en el título, por lo que no entran al precio por unidad.
- En Carulla, un mismo producto (EAN 7702018330126) aparece con dos anuncios (uno de vendedor externo): se conserva el repetido y la canasta usa el más barato.
- Hubo corridas intermedias el 13-nov (17:24 y 17:38) con solo algunos comercios; la ejecución completa es `run-20261113T174237`.

## Declaración de uso de IA

Se usó **Claude (Anthropic)** como asistente de programación para: la migración del esquema (`migrar_db.py`), la validación con pandera (`validacion.py`), la capa de datos (`db.py`), la lógica de actualización (`actualizacion.py`), las páginas de Streamlit, los cálculos de `analisis.py`, las pruebas con pytest y el borrador de este README y del diccionario de datos. El módulo de extracción (`scraper.py`) es del Taller 1.

Verificación: las seis pruebas automáticas, pruebas de la interfaz con una base de ejemplo, ejecución del scraper en línea en mi computador (13-nov-2026), consultas SQL sobre la base real para comprobar las cifras de este documento y revisión de los resultados contra los enunciados del Taller 1 y 2. Soy responsable de todo el código entregado y puedo explicarlo.
