"""Página Productos: tabla con los productos filtrados y descarga en CSV (§7.5)."""
import pandas as pd
import streamlit as st

import db
import interfaz

st.title("Productos")

with interfaz.protegido():
    interfaz.fecha_de_los_datos()
    f = interfaz.filtros_activos()
    datos = db.productos(f)
    st.caption(f"Periodo: {interfaz.describir_periodo(f)}. Una fila por anuncio (su observación más "
               "reciente en el periodo). Haz clic en el título de una columna para ordenar y usa la "
               "lupa de la tabla para buscar.")
    if datos.empty:
        interfaz.sin_datos()
        st.stop()

    # Presentación legible: concentración + forma + contenido (ej. "500 MG · TABLETA · 10 unidad")
    contenido = datos["contenido_total"].map(lambda x: interfaz.numero(x) if pd.notna(x) else None)
    datos["presentacion"] = [
        " · ".join(p for p in (c, fo, f"{n} {u}" if n and u else None) if p)
        for c, fo, n, u in zip(datos["concentracion"].fillna(""), datos["forma"].fillna(""),
                               contenido, datos["unidad_normalizada"])]
    datos["promocion"] = datos["promocion"].map({1: "Sí", 0: "No"})
    datos["disponibilidad"] = datos["disponibilidad"].str.capitalize()
    datos["unidad_precio"] = datos["unidad_normalizada"].map(lambda u: f"COP por {u}" if u else None)

    c1, c2, c3 = st.columns(3)
    c1.metric("Productos en la tabla", interfaz.numero(len(datos)), border=True)
    c2.metric("Con precio", interfaz.numero(datos["precio"].notna().sum()), border=True)
    c3.metric("En promoción", interfaz.numero((datos["promocion"] == "Sí").sum()), border=True)

    columnas = ["comercio", "nombre", "marca", "laboratorio", "subcategoria", "presentacion",
                "precio", "precio_lista", "precio_unitario", "unidad_precio", "promocion",
                "disponibilidad", "fecha_consulta", "url_producto", "id_producto", "sku_comercio",
                "ean", "id_ejecucion"]
    interfaz.tabla(
        datos[columnas], hide_index=True, width="stretch", height=560,
        column_config={
            "comercio": "Comercio", "nombre": st.column_config.TextColumn("Nombre", width="large"),
            "marca": "Marca", "laboratorio": "Laboratorio", "subcategoria": "Subcategoría",
            "presentacion": "Presentación",
            "precio": interfaz.columna_cop("Precio (COP)", "Precio de venta publicado (con IVA)."),
            "precio_lista": interfaz.columna_cop("Precio de lista (COP)", "Precio antes del descuento."),
            "precio_unitario": interfaz.columna_cop("Precio unitario (COP)",
                                                    "Precio dividido por el contenido total."),
            "unidad_precio": "Unidad del precio unitario",
            "promocion": "Promoción", "disponibilidad": "Disponibilidad",
            "fecha_consulta": "Fecha de consulta (hora de Colombia)",
            "url_producto": st.column_config.LinkColumn("Anuncio", display_text="Abrir"),
            "id_producto": "Comparable", "sku_comercio": "SKU", "ean": "EAN",
            "id_ejecucion": "Ejecución"})
    interfaz.descargar_csv(datos[columnas], "productos_filtrados.csv",
                           "Descargar los productos filtrados (CSV)")
