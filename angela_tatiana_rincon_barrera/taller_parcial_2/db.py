"""
Capa de acceso a datos (Módulo 3): db.py

- Todo el SQL de la aplicación vive en este módulo; la interfaz no contiene SQL.
- Filtros, indicadores y agregaciones se calculan con SQL sobre SQLite.
- Todo valor que proviene del usuario se pasa como parámetro (?); en el texto de
  la consulta solo se insertan marcadores "?" generados por el propio código.
- Las conexiones se abren y se cierran con el administrador de contexto `conectar`.
"""

from __future__ import annotations

import re
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional, Sequence, Tuple

import pandas as pd

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "comparador_precios.sqlite"
TZ_COLOMBIA = timezone(timedelta(hours=-5))

MAX_LARGO_BUSQUEDA = 60
_PATRON_BUSQUEDA = re.compile(r"^[0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s\-\+\.,'/&°]*$")


def ahora() -> str:
    return datetime.now(TZ_COLOMBIA).isoformat(timespec="seconds")


# =====================================================================
# CONEXIÓN
# =====================================================================
@contextmanager
def conectar(db_path: Path | str = DB_PATH, solo_lectura: bool = False) -> Iterator[sqlite3.Connection]:
    """Abre una conexión, la entrega y la cierra siempre (incluso si hay error)."""
    ruta = Path(db_path)
    if solo_lectura:
        con = sqlite3.connect(f"file:{ruta.as_posix()}?mode=ro", uri=True, timeout=30)
    else:
        con = sqlite3.connect(ruta, timeout=30)
        con.execute("PRAGMA foreign_keys = ON;")
    try:
        yield con
    finally:
        con.close()


def _df(con: sqlite3.Connection, sql: str, params: Sequence[Any] = ()) -> pd.DataFrame:
    return pd.read_sql_query(sql, con, params=list(params))


def _marcadores(valores: Sequence[Any]) -> str:
    """Genera "?, ?, ?" para una lista IN. Solo se insertan marcadores, nunca valores."""
    return ", ".join("?" for _ in valores)


# =====================================================================
# ESQUEMA
# =====================================================================
DDL_TABLAS = """
CREATE TABLE IF NOT EXISTS corridas (
    id_corrida INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_hora_inicio TEXT NOT NULL,
    fecha_hora_fin TEXT,
    n_total_observaciones INTEGER DEFAULT 0,
    estado TEXT CHECK(estado IN ('completa', 'parcial', 'fallida')) NOT NULL
);
CREATE TABLE IF NOT EXISTS ejecuciones (
    id_ejecucion INTEGER PRIMARY KEY AUTOINCREMENT,
    id_corrida INTEGER NOT NULL,
    fecha_hora_inicio TEXT NOT NULL,
    fecha_hora_fin TEXT,
    comercio TEXT NOT NULL,
    total_reportado_sitio INTEGER,
    total_obtenido INTEGER DEFAULT 0,
    n_registros INTEGER DEFAULT 0,
    estado TEXT CHECK(estado IN ('completa', 'parcial', 'fallida')) NOT NULL,
    FOREIGN KEY (id_corrida) REFERENCES corridas(id_corrida)
);
CREATE TABLE IF NOT EXISTS productos_comparables (
    id_producto_comun TEXT PRIMARY KEY,
    nombre_estandar TEXT NOT NULL,
    marca_estandar TEXT NOT NULL,
    categoria_estandar TEXT NOT NULL,
    presentacion_estandar TEXT NOT NULL,
    contenido_valor REAL NOT NULL,
    contenido_unidad TEXT NOT NULL,
    ean TEXT
);
CREATE TABLE IF NOT EXISTS observaciones (
    id_observacion INTEGER PRIMARY KEY AUTOINCREMENT,
    id_corrida INTEGER NOT NULL,
    id_ejecucion INTEGER NOT NULL,
    comercio TEXT NOT NULL,
    id_producto_comercio TEXT NOT NULL,
    nombre_original TEXT NOT NULL,
    presentacion_original TEXT,
    descripcion_original TEXT,
    marca_original TEXT,
    subcategoria_original TEXT,
    precio_actual REAL,
    precio_lista REAL,
    es_promocion INTEGER NOT NULL DEFAULT 0,
    url TEXT,
    pum_original TEXT,
    fecha_hora_consulta TEXT NOT NULL,
    comparable INTEGER NOT NULL DEFAULT 0,
    id_producto_comun TEXT,
    contenido_valor REAL,
    contenido_unidad TEXT,
    precio_por_unidad REAL,
    en_categoria INTEGER NOT NULL DEFAULT 1,
    motivo_exclusion TEXT,
    ean TEXT,
    FOREIGN KEY (id_corrida) REFERENCES corridas(id_corrida),
    FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion),
    FOREIGN KEY (id_producto_comun) REFERENCES productos_comparables(id_producto_comun),
    CONSTRAINT uq_comercio_prod_fecha UNIQUE (comercio, id_producto_comercio, fecha_hora_consulta)
);
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
    id_rechazo INTEGER PRIMARY KEY AUTOINCREMENT,
    id_corrida INTEGER NOT NULL,
    id_ejecucion INTEGER NOT NULL,
    comercio TEXT,
    id_producto_comercio TEXT,
    nombre_original TEXT,
    precio_actual REAL,
    url TEXT,
    fecha_hora_consulta TEXT,
    motivo TEXT NOT NULL,
    fecha_registro TEXT NOT NULL,
    FOREIGN KEY (id_corrida) REFERENCES corridas(id_corrida),
    FOREIGN KEY (id_ejecucion) REFERENCES ejecuciones(id_ejecucion)
);
CREATE TABLE IF NOT EXISTS correcciones (
    id_correccion INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha_correccion TEXT NOT NULL,
    tabla TEXT NOT NULL,
    id_registro INTEGER NOT NULL,
    campo TEXT NOT NULL,
    valor_anterior TEXT,
    valor_nuevo TEXT,
    motivo TEXT NOT NULL
);
"""

# Columnas añadidas en el Taller 2 a tablas que ya existían en el Taller 1
COLUMNAS_NUEVAS = {
    "corridas": [
        ("modo", "TEXT"),
        ("fecha_datos", "TEXT"),
        ("motivo", "TEXT"),
    ],
    "ejecuciones": [
        ("modo", "TEXT"),
        ("archivo_raw", "TEXT"),
        ("n_rechazadas", "INTEGER DEFAULT 0"),
        ("n_productos_nuevos", "INTEGER"),
        ("n_cambios_precio", "INTEGER"),
        ("n_no_observados", "INTEGER"),
        ("comparables_encontrados", "INTEGER"),
        ("motivo", "TEXT"),
    ],
    "observaciones": [
        ("estado_disponibilidad", "TEXT"),
        ("subcategoria_estandar", "TEXT"),
        ("marca_estandar", "TEXT"),
        ("ean_original", "TEXT"),
        ("descartada", "INTEGER NOT NULL DEFAULT 0"),
        ("motivo_descarte", "TEXT"),
    ],
}

