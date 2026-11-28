"""
Capa de caché entre la interfaz y db.py (Módulo 3).

Cada función abre una conexión de solo lectura, llama a la función de db.py y la
cierra. Los resultados se guardan con st.cache_data y se invalidan con
`limpiar_cache()` al terminar una actualización. Aquí no hay SQL.
"""

from __future__ import annotations

from typing import Any, Dict, Optional, Sequence, Tuple

import pandas as pd
import streamlit as st

import db

TTL = 3600  # segundos


def limpiar_cache() -> None:
    st.cache_data.clear()


def _leer(funcion, *args, **kwargs):
    with db.conectar(solo_lectura=True) as con:
        return funcion(con, *args, **kwargs)


@st.cache_data(ttl=TTL, show_spinner=False)
def corridas() -> pd.DataFrame:
    return _leer(db.listar_corridas)


@st.cache_data(ttl=TTL, show_spinner=False)
def ultima_corrida() -> Optional[Dict[str, Any]]:
    return _leer(db.ultima_corrida)


@st.cache_data(ttl=TTL, show_spinner=False)
def opciones_filtros() -> Dict[str, Any]:
    return _leer(db.opciones_filtros)


@st.cache_data(ttl=TTL, show_spinner=False)
def comparables() -> pd.DataFrame:
    return _leer(db.lista_comparables)


@st.cache_data(ttl=TTL, show_spinner=False)
def observaciones(f: db.Filtros) -> pd.DataFrame:
    return _leer(db.observaciones_filtradas, f)


@st.cache_data(ttl=TTL, show_spinner=False)
def indicadores(f: db.Filtros) -> Dict[str, Any]:
    return _leer(db.indicadores, f)


@st.cache_data(ttl=TTL, show_spinner=False)
def mediana_subcategoria(f: db.Filtros) -> pd.DataFrame:
    return _leer(db.mediana_por_subcategoria, f)


@st.cache_data(ttl=TTL, show_spinner=False)
def distribucion(f: db.Filtros) -> pd.DataFrame:
    return _leer(db.distribucion_precios, f)


@st.cache_data(ttl=TTL, show_spinner=False)
def ahorro_por_producto(id_corrida: int, comercios: Tuple[str, ...], incluir_agotados: bool = False) -> pd.DataFrame:
    return _leer(db.ahorro_por_producto, id_corrida, comercios, incluir_agotados)


@st.cache_data(ttl=TTL, show_spinner=False)
def sobrecosto(id_corrida: int, comercios: Tuple[str, ...], incluir_agotados: bool = False) -> pd.DataFrame:
    return _leer(db.sobrecosto_por_comercio, id_corrida, comercios, incluir_agotados)


@st.cache_data(ttl=TTL, show_spinner=False)
def cambios_ultima() -> Dict[str, Any]:
    return _leer(db.cambios_ultima_corrida)


@st.cache_data(ttl=TTL, show_spinner=False)
def evolucion(id_producto_comun: str, comercios: Tuple[str, ...]) -> pd.DataFrame:
    return _leer(db.evolucion_comparable, id_producto_comun, comercios)


@st.cache_data(ttl=TTL, show_spinner=False)
def precio_unitario(id_corrida: int, comercios: Tuple[str, ...]) -> pd.DataFrame:
    return _leer(db.precio_unitario_comparables, id_corrida, comercios)


@st.cache_data(ttl=TTL, show_spinner=False)
def comparar(id_a: int, id_b: int, comercios: Tuple[str, ...], umbral: float, solo_comparables: bool) -> Dict[str, pd.DataFrame]:
    return _leer(db.comparar_corridas, id_a, id_b, comercios, umbral, solo_comparables)


@st.cache_data(ttl=TTL, show_spinner=False)
def canasta(id_corrida: int, items: Tuple[Tuple[str, int], ...], incluir_agotados: bool) -> Dict[str, Any]:
    return _leer(db.calcular_canasta, id_corrida, items, incluir_agotados)


@st.cache_data(ttl=TTL, show_spinner=False)
def ejecuciones() -> pd.DataFrame:
    return _leer(db.resumen_ejecuciones)


@st.cache_data(ttl=TTL, show_spinner=False)
def ejecuciones_corrida(id_corrida: int) -> pd.DataFrame:
    return _leer(db.ultimas_ejecuciones_corrida, id_corrida)


@st.cache_data(ttl=TTL, show_spinner=False)
def correcciones() -> pd.DataFrame:
    return _leer(db.listar_correcciones)


@st.cache_data(ttl=TTL, show_spinner=False)
def rechazadas() -> pd.DataFrame:
    return _leer(db.listar_rechazadas)


@st.cache_data(ttl=TTL, show_spinner=False)
def disponibilidad(id_corrida: int) -> pd.DataFrame:
    return _leer(db.disponibilidad_por_comercio, id_corrida)
