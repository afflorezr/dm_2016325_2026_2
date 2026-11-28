"""Pruebas con datos mínimos y SQLite temporal; no usan la entrega ni los sitios."""
from functools import partial
import sqlite3
import pytest
import pandas as pd
import db
from codigo.config import COMERCIOS

@pytest.fixture
def muestra(tmp_path):
    ruta=tmp_path/'prueba.sqlite';db.migrar(ruta)
    with db.conexion(ruta) as con:
        for pid in [101,102]:
            con.execute('INSERT INTO productos VALUES(?,?,?,?,?,?,?,?)',(pid,f'Tiras prueba {pid}','prueba','tiras_reactivas',50,'unidad',1,None))
        for n,slug in enumerate(COMERCIOS):
            cid=con.execute('SELECT comercio_id FROM comercios WHERE slug=?',(slug,)).fetchone()[0]
            for dia in [1,2]:
                corrida=f'2026-08-0{dia}T100000';fecha=f'2026-08-0{dia}T10:00:00-05:00'
                eid=con.execute('INSERT INTO ejecuciones(corrida_id,comercio_id,inicio,n_registros,estado) VALUES(?,?,?,2,?)',(corrida,cid,fecha,'completa')).lastrowid
                for pid in [101,102]:
                    con.execute('INSERT OR IGNORE INTO cohortes_comparables VALUES(?,?)',(corrida,pid))
                    con.execute('''INSERT OR IGNORE INTO anuncios(comercio_id,sku,producto_id,comparable,nombre_std,marca_std,subcategoria_std,contenido,unidad,n_unidades,titulo_original,texto_original)
                      VALUES(?,?,?,1,?,'prueba','tiras_reactivas',50,'unidad',1,?,?)''',(cid,str(pid),pid,f'Tiras prueba {pid}',f'Tiras {pid}',f'Tiras {pid}'))
                    aid=con.execute('SELECT anuncio_id FROM anuncios WHERE comercio_id=? AND sku=?',(cid,str(pid))).fetchone()[0]
                    # Habib y Farmaprime empatan; Farmaweb cuesta el doble.
                    precio=(100 if n<2 else 200)+(20 if dia==2 and n==0 else 0)
                    con.execute('INSERT INTO observaciones(anuncio_id,ejecucion_id,precio,fecha_hora,disponibilidad,url,raw_ref) VALUES(?,?,?,?,?,?,?)',(aid,eid,precio,fecha,'disponible','https://example.com/p','raw/prueba.json.gz'))
        con.commit()
    return ruta


def test_ahorro_empates_sql(muestra):
    r=db.ahorros({'corrida':'2026-08-01T100000'},muestra).iloc[0]
    assert r.ahorro_cop==100 and r.ahorro_pct==50
    assert set(r.menor_precio_en.split(' / '))=={'Habib','Farmaprime'}


def test_cambios_sobre_mismo_anuncio(muestra):
    d=db.cambios('2026-08-01T100000','2026-08-02T100000',10,muestra)
    r=d[d.comercio=='Habib'].iloc[0]
    assert r.cambio_cop==20 and r.cambio_pct==20 and r.variacion_grande==1
    assert len(d[d.cambio=='Sin cambio'])==4


def test_canasta_no_total_incompleto(muestra):
    with db.conexion(muestra) as con:
        con.execute("DELETE FROM observaciones WHERE anuncio_id IN (SELECT anuncio_id FROM anuncios WHERE producto_id=102 AND comercio_id=(SELECT comercio_id FROM comercios WHERE nombre='Habib')) AND ejecucion_id IN(SELECT ejecucion_id FROM ejecuciones WHERE corrida_id='2026-08-02T100000')")
        con.commit()
    t,_=db.canasta('2026-08-02T100000',{101:2,102:1},muestra)
    r=t.set_index('comercio').loc['Habib']
    assert r.faltantes==1 and pd.isna(r.total_cop)
    assert t.set_index('comercio').loc['Farmaprime'].total_cop==300


def test_canasta_agotado_no_se_ofrece(muestra):
    with db.conexion(muestra) as con:
        con.execute("UPDATE observaciones SET disponibilidad='agotado' WHERE anuncio_id IN (SELECT anuncio_id FROM anuncios WHERE comercio_id=(SELECT comercio_id FROM comercios WHERE nombre='Habib'))")
        con.commit()
    t,_=db.canasta('2026-08-02T100000',{101:1},muestra)
    assert t.set_index('comercio').loc['Habib'].faltantes==1


def test_canasta_minima_y_cantidades(muestra):
    t,_=db.canasta('2026-08-01T100000',{101:2,102:3},muestra)
    assert set(t.minimo_combinado_cop)=={500}
    assert t.set_index('comercio').loc['Farmaweb'].ahorro_combinado_cop==500
    with pytest.raises(ValueError):db.canasta('x',{101:0},muestra)


def test_busqueda_y_filtros_parametrizados(muestra):
    assert len(db.filtrados({'busqueda':'prueba 101','marca':'prueba','corrida':'2026-08-01T100000'},muestra))==3
    assert db.filtrados({'comercios':[]},muestra).empty
    with pytest.raises(ValueError):db.filtrados({'busqueda':"' OR 1=1 --"},muestra)
    assert db.filtrados({'marca':"' OR 1=1 --"},muestra).empty


