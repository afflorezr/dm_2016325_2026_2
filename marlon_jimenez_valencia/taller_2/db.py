"""
db.py — Capa de acceso a datos de la aplicación (Taller 2, Módulo 3).

Reglas de este módulo (enunciado §5 y §6):
  * Toda consulta de la aplicación está aquí. Las páginas no tienen SQL: llaman a estas
    funciones con los filtros como argumentos y reciben DataFrames.
  * Filtros, indicadores y agregaciones se calculan con SQL sobre SQLite (nada de leer
    una tabla completa y filtrarla después con pandas).
  * Consultas parametrizadas: en el texto del SQL solo se escriben marcadores `?`; los
    valores que vienen del usuario van siempre en `params` (Anexo A). Los fragmentos
    de SQL que se arman en Python son fijos y los escribe este archivo, nunca el usuario.
  * La búsqueda por texto se valida (largo máximo y caracteres permitidos) antes de
    llegar a la consulta.
  * La base se abre en modo de SOLO LECTURA (`mode=ro`) y cada consulta abre y cierra
    su conexión con `contextlib.closing`. Las escrituras las hace solo scraper.py.
  * Los resultados se guardan en caché (`st.cache_data`) y la página de actualización
    llama a limpiar_cache() al terminar.
"""
from __future__ import annotations

import re
import sqlite3
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path

import pandas as pd
import streamlit as st

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "comparador_precios.sqlite"     # ruta relativa a este archivo

TIEMPO_CACHE = 600              # segundos que dura un resultado en caché
LARGO_MAXIMO_TEXTO = 60         # búsqueda por palabras
# Letras (incluidas tildes y ñ), números, espacios y . , / + - % ( )
TEXTO_PERMITIDO = re.compile(r"[\w\s.,/+\-%()]*")
ID_EJECUCION = re.compile(r"E\d{8}T\d{6}")
ID_PRODUCTO = re.compile(r"P\d{2}")
CANTIDAD_MAXIMA = 99


class BaseNoDisponible(RuntimeError):
    """No se encuentra el archivo de la base."""


class EntradaInvalida(ValueError):
    """Un valor ingresado por el usuario no pasa la validación."""


# ---------------------------------------------------------------------------
# Conexión y lectura
# ---------------------------------------------------------------------------
def conectar(ruta: Path | str | None = None) -> sqlite3.Connection:
    """Conexión de SOLO LECTURA. Quien la abre debe cerrarla (usar con closing())."""
    ruta = Path(ruta or DB_PATH).resolve()
    if not ruta.exists():
        raise BaseNoDisponible(f"No se encuentra la base {ruta.name}.")
    return sqlite3.connect(f"{ruta.as_uri()}?mode=ro", uri=True, timeout=30)


@st.cache_data(ttl=TIEMPO_CACHE, show_spinner=False)
def _leer_en_cache(sql: str, params: tuple, ruta: str) -> pd.DataFrame:
    with closing(conectar(ruta)) as con:
        return pd.read_sql_query(sql, con, params=list(params))


def leer(sql: str, params=()) -> pd.DataFrame:
    """Ejecuta una consulta parametrizada y devuelve un DataFrame (con caché)."""
    return _leer_en_cache(sql, tuple(params), str(DB_PATH))


def limpiar_cache() -> None:
    """Se llama al terminar una actualización: indicadores y gráficos se recalculan."""
    _leer_en_cache.clear()


# ---------------------------------------------------------------------------
# Validación de entradas
# ---------------------------------------------------------------------------
def validar_texto(texto: str | None) -> str:
    """Texto de búsqueda: máximo LARGO_MAXIMO_TEXTO caracteres y solo caracteres permitidos."""
    texto = (texto or "").strip()
    if len(texto) > LARGO_MAXIMO_TEXTO:
        raise EntradaInvalida(f"La búsqueda admite máximo {LARGO_MAXIMO_TEXTO} caracteres.")
    if not TEXTO_PERMITIDO.fullmatch(texto):
        raise EntradaInvalida("La búsqueda solo admite letras, números, espacios y los "
                              "signos . , / + - % ( )")
    return texto


def validar_ejecucion(id_ejecucion: str) -> str:
    if not isinstance(id_ejecucion, str) or not ID_EJECUCION.fullmatch(id_ejecucion):
        raise EntradaInvalida(f"Identificador de ejecución no válido: {id_ejecucion!r}")
    return id_ejecucion


