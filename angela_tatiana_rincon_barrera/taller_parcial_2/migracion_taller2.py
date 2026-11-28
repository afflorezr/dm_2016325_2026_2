"""
Migración de la base del Taller 1 al esquema del Taller 2 y corrección documentada.

    python migracion_taller2.py

1. Crea las tablas, columnas, índices, disparadores y vistas nuevas (db.inicializar_bd).
2. Completa la trazabilidad: modo, copia cruda de origen y fecha de los datos de cada ejecución.
3. Reprocesa las MISMAS copias crudas de raw/ con las reglas corregidas de scraper.py y:
   - llena los campos nuevos (disponibilidad, subcategoría y marca estandarizadas, EAN original);
   - corrige los campos estandarizados que cambian (pertenencia a la categoría, contenido,
     unidad, precio por unidad, EAN), registrando cada cambio en la tabla `correcciones`
     con fecha, registro afectado, valor anterior, valor nuevo y motivo.
   No se borra ninguna observación y no se modifican los precios extraídos.
4. Verifica que precio y precio de lista de cada observación coincidan con su copia cruda.

Es idempotente: si se ejecuta de nuevo no repite correcciones.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

import db
import scraper

MOTIVOS_CAMPO = {
    "en_categoria": "Corrección de pertenencia a la categoría: {detalle}",
    "motivo_exclusion": "Corrección de pertenencia a la categoría: {detalle}",
    "contenido_valor": "Contenido mal extraído en el Taller 1 (no se reconocía 'Grs', la descripción tenía prioridad sobre el nombre o era un combo)",
    "contenido_unidad": "Unidad mal extraída en el Taller 1 (no se reconocía 'Grs', la descripción tenía prioridad sobre el nombre o era un combo)",
    "precio_por_unidad": "Recalculado por la corrección del contenido o la unidad",
    "ean": "El campo EAN contenía un código interno del comercio o un texto vacío; se deja NULL (el valor original queda en ean_original)",
    "comparable": "Corrección de la correspondencia de productos comparables",
    "id_producto_comun": "Corrección de la correspondencia de productos comparables",
}
CAMPOS_CORREGIBLES = list(MOTIVOS_CAMPO)
CAMPOS_NUEVOS = ["estado_disponibilidad", "subcategoria_estandar", "marca_estandar", "ean_original"]


def _iguales(a: Any, b: Any) -> bool:
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-6
    return str(a) == str(b)


def migrar(db_path: Path = db.DB_PATH, raw_base: Path = scraper.RAW_DIR) -> Dict[str, int]:
    conteo = {"correcciones": 0, "observaciones_actualizadas": 0, "diferencias_precio": 0}
    with db.conectar(db_path) as con:
        db.inicializar_bd(con)
        ya = con.execute("SELECT COUNT(*) FROM correcciones WHERE motivo LIKE 'Taller 2 -%'").fetchone()[0]
        if ya:
            print("La migración ya se había aplicado; no se repiten correcciones.")
            return conteo

        # Índice de copias crudas por (comercio, timestamp)
        copias = {}
        for comercio in scraper.COMERCIOS:
            for archivo in scraper.listar_copias_crudas(comercio, raw_base):
                ts, _, _ = scraper.leer_copia_cruda(archivo)
                copias[(comercio, ts)] = archivo

        with con:
            ejecuciones = con.execute(
                """SELECT e.id_ejecucion, e.comercio, MIN(o.fecha_hora_consulta), e.archivo_raw, e.modo
                   FROM ejecuciones e JOIN observaciones o ON o.id_ejecucion = e.id_ejecucion
                   GROUP BY e.id_ejecucion""").fetchall()
            for id_ej, comercio, ts, archivo_actual, modo_actual in ejecuciones:
                archivo = copias.get((comercio, ts))
                if archivo is None:
                    raise RuntimeError(f"No se encontró la copia cruda de {comercio} con fecha {ts}")
                ruta = scraper._ruta_relativa(archivo)
                if archivo_actual != ruta:
                    con.execute("UPDATE ejecuciones SET archivo_raw = ? WHERE id_ejecucion = ?", (ruta, id_ej))
                    db.registrar_correccion(con, "ejecuciones", id_ej, "archivo_raw", archivo_actual, ruta,
                                            "Taller 2 - Trazabilidad: copia cruda de origen de la ejecución (campo nuevo)")
                    conteo["correcciones"] += 1
                if modo_actual is None:
                    con.execute("UPDATE ejecuciones SET modo = 'en_linea' WHERE id_ejecucion = ?", (id_ej,))

                # Reprocesar la copia cruda con las reglas corregidas
                ts_raw, _, paginas = scraper.leer_copia_cruda(archivo)
                cfg = scraper.COMERCIOS[comercio]
                nuevos = {p["id_producto_comercio"]: p for p in
                          scraper.extraer_productos_de_paginas(paginas, comercio, ts_raw, cfg["subcategoria_defecto"])}

                filas = con.execute(
                    f"""SELECT id_observacion, id_producto_comercio, precio_actual, precio_lista, motivo_exclusion,
                               {', '.join(CAMPOS_CORREGIBLES)}
                        FROM observaciones WHERE id_ejecucion = ?""", (id_ej,)).fetchall()
                for fila in filas:
                    id_obs, sku, precio, precio_lista, motivo_excl_ant = fila[0], fila[1], fila[2], fila[3], fila[4]
                    actuales = dict(zip(CAMPOS_CORREGIBLES, fila[5:]))
                    p = nuevos.get(sku)
                    if p is None:
                        raise RuntimeError(f"La observación {id_obs} no aparece en su copia cruda {ruta}")
                    if not _iguales(precio, p["precio_actual"]) or not _iguales(precio_lista, p["precio_lista"]):
                        conteo["diferencias_precio"] += 1

                    cambios = {}
                    for campo in CAMPOS_CORREGIBLES:
                        if not _iguales(actuales[campo], p.get(campo)):
                            cambios[campo] = p.get(campo)
                    for campo, valor in cambios.items():
                        detalle = p.get("motivo_exclusion") or "el anuncio sí pertenece a la categoría"
                        db.registrar_correccion(con, "observaciones", id_obs, campo, actuales[campo], valor,
                                                "Taller 2 - " + MOTIVOS_CAMPO[campo].format(detalle=detalle))
                        conteo["correcciones"] += 1
                    asignaciones = {**cambios, **{c: p.get(c) for c in CAMPOS_NUEVOS}}
                    sets = ", ".join(f"{c} = ?" for c in asignaciones)
                    con.execute(f"UPDATE observaciones SET {sets} WHERE id_observacion = ?",
                                list(asignaciones.values()) + [id_obs])
                    conteo["observaciones_actualizadas"] += 1

            # Corridas: modo y fecha de los datos
            con.execute("""UPDATE corridas SET modo = COALESCE(modo, 'en_linea'),
                               fecha_datos = (SELECT MAX(fecha_hora_consulta) FROM observaciones o
                                              WHERE o.id_corrida = corridas.id_corrida)""")
            con.execute("""UPDATE ejecuciones SET comparables_encontrados = (
                               SELECT COUNT(DISTINCT id_producto_comun) FROM observaciones o
                               WHERE o.id_ejecucion = ejecuciones.id_ejecucion AND o.comparable = 1),
                           n_rechazadas = COALESCE(n_rechazadas, 0)""")
        con.execute("VACUUM")
    return conteo


if __name__ == "__main__":
    r = migrar()
    print(f"Correcciones registradas: {r['correcciones']}")
    print(f"Observaciones actualizadas (campos nuevos): {r['observaciones_actualizadas']}")
    print(f"Observaciones cuyo precio no coincide con la copia cruda: {r['diferencias_precio']}")
