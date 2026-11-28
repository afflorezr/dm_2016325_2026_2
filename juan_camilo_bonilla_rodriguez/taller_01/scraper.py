"""Extracción HTTP paginada y reproducción de respuestas originales sin red."""
import os
import re
import json
import time
import requests
import pandas as pd
from codigo.config import COMERCIOS, REGISTRO_COMERCIOS, RAW_DIR, DB_PATH, USER_AGENT, PAUSA_SEG, ahora_iso, nueva_corrida_id
from codigo.rawio import guardar_raw, leer_raw

COLUMNAS = ['comercio','sku','url','titulo_original','descripcion_original','marca_original','categoria_sitio','precio_actual','precio_antes','en_promocion','fecha_hora_consulta','raw_ref']
URLS_COMERCIO1 = ['https://www.locatelcolombia.com/api/catalog_system/pub/products/search/?fq=C:/5/31/', 'https://www.locatelcolombia.com/api/catalog_system/pub/products/search/?fq=C:/5/32/', 'https://www.locatelcolombia.com/api/catalog_system/pub/products/search/?fq=C:/3/21/129/']
URLS_COMERCIO2 = ['https://www.drogueriascafam.com.co/salud-y-medicamentos/equipos-medicos']
URLS_COMERCIO3 = ['https://www.larebajavirtual.com/api/catalog_system/pub/products/search/?fq=C:/6/36/', 'https://www.larebajavirtual.com/api/catalog_system/pub/products/search/?fq=C:/3/668/731/', 'https://www.larebajavirtual.com/api/catalog_system/pub/products/search/?fq=C:/9/1317/']

def _peticion(url):
    """Tres intentos como máximo; no elude bloqueos ni autenticación."""
    for intento in range(3):
        time.sleep(PAUSA_SEG * (intento + 1))
        try:
            r = requests.get(url, headers={'User-Agent': USER_AGENT}, timeout=30)
            r.raise_for_status()
            return r
        except requests.RequestException:
            if intento == 2:
                raise

def _estado(html):
    """Lee el estado de Apollo que ya viene en el HTML público de VTEX."""
    m = re.search(r'\b__STATE__\s*=\s*', html)
    if m:
        return json.JSONDecoder().raw_decode(html[m.end():])[0]
    m = re.search(r'<template[^>]*data-varname="__STATE__"[^>]*>\s*<script[^>]*>(.*?)</script>', html, re.S)
    if m:
        return json.loads(m[1])
    raise ValueError('No se encontró el estado de catálogo en el HTML')

def _productos_html(html):
    """Devuelve productos y total con oferta del vendedor principal del sitio."""
    d = _estado(html)
    busquedas = [v for k,v in d.items() if 'productSearch(' in k and isinstance(v,dict) and 'products' in v]
    if not busquedas:
        raise ValueError('Falta productSearch')
    b = busquedas[0]
    salida = []
    for ref in b['products']:
        clave = ref['id']; p = dict(d[clave]); base = '$' + clave
        # Conserva el JSON del producto; los precios de esta oferta están en COP.
        ofertas = [v for k,v in d.items() if k.startswith(base+'.items(') and k.endswith('.sellers.0.commertialOffer')]
        p['_oferta'] = ofertas[0] if ofertas else {}
        p['_items'] = [v for k,v in d.items() if k.startswith(clave+'.items(') and isinstance(v,dict) and 'itemId' in v]
        p['_ficha'] = {v['name']:v['values'].get('json',[]) for k,v in d.items() if k.startswith(clave+'.specificationGroups.') and isinstance(v,dict) and isinstance(v.get('values'),dict)}
        p['categories'] = p.get('categories',{}).get('json',[])
        salida.append(p)
    return salida, b.get('recordsFiltered')

