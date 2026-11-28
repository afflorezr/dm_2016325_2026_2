"""
Página Actualizar precios (Módulo 2).

El botón llama a las funciones de scraper.py (las mismas del Taller 1, ampliadas):
recolectar_comercio() consulta el sitio o lee raw/, y guardar_comercio() valida e
inserta en una transacción por comercio. Si un comercio falla, se sigue con los demás.
"""
import threading

import pandas as pd
import streamlit as st

import db
import interfaz
import scraper


@st.cache_resource
def candado() -> threading.Lock:
    """Un solo candado para todo el servidor: no corren dos actualizaciones a la vez."""
    return threading.Lock()


ICONOS = {"completa": ":material/check_circle:", "parcial": ":material/warning:",
          "fallida": ":material/cancel:"}

st.title("Actualizar precios")
st.markdown("""
- **En línea**: consulta los tres sitios con el scraper (una petición por segundo y máximo
  {max} peticiones por comercio). Registra una ejecución nueva, valida cada observación e
  inserta solo las que no existen. Tarda varios minutos (Cafam es el más lento).
- **Sin conexión**: vuelve a leer las copias crudas guardadas en `raw/` de una ejecución
  anterior, sin consultar los sitios. Sirve para verificar que la base sale de esas copias;
  como esas observaciones ya están en la base, lo normal es que no se inserte ninguna.
""".format(max=scraper.MAX_PETICIONES))

with interfaz.protegido():
    interfaz.fecha_de_los_datos()
    modo = st.radio("Modo", ["En línea", "Sin conexión (raw/)"], horizontal=True)
    sin_conexion = modo != "En línea"
    claves = scraper.COMERCIOS_POR_DEFECTO
    id_ejecucion = None
    if sin_conexion:
        copias = scraper.copias_en_raw()
        if copias.empty:
            st.error("No hay copias crudas en raw/.")
            st.stop()
        ids = sorted(copias["id_ejecucion"].unique(), reverse=True)
        id_ejecucion = st.selectbox("Ejecución de raw/ a reprocesar", ids)
        claves = copias.loc[copias["id_ejecucion"] == id_ejecucion, "id_comercio"].tolist()
        claves = [c for c in scraper.COMERCIOS_POR_DEFECTO if c in claves]
    elegidos = st.multiselect("Comercios", claves, default=claves,
                              format_func=lambda c: scraper.COMERCIOS[c]["nombre_corto"])

    if st.button("Actualizar precios", type="primary", disabled=not elegidos,
                 icon=":material/sync:"):
        if not candado().acquire(blocking=False):
            st.warning("Ya hay una actualización en curso. Espera a que termine y vuelve a intentar.")
        else:
            resumen = []
            try:
                id_ejecucion = id_ejecucion or scraper.nuevo_id_ejecucion()
                comparables = scraper.comparables_por_comercio()
                con = scraper.conectar()
                try:
                    with st.status(f"Actualizando precios ({id_ejecucion})...", expanded=True) as estado:
                        for clave in elegidos:
                            nombre = scraper.COMERCIOS[clave]["nombre_corto"]
                            st.write(f"{'Leyendo raw/ de' if sin_conexion else 'Consultando'} "
                                     f"{nombre}...")
                            r = scraper.actualizar_comercio(con, clave, id_ejecucion, sin_conexion,
                                                            comparables=comparables)
                            resumen.append(r)
                            texto = (f"{nombre}: **{r['estado']}** · {r['recolectados']} recolectados, "
                                     f"{r['nuevos']} nuevos, {r['cambios_precio']} cambios de precio, "
                                     f"{r['no_observados']} no observados, "
                                     f"{r['observaciones_nuevas']} observaciones insertadas, "
                                     f"{r['rechazadas']} rechazadas")
                            if r["motivo"]:
                                texto += f" · motivo: {r['motivo']}"
                            st.markdown(f"{ICONOS.get(r['estado'], '')} {texto}")
                        fallidos = sum(r["estado"] == "fallida" for r in resumen)
                        estado.update(label=f"Actualización terminada ({id_ejecucion}): "
                                            f"{len(resumen) - fallidos} de {len(resumen)} comercios "
                                            "sin falla",
                                      state="error" if fallidos == len(resumen) else "complete")
                finally:
                    con.close()
            finally:
                candado().release()
                db.limpiar_cache()        # indicadores, gráficos y tablas se recalculan
            st.session_state["ultimo_resumen"] = resumen
            st.session_state["ultimo_modo"] = "sin_conexion" if sin_conexion else "en_linea"

    resumen = st.session_state.get("ultimo_resumen")
    if resumen:
        st.subheader("Resumen por comercio")
        tabla = pd.DataFrame(resumen)
        interfaz.tabla(tabla[["comercio", "id_ejecucion", "modo", "estado", "recolectados", "nuevos",
                            "cambios_precio", "no_observados", "observaciones_nuevas", "rechazadas",
                            "motivo"]],
                     hide_index=True, width="stretch", column_config={
                         "comercio": "Comercio", "id_ejecucion": "Ejecución", "modo": "Modo",
                         "estado": "Estado", "recolectados": "Productos recolectados",
                         "nuevos": "Productos nuevos", "cambios_precio": "Cambios de precio",
                         "no_observados": "No observados",
                         "observaciones_nuevas": "Observaciones insertadas",
                         "rechazadas": "Rechazadas en la validación", "motivo": "Motivo"})
        if (st.session_state.get("ultimo_modo") == "en_linea"
                and all(r["estado"] == "fallida" for r in resumen)):
            st.error("No fue posible consultar los sitios desde este servidor. Es habitual en las "
                     "plataformas en la nube, porque los comercios suelen bloquearlas. Usa el modo "
                     "**Sin conexión** para reprocesar las copias de raw/, o ejecuta la aplicación "
                     "en tu computador (ver README.md).", icon=":material/cloud_off:")
        st.caption("Los indicadores, gráficos y tablas de las demás páginas ya usan los datos nuevos.")

    with st.expander("Copias crudas disponibles en raw/"):
        interfaz.tabla(scraper.copias_en_raw(), hide_index=True, width="stretch")
