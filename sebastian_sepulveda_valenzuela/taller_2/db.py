"""
db.py
=====
Capa de acceso a datos para SQLite (Taller 2 - Módulo 3 y 4).
Toda consulta SQL, indicador, agregación y filtro vive exclusivamente aquí.
La interfaz Streamlit no contiene ninguna sentencia SQL.

Características principales:
  - Context manager seguro para conexiones: `with conexion() as con:`.
  - Consultas 100% parametrizadas con marcadores de posición (`?`).
  - Validación estricta y sanitización de texto con `LIKE ? ESCAPE '\\'`.
  - Agregaciones y cálculo de medianas ejecutados directamente en el motor SQLite.
  - Caché de lecturas mediante `@st.cache_data(ttl=600)`.
  - Función pura de cálculo de canasta óptima con manejo determinista de empates.
"""

import re
import sqlite3
from pathlib import Path
from contextlib import contextmanager
from typing import Dict, List, Any, Optional, Tuple

import pandas as pd
import streamlit as st

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "comparador_precios.sqlite"

# Caracteres permitidos para texto de búsqueda seguro
REGEX_BUSQUEDA_VALIDA = re.compile(r"^[a-zA-Z0-9áéíóúÁÉÍÓÚñÑüÜ\s\-\.\/\%\_]{1,60}$")


def get_db_path() -> Path:
    """Retorna la ruta absoluta del archivo SQLite."""
    return DB_PATH


@contextmanager
def conexion(db_path: Optional[Path] = None):
    """
    Context manager para manejo controlado de conexiones a SQLite.
    Garantiza activación de claves foráneas y cierre al terminar el bloque.
    """
    path = db_path or get_db_path()
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.execute("PRAGMA foreign_keys = ON;")
    try:
        yield conn
    finally:
        conn.close()


def sanitizar_texto_busqueda(texto: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
    """
    Valida y escapa el texto de búsqueda del usuario.
    Retorna: (texto_escapado_para_like, mensaje_error_si_invalido)
    """
    if not texto:
        return None, None
    t = texto.strip()
    if not t:
        return None, None
    if len(t) > 60:
        return None, "El texto de búsqueda no debe exceder 60 caracteres."
    if not REGEX_BUSQUEDA_VALIDA.match(t):
        return None, "Caracteres no permitidos en la búsqueda. Utilice solo letras, números y signos comunes (- . / %)."

    # Escapar caracteres comodín de SQL LIKE (_, %) y el carácter de escape (\)
    escapado = t.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escapado}%", None


# =====================================================================
# CONSULTAS DE FILTROS Y OPCIONES DE INTERFAZ
# =====================================================================

@st.cache_data(ttl=600)
def obtener_opciones_filtros() -> Dict[str, Any]:
    """Obtiene listas únicas de comercio, subcategoría, marca, rango de precio y ejecuciones."""
    with conexion() as con:
        cur = con.cursor()
        
        comercios = [r[0] for r in cur.execute("SELECT nombre FROM comercios ORDER BY nombre").fetchall()]
        
        cur.execute("""
            SELECT DISTINCT subcategoria FROM v_ultimo_precio 
            WHERE subcategoria IS NOT NULL AND subcategoria != '' ORDER BY subcategoria
        """)
        subcats = [r[0] for r in cur.fetchall()]
        
        cur.execute("""
            SELECT DISTINCT marca FROM v_ultimo_precio 
            WHERE marca IS NOT NULL AND marca != '' ORDER BY marca
        """)
        marcas = [r[0] for r in cur.fetchall()]
        
        cur.execute("SELECT min(precio_actual), max(precio_actual) FROM v_ultimo_precio WHERE precio_actual > 0")
        p_min, p_max = cur.fetchone()
        
        cur.execute("""
            SELECT ejecucion_id, comercio, fecha_hora_inicio 
            FROM v_ejecuciones_resumen 
            ORDER BY fecha_hora_inicio DESC
        """)
        ejecs = [{"ejecucion_id": r[0], "comercio": r[1], "fecha": r[2]} for r in cur.fetchall()]
        
    return {
        "comercios": comercios,
        "subcategorias": subcats,
        "marcas": marcas,
        "precio_min_max": (p_min or 500.0, p_max or 250000.0),
        "ejecuciones": ejecs
    }


