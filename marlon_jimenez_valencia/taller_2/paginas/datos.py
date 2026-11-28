"""Página Calidad de los datos: ejecuciones, validación, rechazos, correcciones y raw/ (Módulo 1)."""
import plotly.express as px
import streamlit as st

import db
import interfaz
import scraper

st.title("Calidad de los datos")
st.markdown("Cómo se obtuvieron los datos y qué se corrigió. Nada se borra: las observaciones que "
            "no pasan la validación se guardan en **rechazos** y cada cambio a un dato que ya "
            "estaba se anota en **correcciones**.")

with interfaz.protegido():
    interfaz.fecha_de_los_datos()
    t1, t2, t3, t4, t5, t6 = st.tabs(["Ejecuciones", "Disponibilidad", "Validaciones", "Rechazos",
                                      "Correcciones", "Copias crudas (raw/)"])

    with t1:
        st.caption("Una fila por ejecución y comercio. 'Nuevos' y 'cambios de precio' se calculan "
                   "frente a las observaciones anteriores de cada anuncio.")
        interfaz.tabla(db.resumen_ejecuciones(), hide_index=True, width="stretch", column_config={
            "id_ejecucion": "Ejecución", "comercio": "Comercio", "modo": "Modo", "estado": "Estado",
            "inicio": "Inicio", "fin": "Fin", "recolectados": "Recolectados", "nuevos": "Nuevos",
            "cambios_precio": "Cambios de precio", "no_observados": "No observados",
            "rechazados": "Rechazados", "detalle": "Detalle"})
        completas = db.ejecuciones()
        completas = completas[completas["completa"] == 1]
        st.caption("Ejecuciones completas en los 3 comercios: "
                   + ", ".join(f"{r.id_ejecucion} ({r.fecha})" for r in completas.itertuples()))

    with t2:
        ejecuciones = db.ejecuciones()
        filas = {f.id_ejecucion: f._asdict() for f in ejecuciones.itertuples()}
        id_ej = st.selectbox("Ejecución", list(filas), key="d_ejecucion",
                             index=list(filas).index(db.ejecucion_por_defecto()),
                             format_func=lambda i: interfaz.etiqueta_ejecucion(filas[i]))
        disp = db.disponibilidad(id_ej)
        if disp.empty:
            interfaz.sin_datos("Esta ejecución no tiene observaciones.")
        else:
            fig = px.bar(disp, x="comercio", y="anuncios", color="situacion", barmode="group",
                         text="anuncios",
                         color_discrete_map={"disponible": "#00876f", "agotado": "#c04a24",
                                             "no observado": "#9e968c"},
                         category_orders={"situacion": ["disponible", "agotado", "no observado"],
                                          "comercio": interfaz.ORDEN_COMERCIOS})
            fig.update_traces(textposition="outside")
            interfaz.estilo(fig, "Anuncios", "")
            fig.update_layout(height=340)
            interfaz.mostrar_grafico(fig, disp)
        st.caption("**Disponible** y **agotado** son lo que publica el sitio. **No observado**: el "
                   "anuncio se había visto antes en ese comercio, pero no apareció en esta "
                   "ejecución; no significa que esté agotado.")

    with t3:
        st.caption("Resultado de cada regla de validación (validacion.py) por ejecución y comercio.")
        validaciones = db.validaciones()
        validaciones["aprobada"] = validaciones["aprobada"].map({1: "Sí", 0: "No"})
        interfaz.tabla(validaciones, hide_index=True, width="stretch", column_config={
            "id_ejecucion": "Ejecución", "comercio": "Comercio", "regla": "Regla",
            "n_revisadas": "Revisadas", "n_fallas": "Fallas", "aprobada": "Aprobada",
            "detalle": st.column_config.TextColumn("Detalle", width="large"), "fecha": "Fecha"})

    with t4:
        rechazos = db.rechazos()
        if rechazos.empty:
            st.success("Ninguna observación ha sido rechazada por la validación.")
        else:
            interfaz.tabla(rechazos, hide_index=True, width="stretch")

    with t5:
        resumen = db.correcciones_resumen()
        interfaz.tabla(resumen, hide_index=True, width="stretch", column_config={
            "tabla": "Tabla", "campo": "Campo", "cambios": "Cambios"})
        c1, c2 = st.columns(2)
        tabla = c1.selectbox("Tabla", [None, *sorted(resumen["tabla"].unique())],
                             format_func=lambda t: "Todas" if t is None else t)
        campos = resumen.loc[resumen["tabla"] == tabla, "campo"] if tabla else resumen["campo"]
        campo = c2.selectbox("Campo", [None, *sorted(campos.unique())],
                             format_func=lambda c: "Todos" if c is None else c)
        detalle = db.correcciones(tabla, campo)
        interfaz.tabla(detalle, hide_index=True, width="stretch", height=400, column_config={
            "motivo": st.column_config.TextColumn("Motivo", width="large")})
        interfaz.descargar_csv(detalle, "correcciones.csv")

    with t6:
        st.caption("Copias comprimidas de las respuestas de cada sitio, por comercio y fecha. Con "
                   "ellas se puede reconstruir la base sin conexión (página Actualizar precios).")
        interfaz.tabla(scraper.copias_en_raw(), hide_index=True, width="stretch")
