"""
app.py - Punto de entrada de la aplicación (Streamlit multipágina).
Ejecutar:  streamlit run app.py
"""
import streamlit as st

st.set_page_config(page_title="Comparador de precios · Cuidado del bebé", page_icon="🧷", layout="wide")

import servicios as sv  # noqa: E402  (set_page_config debe ser la primera llamada de Streamlit)
import ui_filtros  # noqa: E402

if not sv.base_disponible():
    st.title("Comparador de precios · Cuidado del bebé")
    st.error("No se encontró una base de datos válida (`comparador_precios.sqlite`). Colócala junto a `app.py` "
             "y recarga la página.")
    st.stop()

paginas = [
    st.Page("paginas/resumen.py", title="Resumen", icon="📊", default=True),
    st.Page("paginas/productos.py", title="Productos", icon="🧾"),
    st.Page("paginas/vista_graficos.py", title="Gráficos", icon="📈"),
    st.Page("paginas/cambios.py", title="Cambios de precio", icon="🔄"),
    st.Page("paginas/canasta.py", title="Canasta", icon="🛒"),
    st.Page("paginas/actualizar.py", title="Actualizar datos", icon="⬇️"),
    st.Page("paginas/origen.py", title="Origen de los datos", icon="🔎"),
]
pagina = st.navigation(paginas)
ui_filtros.panel_lateral()
pagina.run()
