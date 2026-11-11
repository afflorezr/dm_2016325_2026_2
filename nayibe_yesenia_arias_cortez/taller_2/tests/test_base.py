"""tests/test_base.py — inserción sin duplicados, cambios de precio, ahorro con empates y canasta (base temporal)."""
import sqlite3

import db
from conftest import DATOS_E1, E1, E2, EAN_A, EAN_B, cargar


def contar(ruta, tabla):
    with sqlite3.connect(ruta) as con:
        return con.execute(f"SELECT COUNT(*) FROM {tabla}").fetchone()[0]


# [CAMBIO]: §9: insertar dos veces la misma ejecución no duplica observaciones (ni rechazos, ni ejecuciones).
def test_insertar_dos_veces_no_duplica(base):
    antes = {t: contar(base, t) for t in ("observaciones", "ejecuciones", "anuncios")}
    resultado = cargar(base, DATOS_E1["locatel"], "locatel", E1)          # la misma ejecución otra vez
    assert resultado == {"anuncios_nuevos": 0, "observaciones_nuevas": 0, "rechazos_nuevos": 0}
    assert {t: contar(base, t) for t in antes} == antes
    assert antes["observaciones"] == 12                                  # 6 en E1 + 6 en E2


# [CAMBIO]: §9 y §8.2: detección de cambios de precio entre dos ejecuciones (mismo anuncio, mismo comercio).
def test_detecta_cambios_de_precio(base):
    cambios = db.comparar_ejecuciones(E1, E2, umbral_pct=10, db_path=base)
    tipo = {(f.id_comercio, f.sku_comercio): f.tipo_cambio for f in cambios.itertuples()}
    assert tipo[("larebaja", "r1")] == "subió"                # 10.000 → 11.000
    assert tipo[("cafam", "c1")] == "bajó"                    # 9.000 → 8.000
    assert tipo[("locatel", "l1")] == "sin cambio"
    assert tipo[("larebaja", "r2")] == "dejó de observarse"   # B no aparece en E2
    assert tipo[("cafam", "c3")] == "nuevo"                   # C solo en E2
    r1 = cambios[cambios["sku_comercio"] == "r1"].iloc[0]
    assert (r1["diferencia_cop"], r1["variacion_pct"], r1["variacion_grande"]) == (1000, 10.0, 1)
    # con un umbral más alto ya no es una variación grande
    alto = db.comparar_ejecuciones(E1, E2, umbral_pct=15, db_path=base)
    assert alto["variacion_grande"].sum() == 0
    # la vista v_cambios_precio (ejecuciones consecutivas) da los mismos conteos
    resumen = db.cambios_ultima_ejecucion(db_path=base).set_index("id_comercio")
    assert (resumen.loc["larebaja", "n_subieron"], resumen.loc["cafam", "n_bajaron"]) == (1, 1)


# [CAMBIO]: §9: cálculo del ahorro con empates: Locatel y Cafam empatan en el precio mínimo de A en E1.
def test_ahorro_con_empates(base):
    ahorro = db.ahorro_por_comparable(E1, db_path=base).set_index("id_producto_comun")
    assert ahorro.loc[EAN_A, "ahorro_cop"] == 1000                                   # 10.000 − 9.000
    assert set(ahorro.loc[EAN_A, "donde_mas_barato"].split(", ")) == {"Locatel", "Droguerías Cafam"}
    # en el gráfico libre el empate cuenta para ambos comercios
    conteo = dict(db.veces_mas_barato(E1, db_path=base)[["id_comercio", "n_productos_mas_barato"]].values)
    assert conteo == {"larebaja": 1, "locatel": 1, "cafam": 1}
    # canasta A×2 + B×1: el precio mínimo empatado se suma UNA vez
    canasta = db.calcular_canasta(E1, {EAN_A: 2, EAN_B: 1}, db_path=base)
    assert canasta["resumen"]["costo_minimo_cop"] == 2 * 9000 + 20000                 # 38.000
    assert canasta["resumen"]["mejor_total_un_comercio_cop"] == 40000                 # La Rebaja y Cafam empatan
    assert set(canasta["resumen"]["mejor_comercio"].split(", ")) == {"La Rebaja", "Droguerías Cafam"}
    assert canasta["resumen"]["ahorro_cop"] == 2000
    detalle = canasta["detalle"].set_index("id_producto_comun")
    assert set(detalle.loc[EAN_A, "donde_comprar"].split(", ")) == {"Locatel", "Droguerías Cafam"}


# [CAMBIO]: §9 y §8.3: la canasta NO se calcula en un comercio al que le falta un producto (o lo tiene agotado).
def test_canasta_no_se_calcula_si_falta_un_producto(base):
    canasta = db.calcular_canasta(E2, {EAN_A: 1, EAN_B: 1}, db_path=base)
    por_comercio = canasta["por_comercio"].set_index("id_comercio")
    assert por_comercio.loc["larebaja", "total_cop"] != por_comercio.loc["larebaja", "total_cop"]  # NULL → NaN
    assert "ACONDICIONADOR" in por_comercio.loc["larebaja", "faltantes"]          # no se observó B
    assert "ACONDICIONADOR" in por_comercio.loc["cafam", "faltantes"]             # B agotado en Cafam
    assert por_comercio.loc["locatel", "total_cop"] == 9000 + 25000               # el único completo
    assert canasta["resumen"]["mejor_comercio"] == "Locatel"
