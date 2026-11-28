"""Gráficos que consultan únicamente las vistas SQLite."""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import pandas as pd
from .config import COLORES
from .db import ultima_corrida
from .consultas import ejecutar

def grafico_precios(conn,corrida_id=None):
    """Precio del mismo empaque por comercio, en COP."""
    corrida_id=corrida_id or ultima_corrida(conn)
    d=pd.read_sql_query('SELECT producto_id,producto_nombre,comercio,precio FROM v_comparables WHERE corrida_id=? AND precio>0 ORDER BY producto_id,comercio',conn,params=[corrida_id])
    fig,ax=plt.subplots(figsize=(12,6))
    if d.empty:
        ax.text(.5,.5,'Sin comparables con precio válido',ha='center')
        return fig
    nombres=d[['producto_id','producto_nombre']].drop_duplicates().set_index('producto_id').producto_nombre
    ids=list(nombres.index)
    for j,(comercio,color) in enumerate((c,color) for c,color in COLORES.items() if c in set(d.comercio)):
        sub=d[d.comercio==comercio].set_index('producto_id').reindex(ids)
        ax.scatter(sub.precio,[i+(j-1)*.18 for i in range(len(ids))],label=comercio,color=color,s=45)
    ax.set_yticks(range(len(ids)),[f'{i}: {nombres[i]}' for i in ids])
    ax.set_xlabel('Precio del empaque (COP)');ax.set_title('Presentaciones idénticas · '+str(corrida_id));ax.legend();ax.grid(axis='x',alpha=.2)
    fig.tight_layout()
    return fig

def grafico_precio_unitario(conn,corrida_id=None):
    """Panel por unidad; cada fila representa una presentación identificada."""
    corrida_id=corrida_id or ultima_corrida(conn)
    d=pd.read_sql_query('SELECT producto_id,producto_nombre,comercio,unidad,precio_por_unidad FROM v_comparables WHERE corrida_id=? AND precio_por_unidad>0 ORDER BY producto_id',conn,params=[corrida_id])
    unidades=list(d.unidad.dropna().unique())
    fig,axs=plt.subplots(max(1,len(unidades)),1,figsize=(12,6*max(1,len(unidades))),squeeze=False)
    if not unidades:
        axs[0,0].text(.5,.5,'Contenido no identificado',ha='center')
    for ax,u in zip(axs[:,0],unidades):
        sub=d[d.unidad==u]; nombres=sub[['producto_id','producto_nombre']].drop_duplicates().set_index('producto_id').producto_nombre; ids=list(nombres.index)
        for j,(comercio,color) in enumerate((c,color) for c,color in COLORES.items() if c in set(d.comercio)):
            valores=sub[sub.comercio==comercio].set_index('producto_id').reindex(ids)
            ax.scatter(valores.precio_por_unidad,[i+(j-1)*.18 for i in range(len(ids))],color=color,label=comercio)
        ax.set_yticks(range(len(ids)),[f'{i}: {nombres[i]}' for i in ids]);ax.set_xlabel('COP / '+u);ax.legend();ax.grid(axis='x',alpha=.2)
        ax.set_title('Costo unitario por presentación; comparar dentro de cada fila · '+str(corrida_id))
    fig.tight_layout();return fig

def grafico_ahorro(conn,corrida_id=None):
    """Ahorro relativo al precio máximo de cada presentación."""
    d=ejecutar(6,conn,corrida_id)
    fig,ax=plt.subplots(figsize=(12,6))
    if not d.empty:
        ax.barh(d.producto,d.ahorro_pct,color='#5665a3')
        for i,r in enumerate(d.itertuples()):
            ax.text(r.ahorro_pct,i,f' {r.ahorro_cop:,.0f} COP',va='center',fontsize=9)
        ax.invert_yaxis();ax.margins(x=.3)
    ax.set_xlabel('Ahorro frente al precio más alto (%)');ax.set_title('Ahorro por empaque · '+str(corrida_id or ultima_corrida(conn)));fig.tight_layout();return fig
