"""ui_filtros.py - Panel lateral de filtros combinables (se dibuja en app.py y alimenta a todas las páginas)."""
from __future__ import annotations

from datetime import date

import streamlit as st

import analisis as A
import servicios as sv
import validacion as V
from db import Filtros

TODAS = "Última ejecución de cada comercio"


def _fecha(txt: str) -> date:
    return date.fromisoformat(txt)


def panel_lateral() -> Filtros:
    op = sv.consultar("opciones_filtros")
    ejecs = sv.consultar("ejecuciones")
    with st.sidebar:
        st.header("Filtros")
        comercios = st.multiselect("Comercio", op["comercios"], default=op["comercios"], key="f_comercios")
        subcats = st.multiselect("Subcategoría", op["subcategorias"], key="f_subcats", placeholder="Todas")
        marcas = st.multiselect("Marca", op["marcas"], key="f_marcas", placeholder="Todas")

        pmin, pmax = int(op["precio_min"]), int(op["precio_max"]) + 1
        rango = (pmin, pmax)
        if pmax > pmin:
            rango = st.slider("Rango de precio (COP)", pmin, pmax, (pmin, pmax), step=500, key="f_precio")

        opciones_ejec = {TODAS: None}
        for _, e in ejecs.iterrows():
            opciones_ejec[f"{A.etiqueta_ejecucion(e['ejecucion_id'])} · {e['estado']}"] = e["ejecucion_id"]
        eleccion = st.selectbox("Ejecución", list(opciones_ejec), key="f_ejec",
                                help="«Última ejecución de cada comercio» muestra el precio más reciente de cada producto.")

        desde = hasta = None
        if op["fecha_min"] and op["fecha_max"]:
            d0, d1 = _fecha(op["fecha_min"]), _fecha(op["fecha_max"])
            if d1 > d0:
                sel = st.date_input("Rango de fechas de consulta", value=(d0, d1), min_value=d0, max_value=d1, key="f_fechas")
                if isinstance(sel, (tuple, list)) and len(sel) == 2:
                    desde, hasta = sel[0].isoformat(), sel[1].isoformat()

        promos = st.toggle("Solo promociones", key="f_promos")
        comparables = st.toggle("Solo comparables", key="f_comparables",
                                help="Presentaciones idénticas que están en los tres comercios.")
        texto = st.text_input("Buscar en el nombre o la descripción", key="f_busqueda", max_chars=V.MAX_BUSQUEDA,
                              placeholder="p. ej. winny talla xg")
        try:
            busqueda = V.validar_busqueda(texto)
        except ValueError as e:
            st.error(str(e))
            busqueda = ""

    if not comercios:
        st.sidebar.warning("Selecciona al menos un comercio.")
        comercios_filtro = ("__ninguno__",)
    elif len(comercios) == len(op["comercios"]):
        comercios_filtro = ()
    else:
        comercios_filtro = tuple(comercios)
    full_precio = rango == (pmin, pmax)
    filtros = Filtros(
        comercios=comercios_filtro, subcategorias=tuple(subcats), marcas=tuple(marcas),
        precio_min=None if full_precio else float(rango[0]), precio_max=None if full_precio else float(rango[1]),
        ejecucion_id=opciones_ejec[eleccion], fecha_desde=desde, fecha_hasta=hasta,
        solo_promociones=bool(promos), solo_comparables=bool(comparables), busqueda=busqueda)
    st.session_state["filtros"] = filtros
    return filtros
