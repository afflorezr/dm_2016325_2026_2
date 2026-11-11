"""
tests/test_app.py - Pruebas automáticas (pytest) del comparador de precios.

Ejecutar desde taller_2/:   pytest tests/
Usan una base SQLite en memoria (:memory:) con datos simulados: nunca tocan la base de la entrega
ni los sitios de los comercios.
"""

import os
import sqlite3
import sys

import pandas as pd
import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import analisis  # noqa: E402
import migrar_db  # noqa: E402
import scraper  # noqa: E402


# ----------------------------------------------------------------------------
# Fixtures: base en memoria con el esquema del Taller 1 + migración del Taller 2
# ----------------------------------------------------------------------------
@pytest.fixture
def con():
    c = scraper.conectar(":memory:")          # esquema del Taller 1 (tablas y restricciones)
    migrar_db.aplicar_migracion(c)            # columnas, índices y vistas del Taller 2
    for i, nombre in enumerate(["La Rebaja", "Olímpica", "Éxito"], start=1):
        c.execute("INSERT INTO comercios (id, nombre, url_base) VALUES (?,?,?)", (i, nombre, "https://x"))
    for i, (corrida, inicio) in enumerate([("r1", "2026-10-01T10:00:00-05:00"),
                                           ("r2", "2026-11-01T10:00:00-05:00")], start=1):
        c.execute("""INSERT INTO ejecuciones (id, corrida_id, inicio, comercio, modo, n_registros, estado)
                     VALUES (?,?,?,?,?,?,?)""", (i, corrida, inicio, "La Rebaja", "online", 1, "completa"))
    yield c
    c.close()


def fila(comercio="La Rebaja", sku="s1", precio=10000.0, fecha="2026-10-01T10:00:00-05:00"):
    """Fila con las mismas columnas que devuelve el scraper (scraper.COLUMNAS)."""
    return {"comercio": comercio, "sku": sku, "ean": None, "product_id": sku, "url": "https://x/p",
            "nombre_original": "Gel de afeitar 200 ml", "descripcion_original": "",
            "texto_original": "Gel de afeitar 200 ml", "marca_original": "Marca", "categoria_sitio": "Afeitado",
            "precio_cop": precio, "precio_regular_cop": precio, "en_promocion": 0, "disponible": 1,
            "fecha_consulta": fecha}


# ----------------------------------------------------------------------------
# 1. Conversión de precios en texto a número
# ----------------------------------------------------------------------------
def test_limpiar_precio():
    assert scraper.limpiar_precio("$ 12.900") == 12900
    assert isinstance(scraper.limpiar_precio("$ 12.900"), int)
    assert scraper.limpiar_precio("$1.234.567") == 1234567
    assert scraper.limpiar_precio("12.900,50") == 12900.5
    assert scraper.limpiar_precio(12900.0) == 12900
    assert scraper.limpiar_precio("agotado") is None       # sin número: ausente, nunca 0
    assert scraper.limpiar_precio(None) is None


# ----------------------------------------------------------------------------
# 2. Normalización de unidades (L -> mL, kg -> g, paquetes múltiples)
# ----------------------------------------------------------------------------
@pytest.mark.parametrize("texto, esperado", [
    ("Loción 1 L", (1000.0, "mL", 1)),
    ("Espuma 250 ml", (250.0, "mL", 1)),
    ("Crema 2 kg", (2000.0, "g", 1)),
    ("Polvo 500 g", (500.0, "g", 1)),
    ("Ampolla 500 mg", (500.0, "mg", 1)),
    ("Gel 3 x 100 ml", (300.0, "mL", 3)),          # paquete: contenido total
    ("Gel sin tamaño", (None, None, 1)),
])
def test_normalizar_unidades(texto, esperado):
    assert scraper.extraer_contenido(texto) == esperado


# ----------------------------------------------------------------------------
# 3. Ahorro con empates en el precio mínimo
# ----------------------------------------------------------------------------
def test_calculo_ahorro_empates():
    r = analisis.calcular_ahorro({"La Rebaja": 8000, "Olímpica": 8000, "Éxito": 10000})
    assert r["pmin"] == 8000 and r["pmax"] == 10000
    assert r["ahorro_cop"] == 2000
    assert r["ahorro_pct"] == pytest.approx(20.0)                      # 100 * (10000 - 8000) / 10000
    assert r["comercios_minimos"] == ["La Rebaja", "Olímpica"]         # ambos empatan, ninguno se pierde
    # todos iguales: ahorro cero; sin precios válidos: None (no se inventa un ahorro)
    assert analisis.calcular_ahorro({"A": 500, "B": 500})["ahorro_cop"] == 0
    assert analisis.calcular_ahorro({"A": None, "B": float("nan")}) is None


