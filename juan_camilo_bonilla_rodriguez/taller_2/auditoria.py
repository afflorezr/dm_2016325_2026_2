"""Verifica las observaciones contra sus copias crudas, sin peticiones HTTP."""
from contextlib import closing
from pathlib import Path
import sqlite3
import requests
from codigo.config import ROOT, DB_PATH
from codigo.limpieza import limpiar
from codigo.validacion import validar_cobertura
import db


def verificar(ruta=DB_PATH):
    from scraper import SCRAPERS
    original=requests.get
    def sin_red(*args,**kwargs):raise AssertionError('La auditoría intentó consultar la red')
    requests.get=sin_red
    try:
        with db.conexion(ruta) as con:
            assert con.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
            assert not con.execute('PRAGMA foreign_key_check').fetchall()
            n=0
            for slug,corrida in con.execute('''SELECT DISTINCT c.slug,e.corrida_id FROM observaciones o JOIN ejecuciones e USING(ejecucion_id)
              JOIN comercios c USING(comercio_id) ORDER BY e.corrida_id,c.slug''').fetchall():
                crudas=SCRAPERS[slug](offline=True,corrida_id=corrida)
                filas={str(r['sku']):r for r in crudas.to_dict('records')}
                observadas=con.execute('''SELECT a.sku,o.precio,o.precio_antes,o.fecha_hora,o.url,o.raw_ref
                  FROM observaciones o JOIN anuncios a USING(anuncio_id) JOIN ejecuciones e USING(ejecucion_id)
                  JOIN comercios c ON c.comercio_id=e.comercio_id WHERE e.corrida_id=? AND c.slug=?''',(corrida,slug)).fetchall()
                for sku,precio,antes,fecha,url,raw in observadas:
                    r=filas[sku]
                    assert precio==r['precio_actual'],(slug,corrida,sku,'precio')
                    assert antes==r['precio_antes'],(slug,corrida,sku,'precio anterior')
                    assert fecha==r['fecha_hora_consulta'] and url==r['url']
                    assert (ROOT/raw).is_file() and not Path(raw).is_absolute()
                    n+=1
            duplicados=con.execute('SELECT anuncio_id,ejecucion_id,COUNT(*) FROM observaciones GROUP BY 1,2 HAVING COUNT(*)>1').fetchall()
            assert not duplicados
            completos=db.control_historial(ruta)
            assert completos.fecha.nunique()>=2,'Faltan dos fechas completas'
            for corrida in completos.corrida_id:
                assert validar_cobertura(con,corrida)['cumple_requisito_completo']
            print(f'Verificadas {n} observaciones contra raw; integridad y unicidad correctas; {completos.fecha.nunique()} fechas completas.')
    finally:requests.get=original

if __name__=='__main__':verificar()
