import json
import gzip
import pytest
import db
import scraper
from test_logica import fila


def test_disponibilidad_explicita(tmp_path):
    folder=tmp_path/'colsubsidio'/'r';folder.mkdir(parents=True)
    payload=[{'items':[{'itemId':str(i),'sellers':[{'sellerId':'1','commertialOffer':offer}]} for i,offer in enumerate([{'IsAvailable':True},{'IsAvailable':False},{}])]}]
    (folder/'pagina.json.gz').write_bytes(gzip.compress(json.dumps(payload).encode()))
    manifest={'ejecucion':'r','comercio':'colsubsidio','categorias':[{'paginas':['pagina.json.gz']}]}
    result=scraper.evidencia_disponibilidad([{'sku':str(i)} for i in range(3)],manifest,tmp_path)
    assert [r['disponibilidad'] for r in result]==['disponible','agotado','desconocida']


def test_fallo_aislado_y_modo_offline(tmp_path,monkeypatch):
    path=tmp_path/'prueba.sqlite'
    monkeypatch.setattr(scraper,'ROOT',tmp_path)
    monkeypatch.setattr(scraper,'archivadas',lambda raw:['r'])
    monkeypatch.setattr(scraper,'evidencia_disponibilidad',lambda rows,manifest,raw:rows)
    calls=[]
    def tienda(store):
        def call(run,raw,offline):
            calls.append((store,offline))
            if store=='cafam':raise OSError('Fallo de red simulado exclusivamente en prueba')
            row=fila(run=run,store=store)
            return [row],dict(ejecucion=run,comercio=store,inicio=row['fecha_hora'],estado='completa',categorias=[])
        return call
    monkeypatch.setattr(scraper,'FUNCIONES',{s:tienda(s) for s in ('colsubsidio','cafam','larebaja')})
    result=scraper.ejecutar(True,'r',path,raw_root=tmp_path)
    assert len(calls)==3 and all(offline for _,offline in calls)
    assert result['resultados'][1]['estado']=='fallida'
    assert db.calidad(path)['totales'][0]['registros']==2
    assert db.ejecuciones(path)[0]['comercios']==3
    assert not (tmp_path/'.actualizando.lock').exists()
