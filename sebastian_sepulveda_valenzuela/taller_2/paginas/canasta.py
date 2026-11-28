"""
paginas/canasta.py
==================
Página de Simulación de Canasta Familiar de Aseo (Módulo 6, 8.3).
Permite seleccionar productos comparables y cantidades deseadas, calculando:
  - Costo total por comercio solo si este dispone de la totalidad de productos.
  - Costo óptimo combinado (comprando cada ítem en el comercio más barato).
  - Ahorro económico y porcentual frente al mejor comercio individual.
"""

import pandas as pd
import streamlit as st
import plotly.express as px

from db import (
    obtener_comparables_8_catalogo,
    obtener_precios_canasta,
    calcular_canasta_optima,
    obtener_opciones_filtros,
    obtener_sesiones_disponibles
)
from ui_comun import (
    COLORES_COMERCIO,
    formato_cop,
    formato_porcentaje,
    aplicar_estilos_comercio
)

aplicar_estilos_comercio()

st.title("🧺 Canasta Familiar de Aseo y Limpieza")
st.caption("Simulador inteligente de compra para optimizar el gasto familiar entre comercios.")

# Advertencia metodológica obligatoria (Módulo 6, 8.3)
st.warning(
    "⚠️ **Nota al consumidor:** El cálculo de la canasta se basa exclusivamente en los precios de catálogo capturados. "
    "**No incluye costos de envío/domicilio, montos mínimos de compra, costos de desplazamiento ni condiciones comerciales de tarjetas de crédito o fidelización.**"
)

# 1. Selector de sesión de recolección para la canasta (Módulo 6, 8.3)
sesiones = obtener_sesiones_disponibles()

opciones_sesiones = [
    f"{s['sesion_id']} — {s['fecha']} ({len(s['comercios'])} comercios: {', '.join(s['comercios'])})"
    for s in sesiones
]

sesion_sel = st.selectbox(
    "Seleccione la sesión de recolección para los precios:",
    options=opciones_sesiones,
    index=0,
    help="Garantiza que los precios de los 3 comercios correspondan a la misma recolección en el tiempo."
)

sesion_id_usar = sesion_sel.split(" — ")[0] if sesion_sel else None

# 2. Cargar catálogo de los 8 comparables canónicos y precios de la sesión
cat_comp = obtener_comparables_8_catalogo()
df_precios = obtener_precios_canasta(sesion_id_usar)

st.subheader("1. Seleccione los productos y cantidades para su canasta:")
st.caption("Ajuste las cantidades de cada artículo esencial según la necesidad de su hogar:")

# Selector de cantidades
items_seleccionados = {}
cols_prods = st.columns(2)

for i, (_, row) in enumerate(cat_comp.iterrows()):
    pid = int(row["producto_id"])
    col = cols_prods[i % 2]
    with col:
        with st.container(border=True):
            subcol1, subcol2 = st.columns([3, 1])
            with subcol1:
                st.markdown(f"**{row['nombre_referencia']}**")
                st.caption(f"Marca: **{row['marca']}** | Contenido: **{row['contenido_total']} {row['unidad_normalizada']}** | Subcategoría: {row['subcategoria']}")
            with subcol2:
                cant = st.number_input(
                    "Cantidad:",
                    min_value=0,
                    max_value=12,
                    value=1 if i in [0, 2, 4, 6] else 0,  # 4 productos seleccionados por defecto
                    step=1,
                    key=f"cant_{pid}"
                )
            if cant > 0:
                items_seleccionados[pid] = cant

st.divider()

# 3. Cálculo de la canasta con la función pura de db.py
if not items_seleccionados:
    st.info("ℹ️ Seleccione al menos un producto con cantidad mayor a cero para simular la canasta.")
