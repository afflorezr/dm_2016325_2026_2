import time, gzip, json, re, sqlite3, unicodedata
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import requests
import pandas as pd

import validacion

TZ_CO = ZoneInfo("America/Bogota")
CARPETA = Path(__file__).parent          # las rutas desde la carpeta del proyecto
RAW = CARPETA / "raw"
BASE = CARPETA / "comparador_precios.sqlite"
PAUSA = 1.0
MAX_PETICIONES = 300                     #peticiones por ejecución
HEADERS = {"User-Agent": "ComparadorPreciosTaller2/1.0 (curso Mineria de Datos; uso academico)"}

COLUMNAS = ["comercio", "id_producto", "sku", "ean", "nombre", "marca", "categoria_sitio",
            "precio", "precio_antes", "promocion", "disponibilidad", "vendedor", "url",
            "texto_original", "descripcion", "fecha_consulta", "id_ejecucion"]

peticiones = 0


def ahora_iso():
    return datetime.now(TZ_CO).isoformat(timespec="seconds")


def nuevo_id():
    return datetime.now(TZ_CO).strftime("%Y%m%dT%H%M%S")


def nueva_ejecucion():
    """Identificador de una ejecución nueva; reinicia el contador de peticiones."""
    global peticiones
    peticiones = 0
    return nuevo_id()


def nueva_carpeta(clave, id_ej):
    """Crea raw/<comercio>/<AAAA-MM-DD>/<id_ejecucion>/ con la fecha del identificador."""
    carpeta = RAW / clave / f"{id_ej[:4]}-{id_ej[4:6]}-{id_ej[6:8]}" / id_ej
    carpeta.mkdir(parents=True, exist_ok=True)
    return carpeta


def pedir(url, params=None, cuerpo=None, intentos=4):
    """GET (o POST si se pasa cuerpo) que reintenta los errores temporales del servidor."""
    global peticiones
    for i in range(intentos):
        if peticiones >= MAX_PETICIONES:
            raise RuntimeError(f"se alcanzó el tope de {MAX_PETICIONES} peticiones")
        peticiones += 1
        try:
            if cuerpo is None:
                r = requests.get(url, params=params, headers=HEADERS, timeout=30)
            else:
                r = requests.post(url, json=cuerpo, headers=HEADERS, timeout=30)
            if r.status_code in (401, 403):   # bloqueo: no se reintenta
                raise PermissionError(f"el sitio rechazó la consulta (HTTP {r.status_code})")
            if r.status_code in (429, 500, 502, 503, 504):
                raise requests.HTTPError(f"Error temporal {r.status_code}")
            r.raise_for_status()
            return r
        except (requests.HTTPError, requests.ConnectionError, requests.Timeout) as e:
            if i == intentos - 1:
                raise
            print(f"  {e}. Reintento en {2 * 2 ** i} s")
            time.sleep(2 * 2 ** i)


def limpiar_precio(valor):
    """Precio en número o en texto ("$ 12.900", "12.900,50") a float; None si no hay precio."""
    if valor is None or (isinstance(valor, float) and pd.isna(valor)):
        return None
    if isinstance(valor, (int, float)):
        return float(valor)
    texto = re.sub(r"[^\d,.]", "", str(valor))
    if not texto:
        return None
    if re.fullmatch(r"\d+\.\d{1,2}", texto):   
        return float(texto)
    return float(texto.replace(".", "").replace(",", "."))


def guardar_gz(ruta, datos):
    with gzip.open(ruta, "wt", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False)


def leer_gz(ruta):
    with gzip.open(ruta, "rt", encoding="utf-8") as f:
        return json.load(f)


def escribir_manifiesto(carpeta, m):
    (carpeta / "manifiesto.json").write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")


def leer_manifiesto(carpeta):
    return json.loads((Path(carpeta) / "manifiesto.json").read_text(encoding="utf-8"))


#  Éxito y Locatel con VTEX

URL_EXITO = "https://www.exito.com/api/catalog_system/pub/products/search"
FQ_EXITO = "C:/34185083/34185118/34185412/"   # Vitaminas, proteínas y suplementos
CON_PRECIO = "P:[1 TO 99999999]"               # solo productos con precio

URL_LOC = "https://www.locatelcolombia.com/api/catalog_system/pub/products/search"
URL_REGION_LOC = "https://www.locatelcolombia.com/api/checkout/pub/regions"
CODIGO_BOGOTA = "11001"   # código DANE de Bogotá; el sitio lo acepta como código postal
FQ_LOC = {   # Locatel no tiene una categoría deportiva: los productos están repartidos en estas tres
    "C:/6/41/": "Alimentos nutricionales > Suplementos",
    "C:/6/39/245/": "Alimentos nutricionales > Bebidas > Rehidratantes",
    "C:/6/39/241/": "Alimentos nutricionales > Bebidas > Energizantes",
}


def descargar_vtex(url, fqs, carpeta, prefijo, extra=None):
    """Recorre las páginas de 50 productos y guarda cada una; devuelve (total del sitio, descargados)."""
    desde = descargados = 0
    while True:
        r = pedir(url, {"fq": fqs, "_from": desde, "_to": desde + 49, **(extra or {})})
        pagina = r.json()
        guardar_gz(carpeta / f"pagina_{prefijo}_{desde:05d}.json.gz",
                   {"url": r.url, "consultado": ahora_iso(), "cuerpo": pagina})
        total = int(r.headers["resources"].split("/")[1])
        descargados += len(pagina)
        desde += 50
        if not pagina or desde >= total:
            return total, descargados
        time.sleep(PAUSA)