def _patron_like(palabra: str) -> str:
    """'%' y '_' son comodines de LIKE: se escapan para buscarlos como texto."""
    palabra = palabra.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{palabra}%"


def _marcas(valores) -> str:
    """'?, ?, ?' para una lista IN (...). Solo marcadores, nunca valores."""
    return ", ".join("?" * len(valores))


# ---------------------------------------------------------------------------
# Filtros de la barra lateral
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Filtros:
    """Filtros combinables (§7.2). Una tupla vacía significa 'todos'."""
    id_ejecucion: str | None = None        # una ejecución...
    fecha_desde: str | None = None         # ...o un rango de fechas (AAAA-MM-DD)
    fecha_hasta: str | None = None
    comercios: tuple[str, ...] = ()        # id_comercio
    subcategorias: tuple[str, ...] = ()
    marcas: tuple[str, ...] = ()
    precio_min: float | None = None
    precio_max: float | None = None
    solo_promociones: bool = False
    solo_comparables: bool = False
    texto: str = ""


def _consulta_filtrada(f: Filtros, solo_comparables: bool = False,
                       solo_ultima: bool = True) -> tuple[str, list]:
    """
    SELECT con la observación más reciente de cada anuncio que cumple los filtros.
    Con una ejecución, cada anuncio tiene una sola observación; con un rango de fechas
    se toma la última del rango (solo_ultima=False devuelve todas las del periodo).
    Devuelve (sql, params) para usar como subconsulta.
    """
    condiciones, params = ["v.descartada = 0"], []
    if f.id_ejecucion:
        condiciones.append("v.id_ejecucion = ?")
        params.append(validar_ejecucion(f.id_ejecucion))
    else:
        if f.fecha_desde:
            condiciones.append("SUBSTR(v.fecha_consulta, 1, 10) >= ?")
            params.append(str(f.fecha_desde))
        if f.fecha_hasta:
            condiciones.append("SUBSTR(v.fecha_consulta, 1, 10) <= ?")
            params.append(str(f.fecha_hasta))
    for columna, valores in (("v.id_comercio", f.comercios), ("v.subcategoria", f.subcategorias),
                             ("v.marca", f.marcas)):
        if valores:
            condiciones.append(f"{columna} IN ({_marcas(valores)})")
            params.extend(valores)
    if f.solo_comparables or solo_comparables:
        condiciones.append("v.comparable = 1")
    for palabra in validar_texto(f.texto).split():
        condiciones.append("(v.nombre_original LIKE ? ESCAPE '\\' "
                           "OR v.texto_original LIKE ? ESCAPE '\\')")
        params.extend([_patron_like(palabra)] * 2)

    # Precio y promoción se filtran DESPUÉS de elegir la observación más reciente
    externas = ["orden = 1"] if solo_ultima else ["1 = 1"]
    if f.precio_min is not None:
        externas.append("precio >= ?")
        params.append(float(f.precio_min))
    if f.precio_max is not None:
        externas.append("precio <= ?")
        params.append(float(f.precio_max))
    if f.solo_promociones:
        externas.append("promocion = 1")

    sql = f"""
        SELECT * FROM (
            SELECT v.*,
                   ROW_NUMBER() OVER (PARTITION BY v.id_comercio, v.sku_comercio
                                      ORDER BY v.fecha_consulta DESC) AS orden
            FROM v_observaciones v
            WHERE {' AND '.join(condiciones)}
        )
        WHERE {' AND '.join(externas)}"""
    return sql, params


# ---------------------------------------------------------------------------
# Catálogos para los filtros y selectores
# ---------------------------------------------------------------------------
def comercios() -> pd.DataFrame:
    return leer("""SELECT id_comercio, nombre_corto AS comercio, nombre, url_base
                   FROM comercios WHERE activo = 1 ORDER BY nombre_corto""")


def subcategorias() -> list[str]:
    df = leer("""SELECT DISTINCT subcategoria FROM anuncios
                 WHERE subcategoria IS NOT NULL ORDER BY subcategoria""")
    return df["subcategoria"].tolist()


def marcas(subcategorias_elegidas: tuple[str, ...] = (), comercios_elegidos: tuple[str, ...] = ()
           ) -> list[str]:
    """Marcas disponibles, según la subcategoría y los comercios elegidos."""
    condiciones, params = ["marca_std IS NOT NULL"], []
    if subcategorias_elegidas:
        condiciones.append(f"subcategoria IN ({_marcas(subcategorias_elegidas)})")
        params.extend(subcategorias_elegidas)
    if comercios_elegidos:
        condiciones.append(f"id_comercio IN ({_marcas(comercios_elegidos)})")
        params.extend(comercios_elegidos)
    df = leer(f"""SELECT DISTINCT marca_std AS marca FROM anuncios
                  WHERE {' AND '.join(condiciones)} ORDER BY marca_std""", params)
    return df["marca"].tolist()


