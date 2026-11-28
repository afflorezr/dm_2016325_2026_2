"""Reconstrucción del historial conservando fuentes y correspondencias de cada captura."""
import os
import json
from .config import RAW_DIR

def reconstruir(destino):
    """Procesa los manifiestos en orden, sin sobrescribir un destino existente."""
    from scraper import run_all
    if os.path.exists(destino):raise ValueError('El destino ya existe: elija uno nuevo')
    base=os.path.join(RAW_DIR,'manifiestos')
    for nombre in sorted(os.listdir(base)):
        if not nombre.endswith('.json'):continue
        with open(os.path.join(base,nombre),encoding='utf-8') as f:m=json.load(f)
        run_all(offline=True,corrida_id=m['corrida_id'],comercios=m['comercios'],db_path=destino)


import tempfile
import sqlite3
import requests
import pandas as pd
from .consultas import ejecutar
from .validacion import validar_cobertura
from .db import ultima_corrida

SQL = '''SELECT c.slug,a.sku,e.corrida_id,o.fecha_hora,o.precio,o.precio_antes,o.promocion,o.url,o.raw_ref,o.disponibilidad
 FROM observaciones o JOIN anuncios a USING(anuncio_id) JOIN comercios c USING(comercio_id)
 JOIN ejecuciones e USING(ejecucion_id) ORDER BY c.slug,a.sku,e.corrida_id,o.fecha_hora'''

def verificar():
    """Bloquea HTTP, reconstruye el historial y contrasta todos los precios y SQL."""
    original=requests.get
    def sin_red(*args,**kwargs):
        raise AssertionError('El modo sin conexión intentó usar HTTP')
    with tempfile.TemporaryDirectory() as carpeta:
        ruta=os.path.join(carpeta,'nueva.sqlite')
        try:
            requests.get=sin_red
            reconstruir(ruta)
        finally:
            requests.get=original
        a=sqlite3.connect('comparador_precios.sqlite');b=sqlite3.connect(ruta)
        try:
            assert a.execute(SQL).fetchall()==b.execute(SQL).fetchall(), 'El historial no coincide con raw'
            corrida=ultima_corrida(a)
            assert validar_cobertura(a,corrida)['valida']
            for n in range(1,9):
                pd.testing.assert_frame_equal(ejecutar(n,a,corrida),ejecutar(n,b,corrida))
            for con in (a,b):
                assert con.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
                assert not con.execute('PRAGMA foreign_key_check').fetchall()
            for (raw,) in a.execute('SELECT DISTINCT raw_ref FROM observaciones'):
                assert os.path.isfile(raw), 'Copia cruda inexistente: '+raw
            print('VERIFICADO: historial y ocho consultas idénticos, copias crudas e integridad; cero peticiones HTTP.')
            print('Cobertura de la corrida activa:',validar_cobertura(a,corrida))
            print('Disponibilidad mínima de ocho en tres comercios:',validar_cobertura(a,corrida)['cumple_disponibilidad_minima'])
        finally:
            a.close();b.close()

