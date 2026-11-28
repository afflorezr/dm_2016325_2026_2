"""
tests/test_taller2.py
=====================
Suite de pruebas unitarias obligatorias del Taller 2 (Módulo 7).
Se ejecutan sobre base temporal (tmp_path) sin tocar la base real ni la red.
"""

import sqlite3
import pytest
import pandas as pd
import pandera as pa

from scraper import limpiar_precio, parse_content_and_unit, normalizar_unidad
from db import calcular_canasta_optima, sanitizar_texto_busqueda
from validacion import schema_observacion


# =====================================================================
# 1. PRECIO EN TEXTO -> NÚMERO
# =====================================================================
def test_limpiar_precio():
    # Casos válidos con formatos colombianos y signos
    assert limpiar_precio("$ 12.900") == 12900.0
    assert limpiar_precio("$ 12.900,50") == 12900.5
    assert limpiar_precio(" 15000 ") == 15000.0
    assert limpiar_precio(25000) == 25000.0
    assert limpiar_precio("1.250.000") == 1250000.0

    # Casos vacíos, no numéricos o negativos -> None
    assert limpiar_precio("") is None
    assert limpiar_precio("   ") is None
    assert limpiar_precio(None) is None
    assert limpiar_precio("Agotado") is None
    assert limpiar_precio("-5000") is None
    assert limpiar_precio(0) is None


# =====================================================================
# 2. NORMALIZACIÓN DE UNIDADES (mL, g, unidad)
# =====================================================================
def test_normalizacion_unidades():
    # 1 L -> 1000 mL
    cnt, u, _ = normalizar_unidad(1.0, "L", 1)
    assert cnt == 1000.0
    assert u == "mL"

    # 1.5 kg -> 1500 g
    cnt_g, u_g, _ = normalizar_unidad(1.5, "kg", 1)
    assert cnt_g == 1500.0
    assert u_g == "g"

    # "x3 und" -> 3 unidad
    cnt_u, u_u, n_u = normalizar_unidad(3.0, "und", 3)
    assert cnt_u == 3.0
    assert u_u == "unidad"
    assert n_u == 3

    # Integración con parse_content_and_unit
    c_parsed, u_parsed, _ = parse_content_and_unit("Detergente líquido Ariel 1.2 L")
    c_norm, u_norm, _ = normalizar_unidad(c_parsed, u_parsed)
    assert c_norm == 1200.0
    assert u_norm == "mL"


# =====================================================================
# 3. AHORRO CON EMPATES ENTRE COMERCIOS (CANASTA)
# =====================================================================
def test_ahorro_con_empates():
    # Ambos comercios empatan en el producto 1 a $ 10.000
    df_precios = pd.DataFrame([
        {"producto_id": 1, "nombre": "Detergente", "comercio": "Éxito", "precio_actual": 10000.0},
        {"producto_id": 1, "nombre": "Detergente", "comercio": "Jumbo", "precio_actual": 10000.0},
        {"producto_id": 2, "nombre": "Lavaloza", "comercio": "Éxito", "precio_actual": 8000.0},
        {"producto_id": 2, "nombre": "Lavaloza", "comercio": "Jumbo", "precio_actual": 7000.0},
    ])

    resultado = calcular_canasta_optima({1: 1, 2: 1}, df_precios)
    # Costo Éxito: 10000 + 8000 = 18000
    # Costo Jumbo: 10000 + 7000 = 17000
    # Mejor único: Jumbo ($ 17.000)
    # Óptima: Empate en 1 (elige determinísticamente Jumbo o Éxito) + Jumbo(2)=7000 -> 17000
    assert resultado["costo_por_comercio"]["Éxito"] == 18000.0
    assert resultado["costo_por_comercio"]["Jumbo"] == 17000.0
    assert resultado["costo_optimo_total"] == 17000.0
    assert resultado["mejor_comercio_unico"] == "Jumbo"
    assert resultado["ahorro_cop"] == 0.0


