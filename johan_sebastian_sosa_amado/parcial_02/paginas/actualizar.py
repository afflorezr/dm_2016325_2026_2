"""Botón para actualizar los precios y pestañas para revisar la calidad de
los datos: ejecuciones, disponibilidad, correcciones y rechazos."""

import pandas as pd
import streamlit as st

import db
import scraper
import ui

st.title("Actualizar precios")
st.write("El botón ejecuta el mismo scraper del Taller 1 (`scraper.py`), comercio por comercio. "
         "Cada comercio se valida y se guarda en una transacción: si uno falla, los demás siguen.")

modo = st.radio("Modo", ["En línea (consulta las tiendas)", "Sin conexión (reprocesa las copias de raw/)"],
                help="Sin conexión no descarga nada: vuelve a procesar la copia completa más reciente guardada en raw/.")
sin_conexion = modo.startswith("Sin conexión")

if st.button("Actualizar precios", type="primary"):
    resumenes = []
    recoleccion_id = pd.Timestamp.now(tz="America/Bogota").strftime("%Y-%m-%dT%H-%M-%S")
    if sin_conexion:
        # Igual que en scraper.ejecutar_recoleccion().
        recoleccion_id = scraper.recoleccion_sin_conexion() or recoleccion_id
    con = scraper.conectar_base()
    try:
        with st.status("Actualizando precios...", expanded=True) as estado:
            for clave, tienda in scraper.TIENDAS.items():
                st.write(f"Consultando {ui.NOMBRES.get(tienda['comercio'], tienda['comercio'])}...")
                r = scraper.recolectar_comercio(clave, con, recoleccion_id, sin_conexion)
                resumenes.append(r)
                if r["estado"] == "completa":
                    st.write(f"Completa: {r['recolectados']} productos de la categoría")
                else:
                    st.write(f"{r['estado'].capitalize()}: {r['motivo']}")
            st.write("Repitiendo la limpieza y el emparejamiento de productos...")
            scraper.limpiar_y_emparejar(con)
            hubo_fallas = any(r["estado"] != "completa" for r in resumenes)
            estado.update(label="Actualización terminada" + (" con fallas" if hubo_fallas else ""),
                          state="error" if all(r["estado"] == "fallida" for r in resumenes) else "complete")
    finally:
        con.close()
    ui.limpiar_cache()     # así el resto de páginas muestra los precios nuevos
    st.session_state["ultimo_resumen"] = pd.DataFrame(resumenes)
    st.session_state["aviso_sin_respuesta"] = any(r["estado"] == "fallida" for r in resumenes) and not sin_conexion
    # El panel lateral ya se dibujó con la recolección anterior: se vuelve a
    # cargar la página y el panel pasa a la más reciente (ui.panel_filtros).
    st.session_state["mostrar_ultima_recoleccion"] = True
    st.rerun()

if st.session_state.get("aviso_sin_respuesta"):
    st.warning("Algún comercio no respondió. Es común en servidores en la nube, porque las tiendas suelen bloquear "
               "estas plataformas. Puede usar el modo sin conexión para reprocesar las copias guardadas en raw/.")

if "ultimo_resumen" in st.session_state:
    st.subheader("Resumen de la última actualización")
    r = st.session_state["ultimo_resumen"].assign(comercio=lambda d: d["comercio"].map(ui.NOMBRES))
    st.dataframe(ui.formato_tabla(r), hide_index=True, width="stretch", placeholder="",
                 column_order=["comercio", "estado", "recolectados", "nuevos", "cambios_precio",
                               "no_observados", "rechazados", "insertadas", "motivo"],
                 column_config={"comercio": "Comercio", "estado": "Estado",
                                "recolectados": "Productos de la categoría",
                                "nuevos": "Nuevos", "cambios_precio": "Cambios de precio",
                                "no_observados": "No observados", "rechazados": "Rechazados",
                                "insertadas": "Filas guardadas (toda la sección)", "motivo": "Motivo"})
    st.caption("Productos, nuevos, cambios de precio y no observados cuentan solo la categoría. "
               "'Filas guardadas' cuenta todo lo que trae la sección de la tienda, que en Olímpica incluye "
               "productos de otras categorías; es 0 si esa recolección ya estaba en la base (no se duplica).")

st.divider()
st.header("Calidad de los datos")
t1, t2, t3, t4 = st.tabs(["Ejecuciones", "Disponibilidad", "Correcciones del Taller 1", "Rechazos"])
with t1:
    st.dataframe(ui.formato_tabla(db.ejecuciones().assign(
                     comercio=lambda d: d["comercio"].map(ui.NOMBRES),
                     fecha_hora_inicio=lambda d: d["fecha_hora_inicio"].map(ui.fecha_corta))),
                 hide_index=True, width="stretch", placeholder="",
                 column_config={"recoleccion_id": "Recolección", "comercio": "Comercio",
                                "fecha_hora_inicio": "Inicio", "estado": "Estado",
                                "total_servicio": "Productos que informa el sitio", "registros": "Registros",
                                "cargada_desde": "Cargada desde", "carpeta_raw": "Copia en raw/"})
with t2:
    rec = st.session_state["filtros"]["recoleccion_id"]
    disp = ui.disponibilidad(rec)
    st.caption("Disponible y agotado salen de lo que dice cada sitio. 'No observado' es un anuncio visto en otra "
               "recolección que no apareció en esta: no se interpreta como agotado ni retirado. "
               "Olímpica solo publica productos disponibles.")
    if not ui.sin_datos(disp):
        st.dataframe(disp.pivot_table(index="comercio", columns="estado", values="anuncios", fill_value=0)
                     .rename(index=ui.NOMBRES, columns=str.capitalize)
                     .rename_axis(index="Comercio", columns=None), width="stretch")
with t3:
    st.dataframe(ui.formato_tabla(db.tabla_correcciones()), hide_index=True, width="stretch", placeholder="",
                 column_config={"fecha": "Fecha", "referencia": "Registro", "campo": "Campo",
                                "valor_anterior": "Valor anterior", "valor_nuevo": "Valor nuevo",
                                "motivo": "Motivo"})
with t4:
    rechazos = db.tabla_rechazos()
    if not ui.sin_datos(rechazos, "Ninguna observación ha sido rechazada por la validación."):
        st.dataframe(ui.formato_tabla(rechazos), hide_index=True, width="stretch", placeholder="",
                     column_config={"ejecucion_id": "Ejecución", "comercio": "Comercio", "sku": "SKU",
                                    "regla": "Regla", "detalle": "Detalle",
                                    "fecha_hora_consulta": "Fecha de consulta"})
