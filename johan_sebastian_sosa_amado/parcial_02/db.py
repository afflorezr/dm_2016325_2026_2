"""
Acceso a la base comparador_precios.sqlite. Todo el SQL de la aplicación
está aquí; las páginas solo llaman estas funciones.

Primero va preparar_base(), que agrega a la base del Taller 1 las tablas,
columnas, índices y vistas nuevas. Se puede correr muchas veces: solo crea
lo que falta y nunca borra observaciones. Después van las consultas de la app.
"""

import re
import sqlite3
from contextlib import closing, contextmanager
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pandas as pd

# Ruta relativa a la carpeta del taller (no al lugar desde donde se ejecuta):
# Streamlit Community Cloud corre la app desde la raíz del repositorio.
CARPETA = Path(__file__).resolve().parent
RUTA_BASE = CARPETA / "comparador_precios.sqlite"
HORA_COLOMBIA = ZoneInfo("America/Bogota")


# Estructura de la base

TABLAS_NUEVAS = [
    # Cada corrección hecha a la base del Taller 1, con el valor anterior.
    """
    CREATE TABLE IF NOT EXISTS correcciones (
        correccion_id  INTEGER PRIMARY KEY,
        fecha          TEXT NOT NULL,       -- ISO 8601, hora de Colombia
        tabla          TEXT NOT NULL,       -- tabla afectada (anuncios, observaciones...)
        registro_id    INTEGER NOT NULL,    -- id de la fila afectada en esa tabla
        referencia     TEXT,                -- comercio y SKU, para leerlo sin buscar
        campo          TEXT NOT NULL,
        valor_anterior TEXT,
        valor_nuevo    TEXT,
        motivo         TEXT NOT NULL,
        UNIQUE (tabla, registro_id, campo, valor_nuevo)
    );
    """,
    # Lo que no pasa la validación no entra a observaciones, pero queda aquí.
    """
    CREATE TABLE IF NOT EXISTS rechazos (
        rechazo_id          INTEGER PRIMARY KEY,
        ejecucion_id        TEXT NOT NULL,
        comercio            TEXT,
        sku                 TEXT,
        url                 TEXT,
        fecha_hora_consulta TEXT,
        regla               TEXT NOT NULL,  -- regla de validación que falló
        detalle             TEXT
    );
    """,
    # Código estable de cada producto comparable (P01, P02...). La limpieza
    # rehace la tabla productos en cada corrida; aquí el código de un EAN no
    # cambia aunque ese producto falte en alguna ejecución.
    """
    CREATE TABLE IF NOT EXISTS codigos_producto (
        ean         TEXT PRIMARY KEY,
        producto_id TEXT NOT NULL UNIQUE
    );
    """,
]

# Columnas nuevas: se agregan con ALTER TABLE solo si no existen
# (se revisa con PRAGMA table_info).
COLUMNAS_NUEVAS = {
    "anuncios": {
        "variante": "TEXT",              # línea del producto: clasico, ultra, nocturno...
        "contenido_total": "REAL",       # cantidad del empaque
        "unidad_normalizada": "TEXT",    # 'unidad', 'mL' o 'g'
    },
    "observaciones": {
        # 'disponible' o 'agotado' según el sitio. El tercer estado,
        # 'no observado', no es una fila: sale de la vista v_disponibilidad.
        "estado_disponibilidad": "TEXT",
        "descartada": "INTEGER NOT NULL DEFAULT 0",   # 1 = no se usa (ver correcciones)
    },
}

INDICES = [
    # La misma observación no puede entrar dos veces en una ejecución.
    # (La del Taller 1, anuncio + fecha y hora, se mantiene.)
    "CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_anuncio_ejecucion ON observaciones (anuncio_id, ejecucion_id);",
    # Columnas que usan los filtros de la aplicación.
    "CREATE INDEX IF NOT EXISTS ix_obs_ejecucion   ON observaciones (ejecucion_id);",
    "CREATE INDEX IF NOT EXISTS ix_obs_precio      ON observaciones (precio);",
    "CREATE INDEX IF NOT EXISTS ix_obs_promocion   ON observaciones (promocion);",
    "CREATE INDEX IF NOT EXISTS ix_anu_comercio    ON anuncios (comercio_id);",
    "CREATE INDEX IF NOT EXISTS ix_anu_producto    ON anuncios (producto_id);",
    "CREATE INDEX IF NOT EXISTS ix_anu_subcat      ON anuncios (subcategoria_estandar);",
    "CREATE INDEX IF NOT EXISTS ix_anu_marca       ON anuncios (marca_estandar);",
    "CREATE INDEX IF NOT EXISTS ix_eje_recoleccion ON ejecuciones (recoleccion_id);",
    "CREATE INDEX IF NOT EXISTS ix_eje_comercio    ON ejecuciones (comercio_id, fecha_hora_inicio);",
]

