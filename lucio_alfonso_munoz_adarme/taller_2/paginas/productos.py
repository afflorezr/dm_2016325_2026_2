import streamlit as st

import db
from comun import ETIQUETA, aviso_fallidas, panel_filtros

f = panel_filtros()
st.title("Productos")
st.caption(f"Presentaciones de la categoría en la ejecución {f['id_ej']}. Precios en COP; "
           "el precio por unidad es COP por g, ml o unidad, según la columna Unidad.")
aviso_fallidas(f["id_ej"])

datos = db.productos_filtrados(**f)
if datos.empty:
    st.warning("Ningún producto cumple los filtros elegidos. Pruebe con otra ejecución o quite algún filtro.")
    st.stop()

datos["comercio"] = datos["comercio"].map(ETIQUETA)
datos["promocion"] = datos["promocion"].map({1: "Sí", 0: "No"})
st.dataframe(datos, hide_index=True, column_config={
    "comercio": "Comercio", "nombre": "Nombre", "marca": "Marca", "subcategoria": "Subcategoría",
    "contenido": st.column_config.NumberColumn("Presentación", format="%,.0f"),
    "unidad": "Unidad",
    "precio": st.column_config.NumberColumn("Precio (COP)", format="$ %,.0f"),
    "precio_unidad": st.column_config.NumberColumn("Precio por unidad (COP)", format="$ %,.2f"),
    "precio_antes": st.column_config.NumberColumn("Precio antes (COP)", format="$ %,.0f"),
    "promocion": "Promoción", "disponibilidad": "Disponibilidad", "fecha_consulta": "Fecha de consulta",
    "url": st.column_config.LinkColumn("Anuncio"),
})
