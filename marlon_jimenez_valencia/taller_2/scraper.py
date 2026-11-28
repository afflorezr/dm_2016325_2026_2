"""
scraper.py — Módulo de extracción del Taller 1 de Minería de Datos (UNAL, 2026-2),
reutilizado y ampliado en el Taller 2.

Cambios del Taller 2 (la extracción de cada comercio es la misma del Taller 1):
  * La actualización de un comercio se parte en dos pasos, para que la aplicación
    muestre el avance comercio por comercio:
        recolectar_comercio()  -> consulta el sitio (o lee raw/) y devuelve los datos
        guardar_comercio()     -> valida (validacion.py) e inserta en UNA transacción
    actualizar_comercio() hace los dos pasos y devuelve el resumen del comercio.
  * limpiar_precio(): convierte un precio publicado (número o texto) a número.
  * MAX_PETICIONES: tope de peticiones por comercio y ejecución.
  * El esquema de la base está en esquema.sql.
  * Las observaciones que no pasan la validación van a la tabla rechazos, y cada
    cambio en un campo estandarizado de un anuncio queda en la tabla correcciones.
  * Cafam (noviembre de 2026): las subcategorías de más de 600 productos se parten
    por grupos de marcas y no por rango de precio, porque el filtro de precio deja
    por fuera los productos agotados (ver MAXIMO_LISTADO_HTML).

Categoría: Medicamentos antiinfecciosos de uso sistémico.
Comercios: La Rebaja Virtual, Locatel Colombia y Droguerías Cafam.
           (Colsubsidio queda implementado como comercio de respaldo.)

Los cuatro sitios usan la plataforma VTEX.

Cafam: su robots.txt prohíbe /api/, así que leemos sus páginas de categoría
(HTML), que sí están permitidas: /salud-y-medicamentos/<subcategoría>?page=N.
Cada página trae sus 12 productos en un bloque JSON llamado __STATE__
(ver _descargar_cafam).

La Rebaja y Locatel: la página de cada comercio carga sus productos desde el
servicio interno de catálogo de VTEX, que su robots.txt permite:

    GET {sitio}/api/catalog_system/pub/products/search
        ?fq=C:/<ids de la categoría>/      (filtro por categoría)
        &fq=P:[<min> TO <max>]              (filtro por rango de precio, opcional)
        &_from=<i>&_to=<j>                  (paginación: máximo 50 por página)
        &O=OrderByNameASC                   (orden estable entre páginas)

La respuesta es JSON y trae el total en la cabecera HTTP `resources`
("0-49/4306" significa 4306 productos). VTEX no deja paginar más allá de la
posición ~2500, así que cuando una sección tiene más de 2500 productos se
parte por rangos de precio hasta que cada parte quede por debajo del límite.

Uso desde Python o desde la aplicación:
    import scraper
    scraper.ejecutar_recoleccion()                     # en línea
    scraper.ejecutar_recoleccion(sin_conexion=True)    # sin conexión, desde raw/

Uso desde la terminal:
    python scraper.py                  # en línea, los tres comercios
    python scraper.py --sin-conexion   # reprocesa todas las copias de raw/
"""
from __future__ import annotations

import argparse
import gzip
import html
import json
import math
import re
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, quote, urlencode, urlparse

import pandas as pd
import requests

import categoria
import limpieza
import validacion

# ---------------------------------------------------------------------------
# Configuración general
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "comparador_precios.sqlite"
RAW_DIR = BASE_DIR / "raw"
ESQUEMA_PATH = BASE_DIR / "esquema.sql"
CORRESPONDENCIA_PATH = BASE_DIR / "correspondencia.csv"

HORA_COLOMBIA = timezone(timedelta(hours=-5))   # Colombia no tiene horario de verano
PAUSA_SEGUNDOS = 1.0          # pausa entre peticiones (buena práctica)
TAMANO_PAGINA = 50            # máximo que acepta VTEX
LIMITE_PAGINACION = 2500      # VTEX responde 400 si _from supera ~2500
PRECIO_MAXIMO = 5_000_000     # cota superior (COP) para partir por rangos de precio
REINTENTOS = 4
# Taller 2: tope de peticiones por comercio en una ejecución. En octubre una
# ejecución completa usó unas 90 (La Rebaja), 75 (Locatel) y 420 (Cafam).
MAX_PETICIONES = 1000

CABECERAS = {
    "User-Agent": ("Mozilla/5.0 (compatible; TallerMineriaDatosUNAL/1.0; "
                   "uso academico; consulta 1 pagina por segundo)"),
    "Accept": "application/json",
    "Accept-Language": "es-CO,es;q=0.9",
}

COMERCIOS = {
    "larebaja": {
        "nombre": "La Rebaja Virtual (Copservir)",
        "nombre_corto": "La Rebaja",
        "url_base": "https://www.larebajavirtual.com",
        # El departamento DROGUERIA completo: los medicamentos con fórmula están
        # todos en una sola subcategoría, sin separar por grupo terapéutico.
        "secciones": [("C:/9/", "DROGUERIA")],
        "robots": "robots.txt (revisado 2026-10-02) no restringe /api/.",
    },
    "locatel": {
        "nombre": "Locatel Colombia",
        "nombre_corto": "Locatel",
        "url_base": "https://www.locatelcolombia.com",
        "secciones": [("C:/4/25/", "Drogueria > medicamentos"),
                      ("C:/4/28/", "Drogueria > Medicamentos Otc"),
                      ("C:/4/26/168/", "Drogueria > vitaminas > Antiinfecciosos")],
        "robots": "robots.txt (revisado 2026-10-02) no restringe /api/.",
    },
    "cafam": {
        "nombre": "Droguerías Cafam",
        "nombre_corto": "Cafam",
        "url_base": "https://www.drogueriascafam.com.co",
        "plataforma": "VTEX IO (páginas HTML de categoría)",
        # Se recorren las subcategorías de esta sección, cada una con menos de
        # 2500 productos (el máximo que deja paginar VTEX).
        "secciones": [("/salud-y-medicamentos", "Salud y medicamentos")],
        "robots": ("robots.txt (revisado 2026-10-03) prohíbe /api/ y los parámetros ?O=, ?PS=, "
                   "?q= y map=ft, pero no las páginas de categoría con ?page=N. Por eso se leen "
                   "esas páginas (HTML) y no el servicio /api/."),
    },
    "colsubsidio": {   # respaldo: no se usa por defecto
        "nombre": "Droguerías Colsubsidio",
        "nombre_corto": "Colsubsidio",
        "url_base": "https://www.drogueriascolsubsidio.com",
        "secciones": [("C:/1/", "Medicamentos")],
        "robots": ("robots.txt (revisado 2026-10-02) incluye 'Disallow: /api/' para "
                   "rastreadores."),
    },
}
COMERCIOS_POR_DEFECTO = ["larebaja", "locatel", "cafam"]

# Columnas que devuelve SIEMPRE cada función de comercio (mismo orden y formato)
COLUMNAS = [
    "comercio", "id_producto_comercio", "sku_comercio", "ean",
    "nombre_original", "nombre_sku_original", "texto_original",
    "marca_original", "laboratorio_original", "principio_activo_original",
    "presentacion_original", "unidad_medida_original", "cantidad_original",
    "via_original", "requiere_formula", "categoria_comercio",
    "url_producto", "url_extraccion",
    "precio", "precio_lista", "promocion", "disponible",
    "fecha_consulta", "id_ejecucion",
]


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def ahora_iso() -> str:
    """Fecha y hora actual de Colombia en ISO 8601, p. ej. 2026-10-02T10:35:00-05:00."""
    return datetime.now(HORA_COLOMBIA).replace(microsecond=0).isoformat()


def nuevo_id_ejecucion() -> str:
    return "E" + datetime.now(HORA_COLOMBIA).strftime("%Y%m%dT%H%M%S")


def _total_de_cabecera(resources: str | None) -> int | None:
    """'0-49/4306' -> 4306"""
    if not resources or "/" not in resources:
        return None
    try:
        return int(resources.split("/")[-1])
    except ValueError:
        return None


def _spec(p: dict, *nombres: str) -> str | None:
    """Valor de una especificación VTEX (vienen como listas). Une varios con ' | '."""
    for nombre in nombres:
        valor = p.get(nombre)
        if valor:
            if isinstance(valor, list):
                valor = " | ".join(str(v) for v in valor if v not in (None, ""))
            valor = str(valor).strip()
            if valor:
                return valor
    return None


def _guardar_json_gz(ruta: Path, objeto) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(ruta, "wt", encoding="utf-8") as f:
        json.dump(objeto, f, ensure_ascii=False)


def _leer_json_gz(ruta: Path):
    with gzip.open(ruta, "rt", encoding="utf-8") as f:
        return json.load(f)


