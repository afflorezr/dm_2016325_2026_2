import pandas as pd
import streamlit as st

import scraper
from comun import ETIQUETA

st.title("Actualizar precios")
st.write("**En línea:** consulta los tres comercios con las funciones de `scraper.py`, valida las observaciones y "
         "agrega a la base solo las nuevas. Tarda unos 5 minutos.")
st.write("**Sin conexión:** vuelve a procesar las copias guardadas en `raw/`. No se conecta a ningún sitio y no "
         "duplica observaciones.")
st.info("En la versión publicada los comercios suelen bloquear el servidor (Éxito bloquea las consultas "
        "automáticas desde noviembre de 2026). Si un comercio falla, queda registrado con el motivo y se puede "
        "usar el modo sin conexión. Además, la plataforma no conserva los cambios de la base al reiniciarse.")

c = st.columns(2)
en_linea = c[0].button("Actualizar en línea", type="primary")
sin_conexion = c[1].button("Reprocesar raw/ (sin conexión)")

if en_linea or sin_conexion:
    resumen = []
    with st.status("Actualizando precios...", expanded=True) as estado:
        if en_linea:
            id_ej = scraper.nueva_ejecucion()
            for comercio in scraper.COMERCIOS:
                st.write(f"Consultando {ETIQUETA[comercio]}...")
                resumen.append(scraper.recolectar_comercio(comercio, online=True, id_ej=id_ej))
        else:
            for comercio in scraper.COMERCIOS:
                st.write(f"Reprocesando {ETIQUETA[comercio]}...")
                for manifiesto in sorted((scraper.RAW / scraper.CLAVES[comercio]).glob("*/*/manifiesto.json")):
                    resumen.append(scraper.recolectar_comercio(comercio, online=False, carpeta=manifiesto.parent))
        estado.update(label="Actualización terminada", state="complete")
    st.cache_data.clear()   # los indicadores, gráficos y tablas se recalculan con los datos nuevos

    tabla = pd.DataFrame(resumen)
    tabla["comercio"] = tabla["comercio"].map(ETIQUETA)
    for r in tabla[tabla["estado"] != "completa"].itertuples():
        st.warning(f"{r.comercio} ({r.id_ejecucion}): ejecución {r.estado}. Motivo: {r.motivo}")
    st.subheader("Resumen por comercio")
    st.dataframe(tabla, hide_index=True, column_config={
        "comercio": "Comercio", "id_ejecucion": "Ejecución", "estado": "Estado", "motivo": "Motivo",
        "productos": "Productos recolectados", "en_categoria": "En la categoría",
        "nuevos": "Productos nuevos", "cambios_precio": "Cambios de precio", "no_observados": "No observados",
        "insertadas": "Observaciones insertadas", "rechazadas": "Rechazadas", "comparables": "Comparables"})
    st.caption("Nuevos, cambios de precio y no observados se cuentan sobre las presentaciones de la categoría, "
               "frente a la ejecución anterior del mismo comercio.")
