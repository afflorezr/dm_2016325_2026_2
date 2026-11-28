"""Entrada de la aplicación multipágina del Taller 2."""
import streamlit as st
import db
from interfaz import filtros
from paginas.resumen import mostrar as resumen
from paginas.cambios import mostrar as cambios
from paginas.canasta import mostrar as canasta
from paginas.datos import mostrar as datos

st.set_page_config(page_title='Precios de salud · Colombia',page_icon='🩺',layout='wide')
@st.cache_resource
def preparar():
    db.migrar()
    return True
preparar()
st.title('Precios de salud')
st.caption('Termómetros · Tensiómetros · Glucómetros · Tiras reactivas · Lancetas · Oxímetros')
st.session_state['filtros']=filtros()
pagina=st.navigation([
    st.Page(resumen,url_path='resumen',title='Comparar precios',icon=':material/compare_arrows:',default=True),
    st.Page(cambios,url_path='cambios',title='Cambios entre fechas',icon=':material/timeline:'),
    st.Page(canasta,url_path='canasta',title='Mi canasta',icon=':material/shopping_basket:'),
    st.Page(datos,url_path='datos',title='Datos y actualización',icon=':material/database:'),
])
pagina.run()
