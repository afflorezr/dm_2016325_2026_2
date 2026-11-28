"""Única capa SQL de Taller 2. Conexiones breves, filtros parametrizados."""
from contextlib import contextmanager
from pathlib import Path
import hashlib
import json
import os
import sqlite3
from identidad import normalizar_marca
from datetime import date
from legado.scraper import SCHEMA, SOURCES, load_matches, now
from validacion import validar_fila, validar_busqueda, precio_numerico

ROOT = Path(__file__).resolve().parent
DB = Path(os.environ.get("APP_DB", ROOT / "comparador_precios.sqlite"))


@contextmanager
def conexion(path=None):
    con = sqlite3.connect(path or DB, timeout=30)
    con.row_factory = sqlite3.Row
    con.create_function("normalizar_marca",1,normalizar_marca,deterministic=True)
    con.execute("PRAGMA foreign_keys=ON")
    try:
        yield con
        con.commit()
    except Exception:
        con.rollback()
        raise
    finally:
        con.close()


def consultar(sql, params=(), path=None):
    with conexion(path) as con:
        return [dict(r) for r in con.execute(sql, params)]


def inicializar(path=None):
    with conexion(path) as con:
        con.executescript(SCHEMA)
        for key, s in SOURCES.items():
            con.execute("INSERT OR IGNORE INTO comercios VALUES(?,?,?)", (key,s['nombre'],s['host']))
        for p in load_matches():
            con.execute("INSERT OR IGNORE INTO productos VALUES(?,?,?,?,?,?,?,?,?,?,?)", tuple(p[k] for k in
                ('id','nombre','marca','variante','presentacion','contenido_total','unidad','unidades_empaque','grupo_formulacion','ean','evidencia')))
        cols = {r[1] for r in con.execute('PRAGMA table_info(observaciones)')}
        for name, definition in [('descartada','INTEGER NOT NULL DEFAULT 0'),('disponibilidad',"TEXT NOT NULL DEFAULT 'desconocida'")]:
            if name not in cols:
                con.execute(f'ALTER TABLE observaciones ADD COLUMN {name} {definition}')
        con.executescript('''
        CREATE TABLE IF NOT EXISTS migraciones(version TEXT PRIMARY KEY,fecha TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS correcciones(id INTEGER PRIMARY KEY, fecha TEXT NOT NULL,
          observacion_id INTEGER REFERENCES observaciones(id), campo TEXT NOT NULL,
          valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS rechazos(id INTEGER PRIMARY KEY,fecha TEXT NOT NULL,
          ejecucion TEXT NOT NULL,comercio TEXT NOT NULL,sku TEXT,motivos TEXT NOT NULL,
          datos_originales TEXT NOT NULL,huella TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS actualizaciones(id INTEGER PRIMARY KEY,fecha TEXT NOT NULL,
          ejecucion TEXT NOT NULL,comercio TEXT NOT NULL,modo TEXT NOT NULL,estado TEXT NOT NULL,
          recolectados INTEGER NOT NULL,insertados INTEGER NOT NULL,rechazados INTEGER NOT NULL,error TEXT);
        CREATE INDEX IF NOT EXISTS idx_historial ON observaciones(comercio,sku,fecha_hora);
        CREATE INDEX IF NOT EXISTS idx_filtros ON observaciones(ejecucion,incluido,descartada,marca,subcategoria);
        CREATE VIEW IF NOT EXISTS v_catalogo AS
          SELECT o.*,c.nombre comercio_nombre,p.nombre producto,p.presentacion,
          p.grupo_formulacion,CASE WHEN o.contenido_total>0 THEN o.precio/o.contenido_total END precio_unitario
          FROM observaciones o JOIN comercios c ON c.id=o.comercio
          LEFT JOIN productos p ON p.id=o.producto_comun
          WHERE o.incluido=1 AND o.descartada=0 AND o.precio>0;
        CREATE VIEW IF NOT EXISTS v_comparables AS
          SELECT * FROM v_catalogo WHERE comparable=1 AND disponibilidad='disponible';
        CREATE VIEW IF NOT EXISTS v_ultimo_precio AS
          SELECT * FROM (SELECT v.*,ROW_NUMBER() OVER(PARTITION BY comercio,sku ORDER BY fecha_hora DESC,id DESC) posicion
          FROM v_catalogo v) WHERE posicion=1;
        CREATE VIEW IF NOT EXISTS v_cambios_precio AS
          SELECT *,precio-precio_anterior cambio_cop,
          100.0*(precio-precio_anterior)/precio_anterior cambio_pct FROM
          (SELECT v.*,LAG(precio) OVER(PARTITION BY comercio,sku ORDER BY fecha_hora,id) precio_anterior
          FROM v_catalogo v);
        ''')
        if not con.execute("SELECT 1 FROM migraciones WHERE version='t2-1'").fetchone():
            for r in con.execute('SELECT * FROM observaciones').fetchall():
                errores = validar_fila(dict(r))
                if errores:
                    con.execute('UPDATE observaciones SET descartada=1 WHERE id=?',(r['id'],))
                    con.execute('INSERT INTO correcciones(fecha,observacion_id,campo,valor_anterior,valor_nuevo,motivo) VALUES(?,?,?,?,?,?)',
                        (now(),r['id'],'descartada','0','1','Validación histórica: '+'; '.join(errores)))
                # El legado no conserva si IsAvailable faltaba: los ceros no prueban agotamiento.
                estado = 'disponible' if r['disponible']==1 else 'desconocida'
                con.execute('UPDATE observaciones SET disponibilidad=? WHERE id=?',(estado,r['id']))
            con.execute("INSERT INTO migraciones VALUES('t2-1',?)",(now(),))


