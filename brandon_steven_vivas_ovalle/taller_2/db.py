"""
db.py - Capa de acceso a datos del comparador (Taller 2, Minería de Datos, UNAL).

Reglas de diseño
----------------
* La interfaz (app.py y paginas/) NO contiene SQL: todo pasa por las funciones de este módulo.
* Filtros, indicadores y agregaciones se calculan con SQL sobre SQLite (nunca se lee la tabla completa
  para filtrarla después en memoria).
* Todo valor que viene del usuario se pasa como PARÁMETRO ("?"). En el texto SQL solo se insertan
  marcadores "?" y nombres de vistas/columnas tomados de listas blancas fijas en este archivo.
* Las conexiones se abren con `abrir()` (context manager que SIEMPRE cierra) o con `conectar_escritura()`.
* No depende de Streamlit (el caché vive en servicios.py) ni del scraper.
"""
from __future__ import annotations

import os
import re
import sqlite3
import unicodedata
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

# Ruta relativa al archivo (no se usan rutas absolutas); se puede cambiar con la variable de entorno.
RUTA_DB_DEFECTO = Path(os.environ.get("COMPARADOR_DB") or Path(__file__).resolve().parent / "comparador_precios.sqlite")
ESTADOS_DISPONIBILIDAD = ("disponible", "agotado", "no_observado")

# --------------------------------------------------------------------------------------
# Esquema (idempotente: sirve para crear una base nueva y para actualizar la del Taller 1)
# --------------------------------------------------------------------------------------
TABLAS = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS comercios (
    comercio_id INTEGER PRIMARY KEY, clave TEXT UNIQUE NOT NULL, nombre TEXT NOT NULL, url_base TEXT);
CREATE TABLE IF NOT EXISTS ejecuciones (
    ejecucion_id TEXT NOT NULL, comercio_id INTEGER NOT NULL REFERENCES comercios(comercio_id),
    inicio TEXT NOT NULL, fin TEXT, n_registros INTEGER, n_sitio_reportado INTEGER,
    estado TEXT NOT NULL CHECK (estado IN ('completa','parcial','fallida')),
    modo TEXT CHECK (modo IN ('en_linea','sin_conexion')), modo_api TEXT, notas TEXT,
    n_rechazadas INTEGER DEFAULT 0,
    PRIMARY KEY (ejecucion_id, comercio_id));
CREATE TABLE IF NOT EXISTS productos (          -- identificador común entre comercios (solo comparables)
    producto_id INTEGER PRIMARY KEY, clave TEXT UNIQUE NOT NULL, grupo TEXT NOT NULL,
    nombre_std TEXT, marca_std TEXT, subcategoria_std TEXT, variante_std TEXT, etapa_std INTEGER,
    contenido_total REAL, unidad_base TEXT);
CREATE TABLE IF NOT EXISTS anuncios (           -- producto tal como aparece en un comercio
    anuncio_id INTEGER PRIMARY KEY, comercio_id INTEGER NOT NULL REFERENCES comercios(comercio_id),
    sku TEXT NOT NULL, product_id TEXT, ean TEXT, url TEXT NOT NULL,
    nombre_original TEXT NOT NULL, descripcion_original TEXT, ficha_tecnica_original TEXT,
    marca_original TEXT, categoria_sitio TEXT, via TEXT,
    marca_std TEXT, subcategoria_std TEXT, variante_std TEXT, etapa_std INTEGER,
    contenido_total REAL, unidad_base TEXT, unidades_por_paquete REAL,
    incluido INTEGER, motivo_descarte TEXT, inconsistencia_contenido INTEGER DEFAULT 0,
    clave TEXT, producto_id INTEGER REFERENCES productos(producto_id), comparable INTEGER DEFAULT 0,
    UNIQUE (comercio_id, sku));
CREATE TABLE IF NOT EXISTS observaciones (
    obs_id INTEGER PRIMARY KEY, ejecucion_id TEXT NOT NULL, comercio_id INTEGER NOT NULL,
    anuncio_id INTEGER NOT NULL REFERENCES anuncios(anuncio_id),
    fecha_hora_consulta TEXT NOT NULL, fecha_consulta TEXT NOT NULL,
    precio REAL CHECK (precio IS NULL OR precio > 0), precio_lista REAL,
    es_promocion INTEGER CHECK (es_promocion IN (0,1)), disponible INTEGER,
    estado_disponibilidad TEXT CHECK (estado_disponibilidad IN ('disponible','agotado')),
    raw_archivo TEXT,
    FOREIGN KEY (ejecucion_id, comercio_id) REFERENCES ejecuciones(ejecucion_id, comercio_id),
    UNIQUE (anuncio_id, fecha_hora_consulta));
CREATE TABLE IF NOT EXISTS correcciones (
    correccion_id INTEGER PRIMARY KEY, fecha TEXT NOT NULL, tabla TEXT NOT NULL, registro_id TEXT NOT NULL,
    campo TEXT NOT NULL, valor_anterior TEXT, valor_nuevo TEXT, motivo TEXT NOT NULL, autor TEXT);
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
    rechazo_id INTEGER PRIMARY KEY, ejecucion_id TEXT NOT NULL,
    comercio_id INTEGER NOT NULL REFERENCES comercios(comercio_id),
    sku TEXT, url TEXT, fecha_hora_consulta TEXT, precio REAL, disponible INTEGER,
    motivo TEXT NOT NULL, datos_json TEXT, fecha_rechazo TEXT NOT NULL);
