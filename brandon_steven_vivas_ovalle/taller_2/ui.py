"""ui.py - Piezas de interfaz compartidas por todas las páginas (mensajes claros, banner de datos, ejecución segura)."""
from __future__ import annotations

import logging

import streamlit as st

import analisis as A
import servicios as sv

log = logging.getLogger("app")
AVISO_PRECIOS = ("Precios en pesos colombianos (COP) del momento de captura; no incluyen envío ni descuentos por tarjeta o "
                 "por cantidad.")


def banner_datos() -> None:
    """Fecha y estado de la última ejecución (siempre visible)."""
    ult = sv.consultar("ultima_ejecucion")
    if not ult:
        st.warning("La base de datos todavía no tiene ejecuciones. Ve a «Actualizar datos».")
        return
    st.caption(f"📅 Datos de la última ejecución: **{A.etiqueta_ejecucion(ult['ejecucion_id'])}** "
               f"(estado: {ult['estado']}). {AVISO_PRECIOS}")


def sin_datos(detalle: str = "Prueba quitando algún filtro del panel lateral.") -> None:
    st.info(f"No hay productos que cumplan los filtros seleccionados. {detalle}")


def ejecutar_seguro(funcion) -> None:
    """Ejecuta el cuerpo de una página; ante un error inesperado muestra un mensaje claro (no la traza técnica)."""
    try:
        funcion()
    except FileNotFoundError:
        st.error("No se encontró la base de datos del comparador. Revisa que `comparador_precios.sqlite` esté junto a `app.py`.")
    except Exception:  # noqa: BLE001
        log.exception("Error en la página")
        st.error("Ocurrió un problema al consultar los datos. Intenta de nuevo o cambia los filtros; "
                 "el detalle técnico quedó en el registro del servidor.")


def tarjeta(titulo: str, valor: str, detalle: str, ayuda: str | None = None) -> None:
    """Indicador en tarjeta: valor + unidad/periodo en el detalle."""
    with st.container(border=True):
        st.metric(titulo, valor, help=ayuda)
        st.caption(detalle)
