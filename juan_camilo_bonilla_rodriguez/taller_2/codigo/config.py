"""Comercios activos e históricos, con identificadores que no se reutilizan."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / 'comparador_precios.sqlite'
RAW_DIR = ROOT / 'raw'
DATOS_DIR = ROOT / 'datos'
TZ_CO = timezone(timedelta(hours=-5))
USER_AGENT = 'ComparadorAcademico/1.0 (contacto: jbonillaro@unal.edu.co)'
PAUSA_SEG = 1.0
COMERCIOS = {'comercio4':'Habib','comercio5':'Farmaprime','comercio6':'Farmaweb'}
REGISTRO_COMERCIOS = {'comercio1':'Locatel','comercio2':'Cafam','comercio3':'La Rebaja',**COMERCIOS}
COLORES = {'Locatel':'#1f77b4','Cafam':'#ff7f0e','La Rebaja':'#2ca02c',
           'Habib':'#d62728','Farmaprime':'#9467bd','Farmaweb':'#17becf'}
def ahora_iso():
    """Momento actual en Colombia."""
    return datetime.now(TZ_CO).isoformat(timespec='seconds')
def nueva_corrida_id():
    """Identificador de campaña compartido por los comercios."""
    return datetime.now(TZ_CO).strftime('%Y-%m-%dT%H%M%S%f')
