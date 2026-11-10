"""
Datos SINTÉTICOS solo para probar el código (no son precios reales ni se usan en la aplicación ni en la base entregada).
Simulan la API VTEX (modo legacy) de tres comercios sin tocar internet.
"""
from __future__ import annotations

from datetime import datetime, timedelta

import scraper as S

NOMBRES = [  # (nombre, marca, precio base, categoría)
    ("Pañales Huggies Natural Care Etapa 3/G X 50 Und", "Huggies", 69400, "/Cuidado del bebé/Pañales/"),
    ("Pañales Huggies Natural Care Etapa 3/G X 100 Und", "Huggies", 125950, "/Cuidado del bebé/Pañales/"),
    ("Pañales Huggies Active Sec Etapa 3 Paquete X 50 Und", "Huggies", 62950, "/Cuidado del bebé/Pañales/"),
    ("Pañales Huggies Natural Care Etapa 5/XXG X 50 Und", "Huggies", 99950, "/Cuidado del bebé/Pañales/"),
    ("Pañales Winny Ultratrim Sec Etapa 3 X 30 Und", "Winny", 31000, "/Cuidado del bebé/Pañales/"),
    ("Pañales Babysec Ultraprotect Etapa 3 X 50 Unidades", "Babysec", 52000, "/Cuidado del bebé/Pañales/"),
    ("Pañales Pampers Confortsec Talla G 44 Unidades", "Pampers", 78000, "/Cuidado del bebé/Pañales/"),
    ("Toallitas Húmedas Huggies Puro y Natural 3 X 80 Und", "Huggies", 29900, "/Cuidado del bebé/Toallitas/"),
    ("Toallitas Húmedas Huggies Puro y Natural X 80 Und", "Huggies", 11000, "/Cuidado del bebé/Toallitas/"),
    ("Cambiador Desechable Winny X 10 Und", "Winny", 14500, "/Cuidado del bebé/Cambiadores/"),
    ("Crema Antipañalitis Desitin Barrera 57 g", "Desitin", 26000, "/Cuidado del bebé/Cremas/"),
    ("Crema Antipañalitis Desitin Barrera 113 g", "Desitin", 41000, "/Cuidado del bebé/Cremas/"),
    # Para excluir de la categoría:
    ("Pañales para Adulto Tena Slip M X 10 Und", "Tena", 40000, "/Salud/Adulto/"),
    ("Pañalera Bolso Chicco Gris", "Chicco", 150000, "/Cuidado del bebé/Accesorios/"),
    ("Toallitas Desmaquillantes Nivea X 25", "Nivea", 12000, "/Belleza/"),
    ("Pañales Winny Etapa 3 X 200 + 40 Toallitas Húmedas", "Winny", 99000, "/Cuidado del bebé/Pañales/"),
    ("Crema Nistatina Antimicótica Pañalitis 30 g", "Genfar", 9000, "/Salud/"),
]
FACTOR = {"exito": 1.0, "jumbo": 1.05, "olimpica": 0.97}
OMITE_BASE = {"exito": {9}, "jumbo": {6}, "olimpica": {3}}


def producto(i, nombre, marca, precio, cat, factor, tienda, agotado=False, sin_precio=False):
    lista = round(precio * factor)
    pagar = round(lista * (0.9 if i % 5 == 0 else 1))
    if sin_precio:
        pagar = lista = 0
    return {
        "productId": f"{tienda[:1]}{i}", "productName": nombre, "brand": marca, "categories": [cat],
        "link": f"/{nombre.lower().replace(' ', '-')}/p", "description": f"Descripción de {nombre}",
        "items": [{"itemId": f"{1000 + i}", "name": nombre, "nameComplete": nombre, "ean": f"77000{i:04d}",
                   "sellers": [{"commertialOffer": {"Price": pagar, "ListPrice": lista,
                                                    "AvailableQuantity": 0 if agotado else 10}}]}],
    }


class ClienteFalso:
    """Cliente HTTP falso. `mult` {indice: factor} cambia precios; `omite` {comercio: {indices}}; `agotados` {indices};
    `falla` {comercio} simula un sitio bloqueado; `sin_precio_disponible` {indices} produce precio 0 con stock (dato inválido)."""

    def __init__(self, omite=None, mult=None, agotados=(), falla=(), sin_precio_disponible=()):
        self.llamadas = 0
        self.pausa = 0
        self.omite = omite if omite is not None else OMITE_BASE
        self.mult, self.agotados, self.falla = mult or {}, set(agotados), set(falla)
        self.sin_precio_disponible = set(sin_precio_disponible)

    def reiniciar_contador(self):
        pass

    def get_json(self, url, params=None):
        self.llamadas += 1
        tienda = next(k for k, c in S.COMERCIOS.items() if url.startswith(c.base_url))
        if tienda in self.falla:
            raise S.ErrorHTTP(f"HTTP 403 simulado en {url}")
        if "category/tree" in url:
            return [{"id": 1, "name": "Bebé", "children": [{"id": 11, "name": "Pañales", "children": []},
                    {"id": 12, "name": "Toallitas húmedas", "children": []}]}], {}, url
        lista = [producto(i, n[0], n[1], n[2] * self.mult.get(i, 1), n[3], FACTOR[tienda], tienda,
                          agotado=i in self.agotados, sin_precio=i in self.sin_precio_disponible)
                 for i, n in enumerate(NOMBRES) if i not in self.omite.get(tienda, set())]
        a, b = params["_from"], params["_to"]
        return lista[a:b + 1], {"resources": f"{a}-{min(b, len(lista) - 1)}/{len(lista)}"}, url + "?x"


class Reloj:
    """Sustituye S.ahora_iso con marcas de tiempo controladas (un segundo por llamada) para no depender del reloj real."""

    def __init__(self, inicio: str):
        self.t = datetime.fromisoformat(inicio)
        self.original = S.ahora_iso

    def __call__(self):
        self.t += timedelta(seconds=1)
        return self.t.isoformat(timespec="seconds")

    def __enter__(self):
        S.ahora_iso = self
        return self

    def __exit__(self, *a):
        S.ahora_iso = self.original
        return False


def ejecutar(db_path, raw_dir, ejec, inicio, cliente=None, comercios=("exito", "jumbo", "olimpica")):
    """Una ejecución completa con datos falsos y reloj controlado. Devuelve el resumen (DataFrame)."""
    cliente = cliente or ClienteFalso()
    with Reloj(inicio):
        return S.ejecutar_recoleccion(db_path, raw_dir, comercios=list(comercios), cliente=cliente, ejecucion_id=ejec)