# =====================================================================
# INDICADORES PRINCIPALES CALCULADOS 100% EN SQL
# =====================================================================

@st.cache_data(ttl=600)
def obtener_indicadores_generales(ejecucion_id: Optional[str] = None) -> Dict[str, Any]:
    """
    Calcula los 7 indicadores analíticos exigidos por el enunciado directamente en SQLite:
      1. Productos y observaciones por comercio.
      2. Fecha y estado de la última ejecución.
      3. Porcentaje de productos en promoción.
      4. Ahorro máximo entre comercios (COP y %).
      5. Número de cambios de precio en la última ejecución.
      6. Porcentaje de productos agotados.
      7. Total de comparables canónicos activos.
    """
    with conexion() as con:
        cur = con.cursor()

        # 1. Indicadores globales sobre la vista de último precio
        q_global = """
        SELECT 
            COUNT(DISTINCT anuncio_id) AS total_anuncios,
            COUNT(DISTINCT producto_id) AS total_productos_norm,
            ROUND(AVG(CASE WHEN es_promocion = 1 THEN 1.0 ELSE 0.0 END) * 100.0, 1) AS pct_promociones,
            ROUND(AVG(CASE WHEN disponibilidad = 'agotado' THEN 1.0 ELSE 0.0 END) * 100.0, 1) AS pct_agotados,
            COUNT(DISTINCT CASE WHEN es_canasta_8 = 1 THEN producto_id END) AS comparables_8_activos
        FROM v_ultimo_precio;
        """
        g_row = cur.execute(q_global).fetchone()

        # 2. Conteo por comercio
        q_com = """
        SELECT comercio, COUNT(DISTINCT anuncio_id) as n_anuncios, COUNT(DISTINCT sku) as n_skus
        FROM v_ultimo_precio
        GROUP BY comercio
        ORDER BY comercio;
        """
        por_comercio = cur.execute(q_com).fetchall()

        # 3. Fecha y estado de la última ejecución registrada
        q_ultima_ejec = """
        SELECT ejecucion_id, comercio, fecha_hora_inicio, estado
        FROM v_ejecuciones_resumen
        ORDER BY fecha_hora_inicio DESC LIMIT 1;
        """
        ultima_ejec = cur.execute(q_ultima_ejec).fetchone()

        # 4. Ahorro máximo en los 8 comparables canónicos
        q_ahorro = """
        WITH precios_comp AS (
            SELECT producto_id, nombre, min(precio_actual) as p_min, max(precio_actual) as p_max
            FROM v_comparables
            WHERE precio_actual > 0
            GROUP BY producto_id, nombre
        )
        SELECT nombre, p_min, p_max, (p_max - p_min) as ahorro_cop,
               ROUND(((p_max - p_min) * 100.0) / p_max, 1) as ahorro_pct
        FROM precios_comp
        ORDER BY ahorro_cop DESC LIMIT 1;
        """
        ahorro_row = cur.execute(q_ahorro).fetchone()

        # 5. Cambios de precio en la última ejecución
        q_cambios = """
        SELECT 
            COUNT(CASE WHEN tipo_cambio IN ('subida', 'bajada') THEN 1 END) AS n_cambios_reales,
            COUNT(CASE WHEN tipo_cambio = 'subida' THEN 1 END) AS n_subidas,
            COUNT(CASE WHEN tipo_cambio = 'bajada' THEN 1 END) AS n_bajadas,
            COUNT(CASE WHEN tipo_cambio = 'nuevo' THEN 1 END) AS n_nuevos
        FROM v_cambios_precio
        WHERE ejecucion_actual_id = (SELECT ejecucion_id FROM ejecuciones ORDER BY fecha_hora_inicio DESC LIMIT 1);
        """
        cambios_row = cur.execute(q_cambios).fetchone()

    return {
        "total_anuncios": g_row[0] or 0,
        "total_productos_norm": g_row[1] or 0,
        "pct_promociones": g_row[2] or 0.0,
        "pct_agotados": g_row[3] or 0.0,
        "comparables_8_activos": g_row[4] or 0,
        "por_comercio": [{"comercio": r[0], "anuncios": r[1]} for r in por_comercio],
        "ultima_ejecucion": {
            "id": ultima_ejec[0] if ultima_ejec else "N/A",
            "comercio": ultima_ejec[1] if ultima_ejec else "N/A",
            "fecha": ultima_ejec[2] if ultima_ejec else "N/A",
            "estado": ultima_ejec[3] if ultima_ejec else "N/A"
        },
        "ahorro_maximo": {
            "producto": ahorro_row[0] if ahorro_row else "N/A",
            "p_min": ahorro_row[1] if ahorro_row else 0.0,
            "p_max": ahorro_row[2] if ahorro_row else 0.0,
            "ahorro_cop": ahorro_row[3] if ahorro_row else 0.0,
            "ahorro_pct": ahorro_row[4] if ahorro_row else 0.0
        },
        "cambios_ultima_ejec": {
            "total_cambios": cambios_row[0] if cambios_row else 0,
            "subidas": cambios_row[1] if cambios_row else 0,
            "bajadas": cambios_row[2] if cambios_row else 0,
            "nuevos": cambios_row[3] if cambios_row else 0
        }
    }


