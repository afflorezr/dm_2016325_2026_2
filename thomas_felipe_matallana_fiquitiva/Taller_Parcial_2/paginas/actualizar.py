import json
import streamlit as st
import scraper
from ui import refrescar,tabla,leer

st.subheader('Actualizar datos')
st.write('La captura en línea consulta las secciones originales de Colsubsidio, Cafam y La Rebaja, archiva las respuestas y valida antes de insertar. Puede tardar varios minutos.')
mode=st.radio('Origen',['Captura real en línea','Reprocesar respuestas archivadas (sin conexión)'])
offline=mode.startswith('Reprocesar')
run=st.selectbox('Ejecución archivada',scraper.archivadas()) if offline else None
st.info('Reprocesa archivos raw locales: no consulta Internet ni crea una fecha nueva.' if offline else 'Consulta los sitios reales: necesita Internet, archiva respuestas y añade una captura nueva. Puede tardar varios minutos.')
st.caption('Sin conexión no crea una fecha nueva: conserva las fechas originales. Repetir una captura archivada no duplica observaciones.')
if st.button('Ejecutar actualización',type='primary'):
    statuses={}
    progress=st.progress(0)
    def callback(store,event,result):
        if event=='inicio': statuses[store]=st.status('Procesando '+store,expanded=True)
        else:
            statuses[store].write('Resultado: '+result['estado'])
            statuses[store].update(label=store+' · '+result['estado'],state='error' if result['estado']=='fallida' else 'complete',expanded=False)
            progress.progress(len([s for s in statuses])/3)
    try:
        result=scraper.ejecutar(offline,run,callback=callback)
        refrescar()
        st.session_state['resultado_actualizacion']=result
        st.rerun()
    except (RuntimeError,ValueError,OSError) as exc:
        st.error('No se pudo completar la actualización. Revisa si hay otra ejecución en curso o prueba el modo sin conexión.')
        with st.expander('Detalle técnico'):st.code(str(exc))
if 'resultado_actualizacion' in st.session_state:
    result=st.session_state['resultado_actualizacion']
    st.subheader('Resultado · '+result['ejecucion'])
    states=[r['estado'] for r in result['resultados']]
    if all(s=='completa' for s in states):st.success('Procesamiento completo de los tres comercios.')
    elif 'fallida' in states:st.warning('Uno o más comercios fallaron; los demás resultados se conservan.')
    else:st.warning('Captura parcial: revisa cobertura y correspondencias antes de interpretar ausencias.')
    tabla([{k:r.get(k) for k in ['comercio','estado','recolectados','insertados','rechazados','correspondencias']} for r in result['resultados']],'actualizacion')
    with st.expander('Detalles técnicos por comercio'):st.json(result)
    runs=leer('ejecuciones');ids=[r['id'] for r in runs]
    if result['ejecucion'] in ids and ids.index(result['ejecucion'])+1<len(ids):
        tabla(leer('resumen_cambios',ids[ids.index(result['ejecucion'])+1],result['ejecucion']),'resumen_cambios_por_comercio')
    st.download_button('Descargar resultado JSON',json.dumps(result,ensure_ascii=False,indent=2),'actualizacion.json','application/json')
st.warning('En Streamlit Community Cloud el almacenamiento local no es permanente. Descarga y conserva las capturas y la base antes de reiniciar o volver a desplegar; consulta DESPLIEGUE.md.')
