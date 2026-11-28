"""
Módulo de extracción y estandarización: scraper.py
Taller 2 - Minería de Datos - Comparador de precios de protectores solares

Este módulo es el mismo extractor del Taller 1 (API pública de catálogo VTEX que
usan los propios sitios para mostrar sus productos), con los ajustes del Taller 2:

- `recolectar_comercio()` es el punto de entrada por comercio que usa la
  aplicación (botón "Actualizar precios") y la línea de comandos. No escribe en
  la base: devuelve las observaciones estandarizadas y la ruta de la copia cruda.
  La validación está en validacion.py y la inserción en db.py.
- Se registra la disponibilidad que informa el sitio (commertialOffer.IsAvailable).
- Se normalizan las unidades de contenido a mL, g o unidad.
- Se corrigen las reglas de extracción de contenido y de pertenencia a la
  categoría señaladas en la revisión del Taller 1 (ver tabla `correcciones`).
- Buenas prácticas: agente de usuario identificable, pausa entre peticiones y
  número máximo de peticiones por comercio y ejecución.

Comercios: Bella Piel, Drogas La Rebaja y Locatel (mismos del Taller 1).
Droguerías Colsubsidio y Medipiel siguen excluidas por sus reglas de robots.txt.
"""

from __future__ import annotations

import gzip
import json
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

import requests

# Zona horaria oficial de Colombia (UTC-5)
TZ_COLOMBIA = timezone(timedelta(hours=-5))

# Carpeta del proyecto: todas las rutas son relativas a este archivo
BASE_DIR = Path(__file__).resolve().parent
RAW_DIR = BASE_DIR / "raw"

USER_AGENT = (
    "MineriaDeDatos-UNAL-Taller2/1.0 (proyecto academico; Universidad Nacional de Colombia; "
    "comparador de precios de protectores solares)"
)
HEADERS_DEFAULT = {
    "User-Agent": USER_AGENT,
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "es-CO,es;q=0.9",
}

PAUSA_SEGUNDOS = 1.0            # pausa entre peticiones a un mismo sitio
MAX_PETICIONES_POR_COMERCIO = 20  # límite de peticiones por comercio y ejecución
TIMEOUT_SEGUNDOS = 25
TAMANO_PAGINA = 50              # máximo permitido por la API de catálogo VTEX

# Configuración de los tres comercios (endpoints documentados en el README)
COMERCIOS: Dict[str, Dict[str, Any]] = {
    "Bella Piel": {
        "carpeta": "bellapiel",
        "base_url": "https://www.bellapiel.com.co",
        "subcategorias": ["proteccion-solar"],
        "is_fq": False,
        "subcategoria_defecto": "Dermocosmética / Protección Solar",
    },
    "La Rebaja": {
        "carpeta": "larebaja",
        "base_url": "https://www.larebajavirtual.com",
        "subcategorias": ["C:/5/35/", "C:/8/465/"],
        "is_fq": True,
        "subcategoria_defecto": "Farmacia / Protección Solar",
    },
    "Locatel": {
        "carpeta": "locatel",
        "base_url": "https://www.locatelcolombia.com",
        "subcategorias": ["C:/2/17/", "C:/1/8/55/"],
        "is_fq": True,
        "subcategoria_defecto": "Dermocosmética / Cuidado Solar",
    },
}

