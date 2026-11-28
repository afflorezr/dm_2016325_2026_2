"""Reglas previas a insertar: filas válidas, sin duplicados y cobertura del mapeo."""
import re
import pandas as pd
from codigo.validacion import validar_fila, validar_cobertura
from codigo.limpieza import limpiar_precio, normalizar_contenido


def texto_busqueda(valor):
    if not isinstance(valor,str) or len(valor)>120 or not re.fullmatch(r"[\w\s.,+()/%¿?¡!\-]*",valor):
        raise ValueError('La búsqueda admite hasta 120 caracteres: letras, números y signos comunes.')
    return valor.strip()


def preparar_lote(df,mapeo,comercio):
    """No sustituye ausentes. Rechaza las dos filas de una clave repetida."""
    repetidos=df.duplicated(['comercio','sku'],keep=False)
    conservar=[];rechazados=[];validos=set()
    filas=df.copy(deep=False);filas.attrs={}
    for indice,r in filas.iterrows():
        if r.excluido:
            conservar.append(indice);continue
        errores=validar_fila(r.to_dict())
        if repetidos.loc[indice]:errores.append('Anuncio duplicado en la ejecución')
        if errores:rechazados.append((r.to_dict(),'; '.join(errores)))
        else:conservar.append(indice);validos.add(str(r.sku))
    d=pd.read_csv(mapeo,dtype={'sku':str})
    esperados=set(d.loc[d.comercio==comercio,'sku'])
    cobertura=len(esperados)>=8 and esperados<=validos
    salida=df.loc[conservar].copy();salida.attrs=df.attrs.copy()
    return salida,rechazados,cobertura