def test_no_observado_no_es_agotado(muestra):
    with db.conexion(muestra) as con:
        con.execute("DELETE FROM observaciones WHERE ejecucion_id IN(SELECT ejecucion_id FROM ejecuciones WHERE corrida_id='2026-08-02T100000') AND anuncio_id=(SELECT MIN(anuncio_id) FROM anuncios)")
        con.commit()
    d=db.cambios('2026-08-01T100000','2026-08-02T100000',10,muestra)
    assert len(d[d.cambio=='No observado'])==1
    assert d[d.cambio=='No observado'].iloc[0].disponibilidad=='no observado'


def test_validacion_lote_rechaza_duplicados(tmp_path):
    from validacion import preparar_lote
    from codigo.limpieza import limpiar
    from test_comparador import fila
    m=tmp_path/'m.csv';pd.DataFrame([{'comercio':'Locatel','sku':'sku1'}]).to_csv(m,index=False)
    d=limpiar(pd.DataFrame([fila(),fila()]))
    salida,rechazos,cobertura=preparar_lote(d,m,'Locatel')
    assert salida.empty and len(rechazos)==2 and not cobertura


def test_interfaz_temporal(muestra,monkeypatch):
    import interfaz
    from streamlit.testing.v1 import AppTest
    funciones=['opciones','filtrados','indicadores','oferta','estados','evolucion','precios_unidad','familias','ahorros','cambios','cambios_ultima','canasta','control_historial']
    for nombre in funciones:monkeypatch.setattr(db,nombre,partial(getattr(db,nombre),ruta=muestra))
    monkeypatch.setattr(interfaz,'DB_PATH',muestra)
    monkeypatch.setattr(db,'migrar',lambda:None)
    interfaz.consultar.clear()
    app=AppTest.from_file('../app.py',default_timeout=30).run()
    assert not app.exception
    assert len(app.metric)>=6
    app.text_input(key='f_busqueda').set_value('zzzinexistente').run()
    assert not app.exception
    assert any('Ningún producto' in x.value for x in app.info)
    interfaz.consultar.clear()


def test_paginas_cambios_y_canasta(muestra,monkeypatch):
    import interfaz
    from streamlit.testing.v1 import AppTest
    for nombre in ['opciones','cambios','estados','canasta']:
        monkeypatch.setattr(db,nombre,partial(getattr(db,nombre),ruta=muestra))
    monkeypatch.setattr(interfaz,'DB_PATH',muestra);interfaz.consultar.clear()
    at=AppTest.from_string('from paginas.cambios import mostrar\nmostrar()',default_timeout=30).run()
    assert not at.exception and len(at.metric)==4
    at=AppTest.from_string('from paginas.canasta import mostrar\nmostrar()',default_timeout=30).run()
    assert not at.exception
    at.multiselect[0].set_value([101,102]).run()
    assert not at.exception and len(at.metric)==1
    interfaz.consultar.clear()


def test_actualizacion_continua_tras_falla_y_sin_duplicados(tmp_path,monkeypatch):
    import scraper
    from codigo.limpieza import limpiar
    from test_comparador import fila
    destino=tmp_path/'base.sqlite';datos_dir=tmp_path/'datos';datos_dir.mkdir()
    filas_mapeo=[]
    for comercio in COMERCIOS.values():
        for pid in range(1,9):
            filas_mapeo.append(dict(producto_id=pid,nombre_std=f'Tiras {pid}',marca_std='glucoquick',
              subcategoria_std='tiras_reactivas',contenido=50,unidad='unidad',n_unidades=1,concentracion=None,comercio=comercio,sku=str(pid)))
    pd.DataFrame(filas_mapeo).to_csv(datos_dir/'correspondencia.csv',index=False)
    monkeypatch.setattr(scraper,'DATOS_DIR',datos_dir);monkeypatch.setattr(scraper,'ROOT',tmp_path)
    def fabrica(slug):
        def extraer(**kwargs):
            if slug=='comercio5':raise RuntimeError('Falla de red simulada solo en prueba')
            filas=[]
            for pid in range(1,9):
                r=fila();r.update(comercio=COMERCIOS[slug],sku=str(pid),titulo_original='Tiras Glucoquick 50 unidades')
                filas.append(r)
            d=pd.DataFrame(filas);d.attrs.update(completa=True,n_reportado_sitio=8,notas='prueba temporal',disponibilidad={str(i):'disponible' for i in range(1,9)})
            return d
        return extraer
    monkeypatch.setattr(scraper,'SCRAPERS',{slug:fabrica(slug) for slug in COMERCIOS})
    for _ in range(2):
        r=scraper.run_all(offline=bool(_),corrida_id='prueba',db_path=destino,raw_dir=tmp_path/'raw')
        assert r['comercio5']['estado']=='fallida'
        assert r['comercio4']['n']==8 and r['comercio6']['n']==8
    with db.conexion(destino) as con:
        assert con.execute('SELECT COUNT(*) FROM observaciones').fetchone()[0]==16
        assert con.execute('SELECT COUNT(*) FROM ejecuciones').fetchone()[0]==3


def test_rechazo_faltantes_nulos_sin_abortar():
    from codigo.validacion import validar_fila
    from test_comparador import fila
    r=fila();r.update(url=float('nan'),comercio=None,fecha_hora_consulta=None)
    errores=validar_fila(r)
    assert 'Falta url' in errores and 'Falta comercio' in errores and 'Falta fecha_hora_consulta' in errores