# =====================================================================
# CATÁLOGO DE PRODUCTOS COMPARABLES (sin cambios respecto al Taller 1)
# En Locatel se empareja estrictamente por EAN (items[].ean).
# =====================================================================
CATALOGO_COMPARABLES = [
    {
        "id_producto_comun": "ANTHELIOS_UVMUNE_400_50ML",
        "nombre_estandar": "La Roche-Posay Anthelios UVMune 400 Fluido Invisible FPS 50+",
        "marca_estandar": "La Roche-Posay",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 50 ml",
        "contenido_valor": 50.0,
        "contenido_unidad": "mL",
        "ean": "3337875797597",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "anthelios" in n.lower() and "uvmune" in n.lower() and "fluido" in n.lower() and "color" not in n.lower() and "oil" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "3337875797597" or ("anthelios" in n.lower() and "uv mune" in n.lower() and "color" not in n.lower() and "oil" not in n.lower()),
        }
    },
    {
        "id_producto_comun": "ANTHELIOS_UVMUNE_COLOR_50ML",
        "nombre_estandar": "La Roche-Posay Anthelios UVMune 400 Fluido con Color FPS 50+",
        "marca_estandar": "La Roche-Posay",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 50 ml",
        "contenido_valor": 50.0,
        "contenido_unidad": "mL",
        "ean": "3337875797641",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "anthelios" in n.lower() and "uvmune" in n.lower() and "color" in n.lower() and "oil" not in n.lower() and "gel" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "3337875797641" or ("anthelios" in n.lower() and "uv mune" in n.lower() and "color" in n.lower() and "oil" not in n.lower()),
        }
    },
    {
        "id_producto_comun": "CETAPHIL_SUN_KIDS_150ML",
        "nombre_estandar": "Cetaphil Sun Kids Loción Liposomal FPS 50+",
        "marca_estandar": "Cetaphil",
        "categoria_estandar": "Protector Infantil",
        "presentacion_estandar": "Frasco 150 ml",
        "contenido_valor": 150.0,
        "contenido_unidad": "mL",
        "ean": "7612076457430",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "cetaphil" in n.lower() and "kids" in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "7612076457430" or ("cetaphil" in n.lower() and "kids" in n.lower()),
        }
    },
    {
        "id_producto_comun": "CETAPHIL_SUN_GEL_LIGERO_100ML",
        "nombre_estandar": "Cetaphil Sun Gel Ligero FPS 50+",
        "marca_estandar": "Cetaphil",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 100 ml",
        "contenido_valor": 100.0,
        "contenido_unidad": "mL",
        "ean": "7612076457256",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "cetaphil" in n.lower() and "gel" in n.lower() and "ligero" in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "7612076457256" or ("cetaphil" in n.lower() and "gel" in n.lower() and "ligero" in n.lower()),
        }
    },
    {
        "id_producto_comun": "EUCERIN_HYDRO_FLUID_50ML",
        "nombre_estandar": "Eucerin Sun Hydro Protect Ultra-Light Fluid FPS 50+",
        "marca_estandar": "Eucerin",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 50 ml",
        "contenido_valor": 50.0,
        "contenido_unidad": "mL",
        "ean": "4005900994776",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "hydro fluid" in n.lower() and "tono" not in n.lower() and "kit" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "4005900994776" or ("hydro fluid" in n.lower() and "tono" not in n.lower()),
        }
    },
    {
        "id_producto_comun": "EUCERIN_PHOTOAGING_CONTROL_50ML",
        "nombre_estandar": "Eucerin Sun Photoaging Control FPS 50+",
        "marca_estandar": "Eucerin",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 50 ml",
        "contenido_valor": 50.0,
        "contenido_unidad": "mL",
        "ean": "4005900265227",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "eucerin" in n.lower() and ("photoaging" in n.lower() or "antiedad" in n.lower()) and "color" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "4005900265227" or ("eucerin" in n.lower() and "antiedad" in n.lower() and "color" not in n.lower()),
        }
    },
    {
        "id_producto_comun": "EUCERIN_PIGMENT_CONTROL_50ML",
        "nombre_estandar": "Eucerin Sun Pigment Control FPS 50+",
        "marca_estandar": "Eucerin",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 50 ml",
        "contenido_valor": 50.0,
        "contenido_unidad": "mL",
        "ean": "4005800241901",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "pigment control" in n.lower() and "tono" not in n.lower() and "color" not in n.lower() and "tinted" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "4005800241901" or ("antipigmento" in n.lower() and "tono" not in n.lower()),
        }
    },
    {
        "id_producto_comun": "EUCERIN_OIL_CONTROL_MEDIO_50ML",
        "nombre_estandar": "Eucerin Sun Gel-Crema Oil Control FPS 50+ Tono Medio",
        "marca_estandar": "Eucerin",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Frasco 50 ml",
        "contenido_valor": 50.0,
        "contenido_unidad": "mL",
        "ean": "4005900839633",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "oil control" in n.lower() and ("color medio" in n.lower() or "tono medio" in n.lower() or "medio" in n.lower()),
            "La Rebaja": lambda n, d, b, e: e == "4005900839633" or (("oil control" in n.lower() or "toque seco" in n.lower()) and "medio" in n.lower()),
        }
    },
    {
        "id_producto_comun": "UMBRELLA_URBAN_SPF50_50G",
        "nombre_estandar": "Umbrella Urban Fotoprotector FPS 50+",
        "marca_estandar": "Umbrella",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Tubo 50 g",
        "contenido_valor": 50.0,
        "contenido_unidad": "g",
        "ean": "7703281002451",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "umbrella" in n.lower() and "urban" in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "7703281002451" or "umbrella urban" in n.lower(),
        }
    },
    {
        "id_producto_comun": "UMBRELLA_ACQUA_SPF50_50G",
        "nombre_estandar": "Umbrella Acqua Fotoprotector FPS 50+",
        "marca_estandar": "Umbrella",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Tubo 50 g",
        "contenido_valor": 50.0,
        "contenido_unidad": "g",
        "ean": "7703281021551",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "umbrella" in n.lower() and "acqua" in n.lower() and "kit" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "7703281021551" or "umbrella acqua" in n.lower(),
        }
    },
    {
        "id_producto_comun": "SUNAID_EVOLUTION_SPF50_40G",
        "nombre_estandar": "Sunaid Evolution Protector Solar Gel FPS 50+",
        "marca_estandar": "Sunaid",
        "categoria_estandar": "Protector Facial",
        "presentacion_estandar": "Tubo 40 g",
        "contenido_valor": 40.0,
        "contenido_unidad": "g",
        "ean": "7707206270598",
        "reglas": {
            "Bella Piel": lambda n, d, b, e: "sunaid" in n.lower() and "evolution" in n.lower() and "color" not in n.lower(),
            "La Rebaja": lambda n, d, b, e: e == "7707206270598" or ("sunaid" in n.lower() and "evolution" in n.lower() and "color" not in n.lower()),
        }
    }
]