def _fila(p, slug, origen, fecha, raw):
    """Selecciona la oferta principal; nunca agrega precios de vendedores distintos."""
    from codigo.limpieza import limpiar_precio
    if '_oferta' in p:
        oferta = p['_oferta']
    else:
        items = p.get('items') or []
        vendedores = items[0].get('sellers',[]) if items else []
        vendedor = next((v for v in vendedores if v.get('sellerDefault')), vendedores[0] if vendedores else {})
        oferta = vendedor.get('commertialOffer',{})
    precio = limpiar_precio(oferta.get('Price'))
    antes = limpiar_precio(oferta.get('ListPrice'))
    host = origen.split('/')[2]
    enlace = p.get('link') or '/' + p['linkText'] + '/p'
    if not enlace.startswith('http'):
        enlace = 'https://' + host + enlace
    fila = dict(zip(COLUMNAS, [REGISTRO_COMERCIOS[slug],str(p['productId']),enlace,p['productName'],p.get('description'),p.get('brand'),' | '.join(p.get('categories',[])),precio,antes,int(precio is not None and antes is not None and antes>precio),fecha,raw]))
    cantidad = oferta.get('AvailableQuantity')
    disponibilidad = 'desconocida' if cantidad is None else ('disponible' if cantidad > 0 else 'agotado')
    return fila, disponibilidad

def _extraer(slug, urls, raw_dir, offline, corrida_id, html=False):
    """Motor compartido con comprobación de cada página, conteos y límite de peticiones."""
    corrida_id = corrida_id or nueva_corrida_id()
    registros, disponibilidad, cobertura, metadatos = {}, {}, [], {}
    n = 0
    if offline:
        fuentes = list(leer_raw(raw_dir, slug, corrida_id))
        if not fuentes:
            raise ValueError('No hay copias crudas para la ejecución solicitada')
    else:
        fuentes = []
        if os.path.exists(os.path.join(raw_dir,slug,corrida_id)):
            raise ValueError('La corrida ya tiene respuestas: use offline o un identificador nuevo')
        for url in urls:
            vistos, total, pagina = set(), None, 0
            while pagina < 60:
                sep = '&' if '?' in url else '?'
                destino = url + sep + (f'page={pagina+1}' if html else f'_from={pagina*50}&_to={pagina*50+49}')
                r = _peticion(destino)
                if html:
                    contenido = r.text
                    productos, total = _productos_html(contenido)
                else:
                    contenido = r.json()
                    if not isinstance(contenido, list):
                        raise ValueError('El catálogo dejó de devolver una lista JSON')
                    productos = contenido
                    total_header = r.headers.get('resources', r.headers.get('content-range',''))
                    m = re.search(r'/(\d+)', total_header)
                    total = int(m[1]) if m else None
                n += 1
                ruta, ts = guardar_raw(raw_dir,slug,corrida_id,n,contenido,r.url,'html' if html else 'json')
                # Metadatos de cobertura, sin cambiar el contenido original.
                import gzip
                with gzip.open(ruta,'rt',encoding='utf-8') as f:
                    envoltorio = json.load(f)
                envoltorio.update(total_reportado=total, categoria_origen=url)
                with gzip.open(ruta,'wt',encoding='utf-8') as f:
                    json.dump(envoltorio,f,ensure_ascii=False)
                fuentes.append((ruta,envoltorio))
                ids = {str(p['productId']) for p in productos}
                nuevos = ids - vistos
                vistos |= ids
                if total is not None and len(vistos) >= total:
                    break
                if not productos:
                    if total is not None and len(vistos)<total:
                        raise ValueError(f'Categoría incompleta {url}: {len(vistos)}/{total}')
                    break
                if not nuevos:
                    raise ValueError(f'Paginación repetida {url}: {len(vistos)}/{total}')
                pagina += 1
            else:
                raise ValueError('Límite de 60 páginas alcanzado')
    por_categoria = {}
    for ruta, env in fuentes:
        if env['tipo']=='html':
            productos, total = _productos_html(env['contenido'])
        else:
            productos, total = env['contenido'], env.get('total_reportado')
        cat = env.get('categoria_origen', env['url'].split('&_from=')[0].split('?page=')[0])
        info = por_categoria.setdefault(cat, {'ids':set(), 'reportado':total})
        for p in productos:
            fila, disp = _fila(p,slug,env['url'],env['fecha_hora_consulta'],ruta)
            info['ids'].add(fila['sku'])
            if fila['sku'] in registros:
                continue
            registros[fila['sku']] = fila
            disponibilidad[fila['sku']] = disp
            items = p.get('_items',p.get('items',[]))
            if len(items)>1:
                raise ValueError('Producto multivariante: requiere adaptar extracción por SKU '+fila['sku'])
            ficha = p.get('_ficha') or {k:p[k] for k in p.get('allSpecifications',[]) if k in p}
            metadatos[fila['sku']] = {'ean':items[0].get('ean') if items else None,'ficha':ficha,
                'presentacion':p.get('Presentacionunidadmedida'), 'categorias':p.get('categories',[]),
                'descripcion_adicional':p.get('DescripcionContenido')}
    for cat, info in por_categoria.items():
        cobertura.append({'url':cat,'obtenidos':len(info['ids']),'reportado':info['reportado']})
    df = pd.DataFrame(list(registros.values()),columns=COLUMNAS)
    df.attrs['n_reportado_sitio'] = sum(x['reportado'] for x in cobertura) if all(x['reportado'] is not None for x in cobertura) else None
    df.attrs['cobertura'] = cobertura
    df.attrs['completa'] = set(por_categoria)==set(urls) and all(x['reportado'] is not None and x['obtenidos']>=x['reportado'] for x in cobertura)
    df.attrs['notas'] = json.dumps(cobertura,ensure_ascii=False) + '; total reportado suma categorías, puede incluir duplicados y exclusiones'
    df.attrs['disponibilidad'] = disponibilidad
    df.attrs['metadatos'] = metadatos
    print(f"{REGISTRO_COMERCIOS[slug]}: obtenidos {len(df)} únicos de {df.attrs['n_reportado_sitio']} reportados por el sitio")
    return df

