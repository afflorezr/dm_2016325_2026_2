"""
paginas/resumen.py — Taller 2: página "Resumen".

Indicadores en tarjetas (§7.3), distribución de precios por comercio (gráfico 3, §7.4), mediana por subcategoría y
la tabla de productos filtrados con descarga CSV (§7.5). Usa TODOS los filtros del panel lateral. Sin SQL.
"""
import plotly.express as px
import streamlit as st

import componentes as cp

filtros = cp.filtros_actuales()
periodo = cp.describir_periodo(filtros)

st.title("Comparador de precios · Cuidado capilar")
st.write("Precios de champús, acondicionadores, tratamientos, tintes y productos para peinar en **La Rebaja**, "
         "**Locatel** y **Droguerías Cafam**, obtenidos por web scraping de sus sitios.")
st.caption(f"Periodo: {periodo}. Los indicadores de esta fila usan los filtros del panel lateral.")

# [CAMBIO]: fila 1 de indicadores: dependen de los filtros (unidad y periodo en cada tarjeta).
generales = cp.obtener("indicadores_generales", filtros)
if generales is None or generales["n_observaciones"].iloc[0] == 0:
    cp.sin_datos()
    st.stop()
g = generales.iloc[0]
c1, c2, c3, c4 = st.columns(4)
cp.tarjeta(c1, "Productos distintos", f"{int(g['n_productos']):,}".replace(",", "."),
           f"Anuncios (SKU) · {periodo}")
cp.tarjeta(c2, "Observaciones de precio", f"{int(g['n_observaciones']):,}".replace(",", "."),
           f"Registros de precio · {periodo}")
cp.tarjeta(c3, "En promoción", f"{g['pct_promocion']:.1f} %".replace(".", ","),
           f"% de observaciones con precio rebajado · {periodo}")
cp.tarjeta(c4, "Precio promedio", cp.formato_cop(g["precio_promedio"]), f"COP por producto · {periodo}")

# [CAMBIO]: fila 2 de indicadores: referidos a la ÚLTIMA ejecución (no dependen de los filtros).
ultima = cp.obtener("ultima_ejecucion")
if ultima is not None and len(ultima):
    id_ultima = ultima["id_ejecucion"].iloc[0]
    fecha_ultima = cp.formato_fecha(id_ultima)
    c5, c6, c7, c8 = st.columns(4)
    completas = int((ultima["estado"] == "completa").sum())
    cp.tarjeta(c5, "Última ejecución", fecha_ultima[:10],
               f"Hora {fecha_ultima[11:]} · estado: {completas} de {len(ultima)} comercios con ejecución completa")
    ahorro = cp.obtener("ahorro_por_comparable", id_ultima)
    if ahorro is not None and len(ahorro):
        a = ahorro.iloc[0]
        cp.tarjeta(c6, "Ahorro máximo entre comercios", cp.formato_cop(a["ahorro_cop"]),
                   f"COP ({a['ahorro_pct']:.1f} %) en {a['producto'].title()[:45]}: más barato en "
                   f"{a['donde_mas_barato']} · ejecución {fecha_ultima}")
    cambios = cp.obtener("cambios_ultima_ejecucion")
    if cambios is not None and len(cambios):
        cp.tarjeta(c7, "Cambios de precio", f"{int(cambios['n_subieron'].sum() + cambios['n_bajaron'].sum())}",
                   f"Anuncios: {int(cambios['n_subieron'].sum())} subieron y {int(cambios['n_bajaron'].sum())} "
                   f"bajaron frente a la ejecución anterior · {fecha_ultima}")
    disp = cp.obtener("resumen_disponibilidad", id_ultima)
    if disp is not None and len(disp):
        cp.tarjeta(c8, "Productos agotados", f"{int(disp['n_agotados'].sum())}",
                   f"Anuncios agotados según el sitio ({int(disp['n_no_observados'].sum())} no observados) · "
                   f"{fecha_ultima}. Cafam no informa agotados.")

# [CAMBIO]: indicadores por comercio y mediana por subcategoría (SQL), lado a lado.
izquierda, derecha = st.columns(2)
with izquierda:
    st.subheader("Por comercio")
    por_comercio = cp.obtener("resumen_por_comercio", filtros)
    if por_comercio is not None and len(por_comercio):
        st.dataframe(
            por_comercio[["comercio", "n_productos", "n_observaciones", "pct_promocion"]],
            hide_index=True, width="stretch",
            column_config={"comercio": "Comercio", "n_productos": "Productos",
                           "n_observaciones": "Observaciones",
                           "pct_promocion": st.column_config.NumberColumn("En promoción (%)", format="%.1f %%")})
        st.caption(f"Unidades: número de anuncios y de observaciones · {periodo}.")
