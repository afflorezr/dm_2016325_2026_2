"""
Lo que comparten las páginas de la app: caché de las consultas, colores
de cada comercio, formato de pesos y fechas, y el panel de filtros.
Aquí no hay SQL; las consultas están en db.py.
"""

import streamlit as st

import db

# Cada comercio tiene el mismo color en todos los gráficos: amarillo, rojo y
# azul oscuro. No se usa verde, así que los tres se distinguen aunque se
# tenga daltonismo rojo-verde, porque además difieren mucho en claridad.
COLORES = {"Exito": "#E69F00", "La Rebaja": "#C8102E", "Olimpica": "#080AA3"}
NOMBRES = {"Exito": "Éxito", "La Rebaja": "La Rebaja", "Olimpica": "Olímpica"}
UNIDADES = {"unidad": "unidad", "mL": "mL", "g": "g"}
COLORES_VISIBLES = {NOMBRES[c]: color for c, color in COLORES.items()}


def visibles(tabla):
    """Cambia los nombres de comercio de la base por los nombres con tilde."""
    return tabla.assign(comercio=tabla["comercio"].map(lambda c: NOMBRES.get(c, c)))


def estilo(fig):
    """Formato colombiano en los ejes: punto de miles y coma decimal."""
    fig.update_layout(separators=",.", legend_title_text="Comercio")
    return fig


def cop(valor):
    """Pesos con punto de miles: cop(12900) da '$ 12.900'."""
    if valor is None or valor != valor:     # None o NaN
        return "sin dato"
    return "$ " + f"{valor:,.0f}".replace(",", ".")


def pct(valor):
    """Porcentaje con coma decimal: pct(27.6) da '27,6 %'."""
    if valor is None or valor != valor:
        return "sin dato"
    return f"{valor:.1f} %".replace(".", ",")


def formato_tabla(tabla, con_decimal=()):
    """Tabla con formato colombiano para st.dataframe: punto de miles, coma
    decimal y celdas vacías en blanco en lugar de None. Las columnas de
    con_decimal se muestran con un decimal; las demás, sin decimales. Los
    valores siguen siendo números, así que la tabla se ordena bien."""
    estilo = tabla.style.format(precision=0, thousands=".", decimal=",", na_rep="")
    if con_decimal:
        estilo = estilo.format(precision=1, thousands=".", decimal=",", na_rep="", subset=list(con_decimal))
    return estilo


def fecha_corta(iso):
    """Fecha legible: '2026-11-07T19:26:19-05:00' queda '7 nov 2026, 19:26'."""
    if not iso:
        return "sin dato"
    meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    anio, mes, dia = iso[:10].split("-")
    return f"{int(dia)} {meses[int(mes) - 1]} {anio}, {iso[11:16]}"


# Consultas guardadas en caché. Después de actualizar los precios se borra
# la caché (limpiar_cache) para que la app muestre los datos nuevos.

@st.cache_data(show_spinner=False)
def recolecciones():
    return db.recolecciones()


@st.cache_data(show_spinner=False)
def opciones():
    return db.opciones_filtros()


@st.cache_data(show_spinner=False)
def productos_filtrados(filtros):
    return db.productos_filtrados(dict(filtros))


@st.cache_data(show_spinner=False)
def indicadores(filtros):
    return db.indicadores(dict(filtros))


@st.cache_data(show_spinner=False)
def ahorro_comparables(recoleccion_id):
    return db.ahorro_comparables(recoleccion_id)


@st.cache_data(show_spinner=False)
def evolucion_producto(producto_id):
    return db.evolucion_producto(producto_id)


@st.cache_data(show_spinner=False)
def precio_unitario(recoleccion_id, unidad):
    return db.precio_unitario_comparables(recoleccion_id, unidad)


@st.cache_data(show_spinner=False)
def distribucion(filtros):
    return db.precios_para_distribucion(dict(filtros))


@st.cache_data(show_spinner=False)
def promociones(filtros):
    return db.promociones_por_comercio(dict(filtros))


@st.cache_data(show_spinner=False)
def cambios(recoleccion_a, recoleccion_b, umbral, comercios, tipos):
    return db.cambios_entre(recoleccion_a, recoleccion_b, umbral, comercios, tipos)


@st.cache_data(show_spinner=False)
def conteo_cambios(recoleccion_a, recoleccion_b, umbral, comercios):
    return db.conteo_cambios(recoleccion_a, recoleccion_b, umbral, comercios)