DDL_INDICES = """
CREATE INDEX IF NOT EXISTS idx_obs_corrida ON observaciones(id_corrida);
CREATE INDEX IF NOT EXISTS idx_obs_comun ON observaciones(id_producto_comun);
CREATE INDEX IF NOT EXISTS idx_obs_comercio ON observaciones(comercio);
CREATE INDEX IF NOT EXISTS idx_obs_ejecucion ON observaciones(id_ejecucion);
CREATE INDEX IF NOT EXISTS idx_obs_en_cat ON observaciones(en_categoria);
CREATE INDEX IF NOT EXISTS idx_obs_subcat ON observaciones(subcategoria_estandar);
CREATE INDEX IF NOT EXISTS idx_obs_marca ON observaciones(marca_estandar);
CREATE INDEX IF NOT EXISTS idx_obs_precio ON observaciones(precio_actual);
CREATE INDEX IF NOT EXISTS idx_obs_promo ON observaciones(es_promocion);
CREATE INDEX IF NOT EXISTS idx_obs_fecha ON observaciones(fecha_hora_consulta);
CREATE INDEX IF NOT EXISTS idx_obs_comercio_anuncio ON observaciones(comercio, id_producto_comercio, id_corrida);
CREATE INDEX IF NOT EXISTS idx_rech_ejecucion ON observaciones_rechazadas(id_ejecucion);
CREATE INDEX IF NOT EXISTS idx_corr_registro ON correcciones(tabla, id_registro);
"""

# Reglas de dominio que ALTER TABLE no permite como CHECK: se imponen con disparadores
DDL_DISPARADORES = """
DROP TRIGGER IF EXISTS trg_obs_dominios_ins;
CREATE TRIGGER trg_obs_dominios_ins BEFORE INSERT ON observaciones
WHEN NEW.estado_disponibilidad IS NOT NULL AND NEW.estado_disponibilidad NOT IN ('disponible', 'agotado')
  OR NEW.contenido_unidad IS NOT NULL AND NEW.contenido_unidad NOT IN ('mL', 'g', 'unidad')
  OR NEW.precio_actual IS NOT NULL AND NEW.precio_actual <= 0
BEGIN
  SELECT RAISE(ABORT, 'Valor fuera de dominio en observaciones');
END;
DROP TRIGGER IF EXISTS trg_obs_dominios_upd;
CREATE TRIGGER trg_obs_dominios_upd BEFORE UPDATE ON observaciones
WHEN NEW.estado_disponibilidad IS NOT NULL AND NEW.estado_disponibilidad NOT IN ('disponible', 'agotado')
  OR NEW.contenido_unidad IS NOT NULL AND NEW.contenido_unidad NOT IN ('mL', 'g', 'unidad')
  OR NEW.precio_actual IS NOT NULL AND NEW.precio_actual <= 0
BEGIN
  SELECT RAISE(ABORT, 'Valor fuera de dominio en observaciones');
END;
"""

DDL_VISTAS = """
DROP VIEW IF EXISTS v_corridas;
CREATE VIEW v_corridas AS
SELECT c.id_corrida,
       COALESCE(c.fecha_datos, MAX(o.fecha_hora_consulta)) AS fecha_datos,
       c.fecha_hora_inicio, c.fecha_hora_fin, COALESCE(c.modo, 'en_linea') AS modo, c.estado,
       COUNT(o.id_observacion) AS n_observaciones,
       COUNT(DISTINCT o.comercio) AS n_comercios,
       ROW_NUMBER() OVER (ORDER BY COALESCE(c.fecha_datos, MAX(o.fecha_hora_consulta)), c.id_corrida) AS orden
FROM corridas c
JOIN observaciones o ON o.id_corrida = c.id_corrida
GROUP BY c.id_corrida;

DROP VIEW IF EXISTS v_observaciones;
CREATE VIEW v_observaciones AS
SELECT o.*, vc.fecha_datos AS fecha_corrida, vc.orden AS orden_corrida
FROM observaciones o
JOIN v_corridas vc ON vc.id_corrida = o.id_corrida
WHERE o.descartada = 0;

DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
WITH ultima AS (
    SELECT comercio, MAX(orden_corrida) AS orden
    FROM v_observaciones GROUP BY comercio
)
SELECT v.*
FROM v_observaciones v
JOIN ultima u ON u.comercio = v.comercio AND u.orden = v.orden_corrida;

DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT v.id_corrida, v.fecha_corrida, v.orden_corrida, v.comercio, v.id_producto_comun,
       pc.nombre_estandar, pc.marca_estandar, pc.presentacion_estandar,
       pc.contenido_valor, pc.contenido_unidad,
       v.id_producto_comercio, v.nombre_original, v.precio_actual, v.precio_lista, v.es_promocion,
       v.precio_por_unidad, v.estado_disponibilidad, v.url, v.fecha_hora_consulta,
       MIN(v.precio_actual) OVER w AS precio_minimo_corrida,
       v.precio_actual - MIN(v.precio_actual) OVER w AS diferencia_vs_minimo,
       CASE WHEN v.precio_actual = MIN(v.precio_actual) OVER w THEN 1 ELSE 0 END AS es_mas_barato,
       COUNT(*) OVER w AS n_comercios_con_precio
FROM v_observaciones v
JOIN productos_comparables pc ON pc.id_producto_comun = v.id_producto_comun
WHERE v.comparable = 1 AND v.en_categoria = 1 AND v.precio_actual IS NOT NULL
WINDOW w AS (PARTITION BY v.id_corrida, v.id_producto_comun);

DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
WITH serie AS (
    SELECT v.*,
           LAG(v.precio_actual) OVER p AS precio_anterior,
           LAG(v.id_corrida) OVER p AS id_corrida_anterior,
           LAG(v.fecha_hora_consulta) OVER p AS fecha_anterior
    FROM v_observaciones v
    WINDOW p AS (PARTITION BY v.comercio, v.id_producto_comercio ORDER BY v.orden_corrida)
)
SELECT id_corrida, fecha_corrida, id_corrida_anterior, fecha_anterior, comercio, id_producto_comercio,
       nombre_original, id_producto_comun, comparable, en_categoria, url,
       precio_anterior, precio_actual,
       precio_actual - precio_anterior AS cambio_cop,
       ROUND(100.0 * (precio_actual - precio_anterior) / precio_anterior, 2) AS cambio_pct,
       CASE WHEN precio_actual > precio_anterior THEN 'subió'
            WHEN precio_actual < precio_anterior THEN 'bajó' ELSE 'sin cambio' END AS direccion
FROM serie
WHERE precio_anterior IS NOT NULL AND precio_actual IS NOT NULL;

DROP VIEW IF EXISTS v_disponibilidad;
CREATE VIEW v_disponibilidad AS
WITH anuncios AS (
    SELECT comercio, id_producto_comercio, MIN(orden_corrida) AS primera
    FROM v_observaciones GROUP BY comercio, id_producto_comercio
),
corridas_comercio AS (
    SELECT vc.id_corrida, vc.orden AS orden_corrida, c.comercio
    FROM v_corridas vc CROSS JOIN (SELECT DISTINCT comercio FROM v_observaciones) c
)
SELECT cc.id_corrida, cc.orden_corrida, a.comercio, a.id_producto_comercio,
       CASE WHEN v.id_observacion IS NULL THEN 'no_observado'
            ELSE COALESCE(v.estado_disponibilidad, 'sin_informacion') END AS estado
FROM anuncios a
JOIN corridas_comercio cc ON cc.comercio = a.comercio AND cc.orden_corrida >= a.primera
LEFT JOIN v_observaciones v ON v.id_corrida = cc.id_corrida AND v.comercio = a.comercio
                           AND v.id_producto_comercio = a.id_producto_comercio;

DROP VIEW IF EXISTS v_resumen_ejecuciones;
CREATE VIEW v_resumen_ejecuciones AS
SELECT e.id_corrida, e.id_ejecucion, e.comercio, COALESCE(e.modo, 'en_linea') AS modo,
       e.fecha_hora_inicio, e.fecha_hora_fin, e.estado, e.total_reportado_sitio,
       e.total_obtenido AS recolectados, e.n_registros AS insertados, e.n_rechazadas,
       e.n_productos_nuevos, e.n_cambios_precio, e.n_no_observados, e.comparables_encontrados,
       e.archivo_raw, e.motivo
FROM ejecuciones e;
"""


