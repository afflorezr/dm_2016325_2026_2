import sqlite3
from contextlib import closing

import pandas as pd
import streamlit as st

from scraper import BASE


def consultar(sql, params=(), db=BASE):
    """Abre la conexión, ejecuta la consulta con parámetros y la cierra."""
    with closing(sqlite3.connect(db)) as con:
        return pd.read_sql_query(sql, con, params=list(params))


def lista(valores):
    return ",".join("?" * len(valores))


@st.cache_data
def ejecuciones(db=BASE):
    return consultar("""SELECT e.*, (SELECT GROUP_CONCAT(comercio || ': ' || estado, ', ')
                                     FROM ejecuciones x WHERE x.id_ejecucion = e.id_ejecucion) AS estados
                        FROM v_ejecuciones e ORDER BY id_ejecucion DESC""", db=db)


@st.cache_data
def estado_ejecucion(id_ej, db=BASE):
    return consultar("""SELECT comercio, estado, inicio, registros, en_categoria, insertadas, rechazadas,
                               comparables, motivo
                        FROM ejecuciones WHERE id_ejecucion = ? ORDER BY comercio""", (id_ej,), db)


@st.cache_data
def opciones(db=BASE):
    sub = consultar("""SELECT DISTINCT subcategoria_std FROM anuncios
                       WHERE en_categoria = 1 AND subcategoria_std IS NOT NULL ORDER BY 1""", db=db)
    marcas = consultar("""SELECT DISTINCT marca_std FROM anuncios
                          WHERE en_categoria = 1 AND marca_std IS NOT NULL ORDER BY 1""", db=db)
    tope = consultar("""SELECT MAX(precio) FROM v_observaciones WHERE en_categoria = 1""", db=db).iloc[0, 0]
    return list(sub.iloc[:, 0]), list(marcas.iloc[:, 0]), float(tope or 0)


@st.cache_data
def productos_filtrados(id_ej, comercios, subcategorias, marcas, precio_min, precio_max,
                        solo_promocion, solo_comparables, texto, db=BASE):

    """Presentaciones de la categoría en una ejecución"""
    
    sql = f"""SELECT comercio, nombre, marca, subcategoria, contenido, unidad, precio, precio_unidad, precio_antes,
                     promocion, disponibilidad, fecha_consulta, url
              FROM v_observaciones
              WHERE id_ejecucion = ? AND en_categoria = 1 AND precio BETWEEN ? AND ?
                AND comercio IN ({lista(comercios)})"""
    params = [id_ej, precio_min, precio_max, *comercios]
    if subcategorias:
        sql += f" AND subcategoria IN ({lista(subcategorias)})"
        params += subcategorias
    if marcas:
        sql += f" AND marca IN ({lista(marcas)})"
        params += marcas
    if solo_promocion:
        sql += " AND promocion = 1"
    if solo_comparables:
        sql += " AND comparable = 1"
    if texto:
        sql += " AND (nombre LIKE ? OR texto_original LIKE ?)"
        params += [f"%{texto}%", f"%{texto}%"]
    return consultar(sql + " ORDER BY comercio, precio", params, db)


@st.cache_data
def indicadores(id_ej, db=BASE):
    """Indicadores de una ejecucin calculados en SQL"""
    return consultar("""
        WITH obs AS (SELECT * FROM v_observaciones WHERE id_ejecucion = ? AND en_categoria = 1)
        SELECT (SELECT COUNT(*) FROM obs) AS presentaciones,
               (SELECT COUNT(*) FROM v_observaciones) AS observaciones_base,
               (SELECT ROUND(100.0 * AVG(promocion), 1) FROM obs) AS pct_promocion,
               (SELECT COUNT(*) FROM v_cambios_precio WHERE id_ejecucion = ? AND en_categoria = 1) AS cambios,
               (SELECT MIN(inicio) FROM ejecuciones
                WHERE id_ejecucion = (SELECT MAX(id_ejecucion) FROM ejecuciones)) AS ultima_fecha
    """, (id_ej, id_ej), db).iloc[0]


