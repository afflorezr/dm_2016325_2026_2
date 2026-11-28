"""Qué precios subieron, bajaron, aparecieron o dejaron de verse entre dos
recolecciones. Se compara el mismo anuncio en el mismo comercio."""

import streamlit as st

import ui

st.title("Cambios de precio entre dos recolecciones")
recs = ui.recolecciones()
if len(recs) < 2:
    st.info("Hacen falta al menos dos recolecciones para comparar precios.")
    st.stop()

etiquetas = {r["recoleccion_id"]: ui.etiqueta_recoleccion(r) for _, r in recs.iterrows()}
ids = list(etiquetas)                     # de la más reciente a la más antigua
c1, c2, c3 = st.columns([2, 2, 1])
b = c1.selectbox("Recolección reciente", ids, index=0, format_func=etiquetas.get)
a = c2.selectbox("Comparar contra", ids, index=1, format_func=etiquetas.get)
umbral = c3.number_input("Umbral de variación grande (%)", min_value=0, max_value=100, value=10, step=5)
if a == b:
    st.warning("Elija dos recolecciones distintas.")
    st.stop()
if a > b:
    a, b = b, a
    st.caption("Se ordenaron las recolecciones de la más antigua a la más reciente.")

st.caption(f"Mismo anuncio en el mismo comercio. Precios en COP. De {etiquetas[a]} a {etiquetas[b]}.")
comercios = st.session_state["filtros"]["comercios"]
conteo = ui.conteo_cambios(a, b, umbral, comercios)
if conteo["anuncios"] == 0:
    ui.sin_datos(None)
    st.stop()

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric("Subieron", conteo["subieron"])
k2.metric("Bajaron", conteo["bajaron"])
k3.metric(f"Variación ≥ {umbral} %", conteo["grandes"])
k4.metric("Nuevos", conteo["nuevos"])
k5.metric("Dejaron de observarse", conteo["dejaron"])

tipos = st.multiselect("Mostrar", ["subió", "bajó", "nuevo", "dejó de observarse", "igual",
                                   "sin precio en una de las dos"],
                       default=["subió", "bajó", "nuevo", "dejó de observarse"])
if not tipos:
    st.info("Elija al menos un tipo de cambio.")
    st.stop()
vista = ui.cambios(a, b, umbral, comercios, tuple(tipos))
if ui.sin_datos(vista, "No hay anuncios de esos tipos."):
    st.stop()
vista = vista.assign(comercio=lambda d: d["comercio"].map(ui.NOMBRES),
                     producto_id=lambda d: d["producto_id"].fillna(""))


def resaltar(fila):
    color = "background-color: #e2e8f0; font-weight: bold" if fila["grande"] == 1 else ""
    return [color] * len(fila)


st.dataframe(
    ui.formato_tabla(vista, con_decimal=["cambio_pct"]).apply(resaltar, axis=1),
    hide_index=True, width="stretch", placeholder="",
    column_order=["comercio", "nombre_original", "producto_id", "precio_a", "precio_b",
                  "cambio_cop", "cambio_pct", "tipo", "url"],
    column_config={
        "comercio": "Comercio", "nombre_original": "Producto", "producto_id": "Comparable",
        "precio_a": "Precio antes (COP)", "precio_b": "Precio después (COP)",
        "cambio_cop": "Cambio (COP)", "cambio_pct": "Cambio (%)",
        "tipo": "Tipo", "url": st.column_config.LinkColumn("Anuncio", display_text="abrir"),
    })
st.caption(f"Resaltadas en gris y negrita: variaciones de {umbral} % o más. Un producto que dejó de observarse no está necesariamente agotado ni retirado: "
           "solo no apareció en esa recolección.")
