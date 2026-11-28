# -*- coding: utf-8 -*-
"""
db.py - Capa de acceso a datos (Módulo 3). La interfaz NO contiene SQL: llama a estas funciones.

- Todo filtro, indicador y agregación se calcula con SQL sobre SQLite (nunca se lee la tabla completa para filtrar en memoria).
- Todo valor que viene del usuario se pasa como parámetro (?). En el texto SQL solo se insertan marcadores '?'
  y nombres de columna que están escritos en este archivo (constantes), nunca texto del usuario.
- Las consultas usan una conexión de SOLO LECTURA que se cierra al terminar (`sesion`).
- La caché y su invalidación (st.cache_data) viven en la aplicación, que envuelve estas funciones.
"""
import math
import re
import sqlite3
from contextlib import contextmanager
from pathlib import Path

import pandas as pd

DB_DEFECTO = str(Path(__file__).resolve().parent / "comparador_precios.sqlite")
MAX_TEXTO = 60
_TEXTO_PERMITIDO = re.compile(r"^[\w\sáéíóúüñÁÉÍÓÚÜÑ.\-+%/()]*$")


# --------------------------------------------------------------------------- conexión y entradas del usuario
def conectar(db_path=DB_DEFECTO, solo_lectura=True):
    if solo_lectura:
        return sqlite3.connect(f"file:{Path(db_path).as_posix()}?mode=ro", uri=True)
    return sqlite3.connect(db_path)


@contextmanager
def sesion(db_path=DB_DEFECTO, solo_lectura=True):
    """Abre y cierra la conexión de forma controlada: `with sesion() as con: ...`"""
    con = conectar(db_path, solo_lectura)
    try:
        yield con
    finally:
        con.close()


def validar_texto(texto):
    """Valida el texto de búsqueda (longitud y caracteres). Devuelve el texto limpio o lanza ValueError."""
    t = (texto or "").strip()
    if len(t) > MAX_TEXTO:
        raise ValueError(f"La búsqueda admite máximo {MAX_TEXTO} caracteres.")
    if not _TEXTO_PERMITIDO.match(t):
        raise ValueError("La búsqueda contiene caracteres no permitidos.")
    return t


def _like(t):
    """Patrón LIKE con los comodines del usuario escapados."""
    return "%" + t.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _clausulas(comercios=None, subcategorias=None, marcas=None, pmin=None, pmax=None,
               solo_promocion=False, solo_comparables=False, texto=None, solo_en_alcance=True):
    """Devuelve (WHERE, parámetros) para los filtros del panel lateral."""
    cl, par = [], []
    if solo_en_alcance:
        cl.append("en_alcance = 1")
    for col, vals in (("comercio", comercios), ("subcategoria", subcategorias), ("marca_estandar", marcas)):
        if vals:
            cl.append(f"{col} IN ({','.join('?' * len(vals))})")
            par += list(vals)
    if pmin is not None:
        cl.append("precio >= ?"); par.append(float(pmin))
    if pmax is not None:
        cl.append("precio <= ?"); par.append(float(pmax))
    if solo_promocion:
        cl.append("promocion = 1")
    if solo_comparables:
        cl.append("comparable = 1")
    t = validar_texto(texto) if texto else ""
    if t:
        cl.append("(titulo_original LIKE ? ESCAPE '\\' OR texto_original LIKE ? ESCAPE '\\')")
        par += [_like(t), _like(t)]
    return (" WHERE " + " AND ".join(cl)) if cl else "", par


def _fuente(ejecucion, incluir_no_observados=False):
    """Origen de datos: los anuncios observados en la última ejecución de su comercio (por defecto), o también los
    que solo se conocen de una ejecución anterior (con su último precio), o todas las observaciones de una ejecución."""
    if ejecucion:
        return "v_observaciones", " AND id_ejecucion = ?", [ejecucion]
    return "v_ultimo_precio", "" if incluir_no_observados else " AND vigente = 1", []


def _df(con, sql, params=()):
    return pd.read_sql_query(sql, con, params=list(params))


VISTAS_REQUERIDAS = ("v_observaciones", "v_ultimo_precio", "v_cambios_precio", "v_comparables", "v_disponibilidad")