def scrape_comercio1(raw_dir=RAW_DIR, offline=False, corrida_id=None):
    """Catálogo público Locatel, categorías de diagnóstico y accesorios equivalentes."""
    return _extraer('comercio1', URLS_COMERCIO1,raw_dir,offline,corrida_id)
def scrape_comercio2(raw_dir=RAW_DIR, offline=False, corrida_id=None):
    """HTML público paginado de equipos médicos Cafam; no consulta /api/."""
    return _extraer('comercio2', URLS_COMERCIO2,raw_dir,offline,corrida_id,html=True)
def scrape_comercio3(raw_dir=RAW_DIR, offline=False, corrida_id=None):
    """JSON público de diagnóstico, control y termómetros pediátricos La Rebaja."""
    return _extraer('comercio3', URLS_COMERCIO3,raw_dir,offline,corrida_id)

URLS_COMERCIO4 = ['https://www.habibdroguerias.com/api/catalog_system/pub/products/search/?fq=C:/51/176/']
URLS_COMERCIO5 = ['https://farmaprime.com.co/wp-json/wc/store/v1/products?category=51085&per_page=100']
URLS_COMERCIO6 = ['https://farmawebonline.com/wp-json/wc/store/v1/products?category='+str(c)+'&per_page=100' for c in [26968,26887,44978,27026]]

def _woo_producto(p,slug,ruta,env):
    """Normaliza campos del JSON público WooCommerce sin alterar su copia cruda."""
    from bs4 import BeautifulSoup
    precios=p.get('prices',{})
    if precios.get('currency_code')!='COP':
        raise ValueError('La moneda del comercio no es COP')
    escala=10**int(precios.get('currency_minor_unit',0))
    def numero(k):
        v=precios.get(k)
        return float(v)/escala if v not in (None,'') and float(v)>0 else None
    actual,antes=numero('price'),numero('regular_price')
    descripciones=[p[k] for k in ['description','short_description'] if p.get(k)]
    descripcion='\n'.join(descripciones) or None
    texto=BeautifulSoup(descripcion or '', 'lxml').get_text(' ',strip=True)
    marca=None
    if p.get('brands'):
        marca=p['brands'][0].get('name')
    laboratorio=re.search(r'LABORATORIO:\s*([^/]+)',texto,re.I)
    if not marca and laboratorio:
        marca=laboratorio[1].strip() or None
    codigo=re.search(r'CODIGO DE BARRAS:\s*(\d{8,14})',texto,re.I)
    ean=codigo[1] if codigo else None
    fila=dict(zip(COLUMNAS,[REGISTRO_COMERCIOS[slug],str(p['id']),p['permalink'],p['name'],descripcion,marca,
        ' | '.join(x['name'] for x in p.get('categories',[])),actual,antes,
        int(bool(p.get('on_sale')) or actual is not None and antes is not None and antes>actual),
        env['fecha_hora_consulta'],ruta]))
    disponible=p.get('is_in_stock') is True and p.get('is_purchasable') is True and p.get('is_on_backorder') is not True
    estado='disponible' if disponible else 'agotado' if p.get('is_in_stock') is False else 'desconocida'
    meta={'ean':ean,'ficha':{'sku_comercio':p.get('sku'),'attributes':p.get('attributes',[]),
        'images':p.get('images',[]),'is_in_stock':p.get('is_in_stock'),
        'is_purchasable':p.get('is_purchasable'),'is_on_backorder':p.get('is_on_backorder'),
        'stock_availability':p.get('stock_availability'),'currency_minor_unit':precios.get('currency_minor_unit')},
        'presentacion':None,'categorias':[x['name'] for x in p.get('categories',[])]}
    return fila,estado,meta