# =====================================================================
# MEDIANA POR SUBCATEGORÍA (SQL PURO CON VENTANAS ROW_NUMBER)
# =====================================================================

@st.cache_data(ttl=600)
def obtener_mediana_por_subcategoria() -> pd.DataFrame:
    """Calcula la mediana exacta de precios por subcategoría usando ROW_NUMBER() y COUNT() en SQLite."""
    q = """
    WITH ranked AS (
        SELECT 
            subcategoria,
            precio_actual,
            ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio_actual) AS row_num,
            COUNT(*) OVER (PARTITION BY subcategoria) AS total_count
        FROM v_ultimo_precio
        WHERE precio_actual > 0 AND subcategoria IS NOT NULL AND subcategoria != ''
    )
    SELECT 
        subcategoria AS "Subcategoría",
        ROUND(AVG(precio_actual), 0) AS "Precio Mediano (COP)",
        COUNT(*) AS "Productos Evaluados"
    FROM ranked
    WHERE row_num IN ((total_count + 1) / 2, (total_count + 2) / 2)
    GROUP BY subcategoria
    ORDER BY "Precio Mediano (COP)" DESC;
    """
    with conexion() as con:
        return pd.read_sql_query(q, con)


# =====================================================================
# CONSULTAS DE TABLAS Y FILTROS COMBINABLES
# =====================================================================

