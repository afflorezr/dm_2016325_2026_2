"""
componentes.py — Taller 2 Minería de Datos (UNAL): piezas comunes de la interfaz de Streamlit.

* Caché de las consultas (Módulo 3): las páginas NO llaman a db.py directamente; piden los datos con
  `obtener("nombre_de_funcion", argumentos...)`, que usa `consultar()` con st.cache_data. Al terminar una
  actualización se llama a `limpiar_cache()` para que todo se recalcule sin reiniciar la aplicación.
* Presentación (Módulo 5): colores fijos por comercio, formato de pesos y fechas, filtros del panel lateral,
  tarjetas de indicadores y mensajes claros cuando no hay datos o hay un error.
Este archivo no contiene SQL.
"""
from __future__ import annotations

import datetime as dt

import streamlit as st

import db

# --------------------------------------------------------------------------------------------------------------
# Caché de consultas (Módulo 3)
# --------------------------------------------------------------------------------------------------------------
# Funciones de db.py que la interfaz puede pedir (lista cerrada: la interfaz no ejecuta otra cosa).
CONSULTAS_PERMITIDAS = {
    "listar_comercios", "listar_subcategorias", "listar_marcas", "rango_precios", "listar_ejecuciones",
    "listar_comparables", "productos_filtrados", "resumen_por_comercio", "indicadores_generales", "ultima_ejecucion",
    "mediana_por_subcategoria", "ahorro_por_comparable", "cambios_ultima_ejecucion", "resumen_disponibilidad",
    "evolucion_precio", "precio_unitario_comparables", "veces_mas_barato", "comparar_ejecuciones",
    "calcular_canasta",
}


# Consulta con caché. La clave de la caché son el nombre de la función y sus argumentos (filtros), así
# que la misma combinación de filtros no vuelve a consultar la base hasta que se limpie la caché.
@st.cache_data(show_spinner="Consultando la base de datos…")
def consultar(nombre_funcion: str, *args, **kwargs):
    if nombre_funcion not in CONSULTAS_PERMITIDAS:
        raise ValueError(f"Consulta no permitida: {nombre_funcion}")
    return getattr(db, nombre_funcion)(*args, **kwargs)


#Invalida la caché; se llama al terminar una actualización de precios (Módulo 2).
def limpiar_cache() -> None:
    consultar.clear()


# Igual que consultar(), pero si algo falla muestra un mensaje claro en español (no un error técnico) y
# devuelve None, para que la página decida qué mostrar en su lugar.
def obtener(nombre_funcion: str, *args, **kwargs):
    try:
        return consultar(nombre_funcion, *args, **kwargs)
    except ValueError as error:          # entrada no válida (validada en db.py)
        st.warning(f"Revise los filtros: {error}")
    except Exception as error:           # base ausente, dañada, etc.
        st.error("No fue posible consultar la base de datos. Intente de nuevo o recargue la página.")
        st.caption(f"Detalle para soporte: {type(error).__name__}")
    return None


# --------------------------------------------------------------------------------------------------------------
# Colores, formatos y mensajes (Módulo 5)
# --------------------------------------------------------------------------------------------------------------
# Cada comercio conserva el mismo color en toda la aplicación (§7.1). Contraste legible sobre blanco.
COLORES = {"La Rebaja": "#C1121F", "Locatel": "#2B8A3E", "Droguerías Cafam": "#1C4E9C"}
ORDEN_COMERCIOS = list(COLORES)

# Nombres en español para mostrar los valores internos.
NOMBRES_SUBCATEGORIA = {
    "shampoo": "Shampoo", "acondicionador": "Acondicionador", "mascarilla_tratamiento": "Mascarilla / tratamiento",
    "peinado": "Peinado", "coloracion": "Coloración", "otro_capilar": "Otro capilar",
}
NOMBRES_DISPONIBILIDAD = {"disponible": "Disponible", "agotado": "Agotado", "no_observado": "No observado"}


# "$ 12.900" (pesos colombianos sin decimales, punto de miles). Vacío → "—".
def formato_cop(valor) -> str:
    if valor is None or valor != valor:  # None o NaN
        return "—"
    return "$ " + f"{float(valor):,.0f}".replace(",", ".")


# "08/11/2026 16:38" a partir de un id de ejecución (20261108T163807) o una fecha ISO.
def formato_fecha(texto) -> str:
    texto = str(texto or "")
    if len(texto) >= 15 and texto[8] == "T" and texto[:8].isdigit():
        return f"{texto[6:8]}/{texto[4:6]}/{texto[:4]} {texto[9:11]}:{texto[11:13]}"
    if len(texto) >= 16:
        return f"{texto[8:10]}/{texto[5:7]}/{texto[:4]} {texto[11:16]}"
    if len(texto) == 10:  # solo fecha: 2026-10-09
        return f"{texto[8:10]}/{texto[5:7]}/{texto[:4]}"
    return texto or "—"


# Tarjeta de indicador: título, valor y una línea con la unidad y el periodo (§7.3).
def tarjeta(columna, titulo: str, valor: str, detalle: str) -> None:
    with columna.container(border=True):
        st.metric(titulo, valor)
        st.caption(detalle)


