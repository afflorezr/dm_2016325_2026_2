"""Inserción sin duplicados, transacciones, validación, disponibilidad, cambios de precio, canasta y modo sin conexión."""
import sqlite3

import pandas as pd
import pytest

import datos_falsos as F
import db
import limpieza as L
import scraper as S
import validacion as V
from conftest import E1, E2


def contar(ruta, sql, *params):
    con = sqlite3.connect(ruta)
    try:
        return con.execute(sql, params).fetchone()[0]
    finally:
        con.close()


# ---------------------------------------------------------------- inserción
def test_insertar_dos_veces_la_misma_ejecucion_no_duplica_observaciones(tmp_path):
    ruta, raw = tmp_path / "t.sqlite", tmp_path / "raw"
    F.ejecutar(ruta, raw, "run_A", "2026-10-01T10:00:00-05:00")
    antes = contar(ruta, "SELECT COUNT(*) FROM observaciones")
    assert antes > 0
    # Mismo identificador de ejecución, otra hora de consulta: la unicidad (ejecución, anuncio) debe impedir duplicar.
    res = F.ejecutar(ruta, raw, "run_A", "2026-10-01T15:00:00-05:00")
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones") == antes
    assert res["obs_nuevas"].sum() == 0


def test_la_restriccion_de_unicidad_existe_en_la_base(tmp_path):
    con = db.conectar_escritura(tmp_path / "t.sqlite")
    indices = {r[1]: r[2] for r in con.execute("PRAGMA index_list(observaciones)")}
    con.close()
    assert indices.get("ux_obs_ejec_anuncio") == 1          # índice único (ejecución, anuncio)


def test_una_falla_a_mitad_de_la_insercion_revierte_todo(tmp_path, monkeypatch):
    ruta, raw = tmp_path / "t.sqlite", tmp_path / "raw"

    def explota(*a, **k):
        raise RuntimeError("falla simulada")
    monkeypatch.setattr(L, "normalizar_anuncios", explota)
    res = F.ejecutar(ruta, raw, "run_X", "2026-10-01T10:00:00-05:00", comercios=("exito",))
    assert res.loc[0, "estado"] == "fallida" and "revertida" in res.loc[0, "motivo"]
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones") == 0       # nada quedó a medias
    assert contar(ruta, "SELECT COUNT(*) FROM anuncios") == 0
    assert contar(ruta, "SELECT estado FROM ejecuciones") == "fallida"   # pero la falla quedó registrada


def test_un_comercio_que_falla_no_detiene_a_los_demas(tmp_path):
    ruta, raw = tmp_path / "t.sqlite", tmp_path / "raw"
    res = F.ejecutar(ruta, raw, "run_B", "2026-10-01T10:00:00-05:00", F.ClienteFalso(falla={"jumbo"}))
    estados = dict(zip(res["comercio"], res["estado"]))
    assert estados["jumbo"] == "fallida" and estados["exito"] != "fallida" and estados["olimpica"] != "fallida"
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones WHERE comercio_id = (SELECT comercio_id FROM comercios WHERE clave='jumbo')") == 0
    assert "403" in res.loc[res["comercio"] == "jumbo", "motivo"].iloc[0]


# ---------------------------------------------------------------- validación
def test_validacion_rechaza_precio_invalido_url_vacia_y_duplicados():
    import pandas as pd
    base = dict(ejecucion_id="r", comercio="exito", url="https://x/p", nombre_original="n", precio_lista=None,
                disponible=1, fecha_hora_consulta="2026-10-01T10:00:00-05:00")
    df = pd.DataFrame([
        dict(base, sku="1", precio=100.0),                       # válida
        dict(base, sku="2", precio=0.0),                         # precio no positivo
        dict(base, sku="3", precio=None),                        # disponible sin precio
        dict(base, sku="4", precio=50.0, url=""),                # sin URL
        dict(base, sku="5", precio=50.0, fecha_hora_consulta="ayer"),  # fecha inválida
        dict(base, sku="1", precio=100.0),                       # duplicada en la misma ejecución
        dict(base, sku="6", precio=None, disponible=0),          # agotado sin precio: permitido (queda NULL)
    ])
    validas, rech = V.validar_observaciones(df)
    assert sorted(validas["sku"]) == ["1", "6"]
    motivos = dict(zip(rech["sku"] + rech.index.astype(str), rech["motivo"]))
    texto = " ".join(motivos.values())
    for regla in ("precio_numerico_positivo", "url_presente", "fecha_hora_valida", "sin_duplicados_en_ejecucion"):
        assert regla in texto