IDS_COMPARABLES = [c["id_producto_comun"] for c in CATALOGO_COMPARABLES]


def obtener_timestamp_colombia() -> str:
    """Fecha y hora actual de Colombia en formato ISO 8601."""
    return datetime.now(TZ_COLOMBIA).isoformat(timespec="seconds")


# =====================================================================
# 1. LIMPIEZA Y NORMALIZACIÓN
# =====================================================================
def limpiar_precio(valor: Any) -> Optional[float]:
    """
    Convierte un precio en texto o número a float en COP.
    "$ 12.900" -> 12900.0 ; "12.900,50" -> 12900.5 ; 0, "", None o texto sin dígitos -> None.
    En Colombia el punto separa miles y la coma separa decimales.
    """
    if valor is None or isinstance(valor, bool):
        return None
    if isinstance(valor, (int, float)):
        return float(valor) if valor > 0 else None
    texto = re.sub(r"[^\d.,]", "", str(valor))
    if not re.search(r"\d", texto):
        return None
    if "," in texto:
        entero, _, decimal = texto.rpartition(",")
        texto = entero.replace(".", "") + "." + decimal
    else:
        partes = texto.split(".")
        # "12.900" o "1.250.000": puntos de miles. "12.5": decimal.
        if len(partes) > 1 and all(len(p) == 3 for p in partes[1:]):
            texto = "".join(partes)
    try:
        numero = float(texto)
    except ValueError:
        return None
    return numero if numero > 0 else None


_FACTORES_UNIDAD = {
    "ml": (1.0, "mL"), "mililitro": (1.0, "mL"), "mililitros": (1.0, "mL"),
    "cc": (1.0, "mL"),
    "l": (1000.0, "mL"), "lt": (1000.0, "mL"), "litro": (1000.0, "mL"), "litros": (1000.0, "mL"),
    "g": (1.0, "g"), "gr": (1.0, "g"), "grs": (1.0, "g"), "gramo": (1.0, "g"), "gramos": (1.0, "g"),
    "kg": (1000.0, "g"),
    "mg": (0.001, "g"), "miligramo": (0.001, "g"), "miligramos": (0.001, "g"),
    "und": (1.0, "unidad"), "unid": (1.0, "unidad"), "unidad": (1.0, "unidad"),
    "unidades": (1.0, "unidad"), "u": (1.0, "unidad"),
}


def normalizar_unidad(valor: Optional[float], unidad: Optional[str]) -> Tuple[Optional[float], Optional[str]]:
    """
    Normaliza un contenido a una de tres unidades: mL, g o unidad.
    (1, "L") -> (1000.0, "mL"); (500, "mg") -> (0.5, "g"); (50, "Gr") -> (50.0, "g").
    Unidades desconocidas o valores no positivos -> (None, None).
    """
    if valor is None or unidad is None:
        return None, None
    try:
        valor = float(valor)
    except (TypeError, ValueError):
        return None, None
    if valor <= 0:
        return None, None
    clave = unidad.strip().lower().rstrip(".")
    if clave not in _FACTORES_UNIDAD:
        return None, None
    factor, unidad_norm = _FACTORES_UNIDAD[clave]
    return round(valor * factor, 4), unidad_norm


