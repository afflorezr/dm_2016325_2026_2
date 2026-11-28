"""Página Resumen: indicadores (§7.3) y los cuatro gráficos (§7.4)."""
from dataclasses import replace

import pandas as pd
import plotly.express as px
import streamlit as st

import db
import interfaz

st.title("Comparador de precios de antiinfecciosos")
st.markdown("Precios de **medicamentos antiinfecciosos de uso sistémico** (antibióticos, antivirales, "
            "antimicóticos y antiparasitarios) en La Rebaja Virtual, Locatel y Droguerías Cafam, "
            "recolectados con el scraper del curso. Todos los precios están en **pesos colombianos "
            "(COP)** e incluyen IVA, tal como los publica cada sitio.")

with interfaz.protegido():
    interfaz.fecha_de_los_datos()
    f = interfaz.filtros_activos()
    periodo = interfaz.describir_periodo(f)
    conteos = db.conteos_por_comercio(f)
    if conteos.empty:
        interfaz.sin_datos()
        st.stop()

    # Ejecución de referencia para los cambios de precio
    ejecucion_cambios = f.id_ejecucion or db.ultima_ejecucion_en_rango(f.fecha_desde, f.fecha_hasta)
    cambios = (db.cambios_en_ejecucion(ejecucion_cambios, f.comercios) if ejecucion_cambios
               else pd.DataFrame(columns=["comercio", "subieron", "bajaron", "cambios"]))
    # Observaciones acumuladas: con una ejecución elegida se cuentan todas las ejecuciones
    historial = db.observaciones_por_comercio(replace(f, id_ejecucion=None) if f.id_ejecucion else f)
    ahorro = db.ahorro_por_producto(f)
    medianas = db.mediana_por_subcategoria(f)
    ultima = db.ultima_ejecucion()

    # ---------------- Indicadores ----------------
    st.subheader("Indicadores")
    st.caption(f"Periodo: {periodo}. Los indicadores respetan los filtros de la barra lateral.")
    c1, c2, c3, c4 = st.columns(4)
    productos = int(conteos["productos"].sum())
    c1.metric("Productos observados", interfaz.numero(productos), border=True,
              help="Anuncios distintos (un SKU de un comercio) con observación en el periodo.")
    c1.caption(" · ".join(f"{r.comercio}: {interfaz.numero(r.productos)}" for r in conteos.itertuples())
               + " (anuncios)")

    con_precio = conteos["con_precio"].sum()
    pct = 100 * conteos["en_promocion"].sum() / con_precio if con_precio else None
    c2.metric("Productos en promoción", f"{interfaz.numero(pct, 1)} %" if pct is not None else "—",
              border=True, help="Proporción de anuncios con precio menor que el precio de lista.")
    c2.caption(" · ".join(f"{r.comercio}: {interfaz.numero(r.pct_promocion, 1)} %"
                          for r in conteos.itertuples()) + " (% de anuncios con precio)")

    if ahorro.empty:
        c3.metric("Ahorro máximo", "—", border=True)
        c3.caption("Ningún producto comparable con precio en dos o más comercios.")
    else:
        top = ahorro.iloc[0]
        c3.metric("Ahorro máximo", interfaz.cop(top["ahorro"]), border=True,
                  help="Mayor diferencia de precio de una misma presentación comparable (P01 a P10) "
                       "entre el comercio más caro y el más barato. Solo productos disponibles.")
        c3.caption(f"COP · {top['id_producto']} {top['producto']}: más barato en {top['mas_barato']} "
                   f"({interfaz.cop(top['minimo'])}), más caro en {top['mas_caro']} "
                   f"({interfaz.cop(top['maximo'])}).")

    total_cambios = int(cambios["cambios"].sum()) if not cambios.empty else 0
    c4.metric("Cambios de precio", interfaz.numero(total_cambios), border=True,
              help="Anuncios cuyo precio cambió frente a su observación anterior.")
    if ejecucion_cambios:
        c4.caption(f"anuncios · ejecución {ejecucion_cambios}: "
                   f"{interfaz.numero(cambios['subieron'].sum())} subieron, "
                   f"{interfaz.numero(cambios['bajaron'].sum())} bajaron")

    c5, c6, c7, c8 = st.columns(4)
    c5.metric("Última ejecución", interfaz.fecha_legible(ultima["inicio"].max(), con_hora=False)
              if not ultima.empty else "—", border=True,
              help="Fecha de la ejecución más reciente de cada comercio y su estado.")
    c5.caption(" · ".join(f"{r.comercio}: {interfaz.fecha_legible(r.inicio, con_hora=False)}, "
                          f"{r.estado}" for r in ultima.itertuples()))

    c6.metric("Observaciones registradas", interfaz.numero(historial["observaciones"].sum()),
              border=True, help="Precios guardados (una observación por anuncio y ejecución).")
    c6.caption(" · ".join(f"{r.comercio}: {interfaz.numero(r.observaciones)}"
                          for r in historial.itertuples())
               + (" · todas las ejecuciones" if f.id_ejecucion else f" · {periodo}"))

    if medianas.empty:
        c7.metric("Mediana del precio", "—", border=True)
    else:
        principal = medianas.sort_values("productos", ascending=False).iloc[0]
        c7.metric("Mediana del precio", interfaz.cop(principal["mediana"]), border=True,
                  help="Mediana del precio por subcategoría. Aquí, la subcategoría con más "
                       "anuncios; la tabla completa está en 'Indicadores por comercio y mediana "
                       "por subcategoría'.")
        c7.caption(f"COP · {principal['subcategoria']} ({interfaz.numero(principal['productos'])} "
                   "anuncios con precio)")

    agotados = int(conteos["agotados"].sum())
    c8.metric("Productos agotados", interfaz.numero(agotados), border=True,
              help="Anuncios que el sitio publica como agotados. Casi todos conservan el precio "
                   "publicado, pero no cuentan para el ahorro, el precio por unidad, '¿Dónde es "
                   "más barato?' ni la canasta, porque no se pueden comprar.")
    c8.caption(" · ".join(f"{r.comercio}: {interfaz.numero(r.agotados)}" for r in conteos.itertuples())
               + " (anuncios)")

    with st.expander("Indicadores por comercio y mediana por subcategoría", expanded=False):
        tabla = (conteos[["comercio", "productos", "con_precio", "agotados", "en_promocion",
                          "pct_promocion"]]
                 .merge(cambios[["comercio", "subieron", "bajaron"]], on="comercio", how="left"))
        interfaz.tabla(tabla, hide_index=True, width="stretch", column_config={
            "comercio": "Comercio", "productos": "Productos (anuncios)",
            "con_precio": "Con precio", "agotados": "Agotados", "en_promocion": "En promoción",
            "pct_promocion": "% en promoción",
            "subieron": "Precio subió", "bajaron": "Precio bajó"})
        interfaz.tabla(medianas, hide_index=True, width="stretch", column_config={
            "subcategoria": "Subcategoría", "productos": "Anuncios con precio",
            "mediana": interfaz.columna_cop("Mediana del precio (COP)")})

    # ---------------- Gráficos ----------------
    st.subheader("Gráficos")
    t1, t2, t3, t4 = st.tabs(["Evolución del precio", "Precio por unidad",
                              "Distribución de precios", "¿Dónde es más barato?"])

    with t1:
        st.markdown("**¿Cómo ha cambiado el precio de una presentación comparable en cada comercio?**")
        catalogo = db.productos_comparables()
        nombres = dict(zip(catalogo["id_producto"], catalogo["descripcion"]))
        elegido = st.selectbox("Presentación comparable", list(nombres),
                               format_func=lambda p: f"{p} · {nombres[p]}", key="g_producto")
        serie = db.evolucion_precio(elegido, f.comercios, f.fecha_desde, f.fecha_hasta)
        if serie.empty:
            interfaz.sin_datos("Esta presentación no tiene precios en los comercios o fechas elegidos.")
        else:
            serie["fecha"] = pd.to_datetime(serie["fecha_consulta"].str[:19])
            fig = px.line(serie, x="fecha", y="precio", color="comercio", markers=True,
                          color_discrete_map=interfaz.COLORES,
                          category_orders={"comercio": interfaz.ORDEN_COMERCIOS},
                          custom_data=["id_ejecucion", "precio_lista"])
            fig.update_traces(line_width=2, marker_size=9,
                              hovertemplate="%{x|%d/%m/%Y %H:%M}<br>Precio: $ %{y:,.0f}"
                                            "<br>Precio de lista: $ %{customdata[1]:,.0f}"
                                            "<br>%{customdata[0]}<extra>%{fullData.name}</extra>")
            interfaz.estilo(fig, "Precio (COP)", "Fecha de consulta (hora de Colombia)",
                            formato_x="%d/%m/%Y")
            st.caption("Usa todas las ejecuciones (no solo la elegida en la barra lateral). "
                       "Cada punto es una ejecución.")
            interfaz.mostrar_grafico(fig, serie.drop(columns=["fecha"]), {
                "precio": interfaz.columna_cop("Precio (COP)"),
                "precio_lista": interfaz.columna_cop("Precio de lista (COP)"),
                "precio_unitario": interfaz.columna_cop("Precio por unidad (COP)")})

    with t2:
        st.markdown("**¿Cuánto cuesta cada unidad de contenido en cada comercio?** "
                    "Solo presentaciones comparables (P01 a P10) disponibles, sin mezclar unidades "
                    "distintas.")
        unitario = db.precio_unitario_comparables(f)
        if unitario.empty:
            interfaz.sin_datos("No hay presentaciones comparables con los filtros elegidos.")
        else:
            unidades = list(dict.fromkeys(unitario["unidad_normalizada"]))
            pestanas = st.tabs([interfaz.UNIDADES.get(u, u) for u in unidades]) if len(unidades) > 1 \
                else [st.container()]
            for unidad, pestana in zip(unidades, pestanas):
                datos = unitario[unitario["unidad_normalizada"] == unidad].copy()
                datos["presentacion"] = datos["id_producto"] + " · " + datos["producto"].str.slice(0, 45)
                with pestana:
                    fig = px.bar(datos, x="precio_unitario", y="presentacion", color="comercio",
                                 orientation="h", barmode="group",
                                 color_discrete_map=interfaz.COLORES,
                                 category_orders={"comercio": interfaz.ORDEN_COMERCIOS},
                                 custom_data=["precio", "contenido_total"])
                    fig.update_traces(hovertemplate="%{y}<br>$ %{x:,.0f} por " + unidad +
                                      "<br>Precio: $ %{customdata[0]:,.0f} por "
                                      "%{customdata[1]:.0f} " + unidad +
                                      "<extra>%{fullData.name}</extra>")
                    interfaz.estilo(fig, None, interfaz.UNIDADES.get(unidad, unidad),
                                    formato_y=None, formato_x=",.0f")
                    fig.update_yaxes(title_text="", autorange="reversed")
                    fig.update_layout(height=max(320, 70 * datos["id_producto"].nunique()))
                    st.caption(f"Unidad: {interfaz.UNIDADES.get(unidad, unidad)}. {periodo}.")
                    interfaz.mostrar_grafico(fig, datos.drop(columns=["presentacion"]), {
                        "precio": interfaz.columna_cop("Precio (COP)"),
                        "precio_unitario": interfaz.columna_cop(f"Precio por {unidad} (COP)")})

    with t3:
        st.markdown("**¿Cómo se reparten los precios de la categoría en cada comercio?**")
        precios = db.precios_para_distribucion(f)
        if precios.empty:
            interfaz.sin_datos()
        else:
            fig = px.box(precios, x="comercio", y="precio", color="comercio", points="outliers",
                         color_discrete_map=interfaz.COLORES, log_y=True, hover_data=["nombre"],
                         category_orders={"comercio": interfaz.ORDEN_COMERCIOS})
            interfaz.estilo(fig, "Precio (COP, escala logarítmica)", "", leyenda=False)
            st.caption(f"{periodo}. La escala es logarítmica porque los precios van de unos pocos "
                       "miles a varios millones de pesos. La línea de cada caja es la mediana.")
            resumen = (precios.groupby("comercio")["precio"]
                       .describe(percentiles=[0.25, 0.5, 0.75]).reset_index())
            estadisticos = {"mean": "Promedio", "std": "Desviación estándar", "min": "Mínimo",
                            "25%": "Percentil 25", "50%": "Mediana", "75%": "Percentil 75",
                            "max": "Máximo"}
            interfaz.mostrar_grafico(
                fig, resumen,
                {"comercio": "Comercio", "count": "Anuncios con precio",
                 **{c: f"{nombre} (COP)" for c, nombre in estadisticos.items()}},
                columnas_cop=tuple(estadisticos))

    with t4:
        # DECISIÓN (Marlon): gráfico de libre elección. Propuesta por defecto; la pregunta y su
        # justificación van en el README.md (§7.4.4).
        st.markdown("**Si busco exactamente el mismo producto (mismo código de barras) en los "
                    "comercios elegidos, ¿dónde suele estar más barato?**")
        ganadores = db.mas_barato_mismo_ean(f)
        if ganadores.empty:
            interfaz.sin_datos("No hay productos disponibles con el mismo código de barras y "
                               "precio en todos los comercios elegidos. Elige al menos dos "
                               "comercios.")
        else:
            total = int(ganadores["productos_comparados"].iloc[0])
            ganadores["porcentaje"] = 100 * ganadores["productos"] / total
            fig = px.bar(ganadores, x="mas_barato", y="productos", color="mas_barato",
                         color_discrete_map=interfaz.COLORES, text="productos",
                         category_orders={"mas_barato": interfaz.ORDEN_COMERCIOS},
                         custom_data=["porcentaje"])
            fig.update_traces(textposition="outside",
                              hovertemplate="%{x}: %{y} productos (%{customdata[0]:.1f} %)<extra></extra>")
            interfaz.estilo(fig, "Productos en que es el más barato", "", leyenda=False)
            st.caption(f"{total} productos disponibles con el mismo EAN válido y precio en todos "
                       f"los comercios elegidos · {periodo}. 'Empate' = dos o más comercios con el mismo precio "
                       "mínimo.")
            interfaz.mostrar_grafico(fig, ganadores, {
                "mas_barato": "Más barato en", "productos": "Productos",
                "productos_comparados": "Productos comparados",
                "porcentaje": "% de los comparados"})
