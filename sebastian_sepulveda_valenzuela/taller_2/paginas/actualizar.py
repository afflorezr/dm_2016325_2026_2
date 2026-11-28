"""
paginas/actualizar.py
====================
Página de actualización de precios (Taller 2 - Módulo 2).
Permite ejecutar recolección en línea (scraping real con st.status)
o modo sin conexión (reprocesamiento desde raw/) con tolerancia a fallas.
"""

import time
import sqlite3
import pandas as pd
import streamlit as st
from pathlib import Path

# Importar funciones oficiales del scraper sin duplicar lógica
from scraper import (
    COMERCIOS,
    recolectar_comercio,
    get_available_raw_dates,
    construir_correspondencia,
    verificar_conectividad_red,
    DB_PATH
)
from ui_comun import aplicar_estilos_comercio, mostrar_alerta_info

st.header("🔄 Actualización de Precios")
st.markdown("""
Este módulo permite sincronizar la base de datos ejecutando el módulo de web scraping oficial sobre los tres comercios 
(**Olímpica, Jumbo, Éxito**). Cada comercio se procesa en una transacción aislada (`BEGIN ... COMMIT / ROLLBACK`), 
garantizando tolerancia completa ante fallos de red o bloqueos antibot.
""")

# Diagnóstico de conectividad con servidores
with st.expander("🌐 Diagnóstico de conectividad de red y servidores", expanded=False):
    st.caption("Verifica si el entorno de ejecución (local o Streamlit Community Cloud) tiene salida directa a las APIs de catálogo.")
    if st.button("Verificar conectividad ahora", key="btn_check_net"):
        with st.spinner("Comprobando endpoints..."):
            estado_red = verificar_conectividad_red()
            cols = st.columns(len(estado_red))
            for col, (com, est) in zip(cols, estado_red.items()):
                with col:
                    if "disponible" in est:
                        st.success(f"**{com}**\n\n✅ En línea")
                    elif "403" in est:
                        st.warning(f"**{com}**\n\n🛡️ Protegido ({est})")
                    else:
                        st.error(f"**{com}**\n\n❌ {est}")

st.divider()

# Selector de modo
st.subheader("1. Configuración de la ejecución")
modo = st.radio(
    "Seleccione el modo de actualización:",
    ["Sin conexión (reprocesar copias crudas desde raw/)", "En línea (scraping en vivo a APIs de comercio)"],
    index=0,
    help="El modo sin conexión garantiza reproducibilidad inmediata sin riesgo de bloqueos de IP."
)

from_raw = "Sin conexión" in modo
fecha_offline = None

if from_raw:
    fechas_disponibles = get_available_raw_dates()
    if fechas_disponibles:
        fecha_offline = st.selectbox(
            "Seleccione la fecha de captura cruda a reprocesar:",
            fechas_disponibles,
            index=len(fechas_disponibles) - 1,
            help="Fechas almacenadas en formato raw/<Comercio>/<YYYY-MM-DD>/*.json.gz"
        )
        st.info(f"📂 Se reprocesarán las capturas crudas correspondientes al día **{fecha_offline}**.")
    else:
        st.warning("⚠️ No se encontraron carpetas con fechas válidas en `raw/`.")
else:
    st.warning("⚠️ **Atención:** En plataformas en la nube (como Streamlit Community Cloud) los comercios pueden bloquear las solicitudes con HTTP 403 (Cloudflare). Si el scraping en vivo falla, utilice el modo sin conexión.")

# Botón de actualización
st.subheader("2. Ejecutar recolección")
if st.button("🚀 Iniciar Actualización de Precios", type="primary", width="stretch"):
    resumen_total = []
    
    with st.status("Actualizando catálogo de precios...", expanded=True) as status_box:
        conn = sqlite3.connect(DB_PATH)
        
        for comercio in COMERCIOS:
            st.write(f"⏳ **Consultando {comercio}...**")
            t_inicio = time.time()
            
            # Ejecutar recolección transaccional por comercio
            res = recolectar_comercio(
                comercio=comercio,
                conn=conn,
                from_raw=from_raw,
                fecha_offline=fecha_offline
            )
            t_duracion = round(time.time() - t_inicio, 1)
            
            if res["estado"] == "completa":
                st.write(f"✅ **{comercio}:** Completado exitosamente ({res['recolectados']} observaciones en {t_duracion}s)")
            elif res["estado"] == "parcial":
                st.write(f"⚠️ **{comercio}:** Parcial — {res['nota']} ({res['recolectados']} obs en {t_duracion}s)")
            else:
                st.write(f"❌ **{comercio}:** Falló — {res['nota']}")
            
            resumen_total.append(res)
        
        st.write("🔄 **Actualizando correspondencia de los 8 comparables canónicos...**")
        n_comp = construir_correspondencia(DB_PATH)
        st.write(f"✨ Homologación finalizada: {n_comp} productos comparables vigentes.")
        
        conn.close()
        status_box.update(label="¡Actualización de precios finalizada!", state="complete", expanded=False)
    
    # Invalida la caché de Streamlit para reflejar los nuevos datos
    st.cache_data.clear()
    
    # 3. Mostrar resumen final estructurado
    st.subheader("3. Resumen de la Ejecución por Comercio")
    df_resumen = pd.DataFrame(resumen_total)[[
        "comercio", "estado", "recolectados", "nuevos", "cambios_precio",
        "no_observados", "rechazados", "descartados", "nota"
    ]]
    df_resumen.columns = [
        "Comercio", "Estado", "Recolectados", "Nuevos", "Cambios de Precio",
        "No Observados", "Rechazados", "Descartados", "Nota / Causa"
    ]
    
    st.dataframe(
        df_resumen,
        width="stretch",
        hide_index=True
    )
    
    st.success("✅ La base de datos y la caché han sido actualizadas. Puede navegar a las secciones de Resumen, Explorar o Cambios de Precio para visualizar los nuevos datos.")
    
    if st.button("🔄 Refrescar visualizaciones"):
        st.rerun()
