"""Auditoría de solo lectura: integridad, referencias raw, hashes y dos fechas completas."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import db


def verificar(path=None,root=None):
    root=Path(root or db.ROOT)
    issues=[];checked=set()
    for row in db.referencias_raw(path):
        relative=row['archivo_raw'];file=(root/relative).resolve()
        if root.resolve() not in file.parents:
            issues.append('Ruta fuera del proyecto: '+relative);continue
        if relative in checked:continue
        checked.add(relative)
        try:
            payload=gzip.decompress(file.read_bytes())
            meta=json.loads(file.with_suffix('.meta.json').read_text(encoding='utf-8'))
            if hashlib.sha256(payload).hexdigest()!=meta['sha256']:issues.append('Hash no coincide: '+relative)
        except (OSError,ValueError,KeyError) as exc:issues.append(relative+': '+str(exc))
    runs=db.ejecuciones(path)
    complete=[r for r in runs if r['completos']==3 and r['comercios']==3 and r['correspondencias']==24]
    dates=sorted({r['fecha'][:10] for r in complete})
    if len(dates)<2:issues.append('Faltan dos fechas completas con 24 correspondencias disponibles')
    quality=db.calidad(path)
    if quality['integridad']!=[{'integrity_check':'ok'}]:issues.append('Falló integridad SQLite')
    for row in quality['cobertura']:
        if row['estado']=='completa' and row['esperados']!=row['obtenidos']:
            issues.append('Cobertura declarada completa no coincide: '+str(row))
    for file in root.rglob('*'):
        if file.is_file() and file.stat().st_size>=100_000_000:issues.append('Archivo de 100 MB o más: '+str(file.relative_to(root)))
    result={'correcto':not issues,'fechas_completas':dates,'ejecuciones':runs,
        'respuestas_referenciadas_verificadas':len(checked),'totales':quality['totales'],
        'rechazos':quality['rechazos'],'correcciones':len(quality['correcciones']),'errores':issues}
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db',type=Path,default=db.DB)
    parser.add_argument('--salida',type=Path)
    args=parser.parse_args();result=verificar(args.db)
    text=json.dumps(result,ensure_ascii=False,indent=2)
    if args.salida:args.salida.write_text(text,encoding='utf-8')
    print(text)
    raise SystemExit(0 if result['correcto'] else 1)
