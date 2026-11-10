"""
scraper.py - Taller 1 (y reutilizado en el Taller 2) Minería de Datos (UNAL)

Cambios del Taller 2 (el módulo se REUTILIZA; el botón de la aplicación llama a estas funciones):
  * recolectar_comercio(): recolecta, valida e inserta UN comercio (la app la llama comercio por comercio para mostrar avance).
  * Inserción transaccional por comercio con validación previa (validacion.py): lo inválido va a observaciones_rechazadas.
  * Estado de disponibilidad (disponible / agotado), ruta de la copia cruda por observación (raw_archivo).
  * Buenas prácticas: agente de usuario identificable, pausa entre peticiones y tope de peticiones por comercio.
  * reprocesar_raw(): modo sin conexión; no pisa ejecuciones ya cargadas.
  * limpiar_precio(): convierte precios en texto ("$ 12.900") a número.

Categoría: pañales infantiles, pañitos, cambiadores desechables y cremas de barrera no medicinales.

Estrategia
----------
Los tres comercios por defecto (Éxito, Jumbo, Olímpica) usan la plataforma VTEX, que expone
los servicios JSON que la propia página usa para listar productos:
  * Modo "legacy":      GET {base}/api/catalog_system/pub/products/search?fq=C:/id/  |  ft=texto&_from=0&_to=49
  * Modo "intelligent": GET {base}/api/io/_v/api/intelligent-search/product_search?query=texto&page=1&count=50
El modo se detecta automáticamente por comercio (ver `detectar_modo`). Para cada comercio:
  1. Se descubre el árbol de categorías (modo legacy) y se recorren los nodos cuyo nombre sugiere
     la categoría (pañal, toallita, cambiador, antipañalitis...).
  2. Se complementa con búsquedas por texto (CONSULTAS_TEXTO) para no perder productos mal ubicados.
  3. Se deduplica por SKU. La clasificación fina (qué entra y qué se excluye) se hace en limpieza.py
     y todo lo excluido queda registrado con su motivo.

Uso (línea de comandos)
-----------------------
  python scraper.py probe      # diagnóstico: modo, categorías encontradas, robots.txt
  python scraper.py diagnose   # diagnóstico detallado de HTTP por sitio (úselo si un comercio falla)
  python scraper.py run        # recolección completa en línea (guarda raw/ y SQLite)
  python scraper.py offline    # reprocesa raw/ sin conexión y reconstruye la base
"""
from __future__ import annotations

import gzip
import json
import logging
import os
import re
import sqlite3
import time
import unicodedata
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, quote_plus, urlencode, urljoin, urlsplit

import pandas as pd
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

import db
import limpieza as L
import validacion as V

log = logging.getLogger("scraper")

# Colombia no tiene horario de verano: UTC-5 fijo.
TZ_CO = timezone(timedelta(hours=-5))
PAGINA = 50          # máximo de VTEX por petición
MAX_OFFSET = 2500    # VTEX no pagina más allá de 2500 resultados por consulta
MAX_PETICIONES_COMERCIO = int(os.environ.get("MAX_PETICIONES_COMERCIO", 1500))   # tope por comercio y ejecución
PAUSA_SEGUNDOS = max(1.0, float(os.environ.get("PAUSA_SEGUNDOS", 1.0)))          # nunca menos de 1 s entre peticiones
CONTACTO = os.environ.get("SCRAPER_CONTACTO", "uso-academico")
USER_AGENT = os.environ.get(
    "SCRAPER_USER_AGENT",
    f"Mozilla/5.0 (compatible; TallerMineriaDatosUNAL/2.0; +contacto:{CONTACTO}) comparador-precios-academico")
DB_DEFECTO = "comparador_precios.sqlite"
RAW_DEFECTO = "raw"


def limpiar_precio(texto) -> float | None:
    """Convierte un precio escrito como texto a número (convención colombiana: punto = miles, coma = decimales).
    '$ 12.900' -> 12900.0 · '12.900,50' -> 12900.5 · '1.234.567' -> 1234567.0 · '12,5' -> 12.5.
    Devuelve None si no es un número válido o si es <= 0 (un dato ausente queda ausente; nunca se inventa)."""
    if texto is None or isinstance(texto, bool):
        return None
    if isinstance(texto, (int, float)):
        v = float(texto)
        return v if v == v and v > 0 else None
    t = re.sub(r"[^\d.,\-]", "", str(texto).replace("\xa0", " "))
    if not t or t in {"-", ".", ","} or t.count("-") > 1 or ("-" in t and not t.startswith("-")):
        return None
    if "." in t and "," in t:
        decimal = "," if t.rfind(",") > t.rfind(".") else "."
        miles = "." if decimal == "," else ","
        t = t.replace(miles, "").replace(decimal, ".")
    elif "." in t:
        t = t.replace(".", "") if re.fullmatch(r"-?\d{1,3}(\.\d{3})+", t) else t
    elif "," in t:
        t = t.replace(",", ".")
    try:
        v = float(t)
    except ValueError:
        return None
    return v if v > 0 else None


def ahora_iso() -> str:
    """Fecha y hora de Colombia en ISO 8601, p. ej. 2026-10-06T10:35:00-05:00."""
    return datetime.now(TZ_CO).isoformat(timespec="seconds")


