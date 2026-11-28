"""
scraper.py
==========
Módulo de recolección y web scraping para el Taller 1 de Minería de Datos.
Universidad Nacional de Colombia - Asignatura: Minería de Datos (2016325).

Categoría Asignada:
  Cuidado y Limpieza del Hogar (Detergentes, lavalozas, limpiadores,
  desinfectantes de superficies, ambientadores, bolsas de basura y esponjas).

Comercios Evaluados:
  - Supertiendas Olímpica
  - Tiendas Jumbo (Cencosud)
  - Almacenes Éxito

Características Principales:
  - Peticiones HTTP directas mediante `requests` con verificación SSL activa y User-Agent identificable.
  - Paginación completa y sin truncamiento por subcategorías equivalentes homologadas.
  - Extracción y almacenamiento de total oficial del sitio mediante cabecera `resources`.
  - Copias crudas organizadas por comercio y fecha en formato .json.gz con límite automático de <50 MB por archivo.
  - Archivo `meta.json` de trazabilidad para cada captura cruda.
  - Modo sin conexión (`--offline [--fecha YYYY-MM-DD]`) 100% reproducible sin peticiones de red.
  - Persistencia idempotente en SQLite con separación estricta de textos originales y campos estandarizados.
  - Registro auditable de productos excluidos en la tabla `descartados`.
  - Correspondencia automática de productos por EAN, marca, variante y contenido.
"""

import os
import sys
import json
import gzip
import time
import uuid
import re
import sqlite3
import datetime
import argparse
from typing import Dict, List, Any, Optional, Tuple

import requests

# =====================================================================
# CONFIGURACIÓN GENERAL Y RUTAS
# =====================================================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(BASE_DIR, "raw")
DB_PATH = os.path.join(BASE_DIR, "comparador_precios.sqlite")
TIMEZONE_OFFSET = "-05:00"  # America/Bogota (UTC-5)
PAGE_SIZE = 50
MAX_RETRIES = 4
BACKOFF_FACTOR = 1.8
MAX_RAW_FILE_SIZE_BYTES = 45 * 1024 * 1024  # 45 MB para garantizar < 100 MB en GitHub

DEFAULT_HEADERS = {
    "User-Agent": "MineriaDatosUNAL/1.0 (Academic Research; contacto: ssepulvedav@unal.edu.co)",
    "Accept": "application/json, text/plain, */*"
}

def get_ssl_verify_bundle() -> str:
    """
    Retorna la ruta del bundle de certificados para verificación SSL activa.
    Combina certifi con la cadena intermedia de Jumbo (certs/jumbo_chain.pem)
    para resolver la omisión de certificados intermedios por parte del servidor.
    Permite anulación mediante variable de entorno SSL_CERT_FILE o REQUESTS_CA_BUNDLE.
    """
    custom_ca = os.environ.get("SSL_CERT_FILE") or os.environ.get("REQUESTS_CA_BUNDLE")
    if custom_ca and os.path.exists(custom_ca):
        return custom_ca

    import certifi
    base_cert = certifi.where()
    curr_dir = os.path.dirname(os.path.abspath(__file__))
    jumbo_chain = os.path.join(curr_dir, "certs", "jumbo_chain.pem")

    if os.path.exists(jumbo_chain):
        certs_dir = os.path.join(curr_dir, "certs")
        combined_file = os.path.join(certs_dir, "combined_bundle.pem")
        try:
            if not os.path.exists(combined_file) or os.path.getmtime(combined_file) < os.path.getmtime(jumbo_chain):
                with open(base_cert, "r", encoding="utf-8") as fb, open(jumbo_chain, "r", encoding="utf-8") as fc:
                    combined_data = fb.read().strip() + "\n\n" + fc.read().strip() + "\n"
                with open(combined_file, "w", encoding="utf-8") as fo:
                    fo.write(combined_data)
            return combined_file
        except Exception:
            return base_cert

    return base_cert

# =====================================================================
# TAXONOMÍA Y CATEGORÍAS HOMOLOGADAS
# =====================================================================

CATEGORIAS_EQUIVALENTES = {
    "Olimpica": {
        "incluidas": [
            {
                "id": "cuidado-de-la-ropa",
                "nombre": "Cuidado De La Ropa",
                "path": "supermercado/aseo-del-hogar/cuidado-de-la-ropa",
                "motivo": "Contiene detergentes en polvo, líquidos y jabones de lavar ropa."
            },
            {
                "id": "cuidado-de-superficies",
                "nombre": "Cuidado De Superficies",
                "path": "supermercado/aseo-del-hogar/cuidado-de-superficies",
                "motivo": "Contiene lavalozas, limpiapisos, multiusos, desinfectantes y ambientadores."
            },
            {
                "id": "utensilios-de-limpieza",
                "nombre": "Utensilios De Limpieza",
                "path": "supermercado/aseo-del-hogar/utensilios-de-limpieza",
                "motivo": "Contiene esponjas, fibras, paños y traperos de limpieza."
            },
            {
                "id": "desechables",
                "nombre": "Desechables",
                "path": "supermercado/aseo-del-hogar/desechables",
                "motivo": "Contiene bolsas de basura para el hogar."
            }
        ],
        "excluidas": [
            {
                "id": "papeles-desechables",
                "nombre": "Papeles Desechables",
                "motivo": "Excluido por delimitación: papel higiénico, toallas de cocina y servilletas."
            },
            {
                "id": "betunes-cremas-y-liquidos",
                "nombre": "Betunes Cremas y Líquidos",
                "motivo": "Excluido por delimitación: calzado."
            },
            {
                "id": "jardineria",
                "nombre": "Jardinería",
                "motivo": "Excluido por delimitación: abonos y plantas."
            }
        ]
    },
    "Jumbo": {
        "incluidas": [
            {
                "id": "detergentes",
                "nombre": "Detergentes",
                "path": "supermercado/aseo-de-hogar/detergentes",
                "motivo": "Detergentes en polvo y líquidos para ropa."
            },
            {
                "id": "lavalozas-y-lavaplatos",
                "nombre": "Lavalozas y Lavaplatos",
                "path": "supermercado/aseo-de-hogar/lavalozas-y-lavaplatos",
                "motivo": "Lavaplatos líquidos y en crema."
            },
            {
                "id": "limpiadores-multiusos",
                "nombre": "Limpiadores Multiusos",
                "path": "supermercado/aseo-de-hogar/limpiadores-multiusos",
                "motivo": "Limpiapisos y limpiadores de superficies."
            },
            {
                "id": "limpiadores-de-bano",
                "nombre": "Limpiadores de Baño",
                "path": "supermercado/aseo-de-hogar/limpiadores-de-bano",
                "motivo": "Desinfectantes y limpiadores específicos de sanitarios."
            },
            {
                "id": "desinfectantes",
                "nombre": "Desinfectantes",
                "path": "supermercado/aseo-de-hogar/desinfectantes",
                "motivo": "Blanqueadores, cloros y desinfectantes."
            },
            {
                "id": "ambientadores",
                "nombre": "Ambientadores",
                "path": "supermercado/aseo-de-hogar/ambientadores",
                "motivo": "Aerosoles, pastillas y aromatizantes de ambiente."
            },
            {
                "id": "ceras-y-limpiadores-para-pisos",
                "nombre": "Ceras y Limpiadores para Pisos",
                "path": "supermercado/aseo-de-hogar/ceras-y-limpiadores-para-pisos",
                "motivo": "Tratamiento y desinfección de pisos."
            },
            {
                "id": "implementos-de-aseo",
                "nombre": "Implementos de Aseo",
                "path": "supermercado/aseo-de-hogar/implementos-de-aseo",
                "motivo": "Esponjas, guantes, bolsas plásticas de aseo."
            }
        ],
        "excluidas": [
            {
                "id": "papel-higienico",
                "nombre": "Papel Higiénico",
                "motivo": "Excluido por delimitación: higiene personal."
            },
            {
                "id": "suavizantes",
                "nombre": "Suavizantes",
                "motivo": "Excluido por delimitación del taller."
            },
            {
                "id": "insecticidas",
                "nombre": "Insecticidas",
                "motivo": "Excluido por delimitación del taller."
            }
        ]
    },
    "Exito": {
        "incluidas": [
            {
                "id": "jabones-detergentes-y-limpiadores",
                "nombre": "Jabones, detergentes y limpiadores",
                "path": "mercado/aseo-del-hogar/jabones-detergentes-y-limpiadores",
                "motivo": "Detergentes, limpiapisos y multiusos."
            },
            {
                "id": "lavalozas-y-desengrasante",
                "nombre": "Lavalozas y desengrasante",
                "path": "mercado/aseo-del-hogar/lavalozas-y-desengrasante",
                "motivo": "Lavaplatos líquidos y en crema."
            },
            {
                "id": "ambientadores-e-insecticidas",
                "nombre": "Ambientadores e insecticidas",
                "path": "mercado/aseo-del-hogar/ambientadores-e-insecticidas",
                "motivo": "Ambientadores del hogar (se filtran insecticidas con regla documentada)."
            },
            {
                "id": "implementos-para-la-limpieza",
                "nombre": "Implementos para la limpieza",
                "path": "mercado/aseo-del-hogar/implementos-para-la-limpieza",
                "motivo": "Esponjas, paños, fibras y bolsas de basura."
            }
        ],
        "excluidas": [
            {
                "id": "papel-higienico",
                "nombre": "Papel higiénico",
                "motivo": "Excluido por delimitación: higiene personal."
            },
            {
                "id": "suavizantes",
                "nombre": "Suavizantes",
                "motivo": "Excluido por delimitación del taller."
            },
            {
                "id": "servilletas-y-toallas-de-cocina",
                "nombre": "Servilletas y toallas de cocina",
                "motivo": "Excluido por delimitación: papel desechable."
            },
            {
                "id": "desechables-velas-y-carbon",
                "nombre": "Desechables, velas y carbón",
                "motivo": "Excluido por delimitación: carbón, fósforos y velas."
            },
            {
                "id": "betunes-para-zapatos",
                "nombre": "Betunes para zapatos",
                "motivo": "Excluido por delimitación: calzado."
            }
        ]
    }
}

