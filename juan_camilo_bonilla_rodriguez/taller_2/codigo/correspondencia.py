"""Candidatos y revisión estructural del mapeo manual sin precios digitados."""
import pandas as pd
from .config import COMERCIOS, REGISTRO_COMERCIOS

def proponer_candidatos(conn):
    """Candidatos exactos; requieren revisión del modelo, variante y empaque."""
    return pd.read_sql_query('''SELECT marca_std,subcategoria_std,nombre_std,contenido,unidad,n_unidades,concentracion,COUNT(DISTINCT comercio_id) AS comercios FROM anuncios GROUP BY marca_std,subcategoria_std,nombre_std,contenido,unidad,n_unidades,concentracion HAVING COUNT(DISTINCT comercio_id)>=3''',conn)

def validar_correspondencia(conn,csv_path='datos/correspondencia.csv'):
    """Verifica claves, tres comercios, cantidades e identidades consistentes."""
    d=pd.read_csv(csv_path,dtype={'sku':str})
    problemas=[]
    esperados=set(d.comercio)
    if len(esperados)!=3 or not esperados<=set(REGISTRO_COMERCIOS.values()):
        problemas.append((None,'El mapeo debe identificar tres comercios conocidos'))
    for pid,g in d.groupby('producto_id'):
        if len(g)!=3 or set(g.comercio)!=esperados:
            problemas.append((pid,'Falta cobertura de los tres comercios o hay duplicados'))
        for k in ['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion']:
            if g[k].nunique(dropna=False)>1:
                problemas.append((pid,'Diferencias en '+k))
        for r in g.to_dict('records'):
            a=conn.execute('SELECT a.contenido,a.unidad,a.n_unidades FROM anuncios a JOIN comercios c USING(comercio_id) WHERE c.nombre=? AND a.sku=?',(r['comercio'],r['sku'])).fetchone()
            if not a:
                problemas.append((pid,'SKU inexistente '+r['comercio']+' '+r['sku']))
            elif a[0] is not None and a!=(r['contenido'],r['unidad'],r['n_unidades']):
                problemas.append((pid,'Contenido distinto en '+r['comercio']))
    if d.duplicated(['comercio','sku']).any():
        problemas.append((None,'Un anuncio pertenece a varios productos'))
    return pd.DataFrame(problemas,columns=['producto_id','problema'])
