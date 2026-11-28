"""
Componentes de interfaz compartidos: colores por comercio, formato de moneda y
fechas, estilo de gráficos y panel lateral de filtros. No contiene SQL.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

import datos_cache as dc
import db

# Cada comercio conserva el mismo color en toda la aplicación
COLORES_COMERCIO = {
    "Bella Piel": "#C0397A",
    "La Rebaja": "#2563EB",
    "Locatel": "#15803D",
}
ORDEN_COMERCIOS = list(COLORES_COMERCIO)

ETIQUETAS_ESTADO = {"completa": "Completa", "parcial": "Parcial", "fallida": "Fallida"}
ETIQUETAS_DISPONIBILIDAD = {
    "disponible": "Disponible", "agotado": "Agotado según el sitio",
    "no_observado": "No observado en la ejecución", "sin_informacion": "Sin información del sitio",
}
ETIQUETAS_MODO = {"en_linea": "En línea", "sin_conexion": "Sin conexión (raw/)"}


def cop(valor: Any, decimales: int = 0) -> str:
    """Formato de pesos colombianos: $ 123.456 (punto de miles, coma decimal)."""
    if valor is None or (isinstance(valor, float) and pd.isna(valor)):
        return "—"
    texto = f"{float(valor):,.{decimales}f}"
    return "$ " + texto.replace(",", "X").replace(".", ",").replace("X", ".")


def numero(valor: Any, decimales: int = 0) -> str:
    if valor is None or (isinstance(valor, float) and pd.isna(valor)):
        return "—"
    texto = f"{float(valor):,.{decimales}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


def fecha(iso: Optional[str], con_hora: bool = True) -> str:
    """'2026-10-10T02:53:14-05:00' -> '10/10/2026 02:53' (hora de Colombia)."""
    if not iso:
        return "—"
    try:
        d = datetime.fromisoformat(str(iso))
    except ValueError:
        return str(iso)
    return d.strftime("%d/%m/%Y %H:%M") if con_hora else d.strftime("%d/%m/%Y")


def etiqueta_corrida(fila: pd.Series | dict) -> str:
    return (f"Ejecución {int(fila['id_corrida'])} · {fecha(fila['fecha_datos'])} · "
            f"{ETIQUETAS_ESTADO.get(fila['estado'], fila['estado'])}")


def estilo_figura(fig: go.Figure, titulo: str, subtitulo: str = "", alto: int = 420) -> go.Figure:
    fig.update_layout(
        title={"text": f"{titulo}<br><sup>{subtitulo}</sup>" if subtitulo else titulo, "x": 0, "xanchor": "left"},
        separators=",.",               # coma decimal, punto de miles
        height=alto,
        margin={"l": 10, "r": 10, "t": 70 if subtitulo else 50, "b": 10},
        legend={"title": {"text": "Comercio"}, "orientation": "h", "y": -0.18},
        font={"family": "Source Sans Pro, sans-serif"},
        hoverlabel={"namelength": -1},
    )
    return fig


def formato_tabla(df: pd.DataFrame, cop_cols=(), cop1_cols=(), pct_cols=(), num_cols=()):
    """Styler con formato colombiano ($ 123.456); la tabla sigue ordenando por el valor numérico."""
    formatos = {}
    formatos.update({c: (lambda v: cop(v)) for c in cop_cols if c in df.columns})
    formatos.update({c: (lambda v: cop(v, 1)) for c in cop1_cols if c in df.columns})
    formatos.update({c: (lambda v: "—" if pd.isna(v) else f"{numero(v, 1)} %") for c in pct_cols if c in df.columns})
    formatos.update({c: (lambda v: numero(v)) for c in num_cols if c in df.columns})
    return df.style.format(formatos, na_rep="—")


def tarjeta(titulo: str, valor: str, detalle: str = "") -> None:
    with st.container(border=True):
        st.metric(titulo, valor)
        if detalle:
            st.caption(detalle)


def sin_datos(mensaje: str = "No hay datos para los filtros seleccionados. Amplíe el rango de precio, "
                             "quite filtros o elija otra ejecución.") -> None:
    st.info(mensaje, icon=":material/filter_alt_off:")


def nota_fecha_datos() -> None:
    u = dc.ultima_corrida()
    if u:
        st.caption(f"Precios en pesos colombianos (COP), tal como se publicaron en el momento de la captura. "
                   f"Última ejecución con datos: **{etiqueta_corrida(u)}**.")


# =====================================================================
# PANEL LATERAL DE FILTROS
# =====================================================================
def panel_filtros() -> db.Filtros:
    """Dibuja los filtros combinables en el panel lateral y devuelve un objeto db.Filtros."""
    opciones = dc.opciones_filtros()
    corr = dc.corridas()
    sb = st.sidebar
    sb.header("Filtros")

    comercios = sb.multiselect("Comercio", opciones["comercios"], default=opciones["comercios"],
                               help="Selección múltiple. Cada comercio conserva su color en toda la aplicación.")
    subcats = sb.multiselect("Subcategoría", opciones["subcategorias"], placeholder="Todas")
    marcas = sb.multiselect("Marca", opciones["marcas"], placeholder="Todas")

    tope = int(-(-max(opciones["precio_max"], 10000) // 10000) * 10000)
    rango = sb.slider("Rango de precio (COP)", 0, tope, (0, tope), step=5000, format="$ %,d")

    periodo = sb.radio("Periodo", ["Una ejecución", "Rango de fechas"], horizontal=True)
    id_corrida = fecha_desde = fecha_hasta = None
    if periodo == "Una ejecución" and not corr.empty:
        etiquetas = {etiqueta_corrida(f): int(f["id_corrida"]) for _, f in corr.iterrows()}
        elegida = sb.selectbox("Ejecución", list(etiquetas), index=0)
        id_corrida = etiquetas[elegida]
    elif periodo == "Rango de fechas":
        fmin = datetime.fromisoformat(opciones["fecha_min"]).date()
        fmax = datetime.fromisoformat(opciones["fecha_max"]).date()
        rango_f = sb.date_input("Fechas de consulta", (fmin, fmax), min_value=fmin, max_value=fmax, format="DD/MM/YYYY")
        if isinstance(rango_f, tuple) and len(rango_f) == 2:
            fecha_desde, fecha_hasta = rango_f[0].isoformat(), rango_f[1].isoformat()

    solo_promo = sb.toggle("Solo promociones")
    solo_comp = sb.toggle("Solo productos comparables")
    texto = sb.text_input("Buscar en el nombre o el texto del anuncio", max_chars=db.MAX_LARGO_BUSQUEDA,
                          placeholder="Ej.: umbrella acqua")
    try:
        texto = db.validar_texto_busqueda(texto)
    except ValueError as e:
        sb.error(str(e))
        texto = ""

    return db.Filtros(
        comercios=tuple(comercios), subcategorias=tuple(subcats), marcas=tuple(marcas),
        precio_min=float(rango[0]) if rango[0] > 0 else None,
        precio_max=float(rango[1]) if rango[1] < tope else None,
        id_corrida=id_corrida, fecha_desde=fecha_desde, fecha_hasta=fecha_hasta,
        solo_promociones=solo_promo, solo_comparables=solo_comp, texto=texto,
    )


def descripcion_periodo(f: db.Filtros) -> str:
    if f.id_corrida is not None:
        corr = dc.corridas()
        fila = corr[corr["id_corrida"] == f.id_corrida]
        return etiqueta_corrida(fila.iloc[0]) if not fila.empty else f"Ejecución {f.id_corrida}"
    if f.fecha_desde or f.fecha_hasta:
        return f"Consultas del {fecha(f.fecha_desde, False)} al {fecha(f.fecha_hasta, False)}"
    return "Todas las ejecuciones"


def corrida_de_analisis(f: db.Filtros) -> Optional[int]:
    """Ejecución usada en los análisis de una sola ejecución: la del filtro o la más reciente."""
    if f.id_corrida is not None:
        return f.id_corrida
    u = dc.ultima_corrida()
    return int(u["id_corrida"]) if u else None
