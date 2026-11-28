# Insertar dos veces la misma ejecución no duplica observaciones.
# Usamos una copia mínima de raw/ (4 productos reales de La Rebaja del 8 de noviembre,
# en tests/datos/) y una base temporal, así que no se consulta el sitio.
from pathlib import Path

import scraper

RAW_PRUEBA = Path(__file__).parent / "datos" / "raw"
ID = "E20261108T110310"


def contar_observaciones(con):
    return con.execute("SELECT COUNT(*) FROM observaciones").fetchone()[0]


def test_insertar_dos_veces_no_duplica(tmp_path):
    con = scraper.conectar(tmp_path / "prueba.sqlite")
    with con:
        scraper._registrar_comercios(con, scraper.COMERCIOS)

    primera = scraper.actualizar_comercio(con, "larebaja", ID, sin_conexion=True,
                                          raw_dir=RAW_PRUEBA, comparables={})
    despues_de_la_primera = contar_observaciones(con)
    segunda = scraper.actualizar_comercio(con, "larebaja", ID, sin_conexion=True,
                                          raw_dir=RAW_PRUEBA, comparables={})
    despues_de_la_segunda = contar_observaciones(con)
    ejecuciones = con.execute("SELECT COUNT(*) FROM ejecuciones").fetchone()[0]
    con.close()

    # 3 antiinfecciosos; el aceite corporal queda fuera de la categoría
    assert primera["estado"] == "completa"
    assert primera["observaciones_nuevas"] == 3
    assert despues_de_la_primera == 3
    # la segunda vez no entra nada nuevo, y no es porque haya fallado: las repetidas se saltan
    assert segunda["estado"] == "completa"
    assert segunda["observaciones_nuevas"] == 0
    assert despues_de_la_segunda == 3
    assert ejecuciones == 1
