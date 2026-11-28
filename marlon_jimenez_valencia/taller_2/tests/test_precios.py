# Conversión de precios en texto a número y normalización de unidades.
import pytest

from limpieza import contenido_normalizado
from scraper import limpiar_precio


@pytest.mark.parametrize("valor, esperado", [
    ("$ 12.900", 12900),
    ("$12.900", 12900),
    ("COP 8.500", 8500),
    ("$ 1.234.567", 1234567),
    ("12.900,50", 12900.5),
    (12900, 12900),          # VTEX ya trae el precio como número
    (5400.0, 5400),
])
def test_precio_en_texto_a_numero(valor, esperado):
    assert limpiar_precio(valor) == esperado


@pytest.mark.parametrize("valor", [None, "", "$", "Agotado", float("nan")])
def test_precio_ausente_queda_vacio_y_no_en_cero(valor):
    assert limpiar_precio(valor) is None


@pytest.mark.parametrize("unidades, contenido, unidad, esperado", [
    (None, 100, "ML", (100.0, "mL")),     # suspensión o jarabe
    (None, 30, "G", (30.0, "g")),         # crema o polvo
    (10, None, None, (10.0, "unidad")),   # caja de tabletas
    (1, 60, "ML", (60.0, "mL")),          # si hay volumen, se usa el volumen
    (None, None, None, (None, None)),     # sin datos no se inventa un contenido
    (0, 0, "ML", (None, None)),
])
def test_normalizacion_de_unidades(unidades, contenido, unidad, esperado):
    assert contenido_normalizado(unidades, contenido, unidad) == esperado
