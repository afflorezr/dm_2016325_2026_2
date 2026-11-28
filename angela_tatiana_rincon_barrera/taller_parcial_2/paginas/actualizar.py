import pandas as pd
import streamlit as st

import actualizacion
import componentes as ui
import datos_cache as dc
import scraper

st.title("Actualizar datos")
st.markdown(
    "El botón ejecuta el **mismo scraper del Taller 1** (`scraper.py`) sobre la API de catálogo que usa cada sitio, "
    "valida las observaciones (`validacion.py`) e inserta solo las que no existen (`db.py`), en una transacción por "
    "comercio. Si un comercio falla, se continúa con los demás y se registra el motivo."
)
st.caption(f"Buenas prácticas: agente de usuario identificable, pausa de {scraper.PAUSA_SEGUNDOS:.0f} s entre peticiones "
           f"y máximo {scraper.MAX_PETICIONES_POR_COMERCIO} peticiones por comercio.")


def _ejecutar(offline: bool, archivos=None) -> None:
    resumen = []
    titulo = "Reprocesando copias crudas de raw/..." if offline else "Actualizando precios en línea..."
    with st.status(titulo, expanded=True) as estado:
        def aviso(comercio: str, mensaje: str) -> None:
            st.write(f"**{comercio}**: {mensaje}")
        try:
            r = actualizacion.actualizar(offline=offline, archivos_raw=archivos, aviso=aviso)
        except Exception as e:  # error inesperado: mensaje claro, sin traza técnica
            estado.update(label="La actualización no pudo completarse", state="error")
            st.error(f"No fue posible completar la actualización ({type(e).__name__}). La base no quedó modificada "
                     "para los comercios no procesados.")
            return
        etiqueta = {"completa": "complete", "parcial": "complete", "fallida": "error"}[r["estado"]]
        estado.update(label=f"Actualización terminada: ejecución {r['id_corrida']} "
                            f"({ui.ETIQUETAS_ESTADO[r['estado']].lower()})", state=etiqueta)
    st.session_state["ultimo_resumen"] = r
    dc.limpiar_cache()   # invalida la caché: indicadores, gráficos y tablas se recalculan
    st.rerun()


col1, col2 = st.columns(2)
with col1:
    with st.container(border=True):
        st.subheader("En línea")
        st.write("Consulta los tres comercios y guarda una nueva copia cruda en `raw/<comercio>/<fecha>/`.")
        if st.button("Actualizar precios", type="primary", icon=":material/sync:"):
            _ejecutar(offline=False)
with col2:
    with st.container(border=True):
        st.subheader("Sin conexión")
        st.write("Reprocesa copias crudas de `raw/` (modo de demostración cuando un sitio no responde). "
                 "Si la copia ya estaba cargada, no se duplican observaciones.")
        archivos = {}
        with st.expander("Elegir copias crudas"):
            for comercio in scraper.COMERCIOS:
                copias = scraper.listar_copias_crudas(comercio)
                if copias:
                    etiquetas = {f"{c.parent.name} · {c.name}": c for c in reversed(copias)}
                    archivos[comercio] = etiquetas[st.selectbox(comercio, list(etiquetas), key=f"raw_{comercio}")]
        if st.button("Reprocesar copias de raw/", icon=":material/folder_open:"):
            _ejecutar(offline=True, archivos=archivos or None)

r = st.session_state.get("ultimo_resumen")
if r:
    st.subheader(f"Resumen de la última actualización (ejecución {r['id_corrida']}, "
                 f"{ui.ETIQUETAS_MODO[r['modo']].lower()})")
    tabla = pd.DataFrame(r["comercios"])[["comercio", "estado", "recolectados", "insertados", "productos_nuevos",
                                         "cambios_precio", "no_observados", "rechazados", "comparables", "motivo"]]
    tabla["estado"] = tabla["estado"].map(ui.ETIQUETAS_ESTADO)
    st.dataframe(ui.formato_tabla(tabla), hide_index=True, width="stretch",
                 column_config={"comercio": "Comercio", "estado": "Estado", "recolectados": "Productos recolectados",
                                "insertados": "Observaciones insertadas", "productos_nuevos": "Productos nuevos",
                                "cambios_precio": "Cambios de precio", "no_observados": "No observados",
                                "rechazados": "Rechazados por validación", "comparables": "Comparables encontrados",
                                "motivo": st.column_config.TextColumn("Motivo / observaciones", width="large")})
    if r["modo"] == "en_linea" and all(c["estado"] == "fallida" for c in r["comercios"]):
        st.error("El servidor no pudo consultar ningún comercio. Es habitual que los sitios bloqueen las plataformas "
                 "de despliegue en la nube. Use el **modo sin conexión** para reprocesar las copias de `raw/`, o "
                 "ejecute la aplicación localmente para actualizar en línea.", icon=":material/cloud_off:")

st.subheader("Historial de ejecuciones por comercio")
hist = dc.ejecuciones()
if hist.empty:
    st.caption("Sin ejecuciones registradas.")
else:
    hist = hist.assign(estado=hist["estado"].map(ui.ETIQUETAS_ESTADO), modo=hist["modo"].map(ui.ETIQUETAS_MODO),
                       inicio=hist["fecha_hora_inicio"].map(ui.fecha))
    st.dataframe(ui.formato_tabla(hist[["id_corrida", "comercio", "modo", "inicio", "estado", "total_reportado_sitio", "recolectados",
                       "insertados", "n_rechazadas", "n_productos_nuevos", "n_cambios_precio", "n_no_observados",
                       "comparables_encontrados", "archivo_raw", "motivo"]]),
                 hide_index=True, width="stretch",
                 column_config={"id_corrida": "Ejecución", "comercio": "Comercio", "modo": "Modo", "inicio": "Inicio",
                                "estado": "Estado", "total_reportado_sitio": "Total reportado por el sitio",
                                "recolectados": "Recolectados", "insertados": "Insertados", "n_rechazadas": "Rechazados",
                                "n_productos_nuevos": "Nuevos", "n_cambios_precio": "Cambios de precio",
                                "n_no_observados": "No observados", "comparables_encontrados": "Comparables",
                                "archivo_raw": "Copia cruda", "motivo": st.column_config.TextColumn("Motivo", width="large")})
st.caption("En la versión publicada la base vuelve a su estado del repositorio cuando la plataforma reinicia la "
           "aplicación; la actualización en línea con persistencia se hace en la ejecución local.")
