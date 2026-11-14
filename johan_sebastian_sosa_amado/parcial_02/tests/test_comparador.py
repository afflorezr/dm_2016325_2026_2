"""Pruebas del comparador. Desde la carpeta parcial_02:
    pytest tests/
"""

import pandas as pd

import db
import scraper
import validacion
from conftest import R1, cargar

R1_ID, R2_ID = "2026-11-01T10-00-00", "2026-11-02T10-00-00"


def test_limpiar_precio():
    assert scraper.limpiar_precio("$ 12.900") == 12900
    assert scraper.limpiar_precio("12.900,50") == 12900.5
    assert scraper.limpiar_precio(12900) == 12900
    assert scraper.limpiar_precio(0) is None          # VTEX: 0 = sin existencias
    assert scraper.limpiar_precio("") is None
    assert scraper.limpiar_precio(None) is None


def test_normalizacion_de_unidades(base):
    assert scraper.extraer_contenido("Pañal TENA slip L (21  und)") == (21, "und")
    assert scraper.extraer_contenido("Crema Zinc TENA 100 ml") == (100, "mL")
    assert scraper.extraer_contenido("Pañal Tena Slip L X9 Unds") == (9, "und")
    con, _ = base
    unidades = {u for (u,) in con.execute("SELECT DISTINCT unidad_normalizada FROM anuncios;")}
    assert unidades <= {"unidad", "mL", "g", None}
    assert "und" not in unidades


def test_variantes_tena_pants():
    """La variante se lee del nombre para no emparejar clásico con comfort."""
    assert scraper.extraer_variante("ROPA INTERIOR ABSORBENTE TENA PANTS COMFORT M") == "comfort"
    assert scraper.extraer_variante("Pañal Tena Pants Classic Medium X8 Unds") == "clasico"
    assert scraper.extraer_variante("Pañal Tena Slip Comfort L X21 Unds PAÑAL TENA BASIC L") == "comfort"
    assert scraper.extraer_variante("Pañales TENA pants ultra talla L (20 und)") == "ultra"


def test_ahorro_con_empates(base):
    _, ruta = base
    ahorro = db.ahorro_comparables(R1_ID, ruta=ruta).set_index("producto_id")
    pants = ahorro.loc[ahorro["descripcion"].str.contains("pants")].iloc[0]
    assert pants["minimo"] == 28700 and pants["maximo"] == 29100
    assert pants["ahorro_cop"] == 400
    # Empate: los dos comercios con el precio mínimo aparecen.
    assert set(pants["mas_barato"].split(", ")) == {"Exito", "Olimpica"}


def test_insertar_dos_veces_no_duplica(base):
    con, _ = base
    antes = con.execute("SELECT COUNT(*) FROM observaciones;").fetchone()[0]
    cargar(con, R1_ID, "2026-11-01T10:00:00-05:00", R1)          # la misma otra vez
    despues = con.execute("SELECT COUNT(*) FROM observaciones;").fetchone()[0]
    assert despues == antes
    ejecuciones = con.execute("SELECT COUNT(*) FROM ejecuciones;").fetchone()[0]
    assert ejecuciones == 6                                       # 2 recolecciones x 3 comercios
    # Reprocesar la misma ejecución tampoco repite su rechazo.
    sin_filas = pd.DataFrame(columns=["ejecucion_id", "comercio", "sku", "url",
                                      "fecha_hora_consulta", "regla", "detalle"])
    for _ in range(2):
        with con:
            scraper.guardar_rechazos(con, sin_filas, "solo 5 productos comparables", "exito_x", "Exito")
    assert con.execute("SELECT COUNT(*) FROM rechazos WHERE ejecucion_id = 'exito_x';").fetchone()[0] == 1


