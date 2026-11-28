"""Reglas deterministas; se preservan todos los campos originales."""
import re
import unicodedata
import pandas as pd

def normalizar(texto):
    """Minúsculas sin tildes, espacios repetidos ni puntuación."""
    if texto is None or pd.isna(texto):
        return ''
    texto = ''.join(c for c in unicodedata.normalize('NFD', str(texto).lower()) if unicodedata.category(c) != 'Mn')
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', texto)).strip()

def limpiar_precio(texto):
    """Convierte formato colombiano. No transforma ceros ni ausencias en precios."""
    if texto is None or pd.isna(texto):
        return None
    if isinstance(texto, (float, int)):
        return float(texto) if texto > 0 else None
    s = re.sub(r'[^\d,.]', '', str(texto))
    if not s:
        return None
    if ',' in s:
        s = s.replace('.', '').replace(',', '.')
    elif re.fullmatch(r'\d{1,3}(\.\d{3})+', s):
        s = s.replace('.', '')
    valor = float(s)
    return valor if valor > 0 else None

def normalizar_contenido(valor, unidad):
    """Convierte L a mL y kg a g sin mezclar dimensiones."""
    u = unidad.lower()
    factor, base = {'l': (1000, 'mL'), 'ml': (1, 'mL'), 'kg': (1000, 'g'), 'g': (1, 'g'), 'mg': (1, 'mg'), 'unidad': (1, 'unidad')}[u]
    return float(valor) * factor, base

def clasificar(titulo):
    """Excluye pruebas, sensores continuos, accesorios y kits ajenos a la categoría."""
    t = normalizar(titulo)
    if re.search(r'embarazo|ovulacion|suscrip|plan de ahorro|sensor|manometro|brazalete|camara|manguera|pera |inhalador|estetoscopio|fonendoscopio', t):
        return 'otro'
    if ('presion arterial' in t or 'presion sanguinea' in t) and 'monitor' in t:
        return 'tensiometro'
    if 'freestyle optium neo' in t or 'lector freestyle libre' in t:
        return 'glucometro'
    if ('accu' in t and 'active' in t and 'glucosa' in t):
        return 'tiras_reactivas'
    for patron, clase in [(r'lanceta', 'lancetas'), (r'tiras?|tirillas?', 'tiras_reactivas'), (r'termomet', 'termometro'), (r'tensiomet', 'tensiometro'), (r'oximet', 'oximetro'), (r'glucomet', 'glucometro')]:
        if re.search(patron, t):
            if clase=='tiras_reactivas' and not re.search(r'reactiv|reactucoquic|gluc|accu|optium|freestyle|one touch|onetouch|urin',t):
                continue
            return clase
    return 'otro'

def limpiar(df):
    """Añade atributos normalizados; cantidades ambiguas permanecen ausentes."""
    out = df.copy()
    for campo in ['nombre_std', 'marca_std', 'subcategoria_std', 'contenido', 'unidad', 'n_unidades', 'concentracion', 'excluido', 'motivo_exclusion']:
        out[campo] = pd.Series(index=out.index, dtype=object)
    for i, r in out.iterrows():
        t = normalizar(r.titulo_original)
        meta = df.attrs.get('metadatos',{}).get(r.sku,{})
        clase = clasificar(t)
        ficha = meta.get('ficha',{})
        marca = None
        marca = normalizar(r.marca_original) or None
        cantidad, unidad, paquetes = None, None, 1
        # La ficha complementa nombres abreviados sin alterar el anuncio original.
        texto_cantidad = t + ' ' + normalizar(' '.join(meta.get('presentacion') or []))
        if clase in ('lancetas','tiras_reactivas'):
            texto_cantidad += ' ' + t
        # Kits heterogéneos no equivalen a un número de tiras o lancetas.
        mixto = bool(re.search(r'\+|gratis|oferta|pague|lleve|kit', str(r.titulo_original).lower()))
        if clase in ('termometro', 'tensiometro', 'glucometro', 'oximetro') and not mixto:
            cantidad, unidad = 1, 'unidad'
        elif not mixto:
            m = re.search(r'(?:\bx\s*|\b)(\d+)\s*(?:unds?|uds|uni|unidades|unidad|tiras|lancetas)\b', texto_cantidad)
            if not m:
                m = re.search(r'\bx\s*(\d+)\b',t)
            if m:
                cantidad, unidad = float(m[1]), 'unidad'
        # Distingue presentaciones múltiples homogéneas de kits heterogéneos.
        if clase=='tiras_reactivas' and re.search(r'pague 1 lleve 2',t):
            m = re.search(r'25',t)
            if m:
                cantidad,unidad,paquetes=25,'unidad',2
        if clase in ('lancetas','tiras_reactivas') and cantidad is None and not mixto:
            valores = ficha.get('Cantidad por unidad de medida') or ficha.get('Cantidadunidadesmedida')
            if valores and re.fullmatch(r'\d+(?:\.\d+)?',str(valores[0])):
                cantidad,unidad=float(valores[0]),'unidad'
        if clase=='tiras_reactivas' and '2 cajas' in t and cantidad==25:
            paquetes=2
        if 'accu' in t:
            marca='accu-chek'
        elif 'glucoquick' in t:
            marca='glucoquick'
        elif 'freestyle' in t or 'optium' in t:
            marca='abbott'
        elif 'vick' in t:
            marca='vicks'
        nombre = t
        if marca:
            nombre = nombre.replace(marca, '').strip()
        nombre = re.sub(r'\bx\s*\d+\s*(?:und|uni|unidades|unidad)\b', '', nombre).strip()
        vals = [nombre, marca, clase, cantidad, unidad, paquetes, None, int(clase == 'otro'), 'Fuera de delimitación: prueba, accesorio, sensor o producto ajeno' if clase == 'otro' else None]
        for k, value in zip(['nombre_std','marca_std','subcategoria_std','contenido','unidad','n_unidades','concentracion','excluido','motivo_exclusion'], vals):
            out.at[i, k] = value
    out.attrs.update(df.attrs)
    return out