# Las vistas se borran y se vuelven a crear para que siempre tengan la
# definición de este archivo.
VISTAS = {
    # Una fila por observación, con todo lo que muestra la tabla de la app.
    # precio_unitario: COP por pañal, por mL o por g.
    "v_observaciones": """
        CREATE VIEW v_observaciones AS
        SELECT o.observacion_id, o.ejecucion_id, e.recoleccion_id,
               c.clave AS comercio_clave, c.nombre AS comercio,
               a.anuncio_id, a.sku, a.ean, a.nombre_original,
               a.marca_estandar AS marca, a.subcategoria_estandar AS subcategoria,
               a.variante, a.talla, a.presentacion_original,
               a.contenido_total, a.unidad_normalizada,
               a.producto_id, a.comparable, a.url,
               o.precio, o.precio_antes, o.promocion,
               o.estado_disponibilidad, o.fecha_hora_consulta,
               ROUND(o.precio / a.contenido_total, 1) AS precio_unitario
        FROM   observaciones AS o
        JOIN   anuncios      AS a ON a.anuncio_id   = o.anuncio_id
        JOIN   comercios     AS c ON c.comercio_id  = a.comercio_id
        JOIN   ejecuciones   AS e ON e.ejecucion_id = o.ejecucion_id
        WHERE  a.en_categoria = 1
          AND  o.descartada   = 0;
    """,
    # Precio de cada anuncio en la ejecución más reciente (no fallida) de su comercio.
    "v_ultimo_precio": """
        CREATE VIEW v_ultimo_precio AS
        WITH ultima AS (
            SELECT comercio_id, MAX(fecha_hora_inicio) AS inicio
            FROM   ejecuciones
            WHERE  estado <> 'fallida'
            GROUP  BY comercio_id
        )
        SELECT v.*
        FROM   v_observaciones AS v
        JOIN   ejecuciones     AS e ON e.ejecucion_id = v.ejecucion_id
        JOIN   ultima          AS u ON u.comercio_id  = e.comercio_id
                                   AND u.inicio       = e.fecha_hora_inicio;
    """,
    # Cambio de precio de cada anuncio frente a su observación anterior
    # (con LAG), siempre del mismo anuncio en el mismo comercio. Trae las
    # columnas de los filtros del panel para que el indicador los respete.
    "v_cambios_precio": """
        CREATE VIEW v_cambios_precio AS
        WITH serie AS (
            SELECT v.*,
                   LAG(v.precio)         OVER (PARTITION BY v.anuncio_id ORDER BY v.fecha_hora_consulta) AS precio_anterior,
                   LAG(v.recoleccion_id) OVER (PARTITION BY v.anuncio_id ORDER BY v.fecha_hora_consulta) AS recoleccion_anterior
            FROM   v_observaciones AS v
        )
        SELECT recoleccion_id, recoleccion_anterior, comercio, anuncio_id,
               nombre_original, presentacion_original, marca, subcategoria,
               producto_id, promocion, precio_anterior, precio,
               precio - precio_anterior AS cambio_cop,
               ROUND(100.0 * (precio - precio_anterior) / precio_anterior, 1) AS cambio_pct
        FROM   serie
        WHERE  precio IS NOT NULL
          AND  precio_anterior IS NOT NULL
          AND  precio <> precio_anterior;
    """,
    # Productos comparables en cada recolección: precio, precio unitario y
    # puesto entre comercios. RANK deja empatados a los que tienen el mismo precio.
    "v_comparables": """
        CREATE VIEW v_comparables AS
        SELECT p.producto_id, p.descripcion, p.talla, p.ean,
               v.recoleccion_id, v.comercio, v.precio, v.precio_unitario,
               v.contenido_total, v.unidad_normalizada, v.promocion,
               v.estado_disponibilidad, v.fecha_hora_consulta, v.url,
               RANK() OVER (PARTITION BY p.producto_id, v.recoleccion_id
                            ORDER BY v.precio) AS puesto
        FROM   productos       AS p
        JOIN   v_observaciones AS v ON v.producto_id = p.producto_id
        WHERE  v.precio IS NOT NULL;
    """,
    # Tres estados: para cada anuncio de la categoría y cada
    # ejecución de su comercio, disponible / agotado según el sitio / no
    # observado (no apareció en esa ejecución), gracias al LEFT JOIN.
    "v_disponibilidad": """
        CREATE VIEW v_disponibilidad AS
        SELECT e.ejecucion_id, e.recoleccion_id, c.nombre AS comercio,
               a.anuncio_id, a.nombre_original, a.producto_id,
               COALESCE(o.estado_disponibilidad, 'no observado') AS estado
        FROM   anuncios    AS a
        JOIN   comercios   AS c ON c.comercio_id = a.comercio_id
        JOIN   ejecuciones AS e ON e.comercio_id = a.comercio_id
        LEFT JOIN observaciones AS o ON o.anuncio_id   = a.anuncio_id
                                    AND o.ejecucion_id = e.ejecucion_id
        WHERE  a.en_categoria = 1
          AND  e.estado <> 'fallida';
    """,
}


def ahora_colombia():
    return datetime.now(HORA_COLOMBIA).isoformat(timespec="seconds")