def esquema_listo(con):
    """True si la base ya tiene las vistas y tablas del Taller 2 (la prepara migrar_taller2.py)."""
    nombres = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'view')")}
    if not (set(VISTAS_REQUERIDAS) <= nombres and {"observaciones", "ejecuciones", "productos"} <= nombres):
        return False
    # la vista debe ser la versión actual (con la marca `vigente`); si no, hay que volver a correr migrar_taller2.py
    return "vigente" in {r[1] for r in con.execute("PRAGMA table_info(v_ultimo_precio)")}


# --------------------------------------------------------------------------- ejecuciones
def ejecuciones_validas(con):
    """Ejecuciones válidas, de la más reciente a la más antigua (una fila por ejecución)."""
    return _df(con, """
        SELECT id_ejecucion, MIN(fecha_inicio) AS fecha_inicio,
               GROUP_CONCAT(comercio || ': ' || estado, ' · ') AS estados
        FROM ejecuciones WHERE valida = 1 GROUP BY id_ejecucion ORDER BY fecha_inicio DESC""")


def ultima_ejecucion_con_comparables(con):
    fila = con.execute("""SELECT id_ejecucion FROM v_comparables GROUP BY id_ejecucion
                          ORDER BY MAX(fecha_consulta) DESC LIMIT 1""").fetchone()
    return fila[0] if fila else None


def ejecuciones_con_comparables(con):
    """Ejecuciones válidas que tienen precios de los productos comparables (más reciente primero)."""
    return _df(con, """SELECT id_ejecucion, MIN(fecha_consulta) AS fecha_consulta, COUNT(*) AS observaciones
                       FROM v_comparables GROUP BY id_ejecucion ORDER BY MIN(fecha_consulta) DESC""")


def estado_ultima_ejecucion(con):
    """Estado por comercio de la ejecución válida más reciente."""
    return _df(con, """
        SELECT comercio, id_ejecucion, fecha_inicio, estado, registros_obtenidos, registros_insertados
        FROM ejecuciones WHERE valida = 1 AND id_ejecucion = (
            SELECT id_ejecucion FROM ejecuciones WHERE valida = 1 ORDER BY fecha_inicio DESC LIMIT 1)
        ORDER BY comercio""")


# --------------------------------------------------------------------------- filtros, productos y tabla
def opciones_filtros(con):
    ult = "SELECT comercio, subcategoria, marca_estandar, precio FROM v_ultimo_precio WHERE en_alcance = 1 AND vigente = 1"
    return {
        "comercios": [r[0] for r in con.execute(f"SELECT DISTINCT comercio FROM ({ult}) ORDER BY 1")],
        "subcategorias": [r[0] for r in con.execute(
            f"SELECT DISTINCT subcategoria FROM ({ult}) WHERE subcategoria IS NOT NULL ORDER BY 1")],
        "marcas": [r[0] for r in con.execute(
            f"SELECT DISTINCT marca_estandar FROM ({ult}) WHERE marca_estandar IS NOT NULL ORDER BY 1")],
        "precio": con.execute(f"SELECT MIN(precio), MAX(precio) FROM ({ult})").fetchone(),
    }


def productos_filtrados(con, ejecucion=None, limite=20000, incluir_no_observados=False, **filtros):
    vista, extra, par_e = _fuente(ejecucion, incluir_no_observados)
    where, par = _clausulas(**filtros)
    sql = f"""
        SELECT comercio, titulo_original AS producto, marca_estandar AS marca, subcategoria,
               CASE WHEN contenido_num IS NULL THEN NULL ELSE contenido_num || ' ' || unidad END AS presentacion,
               precio, unidad, precio_unitario, promocion, disponible, fecha_consulta, url,
               id_producto_comun, comparable
        FROM {vista}{where or ' WHERE 1 = 1'}{extra}
        ORDER BY precio LIMIT ?"""
    return _df(con, sql, par + par_e + [int(limite)])


