"""
validacion.py - Validación con pandera de las observaciones del scraper ANTES de insertarlas.

Reglas (Módulo 1, sección 3.4):
  * precio numérico y mayor que cero (el precio ausente/NULL se permite: significa "no extraído"
    o "agotado" y nunca se reemplaza por 0; si hay valor, debe ser > 0);
  * `comercio`, `url` y `fecha_consulta` no nulos (y no vacíos);
  * `fecha_consulta` en ISO 8601 con zona horaria;
  * sin observaciones duplicadas (comercio, sku, fecha_consulta).

Uso típico dentro de scraper.py / app.py:
    from validacion import validar_observaciones
    validas, rechazadas = validar_observaciones(df)
    # insertar `validas`; guardar `rechazadas` (tiene la columna `motivo_rechazo`)
"""

import re

import pandas as pd
import pandera as pa
from pandera import Check, Column, DataFrameSchema

# ISO 8601 con offset, p. ej. 2026-08-14T10:35:00-05:00
_ISO_8601 = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$")

# Clave que identifica una observación (coincide con la restricción única de la base).
CLAVE_UNICA = ["comercio", "sku", "fecha_consulta"]

# Nombres de columnas tal como las devuelve el scraper (scraper.COLUMNAS).
# NOTA: pandera exige `unique` sobre columnas existentes; `sku` hace de id_anuncio.
ESQUEMA = DataFrameSchema(
    {
        # Número > 0. nullable=True: un precio no disponible queda como NULL, no como 0.
        "precio_cop": Column(float, Check.gt(0), nullable=True, coerce=True,
                             title="Precio en COP"),
        "comercio": Column(str, Check.str_length(min_value=1), nullable=False,
                           title="Comercio"),
        "url": Column(str, Check.str_length(min_value=1), nullable=False,
                      title="URL de extracción"),
        "fecha_consulta": Column(
            str,
            Check(lambda s: s.map(lambda v: bool(_ISO_8601.match(str(v)))),
                  error="fecha_consulta debe ser ISO 8601 con zona horaria"),
            nullable=False, title="Fecha y hora de consulta"),
        "sku": Column(str, Check.str_length(min_value=1), nullable=False, coerce=True,
                      title="SKU / id del anuncio"),
    },
    unique=CLAVE_UNICA,          # ausencia de duplicados en la misma observación
    unique_column_names=True,
    strict=False,                # se permiten columnas adicionales del scraper
    coerce=False,
)


def _motivos_por_fila(df):
    """Devuelve una Serie con el motivo de rechazo por fila ('' si la fila es válida)."""
    motivos = pd.Series("", index=df.index, dtype=object)

    def marcar(mascara, texto):
        motivos[mascara] = motivos[mascara].map(lambda m: f"{m}; {texto}" if m else texto)

    # Precio: no numérico o <= 0 (los NULL son aceptables)
    precio = pd.to_numeric(df["precio_cop"], errors="coerce")
    marcar(df["precio_cop"].notna() & precio.isna(), "precio no numérico")
    marcar(precio.notna() & (precio <= 0), "precio <= 0")

    # Campos obligatorios no nulos / no vacíos
    for col, nombre in (("comercio", "comercio"), ("url", "url"),
                        ("fecha_consulta", "fecha_consulta"), ("sku", "sku")):
        vacio = df[col].isna() | (df[col].astype(str).str.strip() == "")
        marcar(vacio, f"{nombre} ausente")

    # Formato de fecha
    fecha_ok = df["fecha_consulta"].astype(str).map(lambda v: bool(_ISO_8601.match(v)))
    marcar(df["fecha_consulta"].notna() & ~fecha_ok, "fecha_consulta no es ISO 8601 con zona")

    # Duplicados: se acepta la primera aparición y se rechazan las repetidas
    marcar(df.duplicated(subset=CLAVE_UNICA, keep="first"),
           "observación duplicada (comercio, sku, fecha_consulta)")
    return motivos


def validar_observaciones(df):
    """
    Valida un DataFrame de observaciones nuevas.

    Devuelve (validas, rechazadas):
      * validas     -> filas que cumplen TODAS las reglas (listas para insertar);
      * rechazadas  -> filas que fallan alguna regla, con la columna `motivo_rechazo`.
    Nunca modifica ni "arregla" los valores: una fila inválida se rechaza, no se corrige.
    """
    faltan = [c for c in ESQUEMA.columns if c not in df.columns]
    if faltan:
        raise ValueError(f"Faltan columnas obligatorias: {faltan}")

    motivos = _motivos_por_fila(df)
    rechazadas = df[motivos != ""].copy()
    rechazadas["motivo_rechazo"] = motivos[motivos != ""]
    validas = df[motivos == ""].copy()

    # Verificación final con pandera sobre las filas aceptadas (lazy: reporta todos los errores).
    try:
        ESQUEMA.validate(validas, lazy=True)
    except pa.errors.SchemaErrors as e:    # no debería ocurrir; es una red de seguridad
        raise RuntimeError(f"Validación pandera inconsistente:\n{e.failure_cases}") from e
    return validas, rechazadas


def validar_comparables(df, comparables_por_comercio, minimo=8):
    """
    Regla de cobertura: presencia de los 8 productos comparables en cada comercio.

    df: observaciones válidas con columnas `comercio` y `producto_id`.
    comparables_por_comercio: iterable con los comercios del análisis.
    Devuelve {comercio: n_comparables}; lanza ValueError si algún comercio queda bajo `minimo`.
    """
    conteo = (df.dropna(subset=["producto_id"])
                .groupby("comercio")["producto_id"].nunique().to_dict())
    resumen = {c: int(conteo.get(c, 0)) for c in comparables_por_comercio}
    faltantes = {c: n for c, n in resumen.items() if n < minimo}
    if faltantes:
        raise ValueError(f"Cobertura insuficiente (< {minimo} comparables): {faltantes}")
    return resumen


def guardar_rechazadas(con, rechazadas, corrida_id, fecha_rechazo):
    """Registra en `observaciones_rechazadas` las filas inválidas con su motivo (con= conexión sqlite3)."""
    import json
    con.executemany(
        """INSERT INTO observaciones_rechazadas
           (fecha_rechazo, corrida_id, comercio, sku, fecha_consulta, precio_cop, motivo, fila_json)
           VALUES (?,?,?,?,?,?,?,?)""",
        [(fecha_rechazo, corrida_id, r.get("comercio"), r.get("sku"), r.get("fecha_consulta"),
          None if pd.isna(r.get("precio_cop")) else float(r["precio_cop"]),
          r["motivo_rechazo"], json.dumps(r.to_dict(), default=str, ensure_ascii=False))
         for _, r in rechazadas.iterrows()])
    con.commit()
