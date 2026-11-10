"""Página Gráficos: cuatro gráficos interactivos (plotly)."""
import streamlit as st

import analisis as A
import graficos as G
import servicios as sv
import ui


def cuerpo():
    f = sv.filtros_actuales()
    st.title("Gráficos")
    ui.banner_datos()
    ref = sv.consultar("ejecucion_referencia", f)
    t1, t2, t3, t4 = st.tabs(["Evolución del precio", "Precio por unidad", "Distribución", "¿Dónde pago de más?"])

    with t1:
        prods = sv.consultar("productos_comparables")
        if prods.empty:
            ui.sin_datos("Aún no hay productos comparables.")
        else:
            nombre = st.selectbox("Producto comparable", prods["nombre_std"].tolist(), key="g_producto")
            pid = int(prods.loc[prods["nombre_std"] == nombre, "producto_id"].iloc[0])
            serie = sv.consultar("serie_precio_producto", pid)
            fig = G.evolucion_precio(serie, nombre)
            if fig is None:
                ui.sin_datos("Ese producto no tiene precios disponibles.")
            else:
                st.plotly_chart(fig)
                if serie["ejecucion_id"].nunique() < 2:
                    st.info("Solo hay una ejecución con precio para este producto; al actualizar los datos aparecerá la evolución.")
                st.caption("Precio en COP. Cada punto es una ejecución; una serie por comercio.")

    with t2:
        pu = sv.consultar("precio_unitario_comparables", ref)
        if pu.empty:
            ui.sin_datos("No hay precios unitarios comparables.")
        else:
            st.caption(f"Presentaciones idénticas en los tres comercios · ejecución {A.etiqueta_ejecucion(ref)} · "
                       "una gráfica por unidad (no se mezclan unidades).")
            for unidad in sorted(pu["unidad_base"].dropna().unique()):
                fig = G.precio_por_unidad(pu, unidad)
                if fig is not None:
                    st.plotly_chart(fig)

    with t3:
        dist = sv.consultar("distribucion_precios", f)
        if dist.empty:
            ui.sin_datos("No hay precios en la selección.")
        else:
            log = st.toggle("Escala logarítmica", value=True, key="g_log",
                            help="Los precios van de unos pocos miles a más de cien mil pesos; la escala logarítmica los hace legibles.")
            st.plotly_chart(G.distribucion(dist, log))
            st.caption("Cada punto es un producto con precio en la selección actual (filtros del panel lateral). Precios en COP.")

    with t4:
        sp = sv.consultar("sobreprecio_comparables", ref)
        fig = G.sobreprecio_heatmap(sp)
        if fig is None:
            ui.sin_datos("No hay productos comparables con precio en al menos dos comercios.")
        else:
            st.plotly_chart(fig)
            medio = sp.groupby("comercio")["sobreprecio_pct"].mean().sort_values()
            st.caption(f"Ejecución {A.etiqueta_ejecucion(ref)}. Sobreprecio promedio por comercio: " +
                       " · ".join(f"{c}: {A.pct(v)}" for c, v in medio.items()))


ui.ejecutar_seguro(cuerpo)
