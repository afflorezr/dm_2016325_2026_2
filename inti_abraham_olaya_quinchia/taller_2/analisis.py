"""analisis.py - Cálculos del análisis al consumidor (sin SQL ni Streamlit, fáciles de probar)."""

import pandas as pd


def etiqueta_producto(r):
    """Texto legible de un producto comparable (marca · nombre · contenido)."""
    cont = f" · {r.contenido:g} {r.unidad}" if pd.notna(r.contenido) and r.unidad else ""
    return f"{r.marca or ''} · {r.producto}{cont}".strip(" ·")


def calcular_canasta(precios, cantidades):
    """
    precios: DataFrame (producto_id, comercio, precio) de UNA misma ejecución.
    cantidades: {producto_id: cantidad}; las cantidades <= 0 se ignoran.

    Devuelve:
      totales            - por comercio: costo (None si le falta algún producto), faltantes, completo
      ideal              - por producto: comercio más barato, precio, cantidad y subtotal (None si algún
                           producto no tiene precio en ningún comercio)
      costo_ideal        - suma de la canasta ideal (None si no se puede calcular)
      ahorro_vs_completos- ahorro de la canasta ideal frente a comprar todo en cada comercio completo
      sin_precio         - productos sin precio en ningún comercio
    Un total incompleto NUNCA se calcula: el costo queda en None.
    """
    prods = [p for p, q in cantidades.items() if q and q > 0]
    sub = precios[precios["producto_id"].isin(prods)]
    mejor = {c: s.set_index("producto_id")["precio"] for c, s in sub.groupby("comercio")}
    comercios = sorted(precios["comercio"].unique())

    filas = []
    for c in comercios:
        pc = mejor.get(c, pd.Series(dtype=float))
        faltan = [p for p in prods if p not in pc.index]
        costo = None if (faltan or not prods) else float(sum(pc[p] * cantidades[p] for p in prods))
        filas.append({"comercio": c, "costo": costo, "faltantes": faltan, "completo": costo is not None})
    totales = pd.DataFrame(filas, columns=["comercio", "costo", "faltantes", "completo"])

    sin_precio = [p for p in prods if p not in set(sub["producto_id"])]
    ideal, costo_ideal, ahorro = None, None, pd.DataFrame(columns=["comercio", "costo", "ahorro_cop", "ahorro_pct"])
    if prods and not sin_precio:
        idx = sub.sort_values(["producto_id", "precio", "comercio"]).groupby("producto_id").head(1)
        ideal = idx.assign(cantidad=idx["producto_id"].map(cantidades))
        ideal["subtotal"] = ideal["precio"] * ideal["cantidad"]
        # empates: se avisa cuántos comercios comparten el precio mínimo
        minimos = sub.groupby("producto_id")["precio"].transform("min")
        empates = sub[sub["precio"] == minimos].groupby("producto_id")["comercio"].apply(lambda s: " / ".join(sorted(s)))
        ideal["comercio_mas_barato"] = ideal["producto_id"].map(empates)
        costo_ideal = float(ideal["subtotal"].sum())
        comp = totales[totales["completo"]].copy()
        comp["ahorro_cop"] = comp["costo"] - costo_ideal
        comp["ahorro_pct"] = 100.0 * comp["ahorro_cop"] / comp["costo"]
        ahorro = comp[["comercio", "costo", "ahorro_cop", "ahorro_pct"]]
    return {"totales": totales, "ideal": ideal, "costo_ideal": costo_ideal,
            "ahorro_vs_completos": ahorro, "sin_precio": sin_precio}