def preparar_base(con):
    """Agrega a la base del Taller 1 lo nuevo del Taller 2. Se puede repetir
    sin dañar nada."""
    cur = con.cursor()
    for sql in TABLAS_NUEVAS:
        cur.execute(sql)
    for tabla, columnas in COLUMNAS_NUEVAS.items():
        existentes = pd.read_sql_query(f"PRAGMA table_info({tabla});", con)["name"].tolist()
        for columna, tipo in columnas.items():
            if columna not in existentes:
                cur.execute(f"ALTER TABLE {tabla} ADD COLUMN {columna} {tipo};")
    cur.execute("""
        INSERT OR IGNORE INTO codigos_producto (ean, producto_id)
        SELECT ean, producto_id FROM productos WHERE ean IS NOT NULL;
    """)
    aplicar_correcciones(con)          # primero lo corregido...
    actualizar_campos_derivados(con)   # ...y después lo que se calcula a partir de ello
    normalizar_carpetas_raw(con)
    for sql in INDICES:
        cur.execute(sql)
    for nombre, sql in VISTAS.items():
        cur.execute(f"DROP VIEW IF EXISTS {nombre};")
    for nombre, sql in VISTAS.items():     # en orden: las de abajo usan v_observaciones
        cur.execute(sql)
    con.commit()


def actualizar_campos_derivados(con):
    """Llena las columnas que salen de otras: estado de disponibilidad,
    contenido total y unidad normalizada. Se vuelve a correr después de
    cada limpieza y después de aplicar las correcciones (por ejemplo, un
    contenido corregido pasa así a contenido_total)."""
    cur = con.cursor()
    cur.execute("""
        UPDATE observaciones
        SET    estado_disponibilidad = CASE WHEN disponible = 1 THEN 'disponible'
                                            ELSE 'agotado' END;
    """)
    cur.execute("""
        UPDATE anuncios
        SET    contenido_total    = contenido,
               unidad_normalizada = CASE unidad WHEN 'und' THEN 'unidad'
                                                WHEN 'mL'  THEN 'mL'
                                                WHEN 'g'   THEN 'g' END;
    """)


def ruta_relativa_raw(ruta):
    """Deja la ruta de una copia relativa a la carpeta del taller (desde raw),
    para que la base no guarde la ruta del equipo donde se corrió. Conserva
    el separador que traía la ruta: \\ en Windows, / en Linux."""
    ruta = str(ruta or "")
    partes = re.split(r"[\\/]", ruta)
    if "raw" not in partes:
        return ruta
    inicio = len(partes) - 1 - partes[::-1].index("raw")
    return ("\\" if "\\" in ruta else "/").join(partes[inicio:])


def normalizar_carpetas_raw(con):
    """Deja relativas las rutas de carpeta_raw que se guardaron completas."""
    filas = con.execute("SELECT ejecucion_id, carpeta_raw FROM ejecuciones;").fetchall()
    for ejecucion_id, ruta in filas:
        if ruta and ruta_relativa_raw(ruta) != ruta:
            con.execute("UPDATE ejecuciones SET carpeta_raw = ? WHERE ejecucion_id = ?;",
                        (ruta_relativa_raw(ruta), ejecucion_id))


# Correcciones

def registrar_correccion(con, tabla, registro_id, campo, valor_nuevo, motivo, referencia=None):
    """Guarda una corrección en la tabla correcciones (si no estaba ya) y la
    aplica. El valor anterior se lee de la base antes de cambiarlo.
    Solo se aceptan tablas y campos conocidos: el nombre de una columna no
    puede ir como parámetro "?" en SQL."""
    permitidos = {"anuncios": {"contenido", "contenido_total", "variante", "producto_id",
                               "comparable", "talla"},
                  "observaciones": {"descartada", "precio"}}
    if campo not in permitidos.get(tabla, set()):
        raise ValueError(f"corrección no permitida: {tabla}.{campo}")
    llave = "anuncio_id" if tabla == "anuncios" else "observacion_id"
    anterior = con.execute(f"SELECT {campo} FROM {tabla} WHERE {llave} = ?;",
                           (registro_id,)).fetchone()
    if anterior is None:
        raise ValueError(f"no existe {tabla} con {llave} = {registro_id}")
    con.execute("""
        INSERT OR IGNORE INTO correcciones
              (fecha, tabla, registro_id, referencia, campo, valor_anterior, valor_nuevo, motivo)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    """, (ahora_colombia(), tabla, registro_id, referencia, campo,
          None if anterior[0] is None else str(anterior[0]),
          None if valor_nuevo is None else str(valor_nuevo), motivo))
    con.execute(f"UPDATE {tabla} SET {campo} = ? WHERE {llave} = ?;", (valor_nuevo, registro_id))


def aplicar_correcciones(con):
    """Vuelve a aplicar todas las correcciones registradas. Hace falta porque
    la limpieza del scraper recalcula los campos estandarizados desde el
    texto original cada vez que corre; sin esto, una corrección se perdería
    en la siguiente actualización."""
    filas = con.execute("""
        SELECT tabla, registro_id, campo, valor_nuevo
        FROM   correcciones
        ORDER  BY correccion_id;
    """).fetchall()
    for tabla, registro_id, campo, valor in filas:
        llave = "anuncio_id" if tabla == "anuncios" else "observacion_id"
        con.execute(f"UPDATE {tabla} SET {campo} = ? WHERE {llave} = ?;", (valor, registro_id))
    con.commit()
    return len(filas)


