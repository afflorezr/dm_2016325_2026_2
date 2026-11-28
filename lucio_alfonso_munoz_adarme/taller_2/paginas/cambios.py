import streamlit as st

import db
from comun import ETIQUETA, elegir_ejecucion, numero

st.title("Cambios de precio")
st.caption("Compara el mismo anuncio en el mismo comercio entre dos ejecuciones. Precios en COP.")

c = st.columns(3)
ej_b = elegir_ejecucion("Ejecución reciente", "ej_b", 0, c[0])
ej_a = elegir_ejecucion("Ejecución anterior", "ej_a", 1, c[1])
umbral = c[2].slider("Resaltar variaciones mayores a (%)", 1, 50, 10)
if ej_a == ej_b:
    st.warning("Elija dos ejecuciones distintas.")
    st.stop()
if ej_a > ej_b:
    ej_a, ej_b = ej_b, ej_a

datos = db.cambios_precio(ej_a, ej_b)
fuera = [ETIQUETA[r.comercio] for r in db.estado_ejecucion(ej_a).itertuples() if r.estado == "fallida"] + \
        [ETIQUETA[r.comercio] for r in db.estado_ejecucion(ej_b).itertuples() if r.estado == "fallida"]
if fuera:
    fuera = sorted(set(fuera))
    st.warning(f"No se incluye{'n' if len(fuera) > 1 else ''} {', '.join(fuera)}, porque su ejecución falló en alguna "
               "de las dos fechas. Que un producto no aparezca no quiere decir que esté agotado o retirado.")
if datos.empty:
    st.warning("No hay productos para comparar entre estas dos ejecuciones.")
    st.stop()

conteo = datos["tipo"].value_counts()
m = st.columns(4)
for col, tipo in zip(m, ["subió", "bajó", "nuevo", "ya no se observa"]):
    col.metric(tipo.capitalize(), numero(conteo.get(tipo, 0)), border=True)
st.caption(f"Presentaciones de la categoría; anterior: {ej_a}, reciente: {ej_b}.")

datos["comercio"] = datos["comercio"].map(ETIQUETA)
config = {"comercio": "Comercio", "nombre": "Nombre",
          "precio_a": st.column_config.NumberColumn("Precio anterior (COP)", format="$ %,.0f"),
          "precio_b": st.column_config.NumberColumn("Precio reciente (COP)", format="$ %,.0f"),
          "cambio_cop": st.column_config.NumberColumn("Cambio (COP)", format="$ %,.0f"),
          "cambio_pct": st.column_config.NumberColumn("Cambio (%)", format="%.1f"), "tipo": "Tipo"}


def resaltar(fila):
    grande = abs(fila["cambio_pct"]) >= umbral if fila["cambio_pct"] == fila["cambio_pct"] else False
    return ["background-color: #FFE8A3" if grande else ""] * len(fila)


pestanas = st.tabs(["Subieron o bajaron", "Nuevos", "Ya no se observan"])
with pestanas[0]:
    cambios = datos[datos["tipo"].isin(["subió", "bajó"])]
    if cambios.empty:
        st.info("Ningún precio cambió entre estas dos ejecuciones.")
    else:
        st.dataframe(cambios.style.apply(resaltar, axis=1), hide_index=True, column_config=config)
        st.caption(f"En amarillo, las variaciones de {umbral} % o más.")
with pestanas[1]:
    st.dataframe(datos[datos["tipo"] == "nuevo"], hide_index=True, column_config=config)
with pestanas[2]:
    st.dataframe(datos[datos["tipo"] == "ya no se observa"], hide_index=True, column_config=config)
