"""Datos mínimos sintéticos solo en pruebas, nunca en la entrega ni en sitios reales."""
import pytest
import db
from validacion import precio_numerico,contenido_normalizado,validar_fila,validar_busqueda


@pytest.fixture
def base(tmp_path):
    path=tmp_path/'prueba.sqlite';db.inicializar(path);return path


def fila(run='20260101T100000_test',store='colsubsidio',price=100,sku='1',product='rexona_men_48'):
    return dict(ejecucion=run,comercio=store,sku=sku,producto_sitio=sku,producto_comun=product,
        nombre_original='Producto de prueba',nombre_limpio='producto de prueba',marca='prueba',
        texto_original='{}',precio=price,disponible=1,disponibilidad='disponible',url='https://example.org/producto',
        url_extraccion='https://example.org/api',fecha_hora='2026-01-'+('01' if '0101' in run else '02')+'T10:00:00-05:00',
        contenido_total=48,unidad='g',comparable=1,incluido=1,promocion=0,archivo_raw='raw/prueba.json.gz')


def insertar(path,rows):
    r=rows[0]
    return db.guardar(rows,dict(ejecucion=r['ejecucion'],comercio=r['comercio'],inicio=r['fecha_hora'],fin=r['fecha_hora'],estado='completa',categorias=[]),path=path)


@pytest.mark.parametrize('text,expected',[('$ 12.900',12900),('COP 12.900,50',12900.5),('12900.50',12900.5)])
def test_precio_texto(text,expected): assert precio_numerico(text)==expected


@pytest.mark.parametrize('value',[None,0,-1,'nan',True])
def test_precio_invalido(value):
    with pytest.raises(ValueError): precio_numerico(value)


@pytest.mark.parametrize('text,expected',[('3 x 110 g',(330,'g')),('1 kg',(1000,'g')),('1 L',(1000,'mL'))])
def test_unidades(text,expected): assert contenido_normalizado(text)==expected


def test_ahorro_empates(base):
    for store,price in [('colsubsidio',100),('cafam',100),('larebaja',150)]: insertar(base,[fila(store=store,price=price)])
    result=db.ahorros({},base)[0]
    assert result['ahorro']==50
    assert set(result['ganadores'].split(', '))=={'Colsubsidio','Cafam'}


def test_idempotencia(base):
    insertar(base,[fila()]);result=insertar(base,[fila()])
    assert result['insertados']==0
    assert db.calidad(base)['totales'][0]['registros']==1


def test_cambio_precio(base):
    a=fila();b=fila(run='20260102T100000_test',price=125)
    insertar(base,[a]);insertar(base,[b])
    r=db.cambios(a['ejecucion'],b['ejecucion'],path=base)[0]
    assert r['cambio_cop']==25 and r['cambio_pct']==25 and r['estado']=='cambió'


def test_canasta_incompleta(base):
    a=fila();insertar(base,[a])
    result=db.canasta(a['ejecucion'],{'rexona_men_48':1,'protex_avena_330':2},base)
    assert all(t['total'] is None for t in result['tiendas'])
    assert result['total_dividido'] is None
    assert all(t['faltantes'] for t in result['tiendas'])


def test_rechazo_sin_insertar(base):
    result=insertar(base,[fila(price=None)])
    assert result['rechazados']==1 and result['insertados']==0
    assert db.calidad(base)['rechazos'][0]['cantidad']==1


def test_filtros_parametrizados(base):
    insertar(base,[fila()])
    assert db.catalogo({'busqueda':"' OR 1=1 --"},base)==[]
    assert db.catalogo({'comercio':[]},base)==[]
    assert len(db.catalogo({'comercio':['colsubsidio'],'min_precio':99,'max_precio':101},base))==1


def test_busqueda_invalida():
    with pytest.raises(ValueError): validar_busqueda('a'*121)
    with pytest.raises(ValueError): validar_busqueda('x\x00y')


def test_no_observado_no_es_agotado(base):
    a=fila();b=fila(run='20260102T100000_test',sku='2',product='protex_avena_330')
    insertar(base,[a]);insertar(base,[b])
    assert {r['estado'] for r in db.cambios(a['ejecucion'],b['ejecucion'],path=base)}=={'nuevo','no observado'}


def test_rollback_por_comercio(base):
    a=fila();b=fila(sku='2');b['columna_desconocida']=1
    with pytest.raises(ValueError): insertar(base,[a,b])
    assert db.calidad(base)['totales'][0]['registros']==0
    assert db.ejecuciones(base)==[]


def test_mediana_y_promociones_sql(base):
    a=fila(price=100);b=fila(price=300,sku='2');b['promocion']=1
    insertar(base,[a,b])
    r=db.indicadores({},base)
    assert r['mediana']==200 and r['porcentaje_promocion']==50 and r['registros']==2
