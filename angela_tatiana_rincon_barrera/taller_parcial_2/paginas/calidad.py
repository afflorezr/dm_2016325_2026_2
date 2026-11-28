import plotly.express as px
import streamlit as st

import componentes as ui
import datos_cache as dc

f = st.session_state["filtros"]
st.title("Origen y calidad de los datos")
st.markdown(
    "Todos los precios provienen del web scraping de la **API pública de catálogo VTEX** que los propios sitios usan "
    "para mostrar sus productos (`/api/catalog_system/pub/products/search`). Cada observación se rastrea hasta su "
    "copia cruda en `raw/` (columna *Copia cruda* de cada ejecución) y su ejecución. Un dato ausente queda como ausente."
)

id_analisis = ui.corrida_de_analisis(f)
st.subheader(f"Disponibilidad por comercio · ejecución {id_analisis}")
disp = dc.disponibilidad(id_analisis)
if disp.empty:
    ui.sin_datos()
else:
    disp = disp.assign(estado=disp["estado"].map(ui.ETIQUETAS_DISPONIBILIDAD).fillna(disp["estado"]))
    fig = px.bar(disp, x="anuncios", y="comercio", color="estado", orientation="h", text="anuncios",
                 category_orders={"comercio": ui.ORDEN_COMERCIOS},
                 color_discrete_map={"Disponible": "#15803D", "Agotado según el sitio": "#B91C1C",
                                     "No observado en la ejecución": "#94A3B8", "Sin información del sitio": "#CBD5E1"},
                 labels={"anuncios": "Anuncios", "comercio": "Comercio", "estado": "Estado"})
    fig = ui.estilo_figura(fig, "Estado de disponibilidad de los anuncios",
                           "Anuncios observados alguna vez hasta esta ejecución · tres situaciones distintas", alto=300)
    fig.update_layout(legend_title_text="Estado")
    st.plotly_chart(fig, width="stretch")
    st.caption("«No observado» significa que el anuncio se vio en una ejecución anterior pero no en esta; no se "
               "interpreta como agotado ni como retirado.")

st.subheader("Ejecuciones de esta corrida")
st.dataframe(ui.formato_tabla(dc.ejecuciones_corrida(id_analisis)), hide_index=True, width="stretch")

st.subheader("Correcciones a la base del Taller 1")
corr = dc.correcciones()
st.write(f"{ui.numero(len(corr))} correcciones registradas, con fecha, registro afectado, valor anterior, valor nuevo y motivo. "
         "No se borró ninguna observación.")
if not corr.empty:
    resumen = corr.groupby(["campo", "motivo"]).size().reset_index(name="registros").sort_values("registros", ascending=False)
    st.dataframe(resumen, hide_index=True, width="stretch",
                 column_config={"campo": "Campo", "motivo": st.column_config.TextColumn("Motivo", width="large"),
                                "registros": "Registros"})
    with st.expander("Ver todas las correcciones"):
        st.dataframe(ui.formato_tabla(corr), hide_index=True, width="stretch")

st.subheader("Observaciones rechazadas por la validación")
rech = dc.rechazadas()
if rech.empty:
    st.caption("Ninguna observación ha sido rechazada. Reglas: precio numérico mayor que cero; comercio, URL y fecha "
               "presentes; sin duplicados en la ejecución; unidad mL/g/unidad; disponibilidad válida; al menos 8 "
               "comparables por comercio (si no, la ejecución queda parcial).")
else:
    st.dataframe(ui.formato_tabla(rech), hide_index=True, width="stretch")