# --------------------------------------------------------------------------- indicadores (SQL)
def indicadores(con, ejecucion=None, incluir_no_observados=False, **filtros):
    """Seis o más indicadores con su unidad y su periodo, calculados con SQL."""
    vista, extra, par_e = _fuente(ejecucion, incluir_no_observados)
    where, par = _clausulas(**filtros)
    base = f"FROM {vista}{where or ' WHERE 1 = 1'}{extra}"
    p = par + par_e
    out = {}
    out["por_comercio"] = _df(con, f"SELECT comercio, COUNT(*) AS productos {base} GROUP BY comercio ORDER BY comercio", p)
    out["total_productos"] = con.execute(f"SELECT COUNT(*) {base}", p).fetchone()[0]
    out["total_observaciones"] = con.execute("SELECT COUNT(*) FROM v_observaciones").fetchone()[0]
    pr = con.execute(f"SELECT COUNT(*), COALESCE(SUM(promocion), 0) {base}", p).fetchone()
    out["pct_promocion"] = round(100.0 * pr[1] / pr[0], 1) if pr[0] else None
    out["mediana_por_subcategoria"] = _df(con, f"""
        WITH r AS (SELECT subcategoria, precio,
                          ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS rn,
                          COUNT(*) OVER (PARTITION BY subcategoria) AS n
                   {base} AND subcategoria IS NOT NULL)
        SELECT subcategoria, AVG(precio) AS mediana, MAX(n) AS productos
        FROM r WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY subcategoria ORDER BY mediana DESC""", p)
    out["estado_ultima_ejecucion"] = estado_ultima_ejecucion(con)
    ej = ultima_ejecucion_con_comparables(con)
    out["ejecucion_comparables"] = ej
    ah = ahorro_comparables(con, ej) if ej else pd.DataFrame()
    out["ahorro_maximo"] = ah.sort_values("ahorro_pct", ascending=False).iloc[0].to_dict() if len(ah) else None
    out["cambios_ultima"] = _df(con, """
        SELECT ejecucion_nueva, SUM(variacion_cop > 0) AS suben, SUM(variacion_cop < 0) AS bajan
        FROM v_cambios_precio WHERE variacion_cop <> 0
          AND ejecucion_nueva = (SELECT id_ejecucion FROM ejecuciones WHERE valida = 1
                                 ORDER BY fecha_inicio DESC LIMIT 1)
        GROUP BY ejecucion_nueva""")
    return out


# --------------------------------------------------------------------------- comparables, ahorro y precio por unidad
def ahorro_precios(precios):
    """Ahorro al elegir la oferta más barata. `precios` = {comercio: precio}. Devuelve los empates incluidos."""
    validos = {c: p for c, p in precios.items() if p is not None and not (isinstance(p, float) and math.isnan(p))}
    if not validos:
        return None
    pmin, pmax = min(validos.values()), max(validos.values())
    return {"p_min": pmin, "p_max": pmax,
            "comercios_min": sorted(c for c, p in validos.items() if p == pmin),
            "ahorro_cop": pmax - pmin,
            "ahorro_pct": round(100.0 * (pmax - pmin) / pmax, 2) if pmax else 0.0}


def precios_comparables(con, ejecucion=None):
    ejecucion = ejecucion or ultima_ejecucion_con_comparables(con)
    return _df(con, """
        SELECT id_producto_comun, marca_estandar, nombre_estandar, contenido_num, unidad, comercio,
               precio_vigente AS precio, precio_lista, promocion, precio_unitario, fecha_consulta
        FROM v_comparables WHERE id_ejecucion = ? ORDER BY id_producto_comun, comercio""", [ejecucion])


def ahorro_comparables(con, ejecucion=None):
    """Mínimo, máximo, promedio, comercios más baratos (con empates) y ahorro por presentación comparable."""
    ejecucion = ejecucion or ultima_ejecucion_con_comparables(con)
    df = precios_comparables(con, ejecucion)
    filas = []
    for pid, g in df.groupby("id_producto_comun"):
        a = ahorro_precios(dict(zip(g.comercio, g.precio)))
        filas.append({"id_producto_comun": pid,
                      "producto": f"{g.marca_estandar.iloc[0]} {g.nombre_estandar.iloc[0]}",
                      "presentacion": f"{g.contenido_num.iloc[0]:g} {g.unidad.iloc[0]}",
                      "p_min": a["p_min"], "p_prom": round(g.precio.mean()), "p_max": a["p_max"],
                      "mas_barato": " = ".join(a["comercios_min"]),
                      "ahorro_cop": a["ahorro_cop"], "ahorro_pct": a["ahorro_pct"], "id_ejecucion": ejecucion})
    return pd.DataFrame(filas)


def evolucion_precio(con, id_producto_comun):
    """Serie de precios de un producto comparable: una serie por comercio, una observación por ejecución válida."""
    return _df(con, """
        SELECT fecha_consulta, id_ejecucion, comercio, precio_vigente AS precio
        FROM v_comparables WHERE id_producto_comun = ? ORDER BY fecha_consulta""", [id_producto_comun])


