"""Presentación, componentes y caché; SQL exclusivamente en db.py."""
from html import escape
import pandas as pd
import streamlit as st
import db
import streamlit.components.v1 as components
st.markdown('<meta name="google" content="notranslate">', unsafe_allow_html=True)
from identidad import COMERCIOS,SEMANTICOS,color_marca,nombre_marca
COLORES=COMERCIOS


def estilo():
    st.markdown("""<style>
    .stApp {background:#F8FAFC;color:#193642;}
    [data-testid="stSidebar"] {background:#EAF3FC;border-right:1px solid #D9E6F1;}
    .block-container {padding-top:2rem;padding-bottom:2rem;max-width:1440px;}
    h1 {font-size:1.85rem!important;line-height:1.25!important;}
    h2 {font-size:1.45rem!important;} h3 {font-size:1.15rem!important;}
    [data-testid="stMetric"] {background:white;border:1px solid #DFE7EB;border-radius:12px;padding:14px 18px;}
    [data-testid="stMetricValue"] {font-size:1.8rem;}
    [data-testid="stBaseButton-primary"] {background:#007F86;color:white;border-color:#007F86;}
    .marca {display:inline-block;border:1px solid #DDE5EA;border-left:4px solid var(--marca);border-radius:7px;padding:4px 10px;margin:3px 6px 3px 0;background:#FFF;color:var(--marca);font-weight:600;font-size:.85rem;}
    @media(max-width:700px){.block-container{padding:1.2rem .8rem;} h1{font-size:1.5rem!important;}
    [data-testid="stHorizontalBlock"]{flex-wrap:wrap;} [data-testid="stColumn"]{min-width:100%!important;}}
    </style>""",unsafe_allow_html=True)

@st.cache_data(ttl=300,show_spinner=False)
def datos(nombre,*args,revision=0):return getattr(db,nombre)(*args)
def leer(nombre,*args):return datos(nombre,*args,revision=st.session_state.get('revision',0))
def refrescar():
    st.cache_data.clear();st.session_state['revision']=st.session_state.get('revision',0)+1
def cop(value):return 'Sin dato' if value is None or pd.isna(value) else '$ '+f'{value:,.0f}'.replace(',','.')

def marcas(values):
    unique=sorted({nombre_marca(v) for v in values if v})
    st.markdown(''.join(f'<span class="marca" style="--marca:{color_marca(v)}">{escape(v)}</span>' for v in unique),unsafe_allow_html=True)

def etiqueta_captura(row):
    return f"{row['fecha'][:16].replace('T',' ')} · {row['id']} · {row['completos']}/3 completos · {row['correspondencias']}/24"

def encabezado():
    st.title('Comparador de precios de higiene corporal')
    st.write('Compara presentaciones equivalentes, consulta cómo cambian sus precios y calcula dónde comprar tu canasta.')
    run=st.session_state['filtros']['ejecucion']
    row=next(r for r in leer('ejecuciones') if r['id']==run)
    st.caption('Captura seleccionada: '+etiqueta_captura(row)+' · COP · Colombia (UTC−5)')

def preparar_tabla(rows):
    df=pd.DataFrame(rows).copy()
    if 'promocion' in df:df['promocion']=df.promocion.map({1:'Sí',0:'No'}).fillna('Sin información')
    if 'marca' in df:df['marca']=df.marca.map(nombre_marca)
    if 'estado' in df and 'cambio_cop' in df:
        df['estado']=[('subió' if delta>0 else 'bajó') if state=='cambió' else state for state,delta in zip(df.estado,df.cambio_cop)]
    # Celdas numéricas siguen numéricas para ordenar; Styler presenta NULL como Sin dato.
    for c in df.select_dtypes(include=['object','string']):df[c]=df[c].where(df[c].notna(),'Sin dato')
    return df

def csv_filtrado(df):
    safe=df.copy()
    for c in safe.select_dtypes(include=['object','string']):
        safe[c]=safe[c].map(lambda v:"'"+v if isinstance(v,str) and v.startswith(('=','+','-','@')) else v)
    return safe.to_csv(index=False,na_rep='Sin dato').encode('utf-8-sig')

def tabla(rows,nombre='datos'):
    df=preparar_tabla(rows)
    if df.empty:st.info('No hay resultados. Prueba quitar una marca, ampliar el precio o restablecer los filtros.');return df
    config={'url':st.column_config.LinkColumn('Anuncio',display_text='Abrir tienda')}
    currency={'precio','precio_unitario','total','subtotal','minimo','maximo','ahorro','precio_minimo','precio_antes','precio_despues','cambio_cop'}
    formats={c:(lambda v:'Sin dato' if pd.isna(v) or v=='Sin dato' else f'{v:,.2f}'.replace(',','X').replace('.',',').replace('X','.')) for c in df if c in currency}
    styled=df.style.format(formats,na_rep='Sin dato')
    for c in df:
        config.setdefault(c,st.column_config.Column(c.replace('_',' ').capitalize()+(' (COP)' if c in currency else '')))
    if 'marca' in df:styled=styled.map(lambda v:f'color: {color_marca(v)}; font-weight: bold;',subset=['marca'])
    if 'estado' in df:styled=styled.map(lambda v:f'color: {SEMANTICOS.get(v,"#193642")}; font-weight: bold;',subset=['estado'])
    st.dataframe(styled,hide_index=True,width='stretch',column_config=config)
    st.download_button('Descargar CSV',csv_filtrado(df),nombre+'.csv','text/csv',key='csv_'+nombre)
    return df

