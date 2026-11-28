import streamlit as st

import componentes as ui
import datos_cache as dc

f = st.session_state["filtros"]
st.title("Cambios de precio entre dos ejecuciones")
st.caption("La comparación se hace sobre el mismo anuncio en el mismo comercio. Los comercios del panel lateral "
           "también filtran esta página.")

corr = dc.corridas()
if len(corr) < 2:
    st.info("Por ahora la base tiene una sola ejecución con datos. Cuando se registre una nueva (página "
            "«Actualizar datos»), aquí aparecerán los productos que subieron, bajaron, aparecieron o dejaron de observarse.",
            icon=":material/history:")
    st.stop()

etiquetas = {ui.etiqueta_corrida(fila): int(fila["id_corrida"]) for _, fila in corr.iterrows()}  # más reciente primero
lista = list(etiquetas)
c1, c2, c3 = st.columns([1, 1, 0.8])
with c1:
    a = st.selectbox("Ejecución anterior", lista, index=1)
with c2:
    b = st.selectbox("Ejecución posterior", lista, index=0)
with c3:
    umbral = st.slider("Resaltar variaciones desde (%)", 1, 50, 10, help="Umbral de variación absoluta en porcentaje")
solo_comp = st.toggle("Solo productos comparables", value=f.solo_comparables)

id_a, id_b = etiquetas[a], etiquetas[b]
if id_a == id_b:
    st.warning("Elija dos ejecuciones distintas.")
    st.stop()
if corr.set_index("id_corrida").loc[id_a, "orden"] > corr.set_index("id_corrida").loc[id_b, "orden"]:
    st.warning("La ejecución «anterior» es más reciente que la «posterior»: los cambios se leen en sentido inverso.")

r = dc.comparar(id_a, id_b, f.comercios, float(umbral), solo_comp)
cambios, nuevos, no_obs = r["cambios"], r["nuevos"], r["no_observados"]

m1, m2, m3, m4, m5 = st.columns(5)
with m1:
    ui.tarjeta("Subieron", ui.numero((cambios["direccion"] == "subió").sum()), "anuncios")
with m2:
    ui.tarjeta("Bajaron", ui.numero((cambios["direccion"] == "bajó").sum()), "anuncios")
with m3:
    ui.tarjeta(f"Variación ≥ {umbral} %", ui.numero(cambios["variacion_grande"].sum()), "anuncios resaltados")
with m4:
    ui.tarjeta("Nuevos", ui.numero(len(nuevos)), "en la posterior y no en la anterior")
with m5:
    ui.tarjeta("Dejaron de observarse", ui.numero(len(no_obs)), "no implica agotado ni retirado")

if not r["resumen"].empty:
    st.dataframe(ui.formato_tabla(r["resumen"], num_cols=["subieron", "bajaron", "sin_cambio"]), hide_index=True,
                 column_config={"comercio": "Comercio", "subieron": "Subieron", "bajaron": "Bajaron",
                                "sin_cambio": "Sin cambio"})

st.subheader("Productos que cambiaron de precio")
if cambios.empty:
    ui.sin_datos("Ningún anuncio cambió de precio entre las dos ejecuciones con los filtros elegidos.")
else:
    vista = cambios[["comercio", "nombre", "marca", "precio_anterior", "precio_nuevo", "cambio_cop", "cambio_pct",
                     "direccion", "variacion_grande", "url"]]

    def _resaltar(fila):
        color = "background-color: rgba(220, 38, 38, 0.15)" if fila["direccion"] == "subió" else "background-color: rgba(22, 163, 74, 0.15)"
        return [color if fila["variacion_grande"] else "" for _ in fila]

    estilo = ui.formato_tabla(vista, cop_cols=["precio_anterior", "precio_nuevo", "cambio_cop"], pct_cols=["cambio_pct"]).apply(_resaltar, axis=1)
    st.dataframe(estilo, hide_index=True, width="stretch",
                 column_config={"comercio": "Comercio", "nombre": st.column_config.TextColumn("Producto", width="large"),
                                "marca": "Marca", "precio_anterior": "Precio anterior (COP)", "precio_nuevo": "Precio nuevo (COP)",
                                "cambio_cop": "Cambio (COP)", "cambio_pct": "Cambio (%)", "direccion": "Dirección",
                                "variacion_grande": st.column_config.CheckboxColumn(f"≥ {umbral} %"),
                                "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir")})
    st.caption("Filas resaltadas: variación igual o mayor al umbral (rojo: subió; verde: bajó).")

col_n, col_d = st.columns(2)
cfg = {"comercio": "Comercio", "nombre": "Producto", "marca": "Marca", "precio": "Precio (COP)",
       "comparable": st.column_config.CheckboxColumn("Comparable"), "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir")}
with col_n:
    st.subheader("Nuevos")
    if nuevos.empty:
        st.caption("No hay anuncios nuevos.")
    else:
        st.dataframe(ui.formato_tabla(nuevos, cop_cols=["precio"]), hide_index=True, width="stretch", column_config=cfg)
with col_d:
    st.subheader("Dejaron de observarse")
    if no_obs.empty:
        st.caption("Todos los anuncios de la ejecución anterior se observaron de nuevo.")
    else:
        st.dataframe(ui.formato_tabla(no_obs, cop_cols=["precio"]), hide_index=True, width="stretch", column_config=cfg)
        st.caption("Un anuncio no observado puede deberse a un cambio de catálogo o a una falla parcial; no se "
                   "interpreta como agotado ni retirado sin evidencia.")
ui.nota_fecha_datos()
