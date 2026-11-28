"""Pruebas automáticas del comparador. Ejecutar desde taller_2/:  pytest tests/"""

import gzip
import json

import pytest

import db
import scraper
import validacion
from conftest import cargar, observacion

T1 = "2026-10-10T02:53:00-05:00"
T2 = "2026-11-08T20:00:00-05:00"


# 1. Conversión de precios en texto a número -------------------------------------
@pytest.mark.parametrize("texto, esperado", [
    ("$ 12.900", 12900.0),
    ("$12.900,50", 12900.5),
    ("1.250.000", 1250000.0),
    ("COP 98920", 98920.0),
    (137950, 137950.0),
    ("", None),
    ("Agotado", None),
    (0, None),
    (None, None),
])
def test_limpiar_precio(texto, esperado):
    assert scraper.limpiar_precio(texto) == esperado


# 2. Normalización de unidades -----------------------------------------------------
@pytest.mark.parametrize("valor, unidad, esperado", [
    (50, "ml", (50.0, "mL")),
    (1, "L", (1000.0, "mL")),
    (500, "mg", (0.5, "g")),
    (60, "Grs", (60.0, "g")),
    (2, "Und", (2.0, "unidad")),
    (40, "oz", (None, None)),
    (0, "g", (None, None)),
])
def test_normalizar_unidad(valor, unidad, esperado):
    assert scraper.normalizar_unidad(valor, unidad) == esperado


def test_extraer_contenido_prioriza_nombre_y_reconoce_grs():
    assert scraper.extraer_contenido_y_unidad("Filtrosol Gel Spf50+ 60 Grs", "", "") == (60.0, "g")
    # El nombre dice 40 g y la descripción 40 ml: manda el nombre
    assert scraper.extraer_contenido_y_unidad("Protector Fresh X 40G", "", "Protector x 40 ml") == (40.0, "g")
    # "FPS 50+" no convierte un protector en combo
    assert scraper.clasificar_pertenencia_categoria("Avene Protector Solar Crema Spf 50+ 50 Ml") == (1, None)


# 3. Cálculo del ahorro con empates ------------------------------------------------
def test_ahorro_con_empates(con):
    id_c, _ = cargar(con, [
        observacion("A", "a1", 100000, T1, "P1"),
        observacion("B", "b1", 100000, T1, "P1"),   # empate en el mínimo
        observacion("C", "c1", 130000, T1, "P1"),
    ])
    ah = db.ahorro_por_producto(con, id_c)
    fila = ah.iloc[0]
    assert fila["ahorro_cop"] == 30000
    assert fila["mas_barato_en"] == "A / B"
    assert fila["ahorro_pct"] == pytest.approx(23.1, abs=0.05)

    canasta = db.calcular_canasta(con, id_c, [("P1", 2)])
    assert canasta["detalle_optimo"].iloc[0]["comprar_en"] == "A / B"
    assert canasta["total_optimo"] == 200000
    assert canasta["ahorro_vs_un_comercio"] == 0  # el comercio más barato ya iguala el óptimo


def test_ahorro_sin_diferencia_es_cero(con):
    id_c, _ = cargar(con, [observacion("A", "a1", 50000, T1, "P1"), observacion("B", "b1", 50000, T1, "P1")])
    assert db.ahorro_por_producto(con, id_c).iloc[0]["ahorro_cop"] == 0


# 4. Insertar dos veces la misma ejecución no duplica ------------------------------
def test_insertar_misma_ejecucion_no_duplica(con):
    obs = [observacion("A", "a1", 100000, T1, "P1"), observacion("A", "a2", 50000, T1)]
    _, r1 = cargar(con, obs)
    _, r2 = cargar(con, obs)
    total = con.execute("SELECT COUNT(*) FROM observaciones").fetchone()[0]
    assert total == 2
    assert r1[0]["insertados"] == 2
    assert r2[0]["insertados"] == 0
    assert "ya estaban en la base" in r2[0]["motivo"]


