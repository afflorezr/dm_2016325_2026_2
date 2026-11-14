"""
Comparador de precios de incontinencia y cuidado del adulto.

Se ejecuta desde la carpeta parcial_02 con:
    streamlit run app.py

app.py solo arma la página: el panel de filtros y el menú. Cada sección
está en paginas/, las consultas en db.py y lo que comparten las páginas
(caché, colores, formato) en ui.py.
"""

import streamlit as st

import ui

st.set_page_config(page_title="Comparador de precios", layout="wide")

pagina = st.navigation([
    st.Page("paginas/resumen.py", title="Resumen", default=True),
    st.Page("paginas/comparar.py", title="Comparar comercios"),
    st.Page("paginas/cambios.py", title="Cambios de precio"),
    st.Page("paginas/canasta.py", title="Canasta"),
    st.Page("paginas/datos.py", title="Productos"),
    st.Page("paginas/actualizar.py", title="Actualizar y calidad"),
    st.Page("paginas/catalogo.py", title="Catálogo"),
])

# Tarjetas de indicadores con bordes redondeados. Cada columna tiene un
# fondo claro distinto y un borde izquierdo del mismo tono, para separar
# las tarjetas sin usar los colores de los comercios.
st.markdown("""
<style>
[data-testid="stMetric"] {
    background: #f1f5f9;
    border-left: 4px solid #cbd5e1;
    border-radius: 12px;
    padding: 12px;
}
[data-testid="stColumn"]:nth-child(5n+1) [data-testid="stMetric"] { background: #eef2ff; border-left-color: #a5b4fc; }
[data-testid="stColumn"]:nth-child(5n+2) [data-testid="stMetric"] { background: #ecfeff; border-left-color: #67e8f9; }
[data-testid="stColumn"]:nth-child(5n+3) [data-testid="stMetric"] { background: #fbf7f0; border-left-color: #d6bc8f; }
[data-testid="stColumn"]:nth-child(5n+4) [data-testid="stMetric"] { background: #f0fdf4; border-left-color: #86efac; }
[data-testid="stColumn"]:nth-child(5n+5) [data-testid="stMetric"] { background: #f8fafc; border-left-color: #94a3b8; }
</style>
""", unsafe_allow_html=True)

ui.panel_filtros()
pagina.run()
