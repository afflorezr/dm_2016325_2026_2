"""
db.py — Taller 2 Minería de Datos (UNAL): capa de acceso a datos.

Todo el SQL de la aplicación vive en este archivo; la interfaz (app.py y paginas/) no contiene SQL.

Módulo 1 (este bloque): migración de la base del Taller 1 a la estructura del Taller 2.
  * Tablas nuevas: `correcciones` y `rechazos`.
  * Columnas nuevas: `observaciones.descartada`, `observaciones.motivo_descarte` y las columnas calculadas
    `observaciones.estado_disponibilidad`, `anuncios.unidad_norm` y `productos.unidad_norm`.
  * Restricción de unicidad por ejecución, índices para los filtros y vistas que usa la aplicación.
  * Corrección documentada: las observaciones con precio NULL se marcan como descartadas (no se borran).
La migración se puede ejecutar muchas veces: solo crea lo que falta y nunca borra observaciones.

Módulos 3 y 4 (segundo bloque): consultas que usa la aplicación. Cada función recibe los filtros como argumentos,
valida los valores del usuario, pasa esos valores como parámetros `?` (nunca concatenados en el SQL), abre la
conexión en solo lectura, la cierra al terminar y devuelve una tabla (pandas.DataFrame). Filtros, indicadores y
agregaciones se calculan en SQLite; la app no lee tablas completas para filtrarlas en memoria.

Uso:
    python db.py            # migra comparador_precios.sqlite
"""
from __future__ import annotations

import re
import sqlite3
from contextlib import contextmanager
from pathlib import Path

import pandas as pd

import scraper

# [CAMBIO]: la base es la misma del Taller 1; la ruta se arma relativa a este archivo (sin rutas absolutas).
DB_PATH = scraper.DB_PATH


# --------------------------------------------------------------------------------------------------------------
# Conexión
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: función que se registra en SQLite para buscar sin importar tildes ni mayúsculas: "Tío Nacho" → " tio
# nacho". LIKE de SQLite solo ignora mayúsculas en letras sin tilde, por eso se normaliza antes de comparar.
def _sin_tildes(texto) -> str:
    return " " + re.sub(r"[^a-z0-9]+", " ", scraper.normalizar(texto)).strip()


# [CAMBIO]: conexión controlada: se abre al entrar al bloque `with` y se cierra SIEMPRE al salir, aunque haya error.
# Las consultas de la app usan solo_lectura=True: aunque algo fallara, no podrían modificar la base.
@contextmanager
def abrir_conexion(db_path: Path = DB_PATH, solo_lectura: bool = False):
    """Uso: with abrir_conexion() as con: ...  (la conexión se cierra sola al terminar)."""
    if solo_lectura:
        con = sqlite3.connect(Path(db_path).resolve().as_uri() + "?mode=ro", uri=True)
    else:
        con = sqlite3.connect(db_path)
    con.execute("PRAGMA foreign_keys = ON")
    con.create_function("sin_tildes", 1, _sin_tildes, deterministic=True)
    try:
        yield con
    finally:
        con.close()


# --------------------------------------------------------------------------------------------------------------
# Esquema del Taller 2
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: tablas nuevas exigidas en §3.2 (correcciones) y §3.4 (registro de observaciones rechazadas).
TABLAS_NUEVAS = """
CREATE TABLE IF NOT EXISTS correcciones (
    id_correccion   INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_correccion TEXT NOT NULL,          -- ISO 8601, hora de Colombia
    tabla           TEXT NOT NULL,           -- tabla afectada
    registro        TEXT NOT NULL,           -- clave del registro afectado (p. ej. id_observacion)
    campo           TEXT NOT NULL,           -- columna corregida
    valor_anterior  TEXT,
    valor_nuevo     TEXT,
    motivo          TEXT NOT NULL,
    UNIQUE (tabla, registro, campo)
);
CREATE TABLE IF NOT EXISTS rechazos (
    id_rechazo          INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion        TEXT NOT NULL,
    id_comercio         TEXT NOT NULL,
    sku_comercio        TEXT,
    fecha_hora_consulta TEXT,
    url                 TEXT,
    precio              REAL,
    regla               TEXT NOT NULL,       -- regla de validacion.py que no se cumplió
    motivo              TEXT NOT NULL,       -- explicación legible
    fecha_registro      TEXT NOT NULL,
    UNIQUE (id_ejecucion, id_comercio, sku_comercio, regla)
);
"""

# [CAMBIO]: la unidad normalizada que pide §3.6 (mL, g o unidad) se calcula a partir de la columna `unidad` del
# Taller 1 ('ml', 'g', 'un'), sin modificar el valor original.
_SQL_UNIDAD_NORM = "CASE unidad WHEN 'ml' THEN 'mL' WHEN 'g' THEN 'g' WHEN 'un' THEN 'unidad' END"

# [CAMBIO]: columnas nuevas (tabla, columna, definición). Las GENERATED las calcula SQLite solo, así el código de
# inserción del Taller 1 (scraper._guardar) no cambia. La disponibilidad tiene dos valores por observación; el
# tercer estado, 'no_observado', no es una observación y se deduce en la vista v_disponibilidad.
COLUMNAS_NUEVAS = [
    ("observaciones", "descartada", "INTEGER NOT NULL DEFAULT 0"),
    ("observaciones", "motivo_descarte", "TEXT"),
    ("observaciones", "estado_disponibilidad",
     "TEXT GENERATED ALWAYS AS (CASE WHEN disponible = 1 THEN 'disponible' ELSE 'agotado' END) VIRTUAL"),
    ("anuncios", "unidad_norm", f"TEXT GENERATED ALWAYS AS ({_SQL_UNIDAD_NORM}) VIRTUAL"),
    ("productos", "unidad_norm", f"TEXT GENERATED ALWAYS AS ({_SQL_UNIDAD_NORM}) VIRTUAL"),
]

