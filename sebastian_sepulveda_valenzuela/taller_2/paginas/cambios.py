"""
paginas/cambios.py
==================
Página de Cambios de Precio (Módulo 6, 8.2).
Compara dos sesiones de recolección y muestra las variaciones de precio
en el mismo anuncio y comercio: subidas, bajadas (en COP y porcentaje),
nuevos en catálogo y productos que dejaron de observarse.
Incluye umbral ajustable y resaltado analítico.
"""

import pandas as pd
import streamlit as st
import plotly.express as px

from db import (
    obtener_sesiones_disponibles,
    obtener_cambios_precio_sesiones
)
from ui_comun import (
    COLORES_COMERCIO,
    formato_cop,
    formato_porcentaje,
    aplicar_estilos_comercio
)

aplicar_estilos_comercio()

st.title("📈 Cambios y Evolución de Precios")
st.caption("Rastreo formal de variaciones de precio en el mismo anuncio y comercio entre dos sesiones de recolección.")

# 1. Dos selectores de sesión de recolección y umbral ajustable
sesiones = obtener_sesiones_disponibles()

if not sesiones:
    st.warning("⚠️ No se registran sesiones de recolección en la base de datos.")
    st.stop()

opciones_sesiones = [
    f"{s['sesion_id']} — {s['fecha']} ({len(s['comercios'])} comercios: {', '.join(s['comercios'])})"
    for s in sesiones
]

# Por defecto: sesión objetivo es la más reciente (índice 0), base es la segunda más reciente (índice 1)
idx_obj_default = 0
idx_base_default = 1 if len(opciones_sesiones) > 1 else 0

col_sel1, col_sel2, col_sel3 = st.columns([2, 2, 1])

with col_sel1:
    sel_base = st.selectbox(
        "1. Sesión Base (Anterior):",
        options=opciones_sesiones,
        index=idx_base_default,
        help="Sesión temporal de origen para contrastar el precio inicial."
    )

with col_sel2:
    sel_obj = st.selectbox(
        "2. Sesión Objetivo (Reciente):",
        options=opciones_sesiones,
        index=idx_obj_default,
        help="Sesión temporal de destino para medir la evolución del precio."
    )

with col_sel3:
    umbral_pct = st.slider(
        "Umbral variación mínima (%):",
        min_value=0.0,
        max_value=50.0,
        value=0.0,
        step=1.0,
        help="Filtra productos cuyo cambio porcentual absoluto supere este porcentaje."
    )

sesion_base_id = sel_base.split(" — ")[0]
sesion_obj_id = sel_obj.split(" — ")[0]

if sesion_base_id == sesion_obj_id and len(sesiones) > 1:
    st.info("ℹ️ Ha seleccionado la misma sesión como base y objetivo. Los productos aparecerán sin cambios de precio. Seleccione dos sesiones distintas para comparar evolución.")

# 2. Consultar variaciones entre las dos sesiones
df_cambios = obtener_cambios_precio_sesiones(
    sesion_a=sesion_base_id,
    sesion_b=sesion_obj_id,
    umbral_pct=umbral_pct
)

if df_cambios.empty:
    st.info("ℹ️ No se detectaron productos o variaciones de precio para las sesiones y umbral seleccionados.")
else:
    # 3. Métricas resumen de cambios
    subidas = df_cambios[df_cambios["Tipo de Cambio"] == "subida"]
    bajadas = df_cambios[df_cambios["Tipo de Cambio"] == "bajada"]
    sin_cambio = df_cambios[df_cambios["Tipo de Cambio"] == "sin_cambio"]
    nuevos = df_cambios[df_cambios["Tipo de Cambio"] == "nuevo"]
    no_observados = df_cambios[df_cambios["Tipo de Cambio"] == "no_observado"]

    c1, c2, c3, c4, c5 = st.columns(5)
    with c1:
        with st.container(border=True):
            st.metric("Total Cambios Reales", f"{len(subidas) + len(bajadas):,}".replace(",", "."))
    with c2:
        with st.container(border=True):
            st.metric("⬆️ Subidas de Precio", f"{len(subidas):,}".replace(",", "."), delta=f"+{len(subidas)} alzas", delta_color="inverse")
    with c3:
        with st.container(border=True):
            st.metric("⬇️ Bajadas de Precio", f"{len(bajadas):,}".replace(",", "."), delta=f"-{len(bajadas)} rebajas", delta_color="normal")
    with c4:
        with st.container(border=True):
            st.metric("✨ Nuevos en Catálogo", f"{len(nuevos):,}".replace(",", "."))
    with c5:
        with st.container(border=True):
            st.metric("🚫 Dejaron de Observarse", f"{len(no_observados):,}".replace(",", "."))

    st.divider()

    # 4. Gráfico de dispersión de variaciones porcentuales
    df_graf = df_cambios[df_cambios["Tipo de Cambio"].isin(["subida", "bajada"])]
    if not df_graf.empty:
        st.subheader("📊 Distribución de Variaciones Porcentuales por Comercio")
        fig_var = px.strip(
            df_graf,
            x="Comercio",
            y="Variación (%)",
            color="Comercio",
            hover_name="Producto",
            hover_data=["Precio Anterior", "Precio Nuevo", "Variación (COP)"],
            color_discrete_map=COLORES_COMERCIO,
            title=f"Magnitud de Variaciones de Precio (%) entre {sesion_base_id} y {sesion_obj_id}"
        )
        fig_var.update_layout(yaxis_ticksuffix=" %", showlegend=False)
        st.plotly_chart(fig_var, width="stretch")

    # 5. Filtro de tipo de cambio y tabla interactiva
    st.subheader("📑 Detalle de Productos Comparados")

    col_f1, col_f2 = st.columns([2, 1])
    with col_f1:
        filtro_tipo = st.multiselect(
            "Filtrar por tipo de cambio:",
            options=["subida", "bajada", "nuevo", "no_observado", "sin_cambio"],
            default=["subida", "bajada", "nuevo", "no_observado"] if (len(subidas) + len(bajadas) + len(nuevos) + len(no_observados)) > 0 else ["sin_cambio"]
        )
    with col_f2:
        umbral_resalte = st.number_input(
            "Resaltar variaciones mayores a (%):",
            min_value=1.0,
            max_value=100.0,
            value=10.0,
            step=1.0,
            help="Resalta visualmente en la tabla productos con variación superior a este porcentaje."
        )

    df_tabla = df_cambios[df_cambios["Tipo de Cambio"].isin(filtro_tipo)] if filtro_tipo else df_cambios

    col_config = {
        "Precio Anterior": st.column_config.NumberColumn(format="$ %d"),
        "Precio Nuevo": st.column_config.NumberColumn(format="$ %d"),
        "Variación (COP)": st.column_config.NumberColumn(format="$ %+d"),
        "Variación (%)": st.column_config.NumberColumn(format="%+.1f %%"),
        "Tipo de Cambio": st.column_config.TextColumn(),
        "URL": st.column_config.LinkColumn("Enlace Tienda")
    }

    st.dataframe(
        df_tabla,
        column_config=col_config,
        width="stretch",
        hide_index=True,
        height=480
    )
