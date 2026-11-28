"""
paginas/explorar.py
===================
Página de Explorador de Precios y Catálogo de Productos (Módulo 5, 7.5).
Permite filtrar interactivamente el catálogo mediante el panel lateral,
visualizar la tabla detallada con enlaces y descargar los datos filtrados en CSV.
"""

import io
import pandas as pd
import streamlit as st

from db import (
    obtener_opciones_filtros,
    obtener_productos_filtrados
)
from ui_comun import (
    render_sidebar_filtros,
    formato_cop,
    formato_precio_unitario,
    aplicar_estilos_comercio
)

aplicar_estilos_comercio()

st.title("🔎 Explorador de Precios y Catálogo")
st.caption("Filtre, ordene y compare los productos recolectados en Almacenes Éxito, Supertiendas Olímpica y Tiendas Jumbo.")

# 1. Obtener opciones disponibles para los filtros del sidebar
opciones = obtener_opciones_filtros()

# 2. Renderizar panel lateral de filtros combinables
filtros = render_sidebar_filtros(
    comercios_disponibles=opciones["comercios"],
    subcategorias_disponibles=opciones["subcategorias"],
    marcas_disponibles=opciones["marcas"],
    precio_min_max=opciones["precio_min_max"],
    ejecuciones_disponibles=opciones["ejecuciones"],
    key_prefix="explorar"
)

# 3. Consultar datos filtrados en SQLite a través de db.py (sin SQL en la vista)
df_productos, error_msg = obtener_productos_filtrados(
    comercios=filtros["comercios"],
    subcategoria=filtros["subcategoria"],
    marca=filtros["marca"],
    precio_min=filtros["precio_min"],
    precio_max=filtros["precio_max"],
    texto_busqueda=filtros["texto"],
    solo_promociones=filtros["solo_promociones"],
    solo_comparables=filtros["solo_comparables"]
)

if error_msg:
    st.warning(f"⚠️ {error_msg}")
elif df_productos.empty:
    st.info("ℹ️ No se encontraron productos que coincidan con la combinación de filtros seleccionada. Intente ampliar el rango de precios o limpiar la búsqueda.")
else:
    # Métricas rápidas del subconjunto filtrado
    st.markdown(f"**Resultados encontrados:** `{len(df_productos):,}` ofertas publicadas".replace(",", "."))
    
    # Preparar presentación de tabla y formato
    df_mostrar = df_productos.copy()
    
    # Formatear presentación: "1000 mL", "850 g", "3 unidad"
    df_mostrar["Presentación"] = df_mostrar.apply(
        lambda r: f"{r['Contenido']} {r['Unidad']}" if pd.notnull(r['Contenido']) and pd.notnull(r['Unidad']) else "N/D",
        axis=1
    )
    
    # Columnas ordenadas para el usuario
    cols_orden = [
        "Comercio", "Producto", "Marca", "Subcategoría", "Presentación",
        "Precio (COP)", "Precio Unitario", "Promoción", "Disponibilidad",
        "Fecha Consulta", "Enlace"
    ]
    df_mostrar = df_mostrar[cols_orden]

    # Configuración de columnas interactivas Streamlit
    col_config = {
        "Enlace": st.column_config.LinkColumn(
            "Ver en Tienda",
            help="Enlace directo a la ficha del producto en el comercio oficial",
            display_text="Abrir ↗"
        ),
        "Precio (COP)": st.column_config.NumberColumn(
            "Precio (COP)",
            format="$ %d"
        ),
        "Precio Unitario": st.column_config.NumberColumn(
            "Precio Unitario",
            format="$ %.2f"
        ),
        "Disponibilidad": st.column_config.TextColumn(
            "Disponibilidad"
        ),
        "Promoción": st.column_config.TextColumn(
            "Promoción"
        )
    }

    st.dataframe(
        df_mostrar,
        column_config=col_config,
        width="stretch",
        hide_index=True,
        height=520
    )

    # 4. Botón de descarga en CSV
    csv_buffer = io.StringIO()
    df_mostrar.to_csv(csv_buffer, index=False, sep=";", encoding="utf-8-sig")
    csv_bytes = csv_buffer.getvalue().encode("utf-8-sig")

    st.download_button(
        label="📥 Descargar datos filtrados en CSV",
        data=csv_bytes,
        file_name="comparador_precios_aseo_filtrado.csv",
        mime="text/csv",
        help="Exporta la tabla actualmente filtrada con codificación UTF-8 y separador de punto y coma."
    )
