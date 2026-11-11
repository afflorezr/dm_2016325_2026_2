"""Orquestación Taller 2 sobre el scraper evaluado, conservado en legado/."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import gzip
import json
import os
from pathlib import Path
import uuid
import db
from legado import scraper as original

ROOT=Path(__file__).resolve().parent
FUNCIONES={'colsubsidio':original.scrape_colsubsidio,'cafam':original.scrape_cafam,'larebaja':original.scrape_larebaja}


def archivadas(raw_root=ROOT/'raw'):
    sets=[{p.name for p in (Path(raw_root)/store).glob('*') if (p/'manifest.json').exists()} for store in FUNCIONES]
    return sorted(set.intersection(*sets),reverse=True)


@contextmanager
def bloqueo():
    lock=ROOT/'.actualizando.lock'
    try:
        fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    except FileExistsError:
        raise RuntimeError('Ya hay una actualización en curso. Si se interrumpió el proceso, elimina .actualizando.lock después de comprobarlo.') from None
    try:
        os.write(fd,f'{os.getpid()} {original.now()}'.encode());os.close(fd)
        yield
    finally:
        lock.unlink(missing_ok=True)


def evidencia_disponibilidad(rows,manifest,raw_root):
    """No confundir ausencia de IsAvailable con agotamiento explícito."""
    evidence={}
    directory=Path(raw_root)/manifest['comercio']/manifest['ejecucion']
    for section in manifest.get('categorias',[]):
        for filename in section['paginas']:
            for product in json.loads(gzip.decompress((directory/filename).read_bytes())):
                for item in product.get('items',[]):
                    seller=next((s for s in item.get('sellers',[]) if s.get('sellerId')=='1'),{})
                    value=seller.get('commertialOffer',{}).get('IsAvailable')
                    evidence.setdefault(str(item['itemId']), 'disponible' if value is True else 'agotado' if value is False else 'desconocida')
    for row in rows:
        row['disponibilidad']=evidence.get(row['sku'],'desconocida')
    return rows


def ejecutar(offline=False,run_id=None,path=None,raw_root=ROOT/'raw',callback=None):
    db.inicializar(path)
    if offline:
        runs=archivadas(raw_root)
        run_id=run_id or (runs[0] if runs else None)
        if not run_id or run_id not in runs:
            raise ValueError('No existe la ejecución archivada para los tres comercios')
    elif run_id:
        raise ValueError('El ID manual solo se admite en modo offline')
    else:
        run_id=datetime.now(original.COLOMBIA).strftime('%Y%m%dT%H%M%S')+'_'+uuid.uuid4().hex[:8]
    results=[]
    with bloqueo():
        for store,func in FUNCIONES.items():
            if callback: callback(store,'inicio',None)
            try:
                rows,manifest=func(run_id,Path(raw_root),offline)
                rows=evidencia_disponibilidad(rows,manifest,raw_root)
                summary=db.guardar(rows,manifest,'offline' if offline else 'online',path)
                expected={p['id'] for p in original.load_matches()}
                matched={r['producto_comun'] for r in rows if r['comparable'] and not db.validar_fila(r)}
                summary['correspondencias']=len(matched)
                summary['faltantes_comparables']=sorted(expected-matched)
            except Exception as exc:
                db.registrar_error(run_id,store,'offline' if offline else 'online',exc,path)
                summary={'comercio':store,'estado':'fallida','error':str(exc)}
            results.append(summary)
            if callback: callback(store,'fin',summary)
    return {'ejecucion':run_id,'resultados':results}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--offline',action='store_true')
    parser.add_argument('--run-id')
    parser.add_argument('--db',type=Path,default=db.DB)
    args=parser.parse_args()
    result=ejecutar(args.offline,args.run_id,args.db,callback=lambda s,e,r: print(s,e,json.dumps(r,ensure_ascii=False),flush=True))
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if any(r['estado']=='fallida' for r in result['resultados']):
        raise SystemExit(1)
