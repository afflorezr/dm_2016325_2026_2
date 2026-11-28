"""Componentes compartidos de Streamlit; las consultas permanecen en db.py."""
from pathlib import Path
import threading
import streamlit as st
import db
from codigo.config import DB_PATH, COLORES, COMERCIOS
from validacion import texto_busqueda

@st.cache_data(show_spinner=False)
def consultar(nombre,*args,version=0):
    funciones={k:getattr(db,k) for k in ['opciones','filtrados','indicadores','oferta','estados','evolucion',
       'precios_unidad','familias','ahorros','cambios','cambios_ultima','canasta','control_historial']}
    return funciones[nombre](*args)


def datos(nombre,*args):
    return consultar(nombre,*args,version=Path(DB_PATH).stat().st_mtime_ns)

@st.cache_resource
def candado():
    return threading.Lock()


def cop(valor):
    if valor is None:
        return 'Sin datos'
    import pandas as pd
    if pd.isna(valor):return 'Sin datos'
    return f'$ {valor:,.0f}'.replace(',','.')+' COP'


def filtros():
    op=datos('opciones')
    with st.sidebar:
        st.header('Filtrar la oferta')
        comercios=st.multiselect('Comercios',op['comercios'],default=op['comercios'],key='f_comercios')
        corridas=op['corridas'].corrida_id.tolist()
        if not corridas:st.error('No hay capturas registradas.');st.stop()
        corrida=st.selectbox('Ejecución',corridas,key='f_corrida',help='Una ejecución reúne la consulta de los tres comercios.')
        marca=st.selectbox('Marca',['Todas',*op['marcas']],key='f_marca')
        sub=st.selectbox('Subcategoría',['Todas',*op['subcategorias']],key='f_sub')
        limite=max(1,int(op['maximo'])+1)
        precio=st.slider('Precio del empaque (COP)',0,limite,(0,limite),key='f_precio')
        promo=st.checkbox('Solo promociones',key='f_promo')
        comp=st.checkbox('Solo comparables',key='f_comp')
        busqueda=st.text_input('Buscar en nombre o anuncio',max_chars=120,key='f_busqueda')
        fechas=st.checkbox('Limitar fechas',key='f_fechas')
        desde=hasta=None
        if fechas:
            desde=st.date_input('Desde',key='f_desde');hasta=st.date_input('Hasta',key='f_hasta')
            if desde>hasta:st.error('La fecha inicial debe ser anterior a la final.');st.stop()
        try:texto_busqueda(busqueda)
        except ValueError as e:st.warning(str(e));st.stop()
        st.caption('Precios en COP. Horas de Colombia (UTC−5).')
    return dict(comercios=comercios,corrida=corrida,marca=None if marca=='Todas' else marca,
      subcategoria=None if sub=='Todas' else sub,minimo=precio[0],maximo=precio[1],promociones=promo,
      comparables=comp,busqueda=busqueda,desde=desde,hasta=hasta)


def tabla_productos(df):
    columnas=['comercio','producto_nombre','marca_std','presentacion','precio','precio_por_unidad','unidad',
       'promocion','disponibilidad','fecha_hora','url']
    etiquetas={'comercio':'Comercio','producto_nombre':'Producto','marca_std':'Marca','presentacion':'Presentación',
       'precio':'Precio (COP)','precio_por_unidad':'COP por unidad','unidad':'Unidad','promocion':'Promoción',
       'disponibilidad':'Disponibilidad','fecha_hora':'Consulta (Colombia)','url':'Anuncio'}
    mostrar=df[columnas].rename(columns=etiquetas)
    st.dataframe(mostrar,hide_index=True,width='stretch',column_config={
      'Anuncio':st.column_config.LinkColumn('Anuncio',display_text='Ver producto'),
      'Precio (COP)':st.column_config.NumberColumn(format='$ %.0f'),
      'COP por unidad':st.column_config.NumberColumn(format='%.2f'),
      'Promoción':st.column_config.CheckboxColumn()})
    st.download_button('Descargar datos filtrados (CSV)',mostrar.to_csv(index=False).encode('utf-8-sig'),
      'precios_filtrados.csv','text/csv')
    st.caption('Puede ordenar por una columna y buscar desde la barra de herramientas de la tabla. El CSV contiene las filas de los filtros laterales.')


def grafico(fig):
    fig.update_layout(font=dict(family='Arial',size=13),legend_title_text='Comercio',
      paper_bgcolor='rgba(0,0,0,0)',margin=dict(l=15,r=15,t=50,b=15))
    st.plotly_chart(fig,width='stretch')


def actualizar():
    from scraper import run_all
    st.subheader('Actualizar precios')
    sin_red=st.toggle('Reprocesar copias sin conexión',help='Conserva la fecha original. No representa una nueva consulta de precios.')
    if st.button('Reprocesar copias' if sin_red else 'Consultar los tres comercios',type='primary'):
        lock=candado()
        if not lock.acquire(blocking=False):st.info('Hay otra actualización en curso. Intente de nuevo al terminar.');return
        try:
            with st.status('Reprocesando copias…' if sin_red else 'Consultando las tiendas…',expanded=True) as estado:
                def progreso(slug,resumen):
                    if resumen is None:st.write(f'Consultando {COMERCIOS[slug]}…')
                    else:st.write(f"{COMERCIOS[slug]}: {resumen['estado']}; {resumen.get('n',0)} anuncios recuperados.")
                resumen=run_all(offline=sin_red,progreso=progreso)
                errores=any(r['estado']!='completa' for r in resumen.values())
                estado.update(label='Actualización con incidencias' if errores else 'Procesamiento terminado',state='error' if errores else 'complete')
            consultar.clear()
            import pandas as pd
            resultado=pd.DataFrame(resumen).T.rename_axis('comercio').reset_index()
            resultado['comercio']=resultado.comercio.map(COMERCIOS)
            st.session_state['resumen_actualizacion']=resultado
            st.session_state['actualizacion_con_error']=errores
            st.rerun()
        except Exception:
            st.error('No se pudo completar el procesamiento. Los precios anteriores siguen disponibles. Puede usar el modo sin conexión.')
        finally:lock.release()
    if 'resumen_actualizacion' in st.session_state:
        st.dataframe(st.session_state['resumen_actualizacion'].rename(columns={'comercio':'Comercio','estado':'Estado','n':'Anuncios recuperados','n_reportado':'Total del sitio','anuncios_nuevos':'Anuncios nuevos','obs_insertadas':'Precios agregados','obs_duplicadas':'Observaciones existentes','descartes':'Fuera de categoría','rechazos':'Rechazados','productos_nuevos':'Productos nuevos','cambios_precio':'Cambios de precio','no_observados':'No observados','error':'Incidencia'}),hide_index=True)
        if st.session_state.get('actualizacion_con_error'):
            st.warning('Alguna tienda no completó la extracción. Revise el estado por comercio; puede reprocesar las copias sin conexión. Las capturas parciales se identifican como tales.')
