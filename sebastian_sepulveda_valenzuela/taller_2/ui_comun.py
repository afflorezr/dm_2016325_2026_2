"""
ui_comun.py
===========
Utilidades comunes de interfaz gráfica, formatos y colores consistentes.
Taller 2 - Minería de Datos (UNAL, código 2016325).

Reglas de presentación (Módulo 5):
  - Colores fijos por comercio en toda la aplicación (Olímpica, Jumbo, Éxito).
  - Formato de moneda en Pesos Colombianos COP ($ 12.900) con punto separador de miles.
  - Componentes visuales limpios, legibles y en español.
  - Cero consultas SQL (la lógica de base de datos vive exclusivamente en db.py).
"""

import streamlit as st
from typing import Dict, Any, List, Optional, Tuple

# Paleta oficial y consistente por comercio en toda la aplicación
COLORES_COMERCIO = {
    "Olímpica": "#E53935",   # Rojo institucional
    "Jumbo": "#2E7D32",      # Verde institucional
    "Éxito": "#D97706"       # Ámbar/Amarillo oscuro con alto contraste
}


def formato_cop(valor: Optional[float]) -> str:
    """Formatea una cifra numérica a formato de Pesos Colombianos ($ 12.900)."""
    if valor is None:
        return "N/D"
    try:
        val_redondeado = int(round(float(valor)))
        formateado = f"{val_redondeado:,}".replace(",", ".")
        return f"$ {formateado}"
    except (ValueError, TypeError):
        return "N/D"


def formato_precio_unitario(valor: Optional[float], unidad: Optional[str]) -> str:
    """Formatea el precio unitario ($ 14,20 / mL)."""
    if valor is None or unidad is None:
        return "N/D"
    try:
        v = float(valor)
        if v >= 100:
            txt = f"{int(round(v)):,}".replace(",", ".")
        else:
            txt = f"{v:0.2f}".replace(".", ",")
        return f"$ {txt} / {unidad}"
    except (ValueError, TypeError):
        return "N/D"


def formato_porcentaje(valor: Optional[float]) -> str:
    """Formatea porcentaje con un decimal (ej. 15,4 %)."""
    if valor is None:
        return "N/D"
    try:
        return f"{float(valor):.1f} %".replace(".", ",")
    except (ValueError, TypeError):
        return "N/D"


def aplicar_estilos_comercio():
    """Inyecta estilos CSS para badges de colores consistentes."""
    st.markdown("""
    <style>
    .badge-olimpica {
        background-color: #FFEBEE;
        color: #C62828;
        padding: 3px 8px;
        border-radius: 4px;
        font-weight: 600;
        border: 1px solid #FFCDD2;
    }
    .badge-jumbo {
        background-color: #E8F5E9;
        color: #1B5E20;
        padding: 3px 8px;
        border-radius: 4px;
        font-weight: 600;
        border: 1px solid #C8E6C9;
    }
    .badge-exito {
        background-color: #FEF3C7;
        color: #92400E;
        padding: 3px 8px;
        border-radius: 4px;
        font-weight: 600;
        border: 1px solid #FDE68A;
    }
    .metric-card {
        border-radius: 8px;
        padding: 16px;
        background: #FFFFFF;
        box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    </style>
    """, unsafe_allow_html=True)


def mostrar_alerta_info(mensaje: str):
    """Muestra un mensaje informativo amigable al usuario."""
    st.info(f"ℹ️ {mensaje}")


def render_sidebar_filtros(
    comercios_disponibles: List[str],
    subcategorias_disponibles: List[str],
    marcas_disponibles: List[str],
    precio_min_max: Tuple[float, float],
    ejecuciones_disponibles: List[Dict[str, str]],
    key_prefix: str = "filtro"
) -> Dict[str, Any]:
    """
    Renderiza el panel lateral unificado de filtros interactivos.
    No contiene SQL; únicamente retorna un diccionario de valores seleccionados.
    """
    with st.sidebar:
        st.subheader("🔍 Filtros de Búsqueda")

        # 1. Búsqueda por texto libre
        busqueda_texto = st.text_input(
            "Palabras clave (nombre o producto):",
            value="",
            max_chars=60,
            key=f"{key_prefix}_texto",
            help="Búsqueda insensible a mayúsculas/minúsculas. Longitud máx. 60 caracteres."
        ).strip()

        # 2. Selección múltiple de comercios
        comercios_sel = st.multiselect(
            "Comercios:",
            options=comercios_disponibles,
            default=comercios_disponibles,
            key=f"{key_prefix}_comercios"
        )

        # 3. Subcategorías
        subcats_options = ["(Todas las subcategorías)"] + subcategorias_disponibles
        subcat_sel = st.selectbox(
            "Subcategoría:",
            options=subcats_options,
            index=0,
            key=f"{key_prefix}_subcat"
        )

        # 4. Marcas
        marcas_options = ["(Todas las marcas)"] + marcas_disponibles
        marca_sel = st.selectbox(
            "Marca:",
            options=marcas_options,
            index=0,
            key=f"{key_prefix}_marca"
        )

        # 5. Rango de precios
        p_min_db, p_max_db = precio_min_max
        if p_min_db >= p_max_db:
            p_max_db = p_min_db + 10000.0

        rango_precio = st.slider(
            "Rango de Precio (COP):",
            min_value=float(p_min_db),
            max_value=float(p_max_db),
            value=(float(p_min_db), float(p_max_db)),
            step=500.0,
            format="$ %d",
            key=f"{key_prefix}_rango_precio"
        )

        # 6. Filtro por ejecución o fecha
        opciones_ejec = ["(Última ejecución vigente)"] + [
            f"{e['ejecucion_id']} — {e['comercio']} ({e['fecha'][:10]})"
            for e in ejecuciones_disponibles
        ]
        ejecucion_sel = st.selectbox(
            "Ejecución / Fecha de captura:",
            options=opciones_ejec,
            index=0,
            key=f"{key_prefix}_ejecucion"
        )

        # 7. Banderas booleanas
        st.markdown("**Opciones especiales:**")
        solo_promo = st.checkbox("Solo productos en promoción", value=False, key=f"{key_prefix}_promo")
        solo_comp = st.checkbox("Solo productos comparables (8 canónicos)", value=False, key=f"{key_prefix}_comp")

    return {
        "texto": busqueda_texto,
        "comercios": comercios_sel,
        "subcategoria": None if subcat_sel.startswith("(") else subcat_sel,
        "marca": None if marca_sel.startswith("(") else marca_sel,
        "precio_min": rango_precio[0],
        "precio_max": rango_precio[1],
        "ejecucion_raw": ejecucion_sel,
        "solo_promociones": solo_promo,
        "solo_comparables": solo_comp
    }
