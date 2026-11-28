"""
tests/conftest.py
=================
Configuración global de pytest y fixtures temporales aisladas.
Taller 2 - Minería de Datos (UNAL, código 2016325).
"""

import sys
import os
import sqlite3
import pytest
from pathlib import Path

# Garantizar que taller_2 esté en sys.path usando rutas relativas
TALLER2_DIR = Path(__file__).resolve().parent.parent
if str(TALLER2_DIR) not in sys.path:
    sys.path.insert(0, str(TALLER2_DIR))

from scraper import init_database
from migraciones import migrar_esquema


@pytest.fixture
def temp_db(tmp_path):
    """
    Fixture que crea una base de datos SQLite temporal y limpia en tmp_path.
    Aplica el esquema completo de tablas, vistas e índices sin tocar la base real.
    """
    db_file = tmp_path / "test_comparador.sqlite"
    init_database(str(db_file))
    migrar_esquema(db_file, reprocesar_raw=False)
    return db_file