def guardar(rows, manifest, modo='online', path=None):
    """Una transacción por comercio; validación anterior a cada inserción, sin borrar historia."""
    run, store = manifest['ejecucion'], manifest['comercio']
    nuevos = rechazados = 0
    expected={p['id'] for p in load_matches()}
    matched={r.get('producto_comun') for r in rows if not validar_fila(r) and r.get('comparable')}
    estado=manifest['estado'] if matched>=expected else 'parcial'
    with conexion(path) as con:
        con.execute('INSERT OR IGNORE INTO ejecuciones VALUES(?,?,?,?,?,?,?)',
            (run,store,manifest['inicio'],manifest.get('fin'),estado,len(rows),sum(r['incluido'] for r in rows)))
        for c in manifest.get('categorias',[]):
            con.execute('INSERT OR IGNORE INTO cobertura VALUES(?,?,?,?,?,?,?)',
                (run,store,c['categoria'],c.get('esperados'),c.get('obtenidos'),c.get('estado'),c.get('error')))
        seen = set()
        columns = {r[1] for r in con.execute('PRAGMA table_info(observaciones)')} - {'id'}
        for row in rows:
            errores = validar_fila(row)
            key = (row['comercio'],row['sku'])
            if key in seen:
                errores.append('Duplicado dentro de la respuesta procesada')
            seen.add(key)
            if errores:
                payload = json.dumps(row,ensure_ascii=False,sort_keys=True)
                huella = hashlib.sha256((payload+json.dumps(errores)).encode()).hexdigest()
                con.execute('INSERT OR IGNORE INTO rechazos(fecha,ejecucion,comercio,sku,motivos,datos_originales,huella) VALUES(?,?,?,?,?,?,?)',
                    (now(),run,store,row['sku'],'; '.join(errores),payload,huella))
                rechazados += 1
                continue
            if not set(row) <= columns:
                raise ValueError('Columnas no admitidas')
            row={**row,'precio':precio_numerico(row['precio'])}
            keys = list(row)
            nuevos += con.execute(f"INSERT OR IGNORE INTO observaciones({','.join(keys)}) VALUES({','.join('?' for _ in keys)})",tuple(row[k] for k in keys)).rowcount
        con.execute('INSERT INTO actualizaciones(fecha,ejecucion,comercio,modo,estado,recolectados,insertados,rechazados,error) VALUES(?,?,?,?,?,?,?,?,?)',
            (now(),run,store,modo,estado,len(rows),nuevos,rechazados,None if matched>=expected else 'Faltan comparables: '+', '.join(sorted(expected-matched))))
    return dict(comercio=store,recolectados=len(rows),insertados=nuevos,rechazados=rechazados,estado=estado)


def registrar_error(run,store,modo,error,path=None):
    with conexion(path) as con:
        con.execute('INSERT OR IGNORE INTO ejecuciones VALUES(?,?,?,?,?,?,?)',(run,store,now(),now(),'fallida',0,0))
        con.execute('INSERT INTO actualizaciones(fecha,ejecucion,comercio,modo,estado,recolectados,insertados,rechazados,error) VALUES(?,?,?,?,?,?,?,?,?)',
            (now(),run,store,modo,'fallida',0,0,0,str(error)))


