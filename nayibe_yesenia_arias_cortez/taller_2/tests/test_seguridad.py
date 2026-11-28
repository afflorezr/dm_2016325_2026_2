"""tests/test_seguridad.py — entradas maliciosas (Módulo 4) y tope de peticiones del scraper (§6), sin red."""
import json

import pytest

import db
import scraper


# [CAMBIO]: §6: textos con caracteres no permitidos se rechazan; un valor válido se trata como texto literal (no
# cambia la consulta) y la base sigue intacta.
def test_entradas_maliciosas_no_alteran_la_consulta(base):
    for texto in ["'; DROP TABLE observaciones; --", "x' OR '1'='1", "%", "a" * 61]:
        with pytest.raises(ValueError):
            db.productos_filtrados({"busqueda": texto}, db_path=base)
    with pytest.raises(ValueError):
        db.productos_filtrados({"comercios": ["exito"]}, db_path=base)
    assert db.productos_filtrados({"marcas": ["PRUEBA OR 1"]}, db_path=base).empty   # literal: 0 filas
    assert len(db.productos_filtrados({"marcas": ["PRUEBA"]}, db_path=base)) == 6     # última ejecución
    assert len(db.productos_filtrados({"busqueda": "acondicionador"}, db_path=base)) == 2


# [CAMBIO]: §6: el scraper se detiene al llegar a MAX_PETICIONES y la ejecución queda 'parcial' (no 'completa').
# Se reemplaza la petición HTTP por una respuesta falsa: la prueba no toca la red.
def test_tope_de_peticiones(monkeypatch, tmp_path):
    class RespuestaFalsa:
        status_code, url = 200, "https://prueba.example/api"
        headers = {"resources": "0-49/500"}                    # el "sitio" dice tener 500 productos
        text = json.dumps([{}] * 50)

        def json(self):
            return json.loads(self.text)

    llamadas = []
    monkeypatch.setattr(scraper, "_get", lambda url, params=None: llamadas.append(params) or RespuestaFalsa())
    monkeypatch.setattr(scraper, "MAX_PETICIONES", 3)
    _, manifiesto = scraper._descargar_vtex_api("larebaja", "20261101T100000", tmp_path)
    assert len(llamadas) == 3
    assert manifiesto["estado"] == "parcial"
    assert "tope de 3 peticiones" in manifiesto["error"]
