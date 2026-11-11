"""
validacion.py — Taller 2 Minería de Datos (UNAL): reglas de validación antes de insertar (§3.4 del enunciado).

Ninguna observación entra a la base sin pasar por aquí. Reglas explícitas con pandera:
  R1. precio numérico y mayor que cero (un precio ausente NO se completa: la fila se rechaza);
  R2. comercio, SKU, id de ejecución, URL y fecha y hora de consulta presentes (y con formato válido);
  R3. sin observaciones duplicadas (mismo comercio y SKU) en la misma ejecución: se conserva la primera;
  R4. presencia de los productos comparables en cada comercio (regla sobre el conjunto, no sobre una fila).
Las filas que no cumplen R1-R3 se devuelven aparte, con la regla y el motivo, para la tabla `rechazos`.
"""
from __future__ import annotations

import re

import pandas as pd
import pandera.pandas as pa

import scraper

# Columnas de texto que exige el esquema (las demás columnas del scraper pasan sin revisar).
COLUMNAS_TEXTO = ["comercio", "sku_comercio", "id_ejecucion", "url", "fecha_hora_consulta"]
COLUMNAS_RECHAZO = ["id_ejecucion", "id_comercio", "sku_comercio", "fecha_hora_consulta", "url", "precio",
                    "regla", "motivo"]


# Convierte un precio en texto ("$ 12.900", "12.900,50", "COP 8900").
# Si no hay un número legible devuelve None: el dato ausente queda ausente, nunca se inventa.
def precio_a_numero(valor) -> float | None:
    if valor is None or isinstance(valor, bool):
        return None
    if isinstance(valor, (int, float)):
        return None if pd.isna(valor) else float(valor)
    texto = re.sub(r"[^\d.,]", "", str(valor))       # quita $, COP, espacios...
    if not re.search(r"\d", texto):
        return None
    if "," in texto:                                   # formato colombiano con decimales: 12.900,50
        texto = texto.replace(".", "").replace(",", ".")
    elif re.fullmatch(r"\d{1,3}(\.\d{3})+", texto):    # puntos de miles: 12.900 o 1.250.000
        texto = texto.replace(".", "")
    try:
        return float(texto)
    except ValueError:
        return None


# Reglas R1-R3 en un esquema de pandera (una revisión por fila).
ESQUEMA_OBSERVACIONES = pa.DataFrameSchema(
    {
        "comercio": pa.Column(str, pa.Check.isin(list(scraper.COMERCIOS)), nullable=False),
        "sku_comercio": pa.Column(str, pa.Check.str_length(min_value=1), nullable=False),
        "id_ejecucion": pa.Column(str, pa.Check.str_matches(r"^\d{8}T\d{6}$"), nullable=False),
        "precio": pa.Column(float, pa.Check.gt(0), nullable=False),
        "url": pa.Column(str, pa.Check.str_startswith("https://"), nullable=False),
        "fecha_hora_consulta": pa.Column(str, pa.Check.str_matches(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"),
                                         nullable=False),
    },
    unique=["id_ejecucion", "comercio", "sku_comercio"],
    report_duplicates="exclude_first",  # el primer registro se conserva; los repetidos se rechazan
    strict=False,
)


# Traduce una falla de pandera a una regla corta y un motivo en español para la tabla `rechazos`.
def _regla_y_motivo(columna, revision: str) -> tuple[str, str]:
    if "uniqueness" in revision:
        return "duplicado_en_ejecucion", "Observación repetida (mismo comercio y SKU) en la misma ejecución"
    if columna == "precio":
        if revision == "not_nullable":
            return "precio_mayor_que_cero", "Precio ausente (NULL): el sitio no publicó precio"
        return "precio_mayor_que_cero", f"Precio no válido ({revision})"
    if revision == "not_nullable":
        return "campo_obligatorio", f"Falta el campo obligatorio '{columna}'"
    return "formato_invalido", f"El campo '{columna}' no cumple la regla {revision}"


# Prepara los tipos antes de validar: precio a número y columnas de texto como texto (los ausentes
# siguen ausentes).
def _preparar(df: pd.DataFrame) -> pd.DataFrame:
    datos = df.reset_index(drop=True).copy()
    datos["precio"] = datos["precio"].map(precio_a_numero).astype("float64")
    for columna in COLUMNAS_TEXTO:
        datos[columna] = datos[columna].astype("str")
    return datos


# Aplica R1-R3. Devuelve (validas, rechazadas): las válidas se pueden insertar; las rechazadas traen una
# fila por cada regla incumplida, con las columnas de la tabla `rechazos`.
def validar_observaciones(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    datos = _preparar(df)
    try:
        ESQUEMA_OBSERVACIONES.validate(datos, lazy=True)
        return datos, pd.DataFrame(columns=COLUMNAS_RECHAZO)
    except pa.errors.SchemaErrors as err:
        fallas = err.failure_cases
    if fallas["index"].isna().any():  # falla de toda la tabla (p. ej. falta una columna): no se inserta nada
        raise ValueError(f"La tabla del scraper no tiene la estructura esperada:\n{fallas.to_string()}")

    filas = []
    for (indice, regla), grupo in (fallas.assign(regla=[_regla_y_motivo(c, r)[0] for c, r in
                                                        zip(fallas["column"], fallas["check"])])
                                   .groupby(["index", "regla"])):
        motivos = sorted({_regla_y_motivo(c, r)[1] for c, r in zip(grupo["column"], grupo["check"])})
        fila = datos.loc[int(indice)]
        filas.append({"id_ejecucion": fila["id_ejecucion"], "id_comercio": fila["comercio"],
                      "sku_comercio": fila["sku_comercio"], "fecha_hora_consulta": fila["fecha_hora_consulta"],
                      "url": fila["url"], "precio": fila["precio"], "regla": regla, "motivo": "; ".join(motivos)})
    rechazadas = pd.DataFrame(filas, columns=COLUMNAS_RECHAZO)
    indices_malos = {int(i) for i in fallas["index"]}
    validas = datos[~datos.index.isin(indices_malos)]
    return validas, rechazadas


# R4. Revisa con pandera que todos los SKU comparables esperados de un comercio estén entre las filas
# válidas. Devuelve la lista de los que faltan (vacía si están todos). No rechaza filas: si falta alguno, la
# ejecución de ese comercio se registra como 'parcial' con el aviso (decisión del Paso 1).
def comparables_faltantes(validas: pd.DataFrame, esperados: set[str]) -> list[str]:
    presentes = set(validas["sku_comercio"])
    esquema = pa.DataFrameSchema(checks=pa.Check(lambda d: set(esperados) <= set(d["sku_comercio"]),
                                                 name="comparables_presentes"))
    try:
        esquema.validate(validas)
        return []
    except pa.errors.SchemaError:
        return sorted(set(esperados) - presentes)
