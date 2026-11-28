from datetime import date
import pandas as pd
import plotly.express as px
import streamlit as st
from ui import leer,tabla,figura,COLORES,marcas,etiqueta_captura
st.subheader('Historial y cambios')
st.caption('Historial: usa los comercios laterales, el producto y las fechas de esta página. Los demás filtros no lo restringen. La comparación usa únicamente las dos capturas y su umbral.')
opts=leer('opciones')['productos'];products={p['id']:p for p in opts}
product=st.selectbox('Presentación comparable',list(products),format_func=lambda x:products[x]['nombre']+' · '+products[x]['presentacion'])
marcas([products[product]['marca']])
runs=leer('ejecuciones');a,b=st.columns(2)
start=a.date_input('Desde',value=date.fromisoformat(min(r['fecha'][:10] for r in runs)))
end=b.date_input('Hasta',value=date.fromisoformat(max(r['fecha'][:10] for r in runs)))
if start>end:st.warning('La fecha inicial no puede ser posterior a la final. Corrige el rango para ver el historial.')
else:
    history=pd.DataFrame(leer('historial',product,st.session_state['filtros']['comercio'],str(start),str(end)))
    if history.empty:st.info('No hay observaciones en ese periodo para el producto y los comercios seleccionados.')
    else:
        history['fecha']=pd.to_datetime(history.fecha_hora,utc=True).dt.tz_convert('America/Bogota')
        st.caption(f'Periodo: {start} a {end} · Colores de líneas = comercios; etiqueta superior = marca.')
        for field,title,unit in [('precio','Precio de la presentación','COP'),('precio_unitario','Precio por unidad de contenido','COP / '+str(history.unidad.iloc[0]))]:
            st.subheader(title)
            fig=px.line(history,x='fecha',y=field,color='comercio_nombre',markers=True,color_discrete_map=COLORES,
                labels={'comercio_nombre':'Comercio','fecha':'Fecha de consulta',field:unit,'producto':'Producto','presentacion':'Presentación','disponibilidad':'Disponibilidad'},
                hover_data={'producto':True,'presentacion':True,'fecha_hora':True,'disponibilidad':True,field:':,.2f'})
            figura(fig,unit)
        st.caption('Misma presentación y formulación. Los puntos representan capturas; no se conocen los precios entre fechas.')
st.subheader('Comparar dos capturas')
ids=[r['id'] for r in runs];mapping={r['id']:r for r in runs}
if len(ids)<2:st.info('Hace falta una segunda captura.')
else:
    a,b=st.columns(2)
    before=a.selectbox('Captura anterior',ids,index=1,format_func=lambda x:etiqueta_captura(mapping[x]))
    after=b.selectbox('Captura posterior',ids,index=0,format_func=lambda x:etiqueta_captura(mapping[x]))
    threshold=st.number_input('Umbral absoluto de cambio (%)',min_value=0.,value=0.,step=1.)
    if before==after:st.warning('Elige dos capturas distintas.')
    elif mapping[before]['fecha']>mapping[after]['fecha']:st.warning('La captura anterior debe preceder a la posterior.')
    else:
        if any(mapping[x]['completos']<3 for x in [before,after]):st.warning('Hay una captura parcial: una ausencia puede deberse a cobertura incompleta, no a agotamiento.')
        tabla(leer('cambios',before,after,threshold),'cambios')
        st.caption('Subió (rojo) · Bajó (verde) · Sin cambio (gris) · Nuevo (azul) · No observado (ocre). Los nombres y signos acompañan el color. Nuevos y ausencias nunca se ocultan por el umbral; se refieren al catálogo validado, no prueban lanzamiento, retirada ni agotamiento.')
