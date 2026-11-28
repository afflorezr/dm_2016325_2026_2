"""Pruebas automáticas del Taller 2. Ejecutar desde taller_2/:  pytest tests/"""
import pandas as pd

import db
import scraper
import validacion
from helpers import base_temporal, cargar, contar, registro


# 1. Conversión de precios en texto a número
def test_limpia_precio_en_texto():
    assert scraper.limpiar_precio("$ 12.900") == 12900
    assert scraper.limpiar_precio("1.234.567") == 1234567
    assert scraper.limpiar_precio(15990) == 15990
    assert scraper.limpiar_precio("0") is None          # un precio 0 no es un precio
    assert scraper.limpiar_precio("sin precio") is None
    assert scraper.limpiar_precio(None) is None


# 2. Normalización de unidades (1 L = 1000 mL; 1 kg = 1000 g; 1 g = 1000 mg)
def test_normaliza_unidades():
    assert scraper.normalizar_contenido(1, "L") == (1000.0, "mL")
    assert scraper.normalizar_contenido(0.5, "kg") == (500.0, "g")
    assert scraper.normalizar_contenido(2000, "mg") == (2.0, "g")
    assert scraper.normalizar_contenido(250, "GRS") == (250.0, "g")
    assert scraper.extraer_contenido_texto("Limpiador | 1 L") == (1000.0, "mL")


# 3. Ahorro con empates
def test_ahorro_con_empates():
    a = db.ahorro_precios({"A": 100.0, "B": 100.0, "C": 150.0})
    assert a["comercios_min"] == ["A", "B"]             # los empates se incluyen
    assert a["ahorro_cop"] == 50.0
    assert a["ahorro_pct"] == 33.33
    todos_iguales = db.ahorro_precios({"A": 90.0, "B": 90.0})
    assert todos_iguales["ahorro_cop"] == 0 and todos_iguales["comercios_min"] == ["A", "B"]


# 4. Insertar dos veces la misma ejecución no duplica observaciones
def test_insertar_dos_veces_no_duplica():
    ruta = base_temporal()
    regs = [registro("1", 1000), registro("2", 2000)]
    assert cargar(ruta, "EJEC_20261105_100000", regs) == 2
    assert cargar(ruta, "EJEC_20261105_100000", regs) == 0      # segunda vez: no entra nada
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones") == 2
    assert contar(ruta, "SELECT COUNT(*) FROM ejecuciones") == 1


# 5. Detección de cambios de precio (mismo anuncio, mismo comercio) + nuevos y no observados
def test_detecta_cambios_de_precio():
    ruta = base_temporal()
    cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000), registro("2", 2000), registro("3", 3000)],
           fecha_inicio="2026-11-05T10:00:00-05:00")
    cargar(ruta, "EJEC_20261107_100000",
           [registro("1", 900, fecha="2026-11-07T10:00:00-05:00"),       # bajó 10 %
            registro("2", 2000, fecha="2026-11-07T10:00:00-05:00"),      # igual
            registro("4", 4000, fecha="2026-11-07T10:00:00-05:00")],     # nuevo; el "3" ya no se observó
           fecha_inicio="2026-11-07T10:00:00-05:00")
    with db.sesion(ruta) as con:
        r = db.cambios_entre_ejecuciones(con, "EJEC_20261105_100000", "EJEC_20261107_100000", umbral_pct=5)
    assert list(r["cambios"].producto) == ["Producto 1"]
    assert r["cambios"].variacion_pct.iloc[0] == -10.0 and r["cambios"].variacion_grande.iloc[0] == 1
    assert list(r["nuevos"].producto) == ["Producto 4"]
    assert list(r["no_observados"].producto) == ["Producto 3"]


# 6. La canasta no se calcula cuando falta un producto
def test_canasta_incompleta_no_se_calcula():
    precios = pd.DataFrame([
        {"id_producto_comun": "P01", "comercio": "A", "precio": 100.0},
        {"id_producto_comun": "P02", "comercio": "A", "precio": 200.0},
        {"id_producto_comun": "P01", "comercio": "B", "precio": 90.0},      # B no tiene P02
    ])
    r = db.calcular_canasta(precios, {"P01": 1, "P02": 1})
    tot = r["totales"].set_index("comercio")
    assert bool(tot.loc["A", "completa"]) and tot.loc["A", "total"] == 300.0
    assert not bool(tot.loc["B", "completa"]) and pd.isna(tot.loc["B", "total"])
    assert tot.loc["B", "faltan"] == ["P02"]
    assert r["total_optimo"] == 290.0                    # P01 en B (90) + P02 en A (200)
    assert r["ahorro_cop"] == 10.0 and r["mejor_comercio_unico"] == "A"
    # si un producto no tiene precio en ningún comercio, no hay costo mínimo
    r2 = db.calcular_canasta(precios, {"P01": 1, "P99": 1})
    assert r2["sin_precio"] == ["P99"] and r2["total_optimo"] is None


