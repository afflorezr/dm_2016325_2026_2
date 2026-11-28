"""Página Canasta: costo de una canasta de productos comparables por comercio (§8.3)."""
import plotly.express as px
import streamlit as st

import db
import interfaz

st.title("Canasta")
st.markdown("Elige presentaciones comparables y la cantidad de cada una. Con los precios de **una "
            "misma ejecución**, se calcula cuánto cuesta la canasta en cada comercio y cuánto se "
            "ahorra comprando cada producto donde es más barato.")
st.warning("El resultado **no incluye** costos de envío, mínimos de compra ni condiciones de las "
           "promociones (por ejemplo, límites por cliente o pago con tarjetas específicas).",
           icon=":material/info:")

with interfaz.protegido():
    interfaz.fecha_de_los_datos()
    ejecuciones = db.ejecuciones()
    filas = {f.id_ejecucion: f._asdict() for f in ejecuciones.itertuples()}
    ids = list(filas)
    por_defecto = db.ejecucion_por_defecto()
    id_ejecucion = st.selectbox("Ejecución (precios del mismo momento)", ids,
                                index=ids.index(por_defecto) if por_defecto in ids else 0,
                                format_func=lambda i: interfaz.etiqueta_ejecucion(filas[i]))

    catalogo = db.productos_comparables()
    nombres = dict(zip(catalogo["id_producto"], catalogo["descripcion"]))
    elegidos = st.multiselect("Productos de la canasta", list(nombres), default=list(nombres)[:3],
                              format_func=lambda p: f"{p} · {nombres[p]}")
    if not elegidos:
        interfaz.sin_datos("Elige al menos un producto.")
        st.stop()

    st.markdown("**Cantidad de cada producto** (cajas o frascos)")
    columnas = st.columns(min(len(elegidos), 5))
    cantidades = {}
    for i, p in enumerate(elegidos):
        cantidades[p] = columnas[i % len(columnas)].number_input(
            f"{p}", min_value=1, max_value=db.CANTIDAD_MAXIMA, value=1, step=1, key=f"cant_{p}",
            help=nombres[p])

    resultado = db.canasta(id_ejecucion, cantidades)
    por_comercio = resultado.por_comercio

    # ---------------- Resultado principal ----------------
    c1, c2, c3 = st.columns(3)
    if resultado.mejores_comercios:
        mejor = por_comercio.dropna(subset=["total"]).iloc[0]
        c1.metric("Comercio único más barato", " / ".join(resultado.mejores_comercios), border=True)
        c1.caption(f"Total: {interfaz.cop(mejor['total'])} COP"
                   + (" (empate)" if len(resultado.mejores_comercios) > 1 else ""))
    else:
        c1.metric("Comercio único más barato", "—", border=True)
        c1.caption("Ningún comercio tiene todos los productos con precio.")
    c2.metric("Costo mínimo combinando comercios", interfaz.cop(resultado.costo_minimo), border=True)
    c2.caption("COP, comprando cada producto donde es más barato" if resultado.costo_minimo is not None
               else "Algún producto no tiene precio en ningún comercio.")
    c3.metric("Ahorro frente al mejor comercio único", interfaz.cop(resultado.ahorro), border=True)
    c3.caption("COP · 0 significa que comprar todo en un solo comercio ya es lo más barato"
               if resultado.ahorro is not None else "No se puede calcular: falta un total completo.")

    # ---------------- Total por comercio ----------------
    st.subheader("Total en cada comercio")
    incompletos = por_comercio[por_comercio["total"].isna()]
    for fila in incompletos.itertuples():
        st.info(f"**{fila.comercio}** no tiene precio para: {fila.faltantes}. No se muestra un total "
                "incompleto.", icon=":material/remove_shopping_cart:")
    completos = por_comercio.dropna(subset=["total"])
    if not completos.empty:
        fig = px.bar(completos, x="comercio", y="total", color="comercio", text="total",
                     color_discrete_map=interfaz.COLORES,
                     category_orders={"comercio": interfaz.ORDEN_COMERCIOS})
        fig.update_traces(texttemplate="$ %{y:,.0f}", textposition="outside",
                          hovertemplate="%{x}: $ %{y:,.0f}<extra></extra>")
        interfaz.estilo(fig, "Total de la canasta (COP)", "", leyenda=False)
        if resultado.costo_minimo is not None:
            fig.add_hline(y=resultado.costo_minimo, line_dash="dot", line_width=2,
                          line_color="#8c8378")
            st.caption("La línea punteada es el costo mínimo combinando comercios "
                       f"({interfaz.cop(resultado.costo_minimo)}).")
        fig.update_yaxes(range=[0, completos["total"].max() * 1.15])
        fig.update_layout(height=380)
        interfaz.mostrar_grafico(fig, por_comercio, {
            "comercio": "Comercio", "productos_con_precio": "Productos con precio",
            "productos_pedidos": "Productos pedidos",
            "total": interfaz.columna_cop("Total (COP)"),
            "sobrecosto_frente_al_minimo": interfaz.columna_cop("Pagas de más frente al mínimo (COP)"),
            "faltantes": "Faltan"})

    # ---------------- Detalle por producto ----------------
    st.subheader("Dónde comprar cada producto")
    interfaz.tabla(resultado.detalle, hide_index=True, width="stretch", column_config={
        "id_producto": "Producto", "producto": st.column_config.TextColumn("Presentación", width="large"),
        "cantidad": "Cantidad", "precio_minimo": interfaz.columna_cop("Precio mínimo (COP)"),
        "subtotal_minimo": interfaz.columna_cop("Subtotal (COP)"),
        "donde_comprar": st.column_config.TextColumn(
            "Más barato en", help="Si hay empate, aparecen todos los comercios con el precio mínimo.")})
    if not resultado.precios.empty:
        tabla = resultado.precios.pivot(index="id_producto", columns="comercio", values="precio")
        st.caption("Precio unitario de cada producto en cada comercio (COP). Vacío = sin precio o "
                   "agotado en esa ejecución.")
        interfaz.tabla(tabla.rename_axis("Producto").reset_index(),
                       columnas_cop=tuple(tabla.columns))
