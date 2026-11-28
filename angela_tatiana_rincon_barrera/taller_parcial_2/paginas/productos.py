import streamlit as st

import componentes as ui
import datos_cache as dc

f = st.session_state["filtros"]
st.title("Productos")
st.caption(f"Periodo: **{ui.descripcion_periodo(f)}**. Use los filtros del panel lateral; la tabla permite ordenar "
           "(clic en el encabezado), buscar (lupa de la tabla) y descargar los datos filtrados.")

tabla = dc.observaciones(f)
if tabla.empty:
    ui.sin_datos()
    st.stop()

tabla = tabla.assign(
    presentacion_norm=tabla["contenido_valor"].map(lambda v: ui.numero(v, 0) if v == v and v is not None else "")
    + " " + tabla["contenido_unidad"].fillna(""),
    unidad_ppu="COP/" + tabla["contenido_unidad"].fillna("—"),
    promocion=tabla["es_promocion"].map({1: "Sí", 0: "No"}),
    disponibilidad=tabla["disponibilidad"].map(ui.ETIQUETAS_DISPONIBILIDAD).fillna(tabla["disponibilidad"]),
    fecha_consulta=tabla["fecha_hora_consulta"].map(ui.fecha),
)
vista = tabla[["comercio", "nombre", "marca", "subcategoria", "presentacion_norm", "precio", "precio_lista",
               "precio_por_unidad", "unidad_ppu", "promocion", "disponibilidad", "fecha_consulta", "url"]]

st.write(f"**{ui.numero(len(vista))}** observaciones" + (" (se muestran las primeras 5.000)" if len(vista) >= 5000 else ""))
st.dataframe(
    ui.formato_tabla(vista, cop_cols=["precio", "precio_lista"], cop1_cols=["precio_por_unidad"]), hide_index=True, width="stretch", height=560,
    column_config={
        "comercio": "Comercio", "nombre": st.column_config.TextColumn("Nombre del anuncio", width="large"),
        "marca": "Marca", "subcategoria": "Subcategoría", "presentacion_norm": "Presentación (contenido)",
        "precio": "Precio (COP)", "precio_lista": "Precio de lista (COP)",
        "precio_por_unidad": st.column_config.Column("Precio unitario (COP)",
                                                     help="COP por mL, g o unidad, según la columna siguiente"),
        "unidad_ppu": "Unidad del precio unitario", "promocion": "Promoción", "disponibilidad": "Disponibilidad",
        "fecha_consulta": "Fecha de consulta", "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir"),
    },
)

csv = vista.rename(columns={"presentacion_norm": "presentacion", "precio": "precio_cop", "precio_lista": "precio_lista_cop",
                            "precio_por_unidad": "precio_unitario_cop"}).to_csv(index=False).encode("utf-8-sig")
st.download_button("Descargar CSV con los datos filtrados", csv, file_name="productos_filtrados.csv",
                   mime="text/csv", icon=":material/download:")
ui.nota_fecha_datos()