"""

# Columnas que la base del Taller 1 no tiene: se agregan con ALTER TABLE si faltan.
COLUMNAS_NUEVAS = {
    "observaciones": [
        ("estado_disponibilidad", "TEXT CHECK (estado_disponibilidad IN ('disponible','agotado'))"),
        ("raw_archivo", "TEXT"),
    ],
    "ejecuciones": [("n_rechazadas", "INTEGER DEFAULT 0")],
}

INDICES = """
CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_ejec_anuncio ON observaciones(ejecucion_id, anuncio_id);
CREATE INDEX IF NOT EXISTS ix_obs_ejec ON observaciones(ejecucion_id, comercio_id);
CREATE INDEX IF NOT EXISTS ix_obs_anuncio_fecha ON observaciones(anuncio_id, fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS ix_obs_fecha ON observaciones(fecha_consulta);
CREATE INDEX IF NOT EXISTS ix_obs_precio ON observaciones(precio);
CREATE INDEX IF NOT EXISTS ix_anu_filtros ON anuncios(comercio_id, incluido, subcategoria_std, marca_std);
CREATE INDEX IF NOT EXISTS ix_anu_producto ON anuncios(producto_id);
CREATE INDEX IF NOT EXISTS ix_anu_comparable ON anuncios(comparable, incluido);
CREATE INDEX IF NOT EXISTS ix_anu_clave ON anuncios(clave);
CREATE INDEX IF NOT EXISTS ix_ejec_comercio ON ejecuciones(comercio_id, estado, inicio);
CREATE INDEX IF NOT EXISTS ix_rech_ejec ON observaciones_rechazadas(ejecucion_id, comercio_id);
CREATE INDEX IF NOT EXISTS ix_corr_registro ON correcciones(tabla, registro_id);
"""

VISTAS = {
    # Una fila por ejecución (agrega los comercios).
    "v_ejecuciones_resumen": """
        SELECT e.ejecucion_id,
               MIN(e.inicio) AS inicio, MAX(COALESCE(e.fin, e.inicio)) AS fin, substr(MIN(e.inicio), 1, 10) AS fecha,
               COUNT(*) AS n_comercios,
               SUM(e.estado = 'completa') AS n_completas, SUM(e.estado = 'parcial') AS n_parciales,
               SUM(e.estado = 'fallida') AS n_fallidas, SUM(COALESCE(e.n_registros, 0)) AS n_registros,
               CASE WHEN SUM(e.estado = 'completa') = (SELECT COUNT(*) FROM comercios) THEN 1 ELSE 0 END AS es_completa,
               CASE WHEN SUM(e.estado = 'completa') = (SELECT COUNT(*) FROM comercios) THEN 'completa'
                    WHEN SUM(e.estado IN ('completa', 'parcial')) > 0 THEN 'parcial' ELSE 'fallida' END AS estado,
               GROUP_CONCAT(DISTINCT e.modo) AS modo
        FROM ejecuciones e GROUP BY e.ejecucion_id""",
    # Última ejecución NO fallida de cada comercio.
    "v_ultima_ejecucion_comercio": """
        SELECT e.comercio_id, e.ejecucion_id, e.inicio, e.estado
        FROM ejecuciones e
        WHERE e.estado <> 'fallida'
          AND e.inicio = (SELECT MAX(e2.inicio) FROM ejecuciones e2
                          WHERE e2.comercio_id = e.comercio_id AND e2.estado <> 'fallida')""",
    # Detalle observación + anuncio + comercio (solo anuncios dentro de la categoría delimitada).
    "v_observaciones": """
        SELECT o.obs_id, o.ejecucion_id, o.comercio_id, c.clave AS comercio_clave, c.nombre AS comercio,
               o.anuncio_id, a.sku, a.nombre_original, a.descripcion_original, a.marca_original,
               COALESCE(a.marca_std, a.marca_original) AS marca, a.subcategoria_std AS subcategoria,
               a.variante_std, a.etapa_std, a.contenido_total, a.unidad_base,
               CASE WHEN a.contenido_total IS NOT NULL
                    THEN printf('%g %s', a.contenido_total, COALESCE(a.unidad_base, '')) END AS presentacion,
               a.incluido, a.comparable, a.producto_id, p.nombre_std AS producto_comparable, a.url, a.categoria_sitio,
               o.fecha_hora_consulta, o.fecha_consulta, o.precio, o.precio_lista, o.es_promocion,
               COALESCE(o.estado_disponibilidad, CASE WHEN o.disponible = 1 THEN 'disponible' ELSE 'agotado' END)
                   AS estado_disponibilidad,
               CASE WHEN o.precio IS NOT NULL AND a.contenido_total > 0 THEN o.precio / a.contenido_total END
                   AS precio_unitario,
               o.raw_archivo
        FROM observaciones o
        JOIN anuncios a ON a.anuncio_id = o.anuncio_id
        JOIN comercios c ON c.comercio_id = o.comercio_id
        LEFT JOIN productos p ON p.producto_id = a.producto_id
        WHERE a.incluido = 1""",
    # Observación más reciente de cada anuncio, dentro de la última ejecución de su comercio.
    "v_ultimo_precio": """
        SELECT v.* FROM v_observaciones v
        JOIN v_ultima_ejecucion_comercio u ON u.comercio_id = v.comercio_id AND u.ejecucion_id = v.ejecucion_id""",
    # Una fila por ejecución x comercio x producto comparable (mejor precio disponible).
    "v_comparables": """
        SELECT ejecucion_id, comercio_id, comercio, producto_id, producto_comparable AS nombre_std, subcategoria,
               contenido_total, unidad_base, anuncio_id, precio, COALESCE(precio_lista, precio) AS precio_regular,
               precio_unitario, es_promocion AS en_promocion, fecha_hora_consulta, fecha_consulta, url, n_anuncios
        FROM (SELECT v.*,
                     ROW_NUMBER() OVER (PARTITION BY v.ejecucion_id, v.comercio_id, v.producto_id
                                        ORDER BY v.precio, v.anuncio_id) AS rn,
                     COUNT(*) OVER (PARTITION BY v.ejecucion_id, v.comercio_id, v.producto_id) AS n_anuncios
              FROM v_observaciones v
              WHERE v.comparable = 1 AND v.precio IS NOT NULL AND v.estado_disponibilidad = 'disponible')
        WHERE rn = 1""",
    # Cambios de precio del MISMO anuncio entre observaciones consecutivas.
    "v_cambios_precio": """
        SELECT v.ejecucion_id, v.comercio_id, v.comercio, v.anuncio_id, v.sku, v.nombre_original, v.marca,
               v.subcategoria, v.producto_id, v.comparable, t.ejecucion_anterior, t.fecha_anterior,
               t.precio_anterior, v.precio AS precio_nuevo, v.fecha_hora_consulta,
               v.precio - t.precio_anterior AS variacion_cop,
               100.0 * (v.precio - t.precio_anterior) / t.precio_anterior AS variacion_pct
        FROM (SELECT obs_id,
                     LAG(precio) OVER (PARTITION BY anuncio_id ORDER BY fecha_hora_consulta) AS precio_anterior,
                     LAG(ejecucion_id) OVER (PARTITION BY anuncio_id ORDER BY fecha_hora_consulta) AS ejecucion_anterior,
                     LAG(fecha_hora_consulta) OVER (PARTITION BY anuncio_id ORDER BY fecha_hora_consulta) AS fecha_anterior
              FROM v_observaciones WHERE precio IS NOT NULL AND estado_disponibilidad = 'disponible') t
        JOIN v_observaciones v ON v.obs_id = t.obs_id
        WHERE t.precio_anterior IS NOT NULL AND ABS(v.precio - t.precio_anterior) > 0.5""",
    # Tres estados: disponible, agotado (lo dice el sitio) y no_observado (el anuncio no apareció en la ejecución).
    # Solo se evalúan ejecuciones no fallidas y anuncios vistos por primera vez en o antes de esa ejecución.
    "v_disponibilidad": """
        SELECT e.ejecucion_id, e.comercio_id, a.anuncio_id, a.producto_id, a.comparable,
               CASE WHEN o.obs_id IS NULL THEN 'no_observado'
                    ELSE COALESCE(o.estado_disponibilidad, CASE WHEN o.disponible = 1 THEN 'disponible' ELSE 'agotado' END)
               END AS estado
        FROM ejecuciones e
        JOIN anuncios a ON a.comercio_id = e.comercio_id AND a.incluido = 1
        LEFT JOIN observaciones o ON o.anuncio_id = a.anuncio_id AND o.ejecucion_id = e.ejecucion_id
        WHERE e.estado IN ('completa', 'parcial')
          AND (SELECT MIN(f.fecha_hora_consulta) FROM observaciones f WHERE f.anuncio_id = a.anuncio_id)
              <= COALESCE(e.fin, e.inicio)""",
    # Vista del Taller 1 (se conserva para que el documento del Taller 1 siga reproduciéndose).
    "v_precios_comparables": """
        SELECT o.ejecucion_id, c.nombre AS comercio, p.producto_id, p.nombre_std, p.grupo, p.contenido_total,
               p.unidad_base, MIN(o.precio) AS precio, MIN(COALESCE(o.precio_lista, o.precio)) AS precio_regular,
               COUNT(*) AS n_observaciones, MAX(o.es_promocion) AS alguna_promocion
        FROM observaciones o
        JOIN anuncios a ON a.anuncio_id = o.anuncio_id AND a.comparable = 1
        JOIN productos p ON p.producto_id = a.producto_id
        JOIN comercios c ON c.comercio_id = o.comercio_id
        WHERE o.precio IS NOT NULL AND o.disponible = 1
        GROUP BY o.ejecucion_id, c.comercio_id, p.producto_id""",
}
# Orden de creación (las vistas que dependen de otras van después).
ORDEN_VISTAS = ["v_ejecuciones_resumen", "v_ultima_ejecucion_comercio", "v_observaciones", "v_ultimo_precio",
                "v_comparables", "v_cambios_precio", "v_disponibilidad", "v_precios_comparables"]


def _sin_acentos(s) -> str:
    """Minúsculas y sin tildes: función SQL `norm(x)` para búsquedas que ignoran mayúsculas y acentos."""
    s = unicodedata.normalize("NFKD", str(s or ""))
    return "".join(c for c in s if not unicodedata.combining(c)).lower()


def _registrar_funciones(con: sqlite3.Connection) -> None:
    con.create_function("norm", 1, _sin_acentos, deterministic=True)


def _agregar_columnas_faltantes(con: sqlite3.Connection) -> None:
    for tabla, columnas in COLUMNAS_NUEVAS.items():
        existentes = {r[1] for r in con.execute(f"PRAGMA table_info({tabla})")}
        for nombre, definicion in columnas:
            if nombre not in existentes:
                con.execute(f"ALTER TABLE {tabla} ADD COLUMN {nombre} {definicion}")


def preparar_base(con: sqlite3.Connection) -> None:
    """Crea/actualiza tablas, columnas, índices y vistas. Idempotente. No borra ni modifica datos,
    salvo completar `estado_disponibilidad` (derivado de `disponible`) donde esté vacío."""
    con.executescript(TABLAS)
    _agregar_columnas_faltantes(con)
    con.execute("""UPDATE observaciones SET estado_disponibilidad =
                   CASE WHEN disponible = 1 THEN 'disponible' ELSE 'agotado' END
                   WHERE estado_disponibilidad IS NULL""")
    con.executescript(INDICES)
    for nombre in reversed(ORDEN_VISTAS):
        con.execute(f"DROP VIEW IF EXISTS {nombre}")
    for nombre in ORDEN_VISTAS:
        con.execute(f"CREATE VIEW {nombre} AS {VISTAS[nombre]}")
    if con.in_transaction:
        con.commit()


# --------------------------------------------------------------------------------------
# Conexiones
# --------------------------------------------------------------------------------------
def _uri_solo_lectura(ruta: Path) -> str:
    return Path(ruta).resolve().as_uri() + "?mode=ro"


@contextmanager
def abrir(ruta=None):
    """Conexión de SOLO LECTURA que siempre se cierra al salir del bloque `with`."""
    ruta = Path(ruta or RUTA_DB_DEFECTO)
    if not ruta.exists():
        raise FileNotFoundError(f"No se encontró la base de datos: {ruta.name}")
    con = sqlite3.connect(_uri_solo_lectura(ruta), uri=True, timeout=30)
    try:
        _registrar_funciones(con)
        con.row_factory = sqlite3.Row
        yield con
    finally:
        con.close()


def conectar_escritura(ruta=None, preparar: bool = True) -> sqlite3.Connection:
    """Conexión de escritura en modo autocommit: las transacciones se controlan explícitamente con
    BEGIN/COMMIT/ROLLBACK. Quien la abre debe cerrarla."""
    ruta = Path(ruta or RUTA_DB_DEFECTO)
    con = sqlite3.connect(ruta, timeout=30, isolation_level=None)
    con.execute("PRAGMA foreign_keys = ON")
    _registrar_funciones(con)
    if preparar:
        preparar_base(con)
    return con


def _df(con, sql: str, params=()) -> pd.DataFrame:
    return pd.read_sql_query(sql, con, params=list(params))


def esquema_listo(ruta=None) -> bool:
    """True si la base tiene las tablas y vistas que usa la aplicación."""
    try:
        with abrir(ruta) as con:
            nombres = {r[0] for r in con.execute("SELECT name FROM sqlite_master")}
            return set(VISTAS) <= nombres and {"correcciones", "observaciones_rechazadas"} <= nombres
    except (sqlite3.Error, FileNotFoundError):
        return False


def version_datos(con) -> str:
    """Huella barata de los datos; cambia al insertar observaciones o ejecuciones (clave de caché)."""
    o = con.execute("SELECT COUNT(*), COALESCE(MAX(obs_id), 0) FROM observaciones").fetchone()
    e = con.execute("SELECT COUNT(*), COALESCE(MAX(fin), '') FROM ejecuciones").fetchone()
    c = con.execute("SELECT COUNT(*) FROM correcciones").fetchone()
    return f"{o[0]}-{o[1]}-{e[0]}-{e[1]}-{c[0]}"


# --------------------------------------------------------------------------------------
# Filtros
# --------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Filtros:
    """Filtros combinables del panel lateral. Todos los campos son opcionales (vacío = sin filtro)."""
    comercios: tuple = ()
    subcategorias: tuple = ()
    marcas: tuple = ()
    precio_min: float | None = None
    precio_max: float | None = None
    ejecucion_id: str | None = None        # None = última ejecución de cada comercio
    fecha_desde: str | None = None         # 'AAAA-MM-DD'
    fecha_hasta: str | None = None
    solo_promociones: bool = False
    solo_comparables: bool = False
    busqueda: str = ""


_FUENTES = {"ultimo": "v_ultimo_precio", "todas": "v_observaciones"}   # lista blanca de vistas


def _fuente(f: Filtros) -> str:
    return _FUENTES["ultimo"] if f.ejecucion_id is None else _FUENTES["todas"]


def _escapar_like(s: str) -> str:
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _marcadores(valores) -> str:
    return ",".join("?" * len(valores))


def _condiciones(f: Filtros) -> tuple[str, list]:
    """Devuelve (texto WHERE, parámetros). Solo se escriben marcadores '?' en el texto."""
    cond, params = [], []
    if f.comercios:
        cond.append(f"comercio IN ({_marcadores(f.comercios)})")
        params += list(f.comercios)
    if f.subcategorias:
        cond.append(f"subcategoria IN ({_marcadores(f.subcategorias)})")
        params += list(f.subcategorias)
    if f.marcas:
        cond.append(f"marca IN ({_marcadores(f.marcas)})")
        params += list(f.marcas)
    if f.precio_min is not None:
        cond.append("precio >= ?")
        params.append(float(f.precio_min))
    if f.precio_max is not None:
        cond.append("precio <= ?")
        params.append(float(f.precio_max))
    if f.ejecucion_id is not None:
        cond.append("ejecucion_id = ?")
        params.append(f.ejecucion_id)
    if f.fecha_desde:
        cond.append("fecha_consulta >= ?")
        params.append(f.fecha_desde)
    if f.fecha_hasta:
        cond.append("fecha_consulta <= ?")
        params.append(f.fecha_hasta)
    if f.solo_promociones:
        cond.append("es_promocion = 1")
    if f.solo_comparables:
        cond.append("comparable = 1")
    for palabra in f.busqueda.split():
        patron = f"%{_escapar_like(_sin_acentos(palabra))}%"
        cond.append("(norm(nombre_original) LIKE ? ESCAPE '\\' OR norm(COALESCE(descripcion_original, '')) LIKE ? ESCAPE '\\')")
        params += [patron, patron]
    return (" WHERE " + " AND ".join(cond)) if cond else "", params


# --------------------------------------------------------------------------------------
# Catálogos para la interfaz
# --------------------------------------------------------------------------------------
def opciones_filtros(con) -> dict:
    comercios = [r[0] for r in con.execute("SELECT nombre FROM comercios ORDER BY nombre")]
    subcats = [r[0] for r in con.execute(
        "SELECT DISTINCT subcategoria FROM v_observaciones WHERE subcategoria IS NOT NULL ORDER BY 1")]
    marcas = [r[0] for r in con.execute(
        "SELECT marca, COUNT(*) n FROM v_ultimo_precio WHERE marca IS NOT NULL GROUP BY marca ORDER BY n DESC, marca")]
    pr = con.execute("SELECT MIN(precio), MAX(precio), MIN(fecha_consulta), MAX(fecha_consulta) FROM v_observaciones").fetchone()
    return {"comercios": comercios, "subcategorias": subcats, "marcas": marcas,
            "precio_min": float(pr[0] or 0), "precio_max": float(pr[1] or 0),
            "fecha_min": pr[2], "fecha_max": pr[3]}


def ejecuciones(con) -> pd.DataFrame:
    return _df(con, "SELECT * FROM v_ejecuciones_resumen ORDER BY inicio DESC")


def detalle_ejecuciones(con) -> pd.DataFrame:
    return _df(con, """SELECT e.ejecucion_id, c.nombre AS comercio, e.inicio, e.fin, e.estado, e.modo, e.modo_api,
                              e.n_registros, e.n_sitio_reportado, e.n_rechazadas, e.notas
                       FROM ejecuciones e JOIN comercios c ON c.comercio_id = e.comercio_id
                       ORDER BY e.inicio DESC, c.nombre""")


def ultima_ejecucion(con) -> dict | None:
    r = con.execute("SELECT * FROM v_ejecuciones_resumen ORDER BY inicio DESC LIMIT 1").fetchone()
    return dict(r) if r else None


def ultima_ejecucion_completa(con) -> str | None:
    r = con.execute("SELECT ejecucion_id FROM v_ejecuciones_resumen WHERE es_completa = 1 "
                    "ORDER BY inicio DESC LIMIT 1").fetchone()
    if r:
        return r[0]
    r = con.execute("SELECT ejecucion_id FROM v_ejecuciones_resumen WHERE estado <> 'fallida' "
                    "ORDER BY inicio DESC LIMIT 1").fetchone()
    return r[0] if r else None


def ejecucion_referencia(con, f: Filtros) -> str | None:
    """Ejecución sobre la que se calculan los indicadores comparativos."""
    return f.ejecucion_id or ultima_ejecucion_completa(con)


# --------------------------------------------------------------------------------------
# Tabla e indicadores (todo con SQL)
# --------------------------------------------------------------------------------------
COLUMNAS_TABLA = ["comercio", "nombre_original", "marca", "subcategoria", "presentacion", "precio", "precio_lista",
                  "precio_unitario", "unidad_base", "es_promocion", "estado_disponibilidad", "comparable",
                  "fecha_hora_consulta", "ejecucion_id", "url"]
ORDENES = {"precio": "precio", "precio_unitario": "precio_unitario", "nombre": "nombre_original",
           "comercio": "comercio", "fecha": "fecha_hora_consulta"}   # lista blanca de columnas de orden


def tabla_productos(con, f: Filtros, orden: str = "nombre", descendente: bool = False, limite: int = 5000) -> pd.DataFrame:
    where, params = _condiciones(f)
    col = ORDENES.get(orden, "nombre_original")
    sentido = "DESC" if descendente else "ASC"
    sql = (f"SELECT {', '.join(COLUMNAS_TABLA)} FROM {_fuente(f)}{where} "
           f"ORDER BY {col} {sentido}, anuncio_id LIMIT ?")
    return _df(con, sql, params + [int(limite)])


def conteo_seleccion(con, f: Filtros) -> pd.DataFrame:
    """Productos (anuncios únicos) y observaciones por comercio en la selección."""
    where, params = _condiciones(f)
    return _df(con, f"""SELECT comercio, COUNT(DISTINCT anuncio_id) AS productos, COUNT(*) AS observaciones,
                               SUM(precio IS NOT NULL) AS con_precio
                        FROM {_fuente(f)}{where} GROUP BY comercio ORDER BY comercio""", params)


def indicador_promocion(con, f: Filtros) -> dict:
    where, params = _condiciones(f)
    extra = (" AND " if where else " WHERE ") + "precio IS NOT NULL"
    r = con.execute(f"SELECT COUNT(*), COALESCE(SUM(es_promocion), 0) FROM {_fuente(f)}{where}{extra}", params).fetchone()
    n, promo = r[0], r[1]
    return {"con_precio": n, "en_promocion": promo, "pct": (100.0 * promo / n) if n else None}


def mediana_precio(con, f: Filtros) -> pd.DataFrame:
    """Mediana de precio (COP) por subcategoría, calculada en SQL (SQLite no trae MEDIAN)."""
    where, params = _condiciones(f)
    extra = (" AND " if where else " WHERE ") + "precio IS NOT NULL AND subcategoria IS NOT NULL"
    sql = f"""
        SELECT subcategoria, AVG(precio) AS mediana, MAX(cnt) AS n
        FROM (SELECT subcategoria, precio,
                     ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS rn,
                     COUNT(*) OVER (PARTITION BY subcategoria) AS cnt
              FROM {_fuente(f)}{where}{extra})
        WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
        GROUP BY subcategoria ORDER BY subcategoria"""
    return _df(con, sql, params)


def mediana_global(con, f: Filtros) -> float | None:
    where, params = _condiciones(f)
    extra = (" AND " if where else " WHERE ") + "precio IS NOT NULL"
    sql = f"""SELECT AVG(precio) FROM (SELECT precio, ROW_NUMBER() OVER (ORDER BY precio) AS rn, COUNT(*) OVER () AS cnt
                                       FROM {_fuente(f)}{where}{extra}) WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)"""
    v = con.execute(sql, params).fetchone()[0]
    return float(v) if v is not None else None


def ahorro_por_producto(con, ejecucion_id: str | None) -> pd.DataFrame:
    """Por producto comparable: precio mínimo, máximo, ahorro (COP y %) y comercio(s) más barato(s) (con empates)."""
    if not ejecucion_id:
        return pd.DataFrame()
    return _df(con, """
        WITH m AS (SELECT producto_id, nombre_std, unidad_base, MIN(precio) AS minimo, MAX(precio) AS maximo,
                          COUNT(*) AS n_comercios
                   FROM v_comparables WHERE ejecucion_id = ? GROUP BY producto_id)
        SELECT m.producto_id, m.nombre_std, m.unidad_base, m.minimo, m.maximo, m.n_comercios,
               m.maximo - m.minimo AS ahorro_cop,
               CASE WHEN m.maximo > 0 THEN 100.0 * (m.maximo - m.minimo) / m.maximo END AS ahorro_pct,
               (SELECT GROUP_CONCAT(v.comercio, ', ') FROM v_comparables v
                 WHERE v.ejecucion_id = ? AND v.producto_id = m.producto_id AND v.precio = m.minimo) AS mas_baratos
        FROM m WHERE m.n_comercios >= 2 ORDER BY ahorro_cop DESC, m.nombre_std""", [ejecucion_id, ejecucion_id])


def cambios_ultima_ejecucion(con) -> dict:
    """Cambios de precio y productos no observados en la última ejecución de cada comercio."""
    cambios = con.execute("""SELECT COUNT(*) FROM v_cambios_precio c
                             JOIN v_ultima_ejecucion_comercio u ON u.comercio_id = c.comercio_id
                                                               AND u.ejecucion_id = c.ejecucion_id""").fetchone()[0]
    no_obs = con.execute("""SELECT COUNT(*) FROM v_disponibilidad d
                            JOIN v_ultima_ejecucion_comercio u ON u.comercio_id = d.comercio_id
                                                              AND u.ejecucion_id = d.ejecucion_id
                            WHERE d.estado = 'no_observado'""").fetchone()[0]
    return {"cambios_precio": cambios, "no_observados": no_obs}


def disponibilidad_resumen(con, ejecucion_id: str) -> pd.DataFrame:
    return _df(con, """SELECT c.nombre AS comercio, d.estado, COUNT(*) AS n
                       FROM v_disponibilidad d JOIN comercios c ON c.comercio_id = d.comercio_id
                       WHERE d.ejecucion_id = ? GROUP BY c.nombre, d.estado ORDER BY c.nombre, d.estado""", [ejecucion_id])


# --------------------------------------------------------------------------------------
# Gráficos
# --------------------------------------------------------------------------------------
def productos_comparables(con) -> pd.DataFrame:
    return _df(con, """SELECT p.producto_id, p.nombre_std, p.subcategoria_std AS subcategoria, p.contenido_total, p.unidad_base
                       FROM productos p WHERE EXISTS (SELECT 1 FROM anuncios a WHERE a.producto_id = p.producto_id AND a.comparable = 1)
                       ORDER BY p.subcategoria_std, p.nombre_std""")


def serie_precio_producto(con, producto_id: int) -> pd.DataFrame:
    """Evolución del precio de un producto comparable: una serie por comercio."""
    return _df(con, """SELECT comercio, ejecucion_id, fecha_hora_consulta, precio, precio_unitario, unidad_base, en_promocion
                       FROM v_comparables WHERE producto_id = ? ORDER BY fecha_hora_consulta, comercio""", [int(producto_id)])


def precio_unitario_comparables(con, ejecucion_id: str | None) -> pd.DataFrame:
    if not ejecucion_id:
        return pd.DataFrame()
    return _df(con, """SELECT comercio, nombre_std, subcategoria, unidad_base, contenido_total, precio, precio_unitario
                       FROM v_comparables WHERE ejecucion_id = ? AND precio_unitario IS NOT NULL
                       ORDER BY unidad_base, nombre_std, comercio""", [ejecucion_id])


def distribucion_precios(con, f: Filtros) -> pd.DataFrame:
    where, params = _condiciones(f)
    extra = (" AND " if where else " WHERE ") + "precio IS NOT NULL"
    return _df(con, f"SELECT comercio, subcategoria, nombre_original, precio FROM {_fuente(f)}{where}{extra}", params)


def sobreprecio_comparables(con, ejecucion_id: str | None) -> pd.DataFrame:
    """Para cada producto y comercio: cuánto más caro (%) es frente al comercio más barato de ese producto."""
    if not ejecucion_id:
        return pd.DataFrame()
    return _df(con, """
        SELECT v.comercio, v.nombre_std, v.precio, m.minimo,
               100.0 * (v.precio - m.minimo) / m.minimo AS sobreprecio_pct
        FROM v_comparables v
        JOIN (SELECT producto_id, MIN(precio) AS minimo FROM v_comparables WHERE ejecucion_id = ?
              GROUP BY producto_id HAVING COUNT(*) >= 2) m ON m.producto_id = v.producto_id
        WHERE v.ejecucion_id = ? ORDER BY v.nombre_std, v.comercio""", [ejecucion_id, ejecucion_id])


# --------------------------------------------------------------------------------------
# Comparación entre dos ejecuciones
# --------------------------------------------------------------------------------------
def cambios_entre_ejecuciones(con, ejec_anterior: str, ejec_nueva: str, umbral_pct: float = 5.0,
                              solo_comparables: bool = False, comercios: tuple = ()) -> pd.DataFrame:
    """
    Compara el MISMO anuncio del MISMO comercio entre dos ejecuciones. Solo se evalúan los comercios con datos
    (no fallidos) en ambas ejecuciones. Resultado: una fila por anuncio con `tipo`:
      subió | bajó | sin cambio | nuevo | dejó de observarse | sin precio en alguna ejecución
    """
    cond, params = "", [ejec_anterior, ejec_nueva]          # los dos '?' de los JOIN con ejecuciones
    if solo_comparables:
        cond += " AND a.comparable = 1"
    if comercios:
        cond += f" AND c.nombre IN ({_marcadores(comercios)})"
        params += list(comercios)
    sql = f"""
        SELECT c.nombre AS comercio, a.anuncio_id, a.sku, a.nombre_original,
               COALESCE(a.marca_std, a.marca_original) AS marca, a.subcategoria_std AS subcategoria, a.comparable, a.url,
               oa.precio AS precio_anterior, ob.precio AS precio_nuevo,
               ob.precio - oa.precio AS variacion_cop,
               CASE WHEN oa.precio > 0 THEN 100.0 * (ob.precio - oa.precio) / oa.precio END AS variacion_pct,
               CASE WHEN oa.obs_id IS NULL THEN 'nuevo'
                    WHEN ob.obs_id IS NULL THEN 'dejó de observarse'
                    WHEN oa.precio IS NULL OR ob.precio IS NULL THEN 'sin precio en alguna ejecución'
                    WHEN ob.precio > oa.precio + 0.5 THEN 'subió'
                    WHEN ob.precio < oa.precio - 0.5 THEN 'bajó'
                    ELSE 'sin cambio' END AS tipo
        FROM anuncios a
        JOIN comercios c ON c.comercio_id = a.comercio_id
        JOIN ejecuciones ea ON ea.ejecucion_id = ? AND ea.comercio_id = a.comercio_id AND ea.estado <> 'fallida'
        JOIN ejecuciones eb ON eb.ejecucion_id = ? AND eb.comercio_id = a.comercio_id AND eb.estado <> 'fallida'
        LEFT JOIN observaciones oa ON oa.anuncio_id = a.anuncio_id AND oa.ejecucion_id = ea.ejecucion_id
        LEFT JOIN observaciones ob ON ob.anuncio_id = a.anuncio_id AND ob.ejecucion_id = eb.ejecucion_id
        WHERE a.incluido = 1 AND (oa.obs_id IS NOT NULL OR ob.obs_id IS NOT NULL){cond}
        ORDER BY ABS(COALESCE(100.0 * (ob.precio - oa.precio) / NULLIF(oa.precio, 0), 0)) DESC, c.nombre, a.nombre_original"""
    df = _df(con, sql, params)
    df["variacion_grande"] = (df["variacion_pct"].abs() >= float(umbral_pct)).fillna(False)
    return df


def comercios_sin_comparacion(con, ejec_anterior: str, ejec_nueva: str) -> list[str]:
    """Comercios que no tienen datos válidos en alguna de las dos ejecuciones (no se pueden comparar)."""
    filas = con.execute("""
        SELECT c.nombre FROM comercios c
        WHERE NOT EXISTS (SELECT 1 FROM ejecuciones e WHERE e.ejecucion_id = ? AND e.comercio_id = c.comercio_id AND e.estado <> 'fallida')
           OR NOT EXISTS (SELECT 1 FROM ejecuciones e WHERE e.ejecucion_id = ? AND e.comercio_id = c.comercio_id AND e.estado <> 'fallida')
        ORDER BY c.nombre""", [ejec_anterior, ejec_nueva]).fetchall()
    return [r[0] for r in filas]


# --------------------------------------------------------------------------------------
# Canasta
# --------------------------------------------------------------------------------------
def _valores_canasta(items: dict) -> tuple[str, list]:
    pares = [(int(k), float(v)) for k, v in items.items()]
    return ",".join("(?,?)" for _ in pares), [x for par in pares for x in par]


def canasta_detalle(con, ejecucion_id: str, items: dict) -> pd.DataFrame:
    """Una fila por comercio x producto elegido; precio NULL si el comercio no lo tiene en esa ejecución."""
    if not items:
        return pd.DataFrame()
    valores, params = _valores_canasta(items)
    return _df(con, f"""
        WITH sel(producto_id, cantidad) AS (VALUES {valores})
        SELECT c.nombre AS comercio, p.producto_id, p.nombre_std, sel.cantidad, v.precio,
               v.precio * sel.cantidad AS subtotal
        FROM comercios c CROSS JOIN sel
        JOIN productos p ON p.producto_id = sel.producto_id
        LEFT JOIN v_comparables v ON v.comercio_id = c.comercio_id AND v.producto_id = sel.producto_id
                                 AND v.ejecucion_id = ?
        ORDER BY c.nombre, p.nombre_std""", params + [ejecucion_id])


def canasta_totales(con, ejecucion_id: str, items: dict) -> pd.DataFrame:
    """Costo de la canasta por comercio. `total` es NULL si al comercio le falta algún producto (nunca un total parcial)."""
    if not items:
        return pd.DataFrame()
    valores, params = _valores_canasta(items)
    return _df(con, f"""
        WITH sel(producto_id, cantidad) AS (VALUES {valores}),
        d AS (SELECT c.nombre AS comercio, sel.producto_id, sel.cantidad, v.precio
              FROM comercios c CROSS JOIN sel
              LEFT JOIN v_comparables v ON v.comercio_id = c.comercio_id AND v.producto_id = sel.producto_id
                                       AND v.ejecucion_id = ?)
        SELECT comercio, COUNT(*) AS n_seleccionados, COUNT(precio) AS n_con_precio,
               COUNT(*) - COUNT(precio) AS n_faltantes,
               CASE WHEN COUNT(precio) = COUNT(*) THEN SUM(precio * cantidad) END AS total
        FROM d GROUP BY comercio ORDER BY comercio""", params + [ejecucion_id])


def canasta_minimo(con, ejecucion_id: str, items: dict) -> pd.DataFrame:
    """Para cada producto elegido: precio mínimo entre comercios, comercio(s) que lo ofrecen (con empates) y subtotal."""
    if not items:
        return pd.DataFrame()
    valores, params = _valores_canasta(items)
    return _df(con, f"""
        WITH sel(producto_id, cantidad) AS (VALUES {valores}),
        m AS (SELECT sel.producto_id, sel.cantidad, MIN(v.precio) AS minimo
              FROM sel JOIN v_comparables v ON v.producto_id = sel.producto_id AND v.ejecucion_id = ?
              GROUP BY sel.producto_id, sel.cantidad)
        SELECT p.nombre_std, m.cantidad, m.minimo AS precio_minimo, m.minimo * m.cantidad AS subtotal,
               (SELECT GROUP_CONCAT(v2.comercio, ', ') FROM v_comparables v2
                 WHERE v2.ejecucion_id = ? AND v2.producto_id = m.producto_id AND v2.precio = m.minimo) AS comercios
        FROM m JOIN productos p ON p.producto_id = m.producto_id ORDER BY p.nombre_std""",
               params + [ejecucion_id, ejecucion_id])


# --------------------------------------------------------------------------------------
# Auditoría / trazabilidad
# --------------------------------------------------------------------------------------
def rechazadas(con, ejecucion_id: str | None = None, limite: int = 500) -> pd.DataFrame:
    cond, params = ("WHERE r.ejecucion_id = ?", [ejecucion_id]) if ejecucion_id else ("", [])
    return _df(con, f"""SELECT r.ejecucion_id, c.nombre AS comercio, r.sku, r.url, r.fecha_hora_consulta, r.precio, r.motivo, r.fecha_rechazo
                        FROM observaciones_rechazadas r JOIN comercios c ON c.comercio_id = r.comercio_id {cond}
                        ORDER BY r.rechazo_id DESC LIMIT ?""", params + [int(limite)])


def correcciones(con) -> pd.DataFrame:
    return _df(con, "SELECT fecha, tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo, autor "
                    "FROM correcciones ORDER BY correccion_id")


def cobertura_trazabilidad(con) -> pd.DataFrame:
    """Observaciones con copia cruda registrada (raw_archivo) por ejecución y comercio."""
    return _df(con, """SELECT o.ejecucion_id, c.nombre AS comercio, COUNT(*) AS observaciones,
                              SUM(o.raw_archivo IS NOT NULL) AS con_raw
                       FROM observaciones o JOIN comercios c ON c.comercio_id = o.comercio_id
                       GROUP BY o.ejecucion_id, c.nombre ORDER BY o.ejecucion_id DESC, c.nombre""")


def muestra_trazabilidad(con, ejecucion_id: str, comercio: str, n: int = 10) -> pd.DataFrame:
    return _df(con, """SELECT nombre_original, sku, precio, fecha_hora_consulta, raw_archivo
                       FROM v_observaciones WHERE ejecucion_id = ? AND comercio = ? AND comparable = 1
                       ORDER BY nombre_original LIMIT ?""", [ejecucion_id, comercio, int(n)])


# --------------------------------------------------------------------------------------
# Utilidades para el scraper (escritura)
# --------------------------------------------------------------------------------------
def productos_comparables_faltantes(con, ejecucion_id: str, comercio_id: int) -> list[str]:
    """Productos comparables que NO aparecen (ni siquiera como agotados) en la ejecución de un comercio."""
    filas = con.execute("""
        SELECT p.nombre_std FROM productos p
        WHERE NOT EXISTS (SELECT 1 FROM observaciones o JOIN anuncios a ON a.anuncio_id = o.anuncio_id
                          WHERE a.producto_id = p.producto_id AND a.comparable = 1
                            AND o.ejecucion_id = ? AND o.comercio_id = ?)
        ORDER BY p.nombre_std""", [ejecucion_id, comercio_id]).fetchall()
    return [r[0] for r in filas]


def resumen_ejecucion(con, ejecucion_id: str, comercio_id: int) -> dict:
    """Resumen por comercio de una ejecución: recolectados, nuevos, cambios de precio y no observados."""
    r = con.execute("SELECT COUNT(*) FROM observaciones WHERE ejecucion_id = ? AND comercio_id = ?",
                    [ejecucion_id, comercio_id]).fetchone()[0]
    nuevos = con.execute("""
        SELECT COUNT(*) FROM observaciones o WHERE o.ejecucion_id = ? AND o.comercio_id = ?
          AND NOT EXISTS (SELECT 1 FROM observaciones p WHERE p.anuncio_id = o.anuncio_id
                          AND p.ejecucion_id <> o.ejecucion_id AND p.fecha_hora_consulta < o.fecha_hora_consulta)""",
                         [ejecucion_id, comercio_id]).fetchone()[0]
    cambios = con.execute("SELECT COUNT(*) FROM v_cambios_precio WHERE ejecucion_id = ? AND comercio_id = ?",
                          [ejecucion_id, comercio_id]).fetchone()[0]
    previa = con.execute("""SELECT e.ejecucion_id FROM ejecuciones e
                            WHERE e.comercio_id = ? AND e.estado <> 'fallida' AND e.ejecucion_id <> ?
                              AND e.inicio < (SELECT inicio FROM ejecuciones WHERE ejecucion_id = ? AND comercio_id = ?)
                            ORDER BY e.inicio DESC LIMIT 1""",
                         [comercio_id, ejecucion_id, ejecucion_id, comercio_id]).fetchone()
    no_obs = 0
    if previa:
        no_obs = con.execute("""
            SELECT COUNT(*) FROM v_disponibilidad d
            WHERE d.ejecucion_id = ? AND d.comercio_id = ? AND d.estado = 'no_observado'
              AND EXISTS (SELECT 1 FROM observaciones q WHERE q.anuncio_id = d.anuncio_id AND q.ejecucion_id = ?)""",
                             [ejecucion_id, comercio_id, previa[0]]).fetchone()[0]
    return {"recolectados": r, "nuevos": nuevos, "cambios_precio": cambios, "no_observados": no_obs,
            "ejecucion_previa": previa[0] if previa else None}


def registrar_correccion(con, fecha: str, tabla: str, registro_id, campo: str, valor_anterior, valor_nuevo,
                         motivo: str, autor: str = "estudiante") -> bool:
    """Inserta una fila en `correcciones` si no existe ya (idempotente). Devuelve True si la insertó."""
    ya = con.execute("""SELECT 1 FROM correcciones WHERE tabla = ? AND registro_id = ? AND campo = ?
                        AND COALESCE(valor_nuevo, '') = COALESCE(?, '')""",
                     [tabla, str(registro_id), campo, None if valor_nuevo is None else str(valor_nuevo)]).fetchone()
    if ya:
        return False
    con.execute("""INSERT INTO correcciones(fecha, tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo, autor)
                   VALUES (?,?,?,?,?,?,?,?)""",
                [fecha, tabla, str(registro_id), campo,
                 None if valor_anterior is None else str(valor_anterior),
                 None if valor_nuevo is None else str(valor_nuevo), motivo, autor])
    return True
