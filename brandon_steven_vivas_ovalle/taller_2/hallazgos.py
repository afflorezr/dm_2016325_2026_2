"""
hallazgos.py - Calcula con SQL las cifras de la sección «Hallazgos» del README a partir de la base entregada.
Uso:  python hallazgos.py [ejecucion_id]     (por defecto, la última ejecución completa)
Así cada conclusión del README se puede reproducir y se actualiza fácilmente tras una nueva ejecución.
"""
import sys

import pandas as pd

import analisis as A
import db

pd.set_option("display.width", 200, "display.max_colwidth", 70)

with db.abrir() as con:
    ref = sys.argv[1] if len(sys.argv) > 1 else db.ultima_ejecucion_completa(con)
    print(f"# Ejecución de referencia: {ref} ({A.etiqueta_ejecucion(ref)})\n")
    print(db.ejecuciones(con)[["ejecucion_id", "fecha", "estado", "n_completas", "n_fallidas"]].to_string(index=False), "\n")

    sp = db.sobreprecio_comparables(con, ref)
    print("## 1. Sobreprecio promedio frente al más barato, por comercio (productos comparables)")
    print(sp.groupby("comercio")["sobreprecio_pct"].agg(["mean", "max", "count"]).round(2).to_string(), "\n")
    mas_barato = con.execute("""SELECT mas_baratos, COUNT(*) FROM (
                  SELECT (SELECT GROUP_CONCAT(v.comercio, ' / ') FROM v_comparables v WHERE v.ejecucion_id = ? AND v.producto_id = m.producto_id
                          AND v.precio = m.minimo) AS mas_baratos FROM (SELECT producto_id, MIN(precio) minimo FROM v_comparables
                          WHERE ejecucion_id = ? GROUP BY producto_id HAVING COUNT(*) >= 2) m) GROUP BY mas_baratos ORDER BY 2 DESC""",
                              [ref, ref]).fetchall()
    print("Productos en los que cada comercio (o empate) es el más barato:", [tuple(r) for r in mas_barato], "\n")

    ah = db.ahorro_por_producto(con, ref)
    print("## 2. Mayores ahorros por producto (COP y %)")
    print(ah[["nombre_std", "minimo", "maximo", "ahorro_cop", "ahorro_pct", "mas_baratos"]].head(5).round(1).to_string(index=False), "\n")

    pu = db.precio_unitario_comparables(con, ref)
    print("## 3. Precio por unidad: ¿el paquete grande sale más barato por unidad?")
    gr = pu.copy()
    gr["linea"] = gr["nombre_std"].str.replace(r" x [\d.,]+ \w+$", "", regex=True)
    pares = gr.groupby(["comercio", "linea"]).filter(lambda x: x["contenido_total"].nunique() > 1)
    print(pares.sort_values(["linea", "comercio", "contenido_total"])[["comercio", "nombre_std", "precio", "precio_unitario"]].round(2).to_string(index=False), "\n")

    print("## 4. Cambios de precio entre ejecuciones consecutivas (productos disponibles en ambas)")
    print(pd.read_sql_query("SELECT ejecucion_anterior, ejecucion_id, comercio, COUNT(*) n, ROUND(AVG(variacion_pct),2) pct_prom "
                            "FROM v_cambios_precio GROUP BY 1,2,3", con).to_string(index=False), "\n")
    print("## 5. Promociones en los comparables (ejecución de referencia)")
    print(pd.read_sql_query("SELECT comercio, SUM(en_promocion) en_promo, COUNT(*) n FROM v_comparables WHERE ejecucion_id=? GROUP BY comercio", con,
                            params=[ref]).to_string(index=False))