def test_restriccion_unicidad_impide_duplicado_directo(con):
    cargar(con, [observacion("A", "a1", 100000, T1)])
    fila = con.execute("SELECT id_corrida, id_ejecucion FROM observaciones").fetchone()
    with pytest.raises(Exception):
        con.execute("""INSERT INTO observaciones (id_corrida, id_ejecucion, comercio, id_producto_comercio,
                       nombre_original, fecha_hora_consulta) VALUES (?, ?, 'A', 'a1', 'x', ?)""", (fila[0], fila[1], T1))


# 5. Detección de cambios de precio ------------------------------------------------
def test_detecta_cambios_de_precio(con):
    id_a, _ = cargar(con, [observacion("A", "a1", 100000, T1, "P1"), observacion("A", "a2", 50000, T1),
                           observacion("A", "a3", 20000, T1)])
    id_b, r = cargar(con, [observacion("A", "a1", 90000, T2, "P1"), observacion("A", "a2", 50000, T2),
                           observacion("A", "a4", 10000, T2)])
    comp = db.comparar_corridas(con, id_a, id_b, umbral_pct=5)
    cambios = comp["cambios"]
    assert len(cambios) == 1
    assert cambios.iloc[0]["cambio_cop"] == -10000
    assert cambios.iloc[0]["cambio_pct"] == -10.0
    assert cambios.iloc[0]["direccion"] == "bajó"
    assert cambios.iloc[0]["variacion_grande"] == 1
    assert comp["nuevos"]["nombre"].tolist() == ["Producto a4"]
    assert comp["no_observados"]["nombre"].tolist() == ["Producto a3"]
    # El resumen de la actualización cuenta lo mismo
    assert (r[0]["cambios_precio"], r[0]["productos_nuevos"], r[0]["no_observados"]) == (1, 1, 1)
    # Y la vista v_cambios_precio también
    assert con.execute("SELECT COUNT(*) FROM v_cambios_precio WHERE direccion <> 'sin cambio'").fetchone()[0] == 1


# 6. La canasta no se calcula cuando falta un producto -----------------------------
def test_canasta_no_se_calcula_si_falta_un_producto(con):
    id_c, _ = cargar(con, [
        observacion("A", "a1", 100000, T1, "P1"), observacion("A", "a2", 80000, T1, "P2"),
        observacion("B", "b1", 90000, T1, "P1"),                       # a B le falta P2
        observacion("C", "c1", 95000, T1, "P1"),
        observacion("C", "c2", 70000, T1, "P2", disponibilidad="agotado"),  # agotado cuenta como faltante
    ])
    r = db.calcular_canasta(con, id_c, [("P1", 1), ("P2", 1)])
    pc = r["por_comercio"].set_index("comercio")
    assert pc.loc["A", "total_cop"] == 180000
    assert pc.loc["B", "total_cop"] != pc.loc["B", "total_cop"]  # NULL -> NaN: no hay total incompleto
    assert "Protector Dos" in pc.loc["B", "faltantes"]
    assert "Protector Dos" in pc.loc["C", "faltantes"]
    assert r["total_optimo"] == 90000 + 80000
    assert r["ahorro_vs_un_comercio"] == 10000

    # Si se aceptan agotados, C sí completa la canasta
    r2 = db.calcular_canasta(con, id_c, [("P1", 1), ("P2", 1)], incluir_agotados=True)
    assert r2["por_comercio"].set_index("comercio").loc["C", "total_cop"] == 165000


def test_canasta_sin_producto_en_ningun_comercio(con):
    id_c, _ = cargar(con, [observacion("A", "a1", 100000, T1, "P1")])
    r = db.calcular_canasta(con, id_c, [("P1", 1), ("P2", 1)])
    assert r["total_optimo"] is None
    assert r["comercio_mas_barato"] is None