def aplanar_vtex(productos, comercio, fecha, id_ej):
    filas = []
    for p in productos:
        for item in p.get("items", []):
            vendedores = item.get("sellers") or [{}]
            vendedor = next((v for v in vendedores if v.get("sellerDefault")), vendedores[0])
            oferta = vendedor.get("commertialOffer", {})
            precio = limpiar_precio(oferta.get("Price"))
            antes = limpiar_precio(oferta.get("ListPrice"))
            if antes == precio:
                antes = None
            filas.append({
                "comercio": comercio,
                "id_producto": p.get("productId"),
                "sku": item.get("itemId"),
                "ean": item.get("ean") or None,
                "nombre": p.get("productName"),
                "marca": p.get("brand"),
                "categoria_sitio": (p.get("categories") or [None])[0],
                "precio": precio,
                "precio_antes": antes,
                "promocion": int(bool(precio and antes and precio < antes)),
                "disponibilidad": "disponible" if (oferta.get("AvailableQuantity") or 0) > 0 else "agotado",
                "vendedor": vendedor.get("sellerName"),
                "url": p.get("link"),
                "texto_original": " | ".join(filter(None, [
                    p.get("productName"), item.get("name"), p.get("description")])),
                "descripcion": p.get("description") or None,
                "fecha_consulta": fecha,
                "id_ejecucion": id_ej,
            })
    return pd.DataFrame(filas, columns=COLUMNAS)


def procesar_vtex(carpeta, comercio, fecha, id_ej):
    productos = {}
    for archivo in sorted(Path(carpeta).glob("pagina_*.json.gz")):
        for p in leer_gz(archivo)["cuerpo"]:
            productos[p["productId"]] = p
    return aplanar_vtex(productos.values(), comercio, fecha, id_ej)


def recolectar_exito(online=True, carpeta=None, id_ej=None):
    if not online:
        m = leer_manifiesto(carpeta)
        return procesar_vtex(carpeta, "Exito", m["fecha_consulta"], m["id_ejecucion"]), m

    id_ej = id_ej or nuevo_id()
    fecha = ahora_iso()
    carpeta = nueva_carpeta("exito", id_ej)
    total, bajados = descargar_vtex(URL_EXITO, [FQ_EXITO, CON_PRECIO], carpeta, "cat")
    print(f"Vitaminas, proteínas y suplementos: {bajados} de {total} productos con precio")

    df = procesar_vtex(carpeta, "Exito", fecha, id_ej)
    unicos = int(df["id_producto"].nunique())
    m = {"comercio": "Exito", "id_ejecucion": id_ej, "carpeta": carpeta.relative_to(CARPETA).as_posix(),
         "fecha_consulta": fecha, "fecha_fin": ahora_iso(), "fuente": URL_EXITO,
         "filtros": [FQ_EXITO, CON_PRECIO], "total_sitio": total, "productos_unicos": unicos,
         "filas": len(df), "estado": "completa" if unicos >= total else "parcial"}
    escribir_manifiesto(carpeta, m)
    return df, m


def recolectar_locatel(online=True, carpeta=None, id_ej=None):
    if not online:
        m = leer_manifiesto(carpeta)
        return procesar_vtex(carpeta, "Locatel", m["fecha_consulta"], m["id_ejecucion"]), m

    id_ej = id_ej or nuevo_id()
    fecha = ahora_iso()
    carpeta = nueva_carpeta("locatel", id_ej)
    # Región de Bogotá: el sitio la usa para mostrar la disponibilidad según la dirección
    region = pedir(URL_REGION_LOC, {"country": "COL", "postalCode": CODIGO_BOGOTA}).json()[0]["id"]
    total_sitio, completa = 0, True
    for i, (fq, nombre) in enumerate(FQ_LOC.items()):
        total, bajados = descargar_vtex(URL_LOC, [fq], carpeta, f"c{i}", {"regionId": region})
        total_sitio += total
        completa = completa and bajados >= total
        print(f"{nombre}: {bajados} de {total} productos")
        time.sleep(PAUSA)

    df = procesar_vtex(carpeta, "Locatel", fecha, id_ej)
    unicos = int(df["id_producto"].nunique())
    m = {"comercio": "Locatel", "id_ejecucion": id_ej, "carpeta": carpeta.relative_to(CARPETA).as_posix(),
         "fecha_consulta": fecha, "fecha_fin": ahora_iso(), "fuente": URL_LOC, "region_bogota": region,
         "filtros": list(FQ_LOC), "total_sitio": total_sitio, "productos_unicos": unicos,
         "filas": len(df), "estado": "completa" if completa else "parcial"}   # un producto puede estar en dos secciones
    escribir_manifiesto(carpeta, m)
    return df, m


# ---------------- Farmatodo (Algolia) ----------------
URL_FT = "https://api-search.farmatodo.com/1/indexes/*/queries"
INDICE_FT = "products-colombia"
CATEGORIA_FT = "Suplementos deportivos"
TOPE_FT = 80   # lo que muestra la página de la categoría
# El servicio no deja pedir la categoría, así que se busca por tipo de producto, por marca y por las
# líneas más vendidas. Cada búsqueda se recorre página por página (24 productos por página).
TERMINOS_FT = [
    "proteina", "whey", "isolate", "creatina", "aminoacidos", "bcaa", "glutamina", "preentreno",
    "pre workout", "ganador de peso", "hipercalorica", "gel energetico", "barra proteina",
    "bebida hidratante", "isotonica", "electrolitos", "suplementos deportivos", "proteinas deportivas",
    "snacks de proteina", "energizantes deportivos", "hidratantes deportivos", "creatinas",
    "nutramerican", "megaplex", "bipro", "crea stack", "mega soy", "creatine power", "radical power",
    "100% whey protein", "gainz", "mega carbs", "nitro shock", "smart muscle", "muscletech",
    "optimum nutrition", "dymatize", "healthy sports", "vitanas", "sascha fitness", "going", "benet",
    "benet whey", "gu", "fitbar", "quest", "gatorade", "powerade", "elemental",
]