def ejecuciones(path=None):
    return consultar('''SELECT e.id,MIN(e.inicio) fecha,COUNT(*) comercios,
      SUM(e.estado='completa') completos,SUM(e.registros) recolectados,
      (SELECT COUNT(*) FROM v_comparables v WHERE v.ejecucion=e.id) correspondencias
      FROM ejecuciones e GROUP BY e.id ORDER BY fecha DESC''',path=path)


def opciones(path=None):
    return {key:consultar(query,path=path) for key,query in {
      'comercios':'SELECT id,nombre FROM comercios ORDER BY nombre',
      'marcas':'SELECT DISTINCT normalizar_marca(marca) marca FROM v_catalogo WHERE marca IS NOT NULL ORDER BY marca',
      'subcategorias':'SELECT DISTINCT subcategoria FROM v_catalogo ORDER BY subcategoria',
      'productos':'SELECT id,nombre,marca,presentacion,evidencia,ean FROM productos ORDER BY nombre'}.items()}


def filtro(f, alias=''):
    validar_rangos(f)
    prefix = alias+'.' if alias else ''
    clauses,params=[],[]
    for field in ('ejecucion','producto_comun'):
        if f.get(field):
            clauses.append(prefix+field+'=?');params.append(f[field])
    for field in ('comercio','marca','subcategoria','productos','disponibilidad'):
        values=f.get(field)
        if values is not None:
            if not values: clauses.append('0');continue
            column=prefix+('producto_comun' if field=='productos' else field)
            if field=='marca':
                column='normalizar_marca('+column+')'
                values=[normalizar_marca(v) for v in values]
            clauses.append(column+' IN ('+','.join('?' for _ in values)+')');params.extend(values)
    for field,op in [('min_precio','>='),('max_precio','<=')]:
        if f.get(field) is not None:
            clauses.append(prefix+'precio'+op+'?');params.append(float(f[field]))
    for field,op in [('desde','>='),('hasta','<=')]:
        if f.get(field):
            clauses.append('substr('+prefix+'fecha_hora,1,10)'+op+'?');params.append(str(f[field]))
    if f.get('promocion'): clauses.append(prefix+'promocion=1')
    if f.get('comparable'): clauses.append(prefix+'comparable=1')
    if f.get('busqueda'):
        text=validar_busqueda(f['busqueda']).replace('\\','\\\\').replace('%','\\%').replace('_','\\_')
        clauses.append(f"({prefix}nombre_limpio LIKE ? ESCAPE '\\' OR {prefix}texto_original LIKE ? ESCAPE '\\')")
        params.extend(['%'+text+'%']*2)
    return (' WHERE '+' AND '.join(clauses)) if clauses else '',params


def catalogo(f,path=None):
    where,p=filtro(f)
    return consultar('SELECT comercio_nombre comercio,nombre_original nombre,marca,subcategoria,COALESCE(presentacion,presentacion_original) presentacion,precio,contenido_total,unidad,precio_unitario,promocion,disponibilidad,fecha_hora,url,sku,producto_comun,ejecucion,archivo_raw,url_extraccion,incidencia,texto_original FROM v_catalogo'+where+' ORDER BY comercio_nombre,nombre_original',p,path)


def indicadores(f,path=None):
    where,p=filtro(f)
    return consultar('''WITH datos AS (SELECT * FROM v_catalogo'''+where+'''),
      orden AS (SELECT precio,ROW_NUMBER() OVER(ORDER BY precio) rn,COUNT(*) OVER() n FROM datos),
      ahorros AS (SELECT producto_comun,MAX(precio)-MIN(precio) ahorro FROM datos
        WHERE comparable=1 AND disponibilidad='disponible' GROUP BY ejecucion,producto_comun HAVING COUNT(DISTINCT comercio)>=2)
      SELECT (SELECT COUNT(*) FROM datos) registros,
        (SELECT COUNT(DISTINCT comercio) FROM datos) comercios,
        (SELECT 100.0*AVG(promocion) FROM datos WHERE promocion IS NOT NULL) porcentaje_promocion,
        (SELECT AVG(precio) FROM orden WHERE rn IN ((n+1)/2,(n+2)/2)) mediana,
        (SELECT MAX(ahorro) FROM ahorros) ahorro_maximo,
        (SELECT MAX(fecha_hora) FROM datos) ultima_fecha,
        (SELECT COUNT(*) FROM v_cambios_precio'''+where+(' AND ' if where else ' WHERE ')+'''precio_anterior IS NOT NULL AND cambio_cop!=0) cambios''',p+p,path)[0]


