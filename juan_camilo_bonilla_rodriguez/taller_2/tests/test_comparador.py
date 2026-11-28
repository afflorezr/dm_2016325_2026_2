"""Pruebas aisladas: no consultan sitios ni modifican la base de la entrega."""
import sqlite3
import pytest
import pandas as pd
from codigo.limpieza import limpiar_precio, normalizar_contenido, limpiar
from codigo.validacion import validar_fila
from codigo import db
from scraper import COLUMNAS

@pytest.fixture
def base(tmp_path):
    ruta=str(tmp_path/'temporal.sqlite');db.crear_bd(ruta);con=db.conectar(ruta)
    yield con
    con.close()

def fila(precio=100,fecha='2026-08-14T10:35:00-05:00'):
    return dict(zip(COLUMNAS,['Locatel','sku1','https://example.com/p','Termómetro digital',None,'Marca','termometros',precio,None,0,fecha,'raw/prueba.json.gz']))

def insertar(con,corrida='a',precio=100,fecha='2026-08-14T10:35:00-05:00'):
    eid=db.registrar_ejecucion(con,corrida,'comercio1',fecha,1,1,'completa','prueba')
    d=limpiar(pd.DataFrame([fila(precio,fecha)]));d.attrs['disponibilidad']={'sku1':'disponible'}
    return db.insertar_df(con,d,eid,'comercio1')

def test_precio_colombiano():
    assert limpiar_precio('$ 12.900')==12900
    assert limpiar_precio('$ 12.900,50')==12900.5
    assert limpiar_precio(None) is None
    assert limpiar_precio(0) is None

def test_unidades():
    assert normalizar_contenido(1.5,'L')==(1500,'mL')
    assert normalizar_contenido(2,'kg')==(2000,'g')
    assert normalizar_contenido(10,'mg')==(10,'mg')


def test_reinsertar_no_duplica(base):
    assert insertar(base)['obs_insertadas']==1
    assert insertar(base)['obs_duplicadas']==1
    assert base.execute('SELECT COUNT(*) FROM observaciones').fetchone()[0]==1



def test_rechazo_trazable(base):
    insertar(base,precio=None)
    assert base.execute('SELECT COUNT(*) FROM observaciones').fetchone()[0]==0
    assert base.execute('SELECT COUNT(*) FROM rechazos').fetchone()[0]==1

def test_fecha_obligatoria():
    r=fila();r['fecha_hora_consulta']='2026-08-14'
    assert validar_fila(r)

def test_multipack():
    r=fila();r['titulo_original']='Oferta Tiras Glucoquick X 25Und Pague 1 Lleve 2'
    d=limpiar(pd.DataFrame([r]));assert d.iloc[0].contenido==25;assert d.iloc[0].n_unidades==2

def test_sinonimos_de_tensiometro_y_exclusiones():
    from codigo.limpieza import clasificar
    assert clasificar('Monitor Omron Presión Arterial Automático Brazo')=='tensiometro'
    assert clasificar('Monitor Presion Arterial Omron Hem-7600T-E')=='tensiometro'
    assert clasificar('Manometro Para Tensiometro Manual')=='otro'
    assert clasificar('Prueba de embarazo')=='otro'

@pytest.fixture
def ocho_presentaciones(base):
    """Ocho identidades con tres precios, pero solo una disponible en todos."""
    for pid in range(1,9):
        marca='accu-chek' if pid==1 else 'marca'
        clase='lancetas' if pid==1 else 'termometro'
        contenido=25 if pid==1 else 1
        nombre='Softclix 25' if pid==1 else f'Producto {pid}'
        base.execute('INSERT INTO productos VALUES(?,?,?,?,?,?,?,?)',(pid,nombre,marca,clase,contenido,'unidad',1,None))
        base.execute('INSERT INTO cohortes_comparables VALUES(?,?)',('auditoria',pid))
        for cid,slug in [(1,'comercio1'),(2,'comercio2'),(3,'comercio3')]:
            eid=db.registrar_ejecucion(base,'auditoria',slug,'2026-08-14T10:35:00-05:00',8,8,'completa','prueba aislada')
            cur=base.execute('INSERT INTO anuncios(comercio_id,sku,titulo_original,texto_original,nombre_std,marca_std,subcategoria_std,contenido,unidad,n_unidades,producto_id,comparable) VALUES(?,?,?,?,?,?,?,?,?,?,?,1)',(cid,str(pid),nombre,nombre,nombre,marca,clase,contenido,'unidad',1,pid))
            disp='agotado' if cid==2 and pid>1 else 'disponible'
            base.execute('INSERT INTO observaciones(anuncio_id,ejecucion_id,precio,promocion,fecha_hora,disponibilidad) VALUES(?,?,?,0,?,?)',(cur.lastrowid,eid,100 if cid<3 else 200,'2026-08-14T10:35:00-05:00',disp))
    return base

