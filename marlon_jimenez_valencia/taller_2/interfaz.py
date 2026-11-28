"""
interfaz.py — Piezas de presentación que comparten las páginas (Taller 2, Módulo 5).

Aquí NO hay SQL: los datos se piden a db.py. Este archivo define:
  * el color fijo de cada comercio (el mismo en todos los gráficos);
  * el formato de pesos colombianos y de fechas;
  * los filtros de la barra lateral, que devuelven un db.Filtros;
  * mensajes claros cuando un filtro no devuelve datos o cuando algo falla;
  * el estilo común de los gráficos de plotly.
"""
from __future__ import annotations

import re
import traceback
from contextlib import contextmanager
from datetime import date

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

import db

# Colores fijos por comercio. Los tres primeros se revisaron para daltonismo y contraste
# sobre el fondo de la app (#fbf8f3): se distinguen entre sí y tienen contraste >= 3:1.
# Aun así, cada gráfico ofrece su tabla de datos.
COLORES = {
    "Cafam": "#8e2f6f",        # ciruela
    "La Rebaja": "#c08417",    # mostaza
    "Locatel": "#2f6fa0",      # azul petróleo
    "Colsubsidio": "#5e7d3a",  # oliva (comercio de respaldo, no se usa por defecto)
    "Empate": "#8c8378",       # gris cálido
}
ORDEN_COMERCIOS = ["Cafam", "La Rebaja", "Locatel", "Colsubsidio", "Empate"]
MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
UNIDADES = {"unidad": "COP por unidad (tableta o cápsula)", "mL": "COP por mL", "g": "COP por g"}


# ---------------------------------------------------------------------------
# Formatos
# ---------------------------------------------------------------------------
def cop(valor) -> str:
    """12900.0 -> '$ 12.900'. Un valor ausente se muestra como '—' (nunca como 0)."""
    if valor is None or pd.isna(valor):
        return "—"
    signo = "-" if float(valor) < 0 else ""
    return f"{signo}$ " + f"{abs(float(valor)):,.0f}".replace(",", ".")


def numero(valor, decimales: int = 0) -> str:
    if valor is None or pd.isna(valor):
        return "—"
    texto = f"{float(valor):,.{decimales}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


def fecha_legible(iso: str | None, con_hora: bool = True) -> str:
    """'2026-10-09T23:50:57-05:00' -> '9 oct 2026, 23:50' (hora de Colombia)."""
    if not iso or pd.isna(iso):
        return "—"
    t = pd.Timestamp(iso)
    texto = f"{t.day} {MESES[t.month - 1]} {t.year}"
    return f"{texto}, {t:%H:%M}" if con_hora else texto


def etiqueta_ejecucion(fila) -> str:
    """Texto de una ejecución en los selectores."""
    estado = "completa en los 3 comercios" if fila["completa"] else f"{fila['estados']}"
    return f"{fecha_legible(fila['inicio'])} · {fila['id_ejecucion']} · {estado}"


def color_comercio(nombre: str) -> str:
    return COLORES.get(nombre, "#52514e")


# ---------------------------------------------------------------------------
# Mensajes y manejo de errores
# ---------------------------------------------------------------------------
def sin_datos(mensaje: str = "No hay datos con los filtros elegidos. Prueba con menos filtros.") -> None:
    st.info(mensaje, icon=":material/filter_alt_off:")


@contextmanager
def protegido():
    """
    Muestra un mensaje claro en lugar del error técnico. Se usa en cada página:
        with interfaz.protegido():
            ...
    """
    try:
        yield
    except db.BaseNoDisponible as e:
        st.error(f"{e} Revisa que el archivo comparador_precios.sqlite esté en la carpeta "
                 "taller_2 (ver README.md).", icon=":material/database:")
    except db.EntradaInvalida as e:
        st.warning(str(e), icon=":material/warning:")
    except Exception:   # noqa: BLE001 - cualquier otro error se muestra sin tumbar la app
        st.error("Ocurrió un error inesperado al consultar los datos. Recarga la página; si "
                 "persiste, revisa el detalle técnico.", icon=":material/error:")
        with st.expander("Detalle técnico"):
            st.code(traceback.format_exc())


def fecha_de_los_datos() -> None:
    """Fecha de la última ejecución, visible en todas las páginas (§14)."""
    ultima = db.ultima_ejecucion()
    if ultima.empty:
        return
    partes = [f"{f.comercio} {fecha_legible(f.inicio)} ({f.estado})" for f in ultima.itertuples()]
    st.caption("Última ejecución de cada comercio (hora de Colombia): " + " · ".join(partes)
               + ". Los precios son los del momento de la captura.")


