"""
paginas/comparar.py — Taller 2: página "Productos comparables".

Los 18 productos con el mismo EAN en los tres comercios (comparables.py, Taller 1):
  * gráfico 1: evolución del precio de un comparable elegido, una serie por comercio (§7.4.1);
  * gráfico 2: precio por unidad de contenido (COP por mL o por g), sin mezclar unidades (§7.4.2, §8.1);
  * gráfico 4 (libre): ¿en qué comercio conviene comprar? (§7.4.4; justificación en el README).
Esta página usa sus propios selectores (producto, ejecución, unidad); los filtros del panel lateral aplican a las
páginas Resumen y Cambios de precio. Sin SQL.
"""
import plotly.express as px
import streamlit as st

import componentes as cp

st.title("Productos comparables")
st.write("Presentaciones idénticas (mismo código de barras EAN y mismo contenido) que venden los tres comercios. "
         "Son la base justa para comparar precios.")
st.caption("Esta página usa sus propios selectores; los filtros del panel lateral no se aplican aquí.")

comparables = cp.obtener("listar_comparables")
ejecuciones = cp.obtener("listar_ejecuciones")
if comparables is None or ejecuciones is None or comparables.empty:
    cp.sin_datos("No hay productos comparables en la base.")
    st.stop()
nombres = dict(zip(comparables["id_producto_comun"],
                   comparables["producto"].str.title() + " · " + comparables["contenido"].map("{:g}".format)
                   + " " + comparables["unidad_norm"]))

# [CAMBIO]: gráfico 1: evolución del precio de un producto comparable, una serie por comercio.
st.subheader("1 · Evolución del precio")
elegido = st.selectbox("Producto comparable", list(nombres), format_func=nombres.get)
evolucion = cp.obtener("evolucion_precio", elegido)
if evolucion is None or evolucion.empty:
    cp.sin_datos("Este producto no tiene observaciones de precio.")
else:
    evolucion = evolucion.assign(fecha=evolucion["fecha_hora_consulta"].str[:16].str.replace("T", " "))
    grafico = px.line(evolucion, x="fecha", y="precio", color="comercio", markers=True,
                      color_discrete_map=cp.mapa_colores(), category_orders={"comercio": cp.ORDEN_COMERCIOS},
                      hover_data={"precio": ":,.0f", "estado_disponibilidad": True},
                      labels={"fecha": "Fecha y hora de consulta", "precio": "Precio (COP)", "comercio": "Comercio",
                              "estado_disponibilidad": "Disponibilidad"},
                      title=f"{nombres[elegido]} · precio en COP por ejecución")
    grafico.update_xaxes(type="category")
    st.plotly_chart(grafico, width="stretch")
    id_reciente = ejecuciones["id_ejecucion"].max()
    vistos = set(evolucion.loc[evolucion["id_ejecucion"] == id_reciente, "comercio"])
    faltan = [c for c in cp.ORDEN_COMERCIOS if c not in vistos]
    if faltan:
        st.warning(f"En la última ejecución este producto no apareció en: {', '.join(faltan)} "
                   "(no observado: no significa agotado ni retirado).")
    st.caption(f"{evolucion['id_ejecucion'].nunique()} ejecuciones, del {cp.formato_fecha(evolucion['id_ejecucion'].min())} "
               f"al {cp.formato_fecha(evolucion['id_ejecucion'].max())}.")

# [CAMBIO]: gráfico 2: precio por unidad (COP/mL o COP/g) de una ejecución; nunca se mezclan unidades.
st.subheader("2 · Precio por unidad de contenido")
col_a, col_b = st.columns(2)
id_ejecucion = col_a.selectbox("Ejecución", list(ejecuciones["id_ejecucion"]), format_func=cp.formato_fecha,
                               key="ejecucion_unitario")
unidades = sorted(comparables["unidad_norm"].dropna().unique())
unidad = col_b.radio("Unidad", unidades, horizontal=True,
                     help="Solo se comparan productos con la misma unidad (mL con mL, g con g).")