@st.cache_data(ttl=600)
def obtener_productos_filtrados(
    comercios: List[str],
    subcategoria: Optional[str] = None,
    marca: Optional[str] = None,
    precio_min: float = 0.0,
    precio_max: float = 1000000.0,
    texto_busqueda: Optional[str] = None,
    solo_promociones: bool = False,
    solo_comparables: bool = False,
    limite: int = 1500
) -> Tuple[pd.DataFrame, Optional[str]]:
    """
    Consulta dinámica parametrizada sobre v_ultimo_precio aplicando filtros combinables.
    Usa solo marcadores '?' y ESCAPE '\\' para protección absoluta contra inyección SQL.
    """
    if not comercios:
        return pd.DataFrame(), "Seleccione al menos un comercio para consultar datos."

    like_patron, err_texto = sanitizar_texto_busqueda(texto_busqueda)
    if err_texto:
        return pd.DataFrame(), err_texto

    condiciones = ["precio_actual BETWEEN ? AND ?"]
    params: List[Any] = [precio_min, precio_max]

    # In con marcadores ?
    placeholders = ",".join("?" * len(comercios))
    condiciones.append(f"comercio IN ({placeholders})")
    params.extend(comercios)

    if subcategoria:
        condiciones.append("subcategoria = ?")
        params.append(subcategoria)

    if marca:
        condiciones.append("marca = ?")
        params.append(marca)

    if solo_promociones:
        condiciones.append("es_promocion = 1")

    if solo_comparables:
        condiciones.append("es_canasta_8 = 1")

    if like_patron:
        condiciones.append("(nombre LIKE ? ESCAPE '\\' OR sku LIKE ? ESCAPE '\\')")
        params.extend([like_patron, like_patron])

    where_clause = " AND ".join(condiciones)
    params.append(limite)

    sql = f"""
    SELECT 
        comercio AS "Comercio",
        nombre AS "Producto",
        marca AS "Marca",
        subcategoria AS "Subcategoría",
        contenido_total AS "Contenido",
        unidad_normalizada AS "Unidad",
        precio_actual AS "Precio (COP)",
        precio_unitario AS "Precio Unitario",
        CASE WHEN es_promocion = 1 THEN 'Sí' ELSE 'No' END AS "Promoción",
        disponibilidad AS "Disponibilidad",
        fecha_hora_consulta AS "Fecha Consulta",
        url AS "Enlace",
        sku AS "SKU"
    FROM v_ultimo_precio
    WHERE {where_clause}
    ORDER BY comercio, precio_actual ASC
    LIMIT ?;
    """

    with conexion() as con:
        df = pd.read_sql_query(sql, con, params=params)

    return df, None


# =====================================================================
# CONSULTAS PARA GRÁFICOS INTERACTIVOS (PLOTLY)
# =====================================================================

@st.cache_data(ttl=600)
def obtener_comparables_8_catalogo() -> pd.DataFrame:
    """Retorna el catálogo canónico de los 8 comparables."""
    q = """
    SELECT producto_id, ean, nombre_referencia, marca, subcategoria, contenido_total, unidad_normalizada
    FROM comparables_8
    ORDER BY subcategoria, nombre_referencia;
    """
    with conexion() as con:
        return pd.read_sql_query(q, con)


@st.cache_data(ttl=600)
def obtener_serie_tiempo_comparable(producto_id: int) -> pd.DataFrame:
    """Obtiene la serie temporal de precios para un producto comparable por comercio."""
    q = """
    SELECT 
        comercio,
        fecha_hora_consulta AS fecha,
        precio_actual,
        es_promocion,
        disponibilidad,
        ejecucion_id
    FROM v_comparables
    WHERE producto_id = ?
    ORDER BY fecha_hora_consulta ASC;
    """
    with conexion() as con:
        return pd.read_sql_query(q, con, params=[producto_id])


@st.cache_data(ttl=600)
def obtener_precios_unitarios_comparables(unidad: str) -> pd.DataFrame:
    """
    Obtiene los precios unitarios de productos comparables filtrados por una unidad normalizada
    específica (mL, g o unidad) para evitar estrictamente la mezcla errónea de unidades.
    """
    q = """
    SELECT 
        comercio,
        nombre,
        marca,
        contenido_total,
        unidad_normalizada,
        precio_actual,
        precio_unitario
    FROM v_comparables
    WHERE unidad_normalizada = ? AND precio_unitario > 0
    ORDER BY nombre, comercio;
    """
    with conexion() as con:
        return pd.read_sql_query(q, con, params=[unidad])


@st.cache_data(ttl=600)
def obtener_distribucion_precios() -> pd.DataFrame:
    """Obtiene la distribución de precios por comercio para gráficos boxplot/violín."""
    q = """
    SELECT comercio, precio_actual, subcategoria, es_promocion
    FROM v_ultimo_precio
    WHERE precio_actual > 0 AND precio_actual <= 150000;
    """
    with conexion() as con:
        return pd.read_sql_query(q, con)