def aplanar_farmatodo(productos, fecha, id_ej):
    filas = []
    for h in productos:
        lleno = limpiar_precio(h.get("fullPrice")) or None
        oferta = limpiar_precio(h.get("offerPrice")) or None
        en_oferta = bool(lleno and oferta and oferta < lleno)
        # hasStock siempre llega en False; el sitio marca los agotados con outofstore o sin tiendas con stock
        agotado = bool(h.get("outofstore")) or not h.get("stores_with_stock")
        enlace = h.get("url") or h.get("urlCanonical")   # algunos productos solo traen urlCanonical
        filas.append({
            "comercio": "Farmatodo",
            "id_producto": h.get("objectID"),
            "sku": str(h.get("item") or h.get("objectID")),
            "ean": h.get("barcode") or None,
            "nombre": h.get("mediaDescription"),
            "marca": h.get("marca") or None,
            "categoria_sitio": " > ".join(filter(None, [h.get("categorie"), h.get("subCategory")])) or None,
            "precio": oferta if en_oferta else lleno,
            "precio_antes": lleno if en_oferta else None,
            "promocion": int(en_oferta),
            "disponibilidad": "agotado" if agotado else "disponible",
            "vendedor": "Farmatodo",
            "url": f"https://www.farmatodo.com.co/producto/{enlace}" if enlace else None,
            "texto_original": " | ".join(filter(None, [
                h.get("mediaDescription"), h.get("grayDescription"), h.get("largeDescription")])),
            "descripcion": h.get("largeDescription") or None,
            "fecha_consulta": fecha,
            "id_ejecucion": id_ej,
        })
    return pd.DataFrame(filas, columns=COLUMNAS)


def procesar_farmatodo(carpeta, fecha, id_ej):
    productos = {}
    for archivo in sorted(Path(carpeta).glob("pagina_*.json.gz")):
        for h in leer_gz(archivo)["cuerpo"]["hits"]:
            productos[h["objectID"]] = h
    return aplanar_farmatodo(productos.values(), fecha, id_ej)


def recolectar_farmatodo(online=True, carpeta=None, id_ej=None):
    if not online:
        m = leer_manifiesto(carpeta)
        return procesar_farmatodo(carpeta, m["fecha_consulta"], m["id_ejecucion"]), m

    id_ej = id_ej or nuevo_id()
    fecha = ahora_iso()
    carpeta = nueva_carpeta("farmatodo", id_ej)
    for i, termino in enumerate(TERMINOS_FT):
        pagina = paginas = 0
        while pagina == 0 or pagina < paginas:
            # el término va suelto y la página dentro de params; si no, el servicio repite la página 0
            cuerpo = {"requests": [{"indexName": INDICE_FT, "query": termino,
                                    "params": f"hitsPerPage=24&page={pagina}"}]}
            res = pedir(URL_FT, cuerpo=cuerpo).json()["results"][0]
            guardar_gz(carpeta / f"pagina_t{i:03d}_p{pagina:02d}.json.gz",
                       {"url": URL_FT, "termino": termino, "pagina": pagina, "consultado": ahora_iso(),
                        "cuerpo": res})
            paginas = res["nbPages"]
            pagina += 1
            time.sleep(PAUSA)
        print(f"{termino:24} {res['nbHits']:3} productos en {paginas} páginas")

    df = procesar_farmatodo(carpeta, fecha, id_ej)
    en_cat = int(df["categoria_sitio"].str.startswith(CATEGORIA_FT, na=False).sum())
    m = {"comercio": "Farmatodo", "id_ejecucion": id_ej, "carpeta": carpeta.relative_to(CARPETA).as_posix(),
         "fecha_consulta": fecha, "fecha_fin": ahora_iso(), "fuente": URL_FT, "indice": INDICE_FT,
         "terminos": TERMINOS_FT, "productos_unicos": int(df["id_producto"].nunique()),
         "filas": len(df), "en_suplementos_deportivos": en_cat, "total_sitio": TOPE_FT,
         "estado": "completa"}   # todas las búsquedas se recorrieron hasta su última página
    escribir_manifiesto(carpeta, m)
    return df, m


# ---------------- Limpieza ----------------
def normalizar(texto):
    """Minúsculas, sin tildes y con espacios simples."""
    if pd.isna(texto):
        return ""
    texto = unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", texto.lower()).strip()


# Contenido: unidad del texto -> (unidad estándar, factor)
UNIDADES = {"kg": ("g", 1000), "kilo": ("g", 1000), "kilos": ("g", 1000),
            "g": ("g", 1), "gr": ("g", 1), "grs": ("g", 1), "gramo": ("g", 1), "gramos": ("g", 1),
            "lb": ("g", 453.6), "lbs": ("g", 453.6), "libra": ("g", 453.6), "libras": ("g", 453.6),
            "ml": ("ml", 1), "cc": ("ml", 1), "l": ("ml", 1000), "lt": ("ml", 1000),
            "lts": ("ml", 1000), "litro": ("ml", 1000), "litros": ("ml", 1000)}
NUM = r"(\d+(?:[.,]\d+)?)"
MEDIDA = r"(" + "|".join(sorted(UNIDADES, key=len, reverse=True)) + r")\b"
CONTEO = (r"(?:unidades|unidad|unds|und|unid|uds|ud|u|capsulas|capsula|caps|tabletas|tableta|tabs|"
          r"softgels|softgel|tab|sobres|sobre|sticks|stick|sachets|sachet|barras|barra|geles|gel|"
          r"tarros|tarro|latas|lata|botellas|botella|frascos|frasco|paquetes|paquete)")
SUELTO = r"(?<![a-wyz0-9.,])(\d+)"   # número entero no pegado a una letra (salvo x12): evita leer C4 o B12
PACK_1 = re.compile(rf"{SUELTO}\s*({CONTEO})?\s*(?:x|de|por)\s*{NUM}\s*{MEDIDA}")    # 30 sticks x 6 g
PACK_2 = re.compile(rf"{NUM}\s*{MEDIDA}\s*(?:x|por)\s*(\d+)\s*{CONTEO}\b")           # 500 ml x 6 und
SIMPLE = re.compile(rf"{NUM}\s*{MEDIDA}")                                            # 910 gr, 2 lb
CUENTA = re.compile(rf"{SUELTO}\s*{CONTEO}\b")                                       # x 1 und
CAJA = re.compile(r"\b(?:caja|tubo)\s*(?:x|por)\s*(\d+)\b")                                  # Caja x 12


def a_numero(texto, factor):
    if factor == 1 and re.fullmatch(r"\d{1,3}[.,]\d{3}", texto):   # 1.000 g son mil gramos
        return float(texto[:-4] + texto[-3:])
    return float(texto.replace(",", "."))