# Palabras clave explícitamente excluidas dentro de subcategorías mixtas
EXCLUSION_RULES = [
    ("insecticida", "Producto insecticida/plaguicida fuera de la delimitación"),
    ("cucaracha", "Producto contra insectos fuera de la delimitación"),
    ("zancudo", "Producto contra insectos fuera de la delimitación"),
    ("mosca", "Producto contra insectos fuera de la delimitación"),
    ("repelente", "Repelente corporal/ambiental fuera de la delimitación"),
    ("suavizante", "Suavizante para ropa fuera de la delimitación"),
    ("papel higienico", "Papel higiénico fuera de la delimitación"),
    ("toalla de cocina", "Toalla de cocina desechable fuera de la delimitación"),
    ("toallas de cocina", "Toallas de cocina desechables fuera de la delimitación"),
    ("servilleta", "Servilletas de papel fuera de la delimitación"),
    ("betun", "Cuidado del calzado fuera de la delimitación"),
    ("carbon", "Carbón vegetal para asados fuera de la delimitación"),
    ("vela", "Velas y veladoras fuera de la delimitación"),
    ("fosforo", "Fósforos y encendedores fuera de la delimitación")
]


# =====================================================================
# UTILIDADES DE FECHA, TIEMPO Y PARSER DE CONTENIDO
# =====================================================================

def get_current_iso_timestamp() -> str:
    """Devuelve la fecha y hora actual en formato ISO 8601 con offset Colombia (-05:00)."""
    tz = datetime.timezone(datetime.timedelta(hours=-5))
    return datetime.datetime.now(tz).isoformat(timespec="seconds")


def parse_content_and_unit(text: str) -> Tuple[Optional[float], Optional[str], Optional[int]]:
    """
    Parsea y normaliza el contenido nominal, unidad base y número de unidades.

    Reglas de conversión a unidad base:
      - 1 L / lt / litro -> 1000 mL
      - 1 kg / kilo -> 1000 g
      - 1 g / gr / gramo -> 1 g
      - 1 und / unidades / bolsas / piezas -> 1 und
      - Multipacks: '2 x 450 g' -> contenido total = 900 g, unidades_por_paquete = 2.
      - Combos / Kits con suma ('1000ml + 700ml'): suma contenido si comparten unidad base.
      - Retorna: (contenido_total, unidad_base, unidades_por_paquete).
      - Si no es identificable, retorna (None, None, 1).
    """
    if not text:
        return None, None, 1

    t = re.sub(r'\s+', ' ', text.lower().replace(",", ".")).strip()

    # Caso Combo / Kit con '+' (ej: '1000ml + 700ml', 'x1L + ... x500ml')
    m_combo = re.search(r'(\d+(?:\.\d+)?)\s*(ml|l|lt|litros?|g|gr|gramos?|kg|kilos?)\s*\+\s*(?:[a-zA-Záéíóú\s]+)?(?:x\s*)?(\d+(?:\.\d+)?)\s*(ml|l|lt|litros?|g|gr|gramos?|kg|kilos?)\b', t)
    if m_combo:
        val1, u1 = float(m_combo.group(1)), m_combo.group(2)
        val2, u2 = float(m_combo.group(3)), m_combo.group(4)
        norm1, base_u1, _ = _normalize_units(val1, u1, 1)
        norm2, base_u2, _ = _normalize_units(val2, u2, 1)
        if base_u1 == base_u2:
            return round(norm1 + norm2, 2), base_u1, 2
        else:
            return None, None, 2

    # Caso Multipack con 'x': '2x450 g', '2 x 450 g', 'pack x 2 und 300 ml'
    m_pack1 = re.search(r'(\d+)\s*(?:x|und|unidades|pack)\s*(?:de)?\s*(\d+(?:\.\d+)?)\s*(ml|l|lt|litros?|g|gr|gramos?|kg|kilos?)\b', t)
    if m_pack1 and 1 < int(m_pack1.group(1)) <= 50:
        unidades = int(m_pack1.group(1))
        unit_val = float(m_pack1.group(2))
        raw_unit = m_pack1.group(3)
        return _normalize_units(unidades * unit_val, raw_unit, unidades)

    # Caso Multipack inverso: '450g x 2und', '450 g x 2', '450g x2'
    m_pack2 = re.search(r'(\d+(?:\.\d+)?)\s*(ml|l|lt|litros?|g|gr|gramos?|kg|kilos?)\s*x\s*(\d+)\s*(?:unds?|unidades?|unid\.?)?\b', t)
    if m_pack2 and 1 < int(m_pack2.group(3)) <= 50:
        unit_val = float(m_pack2.group(1))
        raw_unit = m_pack2.group(2)
        unidades = int(m_pack2.group(3))
        return _normalize_units(unidades * unit_val, raw_unit, unidades)

    # Caso Prefijo 'x' con unidad de volumen o masa: 'x1.8L', 'x 5kg', 'x 2000 ml'
    m_prefix = re.search(r'\bx\s*(\d+(?:\.\d+)?)\s*(ml|l|lt|litros?|g|gr|gramos?|kg|kilos?)\b', t)
    if m_prefix:
        val = float(m_prefix.group(1))
        raw_unit = m_prefix.group(2)
        return _normalize_units(val, raw_unit, 1)

    # Caso Medida estándar (acepta múltiples espacios y paréntesis, ej: '(180  gr)', '1.5L', '1 lt')
    m_single = re.search(r'(\d+(?:\.\d+)?)\s*(ml|l|lt|litros?|g|gr|gramos?|kg|kilos?)\b', t)
    if m_single:
        val = float(m_single.group(1))
        raw_unit = m_single.group(2)
        return _normalize_units(val, raw_unit, 1)

    # Caso Artículos contables explícitos: '12 und', '(12  und)', '30 unds', '10 bolsas', '3 unid.'
    m_count = re.search(r'(\d+)\s*(?:unds?|unidades?|unid\.?|bolsas|paquetes?|fibras?|esponjas?|pastillas?)\b', t)
    if m_count:
        val = float(m_count.group(1))
        return val, "und", int(val)

    # Caso Sufijo de multiplicador / conteo: 'tarjeta x3', 'x3 unds', 'x2' (ej: AMBTADOR TERGO GLOP TARJETA X3)
    m_mult = re.search(r'(?:tarjeta|pack|combo|caja|bolsa)?\s*\bx\s*(\d+)\s*(?:unds?|unidades?|unid\.?)?\b', t)
    if m_mult:
        val = float(m_mult.group(1))
        if 1 < val <= 100:
            return val, "und", int(val)

    return None, None, 1


