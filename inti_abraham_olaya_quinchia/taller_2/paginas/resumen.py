"""paginas/resumen.py - Página principal: filtros, indicadores, gráficos y tabla (sin SQL: usa db.py)."""

import pandas as pd
import plotly.express as px
import streamlit as st

import db

DB = db.DB_PATH


def cop(v):
    """Formato de moneda colombiana: $12.900."""
    return "—" if v is None or pd.isna(v) else "$" + f"{v:,.0f}".replace(",", ".")


# ----------------------------------------------------------------------------
# Filtros (panel lateral)
# ----------------------------------------------------------------------------
filtros = db.obtener_filtros(DB)
colores = dict(zip(sorted(filtros["comercios"]), px.colors.qualitative.Set2 * 2))  # un color fijo por comercio

with st.sidebar:
    st.header("Filtros")
    comercios = st.multiselect("Comercio", filtros["comercios"])
    subcategorias = st.multiselect("Subcategoría", filtros["subcategorias"])
    marcas = st.multiselect("Marca", filtros["marcas"])
    tope = max(int(filtros["precio_max"]), 1000)
    precio_min, precio_max = st.slider("Rango de precio (COP)", 0, tope, (0, tope), step=1000)
    fechas = st.date_input("Rango de fechas de consulta", value=(), help="Vacío = todas las fechas")
    busqueda = st.text_input("Buscar en nombre o texto del anuncio", max_chars=60)
    solo_promo = st.checkbox("Solo promociones")
    solo_comp = st.checkbox("Solo comparables")

parametros = {"comercios": comercios, "subcategorias": subcategorias, "marcas": marcas,
              "precio_min": precio_min if precio_min > 0 else None,
              "precio_max": precio_max if precio_max < tope else None,
              "busqueda": busqueda, "solo_promocion": solo_promo, "solo_comparables": solo_comp}
if len(fechas) == 2:      # st.date_input devuelve () / (inicio,) / (inicio, fin)
    parametros["fecha_desde"] = f"{fechas[0]}T00:00:00"
    parametros["fecha_hasta"] = f"{fechas[1]}T23:59:59"

st.title("Comparador de precios")
tabla = db.obtener_tabla(DB, parametros)
if tabla.empty:
    st.info("Ningún producto cumple los filtros. Prueba ampliando el rango de precio o quitando filtros.")
    st.stop()

# ----------------------------------------------------------------------------
# Indicadores (6) calculados en db.py
# ----------------------------------------------------------------------------
ind = db.obtener_indicadores(DB, parametros)
obs = ind["observaciones_por_comercio"]
med = ind["mediana_subcategoria"]
ult = ind["ultima_ejecucion"]
aho = ind["ahorro_maximo"]

c1, c2, c3 = st.columns(3)
c1.metric("Productos", f"{ind['total_productos']['valor']:,}".replace(",", "."),
          help="Anuncios con su último precio observado")
c2.metric("En promoción", "—" if ind["proporcion_promocion"]["valor"] is None
          else f"{ind['proporcion_promocion']['valor']:.1f} %", help="Sobre el último precio observado")
c3.metric("Última ejecución", str(ult["valor"] or "—")[:10], help=f"{ult['corrida_id']} · {ult['estado']}")
c4, c5, c6 = st.columns(3)
c4.metric("Ahorro máximo entre comercios", cop(aho["valor"]),
          delta=None if aho["porcentaje"] is None else f"{aho['porcentaje']:.1f} %",
          delta_color="off", help=f"{aho['producto'] or 'Sin comparables'} · ejecución {aho['corrida_id'] or '—'}")
c5.metric("Observaciones", f"{int(obs['observaciones'].sum()):,}".replace(",", ".") if not obs.empty else "0",
          help="Todas las ejecuciones; el detalle por comercio está abajo")
c6.metric("Mediana más alta por subcategoría", cop(med["mediana_cop"].max()) if not med.empty else "—",
          help=med.iloc[0]["subcategoria"] if not med.empty else "Sin datos")
with st.expander("Detalle: observaciones por comercio y mediana por subcategoría (COP)"):
    d1, d2 = st.columns(2)
    d1.dataframe(obs, hide_index=True, use_container_width=True)
    d2.dataframe(med, hide_index=True, use_container_width=True)
st.caption("Valores en COP; los precios corresponden al momento de cada consulta, no son permanentes.")

# ----------------------------------------------------------------------------
# Gráficos
# ----------------------------------------------------------------------------
g1, g2 = st.columns(2)