def inicializar_bd(con: sqlite3.Connection) -> None:
    """Crea o actualiza el esquema completo (tablas, columnas, índices, disparadores y vistas)."""
    con.executescript(DDL_TABLAS)
    for tabla, columnas in COLUMNAS_NUEVAS.items():
        existentes = {r[1] for r in con.execute(f"PRAGMA table_info({tabla})")}
        for nombre, tipo in columnas:
            if nombre not in existentes:
                con.execute(f"ALTER TABLE {tabla} ADD COLUMN {nombre} {tipo}")
    con.executescript(DDL_INDICES)
    con.executescript(DDL_DISPARADORES)
    con.executescript(DDL_VISTAS)
    con.commit()


def sincronizar_catalogo(con: sqlite3.Connection, catalogo: List[Dict[str, Any]]) -> None:
    for item in catalogo:
        con.execute(
            """INSERT INTO productos_comparables (id_producto_comun, nombre_estandar, marca_estandar,
                   categoria_estandar, presentacion_estandar, contenido_valor, contenido_unidad, ean)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(id_producto_comun) DO NOTHING""",
            (item["id_producto_comun"], item["nombre_estandar"], item["marca_estandar"],
             item["categoria_estandar"], item["presentacion_estandar"], item["contenido_valor"],
             item["contenido_unidad"], item.get("ean")),
        )
    con.commit()


