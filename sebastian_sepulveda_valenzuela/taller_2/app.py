"""
app.py
======
Punto de entrada principal para la aplicación web Streamlit (Taller 2).
Configura la página y la navegación multipágina mediante st.navigation.
"""

import streamlit as st

# Configuración global de la aplicación
st.set_page_config(
    page_title="Comparador de Precios — Aseo del Hogar",
    page_icon="🛒",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Definición de páginas con st.navigation
pg = st.navigation([
    st.Page("paginas/resumen.py", title="Resumen Ejecutivo", icon="📊", default=True),
    st.Page("paginas/explorar.py", title="Explorador de Precios", icon="🔎"),
    st.Page("paginas/cambios.py", title="Cambios de Precio", icon="📈"),
    st.Page("paginas/canasta.py", title="Canasta Familiar de Aseo", icon="🧺"),
    st.Page("paginas/actualizar.py", title="Actualizar Precios", icon="🔄"),
    st.Page("paginas/acerca.py", title="Acerca del Proyecto", icon="ℹ️")
])

# Ejecución de la navegación
pg.run()
