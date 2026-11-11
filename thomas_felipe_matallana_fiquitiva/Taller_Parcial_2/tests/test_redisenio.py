"""Filtros nuevos y presentación; datos de prueba en SQLite temporal."""
import io
import pandas as pd
import pytest
import db
from identidad import normalizar_marca,color_marca
from ui import preparar_tabla,csv_filtrado
from test_logica import base,fila,insertar
from test_interfaz import interfaz
from streamlit.testing.v1 import AppTest

def test_marcas_estables():
    assert normalizar_marca('  DÓVE  ')=='dove'
    assert color_marca('Dove Original')==color_marca('DOVE')
    assert color_marca('Otra marca')==color_marca('  OTRA   MARCA ')
    assert color_marca('rexona')!=color_marca('dove')

def test_filtros_combinados_y_marcas(base):
    a=fila();a.update(marca='  REXONA Clinical ',subcategoria='Desodorantes')
    b=fila(sku='2',product='dove_original_270',price=200);b.update(marca='Dove',disponibilidad='agotado')
    insertar(base,[a,b])
    f={'comercio':['colsubsidio'],'marca':['rexona'],'productos':['rexona_men_48'],'disponibilidad':['disponible'],'subcategoria':['Desodorantes'],'min_precio':99,'max_precio':101}
    assert len(db.catalogo(f,base))==1
    assert db.indicadores(f,base)['registros']==1
    assert db.catalogo({**f,'disponibilidad':['agotado']},base)==[]
    assert len(db.catalogo({'productos':['rexona_men_48','dove_original_270']},base))==2
    assert db.catalogo({'productos':["' OR 1=1 --"]},base)==[]

@pytest.mark.parametrize('f',[{'min_precio':2,'max_precio':1},{'desde':'2026-11-09','hasta':'2026-11-01'}])
def test_rangos_invertidos(f):
    with pytest.raises(ValueError):db.filtro(f)

def test_csv_misma_seleccion_y_estados():
    rows=[{'nombre':'A','marca':'DOVE','precio':100,'promocion':1,'estado':'cambió','cambio_cop':20},
          {'nombre':'B','marca':'Protex','precio':None,'promocion':None,'estado':'cambió','cambio_cop':-10}]
    df=preparar_tabla(rows)
    assert list(df.estado)==['subió','bajó']
    assert list(df.promocion)==['Sí','Sin información']
    exported=pd.read_csv(io.BytesIO(csv_filtrado(df)),keep_default_na=False)
    assert list(exported.nombre)==list(df.nombre)
    assert list(exported.columns)==list(df.columns)
    assert exported.precio.iloc[1]=='Sin dato'

def test_restablecer_y_navegacion(interfaz):
    app=AppTest.from_file(str(interfaz),default_timeout=60).run()
    app.multiselect(key='f_comercios').set_value([]).run()
    assert app.metric[0].value=='0'
    app.text_input(key='f_busqueda').set_value('sin coincidencias').run()
    next(b for b in app.button if b.label=='Restablecer filtros').click().run()
    assert len(app.multiselect(key='f_comercios').value)==3
    assert app.text_input(key='f_busqueda').value==''
    assert app.metric[0].value=='3'
    app.multiselect(key='f_productos').set_value(['rexona_men_48']).run()
    app.switch_page('paginas/catalogo.py').run()
    assert not app.exception and not app.error
    assert len(app.tabs)==3
    assert app.multiselect(key='f_productos').value==['rexona_men_48']