@st.cache_data(ttl=600)
def obtener_frecuencia_comercio_mas_barato() -> pd.DataFrame:
    """
    Gráfico libre analítico: ¿Qué comercio ofrece el precio más económico con mayor
    frecuencia en los 8 productos de consumo esencial?
    """
    q = """
    WITH min_precios AS (
        SELECT producto_id, MIN(precio_actual) AS min_p
        FROM v_comparables
        WHERE precio_actual > 0
        GROUP BY producto_id
    )
    SELECT 
        c.comercio AS "Comercio",
        COUNT(DISTINCT c.producto_id) AS "Veces Más Barato"
    FROM v_comparables c
    JOIN min_precios m ON c.producto_id = m.producto_id AND c.precio_actual = m.min_p
    GROUP BY c.comercio
    ORDER BY "Veces Más Barato" DESC;
    """
    with conexion() as con:
        return pd.read_sql_query(q, con)


# =====================================================================
# SESIONES DE RECOLECCIÓN Y CAMBIOS DE PRECIO ENTRE SESIONES
# =====================================================================

@st.cache_data(ttl=600)
def obtener_sesiones_disponibles() -> List[Dict[str, Any]]:
    """
    Obtiene las sesiones de recolección disponibles en la base de datos,
    agrupando ejecuciones por sesión compartida (prefijo EXEC_YYYYMMDD_HHMMSS_xxxxxx).
    Retorna lista ordenada cronológicamente descendente con metadata de la sesión:
    - sesion_id
    - fecha
    - comercios incluidos
    - registros_totales
    """
    with conexion() as con:
        cur = con.cursor()
        cur.execute("SELECT comercio_id, nombre FROM comercios")
        com_map = dict(cur.fetchall())
        cur.execute("""
            SELECT ejecucion_id, comercio_id, fecha_hora_inicio, registros_obtenidos, estado 
            FROM ejecuciones 
            ORDER BY fecha_hora_inicio DESC
        """)
        rows = cur.fetchall()

    sesiones = {}
    for eid, cid, fecha, regs, estado in rows:
        parts = eid.rsplit('_', 1)
        if len(parts) == 2 and parts[1].upper() in ['OLÍMPICA', 'OLIMPICA', 'JUMBO', 'ÉXITO', 'EXITO']:
            sid = parts[0]
        else:
            sid = eid
        cname = com_map.get(cid, "Desconocido")
        if sid not in sesiones:
            sesiones[sid] = {
                "sesion_id": sid,
                "fecha": fecha[:10],
                "fecha_hora": fecha,
                "comercios": [],
                "registros_totales": 0,
                "ejecuciones": []
            }
        sesiones[sid]["comercios"].append(cname)
        sesiones[sid]["registros_totales"] += (regs or 0)
        sesiones[sid]["ejecuciones"].append(eid)

    return list(sesiones.values())


