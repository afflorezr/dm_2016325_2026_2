import textwrap
import pandas as pd
import plotly.express as px
import streamlit as st
from ui import leer,cop,tabla,figura,COLORES
from identidad import color_marca,nombre_marca
st.subheader('Resumen general')
f=st.session_state['filtros'];k=leer('indicadores',f)
metrics=[('Registros',str(k['registros']),'Filas de categoría válidas después de aplicar todos los filtros.'),
 ('Comercios',str(k['comercios']),'Tiendas con resultados en la selección.'),
 ('En promoción',f"{k['porcentaje_promocion']:.1f}%" if k['porcentaje_promocion'] is not None else 'Sin dato','Precio menor al de lista, entre ofertas con información suficiente.'),
 ('Mediana (COP)',cop(k['mediana']),'Centro de la distribución; no implica equivalencia entre productos.'),
 ('Mayor ahorro (COP)',cop(k['ahorro_maximo']),'Mayor diferencia entre ofertas disponibles de una misma presentación.'),
 ('Precios cambiaron',str(k['cambios']),'Respecto de la observación válida anterior del mismo SKU y tienda.')]
for offset in (0,3):
    for col,(label,value,helptext) in zip(st.columns(3),metrics[offset:offset+3]):col.metric(label,value,help=helptext)
df=pd.DataFrame(leer('catalogo',f))
st.subheader('Distribución de precios por comercio')
if df.empty:st.info('No hay datos para esta selección. Restablece los filtros o amplía el rango de precio.')
else:
    fig=px.box(df,x='comercio',y='precio',color='comercio',color_discrete_map=COLORES,points='outliers',labels={'comercio':'Comercio','precio':'Precio (COP)'},hover_data=['nombre','presentacion','fecha_hora'])
    figura(fig,'Precio (COP)')
    st.caption('Colores = comercios. La mezcla de productos y tamaños afecta la distribución; no prueba qué tienda es más barata para una presentación idéntica.')
st.subheader('¿En qué producto vale más la pena comparar?')
savings=pd.DataFrame(leer('ahorros',f))
if savings.empty:st.info('Selecciona al menos dos comercios con una presentación equivalente disponible para calcular ahorros.')
else:
    savings['marca']=savings.marca.map(nombre_marca)
    savings['etiqueta']=savings.producto.map(lambda v:'<br>'.join(textwrap.wrap(v,width=20)))
    fig=px.bar(savings,x='ahorro',y='etiqueta',orientation='h',color='marca',color_discrete_map={m:color_marca(m) for m in savings.marca.unique()},
        labels={'marca':'Marca','ganadores':'Comercio(s) con menor precio','minimo':'Mínimo (COP)','maximo':'Máximo (COP)','fecha_hora':'Fecha','presentacion':'Presentación','etiqueta':'Producto'},
        hover_data={'ahorro':':,.0f','minimo':':,.0f','maximo':':,.0f','ganadores':True,'presentacion':True,'fecha_hora':True})
    fig.update_layout(height=max(350,80*len(savings)),yaxis={'categoryorder':'total ascending'})
    figura(fig,'',leyenda='Marca',horizontal=True)
    st.caption('Colores = marcas, aproximaciones visuales no oficiales. La tienda ganadora figura en el detalle y la tabla; cada barra compara únicamente el mismo empaque y formulación.')
st.subheader('Comparaciones verificables')
tabla(leer('ahorros',f),'ahorros')