def rango_precios() -> tuple[float, float]:
    df = leer("""SELECT MIN(precio) AS minimo, MAX(precio) AS maximo
                 FROM observaciones WHERE descartada = 0 AND precio IS NOT NULL""")
    return float(df.at[0, "minimo"] or 0), float(df.at[0, "maximo"] or 0)


def rango_fechas() -> tuple[str | None, str | None]:
    df = leer("""SELECT MIN(SUBSTR(fecha_consulta, 1, 10)) AS desde,
                        MAX(SUBSTR(fecha_consulta, 1, 10)) AS hasta
                 FROM observaciones WHERE descartada = 0""")
    return df.at[0, "desde"], df.at[0, "hasta"]


def ejecuciones() -> pd.DataFrame:
    """Una fila por ejecución (todos los comercios), de la más reciente a la más antigua."""
    return leer("""
        SELECT e.id_ejecucion,
               MIN(e.inicio)                                   AS inicio,
               SUBSTR(MIN(e.inicio), 1, 10)                    AS fecha,
               COUNT(*)                                        AS comercios,
               SUM(e.estado = 'completa')                      AS completas,
               GROUP_CONCAT(c.nombre_corto || ': ' || e.estado, ' · ') AS estados,
               e.id_ejecucion IN (SELECT id_ejecucion FROM v_ejecuciones_completas) AS completa,
               (SELECT COUNT(*) FROM observaciones o
                WHERE o.id_ejecucion = e.id_ejecucion AND o.descartada = 0) AS observaciones
        FROM ejecuciones e
        JOIN comercios c ON c.id_comercio = e.id_comercio
        GROUP BY e.id_ejecucion
        ORDER BY inicio DESC""")


def ejecucion_por_defecto() -> str | None:
    """La ejecución completa (los 3 comercios) más reciente; si no hay, la más reciente."""
    df = ejecuciones()
    if df.empty:
        return None
    completas = df[df["completa"] == 1]
    return (completas if not completas.empty else df)["id_ejecucion"].iloc[0]


def ultima_ejecucion_en_rango(fecha_desde: str | None, fecha_hasta: str | None) -> str | None:
    """La ejecución más reciente que empezó dentro del rango de fechas."""
    df = leer("""SELECT id_ejecucion FROM ejecuciones
                 WHERE (? IS NULL OR SUBSTR(inicio, 1, 10) >= ?)
                   AND (? IS NULL OR SUBSTR(inicio, 1, 10) <= ?)
                   AND estado <> 'fallida'
                 ORDER BY inicio DESC LIMIT 1""",
              [fecha_desde, fecha_desde, fecha_hasta, fecha_hasta])
    return None if df.empty else df.at[0, "id_ejecucion"]


def ultima_ejecucion() -> pd.DataFrame:
    """Fecha, modo y estado de la última ejecución de cada comercio activo."""
    return leer("""
        SELECT c.nombre_corto AS comercio, e.id_ejecucion, e.inicio, e.fin, e.modo, e.estado
        FROM ejecuciones e
        JOIN comercios c ON c.id_comercio = e.id_comercio AND c.activo = 1
        WHERE e.inicio = (SELECT MAX(e2.inicio) FROM ejecuciones e2
                          WHERE e2.id_comercio = e.id_comercio)
        ORDER BY c.nombre_corto""")


def productos_comparables() -> pd.DataFrame:
    return leer("""SELECT id_producto, descripcion, principio_activo, concentracion, forma,
                          laboratorio, contenido_total, unidad_normalizada
                   FROM productos ORDER BY id_producto""")


# ---------------------------------------------------------------------------
# Tabla de productos (§7.5)
# ---------------------------------------------------------------------------
def productos(f: Filtros) -> pd.DataFrame:
    base, params = _consulta_filtrada(f)
    return leer(f"""
        SELECT nombre_corto AS comercio, nombre_original AS nombre, marca, laboratorio,
               subcategoria, principio_activo, concentracion, forma,
               contenido_total, unidad_normalizada,
               precio, precio_lista, precio_unitario, promocion, disponibilidad,
               fecha_consulta, id_ejecucion, url_producto, id_producto, sku_comercio, ean
        FROM ({base})
        ORDER BY nombre_corto, nombre_original""", params)