def test_deteccion_de_cambios(base):
    _, ruta = base
    cambios = db.cambios_entre(R1_ID, R2_ID, umbral_pct=4, ruta=ruta)
    por_sku = {(r.comercio, r.nombre_original[:20], r.precio_a, r.precio_b): r.tipo
               for r in cambios.itertuples()}
    tipos = cambios.groupby("tipo").size().to_dict()
    assert tipos.get("subió") == 1           # pants en Éxito: de 28.700 a 30.000
    assert tipos.get("bajó") == 1            # slip en Éxito: de 60.400 a 55.000
    assert tipos.get("nuevo") == 1           # pants de 16 en La Rebaja
    assert tipos.get("dejó de observarse") == 1   # slip de La Rebaja
    sube = cambios[cambios["tipo"] == "subió"].iloc[0]
    assert sube["cambio_cop"] == 1300 and sube["cambio_pct"] == 4.5
    assert sube["grande"] == 1               # 4,5 % supera el umbral de 4 %
    assert len(por_sku) == len(cambios)
    # Las tarjetas salen de SQL y coinciden con la tabla.
    conteo = db.conteo_cambios(R1_ID, R2_ID, umbral_pct=4, ruta=ruta)
    assert conteo == {"subieron": 1, "bajaron": 1, "grandes": 2, "nuevos": 1, "dejaron": 1,
                      "anuncios": len(cambios)}
    # Filtros por comercio y por tipo, también en SQL.
    assert len(db.cambios_entre(R1_ID, R2_ID, comercios=["La Rebaja"], ruta=ruta)) == 3
    assert db.cambios_entre(R1_ID, R2_ID, tipos=["nuevo"], ruta=ruta)["tipo"].tolist() == ["nuevo"]
    # El indicador del resumen (vista v_cambios_precio) da lo mismo: subieron + bajaron.
    assert db.indicadores({"recoleccion_id": R2_ID}, ruta=ruta)["cambios_precio"] == 2


def test_sin_conexion_usa_la_ultima_copia_completa(tmp_path, monkeypatch):
    """Un intento en línea fallido deja carpetas en raw/ sin páginas, con la
    página del error o incompletas: el modo sin conexión debe saltarlas."""
    monkeypatch.setattr(scraper, "CARPETA_RAW", tmp_path / "raw")
    exito = tmp_path / "raw" / "exito"
    pagina = {"codigo_http": 206, "resources": "0-1/3", "respuesta": [{"productId": "1"}, {"productId": "2"}]}
    final = {"codigo_http": 200, "resources": "2-2/3", "respuesta": [{"productId": "3"}]}
    scraper.guardar_crudo(exito / "2026-11-01T10-00-00", "pagina_001.json.gz", pagina)   # completa
    scraper.guardar_crudo(exito / "2026-11-01T10-00-00", "pagina_002.json.gz", final)
    scraper.guardar_crudo(exito / "2026-11-02T10-00-00", "pagina_001.json.gz", pagina)   # falta una página
    scraper.guardar_crudo(exito / "2026-11-03T10-00-00", "pagina_001.json.gz",           # bloqueada
                          {"codigo_http": 403, "respuesta": "<html>Forbidden</html>"})
    (exito / "2026-11-04T10-00-00").mkdir()                                              # solo robots.txt
    (exito / "2026-11-04T10-00-00" / "robots.txt").write_text("", encoding="utf-8")

    assert scraper.ultima_copia("exito").name == "2026-11-01T10-00-00"
    assert scraper.ultima_copia("exito", fecha="2026-11-03") is None
    assert scraper.recoleccion_sin_conexion(["exito", "larebaja"]) == "2026-11-01T10-00-00"


def test_tienda_sin_conexion_queda_fallida_con_motivo(tmp_path, monkeypatch):
    """Lo que pasa en la nube cuando la tienda no responde: la ejecución queda
    fallida, con un motivo claro, y no se inserta ninguna observación."""
    def sin_red(*args, **kwargs):
        raise scraper.requests.ConnectionError("sin red")
    monkeypatch.setattr(scraper, "CARPETA_RAW", tmp_path / "raw")
    monkeypatch.setattr(scraper.requests, "get", sin_red)
    con = scraper.conectar_base(tmp_path / "prueba.sqlite")
    resumen = scraper.recolectar_comercio("exito", con, "2026-11-09T10-00-00", pausa=0)
    assert resumen["estado"] == "fallida"
    assert resumen["motivo"] == "el sitio no devolvió productos: no hubo conexión con el sitio"
    assert con.execute("SELECT COUNT(*) FROM observaciones;").fetchone()[0] == 0
    con.close()


