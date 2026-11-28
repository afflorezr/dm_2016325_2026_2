# Taller 2 · Minería de Datos · Comparador de precios de dermocosmética facial

**Lenguaje:** Python 3 (Streamlit) · **Autora:** Diana Catalina Vásquez León
**Comercios:** Dermatodo, Farmatodo, La Rebaja · **Categoría:** dermocosmética facial

## Aplicación publicada
✏️ Enlace: `https://...streamlit.app` *(pegar aquí el enlace de Streamlit Community Cloud)*

Notas sobre la versión publicada:
- Los comercios suelen bloquear a los servidores de la nube; si la actualización en línea falla, la app lo informa y ofrece el **modo sin conexión** (reprocesa `raw/`).
- Las plataformas gratuitas **no conservan los cambios en la base** al reiniciarse. La actualización en línea funciona al ejecutar la app localmente.

## Ejecución local
```bash
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python migrar_taller2.py          # prepara la base (idempotente) y genera diccionario_datos.md
streamlit run app.py
```
Actualizar desde la app requiere un correo de contacto (viaja en el `User-Agent`): se escribe en la página *Actualizar precios* o en la variable de entorno `SCRAPER_CONTACTO` / `.streamlit/secrets.toml` (ambos en `.gitignore`).

Desde la terminal, sin la app:
```bash
python -c "import scraper; scraper.recolectar_todo()"                 # en línea
python -c "import scraper; scraper.recolectar_todo(offline=True)"     # sin conexión (raw/)
```

## Pruebas
```bash
pytest tests/
```
Doce pruebas con bases temporales (no usan la base de la entrega ni los sitios): conversión de precios, normalización de unidades, ahorro con empates, inserción repetida sin duplicados (también si cambia la hora de consulta), detección de cambios de precio, canasta incompleta, reglas de validación, rechazos registrados, búsqueda segura, anuncios no observados y observaciones repetidas descartadas.

## Estructura
| Archivo | Descripción |
|---|---|
| `app.py`, `paginas/` | Interfaz Streamlit (Resumen, Cambios de precio, Canasta, Actualizar). Sin SQL. |
| `datos.py` | Caché (`st.cache_data`) sobre `db.py`; se invalida al cambiar la base o al terminar una actualización. |
| `db.py` | Capa de acceso a datos: consultas parametrizadas, conexión de solo lectura. |
| `scraper.py` | Extracción del Taller 1 (una función por comercio + `recolectar_todo`), ahora con validación y transacciones. |
| `validacion.py` | Reglas que debe superar cada observación antes de insertarse. |
| `preparacion.py` | Estandarización y correspondencia de los 10 productos comparables. |
| `migrar_taller2.py` | Lleva la base al esquema del Taller 2 (correcciones, vistas, índices, diccionario). |
| `comparador_precios.sqlite` | Base de datos. |
| `raw/` | Copias crudas por comercio/fecha/ejecución (`ejecuciones.ruta_raw` apunta a cada una). |
| `diccionario_datos.md` | Tablas, vistas y columnas. |
| `hallazgos.py` | Recalcula con SQL las cifras de los hallazgos. |
| `verificar_entrega.py` | Revisa la carpeta contra los requisitos del enunciado. |
| `tests/` | Pruebas automáticas. |

## Vistas SQL que usa la aplicación
- `v_observaciones`: observaciones de ejecuciones válidas, con precio unitario.
- `v_ultimo_precio`: última observación válida de cada anuncio (base de filtros e indicadores).
- `v_cambios_precio`: variación entre las dos últimas observaciones de cada anuncio.
- `v_comparables`: los 10 productos comparables por ejecución válida.
- `v_disponibilidad`: disponible / agotado según el sitio / no observado, por ejecución.

## Ejecuciones en la base
| Ejecución | Estado | Uso |
|---|---|---|
| EJEC_20261111_171706 | Completa (3 comercios) | Válida, la más reciente |
| EJEC_20261108_111515 | Completa (3 comercios) | Válida |
| EJEC_20261008_160033 | Dermatodo parcial (criterio anterior) | Válida, solo historial |
| EJEC_20261005_122323 | Sin copias crudas | Descartada |
| EJEC_20261110_155506 | Incompleta (Dermatodo y Farmatodo fallaron) | Descartada |
| EJEC_20261111_163607 | Interrumpida | Descartada |

## Origen y verificación de los datos
Todos los datos provienen de `scraper.py`. Cada ejecución guarda sus respuestas originales en `raw/` y `ejecuciones.ruta_raw` las enlaza. Las correcciones sobre la entrega del Taller 1 están en la tabla `correcciones` (marcas `comparable` del 8/10 reprocesadas, obsequios a $1 excluidos de la categoría, ejecuciones descartadas con su motivo). Las observaciones que no superan la validación se guardan en `observaciones_rechazadas`.

