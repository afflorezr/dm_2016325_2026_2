"""
paginas/actualizar.py — Taller 2: página "Actualizar precios" (Módulo 2).

El botón llama a actualizacion.py, que a su vez llama a las funciones de scraper.py del Taller 1 (no se reescribe
el scraper aquí). El avance se muestra por comercio con st.status y, al terminar, se limpia la caché para que
indicadores, gráficos y tablas muestren los datos nuevos sin reiniciar la aplicación. Esta página no contiene SQL.
"""
import pandas as pd
import streamlit as st

import actualizacion
import componentes
import scraper

# [CAMBIO]: nombres en español para las columnas del resumen por comercio (§4.5).
COLUMNAS_RESUMEN = {
    "comercio": "Comercio", "estado": "Estado", "recolectados": "Productos recolectados",
    "validos": "Válidos", "rechazados": "Rechazados", "productos_nuevos": "Productos nuevos",
    "observaciones_nuevas": "Observaciones nuevas", "precios_subieron": "Precios que subieron",
    "precios_bajaron": "Precios que bajaron", "no_observados": "No observados",
    "comparables_faltantes": "Comparables faltantes", "motivo": "Notas / motivo",
}

st.title("Actualizar precios")
st.write("Ejecuta el scraper del Taller 1 en los tres comercios, valida cada observación antes de guardarla y "
         "agrega solo las que no existen. Las observaciones anteriores nunca se sobrescriben.")

# [CAMBIO]: elección del modo. En línea consulta los sitios; sin conexión reprocesa las copias crudas de raw/.
modo = st.radio("Modo de actualización",
                ["Sin conexión: reprocesar copias guardadas en raw/", "En línea: consultar los sitios de los comercios"],
                help="El modo sin conexión no hace peticiones: vuelve a leer las respuestas guardadas en raw/.")
offline = modo.startswith("Sin conexión")
id_elegido = None
if offline:
    opciones = actualizacion.ejecuciones_en_raw()
    if not opciones:
        st.error("No hay copias crudas en raw/; el modo sin conexión no está disponible.")
        st.stop()
    id_elegido = st.selectbox("Ejecución guardada que se reprocesará", opciones,
                              format_func=lambda i: f"{i[:4]}-{i[4:6]}-{i[6:8]} {i[9:11]}:{i[11:13]} ({i})")
    st.caption("Si esa ejecución ya está en la base, el resumen mostrará 0 observaciones nuevas: no se duplica nada.")
else:
    st.info("Se harán unas 60 peticiones con 1 segundo de pausa entre ellas (unos 3 minutos), con un agente de "
            f"usuario identificable y un máximo de {scraper.MAX_PETICIONES} peticiones por comercio. En el servidor "
            "publicado los comercios suelen bloquear estas consultas: si ocurre, la aplicación lo indicará y podrá "
            "usar el modo sin conexión.")

# [CAMBIO]: el botón: un comercio a la vez dentro de st.status, para mostrar el avance (Anexo B).
if st.button("Actualizar precios", type="primary"):
    try:
        id_ejecucion = actualizacion.iniciar_actualizacion(offline, id_elegido)
    except (FileNotFoundError, ValueError) as error:
        st.error(f"No se pudo iniciar la actualización: {error}")
        st.stop()
    filas = []
    with st.status(f"Actualizando precios · ejecución {id_ejecucion}…", expanded=True) as estado:
        for comercio, datos in scraper.COMERCIOS.items():
            st.write(f"Consultando {datos['nombre']}…")
            fila = actualizacion.actualizar_comercio(comercio, id_ejecucion, offline)
            filas.append(fila)
            st.write(f"→ {datos['nombre']}: ejecución **{fila['estado']}**, {fila['recolectados']} productos "
                     f"recolectados, {fila['observaciones_nuevas']} observaciones nuevas.")
        fallidos = [f["comercio"] for f in filas if f["estado"] == "fallida"]
        if len(fallidos) == len(filas):
            estado.update(label="La actualización falló en todos los comercios", state="error")
        elif fallidos:
            estado.update(label=f"Actualización terminada con fallas en: {', '.join(fallidos)}", state="error")
        else:
            estado.update(label=f"Actualización terminada · ejecución {id_ejecucion}", state="complete")
    componentes.limpiar_cache()  # indicadores, gráficos y tablas se recalculan con los datos nuevos
    st.session_state["resumen_actualizacion"] = pd.DataFrame(filas)
    st.session_state["modo_actualizacion"] = "sin conexión" if offline else "en línea"

# [CAMBIO]: resumen por comercio y mensajes claros cuando un comercio falla.
if "resumen_actualizacion" in st.session_state:
    resumen = st.session_state["resumen_actualizacion"]
    st.subheader(f"Resumen por comercio · ejecución {resumen['id_ejecucion'].iloc[0]} "
                 f"({st.session_state['modo_actualizacion']})")
    st.dataframe(resumen[list(COLUMNAS_RESUMEN)].rename(columns=COLUMNAS_RESUMEN), hide_index=True,
                 width="stretch")
    for fila in resumen.itertuples():
        if fila.estado == "fallida":
            consejo = "" if fila.modo == "sin conexión" else (
                " Si la aplicación está en el servidor publicado, es probable que el comercio bloquee las "
                "consultas desde allí: use el modo sin conexión.")
            st.error(f"{fila.comercio}: no se pudieron obtener datos. Motivo: {fila.motivo}.{consejo}")
        elif fila.estado == "parcial":
            st.warning(f"{fila.comercio}: ejecución parcial. {fila.motivo}")
    st.caption("Productos nuevos: anuncios que no estaban en la base. No observados: anuncios vistos antes que no "
               "aparecieron en esta ejecución (no significa agotados ni retirados). Rechazados: no superaron la "
               "validación y quedaron en la tabla `rechazos` con su motivo.")
