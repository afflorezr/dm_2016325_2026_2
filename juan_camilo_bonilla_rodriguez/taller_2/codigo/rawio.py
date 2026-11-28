"""Lectura y escritura de copias crudas (HTML/JSON) comprimidas en raw/."""
import gzip
import json
import os
import glob

from .config import ahora_iso


def guardar_raw(raw_dir, slug, corrida_id, n, contenido, url, tipo):
    """Guarda una respuesta cruda en raw/<slug>/<corrida_id>/pNNNN.json.gz.

    tipo = 'json' (contenido ya parseado, dict/list) o 'html' (str).
    Devuelve (ruta, fecha_hora_consulta_iso).
    """
    carpeta = os.path.join(raw_dir, slug, corrida_id)
    os.makedirs(carpeta, exist_ok=True)
    ts = ahora_iso()
    ruta = os.path.join(carpeta, f"p{n:04d}.json.gz")
    with gzip.open(ruta, "wt", encoding="utf-8") as f:
        json.dump(
            {"url": url, "tipo": tipo, "fecha_hora_consulta": ts, "contenido": contenido},
            f,
            ensure_ascii=False,
        )
    return ruta, ts


def leer_raw(raw_dir, slug, corrida_id=None):
    """Itera (ruta, envoltorio) de una corrida guardada.

    Si corrida_id es None usa la más reciente.
    envoltorio = {'url', 'tipo', 'fecha_hora_consulta', 'contenido'}
    """
    base = os.path.join(raw_dir, slug)
    if corrida_id is None:
        corrida_id = sorted(os.listdir(base))[-1]
    for ruta in sorted(glob.glob(os.path.join(base, corrida_id, "*.json.gz"))):
        with gzip.open(ruta, "rt", encoding="utf-8") as f:
            yield ruta, json.load(f)
