import streamlit as st
from ui import leer,tabla

st.subheader('Calidad y evidencia')
st.write('Se conserva el Taller 1 evaluado: ocho presentaciones, tres comercios y respuestas originales. Las observaciones históricas inválidas permanecen en la base con marca de exclusión y motivo auditable.')
quality=leer('calidad')
runs=leer('ejecuciones')
complete=[r for r in runs if r['completos']==3 and r['correspondencias']==24]
cols=st.columns(3)
cols[0].metric('Integridad SQLite','Correcta' if quality['integridad']==[{'integrity_check':'ok'}] else 'Revisar')
cols[1].metric('Fechas completas',len({r['fecha'][:10] for r in complete}))
cols[2].metric('Correspondencias última captura',str(runs[0]['correspondencias'])+'/24' if runs else 'Sin dato')
st.caption('Recolectados: filas extraídas antes de validar. Validados: cumplen las reglas. Incluidos: además pertenecen a la categoría. La cobertura por sección cuenta productos del sitio, no necesariamente SKU.')
with st.expander('Ejecuciones e integridad',expanded=True):
    tabla(runs,'ejecuciones')
    st.json(quality['integridad'])
for title,key in [('Cobertura por sección','cobertura'),('Filas rechazadas antes de insertar','rechazos'),('Correcciones históricas','correcciones'),('Registro de actualizaciones','actualizaciones'),('Última observación conocida por SKU — puede ser antigua','ultimos')]:
    with st.expander(title): tabla(quality[key],key)
with st.expander('Correspondencias y evidencia de presentaciones'):
    tabla(leer('opciones')['productos'],'correspondencias')
st.caption('Disponible: evidencia explícita. Agotado: IsAvailable=false en la respuesta. Desconocida: falta evidencia. No observado: ausencia entre dos capturas; no equivale a agotado. En el legado, los ceros se tratan conservadoramente como desconocidos.')
st.subheader('Autoría y alcance')
st.write('Thomas Matallana. Asistido por IA: diseño de módulos, código, pruebas y documentación. Los precios proceden de respuestas archivadas de los comercios.')