# 7. Validación antes de insertar
def test_validacion_rechaza_observaciones_invalidas():
    regs = [registro("ok", 1000), registro("cero", 0), registro("sinurl", 500, url=None),
            registro("sinfecha", 500, fecha="ayer"), registro("ok", 1000)]       # el último duplica a "ok"
    validas, rechazadas = validacion.validar_registros(regs)
    assert [r["sku_comercio"] for r in validas] == ["ok"]
    motivos = {r["sku_comercio"] + str(i): m[:2] for i, (r, m) in enumerate(rechazadas)}
    assert sorted(m[:2] for _, m in rechazadas) == ["R1", "R2", "R3", "R4"]
    assert validacion.faltantes_comparables(validas, {"111": "P01", "222": "P02"}) == ["P01", "P02"]


# 8. Las observaciones rechazadas no se insertan y quedan registradas con su motivo
def test_rechazadas_quedan_registradas():
    ruta = base_temporal()
    n = cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000), registro("2", -5)])
    assert n == 1
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones_rechazadas WHERE motivo LIKE 'R1%'") == 1


# 9. Seguridad: el texto de búsqueda se valida y las consultas van parametrizadas
def test_busqueda_valida_y_parametrizada():
    import pytest
    with pytest.raises(ValueError):
        db.validar_texto("x'; DROP TABLE observaciones;--")
    with pytest.raises(ValueError):
        db.validar_texto("a" * 500)
    ruta = base_temporal()
    cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000, titulo_original="Crema 100% natural")])
    with db.sesion(ruta) as con:
        assert len(db.productos_filtrados(con, texto="100%")) == 1       # el % se trata como texto, no como comodín
        assert len(db.productos_filtrados(con, texto="zzz")) == 0


# 10. Un anuncio que ya no aparece en la última ejecución no cuenta como oferta vigente (salvo que se pida)
def test_anuncios_no_observados_no_cuentan_por_defecto():
    ruta = base_temporal()
    cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000), registro("2", 2000)], fecha_inicio="2026-11-05T10:00:00-05:00")
    cargar(ruta, "EJEC_20261107_100000", [registro("1", 1100, fecha="2026-11-07T10:00:00-05:00")],
           fecha_inicio="2026-11-07T10:00:00-05:00")
    with db.sesion(ruta) as con:
        vigentes = db.productos_filtrados(con)
        con_viejos = db.productos_filtrados(con, incluir_no_observados=True)
        ind = db.indicadores(con)
    assert list(vigentes.producto) == ["Producto 1"] and vigentes.precio.iloc[0] == 1100
    assert sorted(con_viejos.producto) == ["Producto 1", "Producto 2"]
    assert ind["total_productos"] == 1


# 11. Un SKU no se puede insertar dos veces en la misma ejecución, aunque cambie la hora de consulta (p. ej. al reintentar)
def test_mismo_sku_en_la_misma_ejecucion_no_se_repite():
    ruta = base_temporal()
    assert cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000, fecha="2026-11-05T10:00:00-05:00")]) == 1
    assert cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000, fecha="2026-11-05T10:20:00-05:00")]) == 0
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones WHERE sku_comercio = '1'") == 1


# 12. Las observaciones repetidas ya descartadas no se cuentan dos veces al comparar ejecuciones
def test_repetidas_no_inflan_los_cambios_de_precio():
    import sqlite3
    import migrar_taller2
    ruta = base_temporal()
    cargar(ruta, "EJEC_20261105_100000", [registro("1", 1000)], fecha_inicio="2026-11-05T10:00:00-05:00")
    con = sqlite3.connect(ruta)                                   # repetida colada en la ejecución anterior
    cols = [r[1] for r in con.execute("PRAGMA table_info(observaciones)") if r[1] != "id_observacion"]
    sel = ", ".join("REPLACE(fecha_consulta, 'T10:00:00', 'T10:30:00')" if c == "fecha_consulta" else c for c in cols)
    con.execute(f"INSERT INTO observaciones ({', '.join(cols)}) SELECT {sel} FROM observaciones")
    con.commit()
    con.close()
    cargar(ruta, "EJEC_20261107_100000", [registro("1", 900, fecha="2026-11-07T10:00:00-05:00")],
           fecha_inicio="2026-11-07T10:00:00-05:00")
    migrar_taller2.migrar(ruta, raw_dir=ruta + "_raw", verbose=False)         # descarta la repetida
    with db.sesion(ruta) as con:
        r = db.cambios_entre_ejecuciones(con, "EJEC_20261105_100000", "EJEC_20261107_100000", umbral_pct=5)
    assert len(r["cambios"]) == 1