# ---------------------------------------------------------------------------
# Indicadores (§7.3)
# ---------------------------------------------------------------------------
def conteos_por_comercio(f: Filtros) -> pd.DataFrame:
    """Productos, observaciones, agotados y proporción en promoción por comercio."""
    base, params = _consulta_filtrada(f)
    return leer(f"""
        SELECT id_comercio, nombre_corto AS comercio,
               COUNT(*)                                       AS productos,
               SUM(precio IS NOT NULL)                        AS con_precio,
               SUM(disponibilidad = 'agotado')                AS agotados,
               SUM(promocion = 1)                             AS en_promocion,
               ROUND(100.0 * SUM(promocion = 1) / NULLIF(SUM(precio IS NOT NULL), 0), 1)
                                                              AS pct_promocion,
               MIN(fecha_consulta)                            AS desde,
               MAX(fecha_consulta)                            AS hasta
        FROM ({base})
        GROUP BY id_comercio, nombre_corto
        ORDER BY nombre_corto""", params)


def observaciones_por_comercio(f: Filtros) -> pd.DataFrame:
    """Todas las observaciones del periodo (sin quedarse con la última de cada anuncio)."""
    base, params = _consulta_filtrada(f, solo_ultima=False)
    return leer(f"""
        SELECT nombre_corto AS comercio, COUNT(*) AS observaciones,
               COUNT(DISTINCT id_ejecucion) AS ejecuciones
        FROM ({base})
        GROUP BY nombre_corto ORDER BY nombre_corto""", params)


def mediana_por_subcategoria(f: Filtros) -> pd.DataFrame:
    """Mediana del precio por subcategoría. SQLite no tiene MEDIAN: se usa ROW_NUMBER."""
    base, params = _consulta_filtrada(f)
    return leer(f"""
        WITH ordenados AS (
            SELECT subcategoria, precio,
                   ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS fila,
                   COUNT(*)     OVER (PARTITION BY subcategoria)                  AS n
            FROM ({base})
            WHERE precio IS NOT NULL AND subcategoria IS NOT NULL
        )
        SELECT subcategoria, n AS productos, AVG(precio) AS mediana
        FROM ordenados
        WHERE fila IN ((n + 1) / 2, (n + 2) / 2)
        GROUP BY subcategoria, n
        ORDER BY mediana DESC""", params)


def ahorro_por_producto(f: Filtros) -> pd.DataFrame:
    """
    Para cada presentación comparable con precio en al menos dos comercios: precio
    mínimo y máximo, ahorro (máximo - mínimo) y dónde está más barata. Si dos comercios
    empatan en el mínimo, aparecen los dos ("La Rebaja / Locatel").
    Solo cuentan los anuncios disponibles: un agotado suele conservar el precio publicado,
    pero no se puede comprar (igual que en la canasta).
    """
    base, params = _consulta_filtrada(f, solo_comparables=True)
    return leer(f"""
        WITH por_comercio AS (
            SELECT id_producto, id_comercio, nombre_corto, MIN(precio) AS precio
            FROM ({base})
            WHERE precio IS NOT NULL AND id_producto IS NOT NULL
              AND disponibilidad = 'disponible'
            GROUP BY id_producto, id_comercio, nombre_corto
        ),
        rango AS (
            SELECT id_producto, MIN(precio) AS minimo, MAX(precio) AS maximo,
                   COUNT(*) AS comercios
            FROM por_comercio
            GROUP BY id_producto
            HAVING COUNT(*) >= 2
        )
        SELECT r.id_producto, p.descripcion AS producto, r.comercios,
               r.minimo, r.maximo,
               r.maximo - r.minimo                                    AS ahorro,
               ROUND(100.0 * (r.maximo - r.minimo) / r.maximo, 1)     AS ahorro_pct,
               (SELECT GROUP_CONCAT(pc.nombre_corto, ' / ') FROM por_comercio pc
                WHERE pc.id_producto = r.id_producto AND pc.precio = r.minimo) AS mas_barato,
               (SELECT GROUP_CONCAT(pc.nombre_corto, ' / ') FROM por_comercio pc
                WHERE pc.id_producto = r.id_producto AND pc.precio = r.maximo) AS mas_caro
        FROM rango r
        JOIN productos p ON p.id_producto = r.id_producto
        ORDER BY ahorro DESC, r.id_producto""", params)


