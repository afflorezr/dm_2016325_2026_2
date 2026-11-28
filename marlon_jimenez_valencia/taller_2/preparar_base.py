"""
preparar_base.py — Construye la base del Taller 2 a partir de la del Taller 1.

Se corre una sola vez (o con --rehacer, que la borra y la vuelve a construir):

    python preparar_base.py
    python preparar_base.py --rehacer

Pasos:
  1. Crea comparador_precios.sqlite vacía con el esquema nuevo (esquema.sql).
  2. Copia TODAS las filas de la base del Taller 1 (../taller_01/comparador_precios.sqlite,
     que NO se modifica). La disponibilidad se deriva de la columna disponible que
     publicó el sitio: 1 -> 'disponible', 0 -> 'agotado'.
  3. Corrige la tabla productos con correspondencia.csv (verificada a mano) y anota
     cada cambio en la tabla correcciones.
  4. Reprocesa sin conexión todas las copias de raw/, en orden de fecha, con el
     scraper del Taller 2: valida cada observación (validacion.py), recalcula los
     campos estandarizados de los anuncios con las reglas corregidas de limpieza.py
     (cada cambio queda en correcciones) e inserta solo lo que no exista. Como todas
     las observaciones ya estaban, no debe insertarse ninguna.
  5. Comprueba que no se perdió ni se duplicó nada y muestra un resumen.
"""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

import pandas as pd

import scraper

BASE_DIR = Path(__file__).resolve().parent
ORIGEN = BASE_DIR.parent / "taller_01" / "comparador_precios.sqlite"
DESTINO = scraper.DB_PATH
ORIGEN_CORRECCION = "preparar_base.py"

# Tablas del Taller 1, en un orden que respeta las llaves foráneas
TABLAS = ["comercios", "ejecuciones", "productos", "anuncios", "correspondencia",
          "observaciones", "excluidos"]

# Motivo de cada corrección de la tabla productos (frente al Taller 1)
MOTIVOS_PRODUCTO = {
    ("P02", "laboratorio"): ("CLAVULIN es la marca, no el laboratorio. La Rebaja y Cafam publican "
                             "como laboratorio GLAXOSMITHKLINE (GSK)."),
    ("P02", "concentracion"): ("La concentración estaba en el orden contrario al del principio activo "
                               "(ACIDO CLAVULANICO + AMOXICILINA): son 125 mg de ácido clavulánico "
                               "y 875 mg de amoxicilina."),
    ("P08", "concentracion"): ("La concentración estaba en el orden contrario al del principio activo "
                               "(SULFAMETOXAZOL + TRIMETOPRIM): son 400 mg de sulfametoxazol y 80 mg "
                               "de trimetoprim (los comercios escriben 'Trimetoprim Sulfa 80/400')."),
    "descripcion": "La descripción se actualiza con los campos corregidos de la misma fila.",
    "contenido_total": ("Campo faltante en el Taller 1: contenido total de la presentación "
                        "(productos.contenido_ml quedaba vacío en los sólidos). Taller 2, §3.6."),
    "unidad_normalizada": ("Campo faltante en el Taller 1: unidad normalizada (mL, g o unidad) de la "
                           "presentación comparable. Taller 2, §3.6."),
}
CAMPOS_PRODUCTO = ["descripcion", "principio_activo", "concentracion", "forma", "laboratorio",
                   "unidades", "contenido_ml", "contenido_total", "unidad_normalizada"]


def titulo(texto: str) -> None:
    print(f"\n{'=' * 78}\n{texto}\n{'=' * 78}", flush=True)


def copiar_taller_1(con: sqlite3.Connection) -> dict[str, int]:
    """Paso 2: copia las filas de cada tabla del Taller 1, columna por columna."""
    con.execute("ATTACH DATABASE ? AS t1", (str(ORIGEN),))
    conteos = {}
    with con:
        for tabla in TABLAS:
            columnas = [c[1] for c in con.execute(f"PRAGMA t1.table_info({tabla})")]
            lista = ", ".join(columnas)
            if tabla == "observaciones":
                con.execute(f"""INSERT INTO main.observaciones ({lista}, disponibilidad)
                                SELECT {lista},
                                       CASE disponible WHEN 1 THEN 'disponible' ELSE 'agotado' END
                                FROM t1.observaciones""")
            else:
                con.execute(f"INSERT INTO main.{tabla} ({lista}) SELECT {lista} FROM t1.{tabla}")
            conteos[tabla] = con.execute(f"SELECT COUNT(*) FROM t1.{tabla}").fetchone()[0]
            nuevas = con.execute(f"SELECT COUNT(*) FROM main.{tabla}").fetchone()[0]
            print(f"  {tabla:16s} {conteos[tabla]:6d} filas en el Taller 1 -> {nuevas:6d} copiadas")
        scraper._registrar_comercios(con, scraper.COMERCIOS)    # nombre_corto y activo
    con.execute("DETACH DATABASE t1")
    return conteos


