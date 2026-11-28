import plotly.express as px
import streamlit as st

import db
from comun import COLORES, ETIQUETA, aviso_fallidas, elegir_ejecucion, numero, pesos

st.title("Comparar precios")
st.caption("Presentaciones comparables: el mismo producto (mismo código de barras) en los tres comercios.")
productos = db.comparables()
if productos.empty:
    st.warning("La base no tiene productos comparables.")
    st.stop()

st.subheader("Evolución del precio")
nombres = dict(zip(productos["id_producto_comun"], productos["producto"]))
elegido = st.selectbox("Producto", list(nombres), format_func=nombres.get)
datos = db.evolucion(elegido)
if datos.empty:
    st.warning("Este producto no tiene precios en la base.")
else:
    datos["comercio"] = datos["comercio"].map(ETIQUETA)
    fig = px.line(datos, x="fecha_consulta", y="precio", color="comercio", markers=True,
                  color_discrete_map=COLORES,
                  labels={"fecha_consulta": "Fecha y hora de consulta", "precio": "Precio (COP)", "comercio": "Comercio"})
    fig.update_layout(yaxis_tickformat=",.0f")
    st.plotly_chart(fig)

st.subheader("Precio por unidad de contenido")
id_ej = elegir_ejecucion("Ejecución", "c_ejecucion")
aviso_fallidas(id_ej)
unidad = st.radio("Unidad", ["g", "ml", "und"], horizontal=True,
                  format_func={"g": "gramo", "ml": "mililitro", "und": "unidad"}.get)
datos = db.precio_unidad_comparables(id_ej, unidad)
if datos.empty:
    st.warning("No hay presentaciones comparables con esa unidad en la ejecución elegida.")
else:
    datos["comercio"] = datos["comercio"].map(ETIQUETA)
    fig = px.bar(datos, x="precio_unidad", y="producto", color="comercio", barmode="group", orientation="h",
                 color_discrete_map=COLORES,
                 labels={"precio_unidad": f"COP por {unidad}", "producto": "", "comercio": "Comercio"})
    st.plotly_chart(fig)

st.subheader("¿En qué comercio conviene comprar cada presentación?")
ahorro = db.ahorro_comparables(id_ej)
if ahorro.empty:
    st.warning("Se necesitan al menos dos comercios con precio para calcular el ahorro.")
else:
    ahorro["comprar_en"] = ahorro["comprar_en"].map(lambda x: ", ".join(ETIQUETA[c] for c in x.split(", ")))
    ahorro = ahorro.sort_values("ahorro_pct")
    ahorro["texto"] = [f"{numero(p, 1)} % ({pesos(c)})" for p, c in zip(ahorro["ahorro_pct"], ahorro["ahorro_cop"])]
    fig = px.bar(ahorro, x="ahorro_pct", y="producto", color="comprar_en", orientation="h", text="texto",
                 color_discrete_map=COLORES,
                 labels={"ahorro_pct": "Ahorro frente al comercio más caro (%)", "producto": "",
                         "comprar_en": "Comercio más barato"})
    st.plotly_chart(fig)