**Dermatodo:** el sitio declara 840 productos en `collections.json`, pero su listado visible muestra 640 y el feed JSON entrega 637 (los 637 están dentro de los 640; las 3 diferencias son productos ajenos a la categoría). La ejecución se marca completa cuando el feed cubre el listado visible.

## Limitaciones
- **Precios puntuales:** corresponden al momento de la captura; incluyen promociones y no incluyen envío, mínimos de compra ni programas de fidelización.
- **Pocas ejecuciones:** el historial cubre pocas fechas, así que las variaciones de precio entre ellas no permiten concluir tendencias ni causas.
- **Solo 10 productos comunes a los tres comercios:** la comparación directa no generaliza a toda la categoría; no se comparan promedios de surtidos distintos.
- **Dermatodo:** el sitio declara 840 productos pero muestra 640 (ver arriba). La ejecución se marcó completa con ese criterio.
- **Farmatodo:** una parte de sus anuncios no trae URL en la fuente de datos (la API no la entrega). La validación los rechaza y quedan en `observaciones_rechazadas` con su motivo; su número de productos varía entre ejecuciones.
- **Ejecución del 5/10/2026 descartada:** no conserva las copias crudas, así que sus observaciones no son verificables; se marcó como no válida (tabla `correcciones`) y no entra al análisis.
- **Un producto «no observado» no se interpreta como agotado ni retirado.**
- **Despliegue gratuito:** los comercios suelen bloquear a los servidores de la nube y los cambios en la base no se conservan al reiniciar; por eso existe el modo sin conexión.

## Hallazgos para el consumidor
Basados en las ejecuciones **EJEC_20261108_111515 (8/11/2026)** y **EJEC_20261111_171706 (11/11/2026)**, ambas completas en los tres comercios, y en 10 productos idénticos presentes en todos ellos. Los precios son los vigentes al momento de la captura.

1. **No hay un comercio más barato para todo, pero La Rebaja gana en la mayoría.** El 11/11, La Rebaja tuvo el menor precio en 6 de los 10 productos (por ejemplo, Eucerin DermoPure Gel Limpiador 200 mL a $82.000 frente a $114.150 en el más caro: ahorro de $32.150, 28,2 %), Farmatodo en los 4 productos Sesderma, y Dermatodo en ninguno. *Verificable en:* Resumen → «Oportunidad de ahorro».

2. **Para la canasta de los 10 productos, un solo comercio basta.** El 11/11 la canasta (1 unidad de cada uno) costó $1.737.000 en La Rebaja, $1.865.540 en Farmatodo y $1.936.151 en Dermatodo: La Rebaja es $199.151 (10,3 %) más barata que Dermatodo y $128.540 (6,9 %) más barata que Farmatodo. Comprar cada producto donde es más barato daría $1.730.490, solo $6.510 (0,4 %) menos que comprar todo en La Rebaja. Parte de esa ventaja viene de promociones: a precio de lista la canasta de La Rebaja sería $1.809.800 ($72.800 más que con descuentos), y su diferencia con Farmatodo bajaría a $55.740. No incluye envío ni mínimos de compra. *Verificable en:* Canasta, con los 10 productos.

3. **El envase grande sale más barato por mL, aunque cuesta más.** El 11/11, el Cetaphil Limpiador Piel Grasa de 473 mL cuesta alrededor de un 30 % menos por mL que el de 237 mL en los tres comercios: La Rebaja $185,7 frente a $267,0 por mL; Dermatodo $238,4 frente a $341,8; Farmatodo $238,7 frente a $344,5. El desembolso es mayor (en La Rebaja, $87.840 frente a $63.280). *Verificable en:* Resumen → «Precio por unidad» → «Mismo producto en distintos tamaños».

4. **Los precios cambian entre fechas, sobre todo por descuentos.** Entre el 8/11 y el 11/11, 10 anuncios de La Rebaja bajaron (mediana de −20 %), 1 anuncio de Dermatodo subió 53,9 % (su precio anterior equivale exactamente al 65 % del nuevo, compatible con el fin de un descuento del 35 %) y Farmatodo no tuvo cambios. Con solo dos ejecuciones no se pueden afirmar tendencias ni causas. *Verificable en:* Cambios de precio, con esas dos ejecuciones.

Los datos de estos hallazgos se pueden recalcular con `python hallazgos.py`.

## Declaración de uso de inteligencia artificial
- **Herramientas:** Claude (Anthropic).
- **Para qué:** apoyo en el diseño de la base de datos (vistas, tabla de correcciones y de observaciones rechazadas), en `validacion.py`, `db.py`, las páginas de la aplicación, las pruebas automáticas, la corrección de errores del scraper y la revisión de los hallazgos.
- **Cómo se verificó:** ejecuté las 12 pruebas automáticas, revisé cada consulta contra la base, comprobé las cifras de los hallazgos en la aplicación y con `hallazgos.py`, y revisé a mano la correspondencia de los 10 productos y las ejecuciones descartadas. Corrí `verificar_entrega.py` contra los requisitos del enunciado.
- Soy responsable de todo el código entregado y puedo explicarlo.
