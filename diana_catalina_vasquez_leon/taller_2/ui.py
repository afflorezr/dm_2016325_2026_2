# -*- coding: utf-8 -*-
"""ui.py - Piezas visuales compartidas: colores por comercio, formatos, estilo, tarjetas y mensajes."""
import os

import pandas as pd
import streamlit as st

import datos

COLORES = {"Dermatodo": "#4F46E5", "Farmatodo": "#F97316", "La Rebaja": "#10B981"}   # el mismo color en toda la app
ORDEN = ["Dermatodo", "Farmatodo", "La Rebaja"]
MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

CSS = """
<style>
.kpi-valor { font-size: 1.9rem; font-weight: 700; line-height: 1.15; color: #111827; }
.kpi-nota  { font-size: .8rem; color: #6b7280; }
div[data-testid="stVerticalBlockBorderWrapper"] { border-radius: 14px; }
h1, h2, h3 { letter-spacing: -0.3px; }
.aviso { background:#EEF2FF; border-left:5px solid #4F46E5; border-radius:8px; padding:10px 14px; margin:8px 0 18px; }
</style>
"""


def cop(v):
    return "—" if v is None or pd.isna(v) else "$" + f"{v:,.0f}".replace(",", ".")


def num(v, dec=1):
    return "—" if v is None or pd.isna(v) else f"{v:,.{dec}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def fecha_legible(iso):
    """'2026-11-06T10:35:00-05:00' -> '6 nov 2026, 10:35'."""
    if iso is None or pd.isna(iso):
        return "—"
    t = pd.to_datetime(str(iso)[:19])
    return f"{t.day} {MESES[t.month - 1]} {t.year}, {t:%H:%M}"


def aplicar_estilo():
    st.markdown(CSS, unsafe_allow_html=True)


def tarjeta(col, titulo, valor, nota=""):
    with col:
        with st.container(border=True):
            st.caption(titulo)
            st.markdown(f'<div class="kpi-valor">{valor}</div><div class="kpi-nota">{nota}</div>', unsafe_allow_html=True)


def aviso(texto):
    st.markdown(f'<div class="aviso">{texto}</div>', unsafe_allow_html=True)


def sin_datos(texto="No hay datos con esos filtros. Prueba ampliar el rango de precio o quitar algún filtro."):
    st.info(texto)


def mostrar_tabla(df, **kw):
    try:
        st.dataframe(df, use_container_width=True, **kw)
    except Exception:                       # versiones nuevas de Streamlit que reemplazaron el parámetro
        st.dataframe(df, width="stretch", **kw)


def mostrar_grafico(fig):
    try:
        st.plotly_chart(fig, use_container_width=True)
    except Exception:
        st.plotly_chart(fig, width="stretch")


def formato_figura(fig, titulo, subtitulo=None, alto=460):
    t = f"<b>{titulo}</b>" + (f"<br><sup>{subtitulo}</sup>" if subtitulo else "")
    fig.update_layout(title=t, height=alto, template="plotly_white", legend_title_text="Comercio",
                      font=dict(family="sans-serif", size=13), margin=dict(l=20, r=20, t=70, b=40))
    return fig


def fecha_de_los_datos():
    """Fecha de la última ejecución válida (se muestra en todas las páginas)."""
    est = datos.estado_ultima(datos.version())
    return fecha_legible(est.fecha_inicio.min()) if len(est) else "—"


def verificar_base():
    """Detiene la app con un mensaje claro si falta la base o si no tiene el esquema del Taller 2."""
    if not os.path.exists(datos.BASE):
        st.error("No se encontró la base de datos `comparador_precios.sqlite` junto a `app.py`. "
                 "Cópiala a esta carpeta y revisa el README.")
        st.stop()
    if not datos.esquema_listo():
        st.error("La base existe pero no tiene las vistas del Taller 2 (está vacía o sin migrar). "
                 "Cierra la app y ejecuta `python migrar_taller2.py`; luego vuelve a lanzarla.")
        st.stop()
