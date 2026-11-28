# -*- coding: utf-8 -*-
"""app.py - Punto de entrada de la aplicación Streamlit (comparador de precios, Taller 2).
Ejecutar:  streamlit run app.py"""
import streamlit as st

import datos
import ui

st.set_page_config(page_title="Comparador de precios", page_icon="🧴", layout="wide")
ui.aplicar_estilo()

pagina = st.navigation([
    st.Page("paginas/resumen.py", title="Resumen", default=True),
    st.Page("paginas/cambios.py", title="Cambios de precio"),
    st.Page("paginas/canasta.py", title="Canasta"),
    st.Page("paginas/actualizar.py", title="Actualizar precios"),
])
ui.verificar_base()
st.sidebar.caption(f"Datos al {ui.fecha_de_los_datos()}")
pagina.run()
