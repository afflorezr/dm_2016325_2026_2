# Clase 10: explorador de arriendos en Streamlit
# Ejecutar con: streamlit run app.py

import altair as alt
import numpy as np
import pandas as pd
import streamlit as st

st.set_page_config(page_title="Explorador de arriendos", layout="wide")


@st.cache_data
def cargar_datos(ruta="arriendos.csv"):
    return pd.read_csv(ruta)


def asimetria(x):
    # misma fórmula del informe en R (momentos poblacionales)
    d = x - x.mean()
    return (d ** 3).mean() / (d ** 2).mean() ** 1.5


def pesos(x):
    return f"${x:,.0f}".replace(",", ".")


def porcentaje(x, dec=1):
    return f"{100 * x:.{dec}f} %".replace(".", ",")


arriendos = cargar_datos()

# Sidebar: filtros ----------------------------------------------------------

st.sidebar.header("Filtros")
ciudades = st.sidebar.multiselect("Ciudad", sorted(arriendos["ciudad"].unique()),
                                  default=sorted(arriendos["ciudad"].unique()))
estratos = st.sidebar.slider("Rango de estrato", 1, 6, (1, 6))
umbral = st.sidebar.slider("Umbral de asimetría para usar la mediana", 0.1, 2.0, 0.5, 0.1,
                           help="Convención práctica de clase: 0,5")

datos = arriendos[arriendos["ciudad"].isin(ciudades)
                  & arriendos["estrato"].between(*estratos)]

st.title("Explorador de arriendos")
st.caption(f"{len(datos):,} registros seleccionados de {len(arriendos):,}".replace(",", "."))

if len(datos) < 5:
    st.warning("Hay muy pocos registros con estos filtros para calcular las medidas.")
    st.stop()

x = datos["arriendo"]

# Reglas automáticas ----------------------------------------------------------

asim = asimetria(x)
media, mediana, de = x.mean(), x.median(), x.std()
q1, q3 = x.quantile(0.25), x.quantile(0.75)
iqr = q3 - q1
cv = de / media
lim_inf, lim_sup = q1 - 1.5 * iqr, q3 + 1.5 * iqr
atipicos = datos[(x < lim_inf) | (x > lim_sup)].sort_values("arriendo", ascending=False)

usar_mediana = abs(asim) > umbral

c1, c2, c3 = st.columns(3)
if usar_mediana:
    c1.metric("Arriendo típico (mediana)", pesos(mediana), help=f"IQR: {pesos(iqr)}")
else:
    c1.metric("Arriendo típico (media)", pesos(media), help=f"DE: {pesos(de)}")
c2.metric("Coeficiente de variación", porcentaje(cv))
c3.metric("Atípicos (regla del IQR)", len(atipicos))

if usar_mediana:
    st.info(f"La asimetría es {asim:.2f}".replace(".", ",")
            + f", mayor que {umbral:.1f}".replace(".", ",") + " en valor absoluto: la distribución está sesgada, "
            "así que el centro se reporta con la mediana y la dispersión con el IQR "
            f"({pesos(iqr)}). La media ({pesos(media)}) se deja arrastrar por los valores extremos.")
else:
    st.info(f"La asimetría es {asim:.2f}".replace(".", ",")
            + f", menor que {umbral:.1f}".replace(".", ",") + " en valor absoluto: la distribución es casi simétrica, "
            f"así que se reporta la media ({pesos(media)}) con su desviación estándar ({pesos(de)}).")

if cv > 0.30:
    st.warning(f"El CV es {porcentaje(cv)}, mayor que 30 %: el grupo es heterogéneo y un solo "
               "valor típico lo resume mal. Conviene filtrar más (por ciudad o estrato).")

# Pestañas ------------------------------------------------------------------

tab1, tab2, tab3 = st.tabs(["Histograma", "Atípicos", "Correlaciones"])

with tab1:
    lineas = pd.DataFrame({"medida": ["Media", "Mediana"], "valor": [media, mediana]})
    histo = alt.Chart(datos).mark_bar(color="#006DAE", opacity=0.8).encode(
        x=alt.X("arriendo:Q", bin=alt.Bin(maxbins=40), title="Arriendo mensual (COP)"),
        y=alt.Y("count()", title="Registros"),
    )
    reglas = alt.Chart(lineas).mark_rule(size=2).encode(
        x="valor:Q",
        color=alt.Color("medida:N", scale=alt.Scale(domain=["Media", "Mediana"],
                                                    range=["#b2182b", "black"]),
                        title=None),
        tooltip=[alt.Tooltip("medida:N"), alt.Tooltip("valor:Q", format=",.0f")],
    )
    st.altair_chart(histo + reglas, width="stretch")
    st.caption(f"Media: {pesos(media)} · Mediana: {pesos(mediana)}")

with tab2:
    st.write(f"Se marcan como atípicos los arriendos fuera de [{pesos(lim_inf)}, {pesos(lim_sup)}]. "
             "Un atípico no es necesariamente un error: hay que revisarlo junto con el estrato y el área.")
    st.dataframe(atipicos, width="stretch", hide_index=True)
    st.download_button("Descargar atípicos (CSV)",
                       atipicos.to_csv(index=False).encode("utf-8"),
                       file_name="atipicos_arriendos.csv", mime="text/csv")

with tab3:
    variables = ["arriendo", "area_m2", "estrato", "antiguedad"]
    ordinales = {"estrato"}
    pearson = datos[variables].corr(method="pearson")
    spearman = datos[variables].corr(method="spearman")

    # regla: si alguna de las dos variables es ordinal se usa Spearman
    filas = []
    for a in variables:
        for b in variables:
            metodo = "Spearman" if ({a, b} & ordinales) else "Pearson"
            valor = spearman.loc[a, b] if metodo == "Spearman" else pearson.loc[a, b]
            filas.append({"x": a, "y": b, "correlacion": valor, "metodo": metodo})
    matriz = pd.DataFrame(filas)

    base = alt.Chart(matriz).encode(
        x=alt.X("x:N", sort=variables, title=None),
        y=alt.Y("y:N", sort=variables, title=None),
    )
    mapa = base.mark_rect().encode(
        color=alt.Color("correlacion:Q", scale=alt.Scale(scheme="redblue", domain=[-1, 1]),
                        title="Correlación"),
        tooltip=["x", "y", alt.Tooltip("correlacion:Q", format=".2f"), "metodo"],
    )
    texto = base.mark_text().encode(text=alt.Text("correlacion:Q", format=".2f"))
    st.altair_chart((mapa + texto).properties(height=380), width="stretch")
    st.caption("El estrato es ordinal, así que sus correlaciones se calculan con Spearman; "
               "las demás, con Pearson. Si Pearson y Spearman difieren mucho, revisar valores extremos.")
    st.dataframe(pd.DataFrame({
        "Pearson": pearson["arriendo"].drop("arriendo"),
        "Spearman": spearman["arriendo"].drop("arriendo"),
    }).round(2), width="stretch")
