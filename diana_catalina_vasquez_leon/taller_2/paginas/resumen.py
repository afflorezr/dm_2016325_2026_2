# -*- coding: utf-8 -*-
"""Página Resumen: filtros, indicadores, cuatro gráficos interactivos y tabla descargable."""
import pandas as pd
import plotly.express as px
import streamlit as st

import datos
import db
import ui

ui.verificar_base()
v = datos.version()
op = datos.opciones(v)

st.title("Comparador de precios · dermocosmética facial")
ui.aviso(f"Precios observados el <b>{ui.fecha_de_los_datos()}</b> (última ejecución). Moneda: pesos colombianos (COP). "
         "Los precios corresponden al momento de la captura y no incluyen envío.")

# ------------------------------------------------------------------ filtros (panel lateral)
with st.sidebar:
    st.header("Filtros")
    comercios = st.multiselect("Comercio", op["comercios"], default=op["comercios"], placeholder="Elige un comercio")
    subcats = st.multiselect("Subcategoría", op["subcategorias"], placeholder="Todas")
    marcas = st.multiselect("Marca", op["marcas"], placeholder="Todas")
    p_lo, p_hi = float(op["precio"][0] or 0), float(op["precio"][1] or 1)
    rango = st.slider("Rango de precio (COP)", p_lo, p_hi, (p_lo, p_hi), step=1000.0, format="$%d") if p_hi > p_lo else (p_lo, p_hi)
    solo_promo = st.checkbox("Solo promociones")
    solo_comp = st.checkbox("Solo productos comparables")
    no_obs = st.checkbox("Incluir anuncios no observados en la última ejecución",
                         help="Por defecto solo se muestran los anuncios vistos en la última ejecución. Al marcar esta casilla "
                              "se agregan los que ya no aparecieron, con su último precio conocido (no significa que estén agotados o retirados).")
    texto = st.text_input("Buscar en el nombre o la descripción", max_chars=db.MAX_TEXTO)
    try:
        texto = db.validar_texto(texto)
    except ValueError as e:
        st.error(str(e))
        texto = ""

if not comercios:
    st.warning("Selecciona al menos un comercio para ver resultados.")
    st.stop()

filtros = dict(comercios=tuple(comercios), subcategorias=tuple(subcats), marcas=tuple(marcas),
               pmin=rango[0], pmax=rango[1], solo_promocion=solo_promo, solo_comparables=solo_comp, texto=texto,
               incluir_no_observados=no_obs)
df = datos.productos(filtros, v)
ind = datos.indicadores(filtros, v)

if df.empty:
    ui.sin_datos()
    st.stop()

# ------------------------------------------------------------------ indicadores (calculados con SQL en db.py)
est = ind["estado_ultima_ejecucion"]
estados = est.estado.value_counts().to_dict() if len(est) else {}
ah = ind["ahorro_maximo"]
cam = ind["cambios_ultima"]
f1 = st.columns(3)
ui.tarjeta(f1[0], "Productos con estos filtros", f"{ind['total_productos']:,}".replace(",", "."),
           "anuncios observados en la última ejecución" if not no_obs else "anuncios · último precio conocido de cada uno")
ui.tarjeta(f1[1], "Comercios con datos", str(len(ind["por_comercio"])),
           " · ".join(f"{r.comercio}: {r.productos}" for r in ind["por_comercio"].itertuples()))
ui.tarjeta(f1[2], "Productos en promoción", f"{ui.num(ind['pct_promocion'])} %", "% de los productos filtrados")
f2 = st.columns(3)
ui.tarjeta(f2[0], "Última ejecución", ui.fecha_legible(est.fecha_inicio.min()) if len(est) else "—",
           " · ".join(f"{n} {k}" for k, n in estados.items()) or "sin ejecuciones")