with g1:
    st.subheader("Evolución del precio de un producto")
    prods = db.obtener_productos_comparables(DB)
    if prods.empty:
        st.info("Aún no hay productos comparables.")
    else:
        etiquetas = {r.producto_id: f"{r.marca or ''} · {r.producto} · {r.contenido:g} {r.unidad}"
                     if pd.notna(r.contenido) else f"{r.marca or ''} · {r.producto}"
                     for r in prods.itertuples()}
        pid = st.selectbox("Producto comparable", list(etiquetas), format_func=etiquetas.get)
        hist = db.obtener_datos_graficos(DB, {k: v for k, v in parametros.items() if k in
                                              ("comercios", "fecha_desde", "fecha_hasta")} | {"producto_id": pid})
        if hist.empty:
            st.info("Sin observaciones para ese producto con los filtros actuales.")
        else:
            hist["fecha"] = pd.to_datetime(hist["fecha_consulta"], utc=True).dt.tz_convert("America/Bogota")
            fig = px.line(hist, x="fecha", y="precio", color="comercio", markers=True,
                          color_discrete_map=colores, labels={"precio": "Precio (COP)", "fecha": "Fecha de consulta"})
            st.plotly_chart(fig, use_container_width=True)
            st.caption("Una línea por comercio. Con pocas ejecuciones solo se ven unos puntos.")

with g2:
    st.subheader("Precio por unidad de contenido")
    pu = tabla.dropna(subset=["precio_unitario", "unidad"])
    unidades = [u for u in ("mL", "g", "unidad") if u in set(pu["unidad"])]
    if not unidades:
        st.info("Ningún producto filtrado tiene contenido identificable.")
    else:
        unidad = st.radio("Unidad (no se mezclan)", unidades, horizontal=True)
        top = pu[pu["unidad"] == unidad].nsmallest(15, "precio_unitario")
        top = top.assign(etiqueta=top["nombre"].str.slice(0, 40))
        fig = px.bar(top, x="precio_unitario", y="etiqueta", color="comercio", orientation="h",
                     color_discrete_map=colores, labels={"precio_unitario": f"COP por {unidad}", "etiqueta": ""})
        fig.update_yaxes(autorange="reversed")
        st.plotly_chart(fig, use_container_width=True)
        st.caption(f"Los 15 más baratos por {unidad}. Un envase más grande puede tener menor precio por unidad, "
                   "pero exige un desembolso mayor.")

g3, g4 = st.columns(2)
with g3:
    st.subheader("Distribución de precios por comercio")
    fig = px.box(tabla.dropna(subset=["precio"]), x="comercio", y="precio", color="comercio",
                 color_discrete_map=colores, points="outliers", labels={"precio": "Precio (COP)", "comercio": ""})
    fig.update_layout(showlegend=False)
    st.plotly_chart(fig, use_container_width=True)
    st.caption("Compara surtidos distintos: no indica por sí sola qué comercio es más barato.")

with g4:
    st.subheader("Productos con y sin promoción")
    prom = (tabla["en_promocion"].map({1: "Con promoción", 0: "Sin promoción"}).value_counts().rename_axis("estado")
            .reset_index(name="productos"))
    fig = px.pie(prom, names="estado", values="productos", hole=0.45, color="estado",
                 color_discrete_map={"Con promoción": "#E4572E", "Sin promoción": "#9AA5B1"})
    st.plotly_chart(fig, use_container_width=True)
    st.caption("Sobre el último precio observado de cada producto filtrado.")

# ----------------------------------------------------------------------------
# Tabla y descarga
# ----------------------------------------------------------------------------
st.subheader("Productos filtrados")
vista = tabla.drop(columns=["producto_id", "comparable"]).rename(columns={
    "comercio": "Comercio", "nombre": "Nombre", "marca": "Marca", "subcategoria": "Subcategoría",
    "contenido": "Contenido", "unidad": "Unidad", "precio": "Precio (COP)", "precio_unitario": "Precio por unidad (COP)",
    "en_promocion": "Promoción", "disponibilidad": "Disponibilidad", "fecha_consulta": "Fecha de consulta",
    "url": "Anuncio"})
vista["Promoción"] = vista["Promoción"].map({1: "Sí", 0: "No"})
st.dataframe(vista, hide_index=True, use_container_width=True, column_config={
    "Anuncio": st.column_config.LinkColumn("Anuncio", display_text="Ver"),
    "Precio (COP)": st.column_config.NumberColumn(format="$ %d"),
    "Precio por unidad (COP)": st.column_config.NumberColumn(format="$ %.1f")})
st.download_button("Descargar CSV", vista.to_csv(index=False).encode("utf-8-sig"),
                   file_name="productos_filtrados.csv", mime="text/csv")