def extraer_contenido(nombre, total_al_final=False):
    """(contenido total, unidad, unidades del empaque) en g, ml o und; None si no aparece.

    total_al_final: el comercio escribe "x 25 unidades x 500 g" con el total del empaque (Locatel)."""
    m = PACK_1.search(nombre)
    if m and m[2] and total_al_final:
        unidad, factor = UNIDADES[m[4]]
        return round(a_numero(m[3], factor) * factor, 1), unidad, int(m[1])
    if m and (m[2] or int(m[1]) <= 60):   # sin palabra de conteo, un número alto es del nombre (ISO 100)
        n, cantidad, medida = int(m[1]), m[3], m[4]
    elif m := PACK_2.search(nombre):
        n, cantidad, medida = int(m[3]), m[1], m[2]
    elif m := SIMPLE.findall(nombre):   # la última medida: "0.7 Lb 360 G" o "2.2 lb (1.000g)"
        n, (cantidad, medida) = 1, m[-1]
    elif m := CUENTA.search(nombre) or CAJA.search(nombre):
        return float(m[1]), "und", int(m[1])
    else:
        return None, None, None
    unidad, factor = UNIDADES[medida]
    return round(n * a_numero(cantidad, factor) * factor, 1), unidad, n


SABORES = {   # texto en el nombre -> sabor estándar
    "cookies and cream": "cookies and cream", "cookies & cream": "cookies and cream",
    "cookies n cream": "cookies and cream", "chocolate": "chocolate", "vainilla": "vainilla",
    "vanilla": "vainilla", "fresa": "fresa", "frutos rojos": "frutos rojos", "banano": "banano",
    "mango": "mango", "maracuya": "maracuyá", "limon": "limón", "naranja": "naranja",
    "mandarina": "mandarina", "mora": "mora", "uva": "uva", "cereza": "cereza", "sandia": "sandía",
    "pina": "piña", "coco": "coco", "manzana": "manzana", "green apple": "manzana", "kiwi": "kiwi",
    "guayaba": "guayaba", "granada": "granada", "tropical": "tropical", "fruit punch": "ponche de frutas",
    "cafe": "café", "capuchino": "capuchino", "cappuccino": "capuchino", "arequipe": "arequipe",
    "caramelo": "caramelo", "mani": "maní", "sin sabor": "sin sabor", "natural": "sin sabor",
}
ALT_SABORES = "|".join(sorted(map(re.escape, SABORES), key=len, reverse=True))
PATRON_SABOR = re.compile(rf"\b({ALT_SABORES})\b")


def extraer_sabor(nombre):
    return " y ".join(sorted({SABORES[s] for s in PATRON_SABOR.findall(nombre)})) or None


def sin_sabores(nombre):
    """Quita 'sabor X' y cookies and cream para que un sabor no se confunda con un alimento."""
    texto = re.sub(r"cookies ?(?:and|&|n'?|y) ?(?:cream|crema)", " ", nombre)
    return re.sub(rf"\bsabor(?:es)? (?:a )?(?:{ALT_SABORES}|\w+)", " ", texto)


MARCAS = [   # patrón en la marca o el nombre normalizados -> marca estándar
    (r"nutramerican|bipro|mega soy|crea ?stack|radical (?:power|nutrition)", "Nutramerican"),
    (r"megaplex", "Megaplex"),
    (r"smart ?muscle", "Smart Muscle"),
    (r"muscle ?tech", "MuscleTech"),
    (r"optimum|gold standard", "Optimum Nutrition"),
    (r"benet|nutresa", "Benet"),
    (r"\bquest\b", "Quest"),
    (r"sascha", "Sascha Fitness"),
    (r"dymatize", "Dymatize"),
    (r"healthy sports", "Healthy Sports"),
    (r"\bgoing\b", "Going"),
    (r"\bgu\b", "GU"),
]
GENERICAS = {"", "generico", "generica", "sin marca", "otros", "otras", "varios", "na", "n/a"}


def estandarizar_marca(marca, nombre):
    """Marca del diccionario si coincide con la marca del sitio o con el nombre; si no, la del sitio."""
    marca = normalizar(marca)
    textos = [nombre] if marca in GENERICAS else [marca, nombre]
    for texto in textos:
        for patron, estandar in MARCAS:
            if re.search(patron, texto):
                return estandar
    return None if marca in GENERICAS else marca.title()


# Delimitación de la planilla: proteínas, creatina, aminoácidos, preentrenos, geles, barras y bebidas.
# Incluye líneas de producto cuyo nombre no trae el tipo ("Bipro Classic", "Crea Stack", "Radical Nutramerican").
SUBCATEGORIAS = {
    "barra": r"\bbarra|\bbars?\b|barrita|fit ?bar",
    "gel": r"\bgu\b|\bgel(?:es)?\b.*(?:energ|deportiv|isotonic|carbohidrat|cafeina)|energy gel|gel (?:benet|going)",
    "ganador de peso": r"ganador|gainer|\bmass\b|hipercalori|creatine power",
    "preentreno": r"pre ?entreno|pre-?workout|pre ?work|\bc4\b|oxido nitrico|radical (?:power|nutramerican)",
    "bebida deportiva": (r"gatorade|powerade|sporade|isotonic|hidratante|electrolito|bebida deportiv|"
                         r"recuperador|recovery"),
    "creatina": r"creatin|crea ?stack",
    "aminoácidos": (r"bcaa|glutamin|gluta ?stack|aminoacid|\bamino\b|aminomix|\beaas?\b|leucin|arginin|citrulin|"
                    r"beta[ -]?alanin|\bhmb\b|\bbccas?\b"),
    "proteína": r"prote[ií]n|whey|isolat|\biso ?100\b|caseina|casein|suero de leche|bipro",
}
FUERTES = (r"creatin|crea ?stack|whey|isolat|caseina|casein|suero de leche|bipro|bcaa|glutamin|gluta ?stack|"
           r"barra de prote|barra proteic|protein bar|quest bar|fit ?bar|\bgu\b|"
           r"aminoacid|\bamino\b|aminomix|\beaas?\b|pre ?entreno|pre-?workout|ganador|gainer|gatorade|powerade|sporade|isotonic|"
           r"\bgel(?:es)?\b.*energ|energy gel|gel (?:benet|going)")
