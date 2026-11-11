"""
db.py - Capa de acceso a datos (SQLite) del comparador de precios.

Reglas de este módulo:
  * La interfaz (app.py) NO contiene SQL: solo llama a estas funciones.
  * Todo valor del usuario viaja como parámetro (?); jamás se concatena en el SQL.
    Lo único que se arma dinámicamente son marcadores "?" y fragmentos fijos del propio código.
  * Cada consulta abre la base en modo solo lectura y la cierra al terminar.
  * Los resultados se cachean con st.cache_data. Una conexión sqlite3 no se puede
    cachear/hashear, por eso las funciones reciben la RUTA de la base (`con` = ruta)
    y abren la conexión por dentro. Llame a `limpiar_cache()` al terminar una actualización.
  * Filtros e indicadores se calculan con SQL (no se lee la tabla completa a memoria).

`parametros` (dict, todas las claves opcionales):
    comercios: list[str], subcategorias: list[str], marcas: list[str],
    precio_min: float, precio_max: float, solo_promocion: bool, solo_comparables: bool,
    busqueda: str (máx. 60 caracteres), corrida_id: str, fecha_desde / fecha_hasta: str ISO,
    producto_id: int (solo para el histórico)
"""

import os
import sqlite3
from contextlib import closing, contextmanager

import pandas as pd
import streamlit as st

DB_PATH = os.environ.get("COMPARADOR_DB") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "comparador_precios.sqlite")
MAX_BUSQUEDA = 60
MAX_LISTA = 200          # tope de elementos por filtro de lista


# ----------------------------------------------------------------------------
# Conexión controlada
# ----------------------------------------------------------------------------
@contextmanager
def _conectar(db_path):
    """Abre la base en solo lectura y SIEMPRE la cierra (sqlite3.connect como `with` no cierra)."""
    uri = "file:" + os.path.abspath(db_path).replace("\\", "/") + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True)) as con:
        con.row_factory = sqlite3.Row
        yield con


def _df(db_path, sql, params=()):
    """Ejecuta una consulta parametrizada y devuelve un DataFrame."""
    with _conectar(db_path) as con:
        return pd.read_sql_query(sql, con, params=list(params))


def limpiar_cache():
    """Invalida el caché (llamar al terminar una actualización de precios)."""
    st.cache_data.clear()


# ----------------------------------------------------------------------------
# Validación de entradas y construcción de filtros
# ----------------------------------------------------------------------------
def _lista(valores):
    """Lista de textos acotada: solo str, sin vacíos, longitud limitada."""
    return [str(v)[:120] for v in (valores or []) if str(v).strip()][:MAX_LISTA]


def _like(texto):
    """Patrón LIKE seguro: se escapan %, _ y \\ para que el usuario no los use como comodines."""
    t = str(texto or "").strip()[:MAX_BUSQUEDA]
    for ch in ("\\", "%", "_"):
        t = t.replace(ch, "\\" + ch)
    return f"%{t}%" if t else None


def _where(p, col, busqueda_cols):
    """
    Construye (fragmento_sql, params) con los filtros combinables.
    `col` mapea el filtro a la columna de la consulta (nombres fijos del código, no del usuario).
    """
    p = p or {}
    partes, params = [], []

    for clave, nombre in (("comercios", "comercio"), ("subcategorias", "subcategoria"),
                          ("marcas", "marca")):
        vals = _lista(p.get(clave))
        if vals:
            partes.append(f"{col[nombre]} IN ({','.join('?' * len(vals))})")
            params += vals

    if p.get("precio_min") is not None:
        partes.append(f"{col['precio']} >= ?")
        params.append(float(p["precio_min"]))
    if p.get("precio_max") is not None:
        partes.append(f"{col['precio']} <= ?")
        params.append(float(p["precio_max"]))
    if p.get("solo_promocion"):
        partes.append(f"{col['promo']} = 1")
    if p.get("solo_comparables"):
        partes.append(f"{col['comparable']} = 1")
    if p.get("corrida_id"):
        partes.append(f"{col['corrida']} = ?")
        params.append(str(p["corrida_id"])[:60])
    if p.get("fecha_desde"):
        partes.append(f"{col['fecha']} >= ?")
        params.append(str(p["fecha_desde"])[:40])
    if p.get("fecha_hasta"):
        partes.append(f"{col['fecha']} <= ?")
        params.append(str(p["fecha_hasta"])[:40])
    if p.get("producto_id") is not None:
        partes.append(f"{col['producto']} = ?")
        params.append(int(p["producto_id"]))

    patron = _like(p.get("busqueda"))
    if patron:
        partes.append("(" + " OR ".join(f"{c} LIKE ? ESCAPE '\\'" for c in busqueda_cols) + ")")
        params += [patron] * len(busqueda_cols)

    return (" WHERE " + " AND ".join(partes)) if partes else "", params


