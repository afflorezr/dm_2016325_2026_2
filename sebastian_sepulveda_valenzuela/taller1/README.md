# Taller 1: Comparador de Precios con Web Scraping y SQLite

**Asignatura:** Minería de Datos (Código: 2016325) - Semestre 2026-2  
**Institución:** Universidad Nacional de Colombia - Sede Bogotá  
**Estudiante:** Sebastián Sepúlveda Valenzuela  
**Categoría Asignada:** Cuidado y Limpieza del Hogar (*Detergentes, lavalozas, limpiadores, desinfectantes de superficies, ambientadores, bolsas de basura y esponjas*)  
**Comercios Analizados:** Supertiendas Olímpica, Tiendas Jumbo (Cencosud) y Almacenes Éxito  
**Lenguaje Utilizado:** Python 3.9+  
**Zona Horaria:** America/Bogota (UTC-5, formato ISO 8601 con `-05:00`)

---

## 1. Estructura del Repositorio y Archivos

```text
taller1/
├── README.md                      # Documentación del proyecto, instrucciones de ejecución y guía técnica
├── requirements.txt               # Dependencias de Python fijadas con versiones exactas (sin dependencias exclusivas de Windows)
├── .gitignore                     # Exclusión de temporales, caches y bundles generados dinámicamente
├── scraper.py                     # Módulo independiente de recolección, parseo y carga en SQLite
├── taller_1.qmd                   # Documento reproducible (Quarto/Markdown) con pipeline, SQL y gráficos
├── comparador_precios.sqlite      # Base de datos SQLite relacional normalizada con claves foráneas activas
├── certs/                         # Certificados y cadenas criptográficas
│   └── jumbo_chain.pem            # Cadena intermedia oficial para validación SSL activa de Jumbo
├── graficos/                      # Visualizaciones analíticas en alta resolución (300 DPI)
│   ├── 1_precios_comercios.png    # Comparación de precios por presentación
│   ├── 2_precio_por_unidad.png    # Costo por mililitro (economías de escala)
│   └── 3_ahorro_potencial.png     # Dispersión de ahorro potencial (COP y %)
├── tests/                         # Suite de pruebas automatizadas
│   ├── test_parser.py             # Pruebas unitarias para el extractor de contenido y unidades
│   └── test_correspondencia.py    # Pruebas unitarias para homologación EAN y desambiguación
└── raw/                           # Copias crudas originales (JSON comprimidos en gzip < 45 MB)
    ├── Exito/                     # Respuestas crudas particionadas y meta.json por fecha (2026-10-08, 2026-10-28)
    ├── Jumbo/                     # Respuestas crudas particionadas y meta.json por fecha (2026-10-08, 2026-10-26, 2026-10-28)
    ├── Olimpica/                  # Respuestas crudas particionadas y meta.json por fecha (2026-10-08, 2026-10-28)
    └── robots/                    # Evidencia de auditoría ética (robots.txt oficiales descargados)
        ├── Exito_robots.txt
        ├── Jumbo_robots.txt
        └── Olimpica_robots.txt
```

---

## 2. Requisitos Previos e Instalación

### Requisitos del Sistema
- **Python 3.9 o superior** (probado y verificado en Python 3.9.13).
- **Quarto CLI** (opcional, para renderizar `taller_1.qmd` a HTML autónomo).
- Conexión a internet únicamente para la recolección en vivo (`scraper.py`); la ejecución sin conexión no requiere red.

### Instalación de Dependencias
```bash
# 1. Ubicarse en el directorio del taller
cd taller1

# 2. Instalar las dependencias exactas
pip install -r requirements.txt
```

### Ejecución de Pruebas Unitarias
Para validar el funcionamiento del motor de expresiones regulares, normalización de contenidos y reglas de correspondencia:
```bash
pytest tests/
```

---

## 3. Manejo de Certificados SSL (Tiendas Jumbo)

El servidor de Tiendas Jumbo (`www.tiendasjumbo.co`) en ciertas redes omite la entrega del certificado intermedio de la cadena de confianza (GlobalSign), lo que genera errores `SSLCertVerificationError` si no se incluye dicha autoridad intermedia.

Para garantizar verificación SSL 100% activa sin desactivar `verify=True` ni comprometer la seguridad:
1. Se versiona la cadena intermedia en `certs/jumbo_chain.pem`.
2. El script `scraper.py` integra automáticamente esta cadena con los certificados raíz de `certifi` en un bundle temporal local (`certs/combined_bundle.pem`), que es ignorado por git.
3. **Alternativa por variable de entorno:** El usuario o el entorno de integración puede definir `SSL_CERT_FILE` o `REQUESTS_CA_BUNDLE` apuntando a su propio bundle de confianza si así lo requiere:
   ```bash
   export SSL_CERT_FILE=/ruta/al/bundle_completo.pem
   # En Windows PowerShell:
   $env:SSL_CERT_FILE = "C:\ruta\al\bundle_completo.pem"
   ```

---

## 4. Modos de Ejecución del Scraper

El módulo [`scraper.py`](scraper.py) opera de manera autónoma e idempotente mediante dos modalidades principales:

