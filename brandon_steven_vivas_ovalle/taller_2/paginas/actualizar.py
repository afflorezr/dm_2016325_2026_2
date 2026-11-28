"""Página Actualizar datos: scraping en línea (reutiliza scraper.py) y modo sin conexión (reprocesa raw/)."""
import os

import pandas as pd
import streamlit as st

import analisis as A
import servicios as sv
import ui


def _cargar_secretos() -> None:
    """Parámetros opcionales de scraping desde st.secrets (.streamlit/secrets.toml o la plataforma); nunca en el código."""
    try:
        for clave in ("SCRAPER_CONTACTO", "SCRAPER_USER_AGENT", "MAX_PETICIONES_COMERCIO"):
            if clave in st.secrets:
                os.environ.setdefault(clave, str(st.secrets[clave]))
    except Exception:  # noqa: BLE001  (no hay archivo de secretos: se usan los valores por defecto)
        pass


_cargar_secretos()
import scraper as S  # noqa: E402  (después de leer los secretos, porque el módulo lee el entorno al importarse)

COLUMNAS_RESUMEN = {"comercio_nombre": "Comercio", "estado": "Estado", "registros": "Recolectados", "nuevos": "Productos nuevos",
                    "cambios_precio": "Cambios de precio", "no_observados": "No observados", "rechazadas": "Rechazadas",
                    "obs_nuevas": "Observaciones insertadas", "motivo": "Motivo / notas"}


def _mostrar_resumen(filas: list[dict]) -> None:
    df = pd.DataFrame(filas)
    st.dataframe(df[[c for c in COLUMNAS_RESUMEN if c in df.columns]].rename(columns=COLUMNAS_RESUMEN), hide_index=True)
    fallidos = [f["comercio_nombre"] for f in filas if f["estado"] == "fallida"]
    if fallidos:
        st.error("No fue posible actualizar: " + ", ".join(fallidos) + ". Los demás comercios se actualizaron con normalidad. "
                 "Si el servidor está bloqueado por el sitio (frecuente en plataformas en la nube), usa el modo sin conexión.")


def cuerpo():
    st.title("Actualizar datos")
    ui.banner_datos()
    st.markdown(
        "**En línea:** consulta los sitios de los comercios con el scraper del proyecto, valida cada observación y la agrega "
        "a la base **sin sobrescribir** las anteriores (cada comercio se inserta en una transacción). Una recolección completa "
        "tarda varios minutos por la pausa de 1 s entre peticiones que respeta a los sitios.")
    st.caption("En plataformas gratuitas en la nube los comercios suelen bloquear el acceso y la base no conserva los cambios al "
               "reiniciarse. La actualización en línea está pensada para ejecutarse en tu computador.")

    todos = list(S.COMERCIOS_ACTIVOS)
    nombres = {c: S.COMERCIOS[c].nombre for c in todos}
    elegidos = st.multiselect("Comercios a actualizar", todos, default=todos, format_func=nombres.get, key="u_comercios")
    confirmado = st.checkbox("Entiendo que puede tardar varios minutos y que no debo cerrar esta página.", key="u_ok")
    ocupado = st.session_state.get("actualizando", False)

    if st.button("🔄 Actualizar precios (en línea)", disabled=not (confirmado and elegidos) or ocupado, type="primary"):
        st.session_state["actualizando"] = True
        try:
            ejec = S.nueva_ejecucion_id()
            cliente = S.Cliente()
            resumen = []
            with st.status(f"Actualizando precios · ejecución {A.etiqueta_ejecucion(ejec)}", expanded=True) as estado:
                for clave in elegidos:
                    st.write(f"Consultando {nombres[clave]}…")
                    res = S.recolectar_comercio(clave, sv.RUTA_DB, sv.RUTA_RAW, ejec, cliente, "en_linea")
                    resumen.append(res)
                    simbolo = {"completa": "✅", "parcial": "⚠️", "fallida": "❌"}.get(res["estado"], "•")
                    st.write(f"{simbolo} {nombres[clave]}: {res['estado']} · {res['registros']} productos recolectados")
                hubo = any(r["estado"] != "fallida" for r in resumen)
                estado.update(label="Actualización terminada" if hubo else "No se pudo actualizar ningún comercio",
                              state="complete" if hubo else "error")
            sv.invalidar_cache()
            st.session_state["ultimo_resumen"] = resumen
        finally:
            st.session_state["actualizando"] = False

    st.divider()
    st.subheader("Modo sin conexión")
    st.markdown("Reprocesa las copias crudas guardadas en `raw/` (no consulta ningún sitio). Las ejecuciones que ya están en la "
                "base se omiten, así que no se duplican ni se modifican datos.")
    hay_raw = sv.RUTA_RAW.is_dir() and any(sv.RUTA_RAW.glob("*/*/*.json.gz"))
    if not hay_raw:
        st.info("No hay copias crudas en `raw/` en este equipo/servidor, por lo que el modo sin conexión no tiene qué reprocesar.")
    if st.button("📦 Reprocesar copias de raw/ (sin conexión)", disabled=not hay_raw or ocupado):
        st.session_state["actualizando"] = True
        try:
            with st.spinner("Reprocesando copias crudas…"):
                res = S.reprocesar_raw(sv.RUTA_DB, sv.RUTA_RAW)
            sv.invalidar_cache()
            st.session_state["ultimo_resumen"] = res.to_dict("records")
        except FileNotFoundError:
            st.error("No existe la carpeta raw/.")
        finally:
            st.session_state["actualizando"] = False

    if st.session_state.get("ultimo_resumen"):
        st.subheader("Resumen por comercio")
        _mostrar_resumen(st.session_state["ultimo_resumen"])
        st.caption("Los indicadores, gráficos y tablas ya reflejan los datos nuevos (el caché se invalidó al terminar).")

    st.subheader("Historial de ejecuciones")
    det = sv.consultar("detalle_ejecuciones")
    st.dataframe(det.rename(columns={"ejecucion_id": "Ejecución", "comercio": "Comercio", "inicio": "Inicio", "fin": "Fin",
                                     "estado": "Estado", "modo": "Modo", "modo_api": "API", "n_registros": "Registros",
                                     "n_sitio_reportado": "Total del sitio", "n_rechazadas": "Rechazadas", "notas": "Notas"}),
                 hide_index=True)


ui.ejecutar_seguro(cuerpo)