with derecha:
    st.subheader("Mediana del precio por subcategoría")
    medianas = cp.obtener("mediana_por_subcategoria", filtros)
    if medianas is not None and len(medianas):
        medianas = medianas.assign(subcategoria=medianas["subcategoria"].map(cp.NOMBRES_SUBCATEGORIA))
        st.dataframe(medianas, hide_index=True, width="stretch",
                     column_config={"subcategoria": "Subcategoría",
                                    "mediana_cop": st.column_config.NumberColumn("Mediana (COP)", format="$ %,.0f"),
                                    "n_observaciones": "Observaciones"})
        st.caption(f"Mediana en pesos colombianos (COP) · {periodo}.")

# [CAMBIO]: gráfico 3 (§7.4): distribución de precios de la categoría por comercio.
st.subheader("Distribución de precios por comercio")
tabla = cp.obtener("productos_filtrados", filtros)
if tabla is None or tabla.empty:
    cp.sin_datos()
    st.stop()
escala_log = st.toggle("Escala logarítmica", value=True,
                       help="Útil porque hay productos de $1.300 y de más de $500.000.")
grafico = px.box(tabla, x="comercio", y="precio", color="comercio", points="outliers",
                 color_discrete_map=cp.mapa_colores(), category_orders={"comercio": cp.ORDEN_COMERCIOS},
                 hover_data={"nombre": True, "precio": ":,.0f"}, log_y=escala_log,
                 labels={"comercio": "Comercio", "precio": "Precio (COP)", "nombre": "Producto"},
                 title=f"Precio por producto (COP) · {periodo}")
grafico.update_layout(showlegend=False)
if escala_log:  # marcas legibles en pesos (sin las marcas intermedias "2", "5" de plotly)
    marcas = [1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000]
    grafico.update_yaxes(tickvals=marcas, ticktext=[cp.formato_cop(m) for m in marcas])
else:
    grafico.update_yaxes(tickprefix="$ ", tickformat=",.0f")
st.plotly_chart(grafico, width="stretch")
st.caption("Cada caja muestra el 50 % central de los precios; la línea es la mediana. Los puntos son precios atípicos.")

# [CAMBIO]: tabla de productos filtrados (§7.5): ordenar (clic en la columna), buscar (lupa) y descargar CSV.
st.subheader("Productos filtrados")
vista = tabla.assign(
    subcategoria=tabla["subcategoria"].map(cp.NOMBRES_SUBCATEGORIA),
    presentacion=[f"{c:g} {u}" if c == c and u else "—" for c, u in zip(tabla["contenido"], tabla["unidad_norm"])],
    unidad_precio=[f"COP/{u}" if u else "" for u in tabla["unidad_norm"]],
    promocion=tabla["es_promocion"].map({1: "Sí", 0: "No"}),
    disponibilidad=tabla["estado_disponibilidad"].map(cp.NOMBRES_DISPONIBILIDAD),
    fecha=tabla["fecha_hora_consulta"].map(cp.formato_fecha),
)
columnas = ["comercio", "nombre", "marca", "subcategoria", "presentacion", "precio", "precio_unitario",
            "unidad_precio", "precio_antes_descuento", "promocion", "disponibilidad", "fecha", "url"]
st.dataframe(
    vista[columnas], hide_index=True, width="stretch", height=420,
    column_config={
        "comercio": "Comercio", "nombre": "Nombre del anuncio", "marca": "Marca", "subcategoria": "Subcategoría",
        "presentacion": "Presentación",
        "precio": st.column_config.NumberColumn("Precio (COP)", format="$ %,.0f"),
        "precio_unitario": st.column_config.NumberColumn("Precio unitario", format="$ %,.2f"),
        "unidad_precio": "Unidad del precio unitario",
        "precio_antes_descuento": st.column_config.NumberColumn("Precio antes del descuento (COP)", format="$ %,.0f"),
        "promocion": "Promoción", "disponibilidad": "Disponibilidad", "fecha": "Fecha de consulta",
        "url": st.column_config.LinkColumn("Enlace al anuncio", display_text="Ver anuncio"),
    })
st.caption(f"{len(vista):,} filas · {periodo}. Precio unitario = precio ÷ contenido total de la presentación."
           .replace(",", "."))
st.download_button("Descargar datos filtrados (CSV)", vista[columnas].to_csv(index=False).encode("utf-8-sig"),
                   file_name="productos_filtrados.csv", mime="text/csv")