def registrar_correccion(con: sqlite3.Connection, tabla: str, id_registro: int, campo: str,
                         valor_anterior: Any, valor_nuevo: Any, motivo: str) -> None:
    con.execute(
        """INSERT INTO correcciones (fecha_correccion, tabla, id_registro, campo, valor_anterior, valor_nuevo, motivo)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (ahora(), tabla, id_registro, campo,
         None if valor_anterior is None else str(valor_anterior),
         None if valor_nuevo is None else str(valor_nuevo), motivo),
    )


# =====================================================================
# ESCRITURA: EJECUCIONES E INSERCIÓN
# =====================================================================
COLUMNAS_INSERCION = [
    "comercio", "id_producto_comercio", "nombre_original", "presentacion_original",
    "descripcion_original", "marca_original", "subcategoria_original", "precio_actual",
    "precio_lista", "es_promocion", "url", "pum_original", "fecha_hora_consulta", "comparable",
    "id_producto_comun", "contenido_valor", "contenido_unidad", "precio_por_unidad",
    "en_categoria", "motivo_exclusion", "ean", "ean_original", "estado_disponibilidad",
    "subcategoria_estandar", "marca_estandar",
]


def iniciar_corrida(con: sqlite3.Connection, modo: str) -> int:
    cur = con.execute(
        "INSERT INTO corridas (fecha_hora_inicio, n_total_observaciones, estado, modo) VALUES (?, 0, 'parcial', ?)",
        (ahora(), modo),
    )
    con.commit()
    return int(cur.lastrowid)


def _valor_sql(v: Any) -> Any:
    if v is None:
        return None
    try:
        if pd.isna(v):
            return None
    except (TypeError, ValueError):
        pass
    if hasattr(v, "item"):
        return v.item()
    return v


def _estado_ejecucion(n_validas: int, total_obtenido: int, total_reportado: Optional[int], fallo: bool,
                      cumple_comparables: bool) -> str:
    if n_validas == 0:
        return "fallida"
    if (not fallo and total_reportado is not None and total_obtenido >= total_reportado and cumple_comparables):
        return "completa"
    return "parcial"


def guardar_ejecucion_comercio(con: sqlite3.Connection, id_corrida: int, comercio: str, modo: str,
                               timestamp: Optional[str], validas: pd.DataFrame, rechazadas: pd.DataFrame,
                               total_reportado: Optional[int], fallo: bool, motivo: Optional[str],
                               archivo_raw: Optional[str], comparables_encontrados: int,
                               comparables_faltantes: Sequence[str], min_comparables: int = 8) -> Dict[str, Any]:
    """
    Registra la ejecución de un comercio e inserta sus observaciones válidas dentro de
    una transacción. Si algo falla, se revierte la inserción y la ejecución queda como
    'fallida' con el motivo. Devuelve el resumen del comercio.
    """
    cur = con.execute(
        """INSERT INTO ejecuciones (id_corrida, fecha_hora_inicio, comercio, total_reportado_sitio,
               total_obtenido, n_registros, estado, modo, archivo_raw)
           VALUES (?, ?, ?, ?, 0, 0, 'parcial', ?, ?)""",
        (id_corrida, ahora(), comercio, total_reportado, modo, archivo_raw),
    )
    id_ejecucion = int(cur.lastrowid)
    con.commit()

    total_obtenido = int(validas["id_producto_comercio"].nunique()) + int(len(rechazadas))
    resumen = {"comercio": comercio, "id_corrida": id_corrida, "id_ejecucion": id_ejecucion,
               "recolectados": total_obtenido, "insertados": 0, "rechazados": int(len(rechazadas)),
               "productos_nuevos": 0, "cambios_precio": 0, "no_observados": 0,
               "comparables": comparables_encontrados, "estado": "fallida", "motivo": motivo}
    try:
        with con:  # transacción: se confirma al salir o se revierte si hay excepción
            sql = (f"INSERT OR IGNORE INTO observaciones (id_corrida, id_ejecucion, {', '.join(COLUMNAS_INSERCION)}) "
                   f"VALUES (?, ?, {_marcadores(COLUMNAS_INSERCION)})")
            insertados = 0
            for fila in validas.to_dict("records"):
                valores = [id_corrida, id_ejecucion] + [_valor_sql(fila.get(c)) for c in COLUMNAS_INSERCION]
                if valores[2 + COLUMNAS_INSERCION.index("es_promocion")] is None:
                    valores[2 + COLUMNAS_INSERCION.index("es_promocion")] = 0
                if valores[2 + COLUMNAS_INSERCION.index("comparable")] is None:
                    valores[2 + COLUMNAS_INSERCION.index("comparable")] = 0
                if valores[2 + COLUMNAS_INSERCION.index("en_categoria")] is None:
                    valores[2 + COLUMNAS_INSERCION.index("en_categoria")] = 1
                c = con.execute(sql, valores)
                insertados += c.rowcount
            for fila in rechazadas.to_dict("records"):
                con.execute(
                    """INSERT INTO observaciones_rechazadas (id_corrida, id_ejecucion, comercio, id_producto_comercio,
                           nombre_original, precio_actual, url, fecha_hora_consulta, motivo, fecha_registro)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (id_corrida, id_ejecucion, comercio, _valor_sql(fila.get("id_producto_comercio")),
                     _valor_sql(fila.get("nombre_original")), _valor_sql(fila.get("precio_actual")),
                     _valor_sql(fila.get("url")), _valor_sql(fila.get("fecha_hora_consulta")), fila["motivo"], ahora()),
                )
            estadisticas = _estadisticas_ejecucion(con, comercio, id_ejecucion, timestamp)

            motivos = [m for m in [motivo] if m]
            if insertados == 0 and len(validas) > 0:
                motivos.append("Las observaciones ya estaban en la base (copia cruda ya cargada); no se duplicaron.")
            if comparables_encontrados < min_comparables:
                motivos.append(f"Solo {comparables_encontrados} productos comparables; faltan: {', '.join(comparables_faltantes)}")
            if total_reportado is None:
                motivos.append("El sitio no reportó el total de productos de la categoría.")
            elif total_obtenido < total_reportado:
                motivos.append(f"Se obtuvieron {total_obtenido} de {total_reportado} productos reportados por el sitio.")
            estado = _estado_ejecucion(len(validas), total_obtenido, total_reportado, fallo,
                                       comparables_encontrados >= min_comparables)
            con.execute(
                """UPDATE ejecuciones SET fecha_hora_fin = ?, total_obtenido = ?, n_registros = ?, estado = ?,
                       n_rechazadas = ?, n_productos_nuevos = ?, n_cambios_precio = ?, n_no_observados = ?,
                       comparables_encontrados = ?, motivo = ?
                   WHERE id_ejecucion = ?""",
                (ahora(), total_obtenido, insertados, estado, len(rechazadas), estadisticas["productos_nuevos"],
                 estadisticas["cambios_precio"], estadisticas["no_observados"], comparables_encontrados,
                 " | ".join(motivos) or None, id_ejecucion),
            )
        resumen.update(estadisticas)
        resumen.update({"insertados": insertados, "estado": estado, "motivo": " | ".join(motivos) or None})
    except Exception as e:
        texto = f"Inserción revertida: {type(e).__name__}: {e}"
        con.execute("UPDATE ejecuciones SET fecha_hora_fin = ?, estado = 'fallida', n_registros = 0, motivo = ? WHERE id_ejecucion = ?",
                    (ahora(), texto, id_ejecucion))
        con.commit()
        resumen.update({"estado": "fallida", "motivo": texto, "insertados": 0})
    return resumen


def _estadisticas_ejecucion(con: sqlite3.Connection, comercio: str, id_ejecucion: int,
                            timestamp: Optional[str]) -> Dict[str, int]:
    """Productos nuevos, cambios de precio y no observados frente a la observación previa del comercio."""
    if not timestamp:
        return {"productos_nuevos": 0, "cambios_precio": 0, "no_observados": 0}
    nuevos = con.execute(
        """SELECT COUNT(*) FROM observaciones o
           WHERE o.id_ejecucion = ? AND NOT EXISTS (
               SELECT 1 FROM observaciones p WHERE p.comercio = o.comercio
                 AND p.id_producto_comercio = o.id_producto_comercio AND p.fecha_hora_consulta < o.fecha_hora_consulta)""",
        (id_ejecucion,),
    ).fetchone()[0]
    cambios = con.execute(
        """SELECT COUNT(*) FROM observaciones o
           WHERE o.id_ejecucion = ? AND o.precio_actual <> (
               SELECT p.precio_actual FROM observaciones p WHERE p.comercio = o.comercio
                 AND p.id_producto_comercio = o.id_producto_comercio AND p.fecha_hora_consulta < o.fecha_hora_consulta
               ORDER BY p.fecha_hora_consulta DESC LIMIT 1)""",
        (id_ejecucion,),
    ).fetchone()[0]
    previa = con.execute(
        """SELECT MAX(fecha_hora_consulta) FROM observaciones WHERE comercio = ? AND fecha_hora_consulta < ?""",
        (comercio, timestamp),
    ).fetchone()[0]
    no_obs = 0
    if previa:
        no_obs = con.execute(
            """SELECT COUNT(*) FROM observaciones p
               WHERE p.comercio = ? AND p.fecha_hora_consulta = ? AND NOT EXISTS (
                   SELECT 1 FROM observaciones o WHERE o.comercio = p.comercio
                     AND o.id_producto_comercio = p.id_producto_comercio AND o.fecha_hora_consulta = ?)""",
            (comercio, previa, timestamp),
        ).fetchone()[0]
    return {"productos_nuevos": int(nuevos), "cambios_precio": int(cambios), "no_observados": int(no_obs)}


