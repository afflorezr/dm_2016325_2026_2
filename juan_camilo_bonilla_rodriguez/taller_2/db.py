"""Acceso a SQLite. Filtros y cálculos se ejecutan en SQL con parámetros."""
from contextlib import contextmanager
import json
import math
import sqlite3
from pathlib import Path
import pandas as pd
from codigo import db as legado
from codigo.config import DB_PATH, COMERCIOS, ROOT
from validacion import texto_busqueda

COMERCIOS_NOMBRES=tuple(COMERCIOS.values())

@contextmanager
def conexion(ruta=DB_PATH):
    con=legado.conectar(ruta)
    try:yield con
    finally:con.close()


def migrar(ruta=DB_PATH):
    """Añade vistas e índices sin alterar las observaciones heredadas."""
    legado.crear_bd(ruta)
    with conexion(ruta) as con:
        campos={r[1] for r in con.execute('PRAGMA table_info(observaciones)')}
        if 'descartada' not in campos:
            con.execute('ALTER TABLE observaciones ADD COLUMN descartada INTEGER NOT NULL DEFAULT 0 CHECK(descartada IN(0,1))')
        con.executescript('''
        CREATE INDEX IF NOT EXISTS idx_anuncio_producto ON anuncios(producto_id,comercio_id);
        CREATE INDEX IF NOT EXISTS idx_ejecucion_corrida ON ejecuciones(corrida_id,comercio_id,estado);
        CREATE INDEX IF NOT EXISTS idx_precio ON observaciones(precio,promocion);
        DROP VIEW IF EXISTS v_catalogo;
        CREATE VIEW v_catalogo AS
        SELECT v.*,o.disponibilidad,o.raw_ref,o.descartada,
          COALESCE(o.texto_original_captura,v.texto_original) AS texto_capturado,
          COALESCE(p.nombre_std,v.nombre_std,v.titulo_original) AS producto_nombre,
          COALESCE(p.marca_std,v.marca_std) AS producto_marca,
          CASE WHEN v.contenido_total>0 THEN printf('%g %s',v.contenido_total,v.unidad) ELSE 'Sin identificar' END AS presentacion,
          f.familia
        FROM v_observaciones v JOIN observaciones o USING(anuncio_id,ejecucion_id)
        LEFT JOIN productos p USING(producto_id) LEFT JOIN familias_unidad f USING(producto_id)
        WHERE o.descartada=0;
        DROP VIEW IF EXISTS v_comparables;
        CREATE VIEW v_comparables AS
        SELECT v.* FROM v_catalogo v JOIN cohortes_comparables h USING(corrida_id,producto_id)
        WHERE v.comparable=1;
        DROP VIEW IF EXISTS v_ultimo_precio;
        CREATE VIEW v_ultimo_precio AS
        SELECT * FROM v_catalogo v WHERE NOT EXISTS(
        SELECT 1 FROM v_catalogo z WHERE z.anuncio_id=v.anuncio_id AND z.fecha_hora>v.fecha_hora);
        DROP VIEW IF EXISTS v_cambios_precio;
        CREATE VIEW v_cambios_precio AS
        SELECT *,precio-precio_anterior AS cambio_cop,
          100.0*(precio-precio_anterior)/NULLIF(precio_anterior,0) AS cambio_pct
        FROM (SELECT v.*,LAG(precio) OVER(PARTITION BY anuncio_id ORDER BY fecha_hora,ejecucion_id) AS precio_anterior,
          LAG(corrida_id) OVER(PARTITION BY anuncio_id ORDER BY fecha_hora,ejecucion_id) AS corrida_anterior
          FROM v_catalogo v);
        DROP VIEW IF EXISTS v_disponibilidad;
        CREATE VIEW v_disponibilidad AS
        SELECT e.corrida_id,e.ejecucion_id,c.nombre AS comercio,a.anuncio_id,a.producto_id,
          COALESCE(o.disponibilidad,'no observado') AS disponibilidad,e.estado
        FROM ejecuciones e JOIN comercios c USING(comercio_id) JOIN anuncios a USING(comercio_id)
        LEFT JOIN observaciones o ON o.ejecucion_id=e.ejecucion_id AND o.anuncio_id=a.anuncio_id AND o.descartada=0
        WHERE EXISTS(SELECT 1 FROM observaciones z JOIN ejecuciones ez USING(ejecucion_id)
          WHERE z.anuncio_id=a.anuncio_id AND ez.corrida_id<=e.corrida_id);
        ''')
        con.commit()