def _extraer_woo(slug,urls,raw_dir,offline,corrida_id):
    """Recorre categorías completas por page; comprueba X-WP-Total y repeticiones."""
    import gzip
    corrida_id=corrida_id or nueva_corrida_id()
    if offline:
        fuentes=list(leer_raw(raw_dir,slug,corrida_id))
        if not fuentes:raise ValueError('No hay copias crudas para la corrida')
    else:
        if os.path.exists(os.path.join(raw_dir,slug,corrida_id)):
            raise ValueError('La corrida ya existe: use offline u otro identificador')
        fuentes=[];n=0
        for url in urls:
            vistos=set()
            for pagina in range(1,61):
                r=_peticion(url+'&page='+str(pagina))
                contenido=r.json()
                if not isinstance(contenido,list):raise ValueError('Respuesta de catálogo inesperada')
                total=int(r.headers['X-WP-Total']) if r.headers.get('X-WP-Total') else None
                n+=1;ruta,ts=guardar_raw(raw_dir,slug,corrida_id,n,contenido,r.url,'json')
                with gzip.open(ruta,'rt',encoding='utf-8') as f:env=json.load(f)
                env.update(total_reportado=total,categoria_origen=url,plataforma='woocommerce')
                with gzip.open(ruta,'wt',encoding='utf-8') as f:json.dump(env,f,ensure_ascii=False)
                fuentes.append((ruta,env))
                ids={str(p['id']) for p in contenido}
                nuevos=ids-vistos;vistos|=ids
                if total is not None and len(vistos)>=total:break
                if not nuevos and contenido:raise ValueError('Paginación repetida')
                if not contenido:
                    if total is not None and len(vistos)<total:raise ValueError('Categoría incompleta')
                    break
            else:raise ValueError('Límite de sesenta páginas alcanzado')
    registros={};disponibilidad={};metadatos={};secciones={}
    for ruta,env in fuentes:
        cat=env['categoria_origen'];info=secciones.setdefault(cat,{'ids':set(),'reportado':env.get('total_reportado')})
        for p in env['contenido']:
            fila,estado,meta=_woo_producto(p,slug,ruta,env)
            info['ids'].add(fila['sku'])
            if fila['sku'] in registros:continue
            registros[fila['sku']]=fila;disponibilidad[fila['sku']]=estado;metadatos[fila['sku']]=meta
    cobertura=[{'url':u,'obtenidos':len(x['ids']),'reportado':x['reportado']} for u,x in secciones.items()]
    df=pd.DataFrame(registros.values(),columns=COLUMNAS)
    df.attrs.update(cobertura=cobertura,completa=set(secciones)==set(urls) and all(x['reportado'] is not None and x['obtenidos']==x['reportado'] for x in cobertura),
        n_reportado_sitio=sum(x['reportado'] for x in cobertura) if all(x['reportado'] is not None for x in cobertura) else None,
        notas=json.dumps(cobertura,ensure_ascii=False),disponibilidad=disponibilidad,metadatos=metadatos)
    print(f"{REGISTRO_COMERCIOS[slug]}: obtenidos {len(df)} de {df.attrs['n_reportado_sitio']} reportados")
    return df

def scrape_comercio4(raw_dir=RAW_DIR,offline=False,corrida_id=None):
    """Equipos de medición de Habib: VTEX y cantidad disponible del vendedor."""
    return _extraer('comercio4',URLS_COMERCIO4,raw_dir,offline,corrida_id)
def scrape_comercio5(raw_dir=RAW_DIR,offline=False,corrida_id=None):
    """Ortopedia y dispositivos médicos de Farmaprime: API pública de su tienda."""
    return _extraer_woo('comercio5',URLS_COMERCIO5,raw_dir,offline,corrida_id)
