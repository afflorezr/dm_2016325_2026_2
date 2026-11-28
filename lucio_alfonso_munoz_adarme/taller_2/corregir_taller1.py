## Coregimos la base del taller 1 

import sys

import pandas as pd

import scraper
import validacion

EJECUCIONES_T1 = ("20261011T112336", "20261011T114310")
HOY = scraper.ahora_iso()
CAMPOS = {  
    "url": "Farmatodo no publica url en algunos productos; se arma con urlCanonical",
    "contenido": "el nombre trae las unidades como 'Caja x N' o 'N Tab' y no se reconocían",
    "unidad": "el nombre trae las unidades como 'Caja x N' o 'N Tab' y no se reconocían",
    "unidades_empaque": "el nombre trae las unidades como 'Caja x N' o 'N Tab' y no se reconocían",
}


def corregir(con, tabla, id_registro, campo, anterior, nuevo, motivo):
    id_registro = int(id_registro)
    llave = "id_anuncio" if tabla == "anuncios" else "id_observacion"
    if tabla == "productos":
        con.execute(f"UPDATE productos SET {campo} = ? WHERE rowid = ?", (nuevo, id_registro))
    else:
        con.execute(f"UPDATE {tabla} SET {campo} = ? WHERE {llave} = ?", (nuevo, id_registro))
    con.execute("""INSERT INTO correcciones (fecha, tabla, id_registro, campo, valor_anterior, valor_nuevo, motivo)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (HOY, tabla, id_registro, campo, None if anterior is None else str(anterior),
                 None if nuevo is None else str(nuevo), motivo))


def copiar_taller1(con, ruta):
    con.execute("ATTACH DATABASE ? AS t1", (str(ruta),))
    marcas = ",".join("?" * len(EJECUCIONES_T1))
    with con:
        con.execute("INSERT INTO productos SELECT * FROM t1.productos")
        con.execute(f"""INSERT INTO anuncios SELECT * FROM t1.anuncios WHERE id_anuncio IN
                        (SELECT id_anuncio FROM t1.observaciones WHERE id_ejecucion IN ({marcas}))""", EJECUCIONES_T1)
        con.execute(f"""INSERT INTO ejecuciones SELECT id_ejecucion, comercio, inicio, fin, registros, en_categoria,
                        total_sitio, estado, carpeta_raw, NULL, 0, NULL, NULL
                        FROM t1.ejecuciones WHERE id_ejecucion IN ({marcas})""", EJECUCIONES_T1)
        # disponible (1/0) del Taller 1 pasa a la columna de texto disponibilidad
        con.execute(f"""INSERT INTO observaciones (id_observacion, id_anuncio, id_ejecucion, precio, precio_antes,
                            promocion, disponibilidad, vendedor, fecha_consulta)
                        SELECT id_observacion, id_anuncio, id_ejecucion, precio, precio_antes, promocion,
                               CASE WHEN disponible = 1 THEN 'disponible' ELSE 'agotado' END, vendedor, fecha_consulta
                        FROM t1.observaciones WHERE id_ejecucion IN ({marcas})""", EJECUCIONES_T1)
    con.execute("DETACH DATABASE t1")


def corregir_desde_raw(con):
    """Vuelve a leer las copias de raw/ con el código corregido y registra lo que cambia."""
    anuncios = pd.read_sql("SELECT * FROM anuncios", con).set_index(["comercio", "id_producto_comercio", "sku"])
    obs = pd.read_sql("SELECT id_observacion, id_anuncio, id_ejecucion, disponibilidad FROM observaciones", con)
    obs = obs.set_index(["id_anuncio", "id_ejecucion"])
    vistos = set()
    for comercio in scraper.COMERCIOS:
        for id_ej in EJECUCIONES_T1:
            carpeta = next((scraper.RAW / scraper.CLAVES[comercio]).glob(f"*/{id_ej}"))
            df, _ = scraper.RECOLECTORES[comercio](online=False, carpeta=carpeta)
            df = scraper.limpiar(df)
            for r in df.itertuples():
                a = anuncios.loc[(comercio, str(r.id_producto), str(r.sku))]
                if a.name not in vistos:
                    vistos.add(a.name)
                    for campo, motivo in CAMPOS.items():
                        nuevo = getattr(r, campo)
                        nuevo = None if pd.isna(nuevo) else nuevo
                        anterior = None if pd.isna(a[campo]) else a[campo]
                        if nuevo != anterior:
                            corregir(con, "anuncios", a["id_anuncio"], campo, anterior, nuevo, motivo)
                o = obs.loc[(a["id_anuncio"], id_ej)]
                if comercio == "Farmatodo" and o["disponibilidad"] != r.disponibilidad:
                    corregir(con, "observaciones", o["id_observacion"], "disponibilidad", o["disponibilidad"],
                             r.disponibilidad, "hasStock siempre llega en False; se usa outofstore y stores_with_stock")


def descartar_invalidas(con):
    """Aplica las reglas de validación a las observaciones del Taller 1; las que no las cumplen se marcan."""
    df = pd.read_sql("""SELECT o.id_observacion, a.comercio, a.id_producto_comercio AS id_producto, a.sku, a.url,
                               o.fecha_consulta, o.precio, o.id_ejecucion
                        FROM observaciones o JOIN anuncios a ON a.id_anuncio = o.id_anuncio""", con)
    df["precio"] = df["precio"].astype(float)
    _, malas = validacion.validar(df)
    for r in malas.itertuples():
        corregir(con, "observaciones", r.id_observacion, "descartada", 0, 1, f"no cumple la validación: {r.motivo}")
        con.execute("UPDATE observaciones SET motivo_descarte = ? WHERE id_observacion = ?", (r.motivo, int(r.id_observacion)))


def completar_variantes(con):
    """Sabor faltante en presentaciones comparables: se toma del mismo producto (mismo EAN) en otro comercio."""
    grupos = pd.read_sql("""SELECT id_anuncio, comercio, id_producto_comun, variante FROM anuncios
                            WHERE comparable = 1 ORDER BY id_producto_comun, comercio""", con)
    for clave, g in grupos.groupby("id_producto_comun"):
        sabores = g["variante"].dropna()
        if sabores.empty:
            continue
        sabor = sabores.iloc[0]
        for r in g[g["variante"].isna()].itertuples():
            corregir(con, "anuncios", r.id_anuncio, "variante", None, sabor,
                     "sabor faltante; se toma del mismo producto (mismo EAN) en otro comercio")
        fila, variante, nombre, contenido, unidad = con.execute(
            "SELECT rowid, variante, nombre_comun, contenido, unidad FROM productos WHERE id_producto_comun = ?",
            (clave,)).fetchone()
        if variante is None:
            corregir(con, "productos", fila, "variante", None, sabor,
                     "sabor faltante; se toma del mismo producto (mismo EAN) en otro comercio")
            nuevo = nombre.replace(f" {contenido:g} {unidad}", f" {sabor} {contenido:g} {unidad}")
            corregir(con, "productos", fila, "nombre_comun", nombre, nuevo, "se agrega el sabor al nombre")


def completar_ejecuciones(con):
    con.execute("""UPDATE ejecuciones SET
                       insertadas = (SELECT COUNT(*) FROM observaciones o JOIN anuncios a USING (id_anuncio)
                                     WHERE o.id_ejecucion = ejecuciones.id_ejecucion AND a.comercio = ejecuciones.comercio),
                       rechazadas = (SELECT COUNT(*) FROM observaciones o JOIN anuncios a USING (id_anuncio)
                                     WHERE o.id_ejecucion = ejecuciones.id_ejecucion AND a.comercio = ejecuciones.comercio
                                       AND o.descartada = 1),
                       comparables = (SELECT COUNT(*) FROM observaciones o JOIN anuncios a USING (id_anuncio)
                                      WHERE o.id_ejecucion = ejecuciones.id_ejecucion AND a.comercio = ejecuciones.comercio
                                        AND a.comparable = 1 AND o.descartada = 0)""")
    con.execute("""UPDATE ejecuciones SET motivo = '16 búsquedas llegaron al tope de 24 resultados (categoría incompleta)'
                   WHERE comercio = 'Farmatodo' AND estado = 'parcial'""")


if __name__ == "__main__":
    con = scraper.conectar(scraper.BASE)
    copiar_taller1(con, sys.argv[1])
    with con:
        corregir_desde_raw(con)
        descartar_invalidas(con)
        completar_variantes(con)
        completar_ejecuciones(con)
    print(pd.read_sql("SELECT tabla, campo, motivo, COUNT(*) AS n FROM correcciones GROUP BY 1, 2, 3", con))
    con.close()