def tabla(sql,params=(),ruta=DB_PATH):
    with conexion(ruta) as con:return pd.read_sql_query(sql,con,params=params)


def opciones(ruta=DB_PATH):
    return {
      'comercios':list(COMERCIOS_NOMBRES),
      'marcas':tabla("SELECT DISTINCT marca_std FROM v_ultimo_precio WHERE comercio IN (?,?,?) AND marca_std IS NOT NULL ORDER BY 1",COMERCIOS_NOMBRES,ruta).marca_std.tolist(),
      'subcategorias':tabla("SELECT DISTINCT subcategoria_std FROM v_ultimo_precio WHERE comercio IN (?,?,?) AND subcategoria_std IS NOT NULL ORDER BY 1",COMERCIOS_NOMBRES,ruta).subcategoria_std.tolist(),
      'corridas':tabla('''SELECT e.corrida_id,MIN(e.inicio) AS inicio,
       CASE WHEN COUNT(DISTINCT e.comercio_id)=3 AND MIN(e.estado='completa')=1 THEN 'completa' ELSE 'parcial o fallida' END AS estado
       FROM ejecuciones e JOIN comercios c USING(comercio_id) WHERE c.nombre IN (?,?,?)
       GROUP BY e.corrida_id ORDER BY e.corrida_id DESC''',COMERCIOS_NOMBRES,ruta),
      'productos':tabla('''SELECT DISTINCT producto_id,producto_nombre FROM v_comparables
        WHERE comercio IN (?,?,?) ORDER BY producto_nombre''',COMERCIOS_NOMBRES,ruta),
      'maximo':float(tabla('SELECT COALESCE(MAX(precio),1) AS p FROM v_ultimo_precio WHERE comercio IN (?,?,?)',COMERCIOS_NOMBRES,ruta).iloc[0].p)}


def condicion(f):
    clausulas=[];params=[]
    tiendas=f.get('comercios',COMERCIOS_NOMBRES)
    if not tiendas:clausulas.append('0')
    else:
        if not set(tiendas)<=set(COMERCIOS_NOMBRES):raise ValueError('Comercio desconocido')
        clausulas.append('comercio IN ('+','.join('?' for _ in tiendas)+')');params.extend(tiendas)
    for clave,col in [('marca','marca_std'),('subcategoria','subcategoria_std'),('corrida','corrida_id')]:
        if f.get(clave):clausulas.append(col+'=?');params.append(f[clave])
    if f.get('desde'):clausulas.append('substr(fecha_hora,1,10)>=?');params.append(str(f['desde']))
    if f.get('hasta'):clausulas.append('substr(fecha_hora,1,10)<=?');params.append(str(f['hasta']))
    if f.get('promociones'):clausulas.append('promocion=1')
    if f.get('comparables'):clausulas.append('comparable=1 AND EXISTS(SELECT 1 FROM cohortes_comparables h WHERE h.corrida_id=v.corrida_id AND h.producto_id=v.producto_id)')
    minimo=float(f.get('minimo',0));maximo=float(f.get('maximo',1e12))
    if not all(map(math.isfinite,[minimo,maximo])) or minimo<0 or maximo<minimo:raise ValueError('Rango de precios inválido')
    clausulas.append('precio BETWEEN ? AND ?');params.extend([minimo,maximo])
    if f.get('busqueda'):
        for palabra in texto_busqueda(f['busqueda']).split():
            clausulas.append("(lower(producto_nombre) LIKE lower(?) ESCAPE '\\' OR lower(texto_capturado) LIKE lower(?) ESCAPE '\\')")
            p='%'+palabra.replace('\\','\\\\').replace('%','\\%').replace('_','\\_')+'%';params.extend([p,p])
    return ' AND '.join(clausulas),params