def _slug(s: str) -> str:
    """Nombre de archivo seguro: ASCII, sin ':' ni espacios (válido en Windows, Mac y Linux)."""
    return re.sub(r"[^a-z0-9]+", "_", _norm(s)).strip("_")[:60]


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s.lower()).strip()


# --------------------------------------------------------------------------------------
# Configuración de comercios
# --------------------------------------------------------------------------------------
@dataclass
class Comercio:
    clave: str
    nombre: str
    base_url: str
    # Nombres de nodos del árbol de categorías que se consideran equivalentes a la categoría
    patron_categorias: str = (r"pa(n|ñ)al|toallit|pa(n|ñ)itos|cambiador|antipa(n|ñ)alitis|barrera|nalguita|"
                              r"aseo del beb|cuidado del beb|higiene del beb")
    modo: str | None = None  # "legacy" | "intelligent" (autodetectado)


COMERCIOS: dict[str, Comercio] = {
    "exito": Comercio("exito", "Éxito", "https://www.exito.com"),
    "jumbo": Comercio("jumbo", "Jumbo", "https://www.jumbocolombia.com"),
    "olimpica": Comercio("olimpica", "Olímpica", "https://www.olimpica.com"),
    # Alternativas VTEX si alguno bloquea el acceso (cambiar en COMERCIOS_ACTIVOS):
    "carulla": Comercio("carulla", "Carulla", "https://www.carulla.com"),
}
COMERCIOS_ACTIVOS = ["exito", "jumbo", "olimpica"]

CONSULTAS_TEXTO = [
    # Palabras sueltas (las más robustas: algunos sitios responden HTTP 400 a consultas de varias palabras)
    "pañales", "pañal", "toallitas", "pañitos", "cambiador", "cambiadores", "antipañalitis", "nalguita",
    # Frases (si el sitio las rechaza, queda registrado en la ejecución y se continúa)
    "pañales etapa", "pañales recién nacido", "pañales huggies", "pañales pampers", "pañales winny",
    "pañales babysec", "pañales de entrenamiento", "toallitas húmedas bebé", "pañitos húmedos",
    "cambiador desechable", "protector cambiador", "crema antipañalitis", "crema para pañal",
    "crema barrera bebé", "pasta de óxido de zinc bebé",
]

COLUMNAS = [
    "ejecucion_id", "comercio", "sku", "product_id", "ean", "url",
    "nombre_original", "descripcion_original", "ficha_tecnica_original", "marca_original",
    "categoria_sitio", "precio", "precio_lista", "es_promocion", "disponible",
    "unidad_medida_sitio", "multiplicador_unidad", "via", "fecha_hora_consulta", "raw_archivo",
]


# --------------------------------------------------------------------------------------
# Cliente HTTP
# --------------------------------------------------------------------------------------
class ErrorHTTP(RuntimeError):
    pass


class LimitePeticiones(RuntimeError):
    """Se alcanzó el tope de peticiones por comercio y ejecución (buena práctica de recolección)."""


class Cliente:
    """Sesión HTTP con reintentos, pausa entre peticiones, agente de usuario identificable y tope de peticiones."""

    def __init__(self, pausa: float = PAUSA_SEGUNDOS, timeout: int = 30, max_peticiones: int = MAX_PETICIONES_COMERCIO):
        self.pausa, self.timeout, self.max_peticiones = pausa, timeout, max_peticiones
        self.n_peticiones = 0
        self.s = requests.Session()
        retry = Retry(total=3, backoff_factor=1.5, status_forcelist=(429, 500, 502, 503, 504),
                      allowed_methods=("GET",))
        self.s.mount("https://", HTTPAdapter(max_retries=retry))
        self.s.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "es-CO,es;q=0.9",
        })

    def reiniciar_contador(self) -> None:
        self.n_peticiones = 0

    def _contar(self) -> None:
        if self.max_peticiones and self.n_peticiones >= self.max_peticiones:
            raise LimitePeticiones(f"Se alcanzó el tope de {self.max_peticiones} peticiones para este comercio")
        self.n_peticiones += 1

    @staticmethod
    def _detalle(r) -> str:
        return f"HTTP {r.status_code} en {r.url} [server={r.headers.get('server')}] {r.text[:100]!r}"

    def get_json(self, url: str, params: dict | None = None):
        self._contar()
        time.sleep(self.pausa)
        origen = "{0.scheme}://{0.netloc}/".format(urlsplit(url))
        r = None
        # Primero espacios como %20; si el sitio responde 400, se reintenta con '+' (algunos WAF lo exigen).
        for codificador in (quote, quote_plus):
            qs = urlencode(params or {}, quote_via=codificador, safe="/:,")
            r = self.s.get(f"{url}?{qs}" if qs else url, timeout=self.timeout, headers={"Referer": origen})
            if r.status_code != 400:
                break
        if r.status_code not in (200, 206):
            raise ErrorHTTP(self._detalle(r))
        try:
            data = r.json()
        except ValueError as e:
            raise ErrorHTTP("Respuesta no JSON: " + self._detalle(r)) from e
        return data, dict(r.headers), r.url

    def get_text(self, url: str) -> str:
        self._contar()
        time.sleep(self.pausa)
        r = self.s.get(url, timeout=self.timeout)
        r.raise_for_status()
        return r.text