# Mapeo de filtros sobre la vista v_ultimo_precio (indicadores y tabla)
_COL_UP = {"comercio": "comercio", "subcategoria": "subcategoria", "marca": "marca",
           "precio": "precio", "promo": "en_promocion", "comparable": "comparable",
           "corrida": "corrida_id", "fecha": "fecha_consulta", "producto": "producto_id"}
_BUSQ_UP = ["nombre_estandar", "texto_original"]

# Mapeo de filtros sobre las observaciones históricas
_COL_HIST = {"comercio": "c.nombre", "subcategoria": "a.subcategoria", "marca": "a.marca_estandar",
             "precio": "o.precio_cop", "promo": "o.en_promocion",
             "comparable": "(p.comparable = 1 AND a.comercio_id IN (SELECT comercio_id FROM seleccion))",
             "corrida": "e.corrida_id", "fecha": "o.fecha_consulta", "producto": "p.id"}
_BUSQ_HIST = ["a.nombre_estandar", "a.texto_original"]


# ----------------------------------------------------------------------------
# 1. Filtros
# ----------------------------------------------------------------------------
@st.cache_data(show_spinner=False)
def obtener_filtros(con=DB_PATH):
    """Listas únicas para los selectores: comercios, marcas, subcategorías (y ejecuciones)."""
    with _conectar(con) as c:
        uno = lambda sql: [r[0] for r in c.execute(sql)]
        return {
            "comercios": uno("SELECT nombre FROM comercios ORDER BY nombre"),
            "marcas": uno("""SELECT DISTINCT marca_estandar FROM anuncios
                              WHERE marca_estandar IS NOT NULL AND excluido = 0 ORDER BY 1"""),
            "subcategorias": uno("""SELECT DISTINCT subcategoria FROM anuncios
                                     WHERE subcategoria IS NOT NULL AND excluido = 0 ORDER BY 1"""),
            "ejecuciones": uno("""SELECT DISTINCT corrida_id FROM ejecuciones
                                   WHERE estado <> 'fallida' ORDER BY inicio DESC"""),
            "precio_max": (c.execute("SELECT MAX(precio_cop) FROM observaciones").fetchone()[0] or 0),
        }