@st.cache_data
def por_comercio(id_ej, db=BASE):
    return consultar("""
        SELECT e.comercio, e.estado, e.en_categoria AS presentaciones,
               (SELECT COUNT(*) FROM v_observaciones v WHERE v.comercio = e.comercio) AS observaciones_base,
               (SELECT ROUND(100.0 * AVG(v.promocion), 1) FROM v_observaciones v
                WHERE v.comercio = e.comercio AND v.id_ejecucion = e.id_ejecucion AND v.en_categoria = 1) AS pct_promocion
        FROM ejecuciones e WHERE e.id_ejecucion = ? ORDER BY e.comercio""", (id_ej,), db)


@st.cache_data
def mediana_por_subcategoria(id_ej, db=BASE):
    return consultar("""
        WITH x AS (
            SELECT subcategoria, precio,
                   ROW_NUMBER() OVER (PARTITION BY subcategoria ORDER BY precio) AS n,
                   COUNT(*) OVER (PARTITION BY subcategoria) AS total
            FROM v_observaciones
            WHERE id_ejecucion = ? AND en_categoria = 1 AND subcategoria IS NOT NULL)
        SELECT subcategoria, AVG(precio) AS mediana, MAX(total) AS presentaciones
        FROM x WHERE n IN ((total + 1) / 2, (total + 2) / 2)
        GROUP BY subcategoria ORDER BY mediana DESC""", (id_ej,), db)


@st.cache_data
def ahorro_comparables(id_ej, db=BASE):

    """Por presentación comparable: precio mínimo y máximo, ahoro y comercios con el mínimo"""

    return consultar("""
        WITH p AS (SELECT * FROM v_comparables WHERE id_ejecucion = ?),
        r AS (SELECT id_producto_comun, MIN(precio) AS pmin, MAX(precio) AS pmax, COUNT(*) AS comercios
              FROM p GROUP BY id_producto_comun HAVING COUNT(*) >= 2)
        SELECT p.producto, r.comercios, r.pmin AS precio_minimo, r.pmax AS precio_maximo,
               r.pmax - r.pmin AS ahorro_cop, ROUND(100.0 * (r.pmax - r.pmin) / r.pmax, 1) AS ahorro_pct,
               GROUP_CONCAT(CASE WHEN p.precio = r.pmin THEN p.comercio END, ', ') AS comprar_en,
               SUM(p.precio = r.pmin) AS empatados
        FROM p JOIN r ON r.id_producto_comun = p.id_producto_comun
        GROUP BY p.id_producto_comun ORDER BY ahorro_pct DESC""", (id_ej,), db)


@st.cache_data
def comparables(db=BASE):
    return consultar("""SELECT id_producto_comun, marca_std || ' ' || nombre_comun AS producto, unidad
                        FROM productos ORDER BY producto""", db=db)


@st.cache_data
def evolucion(id_producto_comun, db=BASE):
    return consultar("""SELECT fecha_consulta, id_ejecucion, comercio, precio, promocion, disponibilidad
                        FROM v_comparables WHERE id_producto_comun = ?
                        ORDER BY fecha_consulta""", (id_producto_comun,), db)


@st.cache_data
def precio_unidad_comparables(id_ej, unidad, db=BASE):

    """Precio por unidad de contenido de los comparables de una sola unidad (g, ml o und)."""

    return consultar("""SELECT producto, comercio, contenido, unidad, precio,
                               ROUND(precio / contenido, 2) AS precio_unidad
                        FROM v_comparables WHERE id_ejecucion = ? AND unidad = ?
                        ORDER BY producto, comercio""", (id_ej, unidad), db)


