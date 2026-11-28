import pandas as pd
import pytest

import db
import scraper
import validacion


def fila(id_producto, precio, id_ej, url="https://tienda.com/p", comercio="Locatel"):
    return {"comercio": comercio, "id_producto": id_producto, "sku": id_producto, "ean": None,
            "nombre": f"Proteina Whey Vainilla X 900g {id_producto}", "marca": "Marca", "categoria_sitio": "Suplementos deportivos",
            "precio": precio, "precio_antes": None, "promocion": 0, "disponibilidad": "disponible",
            "vendedor": comercio, "url": url, "texto_original": "Proteina whey", "descripcion": None,
            "fecha_consulta": f"{id_ej[:4]}-{id_ej[4:6]}-{id_ej[6:8]}T09:00:00-05:00", "id_ejecucion": id_ej}


def guardar(ruta, filas, id_ej, comercio="Locatel"):
    m = {"comercio": comercio, "id_ejecucion": id_ej, "fecha_consulta": filas[0]["fecha_consulta"] if filas else "",
         "estado": "completa"}
    con = scraper.conectar(ruta)
    resumen = scraper.guardar(con, pd.DataFrame(filas, columns=scraper.COLUMNAS), m)
    con.close()
    return resumen


@pytest.fixture
def base(tmp_path):
    """Base temporal con dos ejecuciones de dos comercios y dos productos comparables."""
    ruta = tmp_path / "prueba.sqlite"
    for comercio, precios in {"Locatel": (100000, 50000, 110000, 50000), "Farmatodo": (100000, 60000, 90000, None)}.items():
        guardar(ruta, [fila("a", precios[0], "20261001T090000", comercio=comercio),
                       fila("b", precios[1], "20261001T090000", comercio=comercio)], "20261001T090000", comercio)
        nuevas = [fila("a", precios[2], "20261101T090000", comercio=comercio)]
        if precios[3]:
            nuevas.append(fila("b", precios[3], "20261101T090000", comercio=comercio))
        guardar(ruta, nuevas, "20261101T090000", comercio)
    con = scraper.conectar(ruta)
    with con:
        con.execute("INSERT INTO productos (id_producto_comun, nombre_comun, marca_std, contenido, unidad) "
                    "VALUES ('pa', 'Whey 900 g', 'Marca', 900, 'g'), ('pb', 'Barra 1 und', 'Marca', 1, 'und')")
        con.execute("UPDATE anuncios SET comparable = 1, id_producto_comun = 'p' || id_producto_comercio")
    con.close()
    db.st.cache_data.clear()
    return ruta


def test_limpiar_precio():
    assert scraper.limpiar_precio("$ 12.900") == 12900
    assert scraper.limpiar_precio("$12.900,50") == 12900.5
    assert scraper.limpiar_precio(119900) == 119900.0
    assert scraper.limpiar_precio("") is None
    assert scraper.limpiar_precio(None) is None


def test_normalizacion_de_unidades():
    assert scraper.extraer_contenido("2 lb") == (907.2, "g", 1)
    assert scraper.extraer_contenido("1,8 kg") == (1800.0, "g", 1)
    assert scraper.extraer_contenido("1.5 l") == (1500.0, "ml", 1)
    assert scraper.extraer_contenido("caja x 30 sticks x 6 gr") == (180.0, "g", 30)
    assert scraper.extraer_contenido("electrolitos caja x 12") == (12.0, "und", 12)


def test_ahorro_con_empates(base):
    ahorro = db.ahorro_comparables("20261001T090000", base).set_index("producto")
    empate = ahorro.loc["Marca Whey 900 g"]       # 100.000 en los dos comercios
    assert empate["ahorro_cop"] == 0
    assert empate["empatados"] == 2
    assert set(empate["comprar_en"].split(", ")) == {"Farmatodo", "Locatel"}
    barra = ahorro.loc["Marca Barra 1 und"]        # 50.000 en Locatel y 60.000 en Farmatodo
    assert barra["ahorro_cop"] == 10000 and barra["comprar_en"] == "Locatel"


def test_insertar_dos_veces_no_duplica(base):
    filas = [fila("a", 110000, "20261101T090000")]
    resumen = guardar(base, filas, "20261101T090000")
    assert resumen["insertadas"] == 0
    total = db.consultar("SELECT COUNT(*) FROM observaciones WHERE id_ejecucion = '20261101T090000'", db=base)
    assert total.iloc[0, 0] == 3


def test_deteccion_de_cambios_de_precio(base):
    cambios = db.cambios_precio("20261001T090000", "20261101T090000", base)
    tipos = dict(zip(cambios["comercio"] + " " + cambios["nombre"].str[-1], cambios["tipo"]))
    assert tipos["Locatel a"] == "subió"
    assert tipos["Farmatodo a"] == "bajó"
    assert tipos["Locatel b"] == "igual"
    assert tipos["Farmatodo b"] == "ya no se observa"
    assert cambios.set_index("tipo").loc["subió", "cambio_pct"] == 10.0


def test_canasta_no_se_calcula_si_falta_un_producto(base):
    por_comercio, minimo = db.canasta("20261101T090000", (("pa", 1), ("pb", 2)), base)
    totales = por_comercio.set_index("comercio")
    assert totales.loc["Locatel", "total"] == 110000 + 2 * 50000
    assert pd.isna(totales.loc["Farmatodo", "total"])     # no tiene la barra en esta ejecución
    assert totales.loc["Farmatodo", "faltan"] == 1
    assert minimo == 90000 + 2 * 50000


def test_validacion_rechaza_observaciones():
    df = pd.DataFrame([fila("a", 1000, "20261101T090000"), fila("a", 1000, "20261101T090000"),
                       fila("b", 0, "20261101T090000"), fila("c", 500, "20261101T090000", url=None)])
    validas, rechazadas = validacion.validar(df)
    assert len(validas) == 1
    assert sorted(rechazadas["motivo"]) == ["URL ausente", "observación duplicada en la ejecución",
                                            "precio no mayor que cero"]


def test_validar_texto_de_busqueda():
    assert validacion.validar_texto("  whey 100% ") == "whey 100%"
    with pytest.raises(ValueError):
        validacion.validar_texto("x' OR 1=1 --")
    with pytest.raises(ValueError):
        validacion.validar_texto("a" * 61)
