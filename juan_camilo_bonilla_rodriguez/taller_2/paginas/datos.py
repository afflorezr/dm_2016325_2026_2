"""Estado de los datos y actualización reutilizando scraper.py."""
import streamlit as st
from interfaz import datos,actualizar


def mostrar():
    st.subheader('Origen y estado de los datos')
    st.write('Los precios se obtienen automáticamente de Habib, Farmaprime y Farmaweb. Cada observación conserva su ejecución, hora de Colombia y referencia a una respuesta JSON comprimida en raw/.')
    st.dataframe(datos('estados',st.session_state['filtros']['corrida']),hide_index=True)
    st.subheader('Historial con cobertura completa')
    historial=datos('control_historial')
    st.dataframe(historial,hide_index=True)
    if historial.fecha.nunique()<2:st.warning('Todavía no hay dos fechas con cobertura completa de las ocho presentaciones.')
    actualizar()
    st.caption('En plataformas gratuitas, las actualizaciones locales de SQLite pueden perderse al reiniciar el servidor. La copia entregada en GitHub conserva las capturas verificadas.')
