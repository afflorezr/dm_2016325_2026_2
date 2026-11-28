"""tests/test_limpieza.py — conversión de precios, normalización de unidades y validación (sin base de datos)."""
import pandas as pd

import scraper
import validacion
from conftest import EAN_A, E1, fila


# [CAMBIO]: §9: conversión de precios en texto a número (formato colombiano); lo ilegible queda ausente (None).
def test_precio_en_texto_a_numero():
    assert validacion.precio_a_numero("$ 12.900") == 12900
    assert validacion.precio_a_numero("COP 1.250.000") == 1250000
    assert validacion.precio_a_numero("12.900,50") == 12900.5
    assert validacion.precio_a_numero(8900) == 8900.0
    assert validacion.precio_a_numero("agotado") is None
    assert validacion.precio_a_numero(None) is None


# [CAMBIO]: §9: normalización de unidades: litros a mL, kilos a g, paquetes multiplican el contenido.
def test_normalizacion_de_unidades():
    # (contenido_unitario, unidad, n_unidades, contenido_total)
    assert scraper.extraer_contenido("Shampoo x 1 Litro") == (1000.0, "ml", 1, 1000.0)
    assert scraper.extraer_contenido("Tinte 1 kg") == (1000.0, "g", 1, 1000.0)
    assert scraper.extraer_contenido("Shampoo 2 x 400 ml") == (400.0, "ml", 2, 800.0)
    assert scraper.extraer_contenido("Crema de peinar 300 g") == (300.0, "g", 1, 300.0)
    # sin contenido en el nombre: se usa la ficha técnica del comercio
    assert scraper.extraer_contenido("Ampolla capilar", "3 Unidades") == (3.0, "un", 1, 3.0)
    # sin dato en ningún lado: queda ausente, no se inventa
    assert scraper.extraer_contenido("Producto sin medida") == (None, None, None, None)


# [CAMBIO]: §3.4: validación antes de insertar: precio ausente o no positivo, URL faltante y duplicados se rechazan.
def test_validacion_rechaza_observaciones_invalidas():
    filas = [fila("larebaja", "ok", EAN_A, 10000, E1),
             fila("larebaja", "nulo", EAN_A, None, E1),
             fila("larebaja", "cero", EAN_A, 0, E1),
             fila("larebaja", "sin_url", EAN_A, 5000, E1),
             fila("larebaja", "ok", EAN_A, 10000, E1)]           # duplicado en la misma ejecución
    filas[3]["url"] = None
    validas, rechazadas = validacion.validar_observaciones(pd.DataFrame(filas, columns=scraper.COLUMNAS))
    assert list(validas["sku_comercio"]) == ["ok"]               # se conserva el primero
    reglas = dict(zip(rechazadas["sku_comercio"] + "/" + rechazadas.index.astype(str), rechazadas["regla"]))
    assert set(rechazadas["regla"]) == {"precio_mayor_que_cero", "campo_obligatorio", "duplicado_en_ejecucion"}
    assert len(rechazadas) == 4, reglas
    # R4: si falta un comparable esperado, se informa cuál
    assert validacion.comparables_faltantes(validas, {"ok", "otro"}) == ["otro"]
