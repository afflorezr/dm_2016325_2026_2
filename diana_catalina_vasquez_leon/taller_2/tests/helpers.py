"""Utilidades de prueba: bases temporales pequeñas (nunca se usa la base de la entrega ni los sitios)."""
import os
import sqlite3
import tempfile
from types import SimpleNamespace

import migrar_taller2
import scraper


def base_temporal():
    """Crea una carpeta temporal con una base vacía (esquema del scraper + vistas del Taller 2)."""
    carpeta = tempfile.mkdtemp(prefix="taller2_")
    ruta = os.path.join(carpeta, "prueba.sqlite")
    scraper.abrir_db(ruta).close()
    migrar_taller2.migrar(ruta, raw_dir=os.path.join(carpeta, "raw"), verbose=False)
    return ruta


def cap_falso(id_ejec, comercio="La Rebaja", fecha_inicio="2026-11-05T10:00:00-05:00"):
    return SimpleNamespace(id_ejec=id_ejec, comercio=comercio, fecha_inicio=fecha_inicio, dir=None)


def registro(sku, precio, comercio="La Rebaja", fecha="2026-11-05T10:00:00-05:00", **kw):
    base = dict(comercio=comercio, sku_comercio=sku, url=f"https://ejemplo.co/{sku}", titulo_original=f"Producto {sku}",
                en_alcance=1, precio_lista=precio, precio_vigente=precio, promocion=0, fecha_consulta=fecha)
    base.update(kw)
    return scraper.nuevo_registro(**base)


def cargar(ruta, id_ejec, registros, comercio="La Rebaja", fecha_inicio="2026-11-05T10:00:00-05:00", estado="completa"):
    """Inserta una ejecución de un comercio usando la misma función que usa el scraper."""
    conn = scraper.abrir_db(ruta)
    res = {"registros": registros, "declarados": len(registros), "estado": estado, "detalle": ""}
    n = scraper._guardar(conn, cap_falso(id_ejec, comercio, fecha_inicio), res, "en_linea")
    conn.close()
    return n


def contar(ruta, sql, params=()):
    con = sqlite3.connect(ruta)
    try:
        return con.execute(sql, params).fetchone()[0]
    finally:
        con.close()