_PATRON_CONTENIDO = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(ml|mililitros?|cc|litros?|lt|l|kg|mg|miligramos?|grs|gr|gramos?|g|"
    r"unidades|unidad|unid|und)\b",
    re.IGNORECASE,
)


def extraer_contenido_y_unidad(*textos: str) -> Tuple[Optional[float], Optional[str]]:
    """
    Busca el contenido (número + unidad) en los textos recibidos, en orden de
    prioridad (nombre, presentación, descripción) y lo devuelve normalizado.
    Corrección del Taller 1: se reconocen "Grs" y se da prioridad al nombre del
    anuncio sobre la descripción.
    """
    for texto in textos:
        if not texto:
            continue
        m = _PATRON_CONTENIDO.search(texto)
        if m:
            valor = float(m.group(1).replace(",", "."))
            return normalizar_unidad(valor, m.group(2))
    return None, None


def normalizar_ean(ean: Any) -> Optional[str]:
    """Devuelve el EAN/GTIN si tiene 8, 12, 13 o 14 dígitos; si no (códigos internos, vacío), None."""
    if ean is None:
        return None
    texto = str(ean).strip()
    return texto if re.fullmatch(r"\d{8}|\d{12,14}", texto) else None


_ALIAS_MARCAS = {
    "anthelios": "La Roche Posay",
    "la roche-posay": "La Roche Posay",
    "la roche posay": "La Roche Posay",
    "sol-or": "Sol-Or",
    "solor": "Sol-Or",
    "sun face": "Sunface",
    "loreal paris": "L'Oréal Paris",
    "acm": "ACM",
    "hn naturals": "HN Naturals",
    "no-ad": "No-Ad",
    "kits": None,
    "locatel": None,
}


def estandarizar_marca(marca: Optional[str]) -> Optional[str]:
    """Unifica mayúsculas y alias conocidos de una marca ("NIVEA" -> "Nivea")."""
    if not marca or not str(marca).strip():
        return None
    clave = str(marca).strip().lower()
    if clave in _ALIAS_MARCAS:
        return _ALIAS_MARCAS[clave]
    return " ".join(p.capitalize() for p in clave.split())


SUBCATEGORIAS = [
    "Facial", "Facial con color", "Corporal", "Infantil", "Labial",
    "Después del sol", "Bronceador", "Fuera de la categoría",
]


def clasificar_subcategoria(nombre: str, contenido_valor: Optional[float], en_categoria: int) -> str:
    """Subcategoría estandarizada a partir del nombre del anuncio (reglas explícitas)."""
    if not en_categoria:
        return "Fuera de la categoría"
    n = (nombre or "").lower()
    if any(k in n for k in ["after sun", "aftersun", "después del sol", "despues del sol", "post solar", "postsolar", "after-sun"]):
        return "Después del sol"
    if any(k in n for k in ["labial", "labios", " lip", "lips"]):
        return "Labial"
    if any(k in n for k in ["kids", "niño", "nino", "infantil", "pediatric", "baby", "bebé", "bebe", "junior", "mustela"]):
        return "Infantil"
    if any(k in n for k in ["bronceador", "bronceante", "aceite bronce", "tanning"]):
        return "Bronceador"
    if "sin color" not in n and any(k in n for k in ["color", "tono ", "tinted", "teinté", "teinte", "bronze", "beige", "tinte"]):
        return "Facial con color"
    if any(k in n for k in ["corporal", "body", "cuerpo", "spray", "aerosol", "bruma corporal"]):
        return "Corporal"
    if any(k in n for k in ["facial", "face", "rostro", "fluid", "fluido", "gel crema", "gel-crema", "toque seco"]):
        return "Facial"
    if contenido_valor is not None and contenido_valor > 100:
        return "Corporal"
    return "Facial"