def limpiar_precio(valor) -> float | None:
    """
    Convierte un precio publicado a número en COP (Taller 2, §9).

    - Si ya es un número (el JSON de VTEX trae Price como número), lo devuelve igual.
    - Si es texto, quita "$", "COP" y espacios, y lee el formato colombiano:
      "$ 12.900" -> 12900.0 ; "12.900,50" -> 12900.5 ; "1.234.567" -> 1234567.0
    - Si no hay precio o no se puede leer, devuelve None: un precio ausente nunca se
      convierte en 0. Que el precio sea mayor que 0 lo revisa validacion.py.
    """
    if valor is None or isinstance(valor, bool):
        return None
    if isinstance(valor, (int, float)):
        return None if math.isnan(valor) else float(valor)
    texto = re.sub(r"[^\d.,]", "", str(valor))
    if not re.search(r"\d", texto):
        return None
    if "," in texto and "." in texto:
        # el separador que aparece de último es el decimal: "12.900,50" o "12,900.50"
        decimal = "," if texto.rfind(",") > texto.rfind(".") else "."
        miles = "." if decimal == "," else ","
        texto = texto.replace(miles, "").replace(decimal, ".")
    elif "," in texto or "." in texto:
        separador = "," if "," in texto else "."
        partes = texto.split(separador)
        # "12.900" o "1.234.567": grupos de tres cifras = separador de miles
        if len(partes) > 2 or (len(partes[-1]) == 3 and partes[0] != ""):
            texto = texto.replace(separador, "")
        else:                          # "12.5" o "0,75": separador decimal
            texto = texto.replace(separador, ".")
    try:
        return float(texto)
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Peticiones HTTP
# ---------------------------------------------------------------------------
class LimitePeticiones(RuntimeError):
    """Se alcanzó MAX_PETICIONES en un comercio: la recolección se detiene."""


def _nueva_sesion() -> requests.Session:
    s = requests.Session()
    s.headers.update(CABECERAS)
    s.peticiones = 0          # Taller 2: contador para el tope MAX_PETICIONES
    return s


def _get(sesion: requests.Session, url: str, params: list[tuple],
         cabeceras: dict | None = None) -> requests.Response:
    """
    GET con reintentos y espera creciente ante 429/5xx o fallas de red.

    Los espacios se codifican como %20 y no como "+": el firewall de La Rebaja
    y Locatel responde 400 ("Scripts are not allowed!") a `P:[0+TO+500000]`.
    Otros errores 4xx no se reintentan, porque repetir la petición no los arregla.
    Cada intento cuenta para el tope MAX_PETICIONES de la sesión (una por comercio).
    """
    consulta = urlencode(params, quote_via=quote)
    url_completa = f"{url}?{consulta}" if consulta else url
    ultimo_error = None
    for intento in range(REINTENTOS):
        sesion.peticiones = getattr(sesion, "peticiones", 0) + 1
        if sesion.peticiones > MAX_PETICIONES:
            raise LimitePeticiones(f"se alcanzó el tope de {MAX_PETICIONES} peticiones "
                                   f"para este comercio; la recolección se detuvo")
        try:
            r = sesion.get(url_completa, timeout=40, headers=cabeceras)
            if r.status_code in (200, 206):
                return r
            if r.status_code in (429, 500, 502, 503, 504):
                ultimo_error = f"HTTP {r.status_code}"
            else:
                raise RuntimeError(f"No se pudo consultar {url_completa}: HTTP {r.status_code} "
                                   f"{r.text[:100]!r}")
        except requests.RequestException as e:   # incluye timeouts
            ultimo_error = repr(e)
        time.sleep(PAUSA_SEGUNDOS * 2 ** (intento + 1))
    raise RuntimeError(f"No se pudo consultar {url} {params}: {ultimo_error}")


def _contar(sesion, url_busqueda: str, filtros: list[str]) -> int:
    params = [("fq", f) for f in filtros] + [("_from", 0), ("_to", 0)]
    r = _get(sesion, url_busqueda, params)
    time.sleep(PAUSA_SEGUNDOS)
    total = _total_de_cabecera(r.headers.get("resources"))
    return total if total is not None else len(r.json())