# [CAMBIO]: unicidad por ejecución (§3.6) e índices sobre las columnas que usan los filtros de la app (§3.6, §7.2).
INDICES = """
CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_ejecucion_anuncio ON observaciones(id_ejecucion, id_comercio, sku_comercio);
CREATE INDEX IF NOT EXISTS ix_obs_precio        ON observaciones(precio);
CREATE INDEX IF NOT EXISTS ix_obs_fecha         ON observaciones(fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS ix_obs_promocion     ON observaciones(es_promocion);
CREATE INDEX IF NOT EXISTS ix_anuncios_subcat   ON anuncios(subcategoria_std);
CREATE INDEX IF NOT EXISTS ix_anuncios_marca    ON anuncios(marca_std);
CREATE INDEX IF NOT EXISTS ix_anuncios_compar   ON anuncios(comparable, id_producto_comun);
"""

# [CAMBIO]: vistas que usa la aplicación (§3.6). Se recrean en cada migración para poder corregirlas.
# Todas excluyen las observaciones descartadas y los anuncios fuera de la delimitación (incluido = 0).
VISTAS = """
DROP VIEW IF EXISTS v_precios;
CREATE VIEW v_precios AS                -- todas las observaciones válidas, con precio por unidad de contenido
SELECT o.id_observacion, o.id_ejecucion, o.id_comercio, c.nombre AS comercio, o.sku_comercio,
       a.nombre_original, a.nombre_std, a.texto_original_anuncio, a.marca_std AS marca,
       a.subcategoria_std AS subcategoria,
       a.contenido, a.unidad_norm,
       o.precio,
       CASE WHEN a.contenido > 0 THEN o.precio / a.contenido END AS precio_unitario,
       o.precio_antes_descuento, o.es_promocion, o.promocion_texto, o.estado_disponibilidad,
       a.comparable, a.id_producto_comun, o.url, o.fecha_hora_consulta
FROM observaciones o
JOIN anuncios a  ON a.id_comercio = o.id_comercio AND a.sku_comercio = o.sku_comercio
JOIN comercios c ON c.id_comercio = o.id_comercio
WHERE o.descartada = 0 AND a.incluido = 1;

DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS          -- precios de la última ejecución no fallida de cada comercio
SELECT p.*
FROM v_precios p
JOIN (SELECT id_comercio, MAX(id_ejecucion) AS id_ejecucion
      FROM ejecuciones WHERE estado <> 'fallida' GROUP BY id_comercio) u
  ON u.id_comercio = p.id_comercio AND u.id_ejecucion = p.id_ejecucion;

DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS         -- mismo anuncio, mismo comercio, ejecuciones consecutivas
WITH ej AS (
    SELECT id_comercio, id_ejecucion,
           LAG(id_ejecucion) OVER (PARTITION BY id_comercio ORDER BY id_ejecucion) AS id_ejecucion_anterior
    FROM ejecuciones WHERE estado <> 'fallida'
)
SELECT ej.id_comercio, c.nombre AS comercio, ej.id_ejecucion_anterior, ej.id_ejecucion,
       o1.sku_comercio, a.nombre_original, a.marca_std AS marca, a.subcategoria_std AS subcategoria,
       a.comparable, a.id_producto_comun,
       o0.precio AS precio_anterior, o1.precio AS precio_actual,
       o1.precio - o0.precio AS diferencia,
       ROUND(100.0 * (o1.precio - o0.precio) / o0.precio, 2) AS variacion_pct,
       CASE WHEN o1.precio > o0.precio THEN 'subió'
            WHEN o1.precio < o0.precio THEN 'bajó' ELSE 'sin cambio' END AS tipo_cambio,
       o1.url
FROM ej
JOIN observaciones o0 ON o0.id_ejecucion = ej.id_ejecucion_anterior AND o0.id_comercio = ej.id_comercio
JOIN observaciones o1 ON o1.id_ejecucion = ej.id_ejecucion AND o1.id_comercio = ej.id_comercio
                     AND o1.sku_comercio = o0.sku_comercio
JOIN anuncios a  ON a.id_comercio = o1.id_comercio AND a.sku_comercio = o1.sku_comercio
JOIN comercios c ON c.id_comercio = ej.id_comercio
WHERE o0.descartada = 0 AND o1.descartada = 0 AND a.incluido = 1;

DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS            -- los productos comparables en cada ejecución y comercio
SELECT o.id_ejecucion, o.id_comercio, c.nombre AS comercio, p.id_producto_comun,
       p.nombre_std AS producto, p.marca_std AS marca, p.subcategoria_std AS subcategoria,
       p.contenido, p.unidad_norm, o.sku_comercio,
       o.precio, o.precio / p.contenido AS precio_unitario,
       o.es_promocion, o.estado_disponibilidad, o.fecha_hora_consulta, o.url
FROM observaciones o
JOIN anuncios a  ON a.id_comercio = o.id_comercio AND a.sku_comercio = o.sku_comercio
JOIN productos p ON p.id_producto_comun = a.id_producto_comun
JOIN comercios c ON c.id_comercio = o.id_comercio
WHERE a.comparable = 1 AND o.descartada = 0;

DROP VIEW IF EXISTS v_disponibilidad;
CREATE VIEW v_disponibilidad AS         -- tres situaciones: disponible, agotado (según el sitio), no_observado
SELECT e.id_ejecucion, e.id_comercio, a.sku_comercio, a.nombre_original, a.comparable, a.id_producto_comun,
       COALESCE(o.estado_disponibilidad, 'no_observado') AS estado_disponibilidad
FROM ejecuciones e
JOIN anuncios a ON a.id_comercio = e.id_comercio AND a.primera_ejecucion <= e.id_ejecucion
LEFT JOIN observaciones o ON o.id_ejecucion = e.id_ejecucion AND o.id_comercio = a.id_comercio
                         AND o.sku_comercio = a.sku_comercio
WHERE a.incluido = 1;
"""