@st.cache_data(ttl=600)
def obtener_cambios_precio_sesiones(
    sesion_a: str,
    sesion_b: str,
    umbral_pct: float = 0.0
) -> pd.DataFrame:
    """
    Compara precios del mismo anuncio y comercio entre dos sesiones de recolección (sesion_a vs sesion_b).
    Identifica:
      - subida: precio_b > precio_a (COP y %)
      - bajada: precio_b < precio_a (COP y %)
      - sin_cambio: precio_b == precio_a
      - nuevo: presente en sesion_b pero no en sesion_a
      - no_observado: presente en sesion_a pero dejó de observarse en sesion_b
    Parametrizada y optimizada con índices sobre observaciones.
    """
    with conexion() as con:
        cur = con.cursor()
        cur.execute("SELECT ejecucion_id FROM ejecuciones WHERE ejecucion_id LIKE ? || '_%' OR ejecucion_id = ?", (sesion_a, sesion_a))
        eids_a = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT ejecucion_id FROM ejecuciones WHERE ejecucion_id LIKE ? || '_%' OR ejecucion_id = ?", (sesion_b, sesion_b))
        eids_b = [r[0] for r in cur.fetchall()]

        if not eids_a or not eids_b:
            return pd.DataFrame()

        pl_a = ','.join(['?'] * len(eids_a))
        pl_b = ','.join(['?'] * len(eids_b))

        q = f"""
        SELECT * FROM (
            SELECT 
                c.nombre AS "Comercio",
                COALESCE(p.nombre_estandar, an.nombre_estandar, an.nombre_original) AS "Producto",
                COALESCE(p.marca_estandar, an.marca_estandar, an.marca_original) AS "Marca",
                COALESCE(p.subcategoria_estandar, an.subcategoria_estandar, an.categoria_original) AS "Subcategoría",
                a.precio_actual AS "Precio Anterior",
                b.precio_actual AS "Precio Nuevo",
                ROUND(b.precio_actual - a.precio_actual, 2) AS "Variación (COP)",
                CASE 
                    WHEN a.precio_actual IS NOT NULL AND a.precio_actual > 0 
                    THEN ROUND(((b.precio_actual - a.precio_actual) * 100.0) / a.precio_actual, 2)
                    ELSE NULL 
                END AS "Variación (%)",
                CASE 
                    WHEN a.observacion_id IS NULL AND b.observacion_id IS NOT NULL THEN 'nuevo'
                    WHEN b.precio_actual > a.precio_actual THEN 'subida'
                    WHEN b.precio_actual < a.precio_actual THEN 'bajada'
                    ELSE 'sin_cambio'
                END AS "Tipo de Cambio",
                COALESCE(b.fecha_hora_consulta, a.fecha_hora_consulta) AS "Fecha Captura",
                an.sku AS "SKU",
                an.ean AS "EAN",
                an.url AS "URL"
            FROM observaciones b INDEXED BY idx_obs_ejecucion
            JOIN anuncios an ON b.anuncio_id = an.anuncio_id
            JOIN comercios c ON an.comercio_id = c.comercio_id
            LEFT JOIN productos p ON an.producto_id = p.producto_id
            LEFT JOIN observaciones a INDEXED BY uidx_obs_anuncio_ejecucion 
                ON b.anuncio_id = a.anuncio_id AND a.ejecucion_id IN ({pl_a}) AND a.descartada = 0
            WHERE b.ejecucion_id IN ({pl_b}) AND b.descartada = 0
            
            UNION ALL
            
            SELECT 
                c.nombre AS "Comercio",
                COALESCE(p.nombre_estandar, an.nombre_estandar, an.nombre_original) AS "Producto",
                COALESCE(p.marca_estandar, an.marca_estandar, an.marca_original) AS "Marca",
                COALESCE(p.subcategoria_estandar, an.subcategoria_estandar, an.categoria_original) AS "Subcategoría",
                a.precio_actual AS "Precio Anterior",
                NULL AS "Precio Nuevo",
                NULL AS "Variación (COP)",
                NULL AS "Variación (%)",
                'no_observado' AS "Tipo de Cambio",
                a.fecha_hora_consulta AS "Fecha Captura",
                an.sku AS "SKU",
                an.ean AS "EAN",
                an.url AS "URL"
            FROM observaciones a INDEXED BY idx_obs_ejecucion
            JOIN anuncios an ON a.anuncio_id = an.anuncio_id
            JOIN comercios c ON an.comercio_id = c.comercio_id
            LEFT JOIN productos p ON an.producto_id = p.producto_id
            WHERE a.ejecucion_id IN ({pl_a}) AND a.descartada = 0
              AND NOT EXISTS (
                  SELECT 1 FROM observaciones b INDEXED BY uidx_obs_anuncio_ejecucion
                  WHERE b.anuncio_id = a.anuncio_id 
                    AND b.ejecucion_id IN ({pl_b}) 
                    AND b.descartada = 0
              )
        )
        ORDER BY ABS(COALESCE("Variación (%)", 0)) DESC;
        """
        params = eids_a + eids_b + eids_a + eids_b
        df = pd.read_sql_query(q, con, params=params)

    if umbral_pct > 0.0 and not df.empty:
        cond = (df["Variación (%)"].abs() >= umbral_pct) | (df["Tipo de Cambio"].isin(["nuevo", "no_observado"]))
        df = df[cond]

    return df