def finalizar_corrida(con: sqlite3.Connection, id_corrida: int) -> str:
    fila = con.execute(
        """SELECT COUNT(*), SUM(estado = 'completa'), SUM(estado = 'fallida'), SUM(n_registros)
           FROM ejecuciones WHERE id_corrida = ?""", (id_corrida,)).fetchone()
    n, completas, fallidas, insertadas = fila[0], fila[1] or 0, fila[2] or 0, fila[3] or 0
    if n == 0 or fallidas == n:
        estado = "fallida"
    elif completas == n:
        estado = "completa"
    else:
        estado = "parcial"
    fecha_datos = con.execute("SELECT MAX(fecha_hora_consulta) FROM observaciones WHERE id_corrida = ?",
                              (id_corrida,)).fetchone()[0]
    con.execute("UPDATE corridas SET fecha_hora_fin = ?, n_total_observaciones = ?, estado = ?, fecha_datos = ? WHERE id_corrida = ?",
                (ahora(), insertadas, estado, fecha_datos, id_corrida))
    con.commit()
    return estado


# =====================================================================
# LECTURA: FILTROS
# =====================================================================
def validar_texto_busqueda(texto: Optional[str]) -> str:
    """Valida el texto de búsqueda: longitud máxima y caracteres permitidos. Lanza ValueError."""
    texto = (texto or "").strip()
    if len(texto) > MAX_LARGO_BUSQUEDA:
        raise ValueError(f"La búsqueda admite máximo {MAX_LARGO_BUSQUEDA} caracteres.")
    if not _PATRON_BUSQUEDA.match(texto):
        raise ValueError("La búsqueda solo admite letras, números, espacios y los signos - + . , ' / & °.")
    return texto


@dataclass(frozen=True)
class Filtros:
    comercios: Tuple[str, ...] = ()
    subcategorias: Tuple[str, ...] = ()
    marcas: Tuple[str, ...] = ()
    precio_min: Optional[float] = None
    precio_max: Optional[float] = None
    id_corrida: Optional[int] = None
    fecha_desde: Optional[str] = None      # AAAA-MM-DD (si no se elige una corrida)
    fecha_hasta: Optional[str] = None
    solo_promociones: bool = False
    solo_comparables: bool = False
    texto: str = ""
    incluir_fuera_categoria: bool = False


def _where(f: Filtros, alias: str = "v") -> Tuple[str, List[Any]]:
    """Construye la cláusula WHERE con marcadores ? y la lista de parámetros."""
    cond: List[str] = []
    params: List[Any] = []
    if not f.incluir_fuera_categoria:
        cond.append(f"{alias}.en_categoria = 1")
    if f.comercios:
        cond.append(f"{alias}.comercio IN ({_marcadores(f.comercios)})")
        params += list(f.comercios)
    if f.subcategorias:
        cond.append(f"{alias}.subcategoria_estandar IN ({_marcadores(f.subcategorias)})")
        params += list(f.subcategorias)
    if f.marcas:
        cond.append(f"{alias}.marca_estandar IN ({_marcadores(f.marcas)})")
        params += list(f.marcas)
    if f.precio_min is not None:
        cond.append(f"{alias}.precio_actual >= ?")
        params.append(float(f.precio_min))
    if f.precio_max is not None:
        cond.append(f"{alias}.precio_actual <= ?")
        params.append(float(f.precio_max))
    if f.id_corrida is not None:
        cond.append(f"{alias}.id_corrida = ?")
        params.append(int(f.id_corrida))
    else:
        if f.fecha_desde:
            cond.append(f"substr({alias}.fecha_hora_consulta, 1, 10) >= ?")
            params.append(f.fecha_desde)
        if f.fecha_hasta:
            cond.append(f"substr({alias}.fecha_hora_consulta, 1, 10) <= ?")
            params.append(f.fecha_hasta)
    if f.solo_promociones:
        cond.append(f"{alias}.es_promocion = 1")
    if f.solo_comparables:
        cond.append(f"{alias}.comparable = 1")
    texto = validar_texto_busqueda(f.texto)
    for palabra in texto.split():
        patron = "%" + palabra.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        cond.append(f"({alias}.nombre_original LIKE ? ESCAPE '\\' OR {alias}.descripcion_original LIKE ? ESCAPE '\\')")
        params += [patron, patron]
    return ("WHERE " + " AND ".join(cond)) if cond else "", params


# =====================================================================
# LECTURA: CATÁLOGOS Y OPCIONES
# =====================================================================
def listar_corridas(con: sqlite3.Connection) -> pd.DataFrame:
    return _df(con, "SELECT * FROM v_corridas ORDER BY orden DESC")


def ultima_corrida(con: sqlite3.Connection) -> Optional[Dict[str, Any]]:
    df = _df(con, "SELECT * FROM v_corridas ORDER BY orden DESC LIMIT 1")
    return None if df.empty else df.iloc[0].to_dict()


def opciones_filtros(con: sqlite3.Connection) -> Dict[str, Any]:
    comercios = _df(con, "SELECT DISTINCT comercio FROM v_observaciones ORDER BY comercio")["comercio"].tolist()
    subcats = _df(con, """SELECT DISTINCT subcategoria_estandar AS s FROM v_observaciones
                          WHERE subcategoria_estandar IS NOT NULL AND en_categoria = 1 ORDER BY s""")["s"].tolist()
    marcas = _df(con, """SELECT DISTINCT marca_estandar AS m FROM v_observaciones
                         WHERE marca_estandar IS NOT NULL AND en_categoria = 1 ORDER BY m""")["m"].tolist()
    rango = con.execute("SELECT MIN(precio_actual), MAX(precio_actual), MIN(substr(fecha_hora_consulta,1,10)), "
                        "MAX(substr(fecha_hora_consulta,1,10)) FROM v_observaciones").fetchone()
    return {"comercios": comercios, "subcategorias": subcats, "marcas": marcas,
            "precio_min": rango[0] or 0, "precio_max": rango[1] or 0,
            "fecha_min": rango[2], "fecha_max": rango[3]}