# ---------------------------------------------------------------------------
# Filtros de la barra lateral (§7.2)
# ---------------------------------------------------------------------------
CLAVES_FILTROS = ["f_comercios", "f_modo", "f_ejecucion", "f_fechas", "f_subcategorias",
                  "f_marcas", "f_precio_min", "f_precio_max", "f_promociones",
                  "f_comparables", "f_texto"]


def _limpiar_filtros() -> None:
    for clave in CLAVES_FILTROS:
        st.session_state.pop(clave, None)


def filtros_barra_lateral() -> db.Filtros | None:
    """Dibuja los filtros y devuelve un db.Filtros. None si no hay ningún comercio elegido."""
    tabla_comercios = db.comercios()
    nombres = dict(zip(tabla_comercios["id_comercio"], tabla_comercios["comercio"]))
    ejecuciones = db.ejecuciones()
    with st.sidebar:
        st.header("Filtros")
        elegidos = st.multiselect("Comercios", list(nombres), default=list(nombres),
                                  format_func=nombres.get, key="f_comercios")

        modo = st.radio("Periodo", ["Una ejecución", "Rango de fechas"], horizontal=True,
                        key="f_modo")
        id_ejecucion = fecha_desde = fecha_hasta = None
        if modo == "Una ejecución":
            filas = {f.id_ejecucion: f for f in ejecuciones.itertuples()}
            ids = list(filas)
            por_defecto = db.ejecucion_por_defecto()
            id_ejecucion = st.selectbox(
                "Ejecución", ids, index=ids.index(por_defecto) if por_defecto in ids else 0,
                format_func=lambda i: etiqueta_ejecucion(filas[i]._asdict()), key="f_ejecucion",
                help="Por defecto, la ejecución más reciente que quedó completa en los 3 comercios.")
        else:
            desde, hasta = db.rango_fechas()
            desde, hasta = date.fromisoformat(desde), date.fromisoformat(hasta)
            rango = st.date_input("Fechas de consulta", (desde, hasta), min_value=desde,
                                  max_value=hasta, format="YYYY-MM-DD", key="f_fechas",
                                  help="Se toma la última observación de cada anuncio en el rango.")
            if isinstance(rango, (tuple, list)) and len(rango) == 2:
                fecha_desde, fecha_hasta = rango[0].isoformat(), rango[1].isoformat()
            else:
                st.caption("Elige la fecha final del rango.")
                fecha_desde = fecha_hasta = (rango[0] if rango else desde).isoformat()

        subcategorias = st.multiselect("Subcategoría", db.subcategorias(), key="f_subcategorias",
                                       placeholder="Todas")
        marcas = st.multiselect("Marca", db.marcas(tuple(subcategorias), tuple(elegidos)),
                                key="f_marcas", placeholder="Todas")
        st.markdown("**Rango de precio (COP)**")
        c1, c2 = st.columns(2)
        precio_min = c1.number_input("Desde", min_value=0, value=None, step=1000,
                                     placeholder="sin mínimo", key="f_precio_min")
        precio_max = c2.number_input("Hasta", min_value=0, value=None, step=1000,
                                     placeholder="sin máximo", key="f_precio_max")
        promociones = st.toggle("Solo promociones", key="f_promociones")
        comparables = st.toggle("Solo comparables (P01 a P10)", key="f_comparables")
        texto = st.text_input("Buscar en el nombre o el texto del anuncio",
                              max_chars=db.LARGO_MAXIMO_TEXTO, key="f_texto",
                              placeholder="p. ej. amoxicilina 500")
        try:
            texto = db.validar_texto(texto)
        except db.EntradaInvalida as e:
            st.error(str(e))
            texto = ""
        st.button("Limpiar filtros", on_click=_limpiar_filtros, width="stretch")

    if not elegidos:
        return None
    if precio_min is not None and precio_max is not None and precio_min > precio_max:
        st.sidebar.warning("El precio 'Desde' es mayor que el precio 'Hasta'.")
    return db.Filtros(id_ejecucion=id_ejecucion, fecha_desde=fecha_desde, fecha_hasta=fecha_hasta,
                      comercios=tuple(elegidos), subcategorias=tuple(subcategorias),
                      marcas=tuple(marcas), precio_min=precio_min, precio_max=precio_max,
                      solo_promociones=promociones, solo_comparables=comparables, texto=texto)


def filtros_activos() -> db.Filtros | None:
    """Los filtros que dibujó app.py para esta página (None si no hay comercios elegidos)."""
    filtros = st.session_state.get("filtros")
    if filtros is None:
        st.warning("Elige al menos un comercio en la barra lateral.", icon=":material/storefront:")
        st.stop()
    return filtros


