"""Utilidades de prueba: base temporal y datos pequeños. Nunca se usa la base de la entrega ni los sitios."""

import sys
from pathlib import Path

import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import db  # noqa: E402

CATALOGO_PRUEBA = [
    {"id_producto_comun": "P1", "nombre_estandar": "Protector Uno FPS 50", "marca_estandar": "Marca A",
     "categoria_estandar": "Protector Facial", "presentacion_estandar": "Tubo 50 ml", "contenido_valor": 50.0,
     "contenido_unidad": "mL", "ean": "1111111111111"},
    {"id_producto_comun": "P2", "nombre_estandar": "Protector Dos FPS 50", "marca_estandar": "Marca B",
     "categoria_estandar": "Protector Facial", "presentacion_estandar": "Tubo 40 g", "contenido_valor": 40.0,
     "contenido_unidad": "g", "ean": "2222222222222"},
]


def observacion(comercio, sku, precio, ts, comun=None, disponibilidad="disponible", **extra):
    fila = {
        "comercio": comercio, "id_producto_comercio": sku, "nombre_original": f"Producto {sku}",
        "presentacion_original": None, "descripcion_original": "", "marca_original": "Marca",
        "subcategoria_original": "Solares", "precio_actual": float(precio), "precio_lista": float(precio),
        "es_promocion": 0, "url": f"https://tienda.example/{sku}/p", "pum_original": None,
        "fecha_hora_consulta": ts, "comparable": 1 if comun else 0, "id_producto_comun": comun,
        "contenido_valor": 50.0, "contenido_unidad": "mL", "precio_por_unidad": float(precio) / 50,
        "en_categoria": 1, "motivo_exclusion": None, "ean": None, "ean_original": "",
        "estado_disponibilidad": disponibilidad, "subcategoria_estandar": "Facial", "marca_estandar": "Marca",
    }
    fila.update(extra)
    return fila


@pytest.fixture
def con(tmp_path):
    """Conexión a una base SQLite temporal con el esquema completo del Taller 2."""
    with db.conectar(tmp_path / "prueba.sqlite") as c:
        db.inicializar_bd(c)
        db.sincronizar_catalogo(c, CATALOGO_PRUEBA)
        yield c


def cargar(con, observaciones, modo="en_linea"):
    """Registra una corrida con las observaciones dadas (agrupadas por comercio) y la cierra."""
    id_corrida = db.iniciar_corrida(con, modo)
    df = pd.DataFrame(observaciones)
    resumenes = []
    for comercio, grupo in df.groupby("comercio"):
        resumenes.append(db.guardar_ejecucion_comercio(
            con, id_corrida, comercio, modo, grupo["fecha_hora_consulta"].iloc[0], grupo.reset_index(drop=True),
            pd.DataFrame(columns=["motivo"]), total_reportado=len(grupo), fallo=False, motivo=None,
            archivo_raw=None, comparables_encontrados=8, comparables_faltantes=[]))
    db.finalizar_corrida(con, id_corrida)
    return id_corrida, resumenes
