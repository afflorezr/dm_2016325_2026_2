"""
actualizacion.py — Taller 2 Minería de Datos (UNAL): actualización de precios (Módulo 2).

Encadena, comercio por comercio:  scraper (recolectar)  →  validacion (validar)  →  db (guardar en una transacción).
No reescribe el scraper: llama a scraper.recolectar_comercio(), la misma función que usa run_all() del Taller 1.
No usa Streamlit: la página paginas/actualizar.py la llama y muestra el avance; también sirve desde la terminal.

Uso:
    python actualizacion.py                       # ejecución NUEVA en línea (consulta los tres sitios)
    python actualizacion.py --offline             # reprocesa la última ejecución guardada en raw/
    python actualizacion.py --offline --id 20261010T184400
"""
from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

import db
import scraper
import validacion

# [CAMBIO]: el enunciado (§3.3) exige al menos 8 productos comparables por comercio en cada ejecución. Una ejecución
# que obtuvo toda la categoría que reporta el sitio sigue siendo 'completa' si tiene 8 o más de los 18 comparables;
# los que falten quedan anotados. Con menos de 8, la ejecución del comercio queda 'parcial' (decisión 2026-11-08).
MINIMO_COMPARABLES = 8


# [CAMBIO]: ejecuciones que tienen copias crudas en raw/ (las que se pueden reprocesar sin conexión), de la más
# reciente a la más antigua. Lee solo nombres de carpetas; no hace peticiones.
def ejecuciones_en_raw(raw_dir: Path = scraper.RAW_DIR) -> list[str]:
    return sorted({p.parent.name for p in Path(raw_dir).glob("*/*/*/manifiesto.json")}, reverse=True)


# [CAMBIO]: id para una actualización: uno nuevo (en línea) o el elegido de raw/ (sin conexión).
def preparar_id_ejecucion(offline: bool, id_ejecucion: str | None = None, raw_dir: Path = scraper.RAW_DIR) -> str:
    if not offline:
        return scraper.nuevo_id_ejecucion()
    disponibles = ejecuciones_en_raw(raw_dir)
    if not disponibles:
        raise FileNotFoundError("No hay copias crudas en raw/ para el modo sin conexión.")
    id_ejecucion = id_ejecucion or disponibles[0]
    if id_ejecucion not in disponibles:
        raise ValueError(f"La ejecución {id_ejecucion} no tiene copias crudas en raw/.")
    return id_ejecucion


# [CAMBIO]: paso previo de toda actualización: asegura la estructura del Taller 2 (no hace nada si ya está) y
# devuelve el id de ejecución que se usará para los tres comercios.
def iniciar_actualizacion(offline: bool, id_ejecucion: str | None = None, db_path: Path = db.DB_PATH,
                          raw_dir: Path = scraper.RAW_DIR) -> str:
    db.migrar(db_path)
    return preparar_id_ejecucion(offline, id_ejecucion, raw_dir)


# [CAMBIO]: añade un texto a la nota de la ejecución sin perder lo que ya traía.
def _agregar_nota(ejecucion: dict, texto: str) -> None:
    ejecucion["nota"] = " | ".join(x for x in [ejecucion.get("nota"), texto] if x)


