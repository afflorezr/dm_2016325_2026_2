"""
app.py — Comparador de precios de antiinfecciosos de uso sistémico (Taller 2).

Ejecutar desde la carpeta taller_2:
    streamlit run app.py

Organización (Módulo 7):
    app.py        este archivo: configuración y navegación entre páginas (sin SQL)
    paginas/      una página por sección de la aplicación
    interfaz.py   colores, formatos, filtros de la barra lateral y mensajes (sin SQL)
    db.py         capa de acceso a datos: todas las consultas SQL
    scraper.py    extracción (Taller 1, ampliado) y guardado en la base
    validacion.py reglas de validación antes de insertar (pandera)
"""
import streamlit as st

import interfaz

st.set_page_config(page_title="Comparador de precios · antiinfecciosos", page_icon=":material/medication:",
                   layout="wide")

PAGINAS_CON_FILTROS = {"Resumen", "Productos"}

pagina = st.navigation({
    "Consultar": [
        st.Page("paginas/resumen.py", title="Resumen", icon=":material/dashboard:", default=True),
        st.Page("paginas/productos.py", title="Productos", icon=":material/table_view:"),
        st.Page("paginas/cambios.py", title="Cambios de precio", icon=":material/trending_up:"),
        st.Page("paginas/canasta.py", title="Canasta", icon=":material/shopping_cart:"),
    ],
    "Datos": [
        st.Page("paginas/actualizar.py", title="Actualizar precios", icon=":material/sync:"),
        st.Page("paginas/datos.py", title="Calidad de los datos", icon=":material/fact_check:"),
    ],
})

# Los filtros se dibujan aquí (y no en cada página) para que se conserven al pasar
# de Resumen a Productos y viceversa.
st.session_state["filtros"] = None
if pagina.title in PAGINAS_CON_FILTROS:
    with interfaz.protegido():
        st.session_state["filtros"] = interfaz.filtros_barra_lateral()

st.sidebar.caption("Datos: La Rebaja Virtual, Locatel y Droguerías Cafam. Taller 2 de Minería "
                   "de Datos, UNAL 2026-2.")
pagina.run()