def conectar(ruta=RUTA_BASE):
    """Abre la base y se asegura de que tenga la estructura del Taller 2."""
    con = sqlite3.connect(ruta)
    con.execute("PRAGMA foreign_keys = ON;")
    preparar_base(con)
    return con


# Consultas de la aplicación.
# Cada función recibe los filtros y devuelve una tabla. Filtros y cálculos se
# hacen en SQL, y lo que escribe el usuario siempre va como parámetro "?",
# nunca pegado al texto de la consulta.

LARGO_MAXIMO_BUSQUEDA = 60
PATRON_BUSQUEDA = re.compile(r"^[0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ .,()/%+-]*$")


@contextmanager
def leer(ruta=RUTA_BASE):
    """Conexión de solo lectura que se cierra al terminar el bloque with."""
    with closing(sqlite3.connect(f"file:{Path(ruta).as_posix()}?mode=ro", uri=True)) as con:
        yield con


def consultar(sql, params=(), ruta=RUTA_BASE):
    """Ejecuta una consulta con parámetros y devuelve un DataFrame."""
    with leer(ruta) as con:
        return pd.read_sql_query(sql, con, params=list(params))


def validar_busqueda(texto):
    """Revisa el texto que escribe el usuario: máximo 60 caracteres y solo
    letras, números y algunos signos. Si no cumple, lanza ValueError."""
    texto = " ".join((texto or "").split())
    if len(texto) > LARGO_MAXIMO_BUSQUEDA:
        raise ValueError(f"La búsqueda admite máximo {LARGO_MAXIMO_BUSQUEDA} caracteres.")
    if not PATRON_BUSQUEDA.match(texto):
        raise ValueError("La búsqueda solo admite letras, números, espacios y . , ( ) / % + -")
    return texto


def marcas_in(valores):
    """'?, ?, ?' para una lista de valores en IN (...)."""
    return ", ".join("?" * len(valores))


def condiciones(filtros):
    """Arma el WHERE de los filtros del panel lateral. Devuelve (sql, params).
    filtros es un diccionario con: recoleccion_id, comercios, subcategorias,
    marcas, precio_min, precio_max, solo_promociones, solo_comparables, texto."""
    partes, params = ["1 = 1"], []
    if filtros.get("recoleccion_id"):
        partes.append("recoleccion_id = ?")
        params.append(filtros["recoleccion_id"])
    for campo, columna in (("comercios", "comercio"), ("subcategorias", "subcategoria"),
                           ("marcas", "marca")):
        valores = filtros.get(campo)
        if valores:
            partes.append(f"{columna} IN ({marcas_in(valores)})")
            params.extend(valores)
    if filtros.get("precio_min") is not None:
        partes.append("precio >= ?")
        params.append(filtros["precio_min"])
    if filtros.get("precio_max") is not None:
        partes.append("precio <= ?")
        params.append(filtros["precio_max"])
    if filtros.get("solo_promociones"):
        partes.append("promocion = 1")
    if filtros.get("solo_comparables"):
        partes.append("producto_id IS NOT NULL")
    texto = validar_busqueda(filtros.get("texto"))
    if texto:
        # Cada palabra debe aparecer en el nombre o en el texto original del anuncio.
        for palabra in texto.split():
            partes.append("(nombre_original LIKE ? OR presentacion_original LIKE ?)")
            params.extend([f"%{palabra}%", f"%{palabra}%"])
    return " AND ".join(partes), params


def recolecciones(ruta=RUTA_BASE):
    """Una fila por recolección: fecha, comercios y estado de cada uno."""
    return consultar("""
        SELECT   e.recoleccion_id,
                 MIN(e.fecha_hora_inicio) AS inicio,
                 COUNT(*)                 AS comercios,
                 SUM(e.estado = 'completa') AS completas,
                 GROUP_CONCAT(c.nombre || ': ' || e.estado, ', ') AS estados
        FROM     ejecuciones AS e
        JOIN     comercios   AS c ON c.comercio_id = e.comercio_id
        GROUP BY e.recoleccion_id
        HAVING   SUM(e.estado <> 'fallida') > 0
        ORDER BY inicio DESC;
    """, ruta=ruta)


def opciones_filtros(ruta=RUTA_BASE):
    """Valores posibles de cada filtro, leídos de la base."""
    with leer(ruta) as con:
        lista = lambda sql: [f[0] for f in con.execute(sql).fetchall()]
        return {
            "comercios": lista("SELECT nombre FROM comercios ORDER BY nombre;"),
            "subcategorias": lista("SELECT DISTINCT subcategoria FROM v_observaciones "
                                   "WHERE subcategoria IS NOT NULL ORDER BY 1;"),
            "marcas": lista("SELECT DISTINCT marca FROM v_observaciones "
                            "WHERE marca IS NOT NULL ORDER BY 1;"),
            "precio_max": con.execute("SELECT MAX(precio) FROM v_observaciones;").fetchone()[0] or 0,
            "productos": pd.read_sql_query(
                "SELECT producto_id, descripcion, contenido, unidad FROM productos ORDER BY producto_id;", con),
        }


