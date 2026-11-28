"""
Validación de observaciones antes de insertarlas en la base (Módulo 1, sección 3.4).

Reglas explícitas con pandera:
  R1. precio_actual numérico y mayor que cero;
  R2. comercio, url y fecha_hora_consulta presentes (no nulos ni vacíos);
  R3. sin observaciones duplicadas en la misma ejecución
      (comercio, id_producto_comercio, fecha_hora_consulta);
  R4. url con esquema http(s);
  R5. unidad de contenido normalizada (mL, g o unidad) o ausente;
  R6. disponibilidad dentro de los valores permitidos o ausente;
  R7. (nivel ejecución) presencia de al menos MIN_COMPARABLES productos comparables
      en el comercio.

Las filas que no cumplen R1-R6 no se insertan: se devuelven con el motivo del
rechazo para registrarlas en la tabla observaciones_rechazadas.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List

import pandas as pd
import pandera.pandas as pa

MIN_COMPARABLES = 8
UNIDADES_VALIDAS = ["mL", "g", "unidad"]
ESTADOS_DISPONIBILIDAD = ["disponible", "agotado"]
CLAVE_UNICA = ["comercio", "id_producto_comercio", "fecha_hora_consulta"]

# Descripción legible de cada regla, para el motivo del rechazo
MOTIVOS = {
    "precio_actual": "R1: precio ausente, no numérico o no mayor que cero",
    "comercio": "R2: comercio ausente",
    "url": "R2/R4: URL ausente o sin esquema http(s)",
    "fecha_hora_consulta": "R2: fecha y hora de consulta ausente",
    "id_producto_comercio": "R2: identificador del anuncio ausente",
    "contenido_unidad": "R5: unidad de contenido no normalizada",
    "estado_disponibilidad": "R6: estado de disponibilidad no permitido",
    "duplicado": "R3: observación duplicada en la misma ejecución",
}

_no_vacio = pa.Check.str_length(min_value=1)

ESQUEMA_OBSERVACION = pa.DataFrameSchema(
    {
        "comercio": pa.Column(str, _no_vacio, nullable=False),
        "id_producto_comercio": pa.Column(str, _no_vacio, nullable=False),
        "nombre_original": pa.Column(str, nullable=False),
        "precio_actual": pa.Column(float, pa.Check.gt(0), nullable=False),
        "url": pa.Column(str, pa.Check.str_matches(r"^https?://\S+$"), nullable=False),
        "fecha_hora_consulta": pa.Column(str, _no_vacio, nullable=False),
        "contenido_unidad": pa.Column(str, pa.Check.isin(UNIDADES_VALIDAS), nullable=True),
        "estado_disponibilidad": pa.Column(str, pa.Check.isin(ESTADOS_DISPONIBILIDAD), nullable=True),
    },
    unique=CLAVE_UNICA,
    report_duplicates="exclude_first",
    coerce=False,
    strict=False,
)

_COLUMNAS_BASE = list(ESQUEMA_OBSERVACION.columns.keys())


@dataclass
class ResultadoValidacion:
    validas: pd.DataFrame
    rechazadas: pd.DataFrame                       # columnas originales + "motivo"
    comparables_encontrados: List[str] = field(default_factory=list)
    comparables_faltantes: List[str] = field(default_factory=list)

    @property
    def cumple_comparables(self) -> bool:
        return len(self.comparables_encontrados) >= MIN_COMPARABLES


def _a_dataframe(productos: List[Dict[str, Any]]) -> pd.DataFrame:
    df = pd.DataFrame(productos)
    for col in _COLUMNAS_BASE + ["comparable", "id_producto_comun"]:
        if col not in df.columns:
            df[col] = None
    # Tipos explícitos sin inventar valores: lo ausente queda como ausente
    df["precio_actual"] = pd.to_numeric(df["precio_actual"], errors="coerce").astype("float64")
    for col in ["comercio", "id_producto_comercio", "nombre_original", "url", "fecha_hora_consulta",
                "contenido_unidad", "estado_disponibilidad"]:
        df[col] = df[col].astype(object).where(df[col].notna(), None)
    return df.reset_index(drop=True)


def validar_observaciones(productos: List[Dict[str, Any]], ids_comparables: List[str]) -> ResultadoValidacion:
    """Aplica las reglas R1-R7 y separa las observaciones válidas de las rechazadas."""
    if not productos:
        vacio = pd.DataFrame(columns=_COLUMNAS_BASE + ["motivo"])
        return ResultadoValidacion(vacio.drop(columns="motivo"), vacio, [], list(ids_comparables))

    df = _a_dataframe(productos)
    motivos: Dict[int, List[str]] = {}
    try:
        ESQUEMA_OBSERVACION.validate(df, lazy=True)
    except pa.errors.SchemaErrors as err:
        casos = err.failure_cases
        for _, caso in casos.iterrows():
            idx = caso.get("index")
            if idx is None or pd.isna(idx):
                continue
            columna = caso.get("column")
            if "unique" in str(caso.get("check")).lower():
                motivo = MOTIVOS["duplicado"]
            else:
                motivo = MOTIVOS.get(str(columna), f"Regla incumplida en {columna}: {caso.get('check')}")
            lista = motivos.setdefault(int(idx), [])
            if motivo not in lista:
                lista.append(motivo)

    # Respaldo explícito de R3 (independiente de la versión de pandera)
    dup = df.duplicated(subset=CLAVE_UNICA, keep="first")
    for idx in df.index[dup]:
        lista = motivos.setdefault(int(idx), [])
        if MOTIVOS["duplicado"] not in lista:
            lista.append(MOTIVOS["duplicado"])

    idx_rech = sorted(motivos)
    rechazadas = df.loc[idx_rech].copy()
    rechazadas["motivo"] = ["; ".join(motivos[i]) for i in idx_rech]
    validas = df.drop(index=idx_rech)

    encontrados = sorted(set(validas.loc[validas["comparable"].fillna(0).astype(int) == 1, "id_producto_comun"].dropna()))
    faltantes = [c for c in ids_comparables if c not in encontrados]
    return ResultadoValidacion(validas.reset_index(drop=True), rechazadas.reset_index(drop=True), encontrados, faltantes)
