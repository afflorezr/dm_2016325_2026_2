"""Indicadores, cuatro gráficos y oferta filtrada."""
import streamlit as st
import plotly.express as px
from interfaz import datos,cop,grafico,tabla_productos
from codigo.config import COLORES


def mostrar():
    f=st.session_state['filtros'];k=datos('indicadores',f)
    st.subheader('La oferta en esta consulta')
    st.caption(f"Ejecución: {f['corrida']} · Última consulta: {k['ultima_consulta'] or 'Sin datos'}")
    cambio=datos('cambios_ultima',f['corrida'])
    tarjetas=[('Productos observados',str(int(k['productos']))),('Observaciones',str(int(k['observaciones']))),
      ('Comercios',str(int(k['comercios']))),('En promoción',f"{k['promociones_pct']:.1f} %" if k['promociones_pct'] is not None else 'Sin datos'),
      ('Precio mediano del empaque',cop(k['mediana_cop'])),('Mayor ahorro comparable',cop(k['ahorro_maximo_cop']))]
    for fila in (tarjetas[:3],tarjetas[3:]):
        for col,(titulo,valor) in zip(st.columns(3),fila):col.metric(titulo,valor,border=True)
    st.caption('Los productos se cuentan por anuncio y comercio. La mediana describe el surtido filtrado; no mide qué tienda es más económica.')
    st.dataframe(datos('oferta',f).rename(columns={'comercio':'Comercio','productos':'Productos','observaciones':'Observaciones','promociones_pct':'Promociones (%)'}),hide_index=True)
    op=datos('opciones');productos=op['productos']
    st.subheader('Cómo cambió un mismo producto')
    pid=st.selectbox('Presentación para la evolución',productos.producto_id.tolist(),
      format_func=lambda p:productos.set_index('producto_id').loc[p,'producto_nombre'])
    d=datos('evolucion',int(pid),f['comercios'])
    if d.empty:st.info('No hay observaciones para esta selección.')
    else:
        grafico(px.line(d,x='fecha_hora',y='precio',color='comercio',markers=True,color_discrete_map=COLORES,
          labels={'fecha_hora':'Fecha de consulta (Colombia)','precio':'Precio del empaque (COP)','comercio':'Comercio'},
          hover_data=['disponibilidad','corrida_id']))
        st.caption('El historial usa el producto y los comercios elegidos, en todas sus fechas. Cada punto es una consulta real; una línea no implica que el precio permaneciera constante entre consultas.')
    st.subheader('Qué tamaño cuesta menos por unidad')
    grupos=datos('familias')
    if grupos.empty:st.info('No hay familias con tamaños equivalentes identificados.')
    else:
        i=st.selectbox('Línea de producto y unidad',range(len(grupos)),format_func=lambda n:f"{grupos.iloc[n].familia} · COP/{grupos.iloc[n].unidad}")
        g=grupos.iloc[i];d=datos('precios_unidad',f,g.familia,g.unidad)
        if d.empty:st.info('No hay tamaños equivalentes con estos filtros.')
        else:
            grafico(px.bar(d,x='producto_nombre',y='precio_por_unidad',color='comercio',barmode='group',
              color_discrete_map=COLORES,labels={'producto_nombre':'Presentación','precio_por_unidad':f'COP/{g.unidad}','comercio':'Comercio'},
              hover_data=['precio','contenido_total','disponibilidad']))
            st.caption('Se compara la misma línea de tiras sin accesorios. Un precio unitario menor puede exigir pagar más por el empaque. Revise la disponibilidad indicada al pasar el cursor.')
    st.subheader('Distribución de precios del surtido')
    d=datos('filtrados',f)
    if d.empty:st.info('Ningún producto coincide con los filtros. Amplíe la selección para consultar la oferta.');return
    grafico(px.box(d,x='comercio',y='precio',color='comercio',points='all',color_discrete_map=COLORES,
       labels={'comercio':'Comercio','precio':'Precio del empaque (COP)'},hover_data=['producto_nombre']))
    st.caption('Cada tienda ofrece productos diferentes. Esta distribución describe el surtido y no permite concluir cuál es globalmente más barata.')
    st.subheader('Dónde hay más oportunidad de ahorro')
    a=datos('ahorros',f)
    if a.empty:st.info('El ahorro requiere las mismas presentaciones con precio y disponibilidad en los tres comercios. Revise los filtros.')
    else:
        grafico(px.bar(a,x='ahorro_pct',y='producto_nombre',orientation='h',color_discrete_sequence=['#16766d'],
          labels={'ahorro_pct':'Ahorro frente al precio máximo (%)','producto_nombre':'Presentación'},
          hover_data=['ahorro_cop','minimo','maximo','menor_precio_en']))
        st.dataframe(a[['producto_nombre','minimo','maximo','ahorro_cop','ahorro_pct','menor_precio_en']].rename(columns={'producto_nombre':'Presentación','minimo':'Mínimo (COP)','maximo':'Máximo (COP)','ahorro_cop':'Ahorro (COP)','ahorro_pct':'Ahorro (%)','menor_precio_en':'Menor precio en'}),hide_index=True)
        st.caption('El ahorro compara la presentación idéntica en una misma ejecución. Incluye los empates en el precio mínimo y excluye envío y condiciones de compra.')
    st.subheader('Productos encontrados')
    tabla_productos(d)
