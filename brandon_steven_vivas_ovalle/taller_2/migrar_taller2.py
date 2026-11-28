"""
migrar_taller2.py - Lleva la base del Taller 1 al esquema del Taller 2 SIN borrar ni inventar datos.

Qué hace (idempotente: se puede ejecutar varias veces)
  1. Crea tablas nuevas (correcciones, observaciones_rechazadas), columnas (estado_disponibilidad, raw_archivo,
     n_rechazadas), índices, restricción de unicidad (ejecución, anuncio) y las vistas SQL (db.preparar_base).
  2. Aplica y REGISTRA en `correcciones` los errores detectados al revisar la base del Taller 1 (sección 3.2):
       a. comercios.url_base de Jumbo apuntaba a un dominio antiguo (tiendasjumbo.co) distinto del que realmente
          se consultó (jumbocolombia.com, el de todas las URL de sus anuncios).
       b. Anuncios de vendedores externos ("Otros vendedores", marketplace) marcados como comparables: el precio
          comparable debe ser el de la oferta propia del comercio.
     No se borra ninguna observación: solo se corrigen campos estandarizados.
  3. (Opcional, --raw raw) enlaza cada observación con su copia cruda: llena observaciones.raw_archivo y verifica que
     el precio de la observación coincida con el de la respuesta original.

Uso:
    python migrar_taller2.py                       # migra comparador_precios.sqlite
    python migrar_taller2.py --raw raw             # además enlaza y verifica contra raw/
"""
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from urllib.parse import urlsplit

import db
import scraper as S

AUTOR = "migrar_taller2.py"


def _hoy() -> str:
    return S.ahora_iso()


def corregir_url_base(con) -> int:
    n = 0
    for clave, cfg in S.COMERCIOS.items():
        fila = con.execute("SELECT comercio_id, url_base FROM comercios WHERE clave = ?", [clave]).fetchone()
        if not fila or fila[1] == cfg.base_url:
            continue
        hosts = {urlsplit(r[0]).netloc for r in con.execute(
            "SELECT url FROM anuncios WHERE comercio_id = ? LIMIT 200", [fila[0]])}
        if urlsplit(cfg.base_url).netloc not in hosts:      # solo si la URL del scraper es la que realmente se usó
            continue
        con.execute("UPDATE comercios SET url_base = ? WHERE comercio_id = ?", [cfg.base_url, fila[0]])
        n += db.registrar_correccion(
            con, _hoy(), "comercios", fila[0], "url_base", fila[1], cfg.base_url,
            "El dominio registrado era el de una versión anterior del sitio; las URL de los anuncios y el scraper usan "
            f"{urlsplit(cfg.base_url).netloc}.", AUTOR)
    return n


def corregir_vendedores_externos(con) -> int:
    """Anuncios comparables vendidos por 'Otros vendedores' (marketplace): dejan de ser comparables."""
    n = 0
    filas = con.execute("""SELECT anuncio_id, producto_id, ficha_tecnica_original, sku, nombre_original
                           FROM anuncios WHERE comparable = 1 AND ficha_tecnica_original IS NOT NULL""").fetchall()
    for aid, pid, ficha, sku, nombre in filas:
        try:
            vendedor = json.loads(ficha).get("Vendido por")
        except (ValueError, AttributeError):
            continue
        if not vendedor or "otros vendedores" not in str(vendedor).lower():
            continue
        motivo = (f"El anuncio («{nombre}») lo vende un tercero ('Otros vendedores', marketplace) y no el comercio; "
                  "se excluye de los comparables para que el precio comparado sea el de la oferta propia del comercio. "
                  "El anuncio y sus observaciones se conservan.")
        con.execute("UPDATE anuncios SET comparable = 0, producto_id = NULL WHERE anuncio_id = ?", [aid])
        n += db.registrar_correccion(con, _hoy(), "anuncios", aid, "comparable", 1, 0, motivo, AUTOR)
        n += db.registrar_correccion(con, _hoy(), "anuncios", aid, "producto_id", pid, None, motivo, AUTOR)
    return n


def enlazar_raw(con, raw_dir: str | Path) -> dict:
    """Llena observaciones.raw_archivo buscando, en cada copia cruda, el SKU y la hora exacta de la consulta, y
    comprueba que el precio guardado coincida con el de la respuesta original."""
    raw_dir = Path(raw_dir)
    if not raw_dir.is_dir():
        raise FileNotFoundError(f"No existe la carpeta {raw_dir}")
    mapa: dict[tuple, tuple] = {}
    for ruta in sorted(raw_dir.glob("*/*/*.json.gz")):
        ejec, clave = ruta.name.split("__")[0], ruta.parent.parent.name
        if clave not in S.COMERCIOS:
            continue
        env = S.leer_raw(ruta)
        if "respuesta" not in env:
            continue
        items, _ = S._items_y_total(env["respuesta"], None, env["modo"])
        ref = S._ref_raw(ruta, raw_dir)
        for p in items:
            for fila in S.parsear_producto(p, S.COMERCIOS[clave], env["etiqueta"]):
                mapa.setdefault((ejec, clave, fila["sku"], env["consulta"]), (ref, fila["precio"]))
    obs = con.execute("""SELECT o.obs_id, o.ejecucion_id, c.clave, a.sku, o.fecha_hora_consulta, o.precio
                         FROM observaciones o JOIN anuncios a ON a.anuncio_id = o.anuncio_id
                         JOIN comercios c ON c.comercio_id = o.comercio_id WHERE o.raw_archivo IS NULL""").fetchall()
    enlazadas = sin_raw = precio_distinto = 0
    con.execute("BEGIN IMMEDIATE")
    try:
        for obs_id, ejec, clave, sku, ts, precio in obs:
            hit = mapa.get((ejec, clave, str(sku), ts))
            if not hit:
                sin_raw += 1
                continue
            ref, precio_raw = hit
            if (precio_raw is None) != (precio is None) or (precio is not None and abs(precio_raw - precio) > 0.5):
                precio_distinto += 1
            con.execute("UPDATE observaciones SET raw_archivo = ? WHERE obs_id = ?", [ref, obs_id])
            enlazadas += 1
        con.execute("COMMIT")
    except BaseException:
        con.execute("ROLLBACK")
        raise
    return {"observaciones_revisadas": len(obs), "enlazadas": enlazadas, "sin_copia_cruda": sin_raw,
            "precio_distinto_al_raw": precio_distinto}


def migrar(db_path: str | Path = db.RUTA_DB_DEFECTO, raw_dir: str | Path | None = None) -> dict:
    con = db.conectar_escritura(db_path)           # crea/actualiza esquema, índices y vistas
    try:
        con.execute("BEGIN IMMEDIATE")                 # las correcciones y su registro se aplican juntas o no se aplican
        try:
            res = {"correcciones_url": corregir_url_base(con), "correcciones_vendedor": corregir_vendedores_externos(con)}
            con.execute("COMMIT")
        except BaseException:
            con.execute("ROLLBACK")
            raise
        if raw_dir:
            res["raw"] = enlazar_raw(con, raw_dir)
        con.execute("ANALYZE")
        return res
    finally:
        con.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=str(db.RUTA_DB_DEFECTO))
    ap.add_argument("--raw", default=None, help="carpeta raw/ para enlazar y verificar las observaciones")
    a = ap.parse_args()
    print(json.dumps(migrar(a.db, a.raw), ensure_ascii=False, indent=2))