def cambios_en_ejecucion(id_ejecucion: str, comercios_elegidos: tuple[str, ...] = ()) -> pd.DataFrame:
    """Cambios de precio de una ejecución frente a la observación anterior del mismo anuncio."""
    condiciones, params = ["id_ejecucion = ?"], [validar_ejecucion(id_ejecucion)]
    if comercios_elegidos:
        condiciones.append(f"id_comercio IN ({_marcas(comercios_elegidos)})")
        params.extend(comercios_elegidos)
    return leer(f"""
        SELECT comercio, SUM(direccion = 'subió') AS subieron, SUM(direccion = 'bajó') AS bajaron,
               COUNT(*) AS cambios
        FROM v_cambios_precio
        WHERE {' AND '.join(condiciones)}
        GROUP BY comercio ORDER BY comercio""", params)


# ---------------------------------------------------------------------------
# Datos para los gráficos (§7.4)
# ---------------------------------------------------------------------------
def evolucion_precio(id_producto: str, comercios_elegidos: tuple[str, ...] = (),
                     fecha_desde: str | None = None, fecha_hasta: str | None = None) -> pd.DataFrame:
    """Gráfico 1: precio de una presentación comparable en cada ejecución, por comercio."""
    if not ID_PRODUCTO.fullmatch(str(id_producto)):
        raise EntradaInvalida(f"Producto no válido: {id_producto!r}")
    condiciones, params = ["id_producto = ?", "precio IS NOT NULL"], [id_producto]
    if comercios_elegidos:
        condiciones.append(f"id_comercio IN ({_marcas(comercios_elegidos)})")
        params.extend(comercios_elegidos)
    if fecha_desde:
        condiciones.append("SUBSTR(fecha_consulta, 1, 10) >= ?")
        params.append(str(fecha_desde))
    if fecha_hasta:
        condiciones.append("SUBSTR(fecha_consulta, 1, 10) <= ?")
        params.append(str(fecha_hasta))
    return leer(f"""
        SELECT comercio, id_ejecucion, fecha_consulta, precio, precio_lista, promocion,
               precio_unitario, unidad_normalizada, producto
        FROM v_comparables
        WHERE {' AND '.join(condiciones)}
        ORDER BY comercio, fecha_consulta""", params)


def precio_unitario_comparables(f: Filtros) -> pd.DataFrame:
    """Gráfico 2: precio por mL, g o unidad de las presentaciones comparables disponibles."""
    base, params = _consulta_filtrada(f, solo_comparables=True)
    return leer(f"""
        SELECT b.nombre_corto AS comercio, b.id_producto, p.descripcion AS producto,
               p.contenido_total, p.unidad_normalizada,
               b.precio, b.precio / p.contenido_total AS precio_unitario, b.fecha_consulta
        FROM ({base}) b
        JOIN productos p ON p.id_producto = b.id_producto
        WHERE b.precio IS NOT NULL AND p.contenido_total IS NOT NULL
          AND b.disponibilidad = 'disponible'
        ORDER BY p.unidad_normalizada, b.id_producto, b.nombre_corto""", params)


def precios_para_distribucion(f: Filtros) -> pd.DataFrame:
    """Gráfico 3: precios de la categoría filtrada (plotly dibuja la caja por comercio)."""
    base, params = _consulta_filtrada(f)
    return leer(f"""SELECT nombre_corto AS comercio, precio, nombre_original AS nombre
                    FROM ({base}) WHERE precio IS NOT NULL""", params)


def mas_barato_mismo_ean(f: Filtros) -> pd.DataFrame:
    """
    Gráfico 4 (libre, DECISIÓN de Marlon): entre los productos con el MISMO código de
    barras (EAN válido) en todos los comercios elegidos, ¿cuántas veces es más barato
    cada comercio? Si hay empate en el precio mínimo, el producto cuenta como 'Empate'.
    Solo cuentan los anuncios disponibles, como en la canasta.
    """
    base, params = _consulta_filtrada(f)
    return leer(f"""
        WITH precios AS (
            SELECT b.ean, b.id_comercio, MIN(b.precio) AS precio
            FROM ({base}) b
            JOIN anuncios a ON a.id_comercio = b.id_comercio AND a.sku_comercio = b.sku_comercio
            WHERE b.precio IS NOT NULL AND a.ean_valido = 1
              AND b.disponibilidad = 'disponible'
            GROUP BY b.ean, b.id_comercio
        ),
        en_todos AS (
            SELECT ean, MIN(precio) AS minimo
            FROM precios
            GROUP BY ean
            HAVING COUNT(*) = (SELECT COUNT(DISTINCT id_comercio) FROM precios)
               AND COUNT(*) >= 2
        ),
        ganadores AS (
            SELECT p.ean, p.id_comercio,
                   COUNT(*) OVER (PARTITION BY p.ean) AS empatados
            FROM precios p
            JOIN en_todos t ON t.ean = p.ean AND p.precio = t.minimo
        )
        SELECT CASE WHEN g.empatados > 1 THEN 'Empate' ELSE c.nombre_corto END AS mas_barato,
               COUNT(DISTINCT g.ean) AS productos,
               (SELECT COUNT(*) FROM en_todos) AS productos_comparados
        FROM ganadores g
        JOIN comercios c ON c.id_comercio = g.id_comercio
        GROUP BY 1
        ORDER BY productos DESC""", params)