@st.cache_data(ttl=600)
def obtener_cambios_precio_ejecuciones(
    ejecucion_act_id: Optional[str] = None,
    umbral_pct: float = 0.0,
    sesion_a: Optional[str] = None,
    sesion_b: Optional[str] = None
) -> pd.DataFrame:
    """
    Función de compatibilidad y punto de entrada para cambios de precio.
    Si se especifican sesion_a y sesion_b, realiza la comparación directa entre sesiones.
    Si no se especifican, compara por defecto las dos sesiones más recientes.
    """
    if sesion_a and sesion_b:
        return obtener_cambios_precio_sesiones(sesion_a, sesion_b, umbral_pct=umbral_pct)

    sesiones = obtener_sesiones_disponibles()
    if len(sesiones) >= 2:
        s_obj = sesiones[0]["sesion_id"]
        s_base = sesiones[1]["sesion_id"]
        return obtener_cambios_precio_sesiones(s_base, s_obj, umbral_pct=umbral_pct)
    elif len(sesiones) == 1:
        s_obj = sesiones[0]["sesion_id"]
        return obtener_cambios_precio_sesiones(s_obj, s_obj, umbral_pct=umbral_pct)

    return pd.DataFrame()


# =====================================================================
# LÓGICA PURA Y CONSULTA DE CANASTA FAMILIAR DE COMPRA
# =====================================================================

@st.cache_data(ttl=600)
def obtener_precios_canasta(sesion_id: Optional[str] = None) -> pd.DataFrame:
    """
    Obtiene los precios de los 8 comparables para una sesión de recolección específica
    (o la sesión más reciente que contenga observaciones de los 3 comercios).
    Garantiza traer los precios de los 3 comercios pertenecientes a dicha sesión.
    """
    with conexion() as con:
        cur = con.cursor()
        if sesion_id:
            cur.execute("""
                SELECT ejecucion_id FROM ejecuciones 
                WHERE ejecucion_id LIKE ? || '_%' OR ejecucion_id = ?
            """, (sesion_id, sesion_id))
            eids = [r[0] for r in cur.fetchall()]
        else:
            # Obtener las ejecuciones de la sesión más reciente
            cur.execute("""
                SELECT ejecucion_id FROM ejecuciones 
                WHERE estado IN ('completa', 'parcial')
                ORDER BY fecha_hora_inicio DESC LIMIT 1
            """)
            latest_row = cur.fetchone()
            if latest_row:
                parts = latest_row[0].rsplit('_', 1)
                latest_prefix = parts[0] if (len(parts) == 2 and parts[1].upper() in ['OLÍMPICA', 'OLIMPICA', 'JUMBO', 'ÉXITO', 'EXITO']) else latest_row[0]
                cur.execute("""
                    SELECT ejecucion_id FROM ejecuciones 
                    WHERE ejecucion_id LIKE ? || '_%' OR ejecucion_id = ?
                """, (latest_prefix, latest_prefix))
                eids = [r[0] for r in cur.fetchall()]
            else:
                eids = []

        if not eids:
            return pd.DataFrame()

        placeholders = ','.join(['?'] * len(eids))
        q = f"""
        SELECT 
            p.producto_id,
            p.ean,
            p.nombre_estandar AS nombre,
            p.marca_estandar AS marca,
            p.contenido_total,
            p.unidad_normalizada,
            c.nombre AS comercio,
            o.precio_actual,
            o.disponibilidad
        FROM comparables_8 c8
        JOIN productos p ON c8.producto_id = p.producto_id
        JOIN anuncios a ON p.producto_id = a.producto_id
        JOIN comercios c ON a.comercio_id = c.comercio_id
        JOIN observaciones o ON a.anuncio_id = o.anuncio_id
        WHERE o.ejecucion_id IN ({placeholders})
          AND o.descartada = 0;
        """
        return pd.read_sql_query(q, con, params=eids)