def historial(producto,stores,desde=None,hasta=None,path=None):
    where,p=filtro({'producto_comun':producto,'comercio':stores,'desde':desde,'hasta':hasta})
    return consultar('SELECT comercio_nombre,producto,marca,presentacion,ejecucion,fecha_hora,precio,precio_unitario,unidad,disponibilidad FROM v_catalogo'+where+' ORDER BY fecha_hora',p,path)


def ahorros(f,path=None):
    where,p=filtro(f)
    return consultar('''WITH elegibles AS (SELECT * FROM v_comparables'''+where+'''),
      extremos AS (SELECT ejecucion,producto_comun,MAX(producto) producto,MAX(marca) marca,MAX(presentacion) presentacion,MAX(fecha_hora) fecha_hora,MIN(precio) minimo,MAX(precio) maximo,
      COUNT(DISTINCT comercio) cobertura FROM elegibles GROUP BY ejecucion,producto_comun)
      SELECT x.*,maximo-minimo ahorro,100.0*(maximo-minimo)/maximo ahorro_pct,
      (SELECT GROUP_CONCAT(e.comercio_nombre,', ') FROM elegibles e WHERE e.ejecucion=x.ejecucion AND e.producto_comun=x.producto_comun AND e.precio=x.minimo) ganadores
      FROM extremos x WHERE cobertura>=2 ORDER BY ahorro DESC''',p,path)


def cambios(antes,despues,umbral=0,path=None):
    return consultar('''WITH a AS (SELECT * FROM v_catalogo WHERE ejecucion=?),
      b AS (SELECT * FROM v_catalogo WHERE ejecucion=?),
      claves AS (SELECT comercio,sku FROM a UNION SELECT comercio,sku FROM b)
      SELECT k.comercio,k.sku,COALESCE(b.nombre_original,a.nombre_original) nombre,
      a.precio precio_antes,b.precio precio_despues,b.precio-a.precio cambio_cop,
      100.0*(b.precio-a.precio)/a.precio cambio_pct,
      CASE WHEN a.id IS NULL THEN 'nuevo' WHEN b.id IS NULL THEN 'no observado'
        WHEN a.precio=b.precio THEN 'sin cambio' ELSE 'cambió' END estado
      FROM claves k LEFT JOIN a ON a.comercio=k.comercio AND a.sku=k.sku
      LEFT JOIN b ON b.comercio=k.comercio AND b.sku=k.sku
      WHERE a.id IS NULL OR b.id IS NULL OR ABS(100.0*(b.precio-a.precio)/a.precio)>=?
      ORDER BY ABS(b.precio-a.precio) DESC''',(antes,despues,float(umbral)),path)


def canasta(run,cantidades,path=None):
    if not cantidades: return {'tiendas':[],'division':[],'total_dividido':None}
    if any(not isinstance(q,int) or not 1<=q<=100 for q in cantidades.values()):
        raise ValueError('Las cantidades deben ser enteros entre 1 y 100')
    values=','.join('(?,?)' for _ in cantidades)
    params=[v for pair in cantidades.items() for v in pair]
    base=f'''WITH pedido(producto_comun,cantidad) AS (VALUES {values}),
      ofertas AS (SELECT * FROM v_comparables WHERE ejecucion=?) '''
    tiendas=consultar(base+'''SELECT c.id comercio,c.nombre,
      COUNT(o.id) cubiertos,COUNT(*) requeridos,
      CASE WHEN COUNT(o.id)=COUNT(*) THEN SUM(o.precio*p.cantidad) END total,
      GROUP_CONCAT(CASE WHEN o.id IS NULL THEN pr.nombre END,'; ') faltantes
      FROM comercios c CROSS JOIN pedido p JOIN productos pr ON pr.id=p.producto_comun
      LEFT JOIN ofertas o ON o.comercio=c.id AND o.producto_comun=p.producto_comun
      GROUP BY c.id ORDER BY total IS NULL,total''',params+[run],path)
    division=consultar(base+'''SELECT p.producto_comun,pr.nombre,p.cantidad,
      MIN(o.precio) precio_minimo,MIN(o.precio)*p.cantidad subtotal,
      (SELECT GROUP_CONCAT(o2.comercio_nombre,', ') FROM ofertas o2 WHERE o2.producto_comun=p.producto_comun
        AND o2.precio=(SELECT MIN(o3.precio) FROM ofertas o3 WHERE o3.producto_comun=p.producto_comun)) tiendas
      FROM pedido p JOIN productos pr ON pr.id=p.producto_comun
      LEFT JOIN ofertas o ON o.producto_comun=p.producto_comun GROUP BY p.producto_comun''',params+[run],path)
    total=consultar(base+'''SELECT CASE WHEN COUNT(precio)=COUNT(*) THEN SUM(precio*cantidad) END total
      FROM (SELECT p.producto_comun,p.cantidad,MIN(o.precio) precio FROM pedido p
      LEFT JOIN ofertas o ON o.producto_comun=p.producto_comun GROUP BY p.producto_comun)''',params+[run],path)[0]['total']
    return {'tiendas':tiendas,'division':division,'total_dividido':total}