def _normalize_units(amount: float, raw_unit: str, units_count: int) -> Tuple[float, str, int]:
    """Convierte cantidades y unidades a la unidad base estándar (g, mL o und)."""
    u = raw_unit.lower()
    if u in ["l", "lt", "litro", "litros"]:
        return round(amount * 1000.0, 2), "ml", units_count
    elif u in ["ml"]:
        return round(amount, 2), "ml", units_count
    elif u in ["kg", "kilo", "kilos"]:
        return round(amount * 1000.0, 2), "g", units_count
    elif u in ["g", "gr", "gramo", "gramos"]:
        return round(amount, 2), "g", units_count
    elif u in ["und", "unds", "unidades", "unid", "bolsas"]:
        return round(amount, 2), "und", units_count
    return round(amount, 2), u, units_count


def check_product_scope(name: str, subcat_name: str, description: str = "") -> Tuple[bool, Optional[str]]:
    """
    Evalúa si un producto pertenece a la delimitación de Cuidado y Limpieza del Hogar.
    Retorna: (es_valido, motivo_descarte)
    """
    text_to_check = f"{name} {subcat_name} {description}".lower()

    # Exclusión explícita de papel higiénico (nombres "Papel Higiénico", "P/HIG")
    clean_text = text_to_check.replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u")
    if any(ph in clean_text for ph in ["p/hig", "p/ hig", "papel hig", "higienico"]):
        return False, "Papel higiénico fuera de la delimitación"

    # Si es explícitamente esponja o bolsa de basura, está dentro del alcance
    if "bolsa" in text_to_check and any(b in text_to_check for b in ["basura", "residuos", "aseo", "rollo", "compostable"]):
        return True, None
    if any(e in text_to_check for e in ["esponja", "fibra", "esponjilla", "sababra"]):
        return True, None

    # Verificar reglas de exclusión generales
    for kw, reason in EXCLUSION_RULES:
        if kw in clean_text:
            return False, reason

    return True, None


# =====================================================================
# GESTIÓN DE ARCHIVOS CRUDOS (RAW) Y PARTICIONAMIENTO < 50 MB
# =====================================================================

