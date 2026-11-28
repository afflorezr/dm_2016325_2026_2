"""Canasta: cuánto cuesta en cada comercio, con precios de una misma
recolección, y cuánto se ahorra comprando cada producto donde es más barato."""

import pandas as pd
import streamlit as st

import ui

st.title("Canasta de productos")
ui.aviso_fecha()
rec = st.session_state["filtros"]["recoleccion_id"]
productos = ui.opciones()["productos"]
if ui.sin_datos(productos, "La base todavía no tiene productos comparables."):
    st.stop()

st.write("Escriba la cantidad de cada producto comparable que quiere comprar.")
editor = st.data_editor(
    productos.assign(cantidad=0)[["producto_id", "descripcion", "cantidad"]],
    hide_index=True, width="stretch", placeholder="", disabled=["producto_id", "descripcion"],
    column_config={"producto_id": "Producto", "descripcion": "Descripción",
                   "cantidad": st.column_config.NumberColumn("Cantidad", min_value=0, max_value=50, step=1)})
cantidades = tuple((r.producto_id, int(r.cantidad)) for r in editor.itertuples() if r.cantidad and r.cantidad > 0)
if not cantidades:
    st.info("Elija al menos un producto.")
    st.stop()

por_comercio, por_producto = ui.canasta(rec, cantidades)
resumen = ui.db.resumen_canasta(por_comercio, por_producto)

st.subheader("Costo de la canasta en cada comercio")
columnas = st.columns(len(por_comercio))
for col, fila in zip(columnas, por_comercio.itertuples()):
    nombre = ui.NOMBRES.get(fila.comercio, fila.comercio)
    if pd.isna(fila.total):
        col.metric(nombre, "sin total")
        col.warning(f"No se calcula el total porque le faltan productos: {fila.faltantes}.")
    else:
        col.metric(nombre, f"{ui.cop(fila.total)} COP")

st.subheader("Comprando cada producto donde es más barato")
if resumen is None:
    st.warning("Algún producto no tiene precio en ningún comercio en esta recolección; no se calcula el costo mínimo.")
else:
    c1, c2 = st.columns(2)
    c1.metric("Costo mínimo", f"{ui.cop(resumen['costo_minimo'])} COP")
    if resumen["mejor_comercio"]:
        c2.metric(f"Ahorro frente a comprar todo en {ui.NOMBRES[resumen['mejor_comercio']]}",
                  f"{ui.cop(resumen['ahorro_vs_mejor'])} COP",
                  f"{ui.cop(resumen['ahorro_vs_peor'])} frente a {ui.NOMBRES[resumen['peor_comercio']]}",
                  delta_color="off", delta_arrow="off")
    st.dataframe(ui.formato_tabla(por_producto.assign(donde=lambda d: d["donde"].fillna("").str.split(", ")
                                  .map(lambda l: ", ".join(ui.NOMBRES.get(x, x) for x in l if x)))),
                 hide_index=True, width="stretch", placeholder="", column_config={
                     "producto_id": "Producto", "descripcion": "Descripción", "cantidad": "Cantidad",
                     "precio_minimo": "Precio mínimo (COP)", "subtotal": "Subtotal (COP)",
                     "donde": "Dónde (empates incluidos)"})

st.caption("El resultado no incluye costos de envío, mínimos de compra ni las condiciones de las promociones.")
