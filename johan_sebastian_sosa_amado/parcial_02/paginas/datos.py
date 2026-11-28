"""Tabla de productos con los filtros del panel, para ordenar, buscar y
descargar en CSV."""

import streamlit as st

import ui

st.title("Productos")
ui.aviso_fecha()
tabla = ui.productos_filtrados(ui.filtros_actuales())
if ui.sin_datos(tabla):
    st.stop()
if len(tabla) > ui.db.LIMITE_TABLA:
    tabla = tabla.head(ui.db.LIMITE_TABLA)
    st.info("La tabla muestra las primeras 2.000 filas. Use los filtros del panel para ver el resto.")

tabla = tabla.assign(comercio=lambda d: d["comercio"].map(ui.NOMBRES),
                     promocion=lambda d: d["promocion"].map({1: "sí", 0: "no"}),
                     presentacion=lambda d: d["presentacion"].fillna("").str.strip().where(
                         d["presentacion"].fillna("").str.strip() != "",
                         d["contenido_total"].map(lambda x: "" if x != x else f"{x:g}") + " " +
                         d["unidad_normalizada"].fillna("")))
st.caption("Precio vacío: el sitio mostraba el producto como agotado y no publicaba precio (no se inventa un valor).")
st.write(f"{len(tabla)} productos. Haga clic en el encabezado de una columna para ordenar; "
         "use la lupa de la tabla para buscar.")
vista = tabla.assign(fecha_hora_consulta=lambda d: d["fecha_hora_consulta"].map(ui.fecha_corta))
st.dataframe(ui.formato_tabla(vista, con_decimal=["precio_unitario"]), hide_index=True, width="stretch", placeholder="",
             column_order=["comercio", "nombre", "marca", "presentacion", "precio", "precio_unitario",
                           "unidad_normalizada", "promocion", "disponibilidad", "fecha_hora_consulta", "url"],
             column_config={
                 "comercio": "Comercio", "nombre": "Nombre", "marca": "Marca", "presentacion": "Presentación",
                 "precio": "Precio (COP)", "precio_unitario": "Precio por unidad de contenido (COP)",
                 "unidad_normalizada": "Unidad", "promocion": "Promoción", "disponibilidad": "Disponibilidad",
                 "fecha_hora_consulta": "Fecha de consulta",
                 "url": st.column_config.LinkColumn("Anuncio", display_text="abrir")})
st.download_button("Descargar CSV", tabla.to_csv(index=False).encode("utf-8-sig"),
                   file_name="productos_filtrados.csv", mime="text/csv")
