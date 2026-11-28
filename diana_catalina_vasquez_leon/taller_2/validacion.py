# -*- coding: utf-8 -*-
"""
validacion.py - Reglas de validación que debe superar cada observación ANTES de insertarse (Módulo 1.4).

Reglas por observación (si falla una, la observación NO se inserta y queda en `observaciones_rechazadas`):
  R1  precio_vigente numérico, finito y mayor que cero
  R2  comercio, sku_comercio, url y fecha_consulta presentes (no vacíos)
  R3  fecha_consulta en ISO 8601 con zona horaria (por ejemplo 2026-11-05T10:35:00-05:00)
  R4  sin duplicados dentro de la misma ejecución (mismo comercio y SKU)
Regla por lote (comercio + ejecución):
  R5  presencia de los productos comparables en el comercio; si falta alguno la ejecución queda 'parcial'

Se implementa en pandas/Python puro (sin dependencias extra) para que corra igual en local y en la nube.
"""
import math
from datetime import datetime

REGLAS = {
    "R1": "precio ausente, no numérico o no positivo",
    "R2": "campo obligatorio vacío",
    "R3": "fecha_consulta no está en ISO 8601 con zona horaria",
    "R4": "observación duplicada en la misma ejecución",
}


def _vacio(x):
    return x is None or (isinstance(x, str) and not x.strip())


def _precio_valido(x):
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return False
    return math.isfinite(x) and x > 0


def _fecha_iso_con_zona(s):
    if not isinstance(s, str):
        return False
    try:
        return datetime.fromisoformat(s).tzinfo is not None
    except ValueError:
        return False


def motivo_rechazo(r):
    """Devuelve el motivo (texto) por el que una observación no es válida, o None si lo es."""
    if not _precio_valido(r.get("precio_vigente")):
        return f"R1: {REGLAS['R1']}"
    for campo in ("comercio", "sku_comercio", "url", "fecha_consulta"):
        if _vacio(r.get(campo)):
            return f"R2: {REGLAS['R2']} ({campo})"
    if not _fecha_iso_con_zona(r["fecha_consulta"]):
        return f"R3: {REGLAS['R3']}"
    return None


def validar_registros(registros):
    """Separa una lista de observaciones (dicts) en (validas, rechazadas).
    `rechazadas` es una lista de tuplas (observación, motivo)."""
    validas, rechazadas, vistos = [], [], set()
    for r in registros:
        motivo = motivo_rechazo(r)
        if motivo is None:
            clave = (r["comercio"], r["sku_comercio"])
            if clave in vistos:
                motivo = f"R4: {REGLAS['R4']}"
            else:
                vistos.add(clave)
        if motivo:
            rechazadas.append((r, motivo))
        else:
            validas.append(r)
    return validas, rechazadas


def faltantes_comparables(registros, productos):
    """Ids de los productos comparables que NO aparecen (con precio) en los registros de un comercio.
    `productos` es {codigo_barras: id_producto_comun}. Si no hay productos definidos, no se exige nada."""
    if not productos:
        return []
    presentes = {r.get("codigo_barras") for r in registros
                 if r.get("en_alcance") == 1 and _precio_valido(r.get("precio_vigente"))}
    return sorted(pid for ean, pid in productos.items() if ean not in presentes)
