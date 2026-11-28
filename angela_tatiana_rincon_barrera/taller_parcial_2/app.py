"""
Comparador de precios de protectores solares — aplicación Streamlit (Taller 2).

Ejecutar desde la carpeta taller_2/:   streamlit run app.py
"""

import streamlit as st

import componentes as ui
import datos_cache as dc
import db

st.set_page_config(page_title="Comparador de precios de protectores solares", page_icon=":material/wb_sunny:",
                   layout="wide")

if not db.DB_PATH.exists():
    st.error("No se encontró la base comparador_precios.sqlite en la carpeta de la aplicación.")
    st.stop()

try:
    if dc.ultima_corrida() is None:
        st.warning("La base no tiene ejecuciones con datos todavía. Use la página «Actualizar datos».")
    st.session_state["filtros"] = ui.panel_filtros() if dc.ultima_corrida() else db.Filtros()
except Exception:  # mensaje claro en lugar del error técnico
    st.error("No fue posible leer la base de datos. Verifique que el archivo comparador_precios.sqlite "
             "esté completo y vuelva a cargar la página.")
    st.stop()

paginas = st.navigation({
    "Consultar": [
        st.Page("paginas/resumen.py", title="Resumen", icon=":material/dashboard:", default=True),
        st.Page("paginas/productos.py", title="Productos", icon=":material/table_view:"),
        st.Page("paginas/comparables.py", title="Comparables y precio unitario", icon=":material/compare_arrows:"),
    ],
    "Decidir la compra": [
        st.Page("paginas/cambios.py", title="Cambios de precio", icon=":material/trending_up:"),
        st.Page("paginas/canasta.py", title="Canasta", icon=":material/shopping_basket:"),
    ],
    "Datos": [
        st.Page("paginas/actualizar.py", title="Actualizar datos", icon=":material/sync:"),
        st.Page("paginas/calidad.py", title="Origen y calidad", icon=":material/fact_check:"),
    ],
})
paginas.run()
