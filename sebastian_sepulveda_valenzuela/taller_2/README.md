# Comparador de Precios — Cuidado y Limpieza del Hogar (Taller 2)

**Asignatura:** Minería de Datos (Código: 2016325) — Semestre 2026-2  
**Institución:** Universidad Nacional de Colombia — Sede Bogotá  
**Estudiante:** Sebastián Sepúlveda Valenzuela  
**Enlace a la Aplicación Publicada:** [https://comparador-precios-aseohogar-sebastian.streamlit.app/](https://comparador-precios-aseohogar-sebastian.streamlit.app/)  

---

## 1. Descripción del Proyecto

Este proyecto corresponde a la entrega del **Taller 2 de Minería de Datos**, enfocado en transformar el pipeline de web scraping y almacenamiento en SQLite del Taller 1 en una **aplicación web analítica multipágina** construida con **Streamlit (Python)**. La plataforma orienta al consumidor sobre dónde y cómo comprar productos de consumo masivo para el aseo del hogar en **Supertiendas Olímpica, Tiendas Jumbo y Almacenes Éxito**, comparando precios por unidad de medida normalizada (`mL`, `g`, `unidad`) y simulando canastas familiares de compra con estrategias de optimización cruzada.

---

## 2. Requisitos del Sistema y Ejecución Local

### 2.1. Requisitos Previos
* Python 3.9, 3.10 o **3.11** (versión oficial recomendada para Streamlit Cloud).
* Git instalado en el sistema.

### 2.2. Paso a Paso para Ejecución Local

1. **Clonar el repositorio y ubicarse en la carpeta del proyecto:**
   ```bash
   cd sebastian_sepulveda_valenzuela/taller_2
   ```

2. **Crear y activar el entorno virtual:**
   ```bash
   # En Windows (PowerShell)
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1

   # En Linux / macOS
   python3 -m venv .venv
   source .venv/bin/activate
   ```

3. **Instalar dependencias fijadas:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Ejecutar las migraciones de base de datos (idempotente):**
   ```bash
   python migraciones.py
   ```
   *Aplica el esquema relacional, crea vistas, normaliza unidades a `mL`, `g` y `unidad`, puebla disponibilidad desde `raw/` y asocia los 8 comparables canónicos.*

5. **Iniciar la aplicación Streamlit:**
   ```bash
   streamlit run app.py
   ```
   *La aplicación se abrirá automáticamente en `http://localhost:8501`.*

### 2.3. Ejecución de Pruebas Automatizadas
Para correr la suite completa de pruebas unitarias sobre una base temporal aislada:
```bash
pytest tests/
```
*Se ejecutan 22 pruebas unitarias automatizadas (100% pasando, 0 fallos).*

---

## 3. Estructura de Archivos del Proyecto

```text
sebastian_sepulveda_valenzuela/
  taller_2/
    app.py                     # Punto de entrada y navegación con st.navigation
    paginas/                   # Módulos multipágina independientes
      resumen.py               # Resumen ejecutivo con 8 métricas y 4 gráficos Plotly
      explorar.py              # Catálogo interactivo con filtros, enlaces y exportación CSV
      cambios.py               # Monitoreo de variaciones de precio y umbral porcentual
      canasta.py               # Simulador de canasta familiar con optimización cruzada
      actualizar.py            # Actualización con st.status, transacciones y modo offline
      acerca.py                # Ficha técnica, taxonomía y documentación metodológica
    db.py                      # Capa de acceso a SQLite (TODO el SQL y la lógica viven aquí)
    scraper.py                 # Scraper oficial del Taller 1 refactorizado y tolerante a fallas
    validacion.py              # Validación de calidad de datos con esquemas Pandera
    migraciones.py             # Migración idempotente del esquema, vistas e índices
    ui_comun.py                # Formatos COP, paleta de colores y componentes visuales
    sql/
      vistas.sql               # Definición SQL canónica de las 6 vistas analíticas
    comparador_precios.sqlite  # Base de datos SQLite normalizada
    diccionario_datos.md       # Diccionario de datos exhaustivo de tablas y vistas
    raw/                       # Copias crudas en .json.gz (<50 MB) y metadatos de trazabilidad
    certs/
      jumbo_chain.pem          # Cadena intermedia SSL oficial para Tiendas Jumbo
    tests/
      conftest.py              # Configuración de fixtures temporales (tmp_path)
      test_taller2.py          # Pruebas obligatorias del enunciado (precios, canasta, unicidad, pandera)
      test_parser.py           # Pruebas del parser de unidades
      test_correspondencia.py  # Pruebas de homologación de productos
    requirements.txt           # Dependencias fijas con versiones exactas (==)
    .python-version            # Versión de Python fijada en 3.11
    .streamlit/
      config.toml              # Configuración de tema visual y layout ancho
      secrets.toml.example     # Plantilla de secretos (secrets.toml está en .gitignore)
    .gitignore                 # Exclusión estricta de credenciales, caches y binarios
    README.md                  # Este documento
```

---

## 4. Selección y Justificación de los 8 Productos Comparables

El enunciado exige identificar exactamente **ocho productos comparables presentes en los tres comercios** de forma simultánea. Se auditaron las capturas reales de catálogo mediante consultas SQL cruzadas por código EAN internacional, marca y contenido neto, verificando su presencia física en las tiendas:

| # | Código EAN | Producto de Referencia | Marca | Subcategoría | Contenido | Unidad Oficial |
| :-: | :--- | :--- | :--- | :--- | :-: | :-: |
| 1 | `7501023131748` | Esponja SCOTCH BRITE esferas limpieza (2 und) | Scotch Brite | Utensilios De Limpieza | 2.0 | `unidad` |
| 2 | `7702037870306` | Esponja ETERNA kit colores surtidos (3 und) | Eterna | Utensilios De Limpieza | 3.0 | `unidad` |
| 3 | `7500435112413` | Detergente en polvo ARIEL triple poder (1000 gr) | Ariel | Cuidado De La Ropa | 1000.0 | `g` |
| 4 | `7702010382147` | Lavaplatos en crema AXION limón (850 gr) | Axion | Cuidado De Superficies | 850.0 | `g` |
| 5 | `7500435122016` | Detergente líquido ARIEL limpieza profunda (1200 ml) | Ariel | Cuidado De La Ropa | 1200.0 | `mL` |
| 6 | `7509546051932` | Lavaplatos líquido AXION limón (750 ml) | Axion | Cuidado De Superficies | 750.0 | `mL` |
| 7 | `7702010225123` | Limpiapisos FABULOSO antibacterial lavanda (1000 ml) | Fabuloso | Cuidado De Superficies | 1000.0 | `mL` |
| 8 | `7503041359241` | Limpiador MR MUSCULO platinum cocina limón (500 ml) | MR MUSCULO | Cuidado De Superficies | 500.0 | `mL` |

**Criterios de selección:**
1. **Diversidad de subcategorías:** Cubre detergentes para ropa (líquido y polvo), lavaplatos (crema y líquido), desengrasantes, limpiapisos y utensilios abrasivos.
2. **Representatividad de unidades:** 2 en `unidad`, 2 en `g` y 4 en `mL`, permitiendo análisis limpios de precio unitario sin mezclar magnitudes.
3. **Consistencia empírica:** Los 8 productos cuentan con observaciones activas en todas las ejecuciones históricas completas en los 3 comercios.

---

## 5. Vistas SQL Implementadas ([sql/vistas.sql](sql/vistas.sql))

1. **`v_observaciones`:** Join plano integral entre observaciones, anuncios, productos y comercios. Calcula en tiempo de ejecución el precio unitario exacto (`precio_actual / contenido_total`).
2. **`v_ultimo_precio`:** Filtra la observación más reciente de cada anuncio activo (`descartada = 0`) resolviendo empates mediante `ROW_NUMBER() OVER(PARTITION BY anuncio_id ORDER BY fecha_hora_consulta DESC)`. Es la vista base para los filtros e indicadores.
3. **`v_comparables`:** Enfocada exclusivamente en los 8 comparables canónicos vinculados a la tabla `comparables_8`, exponiendo precios de venta y precios unitarios homogéneos.
4. **`v_cambios_precio`:** Implementa la función de ventana `LAG()` sobre el historial del mismo anuncio en el mismo comercio, clasificando los registros en `subida`, `bajada`, `sin_cambio` o `nuevo` y calculando la variación en COP y porcentaje.
5. **`v_disponibilidad`:** Genera la matriz cartesiana entre comercios, ejecuciones y los 8 comparables. Si un producto no fue capturado en una fecha dada, deriva dinámicamente el estado `'no_observado'` sin insertar filas ficticias en la base de datos.
6. **`v_ejecuciones_resumen`:** Reporta métricas de control por ejecución: total de anuncios observados, cobertura de los 8 comparables, registros con precio y notas de estado (`completa`, `parcial`, `fallida`).

---

## 6. Justificación del Gráfico Libre (Módulo 5, 7.4)

En la página de **Resumen Ejecutivo**, se incluyó el gráfico interactivo:  
**"¿Qué comercio resulta más barato con mayor frecuencia en los productos esenciales?"** (Gráfico circular tipo donut).

* **Justificación para el consumidor:** Cuando un comprador habitual acude a un supermercado, difícilmente consulta el precio unitario mililitro a mililitro de cada referencia; busca una regla de decisión práctica: *¿cuál supermercado tiende a ser el más barato en la mayoría de sus compras de aseo?*
* **Respuesta analítica:** El gráfico calcula con SQL la frecuencia con la que cada comercio ofrece el precio mínimo absoluto en los 8 comparables canónicos. Esto evidencia que el liderazgo de precios no es monolítico: mientras Jumbo suele liderar en detergentes para ropa, Olímpica y Éxito ofrecen precios más competitivos en lavaplatos y limpiadores de superficies, demostrando el valor de la compra cruzada.

---

## 7. Cambios Respecto al Taller 1 y Registro de Correcciones

Todas las modificaciones sobre los datos entregados en el Taller 1 fueron aplicadas de manera transparente y quedaron registradas en la tabla SQLite `correcciones`:
1. **Adición de trazabilidad de descarte:** Se agregaron las columnas `descartada` y `motivo_descarte` en `observaciones` para evitar borrar registros antiguos.
2. **Captura de disponibilidad:** Se agregaron las columnas `disponibilidad` ('disponible'/'agotado') en `observaciones`, repoblando retrospectivamente 10.685 observaciones a partir de `AvailableQuantity` y `IsAvailable` de los archivos crudos en `raw/`.
3. **Estandarización de unidades normalizadas:** Se migraron las unidades históricas (`ml` $\rightarrow$ `mL`, `und` $\rightarrow$ `unidad`, `g` $\rightarrow$ `g`).
4. **Restricción de unicidad reforzada:** Se creó el índice único `uidx_obs_anuncio_ejecucion ON observaciones(anuncio_id, ejecucion_id)` para garantizar idempotencia total en re-ejecuciones.
5. **Tabla de auditoría de rechazos:** Se creó la tabla `rechazos` vinculada al validador Pandera.
6. **Validación estricta de precios y productos agotados (Pandera):** Se implementó la regla explícita de calidad de datos según la cual un precio solo puede ser `NULL` si el producto está marcado como `'agotado'` (sin oferta comercial activa). Todo producto disponible con precio `NULL` o `NaN` es rechazado y registrado en `rechazos`, al igual que cualquier precio $\le 0$.

---

## 8. Persistencia en la Nube y Modo Sin Conexión

> [!NOTE]
> Las plataformas de alojamiento gratuito como **Streamlit Community Cloud** disponen de almacenamiento de disco efímero: cualquier modificación local sobre el archivo SQLite se reinicia cuando el contenedor se suspende por inactividad.  
> Por ello, la base `comparador_precios.sqlite` se distribuye pre-poblada con todo el historial. La actualización en vivo mediante scraping web es plenamente funcional en ejecuciones locales. En Streamlit Cloud, ante posibles bloqueos antibot perimetrales (HTTP 403 / Cloudflare), la aplicación dispone del **Modo Sin Conexión**, el cual reprocesa instantáneamente las copias crudas archivadas en `raw/`.

---

## 9. Hallazgos Empíricos para el Consumidor (Verificables en la App y entre Sesiones)

A partir del análisis longitudinal comparando la sesión del **28 de octubre de 2026** (`EXEC_20261028_201829_06c93c_*`) con la nueva sesión del **16 de noviembre de 2026** (`EXEC_20261116_025839_e80b52_*`), se identificaron tres conclusiones cuantitativas verificables:

### 💡 Hallazgo 1: Volatilidad y reversión de ofertas en Detergente Líquido Ariel 1200 mL
* **Resultado:** Entre las sesiones del 2026-10-28 y 2026-11-16, se produjo un cambio radical en la referencia comercial (*Detergente líquido ARIEL limpieza profunda 1200 mL*, EAN `7500435122016`):
  - **Jumbo:** Pasó de **$ 15.720 COP** a **$ 26.200 COP**, un alza abrupta de **+$ 10.480 COP (+66,67 %)** al finalizar su campaña de descuento.
  - **Éxito:** En sentido contrario, aplicó un descuento bajando de **$ 27.050 COP** a **$ 21.640 COP**, una reducción de **-$ 5.410 COP (-20,00 %)**.
  - **Olímpica:** Mantuvo estabilidad de precio de lista en **$ 24.290 COP**.
* **Impacto para el consumidor:** Mientras que el 28 de octubre Jumbo era el comercio más barato del mercado ($ 15.720 COP), el 16 de noviembre pasó a ser el más costoso ($ 26.200 COP), siendo superado ampliamente por Éxito ($ 21.640 COP). Comprar esta referencia en Éxito en lugar de Jumbo representa un ahorro directo de **$ 4.560 COP (17,4 %)**.
* **Consulta SQL de verificación:**
  ```sql
  SELECT 
      c.nombre AS comercio,
      o1.precio_actual AS precio_20261028,
      o2.precio_actual AS precio_20261116,
      (o2.precio_actual - o1.precio_actual) AS dif_cop,
      ROUND((o2.precio_actual - o1.precio_actual) * 100.0 / o1.precio_actual, 2) AS var_pct
  FROM productos p
  JOIN anuncios a ON p.producto_id = a.producto_id
  JOIN comercios c ON a.comercio_id = c.comercio_id
  JOIN observaciones o1 ON a.anuncio_id = o1.anuncio_id AND o1.ejecucion_id LIKE 'EXEC_20261028_201829_06c93c_%'
  JOIN observaciones o2 ON a.anuncio_id = o2.anuncio_id AND o2.ejecucion_id LIKE 'EXEC_20261116_025839_e80b52_%'
  WHERE p.ean = '7500435122016';
  ```

---

### 💡 Hallazgo 2: Giro en el liderazgo de la Canasta Familiar y beneficio de la Canasta Óptima
* **Resultado:** La suma de los 8 productos comparables canónicos reveló una reconfiguración total de la competitividad por establecimiento:
  - **Sesión 2026-10-28 (`EXEC_20261028_201829_06c93c_*`):**
    - Jumbo: **$ 84.023 COP** *(Líder en tienda única)*
    - Éxito: **$ 102.265 COP**
    - Olímpica: **$ 110.670 COP**
    - Canasta Óptima Combinada: **$ 82.111 COP** (Ahorro de **$ 28.559 COP / 25,8 %** vs Olímpica).
  - **Sesión 2026-11-16 (`EXEC_20261116_025839_e80b52_*`):**
    - Olímpica: **$ 106.595 COP** *(Pasa a ser la opción más económica de tienda única, -$ 4.075 COP)*
    - Éxito: **$ 106.870 COP**
    - Jumbo: **$ 109.450 COP** *(Pasa al último lugar con un alza agregada de +$ 25.427 COP / +30,26 % por fin de promociones)*
    - Canasta Óptima Combinada: **$ 100.285 COP** (Ahorro de **$ 6.310 COP / 5,9 %** vs Olímpica y **$ 9.165 COP / 8,4 %** vs Jumbo).
* **Conclusión:** Ningún comercio garantiza el menor precio de forma permanente en el tiempo. La estrategia de compra combinada óptima (adquirir 3 productos en Olímpica, 3 en Jumbo y 2 en Éxito) blinda al consumidor contra las oscilaciones de precios, reduciendo la canasta a $ 100.285 COP.
* **Consulta SQL de verificación:**
  ```sql
  -- Costo total de la canasta de 8 comparables por comercio en ambas sesiones
  SELECT 
      c.nombre AS comercio,
      SUM(CASE WHEN o.ejecucion_id LIKE 'EXEC_20261028_201829_06c93c_%' THEN o.precio_actual END) AS canasta_20261028,
      SUM(CASE WHEN o.ejecucion_id LIKE 'EXEC_20261116_025839_e80b52_%' THEN o.precio_actual END) AS canasta_20261116
  FROM observaciones o
  JOIN anuncios a ON o.anuncio_id = a.anuncio_id
  JOIN comercios c ON a.comercio_id = c.comercio_id
  JOIN productos p ON a.producto_id = p.producto_id
  WHERE p.es_canasta_8 = 1
  GROUP BY c.nombre;

  -- Costo de la canasta óptima combinada en 2026-11-16
  WITH min_prod AS (
      SELECT p.producto_id, MIN(o.precio_actual) AS precio_min
      FROM observaciones o
      JOIN anuncios a ON o.anuncio_id = a.anuncio_id
      JOIN productos p ON a.producto_id = p.producto_id
      WHERE p.es_canasta_8 = 1 AND o.ejecucion_id LIKE 'EXEC_20261116_025839_e80b52_%'
      GROUP BY p.producto_id
  )
  SELECT SUM(precio_min) AS costo_optimo_combinado_20261116 FROM min_prod;
  ```

---

### 💡 Hallazgo 3: Descuento agresivo en Olímpica (Limpiapisos Fabuloso 1000 mL)
* **Resultado:** En la categoría de limpieza de pisos, la referencia *Limpiapisos FABULOSO antibacterial lavanda 1000 mL* (EAN `7702010225123`):
  - **Olímpica:** Desplomó su precio de **$ 11.200 COP** a **$ 7.125 COP**, una baja de **-$ 4.075 COP (-36,38 %)**.
  - **Jumbo:** Subió de **$ 7.592 COP** a **$ 9.220 COP** (+21,44 %).
  - **Éxito:** Mantuvo su precio en **$ 9.830 COP**.
* **Conclusión:** Olímpica pasó de ser el comercio más caro en esta referencia el 28 de octubre ($ 11.200 COP) a posicionarse como el líder de ahorro indiscutible el 16 de noviembre ($ 7.125 COP, $ 7,13 / mL), ofreciendo un costo 22,7 % menor que Jumbo y 27,5 % menor que Éxito.
* **Consulta SQL de verificación:**
  ```sql
  SELECT 
      c.nombre AS comercio,
      o1.precio_actual AS precio_20261028,
      o2.precio_actual AS precio_20261116,
      (o2.precio_actual - o1.precio_actual) AS dif_cop,
      ROUND((o2.precio_actual - o1.precio_actual) * 100.0 / o1.precio_actual, 2) AS var_pct
  FROM productos p
  JOIN anuncios a ON p.producto_id = a.producto_id
  JOIN comercios c ON a.comercio_id = c.comercio_id
  JOIN observaciones o1 ON a.anuncio_id = o1.anuncio_id AND o1.ejecucion_id LIKE 'EXEC_20261028_201829_06c93c_%'
  JOIN observaciones o2 ON a.anuncio_id = o2.anuncio_id AND o2.ejecucion_id LIKE 'EXEC_20261116_025839_e80b52_%'
  WHERE p.ean = '7702010225123';
  ```

---

## 10. Guía Paso a Paso para Despliegue en Streamlit Community Cloud

Para desplegar la aplicación en la nube pública sin costo:

1. **Subir los cambios a GitHub:**
   Asegúrese de hacer commit y push de la carpeta `sebastian_sepulveda_valenzuela/taller_2/` en la rama de su repositorio (ej. `main` o rama de trabajo).
2. **Iniciar sesión en Streamlit Cloud:**
   Ingrese a [share.streamlit.io](https://share.streamlit.io/) e inicie sesión vinculando su cuenta de GitHub.
3. **Crear una nueva aplicación ("Create app"):**
   Haga clic en el botón azul **"New app"** y configure:
   * **Repository:** Seleccione el repositorio del curso (`dm_2016325_2026_2`).
   * **Branch:** Seleccione la rama donde reside su entrega (ej. `taller1` o `main`).
   * **Main file path:** Indique la ruta relativa exacta al punto de entrada:
     ```text
     sebastian_sepulveda_valenzuela/taller_2/app.py
     ```
   * **App URL (opcional):** Puede personalizar el subdominio si está disponible.
4. **Configuración avanzada (Advanced settings):**
   * Verifique que la versión de Python seleccionada sea **3.11** (Streamlit Cloud leerá automáticamente el archivo `.python-version`).
   * En la sección **Secrets**, no se requiere configurar variables obligatorias, ya que el proyecto opera de forma autónoma con SQLite local.
5. **Desplegar ("Deploy"):**
   Haga clic en **"Deploy!"**. La plataforma instalará las dependencias desde `requirements.txt` y publicará la aplicación en pocos minutos.
6. **Actualizar el README:**
   Copie la URL generada (ej. `https://comparador-precios-unal.streamlit.app/`) y reemplácela en el campo `<<URL>>` al inicio de este README.

---

## 11. Declaración de Uso de Inteligencia Artificial

*En cumplimiento de la Sección 11 del enunciado del Taller 2:*

* **Herramientas de IA utilizadas:**
  Se empleó **Antigravity CLI / IDE** con el modelo **Gemini 3.8 Flash (Medium)**.
* **Partes del trabajo en que se utilizó:**
  1. *Estructuración del proyecto:* Generación del esqueleto modular multipágina (`st.navigation`) separando la interfaz de la capa de persistencia (`db.py`).
  2. *Refactorización del scraper:* Implementación del patrón de transacción aislada por comercio (`recolectar_comercio`) y el conector de diagnóstico de red.
  3. *Optimización SQL:* Escritura de las consultas de ventana (`ROW_NUMBER()` y `COUNT()`) para el cálculo exacto de medianas en SQLite y la vista de cambios de precio (`LAG()`).
  4. *Diseño de pruebas:* Construcción de fixtures temporales en `pytest` para verificar las restricciones de unicidad, sanitización contra inyección SQL y casos de empate en la canasta.
* **Mecanismos de verificación humana y técnica:**
  * **Verificación empírica con datos crudos:** Se ejecutó un script de verificación cruzada aleatoria comprobando que los precios en la base de datos coincidieran al 100% con los payloads JSON crudos de `raw/`.
  * **Validación de pruebas automatizadas:** Se corrió la suite `pytest tests/`, pasando las 22 pruebas unitarias sin excepciones.
  * **Verificación matemática de indicadores:** Se validó que cada indicador numérico de la interfaz gráfica coincidiera con una consulta SQL directa e independiente ejecutada sobre SQLite.
  * **Auditoría de seguridad:** Escaneo sistemático para certificar la ausencia de credenciales expuestas, ausencia de rutas absolutas locales y uso exclusivo de consultas parametrizadas.
