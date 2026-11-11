"""
migrar_db.py - Migración del esquema de comparador_precios.sqlite (Taller 1 -> Taller 2).

Qué hace (todo idempotente: se puede ejecutar varias veces sin duplicar nada):
  1. Crea la tabla `correcciones` y la tabla `observaciones_rechazadas`.
  2. Añade `disponibilidad` (disponible / agotado / no observado) a `observaciones`.
  3. Añade `contenido_total` (si no existía) y `unidad_normalizada` (mL, g, unidad) a `anuncios`,
     más `contenido_normalizado` (contenido expresado en la unidad normalizada).
  4. Garantiza unicidad (comercio, anuncio, fecha_consulta) en `observaciones`.
  5. Crea índices para los filtros de la aplicación (comercio, subcategoría, marca, ...).
  6. Crea las vistas v_ultimo_precio, v_cambios_precio y v_comparables.

Todo se ejecuta en UNA transacción: si algo falla, la base queda como estaba.

Uso:
    python migrar_db.py [ruta_a_la_base.sqlite]
"""

import os
import sqlite3
import sys

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "comparador_precios.sqlite")


# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------
def _tiene_columna(con, tabla, columna):
    """True si la tabla ya tiene la columna (SQLite no soporta ADD COLUMN IF NOT EXISTS)."""
    return any(f[1] == columna for f in con.execute(f"PRAGMA table_info({tabla})"))


def _agregar_columna(con, tabla, columna, definicion):
    """ALTER TABLE ... ADD COLUMN solo si la columna no existe. Devuelve True si la creó."""
    if _tiene_columna(con, tabla, columna):
        return False
    con.execute(f"ALTER TABLE {tabla} ADD COLUMN {columna} {definicion}")
    return True


# ----------------------------------------------------------------------------
# 1. Tablas nuevas
# ----------------------------------------------------------------------------
TABLAS = """
-- Registro de correcciones hechas sobre la base del Taller 1 (nunca se borran observaciones).
CREATE TABLE IF NOT EXISTS correcciones (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha          TEXT NOT NULL,          -- ISO 8601, hora de Colombia
  id_registro    INTEGER NOT NULL,       -- id del registro afectado (anuncios.id u observaciones.id)
  valor_anterior TEXT,
  valor_nuevo    TEXT,
  motivo         TEXT NOT NULL
);

-- Observaciones que no superaron la validación (pandera): se guardan con el motivo del rechazo.
CREATE TABLE IF NOT EXISTS observaciones_rechazadas (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha_rechazo  TEXT NOT NULL,
  corrida_id     TEXT,
  comercio       TEXT,
  sku            TEXT,
  fecha_consulta TEXT,
  precio_cop     REAL,
  motivo         TEXT NOT NULL,
  fila_json      TEXT                    -- fila completa tal como llegó del scraper
);
"""

# ----------------------------------------------------------------------------
# 4. Triggers: mantienen los campos nuevos al día aunque el scraper no los conozca
# ----------------------------------------------------------------------------
TRIGGERS = """
DROP TRIGGER IF EXISTS trg_obs_campos_nuevos;
CREATE TRIGGER trg_obs_campos_nuevos AFTER INSERT ON observaciones
BEGIN
  UPDATE observaciones
     SET disponibilidad = CASE WHEN NEW.disponible = 1 THEN 'disponible' ELSE 'agotado' END,
         comercio_id    = (SELECT a.comercio_id FROM anuncios a WHERE a.id = NEW.anuncio_id)
   WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS trg_anuncio_ins_unidad;
CREATE TRIGGER trg_anuncio_ins_unidad AFTER INSERT ON anuncios
BEGIN
  UPDATE anuncios
     SET unidad_normalizada = CASE NEW.unidad_base
           WHEN 'mL' THEN 'mL' WHEN 'g' THEN 'g' WHEN 'mg' THEN 'g' WHEN 'unidad' THEN 'unidad' END,
         contenido_normalizado = CASE WHEN NEW.unidad_base = 'mg'
           THEN NEW.contenido_total / 1000.0 ELSE NEW.contenido_total END
   WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS trg_anuncio_upd_unidad;
CREATE TRIGGER trg_anuncio_upd_unidad AFTER UPDATE OF contenido_total, unidad_base ON anuncios
BEGIN
  UPDATE anuncios
     SET unidad_normalizada = CASE NEW.unidad_base
           WHEN 'mL' THEN 'mL' WHEN 'g' THEN 'g' WHEN 'mg' THEN 'g' WHEN 'unidad' THEN 'unidad' END,
         contenido_normalizado = CASE WHEN NEW.unidad_base = 'mg'
           THEN NEW.contenido_total / 1000.0 ELSE NEW.contenido_total END
   WHERE id = NEW.id;
END;
"""