@st.cache_data(show_spinner=False)
def canasta(recoleccion_id, cantidades):
    return db.canasta(recoleccion_id, dict(cantidades))


@st.cache_data(show_spinner=False)
def disponibilidad(recoleccion_id):
    return db.disponibilidad(recoleccion_id)


def limpiar_cache():
    st.cache_data.clear()


def etiqueta_recoleccion(fila):
    return f"{fecha_corta(fila['inicio'])} ({fila['completas']} de {fila['comercios']} completas)"


def panel_filtros():
    """Dibuja los filtros del panel lateral y los devuelve como tupla de
    pares (clave, valor): st.cache_data necesita algo que no cambie."""
    recs = recolecciones()
    ops = opciones()
    with st.sidebar:
        st.header("Filtros")
        if recs.empty:
            st.error("La base no tiene recolecciones. Ejecute primero el scraper.")
            st.stop()
        etiquetas = {r["recoleccion_id"]: etiqueta_recoleccion(r) for _, r in recs.iterrows()}
        if st.session_state.pop("mostrar_ultima_recoleccion", False):
            st.session_state["f_recoleccion"] = list(etiquetas)[0]     # después de actualizar
        recoleccion = st.selectbox("Recolección (fecha de los precios)", list(etiquetas),
                                   format_func=etiquetas.get, key="f_recoleccion")
        comercios = st.multiselect("Comercio", ops["comercios"], default=ops["comercios"],
                                   format_func=lambda c: NOMBRES.get(c, c), placeholder="Elija uno o más",
                                   key="f_comercios")
        subcategorias = st.multiselect("Subcategoría", ops["subcategorias"],
                                       placeholder="Todas", key="f_subcategorias")
        marcas = st.multiselect("Marca", ops["marcas"], placeholder="Todas", key="f_marcas")
        tope = int(ops["precio_max"] // 10000 + 1) * 10000
        valores = list(range(0, tope + 1, 1000))
        # Si una actualización cambió el precio máximo, el rango guardado puede
        # quedar por fuera de las opciones: se vuelve al rango completo.
        if any(v not in valores for v in st.session_state.get("f_precio", ())):
            del st.session_state["f_precio"]
        precio = st.select_slider("Precio (COP)", options=valores, value=(0, tope),
                                  format_func=cop, key="f_precio")
        solo_promo = st.checkbox("Solo promociones", key="f_promo")
        solo_comp = st.checkbox("Solo productos comparables", key="f_comp")
        texto = st.text_input("Buscar en el nombre o en el anuncio", max_chars=db.LARGO_MAXIMO_BUSQUEDA,
                              placeholder="por ejemplo: pants ultra", key="f_texto")
        try:
            texto = db.validar_busqueda(texto)
        except ValueError as error:
            st.warning(str(error))
            texto = ""
    if not comercios:
        st.info("Elija al menos un comercio en el panel de filtros para ver los precios.")
        st.stop()
    filtros = {
        "recoleccion_id": recoleccion, "comercios": tuple(comercios),
        "subcategorias": tuple(subcategorias), "marcas": tuple(marcas),
        "precio_min": precio[0] if precio[0] > 0 else None,
        "precio_max": precio[1] if precio[1] < tope else None,
        "solo_promociones": solo_promo, "solo_comparables": solo_comp, "texto": texto,
    }
    st.session_state["filtros"] = filtros
    st.session_state["etiqueta_recoleccion"] = etiquetas[recoleccion]
    return tuple(filtros.items())


def filtros_actuales():
    return tuple(st.session_state["filtros"].items())


def aviso_fecha():
    """Recuerda en cada página de qué fecha son los precios y cuándo fue la
    última recolección."""
    recs = recolecciones()
    ultima = fecha_corta(recs.iloc[0]["inicio"]) if len(recs) else "sin dato"
    st.caption(f"Precios en pesos colombianos (COP) de la recolección del "
               f"{st.session_state.get('etiqueta_recoleccion', 'sin dato')}. "
               f"Última recolección: {ultima}. "
               "Los precios corresponden al momento de la consulta a cada tienda.")


def sin_datos(tabla, mensaje="Ningún producto cumple los filtros elegidos. Pruebe con menos filtros."):
    """Si no hay datos, muestra un aviso en lugar de un gráfico vacío."""
    if tabla is None or len(tabla) == 0:
        st.info(mensaje)
        return True
    return False