unitario = cp.obtener("precio_unitario_comparables", id_ejecucion, unidad)
if unitario is None or unitario.empty:
    cp.sin_datos(f"No hay comparables medidos en {unidad} en esa ejecución.")
else:
    unitario = unitario.assign(producto=unitario["producto"].str.title().str[:40])
    grafico = px.bar(unitario, x="producto", y="precio_unitario", color="comercio", barmode="group",
                     color_discrete_map=cp.mapa_colores(), category_orders={"comercio": cp.ORDEN_COMERCIOS},
                     hover_data={"precio": ":,.0f", "contenido": True, "precio_unitario": ":,.2f"},
                     labels={"producto": "Producto", "precio_unitario": f"Precio por {unidad} (COP/{unidad})",
                             "comercio": "Comercio", "precio": "Precio (COP)",
                             "contenido": f"Contenido ({unidad})"},
                     title=f"Precio por {unidad} (COP/{unidad}) · ejecución del {cp.formato_fecha(id_ejecucion)}")
    grafico.update_xaxes(tickangle=-35)
    st.plotly_chart(grafico, width="stretch")
    st.caption(f"Precio por {unidad} = precio ÷ contenido total de la presentación. Si falta una barra, el "
               "producto no se observó en ese comercio en esa ejecución.")

# [CAMBIO]: gráfico 4 (libre): ¿en qué comercio conviene comprar la mayoría de los comparables?
st.subheader("3 · ¿En qué comercio conviene comprar?")
st.write("Pregunta del consumidor: *si solo voy a una tienda, ¿cuál tiene el precio más bajo en más productos "
         "comparables?* Se cuenta en cuántos productos disponibles cada comercio tiene el precio mínimo "
         "(en un empate cuenta para todos los empatados).")
id_libre = st.selectbox("Ejecución", list(ejecuciones["id_ejecucion"]), format_func=cp.formato_fecha,
                        key="ejecucion_libre")
conteo = cp.obtener("veces_mas_barato", id_libre)
ahorro = cp.obtener("ahorro_por_comparable", id_libre)
if conteo is None or conteo.empty:
    cp.sin_datos("No hay comparables disponibles en esa ejecución.")
else:
    grafico = px.bar(conteo, x="comercio", y="n_productos_mas_barato", color="comercio", text="n_productos_mas_barato",
                     color_discrete_map=cp.mapa_colores(), category_orders={"comercio": cp.ORDEN_COMERCIOS},
                     labels={"comercio": "Comercio", "n_productos_mas_barato": "Productos con el precio más bajo"},
                     title=f"Número de comparables en que cada comercio es el más barato · "
                           f"ejecución del {cp.formato_fecha(id_libre)}")
    grafico.update_layout(showlegend=False)
    st.plotly_chart(grafico, width="stretch")
if ahorro is not None and len(ahorro):
    st.dataframe(ahorro[["producto", "precio_min", "precio_max", "ahorro_cop", "ahorro_pct", "donde_mas_barato",
                         "donde_mas_caro", "n_comercios"]],
                 hide_index=True, width="stretch",
                 column_config={
                     "producto": "Producto",
                     "precio_min": st.column_config.NumberColumn("Precio mínimo (COP)", format="$ %,.0f"),
                     "precio_max": st.column_config.NumberColumn("Precio máximo (COP)", format="$ %,.0f"),
                     "ahorro_cop": st.column_config.NumberColumn("Ahorro (COP)", format="$ %,.0f"),
                     "ahorro_pct": st.column_config.NumberColumn("Ahorro (%)", format="%.1f %%"),
                     "donde_mas_barato": "Más barato en", "donde_mas_caro": "Más caro en",
                     "n_comercios": "Comercios con el producto disponible"})
    st.caption("Ahorro = precio máximo − precio mínimo entre comercios para el mismo producto, en la misma "
               "ejecución. Solo productos disponibles.")
