"""
graficos.py - Figuras interactivas (plotly) del comparador. Reciben DataFrames ya calculados con SQL (db.py).

Cada comercio conserva el mismo color en toda la aplicación (COLORES). Cada función devuelve una figura o None si no hay
datos, para que la página muestre un mensaje claro en lugar de un gráfico vacío.
"""
from __future__ import annotations

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

import analisis as A

COLORES = {"Éxito": "#E5A100", "Jumbo": "#2E7D32", "Olímpica": "#C62828", "Carulla": "#1565C0"}
ETIQUETAS_UNIDAD = {"unidad": "unidad", "g": "gramo (g)", "ml": "mililitro (mL)"}


def _estilo(fig: go.Figure, titulo: str, alto: int | None = None) -> go.Figure:
    fig.update_layout(title=titulo, separators=",.", legend_title_text="Comercio",
                      margin=dict(l=10, r=10, t=70, b=10), template="plotly_white")
    if alto:
        fig.update_layout(height=alto)
    return fig


def evolucion_precio(df: pd.DataFrame, nombre_producto: str) -> go.Figure | None:
    """Gráfico 1: evolución del precio de un producto comparable, una serie por comercio (eje X = ejecución)."""
    if df is None or df.empty:
        return None
    d = df.copy()
    d["ejecucion"] = d["ejecucion_id"].map(A.etiqueta_ejecucion)
    d = d.sort_values(["fecha_hora_consulta"])
    orden = list(dict.fromkeys(d.sort_values("ejecucion_id")["ejecucion"]))
    fig = px.line(d, x="ejecucion", y="precio", color="comercio", markers=True, color_discrete_map=COLORES,
                  category_orders={"ejecucion": orden}, hover_data={"precio": ":,.0f", "ejecucion": True})
    fig.update_traces(marker=dict(size=9))
    fig.update_xaxes(title="Ejecución (fecha y hora de inicio)", type="category")
    fig.update_yaxes(title="Precio (COP)", tickprefix="$", separatethousands=True, rangemode="tozero")
    return _estilo(fig, f"Evolución del precio · {nombre_producto}")


def precio_por_unidad(df: pd.DataFrame, unidad: str) -> go.Figure | None:
    """Gráfico 2: precio por unidad de contenido. Una figura por unidad base (nunca se mezclan unidades)."""
    d = df[df["unidad_base"] == unidad] if df is not None and not df.empty else None
    if d is None or d.empty:
        return None
    etiqueta = ETIQUETAS_UNIDAD.get(unidad, unidad)
    decimales = 2 if unidad == "unidad" else 1
    fig = px.bar(d, x="precio_unitario", y="nombre_std", color="comercio", orientation="h", barmode="group",
                 color_discrete_map=COLORES, hover_data={"precio": ":,.0f", "precio_unitario": ":,.2f"})
    fig.update_xaxes(title=f"Precio por {etiqueta} (COP)", tickprefix="$", separatethousands=True)
    fig.update_yaxes(title="", autorange="reversed")
    fig.update_traces(texttemplate=f"%{{x:,.{decimales}f}}", textposition="outside")
    return _estilo(fig, f"Precio por {etiqueta} · mismas presentaciones en cada comercio", alto=max(380, 70 * d["nombre_std"].nunique()))


def distribucion(df: pd.DataFrame, escala_log: bool = False) -> go.Figure | None:
    """Gráfico 3: distribución de los precios de la categoría por comercio (cajas con todos los puntos)."""
    if df is None or df.empty:
        return None
    fig = px.box(df, x="comercio", y="precio", color="comercio", points="all", color_discrete_map=COLORES,
                 hover_data=["nombre_original", "subcategoria"])
    fig.update_traces(jitter=0.4, marker=dict(size=4, opacity=0.5))
    fig.update_yaxes(title="Precio (COP)" + (" · escala logarítmica" if escala_log else ""), tickprefix="$",
                     separatethousands=True, type="log" if escala_log else "linear")
    fig.update_xaxes(title="")
    fig.update_layout(showlegend=False)
    return _estilo(fig, "Distribución de precios de la categoría por comercio", alto=520)


def sobreprecio_heatmap(df: pd.DataFrame) -> go.Figure | None:
    """Gráfico 4 (libre): ¿cuánto más caro es cada comercio que el más barato en cada producto comparable?"""
    if df is None or df.empty:
        return None
    pivote = df.pivot_table(index="nombre_std", columns="comercio", values="sobreprecio_pct", aggfunc="min")
    pivote = pivote[[c for c in COLORES if c in pivote.columns] + [c for c in pivote.columns if c not in COLORES]]
    texto = pivote.map(lambda v: "" if pd.isna(v) else ("más barato" if v < 0.05 else f"+{v:.1f} %"))
    fig = go.Figure(go.Heatmap(z=pivote.to_numpy(), x=list(pivote.columns), y=list(pivote.index), text=texto.to_numpy(),
                               texttemplate="%{text}", colorscale="RdYlGn_r", zmin=0,
                               colorbar=dict(title="% sobre el mínimo"), hoverongaps=False))
    fig.update_yaxes(autorange="reversed", title="")
    fig.update_xaxes(title="", side="top")
    return _estilo(fig, "¿Cuánto pago de más frente al comercio más barato? (por producto comparable)",
                   alto=max(420, 38 * len(pivote) + 160))


def variaciones(df: pd.DataFrame, maximo: int = 25) -> go.Figure | None:
    """Barras de las mayores variaciones de precio (subió/bajó) entre dos ejecuciones."""
    d = df[df["tipo"].isin(["subió", "bajó"])].copy() if df is not None and not df.empty else None
    if d is None or d.empty:
        return None
    d["magnitud"] = d["variacion_pct"].abs()
    d = d.sort_values("magnitud", ascending=False).head(maximo)
    d["producto"] = d["nombre_original"].str.slice(0, 55) + " · " + d["comercio"]
    fig = px.bar(d, x="variacion_pct", y="producto", color="tipo", orientation="h",
                 color_discrete_map={"subió": "#C62828", "bajó": "#2E7D32"},
                 hover_data={"precio_anterior": ":,.0f", "precio_nuevo": ":,.0f", "variacion_cop": ":,.0f"})
    fig.update_yaxes(autorange="reversed", title="")
    fig.update_xaxes(title="Variación del precio (%)", ticksuffix=" %")
    fig.update_layout(legend_title_text="Cambio")
    fig.update_layout(title=f"Mayores variaciones de precio (hasta {maximo})", separators=",.",
                      margin=dict(l=10, r=10, t=70, b=10), template="plotly_white",
                      height=max(380, 28 * len(d) + 150))
    return fig