def lista_comparables(con: sqlite3.Connection) -> pd.DataFrame:
    return _df(con, """SELECT id_producto_comun, nombre_estandar, marca_estandar, presentacion_estandar,
                              contenido_valor, contenido_unidad, ean
                       FROM productos_comparables ORDER BY marca_estandar, nombre_estandar""")


# =====================================================================
# LECTURA: TABLA, INDICADORES Y GRÁFICOS
# =====================================================================
def observaciones_filtradas(con: sqlite3.Connection, f: Filtros, limite: int = 5000) -> pd.DataFrame:
    where, params = _where(f)
    sql = f"""
        SELECT v.comercio, v.nombre_original AS nombre, v.marca_estandar AS marca,
               v.subcategoria_estandar AS subcategoria, v.presentacion_original AS presentacion,
               v.contenido_valor, v.contenido_unidad, v.precio_actual AS precio, v.precio_lista,
               v.precio_por_unidad, v.es_promocion, v.comparable, v.id_producto_comun,
               COALESCE(v.estado_disponibilidad, 'sin_informacion') AS disponibilidad,
               v.fecha_hora_consulta, v.id_corrida, v.url
        FROM v_observaciones v
        {where}
        ORDER BY v.comercio, v.nombre_original
        LIMIT ?"""
    return _df(con, sql, params + [int(limite)])


def indicadores(con: sqlite3.Connection, f: Filtros) -> Dict[str, Any]:
    """Indicadores principales calculados en SQL sobre el conjunto filtrado."""
    where, params = _where(f)
    base = f"FROM v_observaciones v {where}"
    general = con.execute(
        f"""SELECT COUNT(*), COUNT(DISTINCT v.comercio || '|' || v.id_producto_comercio),
                   ROUND(100.0 * AVG(v.es_promocion), 1), MIN(v.fecha_hora_consulta), MAX(v.fecha_hora_consulta),
                   ROUND(100.0 * AVG(CASE WHEN v.estado_disponibilidad = 'agotado' THEN 1.0 ELSE 0 END), 1)
            {base}""", params).fetchone()
    por_comercio = _df(con, f"""SELECT v.comercio, COUNT(DISTINCT v.id_producto_comercio) AS productos,
                                       COUNT(*) AS observaciones,
                                       ROUND(100.0 * AVG(v.es_promocion), 1) AS pct_promocion
                                {base} GROUP BY v.comercio ORDER BY v.comercio""", params)
    mediana = con.execute(
        f"""WITH f AS (SELECT v.precio_actual AS p,
                              ROW_NUMBER() OVER (ORDER BY v.precio_actual) AS rn, COUNT(*) OVER () AS n
                       {base} {'AND' if where else 'WHERE'} v.precio_actual IS NOT NULL)
            SELECT AVG(p) FROM f WHERE rn IN ((n + 1) / 2, (n + 2) / 2)""", params).fetchone()[0]
    return {"observaciones": general[0], "productos": general[1], "pct_promocion": general[2],
            "fecha_desde": general[3], "fecha_hasta": general[4], "pct_agotados": general[5],
            "mediana_precio": mediana, "por_comercio": por_comercio}


def mediana_por_subcategoria(con: sqlite3.Connection, f: Filtros) -> pd.DataFrame:
    where, params = _where(f)
    extra = "AND" if where else "WHERE"
    return _df(con, f"""
        WITH f AS (
            SELECT v.subcategoria_estandar AS subcategoria, v.precio_actual AS p,
                   ROW_NUMBER() OVER (PARTITION BY v.subcategoria_estandar ORDER BY v.precio_actual) AS rn,
                   COUNT(*) OVER (PARTITION BY v.subcategoria_estandar) AS n
            FROM v_observaciones v {where} {extra} v.precio_actual IS NOT NULL)
        SELECT subcategoria, ROUND(AVG(p)) AS mediana_cop, MAX(n) AS observaciones
        FROM f WHERE rn IN ((n + 1) / 2, (n + 2) / 2)
        GROUP BY subcategoria ORDER BY mediana_cop DESC""", params)


def distribucion_precios(con: sqlite3.Connection, f: Filtros) -> pd.DataFrame:
    where, params = _where(f)
    extra = "AND" if where else "WHERE"
    return _df(con, f"""SELECT v.comercio, v.precio_actual AS precio, v.nombre_original AS nombre
                        FROM v_observaciones v {where} {extra} v.precio_actual IS NOT NULL""", params)


def ahorro_por_producto(con: sqlite3.Connection, id_corrida: int, comercios: Sequence[str] = (),
                        incluir_agotados: bool = False) -> pd.DataFrame:
    """
    Para cada producto comparable de una corrida: precio mínimo y máximo entre comercios,
    ahorro (máximo - mínimo) y comercio(s) más barato(s). Los empates se listan todos.
    """
    cond_com = f"AND comercio IN ({_marcadores(comercios)})" if comercios else ""
    return _df(con, f"""
        WITH p AS (
            SELECT id_producto_comun, nombre_estandar, comercio, precio_actual
            FROM v_comparables WHERE id_corrida = ? {cond_com}
              AND (? = 1 OR COALESCE(estado_disponibilidad, 'disponible') <> 'agotado')),
        r AS (
            SELECT id_producto_comun, nombre_estandar, MIN(precio_actual) AS precio_min,
                   MAX(precio_actual) AS precio_max, COUNT(*) AS n_comercios
            FROM p GROUP BY id_producto_comun, nombre_estandar)
        SELECT r.id_producto_comun, r.nombre_estandar, r.n_comercios, r.precio_min, r.precio_max,
               r.precio_max - r.precio_min AS ahorro_cop,
               ROUND(100.0 * (r.precio_max - r.precio_min) / r.precio_max, 1) AS ahorro_pct,
               (SELECT GROUP_CONCAT(comercio, ' / ') FROM
                   (SELECT comercio FROM p WHERE p.id_producto_comun = r.id_producto_comun
                      AND p.precio_actual = r.precio_min ORDER BY comercio)) AS mas_barato_en
        FROM r WHERE r.n_comercios >= 2
        ORDER BY ahorro_cop DESC, r.nombre_estandar""", [int(id_corrida)] + list(comercios) + [int(incluir_agotados)])


def ahorro_maximo(con: sqlite3.Connection, id_corrida: int, comercios: Sequence[str] = (),
                  incluir_agotados: bool = False) -> Optional[Dict[str, Any]]:
    df = ahorro_por_producto(con, id_corrida, comercios, incluir_agotados)
    return None if df.empty else df.iloc[0].to_dict()


