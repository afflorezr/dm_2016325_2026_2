"""Punto de entrada: streamlit run app.py."""
import streamlit as st
import db
from ui import filtros,estilo,encabezado

st.set_page_config(page_title='Higiene corporal | Comparador',page_icon='🧼',layout='wide')
db.inicializar()
estilo()
nav=st.navigation([
    st.Page('paginas/resumen.py', title='Resumen general', icon='📊', default=True),
    st.Page('paginas/catalogo.py',title='Catálogo',icon='🔎'),
    st.Page('paginas/historial.py',title='Historial y cambios',icon='📈'),
    st.Page('paginas/canasta.py',title='Mi carrito',icon='🛒'),
    st.Page('paginas/actualizar.py',title='Actualizar datos',icon='🔄'),
    st.Page('paginas/calidad.py',title='Calidad y evidencia',icon='📋'),
])
st.session_state['filtros']=filtros()
encabezado()
try:
    nav.run()
except Exception as exc:
    st.error('No se pudo completar esta operación. Los datos guardados siguen disponibles.')
    with st.expander('Detalle para diagnóstico'):
        st.code(str(exc))
st.caption('Thomas Matallana · Minería de Datos · UNAL · Taller 2 | Jabones, geles de ducha, desodorantes y talcos; excluye higiene íntima e infantil.')