def save_raw_chunks(comercio_slug: str, date_str: str, subcat_id: str, raw_items: List[Dict[str, Any]]) -> List[str]:
    """
    Guarda los datos crudos en raw/<comercio>/<fecha>/ en archivos .json.gz.
    Si el archivo excede los 45 MB, lo particiona automáticamente en varios chunks.
    """
    target_dir = os.path.join(RAW_DIR, comercio_slug, date_str)
    os.makedirs(target_dir, exist_ok=True)

    json_bytes = json.dumps(raw_items, ensure_ascii=False).encode("utf-8")
    saved_files = []

    # Verificar si cabe en un único archivo
    if len(json_bytes) < MAX_RAW_FILE_SIZE_BYTES:
        filename = f"{comercio_slug}_{subcat_id}.json.gz"
        filepath = os.path.join(target_dir, filename)
        with gzip.open(filepath, "wb") as f:
            f.write(json_bytes)
        saved_files.append(filepath)
    else:
        # Particionar en chunks
        chunk_size = max(50, len(raw_items) // ((len(json_bytes) // MAX_RAW_FILE_SIZE_BYTES) + 2))
        part_idx = 1
        for i in range(0, len(raw_items), chunk_size):
            chunk = raw_items[i:i + chunk_size]
            filename = f"{comercio_slug}_{subcat_id}_part{part_idx:03d}.json.gz"
            filepath = os.path.join(target_dir, filename)
            with gzip.open(filepath, "wt", encoding="utf-8") as f:
                json.dump(chunk, f, ensure_ascii=False)
            saved_files.append(filepath)
            part_idx += 1

    return saved_files


def save_metadata(comercio_slug: str, date_str: str, metadata: Dict[str, Any]):
    """Guarda o actualiza el archivo meta.json del comercio y fecha."""
    target_dir = os.path.join(RAW_DIR, comercio_slug, date_str)
    os.makedirs(target_dir, exist_ok=True)
    meta_path = os.path.join(target_dir, "meta.json")

    existing_meta = {}
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                existing_meta = json.load(f)
        except Exception:
            existing_meta = {}

    existing_meta.update(metadata)
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(existing_meta, f, ensure_ascii=False, indent=2)


def load_raw_backup(comercio_slug: str, date_str: Optional[str] = None) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    Carga todos los archivos .json.gz correspondientes al comercio y fecha indicada desde raw/.
    Une automáticamente las particiones y retorna: (lista_productos_crudos, metadata)
    """
    comercio_dir = os.path.join(RAW_DIR, comercio_slug)
    if not os.path.exists(comercio_dir):
        return [], {}

    available_dates = sorted([d for d in os.listdir(comercio_dir) if os.path.isdir(os.path.join(comercio_dir, d))], reverse=True)
    if not available_dates:
        return [], {}

    if date_str:
        if date_str not in available_dates:
            return [], {}
        selected_date = date_str
    else:
        selected_date = available_dates[0]

    target_dir = os.path.join(comercio_dir, selected_date)
    if not os.path.exists(target_dir):
        return [], {}

    meta_path = os.path.join(target_dir, "meta.json")
    meta_data = {}
    if os.path.exists(meta_path):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta_data = json.load(f)
        except Exception:
            meta_data = {}

    all_raw_items = []
    seen_product_ids = set()

    # Buscar todos los .json.gz ordenadamente
    gz_files = sorted([f for f in os.listdir(target_dir) if f.endswith(".json.gz") and not f.endswith(".html.gz")])
    for f in gz_files:
        filepath = os.path.join(target_dir, f)
        with gzip.open(filepath, "rt", encoding="utf-8") as gz:
            try:
                items = json.load(gz)
                if isinstance(items, list):
                    for item in items:
                        pid = str(item.get("productId") or "")
                        if pid and pid in seen_product_ids:
                            continue
                        if pid:
                            seen_product_ids.add(pid)
                        all_raw_items.append(item)
            except Exception as e:
                print(f"[WARN] Error leyendo archivo {filepath}: {e}")

    return all_raw_items, meta_data


# =====================================================================
# MOTOR DE PETICIONES HTTP DIRECTAS
# =====================================================================

def fetch_json_vtex(url: str, session: requests.Session) -> Tuple[List[Dict[str, Any]], Optional[int], str]:
    """
    Ejecuta una petición GET a un endpoint VTEX con verificación SSL,
    reintentos y backoff. Captura el timestamp exacto de la petición y el total de resources.
    """
    for attempt in range(MAX_RETRIES):
        request_timestamp = get_current_iso_timestamp()
        try:
            resp = session.get(url, headers=DEFAULT_HEADERS, timeout=12, verify=get_ssl_verify_bundle())
            if resp.status_code in (200, 206):
                res_hdr = resp.headers.get("resources")
                total = None
                if res_hdr and "/" in res_hdr:
                    try:
                        total = int(res_hdr.split("/")[-1])
                    except ValueError:
                        pass
                data = resp.json()
                return (data if isinstance(data, list) else []), total, request_timestamp
            elif resp.status_code == 404:
                return [], 0, request_timestamp
            else:
                resp.raise_for_status()
        except Exception as e:
            if attempt == MAX_RETRIES - 1:
                print(f"[ERROR] Falló consulta a {url}: {e}")
                raise
            time.sleep(BACKOFF_FACTOR * (attempt + 1))

    return [], None, get_current_iso_timestamp()


# =====================================================================
# TRANSFORMACIÓN, LIMPIEZA Y HOMOLOGACIÓN DE OBSERVACIONES
# =====================================================================

def transform_raw_product(
    product: Dict[str, Any],
    comercio_nombre: str,
    ejecucion_id: str,
    timestamp_consulta: str
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    Transforma un producto crudo de VTEX en observaciones homogéneas.
    Separa texto original de campos normalizados.
    Registra productos descartados si no pertenecen al alcance.
    """
    observations = []
    descartados = []

    nombre_original = (product.get("productName") or "").strip()
    brand_orig = product.get("brand")
    marca_original = brand_orig.strip() if brand_orig and brand_orig.strip().lower() not in ["sin marca", "genérica", "generica", ""] else None
    
    categories = product.get("categories") or []
    categoria_original = categories[0] if categories else ""
    product_id_comercio = str(product.get("productId") or "")
    url = product.get("link") or ""
    descripcion_original = (product.get("description") or "").strip()

    # Ficha técnica / especificaciones originales
    specs = {}
    for spec_name in product.get("allSpecifications", []):
        val = product.get(spec_name)
        if val:
            specs[spec_name] = val[0] if isinstance(val, list) and len(val) == 1 else val
    ficha_tecnica_original = json.dumps(specs, ensure_ascii=False) if specs else None

    # Extraer contenido de especificaciones
    specs_content = ""
    for spec_k in ["Contenido", "Contenido Neto", "Peso del Producto"]:
        if product.get(spec_k):
            val = product[spec_k]
            specs_content = val[0] if isinstance(val, list) and val else str(val)
            break
    contenido_texto_original = specs_content or nombre_original

    # Subcategoría derivada de la categoría original
    subcat_raw = categoria_original.strip("/").split("/")[-1] if categoria_original else "Aseo del Hogar"

    # Verificación de alcance
    in_scope, motivo_descarte = check_product_scope(nombre_original, subcat_raw, descripcion_original)
    if not in_scope:
        descartados.append({
            "comercio": comercio_nombre,
            "ejecucion_id": ejecucion_id,
            "sku": product_id_comercio,
            "nombre": nombre_original,
            "categoria_original": categoria_original,
            "motivo": motivo_descarte
        })
        return [], descartados

    # Parseo estandarizado de contenido y unidad
    cnt_total, u_base, n_unidades = parse_content_and_unit(f"{nombre_original} {specs_content}")

    # Procesar SKUs / variantes
    items = product.get("items", [])
    for item in items:
        sku = str(item.get("itemId") or product_id_comercio)
        ean_raw = str(item.get("ean") or "").strip()
        ean = ean_raw if (ean_raw and len(ean_raw) >= 8 and not ean_raw.startswith("0000")) else None
        item_name = (item.get("name") or nombre_original).strip()

        price_actual = None
        price_antes = None
        es_promocion = None

        sellers = item.get("sellers") or []
        if sellers:
            comm = sellers[0].get("commertialOffer") or {}
            p_val = comm.get("Price")
            l_val = comm.get("ListPrice")

            if p_val is not None and float(p_val) > 0:
                price_actual = float(p_val)
            if l_val is not None and float(l_val) > 0:
                price_antes = float(l_val)

            if price_actual is not None and price_antes is not None:
                es_promocion = 1 if price_actual < price_antes else 0

        obs = {
            "comercio": comercio_nombre,
            "sku": sku,
            "ean": ean,
            "product_id_comercio": product_id_comercio,
            "nombre_original": nombre_original,
            "descripcion_original": descripcion_original or None,
            "ficha_tecnica_original": ficha_tecnica_original,
            "marca_original": marca_original,
            "categoria_original": categoria_original,
            "url": url,
            "precio_actual": price_actual,
            "precio_antes": price_antes,
            "es_promocion": es_promocion,
            "contenido_texto_original": contenido_texto_original,
            "fecha_hora_consulta": timestamp_consulta,
            "ejecucion_id": ejecucion_id,
            # Campos estandarizados
            "nombre_estandar": nombre_original,
            "marca_estandar": marca_original,
            "subcategoria_estandar": subcat_raw,
            "contenido_total": cnt_total,
            "unidad_base": u_base,
            "unidades_por_paquete": n_unidades
        }
        observations.append(obs)

    return observations, descartados


# =====================================================================
# FUNCIONES ESPECÍFICAS DE RECOLECCIÓN POR COMERCIO
# =====================================================================

def _scrape_comercio_subcategorias(
    comercio_nombre: str,
    comercio_slug: str,
    base_endpoint: str,
    subcategorias: List[Dict[str, str]],
    ejecucion_id: str,
    from_raw: bool = False,
    fecha_offline: Optional[str] = None
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], int, int, str]:
    """
    Función interna genérica para extraer todas las subcategorías homologadas de un comercio.
    Garantiza cobertura completa sin topes arbitrarios.
    """
    all_observations = []
    all_descartados = []
    total_sitio_acumulado = 0
    total_obtenido_antes_filtrar = 0

    if from_raw:
        raw_items, meta_info = load_raw_backup(comercio_slug, fecha_offline)
        if not raw_items and not meta_info:
            return [], [], 0, 0, "Sin datos crudos para esta fecha."

        total_sitio_acumulado = meta_info.get("total_sitio", len(raw_items))
        total_obtenido_antes_filtrar = meta_info.get("total_obtenido_bruto", len(raw_items))
        fecha_meta = meta_info.get("fecha_hora_captura", get_current_iso_timestamp())
        eid_to_use = meta_info.get("ejecucion_id") or ejecucion_id
        nota_meta = meta_info.get("nota")

        for prod in raw_items:
            obs_list, desc_list = transform_raw_product(prod, comercio_nombre, eid_to_use, fecha_meta)
            all_observations.extend(obs_list)
            all_descartados.extend(desc_list)

        if nota_meta:
            nota = nota_meta
        elif total_sitio_acumulado > 0 and total_obtenido_antes_filtrar < total_sitio_acumulado:
            nota = f"Extracción offline parcial ({len(all_observations)} observaciones válidas de {total_obtenido_antes_filtrar} brutos; truncada respecto a {total_sitio_acumulado} del catálogo)."
        else:
            nota = f"Extracción completa ({len(all_observations)} observaciones válidas, {len(all_descartados)} descartados de {total_sitio_acumulado} catálogo real)."

        return all_observations, all_descartados, total_sitio_acumulado, total_obtenido_antes_filtrar, nota

    # Modo En Línea: recorrer cada subcategoría homologada
    session = requests.Session()
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    all_raw_collected = []
    subcat_meta = {}

    for subcat in subcategorias:
        subcat_id = subcat["id"]
        subcat_path = subcat["path"]
        subcat_url = f"{base_endpoint}/{subcat_path}"

        # Obtener primera página y total de la subcategoría
        first_page, total_subcat, ts_first = fetch_json_vtex(f"{subcat_url}?_from=0&_to={PAGE_SIZE - 1}", session)
        subcat_items = list(first_page)
        target_subcat_total = total_subcat or len(first_page)
        total_sitio_acumulado += target_subcat_total

        offset = PAGE_SIZE
        while offset < target_subcat_total:
            to_idx = min(offset + PAGE_SIZE - 1, target_subcat_total - 1)
            page_items, _, _ = fetch_json_vtex(f"{subcat_url}?_from={offset}&_to={to_idx}", session)
            if not page_items:
                break
            subcat_items.extend(page_items)
            offset += PAGE_SIZE
            time.sleep(0.2)

        # Guardar copia cruda particionada < 50 MB
        save_raw_chunks(comercio_slug, date_str, subcat_id, subcat_items)
        subcat_meta[subcat_id] = {
            "url": subcat_url,
            "total_sitio": target_subcat_total,
            "items_obtenidos": len(subcat_items),
            "timestamp": ts_first
        }
        all_raw_collected.extend(subcat_items)

    # Deduplicar por productId de catálogo
    seen_pids = set()
    dedup_raw = []
    for p in all_raw_collected:
        pid = str(p.get("productId") or "")
        if pid and pid in seen_pids:
            continue
        if pid:
            seen_pids.add(pid)
        dedup_raw.append(p)

    total_obtenido_antes_filtrar = len(dedup_raw)

    # Guardar metadata general
    meta_general = {
        "ejecucion_id": ejecucion_id,
        "fecha_hora_captura": get_current_iso_timestamp(),
        "total_sitio": total_sitio_acumulado,
        "total_obtenido_bruto": total_obtenido_antes_filtrar,
        "subcategorias": subcat_meta
    }
    save_metadata(comercio_slug, date_str, meta_general)

    # Transformar a observaciones y descartados
    now_ts = get_current_iso_timestamp()
    for prod in dedup_raw:
        obs_list, desc_list = transform_raw_product(prod, comercio_nombre, ejecucion_id, now_ts)
        all_observations.extend(obs_list)
        all_descartados.extend(desc_list)

    nota = f"Extracción completa por subcategorías homologadas. {len(all_observations)} observaciones válidas, {len(all_descartados)} descartados."
    return all_observations, all_descartados, total_sitio_acumulado, total_obtenido_antes_filtrar, nota


