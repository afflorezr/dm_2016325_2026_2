import pandas as pd
import plotly.express as px
import streamlit as st

import componentes as ui
import datos_cache as dc

st.title("Canasta de productos")
st.caption("Elija productos comparables y la cantidad de cada uno. Todos los precios salen de una misma ejecución.")

corr = dc.corridas()
catalogo = dc.comparables()
etiquetas = {ui.etiqueta_corrida(fila): int(fila["id_corrida"]) for _, fila in corr.iterrows()}

c1, c2 = st.columns([1, 1])
with c1:
    id_corrida = etiquetas[st.selectbox("Ejecución", list(etiquetas), index=0)]
with c2:
    incluir_agotados = st.toggle("Considerar disponibles los productos agotados según el sitio", value=False,
                                 help="Por defecto, un producto agotado cuenta como faltante en ese comercio.")

nombres = dict(zip(catalogo["nombre_estandar"] + " · " + catalogo["presentacion_estandar"], catalogo["id_producto_comun"]))
elegidos = st.multiselect("Productos comparables", list(nombres), default=list(nombres)[:3],
                          placeholder="Elija uno o más productos")
if not elegidos:
    st.info("Elija al menos un producto para calcular la canasta.", icon=":material/shopping_basket:")
    st.stop()

base = pd.DataFrame({"Producto": elegidos, "Cantidad": [1] * len(elegidos)})
editado = st.data_editor(base, hide_index=True, width="stretch", disabled=["Producto"],
                         column_config={"Cantidad": st.column_config.NumberColumn("Cantidad", min_value=1, max_value=20, step=1)})
items = tuple((nombres[p], int(q)) for p, q in zip(editado["Producto"], editado["Cantidad"].fillna(1)))

r = dc.canasta(id_corrida, items, incluir_agotados)
por_com = r["por_comercio"]

st.warning("El resultado no incluye costos de envío, mínimos de compra ni condiciones de las promociones; "
           "los precios corresponden al momento de la captura.", icon=":material/info:")

k1, k2, k3 = st.columns(3)
mejor = r["comercio_mas_barato"]
with k1:
    ui.tarjeta("Costo mínimo (compra óptima)",
               ui.cop(r["total_optimo"]) if r["total_optimo"] is not None else "No disponible",
               "COP · cada producto donde es más barato; puede implicar varios comercios" if r["total_optimo"] is not None
               else "Algún producto no está disponible en ningún comercio")
with k2:
    ui.tarjeta("Mejor comercio único", mejor["comercio"] if mejor else "Ninguno",
               f"Canasta completa por {ui.cop(mejor['total_cop'])} COP" if mejor else "Ningún comercio tiene todos los productos")
with k3:
    ui.tarjeta("Ahorro vs. un solo comercio",
               ui.cop(r["ahorro_vs_un_comercio"]) if r["ahorro_vs_un_comercio"] is not None else "—",
               f"COP frente a {mejor['comercio']}" if mejor and r["ahorro_vs_un_comercio"] is not None
               else "Requiere al menos un comercio con la canasta completa")

st.subheader("Costo de la canasta en cada comercio")
vista = por_com.assign(
    total=por_com["total_cop"],
    situacion=por_com.apply(lambda f: "Canasta completa" if pd.notna(f["total_cop"])
                            else f"Faltan: {f['faltantes']}", axis=1))
cols = ["comercio", "productos_disponibles", "productos_canasta", "total", "situacion"]
if "ahorro_optimo_vs_comercio_cop" in vista.columns:
    cols.insert(4, "ahorro_optimo_vs_comercio_cop")
st.dataframe(ui.formato_tabla(vista[cols], cop_cols=["total", "ahorro_optimo_vs_comercio_cop"]), hide_index=True, width="stretch",
             column_config={"comercio": "Comercio", "productos_disponibles": "Productos disponibles",
                            "productos_canasta": "Productos en la canasta", "total": "Total (COP)",
                            "ahorro_optimo_vs_comercio_cop": "Ahorro de la compra óptima (COP)",
                            "situacion": st.column_config.TextColumn("Situación", width="large")})
st.caption("Si a un comercio le falta algún producto no se muestra un total incompleto: se indica qué falta.")

completos = vista.dropna(subset=["total"])
if not completos.empty:
    fig = px.bar(completos, x="comercio", y="total", color="comercio", text="total",
                 color_discrete_map=ui.COLORES_COMERCIO, category_orders={"comercio": ui.ORDEN_COMERCIOS},
                 labels={"comercio": "Comercio", "total": "Total de la canasta (COP)"})
    fig.update_traces(texttemplate="$ %{text:,.0f}", textposition="outside", cliponaxis=False)
    if r["total_optimo"] is not None:
        fig.add_hline(y=r["total_optimo"], line_dash="dash", line_color="#334155",
                      annotation_text=f"Compra óptima: {ui.cop(r['total_optimo'])}", annotation_position="bottom right")
    fig.update_yaxes(tickprefix="$ ")
    st.plotly_chart(ui.estilo_figura(fig, "Total de la canasta por comercio (solo canastas completas)",
                                     f"COP · Ejecución {id_corrida}", alto=380), width="stretch")

st.subheader("Compra óptima: dónde comprar cada producto")
det = r["detalle_optimo"]
st.dataframe(ui.formato_tabla(det, cop_cols=["precio_unitario_cop", "subtotal_cop"]), hide_index=True, width="stretch",
             column_config={"producto": st.column_config.TextColumn("Producto", width="large"), "cantidad": "Cantidad",
                            "precio_unitario_cop": "Precio mínimo (COP)", "subtotal_cop": "Subtotal (COP)",
                            "comprar_en": "Comprar en (empates: todos)"})
ui.nota_fecha_datos()