# ---------------------------------------------------------------------------
# Cambios de precio entre dos ejecuciones (§8.2)
# ---------------------------------------------------------------------------
def cambios_entre(id_anterior: str, id_posterior: str,
                  comercios_elegidos: tuple[str, ...] = ()) -> pd.DataFrame:
    """
    Compara el MISMO anuncio (comercio + SKU) en dos ejecuciones. Tipo de cada fila:
    'subió', 'bajó', 'sin cambio', 'sin precio' (agotado en alguna de las dos), 'nuevo'
    (solo en la posterior) o 'dejó de observarse' (solo en la anterior). Solo se comparan
    los comercios que no fallaron en ninguna de las dos ejecuciones.
    """
    a, b = validar_ejecucion(id_anterior), validar_ejecucion(id_posterior)
    filtro_comercio, params_comercio = "", []
    if comercios_elegidos:
        filtro_comercio = f"AND o.id_comercio IN ({_marcas(comercios_elegidos)})"
        params_comercio = list(comercios_elegidos)
    params = [a, b, a, *params_comercio, b, *params_comercio]
    return leer(f"""
        WITH validos AS (
            SELECT id_comercio FROM ejecuciones WHERE id_ejecucion = ? AND estado <> 'fallida'
            INTERSECT
            SELECT id_comercio FROM ejecuciones WHERE id_ejecucion = ? AND estado <> 'fallida'
        ),
        obs_a AS (
            SELECT o.id_comercio, o.sku_comercio, o.precio
            FROM observaciones o
            WHERE o.id_ejecucion = ? AND o.descartada = 0
              AND o.id_comercio IN (SELECT id_comercio FROM validos) {filtro_comercio}
        ),
        obs_b AS (
            SELECT o.id_comercio, o.sku_comercio, o.precio
            FROM observaciones o
            WHERE o.id_ejecucion = ? AND o.descartada = 0
              AND o.id_comercio IN (SELECT id_comercio FROM validos) {filtro_comercio}
        ),
        pares AS (
            SELECT x.id_comercio, x.sku_comercio, x.precio AS precio_anterior,
                   y.precio AS precio_posterior, 1 AS en_anterior,
                   y.sku_comercio IS NOT NULL AS en_posterior
            FROM obs_a x
            LEFT JOIN obs_b y ON y.id_comercio = x.id_comercio AND y.sku_comercio = x.sku_comercio
            UNION ALL
            SELECT y.id_comercio, y.sku_comercio, NULL, y.precio, 0, 1
            FROM obs_b y
            WHERE NOT EXISTS (SELECT 1 FROM obs_a x
                              WHERE x.id_comercio = y.id_comercio
                                AND x.sku_comercio = y.sku_comercio)
        )
        SELECT c.nombre_corto AS comercio, p.sku_comercio, an.nombre_original AS nombre,
               an.id_producto, an.subcategoria,
               p.precio_anterior, p.precio_posterior,
               p.precio_posterior - p.precio_anterior                                  AS cambio_cop,
               ROUND(100.0 * (p.precio_posterior - p.precio_anterior) / p.precio_anterior, 2)
                                                                                       AS cambio_pct,
               CASE WHEN p.en_anterior = 0  THEN 'nuevo'
                    WHEN p.en_posterior = 0 THEN 'dejó de observarse'
                    WHEN p.precio_anterior IS NULL OR p.precio_posterior IS NULL THEN 'sin precio'
                    WHEN p.precio_posterior > p.precio_anterior THEN 'subió'
                    WHEN p.precio_posterior < p.precio_anterior THEN 'bajó'
                    ELSE 'sin cambio' END                                              AS tipo,
               an.url_producto
        FROM pares p
        JOIN anuncios  an ON an.id_comercio = p.id_comercio AND an.sku_comercio = p.sku_comercio
        JOIN comercios c  ON c.id_comercio = p.id_comercio
        ORDER BY ABS(cambio_pct) DESC, c.nombre_corto, an.nombre_original""", params)