EXCLUSIONES_PREVIAS = [
    ("cuidado personal", r"shampoo|champu|acondicionador|capilar|cabello|keratina|peinar|locion|mascarilla|"
                         r"jabon|desodorante|bloqueador|protector solar|maquillaje|facial|corporal|\bpiel\b|"
                         r"(?<!y )(?<!&)(?<!con )\bcrema\b(?! de mani| agria)|intim|unas|esmalte|manicura|lampara|compresa|gafas|gorro"),
    ("suero de rehidratación de uso médico", r"\bsuero\b(?! de leche)|\belectrolit\b|hidraplus|pedialyte|"
                                             r"rehidratacion oral|sales de rehidratacion"),
    ("colágeno", r"colageno|collagen"),
    ("nutrición general o médica", r"ensure|pediasure|glucerna|nutren|enterex|\bboost\b|formula infantil|"
                                   r"prowhey|fresubin|frebini|diben|supportan|fortisip|fortini|nepro|pulmocare|"
                                   r"prosure|proklein|nutrione|ascenda|gerifood|espesante|similac"),
    ("quemador o termogénico", r"quemador|termogenic|burner|carnitina|\bcla\b|thermo|lipo ?6|movilizador de grasa"),
]
ACCESORIOS = r"shaker|mezclador|\btermo\b|tomatodo|botilito|cinturon|guante|toalla|bascula|pastillero"
EXCLUSIONES = [
    ("alimento general", r"brownie|galleta|cookie|cereal|ponque|pancake|waffle|wafer|granola|avena|"
                         r"mantequilla de mani|crema de mani|\bchips?\b|pudin|helado|\bleche\b|lacte|yogur|"
                         r"kumis|chocolatina|\btorta\b|muffin|\bpan\b|\bpasta\b|\bcafe\b|infusion|\bte\b|"
                         r"panela|\bmiel\b|arequipe"),
    ("vitaminas y minerales", r"vitamin|multivit|mineral|omega|calcio|magnesio|zinc|hierro|biotina|"
                              r"acido folico|complejo b|\bb12\b"),
    ("otro suplemento", r"aloe|ginseng|espirulina|spirulina|moringa|\bmaca\b|curcuma|ashwagandha|levadura|"
                        r"lecitina|aceite|propoleo|valeriana|melatonina|probiotic|fibra|glucosamina|"
                        r"condroitina|cartilago|resveratrol|coenzima|q10"),
]


def subcategoria(nombre):
    """Primero las formas (barra, gel...); entre creatina, aminoácidos y proteína, la que aparece primero."""
    for sub in ("barra", "gel", "ganador de peso", "preentreno", "bebida deportiva"):
        if re.search(SUBCATEGORIAS[sub], nombre):
            return sub
    posiciones = [(m.start(), sub) for sub in ("creatina", "aminoácidos", "proteína")
                  if (m := re.search(SUBCATEGORIAS[sub], nombre))]
    return min(posiciones)[1] if posiciones else None


def clasificar(nombre, comercio, categoria_sitio):
    """(en_categoria, subcategoria, motivo_exclusion) según la delimitación de la planilla."""
    if comercio == "Farmatodo" and not normalizar(categoria_sitio).startswith(normalizar(CATEGORIA_FT)):
        return 0, None, "fuera de Suplementos deportivos en Farmatodo"
    for motivo, patron in EXCLUSIONES_PREVIAS:
        if re.search(patron, nombre):
            return 0, None, motivo
    if re.search(FUERTES, nombre):
        return 1, subcategoria(nombre), None
    if re.search(ACCESORIOS, nombre):   # después de las palabras fuertes: un combo con termo sigue siendo suplemento
        return 0, None, "accesorio"
    texto = sin_sabores(nombre)
    for motivo, patron in EXCLUSIONES:
        if re.search(patron, texto):
            return 0, None, motivo
    sub = subcategoria(nombre)
    return (1, sub, None) if sub else (0, None, "sin palabra clave de nutrición deportiva")


VACIAS = set("""x por de del la las el los en con y para a al sabor sabores sin tarro frasco bolsa doypack
doy pack caja sobre sobres pote paquete botella lata envase und unds unid unidad unidades ud uds polvo
suplemento suplementos dietario dietetico deportivo deportiva nutricional alimento bebida proteina
proteinas protein proteico proteica hidratante isotonica isotonico energetico energetica nuevo nueva
new formula presentacion nutramericanpharma pharma c u g""".split())
SINONIMOS = {"creatine": "creatina", "glutamine": "glutamina", "monohydrate": "monohidratada",
             "monohidrato": "monohidratada", "aislada": "isolate", "aislado": "isolate",
             "isolated": "isolate", "bar": "barra", "bars": "barra", "barras": "barra", "geles": "gel"}


def nombre_estandar(nombre, marca_sitio, marca_std):
    """Nombre sin marca, sabor, contenido ni palabras de relleno, para comparar entre comercios."""
    texto = PATRON_SABOR.sub(" ", sin_sabores(nombre))
    for patron in (PACK_1, PACK_2, SIMPLE, CUENTA):
        texto = patron.sub(" ", texto)
    texto = re.sub(r"(\d+)\s*mg\b", r"\1mg", texto)   # la concentración queda como una palabra
    texto = re.sub(r"suero de leche", "whey", texto)
    texto = re.sub(r"pre ?-?(?:entreno|workout)", "preentreno", texto)
    marca = set((normalizar(marca_sitio) + " " + normalizar(marca_std)).split())
    palabras = [SINONIMOS.get(p, p) for p in re.findall(r"[a-z0-9]+", texto)]
    palabras = [p for p in palabras if p not in VACIAS and p not in marca and not p.isdigit()]
    return " ".join(dict.fromkeys(palabras)) or None


