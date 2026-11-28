import plotly.express as px
import streamlit as st

import componentes as ui
import datos_cache as dc

f = st.session_state["filtros"]
st.title("Comparables y precio unitario")
st.caption("Los productos comparables son la misma presentación (misma marca, línea, FPS y contenido) publicada en "
           "los tres comercios; en Locatel se emparejan por código EAN.")

catalogo = dc.comparables()
id_analisis = ui.corrida_de_analisis(f)

# --- 1. Evolución del precio de un comparable ---------------------------------
st.subheader("Evolución del precio")
nombres = dict(zip(catalogo["nombre_estandar"] + " · " + catalogo["presentacion_estandar"], catalogo["id_producto_comun"]))
elegido = st.selectbox("Producto comparable", list(nombres))
evo = dc.evolucion(nombres[elegido], f.comercios)
if evo.empty:
    ui.sin_datos("No hay observaciones de este producto para los comercios seleccionados.")
else:
    evo = evo.assign(fecha=evo["fecha_hora_consulta"].str.slice(0, 19),
                     disponibilidad=evo["estado_disponibilidad"].map(ui.ETIQUETAS_DISPONIBILIDAD).fillna("Sin información"),
                     promocion=evo["es_promocion"].map({1: "Sí", 0: "No"}))
    fig = px.line(evo, x="fecha", y="precio_actual", color="comercio", markers=True,
                  color_discrete_map=ui.COLORES_COMERCIO, category_orders={"comercio": ui.ORDEN_COMERCIOS},
                  hover_data={"precio_lista": ":,.0f", "promocion": True, "disponibilidad": True, "id_corrida": True},
                  labels={"fecha": "Fecha y hora de consulta", "precio_actual": "Precio (COP)", "comercio": "Comercio",
                          "precio_lista": "Precio de lista (COP)", "promocion": "Promoción",
                          "disponibilidad": "Disponibilidad", "id_corrida": "Ejecución"})
    fig.update_traces(marker={"size": 10})
    fig.update_yaxes(tickprefix="$ ")
    fig.update_xaxes(type="date", tickformat="%d/%m/%Y")
    n_fechas = evo["id_corrida"].nunique()
    st.plotly_chart(ui.estilo_figura(fig, f"Precio de {elegido}",
                                     f"COP por presentación · una serie por comercio · {n_fechas} ejecución(es)"),
                    width="stretch")
    if n_fechas < 2:
        st.caption("Con una sola ejecución cada serie es un punto; la evolución aparece desde la segunda ejecución.")

# --- 2. Precio por unidad de contenido -----------------------------------------
st.subheader("Precio por unidad de contenido")
st.caption(f"Ejecución {id_analisis}. Las unidades no se mezclan: los productos en mL y en g se comparan por separado.")
pu = dc.precio_unitario(id_analisis, f.comercios)
if pu.empty:
    ui.sin_datos("No hay comparables con precio en esta ejecución.")
else:
    unidades = sorted(pu["contenido_unidad"].unique())
    pestanas = st.tabs([f"COP por {u}" for u in unidades])
    for pestana, unidad in zip(pestanas, unidades):
        with pestana:
            d = pu[pu["contenido_unidad"] == unidad].assign(
                producto=lambda x: x["nombre_estandar"].str.replace(r" FPS 50\+", "", regex=True) + " (" + x["presentacion_estandar"] + ")",
                disponibilidad=lambda x: x["estado_disponibilidad"].map(ui.ETIQUETAS_DISPONIBILIDAD).fillna("Sin información"))
            fig = px.bar(d, y="producto", x="precio_por_unidad", color="comercio", barmode="group", orientation="h",
                         color_discrete_map=ui.COLORES_COMERCIO, category_orders={"comercio": ui.ORDEN_COMERCIOS},
                         hover_data={"precio_actual": ":,.0f", "disponibilidad": True},
                         labels={"producto": "Producto", "precio_por_unidad": f"Precio por {unidad} (COP/{unidad})",
                                 "comercio": "Comercio", "precio_actual": "Precio del empaque (COP)",
                                 "disponibilidad": "Disponibilidad"})
            fig.update_xaxes(tickprefix="$ ")
            st.plotly_chart(ui.estilo_figura(fig, f"Precio por {unidad} de los comparables",
                                             f"COP/{unidad} · Ejecución {id_analisis}",
                                             alto=140 + 60 * d["producto"].nunique()), width="stretch")

# --- Tabla de ahorro --------------------------------------------------------------
st.subheader("Dónde comprar cada comparable")
incluir = st.toggle("Incluir productos agotados según el sitio", value=False,
                    help="Por defecto se excluyen: un producto agotado no se puede comprar aunque el sitio muestre su precio.")
ah = dc.ahorro_por_producto(id_analisis, f.comercios, incluir)
if ah.empty:
    ui.sin_datos("No hay comparables con precio en al menos dos comercios.")
else:
    vista = ah[["nombre_estandar", "mas_barato_en", "precio_min", "precio_max", "ahorro_cop", "ahorro_pct", "n_comercios"]]
    st.dataframe(ui.formato_tabla(vista, cop_cols=["precio_min", "precio_max", "ahorro_cop"], pct_cols=["ahorro_pct"]),
                 hide_index=True, width="stretch",
                 column_config={"nombre_estandar": "Producto", "mas_barato_en": "Más barato en (empates: todos)",
                                "precio_min": "Precio mínimo (COP)", "precio_max": "Precio máximo (COP)",
                                "ahorro_cop": "Ahorro frente al más caro (COP)", "ahorro_pct": "Ahorro (%)",
                                "n_comercios": "Comercios con precio"})
ui.nota_fecha_datos()
