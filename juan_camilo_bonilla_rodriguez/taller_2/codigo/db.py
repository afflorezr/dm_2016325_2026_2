"""Persistencia SQLite, transacciones y correspondencia sin sobrescribir precios."""
import csv
import json
import sqlite3
from pathlib import Path
import pandas as pd
from .config import DB_PATH, COMERCIOS, REGISTRO_COMERCIOS, ahora_iso, ROOT, DATOS_DIR

EXTRAS = '''
CREATE TABLE IF NOT EXISTS cohortes_comparables(
 corrida_id TEXT NOT NULL,producto_id INTEGER NOT NULL REFERENCES productos,
 PRIMARY KEY(corrida_id,producto_id));
CREATE TABLE IF NOT EXISTS familias_unidad(
 producto_id INTEGER PRIMARY KEY REFERENCES productos,familia TEXT NOT NULL,
 justificacion TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS correcciones(
 correccion_id INTEGER PRIMARY KEY, fecha TEXT NOT NULL, tabla TEXT NOT NULL,
 registro_id INTEGER NOT NULL, campo TEXT NOT NULL, valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS rechazos(
 rechazo_id INTEGER PRIMARY KEY, ejecucion_id INTEGER REFERENCES ejecuciones,
 sku TEXT, motivo TEXT NOT NULL, datos_json TEXT NOT NULL, UNIQUE(ejecucion_id,sku,motivo));
CREATE UNIQUE INDEX IF NOT EXISTS idx_obs_anuncio_ejecucion ON observaciones(anuncio_id,ejecucion_id);
CREATE INDEX IF NOT EXISTS idx_obs_ejecucion ON observaciones(ejecucion_id, anuncio_id);
CREATE INDEX IF NOT EXISTS idx_obs_fecha ON observaciones(fecha_hora);
CREATE INDEX IF NOT EXISTS idx_anuncios_filtros ON anuncios(comercio_id,subcategoria_std,marca_std,comparable);
CREATE VIEW IF NOT EXISTS v_ultimo_precio AS
 SELECT v.* FROM v_observaciones v JOIN observaciones o ON o.anuncio_id=v.anuncio_id AND o.ejecucion_id=v.ejecucion_id
 WHERE NOT EXISTS(SELECT 1 FROM observaciones z WHERE z.anuncio_id=o.anuncio_id AND z.fecha_hora>o.fecha_hora);
CREATE VIEW IF NOT EXISTS v_cambios_precio AS
 SELECT *, precio - precio_anterior AS cambio_cop,
 100.0*(precio-precio_anterior)/NULLIF(precio_anterior,0) AS cambio_pct
 FROM (SELECT v.*, LAG(precio) OVER(PARTITION BY anuncio_id ORDER BY fecha_hora) AS precio_anterior FROM v_observaciones v);
CREATE VIEW IF NOT EXISTS v_promociones AS
 WITH rotulos AS (
 SELECT anuncio_id,ejecucion_id,
 CASE WHEN instr(texto_original_captura,char(10))>0
 THEN substr(texto_original_captura,1,instr(texto_original_captura,char(10))-1)
 ELSE texto_original_captura END AS titulo_capturado FROM observaciones)
 SELECT v.*,v.promocion AS descuento_verificable,
 CASE WHEN v.promocion=1 OR lower(COALESCE(r.titulo_capturado,v.titulo_original)) LIKE '%oferta%'
 OR lower(COALESCE(r.titulo_capturado,v.titulo_original)) LIKE '%gratis%'
 OR lower(COALESCE(r.titulo_capturado,v.titulo_original)) LIKE '%pague%'
 OR lower(COALESCE(r.titulo_capturado,v.titulo_original)) LIKE '%lleve%'
 THEN 1 ELSE 0 END AS promocion_anunciada
 FROM v_observaciones v JOIN rotulos r USING(anuncio_id,ejecucion_id);

'''

def conectar(db_path=DB_PATH):
    """El consumidor cierra la conexión; SQLite comprueba claves foráneas."""
    con=sqlite3.connect(db_path,timeout=30)
    con.execute('PRAGMA foreign_keys=ON')
    return con

