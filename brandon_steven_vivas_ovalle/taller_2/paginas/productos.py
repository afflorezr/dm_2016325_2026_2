"""Página Productos: tabla filtrable, ordenable, con búsqueda y descarga CSV."""
import streamlit as st

import servicios as sv
import ui

ORDENES = {"Nombre": "nombre", "Precio": "precio", "Precio unitario": "precio_unitario", "Comercio": "comercio",
           "Fecha de consulta": "fecha"}


def cuerpo():
    f = sv.filtros_actuales()
    st.title("Productos")
    ui.banner_datos()
    c1, c2 = st.columns([2, 1])
    orden = c1.selectbox("Ordenar por", list(ORDENES), key="orden_tabla")
    desc = c2.toggle("Descendente", key="orden_desc")
    df = sv.consultar("tabla_productos", f, ORDENES[orden], desc)
    if df.empty:
        ui.sin_datos()
        return
    df = df.copy()
    df["es_promocion"] = df["es_promocion"].astype(bool)
    df["comparable"] = df["comparable"].astype(bool)
    st.caption(f"{len(df):,} productos · precios en COP · precio unitario por unidad base (unidad, g o mL) · "
               "las presentaciones con distinta unidad no son comparables entre sí.".replace(",", "."))
    st.dataframe(
        df, hide_index=True,
        column_order=["comercio", "nombre_original", "marca", "presentacion", "precio", "precio_unitario", "es_promocion",
                      "estado_disponibilidad", "fecha_hora_consulta", "url"],
        column_config={
            "comercio": "Comercio", "nombre_original": "Producto", "marca": "Marca", "presentacion": "Presentación",
            "precio": st.column_config.NumberColumn("Precio (COP)", format="$%d"),
            "precio_unitario": st.column_config.NumberColumn("Precio unitario (COP)", format="$%.2f"),
            "es_promocion": st.column_config.CheckboxColumn("Promoción"),
            "estado_disponibilidad": "Disponibilidad", "fecha_hora_consulta": "Fecha de consulta",
            "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir"),
        })
    st.download_button("⬇️ Descargar CSV (datos filtrados)", df.to_csv(index=False).encode("utf-8-sig"),
                       file_name="productos_filtrados.csv", mime="text/csv")


ui.ejecutar_seguro(cuerpo)
