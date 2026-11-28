import plotly.express as px
import streamlit as st

import componentes as ui
import datos_cache as dc

f = st.session_state["filtros"]
st.title("Resumen de precios")
st.caption(f"Periodo: **{ui.descripcion_periodo(f)}**. Indicadores calculados sobre los productos que cumplen los filtros del panel lateral.")

ind = dc.indicadores(f)
if not ind["observaciones"]:
    ui.sin_datos()
    st.stop()

id_analisis = ui.corrida_de_analisis(f)
ultima = dc.ultima_corrida()
ahorro = dc.ahorro_por_producto(id_analisis, f.comercios)
cambios = dc.cambios_ultima()

c1, c2, c3, c4 = st.columns(4)
with c1:
    ui.tarjeta("Productos observados", ui.numero(ind["productos"]),
               f"Anuncios distintos (comercio + SKU) · {ui.numero(ind['observaciones'])} observaciones")
with c2:
    ui.tarjeta("Productos en promoción", f"{ui.numero(ind['pct_promocion'], 1)} %",
               "Precio actual menor que el precio de lista · % de observaciones")
with c3:
    ui.tarjeta("Precio mediano", ui.cop(ind["mediana_precio"]), "COP por presentación (empaque)")
with c4:
    ui.tarjeta("Agotados según el sitio", f"{ui.numero(ind['pct_agotados'], 1)} %", "% de observaciones del periodo")

c5, c6, c7 = st.columns([1.3, 1, 1])
with c5:
    if ahorro.empty:
        ui.tarjeta("Ahorro máximo entre comercios", "—", "Se necesitan comparables en al menos dos comercios")
    else:
        top = ahorro.iloc[0]
        ui.tarjeta("Ahorro máximo entre comercios", ui.cop(top["ahorro_cop"]),
                   f"COP · {top['nombre_estandar']} ({ui.numero(top['ahorro_pct'], 1)} %): más barato en "
                   f"{top['mas_barato_en']} · Ejecución {id_analisis} · sin agotados")
with c6:
    if cambios["n"] is None:
        ui.tarjeta("Cambios de precio en la última ejecución", "—",
                   "Se necesita una segunda ejecución para comparar precios")
    else:
        ui.tarjeta("Cambios de precio en la última ejecución", ui.numero(cambios["n"]),
                   f"Anuncios con precio distinto · ejecución {cambios['id_b']} frente a {cambios['id_a']}")
with c7:
    ui.tarjeta("Última ejecución con datos", ui.fecha(ultima["fecha_datos"], con_hora=False),
               f"{ui.fecha(ultima['fecha_datos'])[-5:]} h · Estado: {ui.ETIQUETAS_ESTADO.get(ultima['estado'], ultima['estado'])} · "
               f"ejecución {int(ultima['id_corrida'])} · "
               f"{ui.numero(ultima['n_observaciones'])} observaciones")

st.subheader("Por comercio")
por_com = ind["por_comercio"].rename(columns={"comercio": "Comercio", "productos": "Productos (anuncios)",
                                              "observaciones": "Observaciones", "pct_promocion": "En promoción (%)"})
st.dataframe(ui.formato_tabla(por_com, pct_cols=["En promoción (%)"], num_cols=["Productos (anuncios)", "Observaciones"]),
             hide_index=True, width="stretch")

g1, g2 = st.columns(2)
with g1:
    dist = dc.distribucion(f)
    fig = px.box(dist, x="comercio", y="precio", color="comercio", points="outliers",
                 color_discrete_map=ui.COLORES_COMERCIO, category_orders={"comercio": ui.ORDEN_COMERCIOS},
                 hover_data={"nombre": True}, labels={"comercio": "Comercio", "precio": "Precio (COP)", "nombre": "Producto"})
    fig.update_yaxes(tickprefix="$ ")
    st.plotly_chart(ui.estilo_figura(fig, "Distribución de precios de la categoría por comercio",
                                     f"COP por presentación · {ui.descripcion_periodo(f)}"), width="stretch")
with g2:
    med = dc.mediana_subcategoria(f)
    if med.empty:
        ui.sin_datos()
    else:
        fig = px.bar(med, x="mediana_cop", y="subcategoria", orientation="h", text="mediana_cop",
                     hover_data={"observaciones": True},
                     labels={"mediana_cop": "Precio mediano (COP)", "subcategoria": "Subcategoría", "observaciones": "Observaciones"})
        fig.update_traces(marker_color="#78716C", texttemplate="$ %{text:,.0f}", textposition="inside",
                          insidetextanchor="end", textfont_color="white")
        fig.update_yaxes(categoryorder="total ascending")
        fig.update_xaxes(tickprefix="$ ")
        st.plotly_chart(ui.estilo_figura(fig, "Precio mediano por subcategoría",
                                         f"COP por presentación · {ui.descripcion_periodo(f)}"), width="stretch")

st.subheader("¿En qué comercio conviene comprar los productos comparables?")
sob = dc.sobrecosto(id_analisis, f.comercios)
if sob.empty:
    ui.sin_datos("No hay productos comparables con precio en al menos dos comercios para esta ejecución.")
else:
    fig = px.bar(sob, x="comercio", y="sobrecosto_promedio_pct", color="comercio",
                 color_discrete_map=ui.COLORES_COMERCIO, category_orders={"comercio": ui.ORDEN_COMERCIOS},
                 text="sobrecosto_promedio_pct",
                 hover_data={"veces_mas_barato": True, "productos_comparados": True, "sobrecosto_total_cop": ":,.0f"},
                 labels={"comercio": "Comercio", "sobrecosto_promedio_pct": "Sobrecosto promedio frente al más barato (%)",
                         "veces_mas_barato": "Veces que es el más barato", "productos_comparados": "Comparables con precio",
                         "sobrecosto_total_cop": "Sobrecosto acumulado (COP)"})
    fig.update_traces(texttemplate="%{text:.1f} %", textposition="outside", cliponaxis=False)
    fig.update_yaxes(ticksuffix=" %")
    st.plotly_chart(ui.estilo_figura(fig, "Cuánto más se paga, en promedio, frente al comercio más barato",
                                     f"Productos comparables disponibles · Ejecución {id_analisis} · 0 % = siempre el más barato",
                                     alto=380), width="stretch")
    st.caption("Lectura: un comercio con sobrecosto bajo es casi siempre el más barato, pero conviene revisar "
               "cuántos comparables tiene disponibles (los agotados no se cuentan).")

ui.nota_fecha_datos()
