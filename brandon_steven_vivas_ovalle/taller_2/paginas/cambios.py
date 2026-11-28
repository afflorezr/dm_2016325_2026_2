"""Página Cambios de precio: compara dos ejecuciones sobre el mismo anuncio en el mismo comercio."""
import streamlit as st

import analisis as A
import graficos as G
import servicios as sv
import ui
import validacion as V


def cuerpo():
    st.title("Cambios de precio")
    ui.banner_datos()
    ejecs = sv.consultar("ejecuciones")
    utiles = ejecs[ejecs["estado"] != "fallida"]
    if len(utiles) < 2:
        st.info("Se necesitan al menos dos ejecuciones para comparar. Ve a «Actualizar datos» para hacer una nueva.")
        return
    completas = utiles[utiles["es_completa"] == 1]
    base = completas if len(completas) >= 2 else utiles
    ids = utiles["ejecucion_id"].tolist()                      # de la más reciente a la más antigua
    por_defecto = base["ejecucion_id"].tolist()[:2]            # las dos más recientes (completas si existen)
    etiqueta = {i: f"{A.etiqueta_ejecucion(i)} · {utiles.loc[utiles['ejecucion_id'] == i, 'estado'].iloc[0]}" for i in ids}
    c1, c2, c3 = st.columns([2, 2, 1])
    nueva = c1.selectbox("Ejecución nueva", ids, index=ids.index(por_defecto[0]), format_func=etiqueta.get, key="c_nueva")
    anterior = c2.selectbox("Ejecución anterior", ids, index=ids.index(por_defecto[1]), format_func=etiqueta.get, key="c_ant")
    try:
        umbral = V.validar_umbral(c3.number_input("Umbral de variación grande (%)", 0.0, 100.0, 5.0, 0.5, key="c_umbral"))
    except ValueError as e:
        st.error(str(e))
        return
    if nueva == anterior:
        st.warning("Elige dos ejecuciones distintas.")
        return
    if utiles.set_index("ejecucion_id").loc[[nueva, anterior], "fecha"].nunique() == 1:
        st.caption("ℹ️ Las dos ejecuciones son del mismo día; para ver cambios entre fechas distintas usa una ejecución posterior.")
    st.caption("Por defecto se comparan las dos ejecuciones completas más recientes.")
    solo_comp = st.toggle("Solo productos comparables", key="c_comp")
    f = sv.filtros_actuales()
    coms = tuple(c for c in f.comercios if c != "__ninguno__")
    df = sv.consultar("cambios_entre_ejecuciones", anterior, nueva, umbral, solo_comp, coms)
    sin = sv.consultar("comercios_sin_comparacion", anterior, nueva)
    if sin:
        st.warning("Sin datos válidos en alguna de las dos ejecuciones (no se comparan): " + ", ".join(sin))
    if df.empty:
        ui.sin_datos("No hay productos para comparar entre esas ejecuciones.")
        return
    r = A.resumen_tipos(df)
    cols = st.columns(5)
    for col, (clave, titulo) in zip(cols, [("subió", "Subieron"), ("bajó", "Bajaron"), ("sin cambio", "Sin cambio"),
                                           ("nuevo", "Nuevos"), ("dejó de observarse", "Dejaron de observarse")]):
        with col:
            ui.tarjeta(titulo, A.n_(r[clave]), f"productos · {A.etiqueta_ejecucion(anterior)} → {A.etiqueta_ejecucion(nueva)}")
    if r["sin precio en alguna ejecución"]:
        st.caption(f"{A.n_(r['sin precio en alguna ejecución'])} productos estaban agotados (sin precio) en alguna de las dos ejecuciones.")
    grandes = int(df["variacion_grande"].sum())
    st.markdown(f"**{grandes}** producto(s) con variación de al menos **{A.n_(umbral, 1)} %**.")
    fig = G.variaciones(df)
    if fig is not None:
        st.plotly_chart(fig)
    tipos = st.multiselect("Tipos de cambio a mostrar", list(r), default=["subió", "bajó", "nuevo", "dejó de observarse"], key="c_tipos")
    t = df[df["tipo"].isin(tipos)].copy()
    t["variacion_grande"] = t["variacion_grande"].map({True: "⚠️", False: ""})
    st.dataframe(t, hide_index=True,
                 column_order=["comercio", "nombre_original", "tipo", "precio_anterior", "precio_nuevo", "variacion_cop",
                               "variacion_pct", "variacion_grande", "url"],
                 column_config={"comercio": "Comercio", "nombre_original": "Producto", "tipo": "Cambio",
                                "precio_anterior": st.column_config.NumberColumn("Precio anterior (COP)", format="$%d"),
                                "precio_nuevo": st.column_config.NumberColumn("Precio nuevo (COP)", format="$%d"),
                                "variacion_cop": st.column_config.NumberColumn("Variación (COP)", format="%+d"),
                                "variacion_pct": st.column_config.NumberColumn("Variación (%)", format="%+.2f"),
                                "variacion_grande": "Grande", "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir")})
    st.download_button("⬇️ Descargar CSV", t.to_csv(index=False).encode("utf-8-sig"), file_name="cambios_de_precio.csv", mime="text/csv")


ui.ejecutar_seguro(cuerpo)