def evolucion_comparable(con: sqlite3.Connection, id_producto_comun: str, comercios: Sequence[str] = ()) -> pd.DataFrame:
    cond_com = f"AND comercio IN ({_marcadores(comercios)})" if comercios else ""
    return _df(con, f"""SELECT id_corrida, fecha_hora_consulta, comercio, precio_actual, precio_lista,
                               es_promocion, estado_disponibilidad, nombre_estandar
                        FROM v_comparables WHERE id_producto_comun = ? {cond_com}
                        ORDER BY fecha_hora_consulta""", [id_producto_comun] + list(comercios))


def precio_unitario_comparables(con: sqlite3.Connection, id_corrida: int, comercios: Sequence[str] = ()) -> pd.DataFrame:
    cond_com = f"AND comercio IN ({_marcadores(comercios)})" if comercios else ""
    return _df(con, f"""SELECT id_producto_comun, nombre_estandar, presentacion_estandar, contenido_valor,
                               contenido_unidad, comercio, precio_actual, precio_por_unidad, estado_disponibilidad,
                               fecha_hora_consulta
                        FROM v_comparables WHERE id_corrida = ? {cond_com}
                        ORDER BY contenido_unidad, nombre_estandar, comercio""", [int(id_corrida)] + list(comercios))


def sobrecosto_por_comercio(con: sqlite3.Connection, id_corrida: int, comercios: Sequence[str] = (),
                            incluir_agotados: bool = False) -> pd.DataFrame:
    """
    Pregunta del consumidor: ¿en qué comercio conviene comprar los comparables y cuánto
    más se paga en los demás? Por comercio: veces que es el más barato (empates
    incluidos) y sobrecosto promedio frente al precio mínimo del producto.
    """
    cond_com = f"AND comercio IN ({_marcadores(comercios)})" if comercios else ""
    return _df(con, f"""
        WITH p AS (
            SELECT id_producto_comun, comercio, precio_actual,
                   MIN(precio_actual) OVER (PARTITION BY id_producto_comun) AS pmin,
                   COUNT(*) OVER (PARTITION BY id_producto_comun) AS n
            FROM v_comparables WHERE id_corrida = ? {cond_com}
              AND (? = 1 OR COALESCE(estado_disponibilidad, 'disponible') <> 'agotado'))
        SELECT comercio, COUNT(*) AS productos_comparados,
               SUM(precio_actual = pmin) AS veces_mas_barato,
               ROUND(AVG(100.0 * (precio_actual - pmin) / pmin), 1) AS sobrecosto_promedio_pct,
               ROUND(SUM(precio_actual - pmin)) AS sobrecosto_total_cop
        FROM p WHERE n >= 2
        GROUP BY comercio ORDER BY sobrecosto_promedio_pct""", [int(id_corrida)] + list(comercios) + [int(incluir_agotados)])


def cambios_ultima_corrida(con: sqlite3.Connection) -> Dict[str, Any]:
    """Número de cambios de precio entre las dos corridas con datos más recientes."""
    corr = _df(con, "SELECT id_corrida, fecha_datos FROM v_corridas ORDER BY orden DESC LIMIT 2")
    if len(corr) < 2:
        return {"n": None, "id_a": None, "id_b": int(corr.iloc[0]["id_corrida"]) if len(corr) else None}
    id_b, id_a = int(corr.iloc[0]["id_corrida"]), int(corr.iloc[1]["id_corrida"])
    n = con.execute(
        """SELECT COUNT(*) FROM v_observaciones a JOIN v_observaciones b
             ON a.comercio = b.comercio AND a.id_producto_comercio = b.id_producto_comercio
           WHERE a.id_corrida = ? AND b.id_corrida = ? AND a.en_categoria = 1 AND a.precio_actual <> b.precio_actual""",
        (id_a, id_b)).fetchone()[0]
    return {"n": int(n), "id_a": id_a, "id_b": id_b}


# =====================================================================
# ANÁLISIS PARA EL CONSUMIDOR
# =====================================================================
def comparar_corridas(con: sqlite3.Connection, id_a: int, id_b: int, comercios: Sequence[str] = (),
                      umbral_pct: float = 10.0, solo_comparables: bool = False) -> Dict[str, pd.DataFrame]:
    """
    Compara dos corridas sobre el mismo anuncio en el mismo comercio.
    Devuelve: cambios (subió/bajó, COP y %), nuevos (en B y no en A) y no_observados (en A y no en B).
    """
    cond = ["x.en_categoria = 1"]
    params_extra: List[Any] = []
    if comercios:
        cond.append(f"x.comercio IN ({_marcadores(comercios)})")
        params_extra += list(comercios)
    if solo_comparables:
        cond.append("x.comparable = 1")
    filtro = " AND ".join(cond)

    cambios = _df(con, f"""
        SELECT b.comercio, b.nombre_original AS nombre, b.marca_estandar AS marca,
               a.precio_actual AS precio_anterior, b.precio_actual AS precio_nuevo,
               b.precio_actual - a.precio_actual AS cambio_cop,
               ROUND(100.0 * (b.precio_actual - a.precio_actual) / a.precio_actual, 2) AS cambio_pct,
               CASE WHEN b.precio_actual > a.precio_actual THEN 'subió' ELSE 'bajó' END AS direccion,
               CASE WHEN ABS(100.0 * (b.precio_actual - a.precio_actual) / a.precio_actual) >= ? THEN 1 ELSE 0 END AS variacion_grande,
               b.comparable, b.url
        FROM v_observaciones a
        JOIN v_observaciones b ON a.comercio = b.comercio AND a.id_producto_comercio = b.id_producto_comercio
        WHERE a.id_corrida = ? AND b.id_corrida = ? AND a.precio_actual <> b.precio_actual
          AND {filtro.replace('x.', 'b.')}
        ORDER BY ABS(cambio_pct) DESC""", [float(umbral_pct), int(id_a), int(id_b)] + params_extra)

    def _diferencia(id_esta: int, id_no: int) -> pd.DataFrame:
        return _df(con, f"""
            SELECT x.comercio, x.nombre_original AS nombre, x.marca_estandar AS marca,
                   x.precio_actual AS precio, x.comparable, x.url
            FROM v_observaciones x
            WHERE x.id_corrida = ? AND {filtro} AND NOT EXISTS (
                SELECT 1 FROM v_observaciones y WHERE y.id_corrida = ?
                  AND y.comercio = x.comercio AND y.id_producto_comercio = x.id_producto_comercio)
            ORDER BY x.comercio, x.nombre_original""", [int(id_esta)] + params_extra + [int(id_no)])

    resumen = _df(con, f"""
        SELECT b.comercio,
               SUM(b.precio_actual > a.precio_actual) AS subieron,
               SUM(b.precio_actual < a.precio_actual) AS bajaron,
               SUM(b.precio_actual = a.precio_actual) AS sin_cambio
        FROM v_observaciones a
        JOIN v_observaciones b ON a.comercio = b.comercio AND a.id_producto_comercio = b.id_producto_comercio
        WHERE a.id_corrida = ? AND b.id_corrida = ? AND {filtro.replace('x.', 'b.')}
        GROUP BY b.comercio ORDER BY b.comercio""", [int(id_a), int(id_b)] + params_extra)
    return {"cambios": cambios, "nuevos": _diferencia(id_b, id_a), "no_observados": _diferencia(id_a, id_b),
            "resumen": resumen}