# ----------------------------------------------------------------------------
# 5. Índices para los filtros de la aplicación
# ----------------------------------------------------------------------------
INDICES = """
-- Índice único = restricción de unicidad de la observación
CREATE UNIQUE INDEX IF NOT EXISTS ux_obs_comercio_anuncio_fecha
  ON observaciones (comercio_id, anuncio_id, fecha_consulta);
CREATE INDEX IF NOT EXISTS ix_anuncios_comercio     ON anuncios (comercio_id);
CREATE INDEX IF NOT EXISTS ix_anuncios_subcategoria ON anuncios (subcategoria);
CREATE INDEX IF NOT EXISTS ix_anuncios_marca        ON anuncios (marca_estandar);
CREATE INDEX IF NOT EXISTS ix_anuncios_producto     ON anuncios (producto_id);
CREATE INDEX IF NOT EXISTS ix_obs_ejecucion         ON observaciones (ejecucion_id);
CREATE INDEX IF NOT EXISTS ix_obs_comercio          ON observaciones (comercio_id);
CREATE INDEX IF NOT EXISTS ix_ejec_comercio         ON ejecuciones (comercio, inicio);
"""

# ----------------------------------------------------------------------------
# 6. Vistas (la app las consulta directamente)
# ----------------------------------------------------------------------------
# Expresión reutilizada: precio por unidad normalizada (NULL si no hay precio o contenido).
_PRECIO_UNIT = """CASE WHEN {p} IS NOT NULL AND a.contenido_normalizado > 0
                        THEN {p} / a.contenido_normalizado END"""

