import streamlit as st
from ui import leer,tabla,cop,marcas
st.subheader('Mi carrito')
f=st.session_state['filtros']
st.caption('Se usa únicamente la captura indicada arriba y se comparan las tres tiendas, independientemente de los otros filtros laterales.')
opts=leer('opciones')['productos'];products={p['id']:p for p in opts}
selected=st.multiselect('Presentaciones',list(products),default=list(products),format_func=lambda x:products[x]['nombre']+' · '+products[x]['presentacion'])
quantities={}
for offset in range(0,len(selected),2):
    for col,p in zip(st.columns(2),selected[offset:offset+2]):
        with col:
            marcas([products[p]['marca']])
            quantities[p]=int(st.number_input(products[p]['nombre']+' · '+products[p]['presentacion'],min_value=1,max_value=100,value=1,step=1,key='qty_'+p))
result=leer('canasta',f['ejecucion'],quantities)
full=[t for t in result['tiendas'] if t['total'] is not None]
minimum=min((t['total'] for t in full),default=None)
if full:st.success('Tienda(s) más económica(s) con canasta completa: '+', '.join(t['nombre'] for t in full if t['total']==minimum)+' · '+cop(minimum)+' COP')
elif selected:st.warning('Ninguna tienda tiene toda la canasta disponible. Consulta los faltantes; no se calcula un total parcial.')
else:st.info('Selecciona al menos una presentación para calcular tu canasta.')
st.subheader('Totales por comercio')
tabla(result['tiendas'],'canasta_por_tienda')
st.caption('Sin dato en total = cobertura incompleta. Los productos faltantes se indican, sin sustituciones.')
st.subheader('Compra dividida y ahorro')
cols=st.columns(3)
cols[0].metric('Total mínimo dividido (COP)',cop(result['total_dividido']))
cols[1].metric('Mejor tienda completa (COP)',cop(minimum))
cols[2].metric('Ahorro frente a esa tienda (COP)',cop(minimum-result['total_dividido']) if minimum is not None and result['total_dividido'] is not None else 'Sin dato')
tabla(result['division'],'canasta_dividida')
st.info('No incluye envíos, transporte, mínimos de compra, cupones ni promociones condicionadas. Todos los comercios empatados en el mínimo se conservan.')