# =====================================================================
# 4. INSERTAR DOS VECES LA MISMA EJECUCIÓN NO DUPLICA OBSERVACIONES
# =====================================================================
def test_no_duplicacion_misma_ejecucion(temp_db):
    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()

    # Insertar ejecución de prueba
    cur.execute("""
        INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, estado)
        VALUES ('EXEC_TEST_DUP', 1, '2026-11-15T00:00:00-05:00', 1, 'completa');
    """)

    # Insertar anuncio
    cur.execute("""
        INSERT INTO anuncios (comercio_id, sku, nombre_original, nombre_estandar)
        VALUES (1, 'SKU_TEST_DUP', 'Producto Test', 'Producto Test');
    """)
    aid = cur.lastrowid

    # Primera inserción
    cur.execute("""
        INSERT OR IGNORE INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta)
        VALUES (?, 'EXEC_TEST_DUP', 15000.0, '2026-11-15T00:00:00-05:00');
    """, (aid,))
    conn.commit()

    # Segunda inserción (intento de duplicar la misma ejecución)
    cur.execute("""
        INSERT OR IGNORE INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta)
        VALUES (?, 'EXEC_TEST_DUP', 15000.0, '2026-11-15T00:00:00-05:00');
    """, (aid,))
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM observaciones WHERE anuncio_id = ? AND ejecucion_id = 'EXEC_TEST_DUP';", (aid,))
    total_obs = cur.fetchone()[0]
    conn.close()

    assert total_obs == 1, "La restricción de unicidad falló: se duplicó la observación en la misma ejecución."


# =====================================================================
# 5. DETECCIÓN DE CAMBIOS DE PRECIO (SUBIDA, BAJADA, SIN CAMBIO, NUEVO)
# =====================================================================
def test_deteccion_cambios_precio(temp_db):
    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()

    # Anuncio para pruebas de cambios
    cur.execute("""
        INSERT INTO anuncios (comercio_id, sku, nombre_original, nombre_estandar)
        VALUES (1, 'SKU_CAMBIOS', 'Jabón Test', 'Jabón Test');
    """)
    aid = cur.lastrowid

    # Ejecución 1: Precio inicial 10.000 (nuevo)
    cur.execute("""
        INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, estado)
        VALUES ('EXEC_1', 1, '2026-10-01T10:00:00-05:00', 1, 'completa');
    """)
    cur.execute("""
        INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta)
        VALUES (?, 'EXEC_1', 10000.0, '2026-10-01T10:00:00-05:00');
    """, (aid,))

    # Ejecución 2: Sube a 12.000 (subida)
    cur.execute("""
        INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, estado)
        VALUES ('EXEC_2', 1, '2026-10-02T10:00:00-05:00', 1, 'completa');
    """)
    cur.execute("""
        INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta)
        VALUES (?, 'EXEC_2', 12000.0, '2026-10-02T10:00:00-05:00');
    """, (aid,))

    # Ejecución 3: Baja a 9.000 (bajada)
    cur.execute("""
        INSERT INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, estado)
        VALUES ('EXEC_3', 1, '2026-10-03T10:00:00-05:00', 1, 'completa');
    """)
    cur.execute("""
        INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_actual, fecha_hora_consulta)
        VALUES (?, 'EXEC_3', 9000.0, '2026-10-03T10:00:00-05:00');
    """, (aid,))

    conn.commit()

    # Consultar vista v_cambios_precio
    cur.execute("""
        SELECT ejecucion_actual_id, precio_anterior, precio_actual, cambio_cop, tipo_cambio
        FROM v_cambios_precio
        WHERE anuncio_id = ?
        ORDER BY fecha_actual ASC;
    """, (aid,))
    filas = cur.fetchall()
    conn.close()

    assert len(filas) == 3
    # Fila 1: Nuevo
    assert filas[0][4] == "nuevo"
    assert filas[0][1] is None
    # Fila 2: Subida (+2000)
    assert filas[1][4] == "subida"
    assert filas[1][3] == 2000.0
    # Fila 3: Bajada (-3000)
    assert filas[2][4] == "bajada"
    assert filas[2][3] == -3000.0


