"""Reconstruye la entrega en una base NUEVA usando exclusivamente las respuestas raw."""
import argparse
import json
from pathlib import Path
import db
import scraper
from legado.scraper import parse_store,SOURCES


def reconstruir(destino):
    destino=Path(destino)
    if destino.exists():raise FileExistsError('El destino ya existe; indica un archivo nuevo para conservar el original')
    index=json.loads((db.ROOT/'ejecuciones_entrega.json').read_text(encoding='utf-8'))
    for run in index['taller_1']:
        for store in SOURCES:
            rows,manifest=parse_store(store,run,db.ROOT/'raw')
            db.cargar_legado(rows,manifest,destino)
    db.inicializar(destino)
    for run in index['taller_2']:
        result=scraper.ejecutar(True,run,destino)
        if any(r['estado']=='fallida' for r in result['resultados']):raise RuntimeError(result)
    return destino


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db',type=Path,required=True)
    args=parser.parse_args();reconstruir(args.db)
    print('Reconstrucción terminada; huella de observaciones:',db.huella_observaciones(args.db))