def corregir_productos(con: sqlite3.Connection) -> int:
    """Paso 3: compara productos con correspondencia.csv y corrige (con registro) lo distinto."""
    csv = pd.read_csv(scraper.CORRESPONDENCIA_PATH, dtype=str, keep_default_na=False)
    csv = csv[csv["verificado"].str.strip() == "1"].drop_duplicates("id_producto")
    n = 0
    with con:
        for p in csv.to_dict("records"):
            actual = dict(zip(CAMPOS_PRODUCTO, con.execute(
                f"SELECT {', '.join(CAMPOS_PRODUCTO)} FROM productos WHERE id_producto = ?",
                (p["id_producto"],)).fetchone()))
            for campo in CAMPOS_PRODUCTO:
                nuevo = p[campo] or None
                if campo in ("unidades",) and nuevo is not None:
                    nuevo = int(nuevo)
                if campo in ("contenido_ml", "contenido_total") and nuevo is not None:
                    nuevo = float(nuevo)
                if scraper._texto(actual[campo]) == scraper._texto(nuevo):
                    continue
                motivo = (MOTIVOS_PRODUCTO.get((p["id_producto"], campo))
                          or MOTIVOS_PRODUCTO.get(campo))
                if motivo is None:
                    raise ValueError(f"{p['id_producto']}.{campo} cambia y no tiene motivo escrito")
                scraper.registrar_correccion(con, "productos", p["id_producto"], campo,
                                             actual[campo], nuevo, motivo, ORIGEN_CORRECCION)
                con.execute(f"UPDATE productos SET {campo} = ? WHERE id_producto = ?",
                            (nuevo, p["id_producto"]))
                print(f"  {p['id_producto']}.{campo}: {actual[campo]!r} -> {nuevo!r}")
                n += 1
    return n


def reprocesar_raw(con: sqlite3.Connection) -> pd.DataFrame:
    """Paso 4: reprocesa cada copia de raw/ (sin conexión) con validación y registro."""
    copias = scraper.copias_en_raw()
    comparables = scraper.comparables_por_comercio()
    resumen = []
    for c in copias.itertuples(index=False):
        r = scraper.actualizar_comercio(con, c.id_comercio, c.id_ejecucion, sin_conexion=True,
                                        comparables=comparables)
        resumen.append(r)
        print(f"  {c.id_ejecucion} {c.id_comercio:9s} {r['estado']:9s} "
              f"recolectados={r['recolectados']:4d}  insertadas={r['observaciones_nuevas']:3d}  "
              f"rechazadas={r['rechazadas']:3d}" + (f"  | {r['motivo']}" if r["motivo"] else ""),
              flush=True)
    return pd.DataFrame(resumen)


def comprobar(con: sqlite3.Connection, conteos: dict[str, int]) -> bool:
    """Paso 5: nada perdido ni duplicado, llaves foráneas e integridad."""
    bien = True
    for tabla in ("observaciones", "anuncios", "ejecuciones"):
        ahora = con.execute(f"SELECT COUNT(*) FROM {tabla}").fetchone()[0]
        ok = ahora == conteos[tabla]
        bien &= ok
        print(f"  {tabla:14s} Taller 1 = {conteos[tabla]:5d}   Taller 2 = {ahora:5d}   "
              f"{'OK' if ok else 'DIFERENTE'}")
    fk = con.execute("PRAGMA foreign_key_check").fetchall()
    integridad = con.execute("PRAGMA integrity_check").fetchone()[0]
    print(f"  llaves foráneas rotas: {len(fk)}   integridad: {integridad}")
    return bien and not fk and integridad == "ok"


def main() -> None:
    parser = argparse.ArgumentParser(description="Construye la base del Taller 2 desde la del Taller 1")
    parser.add_argument("--rehacer", action="store_true",
                        help="borra comparador_precios.sqlite del Taller 2 y la vuelve a construir")
    args = parser.parse_args()

    if not ORIGEN.exists():
        raise SystemExit(f"No encuentro la base del Taller 1 en {ORIGEN}")
    if DESTINO.exists():
        if not args.rehacer:
            raise SystemExit(f"{DESTINO.name} ya existe. Usa --rehacer para construirla de nuevo.")
        DESTINO.unlink()

    titulo("1. Base vacía con el esquema nuevo (esquema.sql)")
    con = scraper.conectar(DESTINO)
    tablas = [r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' "
        "ORDER BY type, name")]
    print("  " + ", ".join(tablas))

    titulo("2. Copia de las filas del Taller 1 (la base del Taller 1 no se modifica)")
    conteos = copiar_taller_1(con)

    titulo("3. Correcciones a la tabla productos (desde correspondencia.csv)")
    print(f"  {corregir_productos(con)} campos corregidos")

    titulo("4. Reproceso sin conexión de raw/ con validación (no debe insertar nada nuevo)")
    resumen = reprocesar_raw(con)

    titulo("5. Comprobaciones")
    bien = comprobar(con, conteos)
    print("\n  Correcciones registradas, por tabla y campo:")
    for tabla, campo, n in con.execute(
            "SELECT tabla, campo, COUNT(*) FROM correcciones GROUP BY 1, 2 ORDER BY 1, 2"):
        print(f"    {tabla:14s} {campo:20s} {n:5d}")
    print("\n  Reglas de validación que fallaron (ejecución, comercio, regla, detalle):")
    fallas = con.execute("SELECT id_ejecucion, id_comercio, regla, detalle FROM validaciones "
                         "WHERE aprobada = 0 ORDER BY 1, 2, 3").fetchall()
    for f in fallas:
        print(f"    {f[0]} {f[1]:9s} {f[2]:30s} {f[3]}")
    if not fallas:
        print("    ninguna")
    print(f"\n  Rechazos: {con.execute('SELECT COUNT(*) FROM rechazos').fetchone()[0]}   "
          f"Observaciones descartadas: "
          f"{con.execute('SELECT COUNT(*) FROM observaciones WHERE descartada = 1').fetchone()[0]}   "
          f"Observaciones insertadas en el reproceso: {int(resumen['observaciones_nuevas'].sum())}")
    print("\n  Ejecuciones completas en los 3 comercios:")
    for fila in con.execute("SELECT id_ejecucion, fecha FROM v_ejecuciones_completas ORDER BY 1"):
        print(f"    {fila[0]}  ({fila[1]})")
    con.execute("VACUUM")
    con.close()
    print(f"\n{'LISTO' if bien else 'REVISAR: hay diferencias'}: {DESTINO.name}")


if __name__ == "__main__":
    main()
