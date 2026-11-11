"""
tests/test_parser.py
====================
Pruebas unitarias para el parser de contenidos y unidades (parse_content_and_unit)
del módulo scraper.py.
"""

import pytest
from scraper import parse_content_and_unit


def test_multipack_x_after():
    # Caso: '450g x 2und'
    cnt, unit, unds = parse_content_and_unit("Lavaplatos en Crema Axion Limón 450g x 2und")
    assert cnt == 900.0
    assert unit == "g"
    assert unds == 2


def test_multipack_x_before():
    # Caso: '2x450 g'
    cnt, unit, unds = parse_content_and_unit("Lavaplatos Axion Limón Desengrasante Crema 2x450 g")
    assert cnt == 900.0
    assert unit == "g"
    assert unds == 2


def test_liters_decimal():
    # Caso: '1.5L'
    cnt, unit, unds = parse_content_and_unit("Lavaplatos Liquido Axion Limon 1.5L")
    assert cnt == 1500.0
    assert unit == "ml"
    assert unds == 1


def test_liters_lt():
    # Caso: '1 lt'
    cnt, unit, unds = parse_content_and_unit("Limpia Pisos Fabuloso Antibacterial Lavanda 1 lt")
    assert cnt == 1000.0
    assert unit == "ml"
    assert unds == 1


def test_parenthesis_grams():
    # Caso: '(5000  gr)'
    cnt, unit, unds = parse_content_and_unit("Detergente en polvo ARIEL triple poder (5000  gr)")
    assert cnt == 5000.0
    assert unit == "g"
    assert unds == 1


def test_kilograms_capital():
    # Caso: '2 Kg'
    cnt, unit, unds = parse_content_and_unit("Detergente Polvo Fab Ultra flash 2 Kg")
    assert cnt == 2000.0
    assert unit == "g"
    assert unds == 1


def test_x_prefix_liters():
    # Caso: 'x1.8L'
    cnt, unit, unds = parse_content_and_unit("Blanqueador Clorox Original x1.8L")
    assert cnt == 1800.0
    assert unit == "ml"
    assert unds == 1


def test_countable_units():
    # Caso: 'Bolsas para basura 30 und'
    cnt, unit, unds = parse_content_and_unit("Bolsa de basura negra 50x70 cm 30 und")
    assert cnt == 30.0
    assert unit == "und"
    assert unds == 30


def test_unknown_returns_none():
    # Caso: Sin contenido cuantificable
    cnt, unit, unds = parse_content_and_unit("Esponja de brillo multiusos")
    assert cnt is None
    assert unit is None
    assert unds == 1
