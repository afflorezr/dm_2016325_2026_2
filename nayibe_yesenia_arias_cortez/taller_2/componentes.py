"""
componentes.py — Taller 2 Minería de Datos (UNAL): piezas comunes de la interfaz de Streamlit.

Módulo 3 (este bloque): caché de las consultas. Las páginas NO llaman a db.py directamente: piden los datos con
`consultar("nombre_de_funcion", argumentos...)`, que guarda el resultado con st.cache_data. Al terminar una
actualización se llama a `limpiar_cache()` para que indicadores, gráficos y tablas muestren los datos nuevos sin
reiniciar la aplicación.
"""
from __future__ import annotations

import streamlit as st

import db

# [CAMBIO]: funciones de db.py que la interfaz puede pedir (lista cerrada: la interfaz no ejecuta otra cosa).
CONSULTAS_PERMITIDAS = {
    "listar_comercios", "listar_subcategorias", "listar_marcas", "rango_precios", "listar_ejecuciones",
    "listar_comparables", "productos_filtrados", "resumen_por_comercio", "ultima_ejecucion",
    "mediana_por_subcategoria", "ahorro_por_comparable", "cambios_ultima_ejecucion", "resumen_disponibilidad",
    "evolucion_precio", "precio_unitario_comparables", "veces_mas_barato", "comparar_ejecuciones",
    "calcular_canasta",
}


# [CAMBIO]: consulta con caché. La clave de la caché son el nombre de la función y sus argumentos (filtros), así
# que la misma combinación de filtros no vuelve a consultar la base hasta que se limpie la caché.
@st.cache_data(show_spinner="Consultando la base de datos…")
def consultar(nombre_funcion: str, *args, **kwargs):
    if nombre_funcion not in CONSULTAS_PERMITIDAS:
        raise ValueError(f"Consulta no permitida: {nombre_funcion}")
    return getattr(db, nombre_funcion)(*args, **kwargs)


# [CAMBIO]: invalida la caché; se llama al terminar una actualización de precios (Módulo 2).
def limpiar_cache() -> None:
    consultar.clear()