def _num(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else f"{x:.2f}"


def _particionar(sesion, url_busqueda, fq_cat, minimo, maximo) -> list[tuple[list[str], int]]:
    """Parte una sección por rangos de precio hasta que cada parte sea paginable."""
    filtro_precio = f"P:[{_num(minimo)} TO {_num(maximo)}]"
    total = _contar(sesion, url_busqueda, [fq_cat, filtro_precio])
    if total <= LIMITE_PAGINACION or maximo - minimo < 1:
        return [([fq_cat, filtro_precio], total)] if total > 0 else []
    medio = round((minimo + maximo) / 2, 2)
    return (_particionar(sesion, url_busqueda, fq_cat, minimo, medio)
            + _particionar(sesion, url_busqueda, fq_cat, round(medio + 0.01, 2), maximo))


# ---------------------------------------------------------------------------
# Recolección genérica VTEX (en línea) y lectura de copias crudas (sin conexión)
# ---------------------------------------------------------------------------
def _descargar_vtex(clave: str, carpeta: Path, sesion=None) -> dict:
    """
    Recorre todas las secciones configuradas de un comercio, guarda cada
    respuesta en `carpeta` (JSON comprimido) y devuelve un manifiesto con los
    conteos que se usan para verificar que la recolección quedó completa.
    """
    cfg = COMERCIOS[clave]
    sesion = sesion or _nueva_sesion()
    url_busqueda = cfg["url_base"] + "/api/catalog_system/pub/products/search"
    carpeta.mkdir(parents=True, exist_ok=True)

    # Árbol de categorías: se guarda para documentar qué secciones se usaron.
    r_arbol = _get(sesion, cfg["url_base"] + "/api/catalog_system/pub/category/tree/4", [])
    _guardar_json_gz(carpeta / "arbol_categorias.json.gz",
                     {"url": r_arbol.url, "fecha_consulta": ahora_iso(), "respuesta": r_arbol.json()})
    time.sleep(PAUSA_SEGUNDOS)

    manifiesto = {"comercio": clave, "secciones": [], "paginas": 0, "errores": []}
    n_pagina = 0
    for fq_cat, nombre_seccion in cfg["secciones"]:
        total_seccion = _contar(sesion, url_busqueda, [fq_cat])
        consultas = ([([fq_cat], total_seccion)] if total_seccion <= LIMITE_PAGINACION
                     else _particionar(sesion, url_busqueda, fq_cat, 0, PRECIO_MAXIMO))
        manifiesto["secciones"].append({
            "fq": fq_cat, "nombre": nombre_seccion, "total_reportado": total_seccion,
            "particiones": [{"filtros": f, "total": t} for f, t in consultas],
        })
        for parte, (filtros, total) in enumerate(consultas):
            vistos, errores = set(), []
            for vuelta in (1, 2):
                for desde in range(0, total, TAMANO_PAGINA):
                    hasta = min(desde + TAMANO_PAGINA - 1, total - 1)
                    params = ([("fq", f) for f in filtros]
                              + [("_from", desde), ("_to", hasta), ("O", "OrderByNameASC")])
                    n_pagina += 1
                    try:
                        r = _get(sesion, url_busqueda, params)
                        productos = r.json()
                        vistos.update(str(p.get("productId")) for p in productos)
                        pagina = {"url": r.url, "status": r.status_code,
                                  "resources": r.headers.get("resources"),
                                  "fecha_consulta": ahora_iso(), "seccion": nombre_seccion,
                                  "respuesta": productos}
                        _guardar_json_gz(carpeta / f"pagina_{n_pagina:04d}.json.gz", pagina)
                    except LimitePeticiones:
                        raise
                    except Exception as e:   # se anota y se sigue con la siguiente página
                        errores.append({"pagina": n_pagina, "params": params, "error": repr(e)})
                    time.sleep(PAUSA_SEGUNDOS)
                # Si faltan productos, el catálogo cambió mientras pasábamos las páginas
                # (un producto se corrió de página y otro no alcanzó a salir). Damos una
                # segunda vuelta y juntamos lo que salga.
                if len(vistos) >= total:
                    break
            particion = manifiesto["secciones"][-1]["particiones"][parte]
            particion.update({"productos_distintos": len(vistos), "vueltas": vuelta})
            # Los errores de página solo cuentan si ni la segunda vuelta los cubrió. Si
            # faltan productos, _estado lo detecta al comparar la sección completa con
            # su total (un producto que cambió de precio pudo salir en otro rango).
            if len(vistos) < total:
                manifiesto["errores"].extend(errores)
    manifiesto["paginas"] = n_pagina
    return manifiesto


# ---------------------------------------------------------------------------
# Cafam: páginas de categoría en HTML (su robots.txt prohíbe /api/)
# ---------------------------------------------------------------------------
# Cafam usa VTEX IO. Cada página de categoría trae dentro del HTML un bloque
# "__STATE__ = {...}" con los 12 productos que muestra. Leemos ese bloque en vez
# del servicio /api/ y recorremos las páginas con "?page=N", que sí está permitido.
PRODUCTOS_POR_PAGINA_HTML = 12
# VTEX IO no muestra más de 50 páginas por listado (600 productos). Si una
# subcategoría tiene más, se parte en listados por grupos de marcas, por ejemplo
#     /salud-y-medicamentos/medicamentos-rx/mk/genfar?map=marca,marca
# (robots.txt no lo prohíbe; sí prohíbe initialMap=, map=ft, ?O=, ?PS= y ?q=).
# Hasta octubre se partía por rango de precio (?priceRange=A TO B), pero desde
# noviembre Cafam también lista productos agotados y ese filtro los deja por fuera.
MAXIMO_LISTADO_HTML = 50 * PRODUCTOS_POR_PAGINA_HTML
PRODUCTOS_POR_GRUPO = 500   # holgura bajo 600 por si un conteo cambia durante la corrida
MARCAS_POR_GRUPO = 80       # para que la dirección (URL) no quede demasiado larga


def _estado_de_html(texto: str) -> dict:
    """Saca el JSON que viene después de '__STATE__ = ' en el HTML."""
    inicio = texto.find("__STATE__ = ")
    if inicio < 0:
        raise ValueError("la página no trae el bloque __STATE__")
    estado, _ = json.JSONDecoder().raw_decode(texto, inicio + len("__STATE__ = "))
    return estado


def _clave_busqueda(estado: dict) -> str:
    """Clave del bloque que tiene la búsqueda de productos de la página."""
    return next(k for k, v in estado.items()
                if k.startswith("$ROOT_QUERY.productSearch(") and isinstance(v, dict) and "products" in v)


def _referencias(valor) -> list[str]:
    """Ids a los que apunta un valor del __STATE__ (ahí todo se guarda "aplanado")."""
    if isinstance(valor, dict):
        if valor.get("type") == "id" and "id" in valor:
            return [valor["id"]]
        return [r for v in valor.values() for r in _referencias(v)]
    if isinstance(valor, list):
        return [r for v in valor for r in _referencias(v)]
    return []


def _recortar_estado(estado: dict) -> dict:
    """
    Copia cruda que guardamos en raw/: la búsqueda de productos y todo lo que cuelga
    de ella (producto, SKU, vendedor, oferta, especificaciones). Dejamos por fuera las
    facetas de los filtros (la mitad del bloque) y el 'priceToken', que es una firma
    de la sesión y no un dato del producto.
    """
    guardar, pendientes = {}, [_clave_busqueda(estado)]
    while pendientes:
        clave = pendientes.pop()
        if clave in guardar or clave not in estado:
            continue
        valor = estado[clave]
        if isinstance(valor, dict) and "priceToken" in valor:
            valor = {k: v for k, v in valor.items() if k != "priceToken"}
        guardar[clave] = valor
        pendientes.extend(_referencias(valor))
    return guardar


def _productos_de_estado(estado: dict, url_base: str) -> list[dict]:
    """
    Pasa los productos del __STATE__ al mismo formato del servicio de catálogo de
    VTEX (el de La Rebaja y Locatel). Así _fila_base y _spec sirven igual para Cafam.
    """
    def ver(x):   # sigue una referencia del bloque
        if isinstance(x, dict) and x.get("type") == "id":
            return estado.get(x["id"], {})
        if isinstance(x, dict) and x.get("type") == "json":
            return x.get("json")
        return x

    productos = []
    for ref in estado[_clave_busqueda(estado)]["products"]:
        p = ver(ref)
        items = []
        # la página pide los SKU con el filtro FIRST_AVAILABLE: trae uno por producto
        clave_items = next((k for k in p if k.startswith("items")), None)
        for ref_item in p.get(clave_items) or []:
            item = ver(ref_item)
            vendedores = []
            for ref_vendedor in item.get("sellers") or []:
                vendedor = ver(ref_vendedor)
                oferta = {k: v for k, v in (ver(vendedor.get("commertialOffer")) or {}).items()
                          if not isinstance(v, (dict, list))}
                # la página no trae IsAvailable: está disponible si hay unidades
                oferta["IsAvailable"] = (oferta.get("AvailableQuantity") or 0) > 0
                vendedores.append({"sellerId": vendedor.get("sellerId"),
                                   "sellerDefault": vendedor.get("sellerDefault"),
                                   "commertialOffer": oferta})
            items.append({"itemId": item.get("itemId"), "name": item.get("name"),
                          "nameComplete": item.get("nameComplete"), "ean": item.get("ean"),
                          "sellers": vendedores})
        link = p.get("link") or ""
        producto = {"productId": p.get("productId"), "productName": p.get("productName"),
                    "brand": p.get("brand"), "description": p.get("description"),
                    "link": url_base + link if link.startswith("/") else link,
                    "categories": ver(p.get("categories")) or [], "items": items,
                    "allSpecifications": []}
        for ref_prop in p.get("properties") or []:
            prop = ver(ref_prop)
            if prop.get("name"):
                producto[prop["name"]] = ver(prop.get("values"))
                producto["allSpecifications"].append(prop["name"])
        productos.append(producto)
    return productos


def _grupos_de_marcas(marcas: list[tuple[str, int]]) -> list[dict]:
    """
    Junta las marcas de una subcategoría en grupos de máximo PRODUCTOS_POR_GRUPO
    productos y MARCAS_POR_GRUPO marcas. Se empieza por las marcas con más productos
    y cada una entra en el primer grupo donde quepa.
    """
    grupos = []   # cada grupo: {"marcas": [...], "productos": n}
    for marca, cantidad in sorted(marcas, key=lambda m: (-m[1], m[0])):
        caben = [g for g in grupos if g["productos"] + cantidad <= PRODUCTOS_POR_GRUPO
                 and len(g["marcas"]) < MARCAS_POR_GRUPO]
        if caben:
            grupo = caben[0]
        else:
            grupo = {"marcas": [], "productos": 0}
            grupos.append(grupo)
        grupo["marcas"].append(marca)
        grupo["productos"] += cantidad
    return grupos


def _descargar_cafam(clave: str, carpeta: Path, sesion=None) -> dict:
    """
    Recorre las subcategorías de "Salud y medicamentos" página por página y guarda
    en `carpeta` el bloque de productos de cada página. Devuelve el manifiesto.
    """
    cfg = COMERCIOS[clave]
    sesion = sesion or _nueva_sesion()
    carpeta.mkdir(parents=True, exist_ok=True)
    ruta_categoria, nombre_categoria = cfg["secciones"][0]

    def pedir(ruta, pagina, filtro=()):
        params = list(filtro) + [("page", pagina)]
        r = _get(sesion, f"{cfg['url_base']}{ruta}", params, cabeceras={"Accept": "text/html"})
        time.sleep(PAUSA_SEGUNDOS)
        return r.url, r.status_code, _estado_de_html(r.text)

    # 1. Primera página de la sección: el total que muestra el sitio y las subcategorías
    url, _, estado = pedir(ruta_categoria, 1)
    total_sitio = estado[_clave_busqueda(estado)]["recordsFiltered"]
    subcategorias = sorted({(v["value"], v["name"], v["quantity"]) for v in estado.values()
                            if isinstance(v, dict) and v.get("key") == "category-2"})
    _guardar_json_gz(carpeta / "subcategorias.json.gz", {
        "url": url, "fecha_consulta": ahora_iso(), "seccion": nombre_categoria,
        "total_reportado": total_sitio,
        "subcategorias": [{"ruta": f"{ruta_categoria}/{s}", "nombre": n, "cantidad": c}
                          for s, n, c in subcategorias]})

    manifiesto = {"comercio": clave, "secciones": [], "paginas": 0, "errores": [],
                  "total_sitio": total_sitio,
                  "nota": "páginas HTML de categoría (?page=N); en raw/ se guarda el bloque "
                          "__STATE__ con los productos de cada página"}
    # 2. Listados que se van a recorrer: uno por subcategoría o, si la subcategoría
    #    tiene más de 600 productos, uno por grupo de marcas. Las marcas y cuántos
    #    productos tiene cada una salen de la faceta "Marca" que muestra el sitio
    #    (esa faceta sí cuenta los productos agotados).
    listados = []   # (ruta, nombre, filtro)
    for slug, nombre, cantidad in subcategorias:
        ruta = f"{ruta_categoria}/{slug}"
        if cantidad <= MAXIMO_LISTADO_HTML:
            listados.append((ruta, nombre, []))
            continue
        _, _, estado = pedir(ruta, 1)
        marcas = {(v["value"], v["quantity"]) for v in estado.values()
                  if isinstance(v, dict) and v.get("key") == "brand"}
        if sum(q for _, q in marcas) < cantidad:
            manifiesto["errores"].append({"seccion": nombre,
                                          "error": "las marcas no cubren la subcategoría"})
        grupos = _grupos_de_marcas(list(marcas))
        for i, grupo in enumerate(grupos, start=1):
            if grupo["productos"] > MAXIMO_LISTADO_HTML:
                manifiesto["errores"].append({"seccion": nombre,
                                              "error": f"la marca {grupo['marcas'][0]} pasa de 600 productos"})
            listados.append((f"{ruta}/{'/'.join(grupo['marcas'])}",
                             f"{nombre} [marcas, grupo {i} de {len(grupos)}]",
                             [("map", ",".join(["marca"] * len(grupo["marcas"])))]))

    n_pagina = 0
    # 3. Cada listado, página por página. El orden de la página es "por
    #    relevancia" (robots.txt no deja cambiarlo con ?O=), así que si al final
    #    faltan productos damos una segunda vuelta y juntamos lo que salga.
    for ruta, nombre, filtro in listados:
        vistos, total, n_paginas, errores = set(), None, None, []
        for vuelta in (1, 2):
            pagina = 1
            while n_paginas is None or pagina <= n_paginas:
                n_pagina += 1
                try:
                    url, status, estado = pedir(ruta, pagina, filtro)
                    busqueda = estado[_clave_busqueda(estado)]
                    total = busqueda["recordsFiltered"]
                    n_paginas = math.ceil(total / PRODUCTOS_POR_PAGINA_HTML)
                    vistos.update(ref["id"] for ref in busqueda["products"])
                    _guardar_json_gz(carpeta / f"pagina_{n_pagina:04d}.json.gz", {
                        "url": url, "status": status, "fecha_consulta": ahora_iso(),
                        "seccion": nombre, "estado": _recortar_estado(estado)})
                except LimitePeticiones:
                    raise
                except Exception as e:   # se anota y se sigue con la siguiente página
                    errores.append({"pagina": n_pagina, "url": f"{cfg['url_base']}{ruta}",
                                    "filtro": filtro, "page": pagina, "error": repr(e)})
                    if n_paginas is None:
                        break
                pagina += 1
            if total is not None and len(vistos) >= total:
                break
        completa = total is not None and len(vistos) >= total
        manifiesto["secciones"].append({"fq": ruta, "filtro": filtro, "nombre": nombre,
                                        "total_reportado": total or 0, "vueltas": vuelta,
                                        "errores_recuperados": len(errores) if completa else 0})
        # si faltan productos, _estado lo detecta al contar por sección; aquí solo
        # se anotan las peticiones que fallaron
        if not completa:
            manifiesto["errores"].extend(errores)
    manifiesto["paginas"] = n_pagina
    return manifiesto


def _leer_paginas(carpeta: Path) -> list[dict]:
    return [_leer_json_gz(ruta) for ruta in sorted(carpeta.glob("pagina_*.json.gz"))]


def _oferta(item: dict) -> dict:
    vendedores = item.get("sellers") or []
    vendedor = next((s for s in vendedores if s.get("sellerDefault")), vendedores[0] if vendedores else {})
    return vendedor.get("commertialOffer") or {}


def _texto_original(p: dict, item: dict) -> str:
    """Texto del anuncio tal como se publicó: nombre, nombre del SKU, descripción y ficha."""
    especificaciones = {k: p.get(k) for k in (p.get("allSpecifications") or [])
                        if not k.startswith("ML_")}   # ML_* = campos internos de sincronización
    return json.dumps({
        "nombre": p.get("productName"),
        "nombre_sku": item.get("nameComplete") or item.get("name"),
        "descripcion": p.get("description"),
        "especificaciones": especificaciones,
    }, ensure_ascii=False)


def _fila_base(clave: str, p: dict, item: dict, pagina: dict, id_ejecucion: str) -> dict:
    oferta = _oferta(item)
    precio = limpiar_precio(oferta.get("Price"))
    lista = limpiar_precio(oferta.get("ListPrice")) or limpiar_precio(oferta.get("PriceWithoutDiscount"))
    disponible = bool(oferta.get("IsAvailable"))
    if precio is None or (precio == 0 and not disponible):
        precio = None                       # nunca se reemplaza un faltante por 0
    if lista == 0:
        lista = None
    promocion = None if precio is None or lista is None else int(precio < lista)
    return {
        "comercio": clave,
        "id_producto_comercio": str(p.get("productId")),
        "sku_comercio": str(item.get("itemId")),
        "ean": (item.get("ean") or None),
        "nombre_original": p.get("productName"),
        "nombre_sku_original": item.get("nameComplete") or item.get("name"),
        "texto_original": _texto_original(p, item),
        "marca_original": p.get("brand"),
        "categoria_comercio": (p.get("categories") or [None])[0],
        "url_producto": p.get("link"),
        "url_extraccion": pagina.get("url"),
        "precio": float(precio) if precio is not None else None,
        "precio_lista": float(lista) if lista is not None else None,
        "promocion": promocion,
        "disponible": int(disponible),
        "fecha_consulta": pagina.get("fecha_consulta"),
        "id_ejecucion": id_ejecucion,
    }


def _via_desde_descripcion(descripcion: str | None) -> str | None:
    """
    Locatel escribe la vía en la descripción de varias formas: "Vía de administración:
    Oral", "Vía Oftálmica", "Via otica", "Gotas óticas". Tomamos la primera mención
    que sea una vía conocida (así no confundimos "vía urinaria" con una vía).
    """
    if not descripcion:
        return None
    texto = categoria.normalizar(re.sub(r"<[^>]+>", " ", html.unescape(descripcion)))
    for m in re.finditer(r"\bvia\s+(?:de\s+)?(?:administracion\s*)?:?\s*(?:via\s+)?([a-z]+)", texto):
        via = m.group(1).upper()
        if via.startswith(categoria.VIAS_SISTEMICAS + categoria.VIAS_LOCALES):
            return via
    if re.search(r"gotas\s+o(?:p)?ticas", texto):      # Locatel escribe a veces "ópticas"
        return "OTICA"
    if re.search(r"gotas\s+oftalmicas|solucion\s+oftalmica", texto):
        return "OFTALMICA"
    return None


def _principio_desde_descripcion(descripcion: str | None) -> str | None:
    """
    Algunos productos de Locatel no traen la ficha "Principio activo", pero lo
    escriben en la descripción: 'Principio Activo: CEFALEXINA Registro Sanitario: ...'
    o 'Principio activo": ["ITRACONAZOL, SECNIDAZOL"]'. Pedimos los dos puntos para
    no tomar frases como "alergia al principio activo o a los excipientes".
    """
    if not descripcion:
        return None
    texto = " ".join(re.sub(r"<[^>]+>", " ", html.unescape(descripcion)).split())
    m = re.search(r'principio\s+activo"?\s*:\s*\[?\s*"?\s*([^"\]\[:;]{3,80}?)\s*(?:"|\]|registro|$)',
                  texto, re.I)
    return m.group(1).strip(" .,") if m else None


def _a_dataframe(filas: list[dict], manifiesto: dict) -> pd.DataFrame:
    # Taller 2: dtype=object para que un dato faltante siga siendo None, como en el
    # Taller 1 (pandas 2). Con pandas 3 las columnas de texto pasan a ser de tipo
    # "str" y un faltante se vuelve NaN, que limpieza.py leía como el número NaN.
    df = pd.DataFrame(filas, columns=COLUMNAS, dtype=object)
    df.attrs["manifiesto"] = manifiesto
    return df


def _recolectar(clave: str, mapear, id_ejecucion: str, carpeta: Path,
                sin_conexion: bool, sesion=None, descargar=None) -> pd.DataFrame:
    """Flujo común: descargar (o leer raw/) y convertir cada SKU en una fila."""
    if sin_conexion:
        manifiesto = json.loads((carpeta / "manifest.json").read_text(encoding="utf-8"))
    else:
        manifiesto = (descargar or _descargar_vtex)(clave, carpeta, sesion)
    url_base = COMERCIOS[clave]["url_base"]
    filas, productos_vistos, skus_vistos, repetidos = [], set(), set(), 0
    por_seccion = {}   # productos distintos de cada sección, para verificar que esté completa
    huecos = {}        # Cafam: (sección, página) -> productos que faltan en cada vuelta
    for pagina in _leer_paginas(carpeta):
        productos = pagina.get("respuesta")
        if productos is None and "estado" in pagina:      # Cafam: bloque __STATE__ del HTML
            productos = _productos_de_estado(pagina["estado"], url_base)
            # Cafam a veces cuenta un producto que no muestra: una página trae 11 en
            # vez de 12. Se anota lo que falta en cada vuelta para revisarlo abajo.
            total = pagina["estado"][_clave_busqueda(pagina["estado"])]["recordsFiltered"]
            n = int(parse_qs(urlparse(pagina["url"]).query)["page"][0])
            esperados = min(PRODUCTOS_POR_PAGINA_HTML, total - PRODUCTOS_POR_PAGINA_HTML * (n - 1))
            huecos.setdefault((pagina.get("seccion"), n), []).append(max(esperados - len(productos), 0))
        for p in productos or []:
            productos_vistos.add(str(p.get("productId")))
            por_seccion.setdefault(pagina.get("seccion"), set()).add(str(p.get("productId")))
            for item in p.get("items") or []:
                # Un producto con varios SKU de distinto precio puede salir en dos
                # rangos de precio: se conserva solo la primera aparición.
                if str(item.get("itemId")) in skus_vistos:
                    repetidos += 1
                    continue
                skus_vistos.add(str(item.get("itemId")))
                fila = _fila_base(clave, p, item, pagina, id_ejecucion)
                fila.update(mapear(p, item))
                filas.append(fila)
    manifiesto["productos_unicos"] = len(productos_vistos)
    manifiesto["productos_por_seccion"] = {s: len(v) for s, v in por_seccion.items()}
    # Solo cuenta como "no mostrado por el sitio" si el hueco se repitió en las dos
    # vueltas (en la misma página). Si salió en una sola vuelta, no se descuenta.
    no_mostrados = {}
    for (seccion, _), faltan in huecos.items():
        if len(faltan) >= 2 and min(faltan) > 0:
            no_mostrados[seccion] = no_mostrados.get(seccion, 0) + min(faltan)
    if huecos:
        manifiesto["no_mostrados_por_seccion"] = no_mostrados
    manifiesto["skus"] = len(filas)
    manifiesto["skus_repetidos_descartados"] = repetidos
    return _a_dataframe(filas, manifiesto)


# ---------------------------------------------------------------------------
# Una función por comercio (todas devuelven las columnas de COLUMNAS)
# ---------------------------------------------------------------------------
def scrape_larebaja(id_ejecucion: str, carpeta: Path, sin_conexion: bool = False,
                    sesion=None) -> pd.DataFrame:
    def mapear(p, item):
        return {
            "laboratorio_original": _spec(p, "Proveedor", "ML_Laboratorio", "ML_Fabricante"),
            "principio_activo_original": _spec(p, "Principio activo"),
            "presentacion_original": _spec(p, "Presentacionunidadmedida", "Presentacion"),
            "unidad_medida_original": _spec(p, "Unidadmedida"),
            "cantidad_original": _spec(p, "Cantidadunidadesmedida"),
            "via_original": None,
            "requiere_formula": _spec(p, "Producto RX"),
        }
    return _recolectar("larebaja", mapear, id_ejecucion, carpeta, sin_conexion, sesion)


def scrape_locatel(id_ejecucion: str, carpeta: Path, sin_conexion: bool = False,
                   sesion=None) -> pd.DataFrame:
    def mapear(p, item):
        return {
            "laboratorio_original": None,          # Locatel no publica el laboratorio
            "principio_activo_original": (_spec(p, "Principio activo")
                                          or _principio_desde_descripcion(p.get("description"))),
            "presentacion_original": " | ".join(x for x in (item.get("name"), _spec(p, "Presentación")) if x),
            "unidad_medida_original": _spec(p, "PUM - Unidad de Medida"),
            "cantidad_original": _spec(p, "PUM - Medida"),
            "via_original": _via_desde_descripcion(p.get("description")),
            "requiere_formula": None,
        }
    return _recolectar("locatel", mapear, id_ejecucion, carpeta, sin_conexion, sesion)


def scrape_cafam(id_ejecucion: str, carpeta: Path, sin_conexion: bool = False,
                 sesion=None) -> pd.DataFrame:
    def mapear(p, item):
        return {
            "laboratorio_original": _spec(p, "Laboratorio fabricante"),
            "principio_activo_original": _spec(p, "Principio activo"),
            "presentacion_original": " | ".join(x for x in (_spec(p, "Presentación"), _spec(p, "Unidades por Empaque"),
                                                            _spec(p, "Contenido")) if x),
            "unidad_medida_original": _spec(p, "Unidad de medida"),
            "cantidad_original": _spec(p, "Cantidad por unidad de medida"),
            "via_original": _spec(p, "Vía de administración"),
            "requiere_formula": _spec(p, "Requiere prescripción médica"),
        }
    return _recolectar("cafam", mapear, id_ejecucion, carpeta, sin_conexion, sesion,
                       descargar=_descargar_cafam)


def scrape_colsubsidio(id_ejecucion: str, carpeta: Path, sin_conexion: bool = False,
                       sesion=None) -> pd.DataFrame:
    def mapear(p, item):
        return {
            "laboratorio_original": None,
            "principio_activo_original": " ".join(x for x in (_spec(p, "Principio Activo"), _spec(p, "Concentración")) if x) or None,
            "presentacion_original": _spec(p, "Presentación"),
            "unidad_medida_original": "UNIDAD" if _spec(p, "Unidades") else None,
            "cantidad_original": _spec(p, "Unidades"),
            "via_original": None,
            "requiere_formula": _spec(p, "Producto Formulado", "Aplica Formula"),
        }
    return _recolectar("colsubsidio", mapear, id_ejecucion, carpeta, sin_conexion, sesion)


FUNCIONES = {
    "larebaja": scrape_larebaja,
    "locatel": scrape_locatel,
    "cafam": scrape_cafam,
    "colsubsidio": scrape_colsubsidio,
}


# ---------------------------------------------------------------------------
# Base de datos SQLite
# ---------------------------------------------------------------------------
# El esquema (tablas, índices y vistas) está en esquema.sql.
ESQUEMA = ESQUEMA_PATH.read_text(encoding="utf-8")

# Campos de la tabla anuncios que se guardan desde el scraper
CAMPOS_ANUNCIO = ["id_comercio", "sku_comercio", "id_producto_comercio", "ean", "ean_valido",
                  "nombre_original", "marca_original", "laboratorio_original",
                  "principio_activo_original", "presentacion_original", "via_original",
                  "requiere_formula", "categoria_comercio", "url_producto",
                  "principio_activo_std", "subcategoria", "marca_std", "laboratorio_std",
                  "forma_std", "concentracion_std", "unidades", "contenido",
                  "unidad_contenido", "fuente_cantidad", "contenido_total", "unidad_normalizada"]
# Texto publicado por el comercio: si cambia, el anuncio cambió en el sitio
CAMPOS_ORIGINALES = ["nombre_original", "marca_original", "laboratorio_original",
                     "principio_activo_original", "presentacion_original", "via_original",
                     "categoria_comercio"]
# Campos calculados por categoria.py y limpieza.py: si cambian, se anota la corrección
CAMPOS_STD = ["principio_activo_std", "subcategoria", "marca_std", "laboratorio_std",
              "forma_std", "concentracion_std", "unidades", "contenido", "unidad_contenido",
              "fuente_cantidad", "contenido_total", "unidad_normalizada"]
# Columnas que no existían en el Taller 1: llenarlas por primera vez no es una corrección
CAMPOS_NUEVOS_TALLER_2 = {"contenido_total", "unidad_normalizada"}
CAMPOS_OBSERVACION = ["id_ejecucion", "id_comercio", "sku_comercio", "fecha_consulta", "precio",
                      "precio_lista", "promocion", "disponible", "url_extraccion",
                      "texto_original", "disponibilidad"]
CAMPOS_EJECUCION = ["id_ejecucion", "id_comercio", "inicio", "fin", "modo", "paginas",
                    "total_reportado_sitio", "productos_recorridos", "registros_categoria",
                    "excluidos", "estado", "detalle"]


def conectar(db_path: Path | str = DB_PATH) -> sqlite3.Connection:
    """
    Abre la base para ESCRIBIR y aplica esquema.sql (es idempotente: no borra datos).
    La aplicación lee con db.py, que abre la base en modo de solo lectura.
    """
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path, timeout=30)
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript(ESQUEMA)
    return con


