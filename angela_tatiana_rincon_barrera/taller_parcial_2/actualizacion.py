"""
Orquestación de la actualización de precios (Módulo 2).

Flujo por comercio:  scraper.recolectar_comercio()  ->  validacion.validar_observaciones()
                     ->  db.guardar_ejecucion_comercio()  (transacción por comercio)

Lo usan el botón "Actualizar precios" de la aplicación y la línea de comandos:
    python actualizacion.py              # en línea (consulta los sitios)
    python actualizacion.py --offline    # sin conexión: reprocesa la copia más reciente de raw/
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Callable, Dict, List, Optional

import db
import scraper
import validacion

AvisoProgreso = Callable[[str, str], None]  # (comercio, mensaje)


def actualizar(offline: bool = False, db_path: Path = db.DB_PATH, raw_base: Path = scraper.RAW_DIR,
               comercios: Optional[List[str]] = None, archivos_raw: Optional[Dict[str, Path]] = None,
               aviso: Optional[AvisoProgreso] = None) -> Dict[str, object]:
    """
    Ejecuta una corrida completa. Si un comercio falla, continúa con los demás y lo
    registra como parcial o fallido. Devuelve {'id_corrida', 'estado', 'comercios': [resúmenes]}.
    """
    comercios = comercios or list(scraper.COMERCIOS)
    archivos_raw = archivos_raw or {}
    modo = "sin_conexion" if offline else "en_linea"
    avisar = aviso or (lambda c, m: None)

    with db.conectar(db_path) as con:
        db.inicializar_bd(con)
        db.sincronizar_catalogo(con, scraper.CATALOGO_COMPARABLES)
        id_corrida = db.iniciar_corrida(con, modo)
        resumenes = []
        for comercio in comercios:
            avisar(comercio, "consultando el sitio..." if not offline else "reprocesando la copia cruda...")
            res = scraper.recolectar_comercio(comercio, offline=offline, archivo_raw=archivos_raw.get(comercio),
                                              raw_base=raw_base)
            val = validacion.validar_observaciones(res.productos, scraper.IDS_COMPARABLES)
            avisar(comercio, f"{len(res.productos)} productos recolectados; {len(val.rechazadas)} rechazados por validación.")
            resumen = db.guardar_ejecucion_comercio(
                con, id_corrida, comercio, modo, res.timestamp, val.validas, val.rechazadas,
                res.total_reportado, res.fallo, res.motivo, res.archivo_raw,
                len(val.comparables_encontrados), val.comparables_faltantes, validacion.MIN_COMPARABLES,
            )
            avisar(comercio, f"estado: {resumen['estado']}" + (f" — {resumen['motivo']}" if resumen.get("motivo") else ""))
            resumenes.append(resumen)
        estado = db.finalizar_corrida(con, id_corrida)
    return {"id_corrida": id_corrida, "estado": estado, "modo": modo, "comercios": resumenes}


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Actualiza la base de precios mediante web scraping.")
    parser.add_argument("--offline", action="store_true", help="Reprocesar copias crudas de raw/ sin consultar los sitios")
    args = parser.parse_args(argv)
    print(f"Iniciando corrida ({'sin conexión' if args.offline else 'en línea'})...")
    r = actualizar(offline=args.offline, aviso=lambda c, m: print(f"[{c}] {m}"))
    print(f"Corrida {r['id_corrida']} terminada: {r['estado']}")
    for c in r["comercios"]:
        print(f"  {c['comercio']}: recolectados={c['recolectados']} insertados={c['insertados']} "
              f"nuevos={c['productos_nuevos']} cambios={c['cambios_precio']} no_observados={c['no_observados']} "
              f"estado={c['estado']}")
    return 0 if r["estado"] != "fallida" else 1


if __name__ == "__main__":
    raise SystemExit(main())
