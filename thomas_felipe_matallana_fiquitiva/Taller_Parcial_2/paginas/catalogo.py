import streamlit as st
from ui import leer,tabla,marcas
st.subheader('Catálogo por comercio')
st.caption('Aplican todos los filtros laterales. Precio unitario en COP/g, COP/mL o COP/unidad; consulta unidad y compara solo formulaciones equivalentes.')
f=st.session_state['filtros'];names={r['id']:r['nombre'] for r in leer('opciones')['comercios']}
if not f['comercio']:st.info('Selecciona al menos un comercio en el panel lateral.')
else:
    datasets=[leer('catalogo',{**f,'comercio':[s]}) for s in f['comercio']]
    tabs=st.tabs([f'{names[s]} · {len(rows)}' for s,rows in zip(f['comercio'],datasets)])
    for tab,store,rows in zip(tabs,f['comercio'],datasets):
        with tab:
            st.write(f'**{len(rows)} registros encontrados en {names[store]}**')
            marcas([r['marca'] for r in rows])
            st.caption('Etiquetas = marcas (colores aproximados). Las tablas permiten ordenar y buscar. CSV contiene exactamente las filas y columnas mostradas, con protección de fórmulas.')
            first=['nombre','marca','presentacion','precio','precio_unitario','promocion','disponibilidad','unidad','contenido_total','fecha_hora','url','comercio','sku','producto_comun','ejecucion','subcategoria']
            tabla([{k:r.get(k) for k in first} for r in rows],'catalogo_'+store)
            with st.expander('Campos de auditoría de esta selección'):
                tabla([{k:r.get(k) for k in ['sku','ejecucion','archivo_raw','url_extraccion','incidencia','texto_original']} for r in rows],'auditoria_'+store)