def scrape_olimpica(ejecucion_id: str, from_raw: bool = False, fecha_offline: Optional[str] = None):
    """Extracción de Supertiendas Olímpica por subcategorías homologadas."""
    return _scrape_comercio_subcategorias(
        comercio_nombre="Olímpica",
        comercio_slug="Olimpica",
        base_endpoint="https://www.olimpica.com/api/catalog_system/pub/products/search",
        subcategorias=CATEGORIAS_EQUIVALENTES["Olimpica"]["incluidas"],
        ejecucion_id=ejecucion_id,
        from_raw=from_raw,
        fecha_offline=fecha_offline
    )


def scrape_jumbo(ejecucion_id: str, from_raw: bool = False, fecha_offline: Optional[str] = None):
    """Extracción de Tiendas Jumbo (Cencosud) por subcategorías homologadas."""
    return _scrape_comercio_subcategorias(
        comercio_nombre="Jumbo",
        comercio_slug="Jumbo",
        base_endpoint="https://www.tiendasjumbo.co/api/catalog_system/pub/products/search",
        subcategorias=CATEGORIAS_EQUIVALENTES["Jumbo"]["incluidas"],
        ejecucion_id=ejecucion_id,
        from_raw=from_raw,
        fecha_offline=fecha_offline
    )


def scrape_exito(ejecucion_id: str, from_raw: bool = False, fecha_offline: Optional[str] = None):
    """Extracción de Almacenes Éxito por subcategorías homologadas."""
    return _scrape_comercio_subcategorias(
        comercio_nombre="Éxito",
        comercio_slug="Exito",
        base_endpoint="https://www.exito.com/io/api/catalog_system/pub/products/search",
        subcategorias=CATEGORIAS_EQUIVALENTES["Exito"]["incluidas"],
        ejecucion_id=ejecucion_id,
        from_raw=from_raw,
        fecha_offline=fecha_offline
    )


# =====================================================================
# ESQUEMA DE BASE DE DATOS SQLITE Y MIGRACIÓN
# =====================================================================

