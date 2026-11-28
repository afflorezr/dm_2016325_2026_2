# -*- coding: utf-8 -*-
"""Página Actualizar: ejecuta el scraper del Taller 1 (scraper.py) mostrando el avance por comercio."""
import os
import re
from pathlib import Path

import pandas as pd
import streamlit as st

import datos
import db
import scraper
import ui

ui.verificar_base()
v = datos.version()
RAW = str(Path(__file__).resolve().parent.parent / "raw")

st.title("Actualizar precios")
st.write("Este botón ejecuta el **mismo scraper** del Taller 1 (`scraper.py`) sobre los tres comercios, valida cada observación "
         "y agrega las nuevas a la base **sin sobrescribir** las anteriores. Cada comercio se inserta en su propia transacción: "
         "si uno falla, los demás continúan.")
ui.aviso("<b>En la versión publicada</b> los comercios suelen bloquear a los servidores de la nube, y los cambios en la base "
         "no se conservan al reiniciar la app. Si la consulta en línea falla, usa el <b>modo sin conexión</b>: reprocesa las copias "
         "guardadas en <code>raw/</code>. La actualización en línea funciona al ejecutar la app en tu computador.")

offline = st.checkbox("Modo sin conexión (reprocesar las copias de raw/)", value=False)
contacto = ""
if not offline:
    por_defecto = os.environ.get("SCRAPER_CONTACTO", "")
    try:
        por_defecto = st.secrets.get("SCRAPER_CONTACTO", por_defecto)
    except Exception:
        pass
    contacto = st.text_input("Correo de contacto (viaja en el User-Agent para que los sitios puedan identificar el taller)",
                             value=por_defecto, max_chars=80)

if st.button("Actualizar precios", type="primary"):
    if not offline and not re.fullmatch(r"[\w.+-]+@[\w-]+(\.[\w-]+)+", contacto or ""):
        st.error("Escribe un correo válido para identificar el scraper.")
        st.stop()
    if not offline:
        scraper.configurar_contacto(contacto)

    with st.status("Actualizando precios...", expanded=True) as estado:
        def avance(evento, comercio, fila):
            if evento == "inicio":
                st.write(f"Consultando {comercio}...")
            else:
                icono = {"completa": "✅", "parcial": "⚠️", "fallida": "❌"}.get(fila["estado"], "•")
                st.write(f"{icono} {comercio}: {fila['estado']} · {fila['registros']} registros, {fila['insertados']} nuevos")

        try:
            resultado = scraper.recolectar_todo(db_path=db.DB_DEFECTO, raw_dir=RAW, offline=offline,
                                                progreso=avance, verbose=False)
        except Exception as e:
            estado.update(label="La actualización no pudo completarse", state="error")
            st.error("No fue posible actualizar. Si el sitio bloquea la consulta, prueba el modo sin conexión. "
                     f"Detalle técnico: {type(e).__name__}")
            st.stop()
        estado.update(label="Actualización terminada", state="complete")

    datos.limpiar()                                   # los indicadores y gráficos se recalculan con los datos nuevos
    v = datos.version()
    st.subheader("Resumen por comercio")
    filas = []
    for ejec in sorted({r["id_ejecucion"] for r in resultado}):
        res = datos.resumen(ejec, v)
        res.insert(0, "ejecución", ejec)
        filas.append(res[res.comercio.isin([r["comercio"] for r in resultado if r["id_ejecucion"] == ejec])])
    resumen = pd.concat(filas, ignore_index=True) if filas else pd.DataFrame()
    ui.mostrar_tabla(resumen.rename(columns={"comercio": "Comercio", "estado": "Estado", "recolectados": "Productos recolectados",
                                              "rechazados": "Rechazados por validación", "nuevos": "Productos nuevos",
                                              "cambios_de_precio": "Cambios de precio", "no_observados": "No observados"}),
                     hide_index=True)
    for r in resultado:
        if r["estado"] != "completa":
            st.warning(f"**{r['comercio']}** quedó {r['estado']}: {(r['detalle'] or '')[:300]}")
    st.success("Los indicadores, gráficos y tablas ya usan los datos nuevos; no hace falta reiniciar la aplicación.")
    st.caption("Un producto «no observado» no se interpreta como agotado ni retirado sin evidencia.")
