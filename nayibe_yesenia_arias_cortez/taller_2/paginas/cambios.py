"""
paginas/cambios.py — Taller 2: página "Cambios de precio" (§8.2).

Compara dos ejecuciones elegidas por el usuario (por defecto, las dos más recientes): productos cuyo precio subió o
bajó (COP y %), productos nuevos y los que dejaron de observarse, con un umbral ajustable que resalta las
variaciones grandes. La comparación es sobre el mismo anuncio en el mismo comercio. Usa los filtros "Comercio" y
"Solo productos comparables" del panel lateral. Sin SQL.
"""
import streamlit as st

import componentes as cp

st.title("Cambios de precio entre dos ejecuciones")
filtros = cp.filtros_actuales()
st.caption("Usa los filtros «Comercio» y «Solo productos comparables» del panel lateral.")

ejecuciones = cp.obtener("listar_ejecuciones")
if ejecuciones is None or len(ejecuciones) < 2:
    cp.sin_datos("Se necesitan al menos dos ejecuciones para comparar precios.")
    st.stop()
ids = list(ejecuciones["id_ejecucion"])  # de la más reciente a la más antigua

# [CAMBIO]: selección de las dos ejecuciones (por defecto las dos más recientes) y del umbral.
c1, c2, c3 = st.columns([2, 2, 3])
id_a = c1.selectbox("Ejecución anterior (A)", ids, index=1, format_func=cp.formato_fecha)
id_b = c2.selectbox("Ejecución posterior (B)", ids, index=0, format_func=cp.formato_fecha)
umbral = c3.slider("Resaltar variaciones de al menos (%)", 1, 100, 10,
                   help="Las filas con una variación absoluta igual o mayor se marcan como «variación grande».")
if id_a == id_b:
    st.warning("Elija dos ejecuciones distintas.")
    st.stop()
if id_a > id_b:
    id_a, id_b = id_b, id_a
    st.info("Se intercambiaron las ejecuciones para que A sea la más antigua.")

cambios = cp.obtener("comparar_ejecuciones", id_a, id_b, umbral, comercios=filtros["comercios"] or None,
                     solo_comparables=filtros["solo_comparables"])
if cambios is None or cambios.empty:
    cp.sin_datos("No hay anuncios para comparar con estos filtros (o algún comercio no tiene datos en ambas "
                  "ejecuciones).")
    st.stop()

# [CAMBIO]: indicadores de la comparación (conteos calculados en SQL en la columna tipo_cambio).
conteo = cambios["tipo_cambio"].value_counts()
k1, k2, k3, k4, k5 = st.columns(5)
periodo = f"del {cp.formato_fecha(id_a)} al {cp.formato_fecha(id_b)}"
cp.tarjeta(k1, "Subieron", str(conteo.get("subió", 0)), f"Anuncios · {periodo}")
cp.tarjeta(k2, "Bajaron", str(conteo.get("bajó", 0)), f"Anuncios · {periodo}")
cp.tarjeta(k3, f"Variación ≥ {umbral} %", str(int(cambios["variacion_grande"].sum())), "Anuncios con cambio grande")
cp.tarjeta(k4, "Nuevos", str(conteo.get("nuevo", 0)), "Anuncios que solo aparecen en B")
cp.tarjeta(k5, "Dejaron de observarse", str(conteo.get("dejó de observarse", 0)),
           "Solo en A (no significa agotados ni retirados)")

# [CAMBIO]: tablas por tipo de cambio; las variaciones grandes se resaltan con color.
def resaltar(fila):
    color = "background-color: #fde2e1" if fila["variacion_grande"] == 1 and fila["diferencia_cop"] > 0 else (
        "background-color: #dcf5e3" if fila["variacion_grande"] == 1 else "")
    return [color] * len(fila)


configuracion = {
    "comercio": "Comercio", "nombre_original": "Producto", "sku_comercio": "SKU",
    "precio_a": st.column_config.NumberColumn("Precio en A (COP)", format="$ %,.0f"),
    "precio_b": st.column_config.NumberColumn("Precio en B (COP)", format="$ %,.0f"),
    "diferencia_cop": st.column_config.NumberColumn("Diferencia (COP)", format="$ %,.0f"),
    "variacion_pct": st.column_config.NumberColumn("Variación (%)", format="%.2f %%"),
    "tipo_cambio": "Cambio", "variacion_grande": st.column_config.CheckboxColumn("Variación grande"),
    "url": st.column_config.LinkColumn("Enlace", display_text="Ver anuncio"),
}
columnas = ["comercio", "nombre_original", "precio_a", "precio_b", "diferencia_cop", "variacion_pct",
            "variacion_grande", "url"]
pestanas = st.tabs(["Subieron o bajaron", "Nuevos", "Dejaron de observarse", "Todos"])
grupos = [cambios[cambios["tipo_cambio"].isin(["subió", "bajó"])], cambios[cambios["tipo_cambio"] == "nuevo"],
          cambios[cambios["tipo_cambio"] == "dejó de observarse"], cambios]
for pestana, grupo in zip(pestanas, grupos):
    with pestana:
        if grupo.empty:
            cp.sin_datos("No hay anuncios en este grupo.")
            continue
        tabla = grupo[columnas + (["tipo_cambio"] if pestana is pestanas[3] else [])]
        st.dataframe(tabla.style.apply(resaltar, axis=1), hide_index=True, width="stretch",
                     column_config=configuracion, height=min(420, 38 + 35 * len(tabla)))
st.caption("Rojo: subió al menos el umbral. Verde: bajó al menos el umbral. Solo se comparan los comercios con "
           "datos en ambas ejecuciones. Precios en COP.")