def figura(fig,ylabel,leyenda='Comercio',horizontal=False):
    fig.update_layout(template='plotly_white',legend_title_text=leyenda,font=dict(family='Arial',size=12,color='#193642'),
        margin=dict(t=20,b=35,l=15,r=20),separators=',.',paper_bgcolor='#F8FAFC',
        legend=dict(orientation='h',yanchor='bottom',y=1.02,xanchor='left',x=0))
    if horizontal:
        fig.update_xaxes(title_text='Ahorro (COP)',tickformat=',.0f',automargin=True)
        fig.update_yaxes(title_text=None,automargin=True)
    else:fig.update_yaxes(title_text=ylabel,tickformat=',.0f',automargin=True)
    st.plotly_chart(fig,use_container_width=True,config={'displaylogo':False,'locale':'es'})

def restablecer():
    for key in list(st.session_state):
        if key.startswith('f_'):del st.session_state[key]

def filtros():
    runs=leer('ejecuciones');opts=leer('opciones')
    if not runs:st.error('No hay capturas disponibles. Reprocesa las respuestas raw.');st.stop()
    ids=[r['id'] for r in runs];complete=[r['id'] for r in runs if r['completos']==3 and r['correspondencias']==24]
    labels={r['id']:etiqueta_captura(r) for r in runs}
    names={r['id']:r['nombre'] for r in opts['comercios']}
    products={r['id']:r['nombre']+' · '+r['presentacion'] for r in opts['productos']}
    with st.sidebar:
        st.subheader('Filtros de consulta')
        st.button('Restablecer filtros',on_click=restablecer,width='stretch')
        run=st.selectbox('Captura',ids,index=ids.index(complete[0]) if complete else 0,format_func=labels.get,key='f_captura')
        stores=st.multiselect('Comercios',list(names),default=list(names),format_func=names.get,key='f_comercios')
        with st.expander('Categoría, marcas y productos',expanded=True):
            subs=st.multiselect('Subcategorías',[r['subcategoria'] for r in opts['subcategorias'] if r['subcategoria']],key='f_sub')
            brands=st.multiselect('Marcas',[r['marca'] for r in opts['marcas']],format_func=nombre_marca,key='f_marcas')
            if brands:marcas(brands)
            selected=st.multiselect('Productos comparables',list(products),format_func=products.get,key='f_productos')
        with st.expander('Precio y condiciones',expanded=False):
            lo=st.number_input('Precio mínimo (COP)',min_value=0.,value=0.,step=1000.,key='f_min')
            hi=st.number_input('Precio máximo (COP; 0 = sin límite)',min_value=0.,value=0.,step=1000.,key='f_max')
            promo=st.checkbox('Solo promociones',key='f_promo')
            comparable=st.checkbox('Solo las ocho presentaciones',key='f_comparables')
            availability=st.multiselect('Disponibilidad',['disponible','agotado','desconocida'],format_func=lambda x:{'disponible':'Disponible','agotado':'Agotado explícitamente','desconocida':'Desconocida'}[x],key='f_disponibilidad')
        search=st.text_input('Nombre o texto original',max_chars=120,key='f_busqueda')
        st.caption('Todos los filtros: Panorama y Catálogo. Historial: comercios + controles propios. Canasta: solo captura. Cambios, Actualizar y Calidad: controles propios.')
    f=dict(ejecucion=run,comercio=stores,subcategoria=subs or None,marca=brands or None,productos=selected or None,
        min_precio=lo,max_precio=hi or None,promocion=promo,comparable=comparable,disponibilidad=availability or None,busqueda=search)
    try:db.validar_rangos(f)
    except ValueError as exc:st.warning(str(exc));st.stop()
    active=[]
    if set(stores)!=set(names):active.append('Comercios: '+(', '.join(names[s] for s in stores) or 'ninguno'))
    for label,values in [('Categorías',subs),('Marcas',brands),('Presentaciones',[products[p] for p in selected]),('Disponibilidad',availability)]:
        if values:active.append(label+': '+', '.join(values))
    if lo or hi:active.append(f'Precio: {cop(lo)} a {cop(hi) if hi else "sin límite"}')
    if promo:active.append('Solo promociones')
    if comparable:active.append('Solo comparables')
    if search:active.append('Búsqueda: '+search)
    with st.sidebar:
        count=leer('indicadores',f)['registros']
        st.caption(f'{count} registros en el catálogo filtrado')
        st.caption('Filtros activos: '+(' · '.join(active) if active else 'captura seleccionada; todas las tiendas'))
    return f