def test_carpeta_raw_se_guarda_relativa(base):
    assert (db.ruta_relativa_raw(r"C:\Users\USER\taller_2\raw\exito\2026-11-07T21-24-49")
            == r"raw\exito\2026-11-07T21-24-49")
    assert (db.ruta_relativa_raw("/mount/src/taller_2/raw/olimpica/2026-11-07T21-25-07")
            == "raw/olimpica/2026-11-07T21-25-07")
    assert db.ruta_relativa_raw(r"raw\larebaja\2026-10-10T04-22-21") == r"raw\larebaja\2026-10-10T04-22-21"
    # Una fila con la ruta completa queda relativa al preparar la base.
    con, _ = base
    with con:
        con.execute("UPDATE ejecuciones SET carpeta_raw = ? WHERE ejecucion_id = 'exito_2026-11-01T10-00-00';",
                    (r"C:\Users\USER\taller_2\raw\exito\2026-11-01T10-00-00",))
    db.preparar_base(con)
    (ruta,) = con.execute("SELECT carpeta_raw FROM ejecuciones "
                          "WHERE ejecucion_id = 'exito_2026-11-01T10-00-00';").fetchone()
    assert ruta == r"raw\exito\2026-11-01T10-00-00"


def test_canasta_incompleta_no_se_calcula(base):
    _, ruta = base
    productos = db.consultar("SELECT producto_id, descripcion FROM productos;", ruta=ruta)
    slip = productos[productos["descripcion"].str.contains("slip")]["producto_id"].iloc[0]
    pants = productos[productos["descripcion"].str.contains("pants")]["producto_id"].iloc[0]
    por_comercio, por_producto = db.canasta(R2_ID, {pants: 2, slip: 1}, ruta=ruta)
    fila = por_comercio.set_index("comercio")
    # En la recolección 2 el slip está agotado en Olímpica y no se observó en La Rebaja.
    assert pd.isna(fila.loc["Olimpica", "total"]) and slip in fila.loc["Olimpica", "faltantes"]
    assert pd.isna(fila.loc["La Rebaja", "total"])
    assert fila.loc["Exito", "total"] == 2 * 30000 + 55000
    # Comprando cada producto donde es más barato: pants en Olímpica, slip en Éxito.
    resumen = db.resumen_canasta(por_comercio, por_producto)
    assert resumen["costo_minimo"] == 2 * 28700 + 55000
    assert resumen["ahorro_vs_mejor"] == (2 * 30000 + 55000) - (2 * 28700 + 55000)


def test_validacion_rechaza_precios_y_duplicados():
    tabla = pd.DataFrame({
        "ejecucion_id": ["e"] * 4, "comercio": ["Exito"] * 4, "sku": ["1", "2", "2", "3"],
        "url": ["u"] * 4, "fecha_hora_consulta": ["f"] * 4,
        "precio": [100.0, 50.0, 50.0, -5.0], "disponible": [1, 1, 1, 1], "ean": ["x"] * 4})
    validas, rechazos = validacion.validar_observaciones(tabla)
    assert validas["sku"].tolist() == ["1", "2"]
    assert len(rechazos) == 2
    assert rechazos["regla"].str.contains("duplicada").any()
    assert rechazos["regla"].str.contains("mayor que cero").any()


def test_validacion_exige_url_y_fecha_y_acepta_agotados_sin_precio():
    tabla = pd.DataFrame({
        "ejecucion_id": ["e"] * 4, "comercio": ["Exito"] * 4, "sku": ["1", "2", "3", "4"],
        "url": ["u", "", "u", "u"], "fecha_hora_consulta": ["f", "f", None, "f"],
        "precio": [None, 10.0, 10.0, None], "disponible": [0, 1, 1, 1], "ean": ["x"] * 4})
    validas, rechazos = validacion.validar_observaciones(tabla)
    assert validas["sku"].tolist() == ["1"]          # agotado: sin precio es válido
    motivos = dict(zip(rechazos["sku"], rechazos["regla"]))
    assert "URL vacía" in motivos["2"]
    assert "fecha_hora_consulta" in motivos["3"]
    assert "disponible" in motivos["4"]              # sin precio pero disponible
    assert rechazos["detalle"].notna().all()


def test_busqueda_rechaza_texto_peligroso():
    assert db.validar_busqueda("  pants   ultra ") == "pants ultra"
    for texto in ["'; DROP TABLE anuncios; --", "x" * 100]:
        try:
            db.validar_busqueda(texto)
            assert False, "debió rechazarse"
        except ValueError:
            pass
