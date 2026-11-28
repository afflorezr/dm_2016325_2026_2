"""
validacion.py - Reglas explícitas de calidad de datos (antes de insertar) y validación de entradas del usuario.

1. Validación de observaciones (Módulo 1, sección 3.4)
   Cada regla es una función con nombre que devuelve una máscara de FALLOS. `validar_observaciones` aplica todas,
   separa las observaciones válidas de las rechazadas y deja en cada rechazada el motivo (o los motivos).
   Las reglas obligatorias del enunciado son:
     - precio_numerico_positivo      precio numérico y > 0 (NULL solo se admite si el sitio lo marca como agotado)
     - comercio_presente / url_presente / fecha_hora_valida
     - sin_duplicados_en_ejecucion   misma (ejecución, comercio, SKU) no puede repetirse
   y la regla de presencia de los productos comparables, que se evalúa por comercio con la base
   (db.productos_comparables_faltantes) porque necesita el catálogo de comparables.

   Se implementan con pandas puro (sin dependencias extra) para que sean transparentes y se puedan probar
   con datos pequeños; son equivalentes a un esquema de pandera (ver README, sección Validación).

2. Validación de entradas (Módulo 4): longitud máxima y caracteres permitidos antes de usar un valor en una
   consulta. Aun así, las consultas SIEMPRE van parametrizadas (db.py): esta capa es defensa adicional.
"""
from __future__ import annotations

import re

import pandas as pd

MAX_BUSQUEDA = 60
_BUSQUEDA_OK = re.compile(r"^[\w\s.,+&'/\-]*$", re.UNICODE)
_EJECUCION_OK = re.compile(r"^[A-Za-z0-9_\-]{1,40}$")


# --------------------------------------------------------------------------------------
# Reglas sobre observaciones (cada una devuelve True donde la fila FALLA)
# --------------------------------------------------------------------------------------
def _texto_vacio(s: pd.Series) -> pd.Series:
    return s.isna() | (s.astype("string").str.strip().fillna("") == "")


def regla_precio_numerico_positivo(df: pd.DataFrame) -> pd.Series:
    bruto = df["precio"]
    num = pd.to_numeric(bruto, errors="coerce")
    no_numerico = bruto.notna() & num.isna()
    no_positivo = num.notna() & (num <= 0)
    disponible = pd.to_numeric(df["disponible"], errors="coerce").fillna(0) == 1
    disponible_sin_precio = disponible & num.isna()        # un producto disponible debe tener precio
    return no_numerico | no_positivo | disponible_sin_precio


def regla_comercio_presente(df: pd.DataFrame) -> pd.Series:
    return _texto_vacio(df["comercio"])


def regla_url_presente(df: pd.DataFrame) -> pd.Series:
    return _texto_vacio(df["url"])


def regla_sku_presente(df: pd.DataFrame) -> pd.Series:
    return _texto_vacio(df["sku"])


def regla_nombre_presente(df: pd.DataFrame) -> pd.Series:
    return _texto_vacio(df["nombre_original"])


def regla_fecha_hora_valida(df: pd.DataFrame) -> pd.Series:
    vacia = _texto_vacio(df["fecha_hora_consulta"])
    parseada = pd.to_datetime(df["fecha_hora_consulta"], errors="coerce", format="ISO8601", utc=True)
    return vacia | parseada.isna()


def regla_sin_duplicados_en_ejecucion(df: pd.DataFrame) -> pd.Series:
    """La primera aparición es válida; las repetidas de (ejecución, comercio, SKU) se rechazan."""
    return df.duplicated(subset=["ejecucion_id", "comercio", "sku"], keep="first")


def regla_precio_lista_valido(df: pd.DataFrame) -> pd.Series:
    lista = pd.to_numeric(df["precio_lista"], errors="coerce")
    bruto = df["precio_lista"]
    return (bruto.notna() & lista.isna()) | (lista.notna() & (lista <= 0))


REGLAS = {
    "precio_numerico_positivo": regla_precio_numerico_positivo,
    "comercio_presente": regla_comercio_presente,
    "url_presente": regla_url_presente,
    "sku_presente": regla_sku_presente,
    "nombre_presente": regla_nombre_presente,
    "fecha_hora_valida": regla_fecha_hora_valida,
    "sin_duplicados_en_ejecucion": regla_sin_duplicados_en_ejecucion,
    "precio_lista_valido": regla_precio_lista_valido,
}
COLUMNAS_REQUERIDAS = ["ejecucion_id", "comercio", "sku", "url", "nombre_original", "precio", "precio_lista",
                       "disponible", "fecha_hora_consulta"]


def validar_observaciones(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Devuelve (validas, rechazadas). `rechazadas` incluye la columna `motivo` (reglas incumplidas, separadas por ';')."""
    faltan = [c for c in COLUMNAS_REQUERIDAS if c not in df.columns]
    if faltan:
        raise ValueError(f"Faltan columnas para validar: {faltan}")
    if df.empty:
        return df.copy(), df.assign(motivo=pd.Series(dtype="string"))
    df = df.reset_index(drop=True)
    fallos = {nombre: regla(df).fillna(False).astype(bool) for nombre, regla in REGLAS.items()}
    tabla = pd.DataFrame(fallos)
    hay_fallo = tabla.any(axis=1)
    motivo = tabla.apply(lambda fila: ";".join(fila.index[fila.to_numpy()]), axis=1)
    validas = df[~hay_fallo].copy()
    rechazadas = df[hay_fallo].copy()
    rechazadas["motivo"] = motivo[hay_fallo].to_numpy()
    return validas, rechazadas


# --------------------------------------------------------------------------------------
# Entradas del usuario
# --------------------------------------------------------------------------------------
def validar_busqueda(texto) -> str:
    """Texto de búsqueda: máx. 60 caracteres; letras, números, espacios y . , + & ' / - . Devuelve el texto limpio."""
    t = re.sub(r"\s+", " ", str(texto or "")).strip()
    if len(t) > MAX_BUSQUEDA:
        raise ValueError(f"La búsqueda admite como máximo {MAX_BUSQUEDA} caracteres.")
    if not _BUSQUEDA_OK.match(t):
        raise ValueError("La búsqueda solo admite letras, números, espacios y los signos . , + & ' / -")
    return t


def validar_umbral(valor, minimo: float = 0.0, maximo: float = 100.0) -> float:
    try:
        v = float(valor)
    except (TypeError, ValueError) as e:
        raise ValueError("El umbral debe ser un número.") from e
    if v != v or not (minimo <= v <= maximo):          # v != v detecta NaN
        raise ValueError(f"El umbral debe estar entre {minimo:g} y {maximo:g}.")
    return v


def validar_cantidad(valor, maximo: int = 99) -> int:
    try:
        v = int(valor)
    except (TypeError, ValueError) as e:
        raise ValueError("La cantidad debe ser un número entero.") from e
    if not 1 <= v <= maximo:
        raise ValueError(f"La cantidad debe estar entre 1 y {maximo}.")
    return v


def validar_ejecucion_id(valor) -> str:
    v = str(valor or "")
    if not _EJECUCION_OK.match(v):
        raise ValueError("Identificador de ejecución no válido.")
    return v
