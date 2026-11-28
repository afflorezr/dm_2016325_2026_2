"""
paginas/canasta.py — Taller 2: página "Canasta" (§8.3).

El usuario elige productos comparables y la cantidad de cada uno. Con precios de UNA ejecución se calcula (en SQL,
db.calcular_canasta):
  * el costo de la canasta en cada comercio, solo si el comercio tiene todos los productos disponibles; si falta
    alguno se indica cuál, en lugar de mostrar un total incompleto;
  * el costo mínimo comprando cada producto donde es más barato y el ahorro frente al mejor comercio único.
Esta página usa sus propios selectores; los filtros del panel lateral no se aplican aquí. Sin SQL.
"""
import streamlit as st

import componentes as cp

st.title("Canasta de productos")
st.warning("El resultado **no incluye** costos de envío, montos mínimos de compra ni condiciones de las promociones "
           "(por ejemplo, «2×1» o descuentos con tarjeta). Solo se usan productos **disponibles** en cada comercio: "
           "un producto agotado cuenta como faltante.", icon="⚠️")
st.caption("Esta página usa sus propios selectores; los filtros del panel lateral no se aplican aquí.")

comparables = cp.obtener("listar_comparables")
ejecuciones = cp.obtener("listar_ejecuciones")
if comparables is None or ejecuciones is None or comparables.empty:
    cp.sin_datos("No hay productos comparables en la base.")
    st.stop()
nombres = dict(zip(comparables["id_producto_comun"],
                   comparables["producto"].str.title() + " · " + comparables["contenido"].map("{:g}".format)
                   + " " + comparables["unidad_norm"]))

# [CAMBIO]: elección de la ejecución, los productos y sus cantidades (1 a 99).
id_ejecucion = st.selectbox("Precios de la ejecución", list(ejecuciones["id_ejecucion"]),
                            format_func=cp.formato_fecha)
elegidos = st.multiselect("Productos de la canasta", list(nombres), format_func=nombres.get,
                          default=list(nombres)[:3], placeholder="Elija uno o más productos comparables")
if not elegidos:
    cp.sin_datos("Elija al menos un producto para calcular la canasta.")
    st.stop()
cantidades = {}
columnas = st.columns(min(len(elegidos), 4))
for i, id_producto in enumerate(elegidos):
    cantidades[id_producto] = columnas[i % len(columnas)].number_input(
        nombres[id_producto][:60], min_value=1, max_value=99, value=1, step=1, key=f"cantidad_{id_producto}")

resultado = cp.obtener("calcular_canasta", id_ejecucion, cantidades)
if resultado is None:
    st.stop()
por_comercio, detalle, resumen = resultado["por_comercio"], resultado["detalle"], resultado["resumen"]
fecha = cp.formato_fecha(id_ejecucion)

# [CAMBIO]: costo mínimo, mejor comercio único y ahorro (o aviso si no se puede calcular).
k1, k2, k3 = st.columns(3)
costo_minimo = resumen["costo_minimo_cop"]
if costo_minimo is None or costo_minimo != costo_minimo:
    k1.error("No se puede calcular el costo mínimo: algún producto no está disponible en ningún comercio.")
else:
    cp.tarjeta(k1, "Costo mínimo", cp.formato_cop(costo_minimo),
               f"COP comprando cada producto donde es más barato · ejecución del {fecha}")
mejor = resumen["mejor_total_un_comercio_cop"]
if mejor is None or mejor != mejor:
    k2.warning("Ningún comercio tiene todos los productos disponibles: no hay total en un solo comercio.")
else:
    cp.tarjeta(k2, "Mejor comercio único", cp.formato_cop(mejor), f"COP en {resumen['mejor_comercio']}")
    if costo_minimo is not None and costo_minimo == costo_minimo:
        cp.tarjeta(k3, "Ahorro dividiendo la compra", cp.formato_cop(resumen["ahorro_cop"]),
                   "COP frente a comprar todo en el mejor comercio único")

# [CAMBIO]: total por comercio: si falta un producto se dice cuál, en lugar de un total incompleto.
st.subheader("Costo de la canasta en cada comercio")
for fila in por_comercio.itertuples():
    nombre = cp.nombre_con_color(fila.comercio)
    if fila.total_cop is None or fila.total_cop != fila.total_cop:
        st.markdown(f"{nombre}: **canasta incompleta**, tiene {fila.productos_encontrados} de "
                    f"{fila.productos_pedidos} productos disponibles. Falta: {fila.faltantes.title()}.")
    else:
        st.markdown(f"{nombre}: **{cp.formato_cop(fila.total_cop)}** (COP, {fila.productos_pedidos} productos)")

# [CAMBIO]: detalle por producto: dónde comprar cada uno (en empate, todos los comercios empatados).
st.subheader("Dónde comprar cada producto")
detalle = detalle.assign(producto=detalle["producto"].str.title())
st.dataframe(detalle[["producto", "cantidad", "precio_min_cop", "subtotal_min_cop", "donde_comprar"]],
             hide_index=True, width="stretch",
             column_config={"producto": "Producto", "cantidad": "Cantidad",
                            "precio_min_cop": st.column_config.NumberColumn("Precio más bajo (COP)", format="$ %,.0f"),
                            "subtotal_min_cop": st.column_config.NumberColumn("Subtotal (COP)", format="$ %,.0f"),
                            "donde_comprar": "Dónde comprarlo (más barato)"})
st.caption(f"Precios de la ejecución del {fecha}. Si dos comercios empatan en el precio más bajo, aparecen ambos.")
