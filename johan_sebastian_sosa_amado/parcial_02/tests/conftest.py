"""Datos de prueba. Cada prueba usa una base nueva en la carpeta temporal
que crea pytest (tmp_path), nunca la base de la entrega ni los sitios de las
tiendas."""

import sys
from pathlib import Path

import pandas as pd
import pytest

# Para importar scraper, db y validacion desde la carpeta del taller.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import scraper  # noqa: E402

TIENDA = {"exito": "Exito", "larebaja": "La Rebaja", "olimpica": "Olimpica"}


def tabla_tienda(clave, ejecucion_id, fecha, productos):
    """Tabla con las mismas columnas que devuelve el scraper.
    productos: lista de (sku, ean, nombre, precio). precio None = agotado."""
    filas = []
    for sku, ean, nombre, precio in productos:
        filas.append({
            "ejecucion_id": ejecucion_id, "comercio": TIENDA[clave], "seccion": "prueba",
            "pagina": 1, "product_id": sku, "sku": sku, "ean": ean, "marca": "TENA",
            "subcategoria": "/Incontinencia/", "nombre_original": nombre,
            "descripcion_original": nombre, "presentacion_original": None,
            "precio": precio, "precio_antes": precio, "promocion": False,
            "disponible": precio is not None, "vendedor": "1",
            "url": f"https://tienda.example/{clave}/{sku}", "fecha_hora_consulta": fecha,
            "en_categoria": 1, "motivo_exclusion": None,
        })
    tabla = pd.DataFrame(filas, columns=scraper.COLUMNAS)
    tabla.attrs.update({"ejecucion_id": ejecucion_id, "total": len(filas)})
    return tabla


def cargar(con, recoleccion_id, fecha, precios):
    """Carga una recolección de prueba. precios: {clave: [(sku, ean, nombre, precio), ...]}"""
    for clave, productos in precios.items():
        tabla = tabla_tienda(clave, f"{clave}_{recoleccion_id}", fecha, productos)
        with con:
            scraper.guardar_en_sqlite(con, clave, tabla, recoleccion_id, sin_conexion=True)


PANTS = "Pañales TENA pants clásicos talla M (8 und)"
SLIP = "Pañales para adultos TENA slip comfort L (21 und)"

# Recolección 1: los dos productos con precio en las tres tiendas.
# Pants: empate en el precio mínimo entre Éxito y Olímpica (28.700).
R1 = {
    "exito":    [("e1", "7702026174149", PANTS, 28700.0), ("e2", "7702027479731", SLIP, 60400.0)],
    "larebaja": [("l1", "7702026174149", PANTS, 29100.0), ("l2", "7702027479731", SLIP, 50400.0)],
    "olimpica": [("o1", "7702026174149", PANTS, 28700.0), ("o2", "7702027479731", SLIP, 69590.0)],
}
# Recolección 2: el pants sube en Éxito, el slip queda agotado en Olímpica,
# aparece un producto nuevo en La Rebaja y el slip de La Rebaja deja de observarse.
R2 = {
    "exito":    [("e1", "7702026174149", PANTS, 30000.0), ("e2", "7702027479731", SLIP, 55000.0)],
    "larebaja": [("l1", "7702026174149", PANTS, 29100.0),
                 ("l3", "7702026181949", "Pañales TENA pants clásicos M (16 und)", 46000.0)],
    "olimpica": [("o1", "7702026174149", PANTS, 28700.0), ("o2", "7702027479731", SLIP, None)],
}


@pytest.fixture
def base(tmp_path):
    """Base temporal con dos recolecciones y la limpieza ya hecha.
    Devuelve (con, ruta)."""
    ruta = tmp_path / "prueba.sqlite"
    con = scraper.conectar_base(ruta)
    cargar(con, "2026-11-01T10-00-00", "2026-11-01T10:00:00-05:00", R1)
    cargar(con, "2026-11-02T10-00-00", "2026-11-02T10:00:00-05:00", R2)
    scraper.limpiar_y_emparejar(con)
    yield con, ruta
    con.close()
