# Consultas de db.py sobre la base temporal de base_prueba.py: ahorro con empates,
# cambios de precio, canasta y validación de la búsqueda.
import sqlite3
from contextlib import closing

import pandas as pd
import pytest

import db
from base_prueba import E1, E2


def test_ahorro_con_empate(base_prueba):
    ahorro = db.ahorro_por_producto(db.Filtros(id_ejecucion=E1)).set_index("id_producto")
    p01 = ahorro.loc["P01"]
    assert p01["minimo"] == 10000
    assert p01["maximo"] == 12000
    assert p01["ahorro"] == 2000
    # Cafam y La Rebaja empatan en el precio mínimo: aparecen los dos
    assert set(p01["mas_barato"].split(" / ")) == {"Cafam", "La Rebaja"}
    assert p01["mas_caro"] == "Locatel"
    # P03 solo tiene precio en un comercio: no hay con qué compararlo
    assert "P03" not in ahorro.index


def test_agotado_no_cuenta_como_mas_barato(base_prueba):
    # En los sitios, un producto agotado casi siempre conserva el precio publicado.
    # Ponemos agotado a La Rebaja en P01 (E2), que era el más barato, sin quitarle el precio.
    with closing(sqlite3.connect(base_prueba)) as con, con:
        con.execute("""UPDATE observaciones SET disponible = 0, disponibilidad = 'agotado'
                       WHERE id_ejecucion = ? AND sku_comercio = 'R01'""", (E2,))
    db.limpiar_cache()

    p01 = db.ahorro_por_producto(db.Filtros(id_ejecucion=E2)).set_index("id_producto").loc["P01"]
    assert p01["minimo"] == 11000
    assert p01["mas_barato"] == "Cafam"
    assert p01["ahorro"] == 1000
    # La canasta y el gráfico de precio por unidad usan el mismo criterio
    assert db.canasta(E2, {"P01": 1}).detalle.loc[0, "donde_comprar"] == "Cafam"
    unitario = db.precio_unitario_comparables(db.Filtros(id_ejecucion=E2))
    assert "La Rebaja" not in set(unitario.loc[unitario["id_producto"] == "P01", "comercio"])


def test_canasta_con_empate(base_prueba):
    resultado = db.canasta(E1, {"P01": 1})
    assert sorted(resultado.mejores_comercios) == ["Cafam", "La Rebaja"]
    assert resultado.costo_minimo == 10000
    assert resultado.ahorro == 0
    assert set(resultado.detalle.loc[0, "donde_comprar"].split(" / ")) == {"Cafam", "La Rebaja"}


def test_deteccion_de_cambios_de_precio(base_prueba):
    cambios = db.cambios_entre(E1, E2).set_index("sku_comercio")
    assert cambios.loc["C01", "tipo"] == "subió"
    assert cambios.loc["C01", "cambio_cop"] == 1000
    assert cambios.loc["C01", "cambio_pct"] == 10
    assert cambios.loc["R01", "tipo"] == "bajó"
    assert cambios.loc["R01", "cambio_cop"] == -1000
    assert cambios.loc["L01", "tipo"] == "sin cambio"
    assert cambios.loc["R02", "tipo"] == "sin precio"
    assert cambios.loc["C03", "tipo"] == "dejó de observarse"
    assert cambios.loc["L03", "tipo"] == "nuevo"


def test_vista_de_cambios_de_precio(base_prueba):
    # la vista v_cambios_precio (con LAG) solo trae los anuncios cuyo precio cambió
    with closing(sqlite3.connect(base_prueba)) as con:
        filas = con.execute("""SELECT sku_comercio, precio_anterior, precio, direccion
                               FROM v_cambios_precio ORDER BY sku_comercio""").fetchall()
    assert filas == [("C01", 10000, 11000, "subió"), ("R01", 10000, 9000, "bajó")]


def test_canasta_no_se_calcula_si_falta_un_producto(base_prueba):
    resultado = db.canasta(E2, {"P01": 1, "P02": 2})
    totales = resultado.por_comercio.set_index("comercio")
    # P02 está agotado en La Rebaja: ese comercio queda sin total y se dice qué falta
    assert pd.isna(totales.loc["La Rebaja", "total"])
    assert totales.loc["La Rebaja", "faltantes"] == "P02"
    assert totales.loc["Cafam", "total"] == 11000 + 2 * 5000
    assert totales.loc["Locatel", "total"] == 12000 + 2 * 5500
    # combinando comercios: P01 en La Rebaja y P02 en Cafam
    assert resultado.costo_minimo == 9000 + 2 * 5000
    assert resultado.mejores_comercios == ["Cafam"]
    assert resultado.ahorro == 2000


def test_canasta_sin_precio_en_ningun_comercio(base_prueba):
    resultado = db.canasta(E2, {"P01": 1, "P04": 1})
    assert resultado.por_comercio["total"].isna().all()
    assert resultado.costo_minimo is None
    assert resultado.mejores_comercios == []
    assert resultado.ahorro is None


@pytest.mark.parametrize("texto", ["'; DROP TABLE observaciones; --", "a" * 61, "<script>"])
def test_busqueda_rechaza_texto_no_permitido(texto):
    with pytest.raises(db.EntradaInvalida):
        db.validar_texto(texto)


def test_busqueda_trata_el_porcentaje_como_texto(base_prueba):
    # '%' es comodín de LIKE; si no se escapara, la búsqueda traería todos los anuncios
    assert len(db.productos(db.Filtros(id_ejecucion=E2, texto="P01"))) == 3
    assert db.productos(db.Filtros(id_ejecucion=E2, texto="%")).empty