ui.tarjeta(f2[1], "Ahorro máximo entre comercios",
           f"{ui.num(ah['ahorro_pct'])} %" if ah else "—",
           f"{ah['producto']} · {ui.cop(ah['ahorro_cop'])} (ejecución {ah['id_ejecucion'][5:13]})" if ah else "sin comparables")
ui.tarjeta(f2[2], "Cambios de precio en la última ejecución",
           f"{int(cam.suben.iloc[0])} ↑ · {int(cam.bajan.iloc[0])} ↓" if len(cam) else "—",
           "anuncios que subieron / bajaron" if len(cam) else "sin ejecución previa para comparar o sin cambios")

with st.expander("Mediana del precio por subcategoría (COP)"):
    med = ind["mediana_por_subcategoria"]
    if med.empty:
        ui.sin_datos("No hay subcategorías con estos filtros.")
    else:
        fig = px.bar(med, x="mediana", y="subcategoria", orientation="h", text=med.mediana.map(ui.cop),
                     labels={"mediana": "Mediana (COP)", "subcategoria": ""}, color_discrete_sequence=["#4F46E5"])
        fig.update_yaxes(autorange="reversed")
        ui.mostrar_grafico(ui.formato_figura(fig, "Mediana del precio por subcategoría", "COP · última observación de cada anuncio",
                                             alto=max(320, 34 * len(med) + 120)))

# ------------------------------------------------------------------ gráficos y tabla
t1, t2, t3, t4, t5 = st.tabs(["Evolución del precio", "Precio por unidad", "Distribución", "Oportunidad de ahorro", "Tabla"])
ej_comp = ind["ejecucion_comparables"]
ah_df = datos.ahorro(ej_comp, v) if ej_comp else pd.DataFrame()

with t1:                                                       # gráfico 1
    if ah_df.empty:
        ui.sin_datos("Aún no hay productos comparables con precios.")
    else:
        nombres = dict(zip(ah_df.id_producto_comun, ah_df.producto + " (" + ah_df.presentacion + ")"))
        pid = st.selectbox("Producto comparable", list(nombres), format_func=nombres.get)
        ev = datos.evolucion(pid, v)
        ev["fecha"] = pd.to_datetime(ev.fecha_consulta.str[:19])
        fig = px.line(ev, x="fecha", y="precio", color="comercio", markers=True, color_discrete_map=ui.COLORES,
                      category_orders={"comercio": ui.ORDEN}, labels={"precio": "Precio (COP)", "fecha": "Fecha de consulta"})
        fig.update_traces(marker=dict(size=9))
        ui.mostrar_grafico(ui.formato_figura(fig, nombres[pid], f"Una serie por comercio · {ev.id_ejecucion.nunique()} ejecuciones válidas"))
        st.caption("Cada punto es una ejecución del scraper. Las ejecuciones descartadas no se incluyen.")

with t2:                                                       # gráfico 2
    modo = st.radio("Comparar", ["Productos comparables", "Mismo producto en distintos tamaños"], horizontal=True)
    if not ej_comp:
        ui.sin_datos("Aún no hay productos comparables con precios.")
    elif modo == "Productos comparables":
        unidad = st.selectbox("Unidad de contenido (no se mezclan unidades)", datos.unidades(v))
        un = datos.unitario(unidad, ej_comp, v)
        if un.empty:
            ui.sin_datos(f"No hay productos comparables medidos en {unidad}.")
        else:
            fig = px.bar(un, x="producto", y="precio_unitario", color="comercio", barmode="group", color_discrete_map=ui.COLORES,
                         category_orders={"comercio": ui.ORDEN}, labels={"precio_unitario": f"COP por {unidad}", "producto": ""})
            ui.mostrar_grafico(ui.formato_figura(fig, f"Precio por {unidad} de cada producto comparable", f"COP/{unidad} · ejecución {ej_comp}"))
    else:
        fam = datos.familias(ej_comp, v)
        if fam.empty:
            ui.sin_datos("No hay productos con varios tamaños en esta ejecución.")
        else:
            fam["tamaño"] = fam.contenido_num.map(lambda x: f"{x:g}") + " " + fam.unidad
            fig = px.bar(fam, x="tamaño", y="precio_unitario", color="comercio", barmode="group", color_discrete_map=ui.COLORES,
                         text=fam.precio_unitario.round(0), labels={"precio_unitario": "COP por mL", "tamaño": "Tamaño del envase"})
            ui.mostrar_grafico(ui.formato_figura(fig, f"{fam.familia.iloc[0]}: precio por mL según tamaño", "COP/mL · solo mL con mL"))
            st.caption("El envase más grande exige un desembolso mayor, pero suele salir más barato por mL: compara ambas cosas.")

