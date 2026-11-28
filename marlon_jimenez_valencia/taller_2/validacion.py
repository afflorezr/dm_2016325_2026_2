"""
validacion.py — Reglas de validación antes de insertar observaciones (Taller 2, §3.4).

Ninguna observación entra a la base sin pasar por validar_observaciones(). Las reglas
se escriben con pandera (Anexo C del enunciado):

  1. precio_numerico_mayor_que_cero   el precio (y el precio de lista) es un número > 0.
                                      Puede faltar (NULL) solo si el producto está
                                      agotado: un dato ausente queda ausente (§3.1).
  2. disponible_con_precio            un producto disponible debe tener precio.
  3. campos_obligatorios              comercio, SKU, URL de extracción y fecha y hora de
                                      consulta (ISO 8601 con -05:00) presentes y válidos.
  4. sin_duplicados                   una sola observación por (ejecución, comercio, SKU);
                                      se conserva la primera y las demás se rechazan.
  5. comparables_presentes            los productos comparables de correspondencia.csv
                                      están en el comercio (al menos MIN_COMPARABLES).

Las filas que no pasan las reglas 1 a 4 NO se insertan: se devuelven en `rechazadas`
con el motivo, y scraper.py las guarda en la tabla rechazos. La regla 5 es del
comercio completo: si fallan más de los permitidos, la ejecución de ese comercio
queda 'parcial'.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd
import pandera.pandas as pa

MIN_COMPARABLES = 8                     # el enunciado pide ocho productos comparables
FECHA_ISO = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-05:00$"
ID_EJECUCION = r"^E\d{8}T\d{6}$"

REGLAS = ["precio_numerico_mayor_que_cero", "disponible_con_precio", "campos_obligatorios",
          "sin_duplicados", "comparables_presentes"]

ESQUEMA = pa.DataFrameSchema(
    columns={
        "id_ejecucion": pa.Column(str, pa.Check.str_matches(ID_EJECUCION), nullable=False),
        "comercio": pa.Column(str, pa.Check.str_length(min_value=1), nullable=False),
        "sku_comercio": pa.Column(str, pa.Check.str_length(min_value=1), nullable=False),
        "url_extraccion": pa.Column(str, pa.Check.str_matches(r"^https?://\S+$"), nullable=False),
        "fecha_consulta": pa.Column(str, pa.Check.str_matches(FECHA_ISO), nullable=False),
        "precio": pa.Column("float64", pa.Check.gt(0), nullable=True, coerce=True),
        "precio_lista": pa.Column("float64", pa.Check.gt(0), nullable=True, coerce=True),
        "disponible": pa.Column("int64", pa.Check.isin([0, 1]), nullable=False, coerce=True),
    },
    checks=[
        pa.Check(lambda d: d["precio"].notna() | (d["disponible"] == 0),
                 name="disponible_con_precio", error="producto disponible sin precio"),
    ],
    unique=["id_ejecucion", "comercio", "sku_comercio"],
    report_duplicates="exclude_first",
    strict=False,
)


@dataclass
class Resultado:
    validas: pd.DataFrame
    rechazadas: pd.DataFrame                     # mismas columnas + `motivo`
    reglas: list[dict] = field(default_factory=list)
    comparables_presentes: int = 0
    comparables_faltantes: list[str] = field(default_factory=list)


# pandera reporta la regla de toda la fila con su mensaje de error, una vez por columna
DISPONIBLE_CON_PRECIO = {"disponible_con_precio", "producto disponible sin precio"}


def _regla(columna, check: str) -> str:
    """A qué regla del enunciado corresponde una falla que reporta pandera."""
    if check in DISPONIBLE_CON_PRECIO:
        return "disponible_con_precio"
    if "uniqueness" in check or check == "unique":
        return "sin_duplicados"
    if columna in ("precio", "precio_lista"):
        return "precio_numerico_mayor_que_cero"
    return "campos_obligatorios"


def _motivo(columna, check: str, valor) -> str:
    """Motivo del rechazo en español, para la tabla rechazos."""
    if check in DISPONIBLE_CON_PRECIO:
        return "producto disponible sin precio"
    if "uniqueness" in check or check == "unique":
        return "observación duplicada en la misma ejecución (mismo comercio y SKU)"
    if check == "not_nullable":
        return f"falta {columna}"
    if check.startswith("greater_than"):
        return f"{columna} = {valor}: debe ser mayor que 0"
    if check.startswith(("coerce_dtype", "dtype")):
        return f"{columna} = {valor!r}: no es un número"
    if check.startswith("str_length"):
        return f"{columna} vacío"
    if check.startswith("str_matches"):
        return f"{columna} con formato inválido: {valor!r}"
    if check.startswith("isin"):
        return f"{columna} = {valor!r}: valor no permitido"
    return f"{columna}: no cumple {check} (valor {valor!r})"


def validar_observaciones(df: pd.DataFrame, comparables: dict[str, str] | None = None) -> Resultado:
    """
    Valida las observaciones de UN comercio en una ejecución.

    df           filas del scraper ya procesadas (columnas de scraper.COLUMNAS y las
                 estandarizadas). Solo las de la categoría (incluido = True).
    comparables  {sku_comercio: id_producto} de ese comercio, según correspondencia.csv.
    """
    comparables = comparables or {}
    datos = df.reset_index(drop=True)
    fallas: dict[int, list[tuple[str, str]]] = {}     # fila -> [(regla, motivo)]
    if not datos.empty:
        try:
            ESQUEMA.validate(datos, lazy=True)    # lazy=True: reporta TODOS los errores
        except pa.errors.SchemaErrors as err:
            casos = err.failure_cases
            for c in casos.itertuples(index=False):
                check = str(c.check)
                if pd.isna(c.index):
                    # falla de toda la columna (p. ej. la columna no existe): se rechaza todo
                    filas = list(datos.index)
                else:
                    filas = [int(c.index)]
                for i in filas:
                    fallas.setdefault(i, []).append(
                        (_regla(c.column, check), _motivo(c.column, check, c.failure_case)))

    malas = sorted(fallas)
    rechazadas = datos.loc[malas].copy()
    rechazadas["motivo"] = ["; ".join(sorted({m for _, m in fallas[i]})) for i in malas]
    validas = datos.drop(index=malas)

    reglas = []
    for regla in REGLAS[:4]:
        n = sum(any(r == regla for r, _ in fallas[i]) for i in malas)
        ejemplos = sorted({m for i in malas for r, m in fallas[i] if r == regla})[:3]
        reglas.append({"regla": regla, "n_revisadas": len(datos), "n_fallas": n,
                       "aprobada": n == 0,
                       "detalle": "; ".join(ejemplos) if ejemplos else "sin fallas"})

    # Regla 5: productos comparables presentes (entre las observaciones válidas)
    presentes, faltantes, sin_precio = [], [], []
    if comparables:
        por_sku = validas.set_index("sku_comercio")
        for sku, id_producto in sorted(comparables.items(), key=lambda x: x[1]):
            if sku in por_sku.index:
                presentes.append(id_producto)
                if pd.isna(por_sku.loc[sku, "precio"]):
                    sin_precio.append(id_producto)
            else:
                faltantes.append(f"{id_producto} (SKU {sku})")
        detalle = f"{len(presentes)} de {len(comparables)} presentes"
        if faltantes:
            detalle += "; faltan: " + ", ".join(faltantes)
        if sin_precio:
            detalle += "; agotados sin precio: " + ", ".join(sin_precio)
        reglas.append({"regla": "comparables_presentes", "n_revisadas": len(comparables),
                       "n_fallas": len(faltantes), "aprobada": not faltantes,
                       "detalle": detalle})

    return Resultado(validas=validas, rechazadas=rechazadas, reglas=reglas,
                     comparables_presentes=len(presentes), comparables_faltantes=faltantes)
