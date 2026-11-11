"""Paletas visuales aproximadas, no colores oficiales ni logotipos."""
import hashlib
import re
import unicodedata
COMERCIOS={'Colsubsidio':'#007F86','Cafam':'#6654A1','La Rebaja':'#B96B26'}
MARCAS={'dove':'#243C78','rexona':'#236861','protex':'#345C92','yodora':'#81536D',
        'nivea':'#254D91','gillette':'#35556E','mexsana':'#826A30','palmolive':'#3F7254'}
SEMANTICOS={'subió':'#A64238','bajó':'#24714E','sin cambio':'#526373','nuevo':'#315F99','no observado':'#896522','advertencia':'#896522','error':'#A64238'}

def normalizar_marca(value):
    text=unicodedata.normalize('NFKD',str(value or ''))
    text=''.join(c for c in text if not unicodedata.combining(c)).casefold()
    text=re.sub(r'[^\w\s]',' ',text)
    text=' '.join(text.split())
    return {'dove original':'dove','rexona clinical':'rexona','pro tex':'protex','yodora clasico':'yodora'}.get(text,text)

def nombre_marca(value):
    return normalizar_marca(value).title() or 'Sin dato'

def color_marca(value):
    key=normalizar_marca(value)
    if key in MARCAS:return MARCAS[key]
    # Hash estable entre procesos; no depende del orden ni de las marcas filtradas.
    digest=hashlib.sha256(key.encode()).digest()
    import colorsys
    rgb=colorsys.hls_to_rgb(int.from_bytes(digest[:2],'big')/65535,0.33,0.37)
    return '#'+''.join(f'{round(c*255):02x}' for c in rgb)