def limpiar(df):
    """Agrega las columnas estandarizadas sin tocar el texto original."""
    nombres = df["nombre"].map(normalizar)
    contenido = pd.DataFrame([extraer_contenido(n, c == "Locatel") for n, c in zip(nombres, df["comercio"])],
                             index=df.index,
                             columns=["contenido", "unidad", "unidades_empaque"])
    clases = pd.DataFrame([clasificar(n, c, s) for n, c, s in
                           zip(nombres, df["comercio"], df["categoria_sitio"])], index=df.index,
                          columns=["en_categoria", "subcategoria_std", "motivo_exclusion"])
    df = pd.concat([df, contenido, clases], axis=1)
    df["marca_std"] = [estandarizar_marca(m, n) for m, n in zip(df["marca"], nombres)]
    df["nombre_std"] = [nombre_estandar(n, m, s) for n, m, s in zip(nombres, df["marca"], df["marca_std"])]
    df["variante"] = [extraer_sabor(n) for n in nombres]
    df["con_descripcion"] = [int(normalizar(d) != "") for d in df["descripcion"]]
    return df


# ---------------- Base SQLite ----------------
ESQUEMA = """
CREATE TABLE IF NOT EXISTS comercios (
    id_comercio   INTEGER PRIMARY KEY,
    nombre        TEXT NOT NULL UNIQUE,
    url_categoria TEXT
);
INSERT OR IGNORE INTO comercios VALUES
    (1, 'Exito', 'https://tienda.exito.com/cuidado-personal/salud-y-medicamentos/vitaminas-proteinas-y-suplementos'),
    (2, 'Farmatodo', 'https://www.farmatodo.com.co/categorias/bienestar-y-nutricion-deportiva/suplementos-deportivos'),
    (3, 'Locatel', 'https://www.locatelcolombia.com/alimentos-nutricionales/suplementos');
CREATE TABLE IF NOT EXISTS ejecuciones (
    id_ejecucion  TEXT NOT NULL,
    comercio      TEXT NOT NULL REFERENCES comercios (nombre),
    inicio        TEXT NOT NULL,
    fin           TEXT,
    registros     INTEGER NOT NULL,
    en_categoria  INTEGER NOT NULL,
    total_sitio   INTEGER,
    estado        TEXT NOT NULL CHECK (estado IN ('completa', 'parcial', 'fallida')),
    carpeta_raw   TEXT,
    insertadas    INTEGER,
    rechazadas    INTEGER,
    comparables   INTEGER,
    motivo        TEXT,
    PRIMARY KEY (id_ejecucion, comercio)
);
CREATE TABLE IF NOT EXISTS productos (
    id_producto_comun TEXT PRIMARY KEY,
    nombre_comun      TEXT NOT NULL,
    marca_std         TEXT,
    subcategoria_std  TEXT,
    nombre_std        TEXT,
    variante          TEXT,
    contenido         REAL,
    unidad            TEXT,
    unidades_empaque  INTEGER,
    regla             TEXT
);
CREATE TABLE IF NOT EXISTS anuncios (
    id_anuncio           INTEGER PRIMARY KEY,
    comercio             TEXT NOT NULL REFERENCES comercios (nombre),
    id_producto_comercio TEXT NOT NULL,
    sku                  TEXT NOT NULL,
    ean                  TEXT,
    nombre               TEXT,
    texto_original       TEXT,
    categoria_sitio      TEXT,
    marca_sitio          TEXT,
    marca_std            TEXT,
    subcategoria_std     TEXT,
    nombre_std           TEXT,
    variante             TEXT,
    contenido            REAL,
    unidad               TEXT CHECK (unidad IN ('g', 'ml', 'und')),
    unidades_empaque     INTEGER,
    con_descripcion      INTEGER,
    en_categoria         INTEGER NOT NULL,
    motivo_exclusion     TEXT,
    url                  TEXT,
    id_producto_comun    TEXT REFERENCES productos (id_producto_comun),
    comparable           INTEGER NOT NULL DEFAULT 0,
    UNIQUE (comercio, id_producto_comercio, sku)
);
CREATE TABLE IF NOT EXISTS observaciones (
    id_observacion  INTEGER PRIMARY KEY,
    id_anuncio      INTEGER NOT NULL REFERENCES anuncios (id_anuncio),
    id_ejecucion    TEXT NOT NULL,
    precio          REAL CHECK (precio > 0),
    precio_antes    REAL,
    promocion       INTEGER NOT NULL,
    disponibilidad  TEXT NOT NULL CHECK (disponibilidad IN ('disponible', 'agotado')),
    vendedor        TEXT,
    fecha_consulta  TEXT NOT NULL,
    descartada      INTEGER NOT NULL DEFAULT 0,
    motivo_descarte TEXT,
    UNIQUE (id_anuncio, id_ejecucion)
);
CREATE TABLE IF NOT EXISTS rechazos (
    id_rechazo           INTEGER PRIMARY KEY,
    id_ejecucion         TEXT NOT NULL,
    comercio             TEXT NOT NULL,
    id_producto_comercio TEXT,
    sku                  TEXT,
    nombre               TEXT,
    precio               REAL,
    url                  TEXT,
    fecha_consulta       TEXT,
    motivo               TEXT NOT NULL,
    UNIQUE (id_ejecucion, comercio, id_producto_comercio, sku, motivo)
);
CREATE TABLE IF NOT EXISTS correcciones (
    id_correccion  INTEGER PRIMARY KEY,
    fecha          TEXT NOT NULL,
    tabla          TEXT NOT NULL,
    id_registro    INTEGER NOT NULL,
    campo          TEXT NOT NULL,
    valor_anterior TEXT,
    valor_nuevo    TEXT,
    motivo         TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_observaciones_ejecucion ON observaciones (id_ejecucion);
CREATE INDEX IF NOT EXISTS idx_observaciones_anuncio ON observaciones (id_anuncio);
CREATE INDEX IF NOT EXISTS idx_observaciones_precio ON observaciones (precio);
CREATE INDEX IF NOT EXISTS idx_anuncios_filtros ON anuncios (comercio, en_categoria, subcategoria_std, marca_std);
CREATE INDEX IF NOT EXISTS idx_anuncios_comun ON anuncios (comparable, id_producto_comun);

-- Observaciones válidas con los datos del anuncio y el precio por unidad de contenido
CREATE VIEW IF NOT EXISTS v_observaciones AS
SELECT o.id_observacion, o.id_ejecucion, o.fecha_consulta, a.id_anuncio, a.comercio, a.nombre,
       a.texto_original, a.marca_std AS marca, a.subcategoria_std AS subcategoria, a.contenido, a.unidad,
       a.en_categoria, a.comparable, a.id_producto_comun, a.url, o.precio, o.precio_antes, o.promocion,
       o.disponibilidad, o.vendedor,
       ROUND(o.precio / a.contenido, 2) AS precio_unidad
FROM observaciones o
JOIN anuncios a ON a.id_anuncio = o.id_anuncio
WHERE o.descartada = 0;

-- Último precio observado de cada anuncio
CREATE VIEW IF NOT EXISTS v_ultimo_precio AS
SELECT * FROM (
    SELECT v.*, ROW_NUMBER() OVER (PARTITION BY v.id_anuncio ORDER BY v.fecha_consulta DESC) AS orden
    FROM v_observaciones v
) WHERE orden = 1;

-- Cambio de precio de cada anuncio frente a su observación anterior
CREATE VIEW IF NOT EXISTS v_cambios_precio AS
SELECT * FROM (
    SELECT v.id_anuncio, v.comercio, v.nombre, v.en_categoria, v.comparable, v.id_ejecucion, v.precio,
           LAG(v.id_ejecucion) OVER w AS id_ejecucion_anterior,
           LAG(v.precio) OVER w AS precio_anterior
    FROM v_observaciones v
    WINDOW w AS (PARTITION BY v.id_anuncio ORDER BY v.fecha_consulta)
)
WHERE precio_anterior IS NOT NULL AND precio != precio_anterior;

-- Precios de las presentaciones que están en los tres comercios
CREATE VIEW IF NOT EXISTS v_comparables AS
SELECT v.id_ejecucion, v.fecha_consulta, p.id_producto_comun,
       p.marca_std || ' ' || p.nombre_comun AS producto, p.subcategoria_std AS subcategoria,
       p.contenido, p.unidad, v.comercio, v.nombre, v.precio, v.precio_unidad, v.promocion,
       v.disponibilidad, v.url
FROM v_observaciones v
JOIN productos p ON p.id_producto_comun = v.id_producto_comun
WHERE v.comparable = 1;

-- Estado de cada comparable en cada ejecución de su comercio: disponible, agotado o no observado
CREATE VIEW IF NOT EXISTS v_disponibilidad AS
SELECT e.id_ejecucion, e.comercio, e.estado AS estado_ejecucion, a.id_producto_comun, a.nombre,
       COALESCE(o.disponibilidad, 'no observado') AS disponibilidad
FROM ejecuciones e
JOIN anuncios a ON a.comercio = e.comercio AND a.comparable = 1
LEFT JOIN observaciones o ON o.id_anuncio = a.id_anuncio AND o.id_ejecucion = e.id_ejecucion
                          AND o.descartada = 0;

-- Resumen de cada ejecución
CREATE VIEW IF NOT EXISTS v_ejecuciones AS
SELECT id_ejecucion, MIN(inicio) AS inicio,
       SUM(estado = 'completa') AS completas, SUM(estado = 'parcial') AS parciales,
       SUM(estado = 'fallida') AS fallidas, SUM(insertadas) AS insertadas, SUM(rechazadas) AS rechazadas
FROM ejecuciones
GROUP BY id_ejecucion;
"""

