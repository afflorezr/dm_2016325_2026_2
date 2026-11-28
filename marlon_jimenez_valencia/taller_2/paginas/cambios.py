"""Página Cambios de precio: compara dos ejecuciones elegidas por el usuario (§8.2)."""
import plotly.express as px
import streamlit as st

import db
import interfaz

st.title("Cambios de precio")
st.markdown("Compara el **mismo anuncio en el mismo comercio** entre dos ejecuciones: qué subió, qué "
            "bajó (en COP y en %), qué apareció y qué dejó de observarse.")

with interfaz.protegido():
    interfaz.fecha_de_los_datos()
    ejecuciones = db.ejecuciones()
    if len(ejecuciones) < 2:
        interfaz.sin_datos("Se necesitan al menos dos ejecuciones para comparar.")
        st.stop()
    filas = {f.id_ejecucion: f._asdict() for f in ejecuciones.itertuples()}
    ids = list(filas)
    completas = ejecuciones.loc[ejecuciones["completa"] == 1, "id_ejecucion"].tolist()
    por_defecto = completas[:2] if len(completas) >= 2 else ids[:2]   # las dos más recientes

    comercios = db.comercios()
    nombres = dict(zip(comercios["id_comercio"], comercios["comercio"]))
    c1, c2 = st.columns(2)
    id_1 = c1.selectbox("Ejecución anterior", ids, index=ids.index(por_defecto[1]),
                        format_func=lambda i: interfaz.etiqueta_ejecucion(filas[i]))
    id_2 = c2.selectbox("Ejecución posterior", ids, index=ids.index(por_defecto[0]),
                        format_func=lambda i: interfaz.etiqueta_ejecucion(filas[i]))
    c3, c4 = st.columns([2, 1])
    elegidos = c3.multiselect("Comercios", list(nombres), default=list(nombres),
                              format_func=nombres.get)
    umbral = c4.slider("Resaltar variaciones de al menos (%)", 1, 50, 10,
                       help="Las filas con un cambio igual o mayor que este porcentaje se resaltan.")

    if id_1 == id_2:
        st.warning("Elige dos ejecuciones distintas.")
        st.stop()
    if not elegidos:
        st.warning("Elige al menos un comercio.")
        st.stop()
    # La anterior es la que empezó primero, aunque el usuario las elija al revés
    anterior, posterior = sorted([id_1, id_2], key=lambda i: filas[i]["inicio"])
    if (anterior, posterior) != (id_1, id_2):
        st.info(f"Se compara {anterior} (anterior) con {posterior} (posterior), en orden de fecha.")

    cambios = db.cambios_entre(anterior, posterior, tuple(elegidos))
    if cambios.empty:
        interfaz.sin_datos("Ningún comercio tiene datos válidos en las dos ejecuciones.")
        st.stop()
    st.caption(f"Anterior: {interfaz.fecha_legible(filas[anterior]['inicio'])} · Posterior: "
               f"{interfaz.fecha_legible(filas[posterior]['inicio'])}. Solo se comparan los "
               "comercios que no fallaron en ninguna de las dos ejecuciones.")

    conteo = cambios["tipo"].value_counts()
    m = st.columns(5)
    for col, tipo, etiqueta in zip(m, ["subió", "bajó", "nuevo", "dejó de observarse", "sin cambio"],
                                   ["Subieron", "Bajaron", "Nuevos", "Dejaron de observarse",
                                    "Sin cambio"]):
        col.metric(etiqueta, interfaz.numero(conteo.get(tipo, 0)), border=True)
        col.caption("anuncios")

    por_comercio = (cambios[cambios["tipo"].isin(["subió", "bajó", "nuevo", "dejó de observarse"])]
                    .groupby(["comercio", "tipo"]).size().reset_index(name="anuncios"))
    if not por_comercio.empty:
        fig = px.bar(por_comercio, x="tipo", y="anuncios", color="comercio", barmode="group",
                     color_discrete_map=interfaz.COLORES, text="anuncios",
                     category_orders={"comercio": interfaz.ORDEN_COMERCIOS,
                                      "tipo": ["subió", "bajó", "nuevo", "dejó de observarse"]})
        fig.update_traces(textposition="outside")
        interfaz.estilo(fig, "Anuncios", "")
        fig.update_layout(height=320)
        interfaz.mostrar_grafico(fig, por_comercio)

    variaciones = cambios[cambios["tipo"].isin(["subió", "bajó"])].copy()
    st.subheader(f"Precios que cambiaron ({len(variaciones)})")
    if variaciones.empty:
        interfaz.sin_datos("Ningún precio cambió entre estas dos ejecuciones.")
    else:
        grandes = variaciones["cambio_pct"].abs() >= umbral
        st.caption(f"{int(grandes.sum())} cambios de {umbral} % o más, resaltados en amarillo.")

        def resaltar(fila):
            fondo = "background-color: rgba(237, 161, 0, 0.25)" if abs(fila["cambio_pct"]) >= umbral else ""
            return [fondo] * len(fila)

        columnas = ["comercio", "nombre", "precio_anterior", "precio_posterior", "cambio_cop",
                    "cambio_pct", "tipo", "id_producto", "sku_comercio", "url_producto"]
        interfaz.tabla(variaciones[columnas], resaltar=resaltar, height=420, column_config={
                         "comercio": "Comercio", "nombre": st.column_config.TextColumn("Nombre", width="large"),
                         "precio_anterior": interfaz.columna_cop("Precio anterior (COP)"),
                         "precio_posterior": interfaz.columna_cop("Precio posterior (COP)"),
                         "cambio_cop": interfaz.columna_cop("Cambio (COP)"),
                         "cambio_pct": "Cambio (%)",
                         "tipo": "Dirección", "id_producto": "Comparable", "sku_comercio": "SKU",
                         "url_producto": st.column_config.LinkColumn("Anuncio", display_text="Abrir")})
        interfaz.descargar_csv(variaciones[columnas], f"cambios_{anterior}_{posterior}.csv")

    c5, c6 = st.columns(2)
    for col, tipo, titulo in [(c5, "nuevo", "Productos nuevos"),
                              (c6, "dejó de observarse", "Productos que dejaron de observarse")]:
        with col:
            sub = cambios[cambios["tipo"] == tipo]
            st.subheader(f"{titulo} ({len(sub)})")
            if sub.empty:
                st.caption("Ninguno.")
            else:
                precio = "precio_posterior" if tipo == "nuevo" else "precio_anterior"
                interfaz.tabla(sub[["comercio", "nombre", precio, "url_producto"]], hide_index=True,
                             width="stretch", column_config={
                                 "comercio": "Comercio", "nombre": "Nombre",
                                 precio: interfaz.columna_cop("Precio (COP)"),
                                 "url_producto": st.column_config.LinkColumn("Anuncio", display_text="Abrir")})
    st.caption("'Dejó de observarse' significa que el anuncio no apareció en la ejecución posterior; "
               "no quiere decir que esté agotado.")
