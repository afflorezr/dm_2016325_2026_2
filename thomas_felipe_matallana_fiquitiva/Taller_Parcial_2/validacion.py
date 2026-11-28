"""Validaciones puras: no red, SQL ni cambios en los datos de origen."""
import math
import re
from datetime import datetime
from urllib.parse import urlparse
from legado.scraper import parse_content, SOURCES


def precio_numerico(valor):
    if isinstance(valor, bool):
        raise ValueError("Precio booleano")
    if isinstance(valor, str):
        valor = re.sub(r"(?i)COP|\$|\s", "", valor)
        if "," in valor:
            valor = valor.replace(".", "").replace(",", ".")
        elif re.fullmatch(r"\d{1,3}(\.\d{3})+", valor):
            valor = valor.replace(".", "")
    try:
        numero = float(valor)
    except (ValueError, TypeError):
        raise ValueError("Precio ausente o no numérico") from None
    if not math.isfinite(numero) or numero <= 0:
        raise ValueError("Precio debe ser finito y positivo")
    return numero


def contenido_normalizado(texto):
    texto=re.sub(r'(?i)(?<=\d)\s*l\b',' litros',str(texto or ''))
    cantidad, unidad = parse_content(texto)
    if unidad == "mg" and cantidad is not None:
        return cantidad / 1000, "g"
    return cantidad, unidad


def validar_fila(fila):
    errores = []
    try:
        precio_numerico(fila.get("precio"))
    except ValueError as exc:
        errores.append(str(exc))
    if fila.get("comercio") not in SOURCES:
        errores.append("Comercio desconocido")
    for campo in ("sku", "nombre_original", "ejecucion", "archivo_raw"):
        if not str(fila.get(campo) or "").strip():
            errores.append(f"Falta {campo}")
    url = urlparse(str(fila.get("url") or ""))
    if url.scheme not in ("http", "https") or not url.netloc:
        errores.append("URL ausente o inválida")
    try:
        fecha = datetime.fromisoformat(fila.get("fecha_hora") or "")
        if fecha.tzinfo is None:
            errores.append("Fecha sin zona horaria")
    except ValueError:
        errores.append("Fecha ausente o inválida")
    cantidad = fila.get("contenido_total")
    if cantidad is not None and (not isinstance(cantidad, (int, float)) or cantidad <= 0):
        errores.append("Contenido inválido")
    return errores


def validar_busqueda(texto):
    texto = texto.strip()
    if len(texto) > 120 or any(ord(c) < 32 for c in texto):
        raise ValueError("La búsqueda admite hasta 120 caracteres, sin caracteres de control")
    return texto