CAMPOS_ANUNCIO = ["comercio", "id_producto", "sku", "ean", "nombre", "texto_original", "categoria_sitio",
                  "marca", "marca_std", "subcategoria_std", "nombre_std", "variante", "contenido", "unidad",
                  "unidades_empaque", "con_descripcion", "en_categoria", "motivo_exclusion", "url"]
SQL_ANUNCIO = """
INSERT INTO anuncios (comercio, id_producto_comercio, sku, ean, nombre, texto_original, categoria_sitio,
    marca_sitio, marca_std, subcategoria_std, nombre_std, variante, contenido, unidad, unidades_empaque,
    con_descripcion, en_categoria, motivo_exclusion, url)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (comercio, id_producto_comercio, sku) DO UPDATE SET
    ean = excluded.ean, nombre = excluded.nombre, texto_original = excluded.texto_original,
    categoria_sitio = excluded.categoria_sitio, marca_sitio = excluded.marca_sitio,
    marca_std = excluded.marca_std, subcategoria_std = excluded.subcategoria_std,
    nombre_std = excluded.nombre_std, variante = excluded.variante, contenido = excluded.contenido,
    unidad = excluded.unidad, unidades_empaque = excluded.unidades_empaque,
    con_descripcion = excluded.con_descripcion, en_categoria = excluded.en_categoria,
    motivo_exclusion = excluded.motivo_exclusion, url = excluded.url
"""
SQL_OBSERVACION = """
INSERT OR IGNORE INTO observaciones (id_anuncio, id_ejecucion, precio, precio_antes, promocion,
    disponibilidad, vendedor, fecha_consulta)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
"""
SQL_RECHAZO = """
INSERT OR IGNORE INTO rechazos (id_ejecucion, comercio, id_producto_comercio, sku, nombre, precio, url,
    fecha_consulta, motivo)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
"""


def conectar(db=BASE):
    con = sqlite3.connect(db)
    con.executescript(ESQUEMA)
    return con


def a_null(df):
    return df.astype(object).where(df.notna(), None)