# Validación, seguridad y modo sin conexión ----------------------------------------
def test_validacion_rechaza_y_registra_motivo():
    obs = [observacion("A", "a1", 100000, T1), observacion("A", "a1", 100000, T1),
           observacion("A", "a2", 1, T1, url=""), observacion("A", "a3", 1, T1, precio_actual=None)]
    r = validacion.validar_observaciones(obs, ["P1"])
    assert len(r.validas) == 1
    motivos = " ".join(r.rechazadas["motivo"])
    assert "R3" in motivos and "R2/R4" in motivos and "R1" in motivos
    assert r.comparables_faltantes == ["P1"] and not r.cumple_comparables


def test_busqueda_valida_texto_y_usa_parametros(con):
    cargar(con, [observacion("A", "a1", 100000, T1, nombre_original="Protector L'Oréal 50% off")])
    with pytest.raises(ValueError):
        db.validar_texto_busqueda("x'; DROP TABLE observaciones; --")
    with pytest.raises(ValueError):
        db.validar_texto_busqueda("a" * 61)
    # El apóstrofo es válido y viaja como parámetro: no rompe la consulta
    assert len(db.observaciones_filtradas(con, db.Filtros(texto="l'oréal"))) == 1
    assert db.observaciones_filtradas(con, db.Filtros(texto="inexistente")).empty
    assert con.execute("SELECT COUNT(*) FROM observaciones").fetchone()[0] == 1


def test_modo_sin_conexion_reprocesa_copia_cruda(tmp_path):
    pagina = [{"productId": "10", "productName": "Protector Solar Prueba Gel Spf 50+ X 60Grs", "brand": "MARCA",
               "link": "https://tienda.example/prueba/p", "description": "", "categories": ["/Solares/"],
               "items": [{"itemId": "10", "name": "Prueba", "ean": "7700000000001",
                          "sellers": [{"commertialOffer": {"Price": 45900, "ListPrice": 51000, "IsAvailable": False}}]}]}]
    carpeta = tmp_path / "raw" / "locatel" / "2026-11-08"
    carpeta.mkdir(parents=True)
    with gzip.open(carpeta / "locatel_prueba.json.gz", "wt", encoding="utf-8") as fh:
        json.dump({"timestamp": T2, "total_esperado": {"total_esperado": 1}, "pages": [{"items": pagina}]}, fh)
    r = scraper.recolectar_comercio("Locatel", offline=True, raw_base=tmp_path / "raw")
    assert not r.fallo and r.total_reportado == 1
    p = r.productos[0]
    assert (p["precio_actual"], p["es_promocion"], p["estado_disponibilidad"]) == (45900.0, 1, "agotado")
    assert (p["contenido_valor"], p["contenido_unidad"], p["marca_estandar"]) == (60.0, "g", "Marca")


def test_falla_de_un_comercio_no_detiene_la_corrida(tmp_path, monkeypatch):
    import actualizacion

    def falso(comercio, offline=False, archivo_raw=None, raw_base=None):
        if comercio == "La Rebaja":
            return scraper.ResultadoRecoleccion(comercio, "en_linea", T2, [], None, True, "Error de red: ConnectTimeout")
        return scraper.ResultadoRecoleccion(comercio, "en_linea", T2, [observacion(comercio, "x1", 1000, T2)], 1, False)

    monkeypatch.setattr(scraper, "recolectar_comercio", falso)
    r = actualizacion.actualizar(db_path=tmp_path / "b.sqlite", comercios=["Bella Piel", "La Rebaja", "Locatel"])
    estados = {c["comercio"]: c["estado"] for c in r["comercios"]}
    assert estados["La Rebaja"] == "fallida"
    assert estados["Bella Piel"] == estados["Locatel"] == "parcial"   # faltan comparables
    assert r["estado"] == "parcial"
    with db.conectar(tmp_path / "b.sqlite") as c:
        assert c.execute("SELECT COUNT(*) FROM observaciones").fetchone()[0] == 2
        assert "ConnectTimeout" in c.execute("SELECT motivo FROM ejecuciones WHERE comercio = 'La Rebaja'").fetchone()[0]
