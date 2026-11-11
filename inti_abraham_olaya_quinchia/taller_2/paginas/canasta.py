"""paginas/canasta.py - Canasta de productos comparables: costo por comercio y canasta ideal."""

import pandas as pd
import streamlit as st

import analisis
import db

DB = db.DB_PATH


def cop(v):
    return "—" if v is None or pd.isna(v) else "$" + f"{v:,.0f}".replace(",", ".")


st.title("Canasta de productos")
ejec = db.obtener_ejecuciones(DB)
if ejec.empty:
    st.info("Aún no hay ejecuciones con datos.")
    st.stop()

etiqueta = {r.corrida_id: f"{str(r.fecha)[:16].replace('T', ' ')} · {r.corrida_id}" for r in ejec.itertuples()}
corrida = st.selectbox("Ejecución (todos los precios son de la misma ejecución)", list(etiqueta),
                       format_func=etiqueta.get)
precios = db.obtener_precios_canasta(DB, corrida)
if precios.empty:
    st.info("Esa ejecución no tiene precios de productos comparables.")
    st.stop()

prods = precios.drop_duplicates("producto_id")
nombres = {r.producto_id: analisis.etiqueta_producto(r) for r in prods.itertuples()}
elegidos = st.multiselect("Productos comparables", list(nombres), format_func=nombres.get)
if not elegidos:
    st.info("Elige uno o más productos para armar la canasta.")
    st.stop()

st.write("Cantidad de cada producto")
cols = st.columns(min(len(elegidos), 3))
cantidades = {p: cols[i % len(cols)].number_input(nombres[p], min_value=1, max_value=99, value=1, step=1,
                                                  key=f"cant_{p}") for i, p in enumerate(elegidos)}

res = analisis.calcular_canasta(precios, cantidades)

# ----------------------------------------------------------------------------
# Costo de la canasta en cada comercio (solo si tiene TODOS los productos)
# ----------------------------------------------------------------------------
st.subheader("Costo por comercio")
tot = res["totales"]
cols = st.columns(max(len(tot), 1))
for col, r in zip(cols, tot.itertuples()):
    if r.completo:
        col.metric(r.comercio, cop(r.costo))
    else:
        col.metric(r.comercio, "Incompleta")
        col.warning("Le falta: " + ", ".join(nombres.get(p, str(p)) for p in r.faltantes))
if not tot["completo"].any():
    st.error("Ningún comercio tiene todos los productos elegidos, así que no hay un total comparable por comercio.")

# ----------------------------------------------------------------------------
# Canasta ideal (cada producto donde es más barato)
# ----------------------------------------------------------------------------
st.subheader("Canasta ideal")
if res["sin_precio"]:
    st.warning("No se puede calcular: sin precio en ningún comercio para " +
               ", ".join(nombres.get(p, str(p)) for p in res["sin_precio"]) + ".")
else:
    ideal = res["ideal"]
    st.metric("Costo mínimo comprando cada producto donde es más barato", cop(res["costo_ideal"]))
    comp = res["ahorro_vs_completos"]
    if comp.empty:
        st.info("Sin un comercio con la canasta completa no hay una compra en un solo lugar con qué comparar.")
    else:
        mejor = comp.sort_values("costo").iloc[0]
        st.success(f"Ahorro frente al comercio completo más barato ({mejor['comercio']}): "
                   f"{cop(mejor['ahorro_cop'])} ({mejor['ahorro_pct']:.1f} %).")
        st.dataframe(comp.rename(columns={"comercio": "Comprando todo en", "costo": "Costo (COP)",
                                          "ahorro_cop": "Ahorro con canasta ideal (COP)",
                                          "ahorro_pct": "Ahorro (%)"}),
                     hide_index=True, use_container_width=True, column_config={
                         "Costo (COP)": st.column_config.NumberColumn(format="$ %d"),
                         "Ahorro con canasta ideal (COP)": st.column_config.NumberColumn(format="$ %d"),
                         "Ahorro (%)": st.column_config.NumberColumn(format="%.1f %%")})
    detalle = ideal.assign(Producto=ideal["producto_id"].map(nombres))[
        ["Producto", "comercio_mas_barato", "precio", "cantidad", "subtotal"]]
    st.dataframe(detalle.rename(columns={"comercio_mas_barato": "Dónde comprarlo", "precio": "Precio unitario (COP)",
                                         "cantidad": "Cantidad", "subtotal": "Subtotal (COP)"}),
                 hide_index=True, use_container_width=True, column_config={
                     "Precio unitario (COP)": st.column_config.NumberColumn(format="$ %d"),
                     "Subtotal (COP)": st.column_config.NumberColumn(format="$ %d")})
    st.caption("Si hay empate de precio mínimo, se listan los comercios empatados.")

st.warning("El resultado no incluye envío, mínimos de compra ni las condiciones de las promociones. "
           "Los precios son los de la ejecución elegida y pueden haber cambiado.")