def filtrados(f,ruta=DB_PATH):
    where,params=condicion(f)
    return tabla('SELECT * FROM v_catalogo v WHERE '+where+' ORDER BY comercio,producto_nombre,fecha_hora DESC',params,ruta)


def indicadores(f,ruta=DB_PATH):
    where,params=condicion(f)
    return tabla('''WITH x AS (SELECT * FROM v_catalogo v WHERE '''+where+'''),
    orden AS (SELECT precio,ROW_NUMBER() OVER(ORDER BY precio) AS rn,COUNT(*) OVER() AS n FROM x),
    ahorro AS (SELECT producto_id,MAX(precio)-MIN(precio) AS ahorro FROM x WHERE comparable=1 AND disponibilidad='disponible'
      GROUP BY corrida_id,producto_id HAVING COUNT(DISTINCT comercio)=3)
    SELECT COUNT(DISTINCT anuncio_id) AS productos,COUNT(*) AS observaciones,COUNT(DISTINCT comercio) AS comercios,
    100.0*AVG(promocion) AS promociones_pct,MAX(fecha_hora) AS ultima_consulta,
    (SELECT AVG(precio) FROM orden WHERE rn IN ((n+1)/2,(n+2)/2)) AS mediana_cop,
    (SELECT MAX(ahorro) FROM ahorro) AS ahorro_maximo_cop FROM x''',params,ruta).iloc[0].to_dict()


def oferta(f,ruta=DB_PATH):
    where,params=condicion(f)
    return tabla('SELECT comercio,COUNT(DISTINCT anuncio_id) AS productos,COUNT(*) AS observaciones,100.0*AVG(promocion) AS promociones_pct FROM v_catalogo v WHERE '+where+' GROUP BY comercio',params,ruta)


def estados(corrida,ruta=DB_PATH):
    return tabla('SELECT c.nombre AS comercio,e.inicio,e.estado,e.n_registros,e.notas FROM ejecuciones e JOIN comercios c USING(comercio_id) WHERE corrida_id=? AND c.nombre IN (?,?,?)',[corrida,*COMERCIOS_NOMBRES],ruta)


def evolucion(producto,tiendas=COMERCIOS_NOMBRES,ruta=DB_PATH):
    if not tiendas:return pd.DataFrame()
    return tabla('SELECT comercio,fecha_hora,precio,disponibilidad,corrida_id FROM v_comparables WHERE producto_id=? AND comercio IN ('+','.join('?' for _ in tiendas)+') ORDER BY fecha_hora',[int(producto),*tiendas],ruta)


def precios_unidad(f,familia,unidad,ruta=DB_PATH):
    where,params=condicion(f)
    return tabla('SELECT comercio,producto_nombre,contenido_total,unidad,precio,precio_por_unidad,disponibilidad FROM v_comparables v WHERE '+where+' AND familia=? AND unidad=? ORDER BY precio_por_unidad',params+[familia,unidad],ruta)


def familias(ruta=DB_PATH):
    return tabla('SELECT DISTINCT familia,unidad FROM v_comparables WHERE familia IS NOT NULL ORDER BY familia,unidad',ruta=ruta)