def precio_unitario_comparable(con, unidad, ejecucion=None):
    """Precio por unidad de contenido de los comparables, SOLO de una unidad (mL, g o unidad)."""
    ejecucion = ejecucion or ultima_ejecucion_con_comparables(con)
    return _df(con, """
        SELECT id_producto_comun, marca_estandar || ' ' || nombre_estandar AS producto,
               contenido_num, unidad, comercio, precio_vigente AS precio, precio_unitario
        FROM v_comparables WHERE id_ejecucion = ? AND unidad = ? ORDER BY precio_unitario""", [ejecucion, unidad])


def unidades_comparables(con):
    return [r[0] for r in con.execute("SELECT DISTINCT unidad FROM productos ORDER BY 1")]


def precio_unitario_familias(con, ejecucion=None):
    """Mismo producto en distintos tamaños (tabla familias_tamano): precio por mL/g de cada tamaño y comercio."""
    ejecucion = ejecucion or ultima_ejecucion_con_comparables(con)
    return _df(con, """
        SELECT f.nombre_familia AS familia, o.comercio, o.contenido_num, o.unidad, o.precio, o.precio_unitario
        FROM v_observaciones o JOIN familias_tamano f USING (codigo_barras)
        WHERE o.id_ejecucion = ? AND o.en_alcance = 1 ORDER BY o.precio_unitario""", [ejecucion])


# --------------------------------------------------------------------------- cambios de precio entre ejecuciones
def cambios_entre_ejecuciones(con, ejecucion_antes, ejecucion_despues, umbral_pct=10.0):
    """Compara el MISMO anuncio en el MISMO comercio entre dos ejecuciones.
    Devuelve dict con: cambios (suben/bajan, con marca de variación grande), nuevos y no_observados.
    Solo se consideran comercios que tienen datos válidos en ambas ejecuciones."""
    comunes = """comercio IN (SELECT comercio FROM v_observaciones WHERE id_ejecucion = ?)
                 AND comercio IN (SELECT comercio FROM v_observaciones WHERE id_ejecucion = ?)"""
    cambios = _df(con, f"""
        SELECT a.comercio, a.titulo_original AS producto, a.marca_estandar AS marca,
               b.precio AS precio_antes, a.precio AS precio_despues, a.precio - b.precio AS variacion_cop,
               ROUND(100.0 * (a.precio - b.precio) / b.precio, 2) AS variacion_pct,
               CASE WHEN ABS(100.0 * (a.precio - b.precio) / b.precio) >= ? THEN 1 ELSE 0 END AS variacion_grande,
               a.url
        FROM v_observaciones a JOIN v_observaciones b
             ON a.comercio = b.comercio AND a.sku_comercio = b.sku_comercio
        WHERE a.id_ejecucion = ? AND b.id_ejecucion = ? AND a.precio <> b.precio AND a.en_alcance = 1
        ORDER BY ABS(100.0 * (a.precio - b.precio) / b.precio) DESC""",
        [float(umbral_pct), ejecucion_despues, ejecucion_antes])
    nuevos = _df(con, f"""
        SELECT a.comercio, a.titulo_original AS producto, a.marca_estandar AS marca, a.precio, a.url
        FROM v_observaciones a
        WHERE a.id_ejecucion = ? AND a.en_alcance = 1 AND a.{comunes}
          AND NOT EXISTS (SELECT 1 FROM v_observaciones b WHERE b.id_ejecucion = ?
                          AND b.comercio = a.comercio AND b.sku_comercio = a.sku_comercio)
        ORDER BY a.comercio, a.titulo_original""", [ejecucion_despues, ejecucion_antes, ejecucion_despues, ejecucion_antes])
    no_obs = _df(con, f"""
        SELECT b.comercio, b.titulo_original AS producto, b.marca_estandar AS marca, b.precio AS ultimo_precio, b.url
        FROM v_observaciones b
        WHERE b.id_ejecucion = ? AND b.en_alcance = 1 AND b.{comunes}
          AND NOT EXISTS (SELECT 1 FROM v_observaciones a WHERE a.id_ejecucion = ?
                          AND a.comercio = b.comercio AND a.sku_comercio = b.sku_comercio)
        ORDER BY b.comercio, b.titulo_original""", [ejecucion_antes, ejecucion_antes, ejecucion_despues, ejecucion_despues])
    return {"cambios": cambios, "nuevos": nuevos, "no_observados": no_obs}