def resumen_cambios(antes,despues,path=None):
    return consultar('''WITH a AS (SELECT * FROM v_catalogo WHERE ejecucion=?),
      b AS (SELECT * FROM v_catalogo WHERE ejecucion=?),
      claves AS (SELECT comercio,sku FROM a UNION SELECT comercio,sku FROM b)
      SELECT k.comercio,SUM(a.id IS NULL) nuevos,SUM(b.id IS NULL) no_observados,
      SUM(a.precio!=b.precio) cambios_precio FROM claves k
      LEFT JOIN a ON a.comercio=k.comercio AND a.sku=k.sku
      LEFT JOIN b ON b.comercio=k.comercio AND b.sku=k.sku GROUP BY k.comercio''',(antes,despues),path)


def calidad(path=None):
    return {key:consultar(sql,path=path) for key,sql in {
      'integridad':'PRAGMA integrity_check',
      'cobertura':'SELECT * FROM cobertura ORDER BY ejecucion DESC,comercio,categoria',
      'rechazos':'SELECT ejecucion,comercio,motivos,COUNT(*) cantidad FROM rechazos GROUP BY 1,2,3',
      'correcciones':'SELECT * FROM correcciones ORDER BY id',
      'actualizaciones':'SELECT * FROM actualizaciones ORDER BY id DESC LIMIT 60',
      'totales':'SELECT COUNT(*) registros,SUM(descartada) descartados,COUNT(DISTINCT ejecucion) ejecuciones FROM observaciones',
      'ultimos':'SELECT comercio,COUNT(*) productos,MAX(fecha_hora) fecha FROM v_ultimo_precio GROUP BY comercio'
      }.items()}


def esquema(path=None):
    with conexion(path) as con:
        return {r[0]:[dict(x) for x in con.execute('PRAGMA table_info("'+r[0]+'")')]
            for r in con.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'").fetchall()}


def referencias_raw(path=None):
    return consultar('SELECT DISTINCT archivo_raw FROM observaciones',path=path)


def cargar_legado(rows,manifest,path):
    """Reconstrucción histórica exacta, antes de aplicar la migración auditada."""
    from legado.scraper import insert_rows
    insert_rows(path,rows,manifest)


def huella_observaciones(path=None):
    with conexion(path) as con:
        cols=[r[1] for r in con.execute('PRAGMA table_info(observaciones)') if r[1]!='id']
        rows=[dict(r) for r in con.execute('SELECT '+','.join(cols)+' FROM observaciones ORDER BY ejecucion,comercio,sku')]
    return hashlib.sha256(json.dumps(rows,ensure_ascii=False,sort_keys=True).encode()).hexdigest()


def validar_rangos(f):
    lo,hi=f.get('min_precio'),f.get('max_precio')
    if lo is not None and float(lo)<0 or hi is not None and float(hi)<0:
        raise ValueError('Los precios no pueden ser negativos')
    if lo is not None and hi is not None and float(lo)>float(hi):
        raise ValueError('El precio mínimo no puede superar al máximo')
    start,end=f.get('desde'),f.get('hasta')
    if start:date.fromisoformat(str(start))
    if end:date.fromisoformat(str(end))
    if start and end and str(start)>str(end):
        raise ValueError('La fecha inicial no puede ser posterior a la final')
