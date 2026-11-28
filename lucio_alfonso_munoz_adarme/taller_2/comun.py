import streamlit as st

import db
import validacion
from scraper import COMERCIOS

COLORES = {"Éxito": "#E0A100", "Farmatodo": "#1F5AA6", "Locatel": "#1E9E4A"}   # los mismos del Taller 1
ETIQUETA = {"Exito": "Éxito", "Farmatodo": "Farmatodo", "Locatel": "Locatel"}


def numero(x, decimales=0):
    """Separador de miles con punto y decimales con coma: 259.600 o 271,01."""
    return f"{x:,.{decimales}f}".replace(",", "_").replace(".", ",").replace("_", ".")


def pesos(x, decimales=0):
    return "sin dato" if x is None or x != x else "$" + numero(x, decimales)


def fecha(iso):
    """2026-11-14T11:26:26-05:00 -> 14/11/2026 11:26"""
    return f"{iso[8:10]}/{iso[5:7]}/{iso[:4]} {iso[11:16]}" if iso else ""


def nombre_ejecucion(fila):
    return f"{fecha(fila.inicio)} ({fila.id_ejecucion})"


def elegir_ejecucion(etiqueta, clave, posicion=0, lugar=st):
    ej = db.ejecuciones()
    nombres = {r.id_ejecucion: nombre_ejecucion(r) for r in ej.itertuples()}
    return lugar.selectbox(etiqueta, list(nombres), index=posicion, format_func=nombres.get, key=clave)


def panel_filtros():
    """Filtros del panel lateral"""
    subcategorias, marcas, tope = db.opciones()
    s = st.sidebar
    s.header("Filtros")
    id_ej = elegir_ejecucion("Ejecución", "f_ejecucion", lugar=s)
    comercios = s.multiselect("Comercio", COMERCIOS, default=COMERCIOS, format_func=ETIQUETA.get)
    subs = s.multiselect("Subcategoría", subcategorias, placeholder="Todas")
    marcas_elegidas = s.multiselect("Marca", marcas, placeholder="Todas")
    precio = s.slider("Precio (COP)", 0, int(tope) + 1000, (0, int(tope) + 1000), step=1000)
    solo_promo = s.checkbox("Solo promociones")
    solo_comp = s.checkbox("Solo comparables")
    texto = s.text_input("Buscar en el nombre o el texto del anuncio", max_chars=60)
    try:
        texto = validacion.validar_texto(texto)
    except ValueError as e:
        s.error(str(e))
        texto = ""
    return {"id_ej": id_ej, "comercios": tuple(comercios), "subcategorias": tuple(subs),
            "marcas": tuple(marcas_elegidas), "precio_min": precio[0], "precio_max": precio[1],
            "solo_promocion": solo_promo, "solo_comparables": solo_comp, "texto": texto}


def aviso_fallidas(id_ej):
    """cuando no hay datos en la ejecución elegida."""
    estado = db.estado_ejecucion(id_ej)
    for r in estado[estado["estado"] == "fallida"].itertuples():
        st.warning(f"{ETIQUETA[r.comercio]} no tiene datos en esta ejecución: {r.motivo}.")
