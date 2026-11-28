"""
migraciones.py
==============
Módulo de migración idempotente del esquema y estandarización de datos.
Taller 2 - Minería de Datos (UNAL, código 2016325).

Aplica:
  1. Nuevas tablas: correcciones, rechazos, comparables_8.
  2. Nuevas columnas: disponibilidad, descartada, motivo_descarte en observaciones;
     unidad_normalizada en productos y anuncios; es_canasta_8 en productos.
  3. Restricción de unicidad: UNIQUE(anuncio_id, ejecucion_id) en observaciones.
  4. Índices para acelerar filtros de consulta.
  5. Mapeo y normalización de unidades: ml -> mL, und -> unidad, g -> g.
  6. Estandarización y definición explícita de los 8 productos comparables.
  7. Reprocesamiento de copias crudas en raw/ para poblar disponibilidad ('disponible'/'agotado').
  8. Creación de vistas analíticas SQL (sql/vistas.sql).
"""

import os
import sys
import json
import gzip
import sqlite3
import datetime
from pathlib import Path
from typing import Optional

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "comparador_precios.sqlite"
RAW_DIR = BASE_DIR / "raw"
SQL_DIR = BASE_DIR / "sql"

# Definición canónica de los 8 productos comparables en los 3 comercios
CANASTA_8_EANS = [
    ("7501023131748", "Esponja SCOTCH BRITE esferas limpieza (2 und)", "Scotch Brite", "Utensilios De Limpieza", 2.0, "unidad"),
    ("7702037870306", "Esponja ETERNA kit colores surtidos (3 und)", "Eterna", "Utensilios De Limpieza", 3.0, "unidad"),
    ("7500435112413", "Detergente en polvo ARIEL triple poder (1000 gr)", "Ariel", "Cuidado De La Ropa", 1000.0, "g"),
    ("7500435122016", "Detergente líquido ARIEL limpieza profunda (1200 ml)", "Ariel", "Cuidado De La Ropa", 1200.0, "mL"),
    ("7509546051932", "Lavaplatos líquido AXION limón (750 ml)", "Axion", "Cuidado De Superficies", 750.0, "mL"),
    ("7702010382147", "Lavaplatos en crema AXION limón (850 gr)", "Axion", "Cuidado De Superficies", 850.0, "g"),
    ("7702010225123", "Limpiapisos FABULOSO antibacterial lavanda (1000 ml)", "Fabuloso", "Cuidado De Superficies", 1000.0, "mL"),
    ("7503041359241", "Limpiador MR MUSCULO platinum cocina limón (500 ml)", "MR MUSCULO", "Cuidado De Superficies", 500.0, "mL")
]


def agregar_columna_si_no_existe(cur: sqlite3.Cursor, tabla: str, definicion_columna: str):
    col_name = definicion_columna.split()[0].strip()
    try:
        cur.execute(f"ALTER TABLE {tabla} ADD COLUMN {definicion_columna};")
    except sqlite3.OperationalError as e:
        if "duplicate column name" in str(e).lower():
            pass
        else:
            raise


