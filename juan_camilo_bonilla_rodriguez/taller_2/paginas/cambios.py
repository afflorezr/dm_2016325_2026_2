"""Comparación por anuncio del mismo comercio, sin completar precios faltantes."""
import streamlit as st
import plotly.express as px
from interfaz import datos,grafico
from codigo.config import COLORES


def mostrar():
    st.subheader('Cambios entre dos consultas')
    corridas=datos('opciones')['corridas'].corrida_id.tolist()
    if len(corridas)<2:st.info('Se necesitan al menos dos ejecuciones.');return
    a,b=st.columns(2)
    antes=a.selectbox('Consulta anterior',corridas,index=1)
    despues=b.selectbox('Consulta posterior',corridas,index=0)
    if antes>=despues:st.info('Seleccione una consulta anterior a la posterior.');return
    umbral=st.slider('Resaltar variaciones desde (%)',0,100,10)
    d=datos('cambios',antes,despues,umbral)
    st.caption(f'{antes} → {despues} · Precios en COP, fechas de Colombia. Se comparan anuncios del mismo comercio.')
    for col,tipo in zip(st.columns(4),['Subió','Bajó','Nuevo','No observado']):
        columna={'Subió':'n_subio','Bajó':'n_bajo','Nuevo':'n_nuevo','No observado':'n_ausente'}[tipo]
        col.metric(tipo,int(d.iloc[0][columna]) if not d.empty else 0,border=True)
    st.dataframe(d.drop(columns=['n_subio','n_bajo','n_nuevo','n_ausente']).rename(columns={'comercio':'Comercio','producto':'Producto','anuncio_id':'Anuncio','precio_anterior':'Antes (COP)','precio_actual':'Después (COP)','cambio_cop':'Cambio (COP)','cambio_pct':'Cambio (%)','cambio':'Resultado','variacion_grande':'Supera umbral','disponibilidad':'Disponibilidad'}),hide_index=True,column_config={'Supera umbral':st.column_config.CheckboxColumn()})
    st.download_button('Descargar comparación (CSV)',d.to_csv(index=False).encode('utf-8-sig'),'cambios.csv','text/csv')
    cambios=d[d.cambio.isin(['Subió','Bajó'])]
    if cambios.empty:st.info('No se observaron aumentos ni reducciones entre estas consultas.')
    else:grafico(px.bar(cambios,x='producto',y='cambio_pct',color='comercio',barmode='group',color_discrete_map=COLORES,
      labels={'producto':'Anuncio','cambio_pct':'Variación (%)','comercio':'Comercio'},hover_data=['cambio_cop']))
    st.caption('No observado significa que no hubo un precio válido de ese anuncio en la consulta. No demuestra agotamiento ni retiro. Una captura parcial puede explicar ausencias; revise sus estados.')
    st.dataframe(datos('estados',antes),hide_index=True)
    st.dataframe(datos('estados',despues),hide_index=True)