def clasificar_pertenencia_categoria(
    nombre: str, presentacion: str = "", descripcion: str = "", subcategoria: str = ""
) -> Tuple[int, Optional[str]]:
    """
    Determina si un producto pertenece a la categoría delimitada (protectores solares
    faciales, corporales, labiales, infantiles y productos para después del sol).
    Reglas del Taller 1 más las correcciones del Taller 2 (reglas 9 a 11).
    """
    n_lower = (nombre or "").lower()
    # Corrección Taller 2: el "+" de "FPS 50+" o "SPF50 +" no indica un combo
    n_sin_fps = re.sub(r"\d+\s*\+", " ", n_lower)

    # 1. Kits o combos que mezclan productos distintos
    if any(k in n_lower for k in ["kit ", "kit-", "combo", "pack ", "estuche"]) or (
        "+" in n_sin_fps and any(w in n_sin_fps for w in [
            "mela", "serum", "agua micelar", "termal", "mini", "crema", "obsequio", "regalo",
            "cosmetiquera", "mist", "reparador labial", "toalla", "gel x", "gel limpiador"])
    ):
        return 0, "Kit o combo que mezcla productos distintos"
    # 2. Limpiadores, jabones o aguas micelares
    if any(k in n_lower for k in ["limpiador", "limpiadora", "gel moussant", "moussant", "agua micelar",
                                  "cleansing", "syndet", "espuma de limpieza", "espuma limpiadora",
                                  "jabon", "jabón", "desmaquillante"]):
        return 0, "Limpiador o jabón facial o corporal"
    # 3. Suplementos o fotoprotección oral
    if any(k in n_lower for k in ["cápsulas", "capsulas", "comprimidos", "tabletas", "fotoprotector oral", "suplemento"]):
        return 0, "Suplemento o fotoprotector oral"
    # 4. Repelentes
    if "repelente" in n_lower:
        return 0, "Repelente de insectos"
    # 5. Autobronceadores sin filtro UV
    if any(k in n_lower for k in ["autobronceador", "autobronceante"]) and not any(k in n_lower for k in ["protector solar", "fps", "spf"]):
        return 0, "Autobronceador sin filtro UV primario"
    # 6. Maquillaje con FPS secundario
    # Corrección Taller 2: palabras completas ("Ruboril" no es "rubor") y no aplica si el
    # anuncio se presenta como protector solar (p. ej. "Protector Solar ... Primer Color")
    if re.search(r"\b(polvo compacto|polvo trasl[uú]cido|polvo transl[uú]cido|corrector|pestañina|primer|rubor|blush|base isdin coverag)\b", n_lower) \
            and not any(k in n_lower for k in ["protector solar", "fotoprotector"]):
        return 0, "Maquillaje o cosmético con FPS secundario"
    # 7. Serums cosméticos sin fotoprotección primaria
    if any(k in n_lower for k in ["sérum", "serum"]) and not any(k in n_lower for k in ["sun serum", "protector solar", "fotoprotector", "solar", "spf", "fps"]):
        return 0, "Serum cosmético sin fotoprotección primaria"
    # 8. Cremas hidratantes o de tratamiento con FPS secundario
    if any(k in n_lower for k in ["crema de noche", "crema facial de día", "crema de día", "hidratante facial",
                                  "contorno de ojos", "crema aclaradora", "crema hidratante"]):
        if not any(k in n_lower for k in ["protector solar", "bloqueador", "fotoprotector"]):
            return 0, "Crema hidratante o antiedad con FPS secundario"
    if any(k in n_lower for k in ["cicatricure porcelana", "anti-pigment crema", "overhuden", "eclarife", "acladerm", "depigmenting"]):
        if not any(k in n_lower for k in ["protector solar", "bloqueador", "fotoprotector"]):
            return 0, "Crema despigmentante o antiarrugas con FPS secundario"
    # 9. (Taller 2) Productos capilares
    if any(k in n_lower for k in ["acondicionador", "shampoo", "champú", "champu", "tratamiento capilar"]):
        return 0, "Producto capilar fuera de la categoría"
    # 10. (Taller 2) Cremas faciales de tratamiento sin fotoprotección declarada en el nombre
    if any(k in n_lower for k in ["crema facial", "crema activadora", "crema gel antioxidante"]) and not any(
        k in n_lower for k in ["protector", "bloqueador", "fotoprotector", "fps", "spf", "solar", "sun"]
    ):
        return 0, "Crema de tratamiento sin fotoprotección primaria"
    # 11. (Taller 2) Bálsamos labiales reparadores sin FPS
    if any(k in n_lower for k in ["reparacion labios", "reparación labios", "lip repair"]) and not any(
        k in n_lower for k in ["fps", "spf"]
    ):
        return 0, "Bálsamo labial sin FPS"
    return 1, None


