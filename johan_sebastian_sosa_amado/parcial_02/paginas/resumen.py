"""Página de inicio: indicadores, distribución de precios por comercio y
promociones por comercio."""

import plotly.express as px
import streamlit as st

import ui

st.title("Comparador de precios: incontinencia y cuidado del adulto")
ui.aviso_fecha()

filtros = ui.filtros_actuales()
f = dict(filtros)
ind = ui.indicadores(filtros)

# Indicadores
c1, c2, c3 = st.columns(3)
c1.metric("Productos (anuncios)", f"{ind['productos']}",
          help="Anuncios distintos que cumplen los filtros, en la recolección elegida.")
c2.metric("Productos en promoción", ui.pct(ind["pct_promocion"]),
          help="Porcentaje de los productos con precio que están rebajados, en la recolección elegida.")
c3.metric("Cambios de precio", f"{ind['cambios_precio']}",
          help="Anuncios que subieron o bajaron de precio frente a la recolección anterior (número).")

c4, c5, c6 = st.columns(3)
c4.metric("Última recolección", ui.fecha_corta(ind["ultima_fecha"]), ind["ultima_estado"],
          delta_color="off", delta_arrow="off")
if ind["ahorro_maximo"]:
    a = ind["ahorro_maximo"]
    c5.metric("Ahorro máximo entre comercios", ui.cop(a["ahorro_cop"]), f"{ui.pct(a['ahorro_pct'])} en {a['producto_id']}",
              delta_color="off", delta_arrow="off",
              help=f"{a['descripcion']}: más barato en "
                   f"{', '.join(ui.NOMBRES.get(c, c) for c in a['mas_barato'].split(', '))}. "
                   "Compara los tres comercios aunque el filtro tenga menos (COP, recolección elegida).")
else:
    c5.metric("Ahorro máximo entre comercios", "sin dato")
if len(ind["medianas"]):
    m = ind["medianas"].iloc[0]
    c6.metric(f"Precio mediano ({m['subcategoria']})", ui.cop(m["mediana"]), f"{int(m['n'])} precios",
              delta_color="off", delta_arrow="off", help="Mediana en COP de la subcategoría con más precios.")

with st.expander("Productos y observaciones por comercio, y precio mediano por subcategoría"):
    i1, i2 = st.columns(2)
    por = ind["por_comercio"].assign(comercio=lambda d: d["comercio"].map(ui.NOMBRES),
                                     mediana=lambda d: d["mediana"].map(ui.cop))
    i1.dataframe(por, hide_index=True, width="stretch",
                 column_config={"comercio": "Comercio", "productos": "Productos",
                                "observaciones": "Observaciones", "en_promocion": "En promoción",
                                "mediana": "Precio mediano (COP)"})
    med = ind["medianas"].assign(mediana=lambda d: d["mediana"].map(ui.cop))
    i2.dataframe(med, hide_index=True, width="stretch",
                 column_config={"subcategoria": "Subcategoría", "mediana": "Precio mediano (COP)",
                                "n": "Precios"})

st.divider()

# Distribución de precios por comercio
precios = ui.visibles(ui.distribucion(filtros))
st.subheader("¿En qué comercio son más altos los precios de la categoría?")
if not ui.sin_datos(precios):
    mas_caro = ind["por_comercio"].iloc[0]     # viene ordenada por mediana, de mayor a menor
    fig = px.box(precios, x="comercio", y="precio", color="comercio", points="all",
                 color_discrete_map=ui.COLORES_VISIBLES, hover_data=["subcategoria"],
                 labels={"precio": "Precio (COP)", "comercio": "Comercio", "subcategoria": "Subcategoría"},
                 title=f"La mediana más alta está en {ui.NOMBRES.get(mas_caro['comercio'], mas_caro['comercio'])} "
                       f"({ui.cop(mas_caro['mediana'])})")
    fig.update_layout(showlegend=False)
    fig.update_yaxes(tickformat=",.0f")
    st.plotly_chart(ui.estilo(fig), width="stretch")
    st.caption("Cada punto es un producto con precio. La caja va del primer al tercer cuartil y la línea es la mediana. "
               "Mezcla presentaciones distintas: para comparar el mismo producto use la página Comparar comercios.")

# Promociones: ¿dónde hay más y cuánto descuentan?
st.subheader("¿Dónde hay más promociones y cuánto descuentan de verdad?")
promo = ui.visibles(ui.promociones(filtros))
if not ui.sin_datos(promo):
    fila = promo.loc[promo["pct_promocion"].idxmax()]
    fig = px.bar(promo, x="comercio", y="pct_promocion", color="comercio",
                 color_discrete_map=ui.COLORES_VISIBLES, text="pct_promocion",
                 hover_data={"descuento_mediano": True, "en_promocion": True},
                 labels={"pct_promocion": "Productos en promoción (%)", "comercio": "Comercio",
                         "descuento_mediano": "Descuento mediano (%)", "en_promocion": "En promoción"},
                 title=f"{fila['comercio']} tiene la mayor proporción en promoción ({ui.pct(fila['pct_promocion'])})")
    fig.update_traces(texttemplate="%{y:.1f} %")
    fig.update_layout(showlegend=False, yaxis_range=[0, max(100, promo["pct_promocion"].max())])
    st.plotly_chart(ui.estilo(fig), width="stretch")
    texto = ", ".join(f"{r.comercio}: {ui.pct(r.descuento_mediano)}" for r in promo.itertuples()
                      if r.descuento_mediano == r.descuento_mediano)
    st.caption(f"Descuento mediano de los productos en promoción (precio antes frente a precio actual): {texto or 'sin dato'}. "
               "Muchas promociones no significan descuentos grandes.")