def describir_periodo(f: db.Filtros) -> str:
    """Texto del periodo al que corresponden los indicadores y gráficos."""
    if f.id_ejecucion:
        fila = db.ejecuciones().set_index("id_ejecucion").loc[f.id_ejecucion]
        return f"ejecución {f.id_ejecucion} ({fecha_legible(fila['inicio'], con_hora=False)})"
    return (f"última observación de cada anuncio entre el {f.fecha_desde} y el {f.fecha_hasta}")


# ---------------------------------------------------------------------------
# Gráficos
# ---------------------------------------------------------------------------
def estilo(fig: go.Figure, eje_y: str | None = None, eje_x: str | None = None,
           leyenda: bool = True, formato_y: str | None = ",.0f",
           formato_x: str | None = None) -> go.Figure:
    """
    Estilo común: separadores colombianos, ejes discretos, leyenda arriba.
    formato_y / formato_x: formato de los números o fechas del eje (d3), p. ej. ',.0f'
    para pesos (12.900) o '%d/%m/%Y' para fechas. None deja el formato de plotly.
    """
    fig.update_layout(
        separators=",.",                     # decimal con coma, miles con punto
        margin=dict(l=10, r=10, t=30, b=10),
        legend=dict(title_text="", orientation="h", yanchor="bottom", y=1.02, xanchor="left", x=0),
        showlegend=leyenda,
        hoverlabel=dict(namelength=-1),
        barcornerradius=4,
        bargap=0.25,
        bargroupgap=0.08,
    )
    if eje_y is not None:
        fig.update_yaxes(title_text=eje_y)
    if eje_x is not None:
        fig.update_xaxes(title_text=eje_x)
    fig.update_xaxes(showgrid=False)
    fig.update_yaxes(gridwidth=1)
    if formato_y:
        fig.update_yaxes(tickformat=formato_y)
    if formato_x:
        fig.update_xaxes(tickformat=formato_x)
    return fig


def mostrar_grafico(fig: go.Figure, datos: pd.DataFrame | None = None,
                    columnas: dict | None = None, columnas_cop: tuple = ()) -> None:
    """Dibuja el gráfico y, debajo, la tabla con sus datos (vista accesible)."""
    st.plotly_chart(fig, width="stretch", config={"displaylogo": False})
    if datos is not None:
        with st.expander("Ver los datos del gráfico"):
            tabla(datos, columnas, columnas_cop=columnas_cop)


# Columnas que se muestran como pesos o como porcentaje (por el comienzo de su nombre)
PATRON_PCT = re.compile(r"(pct|porcentaje|ahorro_pct|cambio_pct)")
PATRON_COP = re.compile(r"(precio|total|subtotal|cambio_cop|ahorro|minimo|maximo|mediana|"
                        r"sobrecosto|costo)")


def tabla(df: pd.DataFrame, columnas: dict | None = None, columnas_cop: tuple = (),
          columnas_pct: tuple = (), resaltar=None, **opciones) -> None:
    """
    st.dataframe con los números en formato colombiano: pesos como '$ 12.900' y
    porcentajes como '18,5 %'. El formato se aplica con un Styler de pandas, así que la
    tabla se sigue ordenando por el valor numérico. Un valor ausente se muestra como '—'.
    `resaltar`: función que recibe una fila y devuelve el estilo CSS de cada celda.
    """
    columnas = columnas or opciones.pop("column_config", None)
    numericas = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c])]
    formatos = {}
    for c in numericas:
        nombre = str(c)
        if c in columnas_pct or PATRON_PCT.match(nombre):
            formatos[c] = lambda v: "—" if pd.isna(v) else f"{numero(v, 2)} %"
        elif c in columnas_cop or PATRON_COP.match(nombre):
            formatos[c] = cop
        else:
            formatos[c] = lambda v: "—" if pd.isna(v) else numero(v, 0 if float(v).is_integer() else 2)
    estilo = df.style.format(formatos, na_rep="—")
    if resaltar is not None:
        estilo = estilo.apply(resaltar, axis=1)
    opciones.setdefault("hide_index", True)
    opciones.setdefault("width", "stretch")
    st.dataframe(estilo, column_config=columnas, **opciones)


def columna_cop(etiqueta: str, ayuda: str | None = None):
    """Encabezado de una columna en pesos. El formato '$ 12.900' lo pone tabla()."""
    return st.column_config.Column(etiqueta, help=ayuda)


def descargar_csv(df: pd.DataFrame, nombre: str, etiqueta: str = "Descargar CSV") -> None:
    st.download_button(etiqueta, df.to_csv(index=False).encode("utf-8-sig"), file_name=nombre,
                       mime="text/csv", icon=":material/download:")
