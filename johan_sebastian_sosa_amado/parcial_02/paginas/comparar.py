"""Comparar comercios: cómo cambió el precio de un producto, el precio por
unidad de contenido (sin mezclar unidades) y el ahorro en cada producto."""

import plotly.express as px
import streamlit as st

import ui

st.title("Comparar el mismo producto entre comercios")
ui.aviso_fecha()
f = st.session_state["filtros"]
rec = f["recoleccion_id"]
productos = ui.opciones()["productos"]

if ui.sin_datos(productos, "La base todavía no tiene productos comparables."):
    st.stop()

# Evolución del precio
st.subheader("Evolución del precio de un producto")
etiquetas = dict(zip(productos["producto_id"], productos["producto_id"] + ": " + productos["descripcion"]))
elegido = st.selectbox("Producto comparable", list(etiquetas), format_func=etiquetas.get)
serie = ui.visibles(ui.evolucion_producto(elegido))
serie["fecha"] = serie["fecha"].str[:16].str.replace("T", " ")   # hora de Colombia, sin zona
ahorro = ui.ahorro_comparables(rec)
if not ui.sin_datos(serie, "Este producto no tiene precios registrados."):
    # El más barato (con empates) sale de la misma consulta de la tabla de ahorro.
    fila = ahorro[ahorro["producto_id"] == elegido]
    if len(fila):
        donde = ", ".join(ui.NOMBRES.get(c, c) for c in fila.iloc[0]["mas_barato"].split(", "))
        titulo = f"En la recolección elegida es más barato en {donde} ({ui.cop(fila.iloc[0]['minimo'])})"
    else:
        titulo = f"Precio de {elegido} en cada recolección"
    fig = px.line(serie, x="fecha", y="precio", color="comercio", markers=True,
                  color_discrete_map=ui.COLORES_VISIBLES,
                  labels={"fecha": "Fecha de consulta", "precio": "Precio (COP)", "comercio": "Comercio"},
                  title=titulo)
    fig.update_yaxes(tickformat=",.0f")
    # plotly reparte las marcas del eje para que no se monten; solo se da el
    # formato: día/mes/año, o día/mes y hora si el rango es menor a un día.
    fig.update_xaxes(hoverformat="%d/%m/%Y %H:%M",
                     tickformatstops=[dict(dtickrange=[None, 86400000], value="%d/%m %H:%M"),
                                      dict(dtickrange=[86400000, None], value="%d/%m/%Y")])
    st.plotly_chart(ui.estilo(fig), width="stretch")
    st.caption("Un punto por recolección y comercio. Solo hay datos en las fechas en que se ejecutó el scraper.")

st.divider()

# Precio por unidad de contenido
st.subheader("Precio por unidad de contenido")
unidades = [u for u in ["unidad", "mL", "g"] if u in set(productos["unidad"].map({"und": "unidad"}).fillna(productos["unidad"]))]
unidad = st.radio("Unidad (no se mezclan unidades distintas)", unidades or ["unidad"], horizontal=True)
pu = ui.precio_unitario(rec, unidad)
pu = ui.visibles(pu) if len(pu) else pu
if not ui.sin_datos(pu, f"No hay productos comparables medidos en {unidad} en esta recolección."):
    pu["producto"] = pu["producto_id"]
    fig = px.bar(pu, x="producto", y="precio_unitario", color="comercio", barmode="group",
                 color_discrete_map=ui.COLORES_VISIBLES, hover_data=["descripcion", "precio", "contenido_total"],
                 labels={"precio_unitario": f"Precio por {unidad} (COP)", "producto": "Producto comparable",
                         "comercio": "Comercio", "precio": "Precio del paquete (COP)",
                         "contenido_total": f"Contenido ({unidad})"},
                 title=f"Precio por {unidad} de cada producto comparable")
    fig.update_yaxes(tickformat=",.2~f")
    st.plotly_chart(ui.estilo(fig), width="stretch")

st.divider()

# Ahorro por producto
st.subheader("¿Cuánto se ahorra comprando en el comercio más barato?")
if not ui.sin_datos(ahorro, "No hay precios comparables en esta recolección."):
    tabla = ahorro.assign(
        mas_barato=lambda d: d["mas_barato"].str.split(", ").map(lambda l: ", ".join(ui.NOMBRES.get(x, x) for x in l)))
    st.dataframe(ui.formato_tabla(tabla, con_decimal=["ahorro_pct"]), hide_index=True, width="stretch", placeholder="", column_config={
        "producto_id": "Producto", "descripcion": "Descripción",
        "minimo": "Precio mínimo (COP)", "maximo": "Precio máximo (COP)",
        "ahorro_cop": "Ahorro (COP)", "ahorro_pct": "Ahorro (%)",
        "mas_barato": "Más barato en (empates incluidos)",
    })
