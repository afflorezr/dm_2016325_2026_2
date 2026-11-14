"""Catálogo: una foto de referencia de cada producto comparable. Las fotos
están guardadas en la carpeta imagenes/ y no cambian al actualizar precios."""

import streamlit as st

import ui

CARPETA_IMAGENES = ui.db.CARPETA / "imagenes"
EXTENSIONES = (".jpg", ".jpeg", ".png", ".webp")


def foto(producto_id):
    """Ruta de la foto del producto (por ejemplo imagenes/P01.jpg) o None."""
    for extension in EXTENSIONES:
        ruta = CARPETA_IMAGENES / f"{producto_id}{extension}"
        if ruta.exists():
            return ruta
    return None


st.title("Catálogo de productos comparables")
st.caption("Foto de referencia de cada producto que se compara entre comercios. "
           "Las fotos son fijas: no cambian al actualizar los precios.")

productos = ui.opciones()["productos"]
if ui.sin_datos(productos, "La base todavía no tiene productos comparables."):
    st.stop()

# Una fila de cuatro tarjetas por cada cuatro productos, en orden P01, P02...
filas = list(productos.itertuples())
for inicio in range(0, len(filas), 4):
    columnas = st.columns(4)
    for columna, fila in zip(columnas, filas[inicio:inicio + 4]):
        with columna.container(border=True):
            ruta = foto(fila.producto_id)
            if ruta:
                st.image(str(ruta), width="stretch")
            else:
                st.caption("Sin foto")
            st.markdown(f"**{fila.producto_id}**")
            st.write(fila.descripcion)