# [CAMBIO]: motivo de la corrección de §3.2 para los precios ausentes del Taller 1.
MOTIVO_PRECIO_NULO = ("Precio ausente en el sitio (NULL): incumple la regla 'precio numérico y mayor que cero' "
                      "del Taller 2. Se marca como descartada en lugar de borrarla.")


# [CAMBIO]: agrega una columna solo si no existe (table_xinfo también muestra las columnas calculadas).
def _agregar_columna(con: sqlite3.Connection, tabla: str, columna: str, definicion: str) -> bool:
    existentes = {fila[1] for fila in con.execute(f"PRAGMA table_xinfo({tabla})")}
    if columna in existentes:
        return False
    con.execute(f"ALTER TABLE {tabla} ADD COLUMN {columna} {definicion}")
    return True


# [CAMBIO]: corrección §3.2: las observaciones con precio NULL se marcan descartadas y se registra cada cambio
# (fecha, registro, valor anterior, valor nuevo y motivo) en `correcciones`. Solo toca las que aún no lo están.
def descartar_precios_nulos(con: sqlite3.Connection) -> int:
    ids = [fila[0] for fila in con.execute(
        "SELECT id_observacion FROM observaciones WHERE precio IS NULL AND descartada = 0")]
    fecha = scraper.ahora_iso()
    for id_obs in ids:
        con.execute("UPDATE observaciones SET descartada = 1, motivo_descarte = ? WHERE id_observacion = ?",
                    ("precio_ausente", id_obs))
        con.execute("INSERT OR IGNORE INTO correcciones "
                    "(fecha_correccion, tabla, registro, campo, valor_anterior, valor_nuevo, motivo) "
                    "VALUES (?, 'observaciones', ?, 'descartada', '0', '1', ?)",
                    (fecha, str(id_obs), MOTIVO_PRECIO_NULO))
    return len(ids)


# [CAMBIO]: migración. scraper.conectar() crea primero el esquema del Taller 1 si la base está vacía (lo usan las
# pruebas con base temporal). Los pasos de estructura usan IF NOT EXISTS, por eso repetirlos no hace daño; la
# corrección de datos (UPDATE + registro en correcciones) va dentro de una transacción: se aplica completa o nada.
def migrar(db_path: Path = DB_PATH) -> dict:
    con = scraper.conectar(db_path)
    try:
        con.executescript(TABLAS_NUEVAS)
        agregadas = [f"{t}.{c}" for t, c, d in COLUMNAS_NUEVAS if _agregar_columna(con, t, c, d)]
        con.executescript(INDICES)
        con.executescript(VISTAS)
        with con:
            descartadas = descartar_precios_nulos(con)
    finally:
        con.close()
    return {"columnas_agregadas": agregadas, "observaciones_descartadas": descartadas}


# [CAMBIO]: SKU comparables esperados en cada comercio (los 18 congelados en `correspondencia`), para la regla R4
# de validacion.py. Devuelve {id_comercio: {sku, ...}}.
def skus_comparables(con: sqlite3.Connection) -> dict[str, set[str]]:
    esperados: dict[str, set[str]] = {}
    for comercio, sku in con.execute("SELECT DISTINCT id_comercio, sku_comercio FROM correspondencia"):
        esperados.setdefault(comercio, set()).add(sku)
    return esperados


# ==============================================================================================================
# Módulo 2: guardar lo recolectado por un comercio
# ==============================================================================================================
# [CAMBIO]: cuenta anuncios y observaciones de un comercio (para saber cuántos son nuevos tras insertar).
def _conteos(con: sqlite3.Connection, comercio: str) -> tuple[int, int, int]:
    anuncios = con.execute("SELECT COUNT(*) FROM anuncios WHERE id_comercio = ?", (comercio,)).fetchone()[0]
    observaciones = con.execute("SELECT COUNT(*) FROM observaciones WHERE id_comercio = ?",
                                (comercio,)).fetchone()[0]
    rechazos = con.execute("SELECT COUNT(*) FROM rechazos WHERE id_comercio = ?", (comercio,)).fetchone()[0]
    return anuncios, observaciones, rechazos