def test_lo_rechazado_no_se_inserta_y_queda_registrado_con_su_motivo(tmp_path):
    ruta, raw = tmp_path / "t.sqlite", tmp_path / "raw"
    res = F.ejecutar(ruta, raw, "run_V", "2026-10-01T10:00:00-05:00", F.ClienteFalso(sin_precio_disponible={0}))
    assert res["rechazadas"].sum() >= 3                                   # el producto 0 en los tres comercios
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones_rechazadas WHERE motivo LIKE '%precio_numerico_positivo%'") >= 3
    assert contar(ruta, "SELECT COUNT(*) FROM observaciones o JOIN anuncios a USING(anuncio_id) WHERE a.sku = '1000'") == 0


# ---------------------------------------------------------------- disponibilidad
def test_tres_estados_de_disponibilidad(base_demo):
    with db.abrir(base_demo["db"]) as con:
        estados = {r[0] for r in con.execute("SELECT DISTINCT estado FROM v_disponibilidad")}
        assert {"disponible", "agotado", "no_observado"} <= estados
        # el producto 1 (Éxito) existía en la ejecución 1 y no aparece en la 2: no observado, NO agotado
        fila = con.execute("""SELECT d.estado FROM v_disponibilidad d JOIN anuncios a USING(anuncio_id)
                              WHERE a.sku='1001' AND d.comercio_id=(SELECT comercio_id FROM comercios WHERE clave='exito')
                                AND d.ejecucion_id=?""", [E2]).fetchone()
        assert fila[0] == "no_observado"
        # el producto 7 se marcó agotado en la ejecución 2
        fila = con.execute("""SELECT estado_disponibilidad FROM v_observaciones WHERE sku='1007' AND ejecucion_id=? LIMIT 1""", [E2]).fetchone()
        assert fila[0] == "agotado"


def test_ejecucion_a_la_que_le_faltan_comparables_queda_parcial(base_demo):
    with db.abrir(base_demo["db"]) as con:
        fila = con.execute("""SELECT e.estado, e.notas FROM ejecuciones e JOIN comercios c USING(comercio_id)
                              WHERE e.ejecucion_id=? AND c.clave='exito'""", [E2]).fetchone()
    assert fila[0] == "parcial" and "comparable" in fila[1]


# ---------------------------------------------------------------- cambios de precio
def test_deteccion_de_cambios_de_precio_entre_ejecuciones(base_demo):
    with db.abrir(base_demo["db"]) as con:
        df = db.cambios_entre_ejecuciones(con, E1, E2, umbral_pct=5.0)
    por_sku = df.groupby(["comercio", "sku"])["tipo"].first()
    assert por_sku[("Éxito", "1004")] == "subió" and por_sku[("Éxito", "1005")] == "bajó"
    assert por_sku[("Éxito", "1000")] == "nuevo" and por_sku[("Éxito", "1001")] == "dejó de observarse"
    assert por_sku[("Jumbo", "1002")] == "sin cambio"
    sube = df[(df["comercio"] == "Éxito") & (df["sku"] == "1004")].iloc[0]
    assert sube["variacion_pct"] == pytest.approx(10.0, abs=0.1) and bool(sube["variacion_grande"]) is True
    # con umbral 15 % ya no se resalta la subida de 10 %, pero sí la bajada de 20 %
    df15 = db.cambios_entre_ejecuciones(sqlite3.connect(base_demo["db"]), E1, E2, umbral_pct=15.0)
    assert bool(df15[(df15["comercio"] == "Éxito") & (df15["sku"] == "1004")]["variacion_grande"].iloc[0]) is False
    assert bool(df15[(df15["comercio"] == "Éxito") & (df15["sku"] == "1005")]["variacion_grande"].iloc[0]) is True


def test_la_vista_de_cambios_registra_solo_el_mismo_anuncio_en_el_mismo_comercio(base_demo):
    with db.abrir(base_demo["db"]) as con:
        filas = con.execute("SELECT comercio, sku, precio_anterior, precio_nuevo FROM v_cambios_precio WHERE ejecucion_id=?", [E2]).fetchall()
    assert filas and all(r[2] != r[3] for r in filas)
    assert {r[0] for r in filas} == {"Éxito", "Jumbo", "Olímpica"}


