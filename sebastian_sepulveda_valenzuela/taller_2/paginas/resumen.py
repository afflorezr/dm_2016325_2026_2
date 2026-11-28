"""
paginas/resumen.py
==================
Página principal de Resumen Ejecutivo (Módulo 5).
Presenta ≥6 tarjetas métricas calculadas con SQL y ≥4 gráficos interactivos Plotly.
"""

import streamlit as st
import plotly.express as px
import plotly.graph_objects as go

from db import (
    obtener_indicadores_generales,
    obtener_mediana_por_subcategoria,
    obtener_comparables_8_catalogo,
    obtener_serie_tiempo_comparable,
    obtener_precios_unitarios_comparables,
    obtener_distribucion_precios,
    obtener_frecuencia_comercio_mas_barato
)
from ui_comun import (
    COLORES_COMERCIO,
    formato_cop,
    formato_porcentaje,
    aplicar_estilos_comercio
)

aplicar_estilos_comercio()

st.title("📊 Resumen Ejecutivo del Mercado")
st.caption("Observatorio de precios en la categoría Cuidado y Limpieza del Hogar (Olímpica, Jumbo, Éxito)")

# 1. Obtener indicadores en SQL
ind = obtener_indicadores_generales()

# Fecha y estado de la última ejecución
ult_ejec = ind["ultima_ejecucion"]
fecha_txt = ult_ejec["fecha"][:19].replace("T", " ") if ult_ejec["fecha"] != "N/A" else "N/A"

st.markdown(f"**Última ejecución registrada:** `{ult_ejec['id']}` ({ult_ejec['comercio']}) — **Fecha:** `{fecha_txt}` — **Estado:** `{ult_ejec['estado'].upper()}`")

# 2. Tarjetas de métricas (st.metric dentro de st.container(border=True))
col1, col2, col3, col4 = st.columns(4)

with col1:
    with st.container(border=True):
        st.metric(
            label="Catálogo Activo",
            value=f"{ind['total_anuncios']:,}".replace(",", "."),
            help="Total de ofertas y SKUs únicos con precios capturados en los 3 comercios."
        )

with col2:
    with st.container(border=True):
        st.metric(
            label="Productos en Promoción",
            value=formato_porcentaje(ind["pct_promociones"]),
            help="Proporción de publicaciones cuyo precio de venta es inferior al precio de lista."
        )

with col3:
    with st.container(border=True):
        st.metric(
            label="Ahorro Máximo Canasta",
            value=formato_porcentaje(ind["ahorro_maximo"]["ahorro_pct"]),
            delta=formato_cop(ind["ahorro_maximo"]["ahorro_cop"]),
            delta_color="normal",
            help=f"Diferencia máxima entre el comercio más costoso y el más económico para: {ind['ahorro_maximo']['producto']}."
        )

with col4:
    with st.container(border=True):
        st.metric(
            label="Disponibilidad Agotada",
            value=formato_porcentaje(ind["pct_agotados"]),
            help="Porcentaje de productos con inventario cero (AvailableQuantity = 0) en el catálogo."
        )

# Fila 2 de métricas: Cobertura por comercio y variaciones de precio
col_c1, col_c2, col_c3, col_c4 = st.columns(4)

com_dict = {c["comercio"]: c["anuncios"] for c in ind["por_comercio"]}
with col_c1:
    with st.container(border=True):
        st.metric("Éxito (Anuncios)", f"{com_dict.get('Éxito', 0):,}".replace(",", "."))
with col_c2:
    with st.container(border=True):
        st.metric("Olímpica (Anuncios)", f"{com_dict.get('Olímpica', 0):,}".replace(",", "."))
with col_c3:
    with st.container(border=True):
        st.metric("Jumbo (Anuncios)", f"{com_dict.get('Jumbo', 0):,}".replace(",", "."))
with col_c4:
    with st.container(border=True):
        cambios = ind["cambios_ultima_ejec"]
        st.metric(
            "Cambios Última Ejecución",
            f"{cambios['total_cambios']} variaciones",
            delta=f"{cambios['subidas']} ⬆ / {cambios['bajadas']} ⬇",
            help="Número de anuncios que variaron de precio respecto a su observación inmediatamente anterior."
        )

st.divider()

# =====================================================================
# SECCIÓN 1: EVOLUCIÓN TEMPORAL DE PRECIOS (GRÁFICO 1)
# =====================================================================
st.subheader("📈 1. Evolución Temporal de Precios por Producto Comparable")
st.caption("Seleccione uno de los 8 productos comparables canónicos para rastrear la trayectoria histórica de su precio por comercio.")

cat_comp = obtener_comparables_8_catalogo()
if not cat_comp.empty:
    opciones_comp = {
        row["producto_id"]: f"{row['nombre_referencia']} ({row['contenido_total']} {row['unidad_normalizada']})"
        for _, row in cat_comp.iterrows()
    }
    prod_sel_id = st.selectbox(
        "Seleccione el producto a analizar:",
        options=list(opciones_comp.keys()),
        format_func=lambda x: opciones_comp[x]
    )

    df_serie = obtener_serie_tiempo_comparable(prod_sel_id)
    if not df_serie.empty:
        fig_serie = px.line(
            df_serie,
            x="fecha",
            y="precio_actual",
            color="comercio",
            markers=True,
            color_discrete_map=COLORES_COMERCIO,
            labels={"fecha": "Fecha y Hora de Consulta", "precio_actual": "Precio (COP)", "comercio": "Comercio"},
            title=f"Evolución Histórica — {opciones_comp[prod_sel_id]}"
        )
        fig_serie.update_layout(
            hovermode="x unified",
            yaxis_tickformat="$,.0f",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
        )
        st.plotly_chart(fig_serie, width="stretch")
    else:
        st.info("No se registran observaciones históricas para el producto seleccionado.")

