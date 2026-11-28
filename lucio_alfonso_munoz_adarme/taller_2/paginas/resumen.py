import plotly.express as px
import streamlit as st

import db
from comun import COLORES, ETIQUETA, aviso_fallidas, fecha, numero, panel_filtros, pesos

f = panel_filtros()
st.title("Comparador de precios de nutrición deportiva")
st.caption("Éxito, Farmatodo y Locatel, precios de Bogotá en pesos colombianos (COP) obtenidos por web scraping.")

ind = db.indicadores(f["id_ej"])
estado = db.estado_ejecucion(f["id_ej"])
ahorro = db.ahorro_comparables(f["id_ej"])
st.info(f"Datos de la ejecución {f['id_ej']} ({fecha(estado['inicio'].min())}). "
        f"La última ejecución de la base es del {fecha(ind['ultima_fecha'])}.")
aviso_fallidas(f["id_ej"])

c = st.columns(3)
c[0].metric("Presentaciones en la categoría", numero(ind["presentaciones"]), border=True)
c[1].metric("Observaciones en la base", numero(ind["observaciones_base"]), border=True)
c[2].metric("Estado de la ejecución",
            f"{(estado['estado'] == 'completa').sum()} de {len(estado)} completas", border=True)
c = st.columns(3)
c[0].metric("Presentaciones en promoción", f"{numero(ind['pct_promocion'] or 0, 1)} %", border=True)
c[1].metric("Ahorro máximo entre comercios",
            pesos(ahorro["ahorro_cop"].max()) if len(ahorro) else "sin dato", border=True)
c[2].metric("Cambios de precio", numero(ind["cambios"]), border=True)

izq, der = st.columns(2)
with izq:
    st.subheader("Productos y observaciones por comercio")
    tabla = db.por_comercio(f["id_ej"])
    tabla["comercio"] = tabla["comercio"].map(ETIQUETA)
    st.dataframe(tabla, hide_index=True, column_config={
        "presentaciones": "Presentaciones (ejecución)", "observaciones_base": "Observaciones (base)",
        "pct_promocion": st.column_config.NumberColumn("En promoción (%)", format="%.1f")})
with der:
    st.subheader("Mediana del precio por subcategoría (COP)")
    st.dataframe(db.mediana_por_subcategoria(f["id_ej"]), hide_index=True, column_config={
        "mediana": st.column_config.NumberColumn("Mediana (COP)", format="$ %,.0f")})

st.subheader("Distribución de precios por comercio")
datos = db.productos_filtrados(**f)
if datos.empty:
    st.warning("Ningún producto cumple los filtros elegidos.")
else:
    datos["comercio"] = datos["comercio"].map(ETIQUETA)
    fig = px.box(datos, x="comercio", y="precio", color="comercio", color_discrete_map=COLORES,
                 points="outliers",
                 labels={"precio": "Precio (COP)", "comercio": "Comercio"})
    fig.update_layout(showlegend=False, yaxis_tickformat=",.0f")
    st.plotly_chart(fig)
