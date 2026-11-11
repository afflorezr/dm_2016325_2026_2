"""
actualizacion.py - Lógica de actualización de precios (scraping -> validación -> SQLite).

Se separa de app.py para que la interfaz no contenga SQL. Reutiliza scraper.py del Taller 1
(no se copia ni se reescribe) y validacion.py (pandera).

Flujo por comercio:
  1. recolectar_comercio()      -> DataFrame con las columnas de scraper.COLUMNAS
  2. validar_observaciones()    -> filas válidas / rechazadas (con motivo)
  3. UNA transacción (BEGIN ... COMMIT) inserta ejecución + categorías + observaciones;
     si algo falla se hace ROLLBACK y la base no queda a medias.
  4. Si el comercio falla en cualquier paso: se registra la ejecución como 'fallida' y se
     continúa con el siguiente comercio.
"""

from contextlib import closing
from datetime import datetime

import pandas as pd

import scraper
from validacion import guardar_rechazadas, validar_observaciones

COMERCIOS = ["La Rebaja", "Olímpica", "Éxito"]

_SQL_EJECUCION = """INSERT INTO ejecuciones (corrida_id, inicio, comercio, modo, n_registros, n_productos,
    n_esperado_sitio, estado, detalle) VALUES (?,?,?,?,?,?,?,?,?)
    ON CONFLICT(corrida_id, comercio) DO UPDATE SET n_registros=excluded.n_registros,
    n_productos=excluded.n_productos, n_esperado_sitio=excluded.n_esperado_sitio,
    estado=excluded.estado, detalle=excluded.detalle"""


def nueva_corrida_id():
    return "run-" + datetime.now(scraper.TZ).strftime("%Y%m%dT%H%M%S")


def recolectar_comercio(comercio, modo="online", corrida_id=None):
    """Llama al scraper del Taller 1 y devuelve un DataFrame (la meta queda en df.attrs['meta'])."""
    filas, meta = scraper.SCRAPERS[comercio](modo, None, None, corrida_id)
    df = pd.DataFrame(filas, columns=scraper.COLUMNAS)
    df.attrs["meta"] = meta
    return df


def registrar_fallida(comercio, corrida_id, modo, motivo, db_path=None):
    """Deja constancia de una ejecución fallida (sin observaciones)."""
    with closing(scraper.conectar(db_path)) as con:
        con.execute("INSERT OR IGNORE INTO comercios (nombre, url_base) VALUES (?,?)",
                    (comercio, scraper.COMERCIOS[comercio]["base"]))
        con.execute(_SQL_EJECUCION, (corrida_id, scraper.ahora_iso(), comercio, modo,
                                     0, 0, None, "fallida", str(motivo)[:300]))
        con.commit()


def actualizar_comercio(comercio, corrida_id, modo="online", db_path=None):
    """Recolecta, valida e inserta un comercio. Lanza excepción si falla (el llamador la registra)."""
    df = recolectar_comercio(comercio, modo, corrida_id)
    meta = df.attrs.get("meta", {})
    validas, rechazadas = validar_observaciones(df)
    if validas.empty:
        raise ValueError("Ninguna observación superó la validación")
    validas = validas.astype(object).where(validas.notna(), None)   # NaN -> NULL
    cid = meta.get("corrida_id") or (corrida_id if modo == "online" else "raw-" + meta["consulta"])
    estado = "parcial" if (meta.get("incompletas") or len(rechazadas)) else "completa"
    detalle = None if estado == "completa" else (
        f"categorías incompletas: {meta.get('incompletas')}; rechazadas: {len(rechazadas)}")

    with closing(scraper.conectar(db_path)) as con:
        con.isolation_level = None            # transacción manejada a mano
        try:
            con.execute("BEGIN TRANSACTION")
            con.execute("INSERT OR IGNORE INTO comercios (nombre, url_base) VALUES (?,?)",
                        (comercio, scraper.COMERCIOS[comercio]["base"]))
            con.execute(_SQL_EJECUCION, (cid, meta.get("consulta", scraper.ahora_iso()), comercio, modo,
                                         len(df), meta.get("n_productos"), meta.get("n_esperado"),
                                         estado, detalle))
            eid = con.execute("SELECT id FROM ejecuciones WHERE corrida_id=? AND comercio=?",
                              (cid, comercio)).fetchone()["id"]
            for c in meta.get("categorias", []):
                con.execute("INSERT OR REPLACE INTO categorias_sitio VALUES (?,?,?,?,?,?)",
                            (cid, comercio, str(c["id"]), c["nombre"], c["ruta"], c.get("total_sitio")))
            nuevos = sum(scraper._insertar(con, f, eid) for f in validas.to_dict("records"))
            con.execute("COMMIT")
        except Exception:
            if con.in_transaction:
                con.execute("ROLLBACK")       # nada queda a medias
            raise
        if len(rechazadas):
            guardar_rechazadas(con, rechazadas, cid, scraper.ahora_iso())
        cambios = con.execute("""SELECT COUNT(*) FROM v_cambios_precio
                                  WHERE corrida_id=? AND comercio=? AND sentido <> 'igual'""",
                              (cid, comercio)).fetchone()[0]
        no_obs = con.execute("""SELECT COUNT(*) FROM anuncios a JOIN comercios c ON c.id=a.comercio_id
              WHERE c.nombre=? AND a.excluido=0
                AND EXISTS (SELECT 1 FROM observaciones o WHERE o.anuncio_id=a.id)
                AND NOT EXISTS (SELECT 1 FROM observaciones o
                                 WHERE o.anuncio_id=a.id AND o.ejecucion_id=?)""",
                             (comercio, eid)).fetchone()[0]
    return {"comercio": comercio, "estado": estado, "recolectados": len(df),
            "validos": len(validas), "rechazados": len(rechazadas), "nuevos": nuevos,
            "cambios_precio": cambios, "no_observados": no_obs, "motivo": detalle or ""}


def actualizar_todo(comercios=None, modo="online", db_path=None, on_progress=None):
    """Itera por los comercios tolerando fallas. Devuelve (DataFrame resumen, corrida_id)."""
    corrida, resumen = nueva_corrida_id(), []
    avisar = on_progress or (lambda comercio, texto: None)
    for comercio in (comercios or COMERCIOS):
        avisar(comercio, "consultando...")
        try:
            fila = actualizar_comercio(comercio, corrida, modo, db_path)
            avisar(comercio, f"{fila['estado']}: {fila['nuevos']} observaciones nuevas")
        except Exception as e:  # noqa: BLE001 - un comercio caído no detiene a los demás
            try:
                registrar_fallida(comercio, corrida, modo, e, db_path)
            except Exception:  # noqa: BLE001
                pass
            fila = {"comercio": comercio, "estado": "fallida", "recolectados": 0, "validos": 0,
                    "rechazados": 0, "nuevos": 0, "cambios_precio": 0, "no_observados": 0,
                    "motivo": str(e)[:200]}
            avisar(comercio, f"fallida: {fila['motivo']}")
        resumen.append(fila)
    if any(f["estado"] != "fallida" for f in resumen):      # actualiza la correspondencia de comparables
        with closing(scraper.conectar(db_path)) as con:
            ult = con.execute("""SELECT corrida_id FROM ejecuciones WHERE estado <> 'fallida'
                                  ORDER BY id DESC LIMIT 1""").fetchone()
            if ult:
                scraper.asignar_correspondencia(con, ult[0])
    return pd.DataFrame(resumen), corrida