# ---------------------------------------------------------------------------
# Canasta (§8.3)
# ---------------------------------------------------------------------------
@dataclass
class Canasta:
    detalle: pd.DataFrame          # un producto por fila: precio mínimo y dónde comprarlo
    precios: pd.DataFrame          # precio de cada producto en cada comercio
    por_comercio: pd.DataFrame     # total por comercio (NULL si le falta algún producto)
    costo_minimo: float | None     # comprando cada producto donde es más barato
    mejores_comercios: list[str]   # comercio(s) con el menor total completo (puede haber empate)
    ahorro: float | None           # mejor comercio único - costo mínimo


def _validar_cantidades(cantidades: dict[str, int]) -> list[tuple[str, int]]:
    filas = []
    for id_producto, cantidad in cantidades.items():
        if not ID_PRODUCTO.fullmatch(str(id_producto)):
            raise EntradaInvalida(f"Producto no válido: {id_producto!r}")
        cantidad = int(cantidad)
        if not 1 <= cantidad <= CANTIDAD_MAXIMA:
            raise EntradaInvalida(f"La cantidad debe estar entre 1 y {CANTIDAD_MAXIMA}.")
        filas.append((str(id_producto), cantidad))
    if not filas:
        raise EntradaInvalida("La canasta está vacía.")
    return filas


def canasta(id_ejecucion: str, cantidades: dict[str, int]) -> Canasta:
    """
    Costo de una canasta de presentaciones comparables con precios de UNA ejecución.
    Solo cuentan los precios de productos disponibles. Un comercio al que le falta algún
    producto no tiene total (queda NULL y se listan los faltantes).
    """
    filas = _validar_cantidades(cantidades)
    valores = ", ".join("(?, ?)" for _ in filas)
    params = [v for fila in filas for v in fila] + [validar_ejecucion(id_ejecucion)]
    cte = f"""
        WITH canasta (id_producto, cantidad) AS (VALUES {valores}),
        precios AS (
            SELECT c.id_comercio, c.id_producto, MIN(c.precio) AS precio
            FROM v_comparables c
            WHERE c.id_ejecucion = ? AND c.precio IS NOT NULL AND c.disponibilidad = 'disponible'
              AND c.id_producto IN (SELECT id_producto FROM canasta)
            GROUP BY c.id_comercio, c.id_producto
        ),
        minimos AS (
            SELECT id_producto, MIN(precio) AS precio_minimo FROM precios GROUP BY id_producto
        ),
        costo AS (
            SELECT CASE WHEN COUNT(m.id_producto) = (SELECT COUNT(*) FROM canasta)
                        THEN SUM(m.precio_minimo * k.cantidad) END AS costo_minimo
            FROM canasta k LEFT JOIN minimos m ON m.id_producto = k.id_producto
        )"""
    detalle = leer(cte + """
        SELECT k.id_producto, pr.descripcion AS producto, k.cantidad,
               m.precio_minimo, m.precio_minimo * k.cantidad AS subtotal_minimo,
               (SELECT GROUP_CONCAT(co.nombre_corto, ' / ') FROM precios p2
                JOIN comercios co ON co.id_comercio = p2.id_comercio
                WHERE p2.id_producto = k.id_producto AND p2.precio = m.precio_minimo) AS donde_comprar
        FROM canasta k
        JOIN productos pr ON pr.id_producto = k.id_producto
        LEFT JOIN minimos m ON m.id_producto = k.id_producto
        ORDER BY k.id_producto""", params)
    precios = leer(cte + """
        SELECT co.nombre_corto AS comercio, p.id_producto, p.precio, p.precio * k.cantidad AS subtotal
        FROM precios p
        JOIN canasta k ON k.id_producto = p.id_producto
        JOIN comercios co ON co.id_comercio = p.id_comercio
        ORDER BY p.id_producto, co.nombre_corto""", params)
    por_comercio = leer(cte + """
        SELECT co.nombre_corto AS comercio,
               COUNT(p.id_producto)                AS productos_con_precio,
               (SELECT COUNT(*) FROM canasta)      AS productos_pedidos,
               CASE WHEN COUNT(p.id_producto) = (SELECT COUNT(*) FROM canasta)
                    THEN SUM(p.precio * k.cantidad) END AS total,
               CASE WHEN COUNT(p.id_producto) = (SELECT COUNT(*) FROM canasta)
                    THEN SUM(p.precio * k.cantidad) - (SELECT costo_minimo FROM costo) END
                                                   AS sobrecosto_frente_al_minimo,
               (SELECT GROUP_CONCAT(k2.id_producto, ', ') FROM canasta k2
                WHERE NOT EXISTS (SELECT 1 FROM precios p2
                                  WHERE p2.id_comercio = co.id_comercio
                                    AND p2.id_producto = k2.id_producto)) AS faltantes
        FROM comercios co
        CROSS JOIN canasta k
        LEFT JOIN precios p ON p.id_comercio = co.id_comercio AND p.id_producto = k.id_producto
        WHERE co.activo = 1
        GROUP BY co.id_comercio, co.nombre_corto
        ORDER BY total IS NULL, total, co.nombre_corto""", params)
    costo = leer(cte + "SELECT costo_minimo FROM costo", params).at[0, "costo_minimo"]
    costo_minimo = None if pd.isna(costo) else float(costo)

    completos = por_comercio.dropna(subset=["total"])
    mejores, ahorro = [], None
    if not completos.empty:
        mejor_total = completos["total"].min()
        mejores = completos.loc[completos["total"] == mejor_total, "comercio"].tolist()
        if costo_minimo is not None:
            ahorro = float(mejor_total) - costo_minimo
    return Canasta(detalle=detalle, precios=precios, por_comercio=por_comercio,
                   costo_minimo=costo_minimo, mejores_comercios=mejores, ahorro=ahorro)