def ahorros(f,ruta=DB_PATH):
    where,params=condicion(f)
    return tabla('''WITH x AS (SELECT * FROM v_comparables v WHERE '''+where+''' AND disponibilidad='disponible'),
    t AS (SELECT corrida_id,producto_id,producto_nombre,MIN(precio) AS minimo,MAX(precio) AS maximo,
      AVG(precio) AS promedio,MAX(precio)-MIN(precio) AS ahorro_cop,
      100.0*(MAX(precio)-MIN(precio))/MAX(precio) AS ahorro_pct FROM x GROUP BY corrida_id,producto_id
      HAVING COUNT(DISTINCT comercio)=3)
    SELECT t.*, (SELECT group_concat(comercio,' / ') FROM x WHERE x.producto_id=t.producto_id
      AND x.corrida_id=t.corrida_id AND x.precio=t.minimo) AS menor_precio_en FROM t ORDER BY ahorro_pct DESC''',params,ruta)


def cambios(antes,despues,umbral=10,ruta=DB_PATH):
    # UNION de claves incluye nuevos y ausentes, sin suponer que los ausentes están agotados.
    sql='''WITH a AS (SELECT * FROM v_catalogo WHERE corrida_id=? AND comercio IN (?,?,?)),
    b AS (SELECT * FROM v_catalogo WHERE corrida_id=? AND comercio IN (?,?,?)),
    claves AS (SELECT anuncio_id FROM a UNION SELECT anuncio_id FROM b)
    SELECT COALESCE(b.comercio,a.comercio) AS comercio,COALESCE(b.producto_nombre,a.producto_nombre) AS producto,
      k.anuncio_id,a.precio AS precio_anterior,b.precio AS precio_actual,
      b.precio-a.precio AS cambio_cop,100.0*(b.precio-a.precio)/NULLIF(a.precio,0) AS cambio_pct,
      CASE WHEN a.anuncio_id IS NULL THEN 'Nuevo' WHEN b.anuncio_id IS NULL THEN 'No observado'
        WHEN b.precio>a.precio THEN 'Subió' WHEN b.precio<a.precio THEN 'Bajó' ELSE 'Sin cambio' END AS cambio,
      CASE WHEN ABS(100.0*(b.precio-a.precio)/NULLIF(a.precio,0))>=? THEN 1 ELSE 0 END AS variacion_grande,
      COALESCE(b.disponibilidad,'no observado') AS disponibilidad
    FROM claves k LEFT JOIN a USING(anuncio_id) LEFT JOIN b USING(anuncio_id)'''
    return tabla("SELECT r.*,SUM(cambio='Subió') OVER() AS n_subio,SUM(cambio='Bajó') OVER() AS n_bajo,"
      "SUM(cambio='Nuevo') OVER() AS n_nuevo,SUM(cambio='No observado') OVER() AS n_ausente FROM ("+sql+") r ORDER BY ABS(cambio_pct) DESC",
      [antes,*COMERCIOS_NOMBRES,despues,*COMERCIOS_NOMBRES,float(umbral)],ruta)


def cambios_ultima(corrida,ruta=DB_PATH):
    return tabla('''SELECT comercio,COUNT(*) AS cambios FROM v_cambios_precio WHERE corrida_id=?
      AND comercio IN (?,?,?) AND cambio_cop!=0 GROUP BY comercio''',[corrida,*COMERCIOS_NOMBRES],ruta)


