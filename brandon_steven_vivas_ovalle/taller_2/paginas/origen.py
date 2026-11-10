"""Página Origen de los datos: ejecuciones, validación, correcciones y trazabilidad hasta raw/."""
import streamlit as st

import analisis as A
import servicios as sv
import ui


def cuerpo():
    st.title("Origen de los datos")
    ui.banner_datos()
    st.markdown("Todos los precios provienen del scraper del proyecto (`scraper.py`) ejecutado sobre los sitios de los comercios. "
                "Cada observación guarda su ejecución, su fecha y hora de consulta y la copia cruda (`raw/`) de donde salió.")

    st.subheader("Ejecuciones")
    ej = sv.consultar("ejecuciones")
    st.dataframe(ej[["ejecucion_id", "fecha", "estado", "n_comercios", "n_completas", "n_parciales", "n_fallidas", "n_registros", "modo"]]
                 .rename(columns={"ejecucion_id": "Ejecución", "fecha": "Fecha", "estado": "Estado", "n_comercios": "Comercios",
                                  "n_completas": "Completos", "n_parciales": "Parciales", "n_fallidas": "Fallidos",
                                  "n_registros": "Registros", "modo": "Modo"}), hide_index=True)

    st.subheader("Observaciones rechazadas por la validación")
    rech = sv.consultar("rechazadas")
    if rech.empty:
        st.success("Ninguna observación ha sido rechazada hasta ahora.")
    else:
        st.dataframe(rech, hide_index=True)

    st.subheader("Correcciones a la base del Taller 1")
    cor = sv.consultar("correcciones")
    if cor.empty:
        st.info("Sin correcciones registradas.")
    else:
        st.dataframe(cor, hide_index=True)

    st.subheader("Trazabilidad hasta las copias crudas (raw/)")
    cob = sv.consultar("cobertura_trazabilidad")
    st.dataframe(cob.rename(columns={"ejecucion_id": "Ejecución", "comercio": "Comercio", "observaciones": "Observaciones",
                                     "con_raw": "Con copia cruda enlazada"}), hide_index=True)
    if int(cob["con_raw"].sum()) < int(cob["observaciones"].sum()):
        st.caption("Para enlazar las observaciones antiguas con sus copias crudas ejecuta `python migrar_taller2.py --raw raw`.")
    ids = ej["ejecucion_id"].tolist()
    if ids:
        c1, c2 = st.columns(2)
        ejec = c1.selectbox("Ejecución", ids, format_func=A.etiqueta_ejecucion, key="o_ejec")
        com = c2.selectbox("Comercio", sv.consultar("opciones_filtros")["comercios"], key="o_com")
        muestra = sv.consultar("muestra_trazabilidad", ejec, com)
        if muestra.empty:
            ui.sin_datos("No hay comparables en esa ejecución y comercio.")
        else:
            muestra = muestra.copy()
            muestra["existe_en_este_equipo"] = muestra["raw_archivo"].map(
                lambda r: bool(r) and (sv.RUTA_RAW.parent / r).is_file())
            st.dataframe(muestra, hide_index=True)


ui.ejecutar_seguro(cuerpo)
