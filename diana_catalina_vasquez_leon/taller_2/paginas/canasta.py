# -*- coding: utf-8 -*-
"""Página Canasta: costo por comercio (solo si tiene todos los productos) y costo mínimo comprando donde es más barato."""
import plotly.express as px
import streamlit as st

import datos
import db
import ui

ui.verificar_base()
v = datos.version()
st.title("Canasta de productos")

ej = datos.ejecuciones_comparables(v)
if ej.empty:
    st.info("Aún no hay productos comparables con precios en una ejecución válida.")
    st.stop()
etiqueta = {r.id_ejecucion: f"{ui.fecha_legible(r.fecha_consulta)} · {r.id_ejecucion}" for r in ej.itertuples()}
ejec = st.selectbox("Ejecución (los precios de la canasta salen de una misma ejecución)", list(etiqueta), format_func=etiqueta.get)
precios = datos.precios_comparables(ejec, v)

cat = precios.drop_duplicates("id_producto_comun").set_index("id_producto_comun")
nombre = {i: f"{r.marca_estandar} {r.nombre_estandar} ({r.contenido_num:g} {r.unidad})" for i, r in cat.iterrows()}
elegidos = st.multiselect("Productos de la canasta", list(nombre), default=list(nombre)[:3], format_func=nombre.get)
if not elegidos:
    st.info("Elige al menos un producto.")
    st.stop()
cols = st.columns(min(len(elegidos), 3))
cantidades = {}
for n, i in enumerate(elegidos):
    cantidades[i] = cols[n % len(cols)].number_input(nombre[i], min_value=1, max_value=20, value=1, step=1, key=f"q_{i}")

r = db.calcular_canasta(precios, cantidades)
tot = r["totales"].copy()

st.subheader("Costo por comercio")
if not tot.completa.any():
    st.warning("Ningún comercio tiene todos los productos elegidos: no se muestra un total incompleto.")
tot["Total (COP)"] = tot.total.map(lambda x: ui.cop(x) if x == x and x is not None else "Incompleta")
tot["Falta"] = tot.faltan.map(lambda f: ", ".join(nombre[i] for i in f) if f else "")
ui.mostrar_tabla(tot[["comercio", "Total (COP)", "Falta"]].rename(columns={"comercio": "Comercio"}), hide_index=True)
ok = tot[tot.completa]
if len(ok):
    fig = px.bar(ok, x="comercio", y="total", color="comercio", color_discrete_map=ui.COLORES, text=ok.total.map(ui.cop),
                 labels={"total": "Total (COP)", "comercio": ""})
    fig.update_traces(textposition="outside")
    ui.mostrar_grafico(ui.formato_figura(fig, "Costo de la canasta por comercio", f"COP · solo comercios con todos los productos · ejecución {ejec}", alto=400))

st.subheader("Comprando cada producto donde es más barato")
if r["sin_precio"]:
    st.warning("No se calcula el costo mínimo: no hay precio de " + ", ".join(nombre[i] for i in r["sin_precio"]) + " en esta ejecución.")
else:
    m = st.columns(3)
    ui.tarjeta(m[0], "Costo mínimo", ui.cop(r["total_optimo"]), "comprando en varios comercios")
    ui.tarjeta(m[1], "Mejor comercio único", r["mejor_comercio_unico"] or "—", "el más barato con todos los productos" if r["mejor_comercio_unico"] else "ninguno tiene todos")
    ui.tarjeta(m[2], "Ahorro vs. un solo comercio",
               f"{ui.cop(r['ahorro_cop'])} ({ui.num(r['ahorro_pct'])} %)" if r["ahorro_cop"] is not None else "—",
               "frente a comprar todo en el mejor comercio único")
    o = r["optima"].copy()
    o["Producto"] = o.id_producto_comun.map(nombre)
    ui.mostrar_tabla(o[["Producto", "comercio", "precio", "cantidad", "subtotal"]], hide_index=True, column_config={
        "comercio": "Comprar en", "precio": st.column_config.NumberColumn("Precio unitario (COP)", format="$ %d"),
        "cantidad": "Cantidad", "subtotal": st.column_config.NumberColumn("Subtotal (COP)", format="$ %d")})
st.warning("El resultado no incluye costos de envío, mínimos de compra ni las condiciones de las promociones. "
           "Los precios corresponden al momento de la captura.")