def canasta(corrida,cantidades,ruta=DB_PATH):
    if not cantidades:raise ValueError('Seleccione al menos una presentación')
    for pid,q in cantidades.items():
        if not isinstance(pid,int) or not isinstance(q,int) or isinstance(q,bool) or not 1<=q<=100:raise ValueError('Cantidades enteras entre 1 y 100')
    # JSON se pasa como parámetro; nunca se interpolan productos ni cantidades.
    cesta=json.dumps([{'pid':pid,'cantidad':q} for pid,q in cantidades.items()])
    cte='''WITH cesta AS (SELECT json_extract(value,'$.pid') AS pid,json_extract(value,'$.cantidad') AS cantidad FROM json_each(?)),
    precios AS (SELECT * FROM v_comparables WHERE corrida_id=? AND disponibilidad='disponible' AND comercio IN (?,?,?)),
    tiendas AS (SELECT nombre AS comercio FROM comercios WHERE nombre IN (?,?,?)),
    detalle AS (SELECT t.comercio,s.pid,s.cantidad,MIN(p.precio) AS precio FROM tiendas t CROSS JOIN cesta s
      LEFT JOIN precios p ON p.comercio=t.comercio AND p.producto_id=s.pid GROUP BY t.comercio,s.pid),
    minimos AS (SELECT s.pid,s.cantidad,MIN(p.precio) AS precio FROM cesta s LEFT JOIN precios p ON p.producto_id=s.pid GROUP BY s.pid)
    '''
    params=[cesta,corrida,*COMERCIOS_NOMBRES,*COMERCIOS_NOMBRES]
    totales=tabla(cte+'''SELECT comercio,COUNT(*)-COUNT(precio) AS faltantes,
       CASE WHEN COUNT(*)=COUNT(precio) THEN SUM(cantidad*precio) END AS total_cop,
       (SELECT CASE WHEN COUNT(*)=COUNT(precio) THEN SUM(cantidad*precio) END FROM minimos) AS minimo_combinado_cop
       FROM detalle GROUP BY comercio ORDER BY total_cop IS NULL,total_cop''',params,ruta)
    detalle=tabla(cte+'''SELECT d.*,p.nombre_std AS producto FROM detalle d LEFT JOIN productos p ON p.producto_id=d.pid ORDER BY producto,comercio''',params,ruta)
    totales['ahorro_combinado_cop']=totales.total_cop-totales.minimo_combinado_cop
    return totales,detalle


def resumen_actualizacion(con,corrida,slug):
    anterior=con.execute('''SELECT MAX(corrida_id) FROM ejecuciones e JOIN comercios c USING(comercio_id)
     WHERE c.slug=? AND corrida_id<? AND estado='completa' ''',(slug,corrida)).fetchone()[0]
    filas=con.execute('''WITH a AS (SELECT o.anuncio_id,o.precio FROM observaciones o JOIN ejecuciones e USING(ejecucion_id)
      JOIN comercios c USING(comercio_id) WHERE e.corrida_id=? AND c.slug=?),
    b AS (SELECT o.anuncio_id,o.precio FROM observaciones o JOIN ejecuciones e USING(ejecucion_id)
      JOIN comercios c USING(comercio_id) WHERE e.corrida_id=? AND c.slug=?)
    SELECT (SELECT COUNT(*) FROM b WHERE NOT EXISTS(SELECT 1 FROM a WHERE a.anuncio_id=b.anuncio_id)),
      (SELECT COUNT(*) FROM a JOIN b USING(anuncio_id) WHERE a.precio!=b.precio),
      (SELECT COUNT(*) FROM a WHERE NOT EXISTS(SELECT 1 FROM b WHERE b.anuncio_id=a.anuncio_id))''',(anterior,slug,corrida,slug)).fetchone()
    return dict(productos_nuevos=filas[0],cambios_precio=filas[1],no_observados=filas[2])


def control_historial(ruta=DB_PATH):
    return tabla('''SELECT e.corrida_id,substr(MIN(o.fecha_hora),1,10) AS fecha,
      COUNT(DISTINCT v.producto_id) AS presentaciones,COUNT(DISTINCT v.anuncio_id) AS observaciones_comparables
    FROM ejecuciones e JOIN comercios c USING(comercio_id) JOIN observaciones o USING(ejecucion_id)
    LEFT JOIN v_comparables v ON v.ejecucion_id=e.ejecucion_id AND v.anuncio_id=o.anuncio_id
    WHERE c.nombre IN (?,?,?) GROUP BY e.corrida_id
    HAVING COUNT(DISTINCT e.comercio_id)=3 AND MIN(e.estado='completa')=1
      AND COUNT(DISTINCT v.anuncio_id)>=24 ORDER BY e.corrida_id''',COMERCIOS_NOMBRES,ruta)
