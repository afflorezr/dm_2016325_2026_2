"""
validacion.py
=============
Módulo de validación de calidad de datos con Pandera.
Taller 2 - Minería de Datos (UNAL, código 2016325).

Reglas mínimas obligatorias (según PDF 3.4 y Anexo C):
  1. Precio numérico mayor a cero (precio > 0), o NULL únicamente si disponibilidad = 'agotado'.
  2. Comercio, URL y fecha_hora_consulta no nulos.
  3. Ausencia de observaciones duplicadas en la misma ejecución (comercio, sku, ejecucion_id).
  4. Presencia de los ocho productos comparables en el comercio (regla a nivel de lote).
  5. Registro trazable de cualquier rechazo en la tabla SQLite `rechazos`.
"""

import json
import sqlite3
import datetime
from typing import Dict, List, Tuple, Any, Optional
import pandas as pd
try:
    import pandera.pandas as pa
except ImportError:
    import pandera as pa
from pandera import Column, Check, DataFrameSchema


def check_precio_nulo_solo_si_agotado(df: pd.DataFrame) -> pd.Series:
    """
    Regla de negocio:
    El precio puede ser NULL (o NaN) únicamente si disponibilidad == 'agotado'.
    Si el producto está disponible, debe tener precio numérico estrictamente > 0.
    Cualquier precio <= 0 se rechaza siempre.
    """
    es_nulo = df["precio_actual"].isna()
    disp_col = df["disponibilidad"].fillna("").astype(str).str.lower().str.strip()
    es_agotado = disp_col == "agotado"

    # 1. Si es nulo, es válido únicamente si está agotado
    nulo_valido = ~es_nulo | (es_nulo & es_agotado)
    # 2. Si no es nulo, debe ser estrictamente positivo (> 0)
    positivo_valido = es_nulo | (df["precio_actual"] > 0)

    return nulo_valido & positivo_valido


# Esquema Pandera para validación estricta de observaciones individuales
schema_observacion = DataFrameSchema(
    columns={
        "precio_actual": Column(float, nullable=True, coerce=True),
        "disponibilidad": Column(str, nullable=True, coerce=True),
        "comercio": Column(str, Check.str_length(min_value=1), nullable=False),
        "url": Column(str, Check.str_length(min_value=5), nullable=False),
        "fecha_hora_consulta": Column(str, Check.str_length(min_value=10), nullable=False),
        "sku": Column(str, nullable=False, coerce=True),
        "ejecucion_id": Column(str, nullable=False),
    },
    checks=[
        Check(check_precio_nulo_solo_si_agotado, name="precio_nulo_solo_si_agotado_y_mayor_a_cero")
    ],
    unique=["comercio", "sku", "ejecucion_id"],
    coerce=True,
    strict=False
)