def crear_bd(db_path=DB_PATH):
    """Crea el esquema de forma idempotente y añade disponibilidad y auditoría."""
    con=conectar(db_path)
    try:
        esquema=Path(__file__).with_name('schema.sql').read_text()
        esquema=esquema.replace('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS ').replace('CREATE VIEW ', 'CREATE VIEW IF NOT EXISTS ')
        con.executescript(esquema)
        campos={r[1] for r in con.execute('PRAGMA table_info(observaciones)')}
        if 'disponibilidad' not in campos:
            con.execute("ALTER TABLE observaciones ADD COLUMN disponibilidad TEXT NOT NULL DEFAULT 'desconocida' CHECK(disponibilidad IN('disponible','agotado','desconocida'))")
        if 'texto_original_captura' not in campos:
            con.execute('ALTER TABLE observaciones ADD COLUMN texto_original_captura TEXT')
        campos_anuncios={r[1] for r in con.execute('PRAGMA table_info(anuncios)')}
        for campo in ('ean','ficha_original_json','presentacion_original'):
            if campo not in campos_anuncios:
                con.execute(f'ALTER TABLE anuncios ADD COLUMN {campo} TEXT')
        con.executescript(EXTRAS)
        con.executescript("""DROP VIEW IF EXISTS v_comparables;
        CREATE VIEW v_comparables AS
        SELECT v.*,p.nombre_std AS producto_nombre,p.marca_std AS producto_marca
        FROM v_observaciones v JOIN productos p USING(producto_id)
        WHERE v.comparable=1 AND EXISTS(
          SELECT 1 FROM cohortes_comparables h WHERE h.corrida_id=v.corrida_id AND h.producto_id=v.producto_id);
        """)
        for slug,nombre in REGISTRO_COMERCIOS.items():
            con.execute('INSERT OR IGNORE INTO comercios(slug,nombre) VALUES(?,?)',(slug,nombre))
        con.commit()
    finally:
        con.close()

def registrar_ejecucion(conn,corrida_id,comercio_slug,inicio,n_registros,n_reportado_sitio,estado,notas):
    """Reprocesar una corrida preserva su inicio y no crea otra ejecución."""
    cid=conn.execute('SELECT comercio_id FROM comercios WHERE slug=?',(comercio_slug,)).fetchone()[0]
    previo=conn.execute('SELECT ejecucion_id,estado FROM ejecuciones WHERE corrida_id=? AND comercio_id=?',(corrida_id,cid)).fetchone()
    if previo and previo[1]!=estado:
        conn.execute('INSERT INTO correcciones(fecha,tabla,registro_id,campo,valor_anterior,valor_nuevo,motivo) VALUES(?,?,?,?,?,?,?)',
          (ahora_iso(),'ejecuciones',previo[0],'estado',previo[1],estado,'Reprocesamiento de las respuestas originales; se conserva la fecha de captura'))
    conn.execute('''INSERT INTO ejecuciones(corrida_id,comercio_id,inicio,n_registros,n_reportado_sitio,estado,notas)
    VALUES(?,?,?,?,?,?,?) ON CONFLICT(corrida_id,comercio_id) DO UPDATE SET
    n_registros=excluded.n_registros,n_reportado_sitio=excluded.n_reportado_sitio,estado=excluded.estado,notas=excluded.notas''',(corrida_id,cid,inicio,n_registros,n_reportado_sitio,estado,notas))
    return conn.execute('SELECT ejecucion_id FROM ejecuciones WHERE corrida_id=? AND comercio_id=?',(corrida_id,cid)).fetchone()[0]

