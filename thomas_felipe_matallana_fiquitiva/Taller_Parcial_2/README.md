# Comparador de Precios — Higiene Corporal (Taller 2)

**Autor:** Thomas Felipe Matallana Fiquitiva  
**Asignatura:** Minería de Datos (2016325) — Universidad Nacional de Colombia  
**Lenguaje del proceso:** Python 3 (recolección, base de datos SQLite, validación, pruebas y aplicación en Streamlit)  
**Enlace a la aplicación desplegada:** [https://comparador-higiene-tmatallana.streamlit.app](https://comparador-higiene-tmatallana.streamlit.app) *(Reemplazar por URL final de Streamlit Community Cloud)*

---

## 1. Alcance y categoría analizada

Esta aplicación web extiende el trabajo desarrollado en el Taller 1 sobre la categoría de **Higiene corporal** (jabones de tocador en barra, geles de ducha, desodorantes, antitranspirantes y talcos corporales; excluyendo higiene íntima e infantil) en tres comercios con operación en línea en Colombia: **Colsubsidio** (`drogueriascolsubsidio.com`), **Cafam** (`drogueriascafam.com.co`) y **La Rebaja** (`larebajavirtual.com`).

El sistema reutiliza la de recolección del Taller 1, almacena el historial longitudinal en `comparador_precios.sqlite` sin sobrescribir capturas previas y evalúa 8 productos comparables con correspondencia exacta de código EAN, marca, variante y contenido neto en los tres comercios (24 correspondencias por ejecución completa):

1. `yodora_clasico_25`: Yodora Clásico crema (1 tubo de 25 g — EAN `7702057080075`)
2. `dove_original_270`: Dove Original blanco (Tripack 3 barras de 90 g = 270 g — EAN `7891150046481`)
3. `protex_men_330`: Protex Men Sport (Tripack 3 barras de 110 g = 330 g — EAN `7509546667201`)
4. `protex_herbal_330`: Protex Herbal (Tripack 3 barras de 110 g = 330 g — EAN `7702010920660`)
5. `protex_avena_330`: Protex Avena (Tripack 3 barras de 110 g = 330 g — EAN `7702010920615`)
6. `rexona_sport_48`: Rexona Clinical Sport Strength Men (Crema 48 g — EAN `79400300546`)
7. `rexona_women_48`: Rexona Clinical Women Classic (Crema 48 g — EAN `79400052926`)
8. `rexona_men_48`: Rexona Clinical Men (Crema 48 g — EAN `79400052919`)

---

## 2. Correcciones del Taller 1 e historial de capturas

Sin modificar la carpeta original del Taller 1, migré las cuatro ejecuciones históricas del **10 de octubre de 2026** (`20261010T112641_53bf109b`, `20261010T112803_180f96c4`, `20261010T163617_be11ac26` y `20261010T163830_6e2b2b52`) y ejecuté nuevas recolecciones completas en noviembre de 2026 (incluyendo `20261105T181309_52c1039a`, `20261105T222711_2b4be8e5` y `20261109T184812_bf932294`).

* **Trazabilidad de correcciones (`correcciones`):** Identifiqué 40 observaciones históricas del Taller 1 que carecían de precio publicado en el JSON original. Siguiendo las reglas del taller, no borré los registros ni imputé precios artificiales: marqué `descartada = 1` en `observaciones` y documenté los 40 cambios en la tabla `correcciones` con fecha, `observacion_id`, campo, valor anterior, valor nuevo y motivo.
* **Validación previa y rechazos (`rechazos`):** Antes de insertar cualquier fila nueva, `validacion.py` verifica precio numérico mayor a cero, presencia de comercio, URL y timestamp, unicidad `(ejecucion, comercio, sku)` y presencia de los 8 productos comparables. Los registros que incumplen (por ejemplo, SKUs agotados que la API devuelve sin precio) se desvían a la tabla `rechazos` con su huella SHA-256.
* **Disponibilidad explícita:** Se distingue entre `disponible`, `agotado` (según el campo `IsAvailable` del JSON crudo) y `no observado` (calculado por cruce entre ejecuciones en SQL sin asumir retiro definitivo del catálogo).

---

## 3. Estructura de archivos

```text
taller_2/
├── app.py                      # Punto de entrada de Streamlit y navegación multipágina
├── db.py                       # Capa de acceso a datos SQLite, consultas parametrizadas y caché
├── scraper.py                  # Módulo de extracción por comercio y reprocesamiento desde raw/
├── validacion.py               # Reglas de validación pre-inserción y normalización de unidades
├── ui.py                       # Panel lateral de filtros, tarjetas e identidad visual por comercio
├── reconstruir.py              # Script para regenerar la base SQLite desde cero usando raw/
├── verificar.py                # Verificación de integridad SQLite y hashes de respuestas crudas
├── paginas/
│   ├── resumen.py              # Tarjetas de indicadores y gráficos generales de la categoría
│   ├── catalogo.py             # Tabla filtrable, buscador validado y descarga CSV
│   ├── historial.py            # Serie temporal por SKU y comparador entre dos ejecuciones
│   ├── canasta.py              # Simulador de carrito completo, compra dividida y ahorros
│   ├── actualizar.py           # Actualización en línea con st.status y modo sin conexión (raw/)
│   └── calidad.py              # Auditoría de cobertura, rechazos, correcciones y vistas SQL
├── comparador_precios.sqlite   # Base de datos SQLite con historial completo
├── diccionario_datos.md        # Diccionario detallado de tablas, vistas y columnas
├── ejecuciones_entrega.json    # Manifiesto de ejecuciones incluidas en la base
├── legado/                     # Copia de referencia de scripts y consultas del Taller 1
├── raw/                        # Copias crudas comprimidas (.json.gz) por comercio y ejecución
├── tests/                      # Suite de 29 pruebas unitarias e integración con pytest
└── requirements.txt            # Dependencias del proyecto con versiones fijas