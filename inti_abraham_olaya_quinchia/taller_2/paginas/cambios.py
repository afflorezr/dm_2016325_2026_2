"""paginas/cambios.py - Cambios de precio entre dos ejecuciones (mismo anuncio, mismo comercio)."""

import pandas as pd
import streamlit as st

import db

DB = db.DB_PATH


def cop(v):
    return "—" if v is None or pd.isna(v) else "$" + f"{v:,.0f}".replace(",", ".")


st.title("Cambios de precio")
ejec = db.obtener_ejecuciones(DB)
if len(ejec) < 2:
    st.info("Se necesitan al menos dos ejecuciones para comparar. Pulsa «Actualizar precios» para crear una nueva.")
    st.stop()

# Selección de las dos ejecuciones (por defecto, las dos más recientes)
etiqueta = {r.corrida_id: f"{str(r.fecha)[:16].replace('T', ' ')} · {r.corrida_id}" for r in ejec.itertuples()}
ids = list(etiqueta)
c1, c2, c3 = st.columns([2, 2, 1])
antes = c1.selectbox("Ejecución anterior", ids, index=1, format_func=etiqueta.get)
despues = c2.selectbox("Ejecución nueva", ids, index=0, format_func=etiqueta.get)
umbral = c3.number_input("Resaltar variaciones ≥ (%)", min_value=0.0, max_value=100.0, value=10.0, step=1.0)
if antes == despues:
    st.warning("Elige dos ejecuciones distintas.")
    st.stop()
if str(ejec.set_index("corrida_id").loc[antes, "fecha"]) > str(ejec.set_index("corrida_id").loc[despues, "fecha"]):
    st.warning("La ejecución «anterior» es posterior a la «nueva»: los cambios se leerán al revés.")

comercios = st.multiselect("Comercio", db.obtener_filtros(DB)["comercios"])
df = db.obtener_cambios(DB, antes, despues, comercios)
if df.empty:
    st.info("No hay anuncios comparables entre esas ejecuciones (los comercios deben tener datos válidos en ambas).")
    st.stop()

# Resumen
n = df["estado"].value_counts()
m = st.columns(6)
for col, (rot, clave) in zip(m, [("Subieron", "subió"), ("Bajaron", "bajó"), ("Sin cambio", "igual"),
                                 ("Nuevos", "nuevo"), ("No observados", "no observado"), ("Agotados", "agotado")]):
    col.metric(rot, int(n.get(clave, 0)))
st.caption("Cambios sobre el mismo anuncio en el mismo comercio. Precios en COP, a la fecha de cada consulta. "
           "«No observado» significa que no apareció en la ejecución nueva; no implica que esté agotado ni retirado.")

SIMBOLO = {"subió": "▲ Subió", "bajó": "▼ Bajó", "igual": "= Igual"}


def estilo(tabla):
    """Rojo si subió, verde si bajó; negrita si la variación supera el umbral."""
    def fila(r):
        color = {"▲ Subió": "background-color: rgba(220,53,69,.18)",
                 "▼ Bajó": "background-color: rgba(25,135,84,.18)"}.get(r["Cambio"], "")
        grande = pd.notna(r["Diferencia (%)"]) and abs(r["Diferencia (%)"]) >= umbral
        return [color + ("; font-weight: 700" if grande else "")] * len(r)
    return tabla.style.apply(fila, axis=1)


COLS = {"comercio": "Comercio", "nombre": "Producto", "marca": "Marca", "precio_antes": "Precio anterior (COP)",
        "precio_despues": "Precio nuevo (COP)", "diferencia_cop": "Diferencia (COP)",
        "diferencia_pct": "Diferencia (%)", "url": "Anuncio"}
CONF = {"Anuncio": st.column_config.LinkColumn("Anuncio", display_text="Ver"),
        "Precio anterior (COP)": st.column_config.NumberColumn(format="$ %d"),
        "Precio nuevo (COP)": st.column_config.NumberColumn(format="$ %d"),
        "Diferencia (COP)": st.column_config.NumberColumn(format="%+d"),
        "Diferencia (%)": st.column_config.NumberColumn(format="%+.1f %%")}

t1, t2, t3, t4 = st.tabs(["Cambios de precio", "Nuevos", "Dejaron de observarse", "Agotados según el sitio"])

with t1:
    cam = df[df["estado"].isin(SIMBOLO)].copy()
    if cam.empty:
        st.info("Ningún anuncio tiene precio en ambas ejecuciones.")
    else:
        cam["Cambio"] = cam["estado"].map(SIMBOLO)
        cam = cam.rename(columns=COLS)[list(COLS.values()) + ["Cambio"]]
        solo_var = st.checkbox("Mostrar solo los que cambiaron", value=True)
        if solo_var:
            cam = cam[cam["Cambio"] != "= Igual"]
        st.dataframe(estilo(cam), hide_index=True, use_container_width=True, column_config=CONF)
        st.download_button("Descargar CSV", cam.to_csv(index=False).encode("utf-8-sig"),
                           file_name="cambios_precio.csv", mime="text/csv")

with t2:
    x = df[df["estado"] == "nuevo"][["comercio", "nombre", "marca", "precio_despues", "url"]]
    st.dataframe(x.rename(columns=COLS), hide_index=True, use_container_width=True, column_config=CONF)
with t3:
    x = df[df["estado"] == "no observado"][["comercio", "nombre", "marca", "precio_antes", "url"]]
    st.caption("No aparecieron en la ejecución nueva; sin más evidencia no se interpretan como agotados ni retirados.")
    st.dataframe(x.rename(columns=COLS), hide_index=True, use_container_width=True, column_config=CONF)
with t4:
    x = df[df["estado"] == "agotado"][["comercio", "nombre", "marca", "precio_antes", "url"]]
    st.caption("El sitio los marca como agotados en la ejecución nueva.")
    st.dataframe(x.rename(columns=COLS), hide_index=True, use_container_width=True, column_config=CONF)