VISTAS = f"""
-- Última observación de cada anuncio. `disponibilidad` vale 'no observado' cuando el anuncio
-- no apareció en la última ejecución válida de su comercio (no significa agotado ni retirado).
DROP VIEW IF EXISTS v_ultimo_precio;
CREATE VIEW v_ultimo_precio AS
WITH ranked AS (
  SELECT o.*,
         ROW_NUMBER() OVER (PARTITION BY o.anuncio_id
                            ORDER BY o.fecha_consulta DESC, o.id DESC) AS rn
    FROM observaciones o
)
SELECT c.nombre                AS comercio,
       a.id                    AS anuncio_id,
       a.sku, a.url, a.texto_original, a.nombre_estandar,
       a.marca_estandar        AS marca,
       a.subcategoria,
       a.contenido_normalizado, a.unidad_normalizada,
       r.precio_cop            AS precio,
       r.precio_regular_cop,
       r.en_promocion,
       CASE WHEN e.corrida_id = (SELECT e2.corrida_id FROM ejecuciones e2
                                  WHERE e2.comercio = c.nombre AND e2.estado <> 'fallida'
                                  ORDER BY e2.inicio DESC, e2.id DESC LIMIT 1)
            THEN r.disponibilidad ELSE 'no observado' END AS disponibilidad,
       r.fecha_consulta,
       e.corrida_id,
       {_PRECIO_UNIT.format(p="r.precio_cop")} AS precio_unitario,
       p.id                    AS producto_id,
       CASE WHEN p.comparable = 1
             AND a.comercio_id IN (SELECT comercio_id FROM seleccion) THEN 1 ELSE 0 END AS comparable
  FROM ranked r
  JOIN anuncios    a ON a.id = r.anuncio_id
  JOIN comercios   c ON c.id = a.comercio_id
  JOIN ejecuciones e ON e.id = r.ejecucion_id
  LEFT JOIN productos p ON p.id = a.producto_id
 WHERE r.rn = 1 AND a.excluido = 0;

-- Cambios de precio entre observaciones consecutivas del MISMO anuncio en el MISMO comercio.
-- La app filtra por (corrida_anterior, corrida_id) para comparar las ejecuciones elegidas.
DROP VIEW IF EXISTS v_cambios_precio;
CREATE VIEW v_cambios_precio AS
WITH h AS (
  SELECT o.anuncio_id, o.ejecucion_id, o.fecha_consulta, o.precio_cop,
         LAG(o.precio_cop)     OVER (PARTITION BY o.anuncio_id ORDER BY o.fecha_consulta) AS precio_anterior,
         LAG(o.fecha_consulta) OVER (PARTITION BY o.anuncio_id ORDER BY o.fecha_consulta) AS fecha_anterior,
         LAG(o.ejecucion_id)   OVER (PARTITION BY o.anuncio_id ORDER BY o.fecha_consulta) AS ejecucion_anterior
    FROM observaciones o
)
SELECT c.nombre AS comercio, a.id AS anuncio_id, a.sku, a.url, a.texto_original,
       a.marca_estandar AS marca, a.subcategoria,
       ea.corrida_id AS corrida_anterior, e.corrida_id,
       h.fecha_anterior, h.fecha_consulta,
       h.precio_anterior, h.precio_cop AS precio_nuevo,
       h.precio_cop - h.precio_anterior                         AS variacion_cop,
       100.0 * (h.precio_cop - h.precio_anterior) / h.precio_anterior AS variacion_pct,
       CASE WHEN h.precio_cop > h.precio_anterior THEN 'subio'
            WHEN h.precio_cop < h.precio_anterior THEN 'bajo' ELSE 'igual' END AS sentido
  FROM h
  JOIN anuncios    a  ON a.id  = h.anuncio_id
  JOIN comercios   c  ON c.id  = a.comercio_id
  JOIN ejecuciones e  ON e.id  = h.ejecucion_id
  JOIN ejecuciones ea ON ea.id = h.ejecucion_anterior
 WHERE h.precio_anterior > 0 AND h.precio_cop IS NOT NULL AND a.excluido = 0;

-- Observaciones de los productos comparables (mismo producto en los comercios del análisis),
-- con precio unitario y el mínimo/máximo de cada producto en la misma ejecución.
-- es_precio_minimo = 1 también en empates.
DROP VIEW IF EXISTS v_comparables;
CREATE VIEW v_comparables AS
SELECT e.corrida_id, p.id AS producto_id, p.clave_comun, p.marca,
       p.nombre_estandar AS producto,
       c.nombre AS comercio, a.id AS anuncio_id, a.sku, a.url, a.texto_original,
       o.fecha_consulta, o.precio_cop AS precio, o.en_promocion, o.disponibilidad,
       a.contenido_normalizado, a.unidad_normalizada,
       {_PRECIO_UNIT.format(p="o.precio_cop")} AS precio_unitario,
       MIN(o.precio_cop) OVER (PARTITION BY p.id, e.corrida_id) AS precio_min_corrida,
       MAX(o.precio_cop) OVER (PARTITION BY p.id, e.corrida_id) AS precio_max_corrida,
       CASE WHEN o.precio_cop IS NOT NULL
             AND o.precio_cop = MIN(o.precio_cop) OVER (PARTITION BY p.id, e.corrida_id)
            THEN 1 ELSE 0 END AS es_precio_minimo
  FROM observaciones o
  JOIN ejecuciones e ON e.id = o.ejecucion_id
  JOIN anuncios    a ON a.id = o.anuncio_id
  JOIN comercios   c ON c.id = a.comercio_id
  JOIN productos   p ON p.id = a.producto_id
 WHERE p.comparable = 1
   AND a.excluido = 0
   AND a.comercio_id IN (SELECT comercio_id FROM seleccion);
"""