def registrar_rechazo_db(
    conn: sqlite3.Connection,
    ejecucion_id: str,
    comercio: str,
    sku: str,
    datos: Dict[str, Any],
    regla: str,
    motivo: str
):
    """Inserta un registro formal de rechazo en la tabla SQLite rechazos."""
    cur = conn.cursor()
    fecha_iso = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-5))).isoformat(timespec="seconds")
    cur.execute("""
        INSERT INTO rechazos (ejecucion_id, comercio, sku, datos_json, regla, motivo, fecha)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (ejecucion_id, comercio, str(sku), json.dumps(datos, ensure_ascii=False), regla, motivo, fecha_iso))


def validar_lote_observaciones(
    observaciones: List[Dict[str, Any]],
    conn: sqlite3.Connection,
    ejecucion_id: str,
    comercio_nombre: str
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], bool, Optional[str]]:
    """
    Valida un lote de observaciones recolectadas antes de insertar en la base de datos.

    Retorna:
      - validas: Lista de diccionarios de observaciones que cumplen todas las reglas.
      - rechazadas: Lista de diccionarios rechazados con motivo.
      - lote_completo: True si el lote contiene los 8 comparables canónicos; False si falta alguno.
      - motivo_parcial: Descripción del motivo si falta algún comparable (para marcar estado 'parcial').
    """
    if not observaciones:
        return [], [], False, "Lote vacío sin observaciones."

    validas = []
    rechazadas = []

    # 1. Validación registro a registro (claves primarias, nulos, disponibilidad y precio)
    seen_keys = set()
    for row_dict in observaciones:
        item = dict(row_dict)
        sku = str(item.get("sku") or "").strip()
        url = str(item.get("url") or "").strip()
        ts = str(item.get("fecha_hora_consulta") or "").strip()
        p = item.get("precio_actual")
        disp = str(item.get("disponibilidad") or "disponible").lower().strip()
        item["disponibilidad"] = disp

        # Regla: Ausencia de duplicados en la misma ejecución
        key = (comercio_nombre, sku, ejecucion_id)
        if key in seen_keys:
            motivo = "Observación duplicada en la misma ejecución (mismo comercio y sku)"
            registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "duplicado_ejecucion", motivo)
            rechazadas.append({**item, "motivo_rechazo": motivo})
            continue
        seen_keys.add(key)

        # Regla: Campos presentes no nulos
        if not sku:
            motivo = "SKU ausente o nulo"
            registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "sku_vacio", motivo)
            rechazadas.append({**item, "motivo_rechazo": motivo})
            continue

        if not url:
            motivo = "URL ausente o nula"
            registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "url_vacia", motivo)
            rechazadas.append({**item, "motivo_rechazo": motivo})
            continue

        if not ts:
            motivo = "fecha_hora_consulta ausente o nula"
            registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "fecha_vacia", motivo)
            rechazadas.append({**item, "motivo_rechazo": motivo})
            continue

        # Regla: Precio numérico mayor a cero, o NULL únicamente si disponibilidad = 'agotado'
        if p is None or pd.isna(p):
            if disp == "agotado":
                item["precio_actual"] = None
                validas.append(item)
            else:
                motivo = f"Precio actual es NULL/NaN en producto no agotado (disponibilidad='{disp}')"
                registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "precio_nulo_no_agotado", motivo)
                rechazadas.append({**item, "motivo_rechazo": motivo})
            continue

        try:
            p_float = float(p)
            if pd.isna(p_float):
                if disp == "agotado":
                    item["precio_actual"] = None
                    validas.append(item)
                else:
                    motivo = f"Precio actual es NaN en producto no agotado (disponibilidad='{disp}')"
                    registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "precio_nulo_no_agotado", motivo)
                    rechazadas.append({**item, "motivo_rechazo": motivo})
                continue

            if p_float <= 0:
                motivo = f"Precio actual no positivo ({p_float} <= 0)"
                registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "precio_no_positivo", motivo)
                rechazadas.append({**item, "motivo_rechazo": motivo})
                continue

            item["precio_actual"] = p_float
            validas.append(item)
        except (ValueError, TypeError):
            motivo = f"Precio no convertible a float: {p}"
            registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, item, "precio_invalido", motivo)
            rechazadas.append({**item, "motivo_rechazo": motivo})
            continue

    # 2. Validación de lote con Pandera sobre el subset de válidas
    if validas:
        df_validas = pd.DataFrame(validas)
        if "comercio" not in df_validas.columns:
            df_validas["comercio"] = comercio_nombre
        if "ejecucion_id" not in df_validas.columns:
            df_validas["ejecucion_id"] = ejecucion_id
        if "disponibilidad" not in df_validas.columns:
            df_validas["disponibilidad"] = "disponible"

        try:
            schema_observacion.validate(df_validas, lazy=True)
        except pa.errors.SchemaErrors as err:
            indices_fallidos = set()
            failure_cases = err.failure_cases
            if "index" in failure_cases.columns:
                for idx in failure_cases["index"].dropna():
                    try:
                        indices_fallidos.add(int(idx))
                    except (ValueError, TypeError):
                        pass

            nuevas_validas = []
            for i, v in enumerate(validas):
                if i in indices_fallidos:
                    motivo = "Falló validación de esquema Pandera"
                    sku = str(v.get("sku") or "")
                    registrar_rechazo_db(conn, ejecucion_id, comercio_nombre, sku, v, "pandera_schema_error", motivo)
                    rechazadas.append({**v, "motivo_rechazo": motivo})
                else:
                    nuevas_validas.append(v)
            validas = nuevas_validas

    # 3. Regla a nivel de lote: presencia de los 8 productos comparables en el comercio
    cur = conn.cursor()
    cur.execute("SELECT ean, nombre_referencia FROM comparables_8;")
    comparables_requeridos = cur.fetchall()

    eans_en_lote = set(str(v.get("ean") or "") for v in validas if v.get("ean"))
    faltantes = []
    for c_ean, c_nom in comparables_requeridos:
        if str(c_ean) not in eans_en_lote:
            faltantes.append(f"{c_nom} (EAN: {c_ean})")

    if faltantes:
        lote_completo = False
        motivo_parcial = f"Faltan {len(faltantes)} de los 8 comparables canónicos en el lote: {'; '.join(faltantes)}"
    else:
        lote_completo = True
        motivo_parcial = None

    return validas, rechazadas, lote_completo, motivo_parcial
