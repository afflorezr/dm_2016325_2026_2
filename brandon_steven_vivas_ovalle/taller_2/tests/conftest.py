"""Configuración de pytest: rutas y una base temporal con dos ejecuciones sintéticas (nunca la base de la entrega)."""
import sys
from pathlib import Path

import pytest

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import db  # noqa: E402
import limpieza as L  # noqa: E402
import datos_falsos as F  # noqa: E402

E1, E2 = "run_20261001T100000", "run_20261002T100000"


@pytest.fixture
def base_demo(tmp_path):
    """Base temporal: ejecución 1 (1 oct) y ejecución 2 (2 oct) con cambios de precio, un producto nuevo y uno que desaparece."""
    ruta, raw = tmp_path / "t.sqlite", tmp_path / "raw"
    F.ejecutar(ruta, raw, E1, "2026-10-01T10:00:00-05:00",
               F.ClienteFalso(omite={"exito": {9, 0}, "jumbo": {6}, "olimpica": {3}}))
    con = db.conectar_escritura(ruta)
    L.marcar_comparables(con, E1)          # define el catálogo de comparables (como en el Taller 1)
    con.close()
    # Ejecución 2: sube el precio del producto 4 (+10 %), baja el 5 (-20 %); Éxito ahora trae el 0 (nuevo) y omite el 1; agota el 7.
    F.ejecutar(ruta, raw, E2, "2026-10-02T10:00:00-05:00",
               F.ClienteFalso(omite={"exito": {9, 1}, "jumbo": {6}, "olimpica": {3}}, mult={4: 1.10, 5: 0.80}, agotados={7}))
    return {"db": ruta, "raw": raw}