@st.cache_data
def disponibilidad_comparables(id_ej, db=BASE):
    return consultar("""SELECT comercio, disponibilidad, COUNT(*) AS comparables FROM v_disponibilidad
                        WHERE id_ejecucion = ? GROUP BY comercio, disponibilidad""", (id_ej,), db)


@st.cache_data
def cambios_precio(ej_a, ej_b, db=BASE):

    """Compara el mismo anuncio en el mismo comercio entre dos ejecuciones"""

    return consultar("""
        WITH validos AS (SELECT comercio FROM ejecuciones WHERE id_ejecucion IN (?, ?) AND estado != 'fallida'
                         GROUP BY comercio HAVING COUNT(*) = 2),
        a AS (SELECT * FROM v_observaciones WHERE id_ejecucion = ? AND en_categoria = 1
              AND comercio IN (SELECT comercio FROM validos)),
        b AS (SELECT * FROM v_observaciones WHERE id_ejecucion = ? AND en_categoria = 1
              AND comercio IN (SELECT comercio FROM validos)),
        unidos AS (
            SELECT a.id_anuncio, a.comercio, a.nombre, a.precio AS precio_a, b.precio AS precio_b
            FROM a LEFT JOIN b ON b.id_anuncio = a.id_anuncio
            UNION ALL
            SELECT b.id_anuncio, b.comercio, b.nombre, NULL, b.precio
            FROM b WHERE b.id_anuncio NOT IN (SELECT id_anuncio FROM a))
        SELECT comercio, nombre, precio_a, precio_b, precio_b - precio_a AS cambio_cop,
               ROUND(100.0 * (precio_b - precio_a) / precio_a, 1) AS cambio_pct,
               CASE WHEN precio_a IS NULL THEN 'nuevo'
                    WHEN precio_b IS NULL THEN 'ya no se observa'
                    WHEN precio_b > precio_a THEN 'subió'
                    WHEN precio_b < precio_a THEN 'bajó'
                    ELSE 'igual' END AS tipo
        FROM unidos ORDER BY ABS(cambio_pct) DESC""", (ej_a, ej_b, ej_a, ej_b), db)


@st.cache_data
def canasta(id_ej, cantidades, db=BASE):

    """Costo de la canasta por comercio """

    if not cantidades:
        return pd.DataFrame(), None
    valores = " UNION ALL ".join(["SELECT ? AS id_producto_comun, ? AS cantidad"] * len(cantidades))
    params = [x for par in cantidades for x in par]
    por_comercio = consultar(f"""
        WITH pedido AS ({valores}),
        precios AS (SELECT c.comercio, c.id_producto_comun, c.precio * p.cantidad AS subtotal
                    FROM v_comparables c JOIN pedido p ON p.id_producto_comun = c.id_producto_comun
                    WHERE c.id_ejecucion = ?)
        SELECT e.comercio, COUNT(x.id_producto_comun) AS productos,
               (SELECT COUNT(*) FROM pedido) - COUNT(x.id_producto_comun) AS faltan,
               CASE WHEN COUNT(x.id_producto_comun) = (SELECT COUNT(*) FROM pedido) THEN SUM(x.subtotal) END AS total
        FROM ejecuciones e LEFT JOIN precios x ON x.comercio = e.comercio
        WHERE e.id_ejecucion = ?
        GROUP BY e.comercio ORDER BY total IS NULL, total""", params + [id_ej, id_ej], db)
    minimo = consultar(f"""
        WITH pedido AS ({valores}),
        mejores AS (SELECT c.id_producto_comun, MIN(c.precio) * p.cantidad AS subtotal
                    FROM v_comparables c JOIN pedido p ON p.id_producto_comun = c.id_producto_comun
                    WHERE c.id_ejecucion = ? GROUP BY c.id_producto_comun)
        SELECT CASE WHEN COUNT(*) = (SELECT COUNT(*) FROM pedido) THEN SUM(subtotal) END FROM mejores""",
                       params + [id_ej], db).iloc[0, 0]
    return por_comercio, minimo