def init_database(db_path: str = DB_PATH):
    """Crea el esquema SQLite corregido y normalizado."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("PRAGMA foreign_keys = ON;")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS comercios (
        comercio_id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE NOT NULL,
        plataforma TEXT,
        url_base TEXT
    )""")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS ejecuciones (
        ejecucion_id TEXT PRIMARY KEY,
        comercio_id INTEGER NOT NULL,
        fecha_hora_inicio TEXT NOT NULL,
        fecha_hora_fin TEXT,
        registros_obtenidos INTEGER NOT NULL,
        registros_con_precio INTEGER,
        total_sitio INTEGER,
        estado TEXT NOT NULL CHECK(estado IN ('completa', 'parcial', 'fallida')),
        nota TEXT,
        FOREIGN KEY (comercio_id) REFERENCES comercios(comercio_id)
    )""")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS productos (
        producto_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ean TEXT UNIQUE,
        nombre_estandar TEXT NOT NULL,
        marca_estandar TEXT,
        subcategoria_estandar TEXT,
        variante TEXT,
        contenido_total REAL,
        unidad_base TEXT,
        unidades_por_paquete INTEGER DEFAULT 1,
        concentracion TEXT,
        es_comparable INTEGER DEFAULT 0
    )""")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS anuncios (
        anuncio_id INTEGER PRIMARY KEY AUTOINCREMENT,
        comercio_id INTEGER NOT NULL,
        sku TEXT NOT NULL,
        ean TEXT,
        product_id_comercio TEXT,
        url TEXT,
        nombre_original TEXT NOT NULL,
        descripcion_original TEXT,
        ficha_tecnica_original TEXT,
        marca_original TEXT,
        categoria_original TEXT,
        contenido_texto_original TEXT,
        nombre_estandar TEXT,
        marca_estandar TEXT,
        subcategoria_estandar TEXT,
        contenido_total REAL,
        unidad_base TEXT,
        unidades_por_paquete INTEGER DEFAULT 1,
        producto_id INTEGER,
        comparable INTEGER DEFAULT 0,
        FOREIGN KEY (comercio_id) REFERENCES comercios(comercio_id),
        FOREIGN KEY (producto_id) REFERENCES productos(producto_id),
        UNIQUE(comercio_id, sku)
    )""")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS observaciones (
        observacion_id INTEGER PRIMARY KEY AUTOINCREMENT,
        anuncio_id INTEGER NOT NULL,
        ejecucion_id TEXT NOT NULL,
        precio_actual REAL,
        precio_antes REAL,
        es_promocion INTEGER,
        fecha_hora_consulta TEXT NOT NULL,
        FOREIGN KEY (anuncio_id) REFERENCES anuncios(anuncio_id),
        FOREIGN KEY (ejecucion_id) REFERENCES ejecuciones(ejecucion_id),
        UNIQUE(anuncio_id, fecha_hora_consulta)
    )""")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS descartados (
        descarte_id INTEGER PRIMARY KEY AUTOINCREMENT,
        comercio TEXT NOT NULL,
        ejecucion_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        nombre TEXT,
        categoria_original TEXT,
        motivo TEXT NOT NULL,
        fecha_descarte TEXT NOT NULL
    )""")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS correspondencia_rechazada (
        rechazo_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ean TEXT,
        nombre_referencia TEXT,
        marca_referencia TEXT,
        motivo TEXT NOT NULL,
        fecha_rechazo TEXT NOT NULL
    )""")

    # Índices para optimización
    cur.execute("CREATE INDEX IF NOT EXISTS idx_obs_ejecucion ON observaciones(ejecucion_id);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_anuncios_producto ON anuncios(producto_id);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_anuncios_ean ON anuncios(ean);")

    # Inicializar comercios oficiales
    cur.executemany("""
    INSERT OR IGNORE INTO comercios (nombre, plataforma, url_base) VALUES (?, ?, ?)
    """, [
        ("Éxito", "VTEX FastStore", "https://www.exito.com"),
        ("Olímpica", "VTEX", "https://www.olimpica.com"),
        ("Jumbo", "VTEX", "https://www.tiendasjumbo.co")
    ])

    conn.commit()
    conn.close()


def standardize_brand(brand: Optional[str], name: str) -> Optional[str]:
    """Estandariza la marca a partir de la marca original y el nombre del producto."""
    n_lower = name.lower()
    b_lower = (brand or "").lower().strip()

    if not b_lower or b_lower in ["generica", "genérica", "sin marca", "no definida", "desconocida", "none"]:
        b_clean = None
    else:
        b_clean = brand.strip()

    if "scotch-brite" in n_lower or "scotch brite" in n_lower or "scotchbrite" in n_lower or b_lower in ["scotch-brite", "scotch brite", "3m"]:
        return "Scotch Brite"
    if "task" in n_lower or b_lower in ["task", "ilko"]:
        return "Task"
    if "fabuloso" in n_lower:
        return "Fabuloso"
    if "axion" in n_lower or "axión" in n_lower:
        return "Axion"
    if "ariel" in n_lower:
        return "Ariel"
    if "clorox" in n_lower:
        return "Clorox"
    if "ajax" in n_lower:
        return "Ajax"
    if "varsol" in n_lower:
        return "Varsol"
    if "harpic" in n_lower:
        return "Harpic"
    if "binner" in n_lower:
        return "Binner"
    if "tergo" in n_lower:
        return "Tergo"
    if "blanca nieves" in n_lower:
        return "Blanca Nieves"
    if "1a" in n_lower:
        return "1A"
    if "dersa" in n_lower:
        return "Dersa"
    if "top" in n_lower and "terra" in n_lower:
        return "Top Terra"
    if "beckmann" in n_lower or "beckmann" in b_lower:
        return "Dr. Beckmann"
    if "mas color" in n_lower or "mas color" in b_lower or b_lower == "mas":
        return "Mas Color"
    if "easy off" in n_lower or "easy off" in b_lower:
        return "Easy Off"
    if "loza crem" in n_lower or "lozacrem" in n_lower or "loza crem" in b_lower or "lozacrem" in b_lower:
        return "Lozacrem"
    if "aromax" in n_lower or "aromax" in b_lower:
        return "Aromax"
    if "coco varela" in n_lower or b_lower in ["coco", "coco varela"]:
        return "Coco Varela"
    if "ecoazul" in n_lower or "azul k" in b_lower or "ecoazul" in b_lower:
        return "Ecoazul"
    if "eterna" in n_lower or "eterna" in b_lower:
        return "Eterna"
    if "bufalo" in n_lower or "búfalo" in n_lower or "bufalo" in b_lower:
        return "Bufalo"
    if "persil" in n_lower or "persil" in b_lower:
        return "Persil"

    return b_clean


# =====================================================================
# CORRESPONDENCIA AUTOMÁTICA DE PRODUCTOS COMPARABLES
# =====================================================================

def norm_brand_str(b: Optional[str]) -> str:
    """Normaliza texto de marca para comparación robusta (sin signos, minúsculas)."""
    if not b:
        return ""
    b_clean = re.sub(r"[^\w\s]", "", b.lower())
    return re.sub(r"\s+", " ", b_clean).strip()