# ---------------------------------------------------------------------------
# Página de datos y calidad
# ---------------------------------------------------------------------------
def resumen_ejecuciones() -> pd.DataFrame:
    return leer("""SELECT id_ejecucion, comercio, modo, estado, inicio, fin, recolectados, nuevos,
                          cambios_precio, no_observados, rechazados, detalle
                   FROM v_resumen_ejecucion ORDER BY inicio DESC, comercio""")


def disponibilidad(id_ejecucion: str) -> pd.DataFrame:
    """Disponibles, agotados y no observados por comercio en una ejecución (§3.5)."""
    return leer("""
        SELECT c.nombre_corto AS comercio, d.situacion, COUNT(*) AS anuncios
        FROM v_disponibilidad d
        JOIN comercios c ON c.id_comercio = d.id_comercio
        WHERE d.id_ejecucion = ?
        GROUP BY c.nombre_corto, d.situacion
        ORDER BY c.nombre_corto, d.situacion""", [validar_ejecucion(id_ejecucion)])


def validaciones(id_ejecucion: str | None = None) -> pd.DataFrame:
    condicion, params = "", []
    if id_ejecucion:
        condicion, params = "WHERE v.id_ejecucion = ?", [validar_ejecucion(id_ejecucion)]
    return leer(f"""
        SELECT v.id_ejecucion, c.nombre_corto AS comercio, v.regla, v.n_revisadas, v.n_fallas,
               v.aprobada, v.detalle, v.fecha
        FROM validaciones v JOIN comercios c ON c.id_comercio = v.id_comercio
        {condicion}
        ORDER BY v.id_ejecucion DESC, c.nombre_corto, v.regla""", params)


def rechazos() -> pd.DataFrame:
    return leer("""SELECT r.id_ejecucion, c.nombre_corto AS comercio, r.sku_comercio,
                          r.fecha_consulta, r.precio, r.motivo, r.url_extraccion
                   FROM rechazos r LEFT JOIN comercios c ON c.id_comercio = r.id_comercio
                   ORDER BY r.id_ejecucion DESC, comercio""")


def correcciones(tabla: str | None = None, campo: str | None = None) -> pd.DataFrame:
    condiciones, params = ["1 = 1"], []
    if tabla:
        condiciones.append("tabla = ?")
        params.append(tabla)
    if campo:
        condiciones.append("campo = ?")
        params.append(campo)
    return leer(f"""SELECT id_correccion, fecha, tabla, registro, campo, valor_anterior,
                           valor_nuevo, motivo, origen
                    FROM correcciones WHERE {' AND '.join(condiciones)}
                    ORDER BY id_correccion""", params)


def correcciones_resumen() -> pd.DataFrame:
    return leer("""SELECT tabla, campo, COUNT(*) AS cambios FROM correcciones
                   GROUP BY tabla, campo ORDER BY tabla, campo""")