def etiquetar_y_estandarizar_observaciones(productos: List[Dict[str, Any]], comercio: str) -> List[Dict[str, Any]]:
    """
    Normaliza contenido y unidad, calcula el precio por unidad, clasifica la
    pertenencia a la categoría y la subcategoría, y asigna el producto comparable.
    """
    asignados_comun = set()
    for p in productos:
        nombre = p.get("nombre_original", "") or ""
        desc = p.get("descripcion_original", "") or ""
        marca = p.get("marca_original", "") or ""
        pres = p.get("presentacion_original", "") or ""
        precio = p.get("precio_actual")

        en_cat, mot_excl = clasificar_pertenencia_categoria(nombre, pres, desc, p.get("subcategoria_original", ""))
        p["en_categoria"] = en_cat
        p["motivo_exclusion"] = mot_excl

        # Un combo mezcla presentaciones distintas: no tiene un contenido único
        if mot_excl == "Kit o combo que mezcla productos distintos":
            val_cont, unid_cont = None, None
        else:
            val_cont, unid_cont = extraer_contenido_y_unidad(nombre, pres, desc)
        p["contenido_valor"] = val_cont
        p["contenido_unidad"] = unid_cont
        p["precio_por_unidad"] = round(precio / val_cont, 4) if (precio and val_cont) else None
        p["comparable"] = 0
        p["id_producto_comun"] = None

        if en_cat == 1:
            ean_item = str(p.get("ean_original", "") or "").strip()
            for item_cat in CATALOGO_COMPARABLES:
                cid = item_cat["id_producto_comun"]
                if cid in asignados_comun:
                    continue
                if comercio == "Locatel":
                    coincide = bool(ean_item) and ean_item == item_cat.get("ean")
                else:
                    regla = item_cat["reglas"].get(comercio)
                    coincide = bool(regla and regla(nombre, desc, marca, ean_item))
                if coincide:
                    p["comparable"] = 1
                    p["id_producto_comun"] = cid
                    p["contenido_valor"] = item_cat["contenido_valor"]
                    p["contenido_unidad"] = item_cat["contenido_unidad"]
                    p["precio_por_unidad"] = round(precio / item_cat["contenido_valor"], 4) if precio else None
                    asignados_comun.add(cid)
                    break

        p["subcategoria_estandar"] = clasificar_subcategoria(nombre, p["contenido_valor"], en_cat)
        p["marca_estandar"] = estandarizar_marca(marca)
    return productos


# =====================================================================
# 2. COPIAS CRUDAS
# =====================================================================
def leer_copia_cruda(archivo: Path) -> Tuple[str, Optional[int], List[Dict[str, Any]]]:
    """Lee una copia cruda (.json.gz o .json): (timestamp, total reportado, páginas)."""
    archivo = Path(archivo)
    if archivo.name.endswith(".gz"):
        with gzip.open(archivo, "rt", encoding="utf-8") as f:
            datos = json.load(f)
    else:
        with open(archivo, "r", encoding="utf-8") as f:
            datos = json.load(f)
    tot = datos.get("total_esperado")
    if isinstance(tot, dict):
        total_esperado = tot.get("total_esperado")
    elif isinstance(tot, (int, float)):
        total_esperado = int(tot)
    else:
        total_esperado = None
    return datos["timestamp"], total_esperado, datos.get("pages", [])


def listar_copias_crudas(comercio: str, raw_base: Path = RAW_DIR) -> List[Path]:
    """Copias crudas de un comercio, de la más antigua a la más reciente."""
    carpeta = Path(raw_base) / COMERCIOS[comercio]["carpeta"]
    return sorted(f for f in carpeta.glob("**/*.json.gz") if f.is_file())


def guardar_copia_cruda(directorio: Path, prefijo: str, timestamp: str, total_esperado: Any,
                        pages: List[Dict[str, Any]]) -> Path:
    """Guarda raw/<comercio>/<fecha>/<prefijo>_<timestamp>.json.gz y devuelve la ruta."""
    carpeta_destino = Path(directorio) / timestamp.split("T")[0]
    carpeta_destino.mkdir(parents=True, exist_ok=True)
    archivo = carpeta_destino / f"{prefijo}_{timestamp.replace(':', '-')}.json.gz"
    with gzip.open(archivo, "wt", encoding="utf-8") as f:
        json.dump({"timestamp": timestamp, "total_esperado": total_esperado, "pages": pages},
                  f, ensure_ascii=False, indent=2)
    return archivo


