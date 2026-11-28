"""Página Resumen: indicadores (calculados con SQL) en tarjetas."""
import streamlit as st

import analisis as A
import servicios as sv
import ui


def cuerpo():
    f = sv.filtros_actuales()
    st.title("Resumen del mercado")
    ui.banner_datos()
    conteo = sv.consultar("conteo_seleccion", f)
    if conteo.empty:
        ui.sin_datos()
        return
    ref = sv.consultar("ejecucion_referencia", f)
    periodo = f"ejecución {A.etiqueta_ejecucion(f.ejecucion_id)}" if f.ejecucion_id else "última ejecución de cada comercio"
    ult = sv.consultar("ultima_ejecucion")
    promo = sv.consultar("indicador_promocion", f)
    med = sv.consultar("mediana_global", f)
    ahorro = sv.consultar("ahorro_por_producto", ref)
    cam = sv.consultar("cambios_ultima_ejecucion")

    c = st.columns(4)
    with c[0]:
        ui.tarjeta("Productos en la selección", A.n_(int(conteo["productos"].sum())), f"anuncios únicos · {periodo}")
    with c[1]:
        ui.tarjeta("Observaciones", A.n_(int(conteo["observaciones"].sum())),
                   f"filas de precio (con precio: {A.n_(int(conteo['con_precio'].sum()))}) · {periodo}")
    with c[2]:
        ui.tarjeta("Última ejecución", A.etiqueta_ejecucion(ult["ejecucion_id"]) if ult else "—",
                   f"fecha y hora · estado: {ult['estado'] if ult else '—'}")
    with c[3]:
        ui.tarjeta("En promoción", A.pct(promo["pct"]), f"% de productos con precio · {periodo}")
    c = st.columns(4)
    with c[0]:
        ui.tarjeta("Precio mediano", A.cop(med), f"COP, productos con precio · {periodo}")
    with c[1]:
        if len(ahorro):
            top = ahorro.iloc[0]
            ui.tarjeta("Ahorro máximo entre comercios", A.cop(top["ahorro_cop"]),
                       f"{top['nombre_std']} ({A.pct(top['ahorro_pct'])}) · ejecución {A.etiqueta_ejecucion(ref)}")
        else:
            ui.tarjeta("Ahorro máximo entre comercios", "—", "sin comparables en al menos dos comercios")
    with c[2]:
        ui.tarjeta("Cambios de precio", A.n_(cam["cambios_precio"]), "productos cuyo precio cambió · última ejecución")
    with c[3]:
        ui.tarjeta("No observados", A.n_(cam["no_observados"]),
                   "productos vistos antes que no aparecieron · última ejecución")

    st.subheader("Productos y observaciones por comercio")
    st.dataframe(conteo.rename(columns={"comercio": "Comercio", "productos": "Productos", "observaciones": "Observaciones",
                                        "con_precio": "Con precio"}), hide_index=True)
    st.subheader("Mediana de precio por subcategoría (COP)")
    mediana = sv.consultar("mediana_precio", f)
    if mediana.empty:
        ui.sin_datos("No hay precios en la selección.")
    else:
        st.dataframe(mediana.rename(columns={"subcategoria": "Subcategoría", "mediana": "Mediana (COP)", "n": "Productos con precio"}),
                     hide_index=True)
    if len(ahorro):
        st.subheader("Ahorro por producto comparable")
        st.caption(f"Diferencia entre el comercio más caro y el más barato · ejecución {A.etiqueta_ejecucion(ref)} · COP")
        t = ahorro[["nombre_std", "minimo", "maximo", "ahorro_cop", "ahorro_pct", "mas_baratos"]].rename(columns={
            "nombre_std": "Producto", "minimo": "Mínimo", "maximo": "Máximo", "ahorro_cop": "Ahorro (COP)",
            "ahorro_pct": "Ahorro (%)", "mas_baratos": "Más barato en"})
        st.dataframe(t, hide_index=True)


ui.ejecutar_seguro(cuerpo)
