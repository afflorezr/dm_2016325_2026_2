# -*- coding: utf-8 -*-
"""
migrar_taller2.py - Taller 2, Minería de Datos (UNAL)
Lleva la base del Taller 1 al esquema del Taller 2 sin borrar ninguna observación.

Qué hace (idempotente: se puede ejecutar varias veces):
  1. Corre preparacion.preparar(): marca_estandar, id_producto_comun y comparable en TODAS las ejecuciones.
     Cada cambio de `comparable` sobre filas existentes se registra en la tabla `correcciones`.
  2. Crea `correcciones` y `observaciones_rechazadas`.
  3. Agrega a `ejecuciones`: valida, motivo_invalidez y ruta_raw (carpeta de copias crudas).
  4. Crea índices y las vistas v_ultimo_precio, v_cambios_precio, v_comparables y v_disponibilidad.
  5. Genera diccionario_datos.md a partir del esquema real.

Uso:
  python migrar_taller2.py                      # migra y avisa qué ejecuciones no tienen copia cruda
  python migrar_taller2.py --invalidar EJEC_... --motivo "texto"   # descarta una ejecución (queda registrado)
"""
import argparse
import os
import re
import sqlite3
import unicodedata
from datetime import datetime, timedelta, timezone

import preparacion

TZ_CO = timezone(timedelta(hours=-5))
scraper_precio_simbolico = 1.0
MOTIVO_REPETIDA = "observación repetida en la misma ejecución (mismo comercio y SKU); se conserva la primera"
MOTIVO_SIMBOLICO = ("precio simbólico (<= $1): obsequio, muestra o material publicitario, "
                    "no es una oferta de venta")
DB_DEFECTO = "comparador_precios.sqlite"


def ahora_iso():
    return datetime.now(TZ_CO).isoformat(timespec="seconds")