LIMITE_TABLA = 2000


def productos_filtrados(filtros, limite=LIMITE_TABLA + 1, ruta=RUTA_BASE):
    """Productos que cumplen los filtros, para la tabla de la app. Trae una
    fila más que el límite para saber si la tabla quedó cortada."""
    where, params = condiciones(filtros)
    return consultar(f"""
        SELECT comercio, nombre_original AS nombre, marca, subcategoria,
               presentacion_original AS presentacion, contenido_total,
               unidad_normalizada, precio, precio_unitario, precio_antes,
               promocion, estado_disponibilidad AS disponibilidad,
               fecha_hora_consulta, url, producto_id
        FROM   v_observaciones
        WHERE  {where}
        ORDER  BY comercio, nombre_original
        LIMIT  ?;
    """, params + [limite], ruta)


def indicadores(filtros, ruta=RUTA_BASE):
    """Indicadores de la página de resumen. Todos se calculan en SQL
    sobre la recolección y los filtros elegidos. Devuelve un diccionario."""
    where, params = condiciones(filtros)
    with leer(ruta) as con:
        uno = lambda sql, p=params: con.execute(sql, p).fetchone()
        # El porcentaje en promoción se calcula sobre los productos con
        # precio, igual que en el gráfico de promociones (un agotado no
        # tiene precio y no puede estar rebajado).
        n_productos, n_obs, n_con_precio, pct_promocion = uno(f"""
            SELECT COUNT(DISTINCT anuncio_id), COUNT(*), COUNT(precio),
                   ROUND(100.0 * SUM(CASE WHEN precio IS NOT NULL THEN promocion END)
                         / COUNT(precio), 1)
            FROM   v_observaciones WHERE {where};""")
        # SQLite no tiene MEDIAN; la mediana se calcula con ROW_NUMBER y
        # COUNT como funciones de ventana (aquí y en la de subcategorías).
        por_comercio = pd.read_sql_query(f"""
            WITH base AS (SELECT * FROM v_observaciones WHERE {where}),
                 x AS (
                    SELECT comercio, precio,
                           ROW_NUMBER() OVER (PARTITION BY comercio ORDER BY precio) AS fila,
                           COUNT(*)     OVER (PARTITION BY comercio)                 AS n
                    FROM   base WHERE precio IS NOT NULL),
                 mediana AS (
                    SELECT comercio, AVG(precio) AS mediana
                    FROM   x WHERE fila IN ((n + 1) / 2, (n + 2) / 2)
                    GROUP  BY comercio),
                 conteo AS (
                    SELECT comercio, COUNT(DISTINCT anuncio_id) AS productos,
                           COUNT(*) AS observaciones, SUM(promocion) AS en_promocion
                    FROM   base GROUP BY comercio)
            SELECT conteo.*, mediana.mediana
            FROM   conteo LEFT JOIN mediana USING (comercio)
            ORDER  BY mediana.mediana DESC;""", con, params=params)
        medianas = pd.read_sql_query(f"""
            WITH x AS (
                SELECT subcategoria, precio,
                       ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS fila,
                       COUNT(*)     OVER (PARTITION BY subcategoria)                 AS n
                FROM   v_observaciones
                WHERE  {where} AND precio IS NOT NULL
            )
            SELECT subcategoria, AVG(precio) AS mediana, MAX(n) AS n
            FROM   x WHERE fila IN ((n + 1) / 2, (n + 2) / 2)
            GROUP  BY subcategoria ORDER BY n DESC;""", con, params=params)
        ultima = uno("""
            SELECT recoleccion_id, MIN(fecha_hora_inicio),
                   GROUP_CONCAT(estado, ', '), SUM(estado = 'completa'), COUNT(*)
            FROM   ejecuciones
            WHERE  recoleccion_id = (SELECT MAX(recoleccion_id) FROM ejecuciones)
            GROUP  BY recoleccion_id;""", [])
        # Anuncios que cambiaron de precio frente a la recolección anterior.
        anterior = recoleccion_anterior(filtros.get("recoleccion_id"), ruta)
        (n_cambios,) = uno(f"""
            SELECT COUNT(*) FROM v_cambios_precio
            WHERE  {where} AND recoleccion_anterior = ?;""", params + [anterior])
    ahorro = ahorro_comparables(filtros.get("recoleccion_id"), ruta).head(1)
    return {
        "productos": n_productos or 0, "observaciones": n_obs or 0,
        "pct_promocion": pct_promocion,
        "con_precio": n_con_precio or 0,
        "por_comercio": por_comercio, "medianas": medianas,
        "ultima_recoleccion": ultima[0] if ultima else None,
        "ultima_fecha": ultima[1] if ultima else None,
        "ultima_estado": (f"{ultima[3]} de {ultima[4]} comercios completas" if ultima else None),
        "ahorro_maximo": ahorro.iloc[0].to_dict() if len(ahorro) else None,
        "cambios_precio": n_cambios,
    }