def test_vista_comparables_marca_empates(con):
    """En SQL (v_comparables) los dos comercios empatados quedan marcados como precio mínimo."""
    con.execute("INSERT INTO productos (id, clave_comun, nombre_estandar, n_comercios, comparable) VALUES (1,'EAN:1','gel',3,1)")
    con.executemany("INSERT INTO seleccion VALUES (?)", [(1,), (2,), (3,)])
    for cid, precio in [(1, 8000.0), (2, 8000.0), (3, 10000.0)]:
        con.execute("""INSERT INTO anuncios (comercio_id, sku, url, texto_original, producto_id, contenido_total, unidad_base)
                       VALUES (?,?,?,?,1,200,'mL')""", (cid, "s", "u", "t"))
        con.execute("""INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_cop, en_promocion, disponible, fecha_consulta)
                       VALUES (last_insert_rowid(),2,?,0,1,'2026-11-01T10:00:00-05:00')""", (precio,))
    filas = con.execute("SELECT comercio, es_precio_minimo FROM v_comparables ORDER BY comercio").fetchall()
    assert {r[0]: r[1] for r in filas} == {"Éxito": 0, "La Rebaja": 1, "Olímpica": 1}


# ----------------------------------------------------------------------------
# 4. Unicidad: la misma observación no se inserta dos veces
# ----------------------------------------------------------------------------
def test_unicidad_insercion(con):
    f = fila()
    assert scraper._insertar(con, f, 1) == 1        # primera vez: se inserta
    assert scraper._insertar(con, f, 1) == 0        # misma observación y ejecución: se ignora
    n = con.execute("SELECT COUNT(*) FROM observaciones").fetchone()[0]
    assert n == 1                                    # no hay duplicados
    # y la restricción de la base rechaza el duplicado si se intenta forzar
    with pytest.raises(sqlite3.IntegrityError):
        con.execute("""INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_cop, en_promocion, disponible, fecha_consulta)
                       SELECT anuncio_id, ejecucion_id, precio_cop, en_promocion, disponible, fecha_consulta FROM observaciones""")


# ----------------------------------------------------------------------------
# 5. Detección de cambios de precio (diferencia absoluta y porcentual)
# ----------------------------------------------------------------------------
def test_deteccion_cambios(con):
    scraper._insertar(con, fila(precio=10000.0, fecha="2026-10-01T10:00:00-05:00"), 1)
    scraper._insertar(con, fila(precio=12500.0, fecha="2026-11-01T10:00:00-05:00"), 2)
    scraper._insertar(con, fila(sku="s2", precio=8000.0, fecha="2026-10-01T10:00:00-05:00"), 1)
    scraper._insertar(con, fila(sku="s2", precio=6000.0, fecha="2026-11-01T10:00:00-05:00"), 2)
    scraper._insertar(con, fila(sku="s3", precio=5000.0, fecha="2026-10-01T10:00:00-05:00"), 1)
    scraper._insertar(con, fila(sku="s3", precio=5000.0, fecha="2026-11-01T10:00:00-05:00"), 2)
    r = {x["sku"]: x for x in con.execute(
        "SELECT * FROM v_cambios_precio WHERE corrida_anterior='r1' AND corrida_id='r2'")}
    assert r["s1"]["variacion_cop"] == 2500 and r["s1"]["variacion_pct"] == pytest.approx(25.0)
    assert r["s1"]["sentido"] == "subio"
    assert r["s2"]["variacion_cop"] == -2000 and r["s2"]["variacion_pct"] == pytest.approx(-25.0)
    assert r["s2"]["sentido"] == "bajo"
    assert r["s3"]["variacion_pct"] == 0 and r["s3"]["sentido"] == "igual"


# ----------------------------------------------------------------------------
# 6. La canasta no se calcula si a un comercio le falta un producto
# ----------------------------------------------------------------------------
def test_canasta_incompleta():
    precios = pd.DataFrame([
        {"producto_id": 1, "comercio": "La Rebaja", "precio": 10000.0},
        {"producto_id": 2, "comercio": "La Rebaja", "precio": 5000.0},
        {"producto_id": 1, "comercio": "Olímpica", "precio": 9000.0},     # a Olímpica le falta el producto 2
    ])
    r = analisis.calcular_canasta(precios, {1: 2, 2: 1})
    t = r["totales"].set_index("comercio")
    assert t.loc["La Rebaja", "costo"] == 25000.0 and bool(t.loc["La Rebaja", "completo"])
    assert pd.isna(t.loc["Olímpica", "costo"])                              # no se muestra un total incompleto
    assert not bool(t.loc["Olímpica", "completo"])
    assert t.loc["Olímpica", "faltantes"] == [2]
    # la canasta ideal sí existe (cada producto tiene precio en algún comercio) y ahorra frente al comercio completo
    assert r["costo_ideal"] == 9000.0 * 2 + 5000.0
    assert r["ahorro_vs_completos"].iloc[0]["ahorro_cop"] == 25000.0 - 23000.0
    # si un producto no tiene precio en ningún comercio, no hay canasta ideal
    r2 = analisis.calcular_canasta(precios, {1: 1, 99: 1})
    assert r2["costo_ideal"] is None and r2["sin_precio"] == [99]
