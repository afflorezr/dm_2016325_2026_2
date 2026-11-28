import pytest

import db
from base_prueba import crear_base


@pytest.fixture
def base_prueba(tmp_path, monkeypatch):
    """Base temporal de base_prueba.py. db.py la lee en lugar de la base de la entrega."""
    ruta = tmp_path / "prueba.sqlite"
    crear_base(ruta)
    monkeypatch.setattr(db, "DB_PATH", ruta)
    db.limpiar_cache()          # que no quede nada guardado de otra prueba
    yield ruta
    db.limpiar_cache()