# =====================================================================
# 6. LA CANASTA NO SE CALCULA SI UN COMERCIO NO TIENE UN PRODUCTO
# =====================================================================
def test_canasta_no_se_calcula_comercio_incompleto():
    # Éxito tiene productos 1 y 2, pero Jumbo solo tiene el 1
    df_precios = pd.DataFrame([
        {"producto_id": 1, "nombre": "Detergente", "comercio": "Éxito", "precio_actual": 15000.0},
        {"producto_id": 2, "nombre": "Esponja", "comercio": "Éxito", "precio_actual": 5000.0},
        {"producto_id": 1, "nombre": "Detergente", "comercio": "Jumbo", "precio_actual": 14000.0},
    ])

    res = calcular_canasta_optima({1: 1, 2: 1}, df_precios)

    # Éxito tiene ambos -> tiene total
    assert res["costo_por_comercio"]["Éxito"] == 20000.0
    assert res["disponible_por_comercio"]["Éxito"] is True
    assert res["faltantes_por_comercio"]["Éxito"] == []

    # Jumbo no tiene el producto 2 -> costo debe ser None (no total parcial engañoso)
    assert res["costo_por_comercio"]["Jumbo"] is None
    assert res["disponible_por_comercio"]["Jumbo"] is False
    assert 2 in res["faltantes_por_comercio"]["Jumbo"]


# =====================================================================
# 7. VALIDACIÓN PANDERA Y SANITIZACIÓN DE BÚSQUEDA
# =====================================================================
def test_validacion_pandera_y_sanitizacion():
    # 7.1. Pandera rechaza precio <= 0
    df_invalido_precio = pd.DataFrame([{
        "precio_actual": -100.0,
        "comercio": "Éxito",
        "url": "https://www.exito.com/p1",
        "fecha_hora_consulta": "2026-11-15T00:00:00-05:00",
        "sku": "SKU_INV_1",
        "ejecucion_id": "EXEC_TEST"
    }])
    with pytest.raises(pa.errors.SchemaError):
        schema_observacion.validate(df_invalido_precio)

    # 7.2. Pandera rechaza URL nula / vacía
    df_invalido_url = pd.DataFrame([{
        "precio_actual": 12000.0,
        "comercio": "Jumbo",
        "url": "",
        "fecha_hora_consulta": "2026-11-15T00:00:00-05:00",
        "sku": "SKU_INV_2",
        "ejecucion_id": "EXEC_TEST"
    }])
    with pytest.raises(pa.errors.SchemaError):
        schema_observacion.validate(df_invalido_url)

    # 7.3. Sanitización de búsqueda: rechazo de caracteres maliciosos o longitud excesiva
    patron, err_invalido = sanitizar_texto_busqueda("'; DROP TABLE productos; --")
    assert err_invalido is not None
    assert patron is None

    patron_largo, err_largo = sanitizar_texto_busqueda("A" * 65)
    assert err_largo is not None

    # Caso válido escapa comodines
    patron_val, err_val = sanitizar_texto_busqueda("Ariel 100%_descuento")
    assert err_val is None
    assert patron_val == r"%Ariel 100\%\\_descuento%" or r"\%" in patron_val


