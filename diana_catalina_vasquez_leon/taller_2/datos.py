# -*- coding: utf-8 -*-
"""
datos.py - Envuelve las funciones de db.py con caché (st.cache_data).
No contiene SQL. La caché se invalida sola cuando cambia el archivo de la base (parámetro `v`) y
explícitamente con `limpiar()` al terminar una actualización.
"""
import os

import streamlit as st

import db

BASE = db.DB_DEFECTO


def version():
    """Marca de tiempo del archivo de la base: si cambia, la caché deja de valer."""
    return os.path.getmtime(BASE) if os.path.exists(BASE) else 0.0


def esquema_listo():
    """Sin caché: se consulta cada vez para detectar una base vacía o sin migrar."""
    try:
        with _con() as con:
            return db.esquema_listo(con)
    except Exception:
        return False


def limpiar():
    st.cache_data.clear()


def _con():
    return db.sesion(BASE)


@st.cache_data(show_spinner=False)
def opciones(v):
    with _con() as con:
        return db.opciones_filtros(con)


@st.cache_data(show_spinner=False)
def ejecuciones(v):
    with _con() as con:
        return db.ejecuciones_validas(con)


@st.cache_data(show_spinner=False)
def ejecuciones_comparables(v):
    with _con() as con:
        return db.ejecuciones_con_comparables(con)


@st.cache_data(show_spinner=False)
def productos(filtros, v):
    with _con() as con:
        return db.productos_filtrados(con, **filtros)


@st.cache_data(show_spinner=False)
def indicadores(filtros, v):
    with _con() as con:
        return db.indicadores(con, **filtros)


@st.cache_data(show_spinner=False)
def ahorro(ejecucion, v):
    with _con() as con:
        return db.ahorro_comparables(con, ejecucion)


@st.cache_data(show_spinner=False)
def precios_comparables(ejecucion, v):
    with _con() as con:
        return db.precios_comparables(con, ejecucion)


@st.cache_data(show_spinner=False)
def evolucion(id_producto, v):
    with _con() as con:
        return db.evolucion_precio(con, id_producto)


@st.cache_data(show_spinner=False)
def unidades(v):
    with _con() as con:
        return db.unidades_comparables(con)


@st.cache_data(show_spinner=False)
def unitario(unidad, ejecucion, v):
    with _con() as con:
        return db.precio_unitario_comparable(con, unidad, ejecucion)


@st.cache_data(show_spinner=False)
def familias(ejecucion, v):
    with _con() as con:
        return db.precio_unitario_familias(con, ejecucion)


@st.cache_data(show_spinner=False)
def cambios(antes, despues, umbral, v):
    with _con() as con:
        return db.cambios_entre_ejecuciones(con, antes, despues, umbral)


@st.cache_data(show_spinner=False)
def resumen(id_ejecucion, v):
    with _con() as con:
        return db.resumen_ejecucion(con, id_ejecucion)


def estado_ultima(v):
    return indicadores({}, v)["estado_ultima_ejecucion"]