def calcular_canasta_optima(
    items_solicitados: Dict[int, int],
    df_precios: pd.DataFrame
) -> Dict[str, Any]:
    """
    Función pura y determinista que calcula el costo total de la canasta por comercio y la combinación óptima.
    Regla estricta: Solo calcula el costo por comercio si este dispone de TODOS los productos solicitados.
    Si falta algún producto, se declara formalmente incompleto y se detallan los faltantes reales.
    Evalúa consistentemente los 3 comercios oficiales (Éxito, Jumbo, Olímpica).
    """
    comercios_oficiales = ["Éxito", "Jumbo", "Olímpica"]
    if df_precios.empty or not items_solicitados:
        return {
            "costo_por_comercio": {c: None for c in comercios_oficiales},
            "faltantes_por_comercio": {c: list(items_solicitados.keys()) for c in comercios_oficiales},
            "disponible_por_comercio": {c: False for c in comercios_oficiales},
            "costo_optimo_total": None,
            "desglose_optimo": [],
            "mejor_comercio_unico": None,
            "costo_mejor_unico": None,
            "ahorro_cop": 0.0,
            "ahorro_pct": 0.0
        }

    pids_solicitados = set(items_solicitados.keys())

    costo_por_comercio = {}
    faltantes_por_comercio = {}
    disponible_por_comercio = {}

    for c in comercios_oficiales:
        sub = df_precios[df_precios["comercio"] == c] if not df_precios.empty else pd.DataFrame()
        if not sub.empty:
            pids_presentes = set(sub[sub["precio_actual"] > 0]["producto_id"].unique())
        else:
            pids_presentes = set()

        faltantes = sorted(list(pids_solicitados - pids_presentes))

        if not faltantes and not sub.empty:
            total = 0.0
            for pid, cant in items_solicitados.items():
                p = sub[sub["producto_id"] == pid]["precio_actual"].values[0]
                total += float(p) * cant
            costo_por_comercio[c] = round(total, 2)
            faltantes_por_comercio[c] = []
            disponible_por_comercio[c] = True
        else:
            costo_por_comercio[c] = None
            faltantes_por_comercio[c] = faltantes
            disponible_por_comercio[c] = False

    # Combinación óptima (comprar cada artículo donde resulte más barato)
    desglose_optimo = []
    costo_optimo_total = 0.0
    posible_combinada = True

    for pid, cant in items_solicitados.items():
        sub_p = df_precios[(df_precios["producto_id"] == pid) & (df_precios["precio_actual"] > 0)]
        if sub_p.empty:
            posible_combinada = False
            break

        # Ordenar determinísticamente por precio ascendente y nombre de comercio
        sub_p_sorted = sub_p.sort_values(by=["precio_actual", "comercio"], ascending=[True, True])
        best_row = sub_p_sorted.iloc[0]
        p_unit = float(best_row["precio_actual"])
        subtotal = round(p_unit * cant, 2)
        costo_optimo_total += subtotal
        desglose_optimo.append({
            "producto_id": pid,
            "nombre": best_row["nombre"],
            "comercio_elegido": best_row["comercio"],
            "precio_unitario": p_unit,
            "cantidad": cant,
            "subtotal": subtotal
        })

    comercios_completos = {c: cost for c, cost in costo_por_comercio.items() if cost is not None}
    if comercios_completos:
        mejor_comercio_unico = min(comercios_completos, key=comercios_completos.get)
        costo_mejor_unico = comercios_completos[mejor_comercio_unico]
        ahorro_cop = round(costo_mejor_unico - costo_optimo_total, 2)
        ahorro_pct = round((ahorro_cop * 100.0) / costo_mejor_unico, 2) if costo_mejor_unico > 0 else 0.0
    else:
        mejor_comercio_unico = None
        costo_mejor_unico = None
        ahorro_cop = 0.0
        ahorro_pct = 0.0

    return {
        "costo_por_comercio": costo_por_comercio,
        "faltantes_por_comercio": faltantes_por_comercio,
        "disponible_por_comercio": disponible_por_comercio,
        "costo_optimo_total": round(costo_optimo_total, 2) if posible_combinada else None,
        "desglose_optimo": desglose_optimo,
        "mejor_comercio_unico": mejor_comercio_unico,
        "costo_mejor_unico": costo_mejor_unico,
        "ahorro_cop": ahorro_cop,
        "ahorro_pct": ahorro_pct
    }
