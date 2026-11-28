"""Canastas con cantidades idénticas y cobertura completa por comercio."""
import streamlit as st
from interfaz import datos,cop


def mostrar():
    st.subheader('Mi canasta')
    op=datos('opciones');p=op['productos'].set_index('producto_id')
    corrida=st.selectbox('Ejecución para la canasta',op['corridas'].corrida_id.tolist())
    seleccion=st.multiselect('Presentaciones',p.index.tolist(),format_func=lambda pid:p.loc[pid,'producto_nombre'])
    if not seleccion:st.info('Elija al menos una presentación y su cantidad.');return
    cantidades={int(pid):int(st.number_input(p.loc[pid,'producto_nombre'],min_value=1,max_value=100,value=1,step=1,key=f'q_{pid}')) for pid in seleccion}
    totales,detalle=datos('canasta',corrida,cantidades)
    minimo=totales.iloc[0].minimo_combinado_cop
    st.metric('Mínimo comprando cada producto en la tienda más económica',cop(minimo),border=True)
    st.dataframe(totales.rename(columns={'comercio':'Comercio','faltantes':'Productos faltantes','total_cop':'Canasta (COP)',
      'minimo_combinado_cop':'Mínimo combinado (COP)','ahorro_combinado_cop':'Ahorro combinado (COP)'}),hide_index=True)
    for r in totales.itertuples():
        if r.faltantes:st.warning(f'{r.comercio}: faltan {r.faltantes} presentaciones con precio y disponibilidad; no se calcula un total incompleto.')
    st.dataframe(detalle.rename(columns={'comercio':'Comercio','pid':'Identificador','cantidad':'Cantidad','precio':'Precio del empaque (COP)','producto':'Producto'}),hide_index=True)
    st.download_button('Descargar detalle (CSV)',detalle.to_csv(index=False).encode('utf-8-sig'),'canasta.csv','text/csv')
    st.warning('El cálculo no incluye envío, mínimos de compra ni condiciones de las promociones. Comprar en varias tiendas puede aumentar esos costos.')
    st.caption(f'Ejecución {corrida}. Todas las cantidades usan la misma captura. Un dato ausente o un producto agotado impide calcular la canasta de ese comercio.')