def extraer_productos_de_paginas(raw_pages: List[Dict[str, Any]], comercio: str, timestamp: str,
                                 subcategoria_defecto: str = "Dermocosmética / Protección Solar") -> List[Dict[str, Any]]:
    """Convierte las respuestas JSON de la API VTEX en observaciones (una por SKU)."""
    productos: List[Dict[str, Any]] = []
    vistos = set()
    for page in raw_pages:
        items = page.get("items", [])
        if not isinstance(items, list):
            raise ValueError("La respuesta del sitio cambió de estructura: 'items' no es una lista.")
        for p in items:
            product_id = str(p.get("productId", ""))
            categories = p.get("categories", [])
            subcategory = categories[-1].strip("/ ") if categories else subcategoria_defecto
            for sku in p.get("items", []):
                sku_id = str(sku.get("itemId", product_id))
                if (comercio, sku_id) in vistos:
                    continue
                vistos.add((comercio, sku_id))

                price = list_price = None
                disponible = None
                for s in sku.get("sellers", []):
                    comm = s.get("commertialOffer", {})
                    if comm.get("Price") and comm["Price"] > 0:
                        price = comm.get("Price")
                        list_price = comm.get("ListPrice")
                        disponible = comm.get("IsAvailable")
                        break
                price_val = limpiar_precio(price)
                list_price_val = limpiar_precio(list_price)
                if disponible is True:
                    estado = "disponible"
                elif disponible is False:
                    estado = "agotado"
                else:
                    estado = None  # el sitio no informa la disponibilidad

                ean_original = str(sku.get("ean", "") or "").strip()
                productos.append({
                    "comercio": comercio,
                    "id_producto_comercio": sku_id,
                    "nombre_original": p.get("productName", "") or "",
                    "presentacion_original": sku.get("name", ""),
                    "descripcion_original": p.get("description", "") or "",
                    "marca_original": p.get("brand", "") or "",
                    "subcategoria_original": subcategory,
                    "precio_actual": price_val,
                    "precio_lista": list_price_val,
                    "es_promocion": 1 if (list_price_val and price_val and list_price_val > price_val) else 0,
                    "url": p.get("link", "") or "",
                    "pum_original": None,
                    "fecha_hora_consulta": timestamp,
                    "ean_original": ean_original,
                    "ean": normalizar_ean(ean_original),
                    "estado_disponibilidad": estado,
                })
    return etiquetar_y_estandarizar_observaciones(productos, comercio)


# =====================================================================
# 3. EXTRACCIÓN EN LÍNEA (API pública de catálogo VTEX)
# =====================================================================
def descargar_paginas_vtex(base_url: str, subcategorias: List[str], is_fq: bool,
                           sesion: Optional[requests.Session] = None) -> Tuple[List[Dict[str, Any]], Dict[str, int], Optional[str]]:
    """
    Descarga todas las páginas del catálogo de un comercio respetando la pausa y el
    máximo de peticiones. Devuelve (páginas, totales por categoría, motivo de falla o None).
    """
    sesion = sesion or requests.Session()
    paginas: List[Dict[str, Any]] = []
    totales: Dict[str, int] = {}
    motivo: Optional[str] = None
    peticiones = 0

    for subcat in subcategorias:
        start = 0
        while True:
            if peticiones >= MAX_PETICIONES_POR_COMERCIO:
                motivo = f"Se alcanzó el máximo de {MAX_PETICIONES_POR_COMERCIO} peticiones por comercio."
                return paginas, totales, motivo
            end = start + TAMANO_PAGINA - 1
            if is_fq:
                url = f"{base_url}/api/catalog_system/pub/products/search?fq={subcat}&O=OrderByNameASC&_from={start}&_to={end}"
            else:
                url = f"{base_url}/api/catalog_system/pub/products/search/{subcat}?_from={start}&_to={end}"
            if peticiones > 0:
                time.sleep(PAUSA_SEGUNDOS)
            peticiones += 1
            try:
                resp = sesion.get(url, headers=HEADERS_DEFAULT, timeout=TIMEOUT_SEGUNDOS)
            except requests.RequestException as e:
                motivo = f"Error de red: {type(e).__name__}"
                return paginas, totales, motivo
            if resp.status_code not in (200, 206):
                motivo = f"El sitio respondió con código HTTP {resp.status_code} (posible bloqueo)."
                return paginas, totales, motivo

            recursos = resp.headers.get("resources", "")
            total_cat = None
            if "/" in recursos:
                try:
                    total_cat = int(recursos.split("/")[-1])
                    totales[subcat] = total_cat
                except ValueError:
                    pass
            try:
                items = resp.json()
            except ValueError:
                motivo = "La respuesta no es JSON: el sitio cambió de estructura o bloqueó la consulta."
                return paginas, totales, motivo
            if not isinstance(items, list):
                motivo = "La respuesta JSON no tiene la estructura esperada (lista de productos)."
                return paginas, totales, motivo
            if not items:
                break
            paginas.append({"subcategoria_slug": subcat, "page_start": start, "page_end": end,
                            "resources_header": recursos, "items": items})
            start += TAMANO_PAGINA
            if (total_cat and start >= total_cat) or len(items) < TAMANO_PAGINA:
                break
    return paginas, totales, motivo