def calcular_canasta(con: sqlite3.Connection, id_corrida: int, items: Sequence[Tuple[str, int]],
                     incluir_agotados: bool = False) -> Dict[str, Any]:
    """
    Canasta de productos comparables con precios de una misma corrida.
    - por_comercio: total solo si el comercio tiene todos los productos (disponibles);
      si falta alguno, total = NULL y se listan los faltantes.
    - detalle_optimo: cada producto donde es más barato (empates: todos los comercios).
    - total_optimo: costo mínimo comprando cada producto donde es más barato (None si
      algún producto no está en ningún comercio).
    Por defecto, los productos agotados según el sitio no se consideran disponibles.
    """
    items = [(str(i), int(q)) for i, q in items if int(q) > 0]
    if not items:
        return {"por_comercio": pd.DataFrame(), "detalle_optimo": pd.DataFrame(), "total_optimo": None,
                "comercio_mas_barato": None, "ahorro_vs_un_comercio": None}
    valores = ", ".join("(?, ?)" for _ in items)
    params_sel: List[Any] = [v for par in items for v in par]
    cte = f"""
        WITH sel(id_producto_comun, cantidad) AS (VALUES {valores}),
        precios AS (
            SELECT c.comercio, c.id_producto_comun, MIN(c.precio_actual) AS precio
            FROM v_comparables c JOIN sel s ON s.id_producto_comun = c.id_producto_comun
            WHERE c.id_corrida = ? AND (? = 1 OR COALESCE(c.estado_disponibilidad, 'disponible') <> 'agotado')
            GROUP BY c.comercio, c.id_producto_comun),
        comercios AS (SELECT DISTINCT comercio FROM v_observaciones WHERE id_corrida = ?)"""
    params = params_sel + [int(id_corrida), int(incluir_agotados), int(id_corrida)]

    por_comercio = _df(con, cte + """
        SELECT co.comercio,
               SUM(p.precio IS NOT NULL) AS productos_disponibles,
               COUNT(*) AS productos_canasta,
               CASE WHEN SUM(p.precio IS NULL) = 0 THEN SUM(p.precio * s.cantidad) END AS total_cop,
               GROUP_CONCAT(CASE WHEN p.precio IS NULL THEN pc.nombre_estandar END, '; ') AS faltantes
        FROM comercios co CROSS JOIN sel s
        JOIN productos_comparables pc ON pc.id_producto_comun = s.id_producto_comun
        LEFT JOIN precios p ON p.comercio = co.comercio AND p.id_producto_comun = s.id_producto_comun
        GROUP BY co.comercio ORDER BY total_cop IS NULL, total_cop""", params)

    detalle = _df(con, cte + """
        , minimos AS (
            SELECT s.id_producto_comun, s.cantidad, MIN(p.precio) AS precio_min
            FROM sel s LEFT JOIN precios p ON p.id_producto_comun = s.id_producto_comun
            GROUP BY s.id_producto_comun, s.cantidad)
        SELECT pc.nombre_estandar AS producto, m.cantidad, m.precio_min AS precio_unitario_cop,
               m.precio_min * m.cantidad AS subtotal_cop,
               (SELECT GROUP_CONCAT(comercio, ' / ') FROM (SELECT comercio FROM precios p
                   WHERE p.id_producto_comun = m.id_producto_comun AND p.precio = m.precio_min ORDER BY comercio)) AS comprar_en
        FROM minimos m JOIN productos_comparables pc ON pc.id_producto_comun = m.id_producto_comun
        ORDER BY pc.nombre_estandar""", params)

    total_optimo = None if detalle.empty or detalle["precio_unitario_cop"].isna().any() else float(detalle["subtotal_cop"].sum())
    completos = por_comercio.dropna(subset=["total_cop"])
    mas_barato = None if completos.empty else completos.iloc[0].to_dict()
    ahorro = None
    if total_optimo is not None and mas_barato is not None:
        ahorro = float(mas_barato["total_cop"]) - total_optimo
    if total_optimo is not None and not por_comercio.empty:
        por_comercio["ahorro_optimo_vs_comercio_cop"] = por_comercio["total_cop"] - total_optimo
    return {"por_comercio": por_comercio, "detalle_optimo": detalle, "total_optimo": total_optimo,
            "comercio_mas_barato": mas_barato, "ahorro_vs_un_comercio": ahorro}


# =====================================================================
# TRAZABILIDAD
# =====================================================================
def resumen_ejecuciones(con: sqlite3.Connection, limite: int = 100) -> pd.DataFrame:
    return _df(con, "SELECT * FROM v_resumen_ejecuciones ORDER BY id_ejecucion DESC LIMIT ?", [int(limite)])


def ultimas_ejecuciones_corrida(con: sqlite3.Connection, id_corrida: int) -> pd.DataFrame:
    return _df(con, "SELECT * FROM v_resumen_ejecuciones WHERE id_corrida = ? ORDER BY comercio", [int(id_corrida)])


def listar_correcciones(con: sqlite3.Connection) -> pd.DataFrame:
    return _df(con, "SELECT * FROM correcciones ORDER BY id_correccion")


def listar_rechazadas(con: sqlite3.Connection, limite: int = 500) -> pd.DataFrame:
    return _df(con, "SELECT * FROM observaciones_rechazadas ORDER BY id_rechazo DESC LIMIT ?", [int(limite)])


def disponibilidad_por_comercio(con: sqlite3.Connection, id_corrida: int) -> pd.DataFrame:
    return _df(con, """SELECT comercio, estado, COUNT(*) AS anuncios FROM v_disponibilidad
                       WHERE id_corrida = ? GROUP BY comercio, estado ORDER BY comercio, estado""", [int(id_corrida)])