def construir_correspondencia(db_path: str = DB_PATH) -> int:
    """
    Agrupa anuncios de diferentes comercios por EAN idéntico.
    Marca es_comparable=1 solo si:
      - El EAN está presente en los 3 comercios.
      - contenido_total, unidad_base y marca coinciden exactamente entre los 3 comercios (contenido NULL no cuenta).
      - unidades_por_paquete coincide entre los 3 comercios.
      - Si un EAN tiene múltiples SKU por comercio y ejecución, desambigua por contenido/unidades.
        Si no es desambiguable, se excluye de comparables.
    Registra los productos candidatos rechazados con motivo en la tabla 'correspondencia_rechazada'.
    Garantiza estricta idempotencia y exactamente 1 observación por producto, comercio y ejecución.
    """
    init_database(db_path)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # 1. Estandarizar marca_estandar en todos los anuncios
    cur.execute("SELECT anuncio_id, marca_original, nombre_original FROM anuncios")
    for aid, m_orig, n_orig in cur.fetchall():
        m_est = standardize_brand(m_orig, n_orig)
        cur.execute("UPDATE anuncios SET marca_estandar = ? WHERE anuncio_id = ?", (m_est, aid))

    # 2. Resetear banderas de comparabilidad y relaciones previas para evitar desfaces
    cur.execute("UPDATE productos SET es_comparable = 0")
    cur.execute("UPDATE anuncios SET comparable = 0, producto_id = NULL")
    cur.execute("DELETE FROM correspondencia_rechazada")

    now_iso = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S-05:00")

    # 3. Identificar EANs candidatos presentes en los 3 comercios
    q_candidates = """
    SELECT ean
    FROM anuncios
    WHERE ean IS NOT NULL AND ean != '' AND length(ean) >= 8
    GROUP BY ean
    HAVING COUNT(DISTINCT comercio_id) = 3
    """
    cur.execute(q_candidates)
    candidatos_ean = [r[0] for r in cur.fetchall()]

    accepted = []
    rejected = []

    for ean in candidatos_ean:
        cur.execute("""
            SELECT anuncio_id, comercio_id, sku, nombre_original, nombre_estandar, 
                   marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete
            FROM anuncios
            WHERE ean = ?
        """, (ean,))
        anuncios = cur.fetchall()

        ref_nombre = anuncios[0][4] or anuncios[0][3]
        ref_marca = anuncios[0][5]

        # Verificar que los 3 comercios posean contenido cuantificable (> 0) y unidad no nula
        by_com = {1: [], 2: [], 3: []}
        for a in anuncios:
            by_com[a[1]].append(a)

        com_valid = {}
        for cid in [1, 2, 3]:
            com_valid[cid] = [
                a for a in by_com[cid] 
                if a[7] is not None and a[7] > 0 and a[8] is not None and a[8] != ""
            ]

        if any(len(com_valid[cid]) == 0 for cid in [1, 2, 3]):
            rejected.append((ean, ref_nombre, ref_marca, "Al menos un comercio tiene contenido NULL o no cuantificable"))
            continue

        # Especificaciones posibles por comercio: (marca_norm, contenido_total, unidad_base, unidades_por_paquete)
        possible_specs = {}
        for cid in [1, 2, 3]:
            specs = set()
            for a in com_valid[cid]:
                b_norm = norm_brand_str(a[5])
                u_norm = (a[8] or "").lower().strip()
                specs.add((b_norm, a[7], u_norm, a[9] or 1))
            possible_specs[cid] = specs

        common = possible_specs[1] & possible_specs[2] & possible_specs[3]
        if not common:
            cnts = set(a[7] for a in anuncios if a[7] is not None)
            units = set((a[8] or "").lower().strip() for a in anuncios if a[8])
            packs = set(a[9] or 1 for a in anuncios if a[9] is not None)
            brands = set(norm_brand_str(a[5]) for a in anuncios if a[5])
            if len(units) > 1 or len(cnts) > 1 or len(packs) > 1:
                motivo = f"Contenido o unidad distinta entre comercios (cantidades: {cnts}, unidades: {units}, paquetes: {packs})"
            elif len(brands) > 1:
                motivo = f"Marca distinta entre comercios: {brands}"
            else:
                motivo = "Especificaciones de producto no coincidentes entre los 3 comercios"
            rejected.append((ean, ref_nombre, ref_marca, motivo))
            continue

        if len(common) > 1:
            rejected.append((ean, ref_nombre, ref_marca, "Múltiples especificaciones comunes ambiguas"))
            continue

        target_brand_norm, target_cnt, target_unit, target_pack = list(common)[0]

        # Desambiguación por comercio y ejecución
        chosen_anuncio_per_com = {}
        ambiguous = False
        ambig_reason = ""

        for cid in [1, 2, 3]:
            matching = [
                a for a in com_valid[cid]
                if norm_brand_str(a[5]) == target_brand_norm
                and a[7] == target_cnt
                and (a[8] or "").lower().strip() == target_unit
                and (a[9] or 1) == target_pack
            ]

            if not matching:
                ambiguous = True
                ambig_reason = f"Comercio {cid} no tiene anuncio que coincida exactamente con la especificación objetivo"
                break

            # Si hay múltiples anuncios que coinciden, verificar si coexisten observaciones en la misma ejecución
            if len(matching) > 1:
                matching_aids = [a[0] for a in matching]
                placeholders = ",".join("?" * len(matching_aids))
                q_exec_check = f"""
                    SELECT ejecucion_id, COUNT(DISTINCT anuncio_id) as cnt
                    FROM observaciones
                    WHERE anuncio_id IN ({placeholders})
                    GROUP BY ejecucion_id
                    HAVING cnt > 1
                """
                cur.execute(q_exec_check, matching_aids)
                multi_in_exec = cur.fetchall()
                if multi_in_exec:
                    ambiguous = True
                    ambig_reason = f"Múltiples SKU en comercio {cid} con idéntico contenido/unidades en la misma ejecución ({multi_in_exec[0][0]}); no desambiguable"
                    break
                else:
                    # Si no coexisten en la misma ejecución, seleccionar determinísticamente el de menor anuncio_id / sku
                    chosen_anuncio_per_com[cid] = matching[0]
            else:
                chosen_anuncio_per_com[cid] = matching[0]

        if ambiguous:
            rejected.append((ean, ref_nombre, ref_marca, ambig_reason))
            continue

        rep = chosen_anuncio_per_com[1]
        rep_brand = rep[5] or ref_marca
        rep_name = rep[4] or ref_nombre
        rep_subcat = rep[6] or anuncios[0][6]

        accepted.append((ean, rep_name, rep_brand, rep_subcat, target_cnt, target_unit, target_pack, chosen_anuncio_per_com))

    # Guardar registros rechazados con su motivo de auditoría
    for ean_r, nom_r, mar_r, mot_r in rejected:
        cur.execute("""
            INSERT INTO correspondencia_rechazada (ean, nombre_referencia, marca_referencia, motivo, fecha_rechazo)
            VALUES (?, ?, ?, ?, ?)
        """, (ean_r, nom_r, mar_r, mot_r, now_iso))

    # Actualizar catálogo canonical y asociar exactamente 1 anuncio por comercio
    for a in accepted:
        ean, name, brand, subcat, cnt, unit, pack, chosen_dict = a
        cur.execute("""
            INSERT INTO productos (ean, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete, es_comparable)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ON CONFLICT(ean) DO UPDATE SET
                nombre_estandar = excluded.nombre_estandar,
                marca_estandar = excluded.marca_estandar,
                subcategoria_estandar = excluded.subcategoria_estandar,
                contenido_total = excluded.contenido_total,
                unidad_base = excluded.unidad_base,
                unidades_por_paquete = excluded.unidades_por_paquete,
                es_comparable = 1
        """, (ean, name, brand, subcat, cnt, unit, pack))

        cur.execute("SELECT producto_id FROM productos WHERE ean = ?", (ean,))
        pid = cur.fetchone()[0]

        for cid, an_tuple in chosen_dict.items():
            aid = an_tuple[0]
            cur.execute("""
                UPDATE anuncios
                SET producto_id = ?, comparable = 1
                WHERE anuncio_id = ?
            """, (pid, aid))

    conn.commit()
    conn.close()
    return len(accepted)


# =====================================================================
# FUNCIÓN GENERAL DE RECOLECCIÓN COMPLETA
# =====================================================================

def get_available_raw_dates() -> List[str]:
    """Retorna todas las fechas disponibles en raw/ en orden cronológico ascendente."""
    fechas = set()
    if os.path.exists(RAW_DIR):
        for cdir in os.listdir(RAW_DIR):
            cpath = os.path.join(RAW_DIR, cdir)
            if os.path.isdir(cpath) and cdir != "robots":
                for d in os.listdir(cpath):
                    if os.path.isdir(os.path.join(cpath, d)) and re.match(r"^\d{4}-\d{2}-\d{2}$", d):
                        fechas.add(d)
    return sorted(list(fechas))