def insertar_df(conn,df,ejecucion_id,comercio_slug):
    """Inserta originales y normalizados; rechazos y exclusiones quedan auditados."""
    from .validacion import validar_fila
    cid=conn.execute('SELECT comercio_id FROM comercios WHERE slug=?',(comercio_slug,)).fetchone()[0]
    conteos=dict(anuncios_nuevos=0,obs_insertadas=0,obs_duplicadas=0,descartes=0,rechazos=0)
    campos=['url','titulo_original','descripcion_original','marca_original','categoria_sitio','texto_original','nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion','ean','ficha_original_json','presentacion_original']
    for fila in df.to_dict('records'):
        r={k:None if pd.isna(v) else v for k,v in fila.items()}
        if r['excluido']:
            if not conn.execute('SELECT 1 FROM descartes WHERE ejecucion_id=? AND sku=?',(ejecucion_id,r['sku'])).fetchone():
                conn.execute('INSERT INTO descartes(ejecucion_id,comercio_id,sku,url,titulo_original,motivo) VALUES(?,?,?,?,?,?)',(ejecucion_id,cid,r['sku'],r['url'],r['titulo_original'],r['motivo_exclusion']))
            conteos['descartes']+=1
            continue
        meta=df.attrs.get('metadatos',{}).get(r['sku'],{})
        r['ean']=meta.get('ean')
        r['ficha_original_json']=json.dumps(meta.get('ficha',{}),ensure_ascii=False)
        r['presentacion_original']=' | '.join(meta.get('presentacion') or []) or None
        r['texto_original']=r['titulo_original'] + ('\n'+r['descripcion_original'] if r['descripcion_original'] else '')
        existe=conn.execute('SELECT anuncio_id FROM anuncios WHERE comercio_id=? AND sku=?',(cid,r['sku'])).fetchone()
        if existe:
            identidad=conn.execute('SELECT p.nombre_std,p.marca_std,p.subcategoria_std,p.contenido,p.unidad,p.n_unidades,p.concentracion FROM anuncios a JOIN productos p USING(producto_id) WHERE a.anuncio_id=? AND a.comparable=1',(existe[0],)).fetchone()
            if identidad:
                for campo,valor in zip(['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion'],identidad):
                    r[campo]=valor
            antiguos=conn.execute('SELECT nombre_std,marca_std,subcategoria_std,contenido,unidad,n_unidades,concentracion FROM anuncios WHERE anuncio_id=?',(existe[0],)).fetchone()
            for campo,anterior in zip(['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion'],antiguos):
                if anterior != r[campo]:
                    conn.execute('INSERT INTO correcciones(fecha,tabla,registro_id,campo,valor_anterior,valor_nuevo,motivo) VALUES(?,?,?,?,?,?,?)',(ahora_iso(),'anuncios',existe[0],campo,str(anterior),str(r[campo]),'Reprocesamiento o cambio observado de atributos; originales conservados en raw'))
        if not existe:
            conteos['anuncios_nuevos']+=1
        nombres=','.join(campos)
        marcas=','.join('?' for _ in campos)
        cambios=','.join(f'{c}=excluded.{c}' for c in campos)
        conn.execute(f'INSERT INTO anuncios(comercio_id,sku,{nombres}) VALUES(?,?,{marcas}) ON CONFLICT(comercio_id,sku) DO UPDATE SET {cambios}',(cid,r['sku'],*[r[c] for c in campos]))
        aid=conn.execute('SELECT anuncio_id FROM anuncios WHERE comercio_id=? AND sku=?',(cid,r['sku'])).fetchone()[0]
        problemas=validar_fila(r)
        if problemas:
            conn.execute('INSERT OR IGNORE INTO rechazos(ejecucion_id,sku,motivo,datos_json) VALUES(?,?,?,?)',(ejecucion_id,r['sku'],'; '.join(problemas),json.dumps(r,ensure_ascii=False)))
            conteos['rechazos']+=1
            continue
        disp=df.attrs.get('disponibilidad',{}).get(r['sku'],'desconocida')
        cur=conn.execute('''INSERT OR IGNORE INTO observaciones(anuncio_id,ejecucion_id,precio,precio_antes,promocion,fecha_hora,url,raw_ref,disponibilidad,texto_original_captura) VALUES(?,?,?,?,?,?,?,?,?,?)''',(aid,ejecucion_id,r['precio_actual'],r['precio_antes'],r['en_promocion'],r['fecha_hora_consulta'],r['url'],str(Path(r['raw_ref']).relative_to(ROOT)) if Path(r['raw_ref']).is_absolute() else r['raw_ref'],disp,r['texto_original']))
        conteos['obs_insertadas' if cur.rowcount else 'obs_duplicadas']+=1
    return conteos