# --------------------------------------------------------------------------------------
# Copias crudas (raw/)
# --------------------------------------------------------------------------------------
def guardar_raw(raw_dir: Path, comercio: str, nombre: str, envoltura: dict) -> Path:
    """Guarda la respuesta original (+ metadatos de la consulta) comprimida: raw/<comercio>/<fecha>/<nombre>.json.gz"""
    fecha = envoltura["consulta"][:10]
    carpeta = Path(raw_dir) / comercio / fecha
    carpeta.mkdir(parents=True, exist_ok=True)
    ruta = carpeta / f"{nombre}.json.gz"
    with gzip.open(ruta, "wt", encoding="utf-8") as f:
        json.dump(envoltura, f, ensure_ascii=False)
    return ruta


def _ref_raw(ruta: Path, raw_dir: Path) -> str:
    """Ruta de la copia cruda relativa a la carpeta que contiene raw/ (p. ej. 'raw/exito/2026-10-11/archivo.json.gz')."""
    ruta, raw_dir = Path(ruta), Path(raw_dir)
    try:
        return (Path(raw_dir.name) / ruta.relative_to(raw_dir)).as_posix()
    except ValueError:
        return ruta.as_posix()


def leer_raw(ruta: Path) -> dict:
    with gzip.open(ruta, "rt", encoding="utf-8") as f:
        return json.load(f)


# --------------------------------------------------------------------------------------
# Parseo de productos VTEX (común a legacy e intelligent search)
# --------------------------------------------------------------------------------------
def _num(x):
    try:
        v = float(x)
    except (TypeError, ValueError):
        return None
    return v if v > 0 else None  # 0 = no disponible -> NULL, nunca se reemplaza por cero


def _ficha(p: dict) -> str:
    """Ficha técnica tal como la publica el sitio (JSON)."""
    out = {}
    for nombre in p.get("allSpecifications") or []:
        out[nombre] = p.get(nombre)
    if p.get("properties"):
        out["properties"] = p["properties"]
    return json.dumps(out, ensure_ascii=False) if out else None


def parsear_producto(p: dict, cfg: Comercio, via: str) -> list[dict]:
    """Un producto VTEX puede traer varios SKU (items); cada SKU es una presentación."""
    filas = []
    categorias = p.get("categories") or []
    cat = (categorias[0] if categorias else "") or ""
    cat = " > ".join(x for x in cat.strip("/").split("/") if x)
    link = p.get("link") or (f"/{p['linkText']}/p" if p.get("linkText") else None)
    url = urljoin(cfg.base_url + "/", link) if link else None
    for it in p.get("items") or [{}]:
        oferta = {}
        for s in it.get("sellers") or []:
            o = s.get("commertialOffer") or {}
            if o.get("AvailableQuantity", 0) and _num(o.get("Price")):
                oferta = o
                break
        if not oferta and it.get("sellers"):
            oferta = it["sellers"][0].get("commertialOffer") or {}
        precio = _num(oferta.get("Price"))
        lista = _num(oferta.get("ListPrice")) or _num(oferta.get("PriceWithoutDiscount"))
        sin_desc = _num(oferta.get("PriceWithoutDiscount"))
        if sin_desc and (not lista or sin_desc > lista):
            lista = sin_desc
        promo = int(bool(precio and lista and precio < lista))
        filas.append({
            "comercio": cfg.clave,
            "sku": str(it.get("itemId") or p.get("productId")),
            "product_id": str(p.get("productId")),
            "ean": it.get("ean") or None,
            "url": url,
            "nombre_original": it.get("nameComplete") or it.get("name") or p.get("productName"),
            "descripcion_original": p.get("description") or None,
            "ficha_tecnica_original": _ficha(p),
            "marca_original": p.get("brand") or None,
            "categoria_sitio": cat or None,
            "precio": precio,
            "precio_lista": lista if promo else (lista or None),
            "es_promocion": promo,
            "disponible": int(bool(oferta.get("AvailableQuantity", 0))),
            "unidad_medida_sitio": it.get("measurementUnit"),
            "multiplicador_unidad": it.get("unitMultiplier"),
            "via": via,
        })
    return filas


def _items_y_total(data, headers: dict | None, modo: str):
    if modo == "legacy":
        total = None
        m = re.search(r"/(\d+)$", (headers or {}).get("resources", ""))
        if m:
            total = int(m.group(1))
        return (data if isinstance(data, list) else []), total
    return data.get("products", []), data.get("recordsFiltered")


# --------------------------------------------------------------------------------------
# Recorrido de un comercio VTEX
# --------------------------------------------------------------------------------------
def _url_y_params(cfg: Comercio, modo: str, consulta: dict, offset: int) -> tuple[str, dict]:
    if modo == "legacy":
        url = f"{cfg.base_url}/api/catalog_system/pub/products/search"
        params = {"_from": offset, "_to": offset + PAGINA - 1}
        params["fq" if consulta["tipo"] == "categoria" else "ft"] = consulta["valor"]
    else:
        url = f"{cfg.base_url}/api/io/_v/api/intelligent-search/product_search"
        params = {"query": consulta["valor"], "page": offset // PAGINA + 1, "count": PAGINA,
                  "locale": "es-CO", "hideUnavailableItems": "false"}
    return url, params