def guardar(con, df, m):
    """Valida y agrega las observaciones de un comercio en una sola transacción; devuelve el resumen."""
    comercio, id_ej = m["comercio"], m["id_ejecucion"]
    df = limpiar(df)
    df[["id_producto", "sku"]] = df[["id_producto", "sku"]].astype(str)
    validas, rechazadas = validacion.validar(df) if m["estado"] != "fallida" else (df.iloc[0:0], df.iloc[0:0])
    comparables = validacion.contar_comparables(con, comercio, validas)
    estado, motivo = m["estado"], m.get("motivo")
    if estado == "parcial" and not motivo:
        cortadas = m.get("busquedas_cortadas")
        motivo = (f"{len(cortadas)} búsquedas llegaron al tope de 24 resultados" if cortadas
                  else "se obtuvieron menos productos de los que reporta el sitio")
    if estado != "fallida" and comparables < validacion.MIN_COMPARABLES:
        estado = "parcial"
        motivo = "; ".join(filter(None, [motivo, f"solo {comparables} productos comparables"]))

    # ejecución anterior del mismo comercio, para el resumen
    anterior = con.execute("""SELECT MAX(id_ejecucion) FROM ejecuciones
                              WHERE comercio = ? AND estado != 'fallida' AND id_ejecucion < ?""",
                           (comercio, id_ej)).fetchone()[0]
    precios_antes = dict(con.execute("""SELECT o.id_anuncio, o.precio FROM observaciones o
                                        JOIN anuncios a ON a.id_anuncio = o.id_anuncio
                                        WHERE o.id_ejecucion = ? AND a.comercio = ? AND a.en_categoria = 1
                                          AND o.descartada = 0""", (anterior, comercio)))
    ids_antes = {i for (i,) in con.execute("SELECT id_anuncio FROM anuncios WHERE comercio = ?", (comercio,))}

    with con:   # una transacción por comercio: si algo falla no queda nada a medias
        con.execute("""INSERT INTO ejecuciones VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                       ON CONFLICT DO NOTHING""",
                    (id_ej, comercio, m["fecha_consulta"], m.get("fecha_fin"), len(df), int(df["en_categoria"].sum()),
                     m.get("total_sitio"), estado, m.get("carpeta"), 0, len(rechazadas), comparables, motivo))
        con.executemany(SQL_ANUNCIO, a_null(validas[CAMPOS_ANUNCIO]).itertuples(index=False))
        ids = {(p, s): i for i, p, s in con.execute(
            "SELECT id_anuncio, id_producto_comercio, sku FROM anuncios WHERE comercio = ?", (comercio,))}
        antes = con.total_changes
        con.executemany(SQL_OBSERVACION, [
            (ids[(r.id_producto, r.sku)], r.id_ejecucion, r.precio, r.precio_antes, r.promocion,
             r.disponibilidad, r.vendedor, r.fecha_consulta) for r in a_null(validas).itertuples()])
        insertadas = con.total_changes - antes
        con.executemany(SQL_RECHAZO, [
            (id_ej, comercio, r.id_producto, r.sku, r.nombre, r.precio, r.url, r.fecha_consulta, r.motivo)
            for r in a_null(rechazadas).itertuples()])
        if insertadas:
            con.execute("UPDATE ejecuciones SET insertadas = ? WHERE id_ejecucion = ? AND comercio = ?",
                        (insertadas, id_ej, comercio))

    actuales = {ids[(r.id_producto, r.sku)]: r.precio
                for r in validas[validas["en_categoria"] == 1].itertuples()}
    resumen = {
        "comercio": comercio, "id_ejecucion": id_ej, "estado": estado, "motivo": motivo,
        "productos": len(df), "en_categoria": int(df["en_categoria"].sum()),
        "nuevos": sum(i not in ids_antes for i in actuales),
        "cambios_precio": sum(i in precios_antes and p != precios_antes[i] for i, p in actuales.items()),
        "no_observados": sum(i not in actuales for i in precios_antes),
        "insertadas": insertadas, "rechazadas": len(rechazadas), "comparables": comparables,
    }
    print(f"{comercio:10} {id_ej}  {len(df):5} registros, {insertadas:5} insertadas, "
          f"{len(rechazadas):4} rechazadas, {estado}")
    return resumen


def motivo_falla(e):
    if isinstance(e, PermissionError):
        return f"{e}; el sitio bloquea las consultas automáticas"
    if isinstance(e, (requests.ConnectionError, requests.Timeout)):
        return "no se pudo conectar con el sitio"
    if isinstance(e, (KeyError, ValueError, TypeError)):
        return f"cambió la estructura de la respuesta ({type(e).__name__}: {e})"
    return str(e)


RECOLECTORES = {"Exito": recolectar_exito, "Farmatodo": recolectar_farmatodo, "Locatel": recolectar_locatel}
CLAVES = {"Exito": "exito", "Farmatodo": "farmatodo", "Locatel": "locatel"}
COMERCIOS = tuple(RECOLECTORES)


def recolectar_comercio(comercio, online=True, id_ej=None, carpeta=None, db=BASE):
    """Recolecta un comercio en línea (o reprocesa una carpeta de raw/), valida y guarda en la base."""
    if online:
        id_ej = id_ej or nueva_ejecucion()
        inicio = ahora_iso()
        try:
            df, m = RECOLECTORES[comercio](online=True, id_ej=id_ej)
        except Exception as e:   # si un comercio falla, se registra el motivo y se sigue con los demás
            carpeta = nueva_carpeta(CLAVES[comercio], id_ej)
            m = {"comercio": comercio, "id_ejecucion": id_ej, "carpeta": carpeta.relative_to(CARPETA).as_posix(),
                 "fecha_consulta": inicio, "fecha_fin": ahora_iso(), "estado": "fallida", "motivo": motivo_falla(e)}
            escribir_manifiesto(carpeta, m)
            df = pd.DataFrame(columns=COLUMNAS)
    else:
        df, m = RECOLECTORES[comercio](online=False, carpeta=carpeta)
    con = conectar(db)
    try:
        return guardar(con, df, m)
    finally:
        con.close()


def ejecutar_recoleccion(online=True, db=BASE):
    """Recolecta los tres comercios con un mismo id de ejecución, o reprocesa todas las carpetas de raw/."""
    resumen = []
    if online:
        id_ej = nueva_ejecucion()
        for comercio in COMERCIOS:
            print(f"--- {comercio} ---")
            resumen.append(recolectar_comercio(comercio, online=True, id_ej=id_ej, db=db))
    else:
        for comercio in COMERCIOS:
            for manifiesto in sorted((RAW / CLAVES[comercio]).glob("*/*/manifiesto.json")):
                resumen.append(recolectar_comercio(comercio, online=False, carpeta=manifiesto.parent, db=db))
    return pd.DataFrame(resumen)
