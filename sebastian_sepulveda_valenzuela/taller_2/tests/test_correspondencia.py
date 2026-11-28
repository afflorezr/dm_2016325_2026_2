"""
tests/test_correspondencia.py
=============================
Pruebas unitarias para la lógica de correspondencia automática y desambiguación.
"""

import sqlite3
import pytest
from scraper import init_database, construir_correspondencia


@pytest.fixture
def temp_db(tmp_path):
    db_file = str(tmp_path / "test_comparador.sqlite")
    init_database(db_file)
    conn = sqlite3.connect(db_file)
    cur = conn.cursor()

    # Insertar comercios oficiales
    cur.executemany("""
    INSERT OR IGNORE INTO comercios (comercio_id, nombre, plataforma, url_base)
    VALUES (?, ?, ?, ?)
    """, [
        (1, "Éxito", "vtex_faststore", "https://www.exito.com"),
        (2, "Olímpica", "vtex_io", "https://www.olimpica.com"),
        (3, "Jumbo", "vtex_io", "https://www.tiendasjumbo.co"),
    ])
    conn.commit()
    conn.close()
    return db_file


def test_contenido_distinto_es_rechazado(temp_db):
    """Verifica que un EAN con contenidos distintos entre comercios se rechace en correspondencia_rechazada."""
    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()

    ean = "7501058714978"
    # Éxito: 12 und
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (1, 'SKU_E1', ?, 'Harpic 12 und', 'Harpic Pastillas', 'Harpic', 'desinfectantes', 12.0, 'und', 12)
    """, (ean,))
    # Olímpica: 2 und
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (2, 'SKU_O1', ?, 'Harpic 2 und', 'Harpic Pastillas', 'Harpic', 'desinfectantes', 2.0, 'und', 2)
    """, (ean,))
    # Jumbo: 2 und
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (3, 'SKU_J1', ?, 'Harpic 2 und', 'Harpic Pastillas', 'Harpic', 'desinfectantes', 2.0, 'und', 2)
    """, (ean,))
    conn.commit()
    conn.close()

    n = construir_correspondencia(temp_db)
    assert n == 0

    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()
    cur.execute("SELECT motivo FROM correspondencia_rechazada WHERE ean = ?", (ean,))
    row = cur.fetchone()
    assert row is not None
    assert "Contenido o unidad distinta" in row[0]
    conn.close()


def test_desambiguacion_varios_sku_por_contenido(temp_db):
    """Verifica que cuando un comercio tiene 2 SKUs (uno con contenido válido y otro nulo/distinto), se seleccione el válido."""
    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()

    ean = "7702098026063"
    # Éxito: 3 und
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (1, 'SKU_E1', ?, 'Esponja Scotch Brite x3', 'Esponja Cocina', 'Scotch Brite', 'esponjas', 3.0, 'und', 3)
    """, (ean,))
    # Olímpica: 3 und
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (2, 'SKU_O1', ?, 'Esponja Scotch Brite x3', 'Esponja Cocina', 'Scotch Brite', 'esponjas', 3.0, 'und', 3)
    """, (ean,))
    # Jumbo: 2 SKUs (uno con None y uno con 3 und)
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (3, 'SKU_J_INVALID', ?, 'Esponja Scotch Brite gen', 'Esponja Cocina', 'Scotch Brite', 'esponjas', NULL, NULL, 1)
    """, (ean,))
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (3, 'SKU_J_VALID', ?, 'Esponja Scotch Brite 3 und', 'Esponja Cocina', 'Scotch Brite', 'esponjas', 3.0, 'und', 3)
    """, (ean,))
    conn.commit()
    conn.close()

    n = construir_correspondencia(temp_db)
    assert n == 1

    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()
    # Verificar que solo el SKU válido de Jumbo quedó marcado como comparable
    cur.execute("SELECT sku, comparable FROM anuncios WHERE ean = ? AND comercio_id = 3 ORDER BY sku", (ean,))
    rows = cur.fetchall()
    assert rows == [("SKU_J_INVALID", 0), ("SKU_J_VALID", 1)]
    conn.close()


def test_varios_sku_no_desambiguables_es_excluido(temp_db):
    """Verifica que si un comercio tiene 2 SKUs con idénticas especificaciones en la misma ejecución, sea excluido."""
    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()

    ean = "7702377005758"
    exec_id = "EXEC_TEST_20261028_OLIMPICA"
    cur.execute("""
    INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, total_sitio, estado)
    VALUES (?, 2, '2026-10-28T20:00:00-05:00', 2, 2, 'completa')
    """, (exec_id,))

    # Éxito: 700 ml
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (1, 'SKU_E1', ?, 'Cera Bufalo 700ml', 'Cera Bufalo', 'Bufalo', 'limpiadores', 700.0, 'ml', 1)
    """, (ean,))
    # Jumbo: 700 ml
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (3, 'SKU_J1', ?, 'Cera Bufalo 700ml', 'Cera Bufalo', 'Bufalo', 'limpiadores', 700.0, 'ml', 1)
    """, (ean,))

    # Olímpica: 2 SKUs idénticos en la misma ejecución
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (2, 'SKU_O1', ?, 'Cera Bufalo 700ml A', 'Cera Bufalo', 'Bufalo', 'limpiadores', 700.0, 'ml', 1)
    """, (ean,))
    aid1 = cur.lastrowid
    cur.execute("""
    INSERT INTO anuncios (comercio_id, sku, ean, nombre_original, nombre_estandar, marca_estandar, subcategoria_estandar, contenido_total, unidad_base, unidades_por_paquete)
    VALUES (2, 'SKU_O2', ?, 'Cera Bufalo 700ml B', 'Cera Bufalo', 'Bufalo', 'limpiadores', 700.0, 'ml', 1)
    """, (ean,))
    aid2 = cur.lastrowid

    cur.execute("INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta) VALUES (?, ?, 100.0, '2026-10-28T20:00:00-05:00')", (aid1, exec_id))
    cur.execute("INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta) VALUES (?, ?, 100.0, '2026-10-28T20:00:01-05:00')", (aid2, exec_id))

    conn.commit()
    conn.close()

    n = construir_correspondencia(temp_db)
    assert n == 0

    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()
    cur.execute("SELECT motivo FROM correspondencia_rechazada WHERE ean = ?", (ean,))
    row = cur.fetchone()
    assert row is not None
    assert "no desambiguable" in row[0]
    conn.close()
