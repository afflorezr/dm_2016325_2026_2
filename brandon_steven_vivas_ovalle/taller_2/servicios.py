"""
servicios.py - Caché de consultas para la interfaz (único módulo, junto con ui*.py y paginas/, que importa Streamlit).

Cada consulta de db.py se ejecuta con una conexión de solo lectura que se abre y se CIERRA en cada llamada y su
resultado se guarda con st.cache_data. La clave del caché incluye una huella de los datos (db.version_datos), de modo que
cualquier inserción la invalida; además, tras una actualización se llama a `invalidar_cache()`.
"""
from __future__ import annotations

import dataclasses
import logging
from pathlib import Path

import streamlit as st

import db
from db import Filtros

log = logging.getLogger("app")
RUTA_DB = db.RUTA_DB_DEFECTO
RUTA_RAW = Path(__file__).resolve().parent / "raw"


@st.cache_resource(show_spinner=False)
def asegurar_esquema(ruta: str) -> bool:
    """Una vez por proceso: garantiza tablas, índices y vistas (idempotente). Devuelve si la base quedó lista."""
    try:
        con = db.conectar_escritura(ruta)
        con.close()
    except Exception as e:  # noqa: BLE001  (p. ej. sistema de archivos de solo lectura)
        log.warning("No se pudo preparar el esquema: %s", e)
    return db.esquema_listo(ruta)


def base_disponible() -> bool:
    return Path(RUTA_DB).exists() and asegurar_esquema(str(RUTA_DB))


def version_actual() -> str:
    with db.abrir(RUTA_DB) as con:
        return db.version_datos(con)


def _empaquetar(x):
    if isinstance(x, Filtros):
        return {"__filtros__": {k: (list(v) if isinstance(v, tuple) else v) for k, v in dataclasses.asdict(x).items()}}
    return x


def _desempaquetar(x):
    if isinstance(x, dict) and "__filtros__" in x:
        return Filtros(**{k: (tuple(v) if isinstance(v, list) else v) for k, v in x["__filtros__"].items()})
    return x


@st.cache_data(show_spinner=False, max_entries=512)
def _ejecutar(nombre: str, version: str, args: tuple, kwargs: dict):
    """Ejecuta db.<nombre>(con, *args, **kwargs). `nombre` y `version` forman parte de la clave de caché."""
    funcion = getattr(db, nombre)
    with db.abrir(RUTA_DB) as con:
        return funcion(con, *[_desempaquetar(a) for a in args], **{k: _desempaquetar(v) for k, v in kwargs.items()})


def consultar(nombre: str, *args, **kwargs):
    """Consulta cacheada a la capa de datos: consultar('tabla_productos', filtros, 'precio')."""
    return _ejecutar(nombre, version_actual(), tuple(_empaquetar(a) for a in args),
                     {k: _empaquetar(v) for k, v in kwargs.items()})


def invalidar_cache() -> None:
    st.cache_data.clear()


def filtros_actuales() -> Filtros:
    return st.session_state.get("filtros", Filtros())
