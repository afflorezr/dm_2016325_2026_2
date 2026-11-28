"""
paginas/acerca.py
=================
Página de documentación metodológica, alcance y ficha técnica del proyecto.
Taller 2 - Minería de Datos (UNAL, código 2016325).
"""

import streamlit as st
from db import obtener_comparables_8_catalogo
from ui_comun import aplicar_estilos_comercio

aplicar_estilos_comercio()

st.title("ℹ️ Acerca del Proyecto")
st.markdown("### Comparador de Precios y Canasta Familiar de Aseo")
st.markdown("""
**Universidad Nacional de Colombia**  
**Facultad de Ingeniería / Ciencias**  
**Asignatura:** Minería de Datos (Código: 2016325) — Semestre 2026-2  
**Autor:** Sebastián Sepúlveda Valenzuela  
""")

st.divider()

st.subheader("🎯 1. Objetivo General")
st.markdown("""
Convertir el comparador de precios de la categoría **Cuidado y Limpieza del Hogar** desarrollado en el Taller 1 en una 
aplicación web interactiva y modular construida en **Streamlit (Python)**, desplegada en **Streamlit Community Cloud**, 
que consulte la base de datos relacional SQLite, la actualice mediante web scraping confiable y oriente objetivamente 
al consumidor sobre dónde y cómo comprar productos individuales o una canasta básica de aseo.
""")

st.subheader("🛒 2. Comercios Evaluados y Delimitación")
st.markdown("""
Se analizan de forma continua tres cadenas de supermercados líderes en Colombia:
* **Supertiendas Olímpica:** Peticiones HTTPS directas a APIs VTEX de catálogo.
* **Tiendas Jumbo (Cencosud):** APIs de búsqueda VTEX con verificación SSL reforzada mediante bundle intermedio (`certs/jumbo_chain.pem`).
* **Almacenes Éxito:** APIs VTEX FastStore con trazabilidad de catálogo.

**Delimitación de la categoría:**
* **Incluidos:** Detergentes en polvo y líquidos para ropa, lavaplatos líquidos y en crema, limpiadores multiusos y desinfectantes para pisos/baños, ambientadores de ambiente, esponjas/fibras abrasivas de limpieza y bolsas de basura.
* **Excluidos:** Papel higiénico, servilletas y toallas de cocina (higiene personal y celulosa), insecticidas y plaguicidas, ceras para calzado (betunes), carbón y velas.
""")

st.subheader("🏷️ 3. Los 8 Productos Comparables Canónicos")
st.markdown("""
Para garantizar comparaciones científicamente rigurosas, exactas y sin mezclas engañosas de presentaciones, se seleccionaron 
**ocho productos esenciales** presentes en los tres comercios de manera simultánea, con idéntico código EAN internacional, 
marca y contenido estandarizado:
""")

cat_8 = obtener_comparables_8_catalogo()
if not cat_8.empty:
    df_cat_show = cat_8[["ean", "nombre_referencia", "marca", "subcategoria", "contenido_total", "unidad_normalizada"]].copy()
    df_cat_show.columns = ["EAN", "Producto de Referencia", "Marca", "Subcategoría", "Contenido", "Unidad"]
    st.dataframe(df_cat_show, width="stretch", hide_index=True)

st.subheader("🛡️ 4. Calidad, Trazabilidad y Arquitectura")
st.markdown("""
* **Todo dato proviene del scraping:** Prohibido simular o inventar datos. Cada observación se respalda en una copia cruda `.json.gz` en `raw/` con su identificador en `ejecuciones`.
* **Validación rigurosa con Pandera:** Reglas formales de precio $>0$, claves obligatorias no nulas y ausencia de duplicados. Los rechazos se registran en la tabla `rechazos`.
* **Transacciones por comercio:** Las actualizaciones aíslan cada comercio en una transacción `BEGIN ... COMMIT / ROLLBACK` tolerando fallos de red o bloqueos HTTP 403 sin corromper la base de datos.
* **Persistencia en la nube:** La capa gratuita de Streamlit Community Cloud cuenta con almacenamiento efímero (se restablece en reinicios). Las actualizaciones en vivo son plenamente funcionales en ejecución local y se ofrece el modo sin conexión para reproducibilidad inmediata en cualquier servidor.
""")
