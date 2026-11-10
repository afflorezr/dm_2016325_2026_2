"""
analisis.py - Cálculos para el consumidor y formatos de presentación (funciones puras, sin SQL ni Streamlit).

Los datos de entrada salen de db.py (SQL); aquí solo se interpretan: ahorro con empates, resumen de canasta,
clasificación de variaciones de precio y formato colombiano de números y moneda.
"""
from __future__ import annotations

import math

import pandas as pd

ADVERTENCIA_CANASTA = ("El resultado no incluye costos de envío, mínimos de compra ni las condiciones de las promociones "
                       "(por ejemplo, descuentos que exigen tarjeta o cantidad mínima). Los precios son los de la fecha de captura.")


# ------------------------------------------------------------------ formatos
def n_(x, dec: int = 0) -> str:
    """Número con formato colombiano: 1.234,5"""
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    return f"{x:,.{dec}f}".replace(",", "§").replace(".", ",").replace("§", ".")


def cop(x, dec: int = 0) -> str:
    return "—" if x is None or (isinstance(x, float) and math.isnan(x)) else "$" + n_(x, dec) + " COP"


def pct(x, dec: int = 1) -> str:
    return "—" if x is None or (isinstance(x, float) and math.isnan(x)) else n_(x, dec) + " %"


def etiqueta_ejecucion(ejecucion_id: str | None) -> str:
    """'run_20261011T193258' -> '2026-10-11 19:32' (si no tiene el formato esperado, devuelve el identificador)."""
    import re
    m = re.fullmatch(r"run_(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})\d{2}", str(ejecucion_id or ""))
    return f"{m[1]}-{m[2]}-{m[3]} {m[4]}:{m[5]}" if m else str(ejecucion_id or "—")


# ------------------------------------------------------------------ ahorro
def ahorro_entre_comercios(precios: dict) -> dict:
    """
    Ahorro posible para un producto según los precios por comercio ({comercio: precio o None}).
    Los comercios sin precio se ignoran. Con EMPATES en el precio mínimo (o máximo) se devuelven todos los comercios
    empatados; si todos cuestan lo mismo el ahorro es 0 y todos son los 'más baratos'.
    El ahorro (%) es relativo al precio más alto: cuánto se deja de pagar frente al comercio más caro.
    """
    validos = {k: float(v) for k, v in precios.items()
               if v is not None and not (isinstance(v, float) and math.isnan(v)) and float(v) > 0}
    if not validos:
        return {"n_comercios": 0, "minimo": None, "maximo": None, "ahorro_cop": None, "ahorro_pct": None,
                "mas_baratos": [], "mas_caros": []}
    minimo, maximo = min(validos.values()), max(validos.values())
    ahorro = maximo - minimo
    return {"n_comercios": len(validos), "minimo": minimo, "maximo": maximo,
            "ahorro_cop": ahorro if len(validos) >= 2 else None,
            "ahorro_pct": (100.0 * ahorro / maximo) if len(validos) >= 2 and maximo > 0 else None,
            "mas_baratos": sorted(k for k, v in validos.items() if math.isclose(v, minimo)),
            "mas_caros": sorted(k for k, v in validos.items() if math.isclose(v, maximo))}


# ------------------------------------------------------------------ canasta
def resumen_canasta(totales: pd.DataFrame, minimo: pd.DataFrame, n_seleccionados: int) -> dict:
    """
    Interpreta la canasta calculada en SQL (db.canasta_totales y db.canasta_minimo).
      * Un comercio solo tiene total si posee TODOS los productos elegidos; si falta alguno no hay total.
      * `mejor_unico`: el comercio (o comercios empatados) de menor costo entre los que tienen la canasta completa.
      * `costo_minimo`: comprar cada producto donde es más barato; solo se calcula si todos los productos tienen precio
        en algún comercio.
      * `ahorro_vs_mejor_unico`: mejor_unico - costo_minimo (nunca negativo; 0 si comprar todo en un solo sitio ya es lo mínimo).
    """
    completas = totales[totales["total"].notna()] if len(totales) else totales
    incompletas = totales[totales["total"].isna()] if len(totales) else totales
    out = {"comercios_completos": completas["comercio"].tolist() if len(completas) else [],
           "comercios_incompletos": incompletas[["comercio", "n_faltantes"]].to_dict("records") if len(incompletas) else [],
           "mejor_unico": [], "costo_mejor_unico": None, "costo_minimo": None, "ahorro_vs_mejor_unico": None,
           "ahorro_pct_vs_mejor_unico": None, "ahorro_vs_cada_comercio": {}, "productos_sin_precio": 0}
    if len(completas):
        mejor = float(completas["total"].min())
        out["costo_mejor_unico"] = mejor
        out["mejor_unico"] = sorted(completas.loc[completas["total"].map(lambda v: math.isclose(v, mejor)), "comercio"])
    if n_seleccionados and len(minimo) == n_seleccionados and minimo["subtotal"].notna().all():
        out["costo_minimo"] = float(minimo["subtotal"].sum())
        for _, fila in completas.iterrows():
            out["ahorro_vs_cada_comercio"][fila["comercio"]] = max(0.0, float(fila["total"]) - out["costo_minimo"])
        if out["costo_mejor_unico"] is not None:
            out["ahorro_vs_mejor_unico"] = max(0.0, out["costo_mejor_unico"] - out["costo_minimo"])
            out["ahorro_pct_vs_mejor_unico"] = (100.0 * out["ahorro_vs_mejor_unico"] / out["costo_mejor_unico"]
                                                if out["costo_mejor_unico"] else None)
    else:
        out["productos_sin_precio"] = max(0, n_seleccionados - len(minimo))
    return out


# ------------------------------------------------------------------ variaciones
def clasificar_variacion(anterior, nuevo, umbral_pct: float = 5.0, tolerancia: float = 0.5) -> dict:
    """Clasifica el cambio de precio de un mismo anuncio. Devuelve tipo, variación en COP y en %, y si supera el umbral."""
    def _ok(v):
        return v is not None and not (isinstance(v, float) and math.isnan(v))
    if not _ok(anterior) and _ok(nuevo):
        return {"tipo": "nuevo", "variacion_cop": None, "variacion_pct": None, "grande": False}
    if _ok(anterior) and not _ok(nuevo):
        return {"tipo": "dejó de observarse", "variacion_cop": None, "variacion_pct": None, "grande": False}
    if not _ok(anterior) and not _ok(nuevo):
        return {"tipo": "sin precio en alguna ejecución", "variacion_cop": None, "variacion_pct": None, "grande": False}
    delta = float(nuevo) - float(anterior)
    variacion = 100.0 * delta / float(anterior)
    tipo = "subió" if delta > tolerancia else "bajó" if delta < -tolerancia else "sin cambio"
    return {"tipo": tipo, "variacion_cop": delta, "variacion_pct": variacion, "grande": abs(variacion) >= umbral_pct}


def resumen_tipos(df: pd.DataFrame) -> dict:
    """Conteo de productos por tipo de cambio (a partir de db.cambios_entre_ejecuciones)."""
    base = {"subió": 0, "bajó": 0, "sin cambio": 0, "nuevo": 0, "dejó de observarse": 0,
            "sin precio en alguna ejecución": 0}
    if len(df):
        base.update(df["tipo"].value_counts().to_dict())
    return base