# ----------------------------------------------------------------------------
# 2. Indicadores (6) calculados con SQL
# ----------------------------------------------------------------------------
@st.cache_data(show_spinner=False)
def obtener_indicadores(con, parametros=None):
    """
    Devuelve un dict con 6 indicadores, cada uno con su valor, unidad y ejecución/periodo:
      1 total_productos            - anuncios (último precio) que cumplen los filtros
      2 observaciones_por_comercio - DataFrame comercio / observaciones
      3 ultima_ejecucion           - fecha, estado e id de la última ejecución
      4 proporcion_promocion       - % de productos en promoción (último precio)
      5 mediana_subcategoria       - DataFrame subcategoria / mediana (COP)
      6 ahorro_maximo              - mayor ahorro entre comercios, misma ejecución (COP y %)
    """
    where, params = _where(parametros, _COL_UP, _BUSQ_UP)
    ind = {}

    with _conectar(con) as c:
        # 1 y 4: total de productos y proporción en promoción
        r = c.execute(f"""SELECT COUNT(*) AS total,
                                 100.0 * SUM(CASE WHEN en_promocion = 1 THEN 1 ELSE 0 END)
                                       / NULLIF(COUNT(*), 0) AS pct_promo
                            FROM v_ultimo_precio{where}""", params).fetchone()
        ind["total_productos"] = {"valor": r["total"], "unidad": "productos",
                                  "periodo": "último precio observado"}
        ind["proporcion_promocion"] = {"valor": r["pct_promo"], "unidad": "%",
                                       "periodo": "último precio observado"}

        # 2: observaciones por comercio (todas las ejecuciones; respeta filtros de comercio/marca/...)
        w2, p2 = _where(parametros, _COL_HIST, _BUSQ_HIST)
        ind["observaciones_por_comercio"] = pd.read_sql_query(
            f"""SELECT c.nombre AS comercio, COUNT(*) AS observaciones
                  FROM observaciones o
                  JOIN anuncios a    ON a.id = o.anuncio_id
                  JOIN comercios c   ON c.id = a.comercio_id
                  JOIN ejecuciones e ON e.id = o.ejecucion_id
                  LEFT JOIN productos p ON p.id = a.producto_id
                  {w2}
                 GROUP BY c.nombre ORDER BY observaciones DESC""", c, params=p2)

        # 3: última ejecución (id, fecha y estado)
        e = c.execute("""SELECT corrida_id, MAX(inicio) AS inicio,
                                GROUP_CONCAT(comercio || ': ' || estado, ' | ') AS estados
                           FROM ejecuciones
                          WHERE corrida_id = (SELECT corrida_id FROM ejecuciones
                                               ORDER BY inicio DESC, id DESC LIMIT 1)""").fetchone()
        ind["ultima_ejecucion"] = {"valor": e["inicio"], "corrida_id": e["corrida_id"],
                                   "estado": e["estados"], "unidad": "fecha ISO 8601 (Colombia)"}

        # 5: mediana de precio por subcategoría (SQLite no tiene MEDIAN: ventanas + promedio centrales)
        wm = (where + " AND " if where else " WHERE ") + "precio IS NOT NULL"
        ind["mediana_subcategoria"] = pd.read_sql_query(
            f"""WITH t AS (
                  SELECT subcategoria, precio,
                         ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS rn,
                         COUNT(*)     OVER (PARTITION BY subcategoria) AS n
                    FROM v_ultimo_precio{wm})
                SELECT subcategoria, AVG(precio) AS mediana_cop, MAX(n) AS productos
                  FROM t WHERE rn IN ((n + 1) / 2, (n + 2) / 2)
                 GROUP BY subcategoria ORDER BY mediana_cop DESC""", c, params=params)

        # 6: ahorro máximo entre comercios (misma presentación, misma ejecución, comparables)
        wa, pa_ = _where({k: v for k, v in (parametros or {}).items()
                          if k in ("comercios", "marcas", "subcategorias", "busqueda", "corrida_id")},
                         {"comercio": "comercio", "subcategoria": "subcategoria", "marca": "marca",
                          "precio": "precio", "promo": "en_promocion", "comparable": "1",
                          "corrida": "corrida_id", "fecha": "fecha_consulta", "producto": "producto_id"},
                         ["producto", "texto_original"])
        wa = (wa + " AND " if wa else " WHERE ") + "precio IS NOT NULL"
        if not (parametros or {}).get("corrida_id"):
            wa += " AND corrida_id = (SELECT corrida_id FROM ejecuciones WHERE estado <> 'fallida' ORDER BY inicio DESC, id DESC LIMIT 1)"
        a = c.execute(f"""SELECT producto, MAX(precio) - MIN(precio) AS ahorro_cop,
                                 100.0 * (MAX(precio) - MIN(precio)) / MAX(precio) AS ahorro_pct,
                                 MAX(corrida_id) AS corrida_id
                            FROM v_comparables{wa}
                           GROUP BY producto_id HAVING COUNT(DISTINCT comercio) > 1
                           ORDER BY ahorro_cop DESC LIMIT 1""", pa_).fetchone()
        ind["ahorro_maximo"] = ({"valor": a["ahorro_cop"], "porcentaje": a["ahorro_pct"],
                                 "producto": a["producto"], "corrida_id": a["corrida_id"],
                                 "unidad": "COP"} if a else
                                {"valor": None, "porcentaje": None, "producto": None,
                                 "corrida_id": None, "unidad": "COP"})
    return ind