def ahorro_comparables(recoleccion_id, ruta=RUTA_BASE):
    """Por producto comparable: precio mínimo y máximo entre comercios, dónde
    es más barato (con empates: todos los que tienen el mínimo) y ahorro."""
    return consultar("""
        WITH p AS (
            SELECT producto_id, descripcion, comercio, precio,
                   MIN(precio) OVER (PARTITION BY producto_id) AS minimo,
                   MAX(precio) OVER (PARTITION BY producto_id) AS maximo
            FROM   v_comparables
            WHERE  recoleccion_id = ?
        )
        SELECT producto_id, descripcion, minimo, maximo,
               maximo - minimo AS ahorro_cop,
               ROUND(100.0 * (maximo - minimo) / maximo, 1) AS ahorro_pct,
               GROUP_CONCAT(CASE WHEN precio = minimo THEN comercio END, ', ') AS mas_barato
        FROM   p
        GROUP  BY producto_id
        ORDER  BY ahorro_cop DESC;
    """, (recoleccion_id,), ruta)


def evolucion_producto(producto_id, ruta=RUTA_BASE):
    """Gráfico 1: precio de un comparable en cada recolección, por comercio."""
    return consultar("""
        SELECT recoleccion_id, MIN(fecha_hora_consulta) AS fecha, comercio,
               MIN(precio) AS precio, MAX(promocion) AS promocion
        FROM   v_comparables
        WHERE  producto_id = ?
        GROUP  BY recoleccion_id, comercio
        ORDER  BY fecha;
    """, (producto_id,), ruta)


def precio_unitario_comparables(recoleccion_id, unidad, ruta=RUTA_BASE):
    """Gráfico 2: precio por unidad de contenido de cada comparable y
    comercio, solo de una unidad (unidad, mL o g) para no mezclarlas."""
    return consultar("""
        SELECT producto_id, descripcion, comercio, precio, contenido_total,
               unidad_normalizada, precio_unitario
        FROM   v_comparables
        WHERE  recoleccion_id = ? AND unidad_normalizada = ?
        ORDER  BY producto_id, comercio;
    """, (recoleccion_id, unidad), ruta)


def precios_para_distribucion(filtros, ruta=RUTA_BASE):
    """Gráfico 3: precios de la categoría por comercio (solo las columnas
    necesarias, ya filtradas en SQL)."""
    where, params = condiciones(filtros)
    return consultar(f"""
        SELECT comercio, subcategoria, precio
        FROM   v_observaciones
        WHERE  {where} AND precio IS NOT NULL;
    """, params, ruta)


def promociones_por_comercio(filtros, ruta=RUTA_BASE):
    """Gráfico libre: ¿dónde hay más promociones y cuánto descuentan en
    realidad? Proporción de productos en promoción y descuento mediano."""
    where, params = condiciones(filtros)
    return consultar(f"""
        WITH d AS (
            SELECT comercio, promocion,
                   CASE WHEN promocion = 1 AND precio_antes > precio
                        THEN 100.0 * (precio_antes - precio) / precio_antes END AS descuento
            FROM   v_observaciones
            WHERE  {where} AND precio IS NOT NULL
        ),
        orden AS (
            SELECT comercio, descuento,
                   ROW_NUMBER() OVER (PARTITION BY comercio ORDER BY descuento) AS fila,
                   COUNT(descuento) OVER (PARTITION BY comercio) AS n
            FROM   d WHERE descuento IS NOT NULL
        ),
        mediana AS (
            SELECT comercio, ROUND(AVG(descuento), 1) AS descuento_mediano
            FROM   orden WHERE fila IN ((n + 1) / 2, (n + 2) / 2)
            GROUP  BY comercio
        )
        SELECT d.comercio, COUNT(*) AS productos_con_precio,
               SUM(d.promocion) AS en_promocion,
               ROUND(100.0 * SUM(d.promocion) / COUNT(*), 1) AS pct_promocion,
               m.descuento_mediano
        FROM   d LEFT JOIN mediana AS m ON m.comercio = d.comercio
        GROUP  BY d.comercio ORDER BY d.comercio;
    """, params, ruta)


def recoleccion_anterior(recoleccion_id, ruta=RUTA_BASE):
    with leer(ruta) as con:
        fila = con.execute("""
            SELECT MAX(recoleccion_id) FROM ejecuciones
            WHERE  recoleccion_id < ? AND estado <> 'fallida';""", (recoleccion_id,)).fetchone()
    return fila[0] if fila else None