def detectar_modo(cli: Cliente, cfg: Comercio) -> str:
    errores = []
    for modo in ("legacy", "intelligent"):
        try:
            url, params = _url_y_params(cfg, modo, {"tipo": "texto", "valor": "pañales"}, 0)
            data, headers, _ = cli.get_json(url, params)
            items, _ = _items_y_total(data, headers, modo)
            if items:
                return modo
            errores.append(f"{modo}: respuesta sin productos")
        except Exception as e:  # noqa: BLE001
            errores.append(f"{modo}: {type(e).__name__}: {str(e)[:220]}")
            log.warning("%s: modo %s no disponible (%s)", cfg.clave, modo, e)
    raise ErrorHTTP(f"{cfg.clave}: ningún endpoint VTEX respondió productos -> " + " | ".join(errores))


def descubrir_categorias(cli: Cliente, cfg: Comercio) -> list[dict]:
    """Árbol de categorías (solo modo legacy). Devuelve nodos equivalentes a la categoría del taller."""
    data, _, _ = cli.get_json(f"{cfg.base_url}/api/catalog_system/pub/category/tree/4")
    patron = re.compile(cfg.patron_categorias, re.I)
    nodos = []

    def rec(lista, ids, nombres):
        for n in lista:
            i, nom = ids + [str(n["id"])], nombres + [n["name"]]
            if patron.search(_norm(n["name"])):
                nodos.append({"ruta_ids": i, "ruta": " > ".join(nom), "nombre": n["name"]})
                continue  # el nodo ya incluye a sus hijos en VTEX
            rec(n.get("children") or [], i, nom)

    rec(data, [], [])
    return nodos


def _recorrer_consulta(cli, cfg, modo, consulta, etiqueta, ejec, raw_dir, filas_por_sku, meta):
    offset, total, pag = 0, None, 0
    while offset < MAX_OFFSET:
        url, params = _url_y_params(cfg, modo, consulta, offset)
        data, headers, url_final = cli.get_json(url, params)
        ts = ahora_iso()
        items, tot = _items_y_total(data, headers, modo)
        total = tot if tot is not None else total
        ruta_raw = guardar_raw(raw_dir, cfg.clave, f"{ejec}__{etiqueta}__p{pag:03d}", {
            "ejecucion_id": ejec, "comercio": cfg.clave, "modo": modo, "consulta": ts,
            "url": url_final, "etiqueta": etiqueta, "total_sitio": total, "tipo_consulta": consulta["tipo"],
            "respuesta": data,
        })
        ref_raw = _ref_raw(ruta_raw, raw_dir)
        for p in items:
            for fila in parsear_producto(p, cfg, etiqueta):
                fila["fecha_hora_consulta"] = ts
                fila["raw_archivo"] = ref_raw
                meta["items_crudos"] += 1
                if fila["sku"] in filas_por_sku:
                    meta["duplicados_sku"] += 1
                    filas_por_sku[fila["sku"]]["via"] += f"|{etiqueta}"
                else:
                    filas_por_sku[fila["sku"]] = fila
        pag += 1
        offset += PAGINA
        if len(items) < PAGINA or (total is not None and offset >= total):
            break
    return total


def _scrape_vtex(cfg: Comercio, cli: Cliente, ejec: str, raw_dir: Path) -> pd.DataFrame:
    inicio = ahora_iso()
    meta = {"inicio": inicio, "items_crudos": 0, "duplicados_sku": 0, "n_sitio": None,
            "notas": [], "estado": "completa", "consultas": []}
    filas: dict[str, dict] = {}
    if hasattr(cli, "reiniciar_contador"):
        cli.reiniciar_contador()
    try:
        cfg.modo = detectar_modo(cli, cfg)
        consultas = []
        if cfg.modo == "legacy":
            try:
                for nodo in descubrir_categorias(cli, cfg):
                    consultas.append(({"tipo": "categoria", "valor": "C:/" + "/".join(nodo["ruta_ids"]) + "/"},
                                      "cat:" + nodo["ruta"]))
            except Exception as e:  # noqa: BLE001
                meta["notas"].append(f"No se pudo leer el árbol de categorías: {e}")
        consultas += [({"tipo": "texto", "valor": t}, "q:" + t) for t in CONSULTAS_TEXTO]
        suma_sitio = 0
        for consulta, etiqueta in consultas:
            try:
                tot = _recorrer_consulta(cli, cfg, cfg.modo, consulta, _slug(etiqueta),
                                         ejec, raw_dir, filas, meta)
                meta["consultas"].append({"etiqueta": etiqueta, "total_sitio": tot})
                if consulta["tipo"] == "categoria" and tot:
                    suma_sitio += tot
            except LimitePeticiones as e:
                meta["estado"] = "parcial"
                meta["notas"].append(f"{e}; se omiten las consultas restantes (desde {etiqueta})")
                log.warning("%s: %s", cfg.clave, e)
                break
            except Exception as e:  # noqa: BLE001
                meta["estado"] = "parcial"
                meta["notas"].append(f"Falló {etiqueta}: {e}")
                log.error("%s %s: %s", cfg.clave, etiqueta, e)
        meta["n_sitio"] = suma_sitio or None
        if not filas:
            meta["estado"] = "fallida"
    except Exception as e:  # noqa: BLE001
        meta["estado"] = "fallida" if not filas else "parcial"
        meta["notas"].append(str(e))
        log.error("%s: %s", cfg.clave, e)
    meta["fin"] = ahora_iso()
    meta["modo_api"] = cfg.modo
    df = pd.DataFrame(list(filas.values()))
    for c in COLUMNAS:
        if c not in df.columns:
            df[c] = None
    df["ejecucion_id"] = ejec
    df = df[COLUMNAS]
    df.attrs["meta"] = meta
    guardar_raw(raw_dir, cfg.clave, f"{ejec}__MANIFIESTO", {"ejecucion_id": ejec, "comercio": cfg.clave,
                "consulta": meta["inicio"], "manifiesto": meta})
    return df


