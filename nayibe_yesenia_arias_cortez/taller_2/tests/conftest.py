"""
tests/conftest.py — Taller 2: datos de prueba PEQUEÑOS en una base TEMPORAL (§9: nunca la base de la entrega ni
los sitios de los comercios).

La base temporal se llena con el mismo código de la aplicación: estandarizar (scraper.py) → validar
(validacion.py) → guardar_comercio (db.py) → marcar_comparables (comparables.py). Los productos son ficticios y
solo existen dentro de las pruebas; nunca se insertan en comparador_precios.sqlite.

Escenario (dos ejecuciones, tres comercios; precios en COP):
                         Ejecución 1 (E1)               Ejecución 2 (E2)
  A Shampoo 400 ml       rebaja 10.000 · locatel 9.000   rebaja 11.000 (+10 %) · locatel 9.000 ·
  (comparable)           · cafam 9.000  (empate)         cafam 8.000 (-11,1 %)
  B Acondic. 300 ml      rebaja 20.000 · locatel 25.000  rebaja NO aparece · locatel 25.000 ·
  (comparable)           · cafam 22.000                  cafam 22.000 pero AGOTADO
  C Gel 200 g (solo Cafam, no comparable)  —             cafam 15.000 (nuevo)
"""
import pandas as pd
import pytest

import comparables
import db
import scraper
import validacion

E1, E2 = "20261001T100000", "20261101T100000"
EAN_A, EAN_B, EAN_C = "7700000000017", "7700000000024", "7700000000031"
NOMBRES = {EAN_A: "Shampoo Prueba A 400 ml", EAN_B: "Acondicionador Prueba B 300 ml", EAN_C: "Gel Prueba C 200 g"}


# [CAMBIO]: ninguna prueba puede hacer peticiones reales: si algo intentara usar la red, la prueba falla.
@pytest.fixture(autouse=True)
def sin_red(monkeypatch):
    def prohibido(*args, **kwargs):
        raise RuntimeError("Las pruebas no pueden consultar los sitios de los comercios")
    monkeypatch.setattr(scraper, "_get", prohibido)


# [CAMBIO]: una fila con las mismas columnas que devuelve el scraper (scraper.COLUMNAS).
def fila(comercio, sku, ean, precio, id_ejecucion, disponible=1, precio_antes=None):
    return {"comercio": comercio, "sku_comercio": sku, "product_id": sku, "ean": ean,
            "nombre_original": NOMBRES[ean], "texto_original_anuncio": NOMBRES[ean], "marca_original": "Prueba",
            "subcategoria_original": "Cuidado capilar", "rama_origen": "prueba", "presentacion_ficha": None,
            "tiene_descripcion": 0, "precio": precio, "precio_antes_descuento": precio_antes,
            "es_promocion": int(precio_antes is not None), "promocion_texto": None, "disponible": disponible,
            "vendedor": "Prueba", "url": f"https://prueba.example/{comercio}/{sku}",
            "fecha_hora_consulta": f"{id_ejecucion[:4]}-{id_ejecucion[4:6]}-{id_ejecucion[6:8]}T10:00:00-05:00",
            "id_ejecucion": id_ejecucion}


# [CAMBIO]: fila de la tabla `ejecuciones` para un comercio.
def ejecucion(comercio, id_ejecucion, n):
    inicio = f"{id_ejecucion[:4]}-{id_ejecucion[4:6]}-{id_ejecucion[6:8]}T10:00:00-05:00"
    return {"id_ejecucion": id_ejecucion, "id_comercio": comercio, "fecha_hora_inicio": inicio,
            "fecha_hora_fin": inicio, "n_registros": n, "n_productos": n, "total_sitio": n, "n_incluidos": n,
            "estado": "completa", "detalle_ramas": "prueba", "nota": None}


# [CAMBIO]: pasa filas por el mismo camino que la aplicación: estandarizar → validar → guardar (una transacción).
def cargar(db_path, filas, comercio, id_ejecucion):
    datos = scraper.estandarizar(pd.DataFrame(filas, columns=scraper.COLUMNAS))
    validas, rechazadas = validacion.validar_observaciones(datos)
    return db.guardar_comercio(validas, rechazadas, ejecucion(comercio, id_ejecucion, len(filas)), db_path)


DATOS_E1 = {
    "larebaja": [fila("larebaja", "r1", EAN_A, 10000, E1), fila("larebaja", "r2", EAN_B, 20000, E1)],
    "locatel": [fila("locatel", "l1", EAN_A, 9000, E1), fila("locatel", "l2", EAN_B, 25000, E1)],
    "cafam": [fila("cafam", "c1", EAN_A, 9000, E1), fila("cafam", "c2", EAN_B, 22000, E1)],
}
DATOS_E2 = {
    "larebaja": [fila("larebaja", "r1", EAN_A, 11000, E2)],
    "locatel": [fila("locatel", "l1", EAN_A, 9000, E2), fila("locatel", "l2", EAN_B, 25000, E2)],
    "cafam": [fila("cafam", "c1", EAN_A, 8000, E2), fila("cafam", "c2", EAN_B, 22000, E2, disponible=0),
              fila("cafam", "c3", EAN_C, 15000, E2)],
}


# [CAMBIO]: base temporal con las dos ejecuciones y los comparables marcados (se borra sola al terminar).
@pytest.fixture
def base(tmp_path):
    ruta = tmp_path / "prueba.sqlite"
    db.migrar(ruta)
    for datos, id_ejecucion in ((DATOS_E1, E1), (DATOS_E2, E2)):
        for comercio, filas in datos.items():
            cargar(ruta, filas, comercio, id_ejecucion)
    comparables.marcar_comparables(db_path=ruta, id_ejecucion=E1, mostrar=False)
    return ruta