@dataclass
class ResultadoRecoleccion:
    """Resultado de recolectar un comercio (en línea o desde una copia cruda)."""
    comercio: str
    modo: str                                   # "en_linea" o "sin_conexion"
    timestamp: Optional[str] = None
    productos: List[Dict[str, Any]] = field(default_factory=list)
    total_reportado: Optional[int] = None
    fallo: bool = False
    motivo: Optional[str] = None
    archivo_raw: Optional[str] = None           # ruta relativa a la carpeta del proyecto


def _ruta_relativa(ruta: Path) -> str:
    try:
        return Path(ruta).resolve().relative_to(BASE_DIR).as_posix()
    except ValueError:
        return Path(ruta).as_posix()


def recolectar_comercio(comercio: str, offline: bool = False, archivo_raw: Optional[Path] = None,
                        raw_base: Path = RAW_DIR) -> ResultadoRecoleccion:
    """
    Punto de entrada que usan la aplicación y la línea de comandos.
    - En línea: consulta la API del sitio, guarda la copia cruda en raw/ y la procesa.
    - Sin conexión: reprocesa `archivo_raw` o, si no se indica, la copia cruda más reciente.
    Nunca lanza excepciones: si algo falla, devuelve fallo=True y el motivo.
    """
    cfg = COMERCIOS[comercio]
    modo = "sin_conexion" if offline else "en_linea"
    res = ResultadoRecoleccion(comercio=comercio, modo=modo)
    try:
        if offline:
            if archivo_raw is None:
                copias = listar_copias_crudas(comercio, raw_base)
                if not copias:
                    res.fallo, res.motivo = True, "No hay copias crudas en raw/ para este comercio."
                    return res
                archivo_raw = copias[-1]
            ts, total, paginas = leer_copia_cruda(Path(archivo_raw))
            res.timestamp, res.total_reportado = ts, total
            res.archivo_raw = _ruta_relativa(Path(archivo_raw))
        else:
            ts = obtener_timestamp_colombia()
            paginas, totales, motivo = descargar_paginas_vtex(cfg["base_url"], cfg["subcategorias"], cfg["is_fq"])
            res.timestamp = ts
            res.total_reportado = sum(totales.values()) if totales else None
            if motivo:
                res.fallo, res.motivo = True, motivo
            if paginas:
                ruta = guardar_copia_cruda(Path(raw_base) / cfg["carpeta"], cfg["carpeta"], ts,
                                           {"total_esperado": res.total_reportado, "totales_por_categoria": totales},
                                           paginas)
                res.archivo_raw = _ruta_relativa(ruta)
        res.productos = extraer_productos_de_paginas(paginas, comercio, res.timestamp, cfg["subcategoria_defecto"])
    except Exception as e:  # cambio de estructura u otro error inesperado
        res.fallo = True
        res.motivo = f"Error al procesar la respuesta: {type(e).__name__}: {e}"
        res.productos = []
    return res


# Funciones por comercio conservadas del Taller 1 (interfaz modular)
def scrape_bellapiel(offline: bool = False) -> ResultadoRecoleccion:
    return recolectar_comercio("Bella Piel", offline=offline)


def scrape_larebaja(offline: bool = False) -> ResultadoRecoleccion:
    return recolectar_comercio("La Rebaja", offline=offline)


def scrape_locatel(offline: bool = False) -> ResultadoRecoleccion:
    return recolectar_comercio("Locatel", offline=offline)


if __name__ == "__main__":
    # La recolección completa (scraping + validación + inserción) se orquesta en
    # actualizacion.py; este atajo conserva el comando del Taller 1.
    import sys
    from actualizacion import main
    sys.exit(main())