# Una función por comercio: siempre devuelven las mismas columnas (COLUMNAS).
def scrape_exito(cli: Cliente, ejec: str, raw_dir: Path) -> pd.DataFrame:
    return _scrape_vtex(COMERCIOS["exito"], cli, ejec, raw_dir)


def scrape_jumbo(cli: Cliente, ejec: str, raw_dir: Path) -> pd.DataFrame:
    return _scrape_vtex(COMERCIOS["jumbo"], cli, ejec, raw_dir)


def scrape_olimpica(cli: Cliente, ejec: str, raw_dir: Path) -> pd.DataFrame:
    return _scrape_vtex(COMERCIOS["olimpica"], cli, ejec, raw_dir)


def scrape_carulla(cli: Cliente, ejec: str, raw_dir: Path) -> pd.DataFrame:
    return _scrape_vtex(COMERCIOS["carulla"], cli, ejec, raw_dir)


FUNCIONES = {"exito": scrape_exito, "jumbo": scrape_jumbo, "olimpica": scrape_olimpica, "carulla": scrape_carulla}


# --------------------------------------------------------------------------------------
# SQLite (esquema, vistas e índices viven en db.py; aquí solo la escritura de resultados)
# --------------------------------------------------------------------------------------
def conectar(db_path: str | Path = DB_DEFECTO) -> sqlite3.Connection:
    """Conexión de escritura (autocommit; las transacciones son explícitas). Crea/actualiza el esquema si hace falta."""
    return db.conectar_escritura(db_path)


def nueva_ejecucion_id() -> str:
    return "run_" + datetime.now(TZ_CO).strftime("%Y%m%dT%H%M%S")


def _comercio_id(con, clave: str) -> int:
    cfg = COMERCIOS[clave]
    con.execute("INSERT OR IGNORE INTO comercios(clave, nombre, url_base) VALUES (?,?,?)",
                (clave, cfg.nombre, cfg.base_url))
    return con.execute("SELECT comercio_id FROM comercios WHERE clave=?", (clave,)).fetchone()[0]


def _vacio_a_none(v):
    """NaN/NA de pandas -> None, para que SQLite guarde NULL (un dato ausente queda ausente)."""
    try:
        return None if pd.isna(v) else v
    except (TypeError, ValueError):
        return v


def _json_fila(r: dict) -> str:
    campos = ("ejecucion_id", "comercio", "sku", "product_id", "url", "nombre_original", "precio", "precio_lista",
              "es_promocion", "disponible", "fecha_hora_consulta", "raw_archivo")
    return json.dumps({k: _vacio_a_none(r.get(k)) for k in campos}, ensure_ascii=False, default=str)


def _meta_basica(df: pd.DataFrame, clave: str, ejec: str) -> dict:
    meta = dict(df.attrs.get("meta") or {})
    meta.setdefault("inicio", ahora_iso())
    meta.setdefault("notas", [])
    meta.setdefault("estado", "completa")
    meta.update({"ejecucion_id": ejec, "clave": clave})
    return meta