def registrar_correccion(
    cur: sqlite3.Cursor,
    tabla: str,
    registro_id: str,
    campo: str,
    valor_anterior: Optional[str],
    valor_nuevo: Optional[str],
    motivo: str
):
    """Registra de forma trazable una corrección en la tabla correcciones."""
    fecha_iso = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-5))).isoformat(timespec="seconds")
    cur.execute("""
        INSERT INTO correcciones (fecha, tabla, registro_id, campo, valor_anterior, valor_nuevo, motivo)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (fecha_iso, tabla, str(registro_id), campo, str(valor_anterior) if valor_anterior is not None else None, str(valor_nuevo) if valor_nuevo is not None else None, motivo))


def migrar_esquema(db_path: Path = DB_PATH, reprocesar_raw: bool = True):
    print(f"[*] Iniciando migración idempotente sobre: {db_path.name}")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("PRAGMA foreign_keys = ON;")

    # 1. Tabla correcciones
    cur.execute("""
    CREATE TABLE IF NOT EXISTS correcciones (
        correccion_id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        tabla TEXT NOT NULL,
        registro_id TEXT NOT NULL,
        campo TEXT NOT NULL,
        valor_anterior TEXT,
        valor_nuevo TEXT,
        motivo TEXT NOT NULL
    );
    """)

    # 2. Tabla rechazos
    cur.execute("""
    CREATE TABLE IF NOT EXISTS rechazos (
        rechazo_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ejecucion_id TEXT,
        comercio TEXT,
        sku TEXT,
        datos_json TEXT,
        regla TEXT,
        motivo TEXT,
        fecha TEXT NOT NULL
    );
    """)

    # 3. Tabla comparables_8 (catálogo de los 8 productos de referencia)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS comparables_8 (
        producto_id INTEGER PRIMARY KEY,
        ean TEXT UNIQUE NOT NULL,
        nombre_referencia TEXT NOT NULL,
        marca TEXT NOT NULL,
        subcategoria TEXT NOT NULL,
        contenido_total REAL NOT NULL,
        unidad_normalizada TEXT NOT NULL CHECK(unidad_normalizada IN ('mL', 'g', 'unidad')),
        FOREIGN KEY (producto_id) REFERENCES productos(producto_id)
    );
    """)

    # 4. Nuevas columnas en tablas existentes
    agregar_columna_si_no_existe(cur, "observaciones", "descartada INTEGER DEFAULT 0")
    agregar_columna_si_no_existe(cur, "observaciones", "motivo_descarte TEXT")
    agregar_columna_si_no_existe(cur, "observaciones", "disponibilidad TEXT CHECK(disponibilidad IN ('disponible', 'agotado'))")

    agregar_columna_si_no_existe(cur, "anuncios", "unidad_normalizada TEXT CHECK(unidad_normalizada IN ('mL', 'g', 'unidad'))")
    agregar_columna_si_no_existe(cur, "productos", "unidad_normalizada TEXT CHECK(unidad_normalizada IN ('mL', 'g', 'unidad'))")
    agregar_columna_si_no_existe(cur, "productos", "es_canasta_8 INTEGER DEFAULT 0")

    # 5. Restricción de unicidad adicional: UNIQUE(anuncio_id, ejecucion_id)
    cur.execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS uidx_obs_anuncio_ejecucion
    ON observaciones(anuncio_id, ejecucion_id);
    """)

    # 6. Índices para acelerar filtros
    indices = [
        "CREATE INDEX IF NOT EXISTS idx_anuncios_comercio ON anuncios(comercio_id);",
        "CREATE INDEX IF NOT EXISTS idx_anuncios_subcat ON anuncios(subcategoria_estandar);",
        "CREATE INDEX IF NOT EXISTS idx_anuncios_marca ON anuncios(marca_estandar);",
        "CREATE INDEX IF NOT EXISTS idx_anuncios_producto ON anuncios(producto_id);",
        "CREATE INDEX IF NOT EXISTS idx_anuncios_ean ON anuncios(ean);",
        "CREATE INDEX IF NOT EXISTS idx_obs_precio ON observaciones(precio_actual);",
        "CREATE INDEX IF NOT EXISTS idx_obs_fecha ON observaciones(fecha_hora_consulta);",
        "CREATE INDEX IF NOT EXISTS idx_obs_promocion ON observaciones(es_promocion);",
        "CREATE INDEX IF NOT EXISTS idx_obs_disponibilidad ON observaciones(disponibilidad);",
        "CREATE INDEX IF NOT EXISTS idx_obs_descartada ON observaciones(descartada);",
        "CREATE INDEX IF NOT EXISTS idx_prod_canasta8 ON productos(es_canasta_8);"
    ]
    for idx_sql in indices:
        cur.execute(idx_sql)

    # 7. Normalización de unidades en productos y anuncios
    print("[*] Estandarizando unidades normalizadas (mL, g, unidad)...")
    cur.execute("""
        UPDATE productos
        SET unidad_normalizada = CASE
            WHEN lower(unidad_base) in ('ml', 'l', 'lt', 'litro', 'litros') THEN 'mL'
            WHEN lower(unidad_base) in ('g', 'gr', 'gramo', 'gramos', 'kg', 'kilo', 'kilos') THEN 'g'
            WHEN lower(unidad_base) in ('und', 'unds', 'unidades', 'unid', 'bolsas', 'unidad') THEN 'unidad'
            ELSE unidad_normalizada
        END
        WHERE unidad_base IS NOT NULL AND (unidad_normalizada IS NULL OR unidad_normalizada != 'mL');
    """)

    cur.execute("""
        UPDATE anuncios
        SET unidad_normalizada = CASE
            WHEN lower(unidad_base) in ('ml', 'l', 'lt', 'litro', 'litros') THEN 'mL'
            WHEN lower(unidad_base) in ('g', 'gr', 'gramo', 'gramos', 'kg', 'kilo', 'kilos') THEN 'g'
            WHEN lower(unidad_base) in ('und', 'unds', 'unidades', 'unid', 'bolsas', 'unidad') THEN 'unidad'
            ELSE unidad_normalizada
        END
        WHERE unidad_base IS NOT NULL AND (unidad_normalizada IS NULL OR unidad_normalizada != 'mL');
    """)

    # 8. Población de comparables_8 y marca es_canasta_8 = 1
    print("[*] Vinculando los 8 productos comparables canónicos...")
    cur.execute("UPDATE productos SET es_canasta_8 = 0;")
    cur.execute("DELETE FROM comparables_8;")

    for ean, nombre, marca, subcat, cnt, unit in CANASTA_8_EANS:
        cur.execute("SELECT producto_id FROM productos WHERE ean = ?", (ean,))
        row = cur.fetchone()
        if row:
            pid = row[0]
            cur.execute("UPDATE productos SET es_canasta_8 = 1, unidad_normalizada = ? WHERE producto_id = ?", (unit, pid))
            cur.execute("""
                INSERT OR REPLACE INTO comparables_8 (producto_id, ean, nombre_referencia, marca, subcategoria, contenido_total, unidad_normalizada)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (pid, ean, nombre, marca, subcat, cnt, unit))
            registrar_correccion(cur, "productos", str(pid), "es_canasta_8", "0", "1", "Asignación a canasta de 8 comparables canónicos")
        else:
            print(f"[WARN] EAN {ean} no encontrado en tabla productos!")

    # 9. Reprocesar copias crudas en raw/ para poblar disponibilidad en observaciones existentes
    print("[*] Reprocesando disponibilidad desde raw/...")
    total_disponibilidad_actualizada = 0
    sku_avail_map = {}

    if reprocesar_raw and RAW_DIR.exists():
        for comercio_dir in RAW_DIR.iterdir():
            if not comercio_dir.is_dir() or comercio_dir.name == "robots":
                continue
            for fecha_dir in comercio_dir.iterdir():
                if not fecha_dir.is_dir():
                    continue
                for gz_file in fecha_dir.glob("*.json.gz"):
                    if gz_file.name.endswith(".html.gz"):
                        continue
                    try:
                        with gzip.open(gz_file, "rt", encoding="utf-8") as f:
                            raw_items = json.load(f)
                            if isinstance(raw_items, list):
                                for prod in raw_items:
                                    for item in prod.get("items", []):
                                        sku = str(item.get("itemId") or prod.get("productId") or "")
                                        sellers = item.get("sellers") or []
                                        if sellers:
                                            comm = sellers[0].get("commertialOffer") or {}
                                            qty = comm.get("AvailableQuantity")
                                            is_avail = comm.get("IsAvailable")
                                            if qty is not None and qty > 0:
                                                disp = "disponible"
                                            elif is_avail is True:
                                                disp = "disponible"
                                            elif is_avail is False or qty == 0:
                                                disp = "agotado"
                                            else:
                                                disp = "disponible"
                                            if sku:
                                                sku_avail_map[sku] = disp
                    except Exception as e:
                        print(f"[WARN] No se pudo leer {gz_file}: {e}")

    # Actualizar disponibilidad por SKU de anuncios
    cur.execute("SELECT anuncio_id, sku FROM anuncios")
    anuncios_all = cur.fetchall()
    for aid, sku in anuncios_all:
        disp = sku_avail_map.get(str(sku), "disponible")
        cur.execute("""
            UPDATE observaciones
            SET disponibilidad = ?
            WHERE anuncio_id = ? AND disponibilidad IS NULL
        """, (disp, aid))
        total_disponibilidad_actualizada += cur.rowcount

    print(f"[*] Disponibilidad actualizada en observaciones: {total_disponibilidad_actualizada} filas.")

    # 10. Instalar / actualizar vistas desde sql/vistas.sql
    vistas_file = SQL_DIR / "vistas.sql"
    if vistas_file.exists():
        print("[*] Cargando vistas analíticas desde sql/vistas.sql...")
        vistas_sql = vistas_file.read_text(encoding="utf-8")
        cur.executescript(vistas_sql)
        print("[OK] Vistas creadas exitosamente.")
    else:
        print(f"[ERROR] Archivo {vistas_file} no encontrado!")

    conn.commit()
    conn.close()
    print("[OK] Migración completada con éxito.")


if __name__ == "__main__":
    migrar_esquema()
