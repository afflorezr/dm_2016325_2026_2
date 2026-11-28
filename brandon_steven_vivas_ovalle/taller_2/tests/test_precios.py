"""Conversión de precios en texto a número y normalización de unidades."""
import pytest

import limpieza as L
from scraper import limpiar_precio


@pytest.mark.parametrize("texto, esperado", [
    ("$ 12.900", 12900.0), ("12.900", 12900.0), ("$12.900,50", 12900.5), ("1.234.567", 1234567.0),
    ("12,5", 12.5), ("COP 7.450", 7450.0), ("49900", 49900.0), (49900, 49900.0), (1234.5, 1234.5),
])
def test_limpiar_precio_convierte_texto_a_numero(texto, esperado):
    assert limpiar_precio(texto) == esperado


@pytest.mark.parametrize("texto", [None, "", "agotado", "$", "0", "-5.000", "abc", True, float("nan")])
def test_limpiar_precio_invalido_queda_ausente(texto):
    """Un dato ausente o inválido queda como None (NULL): nunca se reemplaza por un valor inventado."""
    assert limpiar_precio(texto) is None


@pytest.mark.parametrize("nombre, subcat, esperado", [
    ("Crema Desitin 57 g", "crema de barrera", (57.0, "g", 1.0)),
    ("Crema Barrera 1 kg", "crema de barrera", (1000.0, "g", 1.0)),
    ("Crema Barrera 0,5 kg", "crema de barrera", (500.0, "g", 1.0)),
    ("Crema líquida 250 ml", "crema de barrera", (250.0, "ml", 1.0)),
    ("Crema líquida 1 L", "crema de barrera", (1000.0, "ml", 1.0)),
    ("Toallitas Húmedas Huggies 3 X 80 Und", "pañitos húmedos", (240.0, "unidad", 80.0)),
    ("Pañales Winny Etapa 3 X 30 Und", "pañal", (30.0, "unidad", 30.0)),
    ("Pañales Huggies Talla G 44 Unidades", "pañal", (44.0, "unidad", 44.0)),
])
def test_normalizacion_de_unidades(nombre, subcat, esperado):
    """El contenido total se expresa siempre en una unidad base: unidad, g o ml."""
    assert L.extraer_contenido(nombre, subcat) == esperado


def test_la_talla_no_se_confunde_con_la_cantidad():
    assert L.extraer_etapa("Pañales Winny Gold Etapa 4 X30 Unds") == L.extraer_etapa("Pañales WINNY gold 4XG (30 und)")
