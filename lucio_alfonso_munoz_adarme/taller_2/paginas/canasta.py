import streamlit as st

import db
from comun import ETIQUETA, aviso_fallidas, elegir_ejecucion, pesos

st.title("Canasta")
st.caption("Elija productos comparables y la cantidad de cada uno. Todos los precios son de la misma ejecución, en COP.")

id_ej = elegir_ejecucion("Ejecución", "k_ejecucion")
aviso_fallidas(id_ej)
productos = db.comparables()
nombres = dict(zip(productos["id_producto_comun"], productos["producto"]))
elegidos = st.multiselect("Productos", list(nombres), format_func=nombres.get, filter_mode=None)
if not elegidos:
    st.info("Elija al menos un producto.")
    st.stop()

cantidades = tuple((p, st.number_input(nombres[p], 1, 20, 1, key=f"n_{p}")) for p in elegidos)
por_comercio, minimo = db.canasta(id_ej, cantidades)

st.subheader("Costo por comercio")
for r in por_comercio.itertuples():
    if r.total is not None and r.total == r.total:
        st.write(f"**{ETIQUETA[r.comercio]}:** {pesos(r.total)}")
    else:
        st.write(f"**{ETIQUETA[r.comercio]}:** no se calcula, le falta{'n' if r.faltan > 1 else ''} {r.faltan} de los {len(elegidos)} productos "
                 "en esta ejecución.")

st.subheader("Comprando cada producto donde es más barato")
completos = por_comercio.dropna(subset=["total"])
if minimo is None or minimo != minimo:
    st.warning("Algún producto no tiene precio en ningún comercio en esta ejecución.")
else:
    st.metric("Costo mínimo", pesos(minimo), border=True)
    for r in completos.itertuples():
        st.write(f"Ahorro frente a comprar todo en {ETIQUETA[r.comercio]}: {pesos(r.total - minimo)}")
    if completos.empty:
        st.write("Ningún comercio tiene todos los productos, así que no hay con qué comparar el ahorro.")