# ----------------------------------------------------------------------------
# 3. Datos para los gráficos (histórico de precios)
# ----------------------------------------------------------------------------
@st.cache_data(show_spinner=False)
def obtener_datos_graficos(con, parametros=None):
    """
    Serie histórica: una fila por observación (comercio, producto, fecha, precio y precio unitario).
    Para la evolución de un producto comparable pase parametros["producto_id"]; el DataFrame trae
    una serie por comercio (columna `comercio`). El precio unitario usa la unidad normalizada
    (mL, g o unidad) y es NULL cuando no hay contenido: nunca se mezclan unidades.
    """
    w, p = _where(parametros, _COL_HIST, _BUSQ_HIST)
    w = (w + " AND " if w else " WHERE ") + "o.precio_cop IS NOT NULL AND a.excluido = 0"
    return _df(con, f"""
        SELECT c.nombre AS comercio, p.id AS producto_id,
               COALESCE(p.nombre_estandar, a.nombre_estandar) AS producto,
               a.subcategoria, a.marca_estandar AS marca,
               e.corrida_id, o.fecha_consulta, o.precio_cop AS precio, o.en_promocion,
               a.unidad_normalizada AS unidad,
               CASE WHEN a.contenido_normalizado > 0
                    THEN o.precio_cop / a.contenido_normalizado END AS precio_unitario
          FROM observaciones o
          JOIN anuncios    a ON a.id = o.anuncio_id
          JOIN comercios   c ON c.id = a.comercio_id
          JOIN ejecuciones e ON e.id = o.ejecucion_id
          LEFT JOIN productos p ON p.id = a.producto_id
          {w}
         ORDER BY o.fecha_consulta, c.nombre""", p)


# ----------------------------------------------------------------------------
# 4. Tabla filtrada y lista de productos comparables (usadas por la página Resumen)
# ----------------------------------------------------------------------------
@st.cache_data(show_spinner=False)
def obtener_tabla(con, parametros=None):
    """Último precio de cada anuncio que cumple los filtros (tabla, boxplot, precio unitario, promociones)."""
    w, p = _where(parametros, _COL_UP, _BUSQ_UP)
    return _df(con, f"""
        SELECT comercio, nombre_estandar AS nombre, marca, subcategoria,
               contenido_normalizado AS contenido, unidad_normalizada AS unidad,
               precio, precio_unitario, en_promocion, disponibilidad,
               fecha_consulta, url, producto_id, comparable
          FROM v_ultimo_precio{w}
         ORDER BY precio LIMIT 20000""", p)


@st.cache_data(show_spinner=False)
def obtener_productos_comparables(con):
    """Productos comparables (uno por producto_id) para el selector de evolución de precios."""
    return _df(con, """SELECT DISTINCT producto_id, marca, producto, contenido_normalizado AS contenido,
                              unidad_normalizada AS unidad
                         FROM v_comparables ORDER BY marca, producto""")


# ----------------------------------------------------------------------------
# 5. Ejecuciones, cambios de precio y precios para la canasta
# ----------------------------------------------------------------------------
@st.cache_data(show_spinner=False)
def obtener_ejecuciones(con):
    """Ejecuciones con datos (no fallidas), de la más reciente a la más antigua."""
    return _df(con, """SELECT corrida_id, MIN(inicio) AS fecha,
                              GROUP_CONCAT(comercio || ': ' || estado, ' | ') AS estados
                         FROM ejecuciones WHERE estado <> 'fallida'
                        GROUP BY corrida_id ORDER BY fecha DESC""")