def sql_comparacion(comercios):
    """Parte común de cambios_entre() y conteo_cambios(): la tabla
    'comparacion' con un anuncio por fila. Devuelve (sql, params) sin los
    parámetros de las recolecciones y el umbral, que van en ese orden:
    recolección a, comercios, recolección b, comercios, umbral.
    SQLite no tiene FULL JOIN, así que se hace un LEFT JOIN y se le suman
    con UNION ALL los anuncios que solo están en b."""
    de_comercios = f"AND comercio IN ({marcas_in(comercios)})" if comercios else ""
    return f"""
        WITH a AS (SELECT * FROM v_observaciones WHERE recoleccion_id = ? {de_comercios}),
             b AS (SELECT * FROM v_observaciones WHERE recoleccion_id = ? {de_comercios}),
             unidos AS (
                SELECT a.comercio, a.nombre_original, a.producto_id, a.url,
                       a.precio AS precio_a, b.precio AS precio_b,
                       b.anuncio_id IS NULL AS solo_a, 0 AS solo_b
                FROM   a LEFT JOIN b ON b.anuncio_id = a.anuncio_id
                UNION ALL
                SELECT b.comercio, b.nombre_original, b.producto_id, b.url,
                       NULL, b.precio, 0, 1
                FROM   b LEFT JOIN a ON a.anuncio_id = b.anuncio_id
                WHERE  a.anuncio_id IS NULL
             ),
             comparacion AS (
                SELECT comercio, nombre_original, producto_id, url, precio_a, precio_b,
                       precio_b - precio_a AS cambio_cop,
                       ROUND(100.0 * (precio_b - precio_a) / precio_a, 1) AS cambio_pct,
                       CASE WHEN solo_b = 1 THEN 'nuevo'
                            WHEN solo_a = 1 THEN 'dejó de observarse'
                            WHEN precio_a IS NULL OR precio_b IS NULL THEN 'sin precio en una de las dos'
                            WHEN precio_b > precio_a THEN 'subió'
                            WHEN precio_b < precio_a THEN 'bajó'
                            ELSE 'igual' END AS tipo,
                       CASE WHEN precio_b <> precio_a
                             AND ABS(100.0 * (precio_b - precio_a) / precio_a) >= ? THEN 1
                            ELSE 0 END AS grande
                FROM   unidos
             )
    """


def parametros_comparacion(recoleccion_a, recoleccion_b, umbral_pct, comercios):
    comercios = list(comercios or [])
    return [recoleccion_a, *comercios, recoleccion_b, *comercios, umbral_pct]


def cambios_entre(recoleccion_a, recoleccion_b, umbral_pct=0, comercios=None, tipos=None,
                  ruta=RUTA_BASE):
    """Compara dos recolecciones (a = anterior, b = posterior) anuncio por
    anuncio. tipo: subió, bajó, igual, nuevo (solo en b), dejó de observarse
    (solo en a) o sin precio en una de las dos. grande = 1 si el cambio
    llega al umbral en %. comercios y tipos limitan las filas (None = todos)."""
    if not recoleccion_a or not recoleccion_b:
        return pd.DataFrame(columns=["comercio", "nombre_original", "producto_id", "url", "precio_a",
                                     "precio_b", "cambio_cop", "cambio_pct", "tipo", "grande"])
    sql = sql_comparacion(comercios)
    de_tipos = f"WHERE tipo IN ({marcas_in(tipos)})" if tipos else ""
    params = parametros_comparacion(recoleccion_a, recoleccion_b, umbral_pct, comercios)
    return consultar(sql + f"""
        SELECT * FROM comparacion {de_tipos}
        ORDER  BY ABS(COALESCE(cambio_pct, 0)) DESC, comercio, nombre_original;
    """, params + list(tipos or []), ruta)


def conteo_cambios(recoleccion_a, recoleccion_b, umbral_pct=0, comercios=None, ruta=RUTA_BASE):
    """Las tarjetas de la página de cambios: cuántos anuncios subieron,
    bajaron, llegaron al umbral, son nuevos o dejaron de observarse."""
    vacio = {"subieron": 0, "bajaron": 0, "grandes": 0, "nuevos": 0, "dejaron": 0, "anuncios": 0}
    if not recoleccion_a or not recoleccion_b:
        return vacio
    params = parametros_comparacion(recoleccion_a, recoleccion_b, umbral_pct, comercios)
    fila = consultar(sql_comparacion(comercios) + """
        SELECT SUM(tipo = 'subió')              AS subieron,
               SUM(tipo = 'bajó')               AS bajaron,
               SUM(grande)                      AS grandes,
               SUM(tipo = 'nuevo')              AS nuevos,
               SUM(tipo = 'dejó de observarse') AS dejaron,
               COUNT(*)                         AS anuncios
        FROM   comparacion;
    """, params, ruta).iloc[0]
    return {clave: int(fila[clave] or 0) for clave in vacio}