else:
    resultado = calcular_canasta_optima(items_seleccionados, df_precios)
    
    st.subheader("2. Resultados del Comparativo de Canasta")
    
    # Tarjetas de costo por comercio
    c_cols = st.columns(3)
    comercios_nombres = ["Éxito", "Olímpica", "Jumbo"]
    
    for c_col, c_nombre in zip(c_cols, comercios_nombres):
        with c_col:
            with st.container(border=True):
                st.markdown(f"### {c_nombre}")
                costo = resultado["costo_por_comercio"].get(c_nombre)
                disponible = resultado["disponible_por_comercio"].get(c_nombre, False)
                faltantes = resultado["faltantes_por_comercio"].get(c_nombre, [])
                
                if disponible and costo is not None:
                    st.metric(label="Costo Total Canasta", value=formato_cop(costo))
                    if c_nombre == resultado["mejor_comercio_unico"]:
                        st.success("🥇 Mejor opción de compra en tienda única")
                else:
                    st.metric(label="Costo Total Canasta", value="Incompleta")
                    st.error(f"❌ No disponible: Faltan {len(faltantes)} producto(s) en este comercio.")
                    with st.expander("Ver faltantes"):
                        for f_pid in faltantes:
                            nom_f = cat_comp[cat_comp["producto_id"] == f_pid]["nombre_referencia"].values
                            st.write(f"- {nom_f[0] if len(nom_f) > 0 else f_pid}")

    st.divider()

    # Estrategia de optimización cruzada
    st.subheader("3. Estrategia Óptima de Compra Cruzada")
    st.caption("Comprando cada producto específico en el establecimiento que ofrece el precio más bajo:")

    m1, m2, m3 = st.columns(3)
    with m1:
        with st.container(border=True):
            st.metric(
                label="Costo Canasta Óptima Combinada",
                value=formato_cop(resultado["costo_optimo_total"]),
                help="Suma total comprando cada artículo en el comercio más barato."
            )
    with m2:
        with st.container(border=True):
            st.metric(
                label="Ahorro en Pesos (vs Mejor Tienda Única)",
                value=formato_cop(resultado["ahorro_cop"]),
                delta=f"- {formato_porcentaje(resultado['ahorro_pct'])}",
                delta_color="normal",
                help="Dinero ahorrado al combinar compras en lugar de comprar todo en un solo comercio."
            )
    with m3:
        with st.container(border=True):
            st.metric(
                label="Ahorro Porcentual",
                value=formato_porcentaje(resultado["ahorro_pct"]),
                help="Porcentaje de ahorro obtenido mediante compra inteligente cruzada."
            )

    # Desglose de la compra óptima
    if resultado["desglose_optimo"]:
        st.markdown("**Desglose de compras sugerido:**")
        df_desglose = pd.DataFrame(resultado["desglose_optimo"])
        df_desglose["Precio Unitario"] = df_desglose["precio_unitario"].apply(formato_cop)
        df_desglose["Subtotal"] = df_desglose["subtotal"].apply(formato_cop)
        df_desglose = df_desglose[["nombre", "comercio_elegido", "cantidad", "Precio Unitario", "Subtotal"]]
        df_desglose.columns = ["Producto", "Comercio Recomendado", "Cantidad", "Precio Unitario", "Subtotal"]

        st.dataframe(df_desglose, width="stretch", hide_index=True)

        # Gráfico de barras de costo por comercio
        df_bar = pd.DataFrame([
            {"Opción": c, "Costo (COP)": cost}
            for c, cost in resultado["costo_por_comercio"].items()
            if cost is not None
        ] + [
            {"Opción": "⚡ Combinada Óptima", "Costo (COP)": resultado["costo_optimo_total"]}
        ])
        
        if not df_bar.empty:
            fig_canasta = px.bar(
                df_bar,
                x="Opción",
                y="Costo (COP)",
                color="Opción",
                color_discrete_map={
                    "Olímpica": COLORES_COMERCIO["Olímpica"],
                    "Jumbo": COLORES_COMERCIO["Jumbo"],
                    "Éxito": COLORES_COMERCIO["Éxito"],
                    "⚡ Combinada Óptima": "#673AB7"
                },
                title="Comparativo de Costo de la Canasta Simulada",
                text_auto=".2s"
            )
            fig_canasta.update_layout(yaxis_tickformat="$,.0f", showlegend=False)
            st.plotly_chart(fig_canasta, width="stretch")