# [CAMBIO]: actualiza UN comercio y devuelve su fila de resumen (§4.5). Nunca lanza excepciones: si algo falla,
# la ejecución del comercio queda 'fallida' con el motivo y se sigue con el siguiente comercio (§4.4).
def actualizar_comercio(comercio: str, id_ejecucion: str, offline: bool,
                        db_path: Path = db.DB_PATH, raw_dir: Path = scraper.RAW_DIR) -> dict:
    nombre = scraper.COMERCIOS[comercio]["nombre"]
    resumen = {"comercio": nombre, "id_comercio": comercio, "id_ejecucion": id_ejecucion,
               "modo": "sin conexión" if offline else "en línea"}
    datos = pd.DataFrame()
    ejecucion = {"id_ejecucion": id_ejecucion, "id_comercio": comercio, "fecha_hora_inicio": scraper.ahora_iso()}
    try:
        # 1. Recolectar (scraper del Taller 1). Los errores de red o de estructura ya vienen como estado 'fallida'.
        datos, ejecucion = scraper.recolectar_comercio(comercio, id_ejecucion, offline, raw_dir)
        # 2. Validar (validacion.py): R1-R3 por fila y R4 (comparables presentes) sobre el conjunto
        with db.abrir_conexion(db_path, solo_lectura=True) as con:
            esperados = db.skus_comparables(con).get(comercio, set())
        if len(datos):
            validas, rechazadas = validacion.validar_observaciones(datos)
        else:
            validas, rechazadas = datos, pd.DataFrame(columns=validacion.COLUMNAS_RECHAZO)
        faltan = validacion.comparables_faltantes(validas, esperados) if len(validas) else sorted(esperados)
        if len(rechazadas):
            _agregar_nota(ejecucion, f"{rechazadas['sku_comercio'].nunique()} observaciones rechazadas por la "
                                     f"validación (ver tabla rechazos)")
        if faltan:
            presentes = len(esperados) - len(faltan)
            _agregar_nota(ejecucion, f"Faltan {len(faltan)} de {len(esperados)} comparables (el sitio no los "
                                     f"publicó en esta ejecución): SKU {', '.join(faltan)}")
            if presentes < MINIMO_COMPARABLES and ejecucion["estado"] != "fallida":
                ejecucion["estado"] = "parcial"
                _agregar_nota(ejecucion, f"Solo {presentes} comparables: menos de los {MINIMO_COMPARABLES} exigidos")
        # 3. Guardar en UNA transacción por comercio (db.py)
        conteos = db.guardar_comercio(validas, rechazadas, ejecucion, db_path)
        detalle = db.resumen_actualizacion(id_ejecucion, comercio, db_path)
    except Exception as e:  # falla al recolectar, validar o guardar: la transacción ya se deshizo
        motivo = f"Error al procesar el comercio: {type(e).__name__}: {e}"
        db.registrar_ejecucion_fallida(ejecucion, motivo, db_path)
        return {**resumen, "estado": "fallida", "recolectados": len(datos), "validos": 0, "rechazados": 0,
                "productos_nuevos": 0, "observaciones_nuevas": 0, "precios_subieron": 0, "precios_bajaron": 0,
                "no_observados": None, "comparables_faltantes": None, "motivo": motivo}
    return {**resumen, "estado": ejecucion["estado"], "recolectados": len(datos), "validos": len(validas),
            "rechazados": rechazadas["sku_comercio"].nunique() if len(rechazadas) else 0,
            "productos_nuevos": conteos["anuncios_nuevos"], "observaciones_nuevas": conteos["observaciones_nuevas"],
            "precios_subieron": detalle["precios_subieron"], "precios_bajaron": detalle["precios_bajaron"],
            "no_observados": detalle["no_observados"], "comparables_faltantes": len(faltan),
            "motivo": ejecucion["nota"]}


# [CAMBIO]: actualiza los tres comercios, uno tras otro. `avisar` recibe un mensaje antes de cada comercio (la
# app lo usa para escribir en st.status; en la terminal es print). Devuelve el resumen como tabla.
def actualizar_todo(offline: bool = False, id_ejecucion: str | None = None, db_path: Path = db.DB_PATH,
                    raw_dir: Path = scraper.RAW_DIR, avisar=print) -> pd.DataFrame:
    id_ejecucion = iniciar_actualizacion(offline, id_ejecucion, db_path, raw_dir)
    filas = []
    for comercio in scraper.COMERCIOS:
        avisar(f"Consultando {scraper.COMERCIOS[comercio]['nombre']}…")
        filas.append(actualizar_comercio(comercio, id_ejecucion, offline, db_path, raw_dir))
    return pd.DataFrame(filas)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Actualiza los precios: scraper → validación → base SQLite")
    ap.add_argument("--offline", action="store_true", help="reprocesar raw/ sin hacer peticiones")
    ap.add_argument("--id", default=None, help="id de ejecución a reprocesar (por defecto, la última en raw/)")
    a = ap.parse_args()
    tabla = actualizar_todo(offline=a.offline, id_ejecucion=a.id)
    with pd.option_context("display.width", 200, "display.max_columns", 20, "display.max_colwidth", 60):
        print(tabla.drop(columns=["id_comercio"]).to_string(index=False))
