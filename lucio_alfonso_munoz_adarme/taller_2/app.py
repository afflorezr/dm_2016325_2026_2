import streamlit as st

st.set_page_config(page_title="Comparador de precios de nutrición deportiva",  layout="wide")

pagina = st.navigation([
    st.Page("paginas/resumen.py", title="Resumen", default=True),
    st.Page("paginas/productos.py", title="Productos"),
    st.Page("paginas/comparar.py", title="Comparar precios"),
    st.Page("paginas/cambios.py", title="Cambios de precio"),
    st.Page("paginas/canasta.py", title="Canasta"),
    st.Page("paginas/actualizar.py", title="Actualizar precios"),
])
pagina.run()