with t3:                                                       # gráfico 3
    log = st.checkbox("Escala logarítmica", value=False)
    fig = px.box(df, x="comercio", y="precio", color="comercio", color_discrete_map=ui.COLORES,
                 category_orders={"comercio": ui.ORDEN}, points="outliers", labels={"precio": "Precio (COP)", "comercio": ""})
    if log:
        fig.update_yaxes(type="log")
    ui.mostrar_grafico(ui.formato_figura(fig, "Distribución de precios por comercio", f"{len(df)} productos con los filtros actuales · COP"))
    st.caption("Comparar medianas de surtidos distintos no prueba que un comercio sea más barato: úsalo para ver el rango de oferta.")

with t4:                                                       # gráfico 4 (libre): ¿dónde se gana más comparando?
    if ah_df.empty:
        ui.sin_datos("Aún no hay productos comparables con precios.")
    else:
        a = ah_df.sort_values("ahorro_pct")
        fig = px.bar(a, x="ahorro_pct", y="producto", orientation="h", color_discrete_sequence=["#4F46E5"],
                     text=[f"{p:.1f} % · {ui.cop(c)} → {m}" for p, c, m in zip(a.ahorro_pct, a.ahorro_cop, a.mas_barato)],
                     labels={"ahorro_pct": "Ahorro (%)", "producto": ""})
        fig.update_traces(textposition="outside")
        fig.update_xaxes(range=[0, max(a.ahorro_pct.max() * 1.6, 1)])
        ui.mostrar_grafico(ui.formato_figura(fig, "¿En qué productos conviene más comparar antes de comprar?",
                                             f"Ahorro al elegir el comercio más barato · ejecución {ej_comp}", alto=520))
        st.caption("Pregunta del consumidor: ¿cuánto me ahorro por producto y en qué comercio? El % se calcula sobre el precio más alto; "
                   "el texto indica el comercio más barato (los empates se muestran juntos).")

with t5:                                                       # tabla
    vista = df.copy()
    vista["disponible"] = vista.disponible.map({1: "Disponible", 0: "Agotado"}).fillna("Sin dato")
    vista["fecha_consulta"] = vista.fecha_consulta.map(ui.fecha_legible)
    vista = vista[["comercio", "producto", "marca", "presentacion", "precio", "precio_unitario", "unidad",
                   "promocion", "disponible", "fecha_consulta", "url"]]
    ui.mostrar_tabla(vista, hide_index=True, column_config={
        "comercio": "Comercio", "producto": "Producto", "marca": "Marca", "presentacion": "Presentación",
        "precio": st.column_config.NumberColumn("Precio (COP)", format="$ %d"),
        "precio_unitario": st.column_config.NumberColumn("Precio unitario (COP)", format="%.1f"),
        "unidad": "Unidad", "promocion": st.column_config.CheckboxColumn("Promoción"), "disponible": "Disponibilidad",
        "fecha_consulta": "Fecha de consulta", "url": st.column_config.LinkColumn("Anuncio", display_text="Abrir")})
    st.download_button("Descargar CSV de los datos filtrados", df.to_csv(index=False).encode("utf-8-sig"),
                       file_name="productos_filtrados.csv", mime="text/csv")
    st.caption("Puedes ordenar por columna y buscar dentro de la tabla (ícono de lupa).")