def _ejecutar_script(con, script):
    """Ejecuta varias sentencias dentro de la transacción abierta (executescript haría COMMIT)."""
    # Se divide por ';' al final de línea, salvo dentro de triggers (BEGIN ... END;).
    sentencia, en_trigger = [], False
    for linea in script.splitlines():
        if linea.strip().startswith("--"):
            continue                      # se ignoran los comentarios
        sentencia.append(linea)
        s = linea.strip().upper()
        if s.startswith("CREATE TRIGGER"):
            en_trigger = True
        if (en_trigger and s == "END;") or (not en_trigger and s.endswith(";")):
            texto = "\n".join(sentencia).strip()
            if texto:
                con.execute(texto)
            sentencia, en_trigger = [], False


def migrar(db_path=DB_PATH):
    """Aplica la migración completa de forma atómica e idempotente."""
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"No existe la base: {db_path}")
    con = sqlite3.connect(db_path, isolation_level=None)   # transacción manejada a mano
    try:
        con.execute("BEGIN")

        # 1. Tablas nuevas
        _ejecutar_script(con, TABLAS)

        # 2. Disponibilidad: disponible / agotado / no observado
        #    ('no observado' no se almacena por observación -porque no hay fila-; lo calcula
        #     v_ultimo_precio. El CHECK permite el valor por si se registra explícitamente).
        _agregar_columna(con, "observaciones", "disponibilidad",
                         "TEXT CHECK (disponibilidad IN ('disponible','agotado','no observado'))")
        con.execute("""UPDATE observaciones
                          SET disponibilidad = CASE WHEN disponible = 1 THEN 'disponible' ELSE 'agotado' END
                        WHERE disponibilidad IS NULL""")

        # 3. Contenido total y unidad normalizada (mL, g, unidad). `contenido_total` ya existe
        #    en `anuncios` desde el Taller 1; la llamada es un no-op en ese caso.
        _agregar_columna(con, "anuncios", "contenido_total", "REAL")
        _agregar_columna(con, "anuncios", "unidad_normalizada",
                         "TEXT CHECK (unidad_normalizada IN ('mL','g','unidad'))")
        _agregar_columna(con, "anuncios", "contenido_normalizado", "REAL")
        # mg se convierte a g (1 g = 1000 mg) para no mezclar unidades en los rankings.
        con.execute("""UPDATE anuncios
                          SET unidad_normalizada = CASE unidad_base
                                WHEN 'mL' THEN 'mL' WHEN 'g' THEN 'g'
                                WHEN 'mg' THEN 'g'  WHEN 'unidad' THEN 'unidad' END,
                              contenido_normalizado = CASE WHEN unidad_base = 'mg'
                                THEN contenido_total / 1000.0 ELSE contenido_total END
                        WHERE unidad_normalizada IS NULL AND unidad_base IS NOT NULL""")

        # 4. Unicidad (comercio, anuncio, fecha_consulta): `observaciones` no guarda el comercio,
        #    así que se añade `comercio_id` (copiado del anuncio) y se indexa de forma única.
        _agregar_columna(con, "observaciones", "comercio_id", "INTEGER REFERENCES comercios(id)")
        con.execute("""UPDATE observaciones
                          SET comercio_id = (SELECT a.comercio_id FROM anuncios a
                                              WHERE a.id = observaciones.anuncio_id)
                        WHERE comercio_id IS NULL""")
        duplicadas = con.execute("""SELECT COUNT(*) FROM (
                                      SELECT 1 FROM observaciones
                                       GROUP BY comercio_id, anuncio_id, fecha_consulta
                                      HAVING COUNT(*) > 1)""").fetchone()[0]
        if duplicadas:
            raise RuntimeError(f"Hay {duplicadas} observaciones duplicadas; resuélvalas antes de migrar.")

        # Triggers (rellenan los campos nuevos cuando el scraper inserta sin conocerlos)
        _ejecutar_script(con, TRIGGERS)

        # 5. Índices (incluye el índice único del punto 4)
        _ejecutar_script(con, INDICES)

        # 6. Vistas
        _ejecutar_script(con, VISTAS)

        con.execute("COMMIT")
        con.execute("ANALYZE")   # estadísticas para que el planificador use los índices
    except Exception:
        if con.in_transaction:
            con.execute("ROLLBACK")
        raise
    finally:
        con.close()


if __name__ == "__main__":
    ruta = sys.argv[1] if len(sys.argv) > 1 else DB_PATH
    migrar(ruta)
    print(f"Migración aplicada a {ruta}")
