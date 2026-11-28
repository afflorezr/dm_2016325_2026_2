"""Reglas explícitas anteriores a la inserción y validación de cobertura."""
import math
from datetime import datetime

def validar_fila(r):
    """Devuelve motivos de rechazo. No fabrica precios ni fechas."""
    errores=[]
    p=r.get('precio_actual')
    if not isinstance(p,(float,int)) or isinstance(p,bool) or not math.isfinite(p) or p<=0:
        errores.append('Precio ausente, no numérico o no positivo')
    for k in ('comercio','sku','url','fecha_hora_consulta'):
        valor=r.get(k)
        if not isinstance(valor,str) or not valor.strip():
            errores.append('Falta '+k)
    url=r.get('url')
    if isinstance(url,str) and url:
        from urllib.parse import urlsplit
        try:
            partes=urlsplit(url)
            if partes.scheme!='https' or not partes.netloc:errores.append('URL no HTTPS válida')
        except ValueError:errores.append('URL inválida')
    try:
        fecha=datetime.fromisoformat(r['fecha_hora_consulta'])
        if fecha.utcoffset().total_seconds()!=-18000:
            errores.append('Fecha sin hora de Colombia')
    except (ValueError,TypeError,KeyError,AttributeError):
        errores.append('Fecha ISO inválida')
    return errores

def validar_cobertura(conn,corrida_id):
    """Separa cobertura de precios e inventario; valida el mínimo completo sin ocultar agotados."""
    filas=conn.execute('''SELECT producto_id FROM v_comparables WHERE corrida_id=? AND precio>0 GROUP BY producto_id HAVING COUNT(*)=3 AND COUNT(DISTINCT comercio_id)=3''',(corrida_id,)).fetchall()
    duplicados=conn.execute('''SELECT producto_id,comercio_id,COUNT(*) FROM v_comparables WHERE corrida_id=? GROUP BY producto_id,comercio_id HAVING COUNT(*)>1''',(corrida_id,)).fetchall()
    disponibles=conn.execute('''SELECT v.producto_id FROM v_comparables v
    JOIN observaciones o ON o.anuncio_id=v.anuncio_id AND o.ejecucion_id=v.ejecucion_id
    WHERE v.corrida_id=? AND v.precio>0 AND o.disponibilidad='disponible'
    GROUP BY v.producto_id HAVING COUNT(*)=3 AND COUNT(DISTINCT v.comercio_id)=3''',(corrida_id,)).fetchall()
    precios_validos=len(filas)>=8 and not duplicados
    return {'productos_completos':len(filas),'observaciones_comparables_completas':len(filas)*3,
            'duplicados':duplicados,'valida':precios_validos,
            'productos_disponibles_en_tres':len(disponibles),
            'cumple_disponibilidad_minima':len(disponibles)>=8,
            'cumple_requisito_completo':precios_validos and len(disponibles)>=8}
