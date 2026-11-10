"""Página Canasta: costo por comercio y costo mínimo comprando cada producto donde es más barato."""
import streamlit as st

import analisis as A
import servicios as sv
import ui
import validacion as V


def cuerpo():
    st.title("Canasta de compra")
    ui.banner_datos()
    ejecs = sv.consultar("ejecuciones")
    utiles = ejecs[ejecs["estado"] != "fallida"]
    prods = sv.consultar("productos_comparables")
    if utiles.empty or prods.empty:
        ui.sin_datos("Aún no hay productos comparables.")
        return
    ids = utiles["ejecucion_id"].tolist()
    defecto = sv.consultar("ultima_ejecucion_completa") or ids[0]
    ejec = st.selectbox("Ejecución (todos los precios salen de la misma)", ids, index=ids.index(defecto),
                        format_func=lambda i: f"{A.etiqueta_ejecucion(i)} · {utiles.loc[utiles['ejecucion_id'] == i, 'estado'].iloc[0]}",
                        key="k_ejec")
    nombres = prods["nombre_std"].tolist()
    elegidos = st.multiselect("Productos comparables", nombres, key="k_prods", placeholder="Elige uno o más productos")
    if not elegidos:
        st.info("Elige al menos un producto para calcular la canasta.")
        return
    items = {}
    st.markdown("**Cantidad de cada producto**")
    for n in elegidos:
        pid = int(prods.loc[prods["nombre_std"] == n, "producto_id"].iloc[0])
        try:
            items[pid] = V.validar_cantidad(st.number_input(n, 1, 99, 1, 1, key=f"k_cant_{pid}"))
        except ValueError as e:
            st.error(str(e))
            return
    totales = sv.consultar("canasta_totales", ejec, items)
    minimo = sv.consultar("canasta_minimo", ejec, items)
    r = A.resumen_canasta(totales, minimo, len(items))

    st.subheader(f"Costo por comercio · ejecución {A.etiqueta_ejecucion(ejec)}")
    cols = st.columns(max(1, len(totales)))
    for col, (_, fila) in zip(cols, totales.iterrows()):
        with col:
            if fila["total"] is not None and fila["total"] == fila["total"]:
                ui.tarjeta(fila["comercio"], A.cop(fila["total"]), "canasta completa · COP")
            else:
                ui.tarjeta(fila["comercio"], "Incompleta", f"le faltan {int(fila['n_faltantes'])} de {int(fila['n_seleccionados'])} producto(s): no se muestra total")
    if r["mejor_unico"]:
        st.success(f"Comprando todo en un solo comercio, el más barato es **{' / '.join(r['mejor_unico'])}** "
                   f"({A.cop(r['costo_mejor_unico'])}).")
    else:
        st.warning("Ningún comercio tiene todos los productos elegidos en esta ejecución.")

    st.subheader("Comprando cada producto donde es más barato")
    if r["costo_minimo"] is None:
        st.warning(f"No se calcula: {r['productos_sin_precio']} producto(s) no tienen precio en ningún comercio en esta ejecución.")
    else:
        st.metric("Costo mínimo de la canasta", A.cop(r["costo_minimo"]))
        if r["ahorro_vs_mejor_unico"] is not None:
            st.markdown(f"Ahorro frente al mejor comercio único: **{A.cop(r['ahorro_vs_mejor_unico'])}** "
                        f"({A.pct(r['ahorro_pct_vs_mejor_unico'])}). " +
                        ("Con empates o si un solo comercio ya es el más barato en todo, el ahorro es 0." if r["ahorro_vs_mejor_unico"] == 0 else ""))
        for c, v in r["ahorro_vs_cada_comercio"].items():
            st.caption(f"Ahorro frente a comprar todo en {c}: {A.cop(v)}")
        st.dataframe(minimo.rename(columns={"nombre_std": "Producto", "cantidad": "Cantidad", "precio_minimo": "Precio mínimo (COP)",
                                            "subtotal": "Subtotal (COP)", "comercios": "Dónde (empates incluidos)"}), hide_index=True)
    st.warning(A.ADVERTENCIA_CANASTA)


ui.ejecutar_seguro(cuerpo)