def canasta(recoleccion_id, cantidades, ruta=RUTA_BASE):
    """cantidades = {producto_id: cantidad}. Con precios de una misma
    recolección devuelve (por_comercio, por_producto):
      por_comercio: total en cada comercio solo si tiene todos los productos;
                    si falta alguno, total NULL y la lista de faltantes;
      por_producto: precio mínimo de cada producto, dónde (con empates) y
                    subtotal comprando cada uno donde es más barato."""
    cantidades = {p: int(c) for p, c in cantidades.items() if int(c) > 0}
    if not cantidades:
        return pd.DataFrame(), pd.DataFrame()
    valores = ", ".join("(?, ?)" for _ in cantidades)
    params = [x for par in cantidades.items() for x in par]
    with leer(ruta) as con:
        por_comercio = pd.read_sql_query(f"""
            WITH canasta (producto_id, cantidad) AS (VALUES {valores}),
                 precios AS (
                    SELECT producto_id, comercio, MIN(precio) AS precio
                    FROM   v_comparables WHERE recoleccion_id = ?
                    GROUP  BY producto_id, comercio),
                 comercios_rec AS (
                    SELECT DISTINCT comercio FROM v_observaciones WHERE recoleccion_id = ?)
            SELECT c.comercio,
                   COUNT(p.precio) AS productos_con_precio,
                   (SELECT COUNT(*) FROM canasta) AS productos_canasta,
                   CASE WHEN COUNT(p.precio) = (SELECT COUNT(*) FROM canasta)
                        THEN SUM(k.cantidad * p.precio) END AS total,
                   GROUP_CONCAT(CASE WHEN p.precio IS NULL THEN k.producto_id END, ', ') AS faltantes
            FROM   comercios_rec AS c
            CROSS JOIN canasta   AS k
            LEFT JOIN precios    AS p ON p.producto_id = k.producto_id AND p.comercio = c.comercio
            GROUP  BY c.comercio
            ORDER  BY total IS NULL, total;
        """, con, params=params + [recoleccion_id, recoleccion_id])
        por_producto = pd.read_sql_query(f"""
            WITH canasta (producto_id, cantidad) AS (VALUES {valores}),
                 precios AS (
                    SELECT producto_id, comercio, MIN(precio) AS precio
                    FROM   v_comparables WHERE recoleccion_id = ?
                    GROUP  BY producto_id, comercio),
                 minimos AS (
                    SELECT producto_id, MIN(precio) AS minimo FROM precios GROUP BY producto_id)
            SELECT k.producto_id, pr.descripcion, k.cantidad, m.minimo AS precio_minimo,
                   k.cantidad * m.minimo AS subtotal,
                   GROUP_CONCAT(p.comercio, ', ') AS donde
            FROM   canasta AS k
            JOIN   productos AS pr ON pr.producto_id = k.producto_id
            LEFT JOIN minimos AS m ON m.producto_id = k.producto_id
            LEFT JOIN precios AS p ON p.producto_id = k.producto_id AND p.precio = m.minimo
            GROUP  BY k.producto_id
            ORDER  BY k.producto_id;
        """, con, params=params + [recoleccion_id])
    return por_comercio, por_producto


def resumen_canasta(por_comercio, por_producto):
    """Costo mínimo y ahorro frente al comercio completo más barato y al más
    caro. Si algún producto no tiene precio en ningún comercio, no se calcula."""
    if por_producto.empty or por_producto["precio_minimo"].isna().any():
        return None
    minimo = float(por_producto["subtotal"].sum())
    completos = por_comercio.dropna(subset=["total"])
    if completos.empty:
        return {"costo_minimo": minimo, "mejor_comercio": None, "ahorro_vs_mejor": None,
                "peor_comercio": None, "ahorro_vs_peor": None}
    mejor = completos.loc[completos["total"].idxmin()]
    peor = completos.loc[completos["total"].idxmax()]
    return {"costo_minimo": minimo,
            "mejor_comercio": mejor["comercio"], "ahorro_vs_mejor": float(mejor["total"]) - minimo,
            "peor_comercio": peor["comercio"], "ahorro_vs_peor": float(peor["total"]) - minimo}


def ejecuciones(ruta=RUTA_BASE):
    return consultar("""
        SELECT e.recoleccion_id, c.nombre AS comercio, e.fecha_hora_inicio, e.estado,
               e.total_servicio, e.registros, e.cargada_desde, e.carpeta_raw
        FROM   ejecuciones AS e JOIN comercios AS c ON c.comercio_id = e.comercio_id
        ORDER  BY e.fecha_hora_inicio DESC;""", ruta=ruta)


def tabla_correcciones(ruta=RUTA_BASE):
    return consultar("""
        SELECT fecha, referencia, campo, valor_anterior, valor_nuevo, motivo
        FROM   correcciones ORDER BY correccion_id;""", ruta=ruta)


def tabla_rechazos(ruta=RUTA_BASE):
    return consultar("""
        SELECT ejecucion_id, comercio, sku, regla, detalle, fecha_hora_consulta
        FROM   rechazos ORDER BY rechazo_id DESC LIMIT 500;""", ruta=ruta)


def disponibilidad(recoleccion_id, ruta=RUTA_BASE):
    """Cuántos anuncios están disponibles, agotados o no observados."""
    return consultar("""
        SELECT comercio, estado, COUNT(*) AS anuncios
        FROM   v_disponibilidad WHERE recoleccion_id = ?
        GROUP  BY comercio, estado ORDER BY comercio, estado;""", (recoleccion_id,), ruta)