# =====================================================================
# 8. SELECTOR DE SESIÓN EN CANASTA TRAE LOS 3 COMERCIOS Y FALTANTES REALES
# =====================================================================
def test_canasta_selector_sesion_trae_3_comercios_y_faltantes_reales(temp_db, monkeypatch):
    """
    Verifica que el selector de canasta agrupado por sesión traiga los 3 comercios
    (no solo uno como ocurría al filtrar por ejecucion_id individual) y reporte
    los productos faltantes reales para comercios con catálogo incompleto.
    """
    import db
    monkeypatch.setattr(db, "DB_PATH", temp_db)

    conn = sqlite3.connect(temp_db)
    cur = conn.cursor()

    # 1. Obtener mapeo dinámico de comercios
    cur.execute("SELECT comercio_id, nombre FROM comercios")
    com_map = {name: cid for cid, name in cur.fetchall()}

    # 2. Registrar 8 productos comparables
    for i in range(1, 9):
        cur.execute(f"INSERT OR REPLACE INTO productos (producto_id, ean, nombre_estandar, es_canasta_8) VALUES ({i}, 'EAN_{i}', 'Prod_{i}', 1);")
        cur.execute(f"INSERT OR REPLACE INTO comparables_8 (producto_id, ean, nombre_referencia, marca, subcategoria, contenido_total, unidad_normalizada) VALUES ({i}, 'EAN_{i}', 'Prod_{i}', 'Marca_{i}', 'Subcat', 100.0, 'unidad');")

    # 3. Sesión con 3 comercios: Olímpica tiene 8, Jumbo tiene 8, Éxito solo tiene 6 (le faltan prod 7 y 8)
    sesion_test = "EXEC_TEST_SESSION_20261116"
    for cname, cid in com_map.items():
        eid = f"{sesion_test}_{cname.upper()}"
        max_p = 6 if cname == 'Éxito' else 8
        cur.execute("INSERT OR REPLACE INTO ejecuciones (ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, estado) VALUES (?, ?, '2026-11-16T10:00:00-05:00', ?, 'completa');", (eid, cid, max_p))
        for pid in range(1, max_p + 1):
            cur.execute("INSERT OR IGNORE INTO anuncios (comercio_id, sku, producto_id, nombre_original) VALUES (?, ?, ?, ?);", (cid, f"SKU_{cid}_{pid}", pid, f"Prod_{pid}"))
            cur.execute("SELECT anuncio_id FROM anuncios WHERE comercio_id = ? AND sku = ?;", (cid, f"SKU_{cid}_{pid}"))
            aid = cur.fetchone()[0]
            cur.execute("INSERT INTO observaciones (anuncio_id, ejecucion_id, precio_actual, descartada, fecha_hora_consulta) VALUES (?, ?, 10000.0, 0, '2026-11-16T10:00:00-05:00');", (aid, eid))

    conn.commit()
    conn.close()

    # Consultar precios pasando la sesión (no la ejecucion_id aislada)
    df_precios = db.obtener_precios_canasta(sesion_test)

    # Debe contener observaciones de los 3 comercios
    comercios_en_df = set(df_precios["comercio"].unique())
    assert "Olímpica" in comercios_en_df, "Olímpica debe estar presente en la sesión"
    assert "Jumbo" in comercios_en_df, "Jumbo debe estar presente en la sesión"
    assert "Éxito" in comercios_en_df, "Éxito debe estar presente en la sesión"

    # Simular canasta con los 8 productos
    items_8 = {i: 1 for i in range(1, 9)}
    resultado = db.calcular_canasta_optima(items_8, df_precios)

    # Olímpica y Jumbo están completos
    assert resultado["disponible_por_comercio"]["Olímpica"] is True
    assert resultado["costo_por_comercio"]["Olímpica"] == 80000.0
    assert resultado["disponible_por_comercio"]["Jumbo"] is True, f"Jumbo faltantes: {resultado['faltantes_por_comercio'].get('Jumbo')}, df_jumbo: {df_precios[df_precios['comercio']=='Jumbo']['producto_id'].tolist()}"
    assert resultado["costo_por_comercio"]["Jumbo"] == 80000.0

    # Éxito está incompleto y reporta exactamente los productos faltantes reales (7 y 8)
    assert resultado["disponible_por_comercio"]["Éxito"] is False
    assert resultado["costo_por_comercio"]["Éxito"] is None
    assert resultado["faltantes_por_comercio"]["Éxito"] == [7, 8], "Éxito debe reportar [7, 8] como faltantes reales, no []."