def _registrar_comercios(con, claves) -> None:
    for clave in claves:
        cfg = COMERCIOS[clave]
        con.execute(
            """INSERT INTO comercios (id_comercio, nombre, url_base, plataforma, secciones,
                                      robots, nombre_corto, activo)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT (id_comercio) DO UPDATE SET
                   nombre = excluded.nombre, url_base = excluded.url_base,
                   plataforma = excluded.plataforma, secciones = excluded.secciones,
                   robots = excluded.robots, nombre_corto = excluded.nombre_corto,
                   activo = excluded.activo""",
            (clave, cfg["nombre"], cfg["url_base"], cfg.get("plataforma", "VTEX"),
             json.dumps(cfg["secciones"], ensure_ascii=False), cfg["robots"],
             cfg["nombre_corto"], int(clave in COMERCIOS_POR_DEFECTO)))


def _py(v):
    """Convierte valores de pandas/numpy a tipos que entiende sqlite3 (NaN -> NULL)."""
    if v is None:
        return None
    try:
        if pd.isna(v):
            return None
    except (TypeError, ValueError):
        pass
    if isinstance(v, bool):
        return int(v)
    return v.item() if hasattr(v, "item") else v


def _texto(v) -> str | None:
    """Valor como texto para comparar y para la tabla correcciones (20.0 -> '20')."""
    v = _py(v)
    if v is None:
        return None
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def registrar_correccion(con, tabla: str, registro: str, campo: str, anterior, nuevo,
                         motivo: str, origen: str) -> None:
    """Anota en la tabla correcciones un cambio a un dato que ya estaba en la base (§3.2)."""
    con.execute(
        """INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior,
                                     valor_nuevo, motivo, origen)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (ahora_iso(), tabla, registro, campo, _texto(anterior), _texto(nuevo), motivo, origen))


def _excluidos(df: pd.DataFrame) -> pd.DataFrame:
    """Antiinfecciosos (o productos de secciones antiinfecciosas) que quedan fuera."""
    return df[~df["incluido"].astype(bool) & (df["motivo_exclusion"] != "no es antiinfeccioso")]


def _procesar(df: pd.DataFrame) -> pd.DataFrame:
    """Aplica la delimitación de la categoría y la estandarización."""
    if df.empty:
        for c in ("incluido", "motivo_exclusion", "principio_activo_std", "subcategoria", "ean_valido"):
            df[c] = pd.Series(dtype=object)
        return df
    clasif = [categoria.clasificar(pa, n, pr, v, sec) for pa, n, pr, v, sec in zip(
        df["principio_activo_original"], df["nombre_original"], df["presentacion_original"],
        df["via_original"], df["categoria_comercio"])]
    clasif = pd.DataFrame(clasif, index=df.index)
    df = pd.concat([df, clasif], axis=1)
    df["ean_valido"] = df["ean"].map(limpieza.ean_valido).astype(int)
    return limpieza.estandarizar(df)


def _estado(manifiesto: dict) -> str:
    """
    'completa' si no hubo errores y CADA sección trae todos los productos que dice el
    sitio. Se revisa sección por sección porque un mismo producto puede estar en dos
    secciones (entonces los productos distintos suman menos que los totales).
    En Cafam se descuentan los productos que el sitio cuenta pero no muestra
    (confirmados en las dos vueltas, ver _recolectar).
    """
    if manifiesto.get("productos_unicos", 0) == 0:
        return "fallida"
    por_seccion = manifiesto.get("productos_por_seccion", {})
    no_mostrados = manifiesto.get("no_mostrados_por_seccion", {})
    falta_en_seccion = any(por_seccion.get(s["nombre"], 0) < s["total_reportado"] - no_mostrados.get(s["nombre"], 0)
                           for s in manifiesto["secciones"])
    falta_en_total = (manifiesto["productos_unicos"]
                      < manifiesto.get("total_sitio", 0) - sum(no_mostrados.values()))
    if manifiesto["errores"] or falta_en_seccion or falta_en_total:
        return "parcial"
    return "completa"


# ---------------------------------------------------------------------------
# Copias crudas y productos comparables
# ---------------------------------------------------------------------------
def carpeta_raw(clave: str, id_ejecucion: str, raw_dir: Path | str = RAW_DIR) -> Path:
    """raw/<comercio>/<AAAA-MM-DD>/<id_ejecucion>/ (la fecha es la del inicio de la ejecución)."""
    fecha = f"{id_ejecucion[1:5]}-{id_ejecucion[5:7]}-{id_ejecucion[7:9]}"
    return Path(raw_dir) / clave / fecha / id_ejecucion


def copias_en_raw(raw_dir: Path | str = RAW_DIR, comercios: list[str] | None = None) -> pd.DataFrame:
    """Copias crudas que se pueden reprocesar: una por ejecución y comercio con manifest.json."""
    filas = []
    for manifest in sorted(Path(raw_dir).glob("*/*/*/manifest.json")):
        carpeta = manifest.parent
        clave = carpeta.parent.parent.name
        if comercios and clave not in comercios:
            continue
        datos = json.loads(manifest.read_text(encoding="utf-8"))
        filas.append({"id_ejecucion": carpeta.name, "id_comercio": clave,
                      "estado": datos.get("estado"), "inicio": datos.get("inicio"),
                      "paginas": len(list(carpeta.glob("pagina_*.json.gz")))})
    columnas = ["id_ejecucion", "id_comercio", "estado", "inicio", "paginas"]
    return pd.DataFrame(filas, columns=columnas).sort_values(["id_ejecucion", "id_comercio"],
                                                              ignore_index=True)


def comparables_por_comercio(ruta_csv: Path | str = CORRESPONDENCIA_PATH) -> dict[str, dict[str, str]]:
    """{comercio: {sku: id_producto}} con las filas verificadas de correspondencia.csv."""
    if not Path(ruta_csv).exists():
        return {}
    corr = pd.read_csv(ruta_csv, dtype=str).fillna("")
    corr = corr[corr["verificado"].str.strip().isin(["1", "si", "sí", "SI", "Sí"])]
    resultado: dict[str, dict[str, str]] = {}
    for f in corr.itertuples(index=False):
        resultado.setdefault(f.id_comercio, {})[f.sku_comercio] = f.id_producto
    return resultado


# ---------------------------------------------------------------------------
# PASO 1: recolectar un comercio (en línea o desde raw/)
# ---------------------------------------------------------------------------
def recolectar_comercio(clave: str, id_ejecucion: str | None = None, sin_conexion: bool = False,
                        raw_dir: Path | str = RAW_DIR) -> tuple[pd.DataFrame, dict]:
    """
    En línea: consulta el sitio con la función del Taller 1 de ese comercio
    (scrape_larebaja, scrape_locatel o scrape_cafam) y guarda cada respuesta en
    raw/<comercio>/<fecha>/<id_ejecucion>/, con su manifest.json.
    Sin conexión: no consulta ningún sitio; vuelve a leer la copia cruda de esa ejecución.

    Devuelve (df, fila):
      df   una fila por SKU recorrido, clasificada (columna `incluido`) y estandarizada;
      fila la fila para la tabla ejecuciones.
    Si el sitio falla (red, bloqueo, cambio de estructura o tope de peticiones) NO se
    lanza la excepción: df queda vacío y fila queda 'fallida' con el motivo en `detalle`,
    para que la actualización siga con los demás comercios.
    """
    if id_ejecucion is None:
        if sin_conexion:
            raise ValueError("en modo sin conexión hay que indicar qué ejecución de raw/ reprocesar")
        id_ejecucion = nuevo_id_ejecucion()
    carpeta = carpeta_raw(clave, id_ejecucion, raw_dir)
    inicio = ahora_iso()
    modo = "sin_conexion" if sin_conexion else "en_linea"
    sesion = None if sin_conexion else _nueva_sesion()
    try:
        if sin_conexion and not (carpeta / "manifest.json").exists():
            raise FileNotFoundError(f"no hay copia cruda de {clave} para la ejecución {id_ejecucion}")
        df = FUNCIONES[clave](id_ejecucion, carpeta, sin_conexion=sin_conexion, sesion=sesion)
        manifiesto = df.attrs["manifiesto"]
        if not sin_conexion:
            manifiesto.update({"id_ejecucion": id_ejecucion, "inicio": inicio, "fin": ahora_iso(),
                               "peticiones": sesion.peticiones})
            manifiesto["estado"] = _estado(manifiesto)
            (carpeta / "manifest.json").write_text(
                json.dumps(manifiesto, ensure_ascii=False, indent=1), encoding="utf-8")
        df = _procesar(df)
        fila = {
            "id_ejecucion": id_ejecucion, "id_comercio": clave,
            "inicio": manifiesto.get("inicio", inicio), "fin": manifiesto.get("fin", ahora_iso()),
            "modo": modo, "paginas": manifiesto["paginas"],
            "total_reportado_sitio": (manifiesto.get("total_sitio")
                                      or sum(s["total_reportado"] for s in manifiesto["secciones"])),
            "productos_recorridos": manifiesto["productos_unicos"],
            "registros_categoria": int(df["incluido"].sum()) if len(df) else 0,
            "excluidos": len(_excluidos(df)) if len(df) else 0,
            "estado": manifiesto.get("estado") or _estado(manifiesto),
            "detalle": json.dumps({"errores": manifiesto["errores"][:20]}, ensure_ascii=False),
        }
    except Exception as e:   # el comercio falla, pero la actualización sigue con los demás
        df = pd.DataFrame(columns=COLUMNAS)
        fila = {"id_ejecucion": id_ejecucion, "id_comercio": clave, "inicio": inicio,
                "fin": ahora_iso(), "modo": modo, "paginas": getattr(sesion, "peticiones", None),
                "total_reportado_sitio": None, "productos_recorridos": 0,
                "registros_categoria": 0, "excluidos": 0, "estado": "fallida",
                "detalle": json.dumps({"error": str(e), "tipo": type(e).__name__},
                                      ensure_ascii=False)}
    return df, fila


# ---------------------------------------------------------------------------
# PASO 2: validar y guardar un comercio (una transacción)
# ---------------------------------------------------------------------------
def _registrar_ejecucion(con, fila: dict) -> None:
    """
    En línea: inserta (o actualiza) la fila de la ejecución.
    Sin conexión: la fila original de la ejecución NO se toca; solo se inserta si la
    base no la tenía (por ejemplo, al reconstruir una base vacía desde raw/).
    """
    columnas = ", ".join(CAMPOS_EJECUCION)
    marcas = ", ".join("?" * len(CAMPOS_EJECUCION))
    if fila["modo"] == "sin_conexion":
        accion = "DO NOTHING"
    else:
        accion = "DO UPDATE SET " + ", ".join(f"{c} = excluded.{c}" for c in CAMPOS_EJECUCION[2:])
    con.execute(f"INSERT INTO ejecuciones ({columnas}) VALUES ({marcas}) "
                f"ON CONFLICT (id_ejecucion, id_comercio) {accion}",
                [fila[c] for c in CAMPOS_EJECUCION])


def _guardar_anuncios(con, df: pd.DataFrame, clave: str) -> int:
    """
    Inserta los anuncios nuevos y actualiza los que ya estaban (upsert). Devuelve
    cuántos anuncios nuevos hubo.

    - Un anuncio solo se actualiza con su observación más reciente: si se reprocesa
      una ejecución vieja, sus textos no reemplazan los de una más nueva.
    - Si cambia un campo estandarizado (CAMPOS_STD) de un anuncio que ya estaba, el
      cambio se anota en correcciones, con el motivo de limpieza.MOTIVOS_CORRECCION o,
      si cambió el texto publicado, "el comercio cambió el texto del anuncio".
    """
    if df.empty:
        return 0
    datos = df.rename(columns={"comercio": "id_comercio"})
    actuales = pd.read_sql_query(
        """SELECT a.*, (SELECT MAX(o.fecha_consulta) FROM observaciones o
                        WHERE o.id_comercio = a.id_comercio
                          AND o.sku_comercio = a.sku_comercio) AS ultima_fecha
           FROM anuncios a WHERE a.id_comercio = ?""",
        con, params=[clave]).set_index("sku_comercio")
    actualizar = ", ".join(f"{c} = excluded.{c}" for c in CAMPOS_ANUNCIO[2:])
    sql = (f"INSERT INTO anuncios ({', '.join(CAMPOS_ANUNCIO)}) "
           f"VALUES ({', '.join('?' * len(CAMPOS_ANUNCIO))}) "
           f"ON CONFLICT (id_comercio, sku_comercio) DO UPDATE SET {actualizar}")
    nuevos = 0
    for fila in datos.to_dict("records"):
        sku = fila["sku_comercio"]
        valores = [_py(fila[c]) for c in CAMPOS_ANUNCIO]
        if sku not in actuales.index:
            con.execute(sql, valores)
            nuevos += 1
            continue
        anterior = actuales.loc[sku]
        if pd.notna(anterior["ultima_fecha"]) and fila["fecha_consulta"] < anterior["ultima_fecha"]:
            continue    # hay una observación más reciente de este anuncio: no se toca
        cambio_en_sitio = any(_texto(anterior[c]) != _texto(fila[c]) for c in CAMPOS_ORIGINALES)
        for campo in CAMPOS_STD:
            antes, ahora = _texto(anterior[campo]), _texto(fila[campo])
            if antes == ahora or (campo in CAMPOS_NUEVOS_TALLER_2 and antes is None):
                continue
            motivo = ("el comercio cambió el texto del anuncio; se recalculó con las reglas actuales"
                      if cambio_en_sitio else
                      limpieza.MOTIVOS_CORRECCION.get(campo, limpieza.MOTIVO_GENERAL))
            registrar_correccion(con, "anuncios", f"{clave}/{sku}", campo, antes, ahora,
                                 motivo, "scraper._guardar_anuncios")
        con.execute(sql, valores)
    return nuevos


def _guardar_observaciones(con, df: pd.DataFrame) -> int:
    """
    Inserta solo las observaciones que no existen. 'ON CONFLICT DO NOTHING' salta las
    repetidas (UNIQUE), pero deja que cualquier otra restricción (CHECK) produzca un
    error, que deshace la transacción del comercio.
    """
    if df.empty:
        return 0
    datos = df.rename(columns={"comercio": "id_comercio"}).copy()
    datos["disponibilidad"] = datos["disponible"].map({1: "disponible", 0: "agotado"})
    antes = con.total_changes
    con.executemany(
        f"INSERT INTO observaciones ({', '.join(CAMPOS_OBSERVACION)}) "
        f"VALUES ({', '.join('?' * len(CAMPOS_OBSERVACION))}) ON CONFLICT DO NOTHING",
        [tuple(_py(v) for v in fila) for fila in datos[CAMPOS_OBSERVACION].itertuples(index=False)])
    return con.total_changes - antes


def _guardar_excluidos(con, df: pd.DataFrame) -> None:
    if df.empty:
        return
    con.executemany(
        """INSERT INTO excluidos (id_ejecucion, id_comercio, sku_comercio, nombre_original,
                                  principio_activo, categoria_comercio, motivo)
           VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING""",
        [tuple(_py(v) for v in fila) for fila in df[
            ["id_ejecucion", "comercio", "sku_comercio", "nombre_original",
             "principio_activo_std", "categoria_comercio", "motivo_exclusion"]
        ].itertuples(index=False)])


def _guardar_rechazos(con, rechazadas: pd.DataFrame) -> None:
    if rechazadas.empty:
        return
    filas = []
    for r in rechazadas.to_dict("records"):
        registro = {k: _py(v) for k, v in r.items() if k not in ("texto_original", "motivo")}
        filas.append((r["id_ejecucion"], _py(r.get("comercio")), _py(r.get("sku_comercio")),
                      _py(r.get("fecha_consulta")), _py(r.get("url_extraccion")),
                      _py(r.get("precio")) if isinstance(_py(r.get("precio")), (int, float)) else None,
                      r["motivo"], json.dumps(registro, ensure_ascii=False, default=str),
                      ahora_iso()))
    con.executemany(
        """INSERT INTO rechazos (id_ejecucion, id_comercio, sku_comercio, fecha_consulta,
                                 url_extraccion, precio, motivo, registro, fecha_registro)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING""", filas)


def _guardar_validaciones(con, id_ejecucion: str, clave: str, reglas: list[dict]) -> None:
    con.executemany(
        """INSERT INTO validaciones (id_ejecucion, id_comercio, regla, n_revisadas, n_fallas,
                                     aprobada, detalle, fecha)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT (id_ejecucion, id_comercio, regla) DO UPDATE SET
               n_revisadas = excluded.n_revisadas, n_fallas = excluded.n_fallas,
               aprobada = excluded.aprobada, detalle = excluded.detalle, fecha = excluded.fecha""",
        [(id_ejecucion, clave, r["regla"], r["n_revisadas"], r["n_fallas"], int(r["aprobada"]),
          r["detalle"], ahora_iso()) for r in reglas])


def _descartar_existentes(con, id_ejecucion: str, clave: str, motivos: dict[str, str]) -> int:
    """
    Observaciones que YA estaban en la base y que ahora no pasan la validación o
    quedaron fuera de la categoría: no se borran, se marcan como descartadas (§3.2)
    y el cambio se anota en correcciones.
    """
    n = 0
    for sku, motivo in motivos.items():
        fila = con.execute("""SELECT id_observacion FROM observaciones
                              WHERE id_ejecucion = ? AND id_comercio = ? AND sku_comercio = ?
                                AND descartada = 0""", (id_ejecucion, clave, sku)).fetchone()
        if fila is None:
            continue
        con.execute("UPDATE observaciones SET descartada = 1, motivo_descarte = ? "
                    "WHERE id_observacion = ?", (motivo, fila[0]))
        registrar_correccion(con, "observaciones", f"id_observacion={fila[0]}", "descartada",
                             0, 1, motivo, "scraper._descartar_existentes")
        n += 1
    return n


def _motivo_falla(fila: dict) -> str | None:
    try:
        detalle = json.loads(fila.get("detalle") or "{}")
    except (TypeError, ValueError):
        return fila.get("detalle")
    if "error" in detalle:
        return detalle["error"]
    if detalle.get("errores"):
        return f"{len(detalle['errores'])} páginas con error (ver detalle de la ejecución)"
    return None


def _resumen_desde_base(con, id_ejecucion: str, clave: str) -> dict:
    fila = con.execute(
        """SELECT estado, recolectados, nuevos, cambios_precio, no_observados
           FROM v_resumen_ejecucion WHERE id_ejecucion = ? AND id_comercio = ?""",
        (id_ejecucion, clave)).fetchone()
    if fila is None:
        return {"recolectados": 0, "nuevos": 0, "cambios_precio": 0, "no_observados": 0}
    return dict(zip(["estado", "recolectados", "nuevos", "cambios_precio", "no_observados"], fila))


def guardar_comercio(con, df: pd.DataFrame, fila: dict,
                     comparables: dict[str, dict[str, str]] | None = None) -> dict:
    """
    Valida las observaciones de un comercio (validacion.py) y las guarda en UNA
    transacción (`with con:`): si algo falla, se deshace todo lo de ese comercio y la
    base queda como estaba (§4.4). Inserta solo las observaciones que no existen.

    Devuelve el resumen del comercio (§4.5): productos recolectados, nuevos, cambios
    de precio y no observados (calculados en la base con la vista v_resumen_ejecucion),
    además de observaciones nuevas, rechazadas, estado y motivo de la falla.
    """
    clave, ejec = fila["id_comercio"], fila["id_ejecucion"]
    sin_conexion = fila["modo"] == "sin_conexion"
    comparables = comparables_por_comercio() if comparables is None else comparables
    resumen = {"id_ejecucion": ejec, "id_comercio": clave,
               "comercio": COMERCIOS[clave]["nombre_corto"], "modo": fila["modo"],
               "estado": fila["estado"], "recolectados": 0, "nuevos": 0, "cambios_precio": 0,
               "no_observados": 0, "observaciones_nuevas": 0, "rechazadas": 0, "motivo": None}

    if fila["estado"] == "fallida":
        if not sin_conexion:            # en línea queda registrada la ejecución fallida
            with con:
                _registrar_ejecucion(con, fila)
        resumen["motivo"] = _motivo_falla(fila)
        return resumen

    incluidos = df[df["incluido"].astype(bool)]
    resultado = validacion.validar_observaciones(incluidos, comparables.get(clave, {}))
    if (not sin_conexion and fila["estado"] == "completa" and comparables.get(clave)
            and resultado.comparables_presentes < validacion.MIN_COMPARABLES):
        fila = {**fila, "estado": "parcial"}
        resumen["motivo"] = (f"solo {resultado.comparables_presentes} productos comparables; "
                             f"se necesitan {validacion.MIN_COMPARABLES}")

    # Observaciones que ya estaban en la base y ahora se rechazan o salen de la categoría.
    # Un SKU que también tiene una fila válida (rechazo por duplicado) no se descarta.
    skus_validos = set(resultado.validas["sku_comercio"])
    por_descartar = {r["sku_comercio"]: f"no pasa la validación: {r['motivo']}"
                     for r in resultado.rechazadas.to_dict("records")
                     if r.get("sku_comercio") and r["sku_comercio"] not in skus_validos}
    for sku, motivo in zip(_excluidos(df)["sku_comercio"], _excluidos(df)["motivo_exclusion"]):
        por_descartar.setdefault(sku, f"fuera de la categoría con las reglas actuales: {motivo}")

    try:
        with con:     # una transacción por comercio: todo o nada
            _registrar_ejecucion(con, fila)
            _guardar_anuncios(con, resultado.validas, clave)
            nuevas = _guardar_observaciones(con, resultado.validas)
            _guardar_excluidos(con, _excluidos(df))
            _guardar_rechazos(con, resultado.rechazadas)
            _guardar_validaciones(con, ejec, clave, resultado.reglas)
            _descartar_existentes(con, ejec, clave, por_descartar)
    except Exception as e:   # se deshizo todo lo de este comercio
        resumen.update(estado="fallida", motivo=f"error al guardar: {e}")
        if not sin_conexion:
            with con:
                _registrar_ejecucion(con, {**fila, "estado": "fallida", "detalle": json.dumps(
                    {"error": f"error al guardar: {e}", "tipo": type(e).__name__},
                    ensure_ascii=False)})
        return resumen

    resumen.update(observaciones_nuevas=nuevas, rechazadas=len(resultado.rechazadas))
    resumen.update(_resumen_desde_base(con, ejec, clave))
    if resumen["motivo"] is None and resumen["estado"] != "completa":
        resumen["motivo"] = _motivo_falla(fila)
    return resumen


def actualizar_comercio(con, clave: str, id_ejecucion: str | None = None,
                        sin_conexion: bool = False, raw_dir: Path | str = RAW_DIR,
                        comparables: dict | None = None) -> dict:
    """PASO 1 + PASO 2 para un comercio. Es lo que llama el botón de la aplicación."""
    df, fila = recolectar_comercio(clave, id_ejecucion, sin_conexion, raw_dir)
    return guardar_comercio(con, df, fila, comparables)


# ---------------------------------------------------------------------------
# Función general (terminal y preparar_base.py)
# ---------------------------------------------------------------------------
def ejecutar_recoleccion(comercios: list[str] | None = None, sin_conexion: bool = False,
                         db_path: Path | str = DB_PATH, raw_dir: Path | str = RAW_DIR,
                         id_ejecucion: str | None = None, verbose: bool = True) -> pd.DataFrame:
    """
    Recolecta los comercios y los guarda en SQLite sin sobrescribir.

    En línea (por defecto): una ejecución nueva, comercio por comercio.
    Sin conexión: reprocesa las copias de raw/ (todas, o solo las de `id_ejecucion`),
        en orden de fecha. Solo se insertan las observaciones que no estén en la base.
    Devuelve un DataFrame con el resumen de cada (ejecución, comercio).
    """
    comercios = comercios or COMERCIOS_POR_DEFECTO
    con = conectar(db_path)
    try:
        with con:
            _registrar_comercios(con, COMERCIOS)
        if sin_conexion:
            copias = copias_en_raw(raw_dir, comercios)
            if id_ejecucion:
                copias = copias[copias["id_ejecucion"] == id_ejecucion]
            if copias.empty:
                raise FileNotFoundError(f"No hay copias crudas en {raw_dir} para {comercios}")
            tareas = list(zip(copias["id_ejecucion"], copias["id_comercio"]))
        else:
            id_ejecucion = id_ejecucion or nuevo_id_ejecucion()
            tareas = [(id_ejecucion, clave) for clave in comercios]
        comparables = comparables_por_comercio()
        resumen = []
        for ejec, clave in tareas:
            if verbose:
                print(f"[{ahora_iso()}] {ejec} {clave}: "
                      f"{'leyendo raw/' if sin_conexion else 'consultando el sitio'}...", flush=True)
            r = actualizar_comercio(con, clave, ejec, sin_conexion, raw_dir, comparables)
            resumen.append(r)
            if verbose:
                print(f"    -> {r['estado']}: {r['recolectados']} recolectados, {r['nuevos']} nuevos, "
                      f"{r['cambios_precio']} cambios de precio, {r['no_observados']} no observados, "
                      f"{r['observaciones_nuevas']} observaciones insertadas, "
                      f"{r['rechazadas']} rechazadas"
                      + (f" | {r['motivo']}" if r["motivo"] else ""), flush=True)
        # Base nueva (p. ej. reconstruida desde raw/): se carga la correspondencia
        if (con.execute("SELECT COUNT(*) FROM productos").fetchone()[0] == 0
                and CORRESPONDENCIA_PATH.exists()):
            limpieza.cargar_correspondencia(con, CORRESPONDENCIA_PATH)
    finally:
        con.close()
    return pd.DataFrame(resumen)


def reprocesar_sin_conexion(**kwargs) -> pd.DataFrame:
    """Atajo: ejecutar_recoleccion(sin_conexion=True, ...)."""
    return ejecutar_recoleccion(sin_conexion=True, **kwargs)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Scraper de antiinfecciosos sistémicos (Talleres 1 y 2)")
    parser.add_argument("--sin-conexion", action="store_true",
                        help="reprocesa las copias de raw/ sin consultar los sitios")
    parser.add_argument("--comercios", nargs="+", default=COMERCIOS_POR_DEFECTO,
                        choices=list(COMERCIOS), help="comercios a recolectar")
    parser.add_argument("--db", default=str(DB_PATH), help="ruta de la base SQLite")
    parser.add_argument("--id-ejecucion", default=None,
                        help="en modo sin conexión, reprocesa solo esta ejecución")
    args = parser.parse_args()
    print(ejecutar_recoleccion(args.comercios, args.sin_conexion, args.db,
                               id_ejecucion=args.id_ejecucion).to_string(index=False))