def resumen_ejecucion(con, id_ejecucion):
    """Resumen por comercio de una ejecución: recolectados, nuevos, cambios de precio y no observados
    respecto a la ejecución válida anterior del mismo comercio."""
    filas = []
    for comercio, estado, obtenidos, rechaz in con.execute("""
            SELECT e.comercio, e.estado, e.registros_obtenidos,
                   (SELECT COUNT(*) FROM observaciones_rechazadas r
                    WHERE r.id_ejecucion = e.id_ejecucion AND r.comercio = e.comercio)
            FROM ejecuciones e WHERE e.id_ejecucion = ? ORDER BY e.comercio""", [id_ejecucion]).fetchall():
        previa = con.execute("""SELECT id_ejecucion FROM ejecuciones WHERE comercio = ? AND valida = 1
                                AND fecha_inicio < (SELECT fecha_inicio FROM ejecuciones WHERE id_ejecucion = ? AND comercio = ?)
                                ORDER BY fecha_inicio DESC LIMIT 1""", [comercio, id_ejecucion, comercio]).fetchone()
        nuevos = cambios = no_obs = None
        if previa:
            cmp_ = cambios_entre_ejecuciones(con, previa[0], id_ejecucion, 0)
            f = lambda d: int((d.comercio == comercio).sum())      # noqa: E731
            nuevos, cambios, no_obs = f(cmp_["nuevos"]), f(cmp_["cambios"]), f(cmp_["no_observados"])
        filas.append({"comercio": comercio, "estado": estado, "recolectados": obtenidos, "rechazados": rechaz,
                      "nuevos": nuevos, "cambios_de_precio": cambios, "no_observados": no_obs})
    return pd.DataFrame(filas)


# --------------------------------------------------------------------------- canasta
def calcular_canasta(precios, cantidades):
    """Canasta con precios de UNA misma ejecución.
    precios: DataFrame con id_producto_comun, comercio, precio. cantidades: {id_producto_comun: cantidad > 0}.
    - El total de un comercio se calcula solo si tiene TODOS los productos; si falta alguno, se indica cuáles.
    - El costo mínimo compra cada producto donde es más barato; se compara con el mejor comercio único completo.
    - Si algún producto no tiene precio en ningún comercio, no se calcula el costo mínimo."""
    ids = [i for i, q in cantidades.items() if q and q > 0]
    sub = precios[precios.id_producto_comun.isin(ids)]
    comercios = sorted(precios.comercio.unique())
    totales = []
    for c in comercios:
        pc = sub[sub.comercio == c].drop_duplicates("id_producto_comun").set_index("id_producto_comun").precio
        faltan = [i for i in ids if i not in pc.index]
        total = None if faltan else float(sum(pc[i] * cantidades[i] for i in ids))
        totales.append({"comercio": c, "total": total, "completa": not faltan, "faltan": faltan})
    sin_precio = [i for i in ids if i not in set(sub.id_producto_comun)]
    res = {"totales": pd.DataFrame(totales), "sin_precio": sin_precio, "optima": pd.DataFrame(),
           "total_optimo": None, "mejor_comercio_unico": None, "ahorro_cop": None, "ahorro_pct": None}
    if not ids or sin_precio:
        return res
    mejores = sub.sort_values(["id_producto_comun", "precio", "comercio"]).drop_duplicates("id_producto_comun").copy()
    mejores["cantidad"] = mejores.id_producto_comun.map(cantidades)
    mejores["subtotal"] = mejores.precio * mejores.cantidad
    res["optima"] = mejores[["id_producto_comun", "comercio", "precio", "cantidad", "subtotal"]]
    res["total_optimo"] = float(mejores.subtotal.sum())
    completos = res["totales"][res["totales"].completa]
    if len(completos):
        mejor = completos.sort_values("total").iloc[0]
        res["mejor_comercio_unico"] = mejor.comercio
        res["ahorro_cop"] = float(mejor.total - res["total_optimo"])
        res["ahorro_pct"] = round(100.0 * res["ahorro_cop"] / mejor.total, 2) if mejor.total else 0.0
    return res