def insertar_resultado(con: sqlite3.Connection, df: pd.DataFrame, modo: str = "en_linea") -> dict:
    """
    Valida e inserta los resultados de UN comercio dentro de UNA transacción (todo o nada).
      1. Validación (validacion.py): lo que no cumple va a `observaciones_rechazadas` con su motivo; no se inserta.
      2. Inserta ejecución, anuncios y observaciones SIN sobrescribir (UNIQUE(ejecucion, anuncio) y UNIQUE(anuncio, fecha_hora)).
      3. Clasifica los anuncios nuevos (limpieza.py) y los enlaza a los productos comparables existentes.
      4. Verifica que estén los productos comparables; si falta alguno, la ejecución del comercio queda 'parcial'.
    Si algo falla, se hace ROLLBACK y la base queda como estaba.
    """
    meta = df.attrs["meta"]
    clave = meta.get("clave") or (df["comercio"].iloc[0] if len(df) else None)
    ejec = meta["ejecucion_id"]
    validas, rechazadas = V.validar_observaciones(df)
    notas = list(meta.get("notas", []))
    estado = meta.get("estado", "completa")
    if validas.empty:
        estado = "fallida"
    con.execute("BEGIN IMMEDIATE")
    try:
        cid = _comercio_id(con, clave)
        con.execute("""INSERT INTO ejecuciones(ejecucion_id, comercio_id, inicio, fin, n_registros, n_sitio_reportado,
                       estado, modo, modo_api, notas, n_rechazadas) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                       ON CONFLICT(ejecucion_id, comercio_id) DO UPDATE SET fin=excluded.fin, n_registros=excluded.n_registros,
                       n_sitio_reportado=excluded.n_sitio_reportado, n_rechazadas=excluded.n_rechazadas""",
                    (ejec, cid, meta["inicio"], meta.get("fin"), len(df), meta.get("n_sitio"), estado, modo,
                     meta.get("modo_api"), None, len(rechazadas)))
        nuevas = 0
        for r in validas.to_dict("records"):
            r = {k: _vacio_a_none(v) for k, v in r.items()}
            con.execute("""INSERT INTO anuncios(comercio_id, sku, product_id, ean, url, nombre_original, descripcion_original,
                           ficha_tecnica_original, marca_original, categoria_sitio, via) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                           ON CONFLICT(comercio_id, sku) DO UPDATE SET url=excluded.url, via=excluded.via""",
                        (cid, r["sku"], r["product_id"], r["ean"], r["url"], r["nombre_original"], r["descripcion_original"],
                         r["ficha_tecnica_original"], r["marca_original"], r["categoria_sitio"], r["via"]))
            aid = con.execute("SELECT anuncio_id FROM anuncios WHERE comercio_id=? AND sku=?", (cid, r["sku"])).fetchone()[0]
            disponible = int(bool(r["disponible"]))
            cur = con.execute("""INSERT OR IGNORE INTO observaciones(ejecucion_id, comercio_id, anuncio_id, fecha_hora_consulta,
                                 fecha_consulta, precio, precio_lista, es_promocion, disponible, estado_disponibilidad, raw_archivo)
                                 VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                              (ejec, cid, aid, r["fecha_hora_consulta"], str(r["fecha_hora_consulta"])[:10], r["precio"],
                               r["precio_lista"], int(r["es_promocion"] or 0), disponible,
                               "disponible" if disponible else "agotado", r.get("raw_archivo")))
            nuevas += cur.rowcount
        ahora = ahora_iso()
        for r in rechazadas.to_dict("records"):
            r = {k: _vacio_a_none(v) for k, v in r.items()}
            precio = r.get("precio")
            try:
                precio = float(precio) if precio is not None else None
            except (TypeError, ValueError):
                precio = None
            con.execute("""INSERT INTO observaciones_rechazadas(ejecucion_id, comercio_id, sku, url, fecha_hora_consulta, precio,
                           disponible, motivo, datos_json, fecha_rechazo) VALUES (?,?,?,?,?,?,?,?,?,?)""",
                        (ejec, cid, None if r.get("sku") is None else str(r["sku"]), r.get("url"),
                         r.get("fecha_hora_consulta"), precio, r.get("disponible"), r["motivo"], _json_fila(r), ahora))
        # Anuncios nuevos: clasificar y enlazar con el catálogo de comparables (sin reconstruirlo).
        L.normalizar_anuncios(con, solo_pendientes=True, commit=False)
        L.asignar_comparables_existentes(con, commit=False)
        faltan = db.productos_comparables_faltantes(con, ejec, cid) if estado != "fallida" else []
        if faltan:
            if estado == "completa":
                estado = "parcial"
            notas.append(f"Faltan {len(faltan)} producto(s) comparable(s) en esta ejecución: " + "; ".join(faltan))
        if len(rechazadas):
            notas.append(f"{len(rechazadas)} observación(es) rechazadas por validación (ver observaciones_rechazadas)")
        con.execute("UPDATE ejecuciones SET estado=?, notas=? WHERE ejecucion_id=? AND comercio_id=?",
                    (estado, "; ".join(notas) or None, ejec, cid))
        con.execute("COMMIT")
    except BaseException:
        if con.in_transaction:
            con.execute("ROLLBACK")
        raise
    res = {"comercio": clave, "comercio_nombre": COMERCIOS[clave].nombre, "ejecucion_id": ejec, "estado": estado,
           "registros": len(df), "obs_nuevas": nuevas, "rechazadas": len(rechazadas),
           "faltan_comparables": faltan, "motivo": "; ".join(notas) or None}
    res.update(db.resumen_ejecucion(con, ejec, cid))
    return res


def registrar_fallo(con, clave: str, ejec: str, meta: dict, modo: str = "en_linea") -> None:
    """Deja constancia de un comercio cuya ejecución falló (en su propia transacción)."""
    con.execute("BEGIN IMMEDIATE")
    try:
        cid = _comercio_id(con, clave)
        con.execute("""INSERT INTO ejecuciones(ejecucion_id, comercio_id, inicio, fin, n_registros, estado, modo, notas)
                       VALUES (?,?,?,?,0,'fallida',?,?)
                       ON CONFLICT(ejecucion_id, comercio_id) DO UPDATE SET fin=excluded.fin, estado='fallida', notas=excluded.notas""",
                    (ejec, cid, meta.get("inicio", ahora_iso()), ahora_iso(), modo, "; ".join(meta.get("notas", [])) or None))
        con.execute("COMMIT")
    except BaseException:
        if con.in_transaction:
            con.execute("ROLLBACK")
        raise


# --------------------------------------------------------------------------------------
# Funciones generales
# --------------------------------------------------------------------------------------
def _resultado_fallido(clave: str, ejec: str, motivo: str) -> dict:
    return {"comercio": clave, "comercio_nombre": COMERCIOS[clave].nombre, "ejecucion_id": ejec, "estado": "fallida",
            "registros": 0, "obs_nuevas": 0, "rechazadas": 0, "nuevos": 0, "cambios_precio": 0, "no_observados": 0,
            "faltan_comparables": [], "motivo": motivo}


def recolectar_comercio(clave: str, db_path: str | Path = DB_DEFECTO, raw_dir: str | Path = RAW_DEFECTO,
                        ejecucion_id: str | None = None, cliente: Cliente | None = None,
                        modo: str = "en_linea") -> dict:
    """
    Recolecta, valida e inserta UN comercio (es la función que llama el botón de la aplicación, comercio por comercio,
    para mostrar el avance). Tolera fallas: si el comercio falla (red, bloqueo, cambio de estructura) queda registrado
    como 'fallida'/'parcial' con el motivo y se devuelve un resumen; no lanza excepciones por errores del sitio.
    """
    if clave not in FUNCIONES:
        raise KeyError(f"Comercio desconocido: {clave}")
    ejec = ejecucion_id or nueva_ejecucion_id()
    cliente = cliente or Cliente()
    try:
        df = FUNCIONES[clave](cliente, ejec, Path(raw_dir))
    except Exception as e:  # noqa: BLE001  (los scrapers capturan sus errores; esto es una red de seguridad)
        log.error("%s: %s", clave, e)
        df = pd.DataFrame(columns=COLUMNAS)
        df.attrs["meta"] = {"inicio": ahora_iso(), "notas": [f"{type(e).__name__}: {e}"], "estado": "fallida"}
    df.attrs["meta"] = _meta_basica(df, clave, ejec)
    con = conectar(db_path)
    try:
        if df.empty:
            registrar_fallo(con, clave, ejec, df.attrs["meta"], modo)
            return _resultado_fallido(clave, ejec, "; ".join(df.attrs["meta"]["notas"]) or "El comercio no devolvió productos")
        try:
            return insertar_resultado(con, df, modo)
        except Exception as e:  # noqa: BLE001  (la transacción ya se revirtió)
            motivo = f"Inserción revertida: {type(e).__name__}: {e}"
            log.error("%s: %s", clave, motivo)
            registrar_fallo(con, clave, ejec, {"inicio": df.attrs["meta"]["inicio"], "notas": [motivo]}, modo)
            return _resultado_fallido(clave, ejec, motivo)
    finally:
        con.close()


def ejecutar_recoleccion(db_path=DB_DEFECTO, raw_dir=RAW_DEFECTO, comercios=None,
                         cliente: Cliente | None = None, ejecucion_id: str | None = None) -> pd.DataFrame:
    """Recolección completa en línea: un comercio tras otro bajo el mismo identificador de ejecución."""
    comercios = comercios or COMERCIOS_ACTIVOS
    cliente = cliente or Cliente()
    ejec = ejecucion_id or nueva_ejecucion_id()
    resumen = []
    for clave in comercios:
        log.info("== %s (%s)", clave, ejec)
        resumen.append(recolectar_comercio(clave, db_path, raw_dir, ejec, cliente, "en_linea"))
    return pd.DataFrame(resumen)


def reprocesar_raw(db_path=DB_DEFECTO, raw_dir=RAW_DEFECTO, fecha: str | None = None, comercios=None,
                   ejecucion_id: str | None = None, forzar: bool = False) -> pd.DataFrame:
    """
    Modo sin conexión: reconstruye la base SOLO desde raw/ (no consulta ningún sitio). Las ejecuciones que ya están
    en la base se omiten (estado 'ya_cargada') salvo `forzar=True`; así reprocesar nunca pisa datos existentes y,
    aun forzado, las restricciones UNIQUE impiden duplicar observaciones.
    """
    raw_dir = Path(raw_dir)
    if not raw_dir.is_dir():
        raise FileNotFoundError(f"No existe la carpeta de copias crudas '{raw_dir.name}/'.")
    con = conectar(db_path)
    try:
        existentes = {(r[0], r[1]) for r in con.execute(
            "SELECT e.ejecucion_id, c.clave FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id")}
        grupos: dict[tuple, list] = {}
        omitidos: set[tuple] = set()
        for ruta in sorted(raw_dir.glob("*/*/*.json.gz")):
            ejec, clave = ruta.name.split("__")[0], ruta.parent.parent.name
            if clave not in COMERCIOS or (comercios and clave not in comercios) or (ejecucion_id and ejec != ejecucion_id):
                continue
            if fecha and ruta.parent.name != fecha:
                continue
            if (ejec, clave) in existentes and not forzar:
                omitidos.add((ejec, clave))
                continue
            grupos.setdefault((ejec, clave), []).append((leer_raw(ruta), ruta))
        resumen = [{"comercio": c, "comercio_nombre": COMERCIOS[c].nombre, "ejecucion_id": e, "estado": "ya_cargada",
                    "registros": 0, "obs_nuevas": 0, "rechazadas": 0, "nuevos": 0, "cambios_precio": 0,
                    "no_observados": 0, "faltan_comparables": [], "motivo": "Ya estaba en la base; no se modificó"}
                   for (e, c) in sorted(omitidos)]
        for (ejec, clave), pares in grupos.items():
            cfg = COMERCIOS[clave]
            pares.sort(key=lambda p: (p[0].get("consulta", ""), str(p[1])))       # orden real de captura
            manifiesto = next((e["manifiesto"] for e, _ in pares if "manifiesto" in e),
                              {"inicio": pares[0][0]["consulta"], "notas": []})
            filas: dict[str, dict] = {}
            for e, ruta in pares:
                if "respuesta" not in e:
                    continue
                items, _ = _items_y_total(e["respuesta"], None, e["modo"])
                for p in items:
                    for fila in parsear_producto(p, cfg, e["etiqueta"]):
                        fila["fecha_hora_consulta"], fila["ejecucion_id"] = e["consulta"], ejec
                        fila["raw_archivo"] = _ref_raw(ruta, raw_dir)
                        if fila["sku"] in filas:
                            filas[fila["sku"]]["via"] += "|" + e["etiqueta"]
                        else:
                            filas[fila["sku"]] = fila
            df = pd.DataFrame(list(filas.values()))
            for c in COLUMNAS:
                if c not in df.columns:
                    df[c] = None
            df = df[COLUMNAS]
            manifiesto.update({"ejecucion_id": ejec, "clave": clave})
            df.attrs["meta"] = manifiesto
            if df.empty:
                registrar_fallo(con, clave, ejec, manifiesto, "sin_conexion")
                resumen.append(_resultado_fallido(clave, ejec, "; ".join(manifiesto.get("notas", [])) or "Sin datos en raw/"))
                continue
            try:
                resumen.append(insertar_resultado(con, df, "sin_conexion"))
            except Exception as e:  # noqa: BLE001
                resumen.append(_resultado_fallido(clave, ejec, f"Inserción revertida: {type(e).__name__}: {e}"))
    finally:
        con.close()
    return pd.DataFrame(resumen)


def probar_sitios(comercios=None) -> None:
    """Diagnóstico rápido: robots.txt, modo de API, categorías detectadas y total del sitio."""
    cli = Cliente(pausa=0.5)
    for clave in comercios or COMERCIOS_ACTIVOS:
        cfg = COMERCIOS[clave]
        print(f"\n=== {cfg.nombre} ({cfg.base_url})")
        try:
            robots = cli.get_text(cfg.base_url + "/robots.txt")
            print("robots.txt (primeras líneas):", " | ".join(robots.splitlines()[:6]))
        except Exception as e:  # noqa: BLE001
            print("robots.txt no disponible:", e)
        try:
            cfg.modo = detectar_modo(cli, cfg)
            print("modo API:", cfg.modo)
            if cfg.modo == "legacy":
                for n in descubrir_categorias(cli, cfg):
                    url, params = _url_y_params(cfg, "legacy", {"tipo": "categoria", "valor": "C:/" + "/".join(n["ruta_ids"]) + "/"}, 0)
                    _, h, _ = cli.get_json(url, params)
                    print("  categoría:", n["ruta"], "-> total sitio:", h.get("resources"))
        except Exception as e:  # noqa: BLE001
            print("ERROR:", e)


def diagnosticar(objetivos=None) -> None:
    """
    Diagnóstico detallado: para cada comercio (clave de COMERCIOS o URL base) prueba la página principal, robots.txt,
    los dos endpoints VTEX y el árbol de categorías, e imprime código HTTP, servidor y los primeros bytes de la
    respuesta. Sirve para entender POR QUÉ un sitio no responde (bloqueo 403, timeout, otra plataforma, etc.).
    Uso:  python scraper.py diagnose            (comercios activos)
          python scraper.py diagnose https://www.locatelcolombia.com https://www.carulla.com
    """
    s = requests.Session()
    s.headers.update(Cliente().s.headers)
    for obj in objetivos or COMERCIOS_ACTIVOS:
        base = COMERCIOS[obj].base_url if obj in COMERCIOS else obj.rstrip("/")
        print(f"\n=== {obj}  ({base})")
        pruebas = [
            ("portada", "/"), ("robots.txt", "/robots.txt"),
            ("vtex legacy", "/api/catalog_system/pub/products/search?ft=pa%C3%B1ales&_from=0&_to=1"),
            ("vtex intelligent", "/api/io/_v/api/intelligent-search/product_search?query=pa%C3%B1ales&page=1&count=2&locale=es-CO"),
            ("arbol categorias", "/api/catalog_system/pub/category/tree/1"),
        ]
        for nombre, ruta in pruebas:
            t0 = time.time()
            try:
                r = s.get(base + ruta, timeout=20, headers={"Referer": base + "/"})
                print(f"  {nombre:17} HTTP {r.status_code}  {r.headers.get('content-type', '')[:28]:28} "
                      f"server={r.headers.get('server')}  {len(r.content)} bytes  {time.time() - t0:.1f}s  :: {r.text[:90]!r}")
            except Exception as e:  # noqa: BLE001
                print(f"  {nombre:17} ERROR {type(e).__name__} tras {time.time() - t0:.1f}s: {str(e)[:140]}")
            time.sleep(0.7)


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    orden = sys.argv[1] if len(sys.argv) > 1 else "run"
    if orden == "probe":
        probar_sitios()
    elif orden == "diagnose":
        diagnosticar(sys.argv[2:] or None)
    elif orden == "offline":
        print(reprocesar_raw().to_string())
    else:
        print(ejecutar_recoleccion(comercios=sys.argv[2:] or None).to_string())