def test_comercio_fallido_no_se_compara(tmp_path):
    ruta, raw = tmp_path / "t.sqlite", tmp_path / "raw"
    F.ejecutar(ruta, raw, "run_1", "2026-10-01T10:00:00-05:00", F.ClienteFalso(falla={"jumbo"}))
    F.ejecutar(ruta, raw, "run_2", "2026-10-02T10:00:00-05:00")
    with db.abrir(ruta) as con:
        assert db.comercios_sin_comparacion(con, "run_1", "run_2") == ["Jumbo"]
        df = db.cambios_entre_ejecuciones(con, "run_1", "run_2")
    assert "Jumbo" not in set(df["comercio"])       # sin base de comparación no se inventan "nuevos"


# ---------------------------------------------------------------- canasta
def _ids(con, *nombres_parciales):
    return {int(r[0]): 1 for r in con.execute("SELECT producto_id, nombre_std FROM productos")
            if any(n in r[1] for n in nombres_parciales)}


def test_la_canasta_no_se_calcula_si_falta_un_producto(base_demo):
    with db.abrir(base_demo["db"]) as con:
        items = {int(r[0]): 1 for r in con.execute("SELECT producto_id FROM productos")}
        faltante = con.execute("SELECT producto_id FROM productos LIMIT 1").fetchone()[0]
        # la ejecución 2 de Éxito no tiene algún comparable: su total debe ser NULL, no un total parcial
        tot = db.canasta_totales(con, E2, items)
        exito = tot[tot["comercio"] == "Éxito"].iloc[0]
        assert exito["n_faltantes"] >= 1 and pd.isna(exito["total"])
        jumbo = tot[tot["comercio"] == "Jumbo"].iloc[0]
        assert jumbo["n_faltantes"] >= 1 and pd.isna(jumbo["total"])      # el 7 está agotado en todos
        # una canasta con productos disponibles en todos sí tiene total
        ok = {int(r[0]): 2 for r in con.execute("SELECT producto_id FROM productos WHERE nombre_std LIKE '%Winny%'")}
        tot_ok = db.canasta_totales(con, E1, ok)
        assert tot_ok["total"].notna().all() and (tot_ok["n_faltantes"] == 0).all()
        assert faltante in items


def test_costo_minimo_de_la_canasta_reconoce_empates(base_demo):
    with db.abrir(base_demo["db"]) as con:
        ok = _ids(con, "Winny")
        m = db.canasta_minimo(con, E1, ok)
        assert len(m) == len(ok) and (m["subtotal"] == m["precio_minimo"] * m["cantidad"]).all()
        tot = db.canasta_totales(con, E1, ok)
        assert m["subtotal"].sum() <= tot["total"].min() + 1e-6          # nunca cuesta más que el mejor comercio único


# ---------------------------------------------------------------- seguridad
def test_la_busqueda_esta_parametrizada_y_no_permite_inyeccion_sql(base_demo):
    ataque = "x' OR '1'='1'; DROP TABLE anuncios; --"
    with db.abrir(base_demo["db"]) as con:
        total = con.execute("SELECT COUNT(*) FROM v_ultimo_precio").fetchone()[0]
        df = db.tabla_productos(con, db.Filtros(busqueda=ataque))
        assert df.empty and total > 0               # no devuelve todo ni ejecuta nada
        df2 = db.tabla_productos(con, db.Filtros(comercios=("Éxito' OR '1'='1",)))
        assert df2.empty
    assert contar(base_demo["db"], "SELECT COUNT(*) FROM anuncios") > 0     # la tabla sigue existiendo


def test_la_busqueda_ignora_mayusculas_y_acentos_y_trata_el_porcentaje_como_texto(base_demo):
    with db.abrir(base_demo["db"]) as con:
        assert len(db.tabla_productos(con, db.Filtros(busqueda="PANALES winny"))) > 0
        assert db.tabla_productos(con, db.Filtros(busqueda="%")).empty        # '%' no es comodín


@pytest.mark.parametrize("texto", ["a" * 61, "winny; DROP TABLE x", "<script>", "pañal\"x"])
def test_validar_busqueda_rechaza_entradas_peligrosas(texto):
    with pytest.raises(ValueError):
        V.validar_busqueda(texto)


def test_validar_busqueda_acepta_texto_normal_y_limpia_espacios():
    assert V.validar_busqueda("  pañales   winny  talla 4 ") == "pañales winny talla 4"


@pytest.mark.parametrize("valor", [-1, 101, "abc", float("nan"), None])
def test_validar_umbral_rechaza_valores_fuera_de_rango(valor):
    with pytest.raises(ValueError):
        V.validar_umbral(valor)


def test_validar_cantidad():
    assert V.validar_cantidad("3") == 3
    for malo in (0, 100, "x", None):
        with pytest.raises(ValueError):
            V.validar_cantidad(malo)