def _ejecutar_recoleccion_una_fecha(
    from_raw: bool = False,
    fecha_offline: Optional[str] = None,
    db_path: str = DB_PATH
) -> str:
    """
    Ejecuta la recolección para una fecha o en vivo en los 3 comercios.
    """
    init_database(db_path)
    session_id = f"EXEC_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    comercio_ids = {}
    for cid, cname in cur.execute("SELECT comercio_id, nombre FROM comercios"):
        comercio_ids[cname] = cid

    scrapers = [
        ("Olímpica", scrape_olimpica),
        ("Jumbo", scrape_jumbo),
        ("Éxito", scrape_exito)
    ]

    print(f"\n=======================================================")
    print(f" INICIANDO RECOLECCIÓN (Sesión: {session_id})")
    print(f" Modo Sin Conexión: {from_raw} | Fecha Ref: {fecha_offline or 'Más reciente'}")
    print(f"=======================================================")

    for cname, scraper_fn in scrapers:
        ejecucion_id_propuesto = f"{session_id}_{cname.upper()}"
        fecha_inicio_propuesta = get_current_iso_timestamp()
        cid = comercio_ids[cname]

        print(f"\n-> Procesando {cname}...")
        try:
            obs_list, desc_list, total_sitio, total_obtenido, nota = scraper_fn(
                ejecucion_id=ejecucion_id_propuesto,
                from_raw=from_raw,
                fecha_offline=fecha_offline
            )

            # Si es modo offline y no hay capturas de este comercio para esta fecha, omitir limpiamente
            if from_raw and not obs_list and not desc_list and total_sitio == 0:
                print(f"   [OMITIR] {cname}: Sin datos crudos para la fecha {fecha_offline}. Omitiendo.")
                continue

            # Reutilizar ejecucion_id y timestamps originales en modo offline si provienen de meta.json
            if from_raw and obs_list:
                ejecucion_id = obs_list[0]["ejecucion_id"]
                fecha_inicio = obs_list[0]["fecha_hora_consulta"]
                fecha_fin = fecha_inicio
            elif from_raw and desc_list:
                ejecucion_id = desc_list[0]["ejecucion_id"]
                fecha_inicio = fecha_inicio_propuesta
                fecha_fin = fecha_inicio
            else:
                ejecucion_id = ejecucion_id_propuesto
                fecha_inicio = fecha_inicio_propuesta
                fecha_fin = get_current_iso_timestamp()

            # Si ya existe en ejecuciones, omitir (idempotente)
            cur.execute("SELECT 1 FROM ejecuciones WHERE ejecucion_id = ?", (ejecucion_id,))
            if cur.fetchone():
                print(f"   [OMITIR] {cname}: Ejecución {ejecucion_id} ya existe en la base. Omitiendo.")
                continue

            # Determinar estado
            if from_raw:
                if total_sitio > 0 and total_obtenido < total_sitio:
                    estado = "parcial"
                elif total_obtenido > 0:
                    estado = "completa"
                else:
                    estado = "fallida"
            else:
                total_bruto = len(obs_list) + len(desc_list)
                if total_sitio > 0 and total_bruto >= total_sitio:
                    estado = "completa"
                elif total_bruto > 0:
                    estado = "parcial"
                else:
                    estado = "fallida"

            con_precio = sum(1 for o in obs_list if o.get("precio_actual") is not None and o.get("precio_actual") > 0)

            # Registrar en tabla ejecuciones
            cur.execute("""
            INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, fecha_hora_fin, registros_obtenidos, registros_con_precio, total_sitio, estado, nota)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (ejecucion_id, cid, fecha_inicio, fecha_fin, len(obs_list), con_precio, total_sitio, estado, nota))

            # Registrar descartados
            for d in desc_list:
                cur.execute("""
                INSERT INTO descartados (comercio, ejecucion_id, sku, nombre, categoria_original, motivo, fecha_descarte)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (d["comercio"], d["ejecucion_id"], d["sku"], d["nombre"], d["categoria_original"], d["motivo"], fecha_fin))

            # Insertar anuncios preservando texto original
            for o in obs_list:
                cur.execute("""
                INSERT INTO anuncios (
                    comercio_id, sku, ean, product_id_comercio, url,
                    nombre_original, descripcion_original, ficha_tecnica_original,
                    marca_original, categoria_original, contenido_texto_original,
                    nombre_estandar, marca_estandar, subcategoria_estandar,
                    contenido_total, unidad_base, unidades_por_paquete
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(comercio_id, sku) DO UPDATE SET
                    ean = COALESCE(excluded.ean, anuncios.ean),
                    url = excluded.url,
                    nombre_estandar = excluded.nombre_estandar,
                    marca_estandar = COALESCE(excluded.marca_estandar, anuncios.marca_estandar),
                    subcategoria_estandar = excluded.subcategoria_estandar,
                    contenido_total = COALESCE(excluded.contenido_total, anuncios.contenido_total),
                    unidad_base = COALESCE(excluded.unidad_base, anuncios.unidad_base),
                    unidades_por_paquete = excluded.unidades_por_paquete
                """, (
                    cid, o["sku"], o["ean"], o["product_id_comercio"], o["url"],
                    o["nombre_original"], o["descripcion_original"], o["ficha_tecnica_original"],
                    o["marca_original"], o["categoria_original"], o["contenido_texto_original"],
                    o["nombre_estandar"], o["marca_estandar"], o["subcategoria_estandar"],
                    o["contenido_total"], o["unidad_base"], o["unidades_por_paquete"]
                ))

                cur.execute("SELECT anuncio_id FROM anuncios WHERE comercio_id = ? AND sku = ?", (cid, o["sku"]))
                aid = cur.fetchone()[0]

                # Insertar observación sin sobrescribir
                cur.execute("""
                INSERT OR IGNORE INTO observaciones (anuncio_id, ejecucion_id, precio_actual, precio_antes, es_promocion, fecha_hora_consulta)
                VALUES (?, ?, ?, ?, ?, ?)
                """, (aid, o["ejecucion_id"], o["precio_actual"], o["precio_antes"], o["es_promocion"], o["fecha_hora_consulta"]))

            conn.commit()
            print(f"   [OK] {cname}: {len(obs_list)} observaciones guardadas. Estado: '{estado}'.")

        except Exception as e:
            print(f"   [FALLO] {cname}: {e}")
            cur.execute("""
            INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, fecha_hora_fin, registros_obtenidos, registros_con_precio, total_sitio, estado, nota)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (ejecucion_id_propuesto, cid, fecha_inicio_propuesta, get_current_iso_timestamp(), 0, 0, 0, "fallida", str(e)))
            conn.commit()

    conn.close()
    return session_id


def ejecutar_recoleccion_completa(
    from_raw: bool = False,
    fecha_offline: Optional[str] = None,
    db_path: str = DB_PATH
) -> str:
    """
    Ejecuta la recolección en los 3 comercios (en línea o sin conexión).
    Si from_raw=True y fecha_offline es None, procesa TODAS las fechas de raw/ en orden cronológico.
    """
    if from_raw and not fecha_offline:
        fechas = get_available_raw_dates()
        last_session = ""
        for f in fechas:
            last_session = _ejecutar_recoleccion_una_fecha(from_raw=True, fecha_offline=f, db_path=db_path)
        n_comp = construir_correspondencia(db_path)
        print(f"\n[CORRESPONDENCIA GENERAL] {n_comp} productos homologados y comparables en los 3 comercios.")
        print(f"=======================================================\n")
        return last_session
    else:
        last_session = _ejecutar_recoleccion_una_fecha(from_raw=from_raw, fecha_offline=fecha_offline, db_path=db_path)
        n_comp = construir_correspondencia(db_path)
        print(f"\n[CORRESPONDENCIA] {n_comp} productos homologados y comparables en los 3 comercios.")
        print(f"=======================================================\n")
        return last_session


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Scraper Taller 1 - Minería de Datos UNAL")
    parser.add_argument("--offline", action="store_true", help="Reprocesar en modo sin conexión desde raw/")
    parser.add_argument("--fecha", type=str, default=None, help="Fecha específica para modo offline (YYYY-MM-DD)")
    args = parser.parse_args()

    ejecutar_recoleccion_completa(from_raw=args.offline, fecha_offline=args.fecha)