def aplicar_correspondencia(conn,csv_path=DATOS_DIR/'correspondencia.csv'):
    """Aplica únicamente correspondencias verificadas; registra cambios posteriores."""
    from .correspondencia import validar_correspondencia
    errores=validar_correspondencia(conn,csv_path)
    if not errores.empty:
        raise ValueError('Correspondencia inválida: '+errores.to_string(index=False))
    tabla=pd.read_csv(csv_path,dtype={'sku':str}).astype(object)
    tabla=tabla.where(pd.notna(tabla),None)
    for r in tabla.to_dict('records'):
        attrs=[r[k] for k in ['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion']]
        anterior_producto=conn.execute('SELECT nombre_std,marca_std,subcategoria_std,contenido,unidad,n_unidades,concentracion FROM productos WHERE producto_id=?',(r['producto_id'],)).fetchone()
        if anterior_producto and tuple(attrs)!=anterior_producto:
            for campo,antes,despues in zip(['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion'],anterior_producto,attrs):
                if antes!=despues:
                    conn.execute('INSERT INTO correcciones(fecha,tabla,registro_id,campo,valor_anterior,valor_nuevo,motivo) VALUES(?,?,?,?,?,?,?)',(ahora_iso(),'productos',r['producto_id'],campo,str(antes),str(despues),'Revisión del mapeo documentado'))
            conn.execute('UPDATE productos SET nombre_std=?,marca_std=?,subcategoria_std=?,contenido=?,unidad=?,n_unidades=?,concentracion=? WHERE producto_id=?',(*attrs,r['producto_id']))
        else:
            conn.execute('INSERT OR IGNORE INTO productos VALUES(?,?,?,?,?,?,?,?)',(r['producto_id'],*attrs))
        aid, anterior=conn.execute('SELECT a.anuncio_id,a.producto_id FROM anuncios a JOIN comercios c USING(comercio_id) WHERE c.nombre=? AND a.sku=?',(r['comercio'],r['sku'])).fetchone()
        if anterior is not None and anterior != r['producto_id']:
            conn.execute('INSERT INTO correcciones(fecha,tabla,registro_id,campo,valor_anterior,valor_nuevo,motivo) VALUES(?,?,?,?,?,?,?)',(ahora_iso(),'anuncios',aid,'producto_id',str(anterior),str(r['producto_id']),'Revisión de correspondencia.csv'))
        for campo in ['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion']:
            previo=conn.execute(f'SELECT {campo} FROM anuncios WHERE anuncio_id=?',(aid,)).fetchone()[0]
            if previo != r[campo]:
                conn.execute('INSERT INTO correcciones(fecha,tabla,registro_id,campo,valor_anterior,valor_nuevo,motivo) VALUES(?,?,?,?,?,?,?)',(ahora_iso(),'anuncios',aid,campo,str(previo),str(r[campo]),'Correspondencia manual documentada: marca, presentación y kit homogéneo/heterogéneo'))
        conn.execute('UPDATE anuncios SET producto_id=?,comparable=1,nombre_std=?,marca_std=?,subcategoria_std=?,contenido=?,unidad=?,n_unidades=?,concentracion=? WHERE anuncio_id=?',(r['producto_id'],*attrs,aid))
    conn.commit()
    return {'productos':tabla.producto_id.nunique(),'anuncios':len(tabla)}


def registrar_cohorte(conn,corrida_id,csv_path):
    """Fija qué identidades se seleccionaron en cada corrida, sin cambiar las históricas."""
    d=pd.read_csv(csv_path)
    for pid in d.producto_id.unique():
        conn.execute('INSERT OR IGNORE INTO cohortes_comparables VALUES(?,?)',(corrida_id,int(pid)))
    if (DATOS_DIR/'familias_unidad.csv').exists():
        for r in pd.read_csv(DATOS_DIR/'familias_unidad.csv').to_dict('records'):
            if conn.execute('SELECT 1 FROM productos WHERE producto_id=?',(r['producto_id'],)).fetchone():
                conn.execute('INSERT OR IGNORE INTO familias_unidad VALUES(?,?,?)',(r['producto_id'],r['familia'],r['justificacion']))
    conn.commit()

def ultima_corrida(conn):
    """Última corrida de los tres comercios activos; las fuentes retiradas no la sustituyen."""
    marcadores=','.join('?' for _ in COMERCIOS)
    fila=conn.execute(f"""SELECT e.corrida_id FROM ejecuciones e JOIN comercios c USING(comercio_id)
    WHERE c.slug IN ({marcadores}) GROUP BY e.corrida_id
    HAVING COUNT(DISTINCT e.comercio_id)=? AND MIN(e.estado='completa')=1
    ORDER BY e.corrida_id DESC LIMIT 1""",[*COMERCIOS,len(COMERCIOS)]).fetchone()
    return fila[0] if fila else None
