# -*- coding: utf-8 -*-
"""Página Cambios de precio: compara dos ejecuciones (mismo anuncio, mismo comercio)."""
import plotly.express as px
import streamlit as st

import datos
import ui

ui.verificar_base()
v = datos.version()
st.title("Cambios de precio entre ejecuciones")

ej = datos.ejecuciones(v)
if len(ej) < 2:
    st.info("Se necesitan al menos dos ejecuciones válidas para comparar precios entre fechas.")
    st.stop()

etiqueta = {r.id_ejecucion: f"{ui.fecha_legible(r.fecha_inicio)} · {r.id_ejecucion}" for r in ej.itertuples()}
ids = list(etiqueta)
c1, c2 = st.columns(2)
antes = c1.selectbox("Ejecución anterior", ids, index=1, format_func=etiqueta.get)
despues = c2.selectbox("Ejecución nueva", ids, index=0, format_func=etiqueta.get)
if antes == despues:
    st.warning("Elige dos ejecuciones distintas.")
    st.stop()
fechas = dict(zip(ej.id_ejecucion, ej.fecha_inicio))
if fechas[antes] > fechas[despues]:
    antes, despues = despues, antes
    st.caption("Se ordenaron las ejecuciones de la más antigua a la más reciente.")
umbral = st.slider("Resaltar variaciones de al menos (%)", 1, 50, 10)

r = datos.cambios(antes, despues, float(umbral), v)
cam, nue, nob = r["cambios"], r["nuevos"], r["no_observados"]
k = st.columns(4)
ui.tarjeta(k[0], "Subieron", str(int((cam.variacion_cop > 0).sum())), "anuncios con precio mayor")
ui.tarjeta(k[1], "Bajaron", str(int((cam.variacion_cop < 0).sum())), "anuncios con precio menor")
ui.tarjeta(k[2], "Productos nuevos", str(len(nue)), "aparecen solo en la ejecución nueva")
ui.tarjeta(k[3], "Dejaron de observarse", str(len(nob)), "no implica que estén agotados o retirados")
st.caption("Se compara el mismo anuncio en el mismo comercio, y solo en comercios con datos válidos en ambas ejecuciones. "
           f"Variación grande: {umbral} % o más.")

tc, tn, to = st.tabs(["Cambios de precio", "Productos nuevos", "Dejaron de observarse"])
with tc:
    if cam.empty:
        ui.sin_datos("No hubo cambios de precio entre estas dos ejecuciones.")
    else:
        top = cam.head(15).copy()
        top["producto_corto"] = top.producto.str.slice(0, 45)
        fig = px.bar(top, x="variacion_pct", y="producto_corto", color="comercio", orientation="h", color_discrete_map=ui.COLORES,
                     labels={"variacion_pct": "Variación (%)", "producto_corto": ""})
        fig.update_yaxes(autorange="reversed")
        ui.mostrar_grafico(ui.formato_figura(fig, "Mayores variaciones de precio", f"% sobre el precio anterior · {len(cam)} cambios en total", alto=560))
        vista = cam.copy()
        vista["variacion_grande"] = vista.variacion_grande.map({1: "Sí", 0: ""})
        ui.mostrar_tabla(vista, hide_index=True, column_config={
            "comercio": "Comercio", "producto": "Producto", "marca": "Marca",
            "precio_antes": st.column_config.NumberColumn("Precio anterior (COP)", format="$ %d"),
            "precio_despues": st.column_config.NumberColumn("Precio nuevo (COP)", format="$ %d"),
            "variacion_cop": st.column_config.NumberColumn("Variación (COP)", format="$ %d"),
            "variacion_pct": st.column_config.NumberColumn("Variación (%)", format="%.1f"),
            "variacion_grande": "Grande", "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir")})
with tn:
    ui.mostrar_tabla(nue, hide_index=True) if len(nue) else ui.sin_datos("No hay productos nuevos.")
with to:
    ui.mostrar_tabla(nob, hide_index=True) if len(nob) else ui.sin_datos("Todos los productos anteriores se siguen observando.")