# ---------------------------------------------------------------- modo sin conexión
def test_modo_sin_conexion_reconstruye_la_base_desde_raw_sin_consultar_sitios(base_demo, tmp_path, monkeypatch):
    llamadas = []
    monkeypatch.setattr(S.Cliente, "get_json", lambda *a, **k: llamadas.append(1))
    nueva = tmp_path / "reconstruida.sqlite"
    res = S.reprocesar_raw(nueva, base_demo["raw"])
    assert llamadas == []                                           # no se consultó ningún sitio
    for tabla in ("ejecuciones", "observaciones", "anuncios"):
        assert contar(nueva, f"SELECT COUNT(*) FROM {tabla}") == contar(base_demo["db"], f"SELECT COUNT(*) FROM {tabla}"), tabla
    assert set(res["estado"]) <= {"completa", "parcial", "fallida"}
    assert contar(nueva, "SELECT COUNT(*) FROM observaciones WHERE raw_archivo IS NOT NULL") == contar(nueva, "SELECT COUNT(*) FROM observaciones")


def test_reprocesar_sobre_una_base_que_ya_tiene_los_datos_no_la_modifica(base_demo):
    antes = contar(base_demo["db"], "SELECT COUNT(*) FROM observaciones")
    res = S.reprocesar_raw(base_demo["db"], base_demo["raw"])
    assert set(res["estado"]) == {"ya_cargada"}
    assert contar(base_demo["db"], "SELECT COUNT(*) FROM observaciones") == antes
    assert contar(base_demo["db"], "SELECT COUNT(DISTINCT modo) FROM ejecuciones WHERE modo='sin_conexion'") == 0


def test_cada_observacion_nueva_es_rastreable_hasta_su_copia_cruda(base_demo):
    con = sqlite3.connect(base_demo["db"])
    sin = con.execute("SELECT COUNT(*) FROM observaciones WHERE raw_archivo IS NULL").fetchone()[0]
    ruta = con.execute("SELECT raw_archivo FROM observaciones LIMIT 1").fetchone()[0]
    con.close()
    assert sin == 0 and (base_demo["raw"].parent / ruta).is_file()


# ---------------------------------------------------------------- esquema
def test_el_esquema_tiene_vistas_indices_y_tablas_requeridas(tmp_path):
    con = db.conectar_escritura(tmp_path / "t.sqlite")
    objetos = {(r[0], r[1]) for r in con.execute("SELECT type, name FROM sqlite_master")}
    con.close()
    for v in ("v_ultimo_precio", "v_cambios_precio", "v_comparables", "v_disponibilidad", "v_ejecuciones_resumen"):
        assert ("view", v) in objetos
    for t in ("correcciones", "observaciones_rechazadas"):
        assert ("table", t) in objetos
    assert len([n for t, n in objetos if t == "index" and n.startswith(("ix_", "ux_"))]) >= 8


def test_preparar_base_es_idempotente(tmp_path):
    con = db.conectar_escritura(tmp_path / "t.sqlite")
    db.preparar_base(con)
    db.preparar_base(con)
    con.close()


def test_el_diccionario_de_datos_documenta_todas_las_columnas(tmp_path):
    from pathlib import Path
    import re
    texto = (Path(__file__).resolve().parent.parent / "diccionario_datos.md").read_text(encoding="utf-8")
    secciones = {m.group(2): m.group(3) for m in re.finditer(r"^## (tabla|vista) `(\w+)`\n(.*?)(?=^## |\Z)", texto, re.S | re.M)}
    con = db.conectar_escritura(tmp_path / "t.sqlite")
    objetos = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'")]
    faltan = []
    for obj in objetos:
        assert obj in secciones, f"{obj} no está en el diccionario"
        for col in (r[1] for r in con.execute(f"PRAGMA table_info({obj})")):
            if f"`{col}`" not in secciones[obj]:
                faltan.append(f"{obj}.{col}")
    con.close()
    assert not faltan, faltan


def test_no_hay_credenciales_en_el_repositorio():
    from pathlib import Path
    import re
    raiz = Path(__file__).resolve().parent.parent
    patron = re.compile(r"(api[_-]?key|secret|token|password|passwd)\s*[=:]\s*['\"][^'\"\s]{8,}", re.I)
    for ruta in raiz.rglob("*"):
        if ruta.suffix in {".py", ".toml", ".md", ".txt", ".yml", ".yaml", ".cfg"} and ruta.is_file() \
                and "tests" not in ruta.parts and ".git" not in ruta.parts and "raw" not in ruta.parts:
            assert not patron.search(ruta.read_text(encoding="utf-8", errors="ignore")), ruta.name