def _slug(nombre):
    s = "".join(c for c in unicodedata.normalize("NFD", nombre) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _tiene_columna(conn, tabla, col):
    return any(r[1] == col for r in conn.execute(f"PRAGMA table_info({tabla})"))


def _agregar_columna(conn, tabla, col, tipo):
    if not _tiene_columna(conn, tabla, col):
        conn.execute(f"ALTER TABLE {tabla} ADD COLUMN {col} {tipo}")


def registrar_correccion(conn, tabla, registro, campo, anterior, nuevo, motivo):
    conn.execute(
        "INSERT INTO correcciones (fecha, tabla, registro, campo, valor_anterior, valor_nuevo, motivo) "
        "VALUES (?,?,?,?,?,?,?)",
        (ahora_iso(), tabla, str(registro), campo,
         None if anterior is None else str(anterior), None if nuevo is None else str(nuevo), motivo))


ESQUEMA_T2 = """
CREATE TABLE IF NOT EXISTS correcciones (
    id_correccion  INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha          TEXT NOT NULL,
    tabla          TEXT NOT NULL,
    registro       TEXT NOT NULL,
    campo          TEXT NOT NULL,
    valor_anterior TEXT,
    valor_nuevo    TEXT,
    motivo         TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
    id_rechazo    INTEGER PRIMARY KEY AUTOINCREMENT,
    id_ejecucion  TEXT,
    comercio      TEXT,
    sku_comercio  TEXT,
    fecha_rechazo TEXT NOT NULL,
    motivo        TEXT NOT NULL,
    datos_json    TEXT
);
"""

INDICES = [
    "CREATE INDEX IF NOT EXISTS idx_obs_comercio_fecha ON observaciones (comercio, fecha_consulta)",
    "CREATE INDEX IF NOT EXISTS idx_obs_marca ON observaciones (marca_estandar)",
    "CREATE INDEX IF NOT EXISTS idx_obs_precio ON observaciones (precio_vigente)",
    "CREATE INDEX IF NOT EXISTS idx_obs_alcance ON observaciones (en_alcance, comparable)",
    "CREATE INDEX IF NOT EXISTS idx_obs_subcat ON observaciones (categoria_origen)",
    "CREATE INDEX IF NOT EXISTS idx_rech_ejec ON observaciones_rechazadas (id_ejecucion, comercio)",
]

VISTAS = {
    # Todas las observaciones de ejecuciones válidas, con precio unitario (base de filtros y comparaciones).
    "v_observaciones": """
        CREATE VIEW v_observaciones AS
        SELECT o.id_observacion, o.id_ejecucion, o.comercio, o.sku_comercio, o.codigo_barras, o.id_producto_comun,
               o.titulo_original, o.marca_estandar, o.categoria_origen AS subcategoria, o.en_alcance, o.comparable,
               o.precio_lista, o.precio_vigente AS precio, o.promocion, o.disponible, o.contenido_num, o.unidad,
               CASE WHEN o.contenido_num > 0 THEN o.precio_vigente / o.contenido_num END AS precio_unitario,
               o.url, o.texto_original, o.fecha_consulta
        FROM observaciones o
        JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
        WHERE e.valida = 1 AND o.precio_vigente IS NOT NULL
          AND COALESCE(o.motivo_exclusion, '') NOT LIKE 'observación repetida%'
    """,
    # Última observación de cada anuncio (comercio + SKU) dentro de las ejecuciones válidas.
    "v_ultimo_precio": """
        CREATE VIEW v_ultimo_precio AS
        SELECT t.id_observacion, t.id_ejecucion, t.comercio, t.sku_comercio, t.codigo_barras, t.id_producto_comun,
               t.titulo_original, t.marca_estandar, t.categoria_origen AS subcategoria, t.en_alcance, t.comparable,
               t.precio_lista, t.precio_vigente AS precio, t.promocion, t.disponible, t.contenido_num, t.unidad,
               CASE WHEN t.contenido_num > 0 THEN t.precio_vigente / t.contenido_num END AS precio_unitario,
               t.url, t.texto_original, t.fecha_consulta,
               CASE WHEN t.id_ejecucion = (SELECT e.id_ejecucion FROM ejecuciones e
                                           WHERE e.comercio = t.comercio AND e.valida = 1 AND e.estado <> 'fallida'
                                           ORDER BY e.fecha_inicio DESC LIMIT 1)
                    THEN 1 ELSE 0 END AS vigente
        FROM (
            SELECT o.*, ROW_NUMBER() OVER (PARTITION BY o.comercio, o.sku_comercio
                                           ORDER BY o.fecha_consulta DESC) AS rn
            FROM observaciones o
            JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
            WHERE e.valida = 1 AND o.precio_vigente IS NOT NULL
              AND COALESCE(o.motivo_exclusion, '') NOT LIKE 'observación repetida%') t
        WHERE t.rn = 1
    """,
    # Cambio de precio del mismo anuncio en el mismo comercio entre sus dos últimas observaciones válidas.
    "v_cambios_precio": """
        CREATE VIEW v_cambios_precio AS
        WITH r AS (
            SELECT o.id_ejecucion, o.comercio, o.sku_comercio, o.titulo_original, o.marca_estandar,
                   o.precio_vigente, o.fecha_consulta, o.url,
                   ROW_NUMBER() OVER (PARTITION BY o.comercio, o.sku_comercio
                                      ORDER BY o.fecha_consulta DESC) AS rn
            FROM observaciones o
            JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
            WHERE e.valida = 1 AND o.precio_vigente IS NOT NULL
              AND COALESCE(o.motivo_exclusion, '') NOT LIKE 'observación repetida%')
        SELECT a.comercio, a.sku_comercio, a.titulo_original, a.marca_estandar,
               b.id_ejecucion AS ejecucion_anterior, a.id_ejecucion AS ejecucion_nueva,
               b.fecha_consulta AS fecha_anterior, a.fecha_consulta AS fecha_nueva,
               b.precio_vigente AS precio_anterior, a.precio_vigente AS precio_nuevo,
               a.precio_vigente - b.precio_vigente AS variacion_cop,
               ROUND(100.0 * (a.precio_vigente - b.precio_vigente) / b.precio_vigente, 2) AS variacion_pct,
               a.url
        FROM r a JOIN r b ON a.comercio = b.comercio AND a.sku_comercio = b.sku_comercio
                          AND a.rn = 1 AND b.rn = 2
    """,
    # Los productos comparables (con su id común) por ejecución válida.
    "v_comparables": """
        CREATE VIEW v_comparables AS
        SELECT o.id_ejecucion, o.comercio, p.id_producto_comun, p.marca_estandar, p.nombre_estandar,
               p.contenido_num, p.unidad, o.precio_lista, o.precio_vigente, o.promocion, o.disponible,
               CASE WHEN p.contenido_num > 0 THEN o.precio_vigente / p.contenido_num END AS precio_unitario,
               o.url, o.titulo_original, o.sku_comercio, o.fecha_consulta
        FROM observaciones o
        JOIN productos p USING (id_producto_comun)
        JOIN ejecuciones e ON e.id_ejecucion = o.id_ejecucion AND e.comercio = o.comercio
        WHERE o.comparable = 1 AND e.valida = 1
    """,
    # Tres estados: disponible / agotado según el sitio / no observado en esa ejecución.
    "v_disponibilidad": """
        CREATE VIEW v_disponibilidad AS
        WITH anuncios AS (SELECT DISTINCT comercio, sku_comercio FROM observaciones),
             ejecs    AS (SELECT id_ejecucion, comercio FROM ejecuciones WHERE valida = 1 AND estado <> 'fallida')
        SELECT e.id_ejecucion, e.comercio, a.sku_comercio,
               CASE WHEN o.id_observacion IS NULL THEN 'no_observado'
                    WHEN o.disponible = 1           THEN 'disponible'
                    WHEN o.disponible = 0           THEN 'agotado'
                    ELSE 'sin_dato' END AS estado_disponibilidad
        FROM ejecs e
        JOIN anuncios a ON a.comercio = e.comercio
        LEFT JOIN observaciones o ON o.id_ejecucion = e.id_ejecucion AND o.comercio = a.comercio
                                 AND o.sku_comercio = a.sku_comercio
                                 AND COALESCE(o.motivo_exclusion, '') NOT LIKE 'observación repetida%'
    """,
}


def ruta_raw_de(id_ejecucion, comercio, raw_dir="raw"):
    m = re.fullmatch(r"EJEC_(\d{4})(\d{2})(\d{2})_\d{6}", id_ejecucion)
    if not m:
        return None
    ruta = os.path.join(raw_dir, _slug(comercio), f"{m.group(1)}-{m.group(2)}-{m.group(3)}", id_ejecucion)
    return ruta.replace(os.sep, "/")


def migrar(db_path=DB_DEFECTO, raw_dir="raw", verbose=True):
    conn = sqlite3.connect(db_path)
    antes = {}
    if _tiene_columna(conn, "observaciones", "comparable"):
        antes = dict(conn.execute("SELECT id_observacion, comparable FROM observaciones"))
    conn.close()

    preparacion.preparar(db_path)           # marca_estandar, id_producto_comun, comparable en todas las ejecuciones

    conn = sqlite3.connect(db_path)
    conn.executescript(ESQUEMA_T2)
    _agregar_columna(conn, "ejecuciones", "valida", "INTEGER NOT NULL DEFAULT 1")
    _agregar_columna(conn, "ejecuciones", "motivo_invalidez", "TEXT")
    _agregar_columna(conn, "ejecuciones", "ruta_raw", "TEXT")

    # Correcciones: filas cuya marca `comparable` cambió al reprocesar
    cambiados = 0
    for id_obs, nuevo in conn.execute("SELECT id_observacion, comparable FROM observaciones").fetchall():
        if id_obs in antes and antes[id_obs] != nuevo:
            registrar_correccion(conn, "observaciones", id_obs, "comparable", antes[id_obs], nuevo,
                                 "La ejecución se cargó después de correr preparacion.py; se reprocesó la "
                                 "correspondencia de productos por EAN, contenido y unidad (Taller 1, cobertura obligatoria).")
            cambiados += 1

    # Obsequios/muestras con precio simbólico (<= $1) ya cargados: se sacan de la categoría y se registra cada cambio
    simbolicos = conn.execute("SELECT id_observacion, en_alcance, motivo_exclusion FROM observaciones "
                              "WHERE en_alcance = 1 AND precio_vigente IS NOT NULL AND precio_vigente <= ?",
                              (scraper_precio_simbolico,)).fetchall()
    for id_obs, en_alc, _ in simbolicos:
        registrar_correccion(conn, "observaciones", id_obs, "en_alcance", en_alc, 0, MOTIVO_SIMBOLICO)
        conn.execute("UPDATE observaciones SET en_alcance = 0, motivo_exclusion = ?, comparable = 0, "
                     "id_producto_comun = NULL WHERE id_observacion = ?", (MOTIVO_SIMBOLICO, id_obs))

    # Observaciones repetidas (mismo comercio y SKU en la MISMA ejecución): se conserva la primera insertada y las demás
    # se sacan de la categoría con su motivo; cada cambio queda en `correcciones` (no se borra nada).
    repetidas = conn.execute("""
        SELECT id_observacion, en_alcance FROM observaciones o
        WHERE en_alcance = 1 AND id_observacion > (
            SELECT MIN(o2.id_observacion) FROM observaciones o2
            WHERE o2.id_ejecucion = o.id_ejecucion AND o2.comercio = o.comercio
              AND o2.sku_comercio = o.sku_comercio AND o2.en_alcance = 1)""").fetchall()
    for id_obs, en_alc in repetidas:
        registrar_correccion(conn, "observaciones", id_obs, "en_alcance", en_alc, 0, MOTIVO_REPETIDA)
        conn.execute("UPDATE observaciones SET en_alcance = 0, motivo_exclusion = ?, comparable = 0, "
                     "id_producto_comun = NULL WHERE id_observacion = ?", (MOTIVO_REPETIDA, id_obs))

    # Ruta a las copias crudas y aviso de las que faltan
    sin_raw = []
    for id_ej, com in conn.execute("SELECT id_ejecucion, comercio FROM ejecuciones").fetchall():
        ruta = ruta_raw_de(id_ej, com, raw_dir)
        existe = ruta is not None and os.path.isdir(ruta)
        conn.execute("UPDATE ejecuciones SET ruta_raw = ? WHERE id_ejecucion = ? AND comercio = ?",
                     (ruta if existe else None, id_ej, com))
        if not existe:
            sin_raw.append((id_ej, com))

    for sql in INDICES:
        conn.execute(sql)
    for nombre, sql in VISTAS.items():
        conn.execute(f"DROP VIEW IF EXISTS {nombre}")
        conn.execute(sql)
    conn.commit()
    conn.close()

    if verbose:
        print(f"Migración lista. Filas con 'comparable' corregido: {cambiados}. "
          f"Obsequios/muestras excluidos de la categoría: {len(simbolicos)}. "
          f"Observaciones repetidas descartadas: {len(repetidas)}.")
        if sin_raw:
            ids = sorted({i for i, _ in sin_raw})
            print("AVISO: sin copia cruda en", raw_dir + "/:", ", ".join(ids))
            print("       Sus observaciones no son verificables; si no la recuperas, descártala con:")
            print('       python migrar_taller2.py --invalidar <ID> --motivo "copias crudas no disponibles"')
    return {"corregidas": cambiados, "ejecuciones_sin_raw": sorted(set(sin_raw))}


def invalidar_ejecucion(db_path, id_ejecucion, motivo):
    """Descarta una ejecución (no borra nada): las vistas dejan de usarla y el cambio queda en `correcciones`."""
    conn = sqlite3.connect(db_path)
    filas = conn.execute("SELECT valida FROM ejecuciones WHERE id_ejecucion = ?", (id_ejecucion,)).fetchall()
    if not filas:
        conn.close()
        raise ValueError(f"No existe la ejecución {id_ejecucion}")
    if any(v == 1 for (v,) in filas):
        conn.execute("UPDATE ejecuciones SET valida = 0, motivo_invalidez = ? WHERE id_ejecucion = ?",
                     (motivo, id_ejecucion))
        registrar_correccion(conn, "ejecuciones", id_ejecucion, "valida", 1, 0, motivo)
        conn.commit()
    conn.close()


# --------------------------------------------------------------------------- diccionario de datos
DESCRIPCIONES = {
    "comercios": "Comercios de los que se extrae información.",
    "ejecuciones": "Una fila por corrida del scraper y comercio.",
    "observaciones": "Una fila por anuncio (SKU) observado en una ejecución, con su precio en ese momento.",
    "productos": "Los productos comparables entre comercios (identificador común, correspondencia verificada a mano).",
    "familias_tamano": "Mismo producto en distintos tamaños, para el precio por unidad de contenido.",
    "correcciones": "Registro de cada corrección hecha sobre datos ya cargados (fecha, registro, valor anterior y nuevo, motivo).",
    "observaciones_rechazadas": "Observaciones que no superaron la validación y por eso no se insertaron.",
    "v_observaciones": "Todas las observaciones de ejecuciones válidas, con precio unitario.",
    "v_ultimo_precio": "Última observación válida de cada anuncio, con precio unitario y la marca `vigente` (observado en la última ejecución).",
    "v_cambios_precio": "Variación de precio de cada anuncio entre sus dos últimas observaciones válidas.",
    "v_comparables": "Observaciones de los productos comparables en las ejecuciones válidas.",
    "v_disponibilidad": "Estado de cada anuncio por ejecución: disponible, agotado o no observado.",
}
COLUMNAS_DESC = {
    "comercio": "Nombre del comercio (La Rebaja, Dermatodo, Farmatodo).",
    "sitio_web": "URL base del comercio.",
    "id_ejecucion": "Identificador de la ejecución: EJEC_AAAAMMDD_HHMMSS.",
    "fecha_inicio": "Inicio de la ejecución, ISO 8601 con hora de Colombia (-05:00).",
    "fecha_fin": "Fin de la ejecución, ISO 8601.",
    "modo": "'en_linea' (consultó el sitio) u 'offline' (reprocesó raw/).",
    "registros_obtenidos": "Anuncios extraídos del comercio en esa ejecución.",
    "registros_insertados": "Anuncios nuevos que entraron a la base.",
    "registros_declarados_sitio": "Cifra que el sitio muestra para la categoría, si está disponible.",
    "estado": "'completa', 'parcial' o 'fallida'.",
    "detalle": "Notas del scraper sobre la ejecución.",
    "valida": "1 = se usa en el análisis; 0 = descartada (motivo en motivo_invalidez).",
    "motivo_invalidez": "Razón por la que la ejecución se descartó.",
    "ruta_raw": "Carpeta con las copias crudas (HTML/JSON) de esa ejecución y comercio; NULL si no existe.",
    "id_observacion": "Identificador interno de la observación.",
    "sku_comercio": "SKU o código del anuncio en el comercio.",
    "codigo_barras": "EAN del producto, si el comercio lo publica.",
    "id_producto_comercio": "Identificador interno del producto en el comercio.",
    "url": "Página de la que se extrajo el precio.",
    "titulo_original": "Nombre del anuncio tal como se publicó (sin limpiar).",
    "marca_original": "Marca tal como se publicó.",
    "presentacion_original": "Presentación/variante tal como se publicó.",
    "texto_original": "Nombre, ficha y descripción del anuncio sin limpiar.",
    "categoria_origen": "Subcategoría de origen según el comercio.",
    "categorias_origen": "Todas las colecciones/categorías del comercio a las que pertenece.",
    "en_alcance": "1 si pertenece a la categoría de la planilla; 0 si se excluyó.",
    "motivo_exclusion": "Razón de la exclusión cuando en_alcance = 0.",
    "precio_lista": "Precio antes del descuento (COP); igual al vigente si no hay promoción.",
    "precio_vigente": "Precio que se paga en el momento de la consulta (COP).",
    "precio_prime": "Precio para clientes con programa de fidelización, si existe (COP).",
    "promocion": "1 si el precio vigente es promocional; 0 si no.",
    "precio_promocional": "Precio promocional (COP) cuando promocion = 1.",
    "tiendas_con_oferta": "Número de tiendas con oferta (Farmatodo).",
    "disponible": "1 = disponible; 0 = agotado según el sitio; NULL = el sitio no lo informa.",
    "es_marketplace": "1 si lo vende un tercero en el marketplace del comercio.",
    "contenido_num": "Contenido total de la presentación, en la unidad normalizada.",
    "unidad": "Unidad normalizada: 'mL', 'g' o 'und' (el mg se convierte a g).",
    "nota_calidad": "Advertencias de calidad del dato (por ejemplo contenido inferido).",
    "fecha_consulta": "Momento en que se observó el precio, ISO 8601 con -05:00.",
    "marca_estandar": "Marca estandarizada (sin tildes/mayúsculas inconsistentes y con alias unificados).",
    "id_producto_comun": "Identificador P01..P10 del producto comparable; NULL si no es comparable.",
    "comparable": "1 si la observación es de un producto comparable en una ejecución con precio; 0 si no.",
    "nombre_estandar": "Nombre estandarizado del producto comparable.",
    "id_familia": "Identificador de la familia de tamaños (F01...).",
    "nombre_familia": "Nombre de la familia de tamaños.",
    "id_correccion": "Identificador de la corrección.",
    "fecha": "Momento en que se registró la corrección.",
    "tabla": "Tabla afectada.",
    "registro": "Clave del registro afectado.",
    "campo": "Campo modificado.",
    "valor_anterior": "Valor antes de la corrección.",
    "valor_nuevo": "Valor después de la corrección.",
    "motivo": "Por qué se corrigió o rechazó.",
    "id_rechazo": "Identificador del rechazo.",
    "fecha_rechazo": "Momento del rechazo.",
    "datos_json": "Observación rechazada, serializada en JSON.",
    "precio": "Precio vigente (COP).",
    "precio_unitario": "Precio por unidad de contenido (COP por mL, g o unidad, según 'unidad').",
    "subcategoria": "Subcategoría de origen del comercio.",
    "ejecucion_anterior": "Ejecución de la observación previa.",
    "ejecucion_nueva": "Ejecución de la observación más reciente.",
    "fecha_anterior": "Fecha de consulta del precio anterior.",
    "fecha_nueva": "Fecha de consulta del precio nuevo.",
    "precio_anterior": "Precio en la observación previa (COP).",
    "precio_nuevo": "Precio en la observación más reciente (COP).",
    "variacion_cop": "precio_nuevo - precio_anterior (COP).",
    "variacion_pct": "Variación porcentual respecto al precio anterior.",
    "vigente": "1 si el anuncio se observó en la última ejecución válida de su comercio; 0 si solo se conoce su último precio de una ejecución anterior.",
    "estado_disponibilidad": "'disponible', 'agotado', 'no_observado' o 'sin_dato'.",
}


def generar_diccionario(db_path=DB_DEFECTO, salida="diccionario_datos.md"):
    conn = sqlite3.connect(db_path)
    objetos = conn.execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') "
                           "AND name NOT LIKE 'sqlite_%' ORDER BY type DESC, name").fetchall()
    out = ["# Diccionario de datos", "",
           "Generado automáticamente desde el esquema de `comparador_precios.sqlite` (`migrar_taller2.py`).", "",
           "Convenciones: precios en pesos colombianos (COP); fechas en ISO 8601 con hora de Colombia (-05:00); "
           "un dato no disponible se guarda como `NULL`, nunca como 0.", ""]
    for nombre, tipo in objetos:
        out += [f"## {'Tabla' if tipo == 'table' else 'Vista'} `{nombre}`", "",
                DESCRIPCIONES.get(nombre, "(sin descripción)"), "",
                "| Columna | Tipo | Descripción |", "|---|---|---|"]
        for _, col, t, *_ in conn.execute(f"PRAGMA table_info({nombre})"):
            out.append(f"| `{col}` | {t or '—'} | {COLUMNAS_DESC.get(col, '(sin descripción)')} |")
        out.append("")
    conn.close()
    with open(salida, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    return salida


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Migra la base del Taller 1 al esquema del Taller 2")
    ap.add_argument("--db", default=DB_DEFECTO)
    ap.add_argument("--raw", default="raw")
    ap.add_argument("--invalidar", metavar="ID_EJECUCION")
    ap.add_argument("--motivo", default="")
    a = ap.parse_args()
    if a.invalidar and not a.motivo:
        ap.error("--invalidar requiere --motivo")
    migrar(a.db, a.raw)                      # primero el esquema (crea la columna `valida`)
    if a.invalidar:
        invalidar_ejecucion(a.db, a.invalidar, a.motivo)
        print(f"Ejecución {a.invalidar} descartada y registrada en `correcciones`.")
    generar_diccionario(a.db)
    print("Listo: diccionario_datos.md actualizado.")
