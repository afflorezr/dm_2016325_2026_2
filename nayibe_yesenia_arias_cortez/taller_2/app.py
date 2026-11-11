"""
app.py — Taller 2 Minería de Datos (UNAL): comparador de precios de cuidado capilar.

Punto de entrada de la aplicación Streamlit (navegación multipágina con st.navigation, §7.1).
Arma el panel lateral (filtros compartidos y fecha de los datos) y ejecuta la página elegida.
Este archivo no contiene SQL: los datos llegan por componentes.py → db.py.

Ejecutar desde taller_2/:   streamlit run app.py
"""
import streamlit as st

import componentes

# [CAMBIO]: configuración general y páginas de la aplicación.
st.set_page_config(page_title="Comparador de precios · Cuidado capilar", page_icon="🧴", layout="wide")

PAGINAS = [
    st.Page("paginas/resumen.py", title="Resumen", icon="📊", default=True),
    st.Page("paginas/comparar.py", title="Productos comparables", icon="⚖️"),
    st.Page("paginas/cambios.py", title="Cambios de precio", icon="📈"),
    st.Page("paginas/canasta.py", title="Canasta", icon="🧺"),
    st.Page("paginas/actualizar.py", title="Actualizar precios", icon="🔄"),
]
pagina = st.navigation(PAGINAS)

# [CAMBIO]: fecha de la última ejecución siempre visible (§14): los precios son los del momento de la captura.
ultima = componentes.obtener("ultima_ejecucion")
if ultima is not None and len(ultima):
    estados = ", ".join(f"{r.comercio}: {r.estado}" for r in ultima.itertuples())
    st.sidebar.caption(f"**Datos al {componentes.formato_fecha(ultima['fecha_hora_inicio'].min())}** "
                       f"(última ejecución). {estados}. Precios en pesos colombianos (COP), con IVA, tal como los "
                       "publica cada sitio.")

# [CAMBIO]: filtros del panel lateral, compartidos por las páginas (cada página indica cuáles usa).
st.session_state["filtros"] = componentes.filtros_laterales()

pagina.run()