def test_cobertura_precios_no_oculta_agotados(ocho_presentaciones):
    from codigo.validacion import validar_cobertura
    from codigo.consultas import ejecutar
    c=ocho_presentaciones;r=validar_cobertura(c,'auditoria')
    assert r['valida'] and r['productos_completos']==8
    assert r['productos_disponibles_en_tres']==1
    assert not r['cumple_requisito_completo']
    resultado=ejecutar(2,c,'auditoria').iloc[0]
    assert resultado.cobertura_precios=='CUMPLE'
    assert resultado.disponibilidad_minima=='NO CUMPLE'
    c.execute("UPDATE observaciones SET disponibilidad='disponible'")
    assert validar_cobertura(c,'auditoria')['cumple_requisito_completo']

def test_sql_precios_y_ahorros_con_empates(ocho_presentaciones):
    from codigo.consultas import ejecutar
    c=ocho_presentaciones
    r=ejecutar(3,c,'auditoria').set_index('producto_id').loc[1]
    assert r.minimo==100 and r.maximo==200
    assert r.promedio==pytest.approx(400/3)
    assert set(r.comercios_menor_precio.split(' / '))=={'Locatel','Cafam'}
    a=ejecutar(4,c,'auditoria').set_index('producto_id').loc[1]
    assert a.ahorro_cop==100 and a.ahorro_pct==50

def test_sql_precio_unitario_compara_tamanos(ocho_presentaciones):
    from codigo.consultas import ejecutar
    c=ocho_presentaciones
    eid=c.execute("SELECT ejecucion_id FROM ejecuciones WHERE corrida_id='auditoria' AND comercio_id=1").fetchone()[0]
    cur=c.execute("INSERT INTO anuncios(comercio_id,sku,titulo_original,texto_original,marca_std,subcategoria_std,contenido,unidad,n_unidades,comparable) VALUES(1,'200','Softclix 200','Softclix 200','accu-chek','lancetas',200,'unidad',1,0)")
    c.execute("INSERT INTO observaciones(anuncio_id,ejecucion_id,precio,fecha_hora,disponibilidad) VALUES(?,?,600,'2026-08-14T10:35:00-05:00','disponible')",(cur.lastrowid,eid))
    r=ejecutar(5,c,'auditoria')
    familia=r[r.grupo.str.contains('Softclix')]
    assert len(familia)==1 and familia.iloc[0].contenido_total==200
    assert familia.iloc[0].cop_por_unidad==3

def test_promocion_textual_preserva_titulo_de_captura(base):
    r=fila();r['titulo_original']='Oferta termómetro digital'
    eid=db.registrar_ejecucion(base,'promo','comercio1',r['fecha_hora_consulta'],1,1,'completa','prueba')
    db.insertar_df(base,limpiar(pd.DataFrame([r])),eid,'comercio1')
    base.execute("UPDATE anuncios SET titulo_original='Termómetro sin oferta'")
    p=base.execute('SELECT descuento_verificable,promocion_anunciada FROM v_promociones').fetchone()
    assert p==(0,1)

def test_woocommerce_escala_cop_y_existencias():
    from scraper import _woo_producto
    p={'id':7,'name':'Tiras Glucoquick 50 unidades','permalink':'https://example.com/p',
       'description':'Descripción original','short_description':'','on_sale':False,
       'prices':{'currency_code':'COP','currency_minor_unit':2,'price':'1234500','regular_price':'1500000'},
       'categories':[],'brands':[],'attributes':[],'images':[],
       'is_in_stock':True,'is_purchasable':True,'is_on_backorder':False}
    env={'fecha_hora_consulta':'2026-08-14T10:35:00-05:00'}
    fila,disp,_=_woo_producto(p,'comercio5','raw/prueba.json.gz',env)
    assert fila['precio_actual']==12345 and fila['precio_antes']==15000
    assert disp=='disponible'
    p['is_on_backorder']=True
    assert _woo_producto(p,'comercio5','raw/prueba.json.gz',env)[1]!='disponible'
    p['is_in_stock']=False
    assert _woo_producto(p,'comercio5','raw/prueba.json.gz',env)[1]=='agotado'

def test_cohorte_no_incluye_identidades_de_otra_seleccion(ocho_presentaciones):
    c=ocho_presentaciones
    c.execute("INSERT INTO productos(producto_id,nombre_std) VALUES(9,'Presentación anterior')")
    cur=c.execute("INSERT INTO anuncios(comercio_id,sku,producto_id,comparable) VALUES(1,'anterior',9,1)")
    eid=c.execute("SELECT ejecucion_id FROM ejecuciones WHERE corrida_id='auditoria' AND comercio_id=1").fetchone()[0]
    c.execute("INSERT INTO observaciones(anuncio_id,ejecucion_id,precio,fecha_hora) VALUES(?,?,50,'2026-08-14T10:35:00-05:00')",(cur.lastrowid,eid))
    assert c.execute("SELECT COUNT(*) FROM v_comparables WHERE corrida_id='auditoria' AND producto_id=9").fetchone()[0]==0
    assert c.execute("SELECT COUNT(*) FROM v_observaciones WHERE corrida_id='auditoria' AND producto_id=9").fetchone()[0]==1
