"""Ahorro con empates, resumen de canasta y clasificación de variaciones."""
import pandas as pd
import pytest

import analisis as A


def test_ahorro_simple():
    r = A.ahorro_entre_comercios({"Éxito": 100.0, "Jumbo": 120.0, "Olímpica": 110.0})
    assert (r["minimo"], r["maximo"], r["ahorro_cop"]) == (100.0, 120.0, 20.0)
    assert r["ahorro_pct"] == pytest.approx(100 * 20 / 120)
    assert r["mas_baratos"] == ["Éxito"] and r["mas_caros"] == ["Jumbo"]


def test_ahorro_con_empate_en_el_minimo_devuelve_todos_los_empatados():
    r = A.ahorro_entre_comercios({"Éxito": 100.0, "Jumbo": 100.0, "Olímpica": 130.0})
    assert r["mas_baratos"] == sorted(["Éxito", "Jumbo"])
    assert r["ahorro_cop"] == 30.0


def test_ahorro_con_todos_empatados_es_cero():
    r = A.ahorro_entre_comercios({"Éxito": 50.0, "Jumbo": 50.0, "Olímpica": 50.0})
    assert r["ahorro_cop"] == 0 and r["ahorro_pct"] == 0
    assert r["mas_baratos"] == sorted(["Éxito", "Jumbo", "Olímpica"])


def test_ahorro_ignora_comercios_sin_precio_y_no_inventa_ahorro_con_uno_solo():
    r = A.ahorro_entre_comercios({"Éxito": 80.0, "Jumbo": None, "Olímpica": float("nan")})
    assert r["n_comercios"] == 1 and r["ahorro_cop"] is None and r["mas_baratos"] == ["Éxito"]
    assert A.ahorro_entre_comercios({})["minimo"] is None


@pytest.mark.parametrize("anterior, nuevo, tipo", [
    (100.0, 110.0, "subió"), (100.0, 90.0, "bajó"), (100.0, 100.0, "sin cambio"), (100.0, 100.3, "sin cambio"),
    (None, 100.0, "nuevo"), (100.0, None, "dejó de observarse"), (None, None, "sin precio en alguna ejecución"),
])
def test_clasificar_variacion(anterior, nuevo, tipo):
    assert A.clasificar_variacion(anterior, nuevo)["tipo"] == tipo


def test_umbral_de_variacion_grande():
    assert A.clasificar_variacion(100.0, 106.0, umbral_pct=5)["grande"] is True
    assert A.clasificar_variacion(100.0, 104.0, umbral_pct=5)["grande"] is False
    assert A.clasificar_variacion(100.0, 104.0, umbral_pct=3)["grande"] is True


def test_formatos_colombianos():
    assert A.n_(1234567.5, 1) == "1.234.567,5"
    assert A.cop(12900) == "$12.900 COP"
    assert A.cop(None) == "—"
    assert A.etiqueta_ejecucion("run_20261011T193258") == "2026-10-11 19:32"


def test_resumen_canasta_sin_total_cuando_falta_un_producto():
    totales = pd.DataFrame({"comercio": ["A", "B"], "n_seleccionados": [2, 2], "n_con_precio": [2, 1],
                            "n_faltantes": [0, 1], "total": [100.0, None]})
    minimo = pd.DataFrame({"nombre_std": ["x", "y"], "cantidad": [1, 1], "precio_minimo": [40.0, 50.0],
                           "subtotal": [40.0, 50.0], "comercios": ["A", "B"]})
    r = A.resumen_canasta(totales, minimo, 2)
    assert r["comercios_completos"] == ["A"] and r["comercios_incompletos"][0]["comercio"] == "B"
    assert r["costo_minimo"] == 90.0 and r["ahorro_vs_mejor_unico"] == 10.0


def test_resumen_canasta_no_calcula_minimo_si_un_producto_no_tiene_precio_en_ningun_comercio():
    totales = pd.DataFrame({"comercio": ["A"], "n_seleccionados": [2], "n_con_precio": [1], "n_faltantes": [1], "total": [None]})
    minimo = pd.DataFrame({"nombre_std": ["x"], "cantidad": [1], "precio_minimo": [40.0], "subtotal": [40.0], "comercios": ["A"]})
    r = A.resumen_canasta(totales, minimo, 2)
    assert r["costo_minimo"] is None and r["productos_sin_precio"] == 1 and r["mejor_unico"] == []


def test_resumen_canasta_con_empate_entre_comercios_y_ahorro_cero():
    totales = pd.DataFrame({"comercio": ["A", "B"], "n_seleccionados": [1, 1], "n_con_precio": [1, 1],
                            "n_faltantes": [0, 0], "total": [70.0, 70.0]})
    minimo = pd.DataFrame({"nombre_std": ["x"], "cantidad": [1], "precio_minimo": [70.0], "subtotal": [70.0], "comercios": ["A, B"]})
    r = A.resumen_canasta(totales, minimo, 1)
    assert r["mejor_unico"] == ["A", "B"] and r["ahorro_vs_mejor_unico"] == 0.0