st.divider()

# =====================================================================
# SECCIÓN 2: COMPARACIÓN DE PRECIO UNITARIO SIN MEZCLAR UNIDADES (GRÁFICO 2)
# =====================================================================
st.subheader("⚖️ 2. Comparación de Precio Unitario Homogéneo")
st.caption("Para evitar mezclas metodológicas espurias, los precios unitarios se segregan estrictamente por unidad normalizada (mL, g o unidad).")

tab_ml, tab_g, tab_und = st.tabs(["Líquidos ($ / mL)", "Sólidos / Polvos ($ / g)", "Artículos Contables ($ / unidad)"])

def render_grafico_unidad(unidad_str: str, titulo: str):
    df_u = obtener_precios_unitarios_comparables(unidad_str)
    if not df_u.empty:
        fig_bar = px.bar(
            df_u,
            x="nombre",
            y="precio_unitario",
            color="comercio",
            barmode="group",
            color_discrete_map=COLORES_COMERCIO,
            labels={"nombre": "Producto", "precio_unitario": f"Precio Unitario (COP / {unidad_str})", "comercio": "Comercio"},
            title=titulo
        )
        fig_bar.update_layout(
            yaxis_tickformat="$,.2f",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
            xaxis_tickangle=-15
        )
        st.plotly_chart(fig_bar, width="stretch")
    else:
        st.info(f"No hay productos comparables con unidad {unidad_str}.")

with tab_ml:
    render_grafico_unidad("mL", "Precio por Mililitro en Productos Líquidos (Detergentes, Lavalozas y Limpiadores)")

with tab_g:
    render_grafico_unidad("g", "Precio por Gramo en Detergentes en Polvo y Cremas Lavaplatos")

with tab_und:
    render_grafico_unidad("unidad", "Precio por Pieza en Esponjas y Fibras Abrasivas")

st.divider()

# =====================================================================
# SECCIÓN 3: DISTRIBUCIÓN DE PRECIOS POR COMERCIO (GRÁFICO 3)
# =====================================================================
st.subheader("📦 3. Distribución de Precios de la Categoría por Comercio")
st.caption("Dispersión, cuartiles y rango intercuartílico de precios en la categoría Aseo y Limpieza del Hogar.")

df_dist = obtener_distribucion_precios()
if not df_dist.empty:
    tipo_graf = st.radio("Formato de visualización de distribución:", ["Diagrama de Cajas (Boxplot)", "Violín (Densidad de Probabilidad)"], horizontal=True)
    
    if "Cajas" in tipo_graf:
        fig_dist = px.box(
            df_dist,
            x="comercio",
            y="precio_actual",
            color="comercio",
            color_discrete_map=COLORES_COMERCIO,
            points="outliers",
            labels={"comercio": "Comercio", "precio_actual": "Precio de Venta (COP)"},
            title="Distribución de Precios de Venta por Comercio"
        )
    else:
        fig_dist = px.violin(
            df_dist,
            x="comercio",
            y="precio_actual",
            color="comercio",
            box=True,
            points="outliers",
            color_discrete_map=COLORES_COMERCIO,
            labels={"comercio": "Comercio", "precio_actual": "Precio de Venta (COP)"},
            title="Densidad y Dispersión de Precios por Comercio"
        )
    
    fig_dist.update_layout(yaxis_tickformat="$,.0f", showlegend=False)
    st.plotly_chart(fig_dist, width="stretch")

st.divider()

# =====================================================================
# SECCIÓN 4: PREGUNTA AL CONSUMIDOR Y MEDIANAS SQL (GRÁFICO 4)
# =====================================================================
col_g4_left, col_g4_right = st.columns([1, 1])

with col_g4_left:
    st.subheader("🏆 4. ¿Qué comercio resulta más barato con mayor frecuencia?")
    st.caption("Frecuencia con la que cada establecimiento lidera el menor precio en los 8 productos comparables.")
    df_frec = obtener_frecuencia_comercio_mas_barato()
    if not df_frec.empty:
        fig_pie = px.pie(
            df_frec,
            names="Comercio",
            values="Veces Más Barato",
            color="Comercio",
            color_discrete_map=COLORES_COMERCIO,
            hole=0.4,
            title="Distribución de Liderazgo en Precios Mínimos"
        )
        fig_pie.update_traces(textposition='inside', textinfo='percent+label+value')
        st.plotly_chart(fig_pie, width="stretch")

with col_g4_right:
    st.subheader("📑 Precio Mediano por Subcategoría (Calculado en SQL)")
    st.caption("Cálculo formal mediante funciones de ventana analíticas en SQLite.")
    df_med = obtener_mediana_por_subcategoria()
    if not df_med.empty:
        df_med_fmt = df_med.copy()
        df_med_fmt["Precio Mediano (COP)"] = df_med_fmt["Precio Mediano (COP)"].apply(formato_cop)
        st.dataframe(df_med_fmt, width="stretch", hide_index=True)
