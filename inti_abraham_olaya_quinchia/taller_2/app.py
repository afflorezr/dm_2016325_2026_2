"""app.py - Punto de entrada multipágina (st.navigation). Sin SQL: usa db.py y actualizacion.py."""

import streamlit as st

import actualizacion

st.set_page_config(page_title="Comparador de precios", layout="wide")


def boton_actualizar():
    """Botón de la barra lateral: scraping por comercio con avance, tolerancia a fallas y resumen."""
    with st.sidebar:
        st.header("Actualización")
        offline = st.toggle("Modo sin conexión (usa raw/)", value=False)
        pulsado = st.button("Actualizar precios", type="primary", use_container_width=True)

    if not pulsado:
        return
    modo = "offline" if offline else "online"
    with st.status("Actualizando precios...", expanded=True) as estado:
        resumen, corrida = actualizacion.actualizar_todo(
            modo=modo, on_progress=lambda c, t: st.write(f"**{c}**: {t}"))
        fallidas = int((resumen["estado"] == "fallida").sum())
        estado.update(label=("Actualización terminada" if not fallidas else
                             f"Terminó con {fallidas} comercio(s) fallido(s)"),
                      state="complete" if not fallidas else "error")

    st.cache_data.clear()      # los indicadores y gráficos se recalculan con los datos nuevos
    st.subheader(f"Resumen de la actualización ({corrida})")
    st.dataframe(resumen, use_container_width=True, hide_index=True)
    st.caption("Precios en COP, a la fecha y hora de esta consulta. "
               "'No observados' no significa agotado ni retirado.")


boton_actualizar()

pagina = st.navigation([st.Page("paginas/resumen.py", title="Resumen", default=True)])
pagina.run()