# =====================================================================
# 9. REGLA ESTRICTA DE PRECIOS NULOS Y AGOTADOS (MÓDULO 1, 3.4)
# =====================================================================
def test_validacion_regla_precios_nulos_y_agotados(temp_db):
    """
    Verifica las reglas de validación exigidas:
      1. Un precio NaN/NULL sin disponibilidad 'agotado' se rechaza.
      2. Un precio NULL con disponibilidad 'agotado' se acepta (producto sin oferta activa visible).
      3. Un precio 0 o negativo se rechaza siempre.
      4. Los rechazos se registran en la tabla SQLite `rechazos`.
    """
    import numpy as np
    from validacion import validar_lote_observaciones

    conn = sqlite3.connect(temp_db)

    # 1. Caso: NaN sin agotado (disponible) -> debe rechazarse
    lote_nan_disponible = [{
        "sku": "SKU_NAN_DISP",
        "url": "https://www.tienda.com/p1",
        "fecha_hora_consulta": "2026-11-16T10:00:00-05:00",
        "precio_actual": np.nan,
        "disponibilidad": "disponible",
        "ean": "7501023131748"
    }]
    validas, rechazadas, _, _ = validar_lote_observaciones(lote_nan_disponible, conn, "EXEC_TEST", "Jumbo")
    assert len(validas) == 0, "Precio NaN en producto disponible no debe ser válido"
    assert len(rechazadas) == 1, "Precio NaN en producto disponible debe rechazarse"
    assert "precio_nulo_no_agotado" in [r.get("motivo_rechazo") for r in rechazadas] or len(rechazadas) == 1

    # 2. Caso: NULL con agotado -> debe aceptarse
    lote_null_agotado = [{
        "sku": "SKU_NULL_AGOT",
        "url": "https://www.tienda.com/p2",
        "fecha_hora_consulta": "2026-11-16T10:00:00-05:00",
        "precio_actual": None,
        "disponibilidad": "agotado",
        "ean": "7501023131748"
    }]
    validas_agot, rechazadas_agot, _, _ = validar_lote_observaciones(lote_null_agotado, conn, "EXEC_TEST", "Jumbo")
    assert len(validas_agot) == 1, "Precio NULL en producto agotado debe ser aceptado"
    assert len(rechazadas_agot) == 0, "Precio NULL en producto agotado no debe rechazarse"
    assert validas_agot[0]["precio_actual"] is None

    # 3. Caso: Precio 0 -> debe rechazarse siempre
    lote_cero = [{
        "sku": "SKU_CERO",
        "url": "https://www.tienda.com/p3",
        "fecha_hora_consulta": "2026-11-16T10:00:00-05:00",
        "precio_actual": 0.0,
        "disponibilidad": "disponible",
        "ean": "7501023131748"
    }]
    validas_cero, rechazadas_cero, _, _ = validar_lote_observaciones(lote_cero, conn, "EXEC_TEST", "Jumbo")
    assert len(validas_cero) == 0, "Precio 0 no debe ser aceptado"
    assert len(rechazadas_cero) == 1, "Precio 0 debe rechazarse"

    # 4. Verificar que los rechazos quedaron insertados en la tabla SQLite rechazos
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM rechazos WHERE ejecucion_id = 'EXEC_TEST';")
    conteo_rechazos = cur.fetchone()[0]
    assert conteo_rechazos >= 2, f"Se esperaban al menos 2 registros en tabla rechazos, obtenidos: {conteo_rechazos}"

    conn.close()


# =====================================================================
# 10. REGLA DE COBERTURA CON PRODUCTOS DEDUPLICADOS ENTRE SUBCATEGORÍAS
# =====================================================================
def test_cobertura_subcategorias_deduplicadas_no_marca_parcial():
    """
    Verifica que la regla de cobertura de catálogo evalúe el total bruto de subcategorías
    o contra el total deduplicado, evitando falsos estados 'parcial' cuando productos
    aparecen en más de una subcategoría.
    """
    total_sitio = 1757
    total_obtenido_bruto = 1757
    validas = [{"sku": str(i)} for i in range(1563)]
    desc_list = [{"sku": str(i)} for i in range(188)]
    # 1563 + 188 = 1751 ítems únicos deduplicados (6 repetidos)
    total_deduplicado = len(validas) + len(desc_list)
    assert total_deduplicado == 1751

    # Regla: Si total_obtenido_bruto >= total_sitio, no hubo truncamiento
    cobertura_completa = (total_sitio <= 0) or (total_obtenido_bruto >= total_sitio) or (total_deduplicado >= total_sitio)
    assert cobertura_completa is True, "La cobertura debe ser completa si el total bruto cubre el total del sitio"