@st.cache_data(show_spinner=False)
def obtener_cambios(con, corrida_antes, corrida_despues, comercios=None):
    """
    Compara el MISMO anuncio en el MISMO comercio entre dos ejecuciones.
    Solo entran comercios con ejecución válida en ambas (si no, todo saldría 'nuevo' sin ser cierto).
    estado: subió, bajó, igual, nuevo, no observado (no apareció; NO significa agotado),
            agotado (el sitio lo marca agotado), sin precio, sin precio anterior.
    """
    extra, p_extra = "", []
    vals = _lista(comercios)
    if vals:
        extra = f" AND c.nombre IN ({','.join('?' * len(vals))})"
        p_extra = vals
    ultima = """SELECT anuncio_id, precio_cop, disponibilidad, fecha_consulta FROM (
                  SELECT o.anuncio_id, o.precio_cop, o.disponibilidad, o.fecha_consulta,
                         ROW_NUMBER() OVER (PARTITION BY o.anuncio_id
                                            ORDER BY o.fecha_consulta DESC, o.id DESC) AS rn
                    FROM observaciones o JOIN ejecuciones e ON e.id = o.ejecucion_id
                   WHERE e.corrida_id = ?) WHERE rn = 1"""
    valida = """c.nombre IN (SELECT comercio FROM ejecuciones WHERE corrida_id = ? AND estado <> 'fallida')"""
    sql = f"""
        WITH a AS ({ultima}), b AS ({ultima})
        SELECT c.nombre AS comercio, an.id AS anuncio_id, an.nombre_estandar AS nombre,
               an.marca_estandar AS marca, an.url,
               a.precio_cop AS precio_antes, b.precio_cop AS precio_despues,
               b.precio_cop - a.precio_cop AS diferencia_cop,
               100.0 * (b.precio_cop - a.precio_cop) / NULLIF(a.precio_cop, 0) AS diferencia_pct,
               CASE WHEN a.anuncio_id IS NULL THEN 'nuevo'
                    WHEN b.anuncio_id IS NULL THEN 'no observado'
                    WHEN b.precio_cop IS NULL THEN
                         CASE WHEN b.disponibilidad = 'agotado' THEN 'agotado' ELSE 'sin precio' END
                    WHEN a.precio_cop IS NULL THEN 'sin precio anterior'
                    WHEN b.precio_cop > a.precio_cop THEN 'subió'
                    WHEN b.precio_cop < a.precio_cop THEN 'bajó' ELSE 'igual' END AS estado
          FROM anuncios an JOIN comercios c ON c.id = an.comercio_id
          LEFT JOIN a ON a.anuncio_id = an.id LEFT JOIN b ON b.anuncio_id = an.id
         WHERE an.excluido = 0 AND (a.anuncio_id IS NOT NULL OR b.anuncio_id IS NOT NULL)
           AND {valida} AND {valida}{extra}
         ORDER BY ABS(COALESCE(100.0 * (b.precio_cop - a.precio_cop) / NULLIF(a.precio_cop, 0), 0)) DESC"""
    return _df(con, sql, [corrida_antes, corrida_despues, corrida_antes, corrida_despues, *p_extra])


@st.cache_data(show_spinner=False)
def obtener_precios_canasta(con, corrida_id):
    """Precio de cada producto comparable en cada comercio, de UNA misma ejecución.
    Si un comercio tiene varios anuncios del mismo producto se toma el más barato.
    Los precios NULL (agotado / no extraído) no entran: cuentan como producto ausente."""
    return _df(con, """SELECT producto_id, MAX(marca) AS marca, MAX(producto) AS producto,
                              MAX(contenido_normalizado) AS contenido, MAX(unidad_normalizada) AS unidad,
                              comercio, MIN(precio) AS precio
                         FROM v_comparables
                        WHERE corrida_id = ? AND precio IS NOT NULL
                        GROUP BY producto_id, comercio""", [str(corrida_id)[:60]])