def scrape_comercio6(raw_dir=RAW_DIR,offline=False,corrida_id=None):
    """Equipamiento médico de Farmaweb: API pública de su tienda."""
    return _extraer_woo('comercio6',URLS_COMERCIO6,raw_dir,offline,corrida_id)

SCRAPERS={'comercio1':scrape_comercio1,'comercio2':scrape_comercio2,'comercio3':scrape_comercio3,
          'comercio4':scrape_comercio4,'comercio5':scrape_comercio5,'comercio6':scrape_comercio6}

def run_all(offline=False, corrida_id=None, comercios=None, db_path=DB_PATH, raw_dir=RAW_DIR):
    """Recolecta por comercio con transacciones independientes e historial acumulativo."""
    from codigo import db
    from codigo.limpieza import limpiar
    comercios = comercios or list(COMERCIOS)
    if offline and corrida_id is None:
        carpetas = [set(os.listdir(os.path.join(raw_dir,s))) for s in comercios]
        comunes = set.intersection(*carpetas)
        if not comunes:
            raise ValueError('No existe una corrida cruda común a todos los comercios')
        corrida_id = sorted(comunes)[-1]
    corrida_id = corrida_id or nueva_corrida_id()
    db.crear_bd(db_path)
    resumen = {}
    with db.conectar(db_path) as con:
        for slug in comercios:
            inicio = ahora_iso()
            try:
                df = SCRAPERS[slug](raw_dir=raw_dir,offline=offline,corrida_id=corrida_id)
                estado = 'completa' if df.attrs['completa'] else 'parcial'
                with con:
                    eid = db.registrar_ejecucion(con,corrida_id,slug,df.fecha_hora_consulta.min() if offline and not df.empty else inicio,len(df),df.attrs['n_reportado_sitio'],estado,df.attrs['notas'])
                    conteos = db.insertar_df(con,limpiar(df),eid,slug)
                resumen[slug] = dict(estado=estado,n=len(df),n_reportado=df.attrs['n_reportado_sitio'],**conteos)
            except Exception as error:
                with con:
                    db.registrar_ejecucion(con,corrida_id,slug,inicio,0,None,'fallida',str(error))
                resumen[slug] = dict(estado='fallida',n=0,error=str(error))
        manifiesto=os.path.join(raw_dir,'manifiestos',corrida_id+'.json')
        if os.path.exists(manifiesto):
            with open(manifiesto,encoding='utf-8') as f:mapeo=json.load(f)['correspondencia']
        else:
            mapeo='datos/correspondencia.csv'
        if os.path.exists(mapeo):
            db.aplicar_correspondencia(con,mapeo)
            db.registrar_cohorte(con,corrida_id,mapeo)
        if not offline:
            import shutil
            os.makedirs('datos/correspondencias',exist_ok=True)
            copia='datos/correspondencias/'+corrida_id+'.csv'
            shutil.copyfile(mapeo,copia)
            os.makedirs(os.path.dirname(manifiesto),exist_ok=True)
            with open(manifiesto,'w',encoding='utf-8') as f:
                json.dump({'corrida_id':corrida_id,'comercios':comercios,'correspondencia':copia},f,ensure_ascii=False,indent=2)
    con.close()
    print('Corrida:',corrida_id)
    print(pd.DataFrame(resumen).T.to_string())
    return resumen

if __name__ == '__main__':
    # CLI sin dependencias adicionales; el documento usa la misma función.
    import argparse
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--offline',action='store_true')
    cli.add_argument('--corrida-id')
    cli.add_argument('--db',default=DB_PATH)
    opciones=cli.add_mutually_exclusive_group()
    opciones.add_argument('--reconstruir',metavar='BASE_NUEVA',help='Reconstruir todo el historial sin conexión')
    opciones.add_argument('--verificar',action='store_true',help='Contrastar la base con una reconstrucción temporal sin red')
    args=cli.parse_args()
    if args.reconstruir:
        from codigo.reproduccion import reconstruir
        reconstruir(args.reconstruir)
    elif args.verificar:
        from codigo.reproduccion import verificar
        verificar()
    else:
        run_all(offline=args.offline,corrida_id=args.corrida_id,db_path=args.db)