### A. Modo Sin Conexión (Reproducibilidad Determinista)
Procesa de forma 100% offline las copias crudas almacenadas en `raw/`, recreando las tablas y observaciones en SQLite sin realizar peticiones de red:
```bash
# Procesa TODAS las fechas disponibles en raw/ en orden cronológico (2026-10-08 -> 2026-10-26 -> 2026-10-28):
python scraper.py --offline

# O procesar una fecha específica:
python scraper.py --offline --fecha 2026-10-08
python scraper.py --offline --fecha 2026-10-28
```

Solo se conservan ejecuciones con copia cruda en raw/.

### B. Modo En Línea (Recolección en Vivo)
Realiza las consultas HTTP directas contra los endpoints de catálogo VTEX de Olímpica, Jumbo y Éxito, paginando por las subcategorías homologadas sin límites truncados (`max_items` artificial eliminado). Guarda automáticamente copias crudas comprimidas en `raw/<Comercio>/<YYYY-MM-DD>/` divididas en bloques menores a 45 MB y registra los metadatos en `meta.json`:
```bash
python scraper.py
```

---

## 5. Renderizado del Documento Reproducible (`taller_1.qmd`)

El informe analítico completo integra en un único flujo:
1. Invocación al pipeline de scraping mediante `scraper.ejecutar_recoleccion_completa(from_raw=True)`.
2. Tabla de auditoría de completitud frente al total reportado por cada sitio.
3. Verificación de integridad relacional (`PRAGMA foreign_key_check` e `integrity_check`).
4. Las 8 consultas SQL del taller completamente parametrizadas.
5. Las 3 visualizaciones analíticas con su respectiva interpretación económica y limitaciones.
6. Orientación al consumidor para optimización del presupuesto del hogar.

Para renderizar el informe a formato HTML:
```bash
quarto render taller_1.qmd
```
El archivo resultante `taller_1.html` es completamente autónomo (`embed-resources: true`) y puede abrirse en cualquier navegador web sin requerir un servidor activo.

---

## 6. Estructura y Normalización de la Base de Datos

La base relacional `comparador_precios.sqlite` implementa `PRAGMA foreign_keys = ON;` y consta de 6 tablas:
- **`comercios`**: Metadatos de cada tienda participante (nombre, plataforma, URL base).
- **`ejecuciones`**: Registro auditable de cada corrida (fechas ISO 8601, total reportado por el sitio, registros obtenidos, estado `completa`/`parcial`/`fallida` y notas técnicas).
- **`productos`**: Catálogo canónico de artículos comparables identificado por código universal EAN, nombre estandarizado, contenido nominal y unidad de medida homogénea (`g`, `ml`, `und`).
- **`anuncios`**: Publicaciones específicas de cada comercio. Preserva el texto original exacto (`nombre_original`, `descripcion_original`, `ficha_tecnica_original`), categoría nativa, SKU y enlace URL.
- **`observaciones`**: Precios de venta vigentes y precios de lista anteriores con marca de tiempo precisa (`-05:00`) e indicador booleano de promoción (`es_promocion`), blindado mediante restricción de unicidad `UNIQUE(anuncio_id, fecha_hora_consulta)`.
- **`descartados`**: Registro transparente de productos filtrados fuera del alcance de la categoría asignada, con indicación explícita del motivo de exclusión.

---

## 7. Procedimiento para la Segunda Ejecución (Comparación Temporal)

Para satisfacer la recomendación de comparar observaciones en fechas distintas:
1. Asegurarse de contar con conexión a internet estable.
2. Ejecutar el recolector en vivo:
   ```bash
   python scraper.py
   ```
3. El script creará automáticamente un nuevo directorio en `raw/<Comercio>/<YYYY-MM-DD>/` con la fecha del día de ejecución, particionando los archivos `.json.gz` y generando su respectivo `meta.json`.
4. En `comparador_precios.sqlite`, la nueva ejecución quedará registrada con su propio `ejecucion_id` único sin sobrescribir las observaciones históricas del `2026-10-08`, `2026-10-26` ni `2026-10-28`.
5. En `taller_1.qmd`, actualizar el prefijo de la sesión analizada si se desea contrastar la nueva ventana temporal contra las anteriores.

---

## 8. Prueba en Colab o GitHub Actions: No realizado

No se ejecutó esta prueba. El flujo completo (`python scraper.py --offline`) se verificó en el equipo local reconstruyendo la base desde las copias de `raw/`. Como sugerencia para quien reproduzca el trabajo: en Colab basta `pip install -r requirements.txt` y `python scraper.py --offline`.

---

## 9. Advertencias Técnicas y Políticas del Repositorio

- **Límite de Tamaño de Archivos:** Ningún archivo supera los 100 MB requeridos por las políticas de GitHub. Los catálogos crudos se particionan automáticamente en archivos `.json.gz` de tamaño inferior a 45 MB.
- **Seguridad y Credenciales:** El proyecto utiliza exclusivamente endpoints públicos de consulta de catálogo; no almacena contraseñas, tokens de autenticación ni datos sensibles.
- **Política de Respaldos:** Antes de cualquier migración de esquema o depuración física, se genera un respaldo en `../backup_taller1/`.