# [CAMBIO]: guarda UN comercio en UNA transacción (§4.4): rechazos, anuncios, observaciones válidas y la fila de
# `ejecuciones`. Si algo falla, se deshace todo lo de ese comercio y la base queda como estaba. Reutiliza
# scraper._guardar del Taller 1 (INSERT OR IGNORE: nunca sobrescribe observaciones anteriores).
def guardar_comercio(validas: pd.DataFrame, rechazadas: pd.DataFrame, ejecucion: dict,
                     db_path: Path = DB_PATH) -> dict:
    comercio = ejecucion["id_comercio"]
    fecha = scraper.ahora_iso()
    filas_rechazo = [(r.id_ejecucion, r.id_comercio, r.sku_comercio, r.fecha_hora_consulta, r.url, r.precio,
                      r.regla, r.motivo, fecha) for r in rechazadas.itertuples()]
    with abrir_conexion(db_path) as con:
        antes = _conteos(con, comercio)
        try:
            con.executemany("INSERT OR IGNORE INTO rechazos (id_ejecucion, id_comercio, sku_comercio, "
                            "fecha_hora_consulta, url, precio, regla, motivo, fecha_registro) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            [tuple(map(scraper._sql_valor, f)) for f in filas_rechazo])
            if len(validas):
                # _guardar abre `with con:` -> confirma (COMMIT) todo junto al final, o lo deshace si falla
                scraper._guardar(con, validas, pd.DataFrame([ejecucion]))
            else:
                with con:  # comercio sin datos válidos: solo queda registrada su ejecución (fallida o parcial)
                    columnas = list(ejecucion)
                    con.execute(f"INSERT OR IGNORE INTO ejecuciones ({', '.join(columnas)}) "
                                f"VALUES ({_marcadores(columnas)})",
                                [scraper._sql_valor(ejecucion[c]) for c in columnas])
        except Exception:
            con.rollback()
            raise
        despues = _conteos(con, comercio)
    return {"anuncios_nuevos": despues[0] - antes[0], "observaciones_nuevas": despues[1] - antes[1],
            "rechazos_nuevos": despues[2] - antes[2]}


# [CAMBIO]: si guardar_comercio falló, deja al menos registrada la ejecución del comercio como 'fallida' con el
# motivo (en su propia transacción), para que la falla quede visible en la tabla de ejecuciones.
def registrar_ejecucion_fallida(ejecucion: dict, motivo: str, db_path: Path = DB_PATH) -> None:
    fila = {**ejecucion, "estado": "fallida", "n_registros": 0, "n_productos": 0, "n_incluidos": 0,
            "nota": motivo, "fecha_hora_fin": scraper.ahora_iso()}
    columnas = list(fila)
    with abrir_conexion(db_path) as con, con:
        con.execute(f"INSERT OR IGNORE INTO ejecuciones ({', '.join(columnas)}) VALUES ({_marcadores(columnas)})",
                    [scraper._sql_valor(fila[c]) for c in columnas])


# [CAMBIO]: corrige el estado de la ejecución de un comercio y deja el registro en `correcciones` (§3.2), todo en
# una transacción. No borra nada: solo cambia el campo `estado` y anota valor anterior, nuevo y motivo.
def corregir_estado_ejecucion(id_ejecucion: str, comercio: str, estado_nuevo: str, motivo: str,
                              db_path: Path = DB_PATH) -> dict:
    if estado_nuevo not in ("completa", "parcial", "fallida"):
        raise ValueError(f"Estado no válido: {estado_nuevo!r}")
    clave = (validar_id_ejecucion(id_ejecucion), validar_comercio(comercio))
    with abrir_conexion(db_path) as con, con:
        fila = con.execute("SELECT estado FROM ejecuciones WHERE id_ejecucion = ? AND id_comercio = ?",
                           clave).fetchone()
        if fila is None:
            raise ValueError(f"No existe la ejecución {id_ejecucion} de {comercio}.")
        if fila[0] == estado_nuevo:
            return {"cambio": False, "estado": estado_nuevo}
        con.execute("UPDATE ejecuciones SET estado = ? WHERE id_ejecucion = ? AND id_comercio = ?",
                    (estado_nuevo, *clave))
        con.execute("INSERT INTO correcciones (fecha_correccion, tabla, registro, campo, valor_anterior, "
                    "valor_nuevo, motivo) VALUES (?, 'ejecuciones', ?, 'estado', ?, ?, ?)",
                    (scraper.ahora_iso(), f"{clave[0]}/{clave[1]}", fila[0], estado_nuevo, motivo))
    return {"cambio": True, "estado_anterior": fila[0], "estado": estado_nuevo}


# [CAMBIO]: datos del resumen por comercio (§4.5) después de guardar: cambios de precio frente a la ejecución
# anterior del comercio y productos no observados (existían antes y no aparecieron en esta ejecución).
def resumen_actualizacion(id_ejecucion: str, comercio: str, db_path: Path = DB_PATH) -> dict:
    params = [validar_id_ejecucion(id_ejecucion), validar_comercio(comercio)]
    cambios = _consultar("""
        SELECT SUM(tipo_cambio = 'subió') AS subieron, SUM(tipo_cambio = 'bajó') AS bajaron
        FROM v_cambios_precio WHERE id_ejecucion = ? AND id_comercio = ?""", params, db_path).iloc[0]
    no_obs = _consultar("""
        SELECT COUNT(*) AS n FROM v_disponibilidad
        WHERE id_ejecucion = ? AND id_comercio = ? AND estado_disponibilidad = 'no_observado'""",
                        params, db_path).iloc[0]["n"]
    estado = _consultar("SELECT estado, nota FROM ejecuciones WHERE id_ejecucion = ? AND id_comercio = ?",
                        params, db_path)
    return {"precios_subieron": int(cambios["subieron"] or 0), "precios_bajaron": int(cambios["bajaron"] or 0),
            "no_observados": int(no_obs),
            "estado_guardado": estado["estado"].iloc[0] if len(estado) else None,
            "nota_guardada": estado["nota"].iloc[0] if len(estado) else None}


# ==============================================================================================================
# Módulos 3 y 4: consultas de la aplicación
# ==============================================================================================================

# --------------------------------------------------------------------------------------------------------------
# Validación de las entradas del usuario (§6: longitud máxima y caracteres permitidos)
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: reglas de entrada. La búsqueda acepta letras (con tildes), números, espacios y . , & + -
LARGO_MAXIMO_TEXTO = 60
_RX_TEXTO_PERMITIDO = re.compile(r"^[^\W_]+(?:[ .,&+\-][^\W_]*)*$")
_RX_ID_EJECUCION = re.compile(r"^\d{8}T\d{6}$")
_RX_FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_RX_ID_PRODUCTO = re.compile(r"^\d{13}$")


# [CAMBIO]: valida un texto escrito por el usuario. Devuelve el texto limpio ('' si está vacío) o lanza ValueError
# con un mensaje claro en español.
def validar_texto(texto, campo: str = "búsqueda") -> str:
    limpio = re.sub(r"\s+", " ", str(texto or "")).strip()
    if not limpio:
        return ""
    if len(limpio) > LARGO_MAXIMO_TEXTO:
        raise ValueError(f"La {campo} admite máximo {LARGO_MAXIMO_TEXTO} caracteres.")
    if not _RX_TEXTO_PERMITIDO.match(limpio):
        raise ValueError(f"La {campo} solo admite letras, números, espacios y los signos . , & + -")
    return limpio


# [CAMBIO]: validadores cortos para los demás valores que llegan desde la interfaz.
def validar_comercio(comercio: str) -> str:
    if comercio not in scraper.COMERCIOS:
        raise ValueError(f"Comercio desconocido: {comercio!r}")
    return comercio


def validar_subcategoria(subcategoria: str) -> str:
    if not re.fullmatch(r"[a-z_]{1,40}", str(subcategoria)):
        raise ValueError(f"Subcategoría no válida: {subcategoria!r}")
    return str(subcategoria)


def validar_id_ejecucion(id_ejecucion: str) -> str:
    if not _RX_ID_EJECUCION.match(str(id_ejecucion)):
        raise ValueError(f"Identificador de ejecución no válido: {id_ejecucion!r}")
    return str(id_ejecucion)


def validar_fecha(fecha) -> str:
    texto = str(fecha)[:10]
    if not _RX_FECHA.match(texto):
        raise ValueError(f"Fecha no válida: {fecha!r} (formato AAAA-MM-DD)")
    return texto


def validar_id_producto(id_producto: str) -> str:
    if not _RX_ID_PRODUCTO.match(str(id_producto)):
        raise ValueError(f"Producto comparable no válido: {id_producto!r}")
    return str(id_producto)


# [CAMBIO]: en LIKE, los signos % y _ son comodines; se escapan para que se busquen como texto.
def _escapar_like(texto: str) -> str:
    return texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


# [CAMBIO]: devuelve "?, ?, ?" con tantos marcadores como valores (solo marcadores en el texto del SQL).
def _marcadores(valores) -> str:
    return ", ".join("?" * len(valores))


# [CAMBIO]: ejecuta una consulta de lectura con parámetros y devuelve un DataFrame. Abre y cierra la conexión.
def _consultar(sql: str, params=(), db_path: Path = DB_PATH) -> pd.DataFrame:
    with abrir_conexion(db_path, solo_lectura=True) as con:
        return pd.read_sql_query(sql, con, params=list(params))


# --------------------------------------------------------------------------------------------------------------
# Filtros del panel lateral (§7.2)
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: filtros que entiende `_filtrar`. Sin ejecución ni fechas, se usan los precios de la última ejecución.
FILTROS_VACIOS = {
    "comercios": [], "subcategorias": [], "marcas": [], "precio_min": None, "precio_max": None,
    "id_ejecucion": None, "fecha_desde": None, "fecha_hasta": None,
    "solo_promociones": False, "solo_comparables": False, "busqueda": "",
}


# [CAMBIO]: arma "SELECT * FROM <vista> WHERE ..." y su lista de parámetros. Los nombres de vista y de columna
# están escritos aquí (fijos); los valores del usuario van SIEMPRE en params.
def _filtrar(filtros: dict | None) -> tuple[str, list]:
    f = {**FILTROS_VACIOS, **(filtros or {})}
    condiciones, params = [], []
    historia = bool(f["id_ejecucion"] or f["fecha_desde"] or f["fecha_hasta"])
    vista = "v_precios" if historia else "v_ultimo_precio"

    if f["comercios"]:
        comercios = [validar_comercio(c) for c in f["comercios"]]
        condiciones.append(f"id_comercio IN ({_marcadores(comercios)})")
        params += comercios
    if f["subcategorias"]:
        subcategorias = [validar_subcategoria(s) for s in f["subcategorias"]]
        condiciones.append(f"subcategoria IN ({_marcadores(subcategorias)})")
        params += subcategorias
    if f["marcas"]:
        marcas = [validar_texto(m, "marca") for m in f["marcas"]]
        condiciones.append(f"marca IN ({_marcadores(marcas)})")
        params += marcas
    if f["precio_min"] is not None:
        condiciones.append("precio >= ?")
        params.append(float(f["precio_min"]))
    if f["precio_max"] is not None:
        condiciones.append("precio <= ?")
        params.append(float(f["precio_max"]))
    if f["id_ejecucion"]:
        condiciones.append("id_ejecucion = ?")
        params.append(validar_id_ejecucion(f["id_ejecucion"]))
    if f["fecha_desde"]:
        condiciones.append("substr(fecha_hora_consulta, 1, 10) >= ?")
        params.append(validar_fecha(f["fecha_desde"]))
    if f["fecha_hasta"]:
        condiciones.append("substr(fecha_hora_consulta, 1, 10) <= ?")
        params.append(validar_fecha(f["fecha_hasta"]))
    if f["solo_promociones"]:
        condiciones.append("es_promocion = 1")
    if f["solo_comparables"]:
        condiciones.append("comparable = 1")
    # Búsqueda por palabras: cada palabra debe ser el comienzo de una palabra del nombre o del texto original,
    # sin importar tildes ni mayúsculas ("tio" encuentra "Tío", pero no "antioxidante").
    for palabra in _sin_tildes(validar_texto(f["busqueda"])).split():
        condiciones.append("(sin_tildes(nombre_original) LIKE ? ESCAPE '\\' "
                           "OR sin_tildes(texto_original_anuncio) LIKE ? ESCAPE '\\')")
        patron = f"% {_escapar_like(palabra)}%"
        params += [patron, patron]

    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    return f"SELECT * FROM {vista}{where}", params


# [CAMBIO]: opciones para llenar los filtros (se consultan en SQL, no se leen tablas completas).
def listar_comercios(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("SELECT id_comercio, nombre FROM comercios ORDER BY nombre", db_path=db_path)


def listar_subcategorias(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("SELECT subcategoria, COUNT(*) AS n_anuncios FROM v_ultimo_precio "
                      "GROUP BY subcategoria ORDER BY subcategoria", db_path=db_path)


def listar_marcas(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("SELECT marca, COUNT(*) AS n_anuncios FROM v_ultimo_precio WHERE marca IS NOT NULL "
                      "GROUP BY marca ORDER BY marca", db_path=db_path)


def rango_precios(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("SELECT MIN(precio) AS precio_min, MAX(precio) AS precio_max FROM v_precios", db_path=db_path)


# [CAMBIO]: una fila por ejecución, con su fecha y el estado de cada comercio (la más reciente primero).
def listar_ejecuciones(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        SELECT id_ejecucion, MIN(fecha_hora_inicio) AS fecha_hora_inicio,
               group_concat(id_comercio || ': ' || estado, '; ') AS estados,
               CASE WHEN SUM(estado = 'completa') = COUNT(*) THEN 'completa'
                    WHEN SUM(estado = 'fallida') = COUNT(*) THEN 'fallida' ELSE 'parcial' END AS estado_general
        FROM ejecuciones GROUP BY id_ejecucion ORDER BY id_ejecucion DESC""", db_path=db_path)


# [CAMBIO]: los productos comparables, para los selectores de la evolución del precio y de la canasta.
def listar_comparables(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("SELECT id_producto_comun, nombre_std AS producto, marca_std AS marca, contenido, unidad_norm "
                      "FROM productos ORDER BY nombre_std", db_path=db_path)


# --------------------------------------------------------------------------------------------------------------
# Tabla de productos filtrados (§7.5) y distribución de precios (gráfico 3)
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: tabla con las columnas que pide §7.5 (la presentación es contenido + unidad normalizada).
def productos_filtrados(filtros: dict | None = None, db_path: Path = DB_PATH) -> pd.DataFrame:
    base, params = _filtrar(filtros)
    return _consultar(f"""
        SELECT comercio, nombre_original AS nombre, marca, subcategoria, contenido, unidad_norm,
               precio, precio_unitario, precio_antes_descuento, es_promocion, promocion_texto,
               estado_disponibilidad, comparable, id_ejecucion, fecha_hora_consulta, url
        FROM ({base}) ORDER BY comercio, nombre_original, fecha_hora_consulta""", params, db_path)


# --------------------------------------------------------------------------------------------------------------
# Indicadores (§7.3): cada uno devuelve su unidad implícita en el nombre de la columna y su periodo
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: productos, observaciones, promociones y precio promedio por comercio, con los filtros aplicados.
def resumen_por_comercio(filtros: dict | None = None, db_path: Path = DB_PATH) -> pd.DataFrame:
    base, params = _filtrar(filtros)
    return _consultar(f"""
        SELECT id_comercio, comercio,
               COUNT(DISTINCT sku_comercio) AS n_productos,
               COUNT(*) AS n_observaciones,
               ROUND(100.0 * AVG(es_promocion), 1) AS pct_promocion,
               MIN(id_ejecucion) AS primera_ejecucion, MAX(id_ejecucion) AS ultima_ejecucion
        FROM ({base}) GROUP BY id_comercio, comercio ORDER BY comercio""", params, db_path)


# [CAMBIO]: fecha, hora y estado de la última ejecución de cada comercio.
def ultima_ejecucion(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        SELECT e.id_ejecucion, e.id_comercio, c.nombre AS comercio, e.fecha_hora_inicio, e.fecha_hora_fin,
               e.estado, e.n_registros, e.total_sitio, e.nota
        FROM ejecuciones e JOIN comercios c ON c.id_comercio = e.id_comercio
        WHERE e.id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones)
        ORDER BY c.nombre""", db_path=db_path)


# [CAMBIO]: mediana del precio (COP) por subcategoría, calculada en SQL con funciones de ventana:
# se ordenan los precios y se promedian el o los dos valores centrales.
def mediana_por_subcategoria(filtros: dict | None = None, db_path: Path = DB_PATH) -> pd.DataFrame:
    base, params = _filtrar(filtros)
    return _consultar(f"""
        WITH ordenado AS (
            SELECT subcategoria, precio,
                   ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS fila,
                   COUNT(*) OVER (PARTITION BY subcategoria) AS n
            FROM ({base}) WHERE precio IS NOT NULL
        )
        SELECT subcategoria, AVG(precio) AS mediana_cop, MAX(n) AS n_observaciones
        FROM ordenado WHERE fila IN ((n + 1) / 2, (n + 2) / 2)
        GROUP BY subcategoria ORDER BY mediana_cop DESC""", params, db_path)


# [CAMBIO]: por producto comparable disponible: precio mínimo, máximo y ahorro (COP y %) entre comercios en una
# ejecución. En empates, `donde_mas_barato` lista todos los comercios con el precio mínimo.
def ahorro_por_comparable(id_ejecucion: str, db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        WITH c AS (SELECT id_producto_comun, producto, comercio, precio FROM v_comparables
                   WHERE id_ejecucion = ? AND estado_disponibilidad = 'disponible'),
             r AS (SELECT id_producto_comun, producto, MIN(precio) AS precio_min, MAX(precio) AS precio_max,
                          COUNT(*) AS n_comercios
                   FROM c GROUP BY id_producto_comun, producto HAVING COUNT(*) >= 2)
        SELECT r.id_producto_comun, r.producto, r.n_comercios, r.precio_min, r.precio_max,
               r.precio_max - r.precio_min AS ahorro_cop,
               ROUND(100.0 * (r.precio_max - r.precio_min) / r.precio_max, 1) AS ahorro_pct,
               (SELECT group_concat(comercio, ', ') FROM c
                WHERE c.id_producto_comun = r.id_producto_comun AND c.precio = r.precio_min) AS donde_mas_barato,
               (SELECT group_concat(comercio, ', ') FROM c
                WHERE c.id_producto_comun = r.id_producto_comun AND c.precio = r.precio_max) AS donde_mas_caro
        FROM r ORDER BY ahorro_cop DESC""", [validar_id_ejecucion(id_ejecucion)], db_path)


# [CAMBIO]: número de cambios de precio (subió / bajó / sin cambio) en la última ejecución de cada comercio,
# frente a su ejecución anterior.
def cambios_ultima_ejecucion(db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        SELECT id_comercio, comercio, id_ejecucion_anterior, id_ejecucion,
               SUM(tipo_cambio = 'subió') AS n_subieron, SUM(tipo_cambio = 'bajó') AS n_bajaron,
               SUM(tipo_cambio = 'sin cambio') AS n_sin_cambio
        FROM v_cambios_precio v
        WHERE id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones e
                              WHERE e.id_comercio = v.id_comercio AND e.estado <> 'fallida')
        GROUP BY id_comercio, comercio, id_ejecucion_anterior, id_ejecucion ORDER BY comercio""", db_path=db_path)


# [CAMBIO]: cuántos anuncios están disponibles, agotados o no observados en una ejecución, por comercio.
def resumen_disponibilidad(id_ejecucion: str, db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        SELECT d.id_comercio, c.nombre AS comercio,
               SUM(estado_disponibilidad = 'disponible') AS n_disponibles,
               SUM(estado_disponibilidad = 'agotado') AS n_agotados,
               SUM(estado_disponibilidad = 'no_observado') AS n_no_observados
        FROM v_disponibilidad d JOIN comercios c ON c.id_comercio = d.id_comercio
        WHERE d.id_ejecucion = ? GROUP BY d.id_comercio, c.nombre ORDER BY c.nombre""",
                      [validar_id_ejecucion(id_ejecucion)], db_path)


# --------------------------------------------------------------------------------------------------------------
# Gráficos (§7.4)
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: gráfico 1: precio de un comparable en cada ejecución, una serie por comercio.
def evolucion_precio(id_producto_comun: str, db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        SELECT id_ejecucion, fecha_hora_consulta, id_comercio, comercio, producto, precio, es_promocion,
               estado_disponibilidad
        FROM v_comparables WHERE id_producto_comun = ?
        ORDER BY fecha_hora_consulta""", [validar_id_producto(id_producto_comun)], db_path)


# [CAMBIO]: gráfico 2: precio por unidad de contenido de los comparables de UNA unidad (mL o g), sin mezclar.
def precio_unitario_comparables(id_ejecucion: str, unidad_norm: str, db_path: Path = DB_PATH) -> pd.DataFrame:
    if unidad_norm not in ("mL", "g", "unidad"):
        raise ValueError(f"Unidad no válida: {unidad_norm!r}")
    return _consultar("""
        SELECT id_producto_comun, producto, id_comercio, comercio, contenido, unidad_norm, precio, precio_unitario,
               estado_disponibilidad
        FROM v_comparables WHERE id_ejecucion = ? AND unidad_norm = ?
        ORDER BY producto, comercio""", [validar_id_ejecucion(id_ejecucion), unidad_norm], db_path)


# [CAMBIO]: gráfico 4 (libre): ¿en qué comercio conviene comprar? Cuenta en cuántos comparables disponibles cada
# comercio tiene el precio más bajo (en un empate, cuenta para todos los comercios empatados).
def veces_mas_barato(id_ejecucion: str, db_path: Path = DB_PATH) -> pd.DataFrame:
    return _consultar("""
        WITH c AS (SELECT id_producto_comun, id_comercio, comercio, precio FROM v_comparables
                   WHERE id_ejecucion = ? AND estado_disponibilidad = 'disponible'),
             minimo AS (SELECT id_producto_comun, MIN(precio) AS precio_min FROM c GROUP BY id_producto_comun)
        SELECT c.id_comercio, c.comercio, COUNT(*) AS n_productos_mas_barato
        FROM c JOIN minimo m ON m.id_producto_comun = c.id_producto_comun AND c.precio = m.precio_min
        GROUP BY c.id_comercio, c.comercio ORDER BY n_productos_mas_barato DESC""",
                      [validar_id_ejecucion(id_ejecucion)], db_path)


# --------------------------------------------------------------------------------------------------------------
# Cambios de precio entre dos ejecuciones elegidas (§8.2)
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: compara el mismo anuncio en el mismo comercio entre la ejecución A (anterior) y B (posterior).
# tipo_cambio: subió, bajó, sin cambio, nuevo (solo en B) o dejó de observarse (solo en A). Solo se comparan los
# comercios que tienen datos en ambas ejecuciones. variacion_grande = 1 si |variación %| >= umbral.
def comparar_ejecuciones(id_ejecucion_a: str, id_ejecucion_b: str, umbral_pct: float = 10.0,
                         comercios: list[str] | None = None, solo_comparables: bool = False,
                         db_path: Path = DB_PATH) -> pd.DataFrame:
    id_a, id_b = validar_id_ejecucion(id_ejecucion_a), validar_id_ejecucion(id_ejecucion_b)
    umbral = abs(float(umbral_pct))
    lista = [validar_comercio(c) for c in (comercios or scraper.COMERCIOS)]
    filtro = f"id_comercio IN ({_marcadores(lista)})" + (" AND comparable = 1" if solo_comparables else "")
    sql = f"""
        WITH a AS (SELECT * FROM v_precios WHERE id_ejecucion = ? AND {filtro}),
             b AS (SELECT * FROM v_precios WHERE id_ejecucion = ? AND {filtro}),
             ambos AS (SELECT id_comercio FROM ejecuciones WHERE id_ejecucion = ? AND estado <> 'fallida'
                       INTERSECT
                       SELECT id_comercio FROM ejecuciones WHERE id_ejecucion = ? AND estado <> 'fallida'),
             union_ab AS (
                SELECT b.id_comercio, b.comercio, b.sku_comercio, b.nombre_original, b.comparable, b.url,
                       a.precio AS precio_a, b.precio AS precio_b
                FROM b LEFT JOIN a ON a.id_comercio = b.id_comercio AND a.sku_comercio = b.sku_comercio
                UNION ALL
                SELECT a.id_comercio, a.comercio, a.sku_comercio, a.nombre_original, a.comparable, a.url,
                       a.precio, NULL
                FROM a LEFT JOIN b ON b.id_comercio = a.id_comercio AND b.sku_comercio = a.sku_comercio
                WHERE b.sku_comercio IS NULL)
        SELECT id_comercio, comercio, sku_comercio, nombre_original, comparable, precio_a, precio_b,
               precio_b - precio_a AS diferencia_cop,
               ROUND(100.0 * (precio_b - precio_a) / precio_a, 2) AS variacion_pct,
               CASE WHEN precio_a IS NULL THEN 'nuevo'
                    WHEN precio_b IS NULL THEN 'dejó de observarse'
                    WHEN precio_b > precio_a THEN 'subió'
                    WHEN precio_b < precio_a THEN 'bajó' ELSE 'sin cambio' END AS tipo_cambio,
               CASE WHEN ABS(100.0 * (precio_b - precio_a) / precio_a) >= ? THEN 1 ELSE 0 END AS variacion_grande,
               url
        FROM union_ab WHERE id_comercio IN (SELECT id_comercio FROM ambos)
        ORDER BY ABS(COALESCE(variacion_pct, 0)) DESC, comercio, nombre_original"""
    params = [id_a, *lista, id_b, *lista, id_a, id_b, umbral]
    return _consultar(sql, params, db_path)


# --------------------------------------------------------------------------------------------------------------
# Canasta (§8.3)
# --------------------------------------------------------------------------------------------------------------
# [CAMBIO]: CTE común de la canasta. `pedido` se arma con VALUES (?, ?) por producto: en el texto solo van
# marcadores; los ids y cantidades van en params. Solo se usan precios de UNA ejecución y, por defecto, solo
# productos disponibles (un producto agotado no se puede comprar).
def _cte_canasta(n_productos: int) -> str:
    valores = ", ".join(["(?, ?)"] * n_productos)
    return f"""
        WITH pedido(id_producto_comun, cantidad) AS (VALUES {valores}),
             precios AS (
                SELECT v.id_comercio, v.comercio, v.id_producto_comun, v.precio, p.cantidad
                FROM v_comparables v JOIN pedido p ON p.id_producto_comun = v.id_producto_comun
                WHERE v.id_ejecucion = ? AND (? = 0 OR v.estado_disponibilidad = 'disponible')),
             comercios_ejec AS (
                SELECT c.id_comercio, c.nombre AS comercio FROM comercios c
                JOIN ejecuciones e ON e.id_comercio = c.id_comercio AND e.id_ejecucion = ?),
             por_comercio AS (
                SELECT ce.id_comercio, ce.comercio,
                       COUNT(pr.id_producto_comun) AS productos_encontrados,
                       (SELECT COUNT(*) FROM pedido) AS productos_pedidos,
                       CASE WHEN COUNT(pr.id_producto_comun) = (SELECT COUNT(*) FROM pedido)
                            THEN SUM(pr.precio * pr.cantidad) END AS total_cop,
                       (SELECT group_concat(pp.nombre_std, ' | ') FROM pedido p2
                        JOIN productos pp ON pp.id_producto_comun = p2.id_producto_comun
                        WHERE NOT EXISTS (SELECT 1 FROM precios x WHERE x.id_comercio = ce.id_comercio
                                          AND x.id_producto_comun = p2.id_producto_comun)) AS faltantes
                FROM comercios_ejec ce LEFT JOIN precios pr ON pr.id_comercio = ce.id_comercio
                GROUP BY ce.id_comercio, ce.comercio),
             detalle AS (
                SELECT p.id_producto_comun, pp.nombre_std AS producto, p.cantidad,
                       MIN(pr.precio) AS precio_min_cop, MIN(pr.precio) * p.cantidad AS subtotal_min_cop,
                       (SELECT group_concat(x.comercio, ', ') FROM precios x
                        WHERE x.id_producto_comun = p.id_producto_comun
                          AND x.precio = (SELECT MIN(y.precio) FROM precios y
                                          WHERE y.id_producto_comun = p.id_producto_comun)) AS donde_comprar
                FROM pedido p JOIN productos pp ON pp.id_producto_comun = p.id_producto_comun
                LEFT JOIN precios pr ON pr.id_producto_comun = p.id_producto_comun
                GROUP BY p.id_producto_comun, pp.nombre_std, p.cantidad)
    """


# [CAMBIO]: calcula la canasta. `cantidades` = {id_producto_comun: cantidad}. Devuelve:
#   por_comercio: total en cada comercio (NULL si le falta algún producto, con la lista de faltantes);
#   detalle: precio mínimo de cada producto y dónde comprarlo (en empate, todos los comercios empatados);
#   resumen: costo mínimo comprando cada producto donde es más barato, mejor comercio único y ahorro.
def calcular_canasta(id_ejecucion: str, cantidades: dict[str, int], solo_disponibles: bool = True,
                     db_path: Path = DB_PATH) -> dict:
    if not cantidades:
        raise ValueError("Elija al menos un producto para la canasta.")
    pares = []
    for id_producto, cantidad in cantidades.items():
        cantidad = int(cantidad)
        if not 1 <= cantidad <= 99:
            raise ValueError("La cantidad de cada producto debe estar entre 1 y 99.")
        pares += [validar_id_producto(id_producto), cantidad]
    id_ejec = validar_id_ejecucion(id_ejecucion)
    params = [*pares, id_ejec, int(solo_disponibles), id_ejec]
    cte = _cte_canasta(len(cantidades))
    por_comercio = _consultar(cte + "SELECT * FROM por_comercio ORDER BY total_cop IS NULL, total_cop, comercio",
                              params, db_path)
    detalle = _consultar(cte + "SELECT * FROM detalle ORDER BY producto", params, db_path)
    resumen = _consultar(cte + """
        SELECT CASE WHEN COUNT(precio_min_cop) = COUNT(*) THEN SUM(subtotal_min_cop) END AS costo_minimo_cop,
               (SELECT MIN(total_cop) FROM por_comercio) AS mejor_total_un_comercio_cop,
               (SELECT group_concat(comercio, ', ') FROM por_comercio
                WHERE total_cop = (SELECT MIN(total_cop) FROM por_comercio)) AS mejor_comercio,
               (SELECT MIN(total_cop) FROM por_comercio)
                 - CASE WHEN COUNT(precio_min_cop) = COUNT(*) THEN SUM(subtotal_min_cop) END AS ahorro_cop
        FROM detalle""", params, db_path)
    return {"por_comercio": por_comercio, "detalle": detalle, "resumen": resumen.iloc[0].to_dict()}


if __name__ == "__main__":
    print(migrar())