# Mensaje cuando un filtro no devuelve datos, en lugar de un gráfico o tabla vacíos.
def sin_datos(texto: str = "No hay datos para los filtros elegidos. Pruebe ampliando el rango o quitando filtros.") -> None:
    st.info(texto, icon="ℹ️")


# Nombre del comercio en negrita y con su color, usando la sintaxis :color[...] de Streamlit (sin HTML).
_COLOR_MARKDOWN = {"La Rebaja": "red", "Locatel": "green", "Droguerías Cafam": "blue"}


def nombre_con_color(comercio: str) -> str:
    return f":{_COLOR_MARKDOWN.get(comercio, 'gray')}[**{comercio}**]"


# Devuelve los colores en el orden de los comercios presentes (para plotly).
def mapa_colores() -> dict:
    return dict(COLORES)


# --------------------------------------------------------------------------------------------------------------
# Filtros del panel lateral (7.2)
# --------------------------------------------------------------------------------------------------------------
# Dibuja los filtros en el panel lateral y devuelve el diccionario que entiende db._filtrar. La búsqueda
# se valida aquí (longitud y caracteres) antes de llegar a la consulta; db.py la vuelve a validar.
def filtros_laterales() -> dict:
    filtros = dict(db.FILTROS_VACIOS)
    barra = st.sidebar
    barra.header("Filtros")
    comercios = obtener("listar_comercios")
    subcategorias = obtener("listar_subcategorias")
    marcas = obtener("listar_marcas")
    ejecuciones = obtener("listar_ejecuciones")
    rango = obtener("rango_precios")
    if any(x is None for x in (comercios, subcategorias, marcas, ejecuciones, rango)):
        return filtros

    nombres = dict(zip(comercios["id_comercio"], comercios["nombre"]))
    filtros["comercios"] = barra.multiselect("Comercio", list(nombres), format_func=nombres.get,
                                             placeholder="Todos los comercios")
    filtros["subcategorias"] = barra.multiselect(
        "Subcategoría", list(subcategorias["subcategoria"]),
        format_func=lambda s: NOMBRES_SUBCATEGORIA.get(s, s), placeholder="Todas")
    filtros["marcas"] = barra.multiselect("Marca", list(marcas["marca"]), placeholder="Todas")

    minimo = int(rango["precio_min"].iloc[0] // 1000 * 1000)
    maximo = int(-(-rango["precio_max"].iloc[0] // 1000) * 1000)
    desde, hasta = barra.slider("Rango de precio (COP)", minimo, maximo, (minimo, maximo), step=1000,
                                format="$%d")
    if desde > minimo:
        filtros["precio_min"] = desde
    if hasta < maximo:
        filtros["precio_max"] = hasta

    opciones_periodo = ["ultima", *ejecuciones["id_ejecucion"], "fechas"]
    etiquetas = {"ultima": "Última ejecución de cada comercio", "fechas": "Rango de fechas…",
                 **{i: f"Ejecución del {formato_fecha(i)}" for i in ejecuciones["id_ejecucion"]}}
    periodo = barra.selectbox("Ejecución o periodo", opciones_periodo, format_func=etiquetas.get)
    if periodo == "fechas":
        fechas = [dt.date.fromisoformat(f[:10]) for f in ejecuciones["fecha_hora_inicio"]]
        rango_fechas = barra.date_input("Fechas de consulta", (min(fechas), max(fechas)),
                                        min_value=min(fechas), max_value=max(fechas), format="DD/MM/YYYY")
        if len(rango_fechas) == 2:
            filtros["fecha_desde"], filtros["fecha_hasta"] = (f.isoformat() for f in rango_fechas)
    elif periodo != "ultima":
        filtros["id_ejecucion"] = periodo

    filtros["solo_promociones"] = barra.checkbox("Solo productos en promoción")
    filtros["solo_comparables"] = barra.checkbox("Solo productos comparables (los 18 presentes en los 3 comercios)")
    texto = barra.text_input("Buscar en el nombre o el texto del anuncio", max_chars=db.LARGO_MAXIMO_TEXTO,
                             placeholder="p. ej. tio nacho keratina")
    try:
        filtros["busqueda"] = db.validar_texto(texto)
    except ValueError as error:
        barra.error(str(error))
        filtros["busqueda"] = ""
    return filtros


# Texto del periodo que cubren los filtros, para mostrarlo junto a indicadores, gráficos y tablas.
def describir_periodo(filtros: dict) -> str:
    if filtros.get("id_ejecucion"):
        return f"ejecución del {formato_fecha(filtros['id_ejecucion'])}"
    if filtros.get("fecha_desde") or filtros.get("fecha_hasta"):
        desde = formato_fecha(filtros.get("fecha_desde") or "")
        hasta = formato_fecha(filtros.get("fecha_hasta") or "")
        return f"consultas del {desde} al {hasta}"
    return "última ejecución de cada comercio"


# Filtros elegidos en el panel lateral (los guarda app.py en cada recarga).
def filtros_actuales() -> dict:
    return st.session_state.get("filtros", dict(db.FILTROS_VACIOS))
